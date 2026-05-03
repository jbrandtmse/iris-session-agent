---
stepsCompleted:
  - step-01-document-discovery
  - step-02-prd-analysis
  - step-03-epic-coverage-validation
  - step-04-ux-alignment
  - step-05-epic-quality-review
  - step-06-final-assessment
filesIncluded:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/epics.md
status: complete
overallReadiness: READY (all issues resolved 2026-05-02)
issuesIdentified:
  high: 1
  medium: 4
  low: 3
  acceptedDeviations: 1
issuesResolved:
  high: 1
  medium: 4
  low: 3
  acceptedAsIs: 1
date: 2026-05-02
---

# Implementation Readiness Assessment Report

**Date:** 2026-05-02
**Project:** iris-session-agent

## Step 1 — Document Discovery

**Documents inventoried (all whole, no shards, no duplicates):**

| Type | File | Size |
|---|---|---|
| PRD | `_bmad-output/planning-artifacts/prd.md` | 80,142 B |
| Architecture | `_bmad-output/planning-artifacts/architecture.md` | 122,903 B |
| UX | `_bmad-output/planning-artifacts/ux-design-specification.md` | 128,597 B |
| Epics | `_bmad-output/planning-artifacts/epics.md` | 285,606 B |

Supporting (not assessed): product brief + distillate, `research/` folder.

**Issues:** none — no duplicates, no missing required documents. Stories appear consolidated within `epics.md` (no separate story files); structure to be verified in Step 4.

## Step 2 — PRD Analysis

### Functional Requirements (59 total, 8 capability areas)

**Session Inspection (FR1-FR12, 12 FRs):** chat panel on Visual Trace subclass scoped to current session (FR1); coherent multi-surface NL Q&A (FR2); read message headers / call graph / statuses / errors (FR3); body dispatch ladder for `%JSON.Adaptor` / virtual-doc / `%Stream.Object` / `%Persistent` (FR4); event log with severity filter (FR5); rule log explanation incl. return value, evaluated rule, component, triggering message (FR6); BP runtime state — class source + persistent instance + `Ens.BP.Context` / `Ens.BP.Thread` (FR7); related sessions via `Ens.SuperSessionIndex` (FR8); pivot via `Ens.SearchTableBase` indexed body field (FR9); decode `%Status` / IRIS error codes (FR10); citation grounding back to tool results, click-through verifiable (FR11); chat-history preserved against the Ensemble session (FR12).

**Message Search (FR13-FR24, 12 FRs):** chat panel on Message Viewer subclass (FR13); curated short-list NL search (FR14); search by `Ens.MessageHeader` indexed cols — TimeCreated, Status, Source/Target ConfigName, MessageBodyClassName, SessionId (FR15); join-by-`MessageBodyId` for `Ens.SearchTableBase` indexed body fields (FR16); cross-instance super-session via `Ens.SuperSessionIndex` (FR17); body-content search via narrow-then-inspect ≤50 candidates (FR18); **bounded-WHERE invariant** — every SQL leads with ≥1 indexed col + 24h default `TimeCreated` window, max 720h (FR19); click-through hand-off to Inspection Agent with conversation context (FR20); operator-saved query alias with elevated confidence (FR21); per-user, per-`MessageBodyClass` vocabulary learning with confidence smoothing `Success/(Success+Failure+1)` (FR22); seed vocabulary ~10 HL7 idiom templates (FR23); user vocabulary digest injected into first user message (top 20 rows, conf ≥ 0.3, ~1,200 tokens) — outside cached prefix (FR24).

**LLM Provider Framework (FR25-FR30, 6 FRs):** four bundled providers — OpenAI, Anthropic, Gemini, OpenAI-compatible (FR25); per-agent independent config of provider/model/max-tokens/temperature/system-prompt (FR26); Anthropic-canonical wire shape internally with mechanical adapters (FR27); 5th-provider extensibility — one subclass + one registry entry, no shared-infra edits (FR28); 90s per-call provider timeout cap, audit-loggable (FR29); Anthropic prompt-caching of `system + tools` prefix, vocab digest outside the cache (FR30).

**Read-Only Enforcement & Audit (FR31-FR37, 7 FRs):** three-layer enforcement — code discipline + dispatch policy gate (`MutatesState=0`) + RBAC role `%SessionAgent_ReadOnly` (FR31); persistent `SessionAgent.Audit.LlmCall` with provider/model/msg-count/tokens/latency/conv-ref (FR32); persistent `SessionAgent.Audit.ToolCall` with name/args/result-or-error/latency/conv-ref (FR33); audit FK-linked to chat-history row (FR34); SQL-only audit access in v1 — no separate UI (FR35); dispatch policy gate rejects any `MutatesState=1` tool before execution (FR36); structured `{isError: true, content:[{type:"text",text:...}]}` envelope, never exceptions (FR37).

**Configuration & Credentials (FR38-FR42, 5 FRs):** Zen-page config UI `SessionAgent.UI.AgentConfig` (FR38); independent per-agent config rows (FR39); credential ladder env-var → `Ens.Config.Credentials` → custom AESGCM-encrypted store (FR40); never persist API keys in config — references only (FR41); per-agent max-tokens / temperature / custom system-prompt override (FR42).

**Chat Lifecycle (FR43-FR47, 5 FRs):** Inspection key `(agentName, irisSessionId, portalUser)`; Search key `(agentName, searchSessionKey, portalUser)` with registry-assigned GUID (FR43); daily sweep removes Inspection rows whose underlying session purged via `Ens.MessageHeader.Purge()` (FR44); TTL sweep for Search history, default 30d configurable (FR45); concurrent-tab serialization via `%OpenId(id, 4)` exclusive lock (FR46); "from search" context indicator on Inspection-side after click-through (FR47).

**Installation & Operator Surface (FR48-FR54, 7 FRs):** single-command install `zpm install iris-session-agent` on IRIS / IRIS for Health 2024.1+ (FR48); install succeeds with embedded Python disabled (FR49); install creates `%SessionAgent_ReadOnly` SELECT-only RBAC role on `Ens.*` (FR50); install creates Mgmt Portal bookmarks for both agent surfaces (FR51); README documents Operator Prerequisites — 60s→300s timeout, RBAC grant, credential supply (FR52); zero transitive Open Exchange deps (FR53); vendored Markdown bundle (`marked` + `Prism.js` + `DOMPurify`) self-hosted at `/csp/static/iris-session-agent/`, no CDN — Growth-tier; MVP may use simpler render path (FR54).

**Developer Extensibility (FR55-FR59, 5 FRs):** pure dispatch contract `(toolName, jsonArgs) → jsonResult` — no `%session.Data` / `%request` / Zen state / `%CSP.Response.Write` / `$NAMESPACE` side effects / exceptions as errors (FR55); every tool declares `Parameter ToolName`, `Parameter Description`, `Parameter MutatesState As %Boolean = 0`, `ClassMethod GetInputSchema()`, `ClassMethod Invoke(pCallerCtx, pJsonArgs, Output pResult)` (FR56); MCP Consumer can introspect & dispatch the tool registry without this project shipping MCP transport (FR57); custom tools via `SessionAgent.Tool.Base` subclass — public-API stability is **post-v1** (FR58); ship a tool-call-roundtrip integration test exercising every provider × every tool (FR59).

**Total FRs: 59.**

### Non-Functional Requirements (33 actual, intro says 30 — discrepancy flagged)

**Performance (NFR-P1 to NFR-P6, 6 NFRs):** 90s per-call LLM cap below 300s gateway → clean structured timeout (P1); search query bound under 90s on ≥1M-row extent when bounded-WHERE holds (P2); body-content search ≤50 candidates within 90s (P3); concurrent-tab serialization via `%OpenId(id,4)` (P4); 5min→1min tab-switching → conversation on common patterns (P5); Anthropic prompt-cache stable prefix; vocab in non-cached segment (P6).

**Security (NFR-S1 to NFR-S6, 6 NFRs):** read-only invariant via 3 layers (S1); credential confinement — no `ApiKey` property in `Config.Agent` (S2); credential resolution hygiene — never log keys, never embed in audit (S3); 100% audit completeness across LLM round-trips and tool dispatches (S4); public-OSS authoring posture for all planning artifacts (S5); tool dispatch purity (S6).

**Reliability (NFR-R1 to NFR-R5, 5 NFRs):** operator-deployment safety guaranteed by S1 (R1); chat-history lifecycle integrity — zero orphans under sustained purge (R2); search-history TTL sweep (R3); provider failure isolation — clean error envelope, no chat/audit corruption (R4); IPM idempotent reinstall (R5).

**Scalability (NFR-SC1 to NFR-SC4, 4 NFRs):** bounded queries on extents up to 10M rows (SC1); concurrent-operator scale via stock CSP threading + per-tab serialization (SC2); no cross-instance / mirror coordination in v1 (SC3); audit-log volume bounded by sweep cascade — within IRIS-default journal (SC4).

**Compatibility & Portability (NFR-C1 to NFR-C6, 6 NFRs):** IRIS 2024.1+ floor; newer-version primitives explicitly excluded (C1); pure ObjectScript runtime — no `[Language = python]` in any shipped class (C2); install succeeds Python-less (C3); zero transitive OEX deps (C4); no CDN / offline-installable; air-gap compatible (C5); evergreen browser support (C6).

**Operability & Maintainability (NFR-O1 to NFR-O5, 5 NFRs):** operator self-service install <30 min (O1); hot config change effective on next turn, no IRIS restart (O2); audit review by SQL only — no separate UI (O3); single-maintainer triage with no SLA committed (O4); documentation deliverables current with each release tag (O5).

**Accessibility (NFR-A1, 1 NFR):** inherits Mgmt Portal Zen accessibility — no independent WCAG commitment (A1).

**Total NFRs: 33.** Categories: 7. Excluded: 4 (i18n, compliance certifications, DR/backup commitments, SLA).

### Additional Requirements / Constraints
- **Phasing constraint:** v1 is a single binding contract but delivery is incremental — **MVP** (Inspection + OpenAI only, ≈ end of Epic 3) → **Growth completing v1** (Search Agent, 3 more providers, vocabulary, body-content search, vendored MD, multi-tab safety, prompt cache, seed vocab, ≈ Epic 7 = Inspection complete; Epic 10 = full v1).
- **MVP-vs-Growth cut affects 4 FRs explicitly:** FR54 (vendored Markdown bundle is Growth-tier; MVP may use simpler render path), and the entire Search Agent block (FR13-FR24) plus 3 of 4 providers (FR25 partial — only OpenAI in MVP) and the prompt-caching path (FR30) sit in Growth. The PRD does not annotate per-FR phase tags; epics must carry that mapping.
- **Plugin contracts (3):** LLM Provider, Tool, MCP-export consumer — all governed by the dispatch-purity invariants in FR55-FR56. **Tool plugin public-API stability is explicitly post-v1** (FR58) — internal subclassing during v1 is supported, public stability is not.
- **Boundary item:** PHI redaction is Vision/post-v1; v1's PHI boundary is namespace segregation.
- **Five "no commitment" categories** sit outside the FR/NFR contract: i18n, compliance certifications, DR/backup, SLA, and (per NFR-A1) independent accessibility.

### PRD Completeness Assessment (preliminary — coverage validation in Step 3)
- **Strengths:** every FR is binding-capability-grade (no aspirational language inside the FR list); NFRs uniformly include a **Test** clause naming the validation mechanism (CI gate, integration test, benchmark, manual review); MVP-vs-Growth cut is justified per-alternative; 4 user journeys map cleanly to capability areas; risk register is comprehensive across technical/market/resource dimensions.
- **Gaps to verify in Step 3 (epic coverage):**
  1. Per-FR phase tagging is implicit (in §Product Scope prose) rather than explicit on each FR — epics must carry the mapping accurately.
  2. NFR count discrepancy (intro says 30, actual 33) — cosmetic but worth a one-character fix in PRD before release.
  3. FR54 (Markdown bundle) has a built-in escape hatch ("MVP can use simpler render path") — epics need to specify *which* path MVP ships and how the swap to vendored bundle happens.
  4. FR58 explicitly defers public-API stability — epics covering tool extensibility must not promise stability beyond the FR.
  5. FR23 (seed vocabulary ~10 templates) and FR24 (digest format) are Growth-tier; epics must not bundle them into MVP work.

## Step 3 — Epic Coverage Validation

### Epic Inventory

10 epics, 64 stories total, distribution:
- Epic 1 — Project Foundation & Installable Package (7 stories)
- Epic 2 — Inspection Agent Backend Plumbing (12 stories)
- Epic 3 — Inspection Agent UI MVP Demo-able Milestone (7 stories) — **PRD MVP first-delight gate (Story 3.7)**
- Epic 4 — Inspection Agent Full Tool Catalogue (7 stories) — **all 13 inspection tools complete (Story 4.7)**
- Epic 5 — Multi-Provider Support (4 stories)
- Epic 6 — Per-Agent Configuration UI (3 stories)
- Epic 7 — Inspection Chat-History Lifecycle (3 stories)
- Epic 8 — Search Agent Foundation (7 stories)
- Epic 9 — Search Agent Vocabulary Learning (5 stories)
- Epic 10 — Search Agent UI, Hand-off & TTL Sweep (9 stories) — **v1 SCOPE COMPLETE (Story 10.9)**

The epics document also publishes a bidirectional mapping table to the architect's original 18-step sequence (epics.md §"Mapping to Architecture's Original 18-Epic Sequence"), so dev agents can navigate either numbering.

### FR Coverage Matrix (against PRD's 59 FRs)

| FR | PRD requirement (capsule) | Epic Coverage | Status |
|---|---|---|---|
| FR1 | Chat panel from Visual Trace subclass | Epic 3 (Story 3.3) | ✓ Covered |
| FR2 | Coherent multi-surface NL Q&A | Epic 3 (UI) + Epic 2 (AgentLoop) | ✓ Covered |
| FR3 | Read message-header data | Epic 4 (Story 4.x) + Epic 2 (Story 2.11 example) | ✓ Covered |
| FR4 | Body-class dispatch ladder | Epic 4 (Story 4.2 — 9-step ladder) | ✓ Covered |
| FR5 | Event log read with severity filter | Epic 4 (Story 4.1) | ✓ Covered |
| FR6 | Rule log read | Epic 4 (Story 4.1) | ✓ Covered |
| FR7 | BP runtime state read | Epic 4 (Story 4.4 — BP introspection trio) | ✓ Covered |
| FR8 | `Ens.SuperSessionIndex` related-sessions | Epic 4 (Story 4.5) | ✓ Covered |
| FR9 | `Ens.SearchTableBase` body-field pivot | Epic 4 (Story 4.6) | ✓ Covered |
| FR10 | `%Status` decoder | Epic 4 (Story 4.7 — `ExplainError`) | ✓ Covered |
| FR11 | Citation grounding with click-through | Epic 3 (Story 3.4) | ✓ Covered |
| FR12 | Chat history preserved against Ens session | Epic 2 (Story 2.6) + Epic 3 (Story 3.3 surfacing) | ✓ Covered |
| FR13 | Chat panel from Message Viewer subclass | Epic 10 (Story 10.1) | ✓ Covered |
| FR14 | Curated-list NL search | Epic 8 | ✓ Covered |
| FR15 | Search by indexed `MessageHeader` cols | Epic 8 (Story 8.3 — 6 simple tools) | ✓ Covered |
| FR16 | Search by indexed body field | Epic 8 (Story 8.5) | ✓ Covered |
| FR17 | Cross-instance super-session search | Epic 8 (Story 8.4) | ✓ Covered |
| FR18 | Two-stage body-content ≤50 candidates | Epic 8 (Story 8.6 — `InspectBodyCandidates`) | ✓ Covered |
| FR19 | Bounded-WHERE invariant | Epic 8 (Story 8.2 — invariant test) | ✓ Covered |
| FR20 | Search→Inspection click-through | Epic 10 (Story 10.3) | ✓ Covered |
| FR21 | Operator-saved query alias | Epic 9 (Story 9.2) — basic inline in Epic 8 Story 8.7 | ✓ Covered |
| FR22 | Per-user vocab learning + smoothing | Epic 9 (Story 9.2 + 9.5) | ✓ Covered |
| FR23 | Seed vocabulary ~10 HL7 templates | Epic 8 (Story 8.1) | ✓ Covered |
| FR24 | Vocab digest as first-user-msg prefix | Epic 9 (Story 9.3 + 9.4) | ✓ Covered |
| FR25 | 4 bundled providers | Epic 2 (OpenAI Story 2.9) + Epic 5 (Stories 5.1–5.3) | ✓ Covered |
| FR26 | Per-agent independent config | Epic 6 (Stories 6.1–6.2) | ✓ Covered |
| FR27 | Anthropic-canonical wire + adapters | Epic 2 (Story 2.8) + Epic 5 (validated by 3 more) | ✓ Covered |
| FR28 | 5th-provider extensibility | Epic 5 (Story 5.4 contract test) | ✓ Covered |
| FR29 | 90s per-call provider timeout | Epic 2 (Story 2.9 + 2.12) | ✓ Covered |
| FR30 | Anthropic prompt-caching | Epic 5 (Story 5.1 — `AnthropicProvider`) | ✓ Covered |
| FR31 | 3-layer read-only enforcement | Epic 1 (L3 RBAC Story 1.4) + Epic 2 (L1+L2 Stories 2.10/2.11) | ✓ Covered |
| FR32 | `Audit.LlmCall` per round-trip | Epic 2 (Story 2.5) | ✓ Covered |
| FR33 | `Audit.ToolCall` per dispatch | Epic 2 (Story 2.5) | ✓ Covered |
| FR34 | FK-linked audit rows | Epic 2 (Story 2.5 + 2.6 schemas) | ✓ Covered |
| FR35 | SQL-only audit access | Epic 2 (Story 2.5 — `audit-sql-recipes.md`) | ✓ Covered |
| FR36 | Dispatch policy gate `MutatesState=0` | Epic 2 (Story 2.10) | ✓ Covered |
| FR37 | Structured tool-error envelopes | Epic 2 (Stories 2.10/2.11) | ✓ Covered |
| FR38 | `AgentConfig.zen` Zen page | Epic 6 (Story 6.1) | ✓ Covered |
| FR39 | Independent per-agent rows | Epic 6 (Story 6.1 + Story 2.4 schema) | ✓ Covered |
| FR40 | Credential resolution ladder | Epic 2 (Story 2.3 — `EnvSecret`) | ✓ Covered |
| FR41 | No keys persisted in `Config.Agent` | Epic 2 (Story 2.4 — schema discipline) | ✓ Covered |
| FR42 | Per-agent max-tokens / temp / prompt | Epic 6 (Story 6.1) | ✓ Covered |
| FR43 | Inspection vs Search keying | Epic 2 (Story 2.6 Inspection) + Epic 8 (Search keying) | ✓ Covered |
| FR44 | Daily orphan-history sweep on purge | Epic 7 (Story 7.2) | ✓ Covered |
| FR45 | TTL search-history sweep | Epic 10 (Story 10.6) | ✓ Covered |
| FR46 | Concurrent-tab `%OpenId(id,4)` lock | Epic 2 (Story 2.6) | ✓ Covered |
| FR47 | "From search" context indicator | Epic 10 (Story 10.4) | ✓ Covered |
| FR48 | `zpm install` on IRIS 2024.1+ | Epic 1 (Story 1.5) | ✓ Covered |
| FR49 | Python-less install success | Epic 1 (Story 1.7 CI grep) | ✓ Covered |
| FR50 | `%SessionAgent_ReadOnly` RBAC role | Epic 1 (Story 1.4) | ✓ Covered |
| FR51 | Mgmt Portal bookmarks for both agents | Epic 1 (Story 1.5) | ✓ Covered |
| FR52 | README operator-prerequisites section | Epic 1 (Story 1.2) | ✓ Covered |
| FR53 | No transitive OEX dependencies | Epic 1 (Story 1.1 — module.xml) | ✓ Covered |
| FR54 | Vendored Markdown bundle | Epic 10 (Story 10.7) — Growth tier; MVP fallback in Epic 3 (Story 3.2) | ✓ Covered |
| FR55 | Tool-registry pure-dispatch contract | Epic 2 (Story 2.10) | ✓ Covered |
| FR56 | Required tool params/methods | Epic 2 (Story 2.10) | ✓ Covered |
| FR57 | MCP Consumer can introspect registry | Epic 2 (Story 2.10 — `Tool.Registry.ListTools`) | ✓ Covered |
| FR58 | `SessionAgent.Tool.Base` subclassable | Epic 2 (Story 2.10 — structurally; v1 ships built-ins only) | ✓ Covered |
| FR59 | Tool-call-roundtrip test every provider × every tool | Epic 5 (Story 5.4 — test infrastructure) | ⚠ Covered with caveat (see "Issues" below) |

**Beyond FRs:** epics also explicitly map 20 ARs (Architecture-derived requirements AR1–AR20), 30+ NFR enforcement points across owning epics, and 30 UX-DRs (UX Design Requirements UX-DR1–UX-DR30) into specific epics/stories. The §"FR Coverage Map" in epics.md (lines 251–336) carries this mapping in compact form; my matrix above audits it FR-by-FR.

### Coverage Statistics
- **Total PRD FRs:** 59
- **FRs covered in epics:** 59
- **Coverage percentage: 100%** (with two issues, both clarity/traceability rather than missing capability — flagged below)
- **Total PRD NFRs:** 33 (actual; PRD intro says 30 — flagged in Step 2). All 33 have an explicit owning epic per the per-epic NFR lists in epics.md §"Epic List" lines 342–426.
- **Total PRD AR + UX-DR:** 20 ARs + 30 UX-DRs — all enumerated and mapped.

### Missing / Weak Coverage — Issues to Resolve

#### Issue C-1 (HIGH — clarity, not capability gap): PRD MVP scope vs MVP demo-able milestone are conflated
**Where:** [prd.md](_bmad-output/planning-artifacts/prd.md) §"Product Scope → MVP" (line 162) declares the **MVP includes 13 inspection tools by name**; line 162 also says the "pre-alpha demo-able artifact" is **≈ end of Epic 3**. But in [epics.md](_bmad-output/planning-artifacts/epics.md), Epic 3 (Story 3.7 = "PRD MVP Exit Criteria Validation") only delivers and validates **3 example tools** (`session_summary`, `session_timeline`, `message_headers` from Story 2.11). The remaining 10 inspection tools land in **Epic 4** (Story 4.7 — full 13-tool catalogue + `InspectionToolTest` matrix).

The PRD's own MVP exit criterion #3 (line 427) — "audit log shows the agent dispatched **all 13 tools** at least once across real sessions" — cannot be satisfied at end of Epic 3; only at end of Epic 4.

**Impact:** A reader following the PRD literally believes "MVP demo-able" = "13 tools available". A reader following epics.md sees "MVP demo-able = 3 tools, full catalog at Epic 4". Operators reading the PRD before downloading the pre-alpha will have mismatched expectations.

**Recommendation:** Pick one of the following PRD edits and apply:
- (a) Move the 13-tool list out of MVP scope and into a new "MVP-completion (Epic 4)" sub-tier — keep the Epic 3 milestone as "first-delight demo with 3 tools".
- (b) Keep MVP = 13 tools and re-pin the milestone reference from "≈ end of Epic 3" to "≈ end of Epic 4" everywhere in the PRD (lines 149, 162, 425, 439).
- The simplest is (b) — single-character change in three places — and leaves epics.md untouched.

#### Issue C-2 (MEDIUM — traceability gap): FR59 cross-matrix re-run isn't story-anchored after Epic 8
**Where:** Story 5.4 (`Test/ToolCallRoundtripIntegrationTest`) iterates `[4 providers] × [every Tool.Base in Tool.Registry]`. When Story 5.4 ships, only the 13 inspection tools exist (Epic 4 has shipped); Epic 8 search tools (8 indexed + `InspectBodyCandidates` + `VocabLookup` = 10 tools) land later. The test would automatically pick up the new tools if invoked, but **no Epic 8 / 9 / 10 story has an explicit AC requiring `ToolCallRoundtripIntegrationTest` re-run** after the search-tool catalog is complete. Story 10.9 (PRD v1 Completion Validation Walkthrough) only validates a single end-to-end scenario, not the 4 × 23 = 92-combination matrix.

**Impact:** FR59's contract — "exercises **every bundled provider against every bundled tool**" — could be partially silent on the search tools at v1 release if the maintainer doesn't notice they need to re-run Story 5.4's test once Epic 8 lands.

**Recommendation:** Add a one-line AC to Story 10.9 (or a new sub-story under Epic 10): *"Re-run `Test.ToolCallRoundtripIntegrationTest` against the full v1 tool catalog (13 inspection + 10 search = 23 tools × 4 providers = 92 combinations); all combinations pass."* Cost: ~1 line of story text.

#### Issue C-3 (LOW — already noted in Step 2): NFR self-count discrepancy
PRD intro (line 10) says "30 NFRs across 7 categories"; actual count is 33. Cosmetic; a one-character fix in PRD before v1.0.0 release.

### Coverage Verdict for Step 3
- **No FR is missing an implementation path.** All 59 FRs trace to at least one story.
- **All 13 named inspection tools are accounted for** (Story 2.11 ships 3 examples; Stories 4.1–4.7 ship the remaining 10).
- **All 10 named search tools are accounted for** (Stories 8.3 ships 6, 8.4/8.5/8.6/8.7 ship the remaining 4).
- **Three issues** flagged for cleanup before v1.0.0 release: C-1 (HIGH — PRD scope/milestone phrasing), C-2 (MEDIUM — FR59 re-run not story-anchored after Epic 8), C-3 (LOW — NFR count discrepancy).

## Step 4 — UX Alignment

### UX Document Status
**Found.** [`ux-design-specification.md`](_bmad-output/planning-artifacts/ux-design-specification.md) — 128,597 bytes, completed 2026-05-02. Source of the 30 UX-DRs distilled into [`epics.md`](_bmad-output/planning-artifacts/epics.md) lines 218-249.

### UX-DR Source Fidelity (UX-spec → epics.md distillation)
**Verdict:** PASS with 4 minor paraphrasing losses. All 30 UX-DRs are present in the UX-spec source with full granularity (variant counts, library versions, exit semantics, token enumeration all match). Epics.md correctly distills them. Four implementation details exist in the UX-spec that did not survive distillation into epics.md (none affect coverage; all are MVP-tier nuance):

| # | UX-spec detail | Where in spec | Why epics.md omitted |
|---|---|---|---|
| 1 | Citation chip MVP off-page partial-sync limitation (Header tab updates, SVG highlight does not) | UX-spec line ~1091 | Captured in UX-DR4-MVP shorthand "partial off-page sync" but mechanism not stated |
| 2 | MVP can use inline `<style>` rather than the `/csp/static/iris-session-agent/sessionagent-chat.css` file | UX-spec line ~404 | Implicit in UX-DR14 "MVP simpler render path" |
| 3 | `sa-from-search-stripe` Accept/Dismiss buttons render with Zen native default styling in MVP | UX-spec lines ~1405–1406 | UX-DR5 doesn't specify MVP styling level |
| 4 | Explicit `aria-live="polite"` attribute placements (`sa-status-text`, `sa-from-search-stripe`) | UX-spec lines ~1549–1551 | UX-DR20 covers ARIA discipline at category level, not per-component placement |

Recommend that the dev agent for Story 3.x work consults the UX-spec line directly when implementing — paraphrasing in epics.md UX-DRs is intentional condensation, not error.

### UX ↔ PRD Alignment
**Verdict: PASS — no gaps found.** All 30 UX-DRs trace to one or more FRs and at least one PRD user-journey capability area (PRD §"Journey Requirements Summary" lines 280–296). No orphan UX features without FR anchor; no FR without a UX path **within its tier** (Search Agent UX deferred to Growth/Epic 10 is intentional per PRD §Product Scope phasing).

### UX ↔ Architecture Alignment
**Verdict: PARTIAL — 1 material gap, 1 minor underspec.**

7 of 8 technical mechanisms the UX requires are fully specified in [`architecture.md`](_bmad-output/planning-artifacts/architecture.md):

| Mechanism UX requires | Architecture coverage |
|---|---|
| Chat panel HTML draw helper (`OnDrawContent`) | ✓ `ChatPanelDrawHelper.cls` per architecture (cited by subagent line 878) |
| ZenMethod hyperevent for chat submit | ✓ `SendChatMessage(...)` returning `%String` |
| `%OpenId(id, 4)` exclusive lock | ✓ Acquired at top of `AgentLoop.RunTurn`, released on `%Save` |
| Citation-chip wiring into parent's `selectItem`/`updateTabs` | ✓ Architecture §UI Integration |
| Vendored Markdown bundle distribution | ✓ `<FileCopy>` + unauthenticated `<CSPApplication>` for `/csp/static/iris-session-agent/` |
| Per-agent Zen config page (`SessionAgent.UI.AgentConfig.zen`) | ✓ Specified |
| Tab placement in `EnsPortal.{VisualTrace,MessageViewer}` subclasses | ✓ Specified |

#### Issue C-4 (MEDIUM — architecture ↔ UX gap): MVP Markdown render fallback is unspecified
**Where:** UX-DR14 (epics.md line 233) and PRD FR54 (parenthetical *"Growth-tier — MVP can use a simpler render path"*) both acknowledge the MVP needs a Markdown render strategy that ships **before** the vendored bundle (which lands in Story 10.7). The UX-spec line ~424 says: *"MVP renders Markdown via a simpler server-side `marked`-equivalent in ObjectScript (or plain text with line-break handling)."*

But the **architecture does not commit to either path**. The closest architecture coverage is a single line ("`Markdown.cls` — server-side hooks if needed (mostly client-side)") that doesn't disambiguate between (a) plain text + `<br>`, (b) ObjectScript-based Markdown stripper, (c) ObjectScript port of a marked-subset, or (d) defer-to-empty-render-until-Story-10.7. The decision point is acknowledged but the mechanism is undefined.

**Impact:**
- Story 3.2 (Client-Side `chat-panel.js` MVP Render & Submit, lines 1099+) will need to make this architectural choice during implementation rather than at architecture time. This violates the "architecture decisions are locked before stories" principle and pushes ambiguity onto the dev agent.
- Possible UX regression risk: if MVP renders plain text only, code blocks (LLM is likely to emit them in answers about ObjectScript / SQL / HL7) will look broken. If MVP renders inline-HTML Markdown without DOMPurify, it's an XSS surface.
- Possible Growth-tier handoff churn: if MVP's output format isn't shape-compatible with the Growth-tier vendored bundle's expectations, Story 10.7 must rework the rendering boundary rather than swap the render layer transparently.

**Recommendation:** Before Epic 3 implementation begins, add a ~100-word §"MVP Markdown Render Strategy" subsection to [`architecture.md`](_bmad-output/planning-artifacts/architecture.md) committing to one of:
- **Option A (most conservative):** plain text render with newline-to-`<br>` substitution + `<pre><code>` for fenced code blocks (no syntax highlighting); MVP escapes HTML; Growth-tier swap to vendored bundle is transparent on the operator side.
- **Option B (richer):** server-side ObjectScript-based Markdown subset (heading + bold + italic + code-fence + link) emitted as pre-sanitized HTML; Growth-tier swap is also transparent.
- **Option C (defer):** ship Story 3.x with plain text only and explicitly accept "no Markdown rendering until Epic 10". Reduces risk but degrades MVP demo quality.

Whichever option lands, Story 3.2 should cite the architecture section and not have to make the call at implementation time.

#### Issue C-5 (LOW — also architecture ↔ UX): MVP stylesheet location is underspecified
UX-spec line ~404 says MVP "can use inline style for simpler render," but doesn't specify *where* (embed in `ChatPanelDrawHelper.OnDrawContent` output, hardcode in the Zen page CSS block, or skip and inherit parent's Zen styling). Architecture lines around 1264 repeat the line but don't choose. Lower-stakes than Issue C-4 because the visual delta between the three options is small for MVP. No story would block on this; it'd just produce slightly different MVP polish.

### Phasing Alignment
**Verdict: PARTIAL — same MVP-render gap drives the only real phasing issue.**

- Epic-to-phase mapping is correct in all three documents (PRD §Product Scope, UX-spec §Implementation Roadmap, architecture, epics.md §Mapping table).
- UX-DR27's MVP component list (`sa-chat-panel`, `sa-message-block` operator+agent only, `sa-tool-card`, `sa-citation-chip` MVP-mode, `sa-status-text`, `sa-input-field`, `sa-config-empty-prompt` admin variant) matches Epic 3's story scope (Stories 3.1–3.7) and Story 3.7's PRD MVP exit criteria validation.
- The unresolved MVP-render strategy (Issue C-4) is the **only phasing risk** — without an architectural commitment, the phased handoff from Epic 3 (MVP render path) to Epic 10 Story 10.7 (vendored bundle) may produce an awkward swap rather than a transparent upgrade.

### UX Alignment Summary

| Audit | Status | Issue # |
|---|---|---|
| UX-DR completeness vs UX-spec source | ✓ PASS | — (4 minor paraphrasing losses noted) |
| UX ↔ PRD | ✓ PASS | — |
| UX ↔ Architecture | ⚠ PARTIAL | C-4 (MEDIUM), C-5 (LOW) |
| Phasing | ⚠ PARTIAL | C-4 same gap |

## Step 5 — Epic Quality Review

Validated all 10 epics against best-practice rubric: user-value focus, independence from later epics, story sizing, AC quality (BDD Given/When/Then), no forward dependencies inside epics, schema-creation timing, and starter-template handling.

### Epic-by-Epic Quality Assessment

| Epic | User outcome stated | Independence | Verdict | Issues |
|---|---|---|---|---|
| **1 — Project Foundation & Installable Package** | "Operator-Admin runs `zpm install`... package compiles cleanly... RBAC role created... README operator-prerequisites concrete" | Stands alone | ✅ Pass | — |
| **2 — Inspection Agent Backend Plumbing** | "**(maintainer checkpoint):** A `%UnitTest`-runnable smoke test invokes `AgentLoop.RunTurn(...)`" | Builds on Epic 1 only | ⚠ Borderline | **Q-1** (see below) — labeled "maintainer checkpoint", which transparently admits this is technical scaffolding rather than operator value |
| **3 — Inspection Agent UI MVP Demo-able Milestone** | "Operator opens Visual Trace... clicks 'Ask the agent'... reads grounded answer with citations" — first-delight moment | Builds on 1+2 | ✅ Pass | — (Story 3.7 is PRD MVP exit gate — clean) |
| **4 — Inspection Agent Full Tool Catalogue** | "Operator now has all 13 Inspection tools available" | Builds on 1+2+3 | ✅ Pass | — (Story 4.7 = comprehensive read-only suite, satisfies PRD's "all 13 tools dispatched" exit criterion) |
| **5 — Multi-Provider Support** | "Operator-Admin can pick Anthropic, Gemini, or any OpenAI-compatible endpoint" | Builds on 1+2 | ✅ Pass | — |
| **6 — Per-Agent Configuration UI** | "Operator-Admin opens AgentConfig.zen... saves... hot config change applies on next agent turn" | Builds on 1+2 (and ideally 5 for >1 provider option) | ✅ Pass | — |
| **7 — Inspection Chat-History Lifecycle** | "Operator's accumulated Inspection chat history is automatically swept when underlying Ens session is purged" | Builds on 1+2 | ✅ Pass | — (operator value = no orphan accumulation, observable via SQL) |
| **8 — Search Agent Foundation** | "Operator opens Message Viewer's 'Ask the agent' tab... gets curated short-list" — but parenthetical clarifies "**Epic 10's UI subclass — Epic 8 ships the backend**" | Builds on 1+2+4 (uses Epic 4's body-class dispatch) | ⚠ Borderline | **Q-2** (see below) — operator outcome described requires Epic 10 to exist; explicitly acknowledged in Epic 8's own Note line 1903 |
| **9 — Search Agent Vocabulary Learning** | "Operator's per-user vocabulary aliases get learned silently from click-through" — but click-through doesn't ship until Epic 10 | Builds on 8 | ⚠ Borderline | **Q-3** (see below) — same shape as Q-2; click-through capture is callable programmatically + via Epic 8's `vocab_lookup mode='save'` only until Epic 10 |
| **10 — Search Agent UI Embed, Hand-off & TTL Sweep** | "Operator clicks curated session entry → navigates to Visual Trace... vocabulary captures silently... v1 SCOPE COMPLETE" | Builds on 1–9 | ✅ Pass | — (Story 10.9 = PRD v1 completion walkthrough) |

### Story-Level Spot Checks

- **Story 1.1 (Project Initialization):** Greenfield-correct (architecture explicitly says "no starter template" per AR1; story hand-authors the module.xml + LICENSE + README + .gitignore + skeleton). ✓
- **Story 1.5 (Installer Scaffold):** Forward-aware "defensive seeding" pattern — references `Config.Agent` (Epic 2 schema) but skips with a log message if class doesn't exist. **Not** a forward dependency; it's a documented incremental-enrichment pattern (Story 2.4 later flips defensive guard off). Frontmatter explicitly cites this pattern as deliberate. Acceptable.
- **Story 2.1–2.12 (12 stories in Epic 2):** Each has BDD Given/When/Then ACs covering happy path + error paths (e.g., Story 2.2 covers retry matrix including never-retry-mid-flight; Story 2.3 covers credential redaction in audit rows). Story sizes look reasonable (no story has >6 AC blocks; most are 3-5). ✓
- **Story 3.7 (PRD MVP Exit Criteria Validation):** Explicit checklist mapping back to PRD §"Product Scope MVP exit criteria". Validates audit log shows the **3 example tools** dispatched (not all 13). Confirms the C-1 issue from Step 3: the PRD says "all 13" but Story 3.7 implements the 3-tool gate.
- **Story 4.7 (`ExplainError` + Read-Only Suite):** Validates all 13 tools have `MutatesState=0` declared. Acceptance gate language: "Epic 4 acceptance gate met". This is where the *full* PRD MVP exit criterion can actually be satisfied — supports re-pinning the PRD's "MVP demo-able" milestone reference to Epic 4.
- **Story 5.4 (Tool-Call-Roundtrip Test):** Full matrix exercised, but only 13 inspection tools exist when this ships (Epic 4 done, Epic 8 not yet). See Issue C-2.
- **Story 8.7 (`VocabLookup` + SearchToolTest):** Implements basic inline `RecordSuccess` for `mode='save'`; Story 9.2 enriches with class-level method + recursion-safe `%OnAfterSave`. Same incremental-enhancement pattern as Story 1.5. Documented in story prose. ✓
- **Story 9.1 (Task-0 Probes for `%OnAfterSave` non-recursion + `SynthesizeAlias` determinism):** Per project rule `research-first.md` Task-0 requirement. ✓
- **Story 10.9 (PRD v1 Completion Validation Walkthrough):** Single end-to-end Devin Journey 2 scenario; closes Epic 10 + closes v1. Doesn't include a full re-run of the Story 5.4 cross-provider × cross-tool matrix (see Issue C-2 from Step 3).

### Within-Epic Story Dependencies

Spot-checked Epic 1 (7 stories), Epic 2 (12 stories), Epic 4 (7 stories), Epic 8 (7 stories), Epic 10 (9 stories). In every case, story N+1 builds only on story ≤ N within the epic. No within-epic forward references found. The "stories in order — each completable based only on previous stories within this epic" claim in epic descriptions holds.

### Database / Schema Creation Timing

✓ Correct pattern throughout. Schemas land at first-need:
- `Config.Agent` → Story 2.4 (used defensively-stubbed in Story 1.5 per documented pattern)
- `Audit.LlmCall` / `Audit.ToolCall` → Story 2.5
- `Chat.History` / `Chat.Turn` → Story 2.6
- `UserVocabulary` / `SeedVocabulary` / `NamespaceVocabulary` → Story 8.1 (enriched with `%OnAfterSave` in Story 9.2)

No "create all tables upfront" anti-pattern.

### Acceptance Criteria Quality

Spot-checked ~12 stories for AC quality:
- ✓ Universal use of BDD Given/When/Then format
- ✓ Multiple AC blocks per story (typically 3–6) covering happy path + edge cases
- ✓ Specific expected outcomes (counts, status codes, schemas, file contents) — not vague language
- ✓ Test mechanism named in NFR-aligned ACs (CI grep, integration test, %UnitTest method)
- ✓ Cross-references to project rules (e.g., "per project rule 'Pattern Replication Completeness'") wherever relevant
- ✓ Cross-references to architecture sections and PRD FRs

### Findings (by severity)

#### 🟠 Q-1 (MAJOR — borderline acceptable): Epic 2 is a technical scaffolding epic
**Where:** Epic 2 (epics.md line 351 + line 666) — operator outcome explicitly labeled **"(maintainer checkpoint)"**.

The standard rubric says technical/infrastructure epics without user value are violations. Epic 2 owns it transparently — the maintainer (Joshua) IS the user, and the deliverable (a `%UnitTest`-runnable smoke test against OpenAI with audit completeness) is meaningfully verifiable.

**Justification accepted:**
1. Epic 2 has 12 stories (largest epic) — combining with Epic 3 would create an unmanageably large epic.
2. Epic 3 ships immediately after with the actual first-delight operator value.
3. The maintainer's confidence in the backend before pilot exposure has real project value (avoids exposing operators to a half-baked agent loop).

**Recommendation:** Accept as-is. The "(maintainer checkpoint)" label is honest framing; this is one of the cases where the rubric's strict "user value per epic" rule should bend to project realities. No PRD/epics.md edit needed.

#### 🟠 Q-2 (MAJOR — internal framing inconsistency): Epic 8 operator outcome describes UI that ships in Epic 10
**Where:** Epic 8 (epics.md line 1901 + 1899): *"Operator opens Message Viewer's 'Ask the agent' tab (Epic 10's UI subclass — Epic 8 ships the backend), types 'find me failed admits from the last hour', gets a curated short-list..."*

The parenthetical clarification is honest, but the surrounding sentence describes an operator experience that **cannot exist until Epic 10 ships**. A reader skimming Epic 8 might believe the operator-facing capability lands here.

**Recommendation:** Rewrite Epic 8's "Operator outcome" header to lead with what Epic 8 actually delivers, e.g.:
*"**Backend outcome (programmatic + via `vocab_lookup`):** All 8 indexed-access search tools + body-content search + vocabulary persistence + ~10 HL7-idiom seed templates are callable via `Tool.Registry.Dispatch` and (for vocabulary) via `vocab_lookup`. The operator-facing chat panel UI lands in Epic 10. **Pilot/maintainer outcome:** maintainer can validate Search Agent backend correctness via `%UnitTest` + `vocab_lookup` exploration before exposing to operators."*

This honors the same "(maintainer checkpoint)" pattern Epic 2 uses successfully. ~3-line edit to epics.md.

#### 🟠 Q-3 (MAJOR — same-shape framing issue): Epic 9 operator outcome describes click-through that ships in Epic 10
**Where:** Epic 9 (epics.md line 2126): *"Operator's per-user vocabulary aliases get learned silently from click-through"* — but click-through to a Search Agent UI doesn't exist until Epic 10.

Same fix shape as Q-2. Recommended rewrite:
*"**Backend outcome:** Vocabulary capture mechanism (silent click-through + explicit-save) is callable via Epic 9's `RecordSuccess` + Epic 8's `vocab_lookup mode='save'`. Vocabulary digest injection into first-user-message prefix is wired into AgentLoop. **Click-through from the operator-facing UI lands in Epic 10 Story 10.3** which calls Epic 9 Story 9.5's `RecordClickThrough` ZenMethod stub."*

#### 🟡 Q-4 (MINOR — documentation): Forward-aware enrichment pattern not surfaced in epics.md preamble
**Observation:** Three stories (1.5, 8.7, and indirectly 7.2/10.6) follow a deliberate "ship-now-with-defensive-stub, enrich-later" pattern. Each story documents this internally, and the epics.md frontmatter `revisions` block calls it out. But there's no §"Cross-cutting patterns" header in the epics.md body explaining the pattern to a first-time reader.

**Recommendation (optional):** Add a 5-line §"Cross-Cutting Story Patterns" subsection between §"Mapping to Architecture's Original 18-Epic Sequence" and the Epic 1 detail header, listing the three instances (Story 1.5 → Story 2.4; Story 1.5 → Stories 7.2/10.6; Story 8.7 → Story 9.2). Helps a first-time dev agent grok the pattern without reading every story file. Not blocking.

### Quality Summary

| Severity | Count | Issues |
|---|---|---|
| 🔴 Critical violations | 0 | — |
| 🟠 Major issues | 3 | Q-1 (Epic 2 scaffolding — accepted), Q-2 (Epic 8 framing), Q-3 (Epic 9 framing) |
| 🟡 Minor concerns | 1 | Q-4 (cross-cutting pattern doc) |

**No technical-epic violations beyond Epic 2's deliberate scaffolding (justified). No within-epic forward dependencies. No story-sizing problems. AC quality is high across the spot-checked sample. Schema creation timing is correct.**

## Summary and Recommendations

### Overall Readiness Status

**🟢 READY (with cleanup recommended)**

The planning artifacts are implementation-ready. All four required documents are present, complete, and internally consistent at a load-bearing level. 100% of PRD's 59 FRs trace to at least one story; all 13 named inspection tools and all 10 named search tools are accounted for; 30 UX-DRs map to FRs with no orphans; epic-to-phase mapping is correct in all four documents; story-level acceptance criteria use BDD format with named test mechanisms. The dev agent for Story 1.1 can begin work immediately.

The 8 issues identified are **clarity, traceability, and framing** — none block the start of implementation, but four (C-1, C-2, C-4, Q-2/Q-3) should be cleaned up before merging the first PR or, at the latest, before the v1.0.0 release tag.

### Issue Roll-up (8 total: 1 HIGH, 4 MEDIUM, 3 LOW)

| ID | Severity | Where | Summary | Effort to fix |
|---|---|---|---|---|
| **C-1** | 🔴 HIGH | PRD §"Product Scope MVP" (lines 149, 162, 425, 439) | MVP scope says "13 inspection tools" but milestone reference says "≈ end of Epic 3" — only 3 tools ship there; full 13 land at end of Epic 4. PRD's own MVP exit criterion #3 ("all 13 tools dispatched") cannot be satisfied at Epic 3. | 1-character edit ×3 — change "Epic 3" → "Epic 4" everywhere MVP completion is referenced; OR move 10 tools out of MVP scope into a sub-tier |
| **C-2** | 🟠 MEDIUM | epics.md Story 10.9 (or new Epic 10 sub-story) | FR59 cross-provider × cross-tool matrix test (Story 5.4) ships before Epic 8 search tools land. No story has an explicit AC requiring re-run after search tools exist. | 1-line AC addition to Story 10.9 |
| **C-3** | 🟡 LOW | PRD line 10 (TOC blurb) | Says "30 NFRs" — actual count is 33 (P:6, S:6, R:5, SC:4, C:6, O:5, A:1) | 1-character fix |
| **C-4** | 🟠 MEDIUM | architecture.md (no §"MVP Markdown Render Strategy" exists) | Both UX-DR14 and PRD FR54 acknowledge MVP needs a render-fallback path before Story 10.7's vendored bundle, but architecture doesn't specify the mechanism. Story 3.2 will have to make the call at implementation time. | ~100 words to architecture.md committing to one of: plain-text + `<br>` + `<pre>` for code blocks (recommended), ObjectScript Markdown subset, or defer-to-Epic-10 |
| **C-5** | 🟡 LOW | architecture.md ~line 1264 | MVP stylesheet location ("inline style") underspecified — embed in `OnDrawContent`, hardcode in Zen page, or skip and inherit | 1-2 sentences to architecture.md |
| **Q-1** | 🟠 MAJOR | epics.md Epic 2 (line 351) | "Maintainer-checkpoint" framing is honest acknowledgement that Epic 2 is technical scaffolding rather than user-facing value | **Accept as-is.** Epic 2 has 12 stories — combining with Epic 3 would be unmanageable. Pattern is justified. |
| **Q-2** | 🟠 MAJOR | epics.md Epic 8 (line 1901) | "Operator outcome" describes UI that ships in Epic 10 (parenthetical clarifies but framing still misleads on first read) | ~3-line rewrite of Epic 8 outcome header — borrow Q-1's "(maintainer checkpoint)" honest-framing pattern |
| **Q-3** | 🟠 MAJOR | epics.md Epic 9 (line 2126) | Same shape as Q-2 — describes click-through that ships in Epic 10 | Same as Q-2 |
| **Q-4** | 🟡 LOW | epics.md (no §"Cross-Cutting Story Patterns" section) | "Defensive stub now, enrich later" pattern (Stories 1.5/8.7) is documented per-story but not surfaced as a cross-cutting pattern in the doc preamble | Optional: add 5-line subsection between mapping table and Epic 1 detail |

(Note: Q-1 is included in the count for completeness but is **accepted as-is** rather than requiring a fix.)

### Recommended Next Steps (priority order)

1. **Apply C-1 fix to PRD** (5 minutes). Either re-pin "MVP demo-able" to Epic 4 or split MVP scope into "MVP first-delight (Epic 3)" + "MVP-complete (Epic 4)". Without this, operators reading the PRD ahead of pre-alpha will have mismatched tool-count expectations. Also fix C-3 and C-5 in the same edit pass.

2. **Add C-4 fix to architecture** (30 minutes). Commit to an MVP Markdown render strategy before Story 3.2 starts so the dev agent doesn't make an architectural decision during implementation. Recommend Option A (plain-text + `<br>` + `<pre>` for code blocks) — most conservative, transparent Growth-tier swap, no XSS surface.

3. **Apply Q-2 and Q-3 fixes to epics.md** (10 minutes). Rewrite Epic 8 and Epic 9 operator-outcome headers using Epic 2's transparent "(maintainer checkpoint)" framing pattern.

4. **Apply C-2 fix to epics.md** (2 minutes). Add a one-line AC to Story 10.9: *"Re-run `Test.ToolCallRoundtripIntegrationTest` against the full v1 catalog (13 inspection + 10 search = 23 tools × 4 providers = 92 combinations); all combinations pass."*

5. **(Optional) Q-4 cross-cutting-patterns subsection** in epics.md if you want to make the "defensive stub → enrich later" pattern obvious to first-time readers.

6. **Begin Story 1.1 implementation** in parallel with the cleanup above. None of the 8 issues block Story 1.1's project initialization work — the issues affect MVP-completion gating (C-1), Epic 3 implementation choices (C-4), and v1-completion validation (C-2). Stories 1.1–1.4 can proceed today.

### Final Note

This assessment identified **8 issues across 3 categories** (PRD self-consistency, architecture completeness, epics framing). One is HIGH-priority (C-1), four are MEDIUM (C-2, C-4, Q-2, Q-3), three are LOW (C-3, C-5, Q-4). One additional finding (Q-1, Epic 2 as scaffolding) was reviewed and accepted as a justified deviation. None block the start of implementation; addressing C-1 and C-4 before Epic 3 begins is strongly recommended; the rest can land alongside implementation work.

**Total cleanup effort estimated: 60–90 minutes of edits across PRD, architecture, and epics.md, after which all four documents are in lock-step for the entire v1 implementation cycle.**

---

**Assessment date:** 2026-05-02
**Assessor:** bmad-check-implementation-readiness skill (Claude / Claude Code)
**Documents assessed:**
- `_bmad-output/planning-artifacts/prd.md` (80,142 bytes, complete, 59 FRs / 33 NFRs)
- `_bmad-output/planning-artifacts/architecture.md` (122,903 bytes, complete)
- `_bmad-output/planning-artifacts/ux-design-specification.md` (128,597 bytes, complete, 30 UX-DRs)
- `_bmad-output/planning-artifacts/epics.md` (285,606 bytes, complete, 10 epics / 64 stories)

---

## Resolution Log (2026-05-02 — same day)

After the assessment was generated, all 8 actionable issues were resolved in a single edit pass. **Q-1 (Epic 2 as scaffolding) was accepted as-is** per the assessment recommendation; no edit was required.

### Issue resolution status

| ID | Severity | Status | Resolution |
|---|---|---|---|
| **C-1** | 🔴 HIGH | ✅ RESOLVED | `prd.md`: Restructured §"Product Scope → MVP" to acknowledge two-checkpoint MVP delivery (Epic 3 = first demo-able with 3 example tools; Epic 4 = MVP complete with full 13-tool catalog). Updated MVP exit criterion #3 to explicitly note it's satisfiable only at end of Epic 4 (Story 4.7 gate). Updated milestone-list line 439 to add Epic 4 as the MVP-complete checkpoint. |
| **C-2** | 🟠 MEDIUM | ✅ RESOLVED | `epics.md` Story 10.9: Added a new Given/When/Then AC block requiring re-run of `Test.ToolCallRoundtripIntegrationTest` against the full v1 tool catalog (23 tools × 4 providers = 92 combinations) before the v1.0.0 release tag. Also added FR59 to the Epic 10 acceptance gate criteria. |
| **C-3** | 🟡 LOW | ✅ RESOLVED | `prd.md` line 66: "30 NFRs" → "33 NFRs". `architecture.md` (5 occurrences via global replace): all "30 NFRs" → "33 NFRs". |
| **C-4** | 🟠 MEDIUM | ✅ RESOLVED | `architecture.md` §"User Interface & Frontend Architecture": added new table row "**MVP Markdown render fallback (Epic 3 Story 3.2)**" committing to Option A (plain-text + HTML-escape + `\n` → `<br>` + `<pre><code>` wrapping for fenced code blocks; ~25 lines in `chat-panel.js`; no external library; transparent Growth-tier swap at Story 10.7; no XSS surface because all content is escaped before substitution). Also updated the existing "Markdown rendering" row to label it "Growth tier — Epic 10 Story 10.7" for clarity. |
| **C-5** | 🟡 LOW | ✅ RESOLVED | `architecture.md` "Bundle optimization" row: clarified that MVP inlines styles via `ChatPanelDrawHelper.OnDrawContent` emitting a `<style>` block (~30 lines) alongside the chat-panel skeleton; Story 10.7 swap replaces the `<style>` block with a `<link rel="stylesheet" href="/csp/static/iris-session-agent/sessionagent-chat.css"/>` reference. |
| **Q-1** | 🟠 MAJOR | ✅ ACCEPTED AS-IS | Epic 2 "(maintainer checkpoint)" framing kept as documented justified deviation. No edit. |
| **Q-2** | 🟠 MAJOR | ✅ RESOLVED | `epics.md` Epic 8 (both summary-list entry at line 400 AND detail block at line 1899): rewrote operator-outcome header using "(maintainer checkpoint)" framing pattern. Now explicitly says "Backend outcome (programmatic + via `vocab_lookup`)" and "Maintainer / pilot outcome" with the operator-facing experience explicitly deferred to Epic 10. |
| **Q-3** | 🟠 MAJOR | ✅ RESOLVED | `epics.md` Epic 9 (both summary-list entry at line 411 AND detail block at line 2124): same shape fix as Q-2. Backend outcome (programmatic capture via `RecordSuccess`/`RecordFailure` + `vocab_lookup mode='save'`) explicitly distinguished from operator outcome (silent click-through) which is reached at end of Epic 10 via Story 10.3. |
| **Q-4** | 🟡 LOW | ✅ RESOLVED | `epics.md`: added new §"Cross-Cutting Story Patterns" subsection between §"Mapping to Architecture's Original 18-Epic Sequence" and the Epic 1 detail header. Documents three patterns: (1) defensive-stub-now-enrich-later with 3 instances cited, (2) maintainer-checkpoint framing with 3 epics cited, (3) carry-forward Task-0 probes anchored at first cross-codebase consumer with all 6 probes cited. |

### Final Status After Resolution

🟢 **READY FOR IMPLEMENTATION** — no outstanding issues. Story 1.1 can begin immediately. All four planning artifacts (PRD, Architecture, UX, Epics) are now in lock-step for the entire v1 implementation cycle. Total resolution time: ~30 minutes of focused edits.

The `git status` after resolution will show modifications to `prd.md`, `architecture.md`, and `epics.md`. The implementation-readiness report itself (this file) is appended-to rather than rewritten so the original assessment findings remain visible as the audit trail.
