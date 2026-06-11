# Epic 14 Golden-Question Eval Set

**Authored:** Story 14.0 (2026-06-10), per sprint-change-proposal-2026-06-10.md §4.3
("Golden-question eval set — authored in 14.0") and Story 14.0 AC-6.

**Purpose.** Concrete acceptance instrument for Epic 14 "Trace Intelligence". Story 14.5
runs this set as a mock-matrix eval; the epic-end battery (Rule 6 bullet 5) drives the
chat panel through it user-led against the sample production
(`SessionAgent.Sample.Production`, 8+ seeded sessions — top up via
`SessionAgent.Sample.BS.OrderIngest:RunScenario` where a question needs volume).

**Source recipes:** `docs/iris-query-guide/07-query-cookbook.md` (cookbook §07) +
`docs/iris-query-guide/01-iris-sql-dialect.md` (dialect traps). Tool names reference the
Epic 14 additions: `get_query_knowledge` (14.1), `list_active_body_types` /
`describe_message_class` / `discover_tables` (14.2), `execute_readonly_sql` (14.3),
`save_schema_note` / `get_schema_notes` (14.4).

**Field key.** Each entry carries: **Q** (operator question text), **Expected behavior**
(which tools / knowledge the agent should consult and how), **Pass criteria** (observable
envelope/transcript checks), **Trap notes** (where applicable).

---

## GQ-1 — Daily message + session counts (30 days)

- **Q:** "How many messages and how many sessions per day did this instance process over the last 30 days?"
- **Expected behavior:** Consults `get_query_knowledge` (aggregation / scalability topic), then `execute_readonly_sql` with the cookbook §07 "Daily message + session counts" shape: `TO_CHAR(TimeCreated,'YYYY-MM-DD')` grouping, `SUM(CASE WHEN SessionId = ID THEN 1 ELSE 0 END)` for session starts (NOT `COUNT(DISTINCT SessionId)`), `TOP`, 30-day `DATEADD` bound.
- **Pass criteria:** SQL is time-bounded AND `TOP`-capped; no `COUNT(DISTINCT)` over `Ens.MessageHeader`; per-day rows returned match a manual run of the cookbook query; executed SQL disclosed in the tool-call card.
- **Trap notes:** `COUNT(DISTINCT)` temp-file trap (guide §05) — the session-start `SUM(CASE …)` approximation is the accepted pattern.

## GQ-2 — Error rate by TargetConfigName (24 h)

- **Q:** "What's the error rate per target component over the last 24 hours?"
- **Expected behavior:** `execute_readonly_sql` grouping `Ens.MessageHeader` by `TargetConfigName` with `COUNT(*)`, `SUM(CASE WHEN IsError=1 …)`, and a computed percentage; 24-hour `DATEADD` bound; `TOP` cap.
- **Pass criteria:** Result has one row per active target (sample production: OrderRouter / target operations) with plausible totals; agent notes `IsError` is set on the **response** leg; SQL disclosed.
- **Trap notes:** `IsError=1` lands on response legs (`Type=2`) — an agent filtering `Type=1 AND IsError=1` undercounts to zero.

## GQ-3 — Top error-text groups (noisy-text grouping)

- **Q:** "Group the errors from the last day by error message — what are the top failure modes?"
- **Expected behavior:** Consults knowledge (error-status rendering), then `execute_readonly_sql` per cookbook §07 "Grouping noisy error text": `GROUP BY SUBSTRING(%ODBCOUT(ErrorStatus), 1, 20)` (prefix-truncated) with `MIN(SUBSTRING(%ODBCOUT(ErrorStatus),1,255))` as the representative full text, ordered by count.
- **Pass criteria:** `%ODBCOUT()` used on `ErrorStatus` (not raw column, not `%EXTERNAL`); grouping is by truncated prefix so IDs/timestamps don't fragment groups; readable error text in the result (no binary garble).
- **Trap notes:** Raw `ErrorStatus` is binary-encoded `%Status` garble; `%EXTERNAL` does NOT decode `%Status` — only `%ODBCOUT` does (guide §01 rendering table).

## GQ-4 — P95-ish latency for a Business Operation

- **Q:** "What does the slow tail of response times look like for the order target operation over the last week?"
- **Expected behavior:** Consults knowledge (latency-pairing topic), then the cookbook §07 single-header pattern: `Type = 1 AND TargetConfigName = '<op>'`, `DATEDIFF('ms', TimeCreated, TimeProcessed)`, `ORDER BY ResponseMs DESC`, `TOP 100` — reading the tail as the P95-ish view rather than attempting exact percentile SQL.
- **Pass criteria:** Single-header pattern used (no ambiguous self-join when `CorrespondingMessageId` is 0); 7-day bound + `TOP`; agent explains it is showing the slowest-N tail, not an exact percentile.
- **Trap notes:** Pairing request/response by self-join is ambiguous when the op fires many times per session — the request leg's own `TimeProcessed − TimeCreated` IS the response latency (guide §02).

## GQ-5 — Active body types this week

- **Q:** "Which message body types have been active on this instance this week?"
- **Expected behavior:** Prefers the Story 14.2 `list_active_body_types` tool; equivalent fallback is the cookbook §07 discovery one-liner (`GROUP BY MessageBodyClassName`, 7-day bound).
- **Pass criteria:** Returns the sample-production body classes (e.g., `SessionAgent.Sample.Msg.OrderRequest`) with counts; time-bounded; no full-table scan without bound.
- **Trap notes:** —

## GQ-6 — Describe an unknown body class + pivot one AdditionalInfo key

- **Q:** "I don't know the shape of `<body class from GQ-5>` — describe its fields, then break down message volume by one of its AdditionalInfo keys (if it has an AdditionalInfo collection)."
- **Expected behavior:** `describe_message_class` (14.2) for properties + SQL projection (schema/table names, collection child tables); if an `AdditionalInfo`-style collection exists, composes the cookbook §07 "failure rate by a dimension" join shape against the `_AdditionalInfo` child table with `element_key = '<key>'`; if the class has no such collection, says so explicitly instead of inventing a join.
- **Pass criteria:** Class description matches `%Dictionary` reality (verify one property name manually); any child-table join uses the real projected table name; no hallucinated columns; honest "no AdditionalInfo collection" path accepted for body classes without one.
- **Trap notes:** Collection properties project to child tables (`<Table>_<Prop>` with `element_key`) — naive `class.Prop` column references fail at prepare time; the agent should discover the projection, not guess it.

## GQ-7 — Long-running sessions

- **Q:** "Find sessions in the last day where processing took more than 20 seconds."
- **Expected behavior:** `execute_readonly_sql` per cookbook §07 "Long-running messages": `{fn TIMESTAMPDIFF(SQL_TSI_SECOND, TimeCreated, TimeProcessed)} > 20`, 1-day bound, `TOP 50`, ordered by duration descending; presents SessionId + component + duration.
- **Pass criteria:** ODBC `{fn TIMESTAMPDIFF(...)}` (or equivalent `DATEDIFF`) used correctly; time-bounded + `TOP`-capped; empty result is presented as "none found" (NOT an error) when the sample production has no slow sessions — optionally agent suggests lowering the threshold.
- **Trap notes:** —

## GQ-8 — "Why did session N error?" (existing-tool regression)

- **Q:** "Why did session `<N>` error?" (pick an `IsError=1` session from the sample production's error-injection scenario)
- **Expected behavior:** Uses the EXISTING inspection tools — `session_summary` → `message_headers`/`session_timeline` → `get_message_detail`/`explain_error` — NOT raw SQL. This is the Epic 14 regression guard: new dynamic-SQL capability must not displace the purpose-built tools for their home turf.
- **Pass criteria:** No `execute_readonly_sql` dispatch for the diagnosis (or only as a supplement after the inspection tools); answer names the failing component and the decoded error text; citations rendered for each tool call.
- **Trap notes:** An agent that reaches for raw SQL first regresses FR55-era behavior — the methodology card (14.5) should steer tool-first.

## GQ-9 — Custom-table discovery

- **Q:** "Are there any custom (non-Ens) message-body tables on this instance, and what columns does one of them have?"
- **Expected behavior:** `discover_tables` (14.2) and/or `INFORMATION_SCHEMA.COLUMNS` + `%Dictionary.CompiledClass` discovery per cookbook §07 one-liners (`UPPER()` on both sides of `%Dictionary` name joins per the 14.2 scope note); then a column listing for one discovered table.
- **Pass criteria:** Discovery query filters sensibly (persistent classes / relevant schema); column list matches `INFORMATION_SCHEMA` reality; no invented table names.
- **Trap notes:** `%Dictionary` name comparisons are case-sensitive on mixed-case class names — `UPPER()` both sides (Epic 14 architecture addendum note).

## GQ-10 — TRAPPED: status string vs integer (silent-wrong-results guard)

- **Q:** "Show me all messages from the last day whose status is not 'Completed'."
- **Expected behavior:** Consults `get_query_knowledge` (integer-string trap topic) BEFORE composing SQL; emits either `%EXTERNAL(Status) != 'Completed'` or the integer-code predicate — NEVER a bare `Status != 'Completed'`.
- **Pass criteria:** The returned row set is the genuinely-filtered set. Explicit FAIL if the agent runs `WHERE Status != 'Completed'` and presents the result without flagging it: `'Completed'` coerces to 0, the predicate becomes `Status != 0`, **every row matches**, and the agent confidently reports an unfiltered set as filtered.
- **Trap notes:** **This is the deliberately-trapped question.** The failure mode it guards is the **silent no-op / silent-wrong-results** class from guide §01: IRIS string→integer coercion makes string predicates on integer-coded enum columns (`Status`, `Type`) silently match everything (`!=`) or nothing (`=`) with SQLCODE 0 — no error envelope, no hint, just wrong data. Empirically reconfirmed during Story 14.0 Task 4 probes: `WHERE SessionId = ?` bound to `'abc'` returned rc=0 silently. The Tier-1 methodology card + knowledge article exist precisely to prevent this; this question quantifies whether they work.

## GQ-11 — Full chronological trace of one session (SQL vs tool cross-check)

- **Q:** "Give me the full chronological trace of session `<N>` as a table — every hop with source, target, body class, status, and error flag."
- **Expected behavior:** Either `session_timeline`/`message_headers` (tool-first, preferred) or the cookbook §07 "Full trace of one session" SQL (`ORDER BY TimeCreated ASC, ID ASC`, `%EXTERNAL(Status)`); ideally the agent cross-validates one against the other when asked to show "as a table".
- **Pass criteria:** Row order is chronological with ID tiebreak; `Status` rendered via `%EXTERNAL` (words, not integers) in any SQL path; hop list matches the Visual Trace for the same session.
- **Trap notes:** `ORDER BY TimeCreated` alone interleaves same-timestamp hops — the ID tiebreak matters on fast sessions.

## GQ-12 — Messages per day through one component (lead's pick #1, cookbook §07 recipe 1)

- **Q:** "How many messages per day went through the order router over the last 30 days?"
- **Expected behavior:** Cookbook §07 "Messages per day through a component": `TargetConfigName = '<router config name>'` + `TO_CHAR(TimeProcessed,'YYYY-MM-DD')` grouping + 30-day bound + `TOP`. Component name discovered live (via `get_production_config_item` / `search_by_target` / discovery query), not guessed.
- **Pass criteria:** Real config-item name used (sample production: the OrderRouter item); time-bounded + capped; daily counts match a manual run.
- **Trap notes:** Guessing `TargetConfigName` strings silently returns 0 rows (string predicates on a real string column are safe but typo-prone) — discovery-first is the pass-shape.

## GQ-13 — Aggregate-first lookup join (lead's pick #2, cookbook §07)

- **Q:** "Break down last week's message volume by source component, and annotate each source with its adapter class from the production config."
- **Expected behavior:** Aggregates `Ens.MessageHeader` FIRST in a subquery (`GROUP BY SourceConfigName`, 7-day bound), THEN joins the small config/lookup surface (`Ens_Config.Item` or per-item `get_production_config_item` calls) to the ~K grouped keys — per cookbook §07 "Aggregate-first, then join lookups". NOT a per-row join of config tables against millions of header rows.
- **Pass criteria:** Subquery-aggregate-then-join shape (or aggregate + per-key tool calls); each source row annotated with a real adapter/class name; time-bounded + capped.
- **Trap notes:** Joining lookup tables to the raw header scan multiplies bitmap-intersection cost — the knowledge article's aggregate-first pattern is the efficiency guard.

---

**Total: 13 entries** (≥12 per AC-6; the 10 proposal-mandated questions are GQ-1…GQ-10;
GQ-11/GQ-12/GQ-13 are the lead's-choice picks from cookbook §07). The trapped question is
GQ-10 and explicitly names the silent-wrong-results failure mode it guards.

---

## Mock-matrix run — Story 14.5, 2026-06-11

**Method.** Each entry's expected tool chain dispatched mechanically through the REAL
`SessionAgent.Tool.Registry.Dispatch` path (registry resolution, arg validation, audit
emit, envelope shaping) via the `SessionAgent.Test.GoldenQuestionDriver.RunTool` helper,
against the live sample production (`Ens.Director.IsProductionRunning=1`; window state at
run time: 223 messages / 37 session starts in the trailing day). This validates toolchain
**mechanics**; the LLM-driven pass is the epic-end user-led walkthrough (Rule 6 bullet 5).

| GQ | Tool(s) dispatched | Envelope outcome | Result (verbatim key rows) | Pass |
|---|---|---|---|---|
| GQ-1 | `get_query_knowledge` (topic=cookbook) → `execute_readonly_sql` | both `render_strategy:"ok"` | knowledge top hit = `daily-counts` recipe; SQL: `["2026-06-11",223,37]` — matches manual run exactly (223/37) | **PASS** |
| GQ-2 | `execute_readonly_sql` | ok, 5 rows | `["SESSIONAGENT.SAMPLE.BP.ORDERROUTER",124,27,"21.77"]` + 4 zero-error targets; one row per active target | **PASS** |
| GQ-3 | `execute_readonly_sql` (`%ODBCOUT` + prefix-truncated GROUP BY) | ok, 1 row | `["خطأ <Ens>ErrGeneral: Injected SQL persist failure for OrderId=ORD-000003 (sample error mode)",27]` — readable decoded text, group total 27 = GQ-2 error count | **PASS** |
| GQ-4 | `execute_readonly_sql` (single-header pattern, `Type=1`, 7-day bound, `TOP 100`) | ok, 31 rows | slow tail max `ResponseMs=7` (ID 1349); no self-join | **PASS** |
| GQ-5 | `list_active_body_types` (hours=168) | ok | `OrderRequest:124`, `OrderResponse:66`, `(no body):33`; `window_start` present | **PASS** |
| GQ-6 | `describe_message_class` → `execute_readonly_sql` (pivot) | ok | 8 columns match `%Dictionary` (verified `OrderId`/`CustomerName`/`LineItems`); `has_additional_info:false` → honest no-AdditionalInfo path; supplemental discovered-column pivot: `none:68, businessOperationFailure:52, partialSuccess:4` via real `SessionAgent_Sample_Msg.OrderRequest` join on id+class | **PASS** |
| GQ-7 | `execute_readonly_sql` (`{fn TIMESTAMPDIFF}` > 20 s) | ok, 0 rows | empty set returned as clean `render_strategy:"ok"` envelope ("none found"), NOT an error | **PASS** |
| GQ-8 | `session_summary` → `message_headers(min_severity=error)` → `get_message_detail` → `explain_error` — ZERO `execute_readonly_sql` | all ok | session 13320: 7 msgs / 2 errors; failing components `SqlPersist`+`FilePublish` (headers 13325/13326); `explain_error` matched `<Ens>ErrGeneral` with decoded text + diagnostics | **PASS** |
| GQ-9 | `discover_tables` (fragment=Order) → `execute_readonly_sql` (INFORMATION_SCHEMA) | ok | 15 real tables, no invented names; `SessionAgent_Sample_Msg.OrderResponse` columns (ID, OrderId, PersistedRowId, ProcessedTimestamp, RejectionReason, Status) match INFORMATION_SCHEMA | **PASS** |
| GQ-10 | `get_query_knowledge` (topic=dialect → `integer-string-trap` article) + BOTH query forms | ok (SQLCODE 0 both — that IS the trap) | **trapped** `WHERE Status != 'Completed'` → `[[223]]` = ENTIRE 1-day window (223 total — every row silently matched); **corrected** `%EXTERNAL(Status) != 'Completed'` → `[[27]]`. Delta 223 vs 27 with zero error envelope = the silent-wrong-results failure mode, demonstrated verbatim | **PASS** |
| GQ-11 | `session_timeline` + `execute_readonly_sql` (full-trace SQL) cross-check | ok | both return 7 hops for session 13320 in identical order (ID tiebreak); SQL renders `%EXTERNAL(Status)` words (`Completed`/`Error`); tool integers 9/8 reconcile to the same enum values | **PASS** |
| GQ-12 | discovery query (`%EXACT(TargetConfigName)` GROUP BY) → `execute_readonly_sql` recipe | ok | live-discovered name `SessionAgent.Sample.BP.OrderRouter` (NOT guessed); daily counts `["2026-06-11",124]` = router total from GQ-2 | **PASS** |
| GQ-13 | `execute_readonly_sql` (aggregate-first subquery + `LEFT JOIN Ens_Config.Item`) | ok, 6 rows | each source annotated with real host class (e.g. `OrderRouter` 93); framework `Ens.ScheduleService` correctly unannotated (no production item) | **PASS** |

**Schema-note round-trip (AC-4 save-then-re-read):** `save_schema_note`
(`ztest-gq145-orderrequest-shape`) → `{"action":"created","audit_emitted":1}` →
`get_schema_notes(subject_fragment=ztest-gq145)` returned the note verbatim (`age_days:0`)
→ fixture swept via `SchemaNoteToolTest.DeleteFixtureRows` → re-read returned `count:0`. **PASS**

**Notes for the epic-end walkthrough.**
- `%ODBCOUT(ErrorStatus)` decodes with an Arabic severity label (`خطأ`) on this instance —
  server NLS rendering, identical via direct `iris_sql_execute` (NOT a tool-path defect).
- Unwrapped string columns in a SELECT list render case-folded (GQ-2's UPPERCASE names);
  `%EXACT(col) AS alias` preserves case (used in GQ-4/12/13 discovery) — consistent with
  guide §01 and the Story 13.3 aliasing rule.
- **Outcome: 13/13 PASS + schema-note round-trip PASS; zero toolchain failures — nothing to
  fix-now under Rule 8.**

---

## User-led live walkthrough — Epic 14 close (Rule 6 bullet 5), 2026-06-11

**Method.** Driven through the chat panel in a real browser (chrome-devtools MCP) against the
live sample production; provider gpt-4.1-mini unless noted. Screenshots in
`_bmad-output/implementation-artifacts/evidence/walkthrough-*.png`.

| GQ | Outcome | Notes |
|---|---|---|
| GQ-1 | **PASS** | First SQL attempt prepare-failed (visible error tool-card), agent self-corrected; honest one-day-of-data caveat (293 msgs / 47 sessions) |
| GQ-2 | **PASS** | Error rates per target (FilePublish 19/41, SqlPersist 18/41) |
| GQ-3 | **PASS (route note)** | Correct top failure modes; used event-log tools rather than the %ODBCOUT SQL grouping |
| GQ-4 | **PASS** | Slow tail 4-8ms; self-corrected from -29; used describe_message_class mid-loop |
| GQ-5 | **PASS** | Preferred typed list_active_body_types (164/86/43) |
| GQ-6 | **PASS** | True 8-field shape; honest no-AdditionalInfo; real-column pivot |
| GQ-7 | **PASS** | Empty result presented as "none found", not an error |
| GQ-8 | **PASS (after 1 transient)** | First attempt hit a non-reproducing OpenAI HTTP 431 (header sizes instrumented normal on success; investigated per Rule 5, not reproduced); retry: tool-first diagnosis, injected SqlPersist+FilePublish failures named |
| GQ-9 | **PASS (with nudge)** | Agent's first fragments missed; operator nudge -> real tables + exact OrderResponse columns; no invented names |
| GQ-10 trap | **PASS** | Agent used typed search_by_status with enumerated statuses (audit 333) — coercion trap had no surface; 19 genuinely-filtered results |
| GQ-11 | **PASS (polish note)** | Full chronological table with error flags; statuses shown as integer codes not %EXTERNAL words |
| GQ-12 | **PASS** | Component name discovered first; 123/day |
| GQ-13 | **PASS** | Per-source volumes annotated with real host classes; honest not-found for framework service |
| Schema note | **PASS** | save_schema_note in one conversation; BRAND-NEW conversation recalled the fact via first-turn digest (digest char-cap visible in quote) |
| EXPLAIN (14.6) | **PASS** | Plan-reasoning answer: master-map scan, temp-file aggregation, no TimeCreated index, optimization offer |

**Multi-provider spot-check (credential probe first; all resolvable):**
- anthropic / claude-haiku-4-5-20251001 — tool round trip + disclosed SQL (audit 404-405); integer predicate per card, though enum value guessed (model-quality note)
- gemini / gemini-2.5-flash — tool round trip + disclosed SQL (audit 406-407)
- openai-compatible / Ollama @ 192.168.0.123:11434 — **walkthrough fix-now**: bare-host EndpointUrl normalized to /chat/completions (no /v1) -> live 404; `NormalizeChatCompletionsLocation` case-4 fixed to /v1/chat/completions + regression test (4/4). Post-fix the request reaches Ollama and OpenAI-shaped envelopes round-trip (model-capability 400 for dolphin3 rendered cleanly; full tool round trip blocked on a tools-capable model loading on that box — its resident gemma-4:31b was busy). Timeout path also exercised: graceful mid-flight-failure envelope.

**Defects caught by the walkthrough/battery (all fixed or documented):**
1. Ambient test pollution of live Config.Agent rows (Enabled=0 earlier; EnvVarName=PATH at battery time) from interrupted test runs — restored both times; durable-fix candidate for the retro.
2. OpenAICompat bare-host URL 404 — fixed now (commit pending), test-locked.
3. Transient OpenAI HTTP 431 (1 occurrence, not reproduced, instrumentation showed normal header sizes on success) — documented.
4. Cosmetic: curated session-list renderer shows "Unknown(undefined)" rows when fed SQL-shaped rows missing expected fields (GQ-12) — retro polish candidate.
