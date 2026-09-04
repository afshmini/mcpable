# frozen_string_literal: true

require "mcpable"
require "mcpable/active_record/column_inference"
require "mcpable/active_record/source"

Mcpable::Dsl::ResourceBuilder.type_inferrer = lambda do |model, name|
  Mcpable::ActiveRecord::ColumnInference.infer(model, name)
end

Mcpable::Dsl::ResourceBuilder.source_factory = lambda do |model, order_whitelist:|
  next nil unless Mcpable::ActiveRecord::Source.supports?(model)

  Mcpable::ActiveRecord::Source.new(model, order_whitelist: order_whitelist)
end
