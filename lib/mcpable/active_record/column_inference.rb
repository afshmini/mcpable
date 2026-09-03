# frozen_string_literal: true

module Mcpable
  module ActiveRecord
    module ColumnInference
      TYPE_MAP = {
        integer: :integer,
        bigint: :integer,
        float: :number,
        decimal: :number,
        boolean: :boolean,
        date: :date,
        datetime: :datetime,
        timestamp: :datetime
      }.freeze

      module_function

      def infer(model, name)
        return nil unless model.respond_to?(:columns_hash)

        enum = enum_values(model, name)
        return { type: :string, enum: enum } if enum

        column = model.columns_hash[name.to_s]
        return nil if column.nil?

        { type: TYPE_MAP.fetch(column.type, :string), enum: nil }
      end

      def enum_values(model, name)
        return nil unless model.respond_to?(:defined_enums)

        values = model.defined_enums[name.to_s]
        values && values.keys
      end

      def to_proc
        method(:infer).to_proc
      end
    end
  end
end
