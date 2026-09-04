# frozen_string_literal: true

module Mcpable
  module Tool
    def self.included(base)
      base.extend(ClassMethods)
    end

    attr_accessor :mcp_call

    def current_user = mcp_call&.user

    def current_scope = mcp_call&.scope

    def current_context = mcp_call&.context || {}

    module ClassMethods
      attr_reader :mcp_definition

      def mcp_tool(&block)
        builder = Dsl::ToolBuilder.new(self)
        Dsl.evaluate(builder, &block)
        @mcp_definition = builder.compile
        Mcpable.registry.register(@mcp_definition)
        @mcp_definition
      end
    end
  end
end
