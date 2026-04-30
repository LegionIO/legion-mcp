# legion-mcp Changelog

## [0.9.0] - 2026-04-29

### Removed
- 38 hardcoded tool files that duplicated dynamic extension discovery (extensions, workers, RBAC, status, config, prompts, datasets, evals, mind-growth, knowledge, mesh, absorb) — these are now auto-discovered via `Settings::Extensions`
- `LoggingSupport` module — replaced by direct `Legion::Logging::Helper` + `Utils` module

### Changed
- `FunctionDiscovery.discover_and_register` now prefers reading tools from `Legion::Settings::Extensions` (the centralized registry in `legion-settings`) when available and populated, falling back to existing `Legion::Tools::Discovery` and runner-module discovery paths for backward compatibility
- `ToolAdapter.from_registry_entry` builds MCP tool classes from registry entry hashes; delegates to `from_legion_tool` when the entry contains a loaded tool class, otherwise builds a thin metadata-driven adapter
- `ToolAdapter.build_from_metadata` handles `:mcp_remote` dispatch type by proxying calls through `MCP::Client::Pool` instead of dispatching to a local tool class
- `Resources::RunnerCatalog#catalog_json` reads from `Settings::Extensions.runners` when available, falling back to the existing `legion-data` database query path
- `tools_loader.rb` now requires only 8 MCP-specific and 18 legion-data CRUD tool files (down from 65)
- All logging in server, catalog_dispatcher, observer, pattern_store, tier_router, do_action, and client/connection migrated from `LoggingSupport` to direct `log.*` calls with `Utils.format_fields`
- Bumped `legion-settings` dependency floor to `>= 1.4.0` (requires `Settings::Extensions` module)

### Added
- `Utils` module (`lib/legion/mcp/utils.rb`) — pure-function summarization and formatting helpers extracted from `LoggingSupport`
- `Client::Pool.refresh_tools!` — re-fetches and re-registers all remote server tools
- `Client::Pool.all_tools` now registers each remote tool into `Settings::Extensions` with `dispatch_type: :mcp_remote`
- `Server.register_mcp_tools_in_settings_extensions` — registers `MCP_SPECIFIC_TOOLS` into `Settings::Extensions` with `dispatch_type: :class_call` after build
- `patterns.rb` barrel file — requires all 13 Tier 0 pattern routing modules
- `discovery.rb` barrel file — requires all 12 tool discovery and adaptation modules
- `FunctionDiscovery.settings_extensions_available?` — guard method checking if `Settings::Extensions` is defined and populated
- `FunctionDiscovery.register_from_settings_extensions` — registers tools from the centralized registry into the MCP server
- `ToolAdapter.from_registry_entry` — factory method to build MCP tools from registry entry hashes
- `ToolAdapter.build_from_metadata` — builds thin MCP tool adapters from metadata when no tool class is loaded
- `RunnerCatalog#settings_extensions_runners_available?` — guard for registry-based runner catalog
- `RunnerCatalog#catalog_from_settings_extensions` — builds runner catalog JSON from the centralized registry

## [0.8.1] - 2026-04-14

### Fixed
- `ContextCompiler::CATEGORIES` now includes a `:skills` category listing all four `legion.skill.*` tools (`legion.skill.list`, `legion.skill.describe`, `legion.skill.invoke`, `legion.skill.cancel`). Previously they were absent from `CATEGORIES` so `compressed_catalog` never surfaced them and `legion.do intent:"list all skills"` would misroute to an auto-discovered swarm-github runner, returning "missing keywords: :owner, :repo, :pull_number"
- `ContextCompiler#keyword_score_map` now adds a +3 bonus per intent keyword that matches tool name terms (split on `.`), preventing semantic-score drift from lifting generic runner stubs above correctly-named skill tools when embeddings are active

## [0.8.0] - 2026-04-12

### Added
- `Tools::SkillList` (`legion.skill.list`) — MCP tool to list all skills registered in the Legion daemon with name, namespace, description, trigger words, and trigger type
- `Tools::SkillDescribe` (`legion.skill.describe`) — MCP tool to get full detail for a named skill (`namespace:name` or bare `name`)
- `Tools::SkillInvoke` (`legion.skill.invoke`) — MCP tool to invoke a skill by name with optional `conversation_id` context
- `Tools::SkillCancel` (`legion.skill.cancel`) — MCP tool to cancel an active skill for a given conversation
- All four skill tools registered in `MCP_SPECIFIC_TOOLS` (now 10 total)
- `require_relative 'tools/skills'` added to `tools_loader.rb`

## [0.7.4] - 2026-04-06

### Changed
- `STATIC_TOOLS` renamed to `MCP_SPECIFIC_TOOLS` (6 MCP-only tools)
- `Catalog::Registry` calls replaced with `Tools::Registry` in catalog_dispatcher

### Removed
- `CatalogBridge` module (replaced by `Tools::Registry`)
- `dynamic_tool_list`, `dispatch_catalog_tool`, `register_catalog_listener` from server.rb
- Stale spec files for catalog integration

## [0.7.2] - 2026-04-03

### Fixed
- CatalogDispatcher sanitizes tool names to strip characters invalid for MCP (e.g., `?` from Ruby predicate methods)

## [0.7.1] - 2026-04-02

### Added
- `LoggingSupport` helper for structured MCP event logging with request, parameter, and result summarization

### Changed
- Uplifted non-Sinatra `lib/**/*.rb` logging paths to use `Legion::Logging::Helper` instead of direct `Legion::Logging.*` calls
- Added `handle_exception` coverage across MCP tool, resource, router, client, observer, and pattern-store rescue paths
- Added `info`-level tracing for MCP tool/resource entrypoints and key client, routing, and pattern lifecycle actions
- Removed the custom fallback logger from `Actor::SelfGenerateCycle` in favor of the shared logging helper
- Added explicit `require 'legion/logging'` at the main MCP entrypoint
- Raised the minimum `legion-logging` dependency to `>= 1.4.3` for helper support

## [0.7.0] - 2026-03-31

### Added
- `DeferredRegistry` module for deferred tool loading — tools not in the always-loaded set return name and description only (no `inputSchema`) in `tools/list`, reducing token footprint by ~75% for standard MCP clients (closes #19)
- `legion.tools` now accepts `tool_names` (array) + `schema: true` parameters to load full JSON schemas for specific deferred tools on demand
- `Settings.deferred_loading_defaults` — configurable `enabled` (default true) and `always_loaded` (custom tool names merged with built-in defaults)
- 13 always-loaded tools: `legion.do`, `legion.tools`, `legion.run_task`, `legion.list_tasks`, `legion.get_task`, `legion.get_status`, `legion.describe_runner`, `legion.plan_action`, `legion.query_knowledge`, `legion.knowledge_context`, `legion.knowledge_health`, `legion.absorb`, `legion.get_task_logs`

- `CatalogDispatcher` module — thin dispatch layer routing MCP tool calls through `Legion::Ingress` for RBAC, audit, and sandbox enforcement; auto-generates tool classes from `Catalog::Registry` entries (closes #20)
- `DynamicInjector` module — context-aware tool injection/removal using `ContextCompiler.match_tools`; sends `notifications/tools/list_changed` when active tool set changes based on conversation context
- `CatalogBridge.register_catalog_tools` — auto-generates and registers catalog-sourced tools through `CatalogDispatcher` at server boot
- `Settings.dynamic_tools_defaults` — configurable `enabled` (default false) and `max_injected` (default 10)
- `StructuralIndex` module — precomputed static index of all extensions, runners, actors, and tools with JSON cache at `~/.legionio/cache/structural_index.json`; supports filtering by extension name or type (closes #18)
- `legion.structural_index` MCP tool (61st tool) — query the structural index with optional `extension`, `type`, and `refresh` parameters
- `ToolQuality` module — docstring quality gate (min description length, param descriptions), category resolution across `CATEGORIES` and `EXPANDED_CATEGORIES`, reads/writes capability matrix, and audit summary (closes #17)
- `legion.tool_audit` MCP tool (62nd tool) — audit all registered tools with modes: `summary` (default), `matrix` (capability matrix), `issues` (quality warnings only)
- `ContextCompiler::CATEGORIES` expanded from 9 to 16 categories: added `knowledge`, `mesh`, `mind_growth`, `prompts`, `datasets`, `evals`, `meta` — all 62 tools now have category assignments
- `StateTracker` module — in-memory state snapshots with timestamps and delta diff computation; tracks tool count, observer stats, pattern count, and extension count (closes #16)
- `legion.state_diff` MCP tool (63rd tool) — return only changed system state since a given timestamp; supports `snapshot: true` to take a baseline and `since:` for delta polling
- `legion.search_sessions` MCP tool (64th tool) — search across past conversation sessions by keyword or topic with relevance-sorted results and context snippets (closes #15)

### Changed
- `Server.build` now installs a custom `tools/list` handler via `install_deferred_tools_list_handler` for mcp gem 0.10 compatibility (replaces removed `tools_list_handler` block API)
- `Server.build` now calls `register_catalog_tools` to auto-generate Ingress-dispatched tool classes from Catalog entries

## [0.6.6] - 2026-03-28

### Added
- `Legion::MCP::Actor::SelfGenerateCycle` — periodic `Every`-style actor that calls `SelfGenerate.run_cycle` on a configurable interval (default 300 s, reads `codegen.self_generate.cycle_interval` from Settings)

## [0.6.5] - 2026-03-28

### Removed
- Legacy `expose_as_mcp_tool` and `mcp_tool_prefix` fallback reads from `FunctionDiscovery#runner_expose_opts` — runners that do not use the definition DSL are no longer exposed; `class_expose` is always `nil` and `prefix` is always `nil` in the opts hash

## [0.6.4] - 2026-03-28

### Changed
- `FunctionDiscovery`: prefer `definition[:mcp_exposed]` over deprecated `expose_as_mcp_tool` class method; fall back to legacy path when definition is absent
- `FunctionDiscovery#build_tool_class`: stores `mcp_category` and `mcp_tier` as singleton methods on dynamically built tool classes so downstream consumers can read them
- `ContextCompiler#compressed_catalog` and `#category_tools` now call `merged_categories`, which supplements the `CATEGORIES` constant with any tool classes that declare `mcp_category:` via the definition DSL
- `ToolGovernance#filter_tools`: prefers definition-level `mcp_tier` singleton method on the tool class over `DEFAULT_TOOL_TIERS` fallback; `DEFAULT_TOOL_TIERS` and `custom_tiers` (Settings) remain as fallbacks
- `FunctionDiscovery#register_function` refactored into `resolve_exposed` + `build_tool_opts` helpers to reduce perceived complexity

### Added
- `FunctionDiscovery#definition_for` — reads `runner_module.definition_for(method)` if available, returns nil otherwise
- `FunctionDiscovery#should_expose_from_definition?` — exposure check that treats `definition[:mcp_exposed]` as highest precedence
- `FunctionDiscovery#build_tool_opts` — builds the options hash passed to `build_tool_class`
- `FunctionDiscovery#wire_call_method` — wires the `call` singleton method onto the built tool class
- `ContextCompiler#merged_categories` — merges `CATEGORIES` with definition-declared categories from registered tool classes
- `ToolGovernance#definition_tier` — extracts `mcp_tier` from a tool class singleton method (returns nil when absent)

## [0.6.3] - 2026-03-27

### Added
- `legion.absorb` MCP tool for programmatic content absorption via pattern-matched absorber dispatch (60th tool)

## [0.6.2] - 2026-03-26

### Fixed
- `deps_satisfied?` now strips leading `::` and rejects empty parts from dependency strings to avoid `NameError` on constants like `::Legion::MCP`
- `discover_and_register` prefers `Legion::Extensions.extensions` public accessor with ivar fallback
- `tool_registry` and `@tool_registry_lock` initialized eagerly at module level to eliminate thread-race on first access
- Removed `@tool_registry_lock ||=` guard from `register_tool`/`unregister_tool` (lock always present)
- Added explicit `require 'concurrent'` to `lib/legion/mcp.rb` to prevent `NameError: uninitialized constant Concurrent` in isolation

### Changed
- Spec descriptions updated from `TOOL_CLASSES` to `tool_registry` / `Server.tool_registry` for accuracy

## [0.6.1] - 2026-03-26

### Changed
- Replace frozen TOOL_CLASSES with mutable tool_registry for dynamic tool registration
- Simplify self_generate to detect gaps and publish via AMQP (removed FunctionGenerator)
- Extract `runner_expose_opts` and `register_function` helpers from `build_tools_from_runner` to reduce cyclomatic complexity
- Split `Settings.defaults` into focused sub-methods to reduce method length

### Added
- Codegen self-generate and MCP auto-expose settings defaults
- Function metadata auto-discovery for dynamic MCP tool registration

### Removed
- `function_generator.rb` and `capability_generator.rb` (generation moved to lex-codegen)

## [0.6.0] - 2026-03-26

### Added
- `legion.knowledge_context` MCP tool (59th tool) — scoped RAG query with local/global/all routing

## [0.5.9] - 2026-03-26

### Added
- `legion.knowledge_health` MCP tool: health report for document knowledge base (local, Apollo, sync stats)
  - Optional `path:` input (falls back to Settings corpus_path)
  - Tool count: 57 → 58

## [0.5.8] - 2026-03-26

### Added
- `legion.query_knowledge` MCP tool: search document knowledge base with optional LLM synthesis (closes #3)
  - Inputs: question (required), top_k (default 5), synthesize (default true)
  - Guards with defined?() — returns error response if lex-knowledge not loaded
  - Tool count: 56 → 57

## [0.5.7] - 2026-03-25

### Changed
- `OverrideBroadcast#store_to_apollo` now routes through `Legion::Apollo.ingest` (core library) instead of calling `Legion::Extensions::Apollo::Runners::Knowledge.handle_ingest` directly — removes the hard coupling to the co-located extension

## [0.5.6] - 2026-03-24

### Changed
- Reindex docs: update CLAUDE.md and README with current architecture and tool inventory

## [0.5.5] - 2026-03-24

### Added
- Mind Growth Phase 7.2: 6 MCP tools for lex-mind-growth integration
- `legion.mind_growth_status` — growth status including proposals and cognitive coverage
- `legion.mind_growth_propose` — propose a new cognitive extension concept
- `legion.mind_growth_approve` — evaluate and score a proposal for approval
- `legion.mind_growth_build_queue` — list approved proposals in the build queue
- `legion.mind_growth_cognitive_profile` — analyze cognitive architecture coverage against reference models
- `legion.mind_growth_health` — extension fitness scores, prune candidates, and improvement candidates
- All 6 tools registered in `TOOL_CLASSES`; total tool count raised from 50 to 56
- Specs for all 6 new tools (38 examples)
- Updated `server_spec.rb` tool count assertion from 50 to 56

## [0.5.4] - 2026-03-24

### Added
- TBI Phase 5: `GapDetector` — detects unmatched intents, high-failure tools, and stale candidates from Observer/PatternStore data
- TBI Phase 5: `FunctionGenerator` — LLM-powered tool spec generation from detected gaps, with validation and pattern registration
- TBI Phase 5: `SelfGenerate` — orchestrates gap detection + function generation cycles with cooldown, history tracking, and status reporting
- 89 new specs across gap_detector, function_generator, and self_generate

### Changed
- Rewrote `GapDetector` from frequency-based to gap-type-based detection (unmatched, failure, stale) with priority scoring

## [0.5.3] - 2026-03-23

### Changed
- Add `caller:` identity to all LLM call sites (do_action tier 1/2, plan_action, capability_generator runner/spec)

## [0.5.2] - 2026-03-23

### Changed
- Bump legion-data dependency to >= 1.4.19

## [0.5.1] - 2026-03-23

### Added
- Dynamic tool list from `Catalog::Registry` merged with static TOOL_CLASSES
- `dispatch_catalog_tool` routes Catalog-sourced MCP tool calls to extension runners
- `CatalogBridge` module extracted for catalog integration (hydration, listener, dispatch, dynamic tools)
- `OverrideBroadcast` for mesh-wide override confirmation via RabbitMQ
- Hydrate `OverrideConfidence` from SQLite (L2) and Apollo (L3) at server boot
- MCP server resets automatically when Catalog registry changes

## [0.5.0] - 2026-03-23

### Added
- MCP client: `ServerRegistry` for static (settings) and dynamic (runtime) server registration with health tracking and cooldown-based recovery
- MCP client: `Connection` class for stdio and HTTP transport connections with TTL-cached tool lists
- MCP client: `Pool` for long-lived connection management, aggregates tools across all healthy servers
- MCP client: `Client.boot` loads server registry from `Legion::Settings[:mcp][:servers]` at startup
- MCP client: `Client.register` / `Client.deregister` for runtime server management
- `Settings` module with defaults for `servers`, `overrides`, `tool_cache_ttl`, `connect_timeout`, `call_timeout`

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
