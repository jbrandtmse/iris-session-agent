# iris-session-agent

> [!WARNING]
> **Under construction — no code has shipped yet.**
>
> This project is in active planning. The full v1 scope, architecture, UX, and 64-story breakdown have been authored as BMAD planning artifacts (linked below); implementation begins with [Epic 1, Story 1.1](_bmad-output/planning-artifacts/epics.md). Pre-alpha distribution starts at end of Epic 3 (first-delight demo) and Epic 4 (MVP-complete).

An open-source InterSystems IRIS module that adds an AI assistant chat experience to the Interoperability operator's existing Management Portal. Two agents share infrastructure inside one IPM-installable package and run on **IRIS / IRIS for Health 2024.1+** in pure ObjectScript — no embedded Python in the runtime path, no AI Hub dependency.

> *"Chatting with your Interoperability Session to really understand what happened — and finding the right session by asking."*

## Operator Prerequisites

Before installing this module, complete the following on your IRIS instance. Most operators finish all seven steps in under 30 minutes. Each step is independent — you can do them in any order, but the install will fail or behave unexpectedly until they are all in place.

### 1. Supported IRIS versions

IRIS / IRIS for Health **2024.1 or later**. The agent runtime is pure ObjectScript; no embedded Python is required on the IRIS host.

### 2. Web Gateway timeout

The Web Gateway's default **"Server Response Timeout"** on a fresh IRIS 2024.1+ install is **`60` seconds** (verified on IRIS for Windows 2025.1 — see [Story 1.2 Task-0 probe](_bmad-output/implementation-artifacts/1-2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites.md#task-0-output) for the live capture). LLM-call latencies often sit in the 30–90s band, and an agent turn typically chains 2–3 tool calls plus one LLM round-trip — the 60s default kills these mid-stream. **Raise it to `300` seconds before installing.**

Navigate to the Web Gateway management page (typically `http://<host>/csp/bin/Systems/Module.cxw`) and follow this path:

```
Web Gateway management page
  → Login (CSPSystem account)
  → Configuration  (left-nav section)
  → Default Parameters
  → "Connections to InterSystems IRIS" group
  → Server Response Timeout:  60   →  change to  →  300
  → Save Configuration
```

The 300s value gives a 90s per-call cap × 3-tool-call agent turn comfortable headroom — see [PRD NFR-P1](_bmad-output/planning-artifacts/prd.md) and the [architecture timeout-cascade rationale at architecture.md line 1131](_bmad-output/planning-artifacts/architecture.md) (Web Gateway 300s prereq ↔ 90s per-call cap ↔ max-iter 10).

### 3. RBAC

The module installer creates the **`SessionAgent_ReadOnly`** role automatically with `SELECT`-only grants on `Ens.*` tables (this role install ships in [Epic 1 Story 1.4](_bmad-output/planning-artifacts/epics.md)). After install completes, assign this role to the IRIS user that the portal user maps to (typically the same user — verify via Security Management).

### 4. Package mapping

Map `SessionAgent.*` from `HSCUSTOMCODE` to your interoperability namespaces (or `%ALL`):

```
Management Portal
  → System Administration → Configuration → Namespaces
  → <target NS> → Package Mappings → Add: SessionAgent.*  ←  HSCUSTOMCODE
```

### 5. API key for the LLM provider

Pick **one** of the two delivery mechanisms:

- **Environment variable (preferred for container deployments):** Set `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY` / `GOOGLE_API_KEY`) as a process environment variable visible to the IRIS process. Container deployments typically inject these via Docker / Kubernetes secrets.
- **`Ens.Config.Credentials` row (traditional on-prem installs):** Create a credentials row with `SystemName='openai-prod'` (or any name you prefer), `Username='apikey'`, `Password='<your-key>'`. Then point `SessionAgent.Config.Agent.CredentialName` at that name.

API keys are **never** stored inside `SessionAgent.Config.Agent` itself.

### 6. Bookmark URLs

After install, both Management Portal entry points are bookmarkable. **Use the URL pattern that matches your IRIS deployment style** — HealthShare-based deployments include the `/healthshare/` segment; plain IRIS deployments do not:

- **HealthShare deployments:**
  - `/csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen` *(Search Agent entry — natural-language session search)*
  - `/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen` *(Inspection Agent — chat about a specific session)*
- **Plain IRIS deployments:**
  - `/csp/<NS>/SessionAgent.EnsPortal.MessageViewer.zen`
  - `/csp/<NS>/SessionAgent.EnsPortal.VisualTrace.zen`

The Search Agent path is for the operator's "find the session I care about" entry; the Visual Trace path opens the Inspection Agent on a specific session that the operator already has selected.

### 7. Daily purge task

The installer schedules `SessionAgent.Task.PurgeOrphanedChatHistory` to run daily at 02:00 UTC (this task ships in [Epic 7 Story 7.2](_bmad-output/planning-artifacts/epics.md)). Verify it's enabled in **Task Manager** after install. The task removes chat-history rows whose linked `Ens.MessageHeader` session has been purged, so no orphaned conversations accumulate.

## What it does

An Ensemble session leaves a trace across six disconnected data surfaces — `Ens.MessageHeader`, dynamically-typed message bodies, `Ens.SearchTableBase` subclass extents (e.g., `EnsLib.HL7.SearchTable`), `Ens.Util.Log`, `Ens.Rule.Log`, and BP runtime state in `Ens.BP.Context` / `Ens.BP.Thread`. Operators reconstruct the cross-surface picture in their heads on every incident, starting from scratch.

This module embeds two AI agents directly in the surfaces operators already use:

- **Session Inspection Agent** — a chat tab on a custom subclass of `EnsPortal.VisualTrace`. Reads the six session-trace surfaces in parallel via 13 disciplined tool calls and answers questions like *"what happened?"* in plain English with citations back to the underlying rule-log / event-log / message-headers rows.
- **Message Search Agent** — a chat tab on a custom subclass of `EnsPortal.MessageViewer`. Helps operators find sessions by natural-language query (*"find me failed admits from the last hour"*) using 8 indexed-access tools + a two-stage body-content search (≤50 candidates) + per-user vocabulary learning that captures aliases on click-through.

**Design properties** that drive the v1 architecture:

- **Read-only by structural enforcement.** Three independent layers — code discipline, dispatch policy gate (`MutatesState=0` check on every tool call), and IRIS RBAC role `SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` tables — make it operationally impossible for the agent to mutate production data.
- **Audit logging at FK-linked granularity.** Every LLM round-trip writes an `Audit.LlmCall` row; every tool dispatch writes an `Audit.ToolCall` row; both are foreign-key linked to the chat-history row. Reviewable via standard IRIS SQL — no separate audit UI.
- **Provider portability.** Four bundled LLM providers (OpenAI, Anthropic, Google Gemini, OpenAI-compatible for Ollama / vLLM / any compatible endpoint) sit behind an Anthropic-canonical wire shape. Adding a 5th provider is one new subclass + one registry entry, no shared-infrastructure edits.
- **MCP-exportable tool registry.** The tool dispatch contract `(toolName, jsonArgs) → jsonResult` stays MCP-friendly with no `%session.Data` reads, no Zen state coupling, no exceptions as error signals. MCP serving itself is delegated to the sibling [`iris-execute-mcp-v2`](https://github.com/jbrandtmse/iris-execute-mcp-v2) project.
- **Lifecycle-coupled chat history.** When `Ens.MessageHeader.Purge()` removes a session, a daily sweep removes the orphaned chat-history rows so no stale conversations accumulate.

## Status

Currently in **Phase 0 — Planning Complete, Implementation Not Started**.

| Stage | Status | Artifact |
|---|---|---|
| Product Brief | Complete | [product-brief-iris-session-agent.md](_bmad-output/planning-artifacts/product-brief-iris-session-agent.md) |
| PRD (59 FRs / 33 NFRs) | Complete | [prd.md](_bmad-output/planning-artifacts/prd.md) |
| Architecture (10 calibration decisions, ~50-class structure) | Complete | [architecture.md](_bmad-output/planning-artifacts/architecture.md) |
| UX Design (30 UX-DRs, 11 components) | Complete | [ux-design-specification.md](_bmad-output/planning-artifacts/ux-design-specification.md) |
| Epics & Stories (10 epics, 64 stories) | Complete | [epics.md](_bmad-output/planning-artifacts/epics.md) |
| Implementation Readiness Assessment | Complete — READY | [implementation-readiness-report-2026-05-02.md](_bmad-output/planning-artifacts/implementation-readiness-report-2026-05-02.md) |
| Epic 1 (Project Foundation) | Not started | — |

## Development Plan

The v1 scope is delivered across 10 user-value-first epics. Each epic delivers a meaningful operator outcome and stands alone (later epics build on earlier ones; earlier epics don't depend on later ones). Three back-end-only epics (2, 8, 9) explicitly use a "maintainer checkpoint" framing — the maintainer validates correctness via `%UnitTest` before the operator-facing UI ships in the following epic.

### MVP tier (Epics 1–4)

The minimum that produces the operator's first delight moment — typing *"what happened?"* into a Visual Trace tab on a real failed session and getting a coherent multi-surface explanation. **Single agent (Inspection), single provider (OpenAI).**

- **Epic 1 — Project Foundation & Installable Package** *(7 stories)*. `zpm install iris-session-agent` succeeds on IRIS 2024.1+ (Python-less); creates `SessionAgent_ReadOnly` RBAC role; pre-registers four audit event types; prints both Mgmt Portal bookmark URLs (HealthShare + plain-IRIS); README operator-prerequisites is structural.
- **Epic 2 — Inspection Agent Backend Plumbing** *(12 stories — maintainer checkpoint)*. Provider abstraction, tool registry + dispatch policy gate, `AgentLoop` with iteration cap + 90s per-call timeout, `Chat.History` with `%OpenId(id, 4)` concurrent-tab serialization, audit ledger, three example tools, end-to-end smoke test against OpenAI mock.
- **Epic 3 — Inspection Agent UI MVP Demo-able** *(7 stories)*. Custom `EnsPortal.VisualTrace` subclass + chat panel + citation chips wired into parent's `selectItem`/`updateTabs` API. **PRD MVP first-delight gate (Story 3.7).**
- **Epic 4 — Inspection Agent Full Tool Catalogue** *(7 stories)*. Remaining 10 inspection tools (event log, rule log, BP introspection trio, body-class dispatch ladder, super-session join, search-table pivot, `%Status` decoder). **PRD MVP-complete gate (Story 4.7).**

### Growth tier (Epics 5–10) — completing v1

- **Epic 5 — Multi-Provider Support** *(4 stories)*. Anthropic ships first (validates canonical-wire inversion), then Gemini, then OpenAI-compatible (Ollama / vLLM). Tool-call-roundtrip integration test exercises every provider × every tool.
- **Epic 6 — Per-Agent Configuration UI** *(3 stories)*. `SessionAgent.UI.AgentConfig.zen` Zen page; hot config change applies on next agent turn without IRIS restart.
- **Epic 7 — Inspection Chat-History Lifecycle** *(3 stories)*. Daily sweep removes orphaned Inspection chat-history when underlying Ens session is purged; 1,000-session integration test.
- **Epic 8 — Search Agent Foundation** *(7 stories — maintainer checkpoint)*. 8 indexed-access search tools + two-stage body-content search + `vocab_lookup` utility + bounded-WHERE invariant test + vocabulary persistence schemas + ~10 HL7-idiom seed templates.
- **Epic 9 — Search Agent Vocabulary Learning** *(5 stories — maintainer checkpoint)*. Per-user vocabulary capture via `RecordSuccess` / `RecordFailure` with confidence smoothing; recursion-safe `%OnAfterSave`; vocabulary-digest assembly + first-user-message prefix injection (preserves Anthropic prompt-cache).
- **Epic 10 — Search Agent UI Embed, Hand-off & TTL Sweep** *(9 stories)*. Custom `EnsPortal.MessageViewer` subclass + click-through hand-off to Inspection ("from search" stripe) + concurrent-tab banner + TTL sweep (30d default) + vendored Markdown bundle (`marked` + `Prism.js` + `DOMPurify`) at `/csp/static/iris-session-agent/`. **v1 SCOPE COMPLETE.**

### Vision tier (post-v1, deferred)

MCP serving (delegated to sibling project), vector / semantic body-content search, PHI redaction architecture, cross-namespace operation, streaming responses, LLM-extracted alias generation, cross-user `NamespaceVocabulary` baseline population, stand-alone terminal REPL. See [PRD §"Vision (Future, post-v1)"](_bmad-output/planning-artifacts/prd.md) for full enumeration.

## Planning Artifacts (BMAD)

All planning artifacts live under [`_bmad-output/planning-artifacts/`](_bmad-output/planning-artifacts/) and are checked into the repo as the audit trail for v1 design decisions.

### Primary documents

- **[Product Brief](_bmad-output/planning-artifacts/product-brief-iris-session-agent.md)** — vision-level input. Six-surface problem statement, primary users, posture (single-author hobby project, MIT, no commercial motion).
- **[Product Brief Distillate](_bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md)** — LLM-optimized condensed reference of the brief.
- **[Product Requirements Document (PRD)](_bmad-output/planning-artifacts/prd.md)** — 59 functional requirements across 8 capability areas + 33 non-functional requirements across 7 categories. Locks the binding capability contract for v1.
- **[Architecture Decision Document](_bmad-output/planning-artifacts/architecture.md)** — 10 calibration decisions, ~50-class structure, six-Topic decision tree, all FR/NFR coverage traced.
- **[UX Design Specification](_bmad-output/planning-artifacts/ux-design-specification.md)** — 30 UX-DRs, 11 `sa-*` components, design-token system, phased UX roadmap (MVP Epic 3 → Growth Epic 10).
- **[Epics & Stories Breakdown](_bmad-output/planning-artifacts/epics.md)** — 10 epics, 64 stories, full FR/AR/NFR/UX-DR coverage map, bidirectional mapping to architect's original 18-step sequence, cross-cutting story patterns.

### Validation

- **[Implementation Readiness Assessment](_bmad-output/planning-artifacts/implementation-readiness-report-2026-05-02.md)** — verdict: READY. Validates 100% FR coverage, no within-epic forward dependencies, schema creation timing correct, AC quality high. Original 8 issues identified (1 HIGH, 4 MEDIUM, 3 LOW) all resolved on the same day; one accepted as-is.

### Research (input to architecture)

Located under [`_bmad-output/planning-artifacts/research/`](_bmad-output/planning-artifacts/research/) — five technical research documents covering pure-ObjectScript implementation paths, Ensemble UI integration, body-class dispatch, and cleanup decisions. Loaded as historical context for architectural decisions; preserved as planning history.

## Project posture

- **License:** MIT (lands in v1 release commit). Open-source from day one.
- **Distribution:** Open Exchange + GitHub — `zpm install iris-session-agent`.
- **Maintainer:** Joshua Brandt (single-maintainer hobby-project velocity; no SLA).
- **Timeline:** Milestone-based, no date commitments. Scope cuts (not deadline pressure) are the response if the project consumes more time than sustainable.
- **Community contributions** are an accelerant, not a baseline assumption — the plan ships without external contributors if none arrive.

## Contributing

Contribution guidelines will land alongside the v1 release. The four bundled LLM providers exist precisely so a community contributor can add a fifth (e.g., Cohere, AWS Bedrock, Vertex AI) by implementing one new subclass of `SessionAgent.LLM.Provider` plus one registry entry — no edits to shared infrastructure. See [Journey 4 (Tomás)](_bmad-output/planning-artifacts/prd.md) for the full contributor experience the architecture supports.
