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
| `Ports::Transport` | `list_tools`, `handle(raw_request, context:)`, `serve_stdio(context:)` |

`Definition` carries `name`, `description`, `arguments`, `handler`, `annotations`
(`read_only:`, `destructive:`, `open_world:`), `profiles` and a free-form `metadata` hash
(`model:`, `action:`, `policy:`, `per_page:`, `paginated:`).

`Argument` carries `name`, `type` (`:string :integer :number :boolean :date :datetime`),
`required`, `description`, `enum` and an optional `filter` spec
`{ kind: :eq | :match | :range_from | :range_to | :scope, target: :column }`.

A handler receives a `ToolCall` (`#args`, `#context`, `#assigns`, `#user`, `#scope`,
`#definition`) and returns a `Result`:

```ruby
Mcpable::Result.ok(payload)   # status :ok,      payload set, error nil
Mcpable::Result.deny("...")   # status :denied,  payload nil,  error set
Mcpable::Result.fail("...")   # status :error,   payload nil,  error set
```

`#ok?`, `#denied?` and `#error?` read the status.

`scope` is an opaque visibility constraint written into `ctx.assigns[:scope]` by auth
middleware. A source composes it and never widens it; a `nil` scope means the source's base.

The examples below all describe one small multi-tenant store application: a `Store` owns
`Category` and `Product` records, and a `User` belongs to one store.

## Rails quick start

Add the gem and require the Rails adapter, which pulls in the core, the `mcp` transport and
the engine:

```ruby
# Gemfile
gem "mcpable", require: "mcpable/rails"
gem "pundit"
```

Declare tools on your models:

```ruby
class Product < ApplicationRecord
  include Mcpable::Resource

  belongs_to :store
  belongs_to :category

  enum :status, { active: 0, out_of_stock: 1, discontinued: 2 }

  mcpable do
    description "Products of the current user's store."
    attributes :id, :store_id, :category_id, :name, :sku, :price_cents, :status
    filter :category_id, description: "Category id."
    filter :status, description: "Stock status."
    filter :name, match: :partial, description: "Case-insensitive substring of the name."
    policy ProductPolicy
    actions :list, :show
    default_page_size 25
  end
end
```

Write an authentication middleware and wire the pipeline:

```ruby
# lib/mcp/authenticate_user.rb
module Mcp
  class AuthenticateUser < Mcpable::Ports::Middleware
    def call(ctx)
      token = ctx.context[:api_token]
      user = token && User.find_by(api_token: token)
      return Mcpable::Result.deny("unauthenticated") if user.nil?

      ctx.assigns[:user] = user
      @app.call(ctx)
    end
  end
end
```

```ruby
# config/initializers/mcpable.rb
require "mcpable/active_record"
require "mcpable/pundit"

require Rails.root.join("lib/mcp/authenticate_user")
require Rails.root.join("lib/mcp/audit_log")

Mcpable.configure do |config|
  config.pipeline.use(Mcp::AuthenticateUser)
  config.pipeline.use(Mcpable::Pundit::Authorize)
  config.pipeline.use(Mcp::AuditLog)

  config.schema_strategy = Mcpable::SchemaStrategies::ExplicitSchema.new

  config.context_builder = ->(env) { { api_token: env["HTTP_X_API_TOKEN"] } }

  config.error_mapper = lambda do |error|
    Rails.logger.error("[mcp] #{error.class}: #{error.message}")

    case error
    when Mcpable::MissingScopeError
      Mcpable::Result.fail("refusing to run: #{error.message}")
    else
      Mcpable::Result.fail("internal error")
    end
  end
end
```

`Mcpable::Configuration` exposes exactly four things: `pipeline` (read-only), plus the
writable `schema_strategy`, `error_mapper` and `context_builder`. The defaults are an empty
pipeline, `ExplicitSchema`, an error mapper returning `Result.fail("internal error")` and a
context builder returning `{}`.

You do not add a route. `mcpable/rails` appends one in an initializer:

```ruby
post "/mcp", to: "mcpable/rails/tools#create", as: :mcpable_root
```

Middlewares belong in `lib/` and should be `require`d rather than autoloaded: they are
installed into a process-wide pipeline at boot, so Rails must not reload their constants. List
that directory in `config.autoload_lib(ignore:)`.

Then talk to it:

```sh
curl -s -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

curl -s -X POST http://localhost:3000/mcp \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Token: acme-member-token' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"products_list","arguments":{"per_page":3}}}'
```

The endpoint reads `params[:profile]` (`POST /mcp?profile=admin`) to pick which tool set to
serve; it defaults to `:default`.

## Data-backed resources

```ruby
class Product
  include Mcpable::Resource

  mcpable do
    description "Products"
    attributes :id, :name, :sku, :price_cents, :store_id
    filter :store_id, type: :integer
    filter :name, match: :partial, type: :string
    filter :released_on, range: true, type: :date
    source Mcpable::Sources::EnumerableSource.new(-> { Product.all_records })
    policy ProductPolicy
    actions :list, :show
    default_page_size 25
    profiles :default
  end
end
```

This compiles two definitions: `products_list` (paginated, filter arguments,
`metadata[:action] == :list`) and `products_show` (a required `id`).
`range: true` expands into `released_on_from` / `released_on_to`.

`attributes` is the serialization whitelist: a record is rendered as exactly those keys, read
by `public_send` and falling back to `[]`. It is one static list per definition, evaluated at
compile time — a column left out of it is unreachable over MCP for every caller.

`name` overrides the base name used for the tool names; it defaults to the underscored,
namespace-stripped class name, pluralized by `Mcpable::Naming.pluralize`, which handles the
`-s/-x/-z/-ch/-sh`, consonant-`y` and `-f/-fe` cases (`category` → `categories_list`). It is
five regex rules, not an inflector: irregular plurals are not covered (`person` → `persons`),
so name those resources explicitly.

`order_whitelist` defaults to the declared `attributes`, and is only consulted by
`ActiveRecord::Source` — see the note under [Sources](#sources) if you declare a `source`
yourself. `annotations(**values)` starts from `{ read_only: true }` for resources. `profiles`
defaults to `[:default]`. `actions` recognises only `:list` and `:show`.

In core, `filter` requires an explicit `type:` and `source` is mandatory. Two soft hooks relax
both. `require "mcpable/active_record"` installs a type inferrer
(`Mcpable::Dsl::ResourceBuilder.type_inferrer`) that reads `columns_hash` and `defined_enums`,
after which `type:` is optional for AR-backed classes, and a source factory
(`Mcpable::Dsl::ResourceBuilder.source_factory`) that wires an `Mcpable::ActiveRecord::Source`
for any AR model, after which `source` is optional too. An explicitly declared `source` always
wins.

## Filter kinds

Every `filter` line expands into one or two `Argument`s, each carrying a
`filter: { kind:, target: }` spec that the source reads back. `target` is always the declared
filter name; only `range: true` gives the arguments different names.

| DSL | Arguments generated | Compiled spec | `ActiveRecord::Source` emits |
| --- | --- | --- | --- |
| `filter :category_id` | `category_id` | `{ kind: :eq, target: :category_id }` | `where("category_id" => value)` |
| `filter :status` on an enum column | `status`, with `enum:` filled from `defined_enums` | `{ kind: :eq, target: :status }` | `where("status" => value)` |
| `filter :name, match: :partial` | `name` | `{ kind: :match, target: :name }` | `arel_table[:name].matches("%value%", nil, false)` — case-insensitive, `ILIKE` on PostgreSQL and `LIKE` elsewhere, with the value passed through `sanitize_sql_like` |
| `filter :released_on, range: true` | `released_on_from`, `released_on_to` | `{ kind: :range_from, target: :released_on }` and `{ kind: :range_to, ... }` | `arel_table[:released_on].gteq(value)` / `.lteq(value)` |
| `filter :recently_released, scope: true, type: :boolean` | `recently_released` | `{ kind: :scope, target: :recently_released }` | `relation.recently_released` when the value is truthy, the relation untouched when it is false |

A `nil` value is skipped, so an omitted filter never narrows anything. `match:` triggers partial
matching only for the literal `:partial`; any other value falls through to `:eq`. `required: true`
is honoured only on the plain `:eq` form; range and scope arguments are always optional. Passing
`type:` explicitly turns inference off for that filter, so an enum's values then have to come
from an explicit `enum:` — omit `type:` to let `defined_enums` fill it in. The
`:list` definition additionally accepts `page`, `per_page` and `order` because its metadata
carries `paginated: true`, and `ExplicitSchema` advertises those three properties.

`order` is a bare attribute name, optionally prefixed with `-` for descending, and is ignored
unless the column is in the `order_whitelist`.

## Command tools

```ruby
class ProductReindex
  include Mcpable::Tool

  mcp_tool do
    name "product_reindex"
    description "Rebuilds the search index for one product."
    argument :product_id, :integer, required: true, description: "Product id."
    annotations read_only: false, destructive: true
    profiles :default, :admin
  end

  def call(product_id:)
    Product.find(product_id).reindex!
  end
end
```

`argument`'s type is positional, not a keyword: `argument :product_id, :integer, required: true`.

`name` defaults to the underscored class name, namespace included (`Search::Reindex` →
`search_reindex`). Only declared arguments are forwarded to `#call`, as keywords — pagination
keys and anything else are stripped — so the class needs a zero-argument `new` and a keyword
`#call`. A non-`Result` return value is wrapped in `Result.ok`. `annotations` starts empty here,
and `read_only?` defaults to `true`, so a write tool must say `annotations read_only: false`.
Declaring `metadata model:, action:, policy:` lets the Pundit middleware authorize a command
tool the same way it authorizes a resource; the action may be any name, since the middleware
just calls `#<action>?`.

### Reaching the caller from inside a tool

Before `#call` runs, the compiled handler assigns the `ToolCall` to the instance if it responds
to `mcp_call=` — which `Mcpable::Tool` provides. That gives every tool three readers:

| Reader | Returns |
| --- | --- |
| `current_user` | `ctx.assigns[:user]`, whatever your auth middleware put there |
| `current_scope` | `ctx.assigns[:scope]`, set by `Pundit::Authorize` on `:list` and `:show` only |
| `current_context` | the transport's context hash, or `{}` |

A write tool should scope its own lookups, because `Pundit::Authorize` does **not** resolve a
`Policy::Scope` for a non-read action — `current_scope` is `nil` inside an `action: :update`
tool. Resolve the scopes yourself:

```ruby
class MoveProductTool
  include Mcpable::Tool

  mcp_tool do
    name "move_product"
    description "Moves a product to another category inside the current user's store."
    argument :product_id, :integer, required: true, description: "Product id."
    argument :category_id, :integer, required: true, description: "Target category id."
    annotations read_only: false, destructive: false
    metadata model: Product, action: :update, policy: ProductPolicy
    profiles :default
  end

  def call(product_id:, category_id:)
    product = visible(Product, ProductPolicy).find_by(id: product_id)
    return Mcpable::Result.fail("product not found") if product.nil?

    category = visible(Category, CategoryPolicy).find_by(id: category_id)
    return Mcpable::Result.fail("category not found") if category.nil?

    product.update!(category: category)
    product.slice(:id, :store_id, :category_id, :name, :sku, :status)
  end

  private

  def visible(model, policy)
    policy::Scope.new(current_user, model.all).resolve
  end
end
```

`metadata action: :update` gets the admin-only `ProductPolicy#update?` check for free; the two
`Scope` resolutions are what stop an admin of one store from moving another store's product.

## Pipeline

```ruby
Mcpable.configure do |config|
  config.pipeline.use(MyApp::Mcp::AuthenticateUser)
  config.pipeline.use(Mcpable::Pundit::Authorize)
  config.pipeline.use(MyApp::Mcp::AuditLog)
end
```

The first `use` is the outermost middleware: the stack is folded from the inside out
(`middlewares.reverse.reduce(HANDLER)`), so `AuthenticateUser` wraps `Pundit::Authorize`, which
wraps `AuditLog`, which wraps the definition's handler. A middleware communicates only through
`ctx.assigns`. Any `StandardError` raised inside the pipeline goes through `error_mapper`, and
the pipeline always returns a `Result` — a handler or middleware that returns something else is
turned into `Result.fail("invalid result")`.

Execute a tool with `Mcpable.runtime.call_tool(name, args:, context:)`, which symbolizes keys,
rejects unknown arguments, rejects missing required ones, coerces each value to its declared
type (`Integer`, `Float`, `true/false/"true"/"1"/1/...`, `Date.iso8601`, `Time.iso8601`), then
runs the pipeline.

### Writing your own middleware

Subclass `Mcpable::Ports::Middleware`. It is constructed as `new(app, *args)` — the extra args
are whatever you passed to `pipeline.use` — and exposes the next link as `app`.

```ruby
class AuthenticateUser < Mcpable::Ports::Middleware
  def call(ctx)
    token = ctx.context[:api_token]
    user = token && User.find_by(api_token: token)
    return Mcpable::Result.deny("unauthenticated") if user.nil?

    ctx.assigns[:user] = user
    @app.call(ctx)
  end
end
```

Returning a `Result` without calling `@app` short-circuits the rest of the stack, including the
handler. Everything downstream reads what you wrote into `assigns`; `ctx.user` and `ctx.scope`
are just readers for `assigns[:user]` and `assigns[:scope]`.

A middleware can also run *after* the call by inspecting the returned `Result`:

```ruby
class AuditLog < Mcpable::Ports::Middleware
  def call(ctx)
    result = @app.call(ctx)
    Rails.logger.info(
      "[mcp] tool=#{ctx.definition.name} user=#{ctx.user&.id.inspect} status=#{result.status}"
    )
    result
  end
end
```

`ctx` gives a middleware `definition`, `args` (already coerced), `context`, `assigns`, `user`
and `scope`. Configuration arguments are passed positionally:

```ruby
config.pipeline.use(RateLimit, 100, per: :minute)  # RateLimit.new(app, 100, per: :minute)
```

## Pundit integration

`require "mcpable/pundit"` gives you `Mcpable::Pundit::Authorize`. It is duck-typed and does
not need the pundit gem. For each call it reads `metadata[:policy]`, `metadata[:model]` and
`metadata[:action]`; with no `:policy` it passes straight through. It then builds
`policy_class.new(ctx.user, model)` and denies with `Result.deny("not authorized")` unless
`#<action>?` is true.

For the read actions `:list` and `:show` — **both** of them — it resolves `Policy::Scope` and
writes the relation into `ctx.assigns[:scope]`, which the source then merges. Scoping `:show`
too is what stops `<plural>_show` from reading a record the caller may not see.

A policy whose class does not define its own `Scope` constant raises
`Mcpable::MissingScopeError` ("policy Foo has no Scope class") rather than silently listing
every tenant. Note the `const_defined?(:Scope, false)` lookup: inheriting a `Scope` from a base
policy does not count, so every policy needs its own.

```ruby
class ProductPolicy < ApplicationPolicy
  def list? = user.present?

  def show? = list?

  def update? = user.present? && user.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(store_id: user.store_id)
    end
  end
end
```

Because the scope is merged rather than replaced, a hostile `store_id` filter cannot widen it:
the caller's own scope and the filter are ANDed, and the result is empty.

## Sources

`Mcpable::ActiveRecord::Source` is installed automatically for AR models by
`require "mcpable/active_record"`. It maps filters as described in the table above, composes
visibility with `relation.merge(scope)`, counts before paginating, and restricts ordering to
the `order_whitelist:` given to its constructor.

`Mcpable::Sources::EnumerableSource` wraps any Enumerable or a callable returning one, and is
the right base for in-memory data. It intersects with `scope` (`records & scope.to_a`, and a
non-Enumerable scope raises) and implements `:eq`, `:match`, `:range_from` and `:range_to`;
`:scope`-kind filters are a no-op there, since there is no named scope to call, and its
ordering is unrestricted.

`order_whitelist` is only handed to the automatic source factory. If you declare `source`
yourself, pass the whitelist to your own constructor — the DSL's copy is never consulted.

### Implementing a custom source

Subclass `Mcpable::Ports::Source`. Its `initialize(base)` stores `base`, and you implement two
methods. `fetch` must return a `Mcpable::Ports::Source::Page`, a
`Data.define(:records, :total, :page, :per_page)`.

`filters` arrives as a Hash of `Argument => value`, with **every** declared filter argument
present and a `nil` value for the ones the caller omitted. Read the spec off the argument with
`#filter_kind` and `#filter_target`.

```ruby
class CatalogApiSource < Mcpable::Ports::Source
  def fetch(filters:, scope: nil, page: nil, per_page: nil, order: nil)
    page = [page.to_i, 1].max
    per_page = per_page.to_i.positive? ? per_page.to_i : 25

    query = query_params(filters).merge(page: page, per_page: per_page)
    query[:sort] = order if order
    query[:store_id] = scope.fetch(:store_id) if scope

    body = base.get("/products", query)

    Page.new(
      records: body.fetch("data"),
      total: body.fetch("meta").fetch("total"),
      page: page,
      per_page: per_page
    )
  end

  def find(id, scope: nil)
    record = base.get("/products/#{id}")
    return nil if record.nil?
    return nil if scope && record["store_id"] != scope.fetch(:store_id)

    record
  end

  private

  def query_params(filters)
    (filters || {}).each_with_object({}) do |(argument, value), out|
      next if value.nil?

      target = argument.filter_target || argument.name

      case argument.filter_kind
      when :eq then out[target] = value
      when :match then out[:"#{target}_contains"] = value
      when :range_from then out[:"#{target}_gte"] = value
      when :range_to then out[:"#{target}_lte"] = value
      when :scope then out[target] = true if value
      end
    end
  end
end
```

Two rules the core relies on:

- `scope` is composed, never widened. Whatever your auth middleware put in
  `ctx.assigns[:scope]` reaches the source as `scope:`; a source may narrow further but must
  never ignore it. A `nil` scope means "no extra constraint", which is only correct when the
  pipeline deliberately left it unset.
- `find` returns `nil` for a record outside the scope, not a raised error. The compiled `show`
  handler turns `nil` into `Result.fail("not found")`, so a foreign record and a missing one
  are indistinguishable to the caller.

Records may be anything the serializer can read — AR models, `Struct`s or plain hashes — since
`attributes` are read by `public_send` with an `[]` fallback.

Declare it with `source`, either as an instance or as a callable resolved per call:

```ruby
source CatalogApiSource.new(CatalogClient.new)
source -> { CatalogApiSource.new(CatalogClient.current) }
```

## Profiles

Every definition declares `profiles` (default `[:default]`), and a transport serves exactly one
profile. That is how one set of definitions becomes several tool sets:

```ruby
class Product
  include Mcpable::Resource

  mcpable do
    # ...
    profiles :default, :admin
  end
end

class PurgeStoreTool
  include Mcpable::Tool

  mcp_tool do
    name "purge_store"
    annotations read_only: false, destructive: true
    profiles :admin
  end
  # ...
end
```

```ruby
Mcpable::Transports::OfficialMcp.new(profile: :default).list_tools  # products_*
Mcpable::Transports::OfficialMcp.new(profile: :admin).list_tools    # products_* and purge_store
```

`Mcpable.registry.for_profile(:admin)` is the underlying selection. Over HTTP the profile comes
from `?profile=`; over stdio you choose it when constructing the transport.

## Serving

```ruby
require "mcpable/transports/official_mcp"

transport = Mcpable::Transports::OfficialMcp.new(profile: :default)
transport.list_tools
transport.handle(request_body, context: { api_token: "..." })
transport.serve_stdio(context: { api_token: ENV["MCP_API_TOKEN"] })
```

`OfficialMcp.new` also takes `registry:`, `runtime:`, `server_name:` (default `"mcpable"`) and
`server_version:` (default `Mcpable::VERSION`). `handle` returns a JSON String when given a
String and a Hash when given a Hash, and returns `nil` for a JSON-RPC notification such as
`notifications/initialized` — which is why the Rails controller answers those with `202` and an
empty body.

Both entry points take the same `context:` hash. Over HTTP a `context_builder` derives it from
the Rack env once per request; over stdio there is no request env, so the process supplies its
context once at startup and every tool call on that connection runs under it. One stdio process
therefore serves exactly one actor.

A stdio entry point must keep fd 1 pure: the JSON-RPC framing is the only thing allowed on
stdout, so application logging has to be moved to stderr *before* anything can write. Capture
the real stdout first, then redirect:

```ruby
#!/usr/bin/env ruby
require_relative "../config/boot"

protocol_stream = $stdout.dup
protocol_stream.sync = true
$stdout.reopen($stderr)

require_relative "../config/environment"

Rails.logger = ActiveSupport::Logger.new($stderr)
ActiveRecord::Base.logger = Rails.logger

$stdout = protocol_stream

Mcpable::Transports::OfficialMcp
  .new(profile: (ENV["MCPABLE_PROFILE"] || "default").to_sym)
  .serve_stdio(context: { api_token: ENV["MCPABLE_API_TOKEN"] })
```

Requiring `config/boot` before the redirection matters under Bundler, which may re-exec the
process and would otherwise inherit an already-swapped fd 1.

Built on the official [`mcp`](https://rubygems.org/gems/mcp) gem: tools are built with
`MCP::Tool.define`, requests go through `MCP::Server#handle_json` (String in, String out) or
`#handle` (Hash in, Hash out), and stdio uses `MCP::Server::Transports::StdioTransport`.
`Result.ok` becomes a text response carrying the JSON payload; `denied` and `error` become
`isError` responses whose text is `"#{status}: #{error}"`, e.g. `denied: not authorized`.

## Testing your tools

A definition is callable without any server. `Mcpable.runtime.call_tool` runs the full pipeline
and returns a `Result`, so assertions go straight on that. (The one exception is an unregistered
tool name, which raises `Mcpable::UnknownToolError` from outside the pipeline, so the
`error_mapper` never sees it.)

```ruby
result = Mcpable.runtime.call_tool(
  "products_list",
  args: { "category_id" => 3, "per_page" => 5 },
  context: { api_token: "acme-member-token" }
)

result.ok?                 # => true
result.payload[:total]     # => 2
result.payload[:records]   # => [{ id: 4, name: "Anchor Bolt Set", ... }, ...]
```

```ruby
denied = Mcpable.runtime.call_tool(
  "move_product",
  args: { product_id: 4, category_id: 2 },
  context: {}
)
denied.denied?             # => true
denied.error               # => "unauthenticated"
```

Argument validation happens before the pipeline, so `call_tool` is also where you assert on
rejected input, and no middleware runs for those:

```ruby
r = Mcpable.runtime
r.call_tool("products_list", args: { cost_cents: 1 }, context: {}).error
# => "unknown arguments: cost_cents"
r.call_tool("move_product", args: { product_id: 4 }, context: {}).error
# => "missing required arguments: category_id"
r.call_tool("products_list", args: { category_id: "abc" }, context: {}).error
# => "category_id is not an integer"
```

`Mcpable.reset!` replaces the registry, configuration and runtime with fresh ones, which is the
cleanest way to isolate a test that registers throwaway definitions. Compiling a definition by
hand is useful for negative tests:

```ruby
builder = Mcpable::Dsl::ResourceBuilder.new(Product)
builder.name "leak"
builder.attributes :id, :store_id, :name
builder.policy ScopelessProductPolicy
builder.actions :list
builder.profiles :leaky
builder.compile.each { |definition| Mcpable.registry.register(definition) }
```

### Isolating a test without touching globals

`Runtime` and `OfficialMcp` accept an injected `Registry` and `Configuration`, and both are
honoured all the way down — the `error_mapper` a pipeline reaches for and the `schema_strategy` a
transport builds schemas with come from the injected configuration, not from `Mcpable.config`.

```ruby
config = Mcpable::Configuration.new
config.error_mapper = ->(e) { Mcpable::Result.fail("boom: #{e.message}") }
config.pipeline.use(MyApp::Mcp::AuthenticateUser)

registry = Mcpable::Registry.new
registry.register(definition)

runtime = Mcpable::Runtime.new(registry: registry, config: config)
runtime.call_tool("products_list", args: {}, context: {})

transport = Mcpable::Transports::OfficialMcp.new(registry: registry, runtime: runtime)
transport.list_tools
```

A transport given no `config:` of its own adopts the one carried by its runtime, and falls back to
`Mcpable.config` only when neither was injected.

Note that the DSL always registers into the **global** registry: `include Mcpable::Resource` and
`mcp_tool` call `Mcpable.registry.register` at class-definition time. An injected registry
therefore holds only definitions you compile and register by hand, which is what the negative-test
example above does.

## Adapter require paths

`require "mcpable"` loads the core only. Adapters are opt-in:

```ruby
require "mcpable/transports/official_mcp"  # needs the mcp gem
require "mcpable/active_record"            # needs ActiveRecord
require "mcpable/pundit"                   # duck-typed, does not need the pundit gem
require "mcpable/rails"                    # needs Rails; also loads the official mcp transport
```

`mcpable/rails` mounts `POST /mcp`, and on every `to_prepare` it resets the registry and
re-registers the definitions in `config.mcpable.eager_load_paths` (default
`%w[app/models app/tools]`) through the application's Zeitwerk loaders, so code reloading
neither drops tools nor raises `DuplicateToolError`. It skips registration while the database
schema is not yet loaded — logging a warning instead — so `db:create` and `db:migrate` still
work on a fresh checkout even though the DSL reads `columns_hash` at class-definition time.

## Not supported yet

Stated plainly, so you do not go looking:

- Tools only. There is no `resources/`, `prompts/`, sampling, progress or cancellation support.
- Resource actions are `:list` and `:show`. Writes are command tools you author yourself;
  declaring `actions :update` (or any other write action) raises an `ArgumentError` at compile
  time rather than registering nothing.
- Offset pagination only (`page` / `per_page`); no cursors, no `has_more`, no upper clamp on
  `per_page`.
- `attributes` is one static list per definition. There is no per-role attribute masking — keep
  a secret out of the whitelist entirely, and expose it from a serializer elsewhere if some
  roles may see it.
- Filters address columns on the model's own table, and the five kinds in the table above are
  all of them. There is no join, association, `IN`, negation, OR or free-form-search filter.
- `enum:` reaches the JSON Schema only; the runtime does not check membership itself.
- Resource tool names are always `<plural>_list` / `<plural>_show`; only the singular base is
  configurable.
- No output schemas or structured content: a payload is serialized to one JSON text block, and
  the only annotations are `readOnlyHint`, `destructiveHint` and `openWorldHint`.
- No streaming or SSE; the Rails engine appends `POST /mcp` only, at a path that is not
  configurable, with no session handling.
- One global pipeline for every tool — no per-tool stacks, and `Pipeline` offers only `use` and
  `clear`.
- No built-in authentication, rate limiting, instrumentation or per-tool timeouts — those are
  middlewares you write.
- Nothing is async, and nothing guarantees thread safety; the registry is a plain Hash.
- No test matchers or fixtures ship with the gem.

## The sample application

A complete working example lives in the `mcpable-demo` repository: a multi-tenant Rails 8.1 app
on SQLite, containerized, with two stores sharing one database. It demonstrates the whole
surface described above — `mcpable` blocks on `Store`, `Category` and `Product`, a Pundit policy
with its own `Scope` per model, a `move_product` command tool, both middlewares, the HTTP
endpoint and the stdio entry point, and a checked-in `.mcp.json` that registers the server with
Claude Code. Its test suite asserts tenancy isolation, every filter kind, pagination, ordering,
command-tool authorization and `MissingScopeError` handling over real JSON-RPC requests, and
`bin/mcp_demo` prints the same walkthrough in readable form.

## Status

v0.1. Core, DSL, pipeline, `EnumerableSource`, `ExplicitSchema`, the Pundit middleware, the
Rails loader and the `mcp` transport are covered by this repository's specs.

`mcpable/rails` and `mcpable/active_record` cannot be unit-tested here — there is no Rails or
ActiveRecord in the development bundle — but they are exercised end to end by the
`mcpable-demo` application in the sibling directory, which has proven the Rails engine and its
appended route, the ActiveRecord source against a real database, and both transports, under
both code reloading and eager loading.

Splitting the adapters into separate gems is a later step; for now everything ships from one
gemspec whose only runtime dependency is `mcp`.

## License

MIT.
