# frozen_string_literal: true

module Mcpable
  module Naming
    module_function

    def underscore(value)
      value
        .to_s
        .gsub("::", "_")
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr("-", "_")
        .downcase
    end

    def pluralize(value)
      word = value.to_s
      case word
      when /(?:s|x|z|ch|sh)\z/ then "#{word}es"
      when /[^aeiou]y\z/ then "#{word[0..-2]}ies"
      when /f\z/ then "#{word[0..-2]}ves"
      when /fe\z/ then "#{word[0..-3]}ves"
      else "#{word}s"
      end
    end
  end
end
