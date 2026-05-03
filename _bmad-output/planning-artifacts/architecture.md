---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
workflowType: 'architecture'
lastStep: 8
status: 'complete'
completedAt: '2026-05-02'
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/product-brief-iris-session-agent.md
  - _bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md
  - _bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md
  - _bmad-output/planning-artifacts/research/technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md
  - _bmad-output/planning-artifacts/research/technical-ensemble-session-inspection-agent-research-2026-04-24.md
  - _bmad-output/planning-artifacts/research/technical-ensemble-session-agent-ui-integration-research-2026-04-24.md
  - _bmad-output/planning-artifacts/research/cleanup-edit-proposal-2026-05-02.md
  - docs/initial-prompt.md
inputDocumentNotes:
  - "The two 2026-04-24 Ensemble research docs are loaded as historical context. Their AI-Hub bindings are explicitly superseded by the 2026-05-01 pure-ObjectScript research; their Ens.* schema, SessionId correlation spine, body-class dispatch ladder, BP introspection, and 14-column trace projection content remain authoritative and is reused verbatim in the v1 design."
  - "docs/initial-prompt.md is the user's original authoritative scope spec; all five expansions it added (two agents, four providers, per-agent Zen config, lifecycle coupling, IPM-installable) are already absorbed into the brief, distillate, and PRD."
referenceSource:
  - irislib/  (full IRIS class library — available for spot-research as needed)
  - sources/iris-session-chat/  (hackathon predecessor codebase — historical reference)
persistentMemoryFacts:
  - Implementation language — pure ObjectScript only; no embedded Python in the runtime path
  - IRIS version floor — 2024.1; every API/class/parameter must be verified available in 2024.1
  - V1 scope — TWO agents (Inspection + Search), FOUR providers (OpenAI/Anthropic/Gemini/Ollama-vLLM, OpenAI ships first), per-agent Zen config, MCP serving deferred (registry stays MCP-exportable), Phase 1 REPL out
  - Package naming — ALL custom classes under SessionAgent.* including portal subclasses; RBAC role is %SessionAgent_ReadOnly
  - Search agent — body-search via two-stage indexed-prefilter + body-inspection; vocabulary keyed (PortalUser, MessageBodyClass, Alias)
  - Product posture — single-author hobby project, MIT open-source from day one, no commercial motion, milestone-based timeline
project_name: 'iris-session-agent'
user_name: 'Joshua Brandt'
date: '2026-05-02'
revisions:
  - date: '2026-05-02'
    by: 'bmad-create-epics-and-stories Step 2 (epic design)'
    summary: 'Aligned epic numbering with epics.md 10-epic consolidated structure. Replaced §"Decision Impact Analysis → Implementation Sequence" 18-step enumeration with 10-epic v1 sequence; updated Implementation Handoff Epic-range references; updated 6 carry-forward Task-0 probes; updated 7 Gap Analysis Epic references; added §"Epic-Sequence Evolution" section preserving the architect''s original 18-step thinking as story-order rationale + bidirectional mapping table; updated §"Enforcement Guidelines" rule 13 (Epic 12+ → Epic 8+).'
  - date: '2026-05-02'
    by: 'bmad-create-epics-and-stories Step 4 (final validation)'
    summary: 'Re-anchored EnsLib.HL7.SearchTable Task-0 probe from Epic 8 to Epic 4 Story 4.6 (FindSessionsByBody is the first cross-codebase SearchTable consumer; Epic 8 Story 8.5 SearchByBodyField reuses the captured shape). Updated §"Implementation Handoff → Carry-forward Task-0 probes" entries 3-6 with story numbers + re-anchoring note; updated Gap Analysis G5 reference.'
---

# Architecture Decision Document — iris-session-agent

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements** — 59 FRs across 8 capability areas:

| Area | FR range | Architectural impact |
|---|---|---|
| Session Inspection | FR1–FR12 | 13-tool catalog over 6 Ens.* data surfaces; chat panel embedded in custom `EnsPortal.VisualTrace` subclass; chat history coupled to Ens session |
| Message Search | FR13–FR24 | 8 indexed-access tools + 1 body-inspection + 1 vocab utility; bounded-WHERE invariant; per-user vocabulary learning |
| LLM Provider Framework | FR25–FR30 | 4-provider abstraction (Anthropic-canonical wire shape, OpenAI ships first); 90s per-call cap; Anthropic prompt-caching of `system + tools` prefix |
| Read-Only Enforcement & Audit | FR31–FR37 | Three-layer enforcement (code + dispatch gate + RBAC); FK-linked LlmCall/ToolCall audit rows; structured tool-error envelopes |
| Configuration & Credentials | FR38–FR42 | Per-agent Zen config page; credential resolution ladder env-var → `Ens.Config.Credentials` → custom encrypted store; never persist keys in config rows |
| Chat Lifecycle | FR43–FR47 | Distinct keying per agent (`irisSessionId` vs registry GUID); daily sweep coupled to `Ens.MessageHeader.Purge()`; TTL sweep for search; `%OpenId(id, 4)` concurrency lock; "from search" context-pass on hand-off |
| Installation & Operator Surface | FR48–FR54 | Single ZPM module, single Resource, no transitive deps; install creates RBAC role and bookmark URLs; vendored Markdown bundle at `/csp/static/iris-session-agent/`; README operator-prerequisites is a structural deliverable |
| Developer Extensibility | FR55–FR59 | Pure dispatch contract `(toolName, jsonArgs) → jsonResult`; tool-call-roundtrip integration test gates each provider |

**Non-Functional Requirements** — 30 NFRs across 7 categories that will drive architectural decisions:

- **Performance** (NFR-P1–P6): 90s per-call LLM cap, search-query latency under 90s on 1M-row extents, ≤50-candidate body-inspection cap, concurrent-tab serialization, 5-min → 1-min commitment-grade time savings, prompt-cache hit-rate preservation.
- **Security** (NFR-S1–S6): three-layer read-only invariant, credential confinement (no API keys in config rows), credential resolution hygiene (no key material in audit rows), 100% audit completeness, public-OSS posture, tool dispatch purity (no `%session`/`%request`/Zen state coupling).
- **Reliability** (NFR-R1–R5): operator-deployment safety, chat-history lifecycle integrity under purge, search-history TTL, provider failure isolation, IPM idempotent reinstall.
- **Scalability** (NFR-SC1–SC4): production extents up to 10M rows, concurrent-operator scale via stock IRIS/CSP threading, no cross-instance coordination in v1, audit-log volume bounded by chat-history sweep cascade.
- **Compatibility & Portability** (NFR-C1–C6): IRIS 2024.1+ floor with every API verified, pure-ObjectScript runtime (no `[Language = python]`), Python-less install success, no transitive ZPM dependencies, no CDN dependency, evergreen browser support.
- **Operability & Maintainability** (NFR-O1–O5): operator self-service install in <30 minutes, hot config change without IRIS restart, audit-log review by SQL only (no separate audit UI), single-maintainer triage cadence, documentation deliverables on every release.
- **Accessibility** (NFR-A1): inherited from Mgmt Portal Zen — no independent WCAG commitment.

**Deliberate exclusions** (NFR §"Categories Deliberately Excluded"): localization/i18n, compliance certifications (SOC2/HIPAA/etc.), DR/backup commitments separate from IRIS journal, SLA.

### Scale & Complexity

- **Project complexity:** **Medium overall** with high technical concentration in pure-OS-runtime, version-floor compliance, three-layer read-only, four-provider abstraction, two-stage body search, vocabulary learning, lifecycle coupling, multi-tab serialization, and Web Gateway timeout coordination.
- **Primary technical domains:** ObjectScript backend (runtime, persistence, SQL); embedded JavaScript (vendored client-side rendering, Zen client-side hyperevent wiring); Zen pages (operator UI); HTTPS integration to four external LLM providers.
- **Estimated architectural components:** ~25–30 distinct classes across `SessionAgent.{Agent, LLM, LLM.Util, Tool, Tool.Inspection, Tool.Search, Chat, Config, Audit, Security, Util, Search, Task, UI, EnsPortal, EnsPortal.Util}.*` plus top-level `SessionAgent.Installer`, plus the vendored static-asset directory under `/csp/static/iris-session-agent/`.
- **Project context**: **greenfield** — no existing production code; v1 ships from scratch under MIT, distributed via Open Exchange and GitHub.

### Technical Constraints & Dependencies

**Binding platform constraints** (saved memory + PRD NFRs):

- **IRIS / IRIS for Health 2024.1+ floor.** Every API, class, and parameter must be verified available in 2024.1. Newer-version features (e.g., `%Library.IRISWallet` introduced in 2026.1, `%Library.Embedding` for vector search) are explicitly excluded from the v1 primary path.
- **Pure ObjectScript runtime.** No `[Language = python]` method exists in any shipped class under `SessionAgent.*`. Build-time tooling and test fixtures may use Python; the runtime artifact does not require embedded Python.
- **No AI Hub primitives.** `%AI.Agent`, `%AI.ToolSet`, `%AI.Tool`, `%AI.Agent.Session`, `%AI.Policy.Authorization`, `%AI.Shell.Console`, `%AI.MCP.Service` — all out of bounds. Replacements built directly on `%Net.HttpRequest` + `%DynamicObject` + `%Persistent` + `%Dictionary.*` + `%SQL.Statement`.
- **Single ZPM module** (`zpm install iris-session-agent`) with one `<Resource Name="SessionAgent.PKG"/>` and zero transitive Open Exchange dependencies.
- **All custom classes under `SessionAgent.*`** (single root package, including portal subclasses — no `Custom.EnsPortal.*`). RBAC role: `%SessionAgent_ReadOnly`.
- **HSCUSTOMCODE database** with operator-controlled package mapping to interop namespaces (HealthShare convention).
- **`$NAMESPACE` switching forbidden in CSP context** (per project rule applied to Zen pages and ZenMethod hyperevents). Each bookmark targets one namespace.
- **MCP serving deferred** to sibling `iris-execute-mcp-v2` project. Tool dispatch contract stays MCP-exportable: `(toolName, jsonArgs) → jsonResult` with no `%session`/`%request`/Zen state coupling, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals.

**External dependencies (runtime):**

- Outbound HTTPS to LLM providers via `%Net.HttpRequest` (operator-supplied API key; per-call timeout cap 90s).
- Vendored client-side rendering bundle (`marked` ≥ 18.0.2 + `Prism.js` curated language pack + `DOMPurify`) — self-hosted, no CDN.
- Operator prerequisites documented in README (Web Gateway "Server Response Timeout" 60s → 300s; RBAC grant; API key supply via env-var or `Ens.Config.Credentials`).

**Project-rule alignment** (from `.claude/rules/`):

- ObjectScript basics rules apply to `src/SessionAgent/` (no `_` in class/method/parameter names; `%EXACT()` on case-sensitive SQL; `$ZTimeStamp` for ISO-8601 UTC; `Security.Events.Create` pre-registration for audit; never `New $NAMESPACE` in REST handlers).
- ObjectScript testing rules apply to `src/SessionAgent/Test/` (`%UnitTest.TestCase` parent; `$$$AssertEquals`/`AssertTrue`/`AssertStatusOK` macros; ~500-line class size limit; proper `%OnNew(initvalue)` handling).
- Research-first rules apply to every story (Task 0 with live `curl`/probe + cited reference + dev-environment capability check + operator-observable state riding the commit).

### Cross-Cutting Concerns Identified

These will appear in multiple components and require consistent treatment across the architecture:

1. **Three-layer read-only enforcement** — code discipline (every tool), dispatch policy gate (`SessionAgent.Tool.Registry.Dispatch` consulting `MutatesState=0/1`), IRIS RBAC role (`%SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` via `SessionAgent.Security.ReadOnlyRole.Install()`).
2. **Audit logging interceptor** at `SessionAgent.Tool.Registry.Dispatch` — writes `SessionAgent.Audit.ToolCall` rows; the `SessionAgent.LLM.Provider.CallMessages` boundary writes `SessionAgent.Audit.LlmCall` rows; both FK-linked to `SessionAgent.Chat.History`. Search-agent dispatch enriches with `ResultSetSize`, `QueryTemplate`, `IndexUsed` columns.
3. **LLM Provider abstraction** — `SessionAgent.LLM.Provider` abstract + 4 concretes (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`, `OpenAICompatProvider`) + `SessionAgent.LLM.Util.{MessageAdapter, ToolDefAdapter, RetryWithBackoff}`. Canonical Anthropic shape; mechanical adapters down to OpenAI / Gemini / OpenAI-compat.
4. **Chat-history lifecycle coupling** — Inspection-agent rows coupled to `Ens.MessageHeader.Purge()` via `SessionAgent.Task.PurgeOrphanedChatHistory` (daily sweep, Topic 10 Option B from research). Search-agent rows TTL-swept (default 30d, configurable) via `SessionAgent.Task.PurgeStaleSearchChat`. Vocabulary rows decay-swept weekly via `SessionAgent.Task.UserVocabularyDecay`.
5. **Concurrent-tab serialization** — `%OpenId(id, 4)` exclusive row lock on `SessionAgent.Chat.History` at the top of every `AgentLoop.RunTurn`; UX surfaces `sa-concurrent-tab-banner` on the loser.
6. **Vendored static-asset distribution** — `/csp/static/iris-session-agent/` served by a dedicated unauthenticated `<CSPApplication>`; both portal subclasses load `marked.min.js`, `prism.min.js + curated language packs`, `dompurify.min.js`, `chat-panel.js`, and `chat-panel.css` from this path.
7. **Web Gateway timeout coordination** — operator README prerequisite (60s → 300s); per-call provider timeout cap at 90s; max-iterations-per-turn cap at ~10. Coordinated so timeouts surface as structured tool-error envelopes inside the gateway window.
8. **Pure-ObjectScript invariant** — release-gate constraint: zero `[Language = python]` methods anywhere under `src/SessionAgent/`; CI static check.
9. **MCP-export discipline** — every tool obeys the seven-anti-pattern checklist; the dispatch contract is `(toolName, jsonArgs) → jsonResult` with no `%session.Data`/`%request`/Zen state coupling.
10. **Vocabulary digest injection** (search agent only) — built per-turn via `SessionAgent.Search.VocabularyDigest.Build(portalUser)`, injected as the *first user message prefix* (uncached); never modifies the cached `system + tools` prefix to preserve Anthropic prompt-cache hit rate.

## Starter Template Evaluation

### Primary Technology Domain

**IRIS IPM (ZPM) module** — pure-ObjectScript class package distributed via `zpm install iris-session-agent`, targeting IRIS / IRIS for Health 2024.1+. Vendored client-side static assets served by a dedicated CSP application. No Docker shipped (operators run their own IRIS); no SPA / REST API surface (operator UI is custom subclasses of existing IRIS Mgmt Portal Zen pages); no embedded Python in runtime.

### Starter Options Considered

| Template | Verdict | Reason |
|---|---|---|
| **`intersystems-community/objectscript-package-template`** | Considered | Closest fit of generic options; ZPM-publishable, `/src/cls/` layout, Docker dev env. Ships sample `ClassExample.cls` + `PersistentClass.cls` + Docker scaffolding we'd delete. |
| **`intersystems-community/intersystems-iris-dev-template`** | Rejected | Broader dev-env focus than module-packaging focus. More scaffolding than we need. |
| **`intersystems-community/iris-embedded-python-template`** | Rejected | Anti-fit — explicit embedded-Python pattern conflicts with NFR-C2 (pure-ObjectScript runtime). |
| **`intersystems-community/iris-angular-template`** | Rejected | Wrong UX pattern — REST + SPA, not Zen page subclasses. |
| **Fork `sources/iris-session-chat/` (hackathon predecessor)** | Rejected as fork base; kept as reference | Predecessor is `ai-hub-dev-template` v2.0.9 with `<Invoke Method="Run" Class="Sample.MCPSetup"/>` — exactly the AI-Hub coupling we're explicitly removing. Predecessor's own CLAUDE.md says *"This repo is set up to host an IRIS or IRIS For Health container with the AI Hub SDK preview."* Risk of accidental inheritance is real. Predecessor remains a useful read-only reference for `<Invoke>` patterns and directory layout. |
| **Hand-author from the research doc's `module.xml`** | **Selected** | The complete `module.xml` is already designed in the inspection-agent research doc lines 957–993. Matches our exact constraints with zero scaffolding to remove. |

### Selected Starter: None — hand-author from research doc

**Rationale:**

The research doc has already designed our exact 33-line `module.xml` against our exact constraints (single `<Resource Name="SessionAgent.PKG"/>`, vendored `<FileCopy>` for static assets, dedicated unauthenticated `<CSPApplication>`, three `<Invoke>` install hooks for `SessionAgent.Installer.Install`, `SessionAgent.Audit.Emit.EnsureEvents`, `SessionAgent.Security.ReadOnlyRole.Install`). No transitive Open Exchange dependencies, no Python sample, no AI-Hub references, no Docker scaffolding (operators run their own IRIS) — exactly what NFR-C2 / NFR-C4 / NFR-C5 require.

Five reasons to author from zero rather than carve away from a template:

1. **The exact `module.xml` we want already exists** (research doc lines 957–993). Any starter either matches it (no value-add) or diverges (negative value — work to remove).
2. **NFR alignment is easier from zero than from carve-away.** "Do not add X" constraints (no transitive deps, no Python, no CDN) are easier to enforce when X was never present.
3. **Risk of accidental inheritance** — particularly from the hackathon predecessor's AI-Hub patterns — is real. Hand-authoring eliminates it.
4. **No "decisions made for us" we'd keep.** Standard starter value (TypeScript config, ESLint, Tailwind, test runner) doesn't apply to IRIS modules; the decisions that would matter are already made by the research doc.
5. **Reference shapes remain available.** `objectscript-package-template`'s `module.xml` and the predecessor's `module.xml` stay readable as comparison references during initial implementation; we just don't fork them.

### Initialization (Story 1.1 work)

There is no `iris init` CLI. The first implementation story creates by hand at the repo root:

- `module.xml` — 33-line shape from research doc lines 957–993
- `LICENSE` — MIT (per posture)
- `README.md` — operator-prerequisites-anchored, content from research doc §"Operator README Content"
- `.gitignore` — standard IRIS / VSCode / IDE patterns
- `src/SessionAgent/` — root package (sub-package layout finalized in Step 6 of this architecture)
- `src/static/` — vendored client-side bundle target for `<FileCopy>` deployment to `/csp/static/iris-session-agent/`

**Architectural decisions provided by this approach** (because they're already locked):

- **Language & Runtime:** ObjectScript only (NFR-C2). No Python, no JavaScript at the IRIS runtime layer (vendored JS is browser-side only).
- **Module shape:** Single ZPM module, single `<Resource>`, no transitive deps (NFR-C4).
- **Static-asset distribution:** Self-hosted under `/csp/static/iris-session-agent/`, no CDN (NFR-C5).
- **Build tooling:** None custom — IRIS's compiler does the work; tests use `%UnitTest.TestCase`; no transpile, bundle, or post-process step at install.
- **Code organization:** All classes under `SessionAgent.*` (single root package, per saved memory `project_package_naming.md`); HSCUSTOMCODE database with operator-controlled mapping to interop namespaces.
- **Development experience:** Standard IRIS dev workflow (Studio or VSCode-ObjectScript extension); no IDE scaffolding shipped by this project.

**Note:** Project initialization (`module.xml` + `LICENSE` + `README.md` + `.gitignore` + empty `src/SessionAgent/` skeleton) should be the first implementation story (Epic 1 Story 1.1 in the inspection-agent epic sequence).

### Reference Repos (read, don't fork)

- [`intersystems-community/objectscript-package-template`](https://github.com/intersystems-community/objectscript-package-template) — comparison reference for `module.xml` shape and IPM resource conventions.
- [`intersystems-community/intersystems-iris-dev-template`](https://github.com/intersystems-community/intersystems-iris-dev-template) — comparison reference for VSCode/Docker dev environment patterns (we don't ship Docker, but operators may want to set up local dev with these patterns).
- `sources/iris-session-chat/` (local) — comparison reference for predecessor's directory layout and `<Invoke>` patterns. **Do not copy AI-Hub-coupled classes** (`Sample.*`, `App.Installer.cls` MCP-setup logic).

## Core Architectural Decisions

### Decision Posture

The architecture for `iris-session-agent` is largely **pre-decided by upstream artifacts** — the PRD's 59 FRs + 30 NFRs, the two pure-ObjectScript research docs, the UX specification, and the project's saved memory facts together leave very little open at architecture-stage. This step's job is to (a) catalogue the locked decisions across the five canonical framework categories so they're inspectable in one place, and (b) surface the genuinely-open calibration decisions for explicit confirmation.

### Decision Priority Analysis

**Critical Decisions (block implementation) — all locked upstream:**

- Pure ObjectScript runtime (NFR-C2)
- IRIS 2024.1+ floor (NFR-C1) — `%Library.IRISWallet` out, AI Hub primitives out, `%Library.Embedding`-required features out
- Three-layer read-only enforcement (FR31, NFR-S1)
- Single ZPM module / single Resource (FR53, NFR-C4)
- All classes under `SessionAgent.*` (project rule)
- MCP-exportable tool dispatch contract (FR55–FR57)
- Anthropic-canonical wire shape with mechanical adapters (FR27, FR28)
- Chat-history lifecycle coupling: Topic-10 Option B (FR44, NFR-R2)
- Concurrent-tab serialization via `%OpenId(id, 4)` (FR46, NFR-P4)
- Web Gateway timeout coordination: 60→300s operator prereq + 90s per-call cap (NFR-P1, FR52)

**Important Decisions (shape the architecture, locked upstream):**

- Two-agent infrastructure sharing rubric (research §"Two-Agent Infrastructure Sharing")
- Bounded-WHERE invariant for search (FR19, NFR-P2)
- Two-stage indexed-prefilter + body-inspection for body-content search (FR18, NFR-P3)
- Vocabulary keyed `(PortalUser, MessageBodyClass, Alias)` with confidence smoothing (FR22)
- Vocabulary digest as first-user-message prefix (uncached) (FR24, NFR-P6)
- Audit interceptor at dispatch boundary, FK-linked rows (FR32–FR34, NFR-S4)
- Vendored client-side rendering bundle, no CDN (FR54, NFR-C5)
- Embed-in-Zen-page UX (no separate SPA) (UX spec, research)
- HSCUSTOMCODE distribution with operator-controlled package mapping (project memory)

**Calibration Decisions (architecture-stage):** OD1–OD10 — see below; recommended defaults accepted.

**Deferred Decisions (post-v1, per PRD §"Vision"):**

- MCP serving (delegated to sibling `iris-execute-mcp-v2`)
- Vector / semantic body-content search (would require `%Library.Embedding`)
- PHI redaction architecture (namespace segregation is v1 boundary)
- Cross-namespace single-conversation operation (`$NAMESPACE` switching forbidden in CSP)
- Streaming responses (SSE / async-poll)
- LLM-extracted alias generation from chat history
- Cross-user `NamespaceVocabulary` baseline population (schema ships in v1, population is v1.5)
- Stand-alone terminal REPL bot
- Body-content search via vector embeddings
- Custom-tool public-API stability (tools are subclassable in v1; public contract stability is post-v1, per FR58)

### Data Architecture

| Decision | Value | Source |
|---|---|---|
| Database engine | IRIS native (`%Persistent` + globals) | inherited |
| Chat persistence | `SessionAgent.Chat.History` `%Persistent`, keyed `(AgentName, SessionKey, PortalUser)`; `TurnsJson` as `%Stream.GlobalCharacter` holding canonical Anthropic-shape JSON | research §"Persistent Session State" |
| Audit persistence | `SessionAgent.Audit.LlmCall` (1 row/HTTP round-trip) + `SessionAgent.Audit.ToolCall` (1 row/dispatch); FK-linked to `Chat.History`. Search-agent dispatch enriches `ToolCall` with `ResultSetSize`, `QueryTemplate`, `IndexUsed` | research |
| Vocabulary persistence | `SessionAgent.Search.UserVocabulary` keyed `(PortalUser, Alias)` (Namespace-key deferred per research open-question 2); `NamespaceVocabulary` (schema ships v1, population v1.5); `SeedVocabulary` (~10 templates seeded by installer) | research §"Vocabulary-Learning Class Family" |
| Concurrency | `%OpenId(id, 4)` exclusive row lock per turn on `Chat.History` | FR46, research |
| Chat lifecycle (inspection) | Topic-10 Option B daily sweep (`SessionAgent.Task.PurgeOrphanedChatHistory`) removes rows whose Ens session was purged | FR44, research |
| Chat lifecycle (search) | TTL-based (default 30d, configurable via `Config.Agent.SearchChatRetentionDays`); `SessionAgent.Task.PurgeStaleSearchChat` daily sweep | FR45, NFR-R3 |
| Vocabulary decay | Weekly sweep (`SessionAgent.Task.UserVocabularyDecay`); deletes `Confidence < 0.2 AND LastUsed > 90d` | OD7, research |
| Caching | Anthropic prompt-caching of `system + tools` prefix; OpenAI auto-caches ≥1024 tokens; vocabulary digest in *uncached* first-user-message prefix | FR24, FR30, NFR-P6 |
| Validation | JSON Schema on every tool input (FR56); search args also pass regex whitelist + bounded-WHERE invariant (FR19); `%EXACT()` on case-sensitive SQL projections and predicates (project rule) | PRD, research |
| Migration approach | N/A in v1 (greenfield); first breaking version bump triggers a migration guide (per FR §"Migration Guide") | PRD |
| Default search time windows | 24h default / 720h (30d) max for filter tools (FR19); 168h (7d) default for `SearchByBodyField`; no time bound for `SearchBySession` and `SearchBySuperSession` (keyed lookups satisfy L3 by themselves) | OD8, research |

### Authentication & Security

| Decision | Value | Source |
|---|---|---|
| Operator authentication | Inherits CSP/Zen portal session (no new auth surface) | UX, research |
| Page authorization | Inherits parent's `%Ens_MessageTrace:USE` / `%Ens_MessageViewer:USE` resource gating | research |
| Tool authorization | Three-layer enforcement: L1 code discipline + L2 dispatch policy gate (`MutatesState=0/1`) + L3 IRIS RBAC role `%SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` | FR31, NFR-S1 |
| Search-arg safety | Three-layer: L1 parameterized prepare (`%SQL.Statement.%Prepare` + `%Execute(?)`) + L2 whitelist regex + L3 bounded-WHERE invariant | research §"Search-Arg-Construction Safety" |
| Credential storage | env-var (`$SYSTEM.Util.GetEnviron`) → `Ens.Config.Credentials` → custom AES-encrypted store; never in `Config.Agent` row | FR40, FR41, NFR-S2 |
| Encryption in transit | TLS via `%Net.HttpRequest.Https=1`; `SSLConfiguration = "DefaultSSL"` (operator-installed) | research |
| Audit completeness | 100% of LLM round-trips and tool dispatches logged; FK-linked to chat history | FR32–FR34, NFR-S4 |
| Native IRIS audit emit | Optional `$System.Security.Audit("SessionAgent","ToolCall",...)` for organizational compliance; events pre-registered via `SessionAgent.Audit.Emit.EnsureEvents()` per project rule | research |
| LLM-content sanitization | DOMPurify gate on the client side before `innerHTML` injection (FR54 dependency) | UX, research |
| `%Library.IRISWallet` | OUT — does not exist in 2024.1; introduced in 2026.1 | research §"Pre-flight Findings" |

### API & Communication Patterns

| Decision | Value | Source |
|---|---|---|
| Operator-facing dispatch | Single ZenMethod hyperevent `SendChatMessage(agentName, sessionKey, userText, contextHints) → resultJson` shared by both portal subclasses | UX, research |
| Search-only ZenMethods | `RecordClickThrough(searchSessionKey, sessionId, contributingToolCallsJson)` for vocabulary capture; `ResetSearchChat()` for explicit clear | research |
| Outbound to LLM | `%Net.HttpRequest` HTTP/1.1 over HTTPS; per-provider concrete classes; canonical Anthropic wire shape with adapters | FR25–FR28 |
| Tool dispatch contract | Pure `(toolName, jsonArgs) → jsonResult`; MCP-exportable; seven-anti-pattern checklist (no `%session`, no `%request`, no Zen state, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals, no streaming via `Write !`) | FR55–FR57 |
| Error envelopes | Structured `{isError: true, content: [{type:"text", text:"..."}]}` per MCP `tools/call` shape; operator-readable text; stack traces only in audit log | FR37, NFR-S6 |
| Per-call timeout cap | 90s per LLM call; surfaces structured timeout error inside Web Gateway 300s window | NFR-P1 |
| Max iterations per turn | **10** (`SessionAgent.Agent.AgentLoop` constant); hitting cap appends synthetic "max-iterations reached, summarize" + break | OD5, research |
| Retry policy | Full-jitter exponential backoff in `SessionAgent.Util.RetryWithBackoff`; 4 attempts, base 1s, cap 32s; non-retryable on 4xx (except 429); honor `Retry-After` (Anthropic/OpenAI) and `error.details[].retryDelay` (Gemini) | research |
| Rate-limit handling | Honor provider 429 + `Retry-After`; never silently retry mid-flight network failures (could double-charge, no idempotency key documented) | research |
| API documentation | Per-tool inline `///` doc comments; `Tool.Registry.ListTools()` returns `[{name, description, inputSchema}, ...]`; README operator-prereqs is structural deliverable | PRD §"Documentation Deliverables" |
| Inter-service communication | N/A in v1; cross-instance coordination is Vision-tier | NFR-SC3 |

### Frontend Architecture

| Decision | Value | Source |
|---|---|---|
| UI hosting | Embedded inside `EnsPortal.VisualTrace` and `EnsPortal.MessageViewer` Zen subclasses (no SPA, no separate URL) | UX, research |
| Design system | Inherit IRIS Mgmt Portal Zen / `EnsPortal.Application` stylesheet entirely; ~10 chat-specific `--sa-*` tokens added | UX §"Design System Foundation" |
| Component library | 11 `sa-*` components with native HTML semantics (`<a>`, `<button>`, `<details>`, `<textarea>`); per UX §"Component Strategy" | UX |
| State management | Vanilla JS + DOM; chat panel state in DOM, persistent state in `Chat.History` row (server) | UX, research |
| Routing | None (no SPA); search→inspection hand-off via URL params `?SESSIONID=...&FROM_SEARCH=...` | UX Journey 2, research |
| Citation deep-link | Parent's existing `selectItem` / `updateTabs` API (we subclass `EnsPortal.VisualTrace` directly); off-page items partial-sync in MVP | UX §"Component 4 — sa-citation-chip" |
| Markdown rendering | Vendored `marked` ≥ 18.0.2 + `Prism.js` curated languages (ObjectScript, JS, JSON, SQL, HL7, XML) + `DOMPurify`; ~45 KB gzipped, served from `/csp/static/iris-session-agent/` | FR54, NFR-C5 |
| Bundle optimization | Pre-minified vendored files; no build-time bundle step; one CSS file (`sessionagent-chat.css`) | UX |
| Browser support | Evergreen Chrome / Firefox / Safari / Edge (latest two versions); desktop-only; English-only | NFR-C6, NFR-A1 |
| Accessibility | Inherited from Mgmt Portal Zen; native HTML semantics + ARIA discipline (`aria-live`, `role="alert"`, `aria-disabled`); no independent WCAG conformance claimed | NFR-A1, UX §"Accessibility" |

### Infrastructure & Deployment

| Decision | Value | Source |
|---|---|---|
| Distribution | Single ZPM module `iris-session-agent`, `<Resource Name="SessionAgent.PKG"/>`, no transitive deps | FR53, NFR-C4 |
| Hosting | Operator runs their own IRIS instance; we don't host anything | brief, PRD |
| Package mapping | HSCUSTOMCODE database with operator-controlled mapping to interop namespaces (HealthShare convention); plain-IRIS Interop deployments document an alternative pattern in the README | OD2, project memory |
| Bookmark URL pattern | HealthShare: `/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`; Plain IRIS: `/csp/<NS>/SessionAgent.EnsPortal.{...}.zen`. Both documented in README; installer prints both | OD3 |
| Static-asset CSP application | Dedicated `<CSPApplication Url="/csp/static/iris-session-agent" Path="${cspdir}static/iris-session-agent" Resource="" Recurse="1" UseCookies="0" AuthenticationMethods="64"/>` (unauthenticated read for static assets) | research |
| Install hooks | Three `<Invoke>` blocks: `SessionAgent.Installer.Install`, `SessionAgent.Audit.Emit.EnsureEvents`, `SessionAgent.Security.ReadOnlyRole.Install`; idempotent | NFR-R5, research |
| Sweep tasks | `PurgeOrphanedChatHistory` (daily 02:00 UTC), `PurgeStaleSearchChat` (daily 03:00 UTC), `UserVocabularyDecay` (Sunday 04:00 UTC); UTC-anchored to match `$ZTimeStamp` ISO-8601 standard | research, OD7 |
| Observability | `SessionAgent.Audit.*` rows queryable via SQL; no separate audit/monitoring UI in v1 | NFR-O3 |
| Scaling | Single-namespace, single-IRIS scope; multi-tab via row lock; no cross-instance coordination in v1 | NFR-SC2, NFR-SC3 |
| CI/CD | **OD1**: lightweight GitHub Actions for v1 (markdown lint + structural checks; full `%UnitTest` on a Python-less 2024.1 community image once that image lands — gate per PRD §"Validation Approach"). Manual smoke-test per release tag is the v1 baseline. | OD1, PRD |
| Default LLM models seeded by installer | OpenAI: `gpt-4o`; Anthropic: `claude-sonnet-4-5`; Gemini: `gemini-2.5-pro`; Ollama-compat: `qwen2.5:32b`. **`Enabled=0` by default** — operator opts in via Zen UI and confirms model. README marks model defaults as "verify current model name before each release tag" (release-gate item, model names drift) | OD4, research |
| License & copyright | `LICENSE` at repo root, MIT text, `Copyright (c) 2026 Joshua Brandt`; lands in v1 release commit | OD9, brief §License |
| Repository | GitHub: `github.com/jbrandtmse/iris-session-agent`; Open Exchange listing created in v1 release commit | OD10, brief |

### Decision Impact Analysis

**Implementation sequence** — 10 consolidated epics for v1, organized by user-value-first (per [`epics.md`](epics.md)). Each epic delivers a meaningful operator outcome and stands alone; story order *within* each epic preserves the architect's original 18-step sub-sequence rationale (e.g., Epic 5 ships Anthropic first to validate the canonical-wire inversion early). The bidirectional mapping to the architect's original 18-step thinking lives in §"Epic-Sequence Evolution" below.

1. **Epic 1** — Project Foundation & Installable Package: IPM packaging + `Installer` skeleton + RBAC role + Audit-event registration + README operator-prereqs + `docs/operator-quickstart.md`. Unblocks every later story; operator can install and verify the foundation.
2. **Epic 2** — Inspection Agent Backend Plumbing: LLM Provider abstraction + `OpenAIProvider` + `RetryWithBackoff` + `EnvSecret` + `Tool.Base` + `Tool.Registry` + 3 example Inspection tools + `Agent.AgentLoop` + `Chat.History` + concurrency locking + audit interceptor + `docs/audit-sql-recipes.md`. Maintainer-validatable backend; `%UnitTest` smoke test exercises end-to-end against OpenAI.
3. **Epic 3** — Inspection Agent UI MVP Demo-able Milestone: shared chat-panel draw helper + client-side JS wrapper + ZenMethod hyperevent + `SessionAgent.EnsPortal.VisualTrace` subclass + citation-chip integration via parent's `selectItem`/`updateTabs` API. **MVP demo-able milestone (PRD §Product Scope MVP exit criterion).**
4. **Epic 4** — Inspection Agent Full Tool Catalogue: remaining 10 Inspection tools (event_log, rule_log, get_message_body's full 9-step body-class dispatch ladder, BP source/instance/methods, find_related_sessions, find_sessions_by_body, explain_error) + comprehensive read-only test suite.
5. **Epic 5** — Multi-Provider Support: `AnthropicProvider` (#2 — validates inversion via direct canonical-shape implementation, enables prompt-caching of `system + tools` prefix) → `GeminiProvider` (#3 — camelCase wire + `error.details[].retryDelay` parsing) → `OpenAICompatProvider` (#4 — Ollama / vLLM / any compatible endpoint) + `Test/ToolCallRoundtripIntegrationTest.cls` (provider × tool gate, FR59).
6. **Epic 6** — Per-Agent Configuration UI: `SessionAgent.UI.AgentConfig` Zen page + per-agent secret routing + hot config change validated.
7. **Epic 7** — Inspection Chat-History Lifecycle: `PurgeOrphanedChatHistory` daily 02:00 UTC sweep + Topic-10 Option B coupling to `Ens.MessageHeader.Purge()` + 1,000-session integration test.
8. **Epic 8** — Search Agent Foundation: `Search.UserVocabulary` + `SeedVocabulary` (~10 HL7 templates) + `NamespaceVocabulary` schema-only + Installer seed + 8-tool search catalog + `InspectBodyCandidates` two-stage body-content search + `VocabLookup` utility + `BoundedWhereInvariantTest`.
9. **Epic 9** — Search Agent Vocabulary Learning: click-through capture + `RecordSuccess` method + `VocabularyDigest.Build` + first-user-message prefix injection (preserves Anthropic prompt-cache hit rate per NFR-P6) + `SynthesizeAlias` determinism test + `%OnAfterSave` recursion-safe direct-SQL UPDATE pattern.
10. **Epic 10** — Search Agent UI Embed, Hand-off & TTL Sweep: `SessionAgent.EnsPortal.MessageViewer` subclass + chat tab + click-through hand-off → Inspection's "from search" stripe + concurrent-tab banner + `PurgeStaleSearchChat` TTL sweep (default 30d, configurable) + `UserVocabularyDecay` weekly Sunday sweep + vendored Markdown bundle (`marked` + `Prism.js` + `DOMPurify`) at `/csp/static/iris-session-agent/`. **Completes v1 scope.**

**Vision tier (post-v1, deferred):** `NamespaceVocabulary` cross-user baseline population (schema ships in Epic 8) + the rest of [PRD §"Vision (Future, post-v1)"](prd.md). Not in any v1 epic.

**Cross-component dependencies:**

- `Tool.Base` → `Tool.Registry` → `Agent.AgentLoop` → `EnsPortal.*` subclasses → `UI.AgentConfig` Zen page
- `LLM.Provider` abstract → 4 concretes → `Agent.AgentLoop`
- `Chat.History` → `Audit.{LlmCall, ToolCall}` (FK) → `Task.Purge*` (sweep)
- `Search.UserVocabulary` → `Search.VocabularyDigest.Build` → `Agent.AgentLoop` (first-turn injection)
- `Installer` → `Audit.Emit.EnsureEvents` (audit pre-registration) → `Security.ReadOnlyRole.Install` (RBAC) → `Task.*` (sweep schedules) → `Config.Agent` seed rows
- `EnsPortal.VisualTrace` (Inspection host) ← URL-param hand-off ← `EnsPortal.MessageViewer` (Search host)

**Calibration constants documented as `Class Parameter`** (so pilot tuning is cheap):

- `SessionAgent.Agent.AgentLoop`: `MaxIterationsPerTurn = 10`, `PerCallProviderTimeoutSec = 90`
- `SessionAgent.Util.RetryWithBackoff`: `MaxAttempts = 4`, `BaseDelaySec = 1`, `MaxDelaySec = 32`
- `SessionAgent.Search.VocabularyDigest`: `MaxEntries = 20`, `MinUserConfidence = 0.3`
- `SessionAgent.Search.UserVocabulary`: `DecayConfidenceThreshold = 0.2`, `DecayLastUsedDays = 90`
- `SessionAgent.Tool.Search.*` (each): `DefaultTimeWindowHours = 24`, `MaxTimeWindowHours = 720` (= 30d), `BodyFieldDefaultHours = 168` (= 7d) where applicable

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

The patterns below consolidate consistency rules from four upstream sources (`.claude/rules/iris-objectscript-basics.md`, `.claude/rules/object-script-testing.md`, `.claude/rules/research-first.md`, the two pure-ObjectScript research docs) so an implementing AI agent can find them in one place. Where a rule originates upstream, the source is cited; where the architecture document is the original locking point, that's marked.

**Conflict points addressed:** ~30 areas where two different AI agents working in this codebase could otherwise make incompatible choices.

### Naming Patterns

#### ObjectScript class, method, property, and variable naming (project rule)

| Element | Convention | Example | Source |
|---|---|---|---|
| Package root | `SessionAgent.*` (single root, no `Custom.*` or `App.*`) | `SessionAgent.Agent.AgentLoop` | project memory `project_package_naming.md` |
| Sub-package names | PascalCase, no underscores | `LLM`, `Tool.Inspection`, `EnsPortal.Util` | research class hierarchy |
| Class names | PascalCase, no underscores; no `%`/`_` characters | `AgentLoop`, `OpenAIProvider`, `GetSessionSummary` | iris-objectscript-basics.md §Basics |
| Method names | camelCase, no underscores; no `_`; never `_` | `RunTurn`, `CallMessages`, `EnsureEvents`. Test methods: `TestSomething`, never `TestSession_45_Init` | iris-objectscript-basics.md §Basics |
| Class Parameter names | No underscores; ALLCAPS or camelCase (`MaxAttempts` or `MAXATTEMPTS`) | `MaxIterationsPerTurn`, `EndpointDefault`, `RoleName` | iris-objectscript-basics.md §Basics |
| Class properties | Capitalized, no prefix | `AgentName`, `SessionKey`, `TurnsJson` | iris-objectscript-basics.md §Naming |
| Method parameters | `p` prefix | `pCallerCtx`, `pJsonArgs`, `pSessionId` | iris-objectscript-basics.md §Naming |
| Local variables | `t` prefix | `tStmt`, `tRs`, `tSC`, `tEndpoint` | iris-objectscript-basics.md §Naming |
| Property accessor on parameter | `..#PARAMETERNAME` | `..#MaxAttempts`, `..#RoleName` | iris-objectscript-basics.md §Naming |

#### Tool naming (MCP-export convention)

| Element | Convention | Example | Source |
|---|---|---|---|
| Tool name (`ToolName` parameter value) | snake_case verb-noun, ≤64 chars, alphanumeric + `_`/`-`, starts with letter | `session_summary`, `search_by_status`, `get_message_body`, `inspect_body_candidates` | research §"MCP — Future-Export Constraints" |
| Tool class name | PascalCase mirror of tool name | `SessionAgent.Tool.Inspection.SessionSummary`, `SessionAgent.Tool.Search.SearchByStatus` | research |
| Tool sub-package | Inspection: `SessionAgent.Tool.Inspection.*`; Search: `SessionAgent.Tool.Search.*` | — | research |

#### Audit event source/type/name triples

All audit events MUST be pre-registered in `%SYS` via `Security.Events.Create()` before first emit (per project rule §"Security.Events Pre-Registration for Audit"). The triple convention:

| Source | Type | Name | Emitter |
|---|---|---|---|
| `SessionAgent` | `LlmCall` | `<provider>` (e.g., `openai`, `anthropic`, `gemini`) | `SessionAgent.LLM.Provider.CallMessages` boundary |
| `SessionAgent` | `ToolCall` | `<tool_name>` (e.g., `session_summary`) | `SessionAgent.Tool.Registry.Dispatch` |
| `SessionAgent` | `VocabWrite` | `clickthrough\|explicit\|extracted\|seed` | `SessionAgent.Search.UserVocabulary.RecordSuccess` |
| `SessionAgent` | `TaskRun` | `<task_name>` (e.g., `PurgeOrphanedChatHistory`) | each `SessionAgent.Task.*.OnTask` |

The `SessionAgent.Audit.Emit.EnsureEvents()` method is invoked at install time (`<Invoke>` in `module.xml`) and registers all four event types idempotently.

#### CSS class and token naming (UX-locked)

| Element | Convention | Example | Source |
|---|---|---|---|
| Component class prefix | `sa-` | `sa-chat-panel`, `sa-message-block`, `sa-tool-call-card`, `sa-citation-chip` | UX §"Token Naming Convention" |
| CSS custom property prefix | `--sa-` | `--sa-message-operator-bg`, `--sa-tool-card-border`, `--sa-status-text-color` | UX §"Token Naming Convention" |
| Stylesheet location | `/csp/static/iris-session-agent/sessionagent-chat.css` (Growth tier) | — | UX §"Implementation Approach" |
| State modifier classes | `sa-msg-operator`, `sa-msg-agent`, `sa-msg-error`, `sa-msg-search-result`, `sa-cite-rule`, `sa-cite-event`, `sa-cite-message`, `sa-cite-ack`, `sa-cite-iolog`, `sa-cite-tool` | — | UX §"Component Strategy" |

#### JSON property naming inside tool args, results, and audit rows

| Context | Convention | Reason |
|---|---|---|
| Tool input properties (in `GetInputSchema()` and `pJsonArgs`) | `snake_case` | Matches LLM/MCP convention (`session_id`, `time_window_hours`, `status_in`); LLM tool-call generation works best when schema mirrors the convention the model has trained on |
| Tool result `structuredContent` keys | `snake_case` | Mirrors input convention; LLM consumption is symmetric |
| `%Persistent` property names (IRIS internal) | `PascalCase` | IRIS convention; SQL projection preserves case via `%EXACT()` |
| `%DynamicObject` keys exchanged with provider HTTP APIs | Whatever the provider's wire format requires (Anthropic: snake_case; OpenAI: snake_case; Gemini: camelCase) | Adapter responsibility; never leaks into tool-side code |

#### SQL global naming (auto-generated by IRIS storage)

IRIS storage generates global names from class names: `SessionAgent.Subpkg.ClassName` → `^SessionAgent.Subpkg.ClassNameD` (data) and `^SessionAgent.Subpkg.ClassNameI` (indices). **Do not edit Storage sections** in any class — the compiler maintains them (project rule §"Storage Sections").

### Structure Patterns

#### Sub-package layout (locked by research)

(Concrete tree finalized in Step 6 of this architecture; sub-package roots:)

`SessionAgent.{Agent, LLM, LLM.Util, Tool, Tool.Inspection, Tool.Search, Chat, Config, Audit, Search, Security, Util, Task, UI, EnsPortal, EnsPortal.Util, Test}` plus top-level `SessionAgent.Installer`.

#### Test class structure (project rule)

- All test classes extend `%UnitTest.TestCase` and live under `src/SessionAgent/Test/`.
- Test class size cap: **~500 lines**; split into multiple classes when exceeded (object-script-testing.md §"Test Class Size").
- `%OnNew(initvalue)` MUST accept the `initvalue` parameter and call `##super(initvalue)` (object-script-testing.md §"Critical Constructor"). MUST NOT have `Private` keyword.
- Assertions use macros (`$$$AssertEquals`, `$$$AssertTrue`, `$$$AssertStatusOK`), NEVER methods (`..AssertX()` is wrong).
- Forbidden macros: `$$$AssertFalse` (use `$$$AssertTrue('cond,...)`), `$$$AssertCondition`.

#### Vendored static-asset layout

```
src/static/
├── marked.min.js                       (≥18.0.2, CVE-fixed; see PRD NFR-C5)
├── prism.min.js                        (core)
├── prism-objectscript.js               (custom grammar; falls back to 'markup')
├── prism-sql.js
├── prism-javascript.js
├── prism-json.js
├── prism-hl7.js                        (custom grammar)
├── prism-xml.js
├── prism.min.css                       (low-contrast theme matching parent palette)
├── dompurify.min.js                    (3.x)
├── chat-panel.js                       (~50-line wrapper: marked → Prism → DOMPurify)
└── sessionagent-chat.css               (Growth-tier; MVP can inline)
```

The `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>` element in `module.xml` deploys this directory at install time.

### Format Patterns

#### MCP tool-result envelope (success)

```objectscript
Set pResult = {
  "content": [{"type": "text", "text": "Human-readable summary"}],
  "structuredContent": {
    "key1": "value1",
    "key2": 42
  }
}
```

- `content` is an array of typed blocks; v1 uses `text` only. (`image` and `resource` types are MCP-allowed but not used by us.)
- `structuredContent` is the typed JSON the LLM consumes for downstream reasoning. Provide both `content.text` and `structuredContent` — older models that don't honor `structuredContent` get the text summary.

#### MCP tool-error envelope

```objectscript
Set pResult = {
  "isError": (1),
  "content": [{"type": "text", "text": "Operator-readable error reason"}]
}
```

- `isError: true` is the MCP error signal — NEVER throw an ObjectScript exception from `Tool.Invoke`.
- Error text is operator-readable ("missing session_id", "argument failed validation", "Tool blocked by read-only policy") — never raw `<UNDEFINED>`/`<PROTECT>` stack traces. Stack traces are written to `SessionAgent.Audit.ToolCall.ErrorText` only.

#### ISO-8601 UTC timestamp construction (project rule)

```objectscript
Set tIso = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
```

- Always `$ZTimeStamp` (UTC), never `$Horolog` (local time) when appending `"Z"` (project rule §"Timestamp and Encoding Standards").
- All `Audit.LlmCall.Timestamp`, `Audit.ToolCall.Timestamp`, `Chat.History.CreatedAt`/`UpdatedAt` use this format.

#### `%DynamicObject` null emission (project rule)

```objectscript
Do dynObj.%Set("key", "", "null")        ; emits JSON null
Do dynObj.%Set("key", "null", "null")    ; emits JSON STRING "null" — WRONG
```

The third parameter is the type hint, not the value. Project rule §"While writing ObjectScript".

#### `%Status` return convention (project rule)

```objectscript
Method DoSomething() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tSC = ##class(...).Foo()
        Quit:$$$ISERR(tSC)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
}
```

- First line `Set tSC = $$$OK`. Last line `Quit tSC`.
- Every method that doesn't have a return value returns `%Status`.
- Triple-dollar macros (`$$$OK`, `$$$ISERR`, `$$$ISOK`, `$$$ERROR`), never double-dollar (project rule).

#### Argumentless `Quit` inside Try/Catch (project rule)

QUIT-with-arguments is **not allowed** inside Try/Catch blocks (ObjectScript ERROR #1043). Pattern (project rule §"QUIT Statement Restrictions"):

```objectscript
Method GetThing() As Thing
{
    Set tResult = $$$NULLOREF
    Try {
        Set tResult = ##class(Thing).%New()
        Quit
    }
    Catch ex {
        Set tResult = $$$NULLOREF
        Quit
    }
    Quit tResult
}
```

#### SQL case-sensitivity (project rule)

Wrap every string equality predicate AND every string projection with `%EXACT()` to preserve case:

```sql
SELECT %EXACT(SessionId), %EXACT(SourceConfigName)
FROM Ens.MessageHeader
WHERE %EXACT(Status) IN ('Error', 'Suspended')
  AND %EXACT(SourceConfigName) = 'EpicADT'
```

### Communication Patterns

#### Tool input JSON Schema subset (locked, MCP-portable)

Use only these JSON Schema keywords inside `GetInputSchema()` for cross-vendor portability:

- Top level: `{type: "object", properties: {...}, required: [...], additionalProperties: false}`
- Property level: `{type, description, enum?, items?, minimum?, maximum?, minItems?, maxItems?}`
- `type` values: `"object"`, `"array"`, `"string"`, `"integer"`, `"number"`, `"boolean"`

**Never use:** `$ref`, `oneOf`, `anyOf`, `allOf`, `pattern`, exotic format keywords. Pattern PD1 selected: hand-author the schema literal in each tool, no fluent builder.

#### Caller context propagation

Every tool's `Invoke()` receives a `pCallerCtx As SessionAgent.Agent.CallerContext` argument with:

- `agentName` — `"session-inspection"` or `"message-search"`
- `irisSessionId` (Inspection only) — Ens session id; empty for Search
- `searchSessionKey` (Search only) — registry-issued GUID; empty for Inspection
- `portalUser` — the operator's portal username (resolved from `%session.Username` AT THE DISPATCH BOUNDARY, never inside a tool)
- `namespace` — the IRIS namespace (NEVER touched by tool code — pass-through only)

**Anti-pattern:** A tool reading `%session.Username`, `%request.UserAgent`, `$NAMESPACE`, or any CSP/Zen state directly.

#### ZenMethod hyperevent return shape

All ZenMethod hyperevents return a `%String` containing JSON. Client-side `chat-panel.js` parses with `JSON.parse()` and dispatches by shape.

```objectscript
Method SendChatMessage(pAgentName, pSessionKey, pUserText, pContextHints) As %String [ ZenMethod ]
{
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn(...)
    Quit tResult.%ToJSON()
}
```

#### Tool dispatch contract — seven anti-patterns

A tool implementation MUST NOT:

1. Read `%session.Data` or `%request.CgiEnvs` from inside `Invoke()`.
2. Assume the caller is a logged-in CSP/portal user.
3. Return HTML, redirects, or use `%CSP.Response.Write()`.
4. Mutate ZenPage fields or rely on Zen page state.
5. Use ObjectScript exceptions to signal tool errors (return structured `{isError:true, content:[...]}` instead).
6. Hardcode namespace via `$NAMESPACE` lookups (namespace is in `pCallerCtx.namespace`).
7. Stream output via `Write !,...` to the device.

### Process Patterns

#### Try/Catch convention (project rule + research)

Every method that calls IRIS APIs that can fail wraps in Try/Catch. Catch-block converts to `%Status`. Outer caller checks with `$$$ISERR(tSC)`.

#### Tool error surfacing (NEVER throw)

Inside `Tool.Invoke()`, errors return structured envelopes — exceptions bubble up only to `Tool.Registry.Dispatch`'s outer Catch, which converts them to `{isError:true, content:[{type:"text", text: ex.DisplayString()}]}`. Tools should pre-surface their own validation errors before reaching the safety-net catch.

#### Concurrency lock acquisition / release

```objectscript
Set tHist = ##class(SessionAgent.Chat.History).%OpenId(tId, 4)
; ... mutate, %Save (releases lock)
```

The `%OpenId(id, 4)` exclusive lock is acquired at the top of every `AgentLoop.RunTurn` and released on the row's `%Save`. Two concurrent tabs serialize.

#### Transaction side-effects (project rule)

NEVER spawn background jobs (`JOB`), signal events (`$System.Event.Signal`), or perform external I/O inside `TSTART`/`TCOMMIT`. Save data needed for side effect in a local var inside the transaction; execute side effect AFTER `TCOMMIT`.

#### `%OnAfterSave` recursion avoidance (research + project rule)

When a `%OnAfterSave` trigger updates a derived field (e.g., `Confidence` recomputed from `Success`/`Failure` counts), use direct SQL UPDATE — NEVER call `%Save()` from within `%OnAfterSave`:

```objectscript
Method %OnAfterSave() As %Status
{
    Set tDenom = ..SuccessCount + ..FailureCount + 1
    Set ..Confidence = ..SuccessCount / tDenom
    &sql(UPDATE SessionAgent_Search.UserVocabulary
         SET Confidence = :..Confidence
         WHERE %ID = :..%Id())
    Quit $$$OK
}
```

(Task-0 probe carried forward: verify `%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1.)

#### Namespace switching (project rule)

**FORBIDDEN in CSP context** (Zen pages, ZenMethod hyperevents). Outside CSP context (`Installer.Install()` running under IPM), use the explicit save/restore pattern. NEVER `New $NAMESPACE`.

#### Audit event pre-registration (project rule)

`$System.Security.Audit("Source","Type","Name",...)` silently returns 0 if Source/Type/Name not pre-registered via `Security.Events.Create()` in `%SYS`. The `SessionAgent.Audit.Emit.EnsureEvents()` method is invoked at install time and registers all four event types idempotently.

#### HTTP retry-after parsing (research)

Parse `retry-after` as integer first, fall back to RFC 7231 HTTP-date, fall back to exponential backoff. For Gemini, use `error.details[].retryDelay` JSON field instead (regex `(\d+)s` → seconds).

#### LLM tool-call idempotency (research)

NEVER retry on mid-flight network failures (request sent, response lost). Only retry on responses we received with retryable status codes (429, 5xx). Surface mid-flight failures with `request-id` from response header.

#### Concurrent tool errors don't halt the agent (research)

If a single tool's `Invoke()` fails, the failed tool returns its `{isError:true, ...}` envelope and the agent loop continues with the remaining tools' results.

### Pattern Decisions Locked at Architecture-Stage

| ID | Decision | Choice | Rationale |
|---|---|---|---|
| **PD1** | Tool input JSON Schema authoring | **Hand-author the schema literal** in each tool's `GetInputSchema()`; no fluent builder | Schema literals are short, self-documenting, grep-able. Builder is v1.5 ergonomics question. |
| **PD2** | Search-tool SQL construction | **Inline construction** in each search tool's `Invoke()`; the 8 canonical query templates documented in this doc as a *checklist*, not a class | Inline keeps SQL grep-able alongside parameter binding; central catalog adds indirection without value. L1 search-arg-safety enforced in each tool. |
| **PD3** | Audit row write timing | **Synchronous inline writes** in `LogToolCall` / `LogLlmCall`; no per-turn buffer | Per-row save cost minimal; failure to write should surface immediately (NFR-S4 100% completeness gate); buffering doesn't help steady-state volume bounded by sweep cascade. |

### Enforcement Guidelines

**All AI Agents MUST:**

1. **Scope every change to `SessionAgent.*`.** Never introduce `Custom.*`, `App.*`, or `EnsCustom.*` packages. Single-root rule.
2. **Use macros for assertions** in `%UnitTest.TestCase` subclasses (`$$$AssertEquals`, `$$$AssertTrue`, `$$$AssertStatusOK`). Never `..AssertX()`.
3. **Wrap string SQL predicates and projections with `%EXACT()`.** Case-folding is a silent correctness bug.
4. **Use `$ZTimeStamp` (UTC)** for any timestamp string ending in `"Z"`. Never `$Horolog`.
5. **Pre-register audit event triples** before emitting via `$System.Security.Audit`.
6. **Pass caller context explicitly** through `pCallerCtx`. Never read `%session.Data`/`%request`/`$NAMESPACE` from inside a tool.
7. **Return structured tool errors**, never throw exceptions from `Invoke()`.
8. **Acquire `%OpenId(id, 4)` lock** before mutating `Chat.History` rows.
9. **Restore `$NAMESPACE` on first line of catch blocks** when temporarily switching to `%SYS`. Never `New $NAMESPACE`.
10. **Never `[Language = python]`** in any shipped class under `src/SessionAgent/`. Build-time/test fixtures may use Python; the runtime artifact may not.
11. **Never edit Storage sections** of `%Persistent` classes. Compiler maintains them.
12. **Read `irislib/<class>.cls` source** before using any IRIS system class for the first time in a story.
13. **Run Task-0 probes** for every Epic 8+ story (Search Agent surface forward) whose AC references a backend surface — and for every story carrying one of the six pre-flight probes enumerated in §"Implementation Handoff → Carry-forward Task-0 probes" regardless of epic number.

**Pattern enforcement mechanism:**

- **Code review** — reviewers reject PRs that violate the patterns above. Cite the specific item.
- **CI lint** (Story 1.x scope) — static checks for forbidden patterns: `[Language = python]` grep against `src/SessionAgent/`; `New $NAMESPACE` grep against `src/SessionAgent/EnsPortal/` and `src/SessionAgent/UI/`; `..Assert` (without `$$$`) grep against `src/SessionAgent/Test/`.
- **Test gate** — `tool-call-roundtrip` integration test (FR59) runs every bundled tool against every bundled provider; the dispatch contract is exercised on every release.
- **Pattern updates** — material additions or revisions to these patterns land as PRs to this `architecture.md` document. The PR description names the specific NFR or operator-observed pattern that motivated the update.

### Pattern Examples

#### Good — canonical tool implementation skeleton

```objectscript
Class SessionAgent.Tool.Inspection.SessionSummary Extends SessionAgent.Tool.Base
{
    Parameter ToolName = "session_summary";
    Parameter Description = "Return shape, duration, error count, and root message class for an Ens session.";
    Parameter MutatesState = 0;

    ClassMethod GetInputSchema() As %DynamicObject
    {
        Quit {
            "type": "object",
            "properties": {
                "session_id": {"type": "string", "description": "Ens session id"}
            },
            "required": ["session_id"],
            "additionalProperties": false
        }
    }

    ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext,
                       pJsonArgs As %DynamicObject,
                       Output pResult As %DynamicObject) As %Status
    {
        Set tSC = $$$OK
        Set pResult = {"content": [{"type":"text","text":""}], "structuredContent":{}}
        Try {
            Set tSessionId = pJsonArgs.%Get("session_id")
            If tSessionId = "" {
                Set pResult = {"isError": (1),
                               "content": [{"type":"text","text":"missing session_id"}]}
                Quit
            }
            Set tStmt = ##class(%SQL.Statement).%New()
            Set tSC = tStmt.%Prepare(
                "SELECT COUNT(*) AS msg_count, "_
                "       SUM(CASE WHEN IsError=1 THEN 1 ELSE 0 END) AS err_count "_
                "FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ?")
            Quit:$$$ISERR(tSC)
            Set tRs = tStmt.%Execute(tSessionId)
            If tRs.%Next() {
                Do pResult.structuredContent.%Set("message_count", tRs.%Get("msg_count"))
                Do pResult.structuredContent.%Set("error_count", tRs.%Get("err_count"))
            }
            Set pResult.content.%Get(0).text = "Session "_tSessionId_": "_
                pResult.structuredContent.message_count_" messages, "_
                pResult.structuredContent.error_count_" errors."
        }
        Catch ex {
            Set pResult = {"isError": (1),
                           "content": [{"type":"text","text":(ex.DisplayString())}]}
        }
        Quit tSC
    }
}
```

Hits every pattern: `t`/`p`-prefix variables, `%Status` convention, Try/Catch with argumentless Quit inside, `%EXACT()` on `SessionId`, parameterized `%Execute`, MCP envelope shapes (success + error), no `%session`/`%request`/Zen state, never throws.

#### Anti-patterns

```objectscript
; WRONG — tool reads CSP session directly. Breaks MCP export. Breaks future cross-tab/multi-namespace.
Set tUser = %session.Username                     ; ANTI-PATTERN
Set tNS = $NAMESPACE                              ; ANTI-PATTERN

; WRONG — exception kills the agent loop turn.
$$$ThrowOnError($$$ERROR($$$GeneralError, "missing session_id"))   ; ANTI-PATTERN

; WRONG — infinite recursion when %Save() is called inside %OnAfterSave.
Method %OnAfterSave() As %Status {
    Set ..Confidence = ..SuccessCount / (..SuccessCount + ..FailureCount + 1)
    Do ..%Save()                                  ; ANTI-PATTERN — re-fires
}

; WRONG — $Horolog is local time; "Z" suffix says UTC. Semantically incorrect on non-UTC servers.
Set tIso = $Translate($ZDateTime($Horolog, 3, 1), " ", "T") _ "Z"  ; ANTI-PATTERN
```

## Project Structure & Boundaries

### Complete Project Directory Structure

```
iris-session-agent/
├── README.md                              # operator-prereq-anchored (FR52); MVP renderable from research §"Operator README Content"
├── LICENSE                                # MIT, "Copyright (c) 2026 Joshua Brandt" (OD9)
├── .gitignore                             # IRIS, VSCode, IDE patterns
├── module.xml                             # 33-line ZPM manifest (FR48, FR53; from research §"IPM module.xml — Concrete v1 Shape")
├── .github/
│   └── workflows/
│       └── ci.yml                         # OD1: lightweight markdown lint + structural checks; full %UnitTest gate added once Python-less 2024.1 image lands
├── _bmad-output/                          # planning artifacts (NOT shipped via ZPM; not in <Resource>)
│   └── planning-artifacts/
│       ├── product-brief-iris-session-agent.md
│       ├── product-brief-iris-session-agent-distillate.md
│       ├── prd.md
│       ├── ux-design-specification.md
│       ├── architecture.md                # this document
│       └── research/
│           ├── technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md
│           ├── technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md
│           ├── technical-ensemble-session-inspection-agent-research-2026-04-24.md           # historical, partially superseded
│           ├── technical-ensemble-session-agent-ui-integration-research-2026-04-24.md       # historical, partially superseded
│           └── cleanup-edit-proposal-2026-05-02.md
├── docs/
│   ├── initial-prompt.md                  # author's authoritative scope spec (existing)
│   ├── operator-quickstart.md             # Aishah Journey 3 walkthrough; complements README (UX Journey 3)
│   └── audit-sql-recipes.md               # sample SQL queries against SessionAgent.Audit.* (UX §"Audit log access")
└── src/                                   # ZPM <SourcesRoot>
    ├── SessionAgent/                      # root package — single ZPM <Resource Name="SessionAgent.PKG"/>
    │   ├── Installer.cls                  # Install: tasks, RBAC, audit events, seed configs, seed vocab
    │   ├── Agent/                         # orchestration layer
    │   │   ├── AgentLoop.cls              # RunTurn — per-turn state machine; locks Chat.History row
    │   │   ├── CallerContext.cls          # DTO {agentName, irisSessionId, searchSessionKey, portalUser, namespace}
    │   │   ├── ProviderResponse.cls       # DTO {content[], stopReason, usage}
    │   │   └── TurnResult.cls             # DTO {assistantMarkdown, usageRollup, durationMs, toolCallsRendered[]}
    │   ├── LLM/                           # provider abstraction + 4 concretes
    │   │   ├── Provider.cls               # [Abstract] CallMessages contract; canonical Anthropic shape
    │   │   ├── OpenAIProvider.cls         # concrete #1, ships first per OD4
    │   │   ├── AnthropicProvider.cls      # concrete #2 — validates abstraction by implementing canonical shape directly
    │   │   ├── GeminiProvider.cls         # concrete #3 — generateContent endpoint, x-goog-api-key auth
    │   │   ├── OpenAICompatProvider.cls   # concrete #4 — Ollama, vLLM, any OpenAI-compat endpoint
    │   │   └── Util/
    │   │       ├── MessageAdapter.cls     # canonical ↔ provider-specific message history
    │   │       ├── ToolDefAdapter.cls     # canonical ↔ provider-specific tool definitions
    │   │       └── GeminiRetryParser.cls  # parse error.details[].retryDelay (Gemini doesn't emit Retry-After header)
    │   ├── Tool/                          # tool registry + base
    │   │   ├── Base.cls                   # [Abstract] ToolName, Description, MutatesState, GetInputSchema, Invoke
    │   │   ├── Registry.cls               # ListTools (reflection via %Dictionary.ClassDefinition); Dispatch (L2 + L4)
    │   │   ├── Inspection/                # 13 tools — all SessionAgent.Tool.Base subclasses, MutatesState=0
    │   │   │   ├── SessionSummary.cls            # tool: session_summary
    │   │   │   ├── SessionTimeline.cls           # tool: session_timeline
    │   │   │   ├── MessageHeaders.cls            # tool: message_headers
    │   │   │   ├── EventLog.cls                  # tool: event_log
    │   │   │   ├── RuleLog.cls                   # tool: rule_log
    │   │   │   ├── FindRelatedSessions.cls       # tool: find_related_sessions
    │   │   │   ├── FindSessionsByBody.cls        # tool: find_sessions_by_body
    │   │   │   ├── GetMessageBody.cls            # tool: get_message_body (9-step body dispatch ladder)
    │   │   │   ├── GetMessageDetail.cls          # tool: get_message_detail
    │   │   │   ├── GetBusinessProcessSource.cls  # tool: get_business_process_source
    │   │   │   ├── GetBusinessProcessInstance.cls # tool: get_business_process_instance
    │   │   │   ├── ListBusinessProcessMethods.cls # tool: list_business_process_methods
    │   │   │   └── ExplainError.cls              # tool: explain_error
    │   │   └── Search/                    # 8 indexed-access + 1 body-inspection + 1 utility
    │   │       ├── SearchByTime.cls               # tool: search_by_time            (lead: TimeCreated)
    │   │       ├── SearchByStatus.cls             # tool: search_by_status          (lead: Status, bitmap)
    │   │       ├── SearchBySource.cls             # tool: search_by_source          (lead: SourceConfigName, bitmap)
    │   │       ├── SearchByTarget.cls             # tool: search_by_target          (lead: TargetConfigName, bitmap)
    │   │       ├── SearchByMessageClass.cls       # tool: search_by_message_class   (lead: MessageBodyClassName, bitmap)
    │   │       ├── SearchBySession.cls            # tool: search_by_session         (lead: SessionId)
    │   │       ├── SearchByBodyField.cls          # tool: search_by_body_field      (SearchTable join on MessageBodyId)
    │   │       ├── SearchBySuperSession.cls       # tool: search_by_supersession    (Ens.SuperSessionIndex join)
    │   │       ├── InspectBodyCandidates.cls      # tool: inspect_body_candidates   (two-stage body-content search; ≤50 candidates)
    │   │       └── VocabLookup.cls                # tool: vocab_lookup              (utility — long-tail vocab retrieval)
    │   ├── Chat/                          # chat-history persistence
    │   │   ├── History.cls                # %Persistent — keyed (AgentName, SessionKey, PortalUser); TurnsJson stream
    │   │   └── Turn.cls                   # serializable shape of one turn (role, content[], usage); included in TurnsJson
    │   ├── Config/                        # per-agent runtime config
    │   │   ├── Agent.cls                  # %Persistent — Provider, Model, MaxTokens, Temperature, SystemPromptOverride, ReadOnly, CredentialName, EnvVarName, EndpointUrl, Enabled, SearchChatRetentionDays
    │   │   └── AgentDefaults.cls          # ClassMethod GetSystemPrompt(agentName), GetSeedConfig(agentName)
    │   ├── Audit/                         # audit ledger
    │   │   ├── LlmCall.cls                # %Persistent — 1 row per provider HTTP round-trip; FK to Chat.History
    │   │   ├── ToolCall.cls               # %Persistent — 1 row per tool dispatch; FK to Chat.History; search-agent enriched cols
    │   │   └── Emit.cls                   # Security.Events.Create + audit emit helper; EnsureEvents() called by installer
    │   ├── Search/                        # search-agent extras
    │   │   ├── UserVocabulary.cls         # %Persistent — keyed (PortalUser, Alias); RecordSuccess/RecordFailure/SynthesizeAlias/DecaySweep
    │   │   ├── NamespaceVocabulary.cls    # %Persistent — schema only in v1; population logic v1.5
    │   │   ├── SeedVocabulary.cls         # %Persistent — ship-with templates (~10); seeded by installer
    │   │   └── VocabularyDigest.cls       # ClassMethod Build(portalUser) — top-N digest for first-user-message prefix
    │   ├── Security/
    │   │   └── ReadOnlyRole.cls           # Layer-3 RBAC installer for %SessionAgent_ReadOnly; idempotent
    │   ├── Util/                          # cross-cutting helpers
    │   │   ├── EnvSecret.cls              # env-var → Ens.Config.Credentials → AES-encrypted custom store
    │   │   ├── Json.cls                   # %DynamicObject helpers (null-emit, deep-merge, redact)
    │   │   ├── Markdown.cls               # server-side hooks if needed (mostly client-side)
    │   │   └── RetryWithBackoff.cls       # full-jitter exponential backoff; honor Retry-After
    │   ├── Task/                          # sweep tasks (installed by Installer)
    │   │   ├── PurgeOrphanedChatHistory.cls   # daily 02:00 UTC; Topic-10 Option B inspection sweep
    │   │   ├── PurgeStaleSearchChat.cls       # daily 03:00 UTC; TTL 30d default search sweep
    │   │   └── UserVocabularyDecay.cls         # weekly Sunday 04:00 UTC; Confidence < 0.2 AND LastUsed > 90d
    │   ├── UI/                            # Zen pages
    │   │   ├── AgentConfig.cls            # Zen page — per-agent config form (%ZEN.Component.page subclass)
    │   │   └── ChatPanel.cls              # shared CSS/JS contributors used by both EnsPortal subclasses
    │   ├── EnsPortal/                     # portal subclasses
    │   │   ├── VisualTrace.cls            # Inspection Agent host — subclass of EnsPortal.VisualTrace; adds chat tab
    │   │   ├── MessageViewer.cls          # Search Agent host — subclass of EnsPortal.MessageViewer; adds chat tab
    │   │   └── Util/
    │   │       └── ChatPanelDrawHelper.cls # shared OnDrawContent("DrawChatPanel") for both subclasses
    │   └── Test/                          # %UnitTest.TestCase subclasses; ≤500 lines each per project rule
    │       ├── AgentLoopTest.cls                  # orchestration loop branching, max-iter cap, lock acquire/release
    │       ├── LlmProviderTest.cls                # provider abstraction; if exceeds 500 lines, split per-provider
    │       ├── MessageAdapterTest.cls             # canonical ↔ OpenAI/Gemini message translation correctness
    │       ├── ToolDefAdapterTest.cls             # canonical ↔ provider-specific tool def translation
    │       ├── ToolBaseTest.cls                   # base contract + parameter inheritance
    │       ├── ToolRegistryTest.cls               # ListTools + Dispatch + L2 read-only enforcement
    │       ├── InspectionToolTest.cls             # 13 tool unit tests (group; split if exceeds 500 lines)
    │       ├── SearchToolTest.cls                 # 8 search tool unit tests + InspectBodyCandidates + VocabLookup
    │       ├── BoundedWhereInvariantTest.cls      # L3 invariant — every search tool's WHERE leads with indexed col + time window
    │       ├── ChatHistoryTest.cls                # %OpenId(id, 4) concurrency + lifecycle + key-shape per agent
    │       ├── AuditTest.cls                      # 100% LlmCall + ToolCall completeness; FK linkage; ResultSetSize/QueryTemplate enrichment
    │       ├── ReadOnlyRoleTest.cls               # Layer-3 RBAC enforcement: attempt INSERT/DELETE → privilege failure
    │       ├── SearchVocabularyTest.cls           # RecordSuccess, SynthesizeAlias determinism, Confidence formula
    │       ├── VocabularyDigestTest.cls           # Build cascade (user → namespace → seed); token-count budget
    │       ├── PurgeTaskTest.cls                  # all three sweep tasks: orphaned, stale, decay
    │       ├── RetryWithBackoffTest.cls           # IsRetryable matrix; ExpBackoff distribution
    │       ├── EnvSecretTest.cls                  # resolution ladder; never-log-key-material
    │       ├── JsonTest.cls                       # null emit, redact, deep-merge
    │       ├── ToolCallRoundtripIntegrationTest.cls   # FR59 — every provider × every tool against canned mock
    │       └── HandoffIntegrationTest.cls         # search→inspection URL-param hand-off; "from search" stripe
    └── static/                            # vendored client-side bundle — <FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>
        ├── marked.min.js                  # ≥ 18.0.2 (CVE-2026-41680 fixed); ~12 KB gzipped
        ├── prism.min.js                   # core
        ├── prism-objectscript.js          # custom grammar; falls back to 'markup'
        ├── prism-sql.js
        ├── prism-javascript.js
        ├── prism-json.js
        ├── prism-hl7.js                   # custom grammar
        ├── prism-xml.js
        ├── prism.min.css                  # low-contrast theme matching parent palette
        ├── dompurify.min.js               # 3.x; XSS gate before innerHTML injection
        ├── chat-panel.js                  # ~50-line wrapper: marked → Prism → DOMPurify pipeline
        └── sessionagent-chat.css          # Growth-tier; MVP can inline the few sa-* token rules
```

**Total ship-source artifact:** ~50 ObjectScript classes + 12 vendored client-side files + `module.xml` + `LICENSE` + `README.md`. The `_bmad-output/` and `docs/` directories are committed to the repo for traceability but not included in the ZPM `<Resource>`.

### Architectural Boundaries

#### The Trust / Transport Boundary (the central architectural seam)

```
┌─────────────────────────────────────────────────────────────────┐
│  ABOVE THE BOUNDARY — CSP/Zen-coupled side                      │
│                                                                 │
│  SessionAgent.EnsPortal.VisualTrace      (Zen page subclass)    │
│  SessionAgent.EnsPortal.MessageViewer    (Zen page subclass)    │
│  SessionAgent.EnsPortal.Util.ChatPanelDrawHelper                │
│  SessionAgent.UI.AgentConfig             (Zen page subclass)    │
│  SessionAgent.UI.ChatPanel               (CSS/JS contributors)  │
│  /csp/static/iris-session-agent/*        (vendored bundle)      │
│                                                                 │
│  These touch: %session, %request, Zen state, %CSP.Response,     │
│  XData, ZenMethod hyperevents, browser DOM, parent class APIs.  │
│                                                                 │
│  ZenMethod hyperevent SendChatMessage(agentName, sessionKey,    │
│                       userText, contextHints) → resultJson      │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  BELOW THE BOUNDARY — MCP-portable side                         │
│                                                                 │
│  SessionAgent.Agent.AgentLoop.RunTurn(...)                      │
│      │                                                          │
│      ├─→ SessionAgent.Tool.Registry.Dispatch(toolName, ctx,...) │
│      │       │                                                  │
│      │       └─→ SessionAgent.Tool.{Inspection,Search}.*.Invoke │
│      │                                                          │
│      ├─→ SessionAgent.LLM.Provider.CallMessages(history,        │
│      │                                          tools, system)  │
│      │       (one of 4 concretes; all canonical Anthropic shape)│
│      │                                                          │
│      ├─→ SessionAgent.Chat.History.LoadOrCreate (lock acquire)  │
│      │                                                          │
│      └─→ SessionAgent.Audit.{LlmCall,ToolCall}.WriteRow         │
│                                                                 │
│  These NEVER touch %session, %request, Zen state, %CSP.Response,│
│  $NAMESPACE side effects, or stream output via Write !,...       │
│  Caller context arrives via SessionAgent.Agent.CallerContext.   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The boundary is **the `RunTurn` entry point**. Everything above can be replaced by a future MCP transport (sibling `iris-execute-mcp-v2` project) without rewriting anything below. This is the load-bearing architectural commitment that makes FR55–FR57 (MCP-exportable dispatch contract) achievable.

#### Sub-package boundaries (what each owns; what depends on what)

| Sub-package | Owns | Depends on | Depended on by |
|---|---|---|---|
| `Agent.*` | Per-turn orchestration loop; DTOs for caller context, provider response, turn result | `LLM.*`, `Tool.*`, `Chat.*`, `Audit.*`, `Search.VocabularyDigest` (search agent only) | `EnsPortal.*` (via ZenMethod) |
| `LLM.*` | Provider abstraction + 4 concretes; HTTP wire format adaptation; retry/backoff | `Util.RetryWithBackoff`, `Util.EnvSecret`, `Util.Json`, `Config.Agent` (for credential ref + endpoint URL) | `Agent.AgentLoop`, `Audit.LlmCall` |
| `Tool.Base` + `Tool.Registry` | Tool dispatch contract; reflection-based tool enumeration; L2 policy gate; audit interceptor | `Config.Agent` (for ReadOnly flag), `Audit.ToolCall` | `Agent.AgentLoop`; `Tool.Inspection.*`, `Tool.Search.*` (subclass) |
| `Tool.Inspection.*` | 13 tools over Ens.* surfaces (SQL + method dispatch) | `Tool.Base`, IRIS Ens.* schema | `Tool.Registry` (registers via reflection) |
| `Tool.Search.*` | 8 indexed-access tools + InspectBodyCandidates + VocabLookup | `Tool.Base`, `Tool.Inspection.GetMessageBody` (body dispatch ladder reuse), `Search.UserVocabulary` (VocabLookup), IRIS Ens.MessageHeader + SearchTable | `Tool.Registry` |
| `Chat.*` | Chat-history persistence; row locking; turn array serialization | `Config.Agent` (for retention + provider/model pin) | `Agent.AgentLoop`, `Task.PurgeOrphanedChatHistory`, `Task.PurgeStaleSearchChat`, `Audit.*` (FK target) |
| `Config.*` | Per-agent runtime config; system-prompt defaults; credential references | (none — pure %Persistent) | `Agent.AgentLoop`, `LLM.Provider`, `UI.AgentConfig` |
| `Audit.*` | Audit ledger persistence; native IRIS audit emit helper | `Chat.History` (FK), `%SYS Security.Events` (pre-registration) | `Tool.Registry` (interceptor), `LLM.Provider` (boundary), `Search.UserVocabulary` (vocab writes), `Task.*` (task-run events) |
| `Search.*` | Per-user vocabulary; namespace baseline (v1.5); seed templates; digest assembly | `Audit.Emit` (vocab-write events), `Config.Agent` (digest tuning) | `Agent.AgentLoop` (first-turn injection), `Tool.Search.VocabLookup`, `Task.UserVocabularyDecay` |
| `Security.ReadOnlyRole` | Layer-3 RBAC role install (`%SessionAgent_ReadOnly`); SELECT grants on `Ens.*` | %SYS `Security.Roles`, `%SYSTEM.SQL.Security` | `Installer.Install` |
| `Util.*` | Cross-cutting helpers — secret resolution, JSON helpers, retry policy | (none cross-package) | `LLM.*`, `Tool.*`, `Audit.*`, `Search.*`, `Task.*` |
| `Task.*` | Three sweep tasks: orphaned chat (inspection), stale chat (search), vocabulary decay | `Chat.History`, `Search.UserVocabulary`, `Audit.Emit` (TaskRun events), `Ens.MessageHeader` (read-only) | `Installer.Install` (schedule installation) |
| `UI.AgentConfig` | Zen-page operator configuration form | `Config.Agent`, `Ens.Config.Credentials` (dropdown population) | (operator browser) |
| `UI.ChatPanel` | Shared CSS/JS contributor methods used by `ChatPanelDrawHelper` | `/csp/static/iris-session-agent/*` (deployed bundle) | `EnsPortal.Util.ChatPanelDrawHelper` |
| `EnsPortal.VisualTrace` | Inspection Agent host page; subclass of `EnsPortal.VisualTrace`; chat tab; `selectItem`/`updateTabs` deep-link target | `EnsPortal.Util.ChatPanelDrawHelper`, `Agent.AgentLoop`, parent `EnsPortal.VisualTrace` API | (operator browser) |
| `EnsPortal.MessageViewer` | Search Agent host page; subclass; chat tab; click-through hand-off navigator | `EnsPortal.Util.ChatPanelDrawHelper`, `Agent.AgentLoop`, parent `EnsPortal.MessageViewer` API, `Search.UserVocabulary.RecordSuccess` | (operator browser) |
| `EnsPortal.Util.ChatPanelDrawHelper` | Shared `OnDrawContent` for both portal subclasses; emits chat panel HTML + script tags | (none) | `EnsPortal.VisualTrace`, `EnsPortal.MessageViewer` |
| `Installer` | IPM `<Invoke>` target; idempotent install of tasks, RBAC role, audit events, seed configs, seed vocab; operator-prereqs reminder log | `Audit.Emit.EnsureEvents`, `Security.ReadOnlyRole.Install`, `Config.Agent` (seed), `Search.SeedVocabulary` (seed), `Task.*` (schedule) | (ZPM install hook) |

#### Data boundaries

- **`SessionAgent.Chat.History`** — one row per `(AgentName, SessionKey, PortalUser)`. Inspection rows keyed by Ens session id; Search rows keyed by registry GUID. Lifecycle distinct per agent (Topic-10 Option B vs TTL).
- **`SessionAgent.Config.Agent`** — exactly two rows in v1: `AgentName='session-inspection'` and `AgentName='message-search'`. Operator edits via Zen UI.
- **`SessionAgent.Audit.{LlmCall, ToolCall}`** — append-only; FK to `Chat.History`. Volume bounded by chat-history sweep cascade (NFR-SC4).
- **`SessionAgent.Search.UserVocabulary`** — one row per `(PortalUser, Alias)`. Confidence formula recomputed via `%OnAfterSave` direct-SQL UPDATE (avoiding recursion).
- **`SessionAgent.Search.SeedVocabulary`** — ~10 rows seeded by installer; operator-editable via SQL or future Zen UI.
- **`SessionAgent.Search.NamespaceVocabulary`** — schema ships v1, population is v1.5.
- **`Ens.MessageHeader`, `Ens.Util.Log`, `Ens.Rule.Log`, `Ens.SuperSessionIndex`, body classes, `Ens.SearchTableBase` extents** — read-only access only (Layer 3 RBAC). Tools never modify.

### Requirements to Structure Mapping

#### Functional Requirements → Files

| FR area | FR → owning files |
|---|---|
| **Session Inspection** (FR1–FR12) | FR1: `EnsPortal/VisualTrace.cls`, `EnsPortal/Util/ChatPanelDrawHelper.cls`. FR2: `Agent/AgentLoop.cls`. FR3: `Tool/Inspection/{MessageHeaders,SessionSummary,SessionTimeline}.cls`. FR4: `Tool/Inspection/GetMessageBody.cls` (9-step dispatch ladder). FR5: `Tool/Inspection/EventLog.cls`. FR6: `Tool/Inspection/RuleLog.cls`. FR7: `Tool/Inspection/{GetBusinessProcessSource,GetBusinessProcessInstance,ListBusinessProcessMethods}.cls`. FR8: `Tool/Inspection/FindRelatedSessions.cls` (Ens.SuperSessionIndex). FR9: `Tool/Inspection/FindSessionsByBody.cls` (SearchTable pivot). FR10: `Tool/Inspection/ExplainError.cls`. FR11: `EnsPortal/VisualTrace.cls` (`onCitationClick` → parent's `selectItem`/`updateTabs`); `static/chat-panel.js`. FR12: `Chat/History.cls` (keyed `(AgentName, SessionKey, PortalUser)`). |
| **Message Search** (FR13–FR24) | FR13: `EnsPortal/MessageViewer.cls`. FR14: `Agent/AgentLoop.cls`. FR15: `Tool/Search/{SearchByTime,SearchByStatus,SearchBySource,SearchByTarget,SearchByMessageClass,SearchBySession}.cls`. FR16: `Tool/Search/SearchByBodyField.cls`. FR17: `Tool/Search/SearchBySuperSession.cls`. FR18: `Tool/Search/InspectBodyCandidates.cls` (delegates to `Tool/Inspection/GetMessageBody.cls`). FR19: `Tool/Search/Base.cls` constructor + each tool's WHERE; tested in `Test/BoundedWhereInvariantTest.cls`. FR20: `EnsPortal/MessageViewer.cls` (`RecordClickThrough`); `EnsPortal/VisualTrace.cls` (FROM_SEARCH read + stripe). FR21: `Tool/Search/VocabLookup.cls` + `Search/UserVocabulary.cls` (`CreatedVia=explicit`). FR22: `Search/UserVocabulary.cls` + silent capture in `EnsPortal/MessageViewer.cls`. FR23: `Search/SeedVocabulary.cls` (~10 rows seeded by installer). FR24: `Search/VocabularyDigest.cls` + `Agent/AgentLoop.cls` (first-turn injection). |
| **LLM Provider Framework** (FR25–FR30) | FR25: `LLM/{OpenAIProvider,AnthropicProvider,GeminiProvider,OpenAICompatProvider}.cls`. FR26: `Config/Agent.cls` + `UI/AgentConfig.cls`. FR27: `LLM/Provider.cls` + `LLM/Util/{MessageAdapter,ToolDefAdapter}.cls`. FR28: pattern doc + `LLM/Provider.cls` doc comment. FR29: `Agent/AgentLoop.cls` Parameter `PerCallProviderTimeoutSec = 90`; enforced in each provider's `CallMessages`. FR30: `LLM/AnthropicProvider.cls` (cache_control); `LLM/Util/MessageAdapter.cls` (cache stability). |
| **Read-Only Enforcement & Audit** (FR31–FR37) | FR31: L1 = code review checklist; L2 = `Tool/Registry.cls` Dispatch; L3 = `Security/ReadOnlyRole.cls`. FR32: `Audit/LlmCall.cls` at `LLM/Provider.CallMessages` boundary. FR33: `Audit/ToolCall.cls` in `Tool/Registry.cls` Dispatch. FR34: FK columns on both `Audit.*` classes. FR35: `docs/audit-sql-recipes.md`. FR36: `Tool/Registry.cls` Dispatch (`MutatesState` check). FR37: `Tool/Registry.cls` outer Catch + pattern doc. |
| **Configuration & Credentials** (FR38–FR42) | FR38: `UI/AgentConfig.cls`. FR39: `Config/Agent.cls` (rows keyed by `AgentName`). FR40: `Util/EnvSecret.cls` (called from `LLM/Provider.GetApiKey`). FR41: `Config/Agent.cls` schema (`EnvVarName` + `CredentialName` only, no `ApiKey`). FR42: `Config/Agent.cls` properties. |
| **Chat Lifecycle** (FR43–FR47) | FR43: `Chat/History.cls` schema. FR44: `Task/PurgeOrphanedChatHistory.cls`. FR45: `Task/PurgeStaleSearchChat.cls`. FR46: `Chat/History.LoadOrCreate` + `Test/ChatHistoryTest.cls`. FR47: `EnsPortal/VisualTrace.cls` (FROM_SEARCH read + `sa-from-search-stripe`). |
| **Installation & Operator Surface** (FR48–FR54) | FR48: `module.xml`. FR49: NFR-C2 + NFR-C3 (CI lint). FR50: `Security/ReadOnlyRole.cls` `Install()`. FR51: `Installer.cls` `PrintOperatorReminders()`. FR52: `README.md`. FR53: `module.xml` (single `<Resource>`). FR54: `src/static/*` + `module.xml` `<FileCopy>` + `<CSPApplication>`. |
| **Developer Extensibility** (FR55–FR59) | FR55: `Tool/{Base,Registry}.cls`. FR56: `Tool/Base.cls` Abstract. FR57: `Tool/Registry.ListTools()`. FR58: `Tool/Base.cls` Abstract; v1 ships built-in tools only. FR59: `Test/ToolCallRoundtripIntegrationTest.cls`. |

#### Non-Functional Requirements → Owning Artifacts

| NFR | Owning artifact / pattern |
|---|---|
| **NFR-P1** 90s per-call cap | `Agent/AgentLoop.cls` Parameter `PerCallProviderTimeoutSec = 90` |
| **NFR-P2** search query bound (1M-row extent) | `Tool/Search/Base.cls` invariant + scale test in `Test/BoundedWhereInvariantTest.cls` |
| **NFR-P3** ≤50 candidate body inspection | `Tool/Search/InspectBodyCandidates.cls` Class Parameter cap |
| **NFR-P4** concurrent-tab serialization | `Chat/History.cls` `%OpenId(id, 4)` |
| **NFR-P5** time-to-resolution | operator self-report (not CI-measurable) |
| **NFR-P6** prompt-cache hit-rate | `LLM/AnthropicProvider.cls` cache_control discipline; `Search/VocabularyDigest.cls` → uncached prefix |
| **NFR-S1** read-only invariant | three layers — code (each `Tool/*.cls`) + dispatch (`Tool/Registry.cls`) + RBAC (`Security/ReadOnlyRole.cls`) |
| **NFR-S2** credential confinement | `Config/Agent.cls` schema (no ApiKey property) |
| **NFR-S3** credential resolution hygiene | `Util/EnvSecret.cls` + `Test/EnvSecretTest.cls` |
| **NFR-S4** audit completeness | synchronous inline write; `Test/AuditTest.cls` validates 100% |
| **NFR-S5** public-OSS posture | release-gate manual review |
| **NFR-S6** dispatch purity | seven-anti-pattern checklist (code review); `Test/ToolBaseTest.cls` |
| **NFR-R1** operator-deployment safety | structurally enforced via NFR-S1 |
| **NFR-R2** chat-history lifecycle integrity | `Task/PurgeOrphanedChatHistory.cls` + `Test/PurgeTaskTest.cls` (1000-row simulation) |
| **NFR-R3** search-history TTL | `Task/PurgeStaleSearchChat.cls` + `Config/Agent.SearchChatRetentionDays` |
| **NFR-R4** provider failure isolation | `LLM/Util/RetryWithBackoff.cls` + each provider's error mapping |
| **NFR-R5** IPM idempotent reinstall | `Installer.cls` (idempotent); `Security/ReadOnlyRole.Install`; `Audit/Emit.EnsureEvents` |
| **NFR-SC1** 10M-row extent | `Tool/Search/Base.cls` invariant (carries from NFR-P2) |
| **NFR-SC2** concurrent operators | inherited IRIS/CSP threading |
| **NFR-SC3** no cross-instance | each bookmark targets one namespace |
| **NFR-SC4** audit-log volume | sweep cascade via `Task/Purge*.cls` |
| **NFR-C1** IRIS 2024.1+ floor | release-gate smoke test; Task-0 probes |
| **NFR-C2** pure ObjectScript runtime | CI grep against `[Language = python]` |
| **NFR-C3** Python-less install | release-gate CI on Python-less 2024.1 image |
| **NFR-C4** no transitive deps | `module.xml` review |
| **NFR-C5** no CDN | `src/static/*` vendored; CI grep against `https://cdn.*` |
| **NFR-C6** evergreen browsers | manual smoke test per release |
| **NFR-O1** operator self-service install | Aishah Journey 3 walkthrough validates |
| **NFR-O2** hot config change | `Agent/AgentLoop.cls` reads `Config.Agent` at top of every `RunTurn` |
| **NFR-O3** audit log via SQL | `docs/audit-sql-recipes.md` |
| **NFR-O4** single-maintainer triage | brief / posture |
| **NFR-O5** documentation deliverables | release-gate manual review |
| **NFR-A1** inherited Mgmt Portal accessibility | UX components use native HTML semantics |

### Integration Points

#### Internal Communication

- **Browser → Server** (operator action): JS `chat-panel.js` calls Zen client-side proxy `zenPage.SendChatMessage(agentName)` → ZenMethod hyperevent over synchronous AJAX POST.
- **Server → Browser** (response): ZenMethod returns `%String` containing JSON; `chat-panel.js` parses and renders message blocks + tool-call cards + citation chips.
- **Server → External LLM provider**: `SessionAgent.LLM.<Concrete>Provider.CallMessages` issues HTTPS POST via `%Net.HttpRequest`; canonical Anthropic-shape internally translated by adapters.
- **Internal IRIS → IRIS**: tools read `Ens.*` extents via `%SQL.Statement` (read-only via Layer-3 RBAC).
- **Audit fan-out** (interceptor): `Tool.Registry.Dispatch` writes `Audit.ToolCall` synchronously; `LLM.Provider.CallMessages` writes `Audit.LlmCall` synchronously. Both FK-linked to `Chat.History`.
- **Vocabulary capture** (search only): JS click event → `EnsPortal/MessageViewer.RecordClickThrough` ZenMethod → `Search/UserVocabulary.RecordSuccess`.
- **Hand-off** (search → inspection): browser navigates to `/csp/.../SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>&FROM_SEARCH=<key>`; inspection page reads URL params and renders `sa-from-search-stripe`.

#### External Integrations

- **Anthropic Messages API** — `https://api.anthropic.com/v1/messages`; `x-api-key`, `anthropic-version: 2023-06-01`. Prompt-caching via `cache_control` markers.
- **OpenAI Chat Completions API** — `https://api.openai.com/v1/chat/completions`; `Authorization: Bearer`. Auto-caching ≥1024 tokens.
- **Google Gemini generateContent API** — `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`; `x-goog-api-key`.
- **Ollama / vLLM / OpenAI-compat** — operator-specified endpoint (`Config.Agent.EndpointUrl`); OpenAI Chat Completions wire format.
- **Operator's Web Gateway** — README documents raising "Server Response Timeout" 60s → 300s.
- **Operator's IRIS instance** — installer creates `%SessionAgent_ReadOnly` role and grants SELECT on `Ens.*`.

#### Data Flow — Operator Asks "What Happened?"

```
[1] Operator types question, presses Enter.
[2] Browser: chat-panel.js → zenPage.SendChatMessage('session-inspection').
[3] ZenMethod: SessionAgent.EnsPortal.VisualTrace.SendChatMessage(...).
[4] Calls SessionAgent.Agent.AgentLoop.RunTurn(...) — crosses trust boundary.
[5] AgentLoop:
    a. Build CallerContext from %session/%request (resolved AT BOUNDARY).
    b. Chat.History.LoadOrCreate(...) — acquire %OpenId(id, 4) lock.
    c. Read Config.Agent row (provider, model, system prompt).
    d. Append user message to history.turns.
    e. LOOP (≤ MaxIterationsPerTurn=10):
       i.   Provider.CallMessages(history, tools, system, cacheConfig).
       ii.  Adapter translates if needed; %Net.HttpRequest POST.
       iii. RetryWithBackoff handles 429/5xx (full-jitter exp backoff).
       iv.  Audit.LlmCall row written.
       v.   Read response.content[]: dispatch each tool_use block →
            Tool.Registry.Dispatch (L2 gate; Invoke; Audit.ToolCall written).
       vi.  Append tool results to history.turns.
       vii. Continue unless stopReason ∈ {end_turn, max_tokens, stop_sequence}.
    f. %Save history (releases lock).
    g. Build TurnResult.
[6] ZenMethod returns TurnResult.%ToJSON() to browser.
[7] Browser: chat-panel.js parses + renders (marked → Prism → DOMPurify).
[8] Operator clicks citation chip → onCitationClick → parent's selectItem/updateTabs.
```

### File Organization Patterns

- **Configuration files at repo root**: `module.xml`, `LICENSE`, `README.md`, `.gitignore`, `.github/workflows/ci.yml`. No `package.json`/`tsconfig.json` — this is an IRIS module.
- **Source organization** under `src/SessionAgent/`: by *responsibility* (Agent, LLM, Tool, Chat, Config, Audit, Search, Security, Util, Task, UI, EnsPortal), not by *type*.
- **Test organization** at `src/SessionAgent/Test/`: one test class per production class (or per behavior cluster); ≤500 lines each.
- **Asset organization** at `src/static/`: vendored client-side bundle deployed to `/csp/static/iris-session-agent/` via `<FileCopy>`.
- **Planning artifacts** at `_bmad-output/planning-artifacts/`: committed for traceability; NOT shipped via ZPM.
- **Operator docs** at `docs/`: `initial-prompt.md`, `operator-quickstart.md`, `audit-sql-recipes.md`.

### Development Workflow Integration

- **Development**: standard IRIS workflow. Author classes in Studio or VSCode-ObjectScript extension; compile via Studio/extension. Run tests via `%UnitTest.Manager`. No build step; no transpile; no bundle.
- **Static asset development**: vendored libs are pre-minified upstream; `chat-panel.js` and `sessionagent-chat.css` are hand-authored.
- **Local install for testing**: `zpm load /path/to/iris-session-agent` compiles + runs install hooks.
- **Build process**: none beyond IRIS compilation. ZPM deployment via `zpm install iris-session-agent` from registry, OR `zpm load <path>` for local dev.
- **Deployment topology**: operator runs their own IRIS; module installed in HSCUSTOM with package mapping to interop namespaces. No cloud deployment, no CI/CD-to-production pipeline shipped.

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:**

All architecturally-binding constraints reinforce each other; no contradictions found:

- Pure-OS runtime (NFR-C2) ↔ no AI Hub primitives ↔ IRIS 2024.1+ floor (NFR-C1) — Topic 8 preflight verified `%Library.IRISWallet` is out; secrets ladder env-var → `Ens.Config.Credentials` → AES.
- Three-layer read-only (FR31, NFR-S1) ↔ MCP-export discipline (FR55, NFR-S6) — both require no `%session`/`%request`/Zen state in tools; mutually reinforcing.
- Anthropic-canonical wire shape (FR27) ↔ OpenAI-first ship priority (OD4) — OpenAI exercised hardest from day one; inversion validated immediately.
- Topic-10 Option B sweep (FR44, NFR-R2) ↔ no chat clutter in Visual Trace; ~24h orphan window acknowledged as acceptable.
- Web Gateway 300s prereq (FR52) ↔ 90s per-call cap (NFR-P1) ↔ max-iter 10 (OD5) — ordered timeout cascade.
- Vocabulary digest in *uncached* first-user-message prefix (FR24) ↔ Anthropic prompt-cache hit-rate (NFR-P6) — designed to preserve cached `system + tools` prefix.
- MCP serving deferred to sibling `iris-execute-mcp-v2` ↔ tool registry stays MCP-exportable (FR57) — registry contract structurally compatible without serving the protocol.

**Pattern Consistency:**

- Naming patterns consistent across all sub-packages.
- `snake_case` JSON in tool args/results matches MCP and LLM-vendor expectations.
- `sa-` CSS prefix consistent across all 11 UX components.
- Audit event triple convention consistent across all emitters.
- MCP envelope shape consistent across all tools.
- Try/Catch + `%Status` + argumentless-Quit-inside-Try pattern consistent across all code examples.

**Structure Alignment:**

- Sub-package layout supports the trust boundary — `EnsPortal.*` and `UI.*` above; `Agent.*`/`LLM.*`/`Tool.*`/`Chat.*`/`Audit.*`/`Search.*` below.
- Test sub-package mirrors production.
- Vendored static-asset path mirrors runtime CSP path.
- Single ZPM `<Resource>` covers all sub-packages.

### Requirements Coverage Validation ✅

**Functional Requirements coverage (all 59 FRs):**

| FR area | Mapped | Status |
|---|---|---|
| Session Inspection (FR1–FR12) | 12/12 | ✅ |
| Message Search (FR13–FR24) | 12/12 | ✅ |
| LLM Provider Framework (FR25–FR30) | 6/6 | ✅ |
| Read-Only Enforcement & Audit (FR31–FR37) | 7/7 | ✅ |
| Configuration & Credentials (FR38–FR42) | 5/5 | ✅ |
| Chat Lifecycle (FR43–FR47) | 5/5 | ✅ |
| Installation & Operator Surface (FR48–FR54) | 7/7 | ✅ |
| Developer Extensibility (FR55–FR59) | 5/5 | ✅ |

**Non-Functional Requirements coverage (all 30 NFRs):**

| NFR category | Count | Status |
|---|---|---|
| Performance (NFR-P1–P6) | 6/6 | ✅ |
| Security (NFR-S1–S6) | 6/6 | ✅ |
| Reliability (NFR-R1–R5) | 5/5 | ✅ |
| Scalability (NFR-SC1–SC4) | 4/4 | ✅ |
| Compatibility & Portability (NFR-C1–C6) | 6/6 | ✅ |
| Operability & Maintainability (NFR-O1–O5) | 5/5 | ✅ |
| Accessibility (NFR-A1) | 1/1 | ✅ |

**Deliberate exclusions** (not gaps): localization/i18n; compliance certifications; DR/backup separate from IRIS journal; SLA.

### Implementation Readiness Validation ✅

**Decision Completeness:**

- All 10 calibration decisions (OD1–OD10) resolved with defaults accepted.
- All numeric Class Parameter defaults documented and located in their owning classes.
- Default LLM models per provider locked (with "verify before each release tag" caveat for model-name drift).
- License, copyright holder, repository URL locked.

**Structure Completeness:**

- Complete file tree shown — every shippable class, every test class, every static asset, every config file at repo root.
- Each sub-package's owns / depends-on / depended-on-by documented.
- All integration points (browser↔server, server↔LLM, internal IRIS, audit fan-out, vocab capture, hand-off) specified.
- Data flow walkthrough from operator-types-question through citation-click documented step-by-step.

**Pattern Completeness:**

- All six conflict categories addressed (Naming, Structure, Format, Communication, Process, Tool-dispatch anti-patterns).
- Concrete canonical tool implementation example shown.
- Four anti-pattern examples shown.
- 13 mandatory enforcement items for AI agents + 4 enforcement mechanisms.

### Gap Analysis Results

**Critical gaps:** None. All 59 FRs and 30 NFRs are architecturally supported.

**Important gaps (non-blocking, story-scoped):**

| ID | Gap | Disposition |
|---|---|---|
| **G1** | Inspection tool details (body-class dispatch, BP introspection, error decoder, 14-column trace projection) live in the 2026-04-24 partially-superseded research docs | Accept. Story dev notes for Epic 4 cite the specific sections; `cleanup-edit-proposal-2026-05-02.md` preserves the Ens.* schema content with explicit "preserved by reference" callouts. |
| **G2** | Reuse mechanism for body-dispatch ladder between `Tool.Inspection.GetMessageBody` and `Tool.Search.InspectBodyCandidates` (direct cross-package call vs. extracted `SessionAgent.Body.DispatchLadder`) | Defer to Epic 8 — choice best made when writing `InspectBodyCandidates`. Both options compatible with this architecture. |
| **G3** | Web Gateway 60s default Task-0 probe (capture verbatim from operator's gateway) | Accept — story scope (Epic 1, operator README authoring). |
| **G4** | `%Dictionary.MethodDefinition` reflection probe on 2024.1 | Accept — story scope (Epic 2, before tool registry generation). |
| **G5** | `EnsLib.HL7.SearchTable` row shape probe | Accept — story scope (Epic 4 Story 4.6 `FindSessionsByBody`, re-anchored from Epic 8 since Inspection is first cross-codebase SearchTable consumer; Epic 8 Story 8.5 `SearchByBodyField` reuses the captured shape). |
| **G6** | `SynthesizeAlias` determinism unit test (~10 reordering scenarios) | Accept — story scope (Epic 9, before vocab capture). |
| **G7** | `%OnAfterSave` non-recursion verification on 2024.1 | Accept — story scope (Epic 9, before vocab persistence). |

All gaps are story-scoped Task-0 probes or reference-doc lookups, not architecture-blocking.

**Minor gaps (nice-to-have, post-v1):**

- `objectscript` and `hl7` Prism grammars — may need custom language definitions or fall back to `markup` gracefully.
- Dark-mode token concrete values — deferred until/unless parent Mgmt Portal ships dark mode.
- Second canonical wire shape alongside Anthropic — risk-mitigation fallback documented in PRD; not blocking.

### Validation Issues Addressed

No critical issues found. All seven important gaps are story-scoped (Task-0 probes or reference-doc lookups), correctly deferred per `research-first.md` rule 4.

### Architecture Completeness Checklist

**Requirements Analysis**

- [x] Project context thoroughly analyzed (Step 2)
- [x] Scale and complexity assessed (medium overall, high in pure-OS runtime / version-floor / 3-layer read-only / 4-provider abstraction / two-stage body search / vocab learning / lifecycle coupling / multi-tab serialization)
- [x] Technical constraints identified (IRIS 2024.1+, pure ObjectScript, no AI Hub, single ZPM module, all classes under `SessionAgent.*`, HSCUSTOMCODE distribution, MCP-exportable contract)
- [x] Cross-cutting concerns mapped (10 concerns documented in Step 2)

**Architectural Decisions**

- [x] Critical decisions documented with versions (Step 4 — all locked from upstream artifacts)
- [x] Technology stack fully specified (ObjectScript, IRIS 2024.1+, marked ≥18.0.2 + Prism + DOMPurify)
- [x] Integration patterns defined (Step 5 + Step 6 §"Integration Points")
- [x] Performance considerations addressed (NFR-P1–P6 mapped to specific class parameters and patterns)

**Implementation Patterns**

- [x] Naming conventions established (Step 5 §"Naming Patterns")
- [x] Structure patterns defined (Step 5 §"Structure Patterns" + Step 6 file tree)
- [x] Communication patterns specified (Step 5 §"Communication Patterns" — JSON schema subset, caller context propagation, ZenMethod return shape, seven anti-patterns)
- [x] Process patterns documented (Step 5 §"Process Patterns" — Try/Catch, tool error surfacing, concurrency, transaction side-effects, %OnAfterSave recursion, namespace switching, audit pre-registration, retry-after parsing, idempotency)

**Project Structure**

- [x] Complete directory structure defined (Step 6 file tree — ~50 ObjectScript classes + 12 vendored client-side files + config files)
- [x] Component boundaries established (Step 6 §"Sub-package boundaries" table)
- [x] Integration points mapped (Step 6 §"Integration Points")
- [x] Requirements to structure mapping complete (Step 6 §"Requirements to Structure Mapping" — all 59 FRs + 30 NFRs traced)

### Architecture Readiness Assessment

**Overall Status:** **READY FOR IMPLEMENTATION**

All 16 checklist items are `[x]`. No critical gaps remain. All seven important gaps are story-scoped Task-0 probes or reference-doc lookups, correctly deferred per `research-first.md` rule 4.

**Confidence Level:** **High**

Most architectural decisions were locked by upstream artifacts (PRD, research docs, UX spec, saved memory) before architecture-stage; this document consolidates them and adds 10 calibration decisions + 3 pattern-stage decisions. Confidence is supported by:

- Comprehensive PRD with 59 FRs + 30 NFRs already traced to acceptance criteria.
- Two pure-ObjectScript research docs (~22,000 words combined) that ran six structured steps each, with cited sources and explicit confidence levels per finding.
- Local `irislib/` source verification of `Ens.MessageHeader` indexes, `Ens.SuperSessionIndex` shape, `Ens.Config.Credentials`, `%Net.HttpRequest`, encryption primitives.
- UX spec with 14 completed steps including component-level detail and accessibility commitments.
- Saved memory facts that lock posture, scope, naming, and search-agent semantics.

The five remaining medium-confidence items (all flagged in research) become Task-0 probes in their owning Epic stories — the standard pattern for our project's `research-first.md` rule 4.

**Key Strengths:**

1. **Trust boundary is structurally clean.** The `SessionAgent.Agent.AgentLoop.RunTurn(...)` entry point is the seam — everything above is CSP/Zen-coupled; everything below is MCP-portable. This is the load-bearing commitment that makes FR55–FR57 (MCP-exportable dispatch contract) achievable without rewriting infrastructure when sibling `iris-execute-mcp-v2` wraps the registry.
2. **Read-only enforcement is structurally non-evadable.** Three independent layers (code discipline, dispatch policy gate, IRIS RBAC role) survive any single-layer oversight. NFR-S1 / NFR-R1 are not aspirational — they're enforced at the database privilege level.
3. **Provider abstraction validated by ship-priority.** OpenAI ships first as a translator-from-Anthropic-canonical, exercising the abstraction's hardest case from day one rather than late. The fifth-provider extensibility claim (FR28, Journey 4 Tomás) is structurally provable by reading two existing concretes.
4. **Two-agent infrastructure sharing is mechanical.** ~80% of the codebase is shared (provider abstraction, agent loop, tool registry pattern, persistence schemas, audit log, RBAC role, Markdown bundle, IPM packaging). The deltas concentrate in tool surfaces (13 inspection vs. 8+1+1 search) + the vocabulary-learning class family + chat-keying lifecycle. Adding a third agent later (e.g., Production Health Agent) costs one tool sub-package + one portal subclass.
5. **Operator-prerequisites are structural deliverables, not optional copy.** README §"Operator Prerequisites" is named in FR52 + Aishah Journey 3 + research §"Operator README Content"; Web Gateway 300s + RBAC grant + credential supply are install-blocking.
6. **Calibration constants documented as `Class Parameter`.** Every tunable (timeouts, max iterations, vocab thresholds, search time windows) is declared as `Parameter` — pilot tuning is cheap; no rewrite cycle needed if pilot data shows misranking or different operator preferences.
7. **No invented complexity.** The architecture sticks tightly to what the research locked. No speculative abstractions, no "framework for the framework," no unused indirection. The 11 UX components, ~50 ObjectScript classes, three sweep tasks, three install hooks — all earn their existence by mapping to a specific FR or NFR.

**Areas for Future Enhancement (post-v1):**

- **Vector / semantic body-content search** — would require `%Library.Embedding` (post-2024.1). Replaces the keyword/regex/LLM-evaluation body-content path. Vision-tier per PRD §Vision.
- **PHI redaction architecture** — body-redaction layer in dispatch path for operators whose namespace boundary doesn't fully contain PHI. Vision-tier.
- **Cross-namespace single-conversation operation** — currently forbidden by `$NAMESPACE` switching prohibition in CSP context. Vision-tier.
- **Streaming responses** — SSE or async-poll instead of blocking dispatch. v1.5+ question.
- **LLM-extracted alias generation** from chat history with regex PHI scrub. v1.5 with regex scrub before persistence.
- **Cross-user `NamespaceVocabulary` baseline** — schema ships in v1; population logic deferred.
- **Reference-implementation maturity** — pattern adopted by sibling IRIS-domain agents (Production Health, Schema Discovery, HealthShare Migration Assistant). Vision-tier.

### Implementation Handoff

**AI Agent Guidelines:**

- Follow all architectural decisions exactly as documented in this `architecture.md`. Where a decision is locked upstream (PRD/research/UX spec/saved memory), this doc cites the source — defer to that source if more detail is needed.
- Use implementation patterns consistently across all components. The 13-item "All AI Agents MUST" enforcement checklist (Step 5 §"Enforcement Guidelines") is mandatory.
- Respect project structure and boundaries. New code lives under `SessionAgent.*` only — never `Custom.*`, `App.*`, `EnsCustom.*`. Trust boundary is the `RunTurn` entry point; don't smuggle CSP state across it.
- Refer to this document for all architectural questions. If a question isn't answered here, the priority order for resolution is: (1) PRD §"Functional Requirements" / §"Non-Functional Requirements", (2) the relevant research doc section, (3) UX spec §"Component Strategy" or §"User Journey Flows", (4) project rules under `.claude/rules/`, (5) saved memory at `~/.claude/projects/c--git-iris-session-agent/memory/`. If none of these answer the question, raise it as a story-scoped open question in the dev notes.

**First Implementation Priority:**

**Story 1.1 — Project Initialization**: Create at the repo root by hand (no starter template, per Step 3 decision):

- `module.xml` (33-line shape from research doc lines 957–993)
- `LICENSE` (MIT, `Copyright (c) 2026 Joshua Brandt`)
- `README.md` (operator-prereq-anchored, content from research doc §"Operator README Content"; both HealthShare and plain-IRIS bookmark URL patterns per OD2/OD3)
- `.gitignore` (standard IRIS / VSCode / IDE patterns)
- `src/SessionAgent/` (empty root package)
- `src/static/` (empty target for vendored bundle)

**Then proceed through the 10-Epic v1 sequence** (per [`epics.md`](epics.md) §"Epic List" + §"Decision Impact Analysis → Implementation Sequence" above):

- **Epics 1–3 deliver the MVP demo-able milestone** (single-agent OpenAI-powered Inspection Agent) — PRD §Product Scope MVP exit criteria. Epic 1 (foundation) → Epic 2 (backend plumbing) → Epic 3 (UI demo-able).
- **Epics 4–7 complete the Inspection Agent** (remaining 10 tools, multi-provider support, per-agent config UI, chat-history lifecycle coupling).
- **Epics 8–10 add the Search Agent** (vocabulary persistence + 8-tool catalog, vocabulary learning + digest assembly, portal subclass + hand-off + TTL sweep + vendored Markdown bundle) — completing v1.
- **Vision tier (post-v1, deferred)**: cross-user `NamespaceVocabulary` baseline population (schema ships in Epic 8) and the rest of [PRD §"Vision (Future, post-v1)"](prd.md).

**Carry-forward Task-0 probes** (run on a live 2024.1 instance before the corresponding epic story is dispatched, per `research-first.md` rule 4):

1. **Epic 1** (Story 1.2): Web Gateway "Server Response Timeout" verbatim default value capture.
2. **Epic 2** (Story 2.10): `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` returns non-null on 2024.1.
3. **Epic 4** (Story 4.6): `EnsLib.HL7.SearchTable` row shape `(DocId, PropName, PropValue)` on operator's instance — re-anchored from Epic 8 to Epic 4 since `FindSessionsByBody` is the first cross-codebase consumer of the SearchTable shape; Epic 8 Story 8.5 (`SearchByBodyField`) reuses the captured shape.
4. **Epic 7** (Story 7.1): `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId)='...')` SQLCODE=0/100 semantics on 2024.1.
5. **Epic 9** (Story 9.1): `%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1.
6. **Epic 9** (Story 9.1): `SynthesizeAlias` deterministic stringification unit test against ~10 reordering scenarios.

Each Task-0 probe and its expected output are captured in the corresponding story's Tasks/Subtasks block at story-creation time.

## Epic-Sequence Evolution

This section records the evolution of the implementation epic sequence between architecture-stage and epic-design-stage, so future readers wondering "why these 10 epics, and what about the architect's original 18-step thinking?" find the answer in-doc rather than in git history.

### What changed (2026-05-02)

The architecture document originally proposed an **18-step implementation sequence** in §"Decision Impact Analysis → Implementation Sequence" (now updated above to the consolidated 10-epic v1 sequence). Downstream of architecture-stage, the [`bmad-create-epics-and-stories`](../../.claude/skills/bmad-create-epics-and-stories/) workflow ran and consolidated the original 18 steps into **10 user-value-first epics** for v1. The result is captured in [`epics.md`](epics.md).

### Why consolidate

BMad's epic-design principle is *organize epics around user value, not technical layers* and *consolidate epics that all modify the same core files*. Several of the architect's original 18 epics did not deliver standalone operator value individually:

- Original Epic 2 (LLM Provider abstraction alone) — operator-invisible.
- Original Epic 3 (Tool.Base + Tool.Registry alone, with no agent loop) — operator-invisible.
- Original Epic 4 (AgentLoop alone, with no UI) — operator-invisible.
- Original Epics 5 + 6 (chat panel + VisualTrace subclass) — meaningless apart; together they're the MVP demo.
- Original Epics 8 + 10 (Anthropic + Gemini + OpenAICompat providers) — all touch the same `LLM/*` package; per BMad's file-overlap rule, consolidate.
- Original Epics 12 + 13 (vocabulary persistence + 8-tool search catalog) — vocabulary schema must exist before search tools can use it; ship together.
- Original Epics 14 + 15 (click-through capture + vocabulary digest assembly) — single coherent vocabulary-learning capability.
- Original Epics 16 + 17 (Message Viewer subclass + TTL sweep) — search agent UI doesn't ship without lifecycle integrity.

Consolidating these gave 10 epics where each epic has a clean operator-facing acceptance criterion. Story sequence *within* each consolidated epic preserves the architect's original sub-step ordering — for example, Epic 5 stories ship Anthropic first (validates the canonical-wire inversion early), then Gemini (camelCase + retryDelay), then OpenAICompat. The architect's reasoning is preserved at story-order level rather than epic-number level.

### Bidirectional mapping (architect's original → consolidated)

| Architect's original epic | epics.md consolidated epic | Notes |
|---|---|---|
| Epic 1 — IPM packaging + Installer + RBAC + Audit-event registration | **Epic 1** — Project Foundation & Installable Package | 1:1 mapping. |
| Epic 2 — LLM Provider abstraction + OpenAIProvider + RetryWithBackoff + EnvSecret | **Epic 2** — Inspection Agent Backend Plumbing | Combined with original Epics 3 + 4. |
| Epic 3 — Tool.Base + Tool.Registry + 3 example tools | **Epic 2** — Inspection Agent Backend Plumbing | Combined with original Epics 2 + 4. |
| Epic 4 — Agent.AgentLoop + Chat.History + concurrency | **Epic 2** — Inspection Agent Backend Plumbing | Combined with original Epics 2 + 3. |
| Epic 5 — Shared chat-panel draw helper + JS + ZenMethod | **Epic 3** — Inspection Agent UI MVP Demo-able | Combined with original Epic 6. |
| Epic 6 — VisualTrace subclass — *MVP demo-able milestone* | **Epic 3** — Inspection Agent UI MVP Demo-able | Combined with original Epic 5. **MVP exit criterion preserved at end of consolidated Epic 3.** |
| Epic 7 — Remaining 10 Inspection tools + read-only test suite | **Epic 4** — Inspection Agent Full Tool Catalogue | 1:1 mapping. |
| Epic 8 — AnthropicProvider + cross-provider integration tests | **Epic 5** — Multi-Provider Support | Combined with original Epic 10. Story order: Anthropic first (validates inversion). |
| Epic 9 — `SessionAgent.UI.AgentConfig` Zen page + per-agent secret routing | **Epic 6** — Per-Agent Configuration UI | 1:1 mapping. |
| Epic 10 — GeminiProvider + OpenAICompatProvider | **Epic 5** — Multi-Provider Support | Combined with original Epic 8. |
| Epic 11 — `PurgeOrphanedChatHistory` + lifecycle coupling | **Epic 7** — Inspection Chat-History Lifecycle | 1:1 mapping. |
| Epic 12 — `Search.UserVocabulary` + `SeedVocabulary` + Installer additions | **Epic 8** — Search Agent Foundation | Combined with original Epic 13 (vocabulary schemas + search catalog ship together). |
| Epic 13 — 8-tool search catalog + `VocabLookup` utility | **Epic 8** — Search Agent Foundation | Combined with original Epic 12. |
| Epic 14 — Click-through capture + `RecordSuccess` method | **Epic 9** — Search Agent Vocabulary Learning | Combined with original Epic 15. |
| Epic 15 — `VocabularyDigest.Build` + first-user-message prefix injection | **Epic 9** — Search Agent Vocabulary Learning | Combined with original Epic 14. |
| Epic 16 — `SessionAgent.EnsPortal.MessageViewer` subclass + chat tab | **Epic 10** — Search Agent UI Embed, Hand-off & TTL Sweep | Combined with original Epic 17. |
| Epic 17 — `PurgeStaleSearchChat` TTL sweep + retention config | **Epic 10** — Search Agent UI Embed, Hand-off & TTL Sweep | Combined with original Epic 16. **Completes v1 scope at end of consolidated Epic 10.** |
| Epic 18 (v1.5) — `NamespaceVocabulary` cross-user baseline | **Vision tier (post-v1, deferred)** | Schema ships in consolidated Epic 8; population logic is post-v1 per [PRD §Vision](prd.md). |

### Cross-reference convention going forward

- **`epics.md`** is the authoritative numbering for v1 implementation.
- **This document (architecture.md)** uses the consolidated 10-epic numbering. The architect's original 18-step thinking is preserved as story order *within* each consolidated epic and as the mapping table above.
- **PRD.md and ux-design-specification.md** are aligned to the consolidated 10-epic numbering.
- **brief / distillate / research docs** retain references to the architect's original 18-step numbering as planning history; readers cross-reference via the mapping table above.
- **Story files** (produced by [`bmad-create-story`](../../.claude/skills/bmad-create-story/) skill) cite both the consolidated epic number AND the architecture section by name in dev notes — e.g., "implements Epic 5 / architecture original Epic 8 (AnthropicProvider) per architecture.md §'Decision Impact Analysis → Implementation Sequence'" — so dev agents picking up a story can find context regardless of which numbering they encounter first.

### Recoverability

The original 18-step enumeration in this document's §"Decision Impact Analysis → Implementation Sequence" was edited in-place during the 2026-05-02 epic-design alignment. Prior versions are recoverable from git history (`git log --oneline _bmad-output/planning-artifacts/architecture.md`) if the original 18-step prose is needed verbatim.

## Status

Architecture workflow complete. Document is ready to drive implementation; all 8 workflow steps recorded in frontmatter `stepsCompleted`. **Revision 2026-05-02:** epic numbering aligned with `epics.md` 10-epic consolidated structure (recorded in frontmatter `revisions`).
