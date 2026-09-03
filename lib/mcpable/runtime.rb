# frozen_string_literal: true

require "date"
require "time"

module Mcpable
  class Runtime
    PAGINATION_TYPES = { page: :integer, per_page: :integer, order: :string }.freeze

    class CoercionError < StandardError; end

    attr_reader :registry, :config

    def initialize(registry: nil, config: nil)
      @registry = registry
      @config = config
    end

    def call_tool(name, args: {}, context: {})
      definition = current_registry.fetch(name)
      symbolized = symbolize(args)

      known = allowed_types(definition)
      unknown = symbolized.keys - known.keys
      return Result.fail("unknown arguments: #{unknown.join(', ')}") if unknown.any?

      missing = definition.arguments.select(&:required).map(&:name) - symbolized.keys
      return Result.fail("missing required arguments: #{missing.join(', ')}") if missing.any?

      coerced =
        begin
          coerce_all(symbolized, known)
        rescue CoercionError => e
          return Result.fail(e.message)
        end

      ctx = ToolCall.new(definition: definition, args: coerced, context: context)
      current_config.pipeline.call(ctx)
    end

    private

    def current_registry = @registry || Mcpable.registry

    def current_config = @config || Mcpable.config

    def symbolize(args)
      (args || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    def allowed_types(definition)
      types = definition.arguments.to_h { |a| [a.name, a.type] }
      types = PAGINATION_TYPES.merge(types) if definition.metadata[:paginated]
      types
    end

    def coerce_all(args, types)
      args.each_with_object({}) do |(key, value), out|
        out[key] = coerce(key, value, types[key])
      end
    end

    def coerce(key, value, type)
      return nil if value.nil?

      case type
      when :integer then coerce_integer(key, value)
      when :number then coerce_number(key, value)
      when :boolean then coerce_boolean(key, value)
      when :date then coerce_date(key, value)
      when :datetime then coerce_datetime(key, value)
      when :string then value.to_s
      else value
      end
    end

    def coerce_integer(key, value)
      return value if value.is_a?(Integer)

      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      raise CoercionError, "#{key} is not an integer"
    end

    def coerce_number(key, value)
      return value if value.is_a?(Numeric)

      Float(value.to_s)
    rescue ArgumentError, TypeError
      raise CoercionError, "#{key} is not a number"
    end

    def coerce_boolean(key, value)
      case value
      when true, false then value
      when "true", "1", 1 then true
      when "false", "0", 0 then false
      else raise CoercionError, "#{key} is not a boolean"
      end
    end

    def coerce_date(key, value)
      return value if value.is_a?(Date) && !value.is_a?(DateTime)

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise CoercionError, "#{key} is not an ISO8601 date"
    end

    def coerce_datetime(key, value)
      return value if value.is_a?(Time)

      Time.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise CoercionError, "#{key} is not an ISO8601 datetime"
    end
  end
end
