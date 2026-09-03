# frozen_string_literal: true

RSpec.describe Mcpable::SchemaStrategies::ExplicitSchema do
  subject(:strategy) { described_class.new }

  def definition(arguments, metadata: {})
    Mcpable::Definition.build(name: "t", arguments: arguments, metadata: metadata)
  end

  it "renders an empty schema for no arguments" do
    expect(strategy.input_schema(definition([])))
      .to eq(type: "object", properties: {}, required: [])
  end

  it "renders every scalar type" do
    args = [
      Mcpable::Argument.build(:a, type: :string),
      Mcpable::Argument.build(:b, type: :integer),
      Mcpable::Argument.build(:c, type: :number),
      Mcpable::Argument.build(:d, type: :boolean),
      Mcpable::Argument.build(:e, type: :date),
      Mcpable::Argument.build(:f, type: :datetime)
    ]

    expect(strategy.input_schema(definition(args))[:properties]).to eq(
      a: { type: "string" },
      b: { type: "integer" },
      c: { type: "number" },
      d: { type: "boolean" },
      e: { type: "string", format: "date" },
      f: { type: "string", format: "date-time" }
    )
  end

  it "lists required arguments" do
    args = [
      Mcpable::Argument.build(:a, type: :string, required: true),
      Mcpable::Argument.build(:b, type: :string),
      Mcpable::Argument.build(:c, type: :string, required: true)
    ]
    expect(strategy.input_schema(definition(args))[:required]).to eq(%i[a c])
  end

  it "includes description and enum" do
    args = [Mcpable::Argument.build(:status, type: :string, description: "State.", enum: %w[open closed])]
    expect(strategy.input_schema(definition(args))[:properties][:status]).to eq(
      type: "string", description: "State.", enum: %w[open closed]
    )
  end

  it "adds pagination arguments when the definition is paginated" do
    schema = strategy.input_schema(definition([], metadata: { paginated: true }))
    expect(schema[:properties].keys).to eq(%i[page per_page order])
    expect(schema[:properties][:page][:type]).to eq("integer")
    expect(schema[:properties][:per_page][:type]).to eq("integer")
    expect(schema[:properties][:order][:type]).to eq("string")
    expect(schema[:required]).to eq([])
  end

  it "keeps declared arguments alongside pagination arguments" do
    args = [Mcpable::Argument.build(:company_id, type: :integer, required: true)]
    schema = strategy.input_schema(definition(args, metadata: { paginated: true }))
    expect(schema[:properties].keys).to eq(%i[company_id page per_page order])
    expect(schema[:required]).to eq([:company_id])
  end

  it "omits pagination arguments otherwise" do
    expect(strategy.input_schema(definition([]))[:properties]).to eq({})
  end
end
