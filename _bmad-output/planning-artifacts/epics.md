---
stepsCompleted: ["step-01-validate-prerequisites", "step-02-design-epics", "step-03-create-stories", "step-04-final-validation"]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
project: iris-session-agent
author: Joshua Brandt
date: 2026-05-02
status: complete
completedAt: 2026-05-02
totalEpics: 10
totalStories: 64
storyDistribution:
  epic-1-foundation: 7
  epic-2-backend-plumbing: 12
  epic-3-ui-mvp-demo: 7
  epic-4-full-tool-catalogue: 7
  epic-5-multi-provider: 4
  epic-6-config-ui: 3
  epic-7-inspection-lifecycle: 3
  epic-8-search-foundation: 7
  epic-9-vocabulary-learning: 5
  epic-10-search-ui-handoff-ttl: 9
epicNumberingNote: "This document is the authoritative epic numbering for v1 implementation. Epic numbers in the PRD, Architecture, and UX Design Specification are aligned with this numbering. Epic numbers in the brief, distillate, and research docs reflect the architect's original 18-step pre-consolidation sequence (preserved as planning history); see §'Mapping to Architecture's Original 18-Epic Sequence' below."
revisions:
  - date: 2026-05-02
    by: "bmad-create-epics-and-stories Step 4 (final validation)"
    summary: "Applied 3 forward-reference fixes (D1: SearchTable Task-0 probe re-anchored from Story 8.1 to Story 4.6 — first cross-codebase consumer; D2: Story 8.1 UserVocabulary.Confidence property doc reworded to remove forward reference to Story 9.x trigger; D3: Story 8.7 vocab_lookup mode='save' implements basic RecordSuccess inline, Story 9.2 enriches with recursion-safe %OnAfterSave per same incremental-enhancement pattern as Story 1.5 → Stories 7.2/10.6). Updated AR13 carry-forward probes table with new probe-to-story anchoring."
---

# iris-session-agent - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for `iris-session-agent`, decomposing the requirements from the [PRD](prd.md), [Architecture](architecture.md), and [UX Design Specification](ux-design-specification.md) into implementable stories.

The 10 v1 epics below consolidate the architect's original 18-step implementation sequence into user-value-first epics — each epic delivers a meaningful operator outcome and stands alone (later epics build on it; earlier epics don't depend on later ones). The architect's 18-step ordering is preserved as story sequence within each consolidated epic; see §"Mapping to Architecture's Original 18-Epic Sequence" for the bidirectional reference.

## Requirements Inventory

### Functional Requirements

**Session Inspection (FR1–FR12)**

- **FR1**: Operator can open a chat panel from a custom subclass of the IRIS Visual Trace page, scoped to the currently-displayed Ensemble session.
- **FR2**: Operator can ask the Inspection Agent any natural-language question about the displayed session and receive a coherent answer that draws on multiple data surfaces.
- **FR3**: Inspection Agent can read message-header data for any session (call graph, configuration hosts, statuses, timing, error markers).
- **FR4**: Inspection Agent can open and render any message body via a runtime dispatch ladder accommodating `%JSON.Adaptor`, virtual document, `%Stream.Object`, and generic `%Persistent` body shapes.
- **FR5**: Inspection Agent can read the event log, filterable by session, message, and minimum severity.
- **FR6**: Inspection Agent can read the rule log to explain routing-rule decisions including return value, evaluated rule, component, and triggering message.
- **FR7**: Inspection Agent can read business-process runtime state for any BPL or custom subclass session, including the BP class source, persistent instance row, and `Ens.BP.Context` / `Ens.BP.Thread` state.
- **FR8**: Inspection Agent can find sessions related to the current session via `Ens.SuperSessionIndex` (cross-instance trace).
- **FR9**: Inspection Agent can find other sessions involving a specific indexed body field (`Ens.SearchTableBase` pivot).
- **FR10**: Inspection Agent can decode any `%Status` value into a human-readable explanation, including IRIS-specific error codes (`<Ens>ErrBPTerm`, `<PROTECT>`, `<UNDEFINED>`).
- **FR11**: Inspection Agent can ground every claim in its answer with a citation back to the underlying tool result, allowing the operator to verify by clicking through.
- **FR12**: Inspection Agent's chat history is preserved against the Ensemble session, so a subsequent operator opening the same session sees prior conversation.

**Message Search (FR13–FR24)**

- **FR13**: Operator can open a chat panel from a custom subclass of the IRIS Message Viewer page.
- **FR14**: Operator can ask the Search Agent any natural-language query and receive a curated short-list of sessions matching the request.
- **FR15**: Search Agent can search by indexed columns of `Ens.MessageHeader`: time created, status, source config name, target config name, message body class name, session id.
- **FR16**: Search Agent can search by indexed body fields via `Ens.SearchTableBase` subclass joins on `MessageBodyId`.
- **FR17**: Search Agent can search by cross-instance super-session via `Ens.SuperSessionIndex`.
- **FR18**: Search Agent can perform body-content search beyond indexed columns by narrowing to a bounded candidate set (≤50) using indexed prefilter, then opening each candidate body via the inspection-agent's body dispatch ladder.
- **FR19**: Search Agent enforces a bounded-WHERE invariant on every query — every search SQL must lead with at least one indexed column AND include a default 24h `TimeCreated` window (max 720h / 30d). No "search forever" mode.
- **FR20**: Operator can click a session in a Search Agent result to navigate into the Inspection Agent for that session, with conversation context (the search that produced the click) carried forward.
- **FR21**: Operator can save a query alias for personal future use; the Search Agent will recognize the alias on subsequent queries with elevated confidence.
- **FR22**: Search Agent learns vocabulary aliases per-user, per-message-body-class, automatically capturing successful query→click-through associations with confidence smoothing (`Success / (Success + Failure + 1)`).
- **FR23**: Search Agent ships with seed vocabulary entries (~10 templates covering common HL7 idioms) usable on first query before user-specific vocabulary is learned.
- **FR24**: Search Agent injects user vocabulary as a digest into the first user message of each conversation (top 20 user rows with confidence ≥ 0.3, capped ~1,200 tokens), preserving Anthropic prompt-cache hit rate by not modifying the cached `system + tools` prefix.

**LLM Provider Framework (FR25–FR30)**

- **FR25**: System can dispatch agent turns through any of four bundled LLM providers: OpenAI, Anthropic, Google Gemini, OpenAI-compatible (Ollama / vLLM / any compatible endpoint).
- **FR26**: Operator-Admin can configure each agent independently to use any bundled provider with its own model selection, max-tokens, temperature, and system-prompt override.
- **FR27**: System represents tool-calling traffic in an Anthropic-canonical wire shape internally; per-provider adapters mechanically convert to/from each provider's native shape.
- **FR28**: Community Contributor can add a fifth (or further) LLM provider by implementing one new subclass of `SessionAgent.LLM.Provider` (with `MessageAdapter` and `ToolDefAdapter`) plus one entry in the registry, with no edits required to shared infrastructure (`AgentLoop`, `ToolRegistry`, `Tool.Inspection.*`, `Tool.Search.*`).
- **FR29**: System enforces a per-call LLM provider timeout cap of 90s; timeouts surface as audit-loggable error events.
- **FR30**: System uses Anthropic prompt-caching of the `system + tools` prefix when the active provider supports prompt caching; user-specific vocabulary digests are placed outside the cached prefix to preserve cache hit rate.

**Read-Only Enforcement & Audit (FR31–FR37)**

- **FR31**: System enforces read-only access to `Ens.*` data through three independent layers: code discipline (no mutation calls in tool implementations), dispatch policy gate (`MutatesState=0` check on every tool dispatch), and IRIS RBAC role `SessionAgent_ReadOnly` (SELECT-only grants).
- **FR32**: System logs every LLM round-trip to a persistent audit class (`SessionAgent.Audit.LlmCall`) including provider, model, message count, token counts, latency, and conversation reference.
- **FR33**: System logs every tool dispatch to a persistent audit class (`SessionAgent.Audit.ToolCall`) including tool name, arguments, result/error, latency, and conversation reference.
- **FR34**: Audit rows are foreign-key linked to the chat-history row that contained the round-trip / dispatch.
- **FR35**: Operator-Admin can review audit rows via standard IRIS SQL access (no separate audit UI ships in v1).
- **FR36**: Tool implementations cannot mutate `Ens.*` state; any tool that attempts mutation is rejected by the dispatch policy gate before execution.
- **FR37**: Tool implementations return errors as structured `{isError: true, content: [{type: "text", text: "..."}]}` envelopes, not as ObjectScript exceptions.

**Configuration & Credentials (FR38–FR42)**

- **FR38**: Operator-Admin can configure per-agent settings via a dedicated Zen page (`SessionAgent.UI.AgentConfig`).
- **FR39**: System supports independent configuration for each of the two agents (different provider / model / temperature / system-prompt / credential-ref per agent).
- **FR40**: System resolves LLM provider API keys via a documented ladder: environment variable (`$SYSTEM.Util.GetEnviron`) preferred → `Ens.Config.Credentials` named entry → custom encrypted persistent store (`$System.Encryption.AESGCMEncrypt`) as last resort.
- **FR41**: System never persists API keys in agent configuration rows; configuration stores credential *references* only.
- **FR42**: Operator-Admin can set the maximum response token cap, temperature, and a custom system-prompt override per agent.

**Chat Lifecycle (FR43–FR47)**

- **FR43**: Inspection Agent chat history is keyed on `(agentName, irisSessionId, portalUser)`; Search Agent chat history is keyed on `(agentName, searchSessionKey, portalUser)` where `searchSessionKey` is a registry-assigned GUID.
- **FR44**: System provides a daily sweep task that removes Inspection Agent chat-history rows whose underlying `Ens.MessageHeader` session has been purged via `Ens.MessageHeader.Purge()` (no orphan history).
- **FR45**: System provides a TTL-based sweep task for Search Agent chat history (default 30 days, configurable).
- **FR46**: Two browser tabs for the same operator targeting the same chat-history row serialize their turns via an exclusive lock (`%OpenId(id, 4)`); concurrent turns do not corrupt history.
- **FR47**: Operator who arrives at the Inspection Agent via a Search Agent click-through sees a "from search" context indicator and can ask follow-up questions that build on the search context.

**Installation & Operator Surface (FR48–FR54)**

- **FR48**: Operator-Admin can install the entire product via a single command: `zpm install iris-session-agent` against any IRIS / IRIS for Health 2024.1+ instance.
- **FR49**: Installation succeeds on IRIS instances regardless of embedded Python availability (no `[Language = python]` in any shipped class, no Python at install or runtime).
- **FR50**: Installation creates the `SessionAgent_ReadOnly` RBAC role with SELECT-only grants on `Ens.*` tables.
- **FR51**: Installation creates Mgmt Portal bookmarks for both agent surfaces (`/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen` and `/csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen`).
- **FR52**: README documents operator prerequisites as a structural section: Web Gateway "Server Response Timeout" raised from 60s → 300s, RBAC role grant, LLM provider API key supply (env-var or `Ens.Config.Credentials`).
- **FR53**: System ships with no transitive Open Exchange dependencies; everything required runs from the single `<Resource Name="SessionAgent.PKG"/>` resource.
- **FR54**: System ships with a vendored client-side Markdown rendering bundle (`marked`, `Prism.js`, `DOMPurify`) self-hosted at `/csp/static/iris-session-agent/`; no CDN dependency. (Growth-tier — MVP can use a simpler render path.)

**Developer Extensibility (FR55–FR59)**

- **FR55**: System exposes a tool registry with a pure dispatch contract: `(toolName, jsonArgs) → jsonResult` with no `%session.Data` reads, no `%request` reads, no Zen state coupling, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals.
- **FR56**: Every tool declares: `Parameter ToolName`, `Parameter Description`, `Parameter MutatesState As %Boolean = 0`, `ClassMethod GetInputSchema()`, `ClassMethod Invoke(pCallerCtx, pJsonArgs, Output pResult)`.
- **FR57**: MCP Consumer can introspect the tool registry to enumerate available tools with their JSON schemas, and dispatch any tool by name with a JSON arguments payload — without `iris-session-agent` itself shipping MCP transport.
- **FR58**: Community Contributor can subclass `SessionAgent.Tool.Base` to add custom tools; v1 ships with built-in tools only and **public-API stability of the Tool plugin contract is post-v1**.
- **FR59**: System ships a tool-call-roundtrip integration test that exercises every bundled provider against every bundled tool, validating the agent loop, adapter conversions, and dispatch policy gate.

### NonFunctional Requirements

**Performance (NFR-P1–P6)**

- **NFR-P1 (LLM call cliff)**: Each LLM call completes within 90s or surfaces as a structured timeout error, sitting *below* the 300s Web Gateway timeout. Test: integration test forces a 91s mock provider response; agent returns structured timeout-error envelope.
- **NFR-P2 (Search-agent query bound)**: Every Search Agent SQL query completes within the 90s LLM-call budget against an `Ens.MessageHeader` extent of ≥ 1,000,000 rows when the bounded-WHERE invariant (FR19) holds. Test: synthetic-1M-row benchmark in CI gates Growth-tier ship.
- **NFR-P3 (Two-stage body search bound)**: Body-content search (FR18) opens at most 50 candidate bodies per query and completes inspection within the 90s cap on operator-grade hardware. Test: synthetic-extent benchmark validates 50-body inspection latency.
- **NFR-P4 (Concurrent-tab serialization)**: Two browser tabs of the same operator targeting the same chat-history row do not corrupt history under concurrent submit. Test: integration test fires two simultaneous submit requests; both turns complete via the `%OpenId(id, 4)` lock or one is rejected with a structured "another turn is in progress" error.
- **NFR-P5 (Time-to-resolution)**: On the curated set of common diagnostic patterns, the agent's response replaces 5 minutes of operator tab-switching with ≤ 1 minute of conversation. Test: operator self-report during pilot (not CI-measurable).
- **NFR-P6 (Anthropic prompt-cache hit rate)**: For providers with prompt caching enabled, the `system + tools` prefix is stable across consecutive turns; user vocabulary digest is in the *non-cached* user-message segment. Test: integration test asserts cache-control breakpoint placement; cache-hit metric in audit row.

**Security (NFR-S1–S6)**

- **NFR-S1 (Read-only invariant)**: No code path inside the agent can mutate `Ens.*` data. Three independent layers (FR31). Test: (1) static — `MutatesState=0` declared on every `SessionAgent.Tool.*`; (2) runtime — dispatch policy gate rejects `MutatesState=1`; (3) RBAC — installation creates `SessionAgent_ReadOnly` SELECT-only, validated by attempting a `DELETE`.
- **NFR-S2 (Credential confinement)**: API keys never persisted in `SessionAgent.Config.Agent` rows (FR41). Test: schema-level — `Config.Agent` has no `ApiKey` property, only `CredentialRef`.
- **NFR-S3 (Credential resolution hygiene)**: API key resolution uses the documented ladder (FR40), never logs the resolved key value, never embeds the key in audit-log rows. Test: audit-log row inspection; redaction unit test for credential-string detection.
- **NFR-S4 (Audit completeness)**: Every LLM round-trip and every tool dispatch logged (FR32–34). 100% completeness — no skipped paths. Test: integration test compares `count(SessionAgent.Audit.LlmCall)` and `count(SessionAgent.Audit.ToolCall)` against agent-loop instrumentation counts; equality required.
- **NFR-S5 (Public-OSS posture)**: All planning artifacts authored knowing they will be publicly visible in the OSS repo. Test: documentation review gate (manual) before each release tag.
- **NFR-S6 (Tool dispatch purity)**: Tool implementations cannot read `%session.Data`, `%request`, Zen state, or `%CSP.Response`; cannot perform `$NAMESPACE` side effects; cannot signal errors via ObjectScript exceptions (FR55). Test: lint check on the `SessionAgent.Tool.*` package; tool-call-roundtrip integration test runs each tool in a clean dispatcher context.

**Reliability (NFR-R1–R5)**

- **NFR-R1 (Operator-deployment safety)**: Operator can deploy the package to a production namespace with confidence that it cannot break production data. Guaranteed by NFR-S1's three-layer enforcement.
- **NFR-R2 (Chat-history lifecycle integrity)**: When `Ens.MessageHeader.Purge()` removes session N, the daily sweep removes any orphaned `SessionAgent.Chat.History` rows for session N (FR44). No orphan accumulation. Test: integration test simulates 1,000 sessions inserted, conversations attached, purge run, sweep run; asserts zero orphans remain.
- **NFR-R3 (Search-history TTL)**: Search Agent chat history older than the configured TTL (default 30 days) is removed by sweep (FR45). Test: integration test fast-forwards system clock and validates sweep behavior.
- **NFR-R4 (Provider failure isolation)**: When the active LLM provider returns an error (timeout, rate limit, malformed response), the agent reports the failure as a tool-error envelope to the operator and does not corrupt chat history or audit log. Test: integration test injects each error class into a mock provider.
- **NFR-R5 (IPM idempotent reinstall)**: `zpm install iris-session-agent` is idempotent — repeated installs do not duplicate RBAC role grants, bookmark entries, or audit-log schema migrations. Test: install twice in CI, validate no duplicate side effects.

**Scalability (NFR-SC1–SC4)**

- **NFR-SC1 (Production extent scale)**: Search Agent queries remain bounded under NFR-P2 even on operator-grade IRIS instances with `Ens.MessageHeader` extents up to 10,000,000 rows. Test: synthetic-extent benchmark at 10M rows.
- **NFR-SC2 (Concurrent operator scale)**: Stock IRIS Web Gateway and CSP threading handle concurrent operators. Per-row chat-history serialization is per-operator-per-tab (FR46), not global.
- **NFR-SC3 (No cross-instance coordination)**: Mirror-replica or cross-instance coordination is **not** in v1. Each IRIS instance runs an independent agent.
- **NFR-SC4 (Audit-log volume)**: Audit log volume is bounded by chat-history sweep cascading. Sustained 24/7 operator usage stays within IRIS-default journal sizing on operator-grade hardware. Test: sustained-load benchmark.

**Compatibility & Portability (NFR-C1–C6)**

- **NFR-C1 (IRIS version floor)**: Product installs and runs on IRIS / IRIS for Health **2024.1+**. Every API/class/parameter referenced is verified available in 2024.1. Newer-version optimizations (`%Library.IRISWallet`, `%AI.*` primitives) explicitly excluded. Test: install + smoke-test on a clean 2024.1 instance gates each release.
- **NFR-C2 (Pure ObjectScript runtime)**: No `[Language = python]` method exists in any shipped class under `SessionAgent.*`. Build-time tooling and test fixtures may use Python; the runtime artifact does not. Test: static check — `grep -r "Language = python" src/SessionAgent/` returns zero matches; CI fails if matched.
- **NFR-C3 (Python-less install success)**: `zpm install iris-session-agent` succeeds on IRIS instances with embedded Python disabled or unavailable (FR49). Test: release-gate CI on a Python-less IRIS image when image becomes available; manual verification on a Python-less instance until then.
- **NFR-C4 (No transitive dependencies)**: ZPM module has zero transitive Open Exchange dependencies (FR53). Test: `module.xml` dependency review — single `<Resource>` element; no `<Dependency>` elements other than IRIS / Ensemble core.
- **NFR-C5 (No CDN / offline-installable)**: All client-side assets self-hosted at `/csp/static/iris-session-agent/`. No CDN fetches at runtime. Operators behind air-gapped firewalls can install and run. Test: static check — no `https://cdn.*` references in shipped CSP files.
- **NFR-C6 (Browser support)**: Operator-facing chat UI works in evergreen browsers (latest two versions of Chrome, Firefox, Safari, Edge). No legacy IE support. Test: README documents support matrix; manual smoke test per release.

**Operability & Maintainability (NFR-O1–O5)**

- **NFR-O1 (Operator self-service install)**: Operator can install, configure, and verify the product in under 30 minutes without contacting the maintainer. Test: Journey 3 (Aishah's 18-minute walkthrough) is the lower bound.
- **NFR-O2 (Hot config change)**: Operator-Admin can change LLM provider, model, temperature, or system prompt and see the change effective on the next agent turn without restarting IRIS. Test: integration test verifies config-row read on each turn.
- **NFR-O3 (Audit log review by SQL)**: Operator-Admin can answer all audit questions via standard IRIS SQL against `SessionAgent.Audit.*` (FR35). No separate audit UI ships in v1.
- **NFR-O4 (Single-maintainer triage)**: Issues, PRs, and security reports surface through standard GitHub workflows. The maintainer triages within timelines compatible with hobby-project velocity (no SLA committed). MIT license + IPM version-pinning let operators run their installed version indefinitely if maintenance pauses.
- **NFR-O5 (Documentation deliverables on every release)**: README, PRD, architecture document, per-tool inline doc comments, and the brief / distillate / research planning artifacts are kept current with each release tag. Test: release-gate manual review.

**Accessibility (NFR-A1)**

- **NFR-A1 (Inherited Mgmt Portal accessibility)**: Agent UI is embedded as Zen pages subclassed from `EnsPortal.VisualTrace` and `EnsPortal.MessageViewer`. The chat panel inherits whatever accessibility characteristics the IRIS Mgmt Portal's Zen framework provides. **No additional accessibility commitments** beyond inherited behavior.

**Categories Deliberately Excluded** (per PRD §"Categories Deliberately Excluded"): Localization/i18n; compliance certifications (SOC2, HIPAA, PCI-DSS, FedRAMP, ISO 27001); disaster recovery/backup commitments separate from IRIS journal; SLA.

### Additional Requirements

Architecture-derived requirements that shape epic structure and acceptance criteria but are not enumerated in the PRD's FR/NFR sections.

- **AR1 (No starter template)**: Hand-author from research-doc shape; first implementation story creates `module.xml` (33-line shape from research lines 957–993) + `LICENSE` (MIT) + `README.md` + `.gitignore` + `src/SessionAgent/` skeleton + `src/static/` empty target. Source: Architecture §"Selected Starter: None".
- **AR2 (ZPM module.xml shape)**: Single `<Resource Name="SessionAgent.PKG"/>`; three idempotent `<Invoke>` install hooks (`SessionAgent.Installer.Install`, `SessionAgent.Audit.Emit.EnsureEvents`, `SessionAgent.Security.ReadOnlyRole.Install`); `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>`; dedicated unauthenticated `<CSPApplication Url="/csp/static/iris-session-agent" ... AuthenticationMethods="64"/>`. Source: Architecture §"Infrastructure & Deployment".
- **AR3 (HSCUSTOM distribution + dual bookmark patterns)**: Operator-controlled package mapping to interop namespaces (HealthShare convention); plain-IRIS Interop deployments document an alternative pattern; README shows BOTH bookmark URL patterns (`/csp/healthshare/<NS>/...zen` AND `/csp/<NS>/...zen`); installer prints both. Source: Architecture OD2/OD3.
- **AR4 (Three sweep tasks scheduled at install time)**: `SessionAgent.Task.PurgeOrphanedChatHistory` (daily 02:00 UTC, removes Inspection chat-history rows whose Ens session was purged via `Ens.MessageHeader.Purge()`); `SessionAgent.Task.PurgeStaleSearchChat` (daily 03:00 UTC, TTL 30d default — operator-tunable via `Config.Agent.SearchChatRetentionDays`); `SessionAgent.Task.UserVocabularyDecay` (Sunday 04:00 UTC, deletes `Confidence < 0.2 AND LastUsed > 90d`). All scheduled by `Installer.Install`. Source: Architecture §"Sweep tasks".
- **AR5 (Audit event pre-registration)**: `SessionAgent.Audit.Emit.EnsureEvents()` invoked at install time via `<Invoke>`; registers four event types in `%SYS` via `Security.Events.Create()` idempotently — `(SessionAgent, LlmCall, <provider>)`, `(SessionAgent, ToolCall, <tool_name>)`, `(SessionAgent, VocabWrite, clickthrough|explicit|extracted|seed)`, `(SessionAgent, TaskRun, <task_name>)`. Without pre-registration, `$System.Security.Audit(...)` silently returns 0. Source: Architecture §"Audit event triples" + project rule "Security.Events Pre-Registration for Audit".
- **AR6 (`SessionAgent_ReadOnly` RBAC role install)**: `SessionAgent.Security.ReadOnlyRole.Install()` via `<Invoke>`; idempotent SELECT-only grants on `Ens.*` tables; `Test/ReadOnlyRoleTest.cls` validates by attempting INSERT/DELETE → privilege failure. Source: Architecture + FR50.
- **AR7 (`SessionAgent.Util.RetryWithBackoff`)**: Full-jitter exponential backoff; `MaxAttempts=4`, `BaseDelaySec=1`, `MaxDelaySec=32`; non-retryable on 4xx (except 429); honor `Retry-After` (Anthropic/OpenAI) and `error.details[].retryDelay` (Gemini); never retry mid-flight network failures (no idempotency key documented across providers); surface mid-flight failures with `request-id` from response header. Source: Architecture §"API & Communication Patterns" + §"HTTP retry-after parsing".
- **AR8 (`SessionAgent.Util.EnvSecret` credential resolution)**: env-var (`$SYSTEM.Util.GetEnviron`) preferred → `Ens.Config.Credentials` named entry → AES-encrypted custom store (`$System.Encryption.AESGCMEncrypt`) as last resort; never log resolved key value; never embed key in audit-log rows; redaction unit test covers credential-string detection. Source: Architecture + FR40 + NFR-S3.
- **AR9 (`SessionAgent.Agent.AgentLoop` constants)**: `MaxIterationsPerTurn=10` (hitting cap appends synthetic "max-iterations reached, summarize" + break); `PerCallProviderTimeoutSec=90` (caught by agent + structured timeout-error envelope before 300s Web Gateway timeout fires). Source: Architecture OD5.
- **AR10 (Calibration constants as Class Parameter)**: `VocabularyDigest.MaxEntries=20`, `MinUserConfidence=0.3`; `UserVocabulary.DecayConfidenceThreshold=0.2`, `DecayLastUsedDays=90`; `Tool/Search/*` `DefaultTimeWindowHours=24`, `MaxTimeWindowHours=720` (30d), `BodyFieldDefaultHours=168` (7d) where applicable; `RetryWithBackoff.MaxAttempts=4`, `BaseDelaySec=1`, `MaxDelaySec=32`; `InspectBodyCandidates` candidate cap. All declared as `Class Parameter` so pilot tuning is cheap. Source: Architecture §"Calibration constants".
- **AR11 (Bounded-WHERE invariant test)**: `Test/BoundedWhereInvariantTest.cls` validates every `Tool/Search/*.cls` WHERE clause leads with ≥1 indexed column AND a `TimeCreated` window. CI fails any tool that violates. Source: Architecture + FR19.
- **AR12 (`Search/UserVocabulary` recursion-safe `%OnAfterSave`)**: Direct SQL UPDATE on the same row to recompute `Confidence` from `Success`/`Failure` counts; never call `%Save()` from within `%OnAfterSave` (would re-fire); Task-0 probe in Epic 9 verifies non-recursion on 2024.1. Source: Architecture §"Process Patterns" + project rule.
- **AR13 (Six carry-forward Task-0 probes)**: Required pre-flight for the corresponding epic story per `research-first.md` rule 4. Each probe lists *epics.md epic / architecture original epic*:
  - **Epic 1 / arch Epic 1**: Web Gateway "Server Response Timeout" verbatim default capture (Story 1.2).
  - **Epic 2 / arch Epic 3**: `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` returns non-null on 2024.1 (Story 2.10).
  - **Epic 4 / arch Epic 13**: `EnsLib.HL7.SearchTable` row shape `(DocId, PropName, PropValue)` on operator's instance (Story 4.6 — re-anchored from Epic 8 since `FindSessionsByBody` is the first cross-codebase consumer; Epic 8 Story 8.5 reuses the captured shape).
  - **Epic 7 / arch Epic 11**: `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId)='...')` SQLCODE=0/100 semantics on 2024.1 (Story 7.1).
  - **Epic 9 / arch Epic 12**: `%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1 (Story 9.1).
  - **Epic 9 / arch Epic 14**: `SynthesizeAlias` deterministic stringification unit test against ~10 reordering scenarios (Story 9.1).
- **AR14 (README operator-prerequisites as structural deliverable)**: Three concrete steps: (1) raise Web Gateway "Server Response Timeout" 60s → 300s with explanation, (2) grant `SessionAgent_ReadOnly` to operator user/role, (3) supply LLM provider API key via env-var (preferred for containers) or `Ens.Config.Credentials` (traditional installs); both bookmark URL patterns (HealthShare + plain IRIS); render-from-research-doc §"Operator README Content" for MVP. Source: FR52 + Aishah Journey 3.
- **AR15 (Operator quickstart and audit recipe docs)**: `docs/operator-quickstart.md` (Aishah Journey 3 walkthrough complementing README); `docs/audit-sql-recipes.md` (sample SQL queries against `SessionAgent.Audit.LlmCall` and `SessionAgent.Audit.ToolCall` for operator self-service audit per FR35 + NFR-O3); `docs/initial-prompt.md` (existing). Source: Architecture §"Project Directory Structure".
- **AR16 (Lightweight CI for v1)**: `.github/workflows/ci.yml` with markdown lint + structural checks; full `%UnitTest` gate added once Python-less 2024.1 community image lands; manual smoke-test per release tag is the v1 baseline. Source: Architecture OD1.
- **AR17 (ISO-8601 UTC timestamp standard)**: Every audit and chat timestamp uses `$Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"` (`$ZTimeStamp` UTC, never `$Horolog` local). Source: Architecture §"Format Patterns" + project rule.
- **AR18 (SQL case-sensitivity)**: `%EXACT()` wrap on every string equality predicate AND every string projection (e.g., `WHERE %EXACT(SessionId)=?`, `SELECT %EXACT(SourceConfigName) ...`); applies to all IRIS SQL inside `Tool/*` and elsewhere. Source: Architecture + project rule.
- **AR19 (Vocabulary persistence shape)**: `SessionAgent.Search.UserVocabulary` keyed `(PortalUser, Alias)` (Namespace-key deferred per research open-question 2); `SessionAgent.Search.SeedVocabulary` ships ~10 templates seeded by Installer (HL7 idioms); `SessionAgent.Search.NamespaceVocabulary` schema ships in v1 but population logic deferred to v1.5. Source: Architecture §"Data Architecture" + FR23.
- **AR20 (Tool-call-roundtrip integration test)**: `Test/ToolCallRoundtripIntegrationTest.cls` exercises every bundled provider × every bundled tool against canned mock; runs on every release; validates agent loop, adapter conversions, dispatch policy gate, and pure-tool-dispatch contract. Source: FR59 + NFR-S6 + Architecture.

### UX Design Requirements

UX requirements are first-class inputs from the [UX Design Specification](ux-design-specification.md) §"Component Strategy" and §"Implementation Roadmap". Each UX-DR is specific enough to seed a story with testable acceptance criteria.

- **UX-DR1 (`sa-chat-panel` container)**: Top-level wrapper hosting the entire chat experience inside a Zen page tab. Auto-focus input on mount; auto-scroll transcript to most recent unless operator scrolled up; semantic `<section role="region" aria-label="Agent chat panel">`; orchestrates state transitions (empty / active / mid-turn / locked / config-required).
- **UX-DR2 (`sa-message-block` component, four variants)**: `sa-msg-operator` / `sa-msg-agent` / `sa-msg-agent sa-msg-error` / `sa-msg-agent sa-msg-search-result`; attribution prefix `**You** —` / `**Agent** —` (body weight, inline at start of first paragraph); `--sa-message-operator-bg` / `--sa-message-agent-bg` background tints; 8px vertical / 12px horizontal padding, 12px bottom margin; `<div role="article">`.
- **UX-DR3 (`sa-tool-call-card` component)**: Single tool dispatch status/name/result; default-collapsed via native `<details>`/`<summary>`; states (running pulsing / complete static check / error red ×); status indicator + monospace tool name + one-line summary on completion; expanded view shows tool input args + JSON result as code blocks (max 320px before internal scroll); single-pixel border in `--sa-tool-card-border`.
- **UX-DR4 (`sa-citation-chip` component, six variants — load-bearing trust mechanism)**: Bracketed inline `<a>` element with onclick handler; variants `sa-cite-rule`, `sa-cite-event`, `sa-cite-message`, `sa-cite-ack`, `sa-cite-iolog`, `sa-cite-tool`; click invokes `ClientMethod onCitationClick(type, id, klass)` on `SessionAgent.EnsPortal.VisualTrace` which wraps parent's `zenPage.svgPage.selectItem(...)` / `zenPage.updateTabs(true)` API; off-page items get partial sync in MVP (Header tab updates, SVG highlight doesn't); descriptive `aria-label`.
- **UX-DR5 (`sa-from-search-stripe` component)**: Single-line context indicator at top of Inspection chat after Search hand-off; three exits — Accept (explicit) / × Dismiss / implicit-accept (operator typing new message); 32px height, 3px left-edge accent via `--sa-from-search-stripe-border`, subtle tint via `--sa-from-search-stripe-bg`; `role="status" aria-live="polite"`; quotes operator's literal search query text (not LLM-rephrased); shows once per chat session, doesn't reappear.
- **UX-DR6 (`sa-status-text` component)**: Italic de-emphasized mid-flight indicator (*"Thinking..."*, *"Checking message headers..."*); 24px line height; `aria-live="polite"`; replaced by tool-call cards as they appear; only one feedback element active at a time (no coexistence with tool cards or final answer).
- **UX-DR7 (`sa-config-empty-prompt` component)**: Inline prompt when no provider configured; two variants — operator-admin sees link to `SessionAgent.UI.AgentConfig.zen`, non-admin sees text-only "Ask your operator-admin"; `role="alert"`; replaces transcript with input disabled.
- **UX-DR8 (`sa-concurrent-tab-banner` component)**: Non-modal informational banner shown when other tab holds `%OpenId(id, 4)` lock; 40-48px height, parent's warning/notice color; `role="alert" aria-live="assertive"`; auto-dismisses on lock release; input field disabled while shown.
- **UX-DR9 (`sa-search-result-entry` component)**: Single clickable session entry inside Search Agent's curated session list; columns SessionId · TimeCreated · Source/Target · MessageBodyClassName · Status · brief context; whole row is real `<a>` or `<button>` with `aria-label` summarizing row; click navigates to Visual Trace + opens Inspection chat tab + displays `sa-from-search-stripe`; vocabulary capture happens silently as side effect.
- **UX-DR10 (`sa-input-field` component)**: Auto-grow `<textarea>` (40px default → 80px max before internal scroll); placeholder text from agent context (Inspection: "Ask anything about this session"; Search: "Find sessions where..."); Enter→send (clears + refocuses); Shift+Enter→newline; Esc→cancel mid-flight; auto-focus on chat-tab open; disabled state with `aria-disabled="true"` plus visual de-emphasis during processing/lock/config-required.
- **UX-DR11 (`sa-config-form` Zen page at `SessionAgent.UI.AgentConfig.zen`)**: Operator-Admin per-agent config form; fields — Agent (Inspection/Search) · Provider (4 options) · Model (combobox provider-specific) · Max tokens · Temperature (0.0-2.0) · System prompt override (textarea, optional) · Credential reference (env-var name OR `Ens.Config.Credentials` named entry); Save/Cancel; hot config change (NFR-O2 — next agent turn picks it up without IRIS restart); native Zen `<vgroup>`/`<hgroup>` form layout matching `EnsPortal.Credentials.zen` conventions.
- **UX-DR12 (`--sa-*` design token system)**: Single `sessionagent-chat.css` at `/csp/static/iris-session-agent/`; chat-specific tokens (`--sa-message-operator-bg`, `--sa-message-agent-bg`, `--sa-tool-card-border`, `--sa-tool-card-status-running|complete|error`, `--sa-citation-chip-bg`, `--sa-citation-chip-text`, `--sa-status-text-color`, `--sa-from-search-stripe-bg`, `--sa-from-search-stripe-border`, `--sa-error-text-color`); semantic mapping resolves against parent `EnsPortal.Application.cls` palette; no hardcoded hex/rgba in component CSS.
- **UX-DR13 (Vendored client-side rendering bundle — Growth tier)**: `marked` ≥ 18.0.2 (CVE-2026-41680 fixed) + `Prism.js` core + curated languages (ObjectScript [custom grammar w/ markup fallback], JS, JSON, SQL, HL7 [custom grammar], XML) + `prism.min.css` low-contrast theme + `DOMPurify` 3.x; `chat-panel.js` ~50-line wrapper (marked → Prism → DOMPurify pipeline); served from `/csp/static/iris-session-agent/`; ~45 KB gzipped; no CDN; deployed via `<FileCopy>` in module.xml.
- **UX-DR14 (MVP-tier render fallback)**: When vendored bundle slips to Growth tier, MVP uses simpler render path (server-side `marked`-equivalent in ObjectScript or plain text with line-break handling). Trade-off accepted: no code-block syntax highlighting in MVP.
- **UX-DR15 ("Ask the agent" tab placement)**: Appended to *right* of existing parent tab strip in both `EnsPortal.VisualTrace` subclass and `EnsPortal.MessageViewer` subclass; same label across both pages so operators learn affordance once; existing tabs remain in their established positions for muscle memory.
- **UX-DR16 (Visible-progress feedback layer)**: Five feedback states across one full turn — send acknowledged (~50ms) / pre-tool-call thinking (0.5–1s) / tools in progress (varies, total typically 5–30s) / reasoning complete (~50ms after last tool) / verifiable (persistent). Rules: no generic spinner, no fake activity (no animated typing dots), no success toast, single feedback layer at a time.
- **UX-DR17 (Five distinct empty-state designs)**: First-time conversation (3-line agent welcome rendered as `sa-message-block sa-msg-agent`) / returning-conversation (transcript scrolled to most recent + "Continue the conversation" placeholder) / Search Agent first encounter (welcome + "Find sessions where..." placeholder) / no-results-from-search (agent explains + suggests refinements) / no-config (`sa-config-empty-prompt`). Rules: never blank panel, never "Coming soon" copy, welcome rendered as agent message-block (not separate splash), no tutorial overlays.
- **UX-DR18 (Graceful-degradation error patterns)**: Provider timeout (90s) shows error envelope in transcript with retry hint; provider network/rate-limit/auth error shows envelope with provider-named reason; tool errors continue with degraded context (failing tool card shows red ×, agent notes limitation in answer); concurrent-tab lock shows non-modal banner; no 500 pages, no full-panel-replacement error states; errors are operator-readable not stack traces (stack traces only in audit log).
- **UX-DR19 (Native HTML semantics across all components)**: Real `<a>` for citation chips and search-result entries (never `<span onclick>`); real `<button>` for actions; real `<textarea>` for input (never `<div contenteditable>`); native `<details>`/`<summary>` for tool-card expand/collapse (never JS-toggled visibility); semantic `<section>`, `<article>` for top-level structure.
- **UX-DR20 (ARIA discipline)**: `aria-live="polite"` on `sa-status-text` and most-recent-message wrapper; `role="alert" aria-live="assertive"` on `sa-config-empty-prompt` + `sa-concurrent-tab-banner`; `role="status" aria-live="polite"` on `sa-from-search-stripe`; `aria-disabled="true"` plus visual de-emphasis on disabled `sa-input-field`; `aria-busy="true"` on transcript during in-flight turn; descriptive `aria-label` on citation chips.
- **UX-DR21 (Color-not-sole-indicator)**: Tool-call card status uses both color AND text label (`Running...`, `Complete`, `Error: <reason>`); error envelopes use both color AND explicit text.
- **UX-DR22 (Manual cross-browser smoke-test posture)**: Per release, test on latest two versions of Chrome/Firefox/Safari/Edge; document support matrix in README; no automated accessibility test suite in v1; no responsive breakpoints (desktop-only NFR-C6); no mobile/tablet accommodations.
- **UX-DR23 (WCAG AA contrast verification)**: Resolved `--sa-*` token values meet 4.5:1 (body text) / 3:1 (large text and non-text content); static check during architecture work + re-check if Mgmt Portal palette changes.
- **UX-DR24 (Citation chip click → parent integration)**: On-page items call `svgPage.selectItem(null, type, svgId, id, klass, line)` (auto-updates current refs + triggers `updateTabs(true)` + highlights SVG box); off-page items set `zenPage.currentId/currentType/currentClass` directly + call `zenPage.updateTabs(true)` (Header re-renders; SVG highlight stays — accepted MVP partial sync); `sa-cite-tool` chips scroll-and-expand the corresponding tool-call card; full off-page sync via `zenPage.openPage(targetPage)` lands in Growth tier.
- **UX-DR25 ("From search" hand-off pattern)**: Three exits (Accept explicit / Dismiss / implicit-accept on operator typing new message); stripe shows once per chat session; doesn't reappear; quotes operator's literal search text (not LLM-rephrased); search → click-through silently captures vocabulary alias on `Search/UserVocabulary.RecordSuccess` with confidence smoothing; explicit save command remains as escape hatch.
- **UX-DR26 (Inherit-and-augment design system posture)**: IRIS Mgmt Portal Zen + `EnsPortal.Application` styling inherited as foundation; `--sa-*` tokens added only for chat-specific affordances; `sa-*` class prefix all components; no Material/Tailwind/Ant; never hardcode colors/fonts/sizing in component CSS; never customize parent stylesheet.
- **UX-DR27 (Phased UX implementation roadmap)**: MVP (Epic 6 demo-able) ships `sa-chat-panel`, `sa-message-block` (operator+agent only), `sa-tool-call-card`, `sa-citation-chip` (full deep-link integration via parent API, partial off-page sync), `sa-status-text`, `sa-input-field`, `sa-config-empty-prompt` (admin variant), `sa-config-form` (Inspection-only). Growth (completing v1) adds: full off-page citation sync via `openPage`, `sa-from-search-stripe`, `sa-concurrent-tab-banner`, `sa-search-result-entry`, error/search-result variants of `sa-message-block`, `sa-config-form` Search variant, vendored Markdown bundle, `--sa-*` token resolution against parent palette.
- **UX-DR28 (No-modals/no-overlays explicit non-pattern)**: No "Are you sure?" dialogs (read-only by structure); no hover tooltips; no popovers (hover citation preview is Vision-tier); no model-selection modal (config in Zen page); no "loading..." overlay (status text + tool cards handle progress in-line).
- **UX-DR29 (Bounded-WHERE search UX)**: Agent narrates limitations (≤50 results cap, time-window cap); offers actionable refinements (*"Try widening to 6h"* / *"Tighten the time window or specify a source/target"*); refuses unbounded queries gracefully (*"I can search up to 30 days back. Would you like to narrow the time window?"*); no pagination — result curation only.
- **UX-DR30 (Single-shot interaction primitives)**: Enter → send, Shift+Enter → newline, Esc → cancel mid-flight; auto-focus on tab open + after every send; no confirmation modals; no draft-saved indicators; no model-selection prompt per-turn; no "are you sure?" — read-only by structure means there's nothing to confirm.

### FR Coverage Map

Every FR mapped to its **primary** epic (the epic that completes its acceptance). FRs whose acceptance spans multiple epics are noted as such; the primary epic is the one where the operator-facing outcome lands.

**Session Inspection (FR1–FR12):**

- **FR1** (chat panel from Visual Trace subclass) → Epic 3
- **FR2** (operator asks question, gets coherent multi-surface answer) → Epic 3 *(backend AgentLoop in Epic 2)*
- **FR3** (read message-header data) → Epic 4 *(example tools in Epic 2)*
- **FR4** (body-class dispatch ladder) → Epic 4
- **FR5** (event log read) → Epic 4
- **FR6** (rule log read) → Epic 4
- **FR7** (BP runtime state read) → Epic 4
- **FR8** (find related sessions via `Ens.SuperSessionIndex`) → Epic 4
- **FR9** (find sessions by indexed body field via `Ens.SearchTableBase`) → Epic 4
- **FR10** (`%Status` decoder) → Epic 4
- **FR11** (citation grounding with click-through) → Epic 3
- **FR12** (chat history preserved against Ens session) → Epic 2 *(persistence)* + Epic 3 *(UI surfacing of returning conversation)*

**Message Search (FR13–FR24):**

- **FR13** (chat panel from Message Viewer subclass) → Epic 10
- **FR14** (Search Agent answers natural-language query with curated list) → Epic 8
- **FR15** (search by indexed `Ens.MessageHeader` columns — 6 indexed-access tools) → Epic 8
- **FR16** (search by indexed body field via SearchTable join) → Epic 8
- **FR17** (search by cross-instance super-session) → Epic 8
- **FR18** (two-stage indexed-prefilter + body-content inspection ≤50 candidates) → Epic 8
- **FR19** (bounded-WHERE invariant — indexed lead column + 24h default / 720h max time window) → Epic 8
- **FR20** (search → inspection click-through with context-pass) → Epic 10
- **FR21** (operator can save query alias for personal future use via `vocab_lookup`) → Epic 9
- **FR22** (per-user vocabulary learning with confidence smoothing) → Epic 9
- **FR23** (~10 seed vocabulary templates seeded by installer) → Epic 8
- **FR24** (vocabulary digest as first-user-message prefix, preserving Anthropic prompt-cache) → Epic 9

**LLM Provider Framework (FR25–FR30):**

- **FR25** (4 bundled providers: OpenAI / Anthropic / Gemini / OpenAI-compatible) → Epic 2 *(OpenAI ships first)* + Epic 5 *(remaining 3)*
- **FR26** (Operator-Admin configures each agent independently per-provider) → Epic 6
- **FR27** (Anthropic-canonical wire shape with mechanical adapters) → Epic 2 *(adapter pattern proven via OpenAI)* + Epic 5 *(further validated by Anthropic+Gemini+OpenAI-compat)*
- **FR28** (5th-provider extensibility — one subclass + one registry entry, no shared-infra edits) → Epic 5 *(proven in practice by adding 3 more)*
- **FR29** (90s per-call provider timeout cap) → Epic 2
- **FR30** (Anthropic prompt-caching of `system + tools` prefix) → Epic 5 *(Anthropic-specific cache_control discipline)*

**Read-Only Enforcement & Audit (FR31–FR37):**

- **FR31** (3-layer read-only: code + dispatch gate + RBAC) → Epic 1 *(L3 RBAC)* + Epic 2 *(L1 code discipline + L2 dispatch policy gate)*
- **FR32** (LlmCall audit row per round-trip) → Epic 2
- **FR33** (ToolCall audit row per dispatch) → Epic 2
- **FR34** (FK-linked audit rows to Chat.History) → Epic 2
- **FR35** (audit review via standard IRIS SQL — no separate UI in v1) → Epic 2 *(`docs/audit-sql-recipes.md`)*
- **FR36** (dispatch policy gate rejects `MutatesState=1`) → Epic 2
- **FR37** (structured tool-error envelopes, never exceptions) → Epic 2

**Configuration & Credentials (FR38–FR42):**

- **FR38** (Zen page `SessionAgent.UI.AgentConfig` for per-agent config) → Epic 6
- **FR39** (independent config per agent — 2 rows in v1) → Epic 6
- **FR40** (credential resolution ladder: env-var → `Ens.Config.Credentials` → AES) → Epic 2 *(EnvSecret implementation)*
- **FR41** (no API keys in `Config.Agent` — references only) → Epic 2 *(schema discipline at first row)*
- **FR42** (per-agent max-tokens / temperature / system-prompt-override UI) → Epic 6

**Chat Lifecycle (FR43–FR47):**

- **FR43** (Inspection-keyed `(agentName, irisSessionId, portalUser)` vs Search-keyed `(agentName, searchSessionKey, portalUser)`) → Epic 2 *(Inspection keying)* + Epic 8 *(Search keying)*
- **FR44** (daily sweep removes orphaned Inspection chat-history after `Ens.MessageHeader.Purge()`) → Epic 7
- **FR45** (TTL-based sweep for Search Agent chat — default 30d) → Epic 10
- **FR46** (concurrent-tab serialization via `%OpenId(id, 4)`) → Epic 2
- **FR47** ("from search" context indicator on hand-off arrival) → Epic 10

**Installation & Operator Surface (FR48–FR54):**

- **FR48** (`zpm install iris-session-agent` against IRIS 2024.1+) → Epic 1
- **FR49** (Python-less install success) → Epic 1
- **FR50** (Installation creates `SessionAgent_ReadOnly` RBAC role) → Epic 1
- **FR51** (Installation creates Mgmt Portal bookmarks for both agents) → Epic 1
- **FR52** (README operator-prerequisites as structural section) → Epic 1
- **FR53** (no transitive Open Exchange dependencies — single Resource) → Epic 1
- **FR54** (vendored client-side Markdown bundle at `/csp/static/iris-session-agent/`) → Epic 10 *(Growth-tier; MVP uses simpler render path per UX-DR14)*

**Developer Extensibility (FR55–FR59):**

- **FR55** (tool registry pure dispatch contract) → Epic 2
- **FR56** (every tool declares the 5 required params/methods) → Epic 2
- **FR57** (MCP Consumer can introspect registry — `Tool.Registry.ListTools`) → Epic 2
- **FR58** (Community Contributor can subclass `SessionAgent.Tool.Base`) → Epic 2 *(structurally supported; v1 ships built-ins only)*
- **FR59** (tool-call-roundtrip integration test exercises every provider × every tool) → Epic 5 *(test infrastructure; re-runs as more tools land in Epic 4 and Epic 8)*

**NFR coverage** is implicit per-epic (each NFR's enforcement mechanism lives in its owning epic — see the per-epic NFR list under §Epic List below). **AR coverage** ditto.

## Epic List

### Epic 1: Project Foundation & Installable Package

**Operator outcome:** Operator-Admin runs `zpm install iris-session-agent` on a fresh IRIS / IRIS for Health 2024.1+ instance and observes: package compiles cleanly with no transitive deps and no Python required, `SessionAgent_ReadOnly` RBAC role created, four audit event types pre-registered in `%SYS`, both Mgmt Portal bookmarks visible (HealthShare + plain-IRIS patterns documented), README's three-step operator-prerequisites section is concrete and actionable. The product is *installable and trustworthy* — but no chat experience yet.

**FRs covered:** FR48, FR49, FR50, FR51, FR52, FR53
**ARs covered:** AR1 (no starter, hand-author from research-doc), AR2 (module.xml shape — single Resource + 3 install hooks + FileCopy + unauthenticated CSPApplication), AR3 (HSCUSTOM + dual bookmark patterns), AR4 (sweep tasks scheduled by Installer — task implementations land in Epics 7 + 10), AR5 (4-event audit pre-registration in `%SYS`), AR6 (RBAC role install — idempotent SELECT-only on `Ens.*`), AR13-Epic1 (Web Gateway timeout Task-0 probe), AR14 (README operator-prerequisites structural deliverable), AR15-quickstart (`docs/operator-quickstart.md`), AR16 (lightweight CI scaffolding)
**NFRs covered:** NFR-S1-L3 (RBAC layer), NFR-S5 (public-OSS posture), NFR-R5 (idempotent install), NFR-R1 (deployment safety — structural via L3), NFR-C1 (2024.1 floor — release-gate smoke), NFR-C2 (no `[Language = python]` — CI grep), NFR-C3 (Python-less install — CI gate), NFR-C4 (no transitive deps — module.xml review), NFR-C5-shape (no CDN — CSPApplication shape), NFR-O1 (operator self-service install)
**UX-DRs covered:** UX-DR22 (cross-browser test posture), UX-DR23 (WCAG AA contrast verification posture)

### Epic 2: Inspection Agent — Backend Plumbing

**Operator outcome (maintainer checkpoint):** A `%UnitTest`-runnable smoke test invokes `SessionAgent.Agent.AgentLoop.RunTurn(...)` programmatically against OpenAI with three example Inspection tools (`session_summary`, `session_timeline`, `message_headers`), receives a coherent multi-tool response, and writes complete `Audit.LlmCall` + `Audit.ToolCall` rows FK-linked to `Chat.History`. Validates: provider abstraction, retry/backoff, secret resolution, tool registry + dispatch policy gate (`MutatesState=0`), AgentLoop iteration cap (10) + 90s per-call timeout, chat-history persistence, `%OpenId(id, 4)` concurrent-tab serialization, structured error envelopes. **Maintainer can verify the agent works before staking pilot operators on a UI.**

**FRs covered:** FR12-persistence, FR25-OpenAI, FR27-canonical-wire, FR29 (90s cap), FR31-L1+L2 (code discipline + dispatch gate), FR32, FR33, FR34, FR35-recipes, FR36, FR37, FR40 (EnvSecret), FR41 (Config.Agent schema discipline), FR43-Inspection-keying, FR46 (concurrency), FR55, FR56, FR57, FR58
**ARs covered:** AR7-OpenAI (RetryWithBackoff), AR8 (EnvSecret credential resolution), AR9 (AgentLoop constants), AR10-initial (calibration constants for AgentLoop + RetryWithBackoff), AR13-Epic2 (`%Dictionary.MethodDefinition` Task-0 probe), AR15-recipes (`docs/audit-sql-recipes.md` when schema lands), AR17 (ISO-8601 UTC timestamps), AR18 (`%EXACT()` SQL discipline)
**NFRs covered:** NFR-P1 (90s cap), NFR-P4 (concurrent-tab), NFR-S1-L1+L2, NFR-S2 (credential confinement — schema), NFR-S3 (credential hygiene — never log), NFR-S4 (audit completeness — synchronous writes), NFR-S6 (dispatch purity — 7 anti-patterns), NFR-O3 (audit SQL access)

### Epic 3: Inspection Agent — UI MVP Demo-able Milestone

**Operator outcome:** Operator opens Visual Trace on a real failed session, clicks the new "Ask the agent" tab, types *"what happened?"*, watches tool-call cards advance in sequence as the three example tools dispatch, and reads a grounded answer with clickable citation chips that navigate to the cited row in the parent's existing rule-log / event-log / message-headers panel. **The first delight moment** — Marisol-style senior on-call operator can validate the *fit* claim on a real incident. Returning to the same session shows the prior conversation. **PRD MVP exit criterion gates at end of this epic.**

**FRs covered:** FR1, FR2, FR11, FR12-UI-surfacing
**UX-DRs covered:** UX-DR1 (sa-chat-panel container), UX-DR2-MVP (sa-message-block operator+agent variants only), UX-DR3 (sa-tool-call-card with `<details>`/`<summary>`), UX-DR4-MVP (sa-citation-chip with parent's selectItem/updateTabs API — 6 variants, partial off-page sync), UX-DR6 (sa-status-text), UX-DR7-admin (sa-config-empty-prompt operator-admin variant), UX-DR10 (sa-input-field), UX-DR12-MVP-subset (minimum --sa-* tokens), UX-DR14 (MVP simpler render path), UX-DR15-Inspection (tab placement Inspection), UX-DR16 (visible-progress feedback layer), UX-DR17-MVP-subset (first-time + returning empty states), UX-DR18-MVP-subset (basic provider-error envelopes), UX-DR19 (native HTML semantics), UX-DR20-MVP (ARIA discipline), UX-DR21 (color-not-sole-indicator), UX-DR24-MVP (partial off-page citation sync), UX-DR26 (inherit-and-augment), UX-DR27-MVP (MVP component scope), UX-DR28 (no-modals discipline), UX-DR30 (single-shot interaction primitives)
**NFRs covered:** NFR-A1 (inherited Mgmt Portal accessibility), NFR-C6 (browser support — manual smoke test), NFR-P5 (time-to-resolution — operator self-report from this epic forward)

### Epic 4: Inspection Agent — Full Tool Catalogue

**Operator outcome:** Operator now has all 13 Inspection tools available — agent can answer the full range of cross-surface questions (event log filtered by severity, rule log decisions, BP source/instance/methods, complete message-body dispatch ladder for `%JSON.Adaptor` + virtual document + `%Stream.Object` + generic `%Persistent` shapes, `Ens.SuperSessionIndex` cross-instance trace, `Ens.SearchTableBase` body-field pivot, `%Status` decoder including IRIS-specific error codes). All 13 tools dispatched in production observed at least once during pilot.

**FRs covered:** FR3-full, FR4, FR5, FR6, FR7, FR8, FR9, FR10
**ARs covered:** Comprehensive read-only test suite extending the Epic 2 baseline

### Epic 5: Multi-Provider Support

**Operator outcome:** Operator-Admin can pick Anthropic, Google Gemini, or any OpenAI-compatible endpoint (Ollama, vLLM, self-hosted) instead of OpenAI. Tool-call-roundtrip integration test gates each provider against every bundled tool; Anthropic prompt-caching of `system + tools` prefix lands with AnthropicProvider; Gemini retry parses `error.details[].retryDelay` (no Retry-After header). Anthropic-canonical wire shape proven by reading two existing concretes — Tomás-class community contributor can add a 5th provider in ~187 lines.

Story order within this epic preserves the architect's sub-step rationale: **Anthropic ships first** (validates the canonical-wire inversion early — direct implementation, no adapter), then **Gemini** (camelCase wire + Gemini-specific retryDelay parsing), then **OpenAICompat** (covers Ollama / vLLM / any compatible endpoint with operator-supplied URL).

**FRs covered:** FR25-full (4 providers shipped), FR27-validated (canonical-wire inversion further validated), FR28 (5th-provider extensibility proven), FR30 (Anthropic prompt-caching), FR59 (tool-call-roundtrip integration test infrastructure — re-runs as more tools land)
**ARs covered:** AR7-Gemini (Gemini retryDelay parser), AR10-per-provider (per-provider calibration constants), AR20 (tool-call-roundtrip test infrastructure)
**NFRs covered:** NFR-P6 (Anthropic prompt-cache hit rate), NFR-R4 (provider failure isolation per-provider error mapping)

### Epic 6: Per-Agent Configuration UI

**Operator outcome:** Operator-Admin opens `SessionAgent.UI.AgentConfig.zen`, picks an agent (Inspection / Search), selects provider + model + temperature + max-tokens + optional system-prompt-override + credential-ref from the existing `Ens.Config.Credentials` dropdown, saves. Hot config change applies on the next agent turn — no IRIS restart, no chat reset. Form feels like other Mgmt Portal config pages (`EnsPortal.Credentials.zen` style).

**FRs covered:** FR26, FR38, FR39, FR42
**UX-DRs covered:** UX-DR11 (sa-config-form Inspection variant), UX-DR7-admin-link (config-empty-prompt admin variant now linkable to AgentConfig.zen)
**NFRs covered:** NFR-O2 (hot config change without IRIS restart)

### Epic 7: Inspection Chat-History Lifecycle

**Operator outcome:** Operator's accumulated Inspection chat history is automatically swept when the underlying Ens session is purged via `Ens.MessageHeader.Purge()` — daily 02:00 UTC sweep removes orphaned `Chat.History` rows. No orphan accumulation under sustained purge cycles. Validated by a 1,000-session integration test (insert sessions + attach conversations + purge + sweep; assert zero orphans).

**FRs covered:** FR44
**ARs covered:** AR4-PurgeOrphanedChatHistory (task implementation), AR13-Epic7 (`&sql SELECT 1 INTO` semantics Task-0 probe)
**NFRs covered:** NFR-R2 (chat-history lifecycle integrity under purge), NFR-SC4-Inspection (audit-log volume bounded by sweep cascade — Inspection portion)

### Epic 8: Search Agent — Foundation

**Backend outcome (programmatic + via `vocab_lookup`):** All 8 indexed-access search tools + `InspectBodyCandidates` two-stage body-content search (≤50 candidates) + `VocabLookup` utility tool callable via `Tool.Registry.Dispatch`. Bounded-WHERE invariant enforced (every search SQL leads with ≥1 indexed column + 24h `TimeCreated` default, max 720h). Vocabulary persistence schemas exist; ~10 HL7-idiom seed templates seeded by installer. **Maintainer / pilot outcome:** maintainer validates Search Agent backend correctness via `%UnitTest` + `vocab_lookup` exploration before exposing to operators. The full operator outcome (Devin Journey 2 — opens Message Viewer's "Ask the agent" tab) is reached at end of **Epic 10** when the `EnsPortal.MessageViewer` subclass + chat panel UI ship — same "(maintainer checkpoint)" framing as Epic 2.

Note: At end of Epic 8, the Search Agent is callable programmatically and via `vocab_lookup`; the **Message Viewer chat panel UI** lands in Epic 10. This split lets vocabulary learning (Epic 9) sit between foundation and UI without UI-side refactoring.

**FRs covered:** FR14, FR15, FR16, FR17, FR18, FR19, FR23, FR43-Search-keying
**ARs covered:** AR11 (bounded-WHERE invariant test), AR19-schemas (UserVocabulary, SeedVocabulary, NamespaceVocabulary schema-only — population logic in Epic 9 / Vision tier), AR13-Epic8 (`EnsLib.HL7.SearchTable` row-shape Task-0 probe)
**UX-DRs covered:** UX-DR29 (bounded-WHERE search UX narration — agent narrates limitations + suggests refinements)
**NFRs covered:** NFR-P2 (1M-row query bound), NFR-P3 (≤50 candidate body inspection), NFR-SC1 (10M-row extent)

### Epic 9: Search Agent — Vocabulary Learning

**Backend outcome:** Vocabulary capture (silent click-through + explicit-save) is callable via `UserVocabulary.RecordSuccess`/`RecordFailure` ClassMethods (with confidence smoothing `Success / (Success + Failure + 1)` via recursion-safe `%OnAfterSave`) and via Epic 8 Story 8.7's `vocab_lookup mode='save'`. Vocabulary digest assembly (top 20 user rows with confidence ≥ 0.3, capped ~1,200 tokens) is wired into `AgentLoop` as a first-user-message prefix — preserves Anthropic prompt-cache hit rate. **Maintainer / pilot outcome:** maintainer validates vocabulary learning end-to-end via `%UnitTest` + explicit `vocab_lookup mode='save'` calls. The full operator outcome (click-through silently captures vocabulary while operator clicks search results in the Message Viewer chat panel — by the third *"admits"* query, the agent skips seed vocabulary entirely) is reached at end of **Epic 10** when Story 10.3's click-through wiring calls Epic 9 Story 9.5's `RecordClickThrough` ZenMethod hyperevent stub.

**FRs covered:** FR21, FR22, FR24
**ARs covered:** AR12 (UserVocabulary recursion-safe `%OnAfterSave`), AR13-Epic9 (`%OnAfterSave` non-recursion + `SynthesizeAlias` determinism Task-0 probes)
**NFRs covered:** NFR-P6-vocabulary (vocabulary digest in *uncached* prefix preserves cache hit rate)

### Epic 10: Search Agent — UI Embed, Hand-off & TTL Sweep

**Operator outcome:** Operator clicks a curated session entry → navigates to Visual Trace + Inspection Agent's chat tab loads with **"from search" stripe** quoting their literal query text + Accept / × Dismiss / implicit-accept; vocabulary capture happens silently as a side effect. Concurrent-tab lock surfaces as a non-modal banner. Search chat history sweeps after 30 days (operator-tunable). Vendored Markdown rendering bundle (marked + Prism.js + DOMPurify) ships at `/csp/static/iris-session-agent/` — code-block syntax highlighting for ObjectScript, JS, JSON, SQL, HL7, XML. **Completes v1 scope.**

**FRs covered:** FR13, FR20, FR45, FR47, FR54
**UX-DRs covered:** UX-DR5 (sa-from-search-stripe with three exits), UX-DR8 (sa-concurrent-tab-banner), UX-DR9 (sa-search-result-entry), UX-DR2-Growth (sa-message-block error variant + search-result variant), UX-DR11-Search (sa-config-form Search agent variant), UX-DR13 (vendored Markdown bundle marked + Prism.js + DOMPurify), UX-DR12-full (full token resolution against parent palette), UX-DR15-Search (Search tab placement), UX-DR17-full (no-results + no-config full-set empty states), UX-DR18-full (graceful-degradation including concurrent-tab + provider error envelopes), UX-DR24-Growth (full off-page sync via `zenPage.openPage`), UX-DR25 (from-search hand-off pattern), UX-DR27-Growth (Growth-tier component scope)
**ARs covered:** AR4-PurgeStaleSearchChat (task implementation), AR4-UserVocabularyDecay (task implementation, weekly Sunday sweep)
**NFRs covered:** NFR-R3 (search-history TTL — 30d default, configurable), NFR-SC4-Search (audit-log volume bounded — Search portion), NFR-C5-Growth (vendored bundle ships)

### Post-v1.0.0 maintenance epics

The epics below were opened after v1.0.0 shipped to address findings from operator usage. They do not change MVP scope — they refine and harden the surfaces already shipped.

### Epic 11: v1.0.1 Patch Release — Targeted Bug Fixes

**Operator outcome:** Four targeted fixes addressing items deferred from Epic 10's retrospective: MaxTokens-on-rotation cascade preservation, EnsureIsErrorOnPrepare defensive sweep across 9 inspection tools, multi-namespace install programmatic bundle copy, OpenAI-compat URL construction investigation. Tagged as v1.0.1.

### Epic 12: Walkthrough Hardening — Bug Fixes & UX Polish

**Operator outcome:** Address the 8 bugs and 3 documentation enhancements surfaced by the 2026-05-08 project-lead walkthrough on the v1.0.1 install. Improves operator experience on both agent surfaces (Search Agent on Message Viewer + Inspection Agent on Visual Trace) without introducing new architectural decisions or changing MVP exit criteria. Source-of-truth artifact: `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md`.

**Severity distribution:** 3 HIGH, 4 MEDIUM, 1 LOW, 3 doc-enhancement.

### Epic 13: Tool Catalog Expansion

**Operator outcome:** Five new agent-introspection tools that close gaps surfaced by the 2026-05-09 demo + lead's scoping conversation. The Inspection Agent gains four source-introspection tools (`get_class_source`, `get_rule_source`, `get_production_config_item`, `get_queue_state`); the Search Agent gains `find_sessions_using_class` for cross-session class-usage discovery. Tool catalog grows from 23 to 28 (FR59 cross-matrix gate from 92 to 112 combinations). Source-of-truth artifact: `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md`.

**Stories:** 6 (13.0 setup + 5 tool-add stories).

**No PRD / architecture / UX-spec edits.** Pure additive surface within the existing tool-registry pattern.

### Vision Tier — Out of Scope (post-v1)

Per [PRD §"Vision (Future, post-v1)"](prd.md#vision-future-post-v1) — explicitly deferred to post-v1 work. Not in any v1 epic; included here for completeness:

- **MCP serving** (delegated to sibling `iris-execute-mcp-v2`; `iris-session-agent`'s tool registry stays MCP-exportable per FR55–FR57)
- **Vector / semantic body-content search** (requires `%Library.Embedding` — post-2024.1)
- **PHI redaction architecture** (namespace segregation is v1 boundary)
- **Cross-namespace single-conversation operation** (`$NAMESPACE` switching forbidden in CSP context)
- **Streaming responses** (SSE / async-poll instead of blocking dispatch)
- **LLM-extracted alias generation** from chat history (with regex PHI scrub before persistence)
- **Cross-user `NamespaceVocabulary` baseline population** (schema ships in v1 from Epic 8; population logic is post-v1) — *architect's original Epic 18 maps here*
- **Stand-alone terminal REPL bot** (was an AI-Hub-coupled freebie; ~30 min of complexity to reimplement; defer until useful)
- **Reference-implementation maturity** — pattern adopted by sibling IRIS-domain agents (Production Health, Schema Discovery, HealthShare Migration Assistant)
- **Long-tail community option** when AI Hub goes GA

## Mapping to Architecture's Original 18-Epic Sequence

The architect's [Architecture §"Decision Impact Analysis → Implementation Sequence"](architecture.md#decision-impact-analysis) originally proposed an 18-step implementation sequence. That sequence is preserved as story order *within* the consolidated 10 epics here. Bidirectional mapping:

| epics.md (this doc) | architecture.md original epics | Why consolidated |
|---|---|---|
| **Epic 1** — Project Foundation & Installable Package | architecture Epic 1 | Single-domain epic — IPM packaging + Installer + RBAC + audit pre-registration are one cohesive deliverable. |
| **Epic 2** — Inspection Agent Backend Plumbing | architecture Epics 2, 3, 4 | LLM Provider abstraction + Tool Registry + AgentLoop are inseparable infrastructure — none stands alone as user value; combined they form a maintainer-validatable backend. |
| **Epic 3** — Inspection Agent UI MVP Demo-able | architecture Epics 5, 6 | Chat-panel JS + ZenMethod hyperevent + VisualTrace subclass must ship together for the MVP demo to work end-to-end. **PRD MVP exit criterion gates here.** |
| **Epic 4** — Inspection Agent Full Tool Catalogue | architecture Epic 7 | Single-domain epic — remaining 10 inspection tools. |
| **Epic 5** — Multi-Provider Support | architecture Epics 8, 10 | All three additional providers touch the same `LLM/*` package + `MessageAdapter` + `ToolDefAdapter`. Story order ships Anthropic first (validates inversion), then Gemini, then OpenAICompat — preserving the architect's rationale. |
| **Epic 6** — Per-Agent Configuration UI | architecture Epic 9 | Single-domain epic — the AgentConfig Zen page. |
| **Epic 7** — Inspection Chat-History Lifecycle | architecture Epic 11 | Single-domain epic — `PurgeOrphanedChatHistory` task + Topic-10 Option B coupling. |
| **Epic 8** — Search Agent Foundation | architecture Epics 12, 13 | Vocabulary persistence schemas + 8-tool search catalog + body-inspection + vocab utility ship together to deliver the first end-to-end Search Agent capability (programmatic + via `vocab_lookup`). |
| **Epic 9** — Search Agent Vocabulary Learning | architecture Epics 14, 15 | Click-through capture + RecordSuccess + VocabularyDigest.Build + first-user-message prefix injection are one logical capability. |
| **Epic 10** — Search Agent UI Embed, Hand-off & TTL | architecture Epics 16, 17 | Message Viewer subclass + chat tab + hand-off stripe + TTL sweep + vendored Markdown bundle (Growth tier) ship together to complete v1. |
| **Vision tier — deferred** | architecture Epic 18 | `NamespaceVocabulary` cross-user baseline population — schema ships in Epic 8, population logic is post-v1 per PRD §Vision. |

**Cross-reference convention.** Story files produced in Step 3 will cite both indices in dev notes — e.g., *"implements architecture Epic 8 (AnthropicProvider) per architecture.md §'Decision Impact Analysis → Implementation Sequence'"* — so dev agents picking up a story can find the architecture context regardless of which numbering they encounter first. The bidirectional mapping table also lives in architecture.md §"Implementation Sequence" so the reverse direction is just as discoverable.

## Cross-Cutting Story Patterns

Three patterns recur across the epic breakdown and warrant a single explanation here so first-time readers (human or AI dev agent) can recognize them on first encounter:

### 1. Defensive-stub-now, enrich-later

A story ships a working stub that depends on (or anticipates) a class/schema that lands in a later story; the later story enriches the stub without changing its public contract. This lets earlier epics ship without forward-dependency violations while later epics deliver the full feature.

Three instances in v1:
- **Story 1.5 → Story 2.4**: `Installer.Install` (Epic 1) defensively skips `Config.Agent` row seeding if the class doesn't exist; Story 2.4 (Epic 2) ships the schema and the seeding flips on at the next install.
- **Story 1.5 → Stories 7.2 / 10.6**: `Installer.Install` defensively skips Task Manager registration for sweep classes (`PurgeOrphanedChatHistory`, `PurgeStaleSearchChat`, `UserVocabularyDecay`) if the task class doesn't exist; Stories 7.2 (Epic 7) and 10.6 (Epic 10) ship the task implementations and registration flips on.
- **Story 8.7 → Story 9.2**: `vocab_lookup mode='save'` (Epic 8) implements `RecordSuccess` inline as a basic open-or-create + increment + save; Story 9.2 (Epic 9) promotes it to a class-level `ClassMethod` on `UserVocabulary` and adds the recursion-safe `%OnAfterSave` Confidence-recomputation trigger. Story 8.7's call delegates to the new ClassMethod once it lands; no behavioral change beyond consolidation.

In every case the stub story's AC explicitly notes the deferred enrichment, and the enrichment story's AC explicitly notes which earlier story it consolidates. No silent dependency.

### 2. "Maintainer / pilot checkpoint" framing for backend-before-UI epics

Three epics (2, 8, 9) ship backend-only deliverables that don't reach a real operator until a later UI epic ships. Their "Operator outcome" headers explicitly use **maintainer-checkpoint or backend-outcome** framing rather than implying an operator-facing experience that doesn't yet exist:

- **Epic 2** (Inspection Agent backend) → operator outcome lands in Epic 3.
- **Epic 8** (Search Agent backend + tool catalog) → operator outcome lands in Epic 10.
- **Epic 9** (Search Agent vocabulary learning) → operator outcome (silent click-through capture) lands in Epic 10.

The framing acknowledges that the maintainer (Joshua) is the user for these epics — verifying backend correctness via `%UnitTest` + programmatic dispatch before exposing pilot operators to a half-baked surface. This is justified for v1's single-maintainer hobby-project posture; combining each backend epic with its UI epic would produce unmanageably large epics (Epic 2 alone has 12 stories).

### 3. Carry-forward Task-0 probes anchored at first cross-codebase consumer

Per `research-first.md` rule 4, six probes verify uncertain runtime primitives on the operator's IRIS 2024.1+ instance before code that depends on them ships. Each probe is anchored at the **first story across the codebase that needs the primitive**, and downstream consumers reuse the captured shape rather than re-probing. The carry-forward set:

- **Web Gateway "Server Response Timeout" verbatim default** → Story 1.2 (README operator-prerequisite authoring needs the exact value to embed).
- **`%Dictionary.MethodDefinition.%OpenId(...)` returns non-null on 2024.1** → Story 2.10 (`Tool.Registry` reflection needs to enumerate registered tools).
- **`EnsLib.HL7.SearchTable` row shape `(DocId, PropName, PropValue)` on operator's instance** → Story 4.6 (`FindSessionsByBody` is the first cross-codebase SearchTable consumer); Story 8.5 (`SearchByBodyField`) reuses the captured shape.
- **`&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId)='...')` SQLCODE=0/100 semantics on 2024.1** → Story 7.1 (`PurgeOrphanedChatHistory` orphan-detection probe).
- **`%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1** → Story 9.1 (`UserVocabulary.Confidence` recomputation needs the non-recursion guarantee).
- **`SynthesizeAlias` deterministic stringification across ~10 reordering scenarios** → Story 9.1 (vocabulary alias capture needs deterministic keys).

Each probe story records the probe output verbatim in its Tasks/Subtasks block before proceeding to AC; if a probe fails, the story escalates for a defer/redesign decision before any production code is written.

---

## Epic 1: Project Foundation & Installable Package

**Operator outcome:** Operator-Admin runs `zpm install iris-session-agent` on a fresh IRIS / IRIS for Health 2024.1+ instance and observes a clean, idempotent install that creates the `SessionAgent_ReadOnly` RBAC role, pre-registers four audit event types in `%SYS`, prints both Mgmt Portal bookmark URLs (HealthShare + plain-IRIS patterns), and surfaces operator-prerequisites via a structural README section. The product is *installable and trustworthy* — no chat experience yet, but the foundation is verifiable end-to-end.

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 1.1**: Project Initialization — repo-root scaffolding files
2. **Story 1.2**: Web Gateway Timeout Task-0 Probe + README Operator Prerequisites authoring
3. **Story 1.3**: Audit Event Pre-Registration (`SessionAgent.Audit.Emit.EnsureEvents`)
4. **Story 1.4**: Read-Only RBAC Role Install (`SessionAgent.Security.ReadOnlyRole.Install`) + privilege-failure integration test
5. **Story 1.5**: Installer Scaffold + `Install` method orchestrating audit + RBAC + bookmark print + sweep-task scheduling framework
6. **Story 1.6**: Operator Quickstart Documentation (`docs/operator-quickstart.md`)
7. **Story 1.7**: Lightweight CI Scaffolding (`.github/workflows/ci.yml`)

### Story 1.1: Project Initialization

As an Operator-Admin,
I want to clone the iris-session-agent repository and find a complete IPM-installable package skeleton,
So that I can run `zpm load /path/to/repo` and observe the package compiles cleanly before any feature work lands.

**Acceptance Criteria:**

**Given** the user has cloned the repository
**When** they inspect the repo root
**Then** `module.xml` exists matching architecture.md §"Project Directory Structure" — single `<Resource Name="SessionAgent.PKG"/>`, three `<Invoke>` install hooks (commented or guarded against missing target classes), `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>`, dedicated unauthenticated `<CSPApplication Url="/csp/static/iris-session-agent" Path="${cspdir}static/iris-session-agent" Resource="" Recurse="1" UseCookies="0" AuthenticationMethods="64"/>`
**And** `LICENSE` exists with MIT text and `Copyright (c) 2026 Joshua Brandt`
**And** `README.md` exists with a project header, one-line description, and a placeholder for `## Operator Prerequisites` (full content lands in Story 1.2)
**And** `.gitignore` exists with standard IRIS, VSCode, and IDE patterns
**And** `src/SessionAgent/` directory exists (empty or with a `.gitkeep`)
**And** `src/static/` directory exists (empty or with a `.gitkeep`)

**Given** a fresh IRIS / IRIS for Health 2024.1+ instance with no existing iris-session-agent install
**When** the user runs `zpm load /path/to/repo`
**Then** the install completes with exit status 0
**And** `module.xml` is parsed without warnings
**And** no `[Language = python]` references appear in any shipped file (CI grep enforces — see Story 1.7)

**Given** the developer wants to verify the project root layout
**When** they view the repository tree
**Then** it matches architecture.md §"Project Directory Structure" file tree (no extra files; no missing required files)

### Story 1.2: Web Gateway Timeout Task-0 Probe + README Operator Prerequisites

As an Operator-Admin,
I want the README to document the three operator prerequisites — Web Gateway timeout raise, RBAC role grant, and LLM provider API key supply — with concrete, verbatim default values captured from a live 2024.1 instance,
So that I can complete the prerequisites in under 30 minutes before installing the product (NFR-O1).

**Acceptance Criteria:**

**Given** the developer is preparing the operator-prerequisites README content
**When** they run the Task-0 probe to capture the Web Gateway "Server Response Timeout" verbatim default value (per architecture §"Carry-forward Task-0 probes" Epic 1)
**Then** the captured value is recorded verbatim in the story's Tasks/Subtasks block
**And** the captured value is embedded in the README §"Operator Prerequisites" content (e.g., "raise from `<probed-default>s` → 300s")
**And** the probe output documents which IRIS version was probed (e.g., "IRIS 2024.1.3 community")

**Given** the operator opens the README
**When** they navigate to §"Operator Prerequisites"
**Then** the section enumerates three concrete steps in order: (1) raise Web Gateway "Server Response Timeout" to 300s with the documented reason (LLM-call latencies often sit in the 30–90s band; default kills them mid-stream), (2) grant `SessionAgent_ReadOnly` to the operator user/role, (3) supply LLM provider API key via env-var (preferred for containers) or `Ens.Config.Credentials` (traditional installs)
**And** the section shows BOTH bookmark URL patterns — HealthShare (`/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`) AND plain IRIS (`/csp/<NS>/SessionAgent.EnsPortal.{...}.zen`)
**And** the section is positioned as the first H2 heading after the project introduction (per Aishah Journey 3 expectation that prerequisites precede the install command)

**Given** the operator follows the prerequisites in order
**When** they raise the Web Gateway timeout per the README's instructions
**Then** the change is verifiable via the Web Gateway management page → System Default Parameters → "Server Response Timeout"
**And** the README's path to that setting matches a verifiable IRIS 2024.1 administrative path

### Story 1.3: Audit Event Pre-Registration

As a System (audit infrastructure),
I want four audit event types pre-registered in `%SYS` via `Security.Events.Create()` at install time,
So that subsequent `$System.Security.Audit("SessionAgent","<Type>","<Name>", ...)` calls in later epics succeed instead of silently returning 0 (per project rule "Security.Events Pre-Registration for Audit").

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Audit.Emit`
**When** they implement the `EnsureEvents()` class method
**Then** the method switches to `%SYS` namespace using the explicit save/restore pattern (per project rule "Namespace Switching") — **never** `New $NAMESPACE`
**And** any catch block restores `$NAMESPACE` as its first line
**And** for each of four event triples — `(SessionAgent, LlmCall, <provider>)` for FR32, `(SessionAgent, ToolCall, <tool_name>)` for FR33, `(SessionAgent, VocabWrite, clickthrough|explicit|extracted|seed)` for Epic 9 vocab emitter, `(SessionAgent, TaskRun, <task_name>)` for Epics 7+10 sweep emitters — the method checks `Security.Events.Exists("SessionAgent","<Type>","<Name>")` and calls `Security.Events.Create(...)` only if absent (idempotent)
**And** the method returns `%Status` per project convention (`Set tSC = $$$OK` first line, `Quit tSC` last line)

**Given** the install has run once
**When** the install runs a second time (idempotent reinstall per NFR-R5)
**Then** `EnsureEvents()` does not duplicate event registrations
**And** the second invocation completes with `$$$OK`

**Given** a unit test in `Test/AuditEmitTest.cls` verifies registration
**When** the test invokes `EnsureEvents()` then queries `%SYS` for the four event triples via `Security.Events.Exists`
**Then** all four exist with the expected Source/Type/Name shape
**And** a second invocation of `EnsureEvents()` does not create duplicates

### Story 1.4: Read-Only RBAC Role Install

As an Operator-Admin,
I want the install process to create the `SessionAgent_ReadOnly` RBAC role with SELECT-only grants on `Ens.*` tables, idempotent across reinstalls,
So that the agent's read-only invariant has structural enforcement at the IRIS database privilege layer (NFR-S1 Layer 3, FR50).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Security.ReadOnlyRole`
**When** they implement the `Install()` class method
**Then** the method switches to `%SYS` namespace using the explicit save/restore pattern (never `New $NAMESPACE`)
**And** if the `SessionAgent_ReadOnly` role does not exist, the method calls `Security.Roles.Create("SessionAgent_ReadOnly", "Read-only access to Ens.* tables for iris-session-agent", "")` per IRIS 2024.1 `Security.Roles` API (verified by reading `irislib/Security/Roles.cls` source per project rule "IRIS Library Source")
**And** the method grants SELECT on `Ens.MessageHeader`, `Ens.Util.Log`, `Ens.Rule.Log`, `Ens.SuperSessionIndex`, and standard body-class projections to the role via `%SQL.Statement` GRANT — using `%EXACT()` discipline where applicable
**And** the grants are explicitly SELECT-only — no INSERT, UPDATE, DELETE, or REFERENCES privileges
**And** the method returns `%Status` per project convention

**Given** the install has run once and `SessionAgent_ReadOnly` exists with grants
**When** `Install()` runs again (idempotent reinstall per NFR-R5)
**Then** the role and its grants are not duplicated
**And** the second invocation completes with `$$$OK`

**Given** an integration test (`Test/ReadOnlyRoleTest.cls`) is run
**When** the test grants `SessionAgent_ReadOnly` to a test user, switches process context to that user via `$System.Security.Login()` (or equivalent that doesn't lose process context per project rule), and attempts `INSERT INTO Ens.MessageHeader ...` and `DELETE FROM Ens.MessageHeader WHERE ...`
**Then** both operations fail with a `<PROTECT>` privilege error (or equivalent SQL privilege exception)
**And** a subsequent `SELECT FROM Ens.MessageHeader` succeeds for the same test user
**And** the test cleans up the test user grant before completing

### Story 1.5: Installer Scaffold + `Install` Method

As an Operator-Admin,
I want `SessionAgent.Installer.Install()` to orchestrate the audit-event pre-registration, RBAC role install, Mgmt Portal bookmark printing, sweep-task scheduling framework, and operator-reminder printing in a single idempotent install hook,
So that `zpm install iris-session-agent` is a single command that produces a fully-prepared installation (FR48, NFR-R5).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Installer`
**When** they implement the `Install()` class method (signature `ClassMethod Install(pVars) As %Status`)
**Then** the method calls `##class(SessionAgent.Audit.Emit).EnsureEvents()` (Story 1.3) and propagates any error via `%Status`
**And** the method calls `##class(SessionAgent.Security.ReadOnlyRole).Install()` (Story 1.4) and propagates any error
**And** the method calls a private helper `PrintOperatorReminders()` which writes to the install log: both bookmark URL patterns (HealthShare and plain-IRIS) parameterized on the current namespace, plus a one-line reminder pointing at the README §"Operator Prerequisites"
**And** the method calls a private helper `ScheduleTaskIfClassExists(taskName, classFullName, frequency, hour, minute)` for each of three tasks (`PurgeOrphanedChatHistory`, `PurgeStaleSearchChat`, `UserVocabularyDecay`) — the helper creates an IRIS Task Manager entry IF the task class exists in the current namespace, OR logs `"<class> not yet implemented; sweep deferred"` and continues so install does not fail when downstream tasks (Epics 7 + 10) are not yet shipped
**And** the method seeds two `SessionAgent.Config.Agent` rows with `Enabled=0` and provider/model defaults per architecture OD4 (one for `session-inspection`, one for `message-search`) — defensive against `SessionAgent.Config.Agent` class not yet existing (skip with log message; the class lands in Epic 2)
**And** the method returns `%Status` per project convention

**Given** module.xml's `<Invoke>` hooks reference `SessionAgent.Installer.Install`, `SessionAgent.Audit.Emit.EnsureEvents`, `SessionAgent.Security.ReadOnlyRole.Install`
**When** `zpm load /path/to/repo` runs against IRIS 2024.1+
**Then** all three hooks execute in order without error
**And** the install log contains both bookmark URL patterns with the current namespace substituted
**And** the install log contains the operator-prerequisites reminder line
**And** install exits with status 0

**Given** the install has run once successfully
**When** the install runs a second time (idempotent reinstall per NFR-R5)
**Then** no duplicate audit event registrations, no duplicate RBAC role grants, no duplicate Task Manager entries, no duplicate seeded `Config.Agent` rows
**And** the second invocation completes with `$$$OK`

### Story 1.6: Operator Quickstart Documentation

As a new Operator-Admin (Aishah-class, never installed iris-session-agent before),
I want a 1-page `docs/operator-quickstart.md` walkthrough that mirrors the [Aishah Journey 3](ux-design-specification.md) install-and-verify experience,
So that I can complete an end-to-end install + verify path in under 30 minutes (NFR-O1) without reading the full README cover-to-cover.

**Acceptance Criteria:**

**Given** the developer is authoring `docs/operator-quickstart.md`
**When** the doc is complete and committed
**Then** the doc opens with a one-paragraph orientation matching the Aishah Journey 3 narrative
**And** the doc enumerates the install path step-by-step: (1) prerequisite checklist with link to README §"Operator Prerequisites", (2) `zpm install iris-session-agent` command + expected install-log output snippet (audit events registered, RBAC role created, both bookmark URLs printed), (3) bookmark navigation to a known-failed session, (4) opening the chat tab and observing the no-config empty state (Epic 6 has not shipped yet — quickstart links forward to "configure your first agent" as future work), (5) verifying the install via SQL queries against `SessionAgent.Audit.*` (empty tables exist; Story 1.3 + Epic 2 schemas guarantee structure)
**And** the doc is concise (1 page when rendered, ~600–1000 words)
**And** the doc is committed under `docs/` per architecture §"Project Directory Structure"

**Given** an operator follows the quickstart on a fresh IRIS 2024.1+ instance
**When** they complete steps 1–5
**Then** the elapsed time is ≤ 30 minutes (NFR-O1; validated by self-report or maintainer-walkthrough during pilot)
**And** they can confirm the install via the documented SQL queries returning expected schemas (no rows, but tables exist)

### Story 1.7: Lightweight CI Scaffolding

As a maintainer,
I want `.github/workflows/ci.yml` to run lightweight checks on every PR — markdown lint, file-presence structural checks, the `[Language = python]` grep enforcing NFR-C2, and the CDN-reference grep enforcing NFR-C5,
So that PRs that violate the structural invariants are caught at PR time rather than at release-tag time (per architecture OD1).

**Acceptance Criteria:**

**Given** the developer is creating `.github/workflows/ci.yml`
**When** the workflow file is committed
**Then** the workflow triggers on `pull_request` against `main` and on `push` to `main`
**And** the workflow runs `markdownlint` (or equivalent) against `*.md` files in the repo
**And** the workflow runs a structural check that verifies `module.xml` exists, `LICENSE` exists, `README.md` contains an `## Operator Prerequisites` heading, and `src/SessionAgent/` and `src/static/` directories exist
**And** the workflow runs `grep -r "Language = python" src/SessionAgent/` and FAILS the build if any match is found (NFR-C2 enforcement per architecture §"Pure-OS-runtime invariant")
**And** the workflow runs `grep -rE "https://cdn\." src/static/` (or equivalent) and FAILS the build if any CDN reference is found in shipped static assets (NFR-C5 enforcement)
**And** the workflow does NOT yet run `%UnitTest` — that gate lands once a Python-less 2024.1 community image is available (per architecture OD1; documented as a TODO comment in the workflow file with the gating condition)

**Given** a PR is opened that introduces `[Language = python]` in any `src/SessionAgent/*.cls` file
**When** the CI workflow runs
**Then** the build fails with a clear error message naming the offending file and line
**And** the PR is blocked from merge until the violation is removed

**Given** a PR is opened that introduces a CDN reference (e.g., `https://cdn.jsdelivr.net/...`) in any file under `src/static/`
**When** the CI workflow runs
**Then** the build fails with a clear error message naming the offending file
**And** the PR is blocked from merge until the violation is removed

**Given** a PR removes or breaks one of the structural files (`module.xml`, `LICENSE`, `README.md` Operator Prerequisites heading, `src/SessionAgent/`, `src/static/`)
**When** the CI workflow runs
**Then** the build fails with a clear error message naming the missing file or heading
**And** the PR is blocked from merge until the structure is restored

---

## Epic 2: Inspection Agent — Backend Plumbing

**Operator outcome (maintainer-checkpoint):** A `%UnitTest`-runnable smoke test invokes `SessionAgent.Agent.AgentLoop.RunTurn(...)` programmatically against OpenAI with three example Inspection tools (`session_summary`, `session_timeline`, `message_headers`), receives a coherent multi-tool response, and writes complete `Audit.LlmCall` + `Audit.ToolCall` rows FK-linked to `Chat.History`. Validates: provider abstraction, retry/backoff, secret resolution, tool registry + dispatch policy gate (`MutatesState=0`), AgentLoop iteration cap (10) + 90s per-call timeout, chat-history persistence, `%OpenId(id, 4)` concurrent-tab serialization, structured error envelopes. **Maintainer can verify the agent works before staking pilot operators on a UI.**

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 2.1**: `Util.Json` helpers + `JsonTest` (null-emit, redact, deep-merge)
2. **Story 2.2**: `Util.RetryWithBackoff` + `RetryWithBackoffTest` (full-jitter exp backoff, Retry-After honoring, idempotency rules)
3. **Story 2.3**: `Util.EnvSecret` credential resolution ladder + `EnvSecretTest` (env-var → `Ens.Config.Credentials` → AES; never-log discipline)
4. **Story 2.4**: `Config.Agent` `%Persistent` schema + `AgentDefaults` (no `ApiKey` property — references only; pilot-tunable defaults)
5. **Story 2.5**: Audit ledger — `Audit.LlmCall` + `Audit.ToolCall` `%Persistent` schemas + `Audit.Emit` emit helpers + `AuditTest` infrastructure + `docs/audit-sql-recipes.md`
6. **Story 2.6**: `Chat.History` + `Chat.Turn` persistence + `%OpenId(id, 4)` concurrency lock + `ChatHistoryTest`
7. **Story 2.7**: Agent DTOs — `CallerContext`, `ProviderResponse`, `TurnResult`
8. **Story 2.8**: `LLM.Provider` abstract + `LLM.Util.MessageAdapter` + `LLM.Util.ToolDefAdapter` (canonical Anthropic wire shape)
9. **Story 2.9**: `LLM.OpenAIProvider` concrete (canonical → OpenAI adapter; per-call 90s timeout; LlmCall audit at boundary)
10. **Story 2.10**: `Tool.Base` abstract + `Tool.Registry` (dispatch + `MutatesState` policy gate + audit interceptor) + Task-0 probe (`%Dictionary.MethodDefinition` reflection on 2024.1) + `ToolBaseTest` + `ToolRegistryTest`
11. **Story 2.11**: Three example Inspection tools — `SessionSummary`, `SessionTimeline`, `MessageHeaders` + `InspectionToolTest` subset
12. **Story 2.12**: `Agent.AgentLoop` orchestration with iteration cap + concurrency lock + end-to-end smoke test against OpenAI mock validating audit completeness

### Story 2.1: `Util.Json` Helpers

As a developer building tools, providers, and audit emitters,
I want a `SessionAgent.Util.Json` class with helper methods for `%DynamicObject` operations that come up across the codebase,
So that I don't reinvent JSON-null emission, redaction, and deep-merge in every class that touches JSON (and so that those operations follow project rule conventions consistently).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Util.Json`
**When** they implement the helper methods
**Then** the class provides `EmitNull(pObj, pKey)` that calls `pObj.%Set(pKey, "", "null")` per project rule "While writing ObjectScript" (third parameter is the type hint — emits JSON `null`, NOT the string `"null"`)
**And** the class provides `Redact(pObj, pKeyList)` that returns a deep-cloned `%DynamicObject` with every property in `pKeyList` (and any nested occurrence) replaced with the literal string `"<redacted>"` — used by audit-log writers to scrub credential strings (NFR-S3)
**And** the class provides `DeepMerge(pBase, pOverlay)` that returns a new `%DynamicObject` combining `pBase` and `pOverlay` with overlay keys winning at any depth
**And** the class provides `IsObject(pValue)` and `IsArray(pValue)` predicates wrapping `$IsObject` + `%ClassName` checks for safe JSON-shape inspection
**And** every method follows project rule `%Status` convention (`Set tSC = $$$OK` first, `Quit tSC` last) where applicable, or returns the produced `%DynamicObject` directly with `Quit` for pure-functional helpers

**Given** `Test/JsonTest.cls` exercises the helpers
**When** the test runs
**Then** `EmitNull` produces JSON output where the resulting `%ToJSON()` string contains the literal `"key": null` (not `"key": "null"`)
**And** `Redact` correctly handles nested `%DynamicObject` and `%DynamicArray` containers — verified by feeding a 3-level-nested object with credential keys at each level
**And** `DeepMerge` correctly handles type-mismatch edge cases (overlay `null` overrides base value; overlay scalar overrides base object; overlay array replaces base array — does not concatenate)
**And** all assertions use macros (`$$$AssertEquals`, `$$$AssertTrue`) per project rule, NEVER methods (`..AssertX()`)

### Story 2.2: `Util.RetryWithBackoff`

As a developer implementing LLM provider HTTP calls,
I want a `SessionAgent.Util.RetryWithBackoff` class with full-jitter exponential backoff that honors provider `Retry-After` headers and respects mid-flight idempotency rules,
So that transient HTTP failures are recovered cleanly without double-charging the operator's LLM API or violating provider rate limits.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Util.RetryWithBackoff`
**When** they implement the retry orchestrator
**Then** the class declares Class Parameters `MaxAttempts = 4`, `BaseDelaySec = 1`, `MaxDelaySec = 32` (per architecture §"Calibration constants")
**And** the class provides `IsRetryable(pStatusCode, pErrorCategory) As %Boolean` returning true for 429 + 5xx, false for 4xx (except 429), false for non-HTTP errors except documented network classes
**And** the class provides `ParseRetryAfter(pHeaderValue) As %Integer` that parses `Retry-After` first as integer seconds, then as RFC 7231 HTTP-date, falling back to 0 when both fail
**And** the class provides `ParseGeminiRetryDelay(pErrorJson) As %Integer` extracting `error.details[].retryDelay` per Gemini's wire shape (regex `(\d+)s` → seconds), since Gemini does not emit `Retry-After`
**And** the class provides `ExpBackoffSec(pAttempt, pBaseSec, pCapSec) As %Numeric` returning a full-jitter random value in `[0, min(cap, base * 2^attempt))` per AWS-style full-jitter algorithm
**And** the class provides `Execute(pCallable, pHttpResponseHandler) As ProviderResponse` (or equivalent signature) that orchestrates: invoke `pCallable`, if response is retryable extract delay (provider-specific), sleep `MAX(provider-specified, ExpBackoffSec)`, retry up to `MaxAttempts` total — never retry on mid-flight network failures (request sent, response lost), surface those with `request-id` from response header per architecture §"LLM tool-call idempotency"

**Given** `Test/RetryWithBackoffTest.cls` exercises the retry matrix
**When** the test runs
**Then** `IsRetryable` returns true for 429, 500, 502, 503, 504 and false for 400, 401, 403, 404, 422
**And** `ParseRetryAfter` correctly parses both integer (`"30"` → 30) and HTTP-date (`"Wed, 21 Oct 2026 07:28:00 GMT"` → seconds-from-now) formats
**And** `ParseGeminiRetryDelay` correctly extracts `"45s"` → 45 from a representative Gemini error-response JSON
**And** `ExpBackoffSec` distributions stay within `[0, min(cap, base * 2^attempt))` over 1000 invocations
**And** `Execute` does NOT retry on a simulated mid-flight network failure (verified by mock that signals "request sent, response lost")
**And** `Execute` retries up to `MaxAttempts=4` total then surfaces a structured failure containing the last response's `request-id`

### Story 2.3: `Util.EnvSecret` Credential Resolution

As an Operator-Admin,
I want `SessionAgent.Util.EnvSecret` to resolve LLM provider API keys via the documented ladder (env-var → `Ens.Config.Credentials` → AES-encrypted custom store) without ever logging the resolved key value,
So that I can supply credentials via my preferred mechanism (containers favor env-var; traditional installs favor `Ens.Config.Credentials`) without changing application code (FR40, NFR-S3).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Util.EnvSecret`
**When** they implement the credential resolver
**Then** the class provides `Resolve(pEnvVarName, pCredentialName) As %String` that returns the resolved API key by checking sources in order: (1) `$SYSTEM.Util.GetEnviron(pEnvVarName)` if `pEnvVarName` is non-empty AND the env-var is set; (2) `##class(Ens.Config.Credentials).%OpenId(pCredentialName).Password` (or the equivalent IRIS API verified by reading `irislib/Ens/Config/Credentials.cls` per project rule "IRIS Library Source") if `pCredentialName` is non-empty; (3) custom AES-encrypted store via `$System.Encryption.AESGCMEncrypt`/`Decrypt` as last resort (interface stub in v1; full implementation deferred unless operator opts in)
**And** the method NEVER writes the resolved key value to `Write`, `^ClineDebug`, `Audit.LlmCall.RawRequestJson`, or any other persistent or log surface
**And** the method NEVER concatenates the key into any string that gets passed to a logger
**And** the method returns an empty string if no source resolves; the caller surfaces this as a structured error (no exception)

**Given** `Test/EnvSecretTest.cls` exercises the resolution ladder
**When** the test runs
**Then** when env-var is set, `Resolve` returns the env-var value
**And** when env-var is not set but `Ens.Config.Credentials` entry exists, `Resolve` returns the credential's password
**And** when neither source resolves, `Resolve` returns empty string
**And** a redaction test feeds a known-key string through a logging path mock and asserts the key value does NOT appear in any captured output (`Audit.LlmCall` rows, debug globals, `Write` capture)

**Given** the resolver is invoked during a real OpenAI call (Story 2.9)
**When** the resolved key is used in the `Authorization: Bearer <key>` header
**Then** the audit row written for that call (`Audit.LlmCall` from Story 2.5) contains a redacted authorization header (`"Authorization": "Bearer <redacted>"` or omitted entirely), NEVER the literal key

### Story 2.4: `Config.Agent` Persistence Schema + `AgentDefaults`

As an Operator-Admin (later, via Epic 6 UI),
I want a `SessionAgent.Config.Agent` `%Persistent` class storing per-agent runtime configuration (provider / model / max-tokens / temperature / system-prompt-override / credential-ref / endpoint-URL / enabled flag / search-chat retention),
So that the AgentLoop can read live config on every turn (NFR-O2 hot config change) without the operator restarting IRIS, and so that no API keys are ever persisted in config rows (NFR-S2).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Config.Agent`
**When** they implement the `%Persistent` class
**Then** the class declares properties `AgentName As %String` (key, values: `session-inspection` | `message-search`), `Provider As %String` (values: `openai` | `anthropic` | `gemini` | `openai-compatible`), `Model As %String`, `MaxTokens As %Integer`, `Temperature As %Numeric`, `SystemPromptOverride As %String(MAXLEN=8192)` (optional), `CredentialName As %String` (named entry in `Ens.Config.Credentials`), `EnvVarName As %String` (env-var key), `EndpointUrl As %String` (operator-supplied for OpenAI-compatible), `ReadOnly As %Boolean = 1`, `Enabled As %Boolean = 0` (operator opts in via Zen UI in Epic 6), `SearchChatRetentionDays As %Integer = 30`
**And** the class has NO `ApiKey` property — only `CredentialName` and `EnvVarName` references (NFR-S2 schema discipline)
**And** the class declares `Index AgentNameIdx On AgentName [Unique]` so lookup by `AgentName` is O(1)
**And** Storage section is auto-generated by the IRIS compiler (per project rule "Storage Sections" — never hand-edit)

**Given** the developer is implementing `SessionAgent.Config.AgentDefaults`
**When** they implement the helper class
**Then** `GetSystemPrompt(pAgentName) As %String` returns a per-agent default system prompt string (Inspection: explains read-only invariant + 13-tool affordance; Search: explains bounded-WHERE invariant + curated-list affordance — content from architecture / research)
**And** `GetSeedConfig(pAgentName) As Config.Agent` returns a populated (un-saved) `Config.Agent` instance with provider/model defaults per architecture OD4 (OpenAI: `gpt-4.1-mini`; Anthropic: `claude-sonnet-4-5`; Gemini: `gemini-2.5-pro`; Ollama-compat: `qwen2.5:32b`) — used by `Installer.Install` Story 1.5 to seed the two agent rows

**Given** the Story 1.5 `Installer.Install` defensive seeding logic was originally guarded against `Config.Agent` not existing
**When** Epic 2 ships Story 2.4 and the install runs again
**Then** Installer successfully seeds two rows (`session-inspection` and `message-search`) with `Enabled=0` and the OD4 defaults
**And** subsequent installs are idempotent (no duplicate rows; `AgentNameIdx` unique constraint enforces)

### Story 2.5: Audit Ledger Schema + Emit Helpers + Recipe Doc

As a System (audit infrastructure) and an Operator-Admin (audit reviewer),
I want `SessionAgent.Audit.LlmCall` and `SessionAgent.Audit.ToolCall` `%Persistent` classes plus emit helper methods on `SessionAgent.Audit.Emit`, plus `docs/audit-sql-recipes.md` with sample SQL queries,
So that every LLM round-trip and every tool dispatch is captured at FK-linked granularity (FR32, FR33, FR34, NFR-S4 100% completeness) and operators can review audit data via standard IRIS SQL with no separate audit UI (FR35, NFR-O3).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Audit.LlmCall`
**When** they implement the `%Persistent` class
**Then** the class declares properties `Timestamp As %String` (ISO-8601 UTC per project rule — `$Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"`), `ChatHistory As Chat.History` (FK reference), `Provider As %String`, `Model As %String`, `RequestMessageCount As %Integer`, `RequestTokens As %Integer`, `ResponseTokens As %Integer`, `LatencyMs As %Integer`, `StopReason As %String`, `CacheHitTokens As %Integer` (Anthropic prompt-cache reporting; 0 for providers without cache support), `IsError As %Boolean`, `ErrorText As %String(MAXLEN=4096)` (operator-readable + stack-trace tail; never key material per NFR-S3)
**And** Storage is auto-generated

**Given** the developer is implementing `SessionAgent.Audit.ToolCall`
**When** they implement the `%Persistent` class
**Then** the class declares properties `Timestamp` (ISO-8601 UTC), `ChatHistory As Chat.History` (FK), `ToolName As %String`, `ArgsJson As %String(MAXLEN=8192)`, `ResultJson As %String(MAXLEN=32768)`, `LatencyMs As %Integer`, `IsError As %Boolean`, `ErrorText As %String(MAXLEN=4096)`, plus search-agent enrichment columns `ResultSetSize As %Integer`, `QueryTemplate As %String(MAXLEN=2048)`, `IndexUsed As %String` (nullable; populated only for search-agent tool dispatches per architecture)
**And** Storage is auto-generated

**Given** the developer is extending `SessionAgent.Audit.Emit` (which already provides `EnsureEvents()` from Story 1.3)
**When** they add the emit helper methods
**Then** `LogLlmCall(pChatHistoryId, pProvider, pModel, pRequestMessageCount, pRequestTokens, pResponseTokens, pLatencyMs, pStopReason, pCacheHitTokens, pIsError, pErrorText) As %Status` writes one `Audit.LlmCall` row synchronously and emits a native IRIS audit event via `$System.Security.Audit("SessionAgent","LlmCall",pProvider,...)` per architecture §"Audit event triples"
**And** `LogToolCall(pChatHistoryId, pToolName, pArgsJson, pResultJson, pLatencyMs, pIsError, pErrorText, pResultSetSize, pQueryTemplate, pIndexUsed) As %Status` writes one `Audit.ToolCall` row synchronously + emits native audit event
**And** both methods scrub credential strings from arg/result JSON via `Util.Json.Redact` (NFR-S3) before persisting
**And** both methods check the `%Save()` return status and surface failure via `%Status` (per project rule "Write Status Checking") — NFR-S4 forbids silently discarding write failures

**Given** `Test/AuditTest.cls` validates 100% completeness
**When** the test exercises the emitters
**Then** for N invocations of `LogLlmCall`, `count(*) FROM SessionAgent_Audit.LlmCall` equals N
**And** for M invocations of `LogToolCall`, `count(*) FROM SessionAgent_Audit.ToolCall` equals M
**And** the FK columns reference valid `Chat.History` rows
**And** a redaction test feeds a request-args JSON containing a known credential string and asserts the persisted `ArgsJson` does NOT contain the credential value

**Given** `docs/audit-sql-recipes.md` is authored
**When** the doc is committed
**Then** the doc contains at minimum these example queries with explanatory headers: "How many tokens did we spend yesterday?", "What tools did the agent dispatch in the last hour?", "Any timeouts or errors today?", "Which sessions had the highest tool-call count?", "Are any audit rows orphaned (missing FK)?"
**And** every query uses `%EXACT()` discipline on string predicates per project rule
**And** every query is verifiable on a populated `SessionAgent.Audit.*` namespace (no syntax errors)

### Story 2.6: `Chat.History` + `Chat.Turn` Persistence + Concurrency Lock

As a System (chat persistence layer),
I want `SessionAgent.Chat.History` `%Persistent` keyed `(AgentName, SessionKey, PortalUser)` storing the canonical-Anthropic-shape turns array as a `%Stream.GlobalCharacter`, plus `%OpenId(id, 4)` exclusive lock acquisition at the top of every turn, plus `Chat.Turn` value-object for serialization,
So that two browser tabs serialize their turns (FR46, NFR-P4), Inspection-keying vs Search-keying are distinct (FR43), and the chat-history row is a stable FK target for audit rows (FR34).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Chat.History`
**When** they implement the `%Persistent` class
**Then** the class declares properties `AgentName As %String` (`session-inspection` | `message-search`), `SessionKey As %String` (Inspection: Ens session id; Search: registry-issued GUID), `PortalUser As %String`, `TurnsJson As %Stream.GlobalCharacter` (canonical Anthropic-shape turns array), `CreatedAt As %String` (ISO-8601 UTC), `UpdatedAt As %String` (ISO-8601 UTC), `ConfigSnapshot As %String(MAXLEN=2048)` (provider/model pin at conversation start, for audit traceability)
**And** the class declares `Index ConvKeyIdx On (AgentName, SessionKey, PortalUser) [Unique]` — lookup is O(1)
**And** the class provides `LoadOrCreate(pAgentName, pSessionKey, pPortalUser) As Chat.History` that returns the row (acquiring `%OpenId(id, 4)` exclusive lock) or creates and saves a new row if none exists for the key tuple

**Given** the developer is implementing `SessionAgent.Chat.Turn`
**When** they implement the value-object class
**Then** the class provides `ToCanonical() As %DynamicObject` returning a turn in canonical Anthropic shape (`{role: "user|assistant|tool", content: [{type, text|tool_use|tool_result, ...}], usage: {...}}`) suitable for inclusion in `TurnsJson`
**And** `FromCanonical(pCanonicalTurnObj) As Chat.Turn` parses the canonical shape back into a Turn instance for in-memory manipulation

**Given** `Test/ChatHistoryTest.cls` validates concurrency
**When** the test fires two simultaneous `LoadOrCreate` + `%Save` cycles against the same `(AgentName, SessionKey, PortalUser)` key from two pseudo-process contexts
**Then** the second `LoadOrCreate` blocks on the first's `%OpenId(id, 4)` lock until the first `%Save` completes
**And** both turns persist in the canonical-Anthropic-shape `TurnsJson` array in the order their locks released
**And** OR (alternative architecture): one of the two contexts surfaces a structured "another turn is in progress" error (NFR-P4 acceptance allows either path)

**Given** the persistence shape is exercised end-to-end
**When** an Inspection-keyed row (`AgentName='session-inspection', SessionKey='1184729'`) and a Search-keyed row (`AgentName='message-search', SessionKey='<guid>'`) both exist
**Then** they coexist independently with no key collision (FR43)
**And** querying by key tuple returns the correct row in each case

### Story 2.7: Agent DTOs

As a developer wiring the AgentLoop, providers, and tools together,
I want `SessionAgent.Agent.CallerContext`, `SessionAgent.Agent.ProviderResponse`, and `SessionAgent.Agent.TurnResult` data-transfer objects with declared shapes,
So that the function signatures across the trust boundary are explicit and type-checkable rather than `%DynamicObject` blobs.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Agent.CallerContext`
**When** they implement the registered class
**Then** the class declares properties `AgentName As %String`, `IrisSessionId As %String` (Inspection only; empty for Search), `SearchSessionKey As %String` (Search only; empty for Inspection), `PortalUser As %String`, `Namespace As %String` (passthrough only — tools NEVER read `$NAMESPACE` per NFR-S6 anti-pattern checklist)

**Given** the developer is implementing `SessionAgent.Agent.ProviderResponse`
**When** they implement the registered class
**Then** the class declares properties `Content As %DynamicArray` (canonical Anthropic content array of `{type: "text|tool_use", ...}` blocks), `StopReason As %String` (`end_turn` | `max_tokens` | `stop_sequence` | `tool_use`), `Usage As %DynamicObject` (`{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`)

**Given** the developer is implementing `SessionAgent.Agent.TurnResult`
**When** they implement the registered class
**Then** the class declares properties `AssistantMarkdown As %String(MAXLEN=65536)` (final rendered answer), `UsageRollup As %DynamicObject` (turn-level token totals), `DurationMs As %Integer`, `ToolCallsRendered As %DynamicArray` (per-card UI payloads — name + args + result + status — for browser rendering)
**And** the class provides `ToJson() As %String` returning the JSON payload that ZenMethod hyperevent returns to the browser

**Given** these DTOs are pure data classes (no business logic)
**When** the test suite is run
**Then** simple instantiation and round-trip serialization tests pass for each DTO
**And** no DTO depends on any other Epic 2 class beyond `Util.Json` (Story 2.1) for JSON serialization helpers

### Story 2.8: `LLM.Provider` Abstract + Adapter Utilities

As a developer adding the first concrete LLM provider (Story 2.9),
I want `SessionAgent.LLM.Provider` abstract base class plus `LLM.Util.MessageAdapter` and `LLM.Util.ToolDefAdapter` utility classes that establish the canonical Anthropic wire shape and the adapter pattern,
So that the FR28 "5th-provider extensibility" contract has its plug-in point defined before the first concrete provider lands (Story 2.9).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.LLM.Provider`
**When** they implement the abstract base
**Then** the class is marked `[Abstract]` with the project-rule curly-brace bodies returning the appropriate type per "Abstract Methods in ObjectScript"
**And** the class declares abstract methods `CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As Agent.ProviderResponse) As %Status` and `GetEndpointUrl() As %String` and `GetAuthHeader(pApiKey As %String) As %String` and `GetProviderName() As %String`
**And** the class provides a non-abstract template method `Invoke(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, pConfigAgent, Output pProviderResponse) As %Status` that resolves the API key via `Util.EnvSecret.Resolve(pConfigAgent.EnvVarName, pConfigAgent.CredentialName)` (Story 2.3), wraps the concrete `CallMessages` in `Util.RetryWithBackoff.Execute` (Story 2.2), enforces the 90s per-call timeout (FR29), and writes the `Audit.LlmCall` row at the boundary (Story 2.5)
**And** the class doc comment explicitly states the FR28 "one new subclass + one registry entry, no shared-infra edits" contract

**Given** the developer is implementing `SessionAgent.LLM.Util.MessageAdapter`
**When** they implement the canonical-shape adapter utility
**Then** the class provides `CanonicalToProvider(pProviderName, pCanonicalHistory) As %DynamicArray` translating canonical Anthropic-shape history into the provider-specific wire (OpenAI: stringify tool_use args; Gemini: camelCase property names; Anthropic: passthrough; OpenAI-compatible: same as OpenAI)
**And** the class provides `ProviderToCanonical(pProviderName, pProviderResponseRaw) As %DynamicObject` translating the provider's response back into canonical shape
**And** the canonical shape is documented inline (one-paragraph doc comment with the canonical block-types list: `text`, `tool_use`, `tool_result`)

**Given** the developer is implementing `SessionAgent.LLM.Util.ToolDefAdapter`
**When** they implement the tool-definition adapter utility
**Then** the class provides `CanonicalToProvider(pProviderName, pCanonicalToolDefs) As %DynamicArray` converting `{name, description, input_schema}` triples into the provider's expected wire shape
**And** OpenAI mapping wraps each tool in `{type: "function", function: {...}}` per OpenAI Chat Completions spec
**And** Gemini mapping wraps each tool in `{functionDeclarations: [...]}` per Gemini generateContent spec
**And** Anthropic mapping passes through unchanged (canonical IS Anthropic)

**Given** `Test/MessageAdapterTest.cls` and `Test/ToolDefAdapterTest.cls` exercise the adapters
**When** the tests run
**Then** round-trip `CanonicalToProvider` then `ProviderToCanonical` preserves semantic content (block ordering, tool args, tool results) for each provider
**And** tool-arg object → string → object round-trip across the OpenAI adapter preserves all keys with no semantic loss (per architecture §"Innovation → Validation Approach")

### Story 2.9: `LLM.OpenAIProvider` Concrete

As an Operator-Admin who has configured OpenAI as the active provider,
I want `SessionAgent.LLM.OpenAIProvider` to issue OpenAI Chat Completions API calls per-call-90s-timeout-capped, with full audit logging, retry/backoff on 429+5xx, and credential resolution via the documented ladder,
So that the AgentLoop (Story 2.12) has a working LLM backend that exercises the canonical-wire adapter (FR27) and the provider abstraction (FR28) hardest from day one (per architecture OD4 OpenAI-first ship priority).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.LLM.OpenAIProvider`
**When** they implement the concrete subclass of `LLM.Provider`
**Then** the class implements `GetEndpointUrl()` returning `Config.Agent.EndpointUrl` if set OR `https://api.openai.com/v1/chat/completions` as default
**And** the class implements `GetAuthHeader(pApiKey)` returning `"Authorization: Bearer "_pApiKey`
**And** the class implements `GetProviderName()` returning `"openai"`
**And** the class implements `CallMessages(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, Output pProviderResponse)` that: builds the request body via `LLM.Util.MessageAdapter.CanonicalToProvider("openai", pCanonicalHistory)` and `LLM.Util.ToolDefAdapter.CanonicalToProvider("openai", pToolDefs)`, issues the HTTPS POST via `%Net.HttpRequest` (`Https=1`, `SSLConfiguration="DefaultSSL"`, `Timeout=90`), parses the response body via `LLM.Util.MessageAdapter.ProviderToCanonical("openai", ...)` populating `pProviderResponse`, and returns `%Status`
**And** the method is wrapped by `LLM.Provider.Invoke` (Story 2.8) for retry/audit/timeout enforcement — the concrete only does wire work

**Given** the request body construction
**When** the test inspects the constructed payload
**Then** the payload contains `model` from `Config.Agent.Model`, `messages` array per OpenAI shape, `tools` array per OpenAI shape (`{type: "function", function: ...}`), `temperature` from `Config.Agent.Temperature`, `max_tokens` from `Config.Agent.MaxTokens`
**And** the payload does NOT contain the API key in any field — auth is in the `Authorization` header only
**And** the payload does NOT contain `cache_control` markers (OpenAI auto-caches ≥1024 tokens; no per-call control)

**Given** an integration test exercises the provider against a mock OpenAI endpoint
**When** the mock returns a 200 response with a `tool_use` block
**Then** `pProviderResponse.Content` contains the tool_use in canonical Anthropic shape (object-form args, NOT stringified JSON — adapter translation has happened)
**And** `pProviderResponse.StopReason` reflects OpenAI's `finish_reason` translated to canonical (`stop` → `end_turn`, `length` → `max_tokens`, `tool_calls` → `tool_use`)
**And** `pProviderResponse.Usage` reflects OpenAI's token counts in canonical shape
**And** an `Audit.LlmCall` row is written by `LLM.Provider.Invoke` (Story 2.8) at the boundary, FK-linked to the chat-history row passed in the caller context

**Given** the mock returns a 429 with `Retry-After: 1`
**When** `Provider.Invoke` orchestrates the retry per `Util.RetryWithBackoff` (Story 2.2)
**Then** the retry honors the 1s delay
**And** total attempts cap at `MaxAttempts=4`
**And** if all attempts fail, the method returns a structured `%Status` error (no exception bubble) and writes an `IsError=1` audit row

**Given** the mock takes 91 seconds to respond
**When** `Provider.Invoke` enforces the per-call 90s timeout cap (NFR-P1)
**Then** the call is aborted before 91s
**And** an `IsError=1` audit row is written with `ErrorText` indicating timeout
**And** the method returns a structured timeout-error envelope per FR37

### Story 2.10: `Tool.Base` Abstract + `Tool.Registry` + Task-0 Probe

As a developer adding the first three Inspection tools (Story 2.11),
I want `SessionAgent.Tool.Base` abstract base class enforcing the FR55–FR58 dispatch contract, plus `SessionAgent.Tool.Registry` with reflection-based tool enumeration (`%Dictionary.MethodDefinition`) and the L2 dispatch policy gate (`MutatesState=0` check) plus audit interceptor,
So that tool implementations follow a uniform pure-dispatch contract and the read-only invariant (NFR-S1 Layer 2) is structurally enforced.

**Acceptance Criteria:**

**Given** the developer is preparing this story
**When** they run the Task-0 probe per architecture §"Carry-forward Task-0 probes" Epic 2
**Then** they execute `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` against a live IRIS 2024.1+ instance
**And** the captured output (the returned `%Dictionary.MethodDefinition` object's `%ToJSON()` or equivalent string representation) is recorded verbatim in the story's Tasks/Subtasks block
**And** if the probe returns a null reference, the story is escalated for re-design (since `Tool.Registry.ListTools` reflection depends on `%Dictionary.MethodDefinition` being available)

**Given** the developer is implementing `SessionAgent.Tool.Base`
**When** they implement the abstract base
**Then** the class is marked `[Abstract]` with project-rule curly-brace bodies
**And** the class declares Class Parameters `ToolName As %String`, `Description As %String`, `MutatesState As %Boolean = 0` (FR56)
**And** the class declares abstract methods `GetInputSchema() As %DynamicObject` (returns `{type: "object", properties: {...}, required: [...], additionalProperties: false}` per architecture §"Tool input JSON Schema subset"), `Invoke(pCallerCtx As Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status`
**And** the class enforces the seven anti-patterns (FR55, NFR-S6) by code-review checklist + the doc comment explicitly enumerates them: no `%session.Data`, no `%request`, no Zen state, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals, no `Write !,...` streaming

**Given** the developer is implementing `SessionAgent.Tool.Registry`
**When** they implement the registry
**Then** `ListTools() As %DynamicArray` introspects `%Dictionary.ClassDefinition` for all subclasses of `SessionAgent.Tool.Base` in the current namespace, returning `[{name, description, input_schema}, ...]` (FR57 — MCP-introspectable)
**And** `Dispatch(pToolName, pCallerCtx, pJsonArgs, Output pResult) As %Status` performs in order: (1) lookup the tool class by `ToolName`; (2) **L2 read-only enforcement** — reject with structured error if `tool.MutatesState=1` (FR36); (3) measure latency via `$ZH`; (4) invoke `tool.Invoke(...)` inside an outer try/catch that converts any escaping exception into a structured `{isError:true, content:[{type:"text", text: ex.DisplayString()}]}` envelope (FR37, defense-in-depth — tools should pre-surface their own errors); (5) write the `Audit.ToolCall` row via `Audit.Emit.LogToolCall` (Story 2.5); (6) return the `%Status`

**Given** `Test/ToolBaseTest.cls` and `Test/ToolRegistryTest.cls` validate the contract
**When** the tests run
**Then** a stub `Tool.Base` subclass with `MutatesState=1` is rejected by `Registry.Dispatch` with a structured error envelope (NOT an exception)
**And** a stub tool that throws an exception in `Invoke` produces a structured error envelope at `Registry.Dispatch` (defense-in-depth wrap)
**And** `Registry.ListTools` returns all subclasses present in the test namespace
**And** every dispatch (success or failure) writes exactly one `Audit.ToolCall` row (NFR-S4 100% completeness)

**Architecture Notes (Story 2.0 triage carry-forward):**

ToolCall audit-event registration is owned by this story per Story 2.0 triage (cites Epic 1 retro 2026-05-02). Add `RegisterIfMissing(source, type, name)` helper to `SessionAgent.Audit.Emit` and call it from `SessionAgent.Tool.Registry.Dispatch` on first emit per tool name. Alternative: extend `EnsureEvents()` with the then-known tool-name universe + retain the lazy helper for late-added tools.

### Story 2.11: Three Example Inspection Tools

As a developer building the AgentLoop smoke test (Story 2.12),
I want three concrete Inspection tools implemented per the FR55–FR58 contract — `SessionSummary`, `SessionTimeline`, `MessageHeaders` — each reading `Ens.MessageHeader` for a given session id with `%EXACT()` SQL discipline and structured tool-result envelopes,
So that the AgentLoop has a working set of tools to dispatch against during end-to-end smoke testing (and as reference implementations for the remaining 10 tools in Epic 4).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.SessionSummary`
**When** they implement the concrete `Tool.Base` subclass
**Then** the class declares `Parameter ToolName = "session_summary"`, `Parameter Description = "Return shape, duration, error count, and root message class for an Ens session."`, `Parameter MutatesState = 0` (FR56)
**And** `GetInputSchema()` returns `{type: "object", properties: {session_id: {type: "string", description: "Ens session id"}}, required: ["session_id"], additionalProperties: false}`
**And** `Invoke(pCallerCtx, pJsonArgs, Output pResult)` validates `session_id` is non-empty (returns `{isError:true, content:[{type:"text",text:"missing session_id"}]}` if missing), runs a `%SQL.Statement.%Prepare`/`%Execute(?)` parameterized query against `Ens.MessageHeader` using `%EXACT()` on the predicate (per project rule), populates `pResult.structuredContent` with `{message_count, error_count, duration_ms, root_message_class}` and `pResult.content[0].text` with a one-line operator-readable summary (per architecture §"MCP tool-result envelope")
**And** the implementation matches the canonical example in architecture §"Pattern Examples → Good — canonical tool implementation skeleton"

**Given** the developer is implementing `SessionAgent.Tool.Inspection.SessionTimeline`
**When** they implement the concrete tool
**Then** input schema declares `session_id` (required), optional `from_time` and `to_time` (ISO-8601 UTC) for windowing
**And** the tool returns the chronological timeline of message events in the session — sender → receiver pairs with timestamps, statuses, and indices
**And** SQL uses `%EXACT()` on string predicates and projections per project rule
**And** structured content includes `{events: [...], event_count, time_span_ms}` and the text summary describes the timeline shape

**Given** the developer is implementing `SessionAgent.Tool.Inspection.MessageHeaders`
**When** they implement the concrete tool
**Then** input schema declares `session_id` (required), optional `min_severity` (filter)
**And** the tool returns the `Ens.MessageHeader` rows for the session as `{headers: [{id, source_config_name, target_config_name, body_class, status, time_created, is_error}, ...]}`
**And** SQL uses `%EXACT()` discipline

**Given** `Test/InspectionToolTest.cls` (subset for these three tools) validates the implementations
**When** the tests run against a populated `Ens.MessageHeader` test fixture (a known session with N messages, K errors)
**Then** `SessionSummary` returns `message_count=N, error_count=K`
**And** `SessionTimeline` returns events in chronological order
**And** `MessageHeaders` returns N rows with the expected column shape
**And** every tool's response shape conforms to the MCP envelope (`content[]` + `structuredContent`)
**And** tools called with missing `session_id` return structured error envelopes (NOT exceptions)

### Story 2.12: `Agent.AgentLoop` Orchestration + End-to-End Smoke Test

As a maintainer (and indirectly, the operator who'll benefit when Epic 3's UI ships),
I want `SessionAgent.Agent.AgentLoop.RunTurn(...)` orchestrating the full per-turn state machine — load chat history with concurrency lock, read live `Config.Agent`, append user message, loop ≤ `MaxIterationsPerTurn=10` LLM round-trips with tool dispatch, write all audit rows, save chat history (releases lock), build TurnResult — and a `%UnitTest`-runnable smoke test exercising end-to-end against a mock OpenAI endpoint with the three Story 2.11 tools,
So that the maintainer can verify the full backend works before staking pilot operators on the UI in Epic 3.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Agent.AgentLoop`
**When** they implement the orchestrator
**Then** the class declares Class Parameters `MaxIterationsPerTurn = 10`, `PerCallProviderTimeoutSec = 90` (per architecture §"Calibration constants")
**And** `RunTurn(pAgentName, pSessionKey, pPortalUser, pUserText, pContextHints) As Agent.TurnResult` performs in this order: (a) build `CallerContext` from `%session.Username` resolved AT THE BOUNDARY (NEVER inside a tool — per NFR-S6 anti-pattern checklist); (b) `Chat.History.LoadOrCreate(...)` acquiring the `%OpenId(id, 4)` lock; (c) read live `Config.Agent` row by `pAgentName` (NFR-O2 hot config — re-read on every turn); (d) append user message to `history.turns`; (e) loop up to `MaxIterationsPerTurn` iterations: invoke `LLM.Provider.Invoke` (Story 2.8), parse response content for `tool_use` blocks, dispatch each via `Tool.Registry.Dispatch` (Story 2.10), append tool_result blocks to history, continue unless `StopReason ∈ {end_turn, max_tokens, stop_sequence}`; (f) hitting `MaxIterationsPerTurn` cap appends a synthetic "max-iterations reached, please summarize" assistant turn + breaks; (g) `%Save` history (releases lock); (h) build and return `TurnResult`
**And** the orchestrator NEVER throws exceptions — all errors surface as `TurnResult` with structured error content (per FR37)
**And** the orchestrator writes ALL `Audit.LlmCall` and `Audit.ToolCall` rows synchronously per NFR-S4 100% completeness (delegated to `Provider.Invoke` and `Registry.Dispatch` respectively)

**Given** `Test/AgentLoopTest.cls` validates orchestration mechanics
**When** the test exercises the loop with mock provider and stub tools
**Then** the `MaxIterationsPerTurn=10` cap is enforced (a runaway tool-loop hits the cap and surfaces the synthetic "max-iterations" message)
**And** `%OpenId(id, 4)` lock is acquired at top of `RunTurn` and released on `%Save` (verified by lock-table inspection during a paused-mid-turn breakpoint OR by a concurrent-tab test that confirms serialization)
**And** if `Provider.Invoke` returns an error `%Status`, `RunTurn` builds a `TurnResult` with the structured error content and still saves the chat history (lock release on `%Save`) — no half-state

**Given** the end-to-end smoke test (`Test/SmokeTest.cls`)
**When** the test invokes `RunTurn` against a mock OpenAI provider returning a deterministic 2-turn dialog (turn 1: assistant requests `session_summary`; turn 2: assistant produces final answer with `end_turn`) with the three Story 2.11 tools available against a populated `Ens.MessageHeader` test fixture
**Then** the returned `TurnResult.AssistantMarkdown` contains the deterministic final answer text
**And** `count(*) FROM SessionAgent_Audit.LlmCall WHERE ChatHistory=<id>` equals 2 (one row per provider HTTP round-trip)
**And** `count(*) FROM SessionAgent_Audit.ToolCall WHERE ChatHistory=<id>` equals 1 (one row for the `session_summary` dispatch)
**And** the FK linkage holds (every audit row references a valid `Chat.History.%Id()`)
**And** the `Chat.History.TurnsJson` stream contains the canonical-shape turns array with the 4 expected entries (user, assistant tool_use, tool_result, assistant final)

**Given** the smoke test runs against a live IRIS 2024.1+ instance with a real OpenAI API key supplied via env-var (NOT mock — gated behind a CI secret)
**When** the test invokes `RunTurn` with a real Ens session id
**Then** the test passes end-to-end: real OpenAI call → real tool dispatch against real `Ens.MessageHeader` → audit rows written → answer text contains expected substrings
**And** this test gates the maintainer-validation milestone (PRD §"Pre-alpha demo-able milestone" — but operator-validation gate is Epic 3, not this story)

---

## Epic 3: Inspection Agent — UI MVP Demo-able Milestone

**Operator outcome:** Operator opens Visual Trace on a real failed session, clicks the new "Ask the agent" tab, types *"what happened?"*, watches tool-call cards advance in sequence as the three example tools dispatch, and reads a grounded answer with clickable citation chips that navigate to the cited row in the parent's existing rule-log / event-log / message-headers panel. **The first delight moment** — Marisol-style senior on-call operator can validate the *fit* claim on a real incident. Returning to the same session shows the prior conversation. **PRD MVP exit criterion gates at end of this epic.**

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 3.1**: Chat Panel HTML Draw Helper + Minimum CSS Tokens (`EnsPortal.Util.ChatPanelDrawHelper` + `UI.ChatPanel` CSS contributors + minimum `--sa-*` token set)
2. **Story 3.2**: Client-Side `chat-panel.js` MVP — input submission, agent response rendering, tool-call cards, citation-chip anchors, fallback Markdown-as-text render path (UX-DR14)
3. **Story 3.3**: `SessionAgent.EnsPortal.VisualTrace` subclass — "Ask the agent" tab placement + `SendChatMessage` ZenMethod hyperevent + returning-conversation surfacing on tab open
4. **Story 3.4**: Citation chips with parent `selectItem`/`updateTabs` integration — six variants, partial off-page sync (MVP scope; Growth-tier full sync resolved by Story 10.8 per AC-6)
5. **Story 3.5**: Empty states + config-empty prompt (admin variant) + provider-error envelopes
6. **Story 3.6**: Cross-Browser Smoke Test + Accessibility Inheritance Verification
7. **Story 3.7**: PRD MVP Exit Criteria Validation — Pilot Operator Walkthrough on a Real Failed Session
8. **Story 3.8**: Programmatic Cross-Session Disclosure — server-side `AgentLoop` notice when tool args contain `session_id` ≠ `pSessionKey` (closes Story 3.7 deferred-work binding entry per Rule 9)
9. **Story 3.9**: Sample Interoperability Production + Walkthrough Re-Run on Rich Data (`SessionAgent.Sample.*` package — adapterless BS + ≥2 BPs + ≥2 BOs + scenario method with success/error injection; rich message bodies; not installed via IPM `<Resource>`; closes the partial portion of PRD MVP Exit Criterion #2)

### Story 3.1: Chat Panel HTML Draw Helper + Minimum CSS Tokens

As a developer building the Inspection Agent UI,
I want a `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper` class providing `OnDrawContent("DrawChatPanel")` that emits the chat panel's static HTML structure, plus a `SessionAgent.UI.ChatPanel` CSS-contributor class providing the minimum `--sa-*` token set and `sa-*` component classes needed for MVP visual coherence,
So that the Visual Trace subclass (Story 3.3) can include the chat panel via a single Zen `OnDrawContent` call and the rendered panel inherits Mgmt Portal styling per UX-DR26.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`
**When** they implement the helper class
**Then** the class provides `DrawChatPanel(pAgentName, pSessionKey, pPortalUser) As %Status` that emits the chat panel's static HTML using `&html<...>` per Zen convention: a `<section role="region" aria-label="Agent chat panel" class="sa-chat-panel">` (UX-DR1), an empty `<div class="sa-message-transcript">` for the message blocks, an empty `<div class="sa-status-text" aria-live="polite"></div>` (UX-DR6), and a `<form class="sa-input-area">` containing a `<textarea class="sa-input-field" aria-label="...">` (UX-DR10) — placeholder text comes from `Inspection: "Ask anything about this session"` per agent context
**And** the helper does NOT include any `<script>` blocks itself — script inclusion is the host page's responsibility (Story 3.3 wires it up via `OnPageHeadStyle`/`OnPageHeadScript`)
**And** the helper writes per-instance JS bootstrap data via a `<script>` block populated from server-side context — `window.SessionAgentChat = {agentName: "...", sessionKey: "...", portalUser: "..."};` — so `chat-panel.js` (Story 3.2) can read context without DOM scraping

**Given** the developer is implementing `SessionAgent.UI.ChatPanel`
**When** they implement the CSS contributor
**Then** the class provides a method that emits `<style>` content (or contributes to the host page's `XData Style`) defining ONLY the minimum `--sa-*` tokens needed for MVP — at minimum: `--sa-message-operator-bg`, `--sa-message-agent-bg`, `--sa-tool-card-border`, `--sa-tool-card-status-running`, `--sa-tool-card-status-complete`, `--sa-tool-card-status-error`, `--sa-citation-chip-bg`, `--sa-citation-chip-text`, `--sa-status-text-color`, `--sa-error-text-color` (UX-DR12-MVP-subset)
**And** the contributor defines `sa-*` component class rules that reference parent palette via inheritance — NO hardcoded hex/rgba per UX-DR26 (token values resolve against parent `EnsPortal.Application.cls` palette)
**And** parent Mgmt Portal styling is inherited entirely for foundation layer (font-family, font-size, line-height, button styles, form controls — none of these are overridden by `sa-*` rules)
**And** styling supports the seven anti-patterns of UX-DR28 (no-modals): no `position: fixed` overlays, no `z-index` games beyond inherited Zen layering, no animation keyframes beyond what Zen renders by default

**Given** a unit test inspects the rendered output
**When** the test invokes `DrawChatPanel("session-inspection", "1184729", "marisol.rivera")`
**Then** the output contains the `sa-chat-panel`, `sa-message-transcript`, `sa-status-text`, `sa-input-area`, `sa-input-field` class names (semantic structure verified)
**And** the output contains the `<script>window.SessionAgentChat = ...</script>` bootstrap with the correct context values
**And** the output passes basic HTML structural validity (every opened tag closed; no `<div onclick>` patterns per UX-DR19)

### Story 3.2: Client-Side `chat-panel.js` MVP Render & Submit

As an Operator using the chat tab in Visual Trace,
I want the client-side `chat-panel.js` to handle: typing in the input field, pressing Enter to submit (Shift+Enter for newline), seeing a "Thinking..." status text appear, watching tool-call cards render in sequence as the agent dispatches tools, reading the final answer with inline citation chips, and clicking a tool-card to expand its raw input/output,
So that I can have a usable conversation with the agent — even though the vendored Markdown bundle (UX-DR13) hasn't shipped yet (per UX-DR14 fallback render path).

**Acceptance Criteria:**

**Given** the developer is authoring `chat-panel.js` for MVP
**When** the file is committed (inline `<script>` in the host page during MVP; vendored at `/csp/static/iris-session-agent/` during Growth tier)
**Then** the script attaches input handlers per UX-DR30: Enter → submit, Shift+Enter → newline, Esc → cancel mid-flight (when implemented; MVP can no-op Esc with a TODO)
**And** the script auto-focuses `.sa-input-field` on tab open + after every Enter submission (UX-DR16)
**And** on submit, the script invokes `zenPage.SendChatMessage(agentName, sessionKey, userText, contextHints)` (Story 3.3 wires the ZenMethod hyperevent), parses the returned JSON `TurnResult`, and renders message blocks + tool-call cards into `.sa-message-transcript`

**Given** the agent dispatches tools during a turn
**When** the response payload contains `toolCallsRendered[]` entries
**Then** the script renders each as a `<details class="sa-tool-call-card sa-tool-card-status-{running|complete|error}">` containing `<summary>` (status indicator + monospace tool name + one-line summary text) + body (tool input args + result rendered as `<pre><code>` blocks for raw inspection) per UX-DR3
**And** the cards render in dispatch order
**And** the operator can expand/collapse cards via native `<details>`/`<summary>` keyboard interaction (UX-DR19)

**Given** the agent's final answer is a Markdown string
**When** the script renders the answer in MVP fallback mode
**Then** the script applies the simpler render path per UX-DR14: paragraph splits on double-newline, inline citation-chip patterns (e.g., `[rule_log:42]`) become `<a class="sa-citation-chip sa-cite-{rule|event|message|ack|iolog|tool}" href="#" data-cite-type="..." data-cite-id="...">` (rendering only — onclick handler lands in Story 3.4), code-block patterns (` ```...``` `) become `<pre><code>` with the language class for future Prism integration
**And** the rendering does NOT yet include vendored `marked` or `Prism.js` — that lands in Epic 10
**And** the rendering does NOT use `innerHTML` on untrusted strings — uses `textContent` for plain text, `createElement`+`setAttribute` for citation chips and tool cards (XSS safety in absence of DOMPurify which lands in Epic 10)

**Given** an integration test exercises the script via headless Chrome (or jsdom)
**When** the test simulates a turn with assistant text + 2 tool-call cards + 3 citation chips
**Then** the rendered DOM contains the expected `sa-*` class structure
**And** clicking a tool-card `<summary>` toggles the `<details>` open state (native browser behavior; verified via DOM state)
**And** the citation chips have correct `data-cite-type` and `data-cite-id` attributes (onclick handler lands in Story 3.4)

**Given** the agent dispatch produces a provider error
**When** the response payload contains an `error` field per UX-DR18-MVP-subset
**Then** the script renders an `sa-message-block sa-msg-agent sa-msg-error` block with the operator-readable error text + retry hint
**And** the input field re-enables after error rendering (operator can retry without page reload)

### Story 3.3: `EnsPortal.VisualTrace` Subclass — Tab Placement + ZenMethod + Returning-Conversation Surfacing

As an Operator opening Visual Trace on a session,
I want a new "Ask the agent" tab right-appended to the existing Visual Trace tab strip, so that clicking it opens the chat panel scoped to the current session — and if I'm returning to a session I've discussed before, my prior conversation appears in the transcript before the input field auto-focuses,
So that the chat experience feels embedded in the page I'm already in (UX-DR15-Inspection) and continuity is automatic per UX-DR17-MVP-subset.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.EnsPortal.VisualTrace`
**When** they implement the Zen page subclass of `EnsPortal.VisualTrace`
**Then** the class is at the path `src/SessionAgent/EnsPortal/VisualTrace.cls` per architecture §"Project Directory Structure"
**And** the subclass extends the parent's tab strip XData by appending a new `<tab caption="Ask the agent" id="askAgentTab">` to the *right* of all existing tabs per UX-DR15-Inspection (operators reach existing tabs by muscle memory; ours sits adjacent without disrupting established order)
**And** the new tab's body content is rendered via `OnDrawContent("DrawChatPanel")` calling `##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel("session-inspection", ..%GetParameter("SESSIONID"), %session.Username)`
**And** the host page contributes `chat-panel.js` (Story 3.2) via `OnPageHeadScript` (or equivalent Zen mechanism)

**Given** the developer is implementing the `SendChatMessage` ZenMethod hyperevent
**When** they implement the method
**Then** the method signature matches `ClassMethod SendChatMessage(pAgentName As %String, pSessionKey As %String, pUserText As %String, pContextHintsJson As %String) As %String [ZenMethod]`
**And** the method resolves caller context (`%session.Username` → `pPortalUser`) AT THE BOUNDARY (per architecture §"Caller context propagation" — never inside a tool)
**And** the method invokes `##class(SessionAgent.Agent.AgentLoop).RunTurn(pAgentName, pSessionKey, pPortalUser, pUserText, pContextHintsJson)` and returns the `TurnResult.ToJson()` string for client-side parsing
**And** the method does NOT throw exceptions — any escape converts to a structured error JSON (FR37 / UX-DR18)

**Given** an Operator opens Visual Trace on a session they've previously discussed
**When** the chat tab is clicked
**Then** the panel renders with the prior conversation transcript visible (loaded from `Chat.History.TurnsJson` — Story 2.6 persistence), scrolled to the most recent message
**And** the input field placeholder text changes from *"Ask anything about this session."* (first-time) to *"Continue the conversation."* (returning) per UX-DR17-MVP-subset
**And** the input field auto-focuses (UX-DR16)
**And** loading the history does NOT block tab open beyond ~50ms perceptible latency

**Given** an Operator opens Visual Trace on a session with no prior conversation
**When** the chat tab is clicked (first-time state)
**Then** the panel renders with a welcome message rendered as `sa-message-block sa-msg-agent` (NOT a separate splash component per UX-DR17 rules)
**And** the welcome message content is: ~3 lines covering capability summary + read-only assertion + 3 example questions (e.g., *"I can read this session's headers, bodies, event log, rule log, and BP state. I can't change anything; I only read. Try: what happened? · why did the rule fire? · show me the failing body."*)
**And** the input field auto-focuses with placeholder *"Ask anything about this session."*

**Given** the page is included in `module.xml`'s `<Resource Name="SessionAgent.PKG"/>`
**When** the package is installed and the operator navigates to `/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=1184729` (HealthShare URL pattern) OR `/csp/<NS>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=1184729` (plain-IRIS URL pattern)
**Then** the page loads with all parent Visual Trace functionality intact (existing tabs work, SVG renders, header/body panels populate)
**And** the new "Ask the agent" tab is visible in the tab strip
**And** clicking the tab opens the chat panel without errors

### Story 3.4: Citation Chips with Parent `selectItem`/`updateTabs` Integration

As an Operator reading an agent's grounded answer with inline citation chips like `[rule_log:42]`,
I want clicking a citation chip to navigate me to the cited row in the parent Visual Trace's existing rule-log / event-log / header / IO-log panel — staying inside the same page (no new tabs, no popups) — and for `sa-cite-tool` chips, scroll-and-expand the corresponding tool-call card in the chat transcript,
So that I can verify any claim in the agent's answer with one click (FR11) and the trust loop is complete in the MVP per UX-DR4-MVP + UX-DR24-MVP.

**Acceptance Criteria:**

**Given** the developer is implementing the citation-chip click handler
**When** they implement `ClientMethod onCitationClick(type, id, klass)` on `SessionAgent.EnsPortal.VisualTrace`
**Then** the method dispatches by `type`: `rule|event|message|ack|iolog` → parent-panel navigation; `tool` → in-chat scroll-and-expand
**And** for parent-panel navigation, the method first attempts on-page navigation: invokes `zenPage.svgPage.selectItem(null, type, svgId, id, klass, line)` (parameters per parent's `EnsPortal.VisualTrace` API — verified by reading `irislib/EnsPortal/VisualTrace.cls` source per project rule "IRIS Library Source") which auto-updates `zenPage.currentId/currentType/currentClass` + triggers `updateTabs(true)` + highlights the SVG box
**And** for off-page items (cited row not on the current SVG page), the method sets `zenPage.currentId/currentType/currentClass` directly and calls `zenPage.updateTabs(true)` — Header tab re-renders with the cited row's details; SVG highlight does NOT update (operator can navigate pages manually) — accepted MVP partial sync per UX-DR24-MVP (MVP partial-sync limitation — Header tab updates, SVG stays; **Growth-tier full sync per UX-DR24-Growth resolved by Story 10.8 with pragmatic-acceptance fallback** — see `deferred-work.md` §"Story 10.8 AC-3 pragmatic-acceptance fallback" for the future-epic page-of-row lookup work item)

**Given** a `sa-cite-tool` chip is clicked
**When** the handler dispatches the `tool` type
**Then** the method scrolls the chat transcript to the corresponding tool-call card (looked up by `data-cite-id` matching the card's data-tool-call-id) and forces the `<details>` open via setting `open` attribute
**And** the highlight effect (subtle background flash via CSS animation, OR `outline` style) fades after ~1 second so the operator's eye lands on the right card

**Given** the citation chip is rendered as a real `<a>` element per UX-DR4-MVP + UX-DR19
**When** the operator hovers, focuses, or clicks the chip
**Then** native anchor behavior provides hover state (browser default `cursor: pointer` + parent palette hover background via `--sa-citation-chip-bg`)
**And** keyboard focus shows the parent's standard focus ring
**And** Enter on a focused chip triggers the same `onCitationClick` (default anchor activation)
**And** the chip has descriptive `aria-label` per UX-DR20-MVP — e.g., `aria-label="Rule log entry 42 — view in Header tab"`

**Given** an integration test exercises citation navigation
**When** the test renders a chat transcript with citation chips referencing on-page and off-page rule-log entries, then simulates clicks
**Then** on-page clicks correctly invoke `selectItem` with the right parameters (verified by mock spying on `zenPage.svgPage.selectItem` calls)
**And** off-page clicks correctly invoke `updateTabs(true)` after setting current refs
**And** `sa-cite-tool` clicks correctly scroll-and-expand the matching tool-call card

### Story 3.5: Empty States + Config-Empty Prompt + Provider-Error Envelopes

As an Operator-Admin (first install) and an Operator (mid-conversation),
I want clear empty-state and error-state messaging in the chat panel: when no agent is configured (admin variant of `sa-config-empty-prompt` linking to `SessionAgent.UI.AgentConfig.zen` — though that page lands in Epic 6), and when a provider call times out or fails (operator-readable error envelopes in the transcript with retry hints),
So that I always know what to do next per UX-DR17-MVP-subset and UX-DR18-MVP-subset — never seeing a blank panel or a stack-trace.

**Acceptance Criteria:**

**Given** the developer is implementing the no-config detection
**When** the chat tab opens AND no `Config.Agent` row exists for the agent OR `Config.Agent.Enabled=0`
**Then** the chat panel renders an `sa-config-empty-prompt` element replacing the transcript area + disables the input field per UX-DR7-admin
**And** if the operator has the `%SessionAgent_Admin` role (or equivalent admin role — TBD with the user; default: any user with `%All` or matching the role check), the prompt includes a link to `SessionAgent.UI.AgentConfig.zen` — Epic 6's config page (which doesn't exist yet, so MVP renders the link as a placeholder with the URL displayed but the link target is "not yet implemented — coming in Epic 6")
**And** if the operator does NOT have admin privileges, the prompt text reads *"This agent isn't configured yet. Ask your operator-admin."* with no link
**And** the prompt has `role="alert"` per UX-DR20-MVP
**And** the input field has `aria-disabled="true"` plus visual de-emphasis per UX-DR20-MVP

**Given** the developer is implementing provider-error envelope rendering
**When** `Agent.AgentLoop.RunTurn` returns a `TurnResult` with structured error content (e.g., 90s timeout from Story 2.9, 4xx provider auth error, 5xx provider unavailable)
**Then** the chat panel renders an `sa-message-block sa-msg-agent sa-msg-error` block in the transcript with operator-readable text per UX-DR18-MVP-subset:
  - **Provider timeout (90s cap)**: *"The LLM call exceeded 90 seconds. The provider may be overloaded or the question too complex. Try again or simplify."*
  - **Provider network/auth/rate-limit error**: *"Couldn't reach `<provider>`: `<reason>`. Check the provider's status or your API key."*
  - **No-config error** (caught here as fallback if Story 2.12 wasn't loaded): *"This agent isn't configured. An operator-admin needs to set up an LLM provider."*
**And** the input field re-enables after error rendering (operator can retry without page reload)
**And** the audit row written by Story 2.5 captures the full error context (with stack trace in `ErrorText`); the operator-facing message contains NO stack trace per UX-DR18

**Given** a tool dispatch fails mid-turn (one of the dispatched tools returned `{isError:true, ...}`)
**When** the tool-call card renders
**Then** the card shows red `×` status indicator + the error reason in the summary slot per UX-DR21 (color + text label, not color alone)
**And** the agent continues processing with degraded context (per architecture §"Concurrent tool errors don't halt the agent") — final answer renders below the failed card with a note about the limitation
**And** the operator does NOT see a panel-level error for tool failures; only per-card status

### Story 3.6: Cross-Browser Smoke Test + Accessibility Inheritance Verification

As a maintainer preparing for the MVP demo-able milestone,
I want a documented manual smoke-test pass on the latest two versions of Chrome / Firefox / Safari / Edge (NFR-C6) plus a keyboard-navigation + screen-reader announcement check (NFR-A1) on at least one of those browsers,
So that we know the chat panel inherits Mgmt Portal accessibility characteristics correctly per UX-DR19 + UX-DR20 + UX-DR21 + UX-DR22 — without making accessibility commitments beyond the parent.

**Acceptance Criteria:**

**Given** the maintainer is preparing the cross-browser smoke test
**When** they author a checklist in `docs/testing/cross-browser-smoke.md` (or equivalent location)
**Then** the checklist enumerates per-browser steps: (1) open Visual Trace on a known-failed session, (2) click "Ask the agent" tab, (3) type a question, press Enter, (4) observe status text → tool-call cards → final answer rendering sequence, (5) click a citation chip, observe parent panel update, (6) click a tool-call card, observe expand/collapse, (7) close + reopen tab, observe returning-conversation surfacing
**And** the checklist documents the latest two versions of Chrome, Firefox, Safari, and Edge as the support matrix per NFR-C6
**And** README is updated to reference the support matrix (per NFR-C6 README documentation)

**Given** the maintainer runs the cross-browser smoke test on each browser
**When** they execute all 7 steps on each browser
**Then** all steps pass on Chrome, Firefox, Safari, and Edge (latest two versions each)
**And** any browser-specific defects are logged as separate issues (NOT blocking this story unless catastrophic)

**Given** the maintainer runs the keyboard-navigation check on at least one browser
**When** they navigate the chat panel using only Tab / Shift+Tab / Enter / Space / Esc
**Then** focus moves through: input field → (if focused-then-Tab) citation chips → tool-card summaries → input field again (no focus traps, no skipped elements)
**And** Enter on a focused citation chip activates the click handler (Story 3.4)
**And** Space or Enter on a focused tool-card `<summary>` toggles the `<details>` open state (native browser behavior)
**And** Esc during mid-flight turn cancels (when implemented; MVP can no-op with a TODO)

**Given** the maintainer runs the screen-reader announcement check on at least one browser
**When** they enable VoiceOver (Safari/Chrome on macOS) OR NVDA (Firefox/Chrome on Windows) and exercise the chat panel
**Then** `sa-status-text` updates announce via `aria-live="polite"` per UX-DR20
**And** new agent message blocks announce via the most-recent-message wrapper's `aria-live="polite"` per UX-DR20
**And** `sa-config-empty-prompt` (when shown) announces via `role="alert"` per UX-DR20
**And** citation chips read as links with their descriptive `aria-label` per UX-DR4-MVP

**Given** the maintainer runs the contrast verification per UX-DR23
**When** they inspect the resolved `--sa-*` token values against parent palette
**Then** `--sa-citation-chip-text` on `--sa-citation-chip-bg` meets WCAG AA contrast (4.5:1 for body text)
**And** `--sa-tool-card-status-error` against parent background meets WCAG AA contrast (3:1 for non-text content)
**And** any contrast failures are documented with proposed token-value adjustments

### Story 3.7: PRD MVP Exit Criteria Validation — Pilot Operator Walkthrough

As the maintainer (Joshua) and the first pilot operator (Marisol-class senior on-call engineer),
I want a documented walkthrough on a real failed Ens session where the operator types *"what happened?"* into the chat tab and gets a coherent grounded answer with verifiable citations, completed within an operator's tolerance for "this is better" (target: ≤ 1 min for a common diagnostic per NFR-P5 commitment-grade — 5 min → 1 min),
So that we explicitly satisfy the [PRD §"Product Scope MVP exit criteria"](prd.md): (1) pre-alpha demo-able OpenAI-powered Inspection Agent reaches an operator's hands, (2) ≥1 operator self-reports a real diagnosis, (3) audit log shows all 3 example tools dispatched at least once.

**Acceptance Criteria:**

**Given** the MVP is built (Stories 3.1–3.6 + Epic 1 + Epic 2 complete) and installed on a pilot IRIS instance
**When** the maintainer prepares the pilot operator walkthrough
**Then** the maintainer identifies a real failed Ens session from the pilot operator's recent on-call history (not a synthetic test fixture)
**And** the maintainer ensures Web Gateway timeout is raised to 300s (Story 1.2 README prereq), `SessionAgent_ReadOnly` is granted to the pilot operator (Story 1.4), an OpenAI API key is configured (Story 2.3 EnvSecret resolution), and the `Config.Agent` row for `session-inspection` is `Enabled=1` with provider=openai, model=gpt-4.1-mini (Story 1.5 Installer seeded; flipped to enabled manually)

**Given** the pilot operator opens Visual Trace on the chosen real-failed session
**When** they click "Ask the agent" and type *"what happened?"* (or an equivalent natural-language opening)
**Then** the operator sees status text within ~1 second
**And** they see tool-call cards advance for at least one of the three Story 2.11 tools (`session_summary`, `session_timeline`, `message_headers`)
**And** they read a final answer that the maintainer verifies aligns with the operator's prior post-mortem of the session (or the operator's understanding if no formal post-mortem exists)
**And** they click at least one citation chip and observe the parent Visual Trace panel updating to the cited row (Story 3.4)

**Given** the walkthrough completes successfully
**When** the maintainer inspects the audit log
**Then** `count(*) FROM SessionAgent_Audit.LlmCall WHERE Provider='openai'` ≥ 1
**And** `count(*) FROM SessionAgent_Audit.ToolCall WHERE ToolName IN ('session_summary','session_timeline','message_headers')` ≥ 1 (each tool dispatched at least once across the pilot conversations)
**And** the operator self-reports the time-to-resolution: target ≤ 1 minute on this common-diagnostic pattern per NFR-P5 (validated by self-report; not a CI-measurable test)
**And** the maintainer captures a 1-paragraph operator quote (or summary) for the release notes

**Given** the operator finds the experience useful (qualitative)
**When** the maintainer documents the walkthrough outcome
**Then** the maintainer updates `docs/operator-quickstart.md` (Story 1.6) with any feedback that warrants addition (e.g., "operator was confused about X — added clarifying step Y")
**And** the maintainer files any defects as separate issues (NOT blocking this story unless they invalidate the MVP exit criteria)
**And** the **PRD §Product Scope MVP exit criterion is formally met** — release tag `v0.1.0-mvp-demo` is created OR the maintainer's milestone tracker is updated to mark "MVP demo-able" reached

### Story 3.8: Programmatic Cross-Session Disclosure

As an **Operator who may legitimately ask the agent to compare details between sessions**,
I want any cross-session tool dispatch (where `tool_args.session_id` ≠ `chat_tab.bound_session_id`) to produce a deterministic operator-facing notice in the agent's final response — even when the LLM forgets to disclose the cross-session reach itself,
So that I always see when the agent has reached outside the bound session, and the audit ledger + the in-turn UI agree on the scope of the dispatch.

This closes the Story 3.7 lead-driven walkthrough's deferred-work entry binding cross-session-disclosure programmatic enforcement to a future story (Rule 9 — see `deferred-work.md` §"Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03) — system-prompt-only cross-session disclosure unreliable"). Added to Epic 3 via Sprint Change Proposal 2026-05-03 after the Story 3.7 walkthrough Turn 5 empirically demonstrated that system-prompt-only enforcement is unreliable when conversation context is dominated by same-session prior turns.

**Acceptance Criteria:**

**Given** the developer is implementing the cross-session detection in `Agent.AgentLoop.RunTurn`
**When** the iteration loop processes a tool's `args` after dispatch
**Then** the loop inspects `args` for a `session_id` value (when present)
**And** if the value differs from `pSessionKey`, the loop appends to a per-turn `tCrossSessionList` ($listbuild of distinct session-ids reached outside scope)
**And** the inspection handles missing-`session_id` gracefully (most tool calls carry a `session_id` arg; tools that don't are unaffected)

**Given** the iteration loop completes
**When** `tCrossSessionList` is non-empty
**Then** the final assistant text emitted by `RunTurn` is server-side-prepended with: *"Note: this turn dispatched tools against session(s) X (and Y, etc.) outside this chat's bound session N. Audit ledger captured all dispatches."* — followed by a paragraph break + the original assistant text
**And** the notice substring is locked by a unit test in `Test/AgentLoopGuardsTest.cls` named `TestRunTurnAppendsCrossSessionNotice`

**Given** the audit ledger semantics from Story 2.5
**When** the cross-session notice is appended
**Then** `Audit.LlmCall` and `Audit.ToolCall` rows still contain the bound `pSessionKey` as `ChatHistoryId` linkage (no audit-row schema change)
**And** the cross-session reach is detectable post-hoc via `SELECT %EXACT(Args) FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = N AND %EXACT(Args) [ '"session_id":"M"'` for any `M ≠ N`

**Given** the Story 3.5 system-prompt language already encourages the LLM to disclose cross-session reaches
**When** the LLM does disclose AND the server-side notice is also appended
**Then** the operator sees both — duplicate disclosure is acceptable (defense-in-depth). The LLM's prose disclosure is conversational; the server-side notice is deterministic. They reinforce each other; they don't conflict.

**Given** the existing 5+ Epic 3 walkthrough turns
**When** an integration test re-runs Story 3.7 Turn 5 (*"Show me what's in session 2"*) against the updated AgentLoop
**Then** the final assistant text begins with the *"Note: this turn dispatched..."* sentence
**And** the cross-session reach is operator-visible regardless of LLM compliance with the system-prompt instruction

### Story 3.9: Sample Interoperability Production + Walkthrough Re-Run on Rich Data

As **the maintainer + pilot operator validating the agent against richer data than the dev install's 4-message-zero-error baseline**,
I want a purpose-built `SessionAgent.Sample.*` interoperability solution — adapterless Business Service callable via a public ClassMethod, ≥2 Business Processes, ≥2 Business Operations, configurable error injection, rich enough message bodies for the agent to answer multi-step diagnostic questions — installed separately from the IPM `<Resource>` so it's clearly a test fixture not runtime,
So that PRD MVP Exit Criterion #2's "real diagnosis through the agent" portion is empirically reproducible AND Epic 4's Story 4.7 ("comprehensive read-only suite verification") has rich data to inspect against.

Added to Epic 3 via Sprint Change Proposal 2026-05-03 after the Story 3.7 walkthrough exposed the dev install's data-thinness (4 sessions / 0 errors) as a structural blocker for richer empirical validation.

**Acceptance Criteria:**

**Given** the developer is implementing the sample-production scaffolding
**When** they ship the `SessionAgent.Sample.*` package
**Then** the package contains an adapterless Business Service (e.g., `SessionAgent.Sample.BS.OrderIngest`) with a public `ClassMethod RunScenario(pErrorMode As %String = "none") As %Status` where `pErrorMode ∈ {none, businessProcessFailure, businessOperationFailure, providerError, partialSuccess}` (or similar — actual list to be finalized in dev). Each scenario produces a multi-step trace ending in the corresponding outcome.
**And** the package contains ≥ 2 Business Processes (e.g., `Sample.BP.OrderRouter`, `Sample.BP.OrderValidator`) with realistic step sequences (3–5 steps each)
**And** the package contains ≥ 2 Business Operations (e.g., `Sample.BO.SqlPersist`, `Sample.BO.FilePublish`) with adapter-less or stub-adapter implementations
**And** message bodies are rich — at minimum `Sample.Msg.Order` with patient-id-style identifier, line items, totals, status, audit notes (5–10 fields), enough field richness that the three Story 2.11 tools (`session_summary` / `session_timeline` / `message_headers`) produce interesting + distinctive output across scenarios

**Given** the developer is implementing the operator-invoked install path
**When** the operator runs `Do ##class(SessionAgent.Sample.Bootstrap).InstallProduction()`
**Then** the helper creates the production + enables it + logs operator instructions for invoking scenarios
**And** the helper is idempotent — re-running on an existing install does not duplicate or break anything
**And** the README operator section documents the install + scenario invocation

**Given** the developer is wiring the package into module.xml
**When** they edit module.xml
**Then** the `Sample.*` classes are NOT included in `<Resource Name="SessionAgent.PKG"/>` — the package is excluded from the IPM install path so it's clearly a test fixture, not runtime
**And** the README explains the rationale + the operator-invoked install path

**Given** the maintainer re-runs the Story 3.7 chrome-devtools-mcp walkthrough against the sample production
**When** they exercise at least one scenario WITH errors (e.g., `pErrorMode="businessOperationFailure"`)
**Then** the agent dispatches multiple tools across the multi-step trace
**And** the agent's final answer references real error context (status codes, error text, source/target config names)
**And** the walkthrough closes the partial portion of PRD MVP Exit Criterion #2 ("≥1 operator self-reports a real diagnosis happening through the agent" — capability demonstrated against real-shape data)

**Given** the developer adds tests
**When** they ship the test class(es)
**Then** at least 3 unit tests are added: `TestSampleProductionStarts`, `TestScenariosProduceExpectedMessageCounts`, `TestErrorInjectionProducesExpectedIsErrorCounts`
**And** per-class compile sweep is clean
**And** the regression-suite count grows by ≥ 3

**Sample-production scope CAP:** Story 3.9 ships ENOUGH richness for the agent demo — not a full healthcare-interop reference implementation. Realistic but minimal: 3–4 message types, 4–6 distinct scenarios. Future Growth-tier work may expand.

---

## Epic 4: Inspection Agent — Full Tool Catalogue

**Operator outcome:** Operator now has all 13 Inspection tools available — agent can answer the full range of cross-surface questions (event log filtered by severity, rule log decisions, BP source/instance/methods, complete message-body dispatch ladder for `%JSON.Adaptor` + virtual document + `%Stream.Object` + generic `%Persistent` shapes, `Ens.SuperSessionIndex` cross-instance trace, `Ens.SearchTableBase` body-field pivot, `%Status` decoder including IRIS-specific error codes). All 13 tools dispatched in production observed at least once during pilot.

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 4.1**: `EventLog` + `RuleLog` tools (paired log-table reads)
2. **Story 4.2**: `GetMessageBody` — 9-step body-class dispatch ladder (the most complex tool)
3. **Story 4.3**: `GetMessageDetail` (single-message header + body summary helper)
4. **Story 4.4**: BP introspection trio — `GetBusinessProcessSource` + `GetBusinessProcessInstance` + `ListBusinessProcessMethods`
5. **Story 4.5**: `FindRelatedSessions` (`Ens.SuperSessionIndex` cross-instance trace)
6. **Story 4.6**: `FindSessionsByBody` (`Ens.SearchTableBase` pivot)
7. **Story 4.7**: `ExplainError` + Comprehensive Read-Only Suite Verification (full 13-tool `InspectionToolTest`)

### Story 4.1: `EventLog` + `RuleLog` Tools

As an Operator asking the Inspection Agent about event-log entries and rule-log decisions for a session,
I want two tools — `event_log` and `rule_log` — that read `Ens.Util.Log` and `Ens.Rule.Log` respectively, filterable by session, message, and minimum severity (event_log) or by session and rule (rule_log),
So that the agent can ground answers about *what happened* and *why the rule fired* in the underlying log rows (FR5, FR6).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.EventLog`
**When** they implement the concrete `Tool.Base` subclass
**Then** the class declares `Parameter ToolName = "event_log"`, `Parameter Description = "Read Ens.Util.Log entries for a session, message, or severity filter."`, `Parameter MutatesState = 0`
**And** `GetInputSchema()` declares `session_id` (required), optional `message_id`, optional `min_severity` (`info` | `warning` | `error` | `assert`), optional `limit` (default 100)
**And** `Invoke` runs a `%SQL.Statement.%Prepare`/`%Execute(?)` parameterized query against `Ens.Util.Log` using `%EXACT()` discipline on string predicates and projections (per project rule)
**And** the returned `structuredContent` is `{events: [{id, time_logged, severity, source, text, session_id, message_id}, ...], event_count, severity_counts}` and `content[0].text` is a one-line summary

**Given** the developer is implementing `SessionAgent.Tool.Inspection.RuleLog`
**When** they implement the concrete subclass
**Then** the class declares `Parameter ToolName = "rule_log"`, `Parameter Description = "Read Ens.Rule.Log decisions for a session — return value, evaluated rule, component, triggering message."`, `Parameter MutatesState = 0`
**And** `GetInputSchema()` declares `session_id` (required), optional `rule_class` filter, optional `limit` (default 100)
**And** `Invoke` queries `Ens.Rule.Log` for the session, returning `{decisions: [{id, time_executed, rule_name, component, return_value, triggering_message_id, reason}, ...], decision_count}` plus a one-line summary
**And** the implementation reads `irislib/Ens/Rule/Log.cls` source per project rule "IRIS Library Source" before referencing column names

**Given** `Test/InspectionToolTest.cls` exercises both tools (subset for these two)
**When** the test runs against a fixture session with N event-log rows + K rule-log rows
**Then** `event_log` with no filter returns N rows; with `min_severity='error'` returns only error-or-worse rows; with a `message_id` filter returns only rows for that message
**And** `rule_log` returns K rows in chronological order
**And** both tools called with missing `session_id` return structured error envelopes per FR37
**And** both tools register in `Tool.Registry.ListTools()` with the correct schemas

### Story 4.2: `GetMessageBody` — 9-Step Body-Class Dispatch Ladder

As an Operator asking the Inspection Agent to *show me the failing body* of a message,
I want a `get_message_body` tool that opens any message body — regardless of body-class shape (`%JSON.Adaptor`, virtual document, `%Stream.Object`, generic `%Persistent`) — via a runtime dispatch ladder that picks the right rendering path,
So that the agent can ground answers about message content even when the body is HL7 / FHIR / X12 / custom XML / generic JSON / a plain stream (FR4).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.GetMessageBody`
**When** they implement the concrete tool
**Then** the class declares `Parameter ToolName = "get_message_body"`, `Parameter Description = "Open and render a message body via the runtime body-class dispatch ladder."`, `Parameter MutatesState = 0`
**And** `GetInputSchema()` declares `message_id` (required), optional `format` (`raw` | `summary` — default `summary`)
**And** `Invoke` implements the 9-step dispatch ladder per architecture / inspection-agent research §"Body-Class Dispatch Ladder":
  1. Look up `Ens.MessageHeader` for `message_id` to get `MessageBodyClassName`
  2. Open the body via `$ClassMethod(MessageBodyClassName, "%OpenId", MessageBodyId)` — handle null result
  3. If body is `EnsLib.HL7.Message` (or virtual-document subclass) → render as HL7 ER7 string + segment-by-segment summary
  4. If body extends `%JSON.Adaptor` → render via `body.%JSONExportToString()` + property summary
  5. If body extends `%XML.Adaptor` → render via XML export + element summary
  6. If body extends `%Stream.Object` (`%Stream.GlobalCharacter`, `%Stream.GlobalBinary`, `%Stream.FileCharacter`, etc.) → read first ~3KB + indicate truncation if longer
  7. If body extends `Ens.MessageBody` and has known property shape → reflect on `%Dictionary.ClassDefinition` + render properties as a key-value table
  8. If body extends generic `%Persistent` → fall back to `body.%ToJSON()` (registered objects) or `body.%GetParameter("ClassType")` reflection
  9. If none of the above → return a structured-content marker `{body_class, dispatch_failed: true, fallback_repr: "<class>:<id>"}` with a clear text summary
**And** the implementation reads relevant `irislib/` source for each body-class family before dispatching (project rule "IRIS Library Source")
**And** the returned `structuredContent` is `{message_id, body_class, body_id, render_strategy, body_repr, truncated, ...}` and `content[0].text` is a 1-3 line operator-readable summary

**Given** `Test/InspectionToolTest.cls` exercises the dispatch ladder
**When** the test runs against fixtures of each body-class family (HL7 ER7 message, JSON.Adaptor object, XML.Adaptor object, %Stream.GlobalCharacter, generic %Persistent)
**Then** each fixture returns the expected `render_strategy` reflecting the dispatch path taken
**And** the rendered `body_repr` matches the expected shape per family
**And** stream bodies longer than the truncation threshold (~3KB) report `truncated: true`
**And** unknown body classes fall back to step 9 without throwing

**Given** the tool is dispatched against a message with no body (`MessageBodyId = ""`)
**When** the dispatch ladder runs
**Then** the tool returns a structured envelope (NOT an exception) with `{render_strategy: "no_body", body_repr: ""}` and a clear text summary

### Story 4.3: `GetMessageDetail`

As an Operator asking the Inspection Agent for a full single-message readout,
I want a `get_message_detail` tool that bundles a message's `Ens.MessageHeader` row + a body summary (via `get_message_body` rendering pathway) + linked rule-log decisions,
So that the agent has a one-shot tool for single-message deep-dives without dispatching three separate tools (FR3 supplemental — header data) and answers about a specific message arrive in fewer agent iterations.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.GetMessageDetail`
**When** they implement the concrete tool
**Then** the class declares `Parameter ToolName = "get_message_detail"`, `Parameter Description = "Return full message header + body summary + linked rule-log decisions for a single message."`, `Parameter MutatesState = 0`
**And** `GetInputSchema()` declares `message_id` (required)
**And** `Invoke` reads the `Ens.MessageHeader` row for `message_id`, invokes the body-rendering pathway shared with `GetMessageBody` (Story 4.2 — the dispatch ladder may be extracted into a helper or directly invoked depending on Epic 8's G2 deferred-decision outcome), and queries `Ens.Rule.Log` for any decisions triggered by this message
**And** the returned `structuredContent` is `{header: {...}, body_summary: "...", body_repr: "...", rule_decisions: [...]}` and `content[0].text` is a 2-3 line operator-readable summary

**Given** `Test/InspectionToolTest.cls` exercises this tool
**When** the test runs against a fixture message with header + body + 2 rule-log decisions
**Then** the response includes the header row, the body summary via the dispatch ladder, and the 2 rule decisions
**And** if the message has no body, `body_repr` is empty + summary notes the absence
**And** if the message triggered no rule decisions, `rule_decisions` is an empty array

### Story 4.4: BP Introspection Trio

As an Operator asking the Inspection Agent about a Business Process's runtime behavior,
I want three tools — `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods` — that respectively read the BPL/custom-subclass source, the persistent BP instance row + `Ens.BP.Context` / `Ens.BP.Thread` state, and the BP class method list (via `%Dictionary.MethodDefinition` reflection),
So that the agent can ground answers about *why this BP awaited here* or *what the BPL was waiting for* in concrete BP-runtime evidence (FR7).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.GetBusinessProcessSource`
**When** they implement the concrete tool
**Then** input schema declares `bp_class_name` (required, e.g., `Ens.BusinessProcess` or a customer subclass)
**And** `Invoke` reads the BP class source via `%Dictionary.ClassDefinition.%OpenId(bp_class_name)` then iterates methods/properties/parameters → renders the source as a structured representation (NOT raw `.cls` text — operator-readable per architecture pattern)
**And** the returned `structuredContent` includes `{class_name, super_class, parameters, properties, methods: [{name, signature, comment, has_body}]}` and `content[0].text` is a one-line summary

**Given** the developer is implementing `SessionAgent.Tool.Inspection.GetBusinessProcessInstance`
**When** they implement the concrete tool
**Then** input schema declares `session_id` (required)
**And** `Invoke` queries the persistent BP instance row for the session — joins `Ens.BP.Context` + `Ens.BP.Thread` state per architecture / inspection-agent research §"BP Introspection"
**And** the returned `structuredContent` is `{session_id, bp_class, instance_id, state, current_response, awaiting_message_id, context: {...}, thread: {...}}` with operator-readable summary
**And** if no BP instance exists for the session, returns `{has_bp: false}` with a clear text summary (NOT an error envelope — absence is a valid answer)

**Given** the developer is implementing `SessionAgent.Tool.Inspection.ListBusinessProcessMethods`
**When** they implement the concrete tool
**Then** input schema declares `bp_class_name` (required)
**And** `Invoke` uses `%Dictionary.MethodDefinition` reflection (the Task-0 probe was validated in Epic 2 Story 2.10) to enumerate the BP class's methods + signatures + comments
**And** the returned `structuredContent` is `{class_name, methods: [{name, signature, return_type, formal_args, comment, is_classmethod}], method_count}` with summary

**Given** all three BP tools register in `Tool.Registry.ListTools()`
**When** `Test/InspectionToolTest.cls` exercises them against a fixture BP class + session
**Then** `get_business_process_source` returns the BP class structure
**And** `get_business_process_instance` returns the live BP instance state for the session
**And** `list_business_process_methods` returns the method list reflecting the test BP class

### Story 4.5: `FindRelatedSessions` (`Ens.SuperSessionIndex`)

As an Operator asking the Inspection Agent *what other sessions are related to this one* (cross-instance trace),
I want a `find_related_sessions` tool that joins `Ens.SuperSessionIndex` to enumerate sessions sharing a super-session key with the current session,
So that the agent can ground answers about cross-instance message flow when production sessions span multiple IRIS instances or BPs (FR8).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.FindRelatedSessions`
**When** they implement the concrete tool
**Then** input schema declares `session_id` (required)
**And** `Invoke` reads `Ens.SuperSessionIndex` for the session's super-session key, then queries `Ens.MessageHeader` (joined on the super-session key) returning related sessions per architecture / inspection-agent research §"SuperSessionIndex"
**And** SQL uses `%EXACT()` discipline on string predicates and projections per project rule
**And** the returned `structuredContent` is `{session_id, super_session_key, related_sessions: [{session_id, time_created, source_config_name, target_config_name, message_count}, ...], related_count}` with summary

**Given** `Test/InspectionToolTest.cls` exercises the tool
**When** the test runs against a fixture with 3 sessions sharing a super-session key
**Then** `find_related_sessions` for any of the 3 returns the other 2 in `related_sessions`
**And** for a session with no super-session entry (sessions can lack super-session keys), the tool returns `{related_sessions: [], related_count: 0}` with a clear text summary (NOT an error)

### Story 4.6: `FindSessionsByBody` (`Ens.SearchTableBase` Pivot)

As an Operator asking the Inspection Agent *what other sessions involve this same indexed body field value* (e.g., other sessions with this MRN, this account number, this order ID),
I want a `find_sessions_by_body` tool that pivots through `Ens.SearchTableBase` subclass extents (e.g., `EnsLib.HL7.SearchTable`) to find sessions whose body matched the indexed field-value pair,
So that the agent can answer cross-session correlation questions grounded in indexed body-field data (FR9).

**Acceptance Criteria:**

**Given** the developer is preparing this story (Task-0 probe per project rule "research-first.md")
**When** they run the `EnsLib.HL7.SearchTable` row-shape probe per architecture §"Carry-forward Task-0 probes" Epic 4 (re-anchored from Epic 8 — this is the FIRST story across the codebase that needs the SearchTable shape verified; Epic 8 Story 8.5 reuses the captured output)
**Then** they execute a query against `EnsLib.HL7.SearchTable` (or whatever SearchTable the operator's instance has populated) and capture verbatim row shape: column names, types, and one sample row
**And** the captured shape is recorded verbatim in this story's Tasks/Subtasks block (expected: `(DocId, PropName, PropValue)` per architecture §"Risk Mitigation → SearchTable shape verification")
**And** if the operator's instance has no `EnsLib.HL7.SearchTable` populated (HealthShare SearchTables not installed), the story documents the fallback behavior referenced by the next AC group below + Epic 8 Story 8.5's parallel fallback

**Given** the developer is implementing `SessionAgent.Tool.Inspection.FindSessionsByBody`
**When** they implement the concrete tool
**Then** input schema declares `search_table_class` (required, e.g., `EnsLib.HL7.SearchTable`), `prop_name` (required), `prop_value` (required), optional `time_window_hours` (default 168 = 7d), optional `limit` (default 50)
**And** `Invoke` validates `search_table_class` is a registered subclass of `Ens.SearchTableBase` (via `%Dictionary.CompiledClass` reflection); rejects with structured error if not
**And** `Invoke` queries the `<search_table_class>` extent for `(PropName, PropValue)` matches per the row shape verified in this story's Task-0 probe above, joins `Ens.MessageHeader` on `MessageBodyId`, applies `TimeCreated` window for safety (≤50 results)
**And** SQL uses `%EXACT()` discipline + parameterized prepare
**And** the returned `structuredContent` is `{search_table_class, prop_name, prop_value, sessions: [{session_id, time_created, source_config_name, target_config_name, message_id}, ...], session_count}` with summary

**Given** the SearchTable extent exists on the operator's instance (this story's Task-0 probe verified the row shape)
**When** `Test/InspectionToolTest.cls` exercises the tool against a fixture HL7 SearchTable
**Then** `find_sessions_by_body` for a known MRN value returns the sessions with that MRN
**And** the time-window filter respects `time_window_hours`
**And** `prop_value` containing wildcards is handled per the SearchTable's expected predicate semantics (no SQL injection — parameterized only)

**Given** the SearchTable class doesn't exist on the operator's instance (e.g., HealthShare SearchTables not installed)
**When** the tool is dispatched
**Then** it returns a structured error envelope with `"<search_table_class> is not installed in this namespace; body-field search is unavailable for this body class"` per architecture §"Risk Mitigation → SearchTable not installed"

### Story 4.7: `ExplainError` + Comprehensive Read-Only Suite Verification

As an Operator who saw a `<PROTECT>` or `<Ens>ErrBPTerm` or `<UNDEFINED>` error and wants a human-readable explanation,
I want an `explain_error` tool that decodes any `%Status` value into operator-readable text including IRIS-specific error codes,
And as a maintainer preparing the full 13-tool catalog for pilot,
I want a comprehensive `InspectionToolTest` that exercises every tool against fixtures + verifies the L1 read-only invariant (every tool declares `MutatesState=0`),
So that error explanations are grounded (FR10) and the L1 enforcement (NFR-S1 Layer 1) is structurally verified before pilot rollout.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Inspection.ExplainError`
**When** they implement the concrete tool
**Then** input schema declares `status_or_error_string` (required, accepts either a `%Status` serialized value OR an error code/message string)
**And** `Invoke` decodes the input via `$System.Status.GetErrorText` for `%Status` shapes, then maps known IRIS-specific codes (`<PROTECT>`, `<Ens>ErrBPTerm`, `<UNDEFINED>`, `<NOTOPEN>`, `<METHOD DOES NOT EXIST>`, etc.) to operator-readable explanations from a curated table
**And** the returned `structuredContent` is `{input, decoded_text, code_class, common_causes: [...], suggested_diagnostics: [...]}` with summary
**And** the curated table is maintained as a Class Parameter or a `%Dictionary` lookup (NOT hardcoded in the dispatch logic)

**Given** the developer is preparing the comprehensive read-only suite
**When** they author / extend `Test/InspectionToolTest.cls`
**Then** the test class iterates all 13 tools registered in `Tool.Registry.ListTools()` and asserts each has `MutatesState = 0` declared (NFR-S1 Layer 1 enforcement — CI fails any tool that omits or sets to 1 per architecture §"Validation Approach")
**And** the test exercises each tool against representative fixtures (one per tool minimum; complex tools like `GetMessageBody` get one per body-class family)
**And** the test validates: structured envelope shape on success (`content` + `structuredContent`), structured error envelope shape on failure (`isError: true` + `content`), no exceptions escape `Invoke` to the test runner
**And** the test runs end-to-end against an `Ens.MessageHeader` test fixture with sessions covering: simple ACK exchange, BPL await, HL7 message routing with rule decisions, error scenarios with event-log entries

**Given** the comprehensive suite is run as part of the per-release manual smoke test
**When** the maintainer executes `do ##class(%UnitTest.Manager).RunTest("SessionAgent.Test")` on a 2024.1+ instance with the test fixture loaded
**Then** all 13 tool tests pass
**And** the L1 enforcement test passes (every tool has `MutatesState=0`)
**And** test output documents which fixtures were used (so the test is reproducible)
**And** the **Epic 4 acceptance gate is met**: pilot operators can dispatch all 13 tools across real on-call sessions; audit log subsequently captures usage of each tool at least once during pilot

---

## Epic 5: Multi-Provider Support

**Operator outcome:** Operator-Admin can pick Anthropic, Google Gemini, or any OpenAI-compatible endpoint (Ollama, vLLM, self-hosted) instead of OpenAI. Tool-call-roundtrip integration test gates each provider against every bundled tool; Anthropic prompt-caching of `system + tools` prefix lands with `AnthropicProvider`; Gemini retry parses `error.details[].retryDelay` (no `Retry-After` header). Anthropic-canonical wire shape proven by reading two existing concretes — Tomás-class community contributor can add a 5th provider in ~187 lines.

Story order within this epic preserves the architect's sub-step rationale: **Anthropic ships first** (validates the canonical-wire inversion early — direct implementation, no adapter), then **Gemini** (camelCase wire + Gemini-specific retryDelay parsing), then **OpenAICompat** (covers Ollama / vLLM / any compatible endpoint with operator-supplied URL).

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 5.1**: `LLM.AnthropicProvider` concrete (canonical-shape native implementation + cache_control prompt-caching discipline)
2. **Story 5.2**: `LLM.GeminiProvider` concrete (camelCase wire + `error.details[].retryDelay` parsing + Gemini-specific error mapping)
3. **Story 5.3**: `LLM.OpenAICompatProvider` concrete (operator-supplied `EndpointUrl` for Ollama / vLLM / self-hosted)
4. **Story 5.4**: `Test/ToolCallRoundtripIntegrationTest.cls` (every provider × every tool against canned mocks per FR59) + per-release validation against real provider endpoints (gated behind CI secrets)

### Story 5.1: `LLM.AnthropicProvider` Concrete

As an Operator-Admin who wants to use Anthropic Claude as the active LLM provider,
I want `SessionAgent.LLM.AnthropicProvider` implementing the `LLM.Provider` abstract directly in the canonical Anthropic wire shape, with `cache_control` markers placed on the `system + tools` prefix to enable Anthropic prompt-caching,
So that the canonical-shape inversion (FR27, architecture Innovation §"Anthropic-canonical adapter inversion") is validated by a direct implementation that does NOT need adapter translation, and `system + tools` prefix achieves cache hits across consecutive turns within a chat session preserving NFR-P6.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.LLM.AnthropicProvider`
**When** they implement the concrete subclass of `LLM.Provider` (Story 2.8)
**Then** the class implements `GetEndpointUrl()` returning `Config.Agent.EndpointUrl` if set OR `https://api.anthropic.com/v1/messages` as default
**And** the class implements `GetAuthHeader(pApiKey)` returning two header lines: `"x-api-key: "_pApiKey` AND `"anthropic-version: 2023-06-01"` (per architecture §"External Integrations → Anthropic Messages API")
**And** the class implements `GetProviderName()` returning `"anthropic"`
**And** the class implements `CallMessages(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, Output pProviderResponse)` that: builds the request body in canonical Anthropic shape **without adapter translation** (canonical IS Anthropic), issues the HTTPS POST via `%Net.HttpRequest`, parses the response body, and populates `pProviderResponse`
**And** the request body's `system` field carries a `cache_control: {type: "ephemeral"}` marker per Anthropic's prompt-caching wire (FR30, NFR-P6)
**And** the request body's `tools` array carries a `cache_control: {type: "ephemeral"}` marker on the LAST tool definition per Anthropic's "cache up to this point" semantics
**And** the request body does NOT carry `cache_control` on user messages (vocabulary digest from Epic 9 sits in the *uncached* user-message prefix)

**Given** the request body construction
**When** the test inspects the constructed payload
**Then** the payload contains `model` from `Config.Agent.Model`, `messages` array per Anthropic shape (object-form tool args, NOT stringified JSON), `tools` array per Anthropic shape, `system` string from `pSystemPrompt`, `max_tokens` from `Config.Agent.MaxTokens`, `temperature` from `Config.Agent.Temperature`
**And** the payload's `system` AND last `tools[]` entry both carry `cache_control: {type: "ephemeral"}`
**And** the payload does NOT contain the API key in any field — auth is in headers only

**Given** an integration test exercises the provider against a mock Anthropic endpoint
**When** the mock returns a 200 response with `content: [{type: "tool_use", ...}]`
**Then** `pProviderResponse.Content` contains the tool_use block in canonical shape (passthrough — no translation)
**And** `pProviderResponse.StopReason` reflects Anthropic's `stop_reason` directly
**And** `pProviderResponse.Usage` includes `cache_creation_input_tokens` and `cache_read_input_tokens` from Anthropic's response (used by `Audit.LlmCall.CacheHitTokens` per Story 2.5)

**Given** an integration test simulates a multi-turn conversation
**When** the second turn re-uses the same `system + tools` prefix with `cache_control` markers
**Then** the mock's response indicates a `cache_read_input_tokens > 0` (cache hit on the prefix)
**And** the `Audit.LlmCall` row for the second turn captures `CacheHitTokens > 0` per architecture §"Audit metric: cache hit"
**And** NFR-P6 is verified: `system + tools` prefix is stable across turns within the cache-control breakpoint

**Given** the mock returns a 429 with `Retry-After: 2`
**When** `Provider.Invoke` orchestrates the retry per `Util.RetryWithBackoff` (Story 2.2)
**Then** the retry honors the 2s delay
**And** total attempts cap at `MaxAttempts=4`
**And** if all attempts fail, the method returns a structured `%Status` error and writes an `IsError=1` audit row

### Story 5.2: `LLM.GeminiProvider` Concrete

As an Operator-Admin who wants to use Google Gemini as the active LLM provider,
I want `SessionAgent.LLM.GeminiProvider` implementing the `LLM.Provider` abstract with `LLM.Util.MessageAdapter` translating canonical Anthropic shape to Gemini's camelCase wire (`generateContent` endpoint, `x-goog-api-key` auth) and a Gemini-specific retry parser extracting `error.details[].retryDelay` (since Gemini does NOT emit `Retry-After` headers),
So that operators can use Gemini 2.5/3 Pro models per OD4 default + the canonical-wire inversion is further validated by a third concrete provider with a notably different wire shape.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.LLM.GeminiProvider`
**When** they implement the concrete subclass
**Then** the class implements `GetEndpointUrl()` returning `Config.Agent.EndpointUrl` if set OR `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` substituting `Config.Agent.Model` (per architecture §"External Integrations → Gemini API")
**And** the class implements `GetAuthHeader(pApiKey)` returning `"x-goog-api-key: "_pApiKey`
**And** the class implements `GetProviderName()` returning `"gemini"`
**And** the class implements `CallMessages(...)` that builds the request body via `LLM.Util.MessageAdapter.CanonicalToProvider("gemini", ...)` and `LLM.Util.ToolDefAdapter.CanonicalToProvider("gemini", ...)` — both adapters from Story 2.8 must already handle the Gemini shape (camelCase keys, `functionDeclarations` wrapper for tools)

**Given** the developer is implementing `LLM.Util.GeminiRetryParser` (or extending `Util.RetryWithBackoff` with the Gemini-specific path per architecture §"HTTP retry-after parsing")
**When** they implement the parser
**Then** the parser extracts `error.details[].retryDelay` from Gemini error response JSON (regex `(\d+)s` → seconds)
**And** if `error.details[]` lacks a `retryDelay` entry, falls back to `Util.RetryWithBackoff.ExpBackoffSec` per Story 2.2

**Given** an integration test exercises the provider against a mock Gemini endpoint
**When** the mock returns a 200 response with a `functionCall` block
**Then** the adapter (Story 2.8) translates `functionCall` into canonical `tool_use` shape
**And** `pProviderResponse.Content` contains the canonical `tool_use` block
**And** `pProviderResponse.StopReason` reflects Gemini's `finishReason` translated to canonical (`STOP` → `end_turn`, `MAX_TOKENS` → `max_tokens`, etc.)

**Given** the mock returns a 429 with body `{"error": {"details": [{"retryDelay": "45s"}]}}`
**When** `Provider.Invoke` orchestrates the retry
**Then** the Gemini retry parser extracts 45 from the response body
**And** the retry honors the 45s delay
**And** the audit row's `ErrorText` (if all attempts fail) includes the parsed retry hint for diagnostic purposes

### Story 5.3: `LLM.OpenAICompatProvider` Concrete

As an Operator-Admin who wants to use a self-hosted Ollama / vLLM / OpenAI-compatible endpoint (zero per-token cost on self-hosted),
I want `SessionAgent.LLM.OpenAICompatProvider` implementing the `LLM.Provider` abstract with operator-supplied `EndpointUrl` (no default — operator MUST configure) and the OpenAI Chat Completions wire format,
So that operators can validate value with a managed provider then migrate to self-hosted if budget is a constraint per [PRD §Risk Mitigation](prd.md) "LLM API costs scare operators off".

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.LLM.OpenAICompatProvider`
**When** they implement the concrete subclass
**Then** the class implements `GetEndpointUrl()` returning `Config.Agent.EndpointUrl` (NO default — if `Config.Agent.EndpointUrl` is empty, the method returns empty + Provider.Invoke surfaces a structured error: *"OpenAI-compatible provider requires Config.Agent.EndpointUrl to be set (e.g., http://localhost:11434/v1/chat/completions for Ollama)."*)
**And** the class implements `GetAuthHeader(pApiKey)` returning `"Authorization: Bearer "_pApiKey` if `pApiKey` is non-empty, OR returns empty header (some self-hosted endpoints don't require auth) — operator decides via Config.Agent.EnvVarName / CredentialName setting
**And** the class implements `GetProviderName()` returning `"openai-compatible"`
**And** the class implements `CallMessages(...)` that builds the request body via the same adapter path as `OpenAIProvider` (Story 2.9) — `LLM.Util.MessageAdapter.CanonicalToProvider("openai", ...)` (since OpenAI-compat means OpenAI-shape)

**Given** an Operator-Admin configures the agent with `Provider="openai-compatible"`, `EndpointUrl="http://localhost:11434/v1/chat/completions"`, `Model="qwen2.5:32b"` per architecture OD4 default
**When** the AgentLoop dispatches a turn
**Then** the request POSTs to the operator's Ollama endpoint with OpenAI-format body
**And** the response is parsed via the OpenAI adapter (no special Ollama handling needed since Ollama exposes OpenAI-compatible endpoints)

**Given** an integration test exercises the provider against a mock OpenAI-compatible endpoint
**When** the mock returns a tool_call response in OpenAI shape
**Then** the adapter translates to canonical `tool_use` correctly
**And** `pProviderResponse.Usage` reflects the mock's reported token counts (OpenAI-shape `usage` object)

**Given** README §"Operator Prerequisites" Story 1.2 mentions OpenAI-compatible deployment
**When** the README is updated for Epic 5 release
**Then** the README documents the OpenAI-compatible setup path: example `Config.Agent` row for Ollama, example for vLLM, note about auth-optional self-hosted endpoints
**And** `docs/operator-quickstart.md` (Story 1.6) is extended with a brief "Switching to self-hosted" section pointing at the README example

### Story 5.4: Tool-Call-Roundtrip Integration Test Infrastructure

As a maintainer (and a community contributor adding a 5th provider per FR28),
I want `SessionAgent.Test.ToolCallRoundtripIntegrationTest` exercising every bundled provider × every bundled tool against canned mock responses, plus a per-release validation pass against real provider endpoints (gated behind CI secrets),
So that every release ships only after the dispatch contract is verified end-to-end across the matrix (FR59), and contributors adding a new provider have a one-command verification that their concrete subclass works with all bundled tools (per [PRD Journey 4](prd.md) Tomás contract acceptance gate).

**Acceptance Criteria:**

**Given** the developer is implementing `Test/ToolCallRoundtripIntegrationTest.cls`
**When** they implement the test class
**Then** the class iterates the cross-product of `[OpenAIProvider, AnthropicProvider, GeminiProvider, OpenAICompatProvider]` × `[every Tool.Base subclass registered in Tool.Registry]`
**And** for each pair, the test invokes `Tool.Registry.Dispatch` via a stub `AgentLoop` that mocks the provider's HTTP layer to return a deterministic 2-turn dialog (turn 1: assistant calls the tool with valid args; turn 2: assistant produces final text with `end_turn`)
**And** the test asserts: tool dispatched correctly, `Audit.ToolCall` row written, response shape matches MCP envelope, no exceptions escape `Invoke`, dispatch policy gate (`MutatesState=0`) is exercised

**Given** the mock provider response harness is implemented
**When** the test runs against canned mocks (no network calls)
**Then** all combinations pass deterministically in <30 seconds total
**And** the test output reports any combination that failed with `provider=<name>, tool=<name>, reason=<...>`
**And** the test counts: `expected_combinations = 4 providers × N tools` and asserts `successful_combinations == expected_combinations`

**Given** a CI workflow extension (per Story 1.7's `ci.yml` evolution)
**When** the workflow runs the per-release real-endpoint validation
**Then** the workflow exposes secrets `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_COMPAT_ENDPOINT_URL` (and optional `OPENAI_COMPAT_API_KEY`) — with the workflow conditional on those secrets being set (skip the real-endpoint pass on PRs from forks where secrets aren't available)
**And** the real-endpoint test runs the same matrix but against actual provider endpoints (within rate-limit budgets per provider — the test uses minimal token counts to stay under provider free tiers where feasible)
**And** any real-endpoint failure surfaces in the workflow output with the request-id for diagnostic purposes

**Given** a community contributor adds a 5th `LLM.Provider` subclass per FR28 (e.g., `CohereProvider` per Tomás Journey 4)
**When** they add a one-line entry to `Tool.Registry` registry (or equivalent registry mechanism — TBD in implementation if `LLM.Registry` is a separate class) AND run the tool-call-roundtrip test
**Then** their new provider is exercised against every bundled tool
**And** if any tool-pair fails, the test output names the failed combination
**And** the Tomás contract is verified: zero edits to `AgentLoop`, `ToolRegistry`, `Tool.Inspection.*`, `Tool.Search.*`, or any shared infrastructure beyond the new subclass + registry entry

---

## Epic 6: Per-Agent Configuration UI

**Operator outcome:** Operator-Admin opens `SessionAgent.UI.AgentConfig.zen`, picks an agent (Inspection / Search), selects provider + model + temperature + max-tokens + optional system-prompt-override + credential-ref from the existing `Ens.Config.Credentials` dropdown, saves. Hot config change applies on the next agent turn — no IRIS restart, no chat reset. Form feels like other Mgmt Portal config pages (`EnsPortal.Credentials.zen` style).

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 6.1**: `SessionAgent.UI.AgentConfig.zen` — form layout with agent-selector + provider/model dropdowns + credential-ref dropdown + temperature/max-tokens/system-prompt-override fields
2. **Story 6.2**: Save handler + validation + hot config change verification (NFR-O2 — next agent turn picks up changes without IRIS restart)
3. **Story 6.3**: Replace placeholder admin-link in `sa-config-empty-prompt` (Story 3.5) with real link to `AgentConfig.zen` + end-to-end "configure → ask question" workflow validation
4. **Story 6.4**: Multi-namespace install support — `Installer.InstallIntoNamespace(pNamespace)` for operators with multiple interop namespaces; per-namespace `Config.Agent` semantics; README operator-walkthrough

### Story 6.1: `AgentConfig.zen` Form Layout

As an Operator-Admin (Aishah-class) who needs to configure each agent's LLM provider settings,
I want a `SessionAgent.UI.AgentConfig.zen` page rendering a Zen form with agent-selector dropdown (Inspection / Search) that loads the chosen agent's `Config.Agent` row, plus provider dropdown (4 options), model combobox (provider-specific suggestions + free-text override), credential-ref dropdown (populated from existing `Ens.Config.Credentials` entries + env-var name option), temperature/max-tokens number inputs, system-prompt-override textarea, and Save/Cancel buttons,
So that I can configure each agent without writing SQL or editing class code, and the form feels like other Mgmt Portal config pages (e.g., `EnsPortal.Credentials.zen` style) per UX-DR11.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.UI.AgentConfig`
**When** they implement the Zen page subclass of `%ZEN.Component.page`
**Then** the page is at the path `src/SessionAgent/UI/AgentConfig.cls` per architecture §"Project Directory Structure"
**And** the page extends `%ZEN.Component.page` and inherits `EnsPortal.Application` styling per UX-DR26 (no Material/Tailwind/etc.)
**And** the page is included in `module.xml`'s `<Resource Name="SessionAgent.PKG"/>`
**And** the URL pattern follows `/csp/healthshare/<NS>/SessionAgent.UI.AgentConfig.zen` (HealthShare) AND `/csp/<NS>/SessionAgent.UI.AgentConfig.zen` (plain IRIS)

**Given** the developer is laying out the form
**When** they implement the form structure
**Then** the form uses Zen `<vgroup>` for vertical stacking + `<hgroup>` for inline button groups per UX-DR11 (matching `EnsPortal.Credentials.zen` conventions)
**And** the form contains in order:
  - **Agent selector** (`<select id="agentSelect" label="Agent" valueList="session-inspection,message-search" displayList="Session Inspection,Message Search">`) — change handler loads the chosen agent's `Config.Agent` row into the form below
  - **Provider** (`<select id="providerSelect" label="Provider" valueList="openai,anthropic,gemini,openai-compatible" displayList="OpenAI,Anthropic,Google Gemini,OpenAI-Compatible (Ollama/vLLM)">`) — change handler updates the model combobox suggestions
  - **Model** (`<combobox id="modelCombo" label="Model">`) — provider-specific suggestions populated from a server-side helper (`OpenAI`: `gpt-4.1-mini`, `gpt-4.1-nano`, `gpt-5-mini`; `Anthropic`: `claude-sonnet-4-5`, `claude-opus-4-7`; `Gemini`: `gemini-2.5-pro`, `gemini-3-pro`; `OpenAI-Compatible`: `qwen2.5:32b`, `llama3.3:70b`) — operator can also type free-text per architecture OD4 model-name-drift guidance
  - **Endpoint URL** (`<text id="endpointUrlText" label="Endpoint URL (OpenAI-Compatible only)">`) — visible only when provider is `openai-compatible`; validation message if provider is `openai-compatible` and field is empty
  - **Credential Reference Type** (`<radioSet id="credTypeRadio" displayList="Environment Variable,Ens.Config.Credentials">`) — change handler shows the appropriate field below
  - **Env Var Name** (`<text id="envVarText" label="Environment Variable Name">`) — visible when credTypeRadio is "Environment Variable" (default `OPENAI_API_KEY` for OpenAI provider, etc.)
  - **Credential Name** (`<combobox id="credCombo" label="Ens.Config.Credentials Entry">`) — visible when credTypeRadio is "Ens.Config.Credentials"; populated from `SELECT %EXACT(ID) FROM Ens_Config.Credentials` (using `%EXACT()` per project rule)
  - **Max Tokens** (`<text id="maxTokensText" type="number" label="Max Tokens">` default 4000)
  - **Temperature** (`<text id="temperatureText" type="number" label="Temperature" min="0" max="2" step="0.1">` default 0.1)
  - **System Prompt Override** (`<textarea id="systemPromptText" label="System Prompt Override (optional)" rows="6" cols="80">` — placeholder text says *"Leave blank to use default per AgentDefaults.GetSystemPrompt"*)
  - **Enabled** (`<checkbox id="enabledCheck" caption="Enable this agent">`)
  - **Action buttons** (`<hgroup>` containing `<button caption="Save" onclick="zenPage.saveConfig();">` + `<button caption="Cancel" onclick="zenPage.cancelEdit();">`)

**Given** the page loads
**When** the operator first visits it
**Then** the agent selector defaults to `session-inspection`
**And** the form below loads with the current `Config.Agent` row's values for that agent (or empty fields if no row exists)
**And** all fields are tab-navigable in the visible order
**And** all fields have associated `<label>` elements per UX-DR19/20

**Given** the operator changes the provider selection
**When** the change-handler fires
**Then** the model combobox suggestions update to the provider-specific list
**And** the endpoint URL field becomes visible/hidden per provider (visible only for `openai-compatible`)
**And** any warning about empty required fields refreshes

### Story 6.2: Save Handler + Hot Config Change Verification

As an Operator-Admin (Aishah-class) who has filled in the AgentConfig form,
I want clicking Save to validate the inputs, persist them to `Config.Agent` (creating the row if it doesn't exist for the selected agent), surface a brief "Saved" confirmation toast, and apply the changes to the *next* agent turn without restarting IRIS,
So that I can iterate on configuration during pilot (NFR-O2 hot config change).

**Acceptance Criteria:**

**Given** the developer is implementing the save handler
**When** they implement `ZenMethod SaveAgentConfig(pAgentName, pProvider, pModel, pEndpointUrl, pCredTypeRadio, pEnvVarName, pCredentialName, pMaxTokens, pTemperature, pSystemPrompt, pEnabled) As %String [ZenMethod]`
**Then** the method validates: `pAgentName ∈ {session-inspection, message-search}`, `pProvider ∈ {openai, anthropic, gemini, openai-compatible}`, `pMaxTokens > 0` and `<= 32000`, `pTemperature >= 0` and `<= 2`, `pCredTypeRadio="env"` requires non-empty `pEnvVarName`, `pCredTypeRadio="creds"` requires non-empty `pCredentialName`, `pProvider="openai-compatible"` requires non-empty `pEndpointUrl`
**And** validation failures return JSON `{success: false, errors: [...]}` for client-side display per UX-DR18 (no exception bubbles)
**And** validation success: opens or creates the `Config.Agent` row keyed by `pAgentName`, sets all properties (clearing the *unused* credential field per radio selection — never store both `EnvVarName` AND `CredentialName` simultaneously), saves, returns `{success: true, message: "Saved"}`
**And** the method NEVER persists `pApiKey` (FR41, NFR-S2 schema discipline) — there is no `pApiKey` parameter at all; auth is via `EnvVarName` or `CredentialName` reference

**Given** the operator clicks Save with valid inputs
**When** the ZenMethod returns success
**Then** the client-side `saveConfig()` shows a brief "Saved" confirmation (toast or inline message — Mgmt Portal-style, NOT a modal per UX-DR28)
**And** the form's "dirty" state resets

**Given** the operator clicks Save with validation errors
**When** the ZenMethod returns errors
**Then** the client-side `saveConfig()` displays the errors inline near the offending fields
**And** the operator can correct + retry without leaving the page

**Given** an operator has made an existing chat-tab visit and started a conversation
**When** the Operator-Admin saves a configuration change (e.g., switches provider from OpenAI to Anthropic)
**And** the operator returns to their existing chat tab and types a new message
**Then** the next `AgentLoop.RunTurn` invocation reads the *new* `Config.Agent` row (NFR-O2 hot config) — no IRIS restart, no chat reset
**And** the new turn dispatches against the new provider
**And** the existing chat history is preserved (the in-progress conversation continues seamlessly with the new provider — though the operator may notice the response style differs)

**Given** an integration test (`Test/AgentConfigTest.cls`) verifies the hot config change
**When** the test: (1) sets `Config.Agent` row to OpenAI, (2) invokes `RunTurn` and observes provider="openai" in the audit row, (3) updates `Config.Agent` row to Anthropic via the save handler, (4) invokes `RunTurn` again
**Then** the second `Audit.LlmCall` row has `Provider="anthropic"` (NFR-O2 verified)
**And** no IRIS restart was needed between (2) and (4)

### Story 6.3: Replace Placeholder Admin Link + End-to-End Configure-and-Ask Validation

As an Operator-Admin (Aishah-class) installing the product for the first time,
I want the no-config empty state in the chat panel (Story 3.5's `sa-config-empty-prompt`) to link directly to `SessionAgent.UI.AgentConfig.zen`, so that I can configure the agent and immediately return to the chat tab to ask my first question,
So that the end-to-end configure-and-ask workflow is one navigation hop, validating the Aishah Journey 3 install-day flow on a real installation.

**Acceptance Criteria:**

**Given** Story 3.5's `sa-config-empty-prompt` admin variant currently displays a placeholder URL
**When** Story 6.3 replaces the placeholder with a real anchor
**Then** the prompt text reads *"This agent isn't configured yet. <a href='/csp/<ns>/SessionAgent.UI.AgentConfig.zen'>Configure agent →</a>"* — with the namespace dynamically substituted server-side (or via JS reading `window.location.pathname`)
**And** the link is a real `<a>` element per UX-DR19 (NOT `<span onclick>`)
**And** the link has `aria-label="Configure agent"` per UX-DR20

**Given** an Operator-Admin clicks the configure link from the no-config empty state
**When** they navigate to `AgentConfig.zen`, fill in provider + model + credentials, save, then click their browser back button (or navigate back to Visual Trace)
**Then** the chat tab on Visual Trace re-detects the config presence and replaces the `sa-config-empty-prompt` with the normal first-time empty state (welcome message + auto-focused input per UX-DR17-MVP-subset)
**And** the operator can immediately type their first question and dispatch the agent

**Given** an end-to-end workflow validation test (`Test/ConfigureAndAskWorkflowTest.cls` or manual smoke checklist)
**When** the test simulates a fresh install: (1) `zpm install`, (2) operator opens Visual Trace + chat tab + sees `sa-config-empty-prompt`, (3) operator clicks configure link → AgentConfig.zen → saves, (4) operator returns to Visual Trace + chat tab + types question
**Then** the question is dispatched + answered correctly using the just-configured provider
**And** the elapsed time from step (1) to step (4) success is within the 30-minute Aishah-walkthrough target (NFR-O1; informally validated by a maintainer or pilot operator dry-run)
**And** the **Epic 6 acceptance gate is met**: per-agent config UI is end-to-end usable; no SQL editing required; Aishah Journey 3 enacted on a real install

### Story 6.4: Multi-Namespace Install Support

As an **Operator-Admin running iris-session-agent in an environment with multiple interop namespaces** (e.g., HSCUSTOM + a dedicated test namespace + a per-tenant namespace),
I want a documented + tested install path that scopes the agent install to one namespace at a time — `Do ##class(SessionAgent.Installer).InstallIntoNamespace("OTHERNS")` — and a clear architectural decision about whether `Config.Agent` rows are per-namespace or shared,
So that I can deploy the agent across multiple operational contexts without overwriting per-namespace configuration or violating the read-only invariant on cross-namespace `Ens.*` data.

Added to Epic 6 via Sprint Change Proposal 2026-05-03 after the Story 3.7 walkthrough surfaced the gap (single-namespace install is documented but multi-namespace is not).

**Acceptance Criteria:**

**Given** the developer is implementing the multi-namespace install path
**When** they add `ClassMethod InstallIntoNamespace(pNamespace As %String) As %Status` to `SessionAgent.Installer`
**Then** the method validates `pNamespace` exists + is not `%SYS`
**And** the method save-and-restores `$NAMESPACE` around delegating to the existing `Install()` work scoped to `pNamespace`
**And** the method is idempotent — re-running on a previously-installed namespace returns `$$$OK` without duplicating Task Manager entries, Config.Agent rows, or audit-event registrations
**And** the existing single-namespace `Install()` path is unchanged — `InstallIntoNamespace` is purely additive

**Given** the developer is documenting the architectural decision about Config.Agent semantics
**When** they update `architecture.md` (or this spec's Dev Notes)
**Then** the decision is recorded: `Config.Agent` rows are PER-NAMESPACE (default) — each namespace's `SessionAgent_Config.Agent` table is independent. Operators with cross-namespace identical config use a documented copy script (`Do ##class(SessionAgent.Installer).CopyConfigBetweenNamespaces(pSrc, pDst)` or similar — finalized in dev).
**And** the rationale: per-namespace is the safer default (no cross-namespace coupling, no risk of one namespace's enable-state affecting another's RBAC scope)
**And** if a future story adds shared-config semantics, it does so additively (e.g., a namespace-column on Config.Agent) rather than retroactively

**Given** the developer is implementing the package-mapping pre-check
**When** `InstallIntoNamespace(pNamespace)` runs
**Then** the method first verifies `SessionAgent.PKG` is mapped to `pNamespace` (via `Config.MapPackages` or equivalent)
**And** if not mapped, the method returns `$$$ERROR(...)` with a clear operator message: *"SessionAgent.PKG is not mapped to namespace 'OTHERNS'. Run: Do ##class(Config.MapPackages).Create(\"OTHERNS\", \"SessionAgent\", \"HSCUSTOM\") (or equivalent for your install topology) before retrying InstallIntoNamespace."*
**And** the operator-error path NEVER throws — always returns a structured `%Status`

**Given** the developer is updating README operator docs
**When** they add the multi-namespace install walkthrough section
**Then** the README documents the full operator workflow: (1) create or identify the target namespace, (2) map `SessionAgent.PKG` to it, (3) run `InstallIntoNamespace`, (4) verify via `iris_role_list` + `iris_credential_list` + `Config.Agent` SQL probe
**And** the README explicitly notes `SessionAgent.UI.ChatPanelAsset.cls` is automatically available at `/csp/<lower-namespace>/SessionAgent.UI.ChatPanelAsset.cls` for any namespace where the package is mapped (no separate static-asset deployment per Story 3.6 asset-class pivot)

**Given** the developer adds an integration test
**When** they ship `Test/MultiNamespaceInstallTest.cls`
**Then** the test creates a temporary test namespace (or skips with a clear message if create-namespace requires permissions the test runner doesn't have)
**And** the test runs `InstallIntoNamespace(pTempNS)` + verifies Config.Agent rows + RBAC role grants + audit-event registration are all per-namespace (not leaked into HSCUSTOM)
**And** the test cleans up the temporary namespace at the end

**Given** the maintainer commits Story 6.4
**When** a future operator with a multi-namespace deployment installs iris-session-agent
**Then** the operator can scope the install per-namespace cleanly + verify each namespace independently
**And** the **Epic 6 acceptance gate is met**: per-agent config UI is end-to-end usable AND multi-namespace deployments are first-class supported

---

## Epic 7: Inspection Chat-History Lifecycle

**Operator outcome:** Operator's accumulated Inspection chat history is automatically swept when the underlying Ens session is purged via `Ens.MessageHeader.Purge()` — daily 02:00 UTC sweep removes orphaned `Chat.History` rows. No orphan accumulation under sustained purge cycles. Validated by a 1,000-session integration test (insert sessions + attach conversations + purge + sweep; assert zero orphans).

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 7.1**: Task-0 probe — `&sql SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId)='...'` SQLCODE=0/100 semantics on 2024.1 + Audit FK cascade design decision
2. **Story 7.2**: `SessionAgent.Task.PurgeOrphanedChatHistory` implementation + `Installer.Install` extension to schedule it (replaces Story 1.5's defensive placeholder for this task with actual scheduling)
3. **Story 7.3**: `Test/PurgeTaskTest.cls` — 1,000-session integration test (insert sessions + attach conversations + simulate Ens.MessageHeader.Purge + run task + assert zero orphans)

### Story 7.1: Task-0 Probe + Audit FK Cascade Design

As a developer preparing the inspection chat-history sweep,
I want a verified Task-0 probe of `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionId)` SQLCODE semantics on a live IRIS 2024.1+ instance, plus a documented design decision on whether `Audit.LlmCall` and `Audit.ToolCall` FK references to `Chat.History` cascade-delete or leave dangling FKs (or are scrubbed by the sweep task itself),
So that the sweep task in Story 7.2 can rely on a verified existence-check primitive and a clear cascade contract per architecture §"Carry-forward Task-0 probes" Epic 7.

**Acceptance Criteria:**

**Given** the developer is preparing this story
**When** they run the Task-0 probe per architecture §"Carry-forward Task-0 probes" Epic 7
**Then** they execute `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionId)` against a live IRIS 2024.1+ instance with: (a) `pSessionId` set to a known-existing session id, (b) `pSessionId` set to a guaranteed-non-existing session id
**And** the captured `SQLCODE` value for case (a) is recorded verbatim in the story's Tasks/Subtasks block (expected: 0)
**And** the captured `SQLCODE` value for case (b) is recorded verbatim (expected: 100)
**And** if either value differs from the expected, the design assumption is escalated and the sweep task's existence-check is redesigned

**Given** the developer is making the Audit FK cascade design decision
**When** they evaluate options
**Then** they document one of three options as the chosen approach:
  - **Option A**: Foreign-key cascade DELETE on `Audit.LlmCall.ChatHistory` and `Audit.ToolCall.ChatHistory` references (audit rows auto-delete when chat history row deletes) — preserves audit-log integrity by removing orphans cleanly; trade-off: audit retention can't outlive chat retention
  - **Option B**: Sweep task explicitly deletes audit rows referencing the chat-history row before deleting the chat-history row itself — explicit, controllable; trade-off: sweep runtime grows linearly with audit volume per chat row
  - **Option C**: Audit rows retain their `ChatHistory` FK reference even after chat row deletion (FK becomes dangling but stays for forensic / compliance purposes) — preserves audit history independent of chat lifecycle; trade-off: NFR-SC4 audit-volume bound is broken (audit no longer cascade-cleaned)
**And** the chosen option is documented in this story + reflected in Story 7.2's implementation
**And** the chosen option is also added as a sentence to architecture.md §"Audit-log volume" or §"Chat-history lifecycle" so future readers see the decision

**Given** the design decision is made
**When** the maintainer reviews the choice
**Then** the maintainer confirms the choice aligns with NFR-SC4 (audit-log volume bounded by sweep cascade) — Option A or Option B preserves the bound; Option C requires a separate audit-volume management strategy

### Story 7.2: `PurgeOrphanedChatHistory` Task + Installer Scheduling

As a System (sweep task) and Operator-Admin (install-time scheduler),
I want `SessionAgent.Task.PurgeOrphanedChatHistory` extending `%SYS.Task.Definition` with daily 02:00 UTC scheduling, scanning Inspection-keyed `Chat.History` rows (`AgentName='session-inspection'`), checking each row's `SessionKey` against `Ens.MessageHeader` via the Story 7.1-verified existence check, deleting orphaned rows + (per Story 7.1 design decision) handling cascading audit cleanup, plus `Installer.Install` extension to schedule the task on first install,
So that orphan accumulation under sustained `Ens.MessageHeader.Purge()` cycles is structurally prevented per FR44 + NFR-R2.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Task.PurgeOrphanedChatHistory`
**When** they implement the task class
**Then** the class extends `%SYS.Task.Definition` (verified by reading `irislib/%SYS/Task/Definition.cls` source per project rule "IRIS Library Source")
**And** the class declares Class Parameters `TaskName = "PurgeOrphanedChatHistory"`, `Description = "Removes Inspection chat-history rows whose underlying Ens session was purged via Ens.MessageHeader.Purge()."`
**And** the class implements `OnTask() As %Status` that: iterates `SELECT %ID FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = 'session-inspection'` (using `%EXACT()` per project rule), for each row checks `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :sessionKey)` per Story 7.1 verified semantics, if `SQLCODE=100` (no row exists) deletes the chat-history row + (per Story 7.1's chosen cascade option) handles audit cleanup
**And** the method emits a native IRIS audit event via `$System.Security.Audit("SessionAgent","TaskRun","PurgeOrphanedChatHistory", {orphans_deleted: N, scan_time_ms: ...})` per architecture §"Audit event triples" (the event was pre-registered by Story 1.3's `Audit.Emit.EnsureEvents`)
**And** the method follows project rule `%Status` convention: `Set tSC = $$$OK` first line, `Quit tSC` last line, Try/Catch with argumentless `Quit` inside catch
**And** transaction discipline per project rule "Transaction Side Effects": no JOB / Event.Signal / external I/O inside any TSTART/TCOMMIT block

**Given** the developer is extending `SessionAgent.Installer.Install` (Story 1.5)
**When** they replace the defensive placeholder for `PurgeOrphanedChatHistory` with actual scheduling
**Then** the Installer's `ScheduleTaskIfClassExists("PurgeOrphanedChatHistory", "SessionAgent.Task.PurgeOrphanedChatHistory", "daily", 2, 0)` (or equivalent) now finds the class + creates an IRIS Task Manager entry running daily at 02:00 UTC
**And** the scheduling is idempotent (per NFR-R5) — re-running the install does not duplicate the task entry
**And** the task entry is named uniquely (e.g., `SessionAgent.PurgeOrphanedChatHistory`) so operators can identify it in the Task Manager UI

**Given** the task is scheduled and runs
**When** the operator inspects IRIS Task Manager
**Then** the task is visible with `Status = "Scheduled"`, last-run time, and history of previous runs
**And** the task can be manually triggered for testing per IRIS Task Manager standard UI

### Story 7.3: 1,000-Session Integration Test

As a maintainer validating NFR-R2 chat-history lifecycle integrity under sustained purge cycles,
I want `Test/PurgeTaskTest.cls` exercising the full lifecycle: insert 1,000 fixture Ens sessions, attach Inspection chat conversations to a subset, simulate `Ens.MessageHeader.Purge()` removing some sessions, run `PurgeOrphanedChatHistory.OnTask()`, assert zero orphan chat-history rows remain,
So that the sweep is structurally validated against realistic operator-grade data volumes.

**Acceptance Criteria:**

**Given** the developer is implementing `Test/PurgeTaskTest.cls`
**When** they implement the integration test
**Then** the test extends `%UnitTest.TestCase` per project rule with proper `%OnNew(initvalue)` handling
**And** test fixture setup: inserts 1,000 fixture `Ens.MessageHeader` rows in a test namespace (or uses a test-scoped table to avoid polluting production data per architecture §"Test Class Size" — break into smaller fixture-set if class exceeds 500 lines)
**And** test fixture setup: creates 600 Inspection-keyed `Chat.History` rows referencing 600 of the 1,000 sessions (so 400 sessions have no chat history; 600 sessions have chat history)
**And** test step 1: simulates `Ens.MessageHeader.Purge()` removing 300 sessions (a mix of 200 with-chat-history + 100 without-chat-history)
**And** test step 2: invokes `##class(SessionAgent.Task.PurgeOrphanedChatHistory).%New().OnTask()` directly (not via Task Manager — direct invocation for test determinism)
**And** test step 3 assertions: `count(*) FROM SessionAgent_Chat.History WHERE AgentName='session-inspection'` equals 400 (600 original − 200 purged-with-chat-history); for the 200 expected-deleted chat rows, no orphans remain
**And** test step 4 assertions: per Story 7.1 cascade design choice, `SessionAgent_Audit.LlmCall WHERE ChatHistory IN (<the 200 deleted IDs>)` is appropriately handled (cascaded if Option A/B; preserved if Option C)
**And** test cleanup: deletes the test fixtures

**Given** the test is run as part of the per-release manual smoke pass
**When** the maintainer executes `do ##class(%UnitTest.Manager).RunTest("SessionAgent.Test.PurgeTaskTest")`
**Then** the test passes within a reasonable runtime (~30 seconds — 1,000-row scan + 200 deletions should be fast)
**And** the test output reports: scan time, orphans found, orphans deleted, audit cascade behavior observed

**Given** a future release modifies the sweep logic
**When** the test is re-run
**Then** any regression that leaks orphans surfaces immediately
**And** the **Epic 7 acceptance gate is met**: NFR-R2 (chat-history lifecycle integrity under purge) is structurally validated; sweep is operator-trusted for production deployment

---

## Epic 8: Search Agent — Foundation

**Backend outcome (programmatic + via `vocab_lookup`):** All 8 indexed-access search tools (`SearchByTime`, `SearchByStatus`, `SearchBySource`, `SearchByTarget`, `SearchByMessageClass`, `SearchBySession`, `SearchBySuperSession`, `SearchByBodyField`) + `InspectBodyCandidates` two-stage body-content search (≤50 candidates, reuses Epic 4's body-class dispatch ladder) + `VocabLookup` utility tool are callable via `Tool.Registry.Dispatch`. Bounded-WHERE invariant test in CI fails any tool that violates (every search SQL leads with ≥1 indexed column + 24h `TimeCreated` default window, max 720h). Vocabulary persistence schemas (`UserVocabulary`, `SeedVocabulary`, `NamespaceVocabulary`) exist; ~10 HL7-idiom seed templates seeded by installer.

**Maintainer / pilot outcome:** Maintainer can validate Search Agent backend correctness via `%UnitTest` (`Test/SearchToolTest`) + `vocab_lookup` exploration before exposing to operators. The full operator outcome (Devin Journey 2 — opens Message Viewer's "Ask the agent" tab, types *"find me failed admits from the last hour"*, gets a curated session list) is reached at end of **Epic 10** when the `EnsPortal.MessageViewer` subclass + chat panel UI ship. This Epic 8 / Epic 10 split lets vocabulary learning (Epic 9) sit between foundation and UI without UI-side refactoring — same transparent "(maintainer checkpoint)" framing pattern Epic 2 uses for the Inspection Agent backend before Epic 3's UI ships.

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 8.1**: `Search.UserVocabulary` / `Search.SeedVocabulary` / `Search.NamespaceVocabulary` `%Persistent` schemas + `SeedVocabulary.Seed()` with ~10 HL7 templates + Installer extension to seed (the `EnsLib.HL7.SearchTable` row-shape Task-0 probe is owned by Epic 4 Story 4.6 — first cross-codebase consumer; this story reuses the captured shape)
2. **Story 8.2**: `Tool.Search.Base` abstract + bounded-WHERE invariant + `Test/BoundedWhereInvariantTest.cls`
3. **Story 8.3**: 6 simple indexed-access tools — `SearchByTime`, `SearchByStatus`, `SearchBySource`, `SearchByTarget`, `SearchByMessageClass`, `SearchBySession`
4. **Story 8.4**: `SearchBySuperSession` (`Ens.SuperSessionIndex` join — different shape from Story 8.3 tools)
5. **Story 8.5**: `SearchByBodyField` (`Ens.SearchTableBase` pivot via the SearchTable row-shape captured by Epic 4 Story 4.6)
6. **Story 8.6**: `InspectBodyCandidates` two-stage body-content search (≤50 candidates; uses `GetMessageBody` from Epic 4)
7. **Story 8.7**: `VocabLookup` utility tool + comprehensive `SearchToolTest`

### Story 8.1: Vocabulary Schemas + Seed Templates

As a developer preparing the Search Agent foundation,
I want three vocabulary `%Persistent` classes (`UserVocabulary`, `SeedVocabulary`, `NamespaceVocabulary` schema-only) + ~10 HL7-idiom seed templates seeded by `Installer.Install`,
So that the Search Agent can ship with operator-immediately-useful seed vocabulary on first install (FR23, AR19). The `EnsLib.HL7.SearchTable` row-shape Task-0 probe needed by Story 8.5 (`SearchByBodyField`) is captured in Epic 4 Story 4.6 — first cross-codebase consumer of the SearchTable shape.

**Acceptance Criteria:**

**Given** Story 4.6 has captured the `EnsLib.HL7.SearchTable` row-shape Task-0 probe (re-anchored to Epic 4 — first story across the codebase that needs the SearchTable shape)
**When** Story 8.5 (`SearchByBodyField`) is implemented later in this epic
**Then** Story 8.5 reuses the row shape captured by Story 4.6 (no duplicate probe)
**And** if Story 4.6's probe revealed the SearchTable is not installed on the operator's instance, Story 8.5 surfaces the same graceful "not configured" error (per architecture §"Risk Mitigation")

**Given** the developer is implementing `SessionAgent.Search.UserVocabulary`
**When** they implement the `%Persistent` class
**Then** the class declares properties `PortalUser As %String`, `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable per `project_search_agent_body_search_refinement.md` saved memory — supports per-class vocabulary refinement), `SuccessCount As %Integer`, `FailureCount As %Integer`, `Confidence As %Numeric` (default 0; the recursion-safe `%OnAfterSave` trigger that recomputes Confidence from Success/Failure counts is added in Epic 9 when vocabulary learning ships — until then, Confidence is stored as 0 and read directly), `LastUsed As %String` (ISO-8601 UTC), `CreatedAt As %String` (ISO-8601 UTC), `CreatedVia As %String` (`clickthrough` | `explicit` | `extracted` | `seed`)
**And** the class declares `Index UserAliasIdx On (PortalUser, Alias) [Unique]`
**And** Storage section is auto-generated per project rule "Storage Sections"

**Given** the developer is implementing `SessionAgent.Search.SeedVocabulary`
**When** they implement the `%Persistent` class
**Then** the class declares properties `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable), `Description As %String(MAXLEN=2048)`, `Aliases As %String(MAXLEN=2048)` (synonyms, comma-separated), `Examples As %String(MAXLEN=2048)` (example queries that match this alias)
**And** the class declares `Index AliasIdx On Alias`
**And** the class provides `ClassMethod Seed() As %Status` that idempotently inserts ~10 HL7-idiom seed templates including: `admit ↔ A01/A04 events`, `discharge ↔ A03 events`, `lab order ↔ ORM messages`, `lab result ↔ ORU messages`, `radiology order ↔ ORM with OBR-4 imaging codes`, `MRN search ↔ PID-3`, `failed message ↔ Status='Error'`, `acknowledgment ↔ ACK messages`, `transfer ↔ A02 events`, `cancellation ↔ A11/A13 events`

**Given** the developer is implementing `SessionAgent.Search.NamespaceVocabulary`
**When** they implement the `%Persistent` class (schema-only per AR19; population logic deferred to v1.5 / Vision tier)
**Then** the class declares properties `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable), `Aliases As %String(MAXLEN=2048)`, `BaselineConfidence As %Numeric`, `BasedOnUsers As %Integer` (count of distinct users contributing to this baseline)
**And** Storage is auto-generated; the class compiles cleanly but has no insert/update logic in v1 — operators see an empty table

**Given** the developer is extending `SessionAgent.Installer.Install` (Story 1.5)
**When** they replace any defensive placeholder for vocabulary seeding with the actual seeding call
**Then** Installer invokes `##class(SessionAgent.Search.SeedVocabulary).Seed()` after RBAC + audit setup
**And** the seeding is idempotent — re-runs do not duplicate templates (per NFR-R5)
**And** the Installer logs: `<seed_count> seed vocabulary templates ensured`

### Story 8.2: `Tool.Search.Base` + Bounded-WHERE Invariant Test

As a developer writing the 8 search tools (Stories 8.3–8.5) and the body-content search (Story 8.6),
I want `SessionAgent.Tool.Search.Base` abstract base class enforcing the bounded-WHERE invariant per FR19 + AR11, plus `Test/BoundedWhereInvariantTest.cls` that fails any search tool whose WHERE clause does not lead with at least one indexed column AND a `TimeCreated` window (default 24h, max 720h),
So that Search Agent SQL queries are structurally bounded against operator-grade `Ens.MessageHeader` extents up to 10M rows (NFR-P2, NFR-SC1).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Search.Base`
**When** they implement the abstract base extending `SessionAgent.Tool.Base`
**Then** the class is marked `[Abstract]` with project-rule curly-brace bodies
**And** the class declares Class Parameters `DefaultTimeWindowHours = 24`, `MaxTimeWindowHours = 720` (= 30d) per architecture §"Calibration constants"
**And** the class declares an abstract method `GetIndexedLeadColumns() As %DynamicArray` returning the list of indexed column names this tool uses (e.g., `["TimeCreated", "Status"]`) — used by the bounded-WHERE invariant test
**And** the class provides a non-abstract helper `BuildBoundedWhereClause(pTimeWindowHours, pAdditionalPredicates...) As %String` that constructs a WHERE clause leading with the appropriate indexed column + `TimeCreated > <now - pTimeWindowHours>` window — `pTimeWindowHours` defaults to `..#DefaultTimeWindowHours` if not supplied; capped at `..#MaxTimeWindowHours`; rejects values outside `[1, 720]` with structured error
**And** the helper uses parameterized prepare (`%SQL.Statement.%Prepare` + `%Execute(?)`) for value substitution — never string concatenation that could enable SQL injection (per architecture §"Search-Arg-Construction Safety")
**And** the helper applies `%EXACT()` discipline on string predicates and projections per project rule

**Given** the developer is implementing `Test/BoundedWhereInvariantTest.cls`
**When** they implement the invariant test
**Then** the test class extends `%UnitTest.TestCase` with proper `%OnNew(initvalue)` handling
**And** the test iterates all `Tool.Search.*` subclasses registered in `Tool.Registry.ListTools()` (filtered to search-namespace tools)
**And** for each tool, the test invokes `tool.GetIndexedLeadColumns()` and asserts: (1) the returned array is non-empty, (2) at least one column is from the documented `Ens.MessageHeader` indexed set (`TimeCreated`, `Status`, `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`, `SessionId`)
**And** the test inspects each tool's SQL construction (via integration: invokes the tool with a deterministic input, captures the prepared SQL via a mocked `%SQL.Statement` or via `PREPARE` plan inspection) and asserts: WHERE clause contains the indexed lead column AND a `TimeCreated > ...` predicate
**And** any tool that violates either condition fails the test with a clear error message naming the offending tool and the missing constraint

**Given** a future story (or a community contribution) adds a new search tool
**When** the contributor runs `Test/BoundedWhereInvariantTest.cls`
**Then** the test catches any unbounded WHERE before merge (CI gate per FR19)

### Story 8.3: 6 Simple Indexed-Access Tools

As an Operator asking the Search Agent for sessions filtered by time, status, source, target, message class, or session id,
I want six tools — `search_by_time`, `search_by_status`, `search_by_source`, `search_by_target`, `search_by_message_class`, `search_by_session` — each leading their WHERE clause with an `Ens.MessageHeader` indexed column (most are bitmap-indexed) plus a `TimeCreated` window for additional bounding,
So that natural-language queries like *"failed sessions in the last hour"* (status + time), *"sessions from EpicADT today"* (source + time), or *"give me session 1184729"* (session-id keyed lookup) all dispatch through bounded SQL (FR15).

**Acceptance Criteria:**

**Given** the developer is implementing each of the 6 tools as concrete `Tool.Search.Base` subclasses
**When** they implement each tool
**Then** each tool declares `Parameter ToolName = "search_by_<name>"`, `Parameter Description = "..."`, `Parameter MutatesState = 0`
**And** each tool implements `GetIndexedLeadColumns()` returning its primary indexed column (e.g., `["TimeCreated"]` for `SearchByTime`, `["Status"]` for `SearchByStatus`, `["SessionId"]` for `SearchBySession`)
**And** each tool's `GetInputSchema()` declares the tool-specific filter input + optional `time_window_hours` (default 24, max 720) + optional `limit` (default 50) per Story 8.2's `Tool.Search.Base.BuildBoundedWhereClause` contract
**And** each tool's `Invoke` constructs the SQL via `Tool.Search.Base.BuildBoundedWhereClause` + parameterized prepare + `%EXACT()` discipline + result limit per FR19
**And** the returned `structuredContent` is `{sessions: [{session_id, time_created, source_config_name, target_config_name, message_body_class_name, status}, ...], result_count, time_window_used, indexed_lead_column}` with one-line operator-readable summary

**Given** specific per-tool input schemas
**When** the test inspects each tool's schema
**Then** `search_by_time` declares `from_time` + `to_time` (both ISO-8601 UTC; if both empty, defaults to last 24h)
**And** `search_by_status` declares `status_in` (array of `Status` values: `Completed | Error | Suspended | Queued | Discarded` etc.)
**And** `search_by_source` declares `source_config_name` (string)
**And** `search_by_target` declares `target_config_name` (string)
**And** `search_by_message_class` declares `message_body_class_name` (string)
**And** `search_by_session` declares `session_id` (string) — note: `SessionId` is a keyed lookup; for this tool the bounded-WHERE invariant is satisfied by `SessionId` itself (no time window needed per architecture OD8 — keyed lookup is its own bound; `Tool.Search.Base.BuildBoundedWhereClause` accepts a "keyed lookup mode" flag that skips the time-window requirement)

**Given** `Test/SearchToolTest.cls` (subset for these 6 tools) exercises the implementations
**When** the test runs against a fixture `Ens.MessageHeader` with N sessions across various sources/targets/statuses/classes
**Then** each tool returns the expected filtered set
**And** time-window filtering correctly applies to all tools except `search_by_session` (keyed lookup)
**And** result count caps at 50 by default, configurable up to ~500 per tool's input schema
**And** every tool passes the bounded-WHERE invariant test (Story 8.2)
**And** every tool's SQL uses `%EXACT()` on string predicates per project rule

### Story 8.4: `SearchBySuperSession`

As an Operator asking the Search Agent for sessions related across IRIS instances or BPs via `Ens.SuperSessionIndex`,
I want a `search_by_super_session` tool that joins `Ens.SuperSessionIndex` to enumerate sessions sharing a super-session key,
So that cross-instance message-flow queries are searchable from the Search Agent (FR17).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Search.SearchBySuperSession`
**When** they implement the concrete tool
**Then** input schema declares `super_session_key` (required) OR `seed_session_id` (required — derives super-session key from this session's index entry)
**And** `GetIndexedLeadColumns()` returns `["SuperSessionKey"]` — the SuperSessionIndex's keyed lookup
**And** `Invoke` joins `Ens.SuperSessionIndex` + `Ens.MessageHeader` per architecture / inspection-agent research §"SuperSessionIndex" + applies result limit (default 50)
**And** SQL uses `%EXACT()` discipline + parameterized prepare
**And** the returned `structuredContent` is `{super_session_key, sessions: [{session_id, time_created, source_config_name, target_config_name, message_count}, ...], session_count}` with summary

**Given** `Test/SearchToolTest.cls` (subset for this tool) exercises the implementation
**When** the test runs against a fixture with 4 sessions sharing a super-session key
**Then** `search_by_super_session` for the super-session key returns all 4 sessions
**And** `search_by_super_session` for a `seed_session_id` first resolves the super-session key, then returns the sibling sessions
**And** the tool passes the bounded-WHERE invariant test (Story 8.2 — keyed-lookup mode satisfies the bound)

### Story 8.5: `SearchByBodyField` (`Ens.SearchTableBase` Pivot)

As an Operator asking the Search Agent for sessions where a specific indexed body-field value appears (e.g., *"sessions for MRN 12345"*, *"orders for account 67890"*),
I want a `search_by_body_field` tool that pivots through `Ens.SearchTableBase` subclass extents (verified by Story 8.1's Task-0 probe row shape) using the same SearchTable join pattern as Inspection's `find_sessions_by_body` (Epic 4 Story 4.6), but bounded by the search-agent's `time_window_hours` + result limit per FR19,
So that natural-language queries grounded in indexed body-field data dispatch through bounded SQL (FR16).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Search.SearchByBodyField`
**When** they implement the concrete tool
**Then** input schema declares `search_table_class` (required), `prop_name` (required), `prop_value` (required), optional `time_window_hours` (default 168 = 7d per architecture OD8 `BodyFieldDefaultHours`, max 720), optional `limit` (default 50)
**And** `GetIndexedLeadColumns()` returns `[prop_name]` (the SearchTable's indexed property column)
**And** `Invoke` validates `search_table_class` is a registered `Ens.SearchTableBase` subclass; rejects with structured error if not (or if SearchTables are not installed in the operator's namespace per architecture §"Risk Mitigation")
**And** `Invoke` queries the `<search_table_class>` extent for `(PropName, PropValue)` matches via the row shape captured by Epic 4 Story 4.6's Task-0 probe, joins `Ens.MessageHeader` on `MessageBodyId`, applies the `time_window_hours` window per `Tool.Search.Base.BuildBoundedWhereClause` + result limit
**And** SQL uses `%EXACT()` discipline + parameterized prepare; `prop_value` containing wildcards is handled per the SearchTable's expected predicate semantics (no SQL injection — parameterized only)
**And** the returned `structuredContent` is `{search_table_class, prop_name, prop_value, sessions: [...], session_count, time_window_used}` with summary

**Given** the SearchTable extent doesn't exist on the operator's instance (Epic 4 Story 4.6's Task-0 probe documented the fallback)
**When** the tool is dispatched
**Then** it returns a structured error envelope with operator-readable text per architecture §"Risk Mitigation" + a hint to install HealthShare SearchTables or use a different search tool
**And** the agent continues with degraded context (per architecture §"Concurrent tool errors don't halt the agent")

**Given** `Test/SearchToolTest.cls` exercises the tool against the same fixture HL7 SearchTable used in Epic 4 Story 4.6
**When** the test runs
**Then** the tool returns the sessions matching the indexed (PropName, PropValue) pair
**And** the time-window filter applies correctly
**And** the tool passes the bounded-WHERE invariant test (Story 8.2)

### Story 8.6: `InspectBodyCandidates` Two-Stage Body-Content Search

As an Operator asking the Search Agent for sessions whose body content matches a pattern that ISN'T indexed (e.g., *"sessions where the diagnosis code starts with E11"*, *"messages mentioning 'penicillin allergy' in the body"*),
I want an `inspect_body_candidates` tool that performs the two-stage indexed-prefilter + body-inspection pattern: narrow to ≤50 candidates via an indexed prefilter, then open each candidate body via Epic 4's body-class dispatch ladder (`GetMessageBody`) and filter by the content pattern,
So that body-content search is *safe at production scale* per architecture §"Innovation §Two-stage indexed-prefilter" + FR18 + NFR-P3 (≤50 candidate body-inspection cap).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Search.InspectBodyCandidates`
**When** they implement the concrete tool
**Then** input schema declares `pattern` (required — regex or literal substring), `prefilter_indexed_column` (required — one of `Status` | `SourceConfigName` | `TargetConfigName` | `MessageBodyClassName`), `prefilter_value` (required — value for the indexed prefilter), optional `time_window_hours` (default 24, max 720), optional `pattern_is_regex` (boolean, default false), optional `candidate_cap` (default 50, max 50 per NFR-P3)
**And** `GetIndexedLeadColumns()` returns `[prefilter_indexed_column]` per Story 8.2's invariant
**And** `Invoke` step 1: queries `Ens.MessageHeader` filtered by `prefilter_indexed_column = prefilter_value` + `TimeCreated` window + `LIMIT 50` (or `candidate_cap` if smaller) → produces ≤50 candidate `MessageId` values
**And** `Invoke` step 2: for each candidate, invokes the Epic 4 body-rendering pathway (the G2 deferred-decision outcome from architecture — direct call to `Tool.Inspection.GetMessageBody.Invoke` OR an extracted `SessionAgent.Body.DispatchLadder` helper) to open the body, then applies the `pattern` (regex or substring) against the rendered body representation
**And** matched bodies are recorded; non-matched are dropped silently (per architecture §"Concurrent tool errors don't halt the agent" — body-open errors on individual candidates degrade gracefully)
**And** the returned `structuredContent` is `{pattern, prefilter_indexed_column, prefilter_value, candidates_inspected, matches: [{message_id, session_id, body_excerpt, body_class}, ...], match_count}` with summary

**Given** the candidate cap is enforced
**When** the test verifies cap behavior
**Then** even if the prefilter would return >50 candidates, the cap limits the body-inspection pass to ≤50 per NFR-P3
**And** the tool's response includes a note in the text summary if the prefilter returned more than 50 candidates (operator can tighten the prefilter)

**Given** `Test/SearchToolTest.cls` (subset for this tool) exercises the two-stage pattern
**When** the test runs against a fixture with 100 sessions of `MessageBodyClassName='EnsLib.HL7.Message'` (prefilter), 30 of which contain the pattern `"E11"` in their bodies
**Then** the tool returns ≤50 matches (capped at 50 even if all 30 in the first 50 candidates match)
**And** the tool's response includes `candidates_inspected ≤ 50`
**And** the tool passes the bounded-WHERE invariant test (Story 8.2)
**And** the tool's total runtime stays within the 90s LLM-call cap per NFR-P3 (validated by benchmark — informally during test, formally during synthetic-extent benchmark in CI)

### Story 8.7: `VocabLookup` Utility + Comprehensive `SearchToolTest`

As an Operator asking the Search Agent to *show me what aliases I have saved* OR explicitly to *save 'failed admits' as a query for me*,
I want a `vocab_lookup` utility tool with three modes — list (show user's vocabulary), save (explicit alias save), search (find matching aliases) — plus a comprehensive `SearchToolTest` that exercises every search tool against fixtures + verifies the L1 read-only invariant for the search-agent surface,
So that operators can manage their personal vocabulary via the agent itself without needing a separate UI (FR21) and the L1 enforcement is structurally validated for all search tools before pilot rollout.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Tool.Search.VocabLookup`
**When** they implement the concrete tool
**Then** the class declares `Parameter ToolName = "vocab_lookup"`, `Parameter Description = "List, save, or search the operator's saved vocabulary aliases."`, `Parameter MutatesState = 0` (lookup IS a write to vocabulary, but vocabulary writes are NOT `Ens.*` mutations — `MutatesState` only flags `Ens.*` mutation per FR31; vocabulary is iris-session-agent's own data)
**And** input schema declares `mode` (required: `list` | `save` | `search`), conditional `alias` (required for `save` and `search`), optional `description` (used during `save`), optional `message_body_class` (nullable per saved memory `project_search_agent_body_search_refinement.md`)
**And** for `mode='list'`, returns the operator's `UserVocabulary` rows (`PortalUser` from `pCallerCtx.PortalUser`) ordered by `Confidence DESC, LastUsed DESC`
**And** for `mode='save'`, implements a basic `RecordSuccess` inline directly in this story — opens or creates the `UserVocabulary` row keyed by `(pPortalUser, alias)`, sets `CreatedVia='explicit'`/`MessageBodyClass`/`CreatedAt`/`Description` on creation, increments `SuccessCount`, updates `LastUsed`, calls `%Save()` and propagates status per project rule "Write Status Checking", emits the `(SessionAgent, VocabWrite, explicit)` audit event per Story 1.3's pre-registration. The Confidence field stays at default 0 in this story; Epic 9 Story 9.2 enriches the same `UserVocabulary` class with the recursion-safe `%OnAfterSave` trigger that recomputes Confidence from Success/Failure counts on every subsequent save (the same incremental-enhancement pattern as Story 1.5's defensive task scheduling that Stories 7.2 and 10.6 enrich)
**And** for `mode='search'`, queries `UserVocabulary WHERE PortalUser = :user AND (Alias LIKE '%alias%' OR Aliases LIKE '%alias%')` with `%EXACT()` discipline + result limit 20

**Given** the developer is extending `Test/SearchToolTest.cls` with comprehensive coverage
**When** they implement the comprehensive test
**Then** the test iterates all `Tool.Search.*` subclasses (8 indexed-access tools + `InspectBodyCandidates` + `VocabLookup` = 10 tools) and asserts each has `MutatesState = 0` declared (NFR-S1 Layer 1 enforcement parallel to Epic 4 Story 4.7's inspection suite)
**And** the test exercises each tool against representative fixtures
**And** the test validates: structured envelope shape on success, structured error envelope shape on failure, no exceptions escape `Invoke` to the test runner
**And** the test runs end-to-end against a populated `Ens.MessageHeader` fixture + `EnsLib.HL7.SearchTable` fixture (per Story 4.6's Task-0 probe verified shape — re-anchored to Epic 4 since it's the first story across the codebase that needs the SearchTable shape)

**Given** the comprehensive suite is run as part of the per-release manual smoke pass
**When** the maintainer executes `do ##class(%UnitTest.Manager).RunTest("SessionAgent.Test.SearchToolTest")` on a 2024.1+ instance
**Then** all 10 search tool tests pass
**And** the L1 enforcement test passes (every search tool has `MutatesState=0`)
**And** the bounded-WHERE invariant test (Story 8.2) passes for all 10 tools (or appropriately exempts `vocab_lookup` since it doesn't query `Ens.*` — this exemption is documented in Story 8.2's test logic)
**And** the **Epic 8 acceptance gate is met**: Search Agent backend is callable via `vocab_lookup` and (programmatically until Epic 10's UI ships) via `Tool.Registry.Dispatch`; bounded-WHERE invariant structurally enforced; vocabulary persistence + seed templates ready for Epic 9's vocabulary-learning capture mechanism

---

## Epic 9: Search Agent — Vocabulary Learning

**Backend outcome:** Vocabulary capture mechanism (silent click-through + explicit-save) is callable via Epic 9 Story 9.2's `UserVocabulary.RecordSuccess` / `RecordFailure` ClassMethods (with confidence smoothing `Success / (Success + Failure + 1)` via recursion-safe `%OnAfterSave` direct-SQL UPDATE) and via Epic 8 Story 8.7's `vocab_lookup mode='save'`. Vocabulary digest assembly (top 20 user rows with confidence ≥ 0.3, capped ~1,200 tokens, with seed-vocabulary fallback for first-time users) is wired into `AgentLoop` as a first-user-message prefix — preserves Anthropic prompt-cache hit rate by not modifying the cached `system + tools` prefix (validated by NFR-P6 test).

**Maintainer / pilot outcome:** Maintainer can validate vocabulary learning end-to-end via `%UnitTest` (`Test/SearchVocabularyTest`) + explicit `vocab_lookup mode='save'` calls. The full operator outcome (click-through silently captures vocabulary while operator clicks search results in the Message Viewer chat panel — by the third *"admits"* query the agent skips seed vocabulary entirely) is reached at end of **Epic 10** when Story 10.3's click-through wiring calls Epic 9 Story 9.5's `RecordClickThrough` ZenMethod hyperevent stub. Epic 9 ships the stub + the full backend; Epic 10's UI calls into it. Same "(maintainer checkpoint)" framing pattern as Epic 2 and Epic 8.

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 9.1**: Task-0 probes — `%OnAfterSave` non-recursion verification on 2024.1 + `SynthesizeAlias` deterministic stringification unit test (~10 reordering scenarios)
2. **Story 9.2**: `UserVocabulary.RecordSuccess` + `RecordFailure` methods + recursion-safe `%OnAfterSave` direct-SQL UPDATE for `Confidence` recomputation
3. **Story 9.3**: `Search.VocabularyDigest.Build` implementation (top-N user rows with `Confidence ≥ 0.3`, capped ~1,200 tokens, with seed-vocabulary fallback for first-time users)
4. **Story 9.4**: `Agent.AgentLoop` integration — first-user-message prefix injection + Anthropic prompt-cache preservation test (NFR-P6)
5. **Story 9.5**: `RecordClickThrough` ZenMethod hyperevent stub on `Tool.Search.VocabLookup` (or a separate `Search.VocabCapture` class) — entry point that Epic 10's UI will call

### Story 9.1: Task-0 Probes — `%OnAfterSave` Non-Recursion + `SynthesizeAlias` Determinism

As a developer preparing the vocabulary-learning capture mechanism,
I want two verified Task-0 probes: (1) `%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1, and (2) the `SynthesizeAlias` deterministic stringification holds across ~10 reordering scenarios,
So that Story 9.2's recursion-safe `%OnAfterSave` Confidence recomputation has a verified non-recursion guarantee + the alias capture in Story 9.5 has a verified deterministic key (per architecture §"Carry-forward Task-0 probes" Epic 9 + AR12 + AR13-Epic9).

**Acceptance Criteria:**

**Given** the developer is preparing this story
**When** they run the `%OnAfterSave` non-recursion probe per architecture §"Carry-forward Task-0 probes" Epic 9
**Then** they create a small probe class with: `Property A As %Integer`, `Property B As %Integer`, `Method %OnAfterSave() As %Status` that issues `&sql(UPDATE Probe SET A = :..A WHERE %ID = :..%Id())` then returns `$$$OK`
**And** they invoke `Save()` on a probe row, observe the audit trail (e.g., set `^ClineDebug` instrumentation per project rule "ObjectScript Debugging Instructions" inside `%OnAfterSave` to count fires)
**And** the captured re-fire count is recorded verbatim in the story's Tasks/Subtasks block — expected: `%OnAfterSave` fires exactly ONCE (not recursively) on 2024.1
**And** if the probe shows recursion, Story 9.2's design is escalated and an alternate Confidence-recomputation strategy is documented (e.g., scheduled task, lazy compute on read)

**Given** the developer is preparing the `SynthesizeAlias` determinism probe
**When** they run the determinism unit test per architecture §"Carry-forward Task-0 probes" Epic 9
**Then** they author a `SynthesizeAlias(args...) As %String` candidate function that takes structured arguments (e.g., the args from a search-agent tool call) and produces a deterministic alias string
**And** the test exercises the function against ~10 reordering scenarios: e.g., `{status: "Error", source: "EpicADT"}` should produce the same alias as `{source: "EpicADT", status: "Error"}` and `{Status: "Error", Source: "EpicADT"}` (case normalization, key-order normalization, value normalization)
**And** all ~10 scenarios produce the same output string for semantically-equivalent inputs
**And** the captured test results are recorded in the story's Tasks/Subtasks block
**And** if the probe shows non-determinism, the function is iterated (e.g., add `$ZSORT` on keys, lowercase normalization) until determinism is verified

**Given** the probes pass
**When** the maintainer reviews
**Then** Story 9.2 + Story 9.5 can proceed with the verified guarantees baked into their AC

### Story 9.2: `UserVocabulary.RecordSuccess` + `RecordFailure` + Recursion-Safe `%OnAfterSave`

As a System (vocabulary capture mechanism enriching Epic 8's foundation),
I want to enrich Epic 8 Story 8.7's basic inline `RecordSuccess` (which exists from `vocab_lookup mode='save'`) by promoting it to a class-level `ClassMethod` on `SessionAgent.Search.UserVocabulary` + adding a `RecordFailure` companion + adding the recursion-safe `%OnAfterSave` trigger that recomputes `Confidence = Success / (Success + Failure + 1)` via direct SQL UPDATE on the same row (verified non-recursive in Story 9.1),
So that vocabulary learns silently from click-through (Story 9.5) AND explicit-save (Story 8.7's `vocab_lookup mode='save'` now picks up Confidence on every subsequent save) per FR22 — same incremental-enhancement pattern as Story 1.5's defensive scheduling enriched by Stories 7.2 and 10.6.

**Acceptance Criteria:**

**Given** the developer is promoting Epic 8 Story 8.7's basic inline `RecordSuccess` to a class-level `ClassMethod` on `SessionAgent.Search.UserVocabulary`
**When** they implement the method (signature `ClassMethod RecordSuccess(pPortalUser, pAlias, pMessageBodyClass="", pCreatedVia="clickthrough", pDescription="") As %Status`)
**Then** the method opens or creates the `UserVocabulary` row keyed by `(pPortalUser, pAlias)` (per `UserAliasIdx` from Story 8.1)
**And** the method body matches the inline implementation Story 8.7 already shipped (open-or-create, set fields on creation, increment SuccessCount, update LastUsed, save, emit audit event) — Story 8.7's inline call is updated to delegate to this new ClassMethod once it lands; no behavioral change beyond consolidation
**And** if creating: sets `CreatedVia=pCreatedVia`, `CreatedAt=$Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"` (project rule ISO-8601 UTC), `MessageBodyClass=pMessageBodyClass`, `Description=pDescription`, `SuccessCount=0`, `FailureCount=0`
**And** increments `SuccessCount += 1`
**And** updates `LastUsed = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"`
**And** calls `%Save()` and propagates the status per project rule "Write Status Checking"
**And** emits a native IRIS audit event via `$System.Security.Audit("SessionAgent","VocabWrite",pCreatedVia, ...)` per Story 1.3's audit event pre-registration

**Given** the developer is implementing `RecordFailure`
**When** they implement the method (signature `ClassMethod RecordFailure(pPortalUser, pAlias) As %Status`)
**Then** the method opens the `UserVocabulary` row by key (returns gracefully if row doesn't exist — failure on absent vocabulary is a no-op)
**And** increments `FailureCount += 1`
**And** updates `LastUsed`
**And** saves + emits audit event with type `failure_decrement` (or similar)

**Given** the developer is implementing recursion-safe `%OnAfterSave`
**When** they implement the trigger
**Then** the method computes `Denom = ..SuccessCount + ..FailureCount + 1` and `..Confidence = ..SuccessCount / Denom`
**And** the method issues `&sql(UPDATE SessionAgent_Search.UserVocabulary SET Confidence = :..Confidence WHERE %ID = :..%Id())` per architecture §"Process Patterns → %OnAfterSave recursion avoidance" + project rule "Pattern Replication Completeness"
**And** the method does NOT call `..%Save()` from within `%OnAfterSave` (would re-fire — Story 9.1's probe verifies the direct-SQL UPDATE pattern is safe on 2024.1)
**And** the method returns `$$$OK`

**Given** `Test/SearchVocabularyTest.cls` exercises the methods
**When** the test runs
**Then** `RecordSuccess` for a new user/alias pair creates the row with `SuccessCount=1, FailureCount=0, Confidence ≈ 0.5` (`1 / (1+0+1) = 0.5`)
**And** subsequent `RecordSuccess` calls increment `SuccessCount` and recompute `Confidence` correctly
**And** `RecordFailure` calls increment `FailureCount` and decrease `Confidence` (e.g., 1 success + 1 failure = `1/(1+1+1) = 0.333`)
**And** `%OnAfterSave` non-recursion is verified — set instrumentation in the trigger to count fires; expect exactly 1 per save (per Story 9.1 probe)
**And** vocabulary writes generate audit rows correctly

### Story 9.3: `Search.VocabularyDigest.Build`

As a System (vocabulary digest assembly for first-turn injection),
I want `SessionAgent.Search.VocabularyDigest.Build(pPortalUser) As %String` that produces a digest containing the operator's top-N vocabulary aliases (default N=20, configurable via Class Parameter `MaxEntries`) with `Confidence ≥ 0.3` (configurable via `MinUserConfidence`) capped at ~1,200 tokens, with seed-vocabulary fallback for first-time users,
So that the AgentLoop (Story 9.4) can inject the digest as the first-user-message prefix per FR24 + NFR-P6 (preserves Anthropic prompt-cache hit rate by NOT modifying the cached `system + tools` prefix).

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Search.VocabularyDigest`
**When** they implement the digest assembly
**Then** the class declares Class Parameters `MaxEntries = 20`, `MinUserConfidence = 0.3` per architecture §"Calibration constants"
**And** `Build(pPortalUser) As %String` queries `UserVocabulary WHERE PortalUser = :user AND Confidence >= ..#MinUserConfidence` ordered by `Confidence DESC, LastUsed DESC`, takes top `..#MaxEntries`, and renders as a Markdown-formatted digest string
**And** the digest format per architecture / search-agent research §"Vocabulary Digest" (operator-readable + LLM-parseable):
  ```
  ## Saved aliases for this user
  - "failed admits" — A01/A04 events with Status='Error' (confidence 0.85)
  - "lab orders" — ORM messages (confidence 0.72)
  ...
  ```
**And** the digest is capped at ~1,200 tokens (rough estimate: ~300 words; truncated with a "(N more aliases hidden)" marker if exceeded)
**And** if the user has no `UserVocabulary` rows OR all have `Confidence < ..#MinUserConfidence`, falls back to the top ~5 `SeedVocabulary` templates as a "Common idioms (no personal aliases yet)" fallback section

**Given** an integration test exercises the digest
**When** the test runs against a fixture with: User A has 25 vocab rows (10 with confidence ≥ 0.3); User B has 0 vocab rows
**Then** `Build("UserA")` returns a digest containing the 10 high-confidence rows (capped at MaxEntries=20)
**And** `Build("UserB")` returns the seed-vocabulary fallback digest
**And** the digest output is below ~1,200 tokens for both cases (verified by `$Length(digest) / 4` rough estimate)

**Given** the digest format
**When** an LLM consumes it (manual inspection by maintainer during pilot)
**Then** the LLM correctly interprets the aliases and uses them in subsequent reasoning (e.g., user types "find me admits" → LLM sees the digest's "failed admits" alias → maps to A01/A04 events without needing seed-vocabulary detour)

### Story 9.4: `AgentLoop` Integration — First-User-Message Prefix Injection

As an Operator using the Search Agent,
I want my first message in each conversation prefixed with my personal vocabulary digest (Story 9.3) — placed in the *uncached* user-message segment per architecture §"Vocabulary digest in *uncached* first-user-message prefix" — so that Anthropic prompt-cache hit rate is preserved (the cached `system + tools` prefix remains stable across turns) while my vocabulary still influences the agent's reasoning (NFR-P6, FR24).

**Acceptance Criteria:**

**Given** the developer is extending `SessionAgent.Agent.AgentLoop.RunTurn`
**When** they implement the first-user-message prefix injection
**Then** the AgentLoop checks `pAgentName == "message-search"` AND the `Chat.History.TurnsJson` contains zero prior user messages (i.e., this is the first turn of the conversation)
**And** if both conditions hold, the loop invokes `##class(SessionAgent.Search.VocabularyDigest).Build(pPortalUser)` and prepends the digest to `pUserText` separated by a clear delimiter (e.g., `"\n\n---\n\nUser: "`) per the canonical Anthropic-shape user message
**And** subsequent user messages in the same conversation do NOT receive the digest prefix (it's first-turn-only)
**And** the digest is in the user-message body, NOT in `system` or `tools` (which are the cached prefix per NFR-P6)

**Given** an integration test verifies cache preservation across turns
**When** the test simulates a 3-turn search-agent conversation: user → assistant → user (follow-up) → assistant → user (follow-up) → assistant
**Then** the second and third turns' provider requests have IDENTICAL `system + tools` prefix (verified by hashing the `system` string + `tools` JSON)
**And** the first turn's `messages[0].content` contains both the digest AND the user text
**And** the second/third turn's `messages[0]` is unchanged (no digest re-injection); new user messages are appended as `messages[N]`
**And** the `Audit.LlmCall.CacheHitTokens` is > 0 for the second and third turns when the active provider is Anthropic (validates Story 5.1's prompt-cache discipline)

**Given** an Operator using the Inspection Agent (NOT search)
**When** the AgentLoop runs `RunTurn` for `pAgentName == "session-inspection"`
**Then** no vocabulary digest is injected (digest is search-agent-only per FR24 design)
**And** the AgentLoop's behavior is unchanged from Story 2.12

### Story 9.5: `RecordClickThrough` ZenMethod Hyperevent Stub

As a developer preparing for Epic 10's Search Agent UI (the click-through capture lives in Epic 10's portal subclass; Epic 9 ships the backend hyperevent that Epic 10 will call),
I want a `RecordClickThrough(pSearchSessionKey, pSessionId, pContributingToolCallsJson) As %String` ZenMethod hyperevent stub on `SessionAgent.UI.ChatPanel` (or a dedicated capture class) that calls `UserVocabulary.RecordSuccess` for every alias inferred from the contributing tool calls,
So that Epic 10's UI side just needs to invoke this hyperevent on click-through without any backend changes per FR22 + Journey 2 Devin click-through silent capture.

**Acceptance Criteria:**

**Given** the developer is implementing the `RecordClickThrough` hyperevent
**When** they implement the method
**Then** the signature is `ClassMethod RecordClickThrough(pSearchSessionKey As %String, pSessionId As %String, pContributingToolCallsJson As %String) As %String [ZenMethod]`
**And** the method resolves caller context: `pPortalUser = %session.Username` (resolved AT THE BOUNDARY per architecture §"Caller context propagation" — never inside a tool)
**And** the method parses `pContributingToolCallsJson` into a `%DynamicArray` of `{tool_name, args, result}` blocks (the tool calls that produced the result list the operator clicked from)
**And** for each contributing tool call, the method invokes `SynthesizeAlias(tool_name, args)` per Story 9.1's verified determinism to produce a candidate alias string
**And** for each candidate alias, the method invokes `UserVocabulary.RecordSuccess(pPortalUser, alias, message_body_class, "clickthrough", "")` per Story 9.2 — the message_body_class comes from the tool's args if present (e.g., `search_by_message_class.message_body_class_name`)
**And** the method returns a JSON success response `{success: true, aliases_recorded: [...]}` for client-side acknowledgment (NOT for display — silent capture per UX-DR25)
**And** the method NEVER throws exceptions — any escape converts to a structured error JSON

**Given** an integration test exercises the hyperevent
**When** the test simulates: a search agent dispatched `search_by_status(status_in=["Error"])` and `search_by_message_class(message_body_class_name="EnsLib.HL7.Message")` then the operator clicked session 1184885
**Then** invoking `RecordClickThrough("<key>", "1184885", "[<two-tool-call-blocks>]")` results in 2 (or 1 if SynthesizeAlias dedupes) `UserVocabulary` rows with `CreatedVia='clickthrough'` and `SuccessCount=1` for the inferred aliases
**And** the audit log captures the vocabulary writes via Story 1.3's pre-registered `VocabWrite` events

**Given** the hyperevent is invoked from a stub or test harness (Epic 10's UI not yet shipped)
**When** the maintainer manually invokes the hyperevent via `%CSP.Page` test or via the Zen page hyperevent harness
**Then** the vocabulary capture works end-to-end without UI integration
**And** Epic 10 Story 10.3's UI-side click-through wiring just has to call this hyperevent — no further backend changes
**And** the **Epic 9 acceptance gate is met**: vocabulary persistence is recursion-safe; digest assembly and first-turn prefix injection preserve Anthropic prompt-cache; click-through capture entry point is ready for Epic 10's UI

---

## Epic 10: Search Agent — UI Embed, Hand-off & TTL Sweep

**Operator outcome:** Operator clicks a curated session entry → navigates to Visual Trace + Inspection Agent's chat tab loads with **"from search" stripe** quoting their literal query text + Accept / × Dismiss / implicit-accept; vocabulary capture happens silently as a side effect. Concurrent-tab lock surfaces as a non-modal banner. Search chat history sweeps after 30 days (operator-tunable). Vendored Markdown rendering bundle (marked + Prism.js + DOMPurify) ships at `/csp/static/iris-session-agent/` — code-block syntax highlighting for ObjectScript, JS, JSON, SQL, HL7, XML. **Completes v1 scope.**

**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 10.1**: `SessionAgent.EnsPortal.MessageViewer` subclass — chat tab + ZenMethod wiring (parallels Story 3.3 for Inspection)
2. **Story 10.2**: Search Agent UI rendering — `sa-search-result-entry` component + curated-list rendering in `chat-panel.js`
3. **Story 10.3**: Click-through capture wiring — silent vocab capture (calls Story 9.5 hyperevent) + navigation to Visual Trace with `FROM_SEARCH` URL param
4. **Story 10.4**: `sa-from-search-stripe` component + Inspection-side reading of `FROM_SEARCH` URL param + three-exit pattern
5. **Story 10.5**: `sa-concurrent-tab-banner` non-modal banner + lock detection + auto-dismiss
6. **Story 10.6**: `PurgeStaleSearchChat` + `UserVocabularyDecay` sweep tasks + Installer extensions
7. **Story 10.7**: Vendored Markdown bundle (marked + Prism.js + DOMPurify) deployment + `chat-panel.js` Growth-tier render upgrade
8. **Story 10.8**: Full `--sa-*` token resolution + Growth-tier components (`sa-config-form` Search variant from Epic 6, full off-page citation sync via `zenPage.openPage`)
9. **Story 10.9**: PRD v1 completion validation walkthrough — full Search → Inspection hand-off journey enacted on a real failed-admit search

### Story 10.1: `EnsPortal.MessageViewer` Subclass — Chat Tab + ZenMethod Wiring

As an Operator opening Message Viewer to find sessions,
I want a new "Ask the agent" tab right-appended to the existing Message Viewer tab strip — so that clicking it opens the Search Agent chat panel scoped to the current namespace's `Ens.MessageHeader` extent — with hot config-change support and returning-conversation surfacing,
So that the Search Agent UI mirrors the Inspection Agent UI affordance per UX-DR15 (operators learn the affordance once across both pages) and FR13.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.EnsPortal.MessageViewer`
**When** they implement the Zen page subclass of `EnsPortal.MessageViewer`
**Then** the class is at `src/SessionAgent/EnsPortal/MessageViewer.cls` per architecture §"Project Directory Structure"
**And** the subclass extends the parent's tab strip XData by appending `<tab caption="Ask the agent" id="askAgentTab">` to the *right* of all existing tabs per UX-DR15 (same label/position as Inspection's chat tab from Story 3.3)
**And** the new tab's body content is rendered via `OnDrawContent("DrawChatPanel")` calling `##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel("message-search", <searchSessionKey>, %session.Username)` — `searchSessionKey` is a registry-issued GUID (NOT an Ens session id) per FR43
**And** the host page contributes `chat-panel.js` (extended in Story 10.7 with Growth-tier render) via `OnPageHeadScript`

**Given** the developer is implementing the search session key generation
**When** the Operator first opens the chat tab on Message Viewer
**Then** the page generates a fresh `searchSessionKey` GUID (e.g., via `$System.Util.CreateGUID()`)
**And** the GUID is stored in `%session.Data` (CSP session) for stability across page interactions within the same browser session
**And** subsequent visits to the chat tab in the same browser session re-use the same `searchSessionKey` (returning conversation surfaced via Story 10.2's renderer reading `Chat.History`)
**And** the operator can explicitly start a new search session via a "New search" affordance (Story 10.2 — small button in the chat panel) which generates a fresh GUID

**Given** the developer is implementing the `SendChatMessage` ZenMethod hyperevent (parallels Story 3.3)
**When** they implement the method
**Then** the signature matches the Inspection-side method: `ClassMethod SendChatMessage(pAgentName, pSessionKey, pUserText, pContextHintsJson) As %String [ZenMethod]` — same name, same shape so client-side `chat-panel.js` works for both pages
**And** the method invokes `##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", pSessionKey, %session.Username, pUserText, pContextHintsJson)` per Story 9.4's first-user-message prefix injection (vocabulary digest is auto-prepended on the first turn)
**And** the method returns the `TurnResult.ToJson()` string for client-side parsing
**And** error handling per Story 3.3: no exceptions escape; structured error JSON for any failure

**Given** the page is included in `module.xml`'s `<Resource Name="SessionAgent.PKG"/>`
**When** the operator navigates to `/csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen` (HealthShare) OR `/csp/<NS>/SessionAgent.EnsPortal.MessageViewer.zen` (plain IRIS)
**Then** the page loads with all parent Message Viewer functionality intact
**And** the new "Ask the agent" tab is visible in the tab strip
**And** clicking the tab opens the chat panel without errors

### Story 10.2: Search Agent UI Rendering — `sa-search-result-entry` + Curated List

As an Operator typing a query in the Search Agent and receiving a curated list of sessions,
I want each session entry rendered as `sa-search-result-entry` (real `<a>` element with descriptive `aria-label`, columns SessionId · TimeCreated · Source/Target · MessageBodyClassName · Status · brief context) — clicking an entry triggers Story 10.3's hand-off to Visual Trace,
So that I can scan results quickly and click-through with one tap per UX-DR9 + Devin Journey 2 first-successful-search experience.

**Acceptance Criteria:**

**Given** the developer is extending `chat-panel.js` (Story 3.2) for the search-agent path
**When** the agent returns a `TurnResult` whose `assistantMarkdown` contains a curated session list (the AgentLoop assembles this from search-tool dispatches in Stories 8.3–8.6)
**Then** the script detects the search-result list shape (e.g., a structured marker in the JSON payload like `result_type: "search_session_list"` plus a `sessions: [...]` array)
**And** the script renders each session as `<a class="sa-search-result-entry" href="#" data-session-id="..." data-search-session-key="..." aria-label="Session 1184885 from EpicADT to PartnerHospital, ADT_A01, Status: Error, 3 minutes ago">`
**And** each entry's visible content includes columns per UX-DR9: SessionId · TimeCreated (relative + absolute on hover) · Source/Target arrow · MessageBodyClassName (truncated) · Status (with `--sa-tool-card-status-error` color for Error per UX-DR21) · brief context (first ~80 chars from the agent's narrative annotation per session, if provided)
**And** the entries are hover-styled per UX-DR9 (subtle background change inheriting parent palette)
**And** the entire row is clickable (anchor + `display: block`)

**Given** the curated list is rendered
**When** the operator clicks a `sa-search-result-entry`
**Then** the click handler is wired to Story 10.3's capture + navigation logic
**And** focus + keyboard activation (Enter) work via the native `<a>` element

**Given** the agent finds no matches
**When** the response payload contains an empty `sessions[]` array OR a structured "no_results" marker
**Then** the script renders an `sa-message-block sa-msg-agent` with the agent's no-match narrative + suggested refinements per UX-DR17-full no-results empty state (e.g., *"No failed admits in the last hour. Try widening to 6h, or check the source connection — the source clinic may not have sent any."*)
**And** the operator can immediately type a refinement without clearing the panel

**Given** the agent returns >50 matches (capped per FR19)
**When** the response payload includes `result_count > 50` or a `truncation_note` marker
**Then** the script renders the agent's narrative noting the truncation per UX-DR29 (*"Showing 50 most recent of 217 matches. Tighten the time window or specify a source/target to narrow further."*)

**Given** an integration test exercises the search rendering path via headless Chrome (or jsdom)
**When** the test simulates a search response with 5 session entries
**Then** the rendered DOM contains 5 `sa-search-result-entry` anchors with correct attributes
**And** each anchor's `aria-label` summarizes the row content per UX-DR20

### Story 10.3: Click-Through Capture + Navigation to Visual Trace

As an Operator clicking a session in a Search Agent result list,
I want the click to silently capture the vocabulary alias (via Story 9.5's `RecordClickThrough` hyperevent) AND navigate to Visual Trace on that session with a `FROM_SEARCH` URL parameter carrying the search context,
So that vocabulary learns automatically (FR22) and the destination Inspection Agent can render the "from search" stripe (Story 10.4) per FR20 + UX-DR25 + Devin Journey 2.

**Acceptance Criteria:**

**Given** the developer is wiring the click handler in `chat-panel.js`
**When** the operator clicks a `sa-search-result-entry`
**Then** the handler invokes `zenPage.RecordClickThrough(searchSessionKey, sessionId, JSON.stringify(contributingToolCalls))` per Story 9.5's hyperevent contract
**And** the contributing tool calls list is assembled client-side from the chat transcript's most recent agent turn (the tool-call cards that produced the result list)
**And** the hyperevent invocation is fire-and-forget (silent capture per UX-DR25 — operator sees no confirmation; no waiting for response before navigating)
**And** the handler then navigates the browser to `/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<sessionId>&FROM_SEARCH=<searchSessionKey>` (HealthShare) OR `/csp/<NS>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<sessionId>&FROM_SEARCH=<searchSessionKey>` (plain IRIS) — the URL pattern matches Story 1.5's installer-printed bookmark patterns with the added `FROM_SEARCH` query param

**Given** the navigation completes
**When** the destination Visual Trace page loads
**Then** Story 10.4's Inspection-side logic reads the `FROM_SEARCH` URL parameter and renders the `sa-from-search-stripe`
**And** the navigation preserves any other URL parameters (e.g., parent's `MSGID`, `RECEIVED`, etc.)

**Given** an integration test exercises the click-through end-to-end
**When** the test simulates: search agent dispatches `search_by_status` + `search_by_message_class` then operator clicks session 1184885 in the rendered list
**Then** Story 9.5's `RecordClickThrough` hyperevent is invoked with the correct contributing tool calls
**And** browser navigation occurs to the correct URL with both `SESSIONID` and `FROM_SEARCH` params
**And** vocabulary rows are captured silently (per Story 9.5)

### Story 10.4: `sa-from-search-stripe` + Inspection-Side `FROM_SEARCH` Handling

As an Operator who arrived at Visual Trace via a Search Agent click-through,
I want a single-line "from search" stripe at the top of the Inspection Agent's chat panel quoting my literal search query (e.g., *"You came from a search for 'failed admits' — want me to look at this session?"*) with three exits (Accept / × Dismiss / implicit-accept on typing a new message),
So that the search context is inherited per FR47 + UX-DR5 + UX-DR25 without forcing me through a modal or extra confirmation.

**Acceptance Criteria:**

**Given** the developer is extending `SessionAgent.EnsPortal.VisualTrace` (Story 3.3)
**When** they implement the `FROM_SEARCH` URL param reading
**Then** when the chat tab opens AND `FROM_SEARCH` URL param is non-empty, the page loads the search session's `Chat.History` row (`AgentName='message-search', SessionKey=<from_search_key>`) and extracts the operator's literal first-user-message (the search query text — stripped of any vocabulary-digest prefix per Story 9.4)
**And** the page passes the literal query text to the chat panel renderer for inclusion in the stripe
**And** if `FROM_SEARCH` is empty (normal Inspection flow without hand-off), no stripe renders

**Given** the developer is implementing the `sa-from-search-stripe` component
**When** they implement the rendering in `chat-panel.js` + CSS in `sessionagent-chat.css`
**Then** the stripe renders as a single line above the chat transcript: 32px height, 3px left-edge accent via `--sa-from-search-stripe-border`, subtle tint background via `--sa-from-search-stripe-bg`, 12px horizontal padding per UX-DR5
**And** the stripe text is *"You came from a search for '<literal-query-text>' — want me to look at this session?"* with `<literal-query-text>` HTML-escaped to prevent XSS
**And** the stripe has two inline buttons: `<button class="sa-stripe-accept">Accept</button>` + `<button class="sa-stripe-dismiss" aria-label="Dismiss from-search context">×</button>`
**And** the stripe has `role="status" aria-live="polite"` per UX-DR20

**Given** the operator clicks Accept
**When** the click handler fires
**Then** the handler triggers an automatic agent turn passing the search context as a `contextHints` payload — e.g., `{from_search: true, search_query: "failed admits", search_session_key: "..."}` — to `SendChatMessage`
**And** the AgentLoop's first agent message acknowledges the context (e.g., *"Looking at this session in context of failed admits..."*) and proceeds to dispatch tools
**And** the stripe is hidden after Accept (UX-DR25 — shows once per chat session, doesn't reappear)

**Given** the operator clicks × Dismiss
**When** the click handler fires
**Then** the stripe is hidden + the search context is cleared (no automatic turn)
**And** the chat operates as a fresh conversation
**And** the stripe stays hidden for the rest of the chat session (UX-DR25 — doesn't reappear)

**Given** the operator types a new message before clicking either button (implicit-accept per UX-DR25)
**When** the operator submits the message
**Then** the search context is still inherited (treated as implicit Accept) — `contextHints` carries the search context to `SendChatMessage`
**And** the stripe is hidden
**And** the agent's first response acknowledges both the operator's message AND the search context

**Given** an integration test exercises the hand-off end-to-end
**When** the test simulates: search session generates `searchSessionKey=K`, operator clicks session 1184885, browser navigates with `FROM_SEARCH=K`, page loads + stripe renders + operator clicks Accept
**Then** the AgentLoop's contextHints payload includes the search context
**And** the agent's first dispatch references the search query in its narrative
**And** the stripe is hidden after Accept

### Story 10.5: `sa-concurrent-tab-banner` Non-Modal Banner

As an Operator opening a chat tab in a second browser tab while the first tab has a turn in flight,
I want a non-modal banner at the top of the chat panel saying *"Another browser tab is mid-conversation with this agent. Switch to it or wait for it to complete."* — input field disabled until the lock releases, banner auto-dismisses,
So that I see graceful degradation (no 500 error, no stuck spinner) per FR46 + UX-DR8 + NFR-P4.

**Acceptance Criteria:**

**Given** the developer is implementing the lock-detection mechanism
**When** the chat panel opens AND another tab holds the `%OpenId(id, 4)` lock on the same `Chat.History` row (per Story 2.6)
**Then** the page detects the lock — either via a server-side check at chat-panel-open time (a `IsLocked()` ZenMethod that returns boolean + lock holder info) OR via the `SendChatMessage` ZenMethod returning a structured "lock held" error envelope on submit
**And** the chat panel renders `<div class="sa-concurrent-tab-banner" role="alert" aria-live="assertive">Another browser tab is mid-conversation with this agent. Switch to it or wait for it to complete.</div>` per UX-DR8 + UX-DR20
**And** the banner is 40-48px height with parent's warning/notice color (TBD-resolved via `--sa-from-search-stripe-bg` or a new `--sa-banner-warning-bg` token)
**And** the input field has `aria-disabled="true"` plus visual de-emphasis per UX-DR20

**Given** the lock releases (the other tab's turn completes)
**When** the banner-detection mechanism polls (or receives a server-side event)
**Then** the banner auto-dismisses without operator action
**And** the input field re-enables
**And** the operator can immediately type and submit

**Given** the polling mechanism is implemented
**When** the implementation choice is made
**Then** the choice is documented: either client-side polling every ~2 seconds while the banner is shown (simple, slight overhead) OR server-side push via Server-Sent Events (cleaner, more complex — likely Vision-tier per architecture §"Streaming responses")
**And** for v1, client-side polling is the default (simpler, fits the blocking-dispatch architecture)

**Given** an integration test simulates concurrent tabs
**When** the test fires two simultaneous `SendChatMessage` requests against the same `Chat.History` row from two pseudo-process contexts
**Then** the first request acquires the lock and proceeds
**And** the second request receives a "lock held" error envelope with the holder's process info
**And** the second tab's UI renders the banner correctly
**And** when the first tab completes, the second tab's polling detects lock release and the banner auto-dismisses

### Story 10.6: `PurgeStaleSearchChat` + `UserVocabularyDecay` Sweep Tasks

As an Operator-Admin with a long-running production install,
I want two sweep tasks running automatically: `PurgeStaleSearchChat` (daily 03:00 UTC, removes Search-keyed `Chat.History` rows older than `Config.Agent.SearchChatRetentionDays` default 30) + `UserVocabularyDecay` (Sunday 04:00 UTC, removes `UserVocabulary` rows where `Confidence < 0.2 AND LastUsed > 90d`),
So that storage doesn't grow unboundedly per FR45 + AR4 + NFR-R3 + NFR-SC4.

**Acceptance Criteria:**

**Given** the developer is implementing `SessionAgent.Task.PurgeStaleSearchChat`
**When** they implement the task class (parallels Story 7.2's `PurgeOrphanedChatHistory`)
**Then** the class extends `%SYS.Task.Definition` with `TaskName = "PurgeStaleSearchChat"`, scheduled daily 03:00 UTC
**And** `OnTask()` reads `Config.Agent.SearchChatRetentionDays` (default 30; per Config.Agent property from Story 2.4) for the `message-search` agent
**And** the method deletes `Chat.History` rows WHERE `AgentName = 'message-search'` AND `UpdatedAt < <now - retentionDays>` (using `%EXACT()` discipline + parameterized prepare per project rule)
**And** per Story 7.1's audit FK cascade design choice, handles audit cleanup accordingly
**And** emits a native IRIS audit event via `$System.Security.Audit("SessionAgent","TaskRun","PurgeStaleSearchChat", {rows_deleted: N, retention_days: ...})`
**And** project-rule discipline: `Set tSC = $$$OK` first line, `Quit tSC` last line, transaction side-effect rules

**Given** the developer is implementing `SessionAgent.Task.UserVocabularyDecay`
**When** they implement the task class
**Then** the class extends `%SYS.Task.Definition` with `TaskName = "UserVocabularyDecay"`, scheduled weekly Sunday 04:00 UTC
**And** the class declares Class Parameters `DecayConfidenceThreshold = 0.2`, `DecayLastUsedDays = 90` per architecture §"Calibration constants"
**And** `OnTask()` deletes `UserVocabulary` rows WHERE `Confidence < ..#DecayConfidenceThreshold` AND `LastUsed < <now - ..#DecayLastUsedDays>` (using `%EXACT()` + parameterized prepare)
**And** emits audit event `(SessionAgent, TaskRun, UserVocabularyDecay)`

**Given** the developer is extending `SessionAgent.Installer.Install` (Story 1.5)
**When** they replace the defensive placeholders for both tasks with actual scheduling
**Then** Installer's `ScheduleTaskIfClassExists("PurgeStaleSearchChat", ..., "daily", 3, 0)` schedules the daily search-chat sweep
**And** Installer's `ScheduleTaskIfClassExists("UserVocabularyDecay", ..., "weekly", 4, 0, "Sunday")` schedules the weekly vocab decay
**And** both schedulings are idempotent per NFR-R5

**Given** integration tests verify both sweeps
**When** the tests run against fixtures: 100 search-chat rows (50 older than 30 days + 50 newer); 50 user-vocab rows (10 with Confidence < 0.2 + LastUsed > 90d, 40 fresh)
**Then** `PurgeStaleSearchChat.OnTask()` deletes the 50 stale search-chat rows leaving the 50 fresh
**And** `UserVocabularyDecay.OnTask()` deletes the 10 decayed vocab rows leaving the 40 fresh
**And** both tasks emit the expected audit events
**And** NFR-R3 (search-history TTL) + NFR-SC4 (audit-log volume bounded) are structurally validated

### Story 10.7: Vendored Markdown Bundle + `chat-panel.js` Growth-Tier Render Upgrade

As an Operator reading a long-form agent answer with code blocks (e.g., the agent shows a fragment of an HL7 message, an SQL query, or an ObjectScript snippet),
I want the answer rendered with proper Markdown structure + syntax-highlighted code blocks via the vendored `marked` + `Prism.js` + `DOMPurify` bundle hosted at `/csp/static/iris-session-agent/`,
So that long-form answers are scannable, code is highlighted (ObjectScript / JS / JSON / SQL / HL7 / XML), and all rendering is XSS-safe per FR54 + UX-DR13 + NFR-C5 (no CDN — self-hosted).

**Acceptance Criteria:**

**Given** the developer is preparing the vendored bundle
**When** they download + commit the asset files to `src/static/`
**Then** the directory contains per architecture §"Vendored static-asset layout":
  - `marked.min.js` (≥ 18.0.2, CVE-2026-41680 fixed; ~12 KB gzipped)
  - `prism.min.js` (core)
  - `prism-objectscript.js` (custom grammar; falls back to 'markup' if not loaded)
  - `prism-sql.js`
  - `prism-javascript.js`
  - `prism-json.js`
  - `prism-hl7.js` (custom grammar)
  - `prism-xml.js`
  - `prism.min.css` (low-contrast theme matching parent palette)
  - `dompurify.min.js` (3.x; XSS gate before innerHTML injection)
  - `chat-panel.js` (~50-line wrapper: marked → Prism → DOMPurify pipeline) — replaces Story 3.2's MVP fallback render path
  - `sessionagent-chat.css` (Growth-tier full token resolution — Story 10.8 finalizes)

**Given** the bundle is deployed via `module.xml`'s `<FileCopy>` (Story 1.1's scaffold)
**When** the operator installs / re-installs the package
**Then** the files land at `/csp/static/iris-session-agent/` per architecture §"Static-asset CSP application"
**And** the `<CSPApplication>` declared in `module.xml` (Story 1.1) serves the files unauthenticated per `AuthenticationMethods="64"`
**And** browser requests to `/csp/static/iris-session-agent/marked.min.js` etc. return the assets with correct MIME types

**Given** the developer is upgrading `chat-panel.js` to use the vendored bundle
**When** they replace the Story 3.2 MVP fallback render path with the Growth-tier pipeline
**Then** the script loads `marked.min.js`, `prism.min.js` + curated language packs, `dompurify.min.js` via `<script>` tags from the host page (Stories 3.3 + 10.1 wire the `<script>` includes)
**And** the agent-answer rendering pipeline is: (1) raw Markdown string from `TurnResult.assistantMarkdown` → (2) `marked.parse(markdown)` → HTML string → (3) `Prism.highlightAllUnder(domNode)` for syntax highlighting → (4) `DOMPurify.sanitize(html)` → safe HTML → (5) `innerHTML` injection
**And** code blocks with language hints (e.g., ` ```objectscript ... ``` `) get the appropriate Prism grammar applied; unknown languages fall back to `markup` (Prism's generic) gracefully
**And** the citation chip parsing (Story 3.2's pattern detection) still works after Markdown render — chips are post-processed via querySelector on the rendered DOM

**Given** an integration test exercises the rendering pipeline via headless Chrome (or jsdom with Markdown libraries)
**When** the test feeds an agent response containing: a paragraph, an HL7 code block, an ObjectScript code block, an inline citation chip
**Then** the rendered DOM contains the paragraph as `<p>`, the code blocks as `<pre><code class="language-hl7">` and `<pre><code class="language-objectscript">` with Prism-applied syntax classes, and the citation chip as a clickable anchor
**And** an XSS-attempt test (Markdown containing `<script>alert(1)</script>` or `<img onerror>`) is sanitized by DOMPurify — the script does NOT execute
**And** NFR-C5 enforcement (no CDN) is verified by Story 1.7's CI grep — no `https://cdn.*` references in `src/static/`

### Story 10.8: Full Token Resolution + Growth-Tier UX Components

As an Operator using the chat panel after Growth-tier polish,
I want the full `--sa-*` token set resolved against the parent Mgmt Portal palette + `sa-config-form` Search-agent variant (parallels Story 6.1) + full off-page citation sync via `zenPage.openPage` (UX-DR24-Growth replacing Story 3.4's MVP partial sync),
So that the visual coherence is complete per UX-DR12-full + UX-DR27-Growth and the citation trust loop works for off-page items per UX-DR24-Growth.

**Acceptance Criteria:**

**Given** the developer is finalizing the `--sa-*` token resolution per UX-DR12-full + UX-DR23
**When** they read `EnsPortal.Application.cls` source per project rule "IRIS Library Source" and resolve the parent palette colors
**Then** every `--sa-*` token in `sessionagent-chat.css` has a concrete fallback value resolving to the parent palette (e.g., `--sa-message-operator-bg: var(--portal-low-contrast-bg, #f5f5f5);`)
**And** all token values pass WCAG AA contrast (4.5:1 body / 3:1 non-text) per UX-DR23 — verified by static check during this story + re-checked if Mgmt Portal palette changes
**And** any contrast failures are corrected with adjusted token values

**Given** the developer is implementing the `sa-config-form` Search-agent variant
**When** they extend Story 6.1's AgentConfig form
**Then** the form's "Agent" selector picks `message-search` and the form pre-populates with the Search agent's current `Config.Agent` row
**And** the form supports the same fields as Inspection: provider, model, temperature, max-tokens, system-prompt-override, credentials, enabled
**And** the form additionally exposes `SearchChatRetentionDays` (Story 2.4's Config.Agent property; Story 10.6's PurgeStaleSearchChat reads it) — number input with default 30, validation `>= 1`
**And** the Save handler (Story 6.2) handles the Search variant identically to Inspection (no special-case logic; same `Config.Agent` row shape)

**Given** the developer is upgrading citation chip off-page sync per UX-DR24-Growth
**When** they replace Story 3.4's MVP partial-sync (Header tab updates; SVG highlight stays) with the Growth-tier full-sync
**Then** the `onCitationClick` handler for off-page items first calls `zenPage.openPage(targetPage)` to navigate the SVG to the page containing the cited row, then calls `svgPage.selectItem(...)` to highlight the cited box, then calls `zenPage.updateTabs(true)` to re-render the Header tab — all three sync points fire, matching the on-page experience
**And** Story 3.4's accepted-MVP-limitation note in this AC and `epics.md` Story 3.4 is updated to reference Story 10.8 as the resolution

**Given** an integration test exercises the Growth-tier components
**When** the test runs against a fixture with: an off-page citation, an `Operator-Admin` configuring the Search agent, and the panel's full token resolution
**Then** the off-page citation click correctly invokes `openPage` → `selectItem` → `updateTabs` (verified by mock spying)
**And** the Search-agent config form persists and reads correctly (NFR-O2 hot config also verified for Search)
**And** all `--sa-*` tokens resolve to the expected parent palette values

### Story 10.9: PRD v1 Completion Validation Walkthrough

As the maintainer (Joshua) and a pilot operator (Devin-class junior engineer + Marisol-class senior),
I want a documented walkthrough on a real production scenario where the Devin-class operator opens Message Viewer's chat tab, types *"find me failed admits from the last hour"*, gets a curated session list, clicks through to Visual Trace, sees the "from search" stripe, asks a follow-up Inspection question, and resolves the incident — all within the Devin Journey 2 flow,
So that we explicitly satisfy [PRD §"Product Scope" v1 completion](prd.md): both agents work end-to-end, hand-off works, vocabulary captures silently, all 10 epics integrate cleanly. **Closes Epic 10 + closes v1.**

**Acceptance Criteria:**

**Given** all v1 epics are complete (Epics 1–10 stories all merged) and installed on a pilot IRIS instance
**When** the maintainer prepares the v1-completion walkthrough
**Then** the maintainer identifies a real scenario from the pilot operator's recent on-call history that exercises the Search → Inspection hand-off (e.g., a real "failed admits" scenario, or an equivalent multi-step diagnostic)
**And** the maintainer ensures both `Config.Agent` rows are `Enabled=1` with provider configured (Story 6.1's UI used)

**Given** the pilot operator opens Message Viewer
**When** they click "Ask the agent" and type *"find me failed admits from the last hour"*
**Then** the Search Agent dispatches the appropriate tools (vocabulary captures the alias if first time; uses learned alias on repeat per Story 9.2)
**And** the agent returns a curated list (≤50 results) within 90s per NFR-P2
**And** the operator clicks one of the results

**Given** the operator clicked a result
**When** the browser navigates to Visual Trace + the chat tab loads
**Then** the `sa-from-search-stripe` is visible quoting their literal search query per UX-DR5 + Story 10.4
**And** vocabulary capture happened silently (verified by checking `UserVocabulary` table after)
**And** the operator clicks Accept (or types a follow-up — implicit accept)
**And** the Inspection Agent dispatches against the chosen session and produces a grounded answer with citations
**And** the operator clicks a citation to verify per Story 3.4

**Given** the walkthrough completes successfully
**When** the maintainer inspects the audit log
**Then** `Audit.LlmCall` rows show both `message-search` and `session-inspection` agents activity for the same operator
**And** `Audit.ToolCall` rows show search-agent tools dispatched followed by inspection-agent tools dispatched (Devin Journey 2 trace)
**And** `UserVocabulary` shows the learned alias from the silent capture
**And** the operator's overall time-to-resolution matches or beats their pre-product baseline (NFR-P5; informally validated by self-report)
**And** the maintainer captures a 1-paragraph operator quote for the v1.0.0 release notes

**Given** the v1 release tag is being prepared
**When** the maintainer runs the full FR59 cross-matrix gate
**Then** the maintainer re-runs `Test.ToolCallRoundtripIntegrationTest` (Story 5.4) against the **complete v1 tool catalog** — 13 inspection tools (from Stories 2.11 + 4.1–4.7) + 10 search tools (from Stories 8.3–8.7) = 23 tools × 4 providers = 92 combinations — and asserts `successful_combinations == 92`
**And** any combination that fails surfaces with `provider=<name>, tool=<name>, reason=<...>` and blocks the v1.0.0 release tag until resolved
**And** the test output is recorded in the release notes for FR59 traceability

**Given** the v1 completion walkthrough succeeds
**When** the maintainer documents v1 release readiness
**Then** the maintainer creates the `v1.0.0` release tag (or updates the milestone tracker to mark v1 complete)
**And** the README + `docs/operator-quickstart.md` are updated with any feedback worth incorporating
**And** the Open Exchange listing is created/updated per architecture OD10
**And** the **Epic 10 acceptance gate is met + v1 SCOPE COMPLETE**: both agents working end-to-end, hand-off validated, vocabulary learning operational, sweep tasks scheduled, vendored Markdown bundle deployed, full UX coherence achieved, FR59 cross-matrix gate passed against the full 23-tool catalog

---

## Epic 12: Walkthrough Hardening — Bug Fixes & UX Polish

**Status:** backlog (opened 2026-05-08).

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` captures all 11 findings (8 bugs + 3 doc enhancements) with reproduction steps, verified root causes (file paths + line numbers), and recommended fix shapes. Each Story 12.x spec cites this artifact as the source-of-truth for ACs.

**Stories (in order):**
- 12.0 — Epic 11 deferred cleanup + Epic 12 setup (Rule 7 sprint-planning gate)
- 12.1 — UX polish: chat panel CSS overflow + Inspection prompt Ensemble domain knowledge (BUG-01 + BUG-08)
- 12.2 — Agent reliability: provider HTTP error diagnostics + tool class-name fallback (BUG-02 + BUG-03)
- 12.3 — MessageViewer session-link override to custom VisualTrace (BUG-04)
- 12.4 — AgentLoop MaxIterationsPerTurn configurability + richer fallback message (BUG-06)
- 12.5 — Search Agent results drive MessageViewer table (BUG-05)
- 12.6 — Chat history tile replay — preserve tool_use / tool_result blocks across page reload (BUG-07)
- 12.7 — README rewrite: Quick Start + screenshots + clean-namespace recipe + launch URLs (ENH-09 + ENH-10 + ENH-11)

**Out of scope for Epic 12:**
- Cross-browser sweep (Firefox / Safari / Edge) — already deferred to a post-MVP cross-browser hardening epic.
- New tool additions or new agents — Epic 12 is hardening only.
- Vocabulary tier or learning-loop changes — Epic 9 territory.
- Architectural changes — none of the 11 findings require architectural decisions.

**Acceptance gate:**
All 8 stories ship `done`. Empirical battery (Rule 6) at retro time exercises each fix end-to-end against real walkthrough scenarios from 2026-05-08. The 11 findings in `walkthrough-bugs-2026-05-08.md` are each addressed (with citation in the Story 12.x Completion Notes that fixed them). README at retro-time has Quick Start, screenshots, clean-namespace recipe, and launch URLs (ENH-09/10/11 all surface in the rendered README). No regression on v1.0.1 functionality.

**Recommended ordering** (from the Sprint Change Proposal):
12.0 → 12.1 → 12.3 → 12.2 → 12.4 → 12.6 → 12.5 → 12.7 — bottom-up by risk, README last so screenshots show all fixes in place.

Per Rule 1 (≤ 250 lines / spec) and the project's `/bmad-create-story` workflow, individual story specs are drafted at `/epic-cycle 12` time (Step 4a of the pipeline), not in this epic-list document.

**See also:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-05-08.md` for the full impact analysis, story bundling rationale, and approval trail that opened this epic.

---

## Epic 13: Tool Catalog Expansion

**Status:** backlog (opened 2026-05-09).

**Source:** `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` captures all 5 tools with per-tool detail (operator-facing question, IRIS API, arguments, response shape, truncation guards, project-rule compliance, LOC estimate). Each Story 13.x spec cites this artifact as the source of truth.

**Trigger:** the 2026-05-09 demo on session 80562 surfaced an explicit gap — the Inspection Agent correctly self-reported *"the full source code is needed to see the exact routing logic"* after using `get_business_process_source` (which returns signatures only). Project lead's scoping conversation expanded the tool plan to 5 new tools across the source / configuration / queue / cross-session-search axes.

**Stories (in order):**
- 13.0 — Epic 12 deferred cleanup + Epic 13 setup (Rule 7 sprint-planning gate)
- 13.1 — `get_class_source` — Inspection tool returning full UDL source for any class with optional method-name filter (~80 LOC + tests). Pairs with `get_business_process_source` (existing). Also builds `Test.Util.RegressionSweepCount` helper that 13.2-13.5 reuse (Epic 12 retro AI-2 carry-forward).
- 13.2 — `get_rule_source` — Inspection tool returning the `RuleDefinition` XData of an Ens rule class (~60 LOC + tests). Pairs with `rule_log` (existing).
- 13.3 — `get_production_config_item` — Inspection tool returning adapter + custom + pool/queue settings for a config item (~80 LOC + tests). Pairs with `session_timeline` / `message_headers`.
- 13.4 — `get_queue_state` — Inspection tool returning `Ens.Queue` row for a config item (~40 LOC + tests). Pairs with `session_summary`.
- 13.5 — `find_sessions_using_class` — **Search** tool (cross-session, lives in `src/SessionAgent/Tool/Search/`, registers with `message-search`) for sessions touching a given class (~80 LOC + tests). Bounded-WHERE invariant per FR59.

**Out of scope for Epic 13:**
- DTL-specific transformation tool (subsumed by `get_class_source` — DTLs are just classes).
- HL7 schema introspection (very niche, large surface).
- Lookup-table content tool (`get_lookup_table`) — deferred per scoping conversation; nice-to-have but not blocking.
- Production-status / list-active-productions tooling (Search-Agent-flavored, low investigation utility).

**Acceptance gate:**
All 6 stories ship `done`. Tool catalog grows to 28 entries verifiable via `Tool.Registry:ListTools`. FR59 cross-matrix gate runs clean against 112 combinations (or skips per credential resolvability per Rule 11). Each new tool ships its own test class. Live-agent demo turn (Rule 6 step 4): Inspection Agent answers *"What does the OrderRouter rule say, and where is FilePublish writing files to?"* — exercises 13.2 + 13.3 in one turn. No regression on v1.0.2 functionality. Final regression sweep clean (≈491 expected — 461 baseline + ~30 new).

**Recommended ordering** (per Sprint Change Proposal — bottom-up by risk):
13.0 → 13.4 → 13.2 → 13.1 → 13.3 → 13.5 — smallest tool first to validate the "add a new tool" path, then build up to the originally-motivating `get_class_source`, then 13.3's `Ens.Config.*` SQL family, then the Search-Agent variant last.

**See also:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-05-09.md` for the full impact analysis, Story 13.0 triage of Epic 12 retro AIs (3 INCLUDE as Carry-Forward, 2 DEFER to v3), and approval trail that opened this epic.
