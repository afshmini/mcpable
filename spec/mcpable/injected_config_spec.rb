# frozen_string_literal: true

require "mcpable/transports/official_mcp"

RSpec.describe "injected configuration" do
  let(:definition) do
    Mcpable::Definition.build(
      name: "boom",
      description: "raises",
      arguments: [],
      handler: ->(_ctx) { raise "kaboom" }
    )
  end

  it "uses the owning configuration's error_mapper, not the global one" do
    Mcpable.config.error_mapper = ->(_e) { Mcpable::Result.fail("global mapper") }

    injected = Mcpable::Configuration.new
    injected.error_mapper = ->(e) { Mcpable::Result.fail("injected saw #{e.message}") }

    registry = Mcpable::Registry.new
    registry.register(definition)
    runtime = Mcpable::Runtime.new(registry: registry, config: injected)

    result = runtime.call_tool("boom", args: {}, context: {})

    expect(result.error).to eq("injected saw kaboom")
  end

  it "falls back to the global error_mapper when no config was injected" do
    Mcpable.config.error_mapper = ->(_e) { Mcpable::Result.fail("global mapper") }
    Mcpable.registry.register(definition)

    expect(Mcpable.runtime.call_tool("boom", args: {}, context: {}).error).to eq("global mapper")
  end
end

RSpec.describe Mcpable::Transports::OfficialMcp do
  let(:definition) do
    Mcpable::Definition.build(
      name: "echo",
      description: "echoes",
      arguments: [Mcpable::Argument.build(:q, type: :string)],
      handler: ->(ctx) { Mcpable::Result.ok(ctx.args) }
    )
  end

  let(:marker_strategy) do
    Class.new(Mcpable::Ports::SchemaStrategy) do
      def input_schema(_definition)
        { "type" => "object", "properties" => { "injected_marker" => { "type" => "string" } }, "required" => [] }
      end
    end.new
  end

  it "builds schemas with the injected configuration's schema_strategy" do
    registry = Mcpable::Registry.new
    registry.register(definition)

    injected = Mcpable::Configuration.new
    injected.schema_strategy = marker_strategy

    transport = described_class.new(
      registry: registry,
      runtime: Mcpable::Runtime.new(registry: registry, config: injected),
      config: injected
    )

    expect(transport.list_tools.first[:inputSchema][:properties].keys.map(&:to_s)).to eq(["injected_marker"])
  end

  it "inherits the configuration carried by an injected runtime" do
    registry = Mcpable::Registry.new
    registry.register(definition)

    injected = Mcpable::Configuration.new
    injected.schema_strategy = marker_strategy

    transport = described_class.new(
      registry: registry,
      runtime: Mcpable::Runtime.new(registry: registry, config: injected)
    )

    expect(transport.list_tools.first[:inputSchema][:properties].keys.map(&:to_s)).to eq(["injected_marker"])
  end
end
