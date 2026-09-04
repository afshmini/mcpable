# mcpable

Expose Ruby objects and Rails models as MCP (Model Context Protocol) tools.

A tool is a `Mcpable::Definition`. Definitions are compiled by a DSL, stored in a
`Mcpable::Registry`, executed through a middleware `Mcpable::Pipeline`, and served by a
`Mcpable::Ports::Transport`. The core is plain Ruby — no Rails, no ActiveRecord.

## Concepts

Four ports are pluggable:

| Port | Contract |
| --- | --- |
| `Ports::Source` | `fetch(filters:, scope:, page:, per_page:, order:) -> Page`, `find(id, scope:)` |
| `Ports::SchemaStrategy` | `input_schema(definition) -> JSON Schema Hash` |
| `Ports::Middleware` | Rack-style `initialize(app, *args)` / `call(ctx) -> Result` |
| `Ports::Transport` | `list_tools`, `handle(raw_request, context:)`, `serve_stdio` |

`Definition` carries `name`, `description`, `arguments`, `handler`, `annotations`
(`read_only:`, `destructive:`, `open_world:`), `profiles` and a free-form `metadata` hash
(`model:`, `action:`, `policy:`, `per_page:`, `paginated:`).

`Argument` carries `name`, `type` (`:string :integer :number :boolean :date :datetime`),
`required`, `description`, `enum` and an optional `filter` spec
`{ kind: :eq | :match | :range_from | :range_to | :scope, target: :column }`.

A handler receives a `ToolCall` (`#args`, `#context`, `#assigns`, `#user`, `#scope`) and
returns a `Result` (`Result.ok(payload)`, `Result.deny(msg)`, `Result.fail(msg)`).

`scope` is an opaque visibility constraint written into `ctx.assigns[:scope]` by auth
middleware. A source composes it and never widens it; a `nil` scope means the source's base.

## Data-backed resources

```ruby
class CostCenter
  include Mcpable::Resource

  mcpable do
    description "Cost centers"
    attributes :id, :name, :number, :company_id
    filter :company_id, type: :integer
    filter :name, match: :partial, type: :string
    filter :created_at, range: true, type: :date
    source Mcpable::Sources::EnumerableSource.new(-> { CostCenter.all_records })
    order_whitelist :id, :name
    policy CostCenterPolicy
    actions :list, :show
    default_page_size 25
    profiles :default
  end
end
```

This compiles two definitions: `cost_centers_list` (paginated, filter arguments,
`metadata[:action] == :list`) and `cost_centers_show` (a required `id`).
`range: true` expands into `created_at_from` / `created_at_to`.

In core, `filter` requires an explicit `type:` and `source` is mandatory. Two soft hooks relax
both. `require "mcpable/active_record"` installs a type inferrer
(`Mcpable::Dsl::ResourceBuilder.type_inferrer`) that reads `columns_hash` and `defined_enums`,
after which `type:` is optional for AR-backed classes, and a source factory
(`Mcpable::Dsl::ResourceBuilder.source_factory`) that wires an `Mcpable::ActiveRecord::Source`
for any AR model, after which `source` is optional too. An explicitly declared `source` always
wins. `order_whitelist` defaults to the declared `attributes`.

## Command tools

```ruby
class Payslip::Regenerate
  include Mcpable::Tool

  mcp_tool do
    name "payslip_regenerate"
    description "Regenerates a payslip."
    argument :payroll_id, :integer, required: true, description: "Payroll id."
    annotations read_only: false, destructive: true
    profiles :default, :admin
  end

  def call(payroll_id:)
    Payroll.find(payroll_id).regenerate!
  end
end
```

`name` defaults to the underscored class name. Only declared arguments are forwarded to
`#call`. A non-`Result` return value is wrapped in `Result.ok`. The instance is handed the
`ToolCall` before `#call` runs, so `current_user`, `current_scope` and `current_context` are
available inside the tool. Declaring `metadata model:, action:, policy:` lets the Pundit
middleware authorize a command tool the same way it authorizes a resource.

## Pipeline

```ruby
Mcpable.configure do |config|
  config.pipeline.use(MyApp::Mcp::AuthenticateUser)
  config.pipeline.use(Mcpable::Pundit::Authorize)
  config.pipeline.use(MyApp::Mcp::AuditLog)

  config.schema_strategy = Mcpable::SchemaStrategies::ExplicitSchema.new
  config.error_mapper    = ->(e) { Sentry.capture_exception(e); Mcpable::Result.fail("internal error") }
  config.context_builder = ->(env) { { user_id: env["warden"]&.user&.id } }
end
```

The first `use` is the outermost middleware. A middleware communicates only through
`ctx.assigns`. Any `StandardError` raised inside the pipeline goes through `error_mapper`,
and the pipeline always returns a `Result`.

Execute a tool with `Mcpable.runtime.call_tool(name, args:, context:)`, which symbolizes and
coerces arguments, validates required and unknown arguments, then runs the pipeline.

## Serving

```ruby
require "mcpable/transports/official_mcp"

transport = Mcpable::Transports::OfficialMcp.new(profile: :default)
transport.list_tools
transport.handle(request_body, context: { user_id: 1 })
transport.serve_stdio
```

Built on the official [`mcp`](https://rubygems.org/gems/mcp) gem: tools are built with
`MCP::Tool.define`, requests go through `MCP::Server#handle_json` (String in, String out) or
`#handle` (Hash in, Hash out), and stdio uses `MCP::Server::Transports::StdioTransport`.
`Result.ok` becomes a text response carrying the JSON payload; `denied` and `error` become
`isError` responses.

## Adapter require paths

`require "mcpable"` loads the core only. Adapters are opt-in:

```ruby
require "mcpable/transports/official_mcp"  # needs the mcp gem
require "mcpable/active_record"            # needs ActiveRecord
require "mcpable/pundit"                   # duck-typed, does not need the pundit gem
require "mcpable/rails"                    # needs Rails
```

`Mcpable::Pundit::Authorize` reads `metadata[:policy]`, calls `#<action>?`, and on the read
actions `:list` and `:show` resolves `Policy::Scope` into `ctx.assigns[:scope]`. A policy
without its own `Scope` class raises `Mcpable::MissingScopeError` rather than silently listing
everything. Scoping `:show` too is what stops `<plural>_show` from reading a record the caller
may not see.

`Mcpable::ActiveRecord::Source` maps filters to `where`, a case-insensitive Arel `matches`
(`ILIKE` on PostgreSQL, `LIKE` elsewhere), Arel `gteq`/`lteq` and named scopes, composes
visibility with `relation.merge(scope)`, and restricts ordering to the `order_whitelist:` given
to its constructor.

`mcpable/rails` mounts `POST /mcp`, and on every `to_prepare` it resets the registry and
re-registers the definitions in `config.mcpable.eager_load_paths` through the application's
Zeitwerk loaders, so code reloading neither drops tools nor raises `DuplicateToolError`. It
skips registration while the database schema is not yet loaded, so `db:create` and `db:migrate`
still work on a fresh checkout even though the DSL reads `columns_hash` at class-definition
time.

## Status

v0.1. Core, DSL, pipeline, `EnumerableSource`, `ExplicitSchema`, the Pundit middleware, the
Rails loader and the `mcp` transport are covered by this repository's specs.

`mcpable/rails` and `mcpable/active_record` cannot be unit-tested here — there is no Rails or
ActiveRecord in the development bundle — but they are now exercised end to end by the
`mcpable-demo` application in the sibling directory, which boots Rails 8.1 on SQLite and asserts
tenancy isolation, every filter kind, pagination, command-tool authorization and
`MissingScopeError` handling over real JSON-RPC requests to `POST /mcp`, under both code
reloading and eager loading.

Splitting the adapters into separate gems is a later step; for now everything ships from one
gemspec whose only runtime dependency is `mcp`.

## License

MIT.
