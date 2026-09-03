# frozen_string_literal: true

require "mcpable/active_record/column_inference"

RSpec.describe Mcpable::ActiveRecord::ColumnInference do
  Column = Struct.new(:type) unless defined?(Column)

  let(:model) do
    columns = {
      "id" => Column.new(:integer),
      "company_id" => Column.new(:bigint),
      "name" => Column.new(:string),
      "rate" => Column.new(:decimal),
      "ratio" => Column.new(:float),
      "active" => Column.new(:boolean),
      "born_on" => Column.new(:date),
      "created_at" => Column.new(:datetime),
      "payload" => Column.new(:jsonb),
      "status" => Column.new(:integer)
    }
    enums = { "status" => { "open" => 0, "closed" => 1 } }

    Class.new do
      define_singleton_method(:columns_hash) { columns }
      define_singleton_method(:defined_enums) { enums }
    end
  end

  it "maps ActiveRecord column types" do
    expect(described_class.infer(model, :id)).to eq(type: :integer, enum: nil)
    expect(described_class.infer(model, :company_id)).to eq(type: :integer, enum: nil)
    expect(described_class.infer(model, :name)).to eq(type: :string, enum: nil)
    expect(described_class.infer(model, :rate)).to eq(type: :number, enum: nil)
    expect(described_class.infer(model, :ratio)).to eq(type: :number, enum: nil)
    expect(described_class.infer(model, :active)).to eq(type: :boolean, enum: nil)
    expect(described_class.infer(model, :born_on)).to eq(type: :date, enum: nil)
    expect(described_class.infer(model, :created_at)).to eq(type: :datetime, enum: nil)
  end

  it "falls back to :string for unmapped column types" do
    expect(described_class.infer(model, :payload)).to eq(type: :string, enum: nil)
  end

  it "reports enum-backed attributes as strings with their values" do
    expect(described_class.infer(model, :status)).to eq(type: :string, enum: %w[open closed])
  end

  it "returns nil for an unknown attribute" do
    expect(described_class.infer(model, :nope)).to be_nil
  end

  it "returns nil for a class without columns" do
    expect(described_class.infer(Class.new, :id)).to be_nil
  end

  describe "the ResourceBuilder soft hook" do
    around do |example|
      previous = Mcpable::Dsl::ResourceBuilder.type_inferrer
      example.run
    ensure
      Mcpable::Dsl::ResourceBuilder.type_inferrer = previous
    end

    it "infers filter types when no explicit type: is given" do
      Mcpable::Dsl::ResourceBuilder.type_inferrer = lambda do |target, name|
        described_class.infer(target, name)
      end

      columns = model
      Class.new do
        include Mcpable::Resource

        define_singleton_method(:name) { "Widget" }
        define_singleton_method(:columns_hash) { columns.columns_hash }
        define_singleton_method(:defined_enums) { columns.defined_enums }

        mcpable do
          attributes :id
          actions :list
          filter :company_id
          filter :status
          filter :created_at, range: true
          filter :name, match: :partial, type: :string
          source Mcpable::Sources::EnumerableSource.new([])
        end
      end

      args = Mcpable.registry.fetch("widgets_list").arguments
      expect(args.map(&:name)).to eq(%i[company_id status created_at_from created_at_to name])
      expect(args.map(&:type)).to eq(%i[integer string datetime datetime string])
      expect(args.first(2).map(&:enum)).to eq([nil, %w[open closed]])
    end

    it "still raises when the inferrer cannot type a filter" do
      Mcpable::Dsl::ResourceBuilder.type_inferrer = ->(_target, _name) { nil }

      expect do
        Class.new do
          include Mcpable::Resource

          define_singleton_method(:name) { "Widget" }

          mcpable do
            filter :mystery
            source Mcpable::Sources::EnumerableSource.new([])
          end
        end
      end.to raise_error(ArgumentError, "filter :mystery needs type:")
    end
  end
end
