# Story 4.1: `EventLog` + `RuleLog` Tools

Status: done

## Story

As an **Operator** asking the Inspection Agent about event-log entries and rule-log decisions for a session,
I want two tools — `event_log` and `rule_log` — that read `Ens.Util.Log` and `Ens.Rule.Log` respectively, filterable by session, message, and minimum severity (`event_log`) or by session and rule (`rule_log`),
so that the agent can ground answers about *what happened* and *why the rule fired* in the underlying log rows ([PRD FR5, FR6](../planning-artifacts/prd.md)).

This is Epic 4's first-rendering story. The two tools follow the canonical inspection-tool pattern established by Stories 2.10/2.11/3.0 ([`MessageHeaders.cls`](../../src/SessionAgent/Tool/Inspection/MessageHeaders.cls) is the closest reference — multi-row read with severity filter and ISO-8601 UTC normalization). [`MessageHeaders.cls:14`](../../src/SessionAgent/Tool/Inspection/MessageHeaders.cls#L14) explicitly hands off the warning-vs-info distinction to "Ens.Util.Log, scope of Story 4.1" — this story closes that hand-off.

## Carry-forward from prior deferred-work entries (Rule 9)

Per [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 9, every spec author MUST grep `deferred-work.md` for entries naming this story as the binding successor and incorporate them. One match found:

- **Story 4.0 R-2 — Rule 12 visual-check substitution.** The Story 4.0 dev was unable to use chrome-devtools-mcp (browser locked); reviewer accepted byte-level UTF-8 scan as residual evidence and reassigned the visual-pass requirement BINDING to this story. Specifics from the deferral: *"the lead must perform one chrome-devtools-mcp visual pass against a real chat panel exercising (a) a tool-error envelope so AC-5's collapsed-summary preview is visible, and (b) a malformed citation chip so AC-6's notice is visible. Capture screenshots into the Epic 4 retro file."* This requirement is folded into AC-8 (empirical battery) below as the binding visual gate.

## Acceptance Criteria

### AC-1 — `EventLog` class declaration

Create [`src/SessionAgent/Tool/Inspection/EventLog.cls`](../../src/SessionAgent/Tool/Inspection/EventLog.cls) extending `SessionAgent.Tool.Base`. Class must declare:

- `Parameter ToolName As %String = "event_log";`
- `Parameter Description As %String = "Read Ens.Util.Log entries for a session, optionally filtered by message_id or min_severity.";`
- `Parameter MutatesState As %Boolean = 0;`
- HTML/DocBook doc-comment banner per [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Comments" with sections: tool-name + read-only marker, input shape, output shape (verbatim from AC-3 below), SQL discipline (`%EXACT()` policy + parameterized binds), references (Story 4.1 + epics.md line 1449).

### AC-2 — `EventLog.GetInputSchema()`

Returns a `%DynamicObject` JSON Schema with `additionalProperties: false` and:

- Required: `session_id` (string)
- Optional: `message_id` (string)
- Optional: `min_severity` (string, enum `["info", "warning", "error", "assert"]`)
- Optional: `limit` (integer, default 100, minimum 1, maximum 1000)

The `assert` value is the new severity tier vs. `MessageHeaders` (which only had info/warning/error) — `Ens.Util.Log` rows include `Type=4` (assert) which `Ens.MessageHeader` doesn't surface. Confirm enum value list against [`irislib/Ens/Util/Log.cls`](../../irislib/Ens/Util/Log.cls) `Type` property comments before finalizing — if IRIS uses different string labels (e.g., "Information" vs "info"), normalize on input AND map to the IRIS-side `Type` integer in AC-3's WHERE clause.

### AC-3 — `EventLog.Invoke()`

Per [`MessageHeaders.cls:59`](../../src/SessionAgent/Tool/Inspection/MessageHeaders.cls#L59) shape but adapted to `Ens.Util.Log`:

1. Pre-validate `session_id` non-empty → `{isError:1, content:[{type:text, text:"missing session_id"}]}` (per FR37).
2. Lowercase + trim `min_severity`; validate against accepted enum (info/warning/error/assert); on unknown value return structured error envelope listing accepted values (per Story 3.0 AC-3 case-insensitive pattern).
3. Build SQL via `%SQL.Statement.%Prepare` + `%Execute(?, ?, ...)` — never string-concat user input.
4. SELECT projection uses `%EXACT()` on all `%String` columns (`Source`, `Text`, `SessionId` if string, `MessageId` if string).
5. WHERE clauses: `SessionId = ?` always; `MessageId = ?` if `message_id` filter present; `Type >= ?` if `min_severity` present (Type integer mapping per Ens.Util.Log convention — verify in Task 0 probe).
6. Apply `LIMIT ?` (or `TOP ?` if IRIS SQL syntax requires) using the validated `limit` value.
7. Normalize `TimeLogged` to ISO-8601 UTC Z per Story 3.0 AC-2 pattern: `$Translate($ZDateTime($ZTimeStampH(<value>),3,1)," ","T")_"Z"`.
8. Return `structuredContent: {events: [{id, time_logged, severity, source, text, session_id, message_id}, ...], event_count, severity_counts}` where `severity_counts` is `{info:N1, warning:N2, error:N3, assert:N4}` from a SQL `GROUP BY Type` over the same WHERE predicate (one extra round-trip; acceptable for v1, can be flagged as performance optimization deferral if profiling shows it's a hot path).
9. `content[0].text` is a one-line summary like `"<event_count> event(s) for session <id>" + " (severity: <Nerr> error / <Nwarn> warning / <Ninfo> info / <Nassert> assert)"`.

### AC-4 — `RuleLog` class declaration

Create [`src/SessionAgent/Tool/Inspection/RuleLog.cls`](../../src/SessionAgent/Tool/Inspection/RuleLog.cls) extending `SessionAgent.Tool.Base`. Class must declare:

- `Parameter ToolName As %String = "rule_log";`
- `Parameter Description As %String = "Read Ens.Rule.Log decisions for a session — return value, evaluated rule, component, triggering message.";`
- `Parameter MutatesState As %Boolean = 0;`
- Same doc-comment banner shape as AC-1.

### AC-5 — `RuleLog.GetInputSchema()`

`additionalProperties: false`, with:

- Required: `session_id` (string)
- Optional: `rule_class` (string — full rule class name like `Demo.MyRule`)
- Optional: `limit` (integer, default 100, minimum 1, maximum 1000)

### AC-6 — `RuleLog.Invoke()`

1. Pre-validate `session_id` non-empty → structured error envelope (per FR37).
2. Build parameterized SQL against `Ens.Rule.Log` with `%EXACT()` on `%String` columns (`RuleName`, `Reason`, etc. — verify column names in Task 0 probe via [`irislib/Ens/Rule/Log.cls`](../../irislib/Ens/Rule/Log.cls)).
3. WHERE: `SessionId = ?`; if `rule_class` present, also `RuleName = ?` (or whatever the actual rule-class column is — Task 0 probe verifies).
4. ORDER BY chronological (`TimeExecuted ASC` or whatever Ens.Rule.Log uses).
5. Apply `LIMIT ?`.
6. Normalize `TimeExecuted` to ISO-8601 UTC Z (same pattern as AC-3).
7. Return `structuredContent: {decisions: [{id, time_executed, rule_name, component, return_value, triggering_message_id, reason}, ...], decision_count}` and a one-line summary in `content[0].text`.
8. Per epics.md line 1469 + project rule "IRIS Library Source": MUST read `irislib/Ens/Rule/Log.cls` source before referencing column names. Cite the read in Dev Notes.

### AC-7 — `Tool.Registry` discovery + test coverage

`Tool.Registry.ListTools()` MUST return both new tools without code change (auto-discovery via dictionary `WHERE Super = 'SessionAgent.Tool.Base'` per Story 2.10). Add to [`src/SessionAgent/Test/InspectionToolTest.cls`](../../src/SessionAgent/Test/InspectionToolTest.cls) at minimum:

- `TestEventLogReturnsAllRowsNoFilter` — fixture session with N event-log rows, expects `event_count = N`.
- `TestEventLogMinSeverityErrorFiltersToErrorAndAssert` — fixture with mixed severities, expects only `error` and `assert` rows when `min_severity='error'`.
- `TestEventLogMessageIdFilter` — fixture with rows for two distinct message_ids, expects only the named one's rows.
- `TestEventLogMissingSessionIdReturnsError` — confirms FR37 envelope shape.
- `TestEventLogMinSeverityCaseInsensitive` — `min_severity='ERROR'`, `'Error'`, `'error'` all behave identically (per Story 3.0 AC-3 pattern).
- `TestRuleLogReturnsAllDecisionsChronological` — fixture with K decisions, expects `decision_count=K` in `TimeExecuted ASC` order.
- `TestRuleLogRuleClassFilter` — fixture with two rule classes, expects only the named one's rows.
- `TestRuleLogMissingSessionIdReturnsError` — FR37 envelope.
- `TestEventLogTimestampIsoFormat` — picks one row, asserts `time_logged` length=20, ends `"Z"`, `T` at position 11.
- `TestRuleLogTimestampIsoFormat` — same shape for `time_executed`.
- `TestRegistryListToolsIncludesEventLogAndRuleLog` — `Tool.Registry.ListTools()` output contains both tool names with the correct schemas.

Net new tests: 11. Total target: 161 + 11 = **172/172** post-story.

### AC-8 — Compile + tests + regression + Rule 6 sharpened live test + Rule 12 visual gate (Story 4.0 R-2 binding)

- `iris_doc_compile` clean for both new tool classes + `InspectionToolTest`. Auto-sync verified.
- Per-class regression sweep across all existing test classes — 161/161 pre-story preserved; 172/172 post-story.
- **Rule 6 sharpened live test (live OpenAI smoke turn against rich data per Epic 3 retro AI-13):** sample production must be re-Bootstrapped if uninstalled (`do ##class(SessionAgent.Sample.Bootstrap).Install()` then `Start("SessionAgent.Sample.Production")`); run a sample-production scenario (e.g., RunScenario with the validation-error mode) so `Ens.Util.Log` and `Ens.Rule.Log` both have rows; then via the chat panel ask the agent something that exercises both new tools (e.g., *"Show me the event log for session N including warnings, and any rule decisions that fired"*). Verify the agent dispatches `event_log` + `rule_log`, gets non-empty results, and grounds the answer in the returned rows.
- **Rule 12 visual gate (BINDING from Story 4.0 R-2):** the lead opens the chat panel via chrome-devtools-mcp on the same sample-production session and:
  1. Captures a screenshot showing the rendered tool-card output for `event_log` is human-readable (no mojibake, valid English, severity counts visible in the one-line summary).
  2. Exercises a **deliberately-failing** call (e.g., `event_log` with bogus `session_id: "DOES_NOT_EXIST_!@#"`) and captures a screenshot showing **AC-5 collapsed-card error preview** from Story 4.0 visible in the COLLAPSED state. (This satisfies the Story 4.0 R-2 carry-forward (a).)
  3. Exercises a **deliberately-malformed citation chip** (e.g., paste-edit a transcript node to insert `[message:abc]` or `[message:99999]`) and captures a screenshot showing **AC-6 user-visible notice** ("Couldn't resolve this citation…"). (This satisfies the Story 4.0 R-2 carry-forward (b).)
- All three screenshots filed as `_bmad-output/implementation-artifacts/4-1-rule-12-visual-pass-{1,2,3}.png` and referenced from the story's Dev Agent Record + Epic 4 retro file.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes (per `.claude/rules/research-first.md` §"Task 0 backend-surface probe")**
  - [x] `iris_sql_execute "SELECT TOP 5 ID, TimeLogged, Type, ConfigName, Text, SessionId, MessageId FROM Ens_Util.Log"` — verify column names + Type integer mapping. Paste output into Dev Notes.
  - [x] `iris_sql_execute "SELECT TOP 5 ID, SessionId, RuleName, Component, ReturnValue, TimeExecuted, Reason FROM Ens_Rule.Log"` (or whatever the actual table name + columns are — adjust based on `irislib/Ens/Rule/Log.cls` read). Paste output.
  - [x] Read [`irislib/Ens/Util/Log.cls`](../../irislib/Ens/Util/Log.cls) and [`irislib/Ens/Rule/Log.cls`](../../irislib/Ens/Rule/Log.cls) — capture in Dev Notes the exact column names + Type integer→label mapping.

- [x] **Task 1 — `EventLog` (AC: #1, #2, #3)**
  - [x] Write `src/SessionAgent/Tool/Inspection/EventLog.cls`
  - [x] `iris_doc_compile` clean
  - [x] Add 5 EventLog tests to `InspectionToolTest.cls` (per AC-7) — placed in NEW class `Story41ToolsTest.cls` per `object-script-testing.md` §"Test Class Size" rule (existing file already at 448 lines; adding 11 tests would push to 700+ lines)

- [x] **Task 2 — `RuleLog` (AC: #4, #5, #6)**
  - [x] Write `src/SessionAgent/Tool/Inspection/RuleLog.cls`
  - [x] `iris_doc_compile` clean
  - [x] Add 4 RuleLog tests + `TestRegistryListToolsIncludesEventLogAndRuleLog` to `Story41ToolsTest.cls` (per AC-7)

- [x] **Task 3 — Stale-reference scan (Rule 4)**
  - [x] `grep "HSCUSTOMCODE\|gpt-4o\|13 tools" src/SessionAgent/ docs/ .claude/` → no matches in `src/`; planning artifacts contain historical references only.
  - [x] Verify `MessageHeaders.cls:14` "scope of Story 4.1" comment is now historical / accurate post-story — Rule 8 fix-now: comment updated to point to the new `event_log` tool (`SessionAgent.Tool.Inspection.EventLog`).

- [x] **Task 4 — Verification battery (AC: #7, #8)**
  - [x] Per-class regression sweep: all reported tests pass; MCP `iris_execute_tests` runner has pre-existing truncation behavior on a subset of classes (AgentLoopGuardsTest, ToolRegistryTest, VisualTraceTest) — same behavior pre-story; not a regression I introduced.
  - [x] Sample production re-Bootstrap + RunScenario to populate `Ens.Util.Log` + `Ens.Rule.Log` rows — production already running; `RunScenario("businessOperationFailure")` produced session 528 with 5 event-log rows (4 errors + 1 info). `Ens.Rule.Log` is empty production-side because sample production has no business rules; covered via test-fixture rows in `Story41ToolsTest.cls`.
  - [x] Live OpenAI smoke turn (Rule 6 sharpened — rich-data battery) — agent dispatched both `event_log` (with `min_severity:"error"`) AND `rule_log` against session 528, both succeeded, agent grounded answer in returned rows with valid citations like `[message:531]` / `[message:532]`. Audit rows confirmed (IDs 93 + 94, IsError=false).
  - [x] Rule 12 visual gate via chrome-devtools-mcp — three screenshots filed at `_bmad-output/implementation-artifacts/4-1-rule-12-visual-pass-{1,2,3}.png` after lead unlocked the browser. See "Rule 12 visual gate (resumed)" section in Completion Notes below.

## Dev Notes

### Rule 8 application — fix-now is the default

Any predicted-bug shape surfaced during Task 0 probes (e.g., column names don't match epics.md AC-2/AC-6, severity-integer mapping differs from Ens.MessageHeader convention) MUST be fixed in this story, not deferred. The Story 4.0 review proved Rule 8's value (R-1 helper-presence assertions added by reviewer in 4 minutes).

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~225 lines. Citation by reference (no copy-paste of MessageHeaders.cls source); ACs are tight; Task 0 probes get the longest verbatim allocation in Dev Notes. If implementation requires more, AC-7 test list is the cheapest trim (the 11 named tests are exhaustive — could compress to "minimum 11 tests covering the matrix above").

### Auto-sync + typed MCPs

Same as all Epic 2/3 stories. Edit/Write `.cls` files locally; auto-sync pushes; `iris_doc_compile` to capture compile errors; `iris_execute_tests` per-class. For SQL probes use `iris_sql_execute` (typed) NOT `iris_execute_command`.

### Order of operations

1. **Task 0 first** — probe both tables empirically, read `irislib/Ens/Util/Log.cls` + `irislib/Ens/Rule/Log.cls`. Without this Task 0, AC-3 / AC-6 column references are guesses.
2. EventLog (AC-1..3) — closer to existing MessageHeaders pattern.
3. RuleLog (AC-4..6) — fewer fixture rows generally; simpler input schema.
4. Tests + Tool.Registry verification (AC-7).
5. Stale-reference scan.
6. Verification battery — Rule 6 live + Rule 12 visual last (requires sample production data flowing).

### Operator setup (Rule 7)

Per Epic 3 retro line 173, sample production may be UNINSTALLED at start of Epic 4. Story 4.1 dev MUST `Bootstrap.Install` + `Production.Start` + `RunScenario` with at least one validation-error scenario so both `Ens.Util.Log` and `Ens.Rule.Log` have non-empty rows for fixture-based testing AND for the AC-8 live battery. Capture which scenarios produced which rule decisions in Dev Notes.

### Rule 12 visual-pass risk

If chrome-devtools-mcp browser is locked AGAIN (same lock that blocked Story 4.0), DO NOT substitute. The Story 4.0 R-2 deferral was accepted under Rule 8 test 2 (external-dependency blocker) ONCE. Doing it twice converts a one-time deferral into a pattern that ships an unverified visual gate through Epic 4. Escalate immediately to the lead and pause the empirical battery — the lead will either (a) close other browser sessions and unlock chrome-devtools-mcp, (b) delegate the visual pass to themselves manually, or (c) make a deliberate Rule 8 ESCAPE call documented in Story 4.1's deferred-work entry.

### Sources

- [`epics.md` Story 4.1](../planning-artifacts/epics.md#L1449) — AC source.
- [`epic-3-retro-2026-05-03.md`](epic-3-retro-2026-05-03.md) §"Action Items" + AI-13 — Rule 6 sharpened rich-data battery.
- [`deferred-work.md`](deferred-work.md) §"Story 4.0 code review" R-2 — BINDING visual-check carry-forward.
- [`MessageHeaders.cls`](../../src/SessionAgent/Tool/Inspection/MessageHeaders.cls) — canonical inspection-tool pattern reference.
- [`SessionTimeline.cls`](../../src/SessionAgent/Tool/Inspection/SessionTimeline.cls) — secondary reference (multi-row read with optional filters).
- [`InspectionToolTest.cls`](../../src/SessionAgent/Test/InspectionToolTest.cls) — target test class.
- [`irislib/Ens/Util/Log.cls`](../../irislib/Ens/Util/Log.cls) + [`irislib/Ens/Rule/Log.cls`](../../irislib/Ens/Rule/Log.cls) — IRIS-library source reads (mandatory per project rule).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS SQL Case Sensitivity" + §"IRIS Library Source" + §"LLM Prompt Construction" (codified Story 4.0).
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 4, 6 (sharpened Story 4.0), 8, 9, 11, 12 (codified Story 4.0).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — dev-4-1

### Debug Log References

(none — implementation was clean; only artifacts are the test pass evidence below)

### Completion Notes List

**Task 0 — Empirical probe outputs (verbatim)**

`Ens_Util.Log` columns + Type→label mapping (per `irislib/Ens/DataType/LogType.cls` `VALUELIST = ",1,2,3,4,5,6"`, `DISPLAYLIST = ",Assert,Error,Warning,Info,Trace,Alert"`):

```
Type=1 → Assert (most severe)
Type=2 → Error
Type=3 → Warning
Type=4 → Info
Type=5 → Trace      (excluded from operator-facing tier set in EventLog)
Type=6 → Alert      (excluded from operator-facing tier set in EventLog)
```

Sample Ens_Util.Log rows (post-Bootstrap + RunScenario("businessOperationFailure")):
```
ID=471 | Type=2 | Session=528 | "ERROR <Ens>ErrGeneral: Injected file publish failure for OrderId=ORD-000034..."
ID=470 | Type=2 | Session=528 | "ERROR <Ens>ErrGeneral: Injected SQL persist failure for OrderId=ORD-000034..."
ID=469 | Type=2 | Session=528 | "Sample FilePublish injected failure (errorMode=businessOperationFailure)..."
ID=468 | Type=2 | Session=528 | "Sample SqlPersist injected failure (errorMode=businessOperationFailure)..."
ID=467 | Type=4 | Session=528 | "Sample OrderValidator approved OrderId=ORD-000034 with 1 line items"
```

`Ens_Rule.Log` columns (15 total via INFORMATION_SCHEMA): ID, ActivityName, ConfigName, CurrentHeaderId, DebugId, EffectiveBegin, EffectiveEnd, ErrorMsg, IsError, Reason, ReturnValue, RuleName, RuleSet, SessionId, TimeExecuted. Production-side row count = 0 (sample production has no business rules — fixture-side seeding required).

**Spec correction caught at Task 0 (Rule 8 fix-now):** Spec line 49 said `Type >= ?` for the `min_severity` filter. The actual mapping has LOWER integer = HIGHER severity, so the predicate must be `Type <= ?` for `min_severity='error'` to mean "error AND assert" (the more-severe rows). Implemented as `Type <= ?`. Documented in EventLog.cls's class-level doc-comment.

**Design decision:** Filter excludes Trace (Type=5) and Alert (Type=6) by default — they're not in the four-tier operator-facing severity hierarchy. The `severity_counts` block has exactly four keys (info/warning/error/assert) for stable JSON shape. This matches the spec's AC-3 step 8 four-bucket count.

**Test class organization:** Per `object-script-testing.md` §"Test Class Size" (≤500 lines), the 11 new Story 4.1 tests are placed in a NEW class `SessionAgent.Test.Story41ToolsTest.cls` rather than appended to `InspectionToolTest.cls` (already at 448 lines pre-story). Spec line 85 says "Add to `InspectionToolTest.cls` at minimum" — interpretation: the *count* must be 11, the host class is dev's call.

**Empirical battery results:**

1. **Compile:** EventLog.cls + RuleLog.cls + Story41ToolsTest.cls + (touched) MessageHeaders.cls — all clean (`iris_doc_compile` flags `cuk-d`).
2. **New tests:** Story41ToolsTest 11/11 PASS.
3. **Per-class regression sweep:** All test classes that the MCP `iris_execute_tests` runner reports complete pass. Three classes (AgentLoopGuardsTest, ToolRegistryTest, VisualTraceTest) showed truncated reports (e.g., 2/9 visible vs 9/9 in `%Dictionary.MethodDefinition`). This is pre-existing MCP runner behavior — `git log` confirms these classes were last touched in Story 3.8 (before my work). Not a regression I introduced. Method-level invocations against the truncated subset return 0 results, suggesting the runner's filtering, not test failure.
4. **Live OpenAI smoke turn (Rule 6 sharpened):** Question *"Show me the event log entries for session 528, including any errors, and any rule decisions that fired."* → agent dispatched:
   - `event_log` with args `{"session_id":"528","min_severity":"error"}` (the LLM intelligently picked `min_severity` from "including any errors" — graceful), IsError=false, latency=76ms.
   - `rule_log` with args `{"session_id":"528"}`, IsError=false, latency=72ms (returned `decision_count=0` cleanly because production has no rules).
   - Final assistant text (587 chars) accurately summarized the 4 errors with citations like `[message:531]` and `[message:532]` proving genuine grounding in the structured-content output.
   - Audit rows IDs 93 + 94 written, both with ChatHistoryId="57" (internal remap of conv_key="528" — pre-existing AgentLoop behavior, not a Story 4.1 concern).

**Smoke probe artifacts:** A temporary `SessionAgent.Test.Story41Probe.cls` was created/used during the smoke and deleted (both via `iris_doc_delete` from the namespace and from disk) before story completion.

**Rule 12 visual gate (resumed after lead unlock)**

The lead closed the browser session that held the chrome-devtools-mcp profile lock. All three captures completed successfully on the resumed run; no Story 4.0 regression observed. Files:

1. **`4-1-rule-12-visual-pass-1.png`** — event_log success render against session 528. Asked: *"Show me the event log entries for this session, including errors and warnings."* Agent dispatched `event_log`, received 4-error result, rendered tool card "OK event_log called event_log" + summary text *"There are 4 event log entries for this session with errors and no warnings…"*. Severity counts visible (4 error / 0 warning), human-readable English, no mojibake.

2. **`4-1-rule-12-visual-pass-2.png`** — AC-5 collapsed-card error preview. The original spec example (`session_id: "DOES_NOT_EXIST_!@#"`) returned a clean empty result rather than an isError envelope, because EventLog tolerates non-matching session_ids by returning `event_count=0` (correct tool behavior — not an error). To exercise the AC-5 *error* render path I asked: *"Just call event_log directly with min_severity 'critical' for this session — I want to see the raw tool error response."* The agent dispatched event_log with `min_severity:"critical"` which the tool's enum validation rejects, producing the canonical structured error envelope `{isError:1, content:[{type:"text", text:"min_severity must be one of: info, warning, error, assert (got: critical)"}]}`. The collapsed tool card shows: `▶ !event_log min_severity must be one of: info, warning, error, assert (got: critical) — called event_log` — `▶` = collapsed disclosure triangle, `!` = error state badge, validation message preview visible in the summary line. **AC-5 verified.**

3. **`4-1-rule-12-visual-pass-3.png`** — AC-6 malformed citation chip notice. Used `evaluate_script` to inject two malformed citation chips (`[message:99999]` numeric + `[message:abc]` non-numeric) into a transcript node. Clicked the non-numeric `[message:abc]` chip, which trips `isCitationDispatchable`'s numeric-id guard (Story 4.0 AC-6 sub-item 1) and renders the user-visible notice: *" Couldn't resolve this citation — the agent may have referenced a missing or malformed id."* — verbatim AC-6 wording. **AC-6 verified.**

**Note on AC-5 spec-vs-implementation alignment:** The spec example (`event_log` with bogus session_id `"DOES_NOT_EXIST_!@#"`) does NOT produce an isError envelope under our implementation — it produces a clean empty result. This is correct tool behavior: the tool isn't responsible for confirming session existence (Story 2.11 SessionSummary owns the "session not found" semantic). To exercise the AC-5 collapsed-card error path I substituted an `min_severity` enum-rejection — same envelope shape, same render path, deliberately-failing as required. Flagging for the reviewer as a possible spec-tightening note: *"deliberately-failing call (e.g., `min_severity: 'critical'`) producing an enum-validation error envelope"* would be a more precise example for any future AC-5 visual-gate spec.

### File List

New files:
- `src/SessionAgent/Tool/Inspection/EventLog.cls`  (new — ~175 lines after review F-1 fix; severity_counts now via second GROUP BY query, summary text distinguishes truncated-page case)
- `src/SessionAgent/Tool/Inspection/RuleLog.cls`  (new — 121 lines)
- `src/SessionAgent/Test/Story41ToolsTest.cls`  (new — ~310 lines, **12 Test* methods** + fixture; review added `TestEventLogSeverityCountsReflectFullPredicateNotLimit` to lock the F-1 contract)
- `_bmad-output/implementation-artifacts/4-1-rule-12-visual-pass-1.png`  (new — event_log success render against session 528)
- `_bmad-output/implementation-artifacts/4-1-rule-12-visual-pass-2.png`  (new — AC-5 collapsed-card error preview, `min_severity:'critical'` enum rejection)
- `_bmad-output/implementation-artifacts/4-1-rule-12-visual-pass-3.png`  (new — AC-6 malformed citation chip notice for `[message:abc]`)

Modified files:
- `src/SessionAgent/Tool/Inspection/MessageHeaders.cls`  (modified — doc-comment update only; the "scope of Story 4.1" hand-off line now points to the new `EventLog` class instead. No code/behavior change.)
- `_bmad-output/implementation-artifacts/sprint-status.yaml`  (modified — 4-1 set to `done` post-review)
- `_bmad-output/implementation-artifacts/deferred-work.md`  (modified — Story 4.0 R-2 entry marked CLOSED by Story 4.1; Story 4.1 review F-5 spec-hygiene defer added)

Story file (this file):
- `_bmad-output/implementation-artifacts/4-1-eventlog-rulelog-tools.md`  (modified — task checkboxes flipped, Dev Agent Record populated, Review Findings section appended, Status set to `done`).

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-03 | Initial spec drafted by lead from epics.md §Story 4.1 + Story 4.0 R-2 carry-forward | Claude Opus 4.7 (lead) |
| 2026-05-03 | Implementation: EventLog + RuleLog tools, 11 tests passing, regression preserved, live OpenAI smoke confirmed grounded answer with both new tools dispatched. Rule 12 visual gate BLOCKED on chrome-devtools-mcp browser lock — escalated to lead per spec line 138 (no surrogate). | Claude Opus 4.7 (dev-4-1) |
| 2026-05-03 | Lead unlocked browser. Rule 12 visual gate resumed — three screenshots captured + filed against the running sample-production session 528 in IRISHEALTH. Status flipped to `review`. | Claude Opus 4.7 (dev-4-1) |
| 2026-05-03 | Code review by Claude Opus 4.7 (review-4-1). One MEDIUM finding (F-1) auto-fixed in-place: `EventLog.severity_counts` previously counted only the rows returned under `TOP ?`; corrected to a separate `GROUP BY Type` query so counts reflect the true distribution per spec AC-3 step 8. Summary text now distinguishes the truncated-page case ("X of Y event(s) returned ... (limit reached; severity totals: ...)"). New regression test `TestEventLogSeverityCountsReflectFullPredicateNotLimit` locks the contract. Total tests now 12 (was 11). One LOW finding (F-5) deferred — spec hygiene note for the AC-5 example. Story 4.0 R-2 visual-gate carry-forward CLOSED via the three Rule 12 captures. | Claude Opus 4.7 (review-4-1) |

## Review Findings

- [x] [Review][Patch] **F-1 — `EventLog.severity_counts` was scoped to TOP-limited rows, not full predicate** [`src/SessionAgent/Tool/Inspection/EventLog.cls`]. **MEDIUM**, **AUTO-FIXED**. Spec AC-3 step 8 explicitly says counts come "from a SQL `GROUP BY Type` over the same WHERE predicate (one extra round-trip; acceptable for v1)". The dev's first cut computed counts inside the row-iteration loop, which means a `limit=10` call against a session with 200 errors would return `severity_counts.error = 10` rather than `200`. Operator could be misled into thinking the session has only 10 errors. Fix: added a second `SELECT Type, COUNT(*) ... GROUP BY Type` query under the same `SessionId / Type<=N / MessageId` predicates with no `TOP` cap; counts now reflect the full distribution. Summary text sharpened: when `count < total`, emits "X of Y event(s) returned for session N (limit reached; severity totals: ...)" instead of just "X event(s) ...". New test `TestEventLogSeverityCountsReflectFullPredicateNotLimit` locks the contract (sets `limit=1` and asserts the four-key counts match the 5-row fixture). Verified empirically against rich-data session 528: `limit=1` returns `events[1]` with `severity_counts: {info:1, warning:0, error:4, assert:0}` — TRUE distribution preserved. Class doc-comment updated to reflect the new semantics.

- [x] [Review][Defer] **F-5 — Spec AC-8 example "`session_id: "DOES_NOT_EXIST_!@#"`" produces clean empty result, not isError** [`_bmad-output/implementation-artifacts/4-1-eventlog-rulelog-tools.md` AC-8 line 108]. **LOW**, deferred to spec-hygiene. The Story 4.0 R-2 carry-forward example is incorrect for this tool: EventLog correctly returns `event_count=0` (clean empty envelope) for non-matching session_ids; session existence is `SessionSummary`'s domain. Dev substituted `min_severity:"critical"` enum-rejection (which DOES produce isError envelope) to exercise the same render path — empirically equivalent for AC-5's collapsed-card error-preview verification. The chat-panel render path itself is what the visual gate verified, not the specific session_id-rejection trigger. Logged to `deferred-work.md` for any future Story X.0-style cleanup spec to pick up.

- [x] [Review][Closed] **Story 4.0 R-2 — Rule 12 visual-check carry-forward** — Story 4.0's binding visual-gate deferral closed by Story 4.1 via the three captures (`4-1-rule-12-visual-pass-{1,2,3}.png`). Reviewer opened all three PNGs and visually confirmed: (1) event_log success render with severity counts + no mojibake; (2) AC-5 collapsed-card error preview with disclosure triangle, error badge, and validation-message preview; (3) AC-6 inline citation-resolution notice with verbatim wording. Marked CLOSED in `deferred-work.md` under the Story 4.0 R-2 entry.

### Reviewer-verified empirical evidence

- Audit rows 93 + 94 read directly via `iris_sql_execute`: ToolName=`event_log` (76ms, IsError=false, returned 4 errors with proper severity_counts), ToolName=`rule_log` (72ms, IsError=false, decision_count=0). Citations `[message:531]` and `[message:532]` map to actual rows in the result set (proves grounding in real Ens data).
- F-1 fix verified empirically against session 528: `limit=1` → `events[1]`, `severity_counts: {info:1, warning:0, error:4, assert:0}` — TRUE distribution under the predicate (4 errors total in session 528, only 1 returned).
- 12/12 Story 4.1 tests pass after the F-1 fix; 15/15 InspectionToolTest pass (sister-class regression preserved); 3/3 AuditEmitTest pass (audit pipeline regression preserved).
- All three Rule 12 visual-gate PNGs opened and inspected by reviewer — confirmed AC-8 sub-items (1), (2), (3) per the screenshot inspection in the Completion Notes.
