# legion-mcp: MCP Server for LegionIO

**Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Standalone gem providing the Model Context Protocol (MCP) server for LegionIO. Extracted from LegionIO to enable independent versioning and reuse. Includes semantic tool matching, observation pipeline, context compilation, tiered inference (Tier 0/1/2), and tool governance.

**GitHub**: https://github.com/LegionIO/legion-mcp
**Version**: 0.7.4
**License**: Apache-2.0
**Ruby**: >= 3.4

## Architecture

```
Legion::MCP
├── Server              # MCP::Server builder, governance-aware build; tool list sourced from Legion::Tools::Registry via DeferredRegistry
├── Auth                # JWT + API key authentication
├── ToolGovernance      # Risk-tier tool filtering + invocation audit
├── ContextCompiler     # Keyword + semantic tool matching, blended scoring (60% semantic + 40% keyword)
├── EmbeddingIndex      # Semantic tool matching; delegates embedding persistence to Tools::EmbeddingCache (L0-L4)
├── Observer            # Instrumentation pipeline: counters, ring buffer, pattern promotion
├── UsageFilter         # Frequency/recency/keyword scoring for dynamic tool filtering
├── PatternStore        # 4-layer degrading storage (L0 memory, L1 cache, L2 local SQLite)
├── TierRouter          # Confidence-gated tier selection (Tier 0/1/2)
├── ContextGuard        # Staleness, rapid-fire, anomaly detection guards
├── ToolAdapter         # Adapts Legion::Tools::Base subclasses to MCP SDK format (McpToolAdapter kept as alias)
├── DeferredRegistry    # Reads deferred tools from Legion::Tools::Registry at request time
├── Tools/              # MCP_SPECIFIC_TOOLS only (6 tools); 57 individual tool files removed — extension tools discovered via Legion::Tools::Discovery
└── Resources/          # RunnerCatalog, ExtensionInfo
```

### Tool Registry Migration Notes

- **Before**: legion-mcp owned 57+ individual `Tools/*.rb` files registered in `TOOL_CLASSES`.
- **After**: Tools discovered dynamically via `Legion::Tools::Discovery` from extension `runner_modules` at boot. `Legion::Tools::Registry` classifies each as `:always` or `:deferred`. `DeferredRegistry` resolves the deferred set at request time.
- `MCP_SPECIFIC_TOOLS` (6 tools) covers MCP-only concerns not owned by any extension.
- `CatalogBridge` removed — bridged old `Extensions::Capability` / `Catalog::Registry` which no longer exist.
- `EmbeddingIndex` uses `Legion::Tools::EmbeddingCache` (5-tier L0–L4) instead of its own in-memory store.

## Dependencies

| Gem | Required | Purpose |
|-----|----------|---------|
| `mcp` (~> 0.8) | Yes | MCP server SDK |
| `legion-data` (>= 1.4) | Yes | Sequel models, migrations |
| `legion-json` (>= 1.2) | Yes | JSON serialization |
| `legion-logging` (>= 0.3) | Yes | Logging |
| `legion-settings` (>= 0.3) | Yes | Configuration |
| `legion-cache` | Optional | L1 pattern cache (memcached/redis) |
| `legion-llm` | Optional | Embeddings for semantic matching |
| `legionio` | Dev only | Full framework for integration testing |

## Guard Strategy

All optional dependencies use `defined?()` guards:
- `defined?(Legion::Cache)` for L1 cache operations
- `defined?(Legion::Data::Local)` for L2 SQLite persistence
- `defined?(Legion::LLM)` for embedding generation
- `defined?(Legion::MCP::EmbeddingIndex)` for semantic matching
- `defined?(Legion::MCP::TierRouter)` for Tier 0 routing
- Every storage write wraps in `begin/rescue => nil` -- failed persistence never blocks Tier 0

## Key Patterns

- **Graceful degradation**: PatternStore works with any combination of L0/L1/L2 available
- **Tier routing**: Tier 0 (>= 0.8 confidence, cached), Tier 1 (0.6-0.8, local/fleet), Tier 2 (< 0.6, cloud)
- **Pattern promotion**: Observer records intent+tool pairs; after 3 successful observations, promotes to PatternStore with seeded confidence 0.5
- **Context guards**: Staleness (1hr), rapid-fire (5 in 10min), anomaly (2 consecutive misses) prevent stale Tier 0

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion/mcp.rb` | Entry point: `Legion::MCP.server` singleton factory |
| `lib/legion/mcp/version.rb` | `Legion::MCP::VERSION` constant |
| `lib/legion/mcp/server.rb` | MCP::Server builder, governance-aware build; reads tools from Tools::Registry |
| `lib/legion/mcp/auth.rb` | JWT + API key authentication |
| `lib/legion/mcp/tool_governance.rb` | Risk-tier tool filtering + invocation audit |
| `lib/legion/mcp/context_compiler.rb` | Keyword + semantic tool matching (60/40 blend) |
| `lib/legion/mcp/embedding_index.rb` | Semantic tool matching; delegates persistence to Legion::Tools::EmbeddingCache |
| `lib/legion/mcp/observer.rb` | Instrumentation: counters, ring buffer, pattern promotion |
| `lib/legion/mcp/usage_filter.rb` | Frequency/recency/keyword scoring for dynamic tool filtering |
| `lib/legion/mcp/pattern_store.rb` | 4-layer degrading storage (L0/L1/L2) with thread-safe access |
| `lib/legion/mcp/tier_router.rb` | Confidence-gated tier selection, tool chain execution |
| `lib/legion/mcp/context_guard.rb` | Staleness, rapid-fire, anomaly detection |
| `lib/legion/mcp/tool_adapter.rb` | MCP::ToolAdapter — wraps Legion::Tools::Base for MCP SDK (McpToolAdapter kept as alias) |
| `lib/legion/mcp/deferred_registry.rb` | DeferredRegistry — reads deferred tools from Legion::Tools::Registry at request time |
| `lib/legion/mcp/tools/` | MCP_SPECIFIC_TOOLS only (6 tools); 57 extension tool files removed |
| `lib/legion/mcp/tools/do_action.rb` | Natural language intent routing with Tier 0 fast path |
| `lib/legion/mcp/tools/discover_tools.rb` | Dynamic tool discovery with context |
| `lib/legion/mcp/tools/run_task.rb` | Execute runner function via dot notation |
| `lib/legion/mcp/tools/query_knowledge.rb` | Query Apollo knowledge store |
| `lib/legion/mcp/tools/knowledge_health.rb` | Knowledge store health and quality report |
| `lib/legion/mcp/tools/knowledge_context.rb` | Scoped RAG query (local/global/all) for current-task context |
| `lib/legion/mcp/tools/eval_*.rb` | Evaluation management (list/run/results) |
| `lib/legion/mcp/tools/experiment_results.rb` | A/B experiment result comparison |
| `lib/legion/mcp/tools/dataset_*.rb` | Dataset browsing (list/show) |
| `lib/legion/mcp/tools/prompt_*.rb` | Prompt template management (list/show/run) |
| `lib/legion/mcp/tools/plan_action.rb` | Agentic planning with action decomposition |
| `lib/legion/mcp/tools/ask_peer.rb` / `notify_peer.rb` / `broadcast_peers.rb` / `list_peers.rb` | Agent mesh communication |
| `lib/legion/mcp/tools/mesh_status.rb` | Mesh topology status |
| `lib/legion/mcp/tools/mind_growth_*.rb` | Mind growth tools (status/propose/approve/build_queue/cognitive_profile/health) |
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
