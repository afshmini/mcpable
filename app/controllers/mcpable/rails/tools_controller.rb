# frozen_string_literal: true

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
  end
end
