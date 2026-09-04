# frozen_string_literal: true

module Mcpable
  module Pundit
    class Authorize < Ports::Middleware
      SCOPED_ACTIONS = %i[list show].freeze

      def call(ctx)
        policy_class = ctx.definition.metadata[:policy] or return @app.call(ctx)
        record = ctx.definition.metadata[:model]
        action = ctx.definition.metadata[:action]
        policy = policy_class.new(ctx.user, record)
        return Result.deny("not authorized") unless policy.public_send("#{action}?")

        ctx.assigns[:scope] = resolve_scope(policy_class, ctx.user, record) if SCOPED_ACTIONS.include?(action)

        @app.call(ctx)
      end

      private

      def resolve_scope(policy_class, user, record)
        scope_class = policy_class.const_defined?(:Scope, false) ? policy_class.const_get(:Scope, false) : nil
        raise MissingScopeError, policy_class.name unless scope_class

        base = record.respond_to?(:all) ? record.all : record
        scope_class.new(user, base).resolve
      end
    end
  end
end
