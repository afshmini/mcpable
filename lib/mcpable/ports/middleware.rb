# frozen_string_literal: true

module Mcpable
  module Ports
    class Middleware
      attr_reader :app

      def initialize(app, *args)
        @app = app
        @args = args
      end

      def call(ctx)
        @app.call(ctx)
      end
    end
  end
end
