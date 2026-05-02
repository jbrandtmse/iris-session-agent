---
title: "Product Brief Distillate: iris-session-agent"
type: llm-distillate
source: "product-brief-iris-session-agent.md"
created: "2026-05-02"
purpose: "Token-efficient context for downstream PRD creation. Dense bullets; each is self-contained. Do not assume the reader has the brief loaded."
---

# Product Brief Distillate: iris-session-agent

## Product Identity & Posture

- **Name**: `iris-session-agent`. Tagline: *"Chatting with your Interoperability Session to really understand what happened."*
- **What**: Open-source IRIS module adding two AI chat agents to the Management Portal — a Session Inspection Agent (chat about a specific session) and a Message Search Agent (find sessions via natural-language query) — both embedded in custom subclasses of `EnsPortal.VisualTrace` and `EnsPortal.MessageViewer` respectively.
- **Posture**: **Hobby project**, single author **Joshua Brandt**. **Open source from day one** under the **MIT license** (inherited posture from `sources/iris-session-chat/LICENSE`; `LICENSE` file lands at repo root in v1 release commit). No commercial motion — no SI partner channel, no closed-source features, no paid support tier. Timeline is **flexible / milestone-based, not date-based**.
- **Origin**: Scoped during InterSystems READY 2026 internal hackathon as the *Ensemble Session Inspection Agent* — planned but not built. Hackathon = origin attribution only; no remaining hackathon ties.
- **Distribution**: Open Exchange (OEX) + GitHub (`github.com/jbrandtmse/iris-session-agent`).

## User & Problem Context

- **Primary users**: IRIS / Ensemble integration engineers and operators on **IRIS / IRIS for Health 2024.1+**. On-call engineers debugging incidents at 2am are the canonical persona.
- **Junior engineers benefit disproportionately** — they can do senior-level diagnosis with the agent's help that they can't do alone.
- **The pain**: An Ensemble session leaves a trace across 5 separate data surfaces (`Ens.MessageHeader`, message bodies as arbitrary `%Persistent` instances, `Ens.Util.Log`, `Ens.Rule.Log`, BP runtime state in `Ens.BP.Context`/`Ens.BP.Thread`); operators join those surfaces in their heads on every incident.
- **Cost of status quo**: 20-30 minutes of expert tab-switching per diagnostic conversation; junior engineers blocked; correlated errors missed.

## Success Criteria (north-star metrics)

- **Primary**: operators' time-to-resolution measurably drops with the agent vs. tab-switching by hand. Aspirational target: 20-30 min → 30 sec; even 5 min → 1 min on common diagnoses is a win.
- **Secondary**: at least one customer site adopts it for production on-call diagnosis.
- **Explicitly NOT** north-star metrics: download counts, stars, maintenance-longevity-for-its-own-sake. Vanity for a hobby project; ignore.

## Tone / Framing Preferences

- **Downplay** the "ahead of AI Hub" framing across all artifacts (brief, PRD, README, OEX listing). Lead with "fills a gap that exists today on the IRIS the community already has." AI Hub precursor framing is one sentence of context, not a banner. Reason: don't read as competitive with InterSystems' own roadmap.
- All planning artifacts authored knowing they will be **public** in the OSS repo; no internal-confidential framing.

## Technical Constraints (non-negotiable)

- **IRIS / IRIS for Health 2024.1+** version floor. Every API/class/parameter must be verified available in 2024.1; design 2024.1-compatible fallbacks before newer-version optimizations.
- **Pure ObjectScript** only in runtime. No embedded Python (`[Language = python]`) in any shipped class. Build-time tooling, tests, and one-off operator scripts may use Python.
- **No AI Hub primitives** (`%AI.Agent`, `%AI.ToolSet`, `%AI.Tool`, `%AI.Agent.Session`, `%AI.Policy.Authorization`, `%AI.Shell.*`, `%AI.MCP.Service`). All replaced with custom code.
- **Read-only** at three layers: (L1) implementation discipline, (L2) `SessionAgent.Tool.Registry.Dispatch` policy gate consulting `MutatesState=0/1`, (L3) IRIS RBAC role `%SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` tables.
- **MCP serving NOT in this project** — handled by sibling [`../iris-execute-mcp-v2`](https://github.com/jbrandtmse/iris-execute-mcp-v2) project. Our tool registry stays MCP-exportable (clean `(toolName, jsonArgs) → jsonResult` contract; no `%session.Data` reads from inside tools, no Zen state coupling, no `$NAMESPACE` side effects, no exception-as-error-signal) so that suite can wrap it.
- **IPM-installable** as a single module (`zpm install iris-session-agent`).
- **`%Library.IRISWallet` does NOT exist in 2024.1** — Secure Wallet introduced in 2026.1. Topic-8 secrets path: env-var via `$SYSTEM.Util.GetEnviron` (primary, container-friendly) → `Ens.Config.Credentials` (secondary, encrypted at rest in `%SYS.Ensemble`) → custom `%Persistent` + `$System.Encryption.AESGCMEncrypt` (last-resort).

## Package Naming Convention

- **`SessionAgent.*` is the single root package** for ALL custom classes. No `Custom.*` for portal subclasses (breaks from HSCUSTOM convention by user choice for single-package consistency).
- Sub-packages (from architecture): `Agent`, `LLM`, `LLM.Util`, `Tool`, `Tool.Inspection`, `Tool.Search`, `Chat`, `Config`, `Audit`, `Security`, `Util`, `Search`, `Task`, `UI`, `EnsPortal`, plus top-level `Installer`.
- IRIS RBAC role: `%SessionAgent_ReadOnly`. IPM resource: single `<Resource Name="SessionAgent.PKG"/>`. Bookmark URL: `/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`.

## V1 Scope (Full Plan, Incremental Delivery)

**In v1 (full scope)**:

- TWO agents sharing ~80% of infrastructure: **Session Inspection Agent** (chat tab on `SessionAgent.EnsPortal.VisualTrace`, 13 tools — 9 SQL + 4 method) and **Message Search Agent** (chat tab on `SessionAgent.EnsPortal.MessageViewer`, 8-9 tools all SQL-driven).
- **FOUR LLM providers, extensible framework**: OpenAI (ships first per user priority), Anthropic, Google Gemini, Ollama / vLLM (any OpenAI-compatible self-hosted). Adding a 5th provider = one new concrete subclass + registry entry, no refactor.
- **Per-agent Zen-page configuration** (`SessionAgent.UI.AgentConfig`): provider, model, max-tokens, temperature, system-prompt override, read-only flag, credential reference.
- **Body-content search** for the Search Agent — two-stage narrow-then-inspect pattern beyond indexed `Ens.MessageHeader` columns; reuses inspection-agent's body-class dispatch ladder.
- **Per-user, per-message-body-class vocabulary learning** for the Search Agent. `SessionAgent.Search.UserVocabulary` keyed on `(PortalUser, MessageBodyClass, Alias)` with `MessageBodyClass=""` as class-agnostic bucket.
- **Audit logging** at LLM round-trip and tool dispatch granularity — two persistent classes (`SessionAgent.Audit.LlmCall`, `SessionAgent.Audit.ToolCall`) FK'd to `SessionAgent.Chat.History`.
- **Chat-history lifecycle coupling**: Inspection agent — coupled to `Ens.MessageHeader.Purge()` via daily sweep task on orphaned `App.Chat.History` rows (Topic 10 Option B). Search agent — TTL-based 30-day default sweep (configurable).
- **Vendored client-side Markdown rendering** (`marked` ≥ 18.0.2 + `Prism.js` curated languages + `DOMPurify`) at `/csp/static/iris-session-agent/`. ~45 KB gzipped, no CDN dependency.

**Out of v1 (intentional deferrals)**:

- MCP serving + Rust transport — handled by sibling `iris-execute-mcp-v2` project. Tool registry must remain introspectable enough for that suite to wrap.
- Phase 1 stand-alone terminal REPL bot — was AI-Hub-coupled freebie via `%AI.Shell.Console`; reimplementing is ~30 min of unwanted complexity for backup-demo path. Defer to v1.5 if useful.
- Vector / semantic search on message bodies — body-content search is keyword/regex/LLM-content-evaluation bounded by indexed pre-filter. Vector path would need `%Library.Embedding` + embedding generation at message save time. v2 concern.
- Cross-namespace single-conversation operation — each bookmark targets one namespace; `$NAMESPACE` switching forbidden in CSP context per project rule.
- PHI redaction architecture — namespace-scoped PHI segregation (current IRIS customer practice) is the v1 boundary. Body-redaction layer in dispatch path is post-v1.
- Cross-user `SessionAgent.Search.NamespaceVocabulary` baseline — schema ships in v1, population logic deferred to v1.5.
- LLM-extracted alias generation from chat history — v1 captures vocabulary signal from click-through and explicit save-as only; LLM extraction is v1.5 with regex-scrubbed PHI mitigation.
- Vendor commercial licensing or SI-partner channel — open source day one, no commercial motion.

## Delivery Cadence

- **Plan for full v1 scope** in PRD, architecture, epics, stories.
- **Deliver INCREMENTALLY** — pre-alpha builds into operators' hands early. The 11-epic inspection-agent sequence has Epic 6 producing first demo-able OpenAI-powered Inspection Agent, before epics 7-11 add polish + remaining providers. Search-agent epics 12-17 follow.
- Milestone-based-not-date-based release planning. PRD / architecture should call out which epics produce **pre-alpha-distributable artifacts**.

## Architecture (Accepted Decisions, see research docs for depth)

### Two-Agent Infrastructure Sharing

| Layer | Status |
|---|---|
| `SessionAgent.Agent.AgentLoop` (one-turn state machine) | **Shared** |
| `SessionAgent.LLM.Provider` family + 4 concretes | **Shared** |
| `SessionAgent.Tool.Base` + `SessionAgent.Tool.Registry` | **Shared** (base classes) |
| `SessionAgent.Tool.Inspection.*` (13 tools) | Distinct to Inspection |
| `SessionAgent.Tool.Search.*` (8-9 tools) | Distinct to Search |
| `SessionAgent.Chat.History` schema | **Shared schema, distinct keying** — Inspection: `(agentName, irisSessionId, portalUser)`; Search: `(agentName, searchSessionKey, portalUser)` where searchSessionKey is registry GUID |
| `SessionAgent.Config.Agent` | **Shared schema, two rows** |
| `SessionAgent.Audit.{LlmCall, ToolCall}` | **Shared** |
| `SessionAgent.Security.ReadOnlyRole` (RBAC) | **Shared** |
| Markdown rendering bundle | **Shared** |
| `SessionAgent.EnsPortal.*` portal subclasses | **Distinct** (one per agent) |

### LLM Provider Abstraction

- Canonical wire shape = **Anthropic Messages API** (most structured). OpenAI / Gemini / Ollama-or-vLLM are mechanical adapters via `MessageAdapter` + `ToolDefAdapter`.
- **Implementation priority order** (per user): OpenAI first → Anthropic second → Gemini third → OpenAI-compat (Ollama/vLLM) free-ride.
- Tool-calling reliability ranking (BFCL V4 + community signal): Claude Opus 4.7 / Sonnet 4.5 ≥ GPT-5 / GPT-4o > Gemini 2.5/3 Pro (Flash erratic) > Qwen 2.5 32B+ > smaller OSS (expect occasional malformed JSON args).
- Anthropic prompt-caching: cached prefix = `system + tools`; user vocabulary digest **must NOT** ride in cached prefix (would shred cache hit rate); inject as first-user-message prefix instead.

### Tool Dispatch Contract (MCP-Exportable)

- Pure: `(toolName, jsonArgs) → jsonResult` with no `%session`, no `%request`, no Zen state, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no ObjectScript exceptions as error signals.
- Tool errors return structured `{isError: true, content: [{type: "text", text: "..."}]}` per MCP `tools/call` envelope.
- Each tool: `Parameter ToolName`, `Parameter Description`, `Parameter MutatesState As %Boolean = 0`, `ClassMethod GetInputSchema()`, `ClassMethod Invoke(pCallerCtx, pJsonArgs, Output pResult)`.

### Search-Agent Specifics

- **8 indexed access paths on `Ens.MessageHeader`** (verified from `irislib/Ens/MessageHeader.cls`): Extent (bitmap), TimeCreated (standard), Status (bitmap), SourceConfigName (bitmap), TargetConfigName (bitmap), SessionId (standard), MessageBodyClassName (bitmap), MessageBodyId (standard). Plus `%ID` IDKEY.
- **NOT indexed by default** (must NOT lead WHERE with these): IsError, Type, CorrespondingMessageId, TimeProcessed, Priority, Description.
- **Body-field search** via `Ens.SearchTableBase` SearchTable subclasses (e.g., `EnsLib.HL7.SearchTable`); join on `MessageBodyId`.
- **Body-content search beyond SearchTable** via two-stage pattern: narrow by indexed columns to small candidate set (≤50), then `InspectBodyCandidates(ids[], pattern)` opens each body via inspection-agent's dispatch ladder.
- **L3 bounded-WHERE invariant**: every search SQL must lead with at least one indexed column AND include a default 24-hour `TimeCreated` window (max 720h / 30d). NO "search forever" mode.
- **Vocabulary keyed `(PortalUser, MessageBodyClass, Alias)`** with `MessageBodyClass=""` for class-agnostic. Confidence formula `Success / (Success + Failure + 1)` smoothed.
- **Digest assembly** at first turn: top 20 user rows with `Confidence ≥ 0.3`, fall back to `NamespaceVocabulary` baseline (v1.5), fall back to `SeedVocabulary` (~10 ship-with templates). Cap at ~1,200 tokens. Uncached prefix of first user message.

### Operational

- **Web Gateway "Server Response Timeout"** default 60s is the LLM-call cliff (NOT `%session.AppTimeout`). Raise to 300s as operator README prerequisite. Per-call provider timeout cap 90s.
- **HSCUSTOMCODE database** + package mapping to target namespaces. Standard HealthShare pattern.
- **CSP integration** via ZenMethod hyperevent → `SessionAgent.Agent.AgentLoop.RunTurn(...)` → tool dispatch. Concurrent operator tabs serialize via `%OpenId(id, 4)` exclusive lock on `SessionAgent.Chat.History` row.

## Tool Catalog (Inspection Agent — 13 tools, content carries from original brief)

| # | Tool | Kind | Purpose |
|---|---|---|---|
| 1 | `session_summary` | SQL | Shape, duration, error count, root message class |
| 2 | `session_timeline` | SQL | UNION ALL of MessageHeader + Util.Log + Rule.Log, ordered |
| 3 | `message_headers` | SQL | All messages in session with decoded status/type/invocation |
| 4 | `event_log` | SQL | Filterable by session, message, min severity |
| 5 | `rule_log` | SQL | Rule evaluations with reason, return value, component, currentHeaderId |
| 6 | `find_related_sessions` | SQL | Cross-instance sessions via `Ens.SuperSessionIndex` |
| 7 | `find_sessions_by_body` | SQL | Sessions by indexed body fields via SearchTable pivot |
| 8 | `get_message_body` | Method | Runtime dispatch ladder: `%JSON.Adaptor` → VDoc → `%Stream.Object` → generic |
| 9 | `get_message_detail` | Method | Combined header + body summary + related log entries |
| 10 | `get_business_process_source` | Method | `%Dictionary.ClassDefinition` + `MethodDefinition.Implementation` stream; BPL via `XDataDefinition` |
| 11 | `get_business_process_instance` | Method | BP persistent instance row + `Ens.BP.Context` + `Ens.BP.Thread` state |
| 12 | `list_business_process_methods` | SQL | Enumerate methods on any class via `%Dictionary.MethodDefinition` |
| 13 | `explain_error` | Method | Decode `%Status`; recognizes `<Ens>ErrBPTerm`, `<PROTECT>`, `<UNDEFINED>`, etc. |

## Tool Catalog (Search Agent — 8 indexed-access tools + 1 body-inspection + 1 vocab utility)

| # | Tool | Lead index | Purpose |
|---|---|---|---|
| 1 | `search_by_time` | TimeCreated | Recent-messages listing |
| 2 | `search_by_status` | Status | Filter by status (Error, Completed, etc.) |
| 3 | `search_by_source` | SourceConfigName | Filter by source business host |
| 4 | `search_by_target` | TargetConfigName | Filter by target business host |
| 5 | `search_by_message_class` | MessageBodyClassName | Filter by message class |
| 6 | `search_by_session` | SessionId | Drill into session |
| 7 | `search_by_body_field` | MessageBodyId + SearchTable | Indexed body-field search (patient-id, MRN, order #) |
| 8 | `search_by_supersession` | Ens.SuperSessionIndex | Cross-instance trace lookup |
| 9 (new) | `inspect_body_candidates` | Two-stage narrow + body-open | Body-content search beyond SearchTable, bounded candidate set |
| 10 (utility) | `vocab_lookup` | n/a | Retrieve a saved alias from `UserVocabulary` long tail |

## Rejected Decisions (Do Not Re-Propose)

| Idea | Rejected because |
|---|---|
| Embedded Python in runtime | Pure ObjectScript per user direction; sidesteps NFR-M9 install-break risk |
| Build on AI Hub primitives | EAP, not in 2024.1; would gate adoption to ~0% of installed base today |
| `Custom.EnsPortal.*` for portal subclasses | User chose single-package consistency; all classes under `SessionAgent.*` |
| `App.*` placeholder package | Generic, collides with anyone else's `App.*`; replaced with `SessionAgent.*` |
| MCP serving in this project | Belongs to sibling `iris-execute-mcp-v2`; cleaner separation of concerns |
| Topic 10 Option A — chat as `Ens.MessageHeader` rows | Pollutes Visual Trace timeline with chat clutter; one-way door |
| Wallet-based secrets | `%Library.IRISWallet` doesn't exist in 2024.1 |
| `%NOLOCK` on agent SELECTs | DML-only hint in IRIS SQL; ignored on SELECT; SELECTs non-blocking by default |
| Daily rotation of search-session GUID | Too aggressive; operators may revisit search across portal-session pause |
| Cross-namespace single conversation | `$NAMESPACE` switching forbidden in CSP context per project rule |
| Anthropic-canonical tool args as stringified JSON | Anthropic shape is object; OpenAI is the outlier (stringifies) |
| LLM-extracted vocabulary aliases in v1 | PHI leakage risk; defer to v1.5 with regex scrub |

## Task-0 Probes Carried Forward to Implementation

Per project's `research-first.md` rule 4 — execute on a live 2024.1 instance **before** dispatching the implementation story they unblock:

1. `%Dictionary.MethodDefinition.%OpenId("Ens.BusinessProcess||OnRequest")` returns non-null on 2024.1 (unblocks Epic 3, tool registry generation).
2. Embedded SQL `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId)='...')` produces SQLCODE=0 / SQLCODE=100 semantics on 2024.1 (unblocks Epic 11, purge sweep).
3. Web Gateway "Server Response Timeout" default value verbatim from operator's gateway version (unblocks Epic 1, README content).
4. `Ens.SearchTableBase` SearchTable subclass row shape on operator's instance (unblocks Epic 13 search, `search_by_body_field`).
5. `SynthesizeAlias` deterministic stringification unit test against ~10 reordering scenarios (unblocks Epic 14, vocabulary capture).
6. `%OnAfterSave` non-recursion verification on 2024.1 (unblocks Epic 12, vocabulary persistence with `Confidence` recompute trigger).

## Open Questions for PRD

- **License**: MIT (locked in 2026-05-02). `LICENSE` file lands at repo root in v1 release commit.
- **PHI redaction policy**: namespace segregation is v1 boundary; if operator has PHI in nominally-non-PHI namespace, body-redaction layer post-v1.
- **Multi-tab UX**: cross-row locking validated; operator-facing UX guidance for two browser tabs same operator (different agents) unwritten.
- **Search agent's chat history visible to inspection agent on hand-off?**: currently URL-parameter context-pass with a "from search" hint stripe; richer transcript-pass deferred.
- **Cross-tab vocabulary contamination across namespaces**: `UserVocabulary` PK might need Namespace; defer until observed.
- **Streaming responses**: v1 stays blocking; SSE / async-poll is v1.5 question.
- **`Ens.Config.Credentials` requires Ensemble enabled** in the namespace — true for HSCUSTOM and any Interop NS. Verify before non-Interop deployments.

## Related Project Context (Saved Memories)

Foundational facts that downstream PRD/architecture/stories should treat as load-bearing:

- `project_implementation_language.md` — pure ObjectScript only, no embedded Python in runtime
- `project_iris_version_floor.md` — IRIS 2024.1+ floor, every API verified
- `project_full_v1_scope.md` — two agents, four providers, per-agent Zen config, lifecycle coupling, IPM-installable
- `project_v1_scope_boundaries.md` — Phase 1 REPL out, MCP serving in sibling project, tool registry stays MCP-exportable
- `project_package_naming.md` — `SessionAgent.*` for ALL classes including portal subclasses; `%SessionAgent_ReadOnly` RBAC role
- `project_search_agent_body_search_refinement.md` — body-content search via two-stage indexed-prefilter + body-inspection; vocabulary keys gain nullable `MessageBodyClass`
- `project_product_posture.md` — hobby project, single author, OSS day one, hackathon origin only, no commercial motion, success metrics, downplay AI-Hub framing, elevator pitch

All located at `~/.claude/projects/c--git-iris-session-agent/memory/`.

## Companion Documents

- [`product-brief-iris-session-agent.md`](product-brief-iris-session-agent.md) — the executive brief
- [`research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md`](research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) — full Inspection Agent architecture (~13,000 words, 6 steps, workflowComplete)
- [`research/technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md`](research/technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md) — full Search Agent architecture (~9,000 words, 6 steps, workflowComplete)
- [`research/cleanup-edit-proposal-2026-05-02.md`](research/cleanup-edit-proposal-2026-05-02.md) — applied; both 2026-04-24 AI-Hub-coupled docs annotated with supersession callouts
- [`docs/initial-prompt.md`](../../docs/initial-prompt.md) — author's authoritative scope spec
