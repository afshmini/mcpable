# frozen_string_literal: true

require "json"
require "mcp"

module Mcpable
  module Transports
    class OfficialMcp < Ports::Transport
      DEFAULT_SERVER_NAME = "mcpable"

      attr_reader :server_name, :server_version

      def initialize(registry: nil, runtime: nil, profile: :default,
                     server_name: DEFAULT_SERVER_NAME, server_version: Mcpable::VERSION)
        super(
          registry: registry || Mcpable.registry,
          runtime: runtime || Mcpable.runtime,
          profile: profile
        )
        @server_name = server_name
        @server_version = server_version
      end

      def list_tools
        build_tools({}).map(&:to_h)
      end

      def handle(raw_request, context: {})
        server = build_server(context)

        case raw_request
        when String then server.handle_json(raw_request)
        when Hash then server.handle(symbolize_deep(raw_request))
        else raise ArgumentError, "unsupported request: #{raw_request.class}"
        end
      end

      def serve_stdio(context: {})
        MCP::Server::Transports::StdioTransport.new(build_server(context)).open
      end

      def build_server(context = {})
        MCP::Server.new(
          name: server_name,
          version: server_version,
          tools: build_tools(context)
        )
      end

      private

      def definitions
        registry.for_profile(profile)
      end

      def build_tools(context)
        definitions.map { |definition| build_tool(definition, context) }
      end

      def build_tool(definition, context)
        runtime = self.runtime
        name = definition.name

        MCP::Tool.define(
          name: name,
          description: definition.description,
          input_schema: normalize_schema(Mcpable.config.schema_strategy.input_schema(definition)),
          annotations: annotations_for(definition)
        ) do |**args|
          args.delete(:server_context)
          OfficialMcp.to_mcp_response(runtime.call_tool(name, args: args, context: context))
        end
      end

      def annotations_for(definition)
        {
          read_only_hint: definition.read_only?,
          destructive_hint: definition.destructive?,
          open_world_hint: definition.open_world?
        }
      end

      def normalize_schema(schema)
        JSON.parse(JSON.generate(schema))
      end

      def symbolize_deep(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_sym, symbolize_deep(v)] }
        when Array then value.map { |v| symbolize_deep(v) }
        else value
        end
      end

      def self.to_mcp_response(result)
        if result.ok?
          MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result.payload) }])
        else
          MCP::Tool::Response.new(
            [{ type: "text", text: "#{result.status}: #{result.error}" }],
            error: true
          )
        end
      end
    end
  end
end
