# legion-mcp Maintainer Guide

`legion-mcp` is a LegionIO **core library**, not a LEX extension. It builds the `legion`
MCP SDK server and contains client-side remote-server integration. See [README.md](README.md)
for installation, operator configuration, transports, and capability limits. Keep `CLAUDE.md`
and `AGENTS.md` byte-for-byte identical; neither is a separate policy layer.

## Architecture and entrypoints

| Path | Responsibility |
|---|---|
| [`lib/legion/mcp.rb`](lib/legion/mcp.rb) | `Legion::MCP.server` (memoized), `server_for(token:, identity:)`, `reset!`; optional integration loading |
| [`lib/legion/mcp/settings.rb`](lib/legion/mcp/settings.rb) | Flat MCP defaults and separate code-generation defaults; explicit framework merges |
| [`lib/legion/mcp/server.rb`](lib/legion/mcp/server.rb) | `Server.build`, authoritative registry, SDK server context, listing/invocation wrappers, tracing and audit |
| [`lib/legion/mcp/auth.rb`](lib/legion/mcp/auth.rb), [`tool_governance.rb`](lib/legion/mcp/tool_governance.rb) | Token authentication; independent live role/risk filtering |
| [`lib/legion/mcp/tools_loader.rb`](lib/legion/mcp/tools_loader.rb), [`tools/`](lib/legion/mcp/tools/) | Tool class loading and implementations; loading is not registration |
| [`lib/legion/mcp/function_discovery.rb`](lib/legion/mcp/function_discovery.rb), [`tool_adapter.rb`](lib/legion/mcp/tool_adapter.rb), [`catalog_dispatcher.rb`](lib/legion/mcp/catalog_dispatcher.rb) | Framework tool discovery, registry adapters, and runner dispatch through `Legion::Ingress` |
| [`lib/legion/mcp/deferred_registry.rb`](lib/legion/mcp/deferred_registry.rb), [`tools/discover_tools.rb`](lib/legion/mcp/tools/discover_tools.rb) | Protocol descriptors and identity-scoped schema lookup |
| [`lib/legion/mcp/context_compiler.rb`](lib/legion/mcp/context_compiler.rb), [`embedding_index.rb`](lib/legion/mcp/embedding_index.rb) | Keyword and optional semantic matching |
| [`lib/legion/mcp/tier_router.rb`](lib/legion/mcp/tier_router.rb), [`context_guard.rb`](lib/legion/mcp/context_guard.rb) | Confidence routing, cached-chain execution, staleness/rapid-fire/anomaly guards |
| [`lib/legion/mcp/observer.rb`](lib/legion/mcp/observer.rb), [`patterns/`](lib/legion/mcp/patterns/) | Usage observations, successful intent/tool learning, pattern compilation/storage/exchange |
| [`lib/legion/mcp/tracing_context.rb`](lib/legion/mcp/tracing_context.rb), [`audit.rb`](lib/legion/mcp/audit.rb), [`transport/`](lib/legion/mcp/transport/) | Request-local tracing and optional audit publication |
| [`lib/legion/mcp/resources/`](lib/legion/mcp/resources/) | Runner catalog and extension resources |
| [`lib/legion/mcp/client.rb`](lib/legion/mcp/client.rb), [`client/`](lib/legion/mcp/client/) | Remote-server configuration, connection lifecycle, pooling, and tool calls |
| [`lib/legion/mcp/self_generate.rb`](lib/legion/mcp/self_generate.rb), [`actors/`](lib/legion/mcp/actors/) | Optional self-generation integration |

The CLI is owned by the separate LegionIO gem: `legionio serve mcp stdio` or
`legionio serve mcp http`. This gem alone is not an HTTP hosting or authentication policy.
Runtime dependency versions are authoritative in [legion-mcp.gemspec](legion-mcp.gemspec):
Ruby >= 3.4 and MCP SDK >= 1.9, < 2. Check the installed SDK contract before changing wrappers.

## Settings and real boot

`Legion::MCP::Settings.default` returns the **contents of `:mcp`**, not a multi-root tree.
Requiring `legion/mcp` loads `settings.rb`, which registers these two payloads explicitly:

```ruby
Legion::Settings.merge_settings(:mcp, Legion::MCP::Settings.default)
Legion::Settings.merge_settings(:codegen, Legion::MCP::Settings.codegen)
```

Keep `Settings.codegen` separate (`self_generate` belongs under `:codegen`). Do not introduce
plural `defaults`, a namespace registration loop, or the LEX `default_settings` convention.
Include every consumed MCP top-level section in the default payload so real framework
`Legion::Settings.validate!` accepts configured auth, governance, roles, tier0, and cold_start.
Preserve preloaded configuration when registering defaults.

Optional configuration is nullable: exercise absent/nil `:mcp`, absent/nil `:deferred_loading`,
and nil `enabled`/`always_loaded`. Deferral remains enabled unless explicitly `false`; custom
always-loaded names are used only when configured as an array. Nullable configuration must
not lose captured identity, break listing, or remove argument schemas. Role semantics are
separate: missing/unknown roles are permissive; an explicitly false role or false tool list
denies access. Do not reinterpret explicit `false` as missing configuration.

Boot regressions belong in [`spec/legion/mcp/settings_boot_spec.rb`](spec/legion/mcp/settings_boot_spec.rb).
Use a fresh Ruby subprocess, isolated HOME/settings environment, the real framework loader,
optional JSON configuration loaded before `require 'legion/mcp'`, and `Settings.validate!`.
Assert observable listing/auth/configuration and retained-server revocation behavior. Do not
replace the loader or manually merge defaults in the child: that masks missing integration.
The in-process reset in `spec/spec_helper.rb` is test isolation, not proof of real boot.

## Registry and protocol contracts

- `Server::MCP_SPECIFIC_TOOLS` defines ten built-ins: `legion.plan`, `legion.tools`,
  `legion.structural_index`, `legion.tool_audit`, `legion.state_diff`, `legion.search_sessions`,
  and `legion.skill.list`, `.describe`, `.invoke`, `.cancel`.
- `tools_loader.rb` also requires `legion.do` and job/CRUD classes. Their presence as Ruby
  constants does **not** place them in the default server catalog. Extension/remote entries
  enter through `Legion::Settings::Extensions` and the server registry; do not infer exposure
  from loaded files or server instruction text. Keep registration and cache invalidation
  centralized in the existing server builder/registry APIs.
- Built-in protocol names use `legion.*`; registry adapters sanitize names. Use the actual
  advertised name, not a guessed universal naming transformation.
- Every `tools/list` descriptor carries the real `inputSchema`, including required arguments
  and property types. Deferred descriptors trim optional metadata, not schemas. Schema lookup
  returns the full tool definition with the same argument schema, not a placeholder.
- `Legion::MCP.server` is memoized; use `Legion::MCP.reset!` when a test needs a fresh singleton.
  Registry, settings, observer, and trace state have separate lifetimes: restore only the state
  a test changes, and do not assume resetting the singleton resets everything else.

## Identity, authorization, and SDK boundaries

`Server.build` captures identity, conversation ID, and trace ID in each server's context.
Keep closures bound to that server; module-level `current_identity`/trace fields are not
execution authority. A later or overlapping build must not change a retained server's caller.
`DiscoverTools` schema resolution receives identity through the SDK `server_context`.

Authentication and supplying trusted identity are different operations. `server_for(identity:)`
accepts a supplied identity; the host must establish its trust. Auth and risk governance are
both disabled by default. Role filtering can apply independently of risk governance, and
missing/unknown roles do not form a deny-by-default policy.

Filter listing and recheck live role/risk settings immediately before each SDK tool invocation.
For tools already registered on a retained server, revoke/regrant and changed risk mappings
must take effect without rebuilding. Rebuild when the available tool set changes.
Do not replace invocation checks with a build-time filter, or infer authorization from discovery.

The tracing wrapper forwards `call_tool(request, **options)` to the SDK with all keyword options
intact. Preserve SDK session/auth/scope and cancellation behavior; do not bypass the SDK to call
classes directly from that wrapper. Preserve the distinction between MCP tool error responses
(`isError`) and JSON-RPC errors. Unknown tools, invalid arguments, tool exceptions, scope denial,
and cancellation need protocol-level coverage. Clear request tracing in `ensure`, including
failures and cancelled calls; audit against the captured caller/session, not global build state.

Direct Ruby APIs such as `TierRouter.route` execute outside the SDK invocation wrapper;
they are not an authorization boundary for untrusted requests.

## Optional services and failure behavior

Gem dependencies and connected runtime services are different requirements. `legion-data` is a
gem dependency, but database connectivity is not required merely to load this library. Backend
operations still need their actual services/models. Check the individual tool before claiming
that a successful server build makes it executable.

- Patterns use L0 memory, optional connected `Legion::Cache` at L1, and optional connected
  `Legion::Data::Local` SQLite at L2. Persistence failures call `handle_exception` and degrade;
  they are not silent success and do not establish durable storage.
- Default semantic embeddings require a started `Legion::LLM`; keyword discovery remains a
  separate path. Skills require `Legion::LLM::Skills::Registry`; invocation additionally needs
  `ConversationStore`, and actual pipeline execution needs its executor/request classes.
  Missing skill services return explicit error or non-executed/queued results as appropriate.
- Runner catalog dispatch needs `Legion::Ingress`. Optional audit transport needs the transport
  classes loaded and a connected transport. Preserve the existing availability checks rather
  than making all optional integrations mandatory at require time.
- Remote-server registration/configuration is not evidence of a working connection. Current
  `Client::Connection` limitations with SDK 1.9: an unconnected `tools` call recursively acquires
  the same mutex through `fetch_tools`/`connect` (`ThreadError`); explicit `connect` requests the
  tool list without first calling the SDK client's `connect` (a connect-required error).
  See [`client/connection.rb`](lib/legion/mcp/client/connection.rb). Do not present this wrapper
  as a working federation quick-start. Connection lifecycle and actual SDK transport round
  trips need smoke coverage; metadata or mocked client examples alone do not prove connectivity.

Use `Legion::Logging::Helper` and `log.*`; every rescue must log/`handle_exception` or re-raise.
Keep stdout free of application logs for stdio MCP: configure file logging before requiring
`legion/mcp` (see the README recipe). Use `Legion::JSON` for application JSON; its loaded keys
are symbols. Qualify root constants such as `::Process` and any necessary `::JSON` references
inside the `Legion::` namespace.

## Tier routing and learning

`TierRouter.route` executes a cached tool chain only at Tier 0:

| Decision | Current behavior |
|---|---|
| Confidence >= 0.8 and guards pass | Tier 0: execute the chain and return its response |
| 0.6 <= confidence < 0.8 | Tier 1: return pattern/reason metadata and `response: nil` |
| Confidence < 0.6 or no matching pattern | Tier 2: return reason metadata and `response: nil` |
| Guard rejection or Tier 0 execution exception | Escalate to Tier 1 metadata; log execution failures |

Tiers 1/2 do not automatically invoke local/fleet/cloud models. No latency or cost guarantee
follows from these labels. Guards cover staleness (default 3600 seconds), rapid-fire requests
(more than 5 within 600 seconds), and repeated misses.

`Observer.record_intent_with_result` promotes successful explicit intent/tool observations;
ordinary tool-call counters alone do not create learned patterns. The default candidate
threshold is 3 observations, seeded confidence is 0.5, and hit/miss adjustments are +0.02/-0.05.
A newly promoted pattern is therefore not immediately Tier 0. Test routing boundaries, guard
escalation, success/failure learning, and observable execution, not just constant equality.
Changes to these semantics require deliberate contract/spec/documentation updates, not blindly
changing assertions to match new constants.

## Tests and maintainer workflow

Useful entrypoints under [`spec/legion/mcp/`](spec/legion/mcp/):

- `settings_boot_spec.rb`, `settings_spec.rb`: real boot and configured-default preservation.
- `server_authorization_spec.rb`, `server_tracing_spec.rb`, `tool_governance_spec.rb`: retained
  server identity, live grants/risk policy, SDK scope/cancellation/error behavior, trace cleanup.
- `server_spec.rb`, `deferred_registry_spec.rb`, `tools/discover_tools_spec.rb`: protocol listing,
  real schemas, nullable options, and schema-discovery authority.
- `tier_router_spec.rb`, `context_guard_spec.rb`, `observer_pattern_promotion_spec.rb`,
  `pattern_store_spec.rb`, `tier0_integration_spec.rb`: routing, learning, persistence boundaries.
- `client/connection_spec.rb`, `client/connection_tracing_spec.rb`, `client/pool_spec.rb`,
  `client_boot_spec.rb`: remote-client lifecycle and propagation boundaries.

The suite loads real Legion libraries but also uses doubles and an ingress fallback; it is not
universally mock-free and does not prove a live external backend works. Prefer real boot/SDK
boundary tests where integration is the contract, with controlled doubles for unrelated services.
Never weaken tests or substitute a manually initialized environment to make a regression pass.

For Ruby changes, use the applicable release/RSpec/RuboCop guidance, update version/changelog
when required, and run these **full-repository** gates from the checkout root once changes land:

```bash
bundle install
bundle exec rspec --format json --out tmp/rspec_results.json --format progress --out tmp/rspec_progress.txt
bundle exec rubocop -A
```

Do not substitute targeted specs or file-scoped lint. Inspect failed examples when needed;
do not dump successful JSON/progress artifacts. Docs-only work should check examples/links and
`cmp -s CLAUDE.md AGENTS.md`; report only checks actually run. Delegated workers leave integrated
verification to their owner unless explicitly assigned to run it.

Work in the existing development checkout. Preserve unrelated user edits and concurrent work;
do not reset, overwrite, or relocate them. [Gemfile](Gemfile) may resolve `legion-settings` from
a companion checkout, so account for the dependency actually used by local development.
Use explicit staging filenames (`git add README.md CLAUDE.md AGENTS.md` for that exact docs scope),
never `git add .` or `git add -A`, and never force-push. Do not stage generated lockfiles, gems,
coverage, or tmp artifacts. Do not add personal/company identifiers. Keep changes scoped, follow
workspace Ruby conventions, and never modify an already-published migration without explicit
per-file approval.
