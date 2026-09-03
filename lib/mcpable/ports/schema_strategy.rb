# frozen_string_literal: true

module Mcpable
  module Ports
    class SchemaStrategy
      def input_schema(definition)
        raise NotImplementedError, "#{self.class}#input_schema"
      end
    end
  end
end
