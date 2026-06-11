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
