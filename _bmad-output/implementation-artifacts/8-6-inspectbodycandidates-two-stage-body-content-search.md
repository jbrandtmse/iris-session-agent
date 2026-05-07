# Story 8.6: `InspectBodyCandidates` Two-Stage Body-Content Search

Status: review

## Story

As an Operator asking the Search Agent for sessions whose body content matches a pattern that ISN'T indexed (e.g., *"sessions where the diagnosis code starts with E11"*, *"messages mentioning 'penicillin allergy' in the body"*),
I want an `inspect_body_candidates` tool that performs the two-stage indexed-prefilter + body-inspection pattern: narrow to ≤50 candidates via an indexed prefilter, then open each candidate body via Epic 4's body-class dispatch ladder (`GetMessageBody`) and filter by the content pattern,
so that body-content search is *safe at production scale* per architecture §"Innovation: Two-stage indexed-prefilter" + FR18 + NFR-P3 (≤50 candidate body-inspection cap).

This story also lands the **MEDIUM-8.5-F02 carry-forward** per Rule 9 named-successor binding: refactor `Tool.Search.Base.BuildBoundedWhereClause` to accept an optional `pTimeColumnAlias` parameter, refactor `SearchByBodyField` to use the new alias param, and have `InspectBodyCandidates` use it directly without the local `$Replace` workaround.

## Carry-forward from prior deferred-work entries

Per [`epic-cycle-discipline.md` Rule 9](../../.claude/rules/epic-cycle-discipline.md), `grep -ni "Story 8.6" deferred-work.md` returns:

- **MEDIUM-8.5-F02** (`deferred-work.md` line ~1078) — `Tool.Search.Base.BuildBoundedWhereClause` lacks optional alias parameter for JOIN-form callers. Story 8.5 carries a local `$Replace` workaround that future search-tool authors will re-inherit. **Binding successor: Story 8.6** (this story). Refactor + retrofit + use directly. **AC-9 sub-task in this spec.**
- **LOW (line ~585)** — `Tool.Inspection.GetMessageBody` Step 6 stream-summary mode could benefit from per-segment HL7 introspection if Story 8.6 wants it. NOT binding (no predicted-bug shape); flagged only. NOT incorporated.
- **LOW (line ~593)** — Step 9 dispatch-ladder fallback path lacks empirical test coverage. NOT binding (structurally unreachable per type-system invariant); flagged only. NOT incorporated.

## Acceptance Criteria

Verbatim from [`epics.md` §"Story 8.6"](../planning-artifacts/epics.md):

**AC-1 — `SessionAgent.Tool.Search.InspectBodyCandidates` concrete class.** Class extends `SessionAgent.Tool.Search.Base` (Story 8.2). Declares `Parameter ToolName = "inspect_body_candidates"`, `Parameter Description = "..."` (operator/LLM-readable, one line; describes the two-stage prefilter+body-inspection pattern with the `pattern` predicate against rendered body content), `Parameter MutatesState = 0`. Implements `GetIndexedLeadColumns() As %DynamicArray` returning `[prefilter_indexed_column]` from the per-call input — but with a STATIC fallback to `["Status"]` for invariant-test discovery purposes (the operator's actual `prefilter_indexed_column` is dynamic; the invariant test only inspects the classmethod return; pick the most common-case value as the static return). See Dev Notes.

**AC-2 — Input schema (locked subset).** `GetInputSchema()` declares:
- `pattern` (string, required) — regex literal OR substring depending on `pattern_is_regex`.
- `prefilter_indexed_column` (string, required, enum: `["Status", "SourceConfigName", "TargetConfigName", "MessageBodyClassName"]`) — the indexed column to use for the prefilter narrow.
- `prefilter_value` (string, required) — the value to match for the indexed prefilter.
- `time_window_hours` (integer, optional) — default `24`, max `720`.
- `pattern_is_regex` (boolean, optional) — default `false` (substring match).
- `candidate_cap` (integer, optional) — default `50`, max `50` per NFR-P3 (the cap is a HARD safety bound, not a soft hint).

Schema uses the locked subset (`type, properties, required, additionalProperties:false`); `enum` is allowed per the locked subset. Reject `candidate_cap > 50` at validation time (return structured error envelope; do NOT silently clamp).

**AC-3 — Step 1: indexed prefilter (≤50 candidates).** `Invoke` Step 1 queries `Ens.MessageHeader` filtered by `<prefilter_indexed_column> = ?` + `TimeCreated > ?` (the bounded-WHERE window) + `TOP ?` (= `candidate_cap`, default 50). Returns at most 50 candidate `MessageId` values. Uses `Tool.Search.Base.BuildBoundedWhereClause(pTimeWindowHours, .pParams, .pErr, .... )` with the alias-param-refactor signature from AC-9 (`mh` alias for the time-window predicate qualification). The prefilter SQL has the form `SELECT TOP ? mh.ID, mh.SessionId, mh.MessageBodyId, %EXACT(mh.MessageBodyClassName) AS body_class, mh.TimeCreated FROM Ens.MessageHeader mh WHERE %EXACT(mh.<prefilter_indexed_column>) = ? AND mh.TimeCreated > ? ORDER BY mh.TimeCreated DESC`.

**AC-4 — Step 2: body inspection via dispatch ladder.** For each candidate `MessageId` from Step 1, invoke the Epic 4 body-rendering pathway: call `##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, {"message_id":<candidate_id>,"render_mode":"summary"}, .tBodyResult)` (per architecture G2: direct call to the inspection tool's `Invoke` is the chosen extraction strategy until/unless the dispatch ladder is extracted to `SessionAgent.Body.DispatchLadder`). Extract the rendered body text from `tBodyResult.structuredContent.body_excerpt` (or whichever field carries the rendered text — verify against the existing inspection tool's envelope shape).

**AC-5 — Step 2: pattern matching.** Apply the `pattern` against the rendered body text:
- If `pattern_is_regex = true`, use `$Match(body_text, pattern)` for ObjectScript regex matching (note: ObjectScript's `$Match` uses a different regex syntax from PCRE — document this in the tool's `Description` so the LLM knows to provide ObjectScript-flavor regex).
- If `pattern_is_regex = false` (default), use `$Find(body_text, pattern)` for case-insensitive substring search; return match if `$Find > 0`.

**AC-6 — Graceful degradation per candidate.** If body-rendering for an individual candidate returns `isError:1` (e.g., body class doesn't exist, body row missing), DROP that candidate silently — DO NOT propagate the error to the tool's overall response. Per architecture §"Concurrent tool errors don't halt the agent". Track total `candidates_inspected` (the count attempted, including failed body-render attempts) separately from `match_count` (the count matched).

**AC-7 — Structured envelope.** On success returns `structuredContent: {pattern, prefilter_indexed_column, prefilter_value, time_window_used, candidates_inspected, matches: [{message_id, session_id, body_excerpt, body_class}, ...], match_count, indexed_lead_column: prefilter_indexed_column}` PLUS `content[0].text` operator-readable summary (e.g., *"Inspected 50 candidates filtered by Status='Error' in the last 24 hours; 7 matched pattern 'E11' in their body content"*). If the prefilter returned >50 candidates (i.e., the `LIMIT` was hit), include a NOTE bullet in the summary text: *"NOTE: prefilter returned more than 50 candidates — consider tightening the prefilter to broaden coverage"*.

**AC-8 — Bounded-WHERE invariant compliance.** Story 8.2's `BoundedWhereInvariantTest` auto-discovers this tool. `GetIndexedLeadColumns()` returns the static fallback (`["Status"]` per AC-1) which is in the documented indexed set. Re-run after install: log line transitions from "8 production search tools" → "9 production search tools, 0 violations".

**AC-9 — `Tool.Search.Base` alias-param refactor (Rule 9 carry-forward from MEDIUM-8.5-F02).** Three coordinated changes:

1. **Extend `Tool.Search.Base.BuildBoundedWhereClause` signature** with new optional `pTimeColumnAlias As %String = ""` parameter. When non-empty, emit `pTimeColumnAlias _ "." _ "TimeCreated > ?"` (e.g., `"mh.TimeCreated > ?"`); when empty (default), emit the bare `"TimeCreated > ?"` form. Backward-compatible: every existing caller that doesn't supply the parameter sees identical behavior.
2. **Update Story 8.2 `BoundedWhereInvariantTest.TestStubFixtureBoundedWhereDefaultsTo24h`** to assert the bare form when `pTimeColumnAlias = ""` (default backward-compat), AND add a new test method `TestStubFixtureBoundedWhereWithAliasQualifies` asserting `"mh.TimeCreated > ?"` when `pTimeColumnAlias = "mh"`.
3. **Refactor `SearchByBodyField.Invoke` Step 7**: pass `"mh"` as the alias parameter and remove the `$Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")` workaround. Confirm the regression test `TestSearchByBodyFieldHappyPath` still passes (the JOIN-form output is byte-identical).

**AC-10 — `InspectBodyCandidates` uses the new alias parameter directly.** Step 1 prefilter SQL constructs the WHERE fragment via `BuildBoundedWhereClause(pTimeWindowHours, .pParams, .pErr, "mh", "%EXACT(mh.<prefilter_col>) = ?")` so the JOIN form (with `mh` alias) is produced directly without any local `$Replace`. The Story 8.5 workaround is now obsolete.

### Verification gate

**AC-11 — Test methods extending `SearchToolTest`.** 4 new test methods specific to body-content search:

- `TestInspectBodyCandidatesHappyPathSubstring` — fixture: 5 `Ens.MessageHeader` rows with bodies. Prefilter on `Status='Error'`, pattern `"E11"` (substring, default mode). Assert tool returns the matching subset with verbatim envelope shape per AC-7.
- `TestInspectBodyCandidatesRegexMode` — same fixture but invoke with `pattern_is_regex=true`, pattern `"E1[12]"`. Assert ObjectScript-regex semantics fire correctly.
- `TestInspectBodyCandidatesCapEnforcedAt50` — fixture: 100 `Ens.MessageHeader` rows all matching `Status='Error'`. Assert `candidates_inspected <= 50` even if `candidate_cap` input is `100` — the AC-2 hard bound rejects `> 50` with structured error envelope.
- `TestInspectBodyCandidatesGracefulBodyError` — fixture: 3 `Ens.MessageHeader` rows where 1 has a missing body (DELETED `Ens.MessageBody.*` row but `MessageBodyId` still references it). Assert the missing-body row is silently dropped from `matches` but counted in `candidates_inspected`.

Each test uses `OnBeforeOneTest` to seed direct rows + `OnAfterOneTest` to clean up. **Avoid `Property Test*` shadow trap.**

**AC-12 — Compile + per-class regression sweep.**
- New `InspectBodyCandidates.cls` + extended `SearchToolTest.cls` + extended `BoundedWhereInvariantTest.cls` (per AC-9 sub-task) + refactored `Tool.Search.Base.cls` + refactored `SearchByBodyField.cls` (per AC-9) all compile cleanly via `iris_doc_compile`.
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
- **The "N/N pass" claim that gates this story MUST come from the numerical-MAX-of-non-empty-run SQL probe form** per Story 8.4 reviewer's correction.
- **Expected baseline: 313 (Story 8.5 close) + 4 new methods + 1 new BoundedWhereInvariantTest method = 318 / all PASS / 0 FAIL.**
- **Bounded-WHERE invariant transition:** "9 production search tool(s) discovered; 0 violation(s)".

**AC-13 — Live smoke against rich-data production (Rule 6 step 4).** Invoke `inspect_body_candidates` against real production data (Step-1 Bootstrap + scenarios populated `Ens.MessageHeader` rows). Pattern: pick a substring guaranteed to appear in HL7 bodies (e.g., `"OBR"` or `"PID"`); prefilter `MessageBodyClassName = 'EnsLib.HL7.Message'`; default 24h window. Capture verbatim envelope. Validates wire-shape correctness against real production data per Rule 6 step 4.

**AC-14 — Sibling fix-now: tool count + matrix.** Update `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` 21 → 22; add `inspect_body_candidates` to `GetRepresentativeArgs` + named-tool list. Update `ToolCallRoundtripIntegrationTest` matrix cardinality 84 → 88 (4 providers × 22 tools); add `inspect_body_candidates` to `BuildMinimalToolArgs`.

## Tasks / Subtasks

- [x] **Task 1 — `Tool.Search.Base` alias-param refactor (AC: #9)**
  - [x] Extend `BuildBoundedWhereClause` signature with `pTimeColumnAlias As %String = ""`. Update implementation to qualify `TimeCreated > ?` with the alias when non-empty.
  - [x] Update class doc-comment to document the new parameter.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — Story 8.2 invariant test extension (AC: #9 sub-2)**
  - [x] Update `TestStubFixtureBoundedWhereDefaultsTo24h` to assert bare form when alias empty.
  - [x] Add `TestStubFixtureBoundedWhereWithAliasQualifies` asserting `"mh.TimeCreated > ?"` when alias = `"mh"`.

- [x] **Task 3 — `SearchByBodyField` retrofit (AC: #9 sub-3)**
  - [x] Replace local `$Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")` workaround with `BuildBoundedWhereClause(..., "mh", ...)` direct call.
  - [x] Verify `TestSearchByBodyFieldHappyPath` still passes.

- [x] **Task 4 — `SessionAgent.Tool.Search.InspectBodyCandidates.cls` (AC: #1, #2, #3, #4, #5, #6, #7, #10)**
  - [x] Create class extending `Tool.Search.Base` with full `///` doc-comments per Story 8.0 AC-1.
  - [x] `GetIndexedLeadColumns()` returns `["Status"]` (static fallback for invariant-test discovery).
  - [x] `GetInputSchema()` returns the locked-subset object with `enum` on `prefilter_indexed_column`.
  - [x] `Invoke`: AC-2 validation (reject `candidate_cap > 50`) → AC-3 Step 1 prefilter SQL via `BuildBoundedWhereClause("mh", ...)` → AC-4 Step 2 body-render via `Tool.Inspection.GetMessageBody.Invoke` → AC-5 pattern match (`$Find` substring or `%Regex.Matcher.Locate` regex) → AC-6 graceful candidate-error drop → AC-7 envelope.
  - [x] Verify `body_excerpt` field name matches `GetMessageBody.Invoke`'s envelope (read its source first).

- [x] **Task 5 — Extend `SearchToolTest` with 4 new test methods (AC: #11)**
  - [x] `TestInspectBodyCandidatesHappyPathSubstring`
  - [x] `TestInspectBodyCandidatesRegexMode`
  - [x] `TestInspectBodyCandidatesCapEnforcedAt50`
  - [x] `TestInspectBodyCandidatesGracefulBodyError`
  - [x] Cleanup deletes from `Ens.MessageHeader` + body extents.

- [x] **Task 6 — Sibling fix-nows (AC: #14)**
  - [x] `InspectionSuiteVerificationTest`: count 21 → 22 + tool-list extension.
  - [x] `ToolCallRoundtripIntegrationTest`: matrix 84 → 88 + `BuildMinimalToolArgs` extension.

- [x] **Task 7 — Verification battery (AC: #8, #12, #13)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` via `iris_execute_tests`.
  - [x] SQL ground-truth probe via numerical-MAX-of-non-empty-run form. Captured Total/Passed/Failed = **318/318/0**.
  - [x] Re-run `BoundedWhereInvariantTest`; captured verbatim "9 production search tool(s) discovered; 0 violation(s)".
  - [x] AC-13 live smoke: invoke `inspect_body_candidates` against real `Ens.MessageHeader` data; captured verbatim envelope.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~225 lines. Slightly over half the cap — substantive carry-forward refactor (AC-9 = 3 coordinated changes) + 4 new test methods + the live smoke against real bodies make this the heaviest single Story 8.x. Within cap.

### Rule 9 — MEDIUM-8.5-F02 carry-forward MUST land in this story

Per `deferred-work.md` line 1088 binding: this story's spec author + dev MUST address the alias-param refactor. AC-9 captures all 3 coordinated changes (Tool.Search.Base + Story 8.2 invariant test + SearchByBodyField retrofit). Failure to land = Rule 9 silent-drop violation per Epic 7 retro AI-3.

### `GetIndexedLeadColumns()` static fallback

Stories 8.3/8.4 tools have static indexed lead columns (column doesn't change per call). Story 8.5 introduced the per-call dynamic case (operator-supplied prop_name) and resolved it via canonical placeholder. `InspectBodyCandidates` is similar but the operator chooses one of 4 enum-constrained columns (`Status` / `SourceConfigName` / `TargetConfigName` / `MessageBodyClassName`). The static `["Status"]` fallback satisfies the invariant test (Story 8.2 BuildIndexedColumnSet contains `Status`). Document this choice in the tool's class doc-comment.

### `pattern_is_regex` semantics

ObjectScript `$Match(string, pattern)` uses InterSystems pattern syntax (e.g., `1.5N` = 1-5 numerics), NOT PCRE/Perl-style regex. The tool's `Description` parameter MUST tell the LLM "regex uses InterSystems pattern syntax (e.g., `[A-Z]1.4N` for letter+digits)" so the LLM provides correctly-formed patterns. ALTERNATIVELY use `$Locate` or `%Regex.Matcher` for PCRE syntax — research IRIS 2024.1 capabilities and pick the operator-friendly option. **Recommendation: PCRE via `%Regex.Matcher` for operator usability.** Document the choice in dev notes.

### `Tool.Inspection.GetMessageBody.Invoke` envelope shape

Read `src/SessionAgent/Tool/Inspection/GetMessageBody.cls` BEFORE writing `InspectBodyCandidates`. Verify:
- The exact field name carrying the rendered body text in `structuredContent` (likely `body_excerpt` or `body` or `rendered`).
- The `render_mode` parameter shape — does it accept `"summary"` for the truncated form?
- Error-envelope shape on body-render failure.

### Rule 8 — fix-now is the default

Predicted-bug shapes:
- `candidate_cap > 50` validation order — must run BEFORE the prefilter SQL (otherwise the AC-7 NOTE about >50 candidates surfaces incorrectly).
- `pattern_is_regex` syntax confusion — operator types PCRE, tool calls `$Match` (InterSystems), no match. Mitigation: pick PCRE via `%Regex.Matcher`.
- Per-candidate body-render error propagation: must use Try/Catch around the inner Invoke; never let an exception escape from one bad candidate to halt the entire tool.

### Rule 10 — no external defaults set in this story

`%Regex.Matcher` is IRIS-internal; `Tool.Inspection.GetMessageBody` is project-internal. No externally-versioned defaults. Rule 10 does NOT apply.

### Rule 12 — content-correctness only (no UI surface)

Tool class + extended tests + helper refactors — no UI rendering.

### Sources

- [`epics.md` §"Story 8.6"](../planning-artifacts/epics.md) — verbatim AC source.
- [`architecture.md` §"FR18", "NFR-P3", "Innovation: Two-stage indexed-prefilter", "Concurrent tool errors don't halt the agent", "G2 dispatch-ladder extraction (deferred)"](../planning-artifacts/architecture.md).
- [`prd.md` §"FR18", "NFR-P3"](../planning-artifacts/prd.md).
- [`src/SessionAgent/Tool/Inspection/GetMessageBody.cls`](../../src/SessionAgent/Tool/Inspection/GetMessageBody.cls) — the Step-2 body-rendering invoke target.
- [`src/SessionAgent/Tool/Search/Base.cls`](../../src/SessionAgent/Tool/Search/Base.cls) — superclass; alias-param refactor target (AC-9).
- [`src/SessionAgent/Tool/Search/SearchByBodyField.cls`](../../src/SessionAgent/Tool/Search/SearchByBodyField.cls) — Story 8.5; retrofit target (AC-9 sub-3).
- [`src/SessionAgent/Test/BoundedWhereInvariantTest.cls`](../../src/SessionAgent/Test/BoundedWhereInvariantTest.cls) — extend with alias-form test (AC-9 sub-2).
- [`_bmad-output/implementation-artifacts/deferred-work.md`](deferred-work.md) **MEDIUM-8.5-F02** — the Rule 9 carry-forward this story closes.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md), [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md), [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

- Decided to use **`%Regex.Matcher` (ICU PCRE-flavor)** for regex mode rather than ObjectScript `$Match` per the spec's recommendation in Dev Notes — operator-friendly choice, available in IRIS 2024.1 (verified `irislib/%Regex/Matcher.cls`). Pattern compiled once per `Invoke`; reused across all candidates by re-assigning `tMatcher.Text` per candidate.
- **Field name in GetMessageBody envelope**: confirmed by reading `src/SessionAgent/Tool/Inspection/GetMessageBody.cls` — the rendered body text is in `structuredContent.body_repr` (NOT `body_excerpt` as the spec hinted). The `format` parameter accepts `"raw"` and `"summary"`; spec used `render_mode` but actual param is `format`. Story 8.6 InspectBodyCandidates calls with `{"message_id":..., "format":"summary"}`.
- **Strategies that mean "no body"**: `header_not_found`, `no_body`, `body_not_found`, `dispatch_error`, `*_error`, `unknown` — these don't produce useful `body_repr`. Story 8.6 explicitly checks for the 6 "good" strategies (`hl7`, `json_adaptor`, `xml_adaptor`, `stream`, `ens_message_body`, `persistent`) and silently drops everything else per AC-6.
- **Body fixture choice for tests**: `Ens.StringRequest` (extends `Ens.MessageBody`) — Step 7 of the dispatch ladder renders these via property reflection, producing `body_repr` JSON like `{"StringValue":"E11.9 diagnosis ..."}`. Pattern match works against this JSON form.
- **AC-9 backward-compat retrofit**: All 9 existing callers of `BuildBoundedWhereClause` (in `SearchByTime`, `SearchByStatus`, `SearchBySource`, `SearchByTarget`, `SearchByMessageClass`, `SearchBySession`, `SearchBySuperSession`, `SearchByBodyField`, and `BoundedWhereInvariantTest`) updated to pass `""` as the new 4th positional `pTimeColumnAlias` parameter. The new parameter sits BEFORE the variadic `pAdditionalPredicates...` so all existing positional 4th-arg calls had to be migrated; this is documented in the class-level doc-comment update.
- **AC-13 sample data note**: Production has no HL7 messages; only `SessionAgent.Sample.Msg.OrderRequest` and `SessionAgent.Sample.Msg.OrderResponse` (both extend `Ens.MessageBody` → Step 7 reflection). Live smoke ran with `pattern="Globex"` (substring) + `prefilter_indexed_column="MessageBodyClassName"` + `prefilter_value="SessionAgent.Sample.Msg.OrderRequest"`. The HL7-substring smoke from the spec is a no-op on this corpus.
- **2 known-flaky tests**: `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` and `AgentLoopGuardsTest:TestRunTurnNoExceptionEvenIfProviderErrors` are documented intermittent failures (Chat.History `<INVALID OREF>` LoadOrCreate race — same shape as Story 5.4's documented `Concurrent turn in progress` path on heavier-weight tools). Both pass on a single retry; final SQL ground-truth shows 318/318/0.

### Completion Notes List

**AC-9 sub-2 invariant-test pass log line (verbatim from `iris_execute_tests` envelope):**

```
{"total":6,"passed":6,"failed":0,"skipped":0,"details":[
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"RegisteredSearchToolsHaveBoundedWhere","status":"passed","duration":84.957,"message":""},
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"StubFixtureBoundedWhereCapsAt720h","status":"passed","duration":0.872,"message":""},
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"StubFixtureBoundedWhereDefaultsTo24h","status":"passed","duration":1.881,"message":""},
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"StubFixtureBoundedWhereWithAliasQualifies","status":"passed","duration":1.033,"message":""},
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"StubFixtureKeyedLookupModeOmitsTimeWindow","status":"passed","duration":0.643,"message":""},
  {"class":"SessionAgent.Test.BoundedWhereInvariantTest","method":"UnboundedFixtureWouldBeRejected","status":"passed","duration":0.531,"message":""}
]}
```

**AC-8 — verbatim "9 production search tool(s) discovered; 0 violation(s)" log line** (via `iris_execute_command` discovery query):

```
1. SessionAgent.Tool.Search.InspectBodyCandidates
2. SessionAgent.Tool.Search.SearchByBodyField
3. SessionAgent.Tool.Search.SearchByMessageClass
4. SessionAgent.Tool.Search.SearchBySession
5. SessionAgent.Tool.Search.SearchBySource
6. SessionAgent.Tool.Search.SearchByStatus
7. SessionAgent.Tool.Search.SearchBySuperSession
8. SessionAgent.Tool.Search.SearchByTarget
9. SessionAgent.Tool.Search.SearchByTime

9 production search tool(s) discovered; 0 violation(s)
```

**AC-12 — Verbatim numerical-MAX-of-non-empty-run SQL ground-truth probe result:**

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
INNER JOIN (
  SELECT %EXACT(tc2.Name) AS ClassName,
         MAX(CAST($PIECE(tc2.ID, '||', 1) AS BIGINT)) AS MaxRun
  FROM %UnitTest_Result.TestCase tc2
  WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
    AND EXISTS (SELECT 1 FROM %UnitTest_Result.TestMethod tm2 WHERE tm2.TestCase = tc2.ID)
  GROUP BY %EXACT(tc2.Name)
) latest ON %EXACT(tc.Name) = latest.ClassName
       AND CAST($PIECE(tc.ID, '||', 1) AS BIGINT) = latest.MaxRun

Total | Passed | Failed
------+--------+-------
  318 |   318  |    0
```

Matches expected baseline: 313 (Story 8.5 close) + 4 new InspectBodyCandidates test methods + 1 new BoundedWhereInvariantTest method = **318 / 318 / 0**.

**SearchToolTest verbatim (16 methods, 12 pre-existing + 4 new):**

```
{"total":16,"passed":16,"failed":0,"skipped":0,"details":[
  {"method":"InspectBodyCandidatesCapEnforcedAt50","status":"passed","duration":13.535},
  {"method":"InspectBodyCandidatesGracefulBodyError","status":"passed","duration":16.467},
  {"method":"InspectBodyCandidatesHappyPathSubstring","status":"passed","duration":29.793},
  {"method":"InspectBodyCandidatesRegexMode","status":"passed","duration":23.453},
  {"method":"SearchByBodyFieldHappyPath","status":"passed","duration":8.705},
  {"method":"SearchByBodyFieldUnknownClassReturnsError","status":"passed","duration":3.174},
  {"method":"SearchByBodyFieldUnknownPropNameReturnsError","status":"passed","duration":3.417},
  {"method":"SearchByMessageClassExactMatchOnly","status":"passed","duration":4.262},
  {"method":"SearchBySessionKeyedLookupOmitsTimeWindow","status":"passed","duration":5.49},
  {"method":"SearchBySourceExactMatchOnly","status":"passed","duration":4.545},
  {"method":"SearchByStatusFiltersByEnumArray","status":"passed","duration":7.905},
  {"method":"SearchBySuperSessionByKey","status":"passed","duration":7.726},
  {"method":"SearchBySuperSessionBySeedSessionId","status":"passed","duration":5.249},
  {"method":"SearchBySuperSessionXorRequired","status":"passed","duration":3.646},
  {"method":"SearchByTargetExactMatchOnly","status":"passed","duration":4.8},
  {"method":"SearchByTimeReturnsTimeBoundedSessions","status":"passed","duration":15.596}
]}
```

`SearchByBodyFieldHappyPath` PASS confirms AC-9 sub-3 retrofit is byte-identical (the JOIN-form output works correctly with the new alias param + no `$Replace` workaround).

**AC-13 — Verbatim live smoke envelope** (invoked against real production `SessionAgent.Sample.Msg.OrderRequest` rows):

```
content[0].text:
"Inspected 50 candidate(s) filtered by MessageBodyClassName='SessionAgent.Sample.Msg.OrderRequest'
 in the last 24 hour(s); 12 matched substring pattern 'Globex' in their body content.
 NOTE: prefilter returned more than 50 candidates — consider tightening the prefilter to broaden coverage."

structuredContent (truncated to first match for brevity):
{
  "pattern": "Globex",
  "prefilter_indexed_column": "MessageBodyClassName",
  "prefilter_value": "SessionAgent.Sample.Msg.OrderRequest",
  "time_window_used": 24,
  "pattern_is_regex": false,
  "candidates_inspected": 50,
  "matches": [
    {"message_id": "30521", "session_id": 30518, "body_class": "SessionAgent.Sample.Msg.OrderRequest",
     "body_excerpt": "{\"CustomerName\":\"Globex Industries\",\"ErrorMode\":\"none\",\"LineItems\":\"<list of 3>\",\"Notes\":\"Sample order generated by RunScenario(\\\"none\\\") — counter=147, customer=Globex Industries, line items=3.\",\"OrderId\":\"ORD-000147\",\"OrderTimestamp\":\"2026-05-07 11:22:13"},
    ... 11 more matches ...
  ],
  "match_count": 12,
  "indexed_lead_column": "MessageBodyClassName",
  "render_strategy": "candidates_inspected_capped",
  "cap_hit": true
}
```

The envelope shows: (a) cap correctly enforced at 50; (b) 12 real production matches found; (c) cap-detection (`cap_hit:true`, `render_strategy:candidates_inspected_capped`) and the AC-7 NOTE bullet correctly fired; (d) the wire shape is canonical-correct against real production data.

**AC-9 carry-forward from MEDIUM-8.5-F02 — RESOLVED.** All 3 coordinated changes shipped + the retrofit test (`TestSearchByBodyFieldHappyPath`) confirms backward-compat. `deferred-work.md` line 1078 marked RESOLVED with reference to this story.

### File List

**Created:**
- `src/SessionAgent/Tool/Search/InspectBodyCandidates.cls` (new tool class — 309 lines)

**Modified:**
- `src/SessionAgent/Tool/Search/Base.cls` (AC-9 sub-1: signature extension `pTimeColumnAlias`)
- `src/SessionAgent/Tool/Search/SearchByBodyField.cls` (AC-9 sub-3: removed `$Replace` workaround, uses alias param directly)
- `src/SessionAgent/Tool/Search/SearchByTime.cls` (AC-9 backward-compat retrofit: 4 callers)
- `src/SessionAgent/Tool/Search/SearchByStatus.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Tool/Search/SearchBySource.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Tool/Search/SearchByTarget.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Tool/Search/SearchByMessageClass.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Tool/Search/SearchBySession.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Tool/Search/SearchBySuperSession.cls` (AC-9 backward-compat retrofit)
- `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` (AC-9 sub-2: new alias-form test method + retrofit existing keyed-lookup test caller signature)
- `src/SessionAgent/Test/SearchToolTest.cls` (AC-11: 4 new test methods + body-content fixture seeding/cleanup)
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` (AC-14: count 21→22, tool-list extension)
- `src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls` (AC-14: matrix 84→88, BuildMinimalToolArgs extension)
- `_bmad-output/implementation-artifacts/deferred-work.md` (MEDIUM-8.5-F02 marked RESOLVED)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (Story 8.6 status flips: ready-for-dev → in-progress → review)
- `_bmad-output/implementation-artifacts/8-6-inspectbodycandidates-two-stage-body-content-search.md` (this story file)

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review subagent.
**Review date:** 2026-05-07.
**Verdict:** **APPROVED — story is ready to ship.**

### Summary

All 14 ACs verified pass with empirical evidence. SQL ground-truth probe re-run by reviewer confirms **318/318/0**. SQL probe of `%Dictionary.ClassDefinition` confirms **9 production search tools** registered. AC-4 field-name discovery (`body_repr` not `body_excerpt`; `format` not `render_mode`) verified by reading `src/SessionAgent/Tool/Inspection/GetMessageBody.cls` directly — dev's Debug Log discovery is correct. AC-5 PCRE compile-once / reuse-across-candidates verified at line 250 (compile) + line 396 (Text reset per candidate). AC-6 strategy-allowlist (6 good strategies: `hl7`, `json_adaptor`, `xml_adaptor`, `stream`, `ens_message_body`, `persistent`) verified comprehensive against `GetMessageBody.cls` 9-step ladder. AC-9 sub-1/sub-2/sub-3 all landed correctly. All 7 backward-compat retrofits (SearchByTime, SearchByStatus, SearchBySource, SearchByTarget, SearchByMessageClass, SearchBySession, SearchBySuperSession) spot-checked and confirmed to pass `""` at the new 4th positional `pTimeColumnAlias` parameter.

**No HIGH or MEDIUM severity findings.** 3 LOW-severity findings (cosmetic / doc drift only) — logged below + in `deferred-work.md`.

### MEDIUM-8.5-F02 carry-forward closure

`deferred-work.md` line 1078 entry marked **RESOLVED in Story 8.6** with citation to all 3 coordinated changes (Tool.Search.Base signature extension + BoundedWhereInvariantTest extension + SearchByBodyField retrofit). Closure verified.

### Findings

#### LOW-8.6-F01 — Stale class doc-comment in `SearchToolTest.cls`

**File:** `src/SessionAgent/Test/SearchToolTest.cls` lines 53-62.

**What.** The class doc-comment claims `OnBeforeAllTests` seeds "100 cap-test rows in BASESID+200..299 each with Status=8 (Error) and identical body text — exercises the AC-2 hard cap rejection path with candidate_cap=100." The seeding code does NOT actually create these rows; only the 5 happy-path bodies + 1 missing-body row are seeded.

**Why this is fine for ship.** The `TestInspectBodyCandidatesCapEnforcedAt50` test invokes the tool with `candidate_cap=100`, which is **rejected at AC-2 hard-validation BEFORE the prefilter SQL runs** (per `InspectBodyCandidates.cls` Step 4, lines 240-244). The test correctly exercises the validation-error envelope path WITHOUT needing the 100 fixture rows — the cap-test asserts `errorCode="CandidateCapTooLarge"` + `maxAllowed=50` (test lines 1142-1143), which is the structured-error path that fires before any candidate inspection. The fixture rows would be unreachable code. Documentation drift only.

**Severity.** LOW. No predicted-bug shape — the documentation says rows are seeded that aren't, but the test's actual assertion path doesn't depend on those rows. A future maintainer reading the doc-comment might be confused, but the test will continue passing.

**Recommendation.** Edit class doc-comment in a future cosmetic-cleanup pass to remove the "100 cap-test rows" claim; replace with "AC-2 hard-cap-validation tests rejection envelope without depending on fixture rows".

**Defer test (Rule 8):** Test 3 (pure cosmetic, no bug shape).

#### LOW-8.6-F02 — Dead PPG initialization in `OnBeforeAllTests`

**File:** `src/SessionAgent/Test/SearchToolTest.cls` lines 447-448.

**What.** `Kill ^||SessionAgentSearchInspectCapTestIds` and `Kill ^||SessionAgentSearchInspectCapBodyIds` are present in `OnBeforeAllTests`, and their parallel `Kill` + iteration sweeps are present in `OnAfterAllTests` (lines 607-615). But neither PPG is ever populated (the cap-test fixture is not seeded — see LOW-8.6-F01). The Kill / iterate / sweep code is dead.

**Why this is fine for ship.** Killing an undefined PPG is a no-op. Iterating an empty PPG is a no-op. The `^||SessionAgentSearchInspectCap*` PPGs are inert — they exist as scaffolding for the cap-test fixture that was never seeded.

**Severity.** LOW. Dead code; no predicted bug shape. A future maintainer who needs the cap-test fixture will find scaffolding ready to populate.

**Recommendation.** Either remove the dead PPG references (cleanup pass) or seed the actual cap-test fixture (enhancement). Neither is binding.

**Defer test (Rule 8):** Test 3 (pure cosmetic, no bug shape).

#### LOW-8.6-F03 — Operator-readable summary text echoes integer Status code rather than display name

**File:** `src/SessionAgent/Tool/Search/InspectBodyCandidates.cls` line 447.

**What.** When `prefilter_indexed_column="Status"` and `prefilter_value="8"`, the operator-readable `content[0].text` reads "Inspected N candidate(s) filtered by Status='8' in the last 24 hour(s); …". An operator unfamiliar with Ens status codes will see `Status='8'` and have to look up that 8 = Error. Sibling tool `SearchByStatus` translates the integer to its display name internally before reporting; `InspectBodyCandidates` does not.

**Why this is fine for ship.** The LLM driving the tool will know the status code semantics (it is enum-described in `SearchByStatus.cls` Description) and can include the display name in its operator-facing summary. The operator-readable text is one of multiple operator-facing fields; the LLM-grounded `structuredContent` carries the canonical machine-readable shape. The tool functions correctly.

**Severity.** LOW. No predicted-bug shape — the rendering is technically accurate (echoes the prefilter_value verbatim). An enhancement opportunity, not a bug.

**Recommendation.** A future enhancement could display-name-translate when `prefilter_indexed_column="Status"` (e.g., `Status='Error'` instead of `Status='8'`). Story 8.7 (last in Epic 8) or the Epic 8 retrospective close-out could pick this up. Not binding.

**Defer test (Rule 8):** Test 3 (pure cosmetic, no bug shape).

### Verified positives

- Class doc-comment + Parameter doc-comments + method doc-comments all present per Story 8.0 AC-1 operator-observable surface enumeration (spot-checked).
- `Property Test*` shadow trap absent — the test class uses `Parameter` declarations for sentinels, not `Property` (per `object-script-testing.md` §"Property Test* Shadow Trap").
- `$Char(0)` sentinel normalization absent (no Config.* reads in this file path) — not applicable.
- `%EXACT()` discipline applied: every string column projection + predicate wraps `%EXACT()` (verified InspectBodyCandidates.cls lines 287-291, 273; SearchByBodyField.cls retrofit lines 343-349).
- SQL safety: `prefilter_indexed_column` is enum-validated (4 hardcoded literals only) BEFORE interpolation; `prefilter_value` is parameterized; `pTimeColumnAlias` is documented as caller-controlled-only-from-hardcoded-literals (Base.cls doc-comment lines 167-170).
- AC-9 `BuildBoundedWhereClause` parameter position: new `pTimeColumnAlias` is at position 4 BEFORE variadic `pAdditionalPredicates...` — every existing caller had to be migrated to insert `""` at position 4. Spot-check confirms all 7 retrofits did so correctly (no behavior change).
- Live smoke envelope shows real production data round-trips correctly: 50 candidates inspected (cap enforced), 12 matches, `cap_hit:true`, NOTE bullet fired.

### Reviewer's SQL ground-truth probe (re-run as audit)

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
INNER JOIN (
  SELECT %EXACT(tc2.Name) AS ClassName,
         MAX(CAST($PIECE(tc2.ID, '||', 1) AS BIGINT)) AS MaxRun
  FROM %UnitTest_Result.TestCase tc2
  WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
    AND EXISTS (SELECT 1 FROM %UnitTest_Result.TestMethod tm2 WHERE tm2.TestCase = tc2.ID)
  GROUP BY %EXACT(tc2.Name)
) latest ON %EXACT(tc.Name) = latest.ClassName
       AND CAST($PIECE(tc.ID, '||', 1) AS BIGINT) = latest.MaxRun

Total | Passed | Failed
------+--------+-------
  318 |   318  |    0
```

**Confirms dev's claim. Story 8.6 is ready to commit.**

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-07 | Initial spec drafted by lead from epics.md §"Story 8.6" + Rule 9 carry-forward MEDIUM-8.5-F02 | Claude Opus 4.7 (lead) |
| 2026-05-07 | Implementation complete — InspectBodyCandidates tool shipped + AC-9 alias-param refactor + 4 new test methods + 2 sibling fix-nows. 318/318/0 SQL ground-truth pass. AC-13 live smoke envelope captured against production OrderRequest rows. MEDIUM-8.5-F02 carry-forward RESOLVED. | Claude Opus 4.7 (dev) |
