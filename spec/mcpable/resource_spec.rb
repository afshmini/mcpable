# frozen_string_literal: true

RSpec.describe Mcpable::Resource do
  CostCenterRecord = Struct.new(:id, :name, :number, :company_id, :created_at, keyword_init: true) unless defined?(CostCenterRecord)

  let(:records) do
    [
      CostCenterRecord.new(id: 1, name: "Berlin",    number: "001", company_id: 1, created_at: Date.new(2026, 1, 1)),
      CostCenterRecord.new(id: 2, name: "Bern",      number: "002", company_id: 1, created_at: Date.new(2026, 2, 1)),
      CostCenterRecord.new(id: 3, name: "Accounting", number: "003", company_id: 2, created_at: Date.new(2026, 3, 1))
    ]
  end

  let(:runtime) { Mcpable::Runtime.new }

  let(:model) do
    rows = records
    Class.new do
      include Mcpable::Resource

      def self.name = "CostCenter"

      define_singleton_method(:all_records) { rows }

      mcpable do
        description "Cost centers"
        attributes :id, :name, :number, :company_id
        filter :company_id, type: :integer
        filter :name, match: :partial, type: :string
        filter :created_at, range: true, type: :date
        source Mcpable::Sources::EnumerableSource.new(rows)
        policy nil
        actions :list, :show
        default_page_size 2
        profiles :default
      end
    end
  end

  before { model }

  it "compiles a list and a show definition" do
    expect(Mcpable.registry.names).to contain_exactly("cost_centers_list", "cost_centers_show")
  end

  it "marks the list definition as paginated with model metadata" do
    definition = Mcpable.registry.fetch("cost_centers_list")
    expect(definition.metadata[:action]).to eq(:list)
    expect(definition.metadata[:paginated]).to be(true)
    expect(definition.metadata[:per_page]).to eq(2)
    expect(definition.metadata[:model]).to be(model)
  end

  it "expands filters into arguments" do
    args = Mcpable.registry.fetch("cost_centers_list").arguments
    expect(args.map(&:name)).to eq(%i[company_id name created_at_from created_at_to])
    expect(args.map(&:filter_kind)).to eq(%i[eq match range_from range_to])
    expect(args.map(&:filter_target)).to eq(%i[company_id name created_at created_at])
    expect(args.map(&:type)).to eq(%i[integer string date date])
  end

  it "lists all records with the default page size" do
    result = runtime.call_tool("cost_centers_list")
    expect(result).to be_ok
    expect(result.payload[:total]).to eq(3)
    expect(result.payload[:per_page]).to eq(2)
    expect(result.payload[:records].map { |r| r[:name] }).to eq(%w[Berlin Bern])
  end

  it "serializes only whitelisted attributes" do
    record = runtime.call_tool("cost_centers_list").payload[:records].first
    expect(record).to eq(id: 1, name: "Berlin", number: "001", company_id: 1)
    expect(record).not_to have_key(:created_at)
  end

  it "applies an eq filter" do
    result = runtime.call_tool("cost_centers_list", args: { "company_id" => "2" })
    expect(result.payload[:total]).to eq(1)
    expect(result.payload[:records].map { |r| r[:name] }).to eq(["Accounting"])
  end

  it "applies a partial match filter" do
    result = runtime.call_tool("cost_centers_list", args: { name: "ber" })
    expect(result.payload[:records].map { |r| r[:name] }).to eq(%w[Berlin Bern])
  end

  it "applies a range filter" do
    result = runtime.call_tool("cost_centers_list", args: { created_at_from: "2026-02-01" })
    expect(result.payload[:records].map { |r| r[:id] }).to eq([2, 3])
  end

  it "paginates and orders" do
    result = runtime.call_tool("cost_centers_list", args: { page: 2, per_page: 1, order: "-id" })
    expect(result.payload[:page]).to eq(2)
    expect(result.payload[:records].map { |r| r[:id] }).to eq([2])
    expect(result.payload[:total]).to eq(3)
  end

  it "shows a single record" do
    result = runtime.call_tool("cost_centers_show", args: { "id" => "3" })
    expect(result).to be_ok
    expect(result.payload).to eq(id: 3, name: "Accounting", number: "003", company_id: 2)
  end

  it "fails when the record is missing" do
    result = runtime.call_tool("cost_centers_show", args: { id: 99 })
    expect(result.status).to eq(:error)
    expect(result.error).to eq("not found")
  end

  it "requires an id for show" do
    expect(runtime.call_tool("cost_centers_show").error).to eq("missing required arguments: id")
  end

  it "raises when a filter has no type and no inferrer" do
    previous = Mcpable::Dsl::ResourceBuilder.type_inferrer
    Mcpable::Dsl::ResourceBuilder.type_inferrer = nil

    expect do
      Class.new do
        include Mcpable::Resource

        def self.name = "Untyped"

        mcpable do
          filter :company_id
          source Mcpable::Sources::EnumerableSource.new([])
        end
      end
    end.to raise_error(ArgumentError, "filter :company_id needs type:")
  ensure
    Mcpable::Dsl::ResourceBuilder.type_inferrer = previous
  end

  it "requires a source" do
    expect do
      Class.new do
        include Mcpable::Resource

        def self.name = "Sourceless"

        mcpable { attributes :id }
      end
    end.to raise_error(ArgumentError, /needs a source/)
  end

  describe "the source_factory soft hook" do
    around do |example|
      previous = Mcpable::Dsl::ResourceBuilder.source_factory
      example.run
    ensure
      Mcpable::Dsl::ResourceBuilder.source_factory = previous
    end

    it "wires a source for a target the factory recognises" do
      seen = nil
      rows = records
      Mcpable::Dsl::ResourceBuilder.source_factory = lambda do |target, order_whitelist:|
        seen = { target: target, order_whitelist: order_whitelist }
        Mcpable::Sources::EnumerableSource.new(rows)
      end

      klass = Class.new do
        include Mcpable::Resource

        def self.name = "Autowired"

        mcpable do
          attributes :id, :name
          actions :list
        end
      end

      expect(seen[:target]).to be(klass)
      expect(seen[:order_whitelist]).to eq(%i[id name])
      expect(runtime.call_tool("autowireds_list").payload[:total]).to eq(3)
    end

    it "passes an explicit order_whitelist to the factory" do
      seen = nil
      rows = records
      Mcpable::Dsl::ResourceBuilder.source_factory = lambda do |_target, order_whitelist:|
        seen = order_whitelist
        Mcpable::Sources::EnumerableSource.new(rows)
      end

      Class.new do
        include Mcpable::Resource

        def self.name = "Ordered"

        mcpable do
          attributes :id, :name, :number
          order_whitelist :number
          actions :list
        end
      end

      expect(seen).to eq([:number])
    end

    it "prefers an explicitly declared source" do
      Mcpable::Dsl::ResourceBuilder.source_factory = ->(_target, order_whitelist:) { raise "not reached" }
      rows = records

      Class.new do
        include Mcpable::Resource

        def self.name = "Explicit"

        mcpable do
          attributes :id
          actions :list
          source Mcpable::Sources::EnumerableSource.new(rows)
        end
      end

      expect(runtime.call_tool("explicits_list").payload[:total]).to eq(3)
    end

    it "still demands a source when the factory declines" do
      Mcpable::Dsl::ResourceBuilder.source_factory = ->(_target, order_whitelist:) { nil }

      expect do
        Class.new do
          include Mcpable::Resource

          def self.name = "Declined"

          mcpable { attributes :id }
        end
      end.to raise_error(ArgumentError, /needs a source/)
    end
  end

  it "accepts a lambda source resolved per call" do
    calls = 0
    rows = records
    Class.new do
      include Mcpable::Resource

      def self.name = "Lazy"

      mcpable do
        attributes :id
        actions :list
        source(lambda do
          calls += 1
          Mcpable::Sources::EnumerableSource.new(rows)
        end)
      end
    end

    runtime.call_tool("lazies_list")
    runtime.call_tool("lazies_list")
    expect(calls).to eq(2)
  end
end
