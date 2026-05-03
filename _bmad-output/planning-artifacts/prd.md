---
title: "Product Requirements Document: iris-session-agent"
project: iris-session-agent
author: Joshua Brandt
date: 2026-05-02
license: MIT
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-05-domain
  - step-06-innovation
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
  - step-12-complete
status: complete
completedAt: 2026-05-02
releaseMode: phased
classification:
  projectType: developer_tool
  domain: general
  complexity: medium
  projectContext: greenfield
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-iris-session-agent.md
  - _bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md
  - _bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md
  - _bmad-output/planning-artifacts/research/technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md
  - _bmad-output/planning-artifacts/research/technical-ensemble-session-inspection-agent-research-2026-04-24.md
  - _bmad-output/planning-artifacts/research/technical-ensemble-session-agent-ui-integration-research-2026-04-24.md
  - _bmad-output/planning-artifacts/research/cleanup-edit-proposal-2026-05-02.md
  - docs/initial-prompt.md
documentCounts:
  briefs: 2
  research: 5
  brainstorming: 0
  projectDocs: 1
workflowType: prd
---

# Product Requirements Document: iris-session-agent

**Author:** Joshua Brandt
**Date:** 2026-05-02
**License:** MIT

This PRD is the planning artifact between the [Product Brief](product-brief-iris-session-agent.md) (vision-level input) and the architecture document + epic breakdown (downstream outputs). It locks the **binding capability contract** for v1 (§Functional Requirements) and the **quality attributes** that contract must satisfy (§Non-Functional Requirements). Architecture and epics expand on this PRD's plan; they do not introduce new capability commitments. The PRD itself plans the **full v1 scope** while the §Project Scoping section calls out incremental delivery cadence (MVP → Growth-completing-v1 → Vision-post-v1).

## Table of Contents

1. [Executive Summary](#executive-summary) — vision, six-surface problem, primary users, posture
2. [Project Classification](#project-classification) — type, domain, complexity, context
3. [Success Criteria](#success-criteria) — user / business / technical success + measurable outcomes
4. [Product Scope](#product-scope) — MVP / Growth / Vision tier contents
5. [User Journeys](#user-journeys) — four narrative journeys + capability summary
6. [Innovation & Novel Patterns](#innovation--novel-patterns) — three genuinely-novel architectural surfaces
7. [Developer-Tool-Specific Requirements](#developer-tool-specific-requirements) — language matrix, install, plugin contracts, code examples
8. [Project Scoping & Phased Development](#project-scoping--phased-development) — MVP cut rationale, resource posture, risk mitigation
9. [Functional Requirements](#functional-requirements) — 59 FRs across 8 capability areas (binding capability contract)
10. [Non-Functional Requirements](#non-functional-requirements) — 30 NFRs across 7 categories + 4 deliberate exclusions

## Executive Summary

`iris-session-agent` is an open-source InterSystems IRIS module that adds an AI assistant chat experience to the Interoperability operator's existing Management Portal. Two agents share infrastructure inside one IPM-installable package: a **Session Inspection Agent** (chat tab on a custom subclass of `EnsPortal.VisualTrace`) explains what happened in a given Ensemble session, and a **Message Search Agent** (chat tab on a custom subclass of `EnsPortal.MessageViewer`) helps operators find sessions by natural-language query. Both run on **IRIS / IRIS for Health 2024.1+** in pure ObjectScript, with no embedded Python in the runtime path and no AI Hub dependency.

> *"Chatting with your Interoperability Session to really understand what happened — and finding the right session by asking."*

The product fills a structural gap that exists today on the IRIS the community already runs. An Ensemble session leaves a trace across six disconnected data surfaces — `Ens.MessageHeader`, dynamically-typed message bodies, `Ens.SearchTableBase` subclass extents (e.g., `EnsLib.HL7.SearchTable`), `Ens.Util.Log`, `Ens.Rule.Log`, and BP runtime state in `Ens.BP.Context` / `Ens.BP.Thread` — and operators reconstruct the cross-surface picture in their heads on every incident, starting from scratch. The agent reads all six surfaces through a disciplined tool registry, correlates them, and answers in plain English.

**Primary users:** IRIS / Ensemble integration engineers and operators on IRIS / IRIS for Health 2024.1+ — the people who carry the on-call pager. Two delight signatures matter equally: **senior on-call engineers** report *"this saved me 25 minutes at 2am"*; **junior engineers** report *"I diagnosed something I couldn't have alone"*. The 20-30 minute expert tab-switching session collapses toward a 30-second conversation; even a 5-minute → 1-minute win on common diagnoses is meaningful.

**Posture:** single-author hobby project, **MIT-licensed open source from day one**, distributed via Open Exchange and GitHub (`github.com/jbrandtmse/iris-session-agent`). No commercial motion, no SI partner channel, milestone-based timeline. v1 ships full scope but with **incremental delivery** — pre-alpha builds reach operators early; the demo-able OpenAI-powered Inspection Agent precedes the second agent and additional providers.

### What Makes This Special

**Fit, not moat.** The IRIS Interoperability ecosystem has no purpose-built AI tool. General AIOps platforms (Datadog Bits, Dynatrace Davis, Splunk AI, IBM AIOps) are blind to Ensemble — IRIS produces no OpenTelemetry, the message-header schema is invisible to ingest pipelines, and the rule-log semantics don't translate. Boomi's Integration Advisor works at design-time, not runtime. InterSystems' AI Hub SDK is pre-release; this product is for the IRIS operators who have running productions today. The unfair advantage is that the agent is built by an IRIS engineer, for IRIS engineers, on the IRIS the community already has.

**Three core insights:**

1. **The data is already structured and queryable.** IRIS exposes the six session-trace surfaces through SQL and object access; an LLM with disciplined tool calls can read in parallel what humans tab-switch to read in series.
2. **The user is already in the right page.** Visual Trace already focuses on a session; Message Viewer is already the query surface. Embed the agent there — don't bolt on a parallel UI.
3. **Provider portability is mechanical, not architectural.** A four-provider LLM abstraction (Anthropic-canonical wire shape; OpenAI, Google Gemini, and any OpenAI-compatible endpoint as adapters) makes switching providers — or adding a fifth — one new concrete subclass plus a registry entry. No refactor.

**Read-only by design.** Three layers of enforcement — code discipline, dispatch policy gate consulting `MutatesState`, and IRIS RBAC role `%SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` tables — make it operationally impossible for the agent to mutate production data. Audit logging captures every LLM round-trip and tool dispatch at FK-linked granularity.

**Vision horizons.** *Near term:* incident triage that fits in a coffee break instead of an evening; junior engineers operating without senior-tutorial overhead; correlated cross-surface errors actually getting found instead of getting missed. *Longer term:* the pure-ObjectScript LLM agent + MCP-exportable tool registry + per-agent Zen-page configuration pattern becomes a **reference implementation** for other IRIS-domain agents (Production Health, Schema Discovery, HealthShare Migration Assistant). When AI Hub matures to GA, this remains a community option for the long tail of older-IRIS deployments and a teaching example for the pattern.

## Project Classification

| Field | Value |
|---|---|
| **Project Type** | Developer tool — IPM-installable IRIS module with extensible LLM provider framework and MCP-exportable tool registry; operator-facing surface is two custom Zen page subclasses inside the IRIS Management Portal. |
| **Domain** | General — enterprise integration tooling for IRIS Interoperability. Deployment context often touches HL7 / FHIR / HealthShare in customer namespaces; v1 boundary on PHI is **namespace segregation** (the IRIS-customer practice today). Body-redaction architecture is post-v1. |
| **Complexity** | Medium overall, with high technical / platform sub-rating concentrated in: pure-ObjectScript runtime invariant, IRIS 2024.1+ version floor (no AI Hub primitives), three-layer read-only enforcement, four-provider LLM abstraction, two-agent infrastructure-sharing rubric, two-stage body-content search, per-message-body-class vocabulary learning, chat-history lifecycle coupling to `Ens.MessageHeader.Purge()`, multi-tab serialization via `%OpenId(id, 4)`, and Web Gateway 60s LLM-call timeout cliff. |
| **Project Context** | Greenfield — no existing production code; v1 ships from scratch under MIT, distributed via Open Exchange and GitHub. |

## Success Criteria

### User Success

The product succeeds when **operators get their evenings back**. Concretely:

- **Time-to-resolution drops measurably** on common diagnostic conversations. *Aspirational:* 20-30 min of expert tab-switching → ~30s of conversation. *Commitment-grade:* 5 min → 1 min on the most common diagnostic patterns — failed-message triage, "where did this message go," "what did the rules decide and why." Measured via operator self-report and side-by-side timing during early-adopter pilots; no instrumentation in v1.
- **Junior engineers reach senior-level diagnosis without senior help.** A junior engineer with the agent produces a session-cause summary that a senior reviewer agrees with on a curated test set of historical incidents. *Target threshold: ≥80% senior-agreement (illustrative-pending-pilot — pin during first pilot).*
- **Operators integrate the agent into their on-call workflow.** Not "tried it once" — they reach for it during real 2am pages and don't switch back to manual tab-switching for the diagnoses the agent handles. Measured qualitatively from named pilot operators.
- **The "aha!" moment** is the first time an operator opens Visual Trace, types *"what happened?"*, gets a coherent multi-surface explanation, and recognizes the agent read more sources in 5 seconds than they would have opened in 5 minutes.

### Business Success

This is a **hobby project** with no commercial motion. The standard "business success" definitions don't apply; adapted to this product's actual posture:

- **At least one customer site genuinely adopts it for production on-call diagnosis.** One real operator integrating it into their workflow beats a hundred curious downloads. Measured by direct contact / community reporting — not by download count.
- **The maintenance load stays sustainable for a single maintainer.** The author triages incoming issues and reviews community PRs without the project consuming weekends. If the project demands more time than the author can give, scope cuts (not deadline pressure) are the response.
- **Community contributions surface from real operators** — PRs that fix things real users hit, issues that reveal real production scenarios, forks that adapt the pattern to other IRIS domains. Not vanity engagement (stars, watchers).

**Explicitly NOT measured** (per brief):

- Download counts, GitHub stars, watchers
- Maintenance-longevity-for-its-own-sake
- Total user counts
- Revenue (MIT open source; no commercial motion exists)

### Technical Success

The product passes its technical bar when the platform invariants hold under operator-grade workloads:

- **`zpm install iris-session-agent`** succeeds on a fresh IRIS / IRIS for Health 2024.1+ instance, including instances with embedded Python disabled. Release-gate CI on a Python-less IRIS image (when available) blocks merges that violate this invariant.
- **Read-only is structurally enforced.** No code path inside the agent mutates `Ens.*` data — verified by (1) periodic audit-log review showing zero non-SELECT statements through the dispatch gate, (2) RBAC role `%SessionAgent_ReadOnly` granted SELECT-only, (3) dispatch policy gate `MutatesState=0` check.
- **Audit logging is 100% complete.** Every LLM round-trip writes a `SessionAgent.Audit.LlmCall` row; every tool dispatch writes a `SessionAgent.Audit.ToolCall` row, FK-linked to the chat-history row.
- **Provider switching is mechanical.** Adding a fifth provider is one new concrete `SessionAgent.LLM.Provider` subclass + one registry entry — no edits to `AgentLoop`, `ToolRegistry`, or any shared infrastructure. Validated when a community contributor adds one (or as a v1.5 self-test).
- **Tool registry remains MCP-exportable.** Sibling `iris-execute-mcp-v2` wraps the registry into MCP `tools/list` + `tools/call` endpoints with no changes to this project. Validated by integration test from the sibling project.
- **Agent answers complete within operator-configured Web Gateway timeout.** README documents the 60s → 300s timeout raise as a prerequisite; per-call provider timeout caps at 90s. v1 operators see no timeout-cliff failures on documented configurations.
- **Concurrent multi-tab access is safe.** Two browser tabs for the same operator don't corrupt chat history — `%OpenId(id, 4)` exclusive lock serializes turns. Validated by integration test.
- **Chat-history lifecycle holds under purge.** When `Ens.MessageHeader.Purge()` removes session N, the daily sweep task removes orphaned `SessionAgent.Chat.History` row(s) for the Inspection Agent. No leaked history.

### Measurable Outcomes

| Outcome | Target | Measurement |
|---|---|---|
| Time savings on common diagnoses | Commitment: 5 min → 1 min; aspirational: 20-30 min → 30s | Operator self-report + side-by-side timing during pilots |
| Junior-diagnosis enablement | ≥80% senior-agreement on a curated test set *(illustrative-pending-pilot)* | Senior reviewer scoring agent-produced summaries |
| Pilot adoption | ≥1 named customer site running in production on-call | Direct operator confirmation |
| Pre-alpha demo-able milestone | OpenAI-powered Inspection Agent reaches an operator's hands at end of Epic 3 | Milestone gate (no fixed date) |
| Read-only enforcement | 0 non-SELECT statements observed in audit-log review | `SessionAgent.Audit.ToolCall` periodic audit |
| Audit-log completeness | 100% of LLM round-trips and tool dispatches captured | Cross-check vs. agent-loop instrumentation |
| Provider portability | Adding a 5th provider = one new subclass + registry entry, no shared-infra edits | Code-review verification when 5th provider is added |
| Web Gateway timeout cliff | 0 operator-visible failures on documented configuration (300s gateway, 90s per-call cap) | Operator reports during pilot |
| Maintenance sustainability | Author triages issues + PRs without weekend consumption | Author self-report; if violated, response is scope cut, not deadline push |

## Product Scope

**Delivery vs. planning intent.** PRD, architecture, and the downstream epics document plan the **full v1 scope** — both the MVP and Growth tiers below are committed v1 work. Delivery is incremental: pre-alpha builds reach operators at MVP completion, then Growth features land across subsequent epics in the inspection-agent + search-agent epic sequence. The Vision tier is post-v1 deferred work, not part of v1 planning depth.

### MVP — Minimum Viable Product

**The pre-alpha demo-able artifact (≈ end of Epic 3 in the consolidated 10-epic v1 sequence — see [`epics.md`](epics.md)):**

- **Single agent**: Session Inspection Agent only.
- **Single provider**: OpenAI only.
- **Embedded as a chat tab** in `SessionAgent.EnsPortal.VisualTrace` (subclass of `EnsPortal.VisualTrace`).
- **13 inspection tools**: `session_summary`, `session_timeline`, `message_headers`, `event_log`, `rule_log`, `find_related_sessions`, `find_sessions_by_body`, `get_message_body`, `get_message_detail`, `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods`, `explain_error`.
- **Three-layer read-only enforcement** (code discipline + dispatch policy gate + RBAC role `%SessionAgent_ReadOnly`).
- **Audit logging** at LLM round-trip and tool dispatch granularity.
- **Per-agent Zen config page** (`SessionAgent.UI.AgentConfig`) — single-agent variant.
- **Chat history coupled to `Ens.MessageHeader.Purge()`** via daily sweep task.
- **IPM-installable**: `zpm install iris-session-agent` against IRIS 2024.1+.
- **README operator prerequisites**: Web Gateway timeout 60s → 300s, RBAC role grant, OpenAI API key in env-var or `Ens.Config.Credentials`.

**Why MVP scope ends here**: the operator's first delight moment ("type *what happened?* into a Visual Trace tab and watch a coherent answer come back") is reachable without the second agent or the three additional providers. Pre-alpha distribution from this baseline is the lowest-friction validation surface.

### Growth Features (Post-MVP, completing v1)

- **Second agent: Message Search Agent** on `SessionAgent.EnsPortal.MessageViewer` — 8 indexed-access tools + 1 body-inspection tool + 1 vocabulary utility.
- **Three additional LLM providers**: Anthropic, Google Gemini, Ollama / vLLM (any OpenAI-compatible self-hosted endpoint).
- **Per-user, per-message-body-class vocabulary learning** for the Search Agent (`SessionAgent.Search.UserVocabulary` keyed on `(PortalUser, MessageBodyClass, Alias)`).
- **Body-content search** beyond indexed columns — two-stage narrow-then-inspect pattern, ≤50 candidate cap, default 24h time window with 720h (30d) max.
- **Vendored client-side Markdown rendering** (`marked` + `Prism.js` curated languages + `DOMPurify`) at `/csp/static/iris-session-agent/`.
- **Search-agent chat-history sweep** — TTL-based 30-day default (configurable).
- **Concurrent multi-tab safety** validated under load (`%OpenId(id, 4)` exclusive lock).
- **Anthropic prompt caching** of `system + tools` prefix; vocabulary digest carried as first-user-message prefix to preserve cache hit rate.
- **`SessionAgent.Search.SeedVocabulary`** ship-with templates (~10 entries).

### Vision (Future, post-v1)

- **MCP serving** — delegated to sibling [`iris-execute-mcp-v2`](https://github.com/jbrandtmse/). Our tool registry remains MCP-exportable; the sibling provides the transport.
- **Vector / semantic body-content search** — requires `%Library.Embedding` + embedding generation at message save time. Replaces the keyword/regex/LLM-evaluation body-content path.
- **PHI redaction architecture** — body-redaction layer in dispatch path for operators whose namespace boundary doesn't fully contain PHI.
- **Cross-namespace single-conversation operation** — currently forbidden by `$NAMESPACE` switching prohibition in CSP context.
- **Streaming responses** — SSE / async-poll instead of blocking dispatch.
- **LLM-extracted alias generation** from chat history with regex PHI scrub.
- **Cross-user `NamespaceVocabulary` baseline** — schema ships in v1; population logic deferred.
- **Stand-alone terminal REPL bot** — was an AI-Hub-coupled freebie; ~30 min of complexity to reimplement; defer until useful.
- **Reference-implementation maturity** — pattern adopted by sibling IRIS-domain agents (Production Health, Schema Discovery, HealthShare Migration Assistant).
- **Long-tail community option** when AI Hub goes GA — remains the offering for older-IRIS deployments and a teaching example for the pure-ObjectScript-agent pattern.

## User Journeys

### Journey 1 — Senior on-call: "The 2am page"

**Persona — Marisol Rivera, Senior Integration Engineer.** Five years at a regional health system; carries the on-call pager for HealthShare interoperability one week in four. Knows the message flows by heart; every incident still costs her tab-switches.

**Situation.** It's 2:14am. PagerDuty fires: a critical lab-order interface has a stuck session, the partner hospital is queuing messages waiting for an ACK, and the on-call shift has 47 minutes before the next page-up to leadership.

**Goal.** Find out *what happened* in session `1184729` and resolve the block — fast enough that she can sleep before the 7am stand-up.

**Obstacle.** Her usual playbook is: open Visual Trace, eyeball the call graph; jump to Message Viewer for the failing body; switch to Event Log namespace for adapter retries; check Rule Log for routing decisions; if there's a BPL, open the BP class source for the `await` boundary. She'd do that 4-5 times before realizing it's a routing-rule misfire. 25 minutes minimum.

**The story.** Marisol opens Visual Trace on session `1184729` — same as always — but now there's an "Ask the agent" tab. She types *"what happened?"* The agent runs `session_summary`, `session_timeline`, `rule_log`, opens the body via `get_message_body`, and answers in two paragraphs: the rule for `OrderType=LAB` returned the *fallback* target because the source MRN field was empty in this body, and the router's `defaultTarget` is a queue the receiving hospital decommissioned last week. *Confidence: high — three independent signals agree.*

**Resolution.** Marisol confirms by clicking the cited rule-log row (every claim links to the underlying tool result). She updates the routing rule's fallback target, reposts the queued message, closes the page. Total: 4 minutes. Asleep by 2:20am.

**Capabilities revealed.** Inspection Agent embedded in `EnsPortal.VisualTrace`; agent loop dispatching the 13 inspection tools; grounded answers with citations to underlying tool results; read-only enforcement (Marisol couldn't have *fixed* the rule via the agent even if she'd asked); audit logging of every LLM round-trip and tool dispatch; chat history preserved against session `1184729` so a colleague picking up at 7am sees the conversation.

### Journey 2 — Junior engineer + Search-to-Inspection hand-off: "I can't reach Marisol"

**Persona — Devin Park, Junior Integration Engineer (six months in).** Recent bootcamp grad; competent debugging but doesn't yet have the schema in his head. Carries the *backup* pager when Marisol is on primary.

**Situation.** Same night. While Marisol diagnoses the lab-order issue, a second alert fires: ADT admit messages from a rural clinic are silently failing — no error, just no ACK. Devin is secondary on-call. He doesn't know which session is broken, only that something's off.

**Goal.** Find the failing admits, diagnose, and resolve before Marisol has to wake up further.

**Obstacle.** Devin doesn't know how to find sessions by "admit type" — Message Viewer's field-search would require him to know the right `Ens.SearchTableBase` subclass, the body class, and the exact column. Two months ago he gave up and paged Marisol.

**The story.** Devin opens Message Viewer's "Ask the agent" tab and types *"find me failed admits from the last hour."* The agent has never seen "admits" from Devin before, so it consults seed vocabulary (HL7-aware: `admit ↔ A01/A04 events`), bounds with a 1-hour `TimeCreated` window, and runs `search_by_status` + `search_by_message_class` + `search_by_body_field` against `EnsLib.HL7.SearchTable`. Returns 7 sessions, by recency, with source clinic and ADT event code labeled.

Devin clicks session `1184885` (the rural clinic one). The portal navigates to Visual Trace, the chat tab carries a "from search" stripe, and the Inspection Agent picks up the context: *"You came from a search for failed admits — want me to look at this session?"* Devin types yes. The agent reports: the rural clinic's outbound message uses a non-standard `MSH-3` (sending application) value that the partner's HL7 router rejects with an unparsable validation error swallowed inside an event-log entry standard Visual Trace doesn't surface.

**Resolution.** Devin opens a ticket for the routing team to whitelist the clinic's `MSH-3`, posts a status update, closes the alert. He didn't wake Marisol. He didn't even know what `MSH-3` was before tonight. Total: 9 minutes. The next time he asks for "admits" the search is instant: vocabulary learning captured the alias from his click-through and confidence is now `Success / (Success + Failure + 1) = 0.5`. By the third time he asks, the agent skips the seed-vocabulary detour entirely.

**Capabilities revealed.** Search Agent embedded in `EnsPortal.MessageViewer`; 8 indexed-access tools + 1 body-inspection + 1 vocabulary utility; per-user vocabulary learning keyed on `(PortalUser, MessageBodyClass, Alias)` with confidence smoothing; seed vocabulary ship-with templates for HL7 idioms; URL-parameter context-pass at hand-off to Inspection Agent; both agents share the LLM provider abstraction and audit infrastructure; bounded-WHERE invariant (24h default, 720h max) keeps search fast on a million-message production.

### Journey 3 — Operator install + configure: "Welcome to v0.1.0"

**Persona — Aishah Khan, IRIS Platform Lead.** Manages the HSCUSTOM environment for a multi-hospital integration team. Decides what software lands in production. Doesn't write much ObjectScript day-to-day but knows IPM, RBAC, and Web Gateway intimately.

**Situation.** Marisol's team has been asking for an AI assistant on Visual Trace for months; Aishah saw the v0.1.0 announcement on Open Exchange this morning. README is 2,400 words; she has 30 minutes before her next meeting.

**Goal.** Install into a non-production HSCUSTOM namespace, configure OpenAI as the provider, verify a known-good session inspection works, decide whether to schedule production rollout.

**Obstacle.** Most IRIS open-source tools she's evaluated either skip operator-prerequisites (and her team gets paged at 3am because the Web Gateway timed out an LLM call) or bundle so many transitive deps that approving them through security review is a multi-day saga. She's burned out on both shapes.

**The story.** Aishah opens the README. First H2 is **Operator Prerequisites** with three concrete steps: (1) raise Web Gateway "Server Response Timeout" from 60s → 300s — *with an explanation of why* (LLM-call latencies often sit in the 30-90s band; default kills them mid-stream); (2) grant `%SessionAgent_ReadOnly` to the operator user/role; (3) supply the OpenAI API key via `$SYSTEM.Util.GetEnviron("OPENAI_API_KEY")` (preferred for containers) or `Ens.Config.Credentials` (traditional installs).

She runs `zpm install iris-session-agent` in HSCUSTOM. The Installer compiles `SessionAgent.*` cleanly — no Python required, no transitive Open Exchange deps. The bookmark `/csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen` shows up in the Mgmt Portal bookmark list. She clicks it on a known-failed session from yesterday. The agent config tab is empty — no provider yet.

She opens **Agent Configuration**, picks `OpenAI` from the provider dropdown, model `gpt-4o`, temperature `0.1`, leaves system prompt at default. The credential dropdown lists her `Ens.Config.Credentials` named `OPENAI_PROD` (configured 5 minutes ago). Saves. Returns to Visual Trace. Types "what happened?" The agent answers in 6 seconds. The diagnosis matches the post-mortem her team wrote yesterday.

**Resolution.** Total elapsed: 18 minutes including the README. Aishah schedules production rollout review for next sprint and posts to her team Slack: *"This is good. Here's how to use it."* Links the Open Exchange page.

**Capabilities revealed.** IPM packaging as a single module (`<Resource Name="SessionAgent.PKG"/>`); Installer compiles cleanly with no transitive Open Exchange deps and no embedded Python at install or runtime; README **Operator Prerequisites** section as a structural deliverable (not optional copy); Zen-page agent configuration UI (provider / model / max-tokens / temperature / system-prompt-override / read-only flag / credential-ref); credential resolution ladder (env-var → `Ens.Config.Credentials` → custom encrypted store); RBAC role `%SessionAgent_ReadOnly` with SELECT-only grants on `Ens.*`; bookmark URL pattern `/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`.

### Journey 4 — Community contributor: "Adding Cohere"

**Persona — Tomás Alves, Senior IRIS Engineer at a São Paulo SI partner.** Active in the IRIS Open Exchange community; maintains a few of his own modules. His shop standardized on Cohere's Command-R for cost reasons; iris-session-agent ships with OpenAI / Anthropic / Gemini / Ollama but not Cohere.

**Situation.** Tomás wants Cohere as a fifth provider. He's read the architecture doc and the brief's promise that *adding a provider is one new subclass + one registry entry*.

**Goal.** Submit a clean PR adding Cohere, get it merged, use his own contribution at his shop.

**Obstacle.** In other open-source projects he's contributed to, "extensible" turned out to be marketing — half the AgentLoop assumed OpenAI-shaped tool-call args, and the registry was a hard-coded switch statement. He was burned twice in the last year and is skeptical.

**The story.** Tomás clones the repo. He reads `SessionAgent.LLM.Provider.cls` (abstract base) and the four concrete subclasses for OpenAI, Anthropic, Gemini, and the OpenAI-compatible adapter (which already covers Ollama and vLLM). The pattern is exactly as advertised: an abstract `Provider` with a `MessageAdapter` and a `ToolDefAdapter`, each concrete provider implementing conversion to and from the **canonical Anthropic Messages wire shape**.

He subclasses `SessionAgent.LLM.Provider` as `SessionAgent.LLM.CohereProvider`, implements `Invoke()` against Cohere's `/v2/chat` endpoint, maps Cohere's `tool_calls` shape into the Anthropic-canonical `content[type=tool_use]` block in `MessageAdapter`, and implements `ToolDefAdapter` to render tool definitions in Cohere's expected schema. One-line entry added to `SessionAgent.LLM.Registry`. He runs the tool-call-roundtrip integration test against a Cohere mock — passes. Runs against his real Cohere key against a live IRIS — passes. **Total: 187 lines including tests, 4 hours.** No edits to `AgentLoop`, `ToolRegistry`, `Tool.Inspection.*`, `Tool.Search.*`, or anything else.

**Resolution.** Tomás opens a PR. One round of review feedback (a `Quit` should be `Quit tSC` in a `try` block — pure-ObjectScript hygiene); merged within a week. He links the merge in his shop's Slack; his team migrates iris-session-agent's LLM cost line to Cohere on Monday.

**Capabilities revealed.** Provider framework as four-class plugin contract (abstract base + `MessageAdapter` + `ToolDefAdapter` + registry); Anthropic-canonical wire shape as the integration point so adapters are mechanical; tool-call-roundtrip integration test as the contract acceptance gate; OSS contribution flow (clone, branch, PR, review, merge) is the supported community path; MIT license enables Tomás's shop to contribute without IP review overhead.

### Journey Requirements Summary

The four journeys collectively reveal these capability areas the PRD must cover in functional and non-functional requirements:

| Capability area | Journeys | Notes |
|---|---|---|
| **Inspection Agent embed in Visual Trace** | J1, J2 | 13 tools dispatched by agent loop; grounded answers with citations |
| **Search Agent embed in Message Viewer** | J2 | 8-9 tools; bounded-WHERE invariant; vocabulary learning |
| **Search-to-Inspection hand-off** | J2 | URL-parameter context-pass; "from search" stripe |
| **Per-user vocabulary learning** | J2 | `(PortalUser, MessageBodyClass, Alias)` keying; confidence smoothing; seed-vocabulary fallback |
| **Three-layer read-only enforcement** | J1 | Code discipline + dispatch policy gate + RBAC role |
| **Audit logging** | J1 | LLM round-trip + tool dispatch FK-linked to chat history |
| **Provider abstraction (4-class plugin)** | J4 | Anthropic-canonical wire shape; registry; one-subclass-plus-registry-entry contract |
| **IPM packaging** | J3 | Single module, no transitive deps, no Python at install/runtime |
| **Operator prerequisites doc** | J3 | Web Gateway timeout, RBAC role grant, credential setup |
| **Zen-page agent configuration** | J3 | Provider / model / temperature / system-prompt / credential-ref UI |
| **Credential management** | J3 | Env-var → `Ens.Config.Credentials` → custom encrypted store |
| **Bookmark URL pattern** | J3 | `/csp/healthshare/<NS>/SessionAgent.EnsPortal.*.zen` |
| **Chat-history binding to session** | J1 | Inspection-agent history coupled to `Ens.MessageHeader.Purge` |
| **Test/CI surface** | J4 | Tool-call-roundtrip integration test as contract gate |
| **OSS contribution flow** | J4 | Clone → branch → PR → review → merge; MIT license; pure-ObjectScript hygiene rules |

## Innovation & Novel Patterns

This product's market positioning is *"fit, not moat"* — execution and IRIS-fit are the unfair advantage, not novelty. Even so, three architectural surfaces are genuinely novel within the IRIS Interoperability ecosystem and warrant explicit validation criteria so downstream architecture work treats them as designed-novel rather than well-understood.

### Detected Innovation Areas

1. **Pure-ObjectScript LLM agent with structured tool calling, on IRIS 2024.1+.** No prior art in the IRIS community at v1 ship time. AI Hub primitives will eventually fill this niche but are pre-release. The brief's Vision tier explicitly positions this product as a "reference implementation that other IRIS-domain agents are built on" (Production Health, Schema Discovery, HealthShare Migration Assistant). The pattern itself — agent loop + provider abstraction + tool registry + audit + RBAC, all in pure ObjectScript — is the novel artifact.

2. **Two-stage indexed-prefilter + body-inspection pattern for unindexed body-content search.** Standard Message Viewer search is single-pass against indexed columns or `Ens.SearchTableBase`-indexed body fields. This product extends search to *unindexed* body content via a bounded narrow-then-inspect pattern: lead WHERE with at least one indexed column + a default 24h `TimeCreated` window (max 720h), narrow to ≤50 candidates, then `InspectBodyCandidates(ids[], pattern)` opens each body via the inspection-agent's body-class dispatch ladder. No existing IRIS tool does this. The novelty is *making body-content search safe at production scale* — the bound is the innovation, not the search.

3. **Anthropic-canonical wire shape with mechanical adapter pattern.** A deliberate architectural inversion of the prevailing OpenAI-canonical convention in LLM-agent libraries. The justification: Anthropic's Messages API has the most structured shape — object-form tool args (vs. OpenAI's stringified JSON), native multi-block `content` array — so adapting *out* to less-structured shapes is mechanical, while the reverse is lossy. Result: adding a 5th provider is one new subclass plus one registry entry, no shared-infrastructure edits (per Journey 4's contract).

### Market Context & Competitive Landscape

The brief's competitive analysis stands; not repeating in full. Key context:

- **No purpose-built IRIS Interoperability AI tool exists.** General AIOps platforms (Datadog Bits, Dynatrace Davis, Splunk AI, IBM AIOps) are blind to Ensemble — IRIS produces no OTLP, the message-header schema is invisible to ingest pipelines, and the rule-log semantics don't translate. Boomi's Integration Advisor is design-time, not runtime. InterSystems' AI Hub is pre-release.
- **No prior art for two-stage body-content search in IRIS.** `Ens.SearchTableBase` is the existing extension surface; this product layers above it.
- **Anthropic-canonical adapter inversion is uncommon but not unique.** A small number of multi-provider agent libraries adopt this pattern; most default to OpenAI-canonical for historical reasons.

### Validation Approach

| Innovation | How we validate it works |
|---|---|
| Pure-OS LLM agent reference implementation | (1) Tool-call-roundtrip integration test on each provider against a recorded transcript; (2) ≥1 customer site adopts in production on-call (Success Criteria → Pilot adoption); (3) Community contributor adds a 5th provider via the documented contract (Journey 4) without shared-infra edits. |
| Two-stage body-content search | (1) Bounded-WHERE invariant enforced by static check in `SessionAgent.Tool.Search` base class — every search SQL must lead with ≥1 indexed column + a `TimeCreated` window; CI fails any tool that violates; (2) performance test against a synthetic 1M-message extent — search must complete inside the 90s per-call provider timeout cap with ≤50-candidate body inspection; (3) operator self-report during pilot — does it find what they're looking for, fast enough? |
| Anthropic-canonical adapter inversion | (1) Tool-call-roundtrip test exercises every provider through identical agent-loop input; (2) round-trip preserves tool args object→string→object across the OpenAI adapter without semantic loss; (3) Provider Portability outcome from Success Criteria — one subclass + one registry entry to add a 5th. |

### Risk Mitigation

| Risk | Mitigation / Fallback |
|---|---|
| Pure-OS LLM agent has no escape hatch when AI Hub goes GA | The two are not mutually exclusive — when AI Hub matures, `iris-session-agent` remains an option for older-IRIS deployments and an independent reference for the pattern. The brief's Vision tier already names this. |
| Two-stage body search is too slow on a real production extent | The bounded-WHERE invariant is the primary protection. Fallbacks: (1) tighten default time window from 24h → 1h on operator opt-in; (2) lower candidate cap from 50 → 20; (3) defer to v2 vector / semantic search path. The body-content search tool's interface is stable across these fallbacks — only the prefilter changes. |
| Anthropic-canonical inversion makes OpenAI-shaped providers awkward | OpenAI is the *first-shipping* provider per user priority — the adapter is exercised hardest from day one, not added late. If the inversion proves awkward in practice (e.g., a provider with a truly incompatible tool-call shape), the adapter pattern allows hosting a *second canonical wire* alongside Anthropic's. We do not expect this. |
| Two-stage body search creates audit-log volume problem | `SessionAgent.Audit.ToolCall` rows are FK-linked to chat history; chat-history sweep cascades. The same lifecycle that handles inspection-agent rows handles search rows; no separate plumbing. |

## Developer-Tool-Specific Requirements

### Project-Type Overview

`iris-session-agent` is a **developer-tool-shaped IPM module** with a runtime user-facing UI surface. This dual shape — package-installable artifact + operator-facing chat experience — splits the developer-tool requirements into two audiences:

- **Operators** install the package, configure it, and use the chat experience (covered in Journey 3 and Success Criteria → Technical Success).
- **Developers** (community contributors and the sibling `iris-execute-mcp-v2` project) extend the module via documented plugin contracts (covered in Journey 4 and Innovation → Anthropic-canonical adapter inversion).

This section consolidates the developer-facing surfaces into a single reference; narrative coverage already lives elsewhere in the PRD.

### Language Matrix

| Layer | Language | Notes |
|---|---|---|
| Runtime (server) | **ObjectScript only** | No `[Language = python]` in any shipped class. NFR-locked per project posture. |
| Front-end (browser) | **Vendored JavaScript** (`marked` ≥ 18.0.2 + `Prism.js` curated languages + `DOMPurify`) | Self-hosted at `/csp/static/iris-session-agent/`. ~45 KB gzipped, no CDN dependency. Lands in the Growth tier; MVP uses a simpler render path. |
| Build / test tooling (optional) | Python, shell | Test fixtures and CI helpers may use Python; no Python ships in the runtime artifact. |
| Configuration | Zen (server-rendered) + ObjectScript class definitions | Per-agent config Zen page (`SessionAgent.UI.AgentConfig`); class-level config persisted in `SessionAgent.Config.Agent`. |

### Installation Methods

- **Single distribution channel: IPM (`zpm`)** — `zpm install iris-session-agent` against any IRIS / IRIS for Health 2024.1+ instance.
- **Single ZPM module** with one `<Resource Name="SessionAgent.PKG"/>` resource and zero transitive Open Exchange dependencies.
- **No alternate channels** — no Docker-image pre-build (operators run their own IRIS), no `irispip`-installed dependencies. Project rule: `irispip install` is operator-executed, never invoked from a ZPM hook.
- **Operator prerequisites** documented in README §Operator Prerequisites (covered in Journey 3): Web Gateway "Server Response Timeout" raised from 60s → 300s; `%SessionAgent_ReadOnly` granted to operator user/role; LLM provider API key supplied via env-var (preferred) or `Ens.Config.Credentials` (secondary).

### API Surface (Developer-Facing Plugin Contracts)

Three documented plugin contracts:

| Contract | Plugin point | Purpose | Evidence elsewhere in PRD |
|---|---|---|---|
| **LLM Provider** | Subclass `SessionAgent.LLM.Provider` + register in `SessionAgent.LLM.Registry` | Add a 5th LLM provider (Cohere, AWS Bedrock, Vertex AI, etc.) | Journey 4 (Tomás); Innovation §Anthropic-canonical adapter; Success Criteria → Provider Portability |
| **Tool** | Subclass `SessionAgent.Tool.Base` + register in `Tool.Inspection.*` or `Tool.Search.*` | Add a custom tool to either agent (e.g., an organization-specific lookup like `lookup_clinic_by_msh3`) | Journey Requirements Summary (Test/CI surface row). v1 ships with built-in tools only; **public-extensibility guarantee is post-v1** — internal subclassing during v1 development is supported, public-API stability is not. |
| **MCP export** | Read-only consumer of the tool registry | Sibling `iris-execute-mcp-v2` wraps the registry into MCP `tools/list` + `tools/call` endpoints | Innovation §Detected Innovation Areas; Success Criteria → MCP-exportable; Vision tier |

**Plugin contract invariants** (hold across all three):

- **Pure tool dispatch**: `(toolName, jsonArgs) → jsonResult` with no `%session.Data` reads, no `%request` reads, no Zen state, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no ObjectScript exceptions as error signals.
- **Structured error envelope**: tool errors return `{isError: true, content: [{type: "text", text: "..."}]}` per MCP `tools/call` envelope.
- **Required parameters / methods on every tool**: `Parameter ToolName`, `Parameter Description`, `Parameter MutatesState As %Boolean = 0`, `ClassMethod GetInputSchema()`, `ClassMethod Invoke(pCallerCtx, pJsonArgs, Output pResult)`.
- **The `MutatesState=0` check is the dispatch policy gate** — read-only enforcement Layer 2.

### Code Examples Shipping in v1

| Example | Purpose | Location |
|---|---|---|
| **Reference LLM provider implementations** | Demonstrate the provider plugin contract end-to-end across four wire shapes | `SessionAgent.LLM.OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`, `OpenAICompatProvider` (Ollama / vLLM). Tomás-style 5th-provider work clones the closest match. |
| **Reference inspection tool** | Demonstrate `SessionAgent.Tool.Base` + `MutatesState=0` discipline + JSON schema generation | `SessionAgent.Tool.Inspection.SessionSummary` (simplest of the 13 inspection tools) |
| **Reference search tool with bounded WHERE** | Demonstrate the bounded-WHERE invariant for the Search Agent | `SessionAgent.Tool.Search.SearchByTime` (canonical lead-with-`TimeCreated`-window pattern) |
| **Seed vocabulary entries (~10)** | Demonstrate the user-vocabulary capture format and HL7 idiom seeding | `SessionAgent.Search.SeedVocabulary` |
| **Sample agent configuration rows** | Demonstrate Zen-page-saved config for the two agents | `SessionAgent.Config.Agent` rows created by Installer (one row per agent) |

### Migration Guide

**Not applicable in v1** — no prior version exists. A migration guide will land at the first breaking version bump.

### Implementation Considerations

- **No IDE integration ships in v1.** Standard IRIS development happens in Studio or the VSCode-ObjectScript extension; this product doesn't add a Studio plugin or VSCode language server. Operators of *any* IRIS-extension-active workspace should follow the user's global rule on toggling `objectscript.conn.active=false` during bulk document exports — that's an external concern not owned by this project.
- **Test/CI surface is a public deliverable.** Per Journey 4's contract acceptance gate, the tool-call-roundtrip integration test against each LLM provider mock is part of the supported developer experience. Community contributors run it before submitting a PR.
- **Documentation deliverables.** README (operator-prerequisite-anchored, with quickstart), this PRD (planning depth), the architecture document (technical depth), per-tool inline `///` doc comments, the brief / distillate / research docs (kept as planning-history reference). MIT `LICENSE` file lands at repo root in the v1 release commit.

### Skipped Sections (per project-type CSV)

| Skipped | Reason |
|---|---|
| `visual_design` | Embedded into existing IRIS Management Portal styling (Zen page subclasses inherit parent visual conventions); vendored Markdown rendering bundle uses Prism.js's bundled themes. No novel design system. |
| `store_compliance` | No app store distribution. Open Exchange listing requirements are publication metadata, not technical compliance — they don't shape product behavior. |

## Project Scoping & Phased Development

This product follows the brief's directive: **plan the full v1 scope in PRD / architecture / epics / stories; deliver it incrementally.** The MVP / Growth / Vision tiers are enumerated in §Product Scope; this section adds the strategic rationale, resource posture, and risk mitigation that drive the phased decision.

### MVP Strategy & Philosophy

**MVP approach: problem-solving MVP.** The minimum that makes operators say *"this is useful"* is the **operator's first delight moment** — typing *what happened?* into a Visual Trace tab on a real failed session and getting a coherent multi-surface explanation. That moment is reachable with a *single agent (Inspection)* on a *single LLM provider (OpenAI)* — second agent and three additional providers are committed v1 work but not load-bearing for first-delight validation.

**Why this MVP cut over alternatives:**

| Alternative MVP | Why rejected |
|---|---|
| **Both agents, OpenAI only** | Second agent needs vocabulary learning + bounded-WHERE + body-content-search infrastructure to be interesting. Adds ~3 epics of scope without changing first-delight validation (Inspection alone proves the cross-surface diagnosis value proposition). |
| **Single agent, all 4 providers** | Provider-switching is mechanical (one new subclass + registry entry per provider, per Innovation §Anthropic-canonical adapter). Adding 3 more providers in MVP delivers no new operator value over single-provider — they're a pre-validated multiplier. |
| **Inspection only, fewer tools** | Each of the 13 inspection tools maps to one of the six data surfaces or to a multi-surface correlation; cutting tools cuts the cross-surface promise. Tool count is the value proposition, not optional scope. |
| **No audit logging / no read-only in MVP** | Read-only enforcement is a *trust foundation*, not a feature — operators won't deploy to production without it. Cutting either re-introduces the scope at zero leverage during pilot. |

**MVP exit criteria** — the gate from MVP to Growth-tier work:

1. The pre-alpha demo-able OpenAI-powered Inspection Agent reaches an operator's hands (Success Criteria → "Pre-alpha demo-able milestone").
2. ≥1 operator self-reports a real diagnosis happening through the agent (validates the *fit* claim).
3. The audit log shows the agent dispatched all 13 tools at least once across real sessions (validates the cross-surface claim).

Once these gate, Growth-tier work proceeds: Search Agent, three additional providers, vocabulary learning, body-content search, vendored Markdown bundle, concurrent-tab safety.

### Resource Requirements

**Resourcing posture: single maintainer, hobby-project velocity.** The author owns implementation, review, release, support, and community-PR triage. Standard PRD-template assumptions about team-size, headcount, sprint capacity, and budget do not apply.

**Implications for scope:**

- **Scope cuts are the response to over-budget, not deadline pushes.** If the project consumes more time than the author can sustainably give, the response is to defer Growth-tier items (search agent, additional providers, vocabulary learning, vendored Markdown) — *not* to compromise on MVP quality, audit completeness, or the read-only invariant.
- **Community PRs are an accelerant, not a baseline assumption.** The plan does not depend on outside contributors arriving. If they do (Tomás-style 5th provider, novel tool contributions), they help. If they don't, the maintainer ships without them.
- **No date commitments anywhere.** Milestone gates (Epic 3 = MVP demo-able; Epic 7 = Inspection complete including chat-history lifecycle; Epic 10 = full v1 including Search Agent) drive release cadence; calendar time is whatever it takes. Epic numbers per [`epics.md`](epics.md) consolidated 10-epic v1 sequence.

### Phased Roadmap

**Phasing decision:** Phased delivery, three tiers, fully enumerated in §Product Scope (MVP / Growth Features completing v1 / Vision post-v1). Not duplicating tier contents here.

**Phase mapping to user journeys** (cross-reference to §User Journeys):

| Tier | Journeys validated | Validates |
|---|---|---|
| **MVP (Phase 1)** | J1 (Senior on-call), J3 (Operator install) | The *fit* claim and the *operator-can-deploy-it* claim. |
| **Growth (Phase 2 — completing v1)** | J2 (Junior + Search), J4 (Community contributor) | The *full-product* claim and the *plugin-contract* claim. |
| **Vision (post-v1)** | None of the v1 journeys; net-new journeys | Each Vision item produces its own journey when it lands. |

**Single-release alternative was considered and rejected.** Per user direction during PRD authoring (2026-05-02): *"I'm fine with [the MVP] cut, but we need to plan for the full scope... I want a full plan to get to the full scope, not just pre-alpha."* Phased is right; single-release would either bloat MVP into "full v1 before any release" (delaying first-delight feedback by months) or cut the brief's committed v1 scope.

### Risk Mitigation Strategy

**Technical risks:**

| Risk | Mitigation |
|---|---|
| LLM tool-calling reliability is too low on production-grade incidents | Provider portability is the hedge. Brief's BFCL signal puts Claude Opus 4.7 / Sonnet 4.5 ≥ GPT-5 / GPT-4o > Gemini 2.5/3 Pro. If OpenAI underperforms in pilot, operator switches to Anthropic with one config change. Tool-call-roundtrip integration test ensures all four providers are exercised. |
| Two-stage body-content search is too slow at production scale | Bounded-WHERE invariant + ≤50 candidate cap + 24h default time window are the primary protection. Performance test against synthetic 1M-message extent gates Growth-tier ship (Innovation §Validation). Three documented fallback levers (tighter window, lower cap, defer to vector path). |
| Web Gateway 60s timeout cliff bites operators who skip the README | README §Operator Prerequisites is a structural deliverable (Journey 3); per-call provider timeout cap of 90s ensures gateway timeout fires *with a clear error*, not silent stream truncation. Any timeout-cliff event surfaces as an audit-log row visible to the maintainer. |
| Anthropic-canonical adapter inversion proves awkward in production | OpenAI ships *first* (per user priority) so the inversion is exercised hardest from day one. If genuinely awkward, a second canonical wire alongside Anthropic is a documented fallback (Innovation §Risk Mitigation). |
| `Ens.Config.Credentials` requires Ensemble enabled in the namespace | Documented in distillate Open Questions; verified true for HSCUSTOM and any Interop NS. Non-Interop deployments fall back to env-var path. README §Operator Prerequisites covers both. |
| `%Library.IRISWallet` doesn't exist in 2024.1 | Already mitigated — secrets ladder is env-var → `Ens.Config.Credentials` → custom encrypted store. Wallet deferred until 2026.1 floor (post-v1 if ever). |

**Market risks:**

| Risk | Mitigation |
|---|---|
| AI Hub goes GA earlier than expected and "steals the niche" | Per Vision §Long-tail community option — when AI Hub matures, this product remains the offering for older-IRIS deployments and a teaching example for the pure-OS-agent pattern. Brief explicitly downplays "ahead-of-AI-Hub" framing for this risk; the product's positioning never depends on AI Hub's absence. |
| Operators don't install OSS tools without commercial-vendor backing | One pilot is enough to validate (Success Criteria → ≥1 customer site). The brief is honest: *one genuinely-using customer beats a hundred curious downloads*. Failure mode is "stays a personal-use project" — author still gets value, no sunk-cost crisis. |
| Healthcare customers can't deploy due to PHI concerns | Namespace-segregation is the v1 boundary (Project Classification → Domain). PHI redaction is explicit Vision-tier work. Customers in non-PHI namespaces are unaffected; PHI-touching customers wait for Vision-tier or manage PHI through their existing namespace boundaries. |
| LLM API costs scare operators off | Provider portability includes Ollama / vLLM (zero per-token cost on self-hosted). Pilot operators can validate value with managed providers, then migrate to self-hosted if budget is a constraint. |

**Resource risks:**

| Risk | Mitigation |
|---|---|
| Author becomes unavailable mid-build | MIT license + open-source from day one means anyone can fork, complete, and continue. The PRD, architecture, and epics document are the planning artifacts that let a successor pick up. Single-author-loss is a community-takeover risk, not a project-death risk. |
| Single-author maintenance load grows unsustainably post-release | First response: scope cuts (defer Growth-tier items to "won't ship"). Second response: community-maintainer hand-off via OEX / GitHub. Third response: project archive. None compromise existing operator deployments — MIT license + IPM version-pinning let operators run their installed version indefinitely. |
| Community contributions don't materialize | The plan doesn't depend on them (see Resource Requirements). If Tomás-style PRs never arrive, the four bundled providers cover the documented roadmap. |
| Author runs out of motivation | Brief explicitly names the success metric: *"the author's satisfaction comes from operators getting their evenings back."* If even one operator reports the saved-25-minutes outcome, the project succeeded; further work is bonus. |

## Functional Requirements

This section is the **binding capability contract** for the product. Every feature in v1 must trace back to one of the FRs here; any feature not listed will not exist unless explicitly added. UX, architecture, and epic breakdown will support only what's enumerated below.

**Actors:**

- **Operator** — generic Mgmt Portal user with Interoperability access. Covers senior on-call (Marisol), junior engineer (Devin), and ops-lead (Aishah).
- **Operator-Admin** — privileged operator who installs, configures, and manages credentials.
- **Community Contributor** — IRIS engineer extending the product (Tomás-style).
- **MCP Consumer** — external project that wraps the tool registry as MCP `tools/list` + `tools/call` (sibling `iris-execute-mcp-v2`).
- **System** — automated background processes (sweeper, audit logger, dispatch policy gate, agent loop).

### Session Inspection

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

### Message Search

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

### LLM Provider Framework

- **FR25**: System can dispatch agent turns through any of four bundled LLM providers: OpenAI, Anthropic, Google Gemini, OpenAI-compatible (Ollama / vLLM / any compatible endpoint).
- **FR26**: Operator-Admin can configure each agent independently to use any bundled provider with its own model selection, max-tokens, temperature, and system-prompt override.
- **FR27**: System represents tool-calling traffic in an Anthropic-canonical wire shape internally; per-provider adapters mechanically convert to/from each provider's native shape.
- **FR28**: Community Contributor can add a fifth (or further) LLM provider by implementing one new subclass of `SessionAgent.LLM.Provider` (with `MessageAdapter` and `ToolDefAdapter`) plus one entry in the registry, with no edits required to shared infrastructure (`AgentLoop`, `ToolRegistry`, `Tool.Inspection.*`, `Tool.Search.*`).
- **FR29**: System enforces a per-call LLM provider timeout cap of 90s; timeouts surface as audit-loggable error events.
- **FR30**: System uses Anthropic prompt-caching of the `system + tools` prefix when the active provider supports prompt caching; user-specific vocabulary digests are placed outside the cached prefix to preserve cache hit rate.

### Read-Only Enforcement & Audit

- **FR31**: System enforces read-only access to `Ens.*` data through three independent layers: code discipline (no mutation calls in tool implementations), dispatch policy gate (`MutatesState=0` check on every tool dispatch), and IRIS RBAC role `%SessionAgent_ReadOnly` (SELECT-only grants).
- **FR32**: System logs every LLM round-trip to a persistent audit class (`SessionAgent.Audit.LlmCall`) including provider, model, message count, token counts, latency, and conversation reference.
- **FR33**: System logs every tool dispatch to a persistent audit class (`SessionAgent.Audit.ToolCall`) including tool name, arguments, result/error, latency, and conversation reference.
- **FR34**: Audit rows are foreign-key linked to the chat-history row that contained the round-trip / dispatch.
- **FR35**: Operator-Admin can review audit rows via standard IRIS SQL access (no separate audit UI ships in v1).
- **FR36**: Tool implementations cannot mutate `Ens.*` state; any tool that attempts mutation is rejected by the dispatch policy gate before execution.
- **FR37**: Tool implementations return errors as structured `{isError: true, content: [{type: "text", text: "..."}]}` envelopes, not as ObjectScript exceptions.

### Configuration & Credentials

- **FR38**: Operator-Admin can configure per-agent settings via a dedicated Zen page (`SessionAgent.UI.AgentConfig`).
- **FR39**: System supports independent configuration for each of the two agents (different provider / model / temperature / system-prompt / credential-ref per agent).
- **FR40**: System resolves LLM provider API keys via a documented ladder: environment variable (`$SYSTEM.Util.GetEnviron`) preferred → `Ens.Config.Credentials` named entry → custom encrypted persistent store (`$System.Encryption.AESGCMEncrypt`) as last resort.
- **FR41**: System never persists API keys in agent configuration rows; configuration stores credential *references* only.
- **FR42**: Operator-Admin can set the maximum response token cap, temperature, and a custom system-prompt override per agent.

### Chat Lifecycle

- **FR43**: Inspection Agent chat history is keyed on `(agentName, irisSessionId, portalUser)`; Search Agent chat history is keyed on `(agentName, searchSessionKey, portalUser)` where `searchSessionKey` is a registry-assigned GUID.
- **FR44**: System provides a daily sweep task that removes Inspection Agent chat-history rows whose underlying `Ens.MessageHeader` session has been purged via `Ens.MessageHeader.Purge()` (no orphan history).
- **FR45**: System provides a TTL-based sweep task for Search Agent chat history (default 30 days, configurable).
- **FR46**: Two browser tabs for the same operator targeting the same chat-history row serialize their turns via an exclusive lock (`%OpenId(id, 4)`); concurrent turns do not corrupt history.
- **FR47**: Operator who arrives at the Inspection Agent via a Search Agent click-through sees a "from search" context indicator and can ask follow-up questions that build on the search context.

### Installation & Operator Surface

- **FR48**: Operator-Admin can install the entire product via a single command: `zpm install iris-session-agent` against any IRIS / IRIS for Health 2024.1+ instance.
- **FR49**: Installation succeeds on IRIS instances regardless of embedded Python availability (no `[Language = python]` in any shipped class, no Python at install or runtime).
- **FR50**: Installation creates the `%SessionAgent_ReadOnly` RBAC role with SELECT-only grants on `Ens.*` tables.
- **FR51**: Installation creates Mgmt Portal bookmarks for both agent surfaces (`/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen` and `/csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen`).
- **FR52**: README documents operator prerequisites as a structural section: Web Gateway "Server Response Timeout" raised from 60s → 300s, RBAC role grant, LLM provider API key supply (env-var or `Ens.Config.Credentials`).
- **FR53**: System ships with no transitive Open Exchange dependencies; everything required runs from the single `<Resource Name="SessionAgent.PKG"/>` resource.
- **FR54**: System ships with a vendored client-side Markdown rendering bundle (`marked`, `Prism.js`, `DOMPurify`) self-hosted at `/csp/static/iris-session-agent/`; no CDN dependency. (Growth-tier — MVP can use a simpler render path.)

### Developer Extensibility

- **FR55**: System exposes a tool registry with a pure dispatch contract: `(toolName, jsonArgs) → jsonResult` with no `%session.Data` reads, no `%request` reads, no Zen state coupling, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals.
- **FR56**: Every tool declares: `Parameter ToolName`, `Parameter Description`, `Parameter MutatesState As %Boolean = 0`, `ClassMethod GetInputSchema()`, `ClassMethod Invoke(pCallerCtx, pJsonArgs, Output pResult)`.
- **FR57**: MCP Consumer can introspect the tool registry to enumerate available tools with their JSON schemas, and dispatch any tool by name with a JSON arguments payload — without `iris-session-agent` itself shipping MCP transport.
- **FR58**: Community Contributor can subclass `SessionAgent.Tool.Base` to add custom tools; v1 ships with built-in tools only and **public-API stability of the Tool plugin contract is post-v1**.
- **FR59**: System ships a tool-call-roundtrip integration test that exercises every bundled provider against every bundled tool, validating the agent loop, adapter conversions, and dispatch policy gate.

## Non-Functional Requirements

NFRs specify HOW WELL the system must perform. This list is selective — only categories that actually apply are included. Each NFR is testable; where the test is structural (not a number), the test mechanism is named.

### Performance

- **NFR-P1 (LLM call cliff)**: Each LLM call completes within 90s or surfaces as a structured timeout error. The 90s per-call provider timeout cap sits *below* the 300s Web Gateway timeout that operators are required to configure (FR52), so timeouts are caught by the agent and reported cleanly rather than propagating to the gateway as silent stream truncation. **Test:** integration test forces a 91s mock provider response; agent returns structured timeout-error envelope.
- **NFR-P2 (Search-agent query bound)**: Every Search Agent SQL query completes within the 90s LLM-call budget against a production-scale `Ens.MessageHeader` extent of ≥ 1,000,000 rows when the bounded-WHERE invariant (FR19) holds. **Test:** synthetic-1M-row benchmark in CI gates Growth-tier ship (Innovation §Validation Approach).
- **NFR-P3 (Two-stage body search bound)**: Body-content search (FR18) opens at most 50 candidate bodies per query and completes the candidate inspection pass within the 90s cap on operator-grade hardware. **Test:** synthetic-extent benchmark validates 50-body inspection latency.
- **NFR-P4 (Concurrent-tab serialization)**: Two browser tabs of the same operator targeting the same chat-history row do not corrupt history under concurrent submit. **Test:** integration test fires two simultaneous submit requests against the same row; both turns complete via the `%OpenId(id, 4)` lock (FR46), or one is rejected with a structured "another turn is in progress" error.
- **NFR-P5 (Time-to-resolution)**: On the curated set of common diagnostic patterns (failed-message triage, "where did this go?", "what did the rules decide?"), the agent's response replaces 5 minutes of operator tab-switching with ≤ 1 minute of conversation. **Test:** operator self-report during pilot (Success Criteria → Time savings); not a CI-measurable test.
- **NFR-P6 (Anthropic prompt-cache hit rate)**: For providers with prompt caching enabled (currently Anthropic), the `system + tools` prefix is stable across consecutive turns within a chat session, achieving cache hits on the prefix. User vocabulary digest is in the *non-cached* user-message segment. **Test:** integration test asserts cache-control breakpoint placement; cache-hit metric reported in audit row.

### Security

- **NFR-S1 (Read-only invariant)**: No code path inside the agent can mutate `Ens.*` data. Enforced by three independent layers (FR31). **Test:** (1) static — `MutatesState=0` declared on every `SessionAgent.Tool.*` class, CI fails any tool that omits or sets to 1; (2) runtime — dispatch policy gate rejects any tool with `MutatesState=1`; (3) RBAC — installation creates `%SessionAgent_ReadOnly` with SELECT-only grants on `Ens.*` (FR50), validated by attempting a `DELETE` and observing the privilege failure.
- **NFR-S2 (Credential confinement)**: API keys are never persisted in `SessionAgent.Config.Agent` rows. Configuration stores credential *references* only (FR41). **Test:** schema-level — `Config.Agent` has no `ApiKey` property, only `CredentialRef`. Code review enforced.
- **NFR-S3 (Credential resolution hygiene)**: API key resolution uses the documented ladder env-var → `Ens.Config.Credentials` → custom encrypted store (FR40), *never* logs the resolved key value, and *never* embeds the key in audit-log rows. **Test:** audit-log row inspection validates no key material; redaction unit test covers credential-string detection.
- **NFR-S4 (Audit completeness)**: Every LLM round-trip and every tool dispatch is logged (FR32-34). 100% completeness — no skipped paths. **Test:** integration test compares `count(SessionAgent.Audit.LlmCall)` and `count(SessionAgent.Audit.ToolCall)` against agent-loop instrumentation counts; equality required.
- **NFR-S5 (Public-OSS posture)**: All planning artifacts (PRD, brief, distillate, research, architecture) are authored knowing they will be publicly visible in the OSS repo. No internal-confidential framing. **Test:** documentation review gate (manual) before each release tag.
- **NFR-S6 (Tool dispatch purity)**: Tool implementations cannot read `%session.Data`, `%request`, Zen state, or `%CSP.Response`; cannot perform `$NAMESPACE` side effects; cannot signal errors via ObjectScript exceptions (FR55). **Test:** lint check on the `SessionAgent.Tool.*` package — code review gate; tool-call-roundtrip integration test runs each tool in a clean dispatcher context (no `%session.Data` populated) to validate purity.

### Reliability

- **NFR-R1 (Operator-deployment safety)**: Operator can deploy the package to a production namespace with confidence that it cannot break production data, even under operator misuse or malicious LLM output. Guaranteed by NFR-S1's three-layer read-only enforcement. **Test:** structurally enforced — see NFR-S1.
- **NFR-R2 (Chat-history lifecycle integrity)**: When `Ens.MessageHeader.Purge()` removes session N, the daily sweep removes any orphaned `SessionAgent.Chat.History` row(s) for session N (FR44). No orphan accumulation under sustained purge cycles. **Test:** integration test simulates 1,000 sessions inserted, conversations attached, purge run, sweep run; asserts zero orphans remain.
- **NFR-R3 (Search-history TTL)**: Search Agent chat history older than the configured TTL (default 30 days) is removed by sweep (FR45). **Test:** integration test fast-forwards system clock and validates sweep behavior.
- **NFR-R4 (Provider failure isolation)**: When the active LLM provider returns an error (timeout, rate limit, malformed response), the agent reports the failure as a tool-error envelope to the operator and does not corrupt chat history or audit log. **Test:** integration test injects each error class into a mock provider and validates clean failure surface.
- **NFR-R5 (IPM idempotent reinstall)**: `zpm install iris-session-agent` is idempotent — repeated installs do not duplicate RBAC role grants, bookmark entries, or audit-log schema migrations. **Test:** install twice in CI, validate no duplicate side effects.

### Scalability

The product is **operator-scale, not enterprise-multi-tenant**. Each agent serves one operator at a time inside one IRIS namespace; concurrent multi-operator usage is supported by stock IRIS / CSP threading, not by coordination logic in the agent itself.

- **NFR-SC1 (Production extent scale)**: Search Agent queries remain bounded under NFR-P2 even on operator-grade IRIS instances with `Ens.MessageHeader` extents up to 10,000,000 rows. The bounded-WHERE invariant (FR19) and time-window cap (24h default, 720h max) are the structural mechanism. **Test:** synthetic-extent benchmark at 10M rows.
- **NFR-SC2 (Concurrent operator scale)**: Stock IRIS Web Gateway and CSP threading handle concurrent operators. Per-row chat-history serialization is per-operator-per-tab (FR46), not global.
- **NFR-SC3 (No cross-instance coordination)**: Mirror-replica or cross-instance coordination is **not** in v1. Each IRIS instance runs an independent agent. Cross-instance is a Vision-tier item.
- **NFR-SC4 (Audit-log volume)**: Audit log volume is bounded by chat-history sweep cascading. Sustained 24/7 operator usage stays within IRIS-default journal sizing on operator-grade hardware. **Test:** sustained-load benchmark estimates audit volume per operator-month and validates against journal-rotation defaults.

### Compatibility & Portability

- **NFR-C1 (IRIS version floor)**: Product installs and runs on IRIS / IRIS for Health **2024.1+**. Every API, class, and parameter referenced in the codebase is verified available in 2024.1. Newer-version optimizations (e.g., `%Library.IRISWallet`, `%AI.*` primitives) are explicitly excluded. **Test:** install + smoke-test on a clean 2024.1 instance gates each release.
- **NFR-C2 (Pure ObjectScript runtime)**: No `[Language = python]` method exists in any shipped class under `SessionAgent.*`. Build-time tooling and test fixtures may use Python; the runtime artifact does not require embedded Python. **Test:** static check — `grep -r "Language = python" src/SessionAgent/` returns zero matches; CI fails if matched.
- **NFR-C3 (Python-less install success)**: `zpm install iris-session-agent` succeeds on IRIS instances with embedded Python disabled or unavailable (FR49). **Test:** release-gate CI on a Python-less IRIS image when image becomes available; manual verification on a Python-less instance until then.
- **NFR-C4 (No transitive dependencies)**: ZPM module has zero transitive Open Exchange dependencies (FR53). **Test:** `module.xml` dependency review — single `<Resource>` element; no `<Dependency>` elements other than IRIS / Ensemble core.
- **NFR-C5 (No CDN / offline-installable)**: All client-side assets (Markdown rendering bundle, Prism.js themes) are self-hosted at `/csp/static/iris-session-agent/`. No CDN fetches at runtime. Operators behind air-gapped firewalls can install and run without external network access (other than to their LLM provider, configured per their network policy). **Test:** static check — no `https://cdn.*` references in shipped CSP files.
- **NFR-C6 (Browser support)**: Operator-facing chat UI works in evergreen browsers (latest two versions of Chrome, Firefox, Safari, Edge). No legacy IE support. **Test:** README quickstart documents support matrix; manual smoke test per release.

### Operability & Maintainability

- **NFR-O1 (Operator self-service install)**: Operator can install, configure, and verify the product in under 30 minutes without contacting the maintainer. **Test:** Journey 3 (Aishah's 18-minute walkthrough) is the lower bound; pilot-operator README walkthrough validates.
- **NFR-O2 (Hot config change)**: Operator-Admin can change LLM provider, model, temperature, or system prompt and see the change effective on the next agent turn without restarting IRIS. **Test:** integration test verifies config-row read on each turn.
- **NFR-O3 (Audit log review by SQL)**: Operator-Admin can answer all audit questions ("what tools did the agent call yesterday?", "what were the errors?", "how many tokens did we spend?") via standard IRIS SQL against `SessionAgent.Audit.*` (FR35). No separate audit UI ships in v1.
- **NFR-O4 (Single-maintainer triage)**: Issues, PRs, and security reports surface through standard GitHub workflows. The maintainer triages within timelines compatible with hobby-project velocity (no SLA committed). MIT license + IPM version-pinning let operators run their installed version indefinitely if maintenance pauses (Risk Mitigation §Resource).
- **NFR-O5 (Documentation deliverables on every release)**: README, this PRD, the architecture document, per-tool inline doc comments, and the brief / distillate / research planning artifacts are kept current with each release tag. **Test:** release-gate manual review — README references match the shipping version's behavior; PRD frontmatter `stepsCompleted` reflects the document's actual state.

### Accessibility

- **NFR-A1 (Inherited Mgmt Portal accessibility)**: The agent's UI is embedded as Zen pages subclassed from `EnsPortal.VisualTrace` and `EnsPortal.MessageViewer`. The chat panel inherits whatever accessibility characteristics the IRIS Mgmt Portal's Zen framework provides. The product makes **no additional accessibility commitments** beyond inherited behavior. *Reason:* this is a developer tool used by integration engineers in their daily Mgmt Portal workflow; it doesn't add a parallel UI surface that would warrant independent WCAG conformance work. If the parent portal upgrades its accessibility characteristics, this product's UI inherits the upgrade automatically.

### Categories Deliberately Excluded

- **Localization / Internationalization**: Operator-facing UI is English-only in v1. Brief and distillate make no commitment to multi-language. No i18n scaffolding ships.
- **Compliance certifications**: No certifications (SOC2, HIPAA, PCI-DSS, FedRAMP, ISO 27001) are claimed. Operators deploying into compliance-bound environments handle those obligations themselves; the agent's read-only invariant + audit logging supports their compliance posture but doesn't create one.
- **Disaster recovery / backup commitments**: Chat history and audit log are persisted in the IRIS namespace. Operator's existing IRIS journal + database backup procedures cover them the same way they cover everything else. No separate DR commitment.
- **Service-level agreement**: This is a hobby-project OSS module. No SLA is offered (Risk Mitigation §Resource).
