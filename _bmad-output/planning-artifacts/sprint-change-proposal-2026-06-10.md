# Sprint Change Proposal — Epic 14: Trace Intelligence

**Date:** 2026-06-10
**Workflow:** `/bmad-correct-course`
**Trigger:** Product-owner enhancement request — "make the agent smarter about the content of message traces" using the knowledge in `docs/iris-query-guide/`
**Status:** **APPROVED 2026-06-10** by product owner with decisions **D1 = both agents, D2 = XData seed, D3 = EXPLAIN as stretch story 14.6, D4 = build digest injection now** (D4 differs from the original recommendation; FR63, architecture addendum §4.2, and Story 14.4 below are updated accordingly). Planning artifacts (prd.md, architecture.md, epics.md, sprint-status.yaml) updated in the approval commit.

---

## 1. Issue Summary

**Problem statement.** The v1 agents can only answer questions reachable through the 28 fixed-purpose tools (EXPECTEDTOOLCOUNT=28, README v1.0.4). Every tool wraps hardcoded parameterized SQL (e.g., `session_summary` runs exactly 3 fixed statements against `Ens.MessageHeader`). The agent therefore **cannot answer open-ended analytical questions about trace content** — failure rate by endpoint, daily volume/session trends, latency distributions, payload-derived dimensions (SAML org, AdditionalInfo keys, document counts from streams), custom application tables, or anything requiring a header↔body JOIN it wasn't pre-built for. It also holds **near-zero stored knowledge** of the IRIS SQL dialect, the Interoperability data model, or schema-discovery technique: the Session-Inspection system prompt contains one sentence of domain knowledge (NULL error-response bodies); the Search prompt only states the bounded-WHERE invariant.

**What changed.** `docs/iris-query-guide/` (10 files, commit `89c5fce`) now captures the distilled expertise needed to query this database correctly: the discover→build→execute→validate methodology, the dialect traps that produce *silently wrong results* (integer-vs-string coercion, `%EXTERNAL` vs `%ODBCOUT`, class-scoped `MessageBodyId`, case folding), the session/correlation model, runtime schema discovery, performance patterns, and a query cookbook. The guide is explicitly *not* a script — it is knowledge that must be **operationalized as tools, prompts, and stored knowledge**.

**Issue type:** New requirement / capability gap (not a defect; no completed work is invalidated).

**Evidence.**
- Guide cookbook patterns with no tool coverage today: daily counts, error-rate-by-dimension, latency profiling, AdditionalInfo pivots, stream document counting, orphan screens, custom-table discovery (`docs/iris-query-guide/07-query-cookbook.md`).
- Current prompts: `src/SessionAgent/Config/AgentDefaults.cls` `GetSystemPrompt()` — no dialect or data-model knowledge.
- Current tool SQL is fully static: `src/SessionAgent/Tool/Inspection/*.cls`, `src/SessionAgent/Tool/Search/*.cls`.
- No knowledge/RAG mechanism exists in v1 beyond search-vocabulary aliases (`SessionAgent.Search.*Vocabulary`).

---

## 2. Impact Analysis

### 2.1 Epic impact
- **Current epic:** none in flight. v1 is feature-complete — Epics 1–13 done, 64 v1 stories + Epic 11/12/13 shipped, 509/509 regression baseline (sprint-status.yaml, 2026-05-09).
- **Required change:** **add one new epic — Epic 14 "Trace Intelligence"** (~6 stories + optional stretch). No completed epic is modified; no planned epics exist to resequence.
- **Natural carry-forwards into Epic 14** (Rule 9 grep performed):
  - deferred-work LOW: `%Execute()` SQLCODE not checked across 15+ inspection tools — Epic 14 builds new SQL-running tools and is the named "future defensive-sweep" carrier.
  - Epic 13 retro AI-2 (EnsureIsErrorOnPrepareFailure in new-tool spec template) and AI-3 (EXPECTEDTOOLCOUNT bump visibility) — both "PENDING next Story X.0"; Story 14.0 closes them.

### 2.2 Artifact conflicts
| Artifact | Conflict? | Action |
|---|---|---|
| PRD | No conflicts; vision strengthened (both delight signatures). | Addendum: new FR60–FR64 (§4.1). MVP unaffected (already shipped). |
| Architecture | No pattern overturned. New tool family + knowledge package are additive; reuse Registry/Audit/Seed patterns. | Addendum sections (§4.2). |
| UX | Chat panel already renders tool-call cards (SQL visible in args). | Welcome-message capability text must be updated (Rule 4 watch-item; `static/chat-panel.js` `renderWelcomeMessage()` ~line 679). |
| Tests/CI | New invariant test required (mirrors `BoundedWhereInvariantTest`); `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` bumps. | Per-story ACs. |
| README / module.xml | New tools + knowledge subsystem are operator-observable. | Same-commit README updates (research-first rule item 5). |

### 2.3 Technical impact and constraints (verified)
- **Read-only:** v1's three-layer enforcement maps cleanly onto dynamic SQL. L1 becomes a compiler-level gate: after `%Prepare()`, `%SQL.Statement.%Metadata.statementType = 1` ⇔ SELECT — verified in `irislib/%SQL/StatementMetadata.cls` (property line 107; value table line 25: 1=SELECT, 2=INSERT, 3=UPDATE, 4=DELETE, 45=CALL, 79=EXPLAIN). L2 = `MutatesState=0` dispatch gate (unchanged). L3 = `SessionAgent_ReadOnly` RBAC role (unchanged).
- **No vectors:** NFR-C1 bans `%Library.Embedding` → knowledge retrieval must be topic/keyword-keyed, not embedding-based. Corpus is small (~35 articles), so this costs little.
- **Prompt-cache discipline (NFR-P6):** static knowledge goes in the cached `system + tools` prefix; learned/dynamic knowledge is retrieved via tools (or, later, the existing first-user-message digest channel). The two-array invariant from Story 9.4 is reused unchanged.
- **Registry:** `Tool.Registry.ListTools()` has no per-agent filter — new tools auto-expose to **both** agents (verified `src/SessionAgent/Tool/Registry.cls`).
- **Seeding precedent:** `SessionAgent.Search.SeedVocabulary.Seed()` idempotent installer-invoked pattern is reused for knowledge articles.
- **Timeout reality:** in-process dynamic SQL cannot be preempted mid-statement; guards are row caps + fetch-loop elapsed checks + prompt-enforced time predicates. Web Gateway 300s remains the hard backstop (NFR-P1).

---

## 3. Recommended Approach

### 3.1 Options considered
| Option | Verdict | Notes |
|---|---|---|
| **1. Direct adjustment — new Epic 14 within existing plan** | **SELECTED** — Effort: Medium-High (~6 stories, Epic-13 scale). Risk: Medium, mitigated below. | Purely additive; reuses Registry, Audit, Seed, invariant-test, and prompt-cache patterns. |
| 2. Rollback | Not applicable | Nothing to revert; v1 stable. |
| 3. MVP review | Not applicable | MVP shipped; this is post-MVP scope extension. |

Also considered and rejected:
- **More fixed tools only** (keep adding `search_by_*`): cannot cover the combinatorial space the guide demonstrates (every aggregate × dimension × body-class × correlation); research consensus is that dozens of typed tools become unmaintainable while a guarded dynamic-SQL tool unlocks the long tail.
- **Dynamic SQL only, no knowledge**: LLMs reliably fall into exactly the silent-wrong-results traps the guide documents (integer-vs-string predicates, wrong decode function, `MessageBodyId` joins without class). Knowledge injection is what makes generative SQL *correct*, not just possible.

### 3.2 Design principles (research-grounded)
Perplexity deep-research verification line (Rule 10 form): *Verified current as of 2026-06-10 via Perplexity deep research on 2024–2026 NL2SQL/agent practice: (a) hybrid "typed tools + one guarded read-only dynamic SQL tool" is the consensus production pattern (OpenAI SQL Actions cookbook; Arcade; Alation/Numbers Station); (b) execution-feedback self-correction recovers 60–80% of first-attempt SQL failures with a 3-retry sweet spot (Callsphere: ~85%→95% system accuracy with no model change); (c) schema descriptions + 2–3 sample rows measurably reduce hallucinated columns (Microsoft guidance; SEED/BIRD evidence experiments; X-SQL schema-linking +5.5%); (d) read-only enforcement layering: DB role strongest, middleware parser mandatory, prompt instruction weakest-and-insufficient (Arcade); (e) learned schema memory must be timestamped/versioned to avoid staleness ("memory entanglement").*

The eight principles applied to this design:
1. **Hybrid, not replacement.** The 28 typed tools stay (fast, deterministic, cheap). New capability is additive; recurring dynamic-SQL patterns get promoted to typed tools in later epics.
2. **Three knowledge tiers, cache-aligned.** Tier 1: a compact static "dialect & data-model card" in the system prompt (always needed, cacheable). Tier 2: on-demand retrieval via a `get_query_knowledge` tool over the seeded guide corpus. Tier 3: learned per-namespace schema notes the agent writes and re-reads (the guide's "persist what you learn" habit, §00/§04).
3. **Discovery as typed tools.** Catalog queries (`INFORMATION_SCHEMA`, `%Dictionary`) are deterministic — wrap them as cheap tools rather than having the LLM author them, eliminating one whole error class.
4. **Compiler-level SELECT-only gate**, not regex: `statementType=1` after `%Prepare`, plus single-statement check, row cap, char budget, elapsed guard. Prompt instruction remains, but as the *weakest* layer.
5. **Knowledge-infused error envelopes.** The guide's diagnostic checklist (§00) maps SQLCODE/symptom → fix hint; returning the hint with the error makes the LLM's self-correction loop converge fast (research: error-context-aware correction beats error-message-only).
6. **Preview-first.** Default row cap 50 (max 200); prompt methodology card mandates `TOP N` + time-window on every exploratory query — same habit the guide teaches humans.
7. **Audit everything.** Every dynamic statement is already captured by `SessionAgent.Audit.ToolCall` (args = the SQL); enrich with row count/elapsed/truncation like the search tools' `ResultSetSize` enrichment.
8. **Staleness-aware memory.** Schema notes carry `Namespace`, `VerifiedAt`, and source; retrieval surfaces age so the agent re-verifies stale facts instead of trusting them.

---

## 4. Detailed Change Proposals

### 4.1 PRD addendum (new FRs; no existing FR/NFR modified)

> **FR60 — Guarded dynamic read-only SQL.** The system shall provide an `execute_readonly_sql` tool accepting a single SQL statement and executing it only when, after `%Prepare()`, `%SQL.StatementMetadata.statementType = 1` (SELECT). Enforcement additionally includes: single-statement input, result row cap (default 50, max 200), total result character budget (≈32 KB with explicit truncation markers), fetch-loop elapsed-time guard (default 30 s), and `%SelectMode` ODBC for stable timestamp/decode rendering. Statement text, outcome, row count, and elapsed ms shall be audited per FR34. Failures shall return the SQLCODE, `%Message`, and a diagnostic hint drawn from the knowledge corpus (e.g., −29 → "column alias in GROUP BY — repeat the expression or use a subquery"; −37 → "SUBSTR on a stream — use SUBSTRING").
>
> **FR61 — Schema discovery tools.** The system shall provide typed discovery tools: `list_active_body_types` (windowed `MessageBodyClassName` census with counts), `describe_message_class` (authoritative class→`schema.table` mapping via `%Dictionary.CompiledClass`, columns/types via `INFORMATION_SCHEMA.COLUMNS`, indexes, subclass enumeration, collection child tables, and — when present — `_AdditionalInfo` key census), and `discover_tables` (schema/table browse with name-fragment match, system schemas excluded by default).
>
> **FR62 — Query-knowledge corpus.** The system shall ship a persistent, install-seeded knowledge corpus (`SessionAgent.Knowledge.Article`) distilled from `docs/iris-query-guide/`, retrievable via a `get_query_knowledge` tool by topic enum and keyword match (non-vector per NFR-C1). Articles carry dialect rules, data-model patterns, correlation patterns, performance guidance, and parameterizable cookbook recipes.
>
> **FR63 — Learned schema notes.** The system shall persist agent-authored schema notes (`SessionAgent.Knowledge.SchemaNote`, keyed Namespace + Subject) writable via `save_schema_note` and readable via `get_schema_notes`. Notes are timestamped (`VerifiedAt`) and retrieval surfaces age. A compact schema-notes digest (most-recently-verified notes for the active namespace, entry- and token-capped) is injected into the first-user-message segment of each conversation for **both agents** via the existing two-array channel (FR24 precedent), preserving the cached `system + tools` prefix per NFR-P6. Writes target agent-owned tables only (vocab_lookup save-mode precedent) and are audited. *(Digest injection in-scope per approval decision D4, 2026-06-10.)*
>
> **FR64 — Query-methodology prompting.** Agent system prompts shall include a static dialect-and-data-model card (cardinal traps: integer-enum predicates, `%EXTERNAL`/`%ODBCOUT`, id+class body joins, time-bounding, TOP-N preview, `ID = SessionId` session anchor) and directives to consult `get_query_knowledge`/`get_schema_notes` before authoring SQL and to disclose executed SQL in answers. Prompt content remains static (no runtime-state enumeration) and prompt-cache-stable.

NFR mapping (no new NFR sections needed): FR60 guards satisfy NFR-S1 (read-only, three layers) and the NFR-P2-style execution bound; Tier-1/2/3 knowledge placement preserves NFR-P6 (cache); FR62 retrieval is non-vector per NFR-C1; everything is pure ObjectScript per NFR-C2.

### 4.2 Architecture addendum

1. **New tool family** `SessionAgent.Tool.Query.*` with abstract `Tool.Query.Base`:
   - Registry discovery SQL gains the third base class (today it matches `Tool.Base` + `Tool.Search.Base` supers).
   - Base owns the guard pipeline: single-statement validation → `%Prepare` → `statementType=1` gate → execute → capped/elapsed-guarded fetch → envelope shaping. New CI invariant test `ReadOnlySqlInvariantTest` (mirrors `BoundedWhereInvariantTest`): every `Tool.Query.*` concrete must route execution through the base pipeline.
   - SQL-injection 4-layer rule applies in adapted form: the *input is* SQL by design, so layer 1 = schema `description` priming ("single SELECT statement; always include a time-window predicate and TOP N"), layer 2 = statementType gate (stronger than `$Match`), layer 3 = parameterless single-statement execution with caps, layer 4 = reviewer confirmation.
   - **Residual risk (documented, accepted):** a SELECT can invoke SQL-projected class methods with side effects. Mitigations: L3 RBAC backstop, 100% SQL audit (FR34), read-only prompt covenant. Optional future hardening: execute under a restricted-privilege job. This matches v1's trust posture (operators are already privileged portal users).
2. **New package** `SessionAgent.Knowledge.*`: `Article` (persistent, seeded), `SchemaNote` (persistent, learned), `SeedContent` (XData-carried distilled corpus → no file-path dependency; avoids the `static/` FileCopy placement ambiguity in deferred-work), idempotent `Seed()` invoked by `SessionAgent.Installer` (SeedVocabulary precedent, NFR-R5 install-log line).
3. **Audit enrichment:** `execute_readonly_sql` envelopes include `row_count`, `truncated`, `elapsed_ms`; ToolCall audit rows therefore carry them (args already capture the SQL text).
4. **Prompt assembly:** `AgentDefaults.GetSystemPrompt()` appends the static methodology card to both agents; per-row `SystemPromptOverride` semantics unchanged.
5. **Calibration constants** (AR10 pattern, Class Parameters on `Tool.Query.Base`): `DefaultMaxRows=50`, `HardMaxRows=200`, `ResultCharBudget=32000`, `DefaultElapsedGuardSec=30`, `HardElapsedGuardSec=60`.

**Decisions — RESOLVED at approval (2026-06-10):**
- **D1 — Tool exposure: BOTH AGENTS** (as recommended). Registry has no per-agent filter; both benefit; guards are agent-independent.
- **D2 — Seed format: CLASS XDATA** (as recommended). Distilled articles compiled into the package — namespace-portable, no file dependency (FileCopy path-ambiguity precedent avoided).
- **D3 — EXPLAIN support** (`statementType=79`): **STRETCH STORY 14.6** (as recommended). SELECT-only first.
- **D4 — Schema-notes digest injection: BUILD NOW** (product-owner override of the defer recommendation). `SessionAgent.Knowledge.SchemaNoteDigest.Build(namespace)` mirrors `Search.VocabularyDigest.Build` (AR10-style class parameters: `MaxEntries=10`, `MaxChars≈2000`, most-recently-verified-first ordering). AgentLoop first-turn injection extends the Story 9.4 two-array channel to **both agents**: search agent concatenates vocabulary digest + schema-notes digest in the first-user-message prefix; inspection agent gains its first first-turn digest. Cache discipline preserved (uncached user segment); cache-stability test extended. Lands in Story 14.4.

### 4.3 Epic 14 — Trace Intelligence (draft story breakdown)

| Story | Title | Scope sketch |
|---|---|---|
| **14.0** | Epic setup + carry-forward closure | Rule 7 operator-state + sample-production probe; Rule 9 grep closure: `%Execute()` SQLCODE sweep across `Tool.Inspection.*` (deferred-work carrier), Epic 13 AI-2 (EnsureIsErrorOnPrepareFailure in spec template), AI-3 (EXPECTEDTOOLCOUNT visibility); stale-reference scan incl. welcome-message capability text; commit PRD/architecture addenda; golden-question eval set authored (≈12 questions drawn from cookbook §07). |
| **14.1** | Knowledge corpus + `get_query_knowledge` | `Knowledge.Article` + `SeedContent` XData (distill guide → ~35 topic articles, Appendix C); idempotent `Seed()` + Installer wiring + install-log count; tool with topic enum + keyword match; bounded result size; tests. |
| **14.2** | Schema-discovery tools | `list_active_body_types`, `describe_message_class`, `discover_tables` per FR61; `UPPER()` both sides for `%Dictionary` joins; `%EXACT`-alias rule respected (positional reads); tests incl. subclass + collection-table cases. |
| **14.3** | `execute_readonly_sql` + `Tool.Query.Base` | Guard pipeline per FR60; SQLCODE→hint map from corpus; `ReadOnlySqlInvariantTest` CI check; audit enrichment; EXPECTEDTOOLCOUNT bump; Task 0 probes: `statementType` empirical check on live IRIS (SELECT/INSERT/CALL/EXPLAIN), `%SelectMode` rendering check. |
| **14.4** | Learned schema notes + digest injection (D4) | `Knowledge.SchemaNote` + `save_schema_note`/`get_schema_notes` per FR63; `SchemaNoteDigest.Build` (VocabularyDigest precedent) + AgentLoop first-turn injection for **both agents** extending the Story 9.4 two-array channel; NFR-P6 cache-stability test extension; staleness surfacing; write-status discipline incl. ByRef audit-emitted envelope-correctness (Rule 8 defensive-surface enumeration); tests. |
| **14.5** | Prompts + welcome text + eval pass | FR64 methodology card on both agents; welcome-message capability text update (Rule 4 watch-item); prompt-cache stability verification (NFR-P6 two-array invariant untouched); mock-matrix run of the golden-question set; README tool-catalog update. |
| **14.6** | *(stretch — D3)* Plan-reasoning support | EXPLAIN (`statementType=79`) allowance + `%PARALLEL`/`%IGNOREINDEX` guidance article activation; only if 14.0–14.5 land clean. |

**Epic-end battery (Rule 6, run before retro):** standard checklist bullets 1–4 **plus** bullet-5 user-led functional walkthrough: drive the chat panel through the golden-question set against the sample production (rich data per Rule 6 step 4), each configured provider taking at least one dynamic-SQL turn; verify the agent (a) consults knowledge before SQL, (b) time-bounds + TOPs, (c) self-corrects from a seeded SQLCODE error, (d) saves and re-reads a schema note, (e) discloses executed SQL. Credential-resolvability probe first (Rule 11) — Epic 13 matrix shows all 4 providers resolvable.

**Golden-question eval set (authored in 14.0; illustrative):** daily message+session counts last 30 days; error rate by `TargetConfigName` last 24 h; top error-text groups (noisy-text grouping); P95-ish latency for a Business Operation (single-header pattern); which body types are active this week; describe an unknown body class and pivot one of its AdditionalInfo keys; find long-running sessions; explain why session N errored (existing-tool regression); one custom-table discovery question; one deliberately-trapped question (status string vs integer) to verify the card/knowledge prevents the silent no-op.

### 4.4 UI/UX changes
None structural. Tool-call cards already render args (the generated SQL) and results. Welcome-message capability text updated in 14.5. No new Zen surfaces.

### 4.5 Effort / risk / timeline
- **Effort:** ~6 stories ≈ Epic 13 scale (6 stories, one cycle).
- **Risks & mitigations:** (1) LLM emits trap-laden SQL → Tier-1 card + knowledge tool + hint-bearing error envelopes + golden-question gate; (2) expensive queries → caps, elapsed guard, prompt time-bounding, `TOP` injection habit; (3) smaller default models (gpt-4.1-mini / haiku) underperform on dialect → knowledge tiers exist precisely for this; eval set quantifies before/after, and per-agent model choice remains an operator knob; (4) prompt-cache invalidation when tools array grows → one-time, accepted (same as every prior tool addition).

---

## 5. Implementation Handoff

**Scope classification: Moderate** (new epic + PRD/architecture addenda; no fundamental replan — all v1 patterns reused).

| Role | Responsibility |
|---|---|
| **Product owner (user)** | Approve/adjust this proposal; decide D1–D4 (recommendations inline). |
| **PM/Architect (lead, on approval)** | Commit PRD addendum (FR60–FR64), architecture addendum (§4.2), epics.md Epic 14 section; add `epic-14` backlog entries to sprint-status.yaml (checklist item 6.4 — deferred until approval). |
| **Dev/Reviewer agents (via `/epic-cycle`)** | Execute Stories 14.0→14.5 (14.6 stretch) under the epic-cycle discipline rules; Story 14.3 Task 0 must empirically probe `statementType` values and `%SelectMode` rendering before AC authoring (research-first rule item 4). |

**Success criteria:** golden-question set passes user-led chat-panel walkthrough on the sample production; regression baseline grows from 509 with zero failures; EXPECTEDTOOLCOUNT reconciles; knowledge corpus seeded and retrievable on fresh install; audit rows show 100% dynamic-SQL capture.

---

## Appendix A — Change-analysis checklist record

| Item | Status | Note |
|---|---|---|
| 1.1 Trigger story | [x] | Not a story — post-v1 PO request, 2026-06-10; guide landed `89c5fce`. |
| 1.2 Problem defined | [x] | §1 — new requirement / capability gap. |
| 1.3 Evidence | [x] | §1 Evidence. |
| 2.1 Current epic viability | [x] | None in flight; v1 complete. |
| 2.2 Epic changes | [x] | Add Epic 14 only. |
| 2.3 Future epics review | [N/A] | No planned epics exist. |
| 2.4 Invalidation/new epics | [x] | Nothing invalidated; one new epic. |
| 2.5 Priority/order | [x] | Epic 14 next; carry-forwards folded into 14.0. |
| 3.1 PRD conflicts | [x] | Additive FR60–FR64; MVP shipped/unaffected. |
| 3.2 Architecture conflicts | [x] | Additive §4.2; no pattern overturned. |
| 3.3 UI/UX conflicts | [x] | Welcome text only. |
| 3.4 Other artifacts | [x] | README, module.xml, tests, deferred-work closure. |
| 4.1 Direct adjustment | [x] Viable — **selected** | Effort M-H, risk M. |
| 4.2 Rollback | [N/A] | Nothing to revert. |
| 4.3 MVP review | [N/A] | Post-MVP. |
| 4.4 Path selected | [x] | Option 1, §3. |
| 5.1–5.5 Proposal components | [x] | §§1–5. |
| 6.1–6.2 Review | [x] | Cross-checked against PRD/architecture survey + codebase verification. |
| 6.3 User approval | [x] | **APPROVED 2026-06-10** — D1 both agents, D2 XData, D3 stretch 14.6, D4 build now. |
| 6.4 sprint-status.yaml update | [x] | epic-14 + 7 story entries added (backlog) in approval commit. |
| 6.5 Handoff confirmation | [x] | §5 — next action: `/epic-cycle` Epic 14. |

## Appendix B — Source verification trail

- `docs/iris-query-guide/00–08 + README` — read in full; design maps every file to a knowledge tier or tool (Appendix C).
- `irislib/%SQL/StatementMetadata.cls` — `statementType` property + value table verified (1=SELECT … 45=CALL, 79=EXPLAIN).
- `src/SessionAgent/Tool/Registry.cls` — discovery SQL + no per-agent filter verified.
- `src/SessionAgent/Search/SeedVocabulary.cls` — idempotent `Seed()` installer precedent verified.
- `src/SessionAgent/Config/AgentDefaults.cls` — current prompts captured (via codebase survey).
- Perplexity deep research (2026-06-10) — key citations: OpenAI SQL Actions cookbook (hybrid pattern); arcade.dev SQL-tool security layering; Callsphere self-healing loop numbers (60–80% recovery, 3-retry); SEED/BIRD evidence experiments; X-SQL schema-linking gains; Anthropic context-engineering + advanced-tool-use guidance; docs.intersystems.com IRIS SQL language elements.

## Appendix C — Knowledge corpus seed inventory (distillation map)

| Guide source | Article topics (~35 total) |
|---|---|
| 00-methodology | methodology-loop; diagnostic-checklist (symptom→fix, doubles as SQLCODE hint map) |
| 01-dialect | top-not-limit; %ID-joins; class-to-table; date-time-functions; decode-functions; integer-string-trap; case-and-%EXACT; list-extraction; stream-reading; groupby-restrictions; reserved-aliases; count-distinct-cost; prefix-match; hint-placement |
| 02-message-model | persistence-projection; inheritance-extents-%CLASSNAME; header-spine; header-body-join; session-model; request-response-correlation; errors-on-response; additionalinfo-pivot |
| 03-performance | cost-vs-runtime; parallel-hint; ignoreindex-pattern; indexing-realities; io-bound-vs-plan-bound; orphan-detection-caveats |
| 04-discovery | (mostly became FR61 tools) custom-table-discovery-workflow; search-table-tip |
| 05/06-references | ens-messageheader-card; ens-util-log-card; hs-body-patterns (SAML location, nested-$LIST, doc-counting) — HS articles seeded only as *patterns*, names verified live per guide warning |
| 07-cookbook | ~12 parameterizable recipes (daily-counts, error-rate-by-dimension, latency ×3, session-trace, noisy-error-grouping, aggregate-first-join, watermark-scan, doc-count, orphan-screen) |
| 08-execution | (absorbed into FR60 tool contract + read-only covenant in prompt card) |
