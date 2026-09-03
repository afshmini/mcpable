# frozen_string_literal: true

module Mcpable
  module Resource
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      attr_reader :mcp_definitions

      def mcpable(&block)
        builder = Dsl::ResourceBuilder.new(self)
        Dsl.evaluate(builder, &block)
        @mcp_definitions = builder.compile
        @mcp_definitions.each { |definition| Mcpable.registry.register(definition) }
        @mcp_definitions
      end
    end
  end
end
