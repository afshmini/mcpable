# frozen_string_literal: true

module Mcpable
  module Dsl
    module_function

    def evaluate(builder, &block)
      return builder if block.nil?

      if block.arity == 1
        block.call(builder)
      else
        builder.instance_eval(&block)
      end
      builder
    end
  end
end
