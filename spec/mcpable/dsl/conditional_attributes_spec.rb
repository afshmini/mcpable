# frozen_string_literal: true

RSpec.describe "conditional attributes" do
  ItemRecord = Struct.new(:id, :name, :price_cents, :cost_cents, keyword_init: true) unless defined?(ItemRecord)

  Viewer = Struct.new(:admin) do
    def admin? = admin
  end unless defined?(Viewer)

  let(:rows) do
    [
      ItemRecord.new(id: 1, name: "Wrench", price_cents: 4999, cost_cents: 2100),
      ItemRecord.new(id: 2, name: "Bolt", price_cents: 1299, cost_cents: 400)
    ]
  end

  let(:assigner) do
    viewer = @viewer
    Class.new(Mcpable::Ports::Middleware) do
      define_method(:call) do |ctx|
        ctx.assigns[:user] = viewer
        @app.call(ctx)
      end
    end
  end

  def compile!(condition)
    records = rows
    builder = Mcpable::Dsl::ResourceBuilder.new(ItemRecord)
    builder.name "item"
    builder.description "Items."
    builder.attributes :id, :name, :price_cents
    builder.attribute :cost_cents, if: condition
    builder.source Mcpable::Sources::EnumerableSource.new(-> { records })
    builder.actions :list, :show
    builder.compile.each { |d| Mcpable.registry.register(d) }
    Mcpable.config.pipeline.use(assigner)
  end

  it "hides the attribute from a caller that fails the symbol condition" do
    @viewer = Viewer.new(false)
    compile!(:admin?)

    record = Mcpable.runtime.call_tool("items_list", args: {}, context: {}).payload[:records].first
    expect(record.keys).to eq(%i[id name price_cents])
  end

  it "shows the attribute to a caller that passes the symbol condition" do
    @viewer = Viewer.new(true)
    compile!(:admin?)

    record = Mcpable.runtime.call_tool("items_list", args: {}, context: {}).payload[:records].first
    expect(record).to include(cost_cents: 2100)
  end

  it "applies the same masking to show" do
    @viewer = Viewer.new(false)
    compile!(:admin?)

    expect(Mcpable.runtime.call_tool("items_show", args: { id: 1 }, context: {}).payload.keys)
      .to eq(%i[id name price_cents])
  end

  it "accepts a lambda condition receiving the tool call" do
    @viewer = Viewer.new(true)
    compile!(->(ctx) { ctx.user&.admin? })

    expect(Mcpable.runtime.call_tool("items_show", args: { id: 2 }, context: {}).payload)
      .to include(cost_cents: 400)
  end

  it "treats a nil user as failing a symbol condition" do
    @viewer = nil
    compile!(:admin?)

    expect(Mcpable.runtime.call_tool("items_show", args: { id: 1 }, context: {}).payload.keys)
      .not_to include(:cost_cents)
  end

  it "refuses a filter that targets a conditionally visible attribute" do
    builder = Mcpable::Dsl::ResourceBuilder.new(ItemRecord)
    builder.name "item"
    builder.attributes :id, :name
    builder.attribute :cost_cents, if: :admin?
    builder.filter :cost_cents, type: :integer
    builder.source Mcpable::Sources::EnumerableSource.new(-> { [] })

    expect { builder.compile }
      .to raise_error(ArgumentError, /filters on conditionally visible attributes: cost_cents/)
  end

  it "keeps conditional attributes out of the default order whitelist" do
    captured = nil
    factory = lambda do |target, order_whitelist:|
      captured = order_whitelist
      Mcpable::Sources::EnumerableSource.new(-> { [] })
    end

    previous = Mcpable::Dsl::ResourceBuilder.source_factory
    Mcpable::Dsl::ResourceBuilder.source_factory = factory
    begin
      builder = Mcpable::Dsl::ResourceBuilder.new(ItemRecord)
      builder.name "item"
      builder.attributes :id, :name
      builder.attribute :cost_cents, if: :admin?
      builder.compile
    ensure
      Mcpable::Dsl::ResourceBuilder.source_factory = previous
    end

    expect(captured).to eq(%i[id name])
  end
end
