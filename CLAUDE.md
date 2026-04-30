# legion-mcp: MCP Server for LegionIO

**Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Standalone gem providing the Model Context Protocol (MCP) server for LegionIO. Extracted from LegionIO to enable independent versioning and reuse. Includes semantic tool matching, observation pipeline, context compilation, tiered inference (Tier 0/1/2), and tool governance.

**GitHub**: https://github.com/LegionIO/legion-mcp
**Version**: 0.9.0
**License**: Apache-2.0
**Ruby**: >= 3.4

## Architecture

```
Legion::MCP
├── Server              # MCP::Server builder, governance-aware build; tool list sourced from Legion::Settings::Extensions via DeferredRegistry
├── Auth                # JWT + API key authentication
├── Utils               # Pure-function summarization and formatting helpers (extracted from LoggingSupport)
├── ToolGovernance      # Risk-tier tool filtering + invocation audit
├── ToolAdapter         # Adapts Legion::Tools::Base to MCP SDK format; handles :mcp_remote dispatch
├── DeferredRegistry    # Reads deferred/always-loaded tools from Legion::Settings::Extensions at request time
├── Client::Pool        # Remote MCP server connections; registers tools into Settings::Extensions
├── Client::Connection  # stdio and HTTP transport connections with TTL-cached tool lists
├── Client::ServerRegistry # Static and dynamic server registration with health tracking
├── patterns.rb         # Barrel: PatternStore, TierRouter, ContextGuard, Observer, etc. (13 modules)
├── discovery.rb        # Barrel: FunctionDiscovery, ToolAdapter, ToolGovernance, etc. (12 modules)
├── Tools/              # MCP_SPECIFIC_TOOLS (10) + legion-data CRUD tools (18); extension tools via Settings::Extensions
└── Resources/          # RunnerCatalog, ExtensionInfo
```

### Tool Registry

- **MCP_SPECIFIC_TOOLS** (10 tools): do_action, discover_tools, plan_action, structural_index, tool_audit, state_diff, search_sessions, skill_list, skill_describe, skill_invoke, skill_cancel
- **legion-data CRUD** (18 tools): run_task, describe_runner, list/get/delete tasks, get_task_logs, CRUD chains/relationships/schedules
- **Extension tools**: Auto-discovered via `Legion::Settings::Extensions` at runtime; not shipped as static files
- **Remote MCP tools**: Fetched from remote servers via `Client::Pool.all_tools`, registered into `Settings::Extensions` with `dispatch_type: :mcp_remote`

## Dependencies

| Gem | Required | Purpose |
|-----|----------|---------|
| `mcp` (~> 0.8) | Yes | MCP server SDK |
| `legion-data` (>= 1.4) | Yes | Sequel models, migrations |
| `legion-json` (>= 1.2) | Yes | JSON serialization |
| `legion-logging` (>= 1.4.3) | Yes | Logging via Helper |
| `legion-settings` (>= 1.4.0) | Yes | Configuration + Settings::Extensions |
| `legion-cache` | Optional | L1 pattern cache (memcached/redis) |
| `legion-llm` | Optional | Embeddings for semantic matching |
| `legionio` | Dev only | Full framework for integration testing |

## Guard Strategy

All optional dependencies use `defined?()` guards:
- `defined?(Legion::Cache)` for L1 cache operations
- `defined?(Legion::Data::Local)` for L2 SQLite persistence
- `defined?(Legion::LLM)` for embedding generation
- `defined?(Legion::Settings::Extensions)` for central tool registry
- `defined?(Legion::MCP::EmbeddingIndex)` for semantic matching
- `defined?(Legion::MCP::TierRouter)` for Tier 0 routing
- Every storage write wraps in `begin/rescue => nil` -- failed persistence never blocks Tier 0

## Key Patterns

- **Graceful degradation**: PatternStore works with any combination of L0/L1/L2 available
- **Tier routing**: Tier 0 (>= 0.8 confidence, cached), Tier 1 (0.6-0.8, local/fleet), Tier 2 (< 0.6, cloud)
- **Pattern promotion**: Observer records intent+tool pairs; after 3 successful observations, promotes to PatternStore with seeded confidence 0.5
- **Context guards**: Staleness (1hr), rapid-fire (5 in 10min), anomaly (2 consecutive misses) prevent stale Tier 0
- **Settings::Extensions integration**: MCP-specific tools register with `dispatch_type: :class_call`; remote MCP tools register with `dispatch_type: :mcp_remote`

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
| `lib/legion/mcp/tool_adapter.rb` | MCP::ToolAdapter — wraps tools for MCP SDK; handles :mcp_remote dispatch |
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

## Development

```bash
bundle install
bundle exec rspec       # 0 failures
bundle exec rubocop -A  # auto-fix
bundle exec rubocop     # lint check
```

## Pre-Push Pipeline

See parent CLAUDE.md for the required pipeline: rspec -> rubocop -A -> rubocop -> version bump -> CHANGELOG -> push

---

**Maintained By**: Matthew Iverson (@Esity)
