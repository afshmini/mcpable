# frozen_string_literal: true

module Mcpable
  class ToolCall
    attr_reader :definition, :args, :context, :assigns

    def initialize(definition:, args:, context:)
      @definition = definition
      @args = args
      @context = context
      @assigns = {}
    end

    def user = assigns[:user]

    def scope = assigns[:scope]
  end
end
