# legion-mcp: MCP Server for LegionIO

**Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Standalone gem providing the Model Context Protocol (MCP) server for LegionIO. Extracted from LegionIO to enable independent versioning and reuse. Includes semantic tool matching, observation pipeline, context compilation, tiered inference (Tier 0/1/2), and tool governance.

**GitHub**: https://github.com/LegionIO/legion-mcp
**Version**: 0.1.0
**License**: Apache-2.0
**Ruby**: >= 3.4

## Architecture

```
Legion::MCP
├── Server              # MCP::Server builder, TOOL_CLASSES registration, governance-aware build
├── Auth                # JWT + API key authentication
├── ToolGovernance      # Risk-tier tool filtering + invocation audit
├── ContextCompiler     # Keyword + semantic tool matching, blended scoring (60% semantic + 40% keyword)
├── EmbeddingIndex      # In-memory vector cache for semantic tool matching
├── Observer            # Instrumentation pipeline: counters, ring buffer, pattern promotion
├── UsageFilter         # Frequency/recency/keyword scoring for dynamic tool filtering
├── PatternStore        # 4-layer degrading storage (L0 memory, L1 cache, L2 local SQLite)
├── TierRouter          # Confidence-gated tier selection (Tier 0/1/2)
├── ContextGuard        # Staleness, rapid-fire, anomaly detection guards
├── Tools/              # 35 MCP::Tool subclasses (legion.* namespace)
└── Resources/          # RunnerCatalog, ExtensionInfo
```

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
- **Pattern promotion**: Observer records intent+tool pairs; after 3 successful observations, promotes to PatternStore
- **Context guards**: Staleness (1hr), rapid-fire (5 in 10min), anomaly (2 consecutive misses) prevent stale Tier 0

## Pre-Push Pipeline

See parent CLAUDE.md for the required pipeline: rspec -> rubocop -A -> rubocop -> version bump -> CHANGELOG -> push

---

**Last Updated**: 2026-03-19
**Maintained By**: Matthew Iverson (@Esity)
