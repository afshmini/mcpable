# frozen_string_literal: true

require "mcpable/pundit"

RSpec.describe Mcpable::Pundit::Authorize do
  let(:user) { double("user", id: 7) }
  let(:records) { [{ id: 1, owner: 7 }, { id: 2, owner: 8 }] }

  let(:model) do
    rows = records
    Class.new do
      define_singleton_method(:all) { rows }
    end
  end

  let(:permissive_policy) do
    Class.new do
      def initialize(user, record)
        @user = user
        @record = record
      end

      def list? = true
      def show? = true

      self::Scope = Class.new do
        def initialize(user, scope)
          @user = user
          @scope = scope
        end

        def resolve = @scope.select { |r| r[:owner] == @user.id }
      end
    end
  end

  let(:restrictive_policy) do
    Class.new do
      def initialize(user, record); end

      def list? = false
      def show? = false
    end
  end

  let(:scopeless_policy) do
    Class.new do
      def initialize(user, record); end

      def list? = true

      def self.name = "ScopelessPolicy"
    end
  end

  def definition(action:, policy:)
    Mcpable::Definition.build(
      name: "probe",
      metadata: { model: model, action: action, policy: policy },
      handler: ->(ctx) { Mcpable::Result.ok(scope: ctx.scope, user: ctx.user) }
    )
  end

  let(:assign_user_middleware) do
    current_user = user
    Class.new(Mcpable::Ports::Middleware) do
      define_method(:call) do |ctx|
        ctx.assigns[:user] ||= current_user
        @app.call(ctx)
      end
    end
  end

  before do
    Mcpable.config.pipeline.use(assign_user_middleware)
  end

  def call(action:, policy:)
    Mcpable.config.pipeline.use(described_class)
    ctx = Mcpable::ToolCall.new(definition: definition(action: action, policy: policy), args: {}, context: {})
    Mcpable.config.pipeline.call(ctx)
  end

  it "assigns the policy scope on show so a record cannot be read across tenants" do
    result = call(action: :show, policy: permissive_policy)
    expect(result).to be_ok
    expect(result.payload[:scope]).to eq([{ id: 1, owner: 7 }])
    expect(result.payload[:user]).to be(user)
  end

  it "refuses a show loudly when the policy has no Scope class" do
    Mcpable.configure { |c| c.error_mapper = ->(e) { raise e } }
    scopeless = scopeless_policy
    scopeless.define_method(:show?) { true }

    expect { call(action: :show, policy: scopeless) }
      .to raise_error(Mcpable::MissingScopeError, /ScopelessPolicy/)
  end

  it "leaves the scope alone for a non-read action" do
    writable = permissive_policy
    writable.define_method(:update?) { true }

    result = call(action: :update, policy: writable)
    expect(result).to be_ok
    expect(result.payload[:scope]).to be_nil
  end

  it "assigns the policy scope on list" do
    result = call(action: :list, policy: permissive_policy)
    expect(result).to be_ok
    expect(result.payload[:scope]).to eq([{ id: 1, owner: 7 }])
  end

  it "denies an unauthorized action" do
    result = call(action: :show, policy: restrictive_policy)
    expect(result.status).to eq(:denied)
    expect(result.error).to eq("not authorized")
  end

  it "denies an unauthorized list before resolving any scope" do
    expect(call(action: :list, policy: restrictive_policy).status).to eq(:denied)
  end

  it "refuses a list loudly when the policy has no Scope class" do
    Mcpable.configure { |c| c.error_mapper = ->(e) { raise e } }
    expect { call(action: :list, policy: scopeless_policy) }
      .to raise_error(Mcpable::MissingScopeError, /ScopelessPolicy/)
  end

  it "surfaces the missing scope through the error mapper by default" do
    result = call(action: :list, policy: scopeless_policy)
    expect(result.status).to eq(:error)
    expect(result.error).to eq("internal error")
  end

  it "does not consider an inherited Scope constant" do
    Mcpable.configure { |c| c.error_mapper = ->(e) { raise e } }
    subclass = Class.new(permissive_policy) { def self.name = "SubPolicy" }
    expect { call(action: :list, policy: subclass) }.to raise_error(Mcpable::MissingScopeError)
  end

  it "passes straight through when there is no policy" do
    expect(call(action: :list, policy: nil)).to be_ok
  end
end
