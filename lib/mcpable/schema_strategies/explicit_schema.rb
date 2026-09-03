# frozen_string_literal: true

module Mcpable
  module SchemaStrategies
    class ExplicitSchema < Ports::SchemaStrategy
      JSON_TYPES = {
        integer: "integer",
        number: "number",
        boolean: "boolean",
        string: "string",
        date: "string",
        datetime: "string"
      }.freeze

      FORMATS = { date: "date", datetime: "date-time" }.freeze

      PAGINATION_PROPERTIES = {
        page: { type: "integer", description: "Page number, 1-based." },
        per_page: { type: "integer", description: "Records per page." },
        order: { type: "string", description: "Sort attribute, prefix with - for descending." }
      }.freeze

      def input_schema(definition)
        properties = {}
        required = []

        definition.arguments.each do |argument|
          properties[argument.name] = property_for(argument)
          required << argument.name if argument.required
        end

        properties = properties.merge(PAGINATION_PROPERTIES) if definition.metadata[:paginated]

        { type: "object", properties: properties, required: required }
      end

      private

      def property_for(argument)
        property = { type: JSON_TYPES.fetch(argument.type, "string") }
        format = FORMATS[argument.type]
        property[:format] = format if format
        property[:description] = argument.description if argument.description
        property[:enum] = argument.enum if argument.enum
        property
      end
    end
  end
end
