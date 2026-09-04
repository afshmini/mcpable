# frozen_string_literal: true

require "json"
require "stringio"
require "mcpable/transports/official_mcp"

RSpec.describe Mcpable::Transports::OfficialMcp do
  subject(:transport) { described_class.new }

  let(:handler) { ->(ctx) { Mcpable::Result.ok(echo: ctx.args, context: ctx.context) } }

  def register(name: "cost_centers_list", profiles: [:default], arguments: nil, metadata: { paginated: true },
               annotations: { read_only: true }, handler: self.handler)
    arguments ||= [
      Mcpable::Argument.build(:company_id, type: :integer, required: true, description: "Company id."),
      Mcpable::Argument.build(:status, type: :string, enum: %w[open closed])
    ]

    Mcpable.registry.register(
      Mcpable::Definition.build(
        name: name,
        description: "Cost centers.",
        arguments: arguments,
        handler: handler,
        annotations: annotations,
        profiles: profiles,
        metadata: metadata
      )
    )
  end

  def rpc(method, params = nil, id: 1)
    JSON.generate({ jsonrpc: "2.0", id: id, method: method, params: params }.compact)
  end

  describe "#list_tools" do
    it "returns the registered tool names" do
      register
      register(name: "payslip_regenerate", arguments: [], metadata: {})
      expect(transport.list_tools.map { |t| t[:name] }).to contain_exactly("cost_centers_list", "payslip_regenerate")
    end

    it "only exposes tools in the transport profile" do
      register(name: "public_list", profiles: [:default])
      register(name: "admin_list", profiles: [:admin])

      expect(transport.list_tools.map { |t| t[:name] }).to eq(["public_list"])
      expect(described_class.new(profile: :admin).list_tools.map { |t| t[:name] }).to eq(["admin_list"])
    end

    it "renders the input schema from the configured schema strategy" do
      register
      schema = transport.list_tools.first[:inputSchema]

      expect(schema[:type]).to eq("object")
      expect(schema[:required]).to eq(["company_id"])
      expect(schema[:properties][:company_id]).to eq(type: "integer", description: "Company id.")
      expect(schema[:properties][:status]).to eq(type: "string", enum: %w[open closed])
      expect(schema[:properties].keys).to include(:page, :per_page, :order)
    end

    it "maps annotations onto MCP hints" do
      register(annotations: { read_only: false, destructive: true, open_world: true })
      annotations = transport.list_tools.first[:annotations]

      expect(annotations[:readOnlyHint]).to be(false)
      expect(annotations[:destructiveHint]).to be(true)
      expect(annotations[:openWorldHint]).to be(true)
    end
  end

  describe "#handle" do
    it "answers tools/list over JSON-RPC" do
      register
      response = JSON.parse(transport.handle(rpc("tools/list")))
      expect(response["result"]["tools"].map { |t| t["name"] }).to eq(["cost_centers_list"])
    end

    it "executes a registered tool through tools/call" do
      register
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 5 } }, id: 2))
      response = JSON.parse(raw)

      expect(response["id"]).to eq(2)
      expect(response["result"]["isError"]).to be(false)

      payload = JSON.parse(response["result"]["content"].first["text"])
      expect(payload["echo"]).to eq("company_id" => 5)
    end

    it "forwards optional and pagination arguments" do
      register
      raw = transport.handle(
        rpc("tools/call", { name: "cost_centers_list",
                            arguments: { company_id: 5, status: "open", page: 2, per_page: 10, order: "-name" } })
      )
      payload = JSON.parse(JSON.parse(raw)["result"]["content"].first["text"])

      expect(payload["echo"]).to eq(
        "company_id" => 5, "status" => "open", "page" => 2, "per_page" => 10, "order" => "-name"
      )
    end

    it "does not leak the mcp server_context keyword into tool arguments" do
      register
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } }))
      payload = JSON.parse(JSON.parse(raw)["result"]["content"].first["text"])

      expect(payload["echo"].keys).to eq(["company_id"])
    end

    it "rejects a missing required argument" do
      register
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: {} }))
      result = JSON.parse(raw)["result"]

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to match(/company_id/)
    end

    it "passes the transport context to the handler" do
      register
      raw = transport.handle(
        rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } }),
        context: { user_id: 42 }
      )
      payload = JSON.parse(JSON.parse(raw)["result"]["content"].first["text"])
      expect(payload["context"]).to eq("user_id" => 42)
    end

    it "reports a denied result as an error response" do
      register(handler: ->(_ctx) { Mcpable::Result.deny("not authorized") })
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } }))
      result = JSON.parse(raw)["result"]

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to eq("denied: not authorized")
    end

    it "reports a failed result as an error response" do
      register(handler: ->(_ctx) { Mcpable::Result.fail("boom") })
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } }))
      result = JSON.parse(raw)["result"]

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to eq("error: boom")
    end

    it "lets the mcp server reject an argument that violates the input schema" do
      register
      raw = transport.handle(rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: "abc" } }))
      result = JSON.parse(raw)["result"]

      expect(result["isError"]).to be(true)
      expect(result["content"].first["text"]).to match(/company_id/)
    end

    it "accepts a parsed hash request" do
      register
      response = transport.handle({ "jsonrpc" => "2.0", "id" => 3, "method" => "tools/list" })
      expect(response[:result][:tools].map { |t| t[:name] }).to eq(["cost_centers_list"])
    end

    it "returns nil for a notification" do
      register
      expect(transport.handle(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))).to be_nil
    end
  end

  describe "#serve_stdio" do
    def serve(lines, context: {})
      original_stdin = $stdin
      original_stdout = $stdout
      $stdin = StringIO.new(lines.map { |line| "#{line}\n" }.join)
      $stdout = StringIO.new
      transport.serve_stdio(context: context)
      $stdout.string.each_line.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
    end

    it "completes the handshake and lists tools over a newline delimited stream" do
      register
      responses = serve([
        rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "1" } }),
        JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"),
        rpc("tools/list", nil, id: 2)
      ])

      expect(responses.length).to eq(2)
      expect(responses.first["result"]["protocolVersion"]).to eq("2025-06-18")
      expect(responses.first["result"]["serverInfo"]["name"]).to eq("mcpable")
      expect(responses.first["result"]["capabilities"]).to include("tools")
      expect(responses.last["id"]).to eq(2)
      expect(responses.last["result"]["tools"].map { |t| t["name"] }).to eq(["cost_centers_list"])
    end

    it "runs every tool call on the connection under the context given at startup" do
      register
      responses = serve(
        [rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } })],
        context: { api_token: "nw-member-token" }
      )
      payload = JSON.parse(responses.first["result"]["content"].first["text"])

      expect(payload["context"]).to eq("api_token" => "nw-member-token")
    end

    it "defaults to an empty context" do
      register
      responses = serve([rpc("tools/call", { name: "cost_centers_list", arguments: { company_id: 1 } })])
      payload = JSON.parse(responses.first["result"]["content"].first["text"])

      expect(payload["context"]).to eq({})
    end

    it "writes nothing for a notification" do
      register
      expect(serve([JSON.generate(jsonrpc: "2.0", method: "notifications/initialized")])).to be_empty
    end
  end
end
