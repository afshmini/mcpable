# frozen_string_literal: true

module Mcpable
  module Pundit
    class Authorize < Ports::Middleware
      def call(ctx)
        policy_class = ctx.definition.metadata[:policy] or return @app.call(ctx)
        record = ctx.definition.metadata[:model]
        action = ctx.definition.metadata[:action]
        policy = policy_class.new(ctx.user, record)
        return Result.deny("not authorized") unless policy.public_send("#{action}?")

        if action == :list
          scope_class = policy_class.const_defined?(:Scope, false) ? policy_class.const_get(:Scope, false) : nil
          raise MissingScopeError, policy_class.name unless scope_class

          base = record.respond_to?(:all) ? record.all : record
          ctx.assigns[:scope] = scope_class.new(ctx.user, base).resolve
        end

        @app.call(ctx)
      end
    end
  end
end
