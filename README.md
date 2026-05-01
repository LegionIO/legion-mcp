# legion-mcp

Model Context Protocol (MCP) server for the LegionIO framework. Provides semantic tool matching, observation pipeline, context compilation, tiered behavioral intelligence (Tier 0/1/2 routing), tool governance, deferred tool loading, and MCP client pooling for remote server federation.

**Version**: 0.9.1
**License**: Apache-2.0
**Ruby**: >= 3.4

Extracted from [LegionIO](https://github.com/LegionIO/LegionIO) for independent versioning and reuse.

## Installation

```ruby
gem 'legion-mcp'
```

Or in a Gemfile:

```ruby
gem 'legion-mcp', '~> 0.9'
```

## Architecture

```
Legion::MCP
├── Server              # MCP::Server builder, governance-aware build; tool list sourced via DeferredRegistry
├── Auth                # JWT + API key authentication
├── Utils               # Pure-function summarization and formatting helpers
├── ToolGovernance      # Risk-tier tool filtering + invocation audit
├── ToolAdapter         # Adapts Legion::Tools::Base to MCP SDK format; handles :mcp_remote dispatch
├── DeferredRegistry    # Reads deferred/always-loaded tools from Settings::Extensions at request time
├── ContextCompiler     # Keyword + semantic tool matching (60/40 blend), 17 categories
├── EmbeddingIndex      # In-memory vector cache for semantic matching
├── Observer            # Instrumentation: counters, ring buffer, intent tracking, pattern promotion
├── UsageFilter         # Frequency/recency/keyword scoring for dynamic tool filtering
├── DynamicInjector     # Context-aware tool injection/removal with tools/list_changed notification
├── CatalogDispatcher   # Dispatch layer routing MCP calls through Legion::Ingress
├── Patterns::Store     # 3-layer degrading storage (L0 memory -> L1 cache -> L2 SQLite)
├── Patterns::Schema    # Portable pattern format with trust-level confidence capping
├── Patterns::Exchange  # Bulk import/export of patterns via JSON files
├── Patterns::Gossip    # AMQP-based pattern sharing between instances
├── Patterns::Compiler  # Compressed tool definitions and compiled workflows
├── TierRouter          # Confidence-gated tier selection (0/1/2)
├── ContextGuard        # Staleness, rapid-fire, anomaly detection guards
├── StateTracker        # In-memory state snapshots with delta diff computation
├── StructuralIndex     # Precomputed index of extensions, runners, actors, and tools
├── ToolQuality         # Docstring quality audit, category resolution, capability matrix
├── GapDetector         # Unmatched intents, high-failure tools, stale candidate detection
├── SelfGenerate        # Gap detection + publication cycles with cooldown
├── OverrideBroadcast   # Mesh-wide override confirmation via RabbitMQ
├── TracingContext       # Thread-local conversation/request/exchange/trace ID propagation
├── Client::Pool        # Remote MCP server connections; registers tools into Settings::Extensions
├── Client::Connection  # stdio and HTTP transport connections with TTL-cached tool lists
├── Client::ServerRegistry # Static and dynamic server registration with health tracking
├── Tools/              # 10 MCP-specific + 18 legion-data CRUD tools; extension tools via Settings::Extensions
└── Resources/          # RunnerCatalog, ExtensionInfo
```

### Tool Registry

- **MCP_SPECIFIC_TOOLS** (10 tools): `do_action`, `discover_tools`, `plan_action`, `structural_index`, `tool_audit`, `state_diff`, `search_sessions`, `skill_list`, `skill_describe`, `skill_invoke`, `skill_cancel`
- **legion-data CRUD** (18 tools): `run_task`, `describe_runner`, list/get/delete tasks, `get_task_logs`, CRUD chains/relationships/schedules
- **Extension tools**: Auto-discovered via `Legion::Settings::Extensions` at runtime; not shipped as static files
- **Remote MCP tools**: Fetched from remote servers via `Client::Pool.all_tools`, registered into `Settings::Extensions` with `dispatch_type: :mcp_remote`

## Tiered Behavioral Intelligence

Requests flow through three tiers, each with increasing latency and capability:

| Tier | Confidence | What happens | Latency |
|------|-----------|--------------|---------|
| 0 | >= 0.8 | Cached pattern match, no LLM | < 5ms |
| 1 | 0.6 - 0.8 | Local/fleet model hint | ~100ms |
| 2 | < 0.6 | Full cloud LLM | ~1-3s |

### Pattern Lifecycle

1. **Observer** records intent+tool pairs from MCP tool invocations
2. After 3 successful observations, promotes candidate to **PatternStore** (seeded confidence 0.5)
3. Successful executions increase confidence (+0.02), failures decrease it (-0.05)
4. Once confidence reaches 0.8, **TierRouter** serves the pattern at Tier 0

### Context Guards

Before serving a Tier 0 response, **ContextGuard** checks:

- **Staleness**: Pattern not hit in > 1 hour
- **Rapid-fire**: > 5 requests in 10 minutes (possible loop)
- **Anomaly**: 2+ consecutive misses (pattern may be stale)

If any guard triggers, the request escalates to Tier 1.

### Storage Layers

PatternStore degrades gracefully across 3 layers:

| Layer | Backend | Requirement |
|-------|---------|-------------|
| L0 | In-memory hash | Always available |
| L1 | Legion::Cache (memcached/redis) | `defined?(Legion::Cache)` |
| L2 | Legion::Data::Local (SQLite) | `defined?(Legion::Data::Local)` |

All persistence wraps in `begin/rescue => nil` -- failed writes never block Tier 0.

## Tools

28 built-in MCP tools in the `legion.*` namespace (10 MCP-specific + 18 legion-data CRUD). Extension-owned tools are auto-discovered at runtime via `Legion::Settings::Extensions`.

| Tool | Purpose |
|------|---------|
| `legion.do` | Natural language intent routing (Tier 0 fast path) |
| `legion.tools` | Dynamic tool discovery by category, intent, or schema resolution |
| `legion.plan` | Multi-step workflow planning with LLM narrative |
| `legion.structural_index` | Precomputed structural index of extensions/runners/actors/tools |
| `legion.tool_audit` | Quality audit of registered tools (summary/matrix/issues) |
| `legion.state_diff` | Delta state polling since a given timestamp |
| `legion.search_sessions` | Search past conversation sessions by keyword |
| `legion.skill.list` | List all registered LLM skills |
| `legion.skill.describe` | Describe a specific skill |
| `legion.skill.invoke` | Invoke a skill for a conversation |
| `legion.skill.cancel` | Cancel an active skill run |
| `legion.run_task` | Execute a runner function via dot notation |
| `legion.describe_runner` | Runner/function discovery |
| `legion.list_tasks` / `get_task` / `delete_task` / `get_task_logs` | Task CRUD + logs |
| `legion.list_chains` / `create_chain` / `update_chain` / `delete_chain` | Chain management |
| `legion.list_relationships` / `create_*` / `update_*` / `delete_*` | Relationship CRUD |
| `legion.list_schedules` / `create_*` / `update_*` / `delete_*` | Schedule CRUD |

## Resources

| URI | Description |
|-----|-------------|
| `legion://runners` | All registered extension.runner.function paths |
| `legion://extensions/{name}` | Extension detail template |

## MCP Client (Federation)

Connect to remote MCP servers via stdio or HTTP transport:

```ruby
# Via settings (loaded at boot)
# settings/mcp.json:
# { "mcp": { "servers": { "code_server": { "transport": "stdio", "command": "npx @example/mcp-server" } } } }

Legion::MCP::Client.boot

# Or register at runtime
Legion::MCP::Client.register(:my_server, transport: :http, url: 'http://localhost:9393/mcp')

# All remote tools are registered into Settings::Extensions with dispatch_type: :mcp_remote
tools = Legion::MCP::Client::Pool.all_tools
```

## Usage

### Standalone MCP server

```ruby
require 'legion/mcp'

server = Legion::MCP.server
server.start
```

### Within LegionIO

```bash
# stdio transport (default)
legionio mcp stdio

# HTTP transport
legionio mcp http --port 9393
```

### Tier 0 direct usage

```ruby
result = Legion::MCP::TierRouter.route(
  intent: "list all running tasks",
  params: { status: "running" },
  context: {}
)

case result[:tier]
when 0 then puts "Cached: #{result[:response]}"
when 1 then puts "Escalate to local model"
when 2 then puts "Escalate to cloud LLM"
end
```

### Identity-scoped server

```ruby
server = Legion::MCP.server_for(token: jwt_token)
# Returns governance-filtered tool set based on JWT claims
```

## Configuration

All configuration is optional and read via `Legion::Settings` when available:

```json
{
  "mcp": {
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
    "auto_expose_runners": false,
    "servers": {},
    "cold_start": {
      "patterns_path": null
    },
    "roles": {}
  }
}
```

## Dependencies

| Gem | Required | Purpose |
|-----|----------|---------|
| `mcp` (~> 0.8) | Yes | MCP server SDK |
| `legion-data` (>= 1.4) | Yes | Sequel models, migrations |
| `legion-json` (>= 1.2) | Yes | JSON serialization |
| `legion-logging` (>= 1.4.3) | Yes | Structured logging via Helper |
| `legion-settings` (>= 1.4.0) | Yes | Configuration + Settings::Extensions |
| `legion-cache` | Optional | L1 pattern cache (memcached/redis) |
| `legion-llm` | Optional | Embeddings for semantic matching, Tier 1/2 LLM |

## Guard Strategy

All optional dependencies use `defined?()` guards:
- `defined?(Legion::Cache)` for L1 cache operations
- `defined?(Legion::Data::Local)` for L2 SQLite persistence
- `defined?(Legion::LLM)` for embedding generation and tiered LLM routing
- `defined?(Legion::Settings::Extensions)` for central tool registry
- `defined?(Legion::MCP::EmbeddingIndex)` for semantic matching
- `defined?(Legion::MCP::TierRouter)` for Tier 0 routing

Every storage write wraps in `begin/rescue => nil` -- failed persistence never blocks Tier 0.

## Key Conventions

- `Legion::JSON.load` returns **symbol keys** -- use `body[:data]`, not `body['data']`
- `Legion::JSON.dump` takes exactly 1 positional arg -- wrap kwargs in explicit `{}`
- `::Process` and `::JSON` must be explicit inside the `Legion::` namespace
- `Legion::MCP.server` is a memoized singleton -- call `Legion::MCP.reset!` in tests
- MCP tool naming: `legion.snake_case_name` (dot namespace)
- Every rescue block calls `handle_exception(e, level:, handled:, operation:)`
- Logging via `extend Legion::Logging::Helper` (modules) or `include Legion::Logging::Helper` (classes/class << self)

## Development

```bash
bundle install
bundle exec rspec       # 0 failures
bundle exec rubocop -A  # auto-fix
bundle exec rubocop     # lint check
```

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion/mcp.rb` | Entry point: `Legion::MCP.server` singleton factory |
| `lib/legion/mcp/version.rb` | `Legion::MCP::VERSION` constant |
| `lib/legion/mcp/utils.rb` | Pure-function summarization and formatting helpers |
| `lib/legion/mcp/server.rb` | MCP::Server builder, governance-aware build; reads tools from Settings::Extensions |
| `lib/legion/mcp/auth.rb` | JWT + API key authentication |
| `lib/legion/mcp/patterns.rb` | Barrel file for 13 Tier 0 pattern routing modules |
| `lib/legion/mcp/discovery.rb` | Barrel file for 12 tool discovery and adaptation modules |
| `lib/legion/mcp/tool_adapter.rb` | MCP::ToolAdapter -- wraps tools for MCP SDK; handles :mcp_remote dispatch |
| `lib/legion/mcp/deferred_registry.rb` | Deferred/always-loaded tool list management |
| `lib/legion/mcp/catalog_dispatcher.rb` | Dispatch layer routing through Legion::Ingress |
| `lib/legion/mcp/dynamic_injector.rb` | Context-aware tool injection/removal |
| `lib/legion/mcp/client.rb` | Client boot/shutdown, server registration |
| `lib/legion/mcp/client/pool.rb` | Connection pool; all_tools registers into Settings::Extensions |
| `lib/legion/mcp/client/connection.rb` | stdio/HTTP transport connections |
| `lib/legion/mcp/client/server_registry.rb` | Server health tracking and registration |
| `lib/legion/mcp/tools/do_action.rb` | Natural language intent routing with Tier 0 fast path |
| `lib/legion/mcp/tools/discover_tools.rb` | Dynamic tool discovery with context |
| `lib/legion/mcp/tools/run_task.rb` | Execute runner function via dot notation |
| `lib/legion/mcp/tools/plan_action.rb` | Agentic planning with action decomposition |
| `lib/legion/mcp/tools/skills.rb` | Skill list/describe/invoke/cancel tools |
| `lib/legion/mcp/tools/structural_index.rb` | Query precomputed structural index |
| `lib/legion/mcp/tools/tool_audit.rb` | Audit registered tools quality |
| `lib/legion/mcp/tools/state_diff.rb` | Changed system state since timestamp |
| `lib/legion/mcp/tools/search_sessions.rb` | Search past conversation sessions |
| `lib/legion/mcp/resources/runner_catalog.rb` | `legion://runners` resource |
| `lib/legion/mcp/resources/extension_info.rb` | `legion://extensions/{name}` resource template |

## License

Apache-2.0
