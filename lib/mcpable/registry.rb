# frozen_string_literal: true

module Mcpable
  class Registry
    def initialize
      @definitions = {}
    end

    def register(definition)
      name = definition.name.to_s
      raise DuplicateToolError, name if @definitions.key?(name)

      @definitions[name] = definition
    end

    def fetch(name)
      @definitions.fetch(name.to_s) { raise UnknownToolError, name.to_s }
    end

    def key?(name) = @definitions.key?(name.to_s)

    def for_profile(profile)
      @definitions.values.select { |d| d.profiles.include?(profile) }
    end

    def all = @definitions.values

    def names = @definitions.keys

    def reset!
      @definitions = {}
      self
    end
  end
end
