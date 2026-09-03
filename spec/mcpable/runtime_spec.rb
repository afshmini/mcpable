# frozen_string_literal: true

RSpec.describe Mcpable::Runtime do
  subject(:runtime) { described_class.new }

  let(:seen) { [] }

  def register(arguments, metadata: {})
    Mcpable.registry.register(
      Mcpable::Definition.build(
        name: "probe",
        arguments: arguments,
        metadata: metadata,
        handler: ->(ctx) { Mcpable::Result.ok(ctx.args) }
      )
    )
  end

  it "symbolizes string argument keys" do
    register([Mcpable::Argument.build(:name, type: :string)])
    result = runtime.call_tool("probe", args: { "name" => "alice" })
    expect(result.payload).to eq(name: "alice")
  end

  it "coerces integers from strings" do
    register([Mcpable::Argument.build(:count, type: :integer)])
    expect(runtime.call_tool("probe", args: { "count" => "42" }).payload).to eq(count: 42)
  end

  it "fails on a non-integer" do
    register([Mcpable::Argument.build(:count, type: :integer)])
    result = runtime.call_tool("probe", args: { count: "abc" })
    expect(result.status).to eq(:error)
    expect(result.error).to eq("count is not an integer")
  end

  it "coerces booleans from strings" do
    register([Mcpable::Argument.build(:active, type: :boolean)])
    expect(runtime.call_tool("probe", args: { active: "true" }).payload).to eq(active: true)
    expect(runtime.call_tool("probe", args: { active: "false" }).payload).to eq(active: false)
  end

  it "fails on a non-boolean" do
    register([Mcpable::Argument.build(:active, type: :boolean)])
    expect(runtime.call_tool("probe", args: { active: "maybe" }).error).to eq("active is not a boolean")
  end

  it "coerces ISO8601 dates" do
    register([Mcpable::Argument.build(:on, type: :date)])
    expect(runtime.call_tool("probe", args: { on: "2026-01-31" }).payload[:on]).to eq(Date.new(2026, 1, 31))
  end

  it "fails on a malformed date" do
    register([Mcpable::Argument.build(:on, type: :date)])
    expect(runtime.call_tool("probe", args: { on: "31/01/2026" }).error).to eq("on is not an ISO8601 date")
  end

  it "coerces ISO8601 datetimes" do
    register([Mcpable::Argument.build(:at, type: :datetime)])
    expect(runtime.call_tool("probe", args: { at: "2026-01-31T10:00:00Z" }).payload[:at])
      .to eq(Time.utc(2026, 1, 31, 10, 0, 0))
  end

  it "coerces floats" do
    register([Mcpable::Argument.build(:rate, type: :number)])
    expect(runtime.call_tool("probe", args: { rate: "1.5" }).payload).to eq(rate: 1.5)
  end

  it "fails when a required argument is missing" do
    register([Mcpable::Argument.build(:company_id, type: :integer, required: true)])
    result = runtime.call_tool("probe", args: {})
    expect(result.status).to eq(:error)
    expect(result.error).to eq("missing required arguments: company_id")
  end

  it "fails on unknown arguments" do
    register([Mcpable::Argument.build(:name, type: :string)])
    result = runtime.call_tool("probe", args: { name: "a", bogus: 1, other: 2 })
    expect(result.status).to eq(:error)
    expect(result.error).to eq("unknown arguments: bogus, other")
  end

  it "accepts pagination arguments on paginated definitions" do
    register([], metadata: { paginated: true })
    result = runtime.call_tool("probe", args: { "page" => "2", "per_page" => "5", "order" => "-name" })
    expect(result.payload).to eq(page: 2, per_page: 5, order: "-name")
  end

  it "rejects pagination arguments on unpaginated definitions" do
    register([])
    expect(runtime.call_tool("probe", args: { page: 2 }).error).to eq("unknown arguments: page")
  end

  it "raises for an unknown tool" do
    expect { runtime.call_tool("nope") }.to raise_error(Mcpable::UnknownToolError)
  end

  it "passes the context through to the tool call" do
    Mcpable.registry.register(
      Mcpable::Definition.build(name: "probe", handler: ->(ctx) { Mcpable::Result.ok(ctx.context) })
    )
    expect(runtime.call_tool("probe", context: { user_id: 7 }).payload).to eq(user_id: 7)
  end
end
