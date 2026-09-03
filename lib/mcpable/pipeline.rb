# frozen_string_literal: true

module Mcpable
  class Pipeline
    HANDLER = lambda do |ctx|
      handler = ctx.definition.handler
      raise Error, "definition #{ctx.definition.name} has no handler" if handler.nil?

      handler.call(ctx)
    end

    attr_reader :middlewares

    def initialize
      @middlewares = []
    end

    def use(mw, *args)
      @middlewares << [mw, args]
      self
    end

    def clear
      @middlewares = []
      self
    end

    def call(ctx)
      result = build_stack.call(ctx)
      result.is_a?(Result) ? result : Result.fail("invalid result")
    rescue StandardError => e
      mapped = Mcpable.config.error_mapper.call(e)
      mapped.is_a?(Result) ? mapped : Result.fail("invalid result")
    end

    private

    def build_stack
      @middlewares.reverse.reduce(HANDLER) do |app, (mw, args)|
        mw.new(app, *args)
      end
    end
  end
end
