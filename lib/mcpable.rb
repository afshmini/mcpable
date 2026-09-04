# frozen_string_literal: true

require "mcpable/version"

module Mcpable
  class Error < StandardError; end

  class DuplicateToolError < Error
    def initialize(name) = super("tool already registered: #{name}")
  end

  class UnknownToolError < Error
    def initialize(name) = super("unknown tool: #{name}")
  end

  class MissingScopeError < Error
    def initialize(name) = super("policy #{name} has no Scope class")
  end
end

require "mcpable/naming"
require "mcpable/argument"
require "mcpable/definition"
require "mcpable/result"
require "mcpable/tool_call"
require "mcpable/ports/source"
require "mcpable/ports/schema_strategy"
require "mcpable/ports/middleware"
require "mcpable/ports/transport"
require "mcpable/pipeline"
require "mcpable/registry"
require "mcpable/runtime"
require "mcpable/schema_strategies/explicit_schema"
require "mcpable/sources/enumerable_source"
require "mcpable/dsl"
require "mcpable/dsl/tool_builder"
require "mcpable/dsl/resource_builder"
require "mcpable/tool"
require "mcpable/resource"

module Mcpable
  class Configuration
    DEFAULT_ERROR_MAPPER = ->(_error) { Result.fail("internal error") }
    DEFAULT_CONTEXT_BUILDER = ->(_env) { {} }

    attr_reader :pipeline
    attr_accessor :schema_strategy, :error_mapper, :context_builder

    def initialize
      @pipeline = Pipeline.new(config: self)
      @schema_strategy = SchemaStrategies::ExplicitSchema.new
      @error_mapper = DEFAULT_ERROR_MAPPER
      @context_builder = DEFAULT_CONTEXT_BUILDER
    end
  end

  class << self
    def registry = @registry ||= Registry.new

    def config = @config ||= Configuration.new

    def configure
      yield config
      config
    end

    def runtime = @runtime ||= Runtime.new

    def reset!
      @registry = Registry.new
      @config = Configuration.new
      @runtime = Runtime.new
      self
    end
  end
end
