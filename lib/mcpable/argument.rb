# frozen_string_literal: true

module Mcpable
  Argument = Data.define(
    :name,
    :type,
    :required,
    :description,
    :enum,
    :filter
  ) do
    def self.build(name, type:, required: false, description: nil, enum: nil, filter: nil)
      new(
        name: name.to_sym,
        type: type.to_sym,
        required: required,
        description: description,
        enum: enum,
        filter: filter
      )
    end

    def filter? = !filter.nil?

    def filter_kind = filter && filter[:kind]

    def filter_target = filter && filter[:target]
  end
end
