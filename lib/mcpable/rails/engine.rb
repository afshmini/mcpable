# frozen_string_literal: true

require "rails/engine"
require "mcpable/rails/loader"

module Mcpable
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Mcpable::Rails

      config.mcpable = ActiveSupport::OrderedOptions.new
      config.mcpable.eager_load_paths = %w[app/models app/tools]

      initializer "mcpable.routes" do |app|
        app.routes.append do
          post "/mcp", to: "mcpable/rails/tools#create", as: :mcpable_root
        end
      end

      config.to_prepare do
        if Mcpable::Rails::Loader.schema_ready?
          Mcpable::Rails::Loader.reload!
        else
          ::Rails.logger&.warn("[mcpable] database schema is not ready; no MCP tools were registered")
        end
      end
    end
  end
end
