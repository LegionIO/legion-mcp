# legion-mcp

MCP (Model Context Protocol) server for the LegionIO framework. Provides semantic tool matching, observation pipeline, context compilation, and tiered behavioral intelligence (Tier 0/1/2 routing).

**Version**: 0.6.0

Extracted from [LegionIO](https://github.com/LegionIO/LegionIO) for independent versioning and reuse.

## Installation

```ruby
gem 'legion-mcp'
```

Or in a Gemfile:

```ruby
gem 'legion-mcp', '~> 0.5'
```

## Architecture

```
Legion::MCP
├── Server              # MCP::Server builder, TOOL_CLASSES registration
├── Auth                # JWT + API key authentication
├── ToolGovernance      # Risk-tier tool filtering + invocation audit
├── ContextCompiler     # Keyword + semantic tool matching (60/40 blend)
├── EmbeddingIndex      # In-memory vector cache for semantic matching
├── Observer            # Instrumentation: counters, ring buffer, pattern promotion
├── UsageFilter         # Frequency/recency/keyword scoring for dynamic tool filtering
├── PatternStore        # 4-layer degrading storage (L0 memory → L1 cache → L2 SQLite)
├── TierRouter          # Confidence-gated tier selection (0/1/2)
├── ContextGuard        # Staleness, rapid-fire, anomaly detection
├── Tools/              # 59 MCP::Tool subclasses (legion.* namespace)
└── Resources/          # RunnerCatalog, ExtensionInfo
```

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

PatternStore degrades gracefully across 4 layers:

| Layer | Backend | Requirement |
|-------|---------|-------------|
| L0 | In-memory hash | Always available |
| L1 | Legion::Cache (memcached/redis) | `defined?(Legion::Cache)` |
| L2 | Legion::Data::Local (SQLite) | `defined?(Legion::Data::Local)` |

All persistence wraps in `begin/rescue => nil` — failed writes never block Tier 0.

## Tools

59 MCP tools in the `legion.*` namespace:

| Tool | Purpose |
|------|---------|
| `legion.do` | Natural language intent routing (Tier 0 fast path) |
| `legion.discover_tools` | Dynamic tool discovery with context |
| `legion.run_task` | Execute a runner function via dot notation |
| `legion.describe_runner` | Runner/function discovery |
| `legion.list_tasks` / `get_task` / `delete_task` | Task CRUD |
| `legion.get_task_logs` | Task execution logs |
| `legion.list_chains` / `create_chain` / `update_chain` / `delete_chain` | Chain management |
| `legion.list_relationships` / `create_relationship` / `update_relationship` / `delete_relationship` | Task relationships |
| `legion.list_extensions` / `get_extension` / `enable_extension` / `disable_extension` | Extension management |
| `legion.list_schedules` / `create_schedule` / `update_schedule` / `delete_schedule` | Schedule CRUD |
| `legion.get_status` / `get_config` | System introspection |
| `legion.list_workers` / `show_worker` / `worker_lifecycle` / `worker_costs` | Worker management |
| `legion.team_summary` / `routing_stats` | Team and routing metrics |
| `legion.rbac_assignments` / `rbac_check` / `rbac_grants` | Access control |
| `legion.mind_growth_status` / `mind_growth_propose` / `mind_growth_approve` | Cognitive architecture growth |
| `legion.mind_growth_build_queue` / `mind_growth_cognitive_profile` / `mind_growth_health` | Growth analysis and health |
| `legion.query_knowledge` | Query Apollo knowledge store |
| `legion.knowledge_health` | Knowledge store health and quality report |
| `legion.knowledge_context` | Scoped RAG knowledge retrieval (local/global/all) |
| `legion.eval_list` / `eval_run` / `eval_results` | Evaluation management |
| `legion.experiment_results` | A/B experiment result comparison |
| `legion.dataset_list` / `dataset_show` | Dataset browsing |
| `legion.prompt_list` / `prompt_show` / `prompt_run` | Prompt template management |
| `legion.plan_action` | Agentic planning with action decomposition |
| `legion.ask_peer` / `notify_peer` / `broadcast_peers` / `list_peers` | Agent mesh communication |
| `legion.mesh_status` | Mesh topology status |

## Resources

| URI | Description |
|-----|-------------|
| `legion://runners` | All registered extension.runner.function paths |
| `legion://extensions/{name}` | Extension detail template |

## Usage

### Standalone MCP server

```ruby
require 'legion/mcp'

server = Legion::MCP.server
# Start via stdio transport
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

## Configuration

All configuration is optional and read via `Legion::Settings` when available:

```json
{
  "mcp": {
    "context_guard": {
      "max_stale_seconds": 3600,
      "rapid_fire_threshold": 5,
      "rapid_fire_window_secs": 600,
      "anomaly_miss_threshold": 2
    }
  }
}
```

## Dependencies

| Gem | Required | Purpose |
|-----|----------|---------|
| `mcp` (~> 0.8) | Yes | MCP server SDK |
| `legion-data` (>= 1.4) | Yes | Sequel models, migrations |
| `legion-json` (>= 1.2) | Yes | JSON serialization |
| `legion-logging` (>= 0.3) | Yes | Logging |
| `legion-settings` (>= 0.3) | Yes | Configuration |
| `legion-cache` | Optional | L1 pattern cache |
| `legion-llm` | Optional | Embeddings for semantic matching |

## Development

```bash
bundle install
bundle exec rspec       # 0 failures
bundle exec rubocop -A  # auto-fix
bundle exec rubocop     # lint check
```

## License

Apache-2.0
