# legion-mcp Changelog

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
