# legion-mcp

`legion-mcp` is the LegionIO Model Context Protocol (MCP) server and client library. It adapts the Legion tool registry to the MCP SDK, exposes Legion-owned discovery and inspection tools, applies role/risk policy, records tool observations, and includes remote-server registration and federation client APIs.

This gem is a **core Legion library**, not a LEX extension. It does not provide a general-purpose LLM host, an HTTP deployment platform, or a complete authentication/authorization deployment by itself.

- **Source version:** 0.9.3
- **Ruby:** >= 3.4
- **License:** Apache-2.0
- **Source:** [LegionIO/legion-mcp](https://github.com/LegionIO/legion-mcp)

## Installation

Add the gem to the application bundle:

```ruby
gem 'legion-mcp', '~> 0.9', '>= 0.9.3'
```

Then install:

```bash
bundle install
```

The gemspec requires the MCP Ruby SDK `>= 1.9, < 2`, Ruby 3.4 or newer, and the Legion dependencies listed in [Dependencies](#dependencies). The SDK range includes the OAuth-discovery SSRF fix described in [GHSA-4m5j-jjfc-97gx](https://github.com/modelcontextprotocol/ruby-sdk/security/advisories/GHSA-4m5j-jjfc-97gx).

## Starting a server

### Standalone stdio

Save the following as `mcp_stdio.rb`. Configure file logging **before** loading MCP so log output cannot corrupt the JSON-RPC stream:

```ruby
# mcp_stdio.rb
require 'legion/logging'

Legion::Logging.setup(
  log_file: File.expand_path('~/.legionio/logs/mcp.log'),
  log_stdout: false
)

require 'legion/mcp'
require 'mcp/server/transports/stdio_transport'

transport = ::MCP::Server::Transports::StdioTransport.new(Legion::MCP.server)
transport.open
```

Launch it with `bundle exec ruby mcp_stdio.rb`. The explicit file destination matters: `log_stdout: false` without a file destination can still leave logging on stdout. Reserve stdout for MCP JSON-RPC.

### LegionIO CLI

When running inside LegionIO, use the framework command:

```bash
legionio serve mcp stdio
legionio serve mcp http --host 127.0.0.1 --port 9393
```

`stdio` is the default subcommand. HTTP uses the MCP SDK streamable-HTTP transport and Puma through the LegionIO CLI. The current CLI checks a bearer token when `mcp.auth.enabled` is true, but uses the shared `Legion::MCP.server`; that token check does not automatically bind JWT claims to an identity-scoped server. Hosts that require per-identity policy must authenticate the request and select a trusted identity-scoped server explicitly.

## What is registered by default

`Legion::MCP::Server::MCP_SPECIFIC_TOOLS` is the authoritative built-in MCP registry. It contains these ten tools:

| Tool | Purpose |
| --- | --- |
| `legion.plan` | Rank matching tools into an ordered plan; an optional narrative is generated only when a Legion LLM integration is available. |
| `legion.tools` | Discover tools by category or intent, or resolve full schemas by name. |
| `legion.structural_index` | Query the precomputed extension, runner, actor, and tool index. |
| `legion.tool_audit` | Audit registered tool metadata and quality. |
| `legion.state_diff` | Read state changes since a supplied point in time. |
| `legion.search_sessions` | Search available conversation sessions. |
| `legion.skill.list` | List registered skills. |
| `legion.skill.describe` | Describe a skill. |
| `legion.skill.invoke` | Invoke a skill for a conversation. |
| `legion.skill.cancel` | Cancel an active skill run. |

`lib/legion/mcp/tools_loader.rb` requires additional tool classes, including `legion.run_task` and Legion Data CRUD classes, so those constants are available to the Ruby process. Loading a class does **not** make it a default MCP catalog entry. Extension-owned and runner-derived tools are added only when the Legion settings/extension registry and exposure rules provide them; data-backed tools also require their corresponding runtime services.

Remote tools are separate registry entries created by the federation client with `dispatch_type: :mcp_remote`. They are not part of the ten-tool built-in registry.

Every MCP tool descriptor has an `inputSchema`. Deferred descriptors may omit optional metadata, but they do not omit the schema or required arguments.

## Tool dispatch and resources

The server builds MCP tools from three sources:

1. the ten MCP-specific classes above;
2. entries in `Legion::Settings::Extensions`, adapted by `Legion::MCP::ToolAdapter`; and
3. runner functions discovered and exposed by Legion's function-discovery path.

Dispatch depends on the registry entry. A loaded tool class may be called directly, a catalog-generated runner tool uses `Legion::Ingress` when that integration is available, and an MCP-remote entry calls its federation connection. Do not assume every MCP call follows the catalog/Ingress path.

The server also registers:

- `legion://runners`, an application runner catalog; and
- `legion://extensions/{name}`, an extension information resource template.

The catalog uses the settings extension registry when populated, otherwise it requires the relevant Legion Data connection.

## Deferred schemas and discovery

Deferred loading is enabled by default. The `tools/list` handler returns full definitions for always-loaded tools and a reduced descriptor for deferred tools. The reduced descriptor still includes the name, description, and actual `inputSchema`.

To request complete definitions for selected tools, call `legion.tools` with `tool_names` and `schema: true`:

```json
{
  "tool_names": ["legion.skill.describe"],
  "schema": true
}
```

Schema resolution is evaluated against the identity-scoped, governed tool registry. A tool that is not registered or not permitted for that identity is not returned.

## Configuration and settings registration

Loading `legion/mcp` registers two separate settings payloads:

- `Legion::MCP::Settings.default` is the **flat contents of the `:mcp` namespace**.
- `Legion::MCP::Settings.codegen` is merged separately under `:codegen`.

The entrypoint calls:

```ruby
Legion::Settings.merge_settings(:mcp, Legion::MCP::Settings.default)
Legion::Settings.merge_settings(:codegen, Legion::MCP::Settings.codegen)
```

Application configuration is normally supplied through the Legion settings loader. The following shows the principal MCP keys and their defaults; it is a configuration shape, not a requirement to enable every feature:

```json
{
  "mcp": {
    "servers": {},
    "overrides": {},
    "tool_cache_ttl": 300,
    "connect_timeout": 10,
    "call_timeout": 30,
    "auto_expose_runners": false,
    "auth": {
      "enabled": false,
      "require_auth": false,
      "jwt_secret": null,
      "jwt_algorithm": "HS256",
      "jwt_issuer": "legion",
      "allowed_api_keys": []
    },
    "governance": {
      "enabled": false,
      "audit_invocations": true,
      "tool_risk_tiers": {}
    },
    "roles": {},
    "deferred_loading": {
      "enabled": true,
      "always_loaded": []
    },
    "dynamic_tools": {
      "enabled": false,
      "max_injected": 10
    },
    "tier0": {
      "guards": {
        "max_stale_seconds": 3600,
        "rapid_fire_threshold": 5,
        "rapid_fire_window_seconds": 600
      }
    },
    "cold_start": {
      "patterns_path": null
    }
  },
  "codegen": {
    "self_generate": {
      "enabled": false,
      "cycle_interval": 300,
      "cooldown_seconds": 300,
      "max_gaps_per_cycle": 5
    }
  }
}
```

For a standalone host, configure logging first, then load the saved JSON before
requiring MCP:

```ruby
require 'legion/settings'
Legion::Settings.load(config_file: File.expand_path('settings/mcp.json'))
require 'legion/mcp'
Legion::Settings.validate!
```

The full self-generation payload also contains tiering, validation, approval, hot-registration, corroboration, runner/extension output, and GitHub settings in `Legion::MCP::Settings.codegen`. Self-generation is disabled by default. Enabling it publishes detected gaps to the Legion transport when that integration is present; it does not itself generate, validate, bundle, or merge code synchronously in an MCP request.

The global `tool_cache_ttl`, `connect_timeout`, and `call_timeout` keys are declared defaults, but the current federation wrapper does not read them. `Client::Connection` currently uses its fixed 300-second tool-cache constant; do not rely on those global keys to change transport behavior.

## Authentication and governance boundaries

Authentication and trusted identity are separate concerns:

- Authentication is disabled by default. `Legion::MCP.server` builds an unscoped server with `identity: nil`; `server_for` falls back to the anonymous low-risk identity when token authentication is inactive.
- `server_for(token: ...)` authenticates when `auth.enabled` is true, or when `auth.require_auth` is true and a token was supplied. `require_auth` alone does not reject a missing token; the host must enforce its authentication boundary.
- `Legion::MCP.server_for(identity: ...)` accepts an identity supplied by a trusted host. Do not treat a caller-provided identity as proof of authentication.
- JWT claims provide `sub`, optional `risk_tier`, `tenant_id`, and `worker_id`; role authorization must be supplied by the host/application identity path.
- Risk-tier filtering is disabled by default. A supplied role is filtered independently of that switch. Both policies are checked again immediately before each SDK tool call.
- Missing or unknown roles are permissive unless a role is explicitly configured with `false` or with an empty tool allowlist. Set explicit roles and risk tiers when a restrictive policy is required.

For example, an identity-scoped server can be built after an upstream authenticator has established the identity:

```ruby
require 'legion/mcp'

Legion::Settings.loader.settings[:mcp][:roles][:operator] = { tools: ['legion.tools'] }
server = Legion::MCP.server_for(
  identity: {
    user_id: 'example-operator',
    role: 'operator',
    risk_tier: :low
  }
)
```

The gem provides tool-level filtering and optional audit events. Deployment-level TLS, proxy policy, token delivery, network isolation, and the trustworthiness of an externally supplied identity remain application responsibilities.

Revocation and regrant apply to tools already registered on a retained server. Rebuild the server when its available tool set changes. Direct Ruby APIs such as `TierRouter.route` execute outside the SDK `tools/call` wrapper and are not an authorization boundary for untrusted requests.

## Federation with remote MCP servers

The client supports configured `stdio`, `http`, and `streamable_http` server entries. This example documents the expected configuration shape only; it does not claim that the named remote endpoint exists or that connectivity has been verified:

```json
{
  "mcp": {
    "servers": {
      "local_server": {
        "transport": "stdio",
        "command": ["bundle", "exec", "ruby", "mcp_stdio.rb"]
      },
      "remote_server": {
        "transport": "http",
        "url": "http://127.0.0.1:9393/mcp"
      }
    }
  }
}
```

The registry APIs are available for application integration:

```ruby
require 'legion/mcp'

Legion::MCP::Client.boot # loads mcp.servers into the server registry
Legion::MCP::Client.register(
  :another_server,
  transport: :http,
  url: ENV.fetch('MCP_REMOTE_URL')
)

# Remove configured/dynamic servers and close any created connections.
Legion::MCP::Client.shutdown
```

`Pool.all_tools` is intended to fetch healthy-server catalogs and register
remote entries as `:mcp_remote`. In the 0.9.3 wrapper, do not treat it as a
working connectivity probe: the current pool/connection path can recursively
lock while creating a connection, and the connection path does not perform the
MCP SDK `connect` handshake before its first request. These are known
federation limitations of this release, so test the selected MCP SDK transport
and remote service in the target deployment before relying on federation.

## Tiered routing and learned patterns

`Legion::MCP::TierRouter.route` is a local confidence gate over stored tool chains. It is not an automatic local/cloud LLM router:

- **Tier 0** (`confidence >= 0.8`): after context guards pass, execute the cached tool chain locally and return its response.
- **Tier 1** (`0.6 <= confidence < 0.8`, or a guard fails): return pattern metadata with `response: nil` and a reason for escalation.
- **Tier 2** (no matching pattern or `confidence < 0.6`): return `response: nil` with a reason.

The method returns a hash. Only a Tier 0 execution includes a generated response and measured `latency_ms`; Tier 1 and Tier 2 do not invoke an LLM automatically:

```ruby
require 'legion/mcp'
require 'legion/mcp/tier_router'

result = Legion::MCP::TierRouter.route(
  intent: 'list running tasks',
  params: { status: 'running' },
  context: {}
)

case result[:tier]
when 0
  puts result[:response]
when 1, 2
  puts "Escalation required: #{result[:reason]}"
end
```

Learning is observation-driven rather than a claim that every tool call becomes a pattern:

1. Successful intent/tool observations are accumulated; `legion.do` handles promotion with knowledge of its resolved tool.
2. A candidate is promoted after three observations for the candidate key and starts at confidence `0.5`.
3. Successful Tier 0 hits add `0.02`; misses subtract `0.05`, bounded to `0.0..1.0`.
4. Exact and, when an embedding index is populated, semantic lookups can find stored patterns.
5. Context guards cover staleness, rapid-fire requests, and consecutive misses before Tier 0 execution.

Patterns are held in memory first. When connected, Legion Cache and Legion Data Local provide optional persistence layers. Persistence failures are logged and handled so the in-memory path can continue; they are not silent successes. `mcp.cold_start.patterns_path` can import community patterns when the in-memory store is empty.

## Dependencies

Required runtime dependencies from the gemspec:

| Gem | Minimum/range | Role |
| --- | --- | --- |
| `mcp` | `>= 1.9, < 2` | MCP server/client SDK and transports |
| `base64` | `>= 0.2` | SDK OAuth client support on Ruby 3.4+ |
| `concurrent-ruby` | `>= 1.2` | Concurrent registries and synchronization |
| `legion-data` | `>= 1.4.19` | Legion data models and optional local persistence integration |
| `legion-json` | `>= 1.2.0` | Legion JSON serialization |
| `legion-logging` | `>= 1.4.3` | Structured logging and exception handling |
| `legion-settings` | `>= 1.4.5` | Settings and the central extension/tool registry |

`legion-cache`, Legion LLM integrations, Legion Crypt, Legion Transport, and the LegionIO runtime are optional integrations. Their presence enables additional behavior; they are not dependencies declared by this gemspec. The `Legion::Settings::Extensions` registry API itself comes from the required `legion-settings` dependency.

## Development

From this repository:

```bash
bundle install
bundle exec rspec --format json --out tmp/rspec_results.json --format progress --out tmp/rspec_progress.txt
bundle exec rubocop -A
bundle exec rubocop
```

Useful source entry points:

- [`lib/legion/mcp.rb`](lib/legion/mcp.rb) — requires MCP and registers the `:mcp` and `:codegen` settings payloads.
- [`lib/legion/mcp/settings.rb`](lib/legion/mcp/settings.rb) — default settings and self-generation settings.
- [`lib/legion/mcp/server.rb`](lib/legion/mcp/server.rb) — server construction, registry, resources, and per-call governance checks.
- [`lib/legion/mcp/tool_adapter.rb`](lib/legion/mcp/tool_adapter.rb) — registry-entry adaptation and dispatch selection.
- [`lib/legion/mcp/deferred_registry.rb`](lib/legion/mcp/deferred_registry.rb) — deferred descriptors and schema resolution.
- [`lib/legion/mcp/client/`](lib/legion/mcp/client/) — federation registry, pool, and connections.
- [`lib/legion/mcp/tier_router.rb`](lib/legion/mcp/tier_router.rb) and [`lib/legion/mcp/patterns/`](lib/legion/mcp/patterns/) — routing and pattern storage.
- [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) — protocol and transport implementation.
- [LegionIO](https://github.com/LegionIO/LegionIO) — framework CLI and runtime integration.

## License

Apache-2.0
