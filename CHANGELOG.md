# legion-mcp Changelog

## [0.4.5] - 2026-03-22

### Fixed
- Corrected dependency version constraints in gemspec: legion-data >= 1.4.15, legion-logging >= 1.2.8, legion-settings >= 1.3.12

## [0.4.4] - 2026-03-22

### Changed
- Updated gemspec dependency version constraints: legion-data >= 1.4.4, legion-json >= 1.2.0, legion-logging >= 1.2.5, legion-settings >= 1.3.9

## [0.4.3] - 2026-03-22

### Changed
- Added `Legion::Logging.debug`/`.warn` calls to all previously silent rescue blocks across lib/legion/mcp/ and all tool files; silent rescues now surface failures through the logging subsystem when available

## [0.4.2] - 2026-03-22

### Added
- `legion.ask_peer` — synchronous RPC query to a specific mesh peer via `lex-mesh` `request_task`
- `legion.list_peers` — list all registered mesh agents, with optional capability filter via `find_agents`
- `legion.notify_peer` — fire-and-forget unicast notification to a specific mesh agent via `send_message`
- `legion.broadcast_peers` — broadcast to all agents or multicast to a capability group via `send_message`
- `legion.mesh_status` — retrieve current mesh network state via `mesh_status`
- All 5 tools registered in `TOOL_CLASSES`; total tool count raised from 45 to 50
- Specs for all 5 new tools (25 examples)
- Updated `server_spec.rb` tool count assertion from 45 to 50

## [0.4.1] - 2026-03-19

### Added
- `legion.prompt_list` — list all stored prompt templates via lex-prompt Client
- `legion.prompt_show` — fetch a prompt by name, version, or tag via lex-prompt Client
- `legion.prompt_run` — render a prompt template with ERB variable substitution via lex-prompt Client
- `legion.dataset_list` — list all stored datasets via lex-dataset Client
- `legion.dataset_show` — fetch a dataset with all rows, optionally version-pinned, via lex-dataset Client
- `legion.experiment_results` — retrieve per-row results and summary for a named experiment from lex-dataset
- `legion.eval_list` — list available evaluator templates via lex-eval Client
- `legion.eval_run` — run a single input/output pair through a named evaluator via lex-eval Client
- `legion.eval_results` — retrieve stored experiment results via lex-dataset experiment store
- All 9 tools registered in `TOOL_CLASSES`; total tool count raised from 36 to 45
- Specs for all 9 new tools

## [0.4.0] - 2026-03-20

### Added
- PatternSchema v1: portable pattern format with trust-level confidence capping on import/export
- PatternExchange: bulk import/export of patterns via JSON files with deduplication
- PatternGossip: AMQP-based pattern sharing between instances (org trust level)
- ColdStart: community pattern loading on first boot when PatternStore is empty

## [0.3.0] - 2026-03-20

### Added
- GapDetector: analyzes observations for repeated manual patterns and frequent unpatched intents
- PatternCompiler: generates compressed tool definitions and compiled workflows from promoted patterns
- CapabilityGenerator: autonomous function generation from detected gaps with LLM code generation
- Validation pipeline with Ruby syntax check and optional lex-eval integration

## [0.2.0] - 2026-03-20

### Fixed
- Observer feedback bug: records actual matched tool name instead of 'legion.do'
- wire_observer skips legion.do calls (feedback handled inside DoAction with correct tool name)

### Added
- Boot-time L2 → L0 pattern hydration (`PatternStore.hydrate_from_l2`)
- Pattern confidence decay with archive threshold (`PatternStore.decay_all`)
- Tier 1 execution: pattern-hinted local/fleet LLM routing in DoAction
- Tier 2 execution: cloud LLM with compressed catalog context in DoAction
- `legion.plan` meta-tool for multi-step workflow planning (36 tools total)
- Response template learning from observed Tier 0 outputs (`PatternStore.learn_response_template`)

## [0.1.0]

### Added
- Initial extraction from LegionIO
- MCP server builder with 35 tool classes
- Observer instrumentation pipeline (TBI Phase 0)
- ContextCompiler with semantic + keyword blended scoring (TBI Phase 2)
- UsageFilter with frequency/recency/keyword scoring (TBI Phase 2)
- EmbeddingIndex for semantic tool matching (TBI Phase 3)
- Auth (JWT + API key)
- ToolGovernance (risk-tier filtering)
- Resources: RunnerCatalog, ExtensionInfo
- PatternStore: 4-layer degrading storage (memory -> cache -> local SQLite -> shared DB)
- TierRouter: confidence-gated tier selection (Tier 0/1/2)
- ContextGuard: staleness, rapid-fire, anomaly detection guards
- Enhanced DoAction (legion.do) with Tier 0 routing before ContextCompiler fallback
- Observer feedback loop: automatic pattern candidate promotion after N successes
- Semantic intent matching via cosine similarity on stored pattern vectors
