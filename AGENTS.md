# legion-mcp Agent Notes

## Scope

`legion-mcp` is the standalone MCP server gem for Legion. It owns tool/resource registration, tier routing, tool governance, semantic matching, and observation/pattern promotion.

## Fast Start

```bash
bundle install
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
```

## Primary Entry Points

- `lib/legion/mcp.rb`
- `lib/legion/mcp/server.rb`
- `lib/legion/mcp/context_compiler.rb`
- `lib/legion/mcp/tier_router.rb`
- `lib/legion/mcp/pattern_store.rb`
- `lib/legion/mcp/observer.rb`
- `lib/legion/mcp/tools/`

## Guardrails

- Keep optional dependencies guarded (`legion-cache`, `legion-llm`, `Data::Local`); this gem must degrade cleanly.
- Tier confidence behavior is core contract: Tier 0 (>= 0.8), Tier 1 (0.6-0.8), Tier 2 (< 0.6).
- Pattern storage failures must not block tool execution.
- Tool registration remains centralized through server builder/registry; avoid ad hoc registration paths.
- Preserve governance checks and audit trails for tool invocation.

## Validation

- Run specs for changed tools/router/compiler paths.
- Before handoff, run `bundle exec rspec`, `bundle exec rubocop -A`, then `bundle exec rubocop`.
