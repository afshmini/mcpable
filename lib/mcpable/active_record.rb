# frozen_string_literal: true

require "mcpable"
require "mcpable/active_record/column_inference"
require "mcpable/active_record/source"

Mcpable::Dsl::ResourceBuilder.type_inferrer = lambda do |model, name|
  Mcpable::ActiveRecord::ColumnInference.infer(model, name)
end
