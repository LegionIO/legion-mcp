# legion-mcp Changelog

## v0.1.0

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
