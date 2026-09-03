# frozen_string_literal: true

RSpec.describe Mcpable::Tool do
  let(:runtime) { Mcpable::Runtime.new }

  def build_tool(&block)
    Class.new do
      include Mcpable::Tool

      def self.name = "Payslip::Regenerate"

      def call(payroll_id:, dry_run: false)
        { payroll_id: payroll_id, dry_run: dry_run }
      end

      class_exec(&block)
    end
  end

  it "registers a definition with the declared name" do
    build_tool do
      mcp_tool do
        name "payslip_regenerate"
        description "Regenerates a payslip."
        argument :payroll_id, :integer, required: true, description: "Payroll id."
        annotations read_only: false, destructive: true
        profiles :default, :admin
      end
    end

    definition = Mcpable.registry.fetch("payslip_regenerate")
    expect(definition.description).to eq("Regenerates a payslip.")
    expect(definition.read_only?).to be(false)
    expect(definition.destructive?).to be(true)
    expect(definition.profiles).to eq(%i[default admin])
    expect(definition.arguments.map(&:name)).to eq([:payroll_id])
    expect(definition.argument(:payroll_id).required).to be(true)
  end

  it "defaults the name to the underscored class name" do
    build_tool do
      mcp_tool { description "d" }
    end

    expect(Mcpable.registry.names).to eq(["payslip_regenerate"])
  end

  it "exposes the compiled definition on the class" do
    klass = build_tool { mcp_tool { name "t" } }
    expect(klass.mcp_definition).to be(Mcpable.registry.fetch("t"))
  end

  it "runs end to end through the runtime and wraps a plain return in Result.ok" do
    build_tool do
      mcp_tool do
        name "payslip_regenerate"
        argument :payroll_id, :integer, required: true
        argument :dry_run, :boolean
      end
    end

    result = runtime.call_tool("payslip_regenerate", args: { "payroll_id" => "17", "dry_run" => "true" })

    expect(result).to be_ok
    expect(result.payload).to eq(payroll_id: 17, dry_run: true)
  end

  it "passes a Result return through untouched" do
    klass = Class.new do
      include Mcpable::Tool

      def self.name = "Thing"

      def call = Mcpable::Result.deny("nope")

      mcp_tool { name "thing" }
    end

    expect(klass).to be_truthy
    result = runtime.call_tool("thing")
    expect(result.status).to eq(:denied)
    expect(result.error).to eq("nope")
  end

  it "only forwards declared arguments to #call" do
    seen = nil
    klass = Class.new do
      include Mcpable::Tool

      def self.name = "Narrow"

      define_method(:call) { |a:| seen = a }

      mcp_tool do
        name "narrow"
        argument :a, :integer
      end
    end

    expect(klass.mcp_definition.name).to eq("narrow")
    runtime.call_tool("narrow", args: { a: 5 })
    expect(seen).to eq(5)
  end

  it "supports an explicit builder argument" do
    build_tool do
      mcp_tool do |t|
        t.name "explicit"
        t.description "via arg"
      end
    end

    expect(Mcpable.registry.fetch("explicit").description).to eq("via arg")
  end
end
