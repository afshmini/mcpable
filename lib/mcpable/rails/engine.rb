# frozen_string_literal: true

require "rails/engine"

module Mcpable
  module Rails
    class ToolsController < ActionController::API
      def create
        transport = Mcpable::Transports::OfficialMcp.new(
          registry: Mcpable.registry,
          runtime: Mcpable.runtime,
          profile: (params[:profile] || :default).to_sym
        )
        context = Mcpable.config.context_builder.call(request.env)
        response_body = transport.handle(request.body.read, context: context)

        if response_body.nil?
          head :accepted
        else
          render json: response_body
        end
      end
    end

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
        Mcpable.registry.reset!

        Engine.config.mcpable.eager_load_paths.each do |relative|
          path = ::Rails.root.join(relative)
          next unless path.exist?

          Dir.glob(path.join("**", "*.rb")).sort.each do |file|
            require_dependency file
          end
        end
      end
    end
  end
end
