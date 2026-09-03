# frozen_string_literal: true

module Mcpable
  module Ports
    class Transport
      attr_reader :registry, :runtime, :profile

      def initialize(registry:, runtime:, profile: :default)
        @registry = registry
        @runtime = runtime
        @profile = profile
      end

      def list_tools
        raise NotImplementedError, "#{self.class}#list_tools"
      end

      def handle(raw_request, context: {})
        raise NotImplementedError, "#{self.class}#handle"
      end

      def serve_stdio
        raise NotImplementedError, "#{self.class}#serve_stdio"
      end
    end
  end
end
