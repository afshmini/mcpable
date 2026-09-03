# frozen_string_literal: true

RSpec.describe Mcpable::Pipeline do
  subject(:pipeline) { described_class.new }

  let(:trace) { [] }

  def definition(handler)
    Mcpable::Definition.build(name: "t", handler: handler)
  end

  def ctx_for(handler, args: {})
    Mcpable::ToolCall.new(definition: definition(handler), args: args, context: {})
  end

  let(:tracer) do
    Class.new(Mcpable::Ports::Middleware) do
      def initialize(app, label, trace)
        super(app)
        @label = label
        @trace = trace
      end

      def call(ctx)
        @trace << "#{@label}:in"
        result = @app.call(ctx)
        @trace << "#{@label}:out"
        result
      end
    end
  end

  it "runs the first registered middleware outermost" do
    pipeline.use(tracer, "outer", trace)
    pipeline.use(tracer, "inner", trace)

    result = pipeline.call(ctx_for(->(_c) { trace << "handler"; Mcpable::Result.ok(1) }))

    expect(result).to be_ok
    expect(trace).to eq(["outer:in", "inner:in", "handler", "inner:out", "outer:out"])
  end

  it "lets a middleware short-circuit with a deny" do
    denier = Class.new(Mcpable::Ports::Middleware) do
      def call(_ctx) = Mcpable::Result.deny("nope")
    end

    pipeline.use(denier)
    pipeline.use(tracer, "inner", trace)

    result = pipeline.call(ctx_for(->(_c) { trace << "handler"; Mcpable::Result.ok(1) }))

    expect(result.status).to eq(:denied)
    expect(result.error).to eq("nope")
    expect(trace).to be_empty
  end

  it "propagates assigns from middleware to the handler" do
    assigner = Class.new(Mcpable::Ports::Middleware) do
      def call(ctx)
        ctx.assigns[:user] = "alice"
        ctx.assigns[:scope] = [1, 2]
        @app.call(ctx)
      end
    end

    pipeline.use(assigner)
    result = pipeline.call(ctx_for(->(c) { Mcpable::Result.ok(user: c.user, scope: c.scope) }))

    expect(result.payload).to eq(user: "alice", scope: [1, 2])
  end

  it "routes a StandardError through the configured error mapper" do
    seen = nil
    Mcpable.configure { |c| c.error_mapper = ->(e) { seen = e; Mcpable::Result.fail("mapped: #{e.message}") } }

    result = pipeline.call(ctx_for(->(_c) { raise ArgumentError, "boom" }))

    expect(seen).to be_a(ArgumentError)
    expect(result.error).to eq("mapped: boom")
  end

  it "uses the default error mapper when unconfigured" do
    result = pipeline.call(ctx_for(->(_c) { raise "boom" }))
    expect(result.status).to eq(:error)
    expect(result.error).to eq("internal error")
  end

  it "maps a non-Result handler return to a failure" do
    result = pipeline.call(ctx_for(->(_c) { { not: "a result" } }))
    expect(result.status).to eq(:error)
    expect(result.error).to eq("invalid result")
  end

  it "maps a non-Result middleware return to a failure" do
    liar = Class.new(Mcpable::Ports::Middleware) do
      def call(_ctx) = :whoops
    end

    pipeline.use(liar)
    result = pipeline.call(ctx_for(->(_c) { Mcpable::Result.ok(1) }))
    expect(result.error).to eq("invalid result")
  end

  it "lets the error mapper re-raise" do
    Mcpable.configure { |c| c.error_mapper = ->(e) { raise e } }
    expect { pipeline.call(ctx_for(->(_c) { raise ArgumentError, "boom" })) }
      .to raise_error(ArgumentError, "boom")
  end
end
