# frozen_string_literal: true

RSpec.describe Mcpable::Sources::EnumerableSource do
  Rec = Struct.new(:id, :name, :company_id, :created_at, keyword_init: true) unless defined?(Rec)

  let(:records) do
    [
      Rec.new(id: 1, name: "Alpha",   company_id: 1, created_at: Date.new(2026, 1, 1)),
      Rec.new(id: 2, name: "Beta",    company_id: 1, created_at: Date.new(2026, 2, 1)),
      Rec.new(id: 3, name: "Gamma",   company_id: 2, created_at: Date.new(2026, 3, 1)),
      Rec.new(id: 4, name: "alphabet", company_id: 2, created_at: Date.new(2026, 4, 1))
    ]
  end

  subject(:source) { described_class.new(records) }

  def arg(name, kind, target: nil, type: :string)
    Mcpable::Argument.build(name, type: type, filter: { kind: kind, target: target || name })
  end

  def fetch(filters: {}, scope: nil, page: nil, per_page: nil, order: nil)
    source.fetch(filters: filters, scope: scope, page: page, per_page: per_page, order: order)
  end

  it "filters with :eq" do
    page = fetch(filters: { arg(:company_id, :eq, type: :integer) => 1 })
    expect(page.records.map(&:id)).to eq([1, 2])
    expect(page.total).to eq(2)
  end

  it "ignores a nil filter value" do
    expect(fetch(filters: { arg(:company_id, :eq) => nil }).total).to eq(4)
  end

  it "filters with :match case-insensitively on a substring" do
    page = fetch(filters: { arg(:name, :match) => "alph" })
    expect(page.records.map(&:name)).to eq(%w[Alpha alphabet])
  end

  it "filters with :range_from" do
    page = fetch(filters: { arg(:created_at_from, :range_from, target: :created_at, type: :date) => Date.new(2026, 3, 1) })
    expect(page.records.map(&:id)).to eq([3, 4])
  end

  it "filters with :range_to" do
    page = fetch(filters: { arg(:created_at_to, :range_to, target: :created_at, type: :date) => Date.new(2026, 2, 1) })
    expect(page.records.map(&:id)).to eq([1, 2])
  end

  it "combines a range into a window" do
    filters = {
      arg(:created_at_from, :range_from, target: :created_at, type: :date) => Date.new(2026, 2, 1),
      arg(:created_at_to, :range_to, target: :created_at, type: :date) => Date.new(2026, 3, 1)
    }
    expect(fetch(filters: filters).records.map(&:id)).to eq([2, 3])
  end

  it "skips :scope filters" do
    expect(fetch(filters: { arg(:mine, :scope, type: :boolean) => true }).total).to eq(4)
  end

  it "intersects the base with the scope" do
    page = fetch(scope: [records[0], records[2]])
    expect(page.records.map(&:id)).to eq([1, 3])
    expect(page.total).to eq(2)
  end

  it "applies filters within the scope only" do
    page = fetch(filters: { arg(:company_id, :eq, type: :integer) => 1 }, scope: [records[1], records[2]])
    expect(page.records.map(&:id)).to eq([2])
  end

  it "rejects a non-Enumerable scope" do
    expect { fetch(scope: :nope) }.to raise_error(Mcpable::Error, /Enumerable/)
  end

  it "orders ascending" do
    expect(fetch(order: "name").records.map(&:name)).to eq(%w[Alpha Beta Gamma alphabet])
  end

  it "orders descending with a - prefix" do
    expect(fetch(order: "-id").records.map(&:id)).to eq([4, 3, 2, 1])
  end

  it "paginates and reports the filtered total" do
    page = fetch(page: 2, per_page: 2, order: "id")
    expect(page.records.map(&:id)).to eq([3, 4])
    expect(page.total).to eq(4)
    expect(page.page).to eq(2)
    expect(page.per_page).to eq(2)
  end

  it "reports the filtered total, not the base total" do
    page = fetch(filters: { arg(:company_id, :eq, type: :integer) => 2 }, page: 1, per_page: 1)
    expect(page.total).to eq(2)
    expect(page.records.size).to eq(1)
  end

  it "returns an empty page past the end" do
    expect(fetch(page: 99, per_page: 2).records).to be_empty
  end

  it "defaults page and per_page" do
    page = fetch
    expect(page.page).to eq(1)
    expect(page.per_page).to eq(25)
  end

  it "accepts a lambda base" do
    lazy = described_class.new(-> { records.first(2) })
    expect(lazy.fetch(filters: {}, scope: nil, page: nil, per_page: nil, order: nil).total).to eq(2)
  end

  it "reads hash records" do
    hashes = described_class.new([{ id: 1, name: "Alpha" }, { id: 2, name: "Beta" }])
    page = hashes.fetch(filters: { arg(:name, :match) => "bet" }, scope: nil, page: nil, per_page: nil, order: nil)
    expect(page.records).to eq([{ id: 2, name: "Beta" }])
  end

  describe "#find" do
    it "finds by id" do
      expect(source.find(3).name).to eq("Gamma")
    end

    it "finds by a string id" do
      expect(source.find("3").name).to eq("Gamma")
    end

    it "returns nil when absent" do
      expect(source.find(99)).to be_nil
    end

    it "honours the scope" do
      expect(source.find(1, scope: [records[2]])).to be_nil
      expect(source.find(3, scope: [records[2]]).name).to eq("Gamma")
    end
  end
end
