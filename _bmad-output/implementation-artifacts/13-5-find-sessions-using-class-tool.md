# Story 13.5: find_sessions_using_class — Cross-Session Class Search

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` (TOOL-5).
**AI-1 carry-forward:** SQL injection 4-layer defense codified in `.claude/rules/iris-objectscript-basics.md` §"SQL Injection Defense in ObjectScript" BEFORE this story was specced. ✓
**AI-5 carry-forward:** Enumerate ALL expected hits in any substring-grep test assertion.
**Rule 9 grep:** `grep -ni "Story 13.5\|story-13-5" deferred-work.md` → 0 hits.

## User Story

As the **Message-Search Agent**, I want a `find_sessions_using_class` tool so that I can
identify which sessions have touched a given class (as source, target, or message body)
in a configurable time window — enabling operators to assess the blast radius when a
class needs repair.

## Acceptance Criteria

**AC-1 — Tool registered.** Class `SessionAgent.Tool.Search.FindSessionsUsingClass`
compiled, registered, and returned by `Tool.Registry.ListTools` with non-empty Description.
`BoundedWhereInvariantTest` passes automatically (new tool declares valid indexed lead columns).

> **Then** ListTools envelope contains `"name":"find_sessions_using_class"` with non-empty Description.

**AC-2 — SQL injection 4-layer defense present.** All four layers from
`.claude/rules/iris-objectscript-basics.md §"SQL Injection Defense"` confirmed present
in the implementation:
(a) schema description warns about class-name format;
(b) server-side `$Match` regex `^[A-Za-z%][A-Za-z0-9%._]*$` blocks malformed input;
(c) class_name bound as `?` placeholder — never concatenated into SQL text;
(d) reviewer confirms all three implementation layers in Review Findings.

> **Then** passing `class_name="'; DROP TABLE Ens_MessageHeader; --"` returns `isError=1`
> (regex rejection, not SQL execution).

**AC-3 — Sessions returned for known class.** When `class_name` matches live
`Ens.MessageHeader` data, `sessions` array is non-empty; each entry has
`session_id`, `first_seen`, `last_seen`, `msg_count`, `matched_via`.

> **Then** a known live class name returns at least one session with non-empty `session_id`.

**AC-4 — match_field filtering.** When `match_field` is `source_config`, `target_config`,
or `message_body`, only that column is searched. Default `any` searches all three.

> **Then** `match_field="source_config"` with a class only appearing as TargetConfigName
> returns empty sessions.

**AC-5 — time_window_hours enforced.** Default is 24h; max 168h. Passing 0 → default.
Passing > 168 returns error or is clamped (match existing search-tool convention).

> **Then** valid `time_window_hours=2` searches only the last 2 hours.

**AC-6 — limit enforced.** Default 20, max 100. Over-limit clamped or errors per
search-tool convention.

> **Then** `limit=5` returns at most 5 sessions.

**AC-7 — no results returns empty array cleanly.** When class_name matches nothing,
`sessions=[]`, `session_count=0`, `render_strategy="ok"`, no `isError`.

> **Then** unknown class name: `"sessions":[],"session_count":0,"render_strategy":"ok"`.

**AC-8 — Strip-last-segment fallback.** When `class_name` ends with a method-name
segment causing zero results on the suffix-test (regex accepts it but no sessions found
with that exact name), strip the last segment and retry once. Success → normal response +
`class_name_auto_corrected_from`. Still-not-found → empty sessions + `candidate_class_name`.

> **Note:** Strip-last-segment for Search differs from Inspection: we can only retry the
> SQL query, not `%OpenId`. The fallback is a best-effort search hint, not a guarantee.

**AC-9 — Anti-method-suffix warning in schema.** `class_name` description includes
"Pass the class name only — do not include method names."

> **Then** `GetInputSchema()` `properties.class_name.description` contains "Pass the class name only".

**AC-10 — Regression sweep.** All pre-existing tests plus new tests pass.

> **Then** `SessionAgent.Test.Util.RegressionSweepCount()` returns `Total=N, Passed=N, Failed=0`
> where N ≥ 499 (Story 13.3 baseline) + new test count.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight probes + AI-1 carry-forward (COMPLETE)**
  - `SELECT %EXACT(SourceConfigName), %EXACT(TargetConfigName), %EXACT(MessageBodyClassName) FROM Ens.MessageHeader` → confirmed column names valid. ✓
  - SQL injection 4-layer defense rule added to `.claude/rules/iris-objectscript-basics.md`. ✓
  - `BoundedWhereInvariantTest` doc confirms `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName` all in the documented indexed set. ✓
- [x] **Task 1 — Implement `SessionAgent.Tool.Search.FindSessionsUsingClass`**
  - File: `src/SessionAgent/Tool/Search/FindSessionsUsingClass.cls`
  - Extends `SessionAgent.Tool.Search.Base`; `MutatesState=0`
  - See Dev Notes for SQL structure and 4-layer defense pattern
- [x] **Task 2 — Implement `SessionAgent.Test.FindSessionsUsingClassTest`**
  - File: `src/SessionAgent/Test/FindSessionsUsingClassTest.cls`
  - AI-5 carry-forward: enumerate ALL expected hits in any substring-grep assertion
- [x] **Task 3 — Compile, test, regression sweep**
  - Compile; zero errors; run tests; `RegressionSweepCount()`
- [x] **Task 4 — Update sprint-status.yaml**
  - Flip `13-5-find-sessions-using-class-tool: ready-for-dev` → `review`

## Dev Notes

**This is a SEARCH tool.** Extends `SessionAgent.Tool.Search.Base`, NOT `Tool.Inspection.Base`.
File goes under `src/SessionAgent/Tool/Search/FindSessionsUsingClass.cls`.
Reference implementation: `src/SessionAgent/Tool/Search/SearchByMessageClass.cls`.

**4-Layer SQL Injection Defense (AC-2 — MANDATORY):**
```objectscript
; Layer (b) — regex validation BEFORE any SQL
Set tClassName = pJsonArgs.%Get("class_name")
If tClassName = "" || (tClassName = $$$NULLOREF) {
    Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing class_name"}]}
    Quit
}
If '$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$") {
    Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid class_name format — must be a valid ObjectScript class name"}]}
    Quit
}
; Layer (c) — all SQL uses ? placeholders; tClassName is NEVER concatenated into SQL text
```

**GetIndexedLeadColumns — declare all 3 searched columns:**
```objectscript
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["SourceConfigName", "TargetConfigName", "MessageBodyClassName"]
}
```

**SQL structure by match_field:**
```objectscript
; Build inner filter based on match_field ("any" / "source_config" / "target_config" / "message_body")
If tMatchField = "source_config" {
    Set tColFilter = "%EXACT(mh.SourceConfigName) = ?"
    Set tMatchedVia = "source_config"
} ElseIf tMatchField = "target_config" {
    Set tColFilter = "%EXACT(mh.TargetConfigName) = ?"
    Set tMatchedVia = "target_config"
} ElseIf tMatchField = "message_body" {
    Set tColFilter = "%EXACT(mh.MessageBodyClassName) = ?"
    Set tMatchedVia = "message_body"
} Else {
    Set tColFilter = "(%EXACT(mh.SourceConfigName) = ? OR %EXACT(mh.TargetConfigName) = ? OR %EXACT(mh.MessageBodyClassName) = ?)"
    Set tMatchedVia = "any"
}

; Use BuildBoundedWhereClause for time window; inject column filter as extra predicate
Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(tWindowHours, .tParams, .tErr, "", tColFilter)

; Bind class_name as ? — once for single-column, three times for "any"
If tMatchField = "any" {
    Do tParams.%Push(tClassName)
    Do tParams.%Push(tClassName)
    Do tParams.%Push(tClassName)
} Else {
    Do tParams.%Push(tClassName)
}
```

**Full SQL:**
```objectscript
Set tSql = "SELECT DISTINCT TOP ? %EXACT(mh.SessionId) AS sid, MIN(mh.TimeCreated) AS first_seen, MAX(mh.TimeCreated) AS last_seen, COUNT(*) AS msg_count FROM Ens.MessageHeader mh WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MAX(mh.TimeCreated) DESC"
```

**Strip-last-segment for Search tools:** after GROUP BY returns 0 rows with the original class_name, strip and re-run the SQL once. If the stripped name returns rows, include `class_name_auto_corrected_from`. If still empty, include `candidate_class_name` in the response. This is query-level only — no `%OpenId` involved.

**Response shape:**
```json
{
  "class_name": "SessionAgent.Sample.BO.FilePublish",
  "match_field": "any",
  "time_window_hours": 24,
  "session_count": 3,
  "sessions": [
    {"session_id": 80569, "first_seen": "2026-05-09T17:26:23Z", "last_seen": "2026-05-09T17:26:23Z", "msg_count": 1, "matched_via": "any"},
    {"session_id": 80562, "first_seen": "2026-05-09T17:26:17Z", "last_seen": "2026-05-09T17:26:17Z", "msg_count": 1, "matched_via": "any"}
  ],
  "truncated": false,
  "render_strategy": "ok"
}
```

**Test approach (live Ens.MessageHeader data):**
- Use `SessionAgent.Sample.BP.OrderRouter` or `SessionAgent.Sample.BO.FilePublish` as the known class_name
- For AC-2: test regex rejection with `"Invalid!Class"` or `"'; DROP TABLE--"`
- For AC-4: test `match_field="source_config"` with a known-TargetOnly class → expect 0 results
- For AC-7: test with `"Nonexistent.Class.XYZ"` → `sessions=[]`, no isError

**Layer (a) schema description example:**
```objectscript
"class_name": {"type": "string", "description": "Full package-qualified class name to search for in Ens.MessageHeader columns (e.g. 'SessionAgent.Sample.BP.OrderRouter'). Pass the class name only — do not include method names. Searched against SourceConfigName, TargetConfigName, and/or MessageBodyClassName per match_field."}
```

**Regression sweep:** call `SessionAgent.Test.Util.RegressionSweepCount()` (built in 13.1).

## Dev Agent Record

### Implementation Plan

- Task 1: Implemented `SessionAgent.Tool.Search.FindSessionsUsingClass` extending `SessionAgent.Tool.Search.Base` with all 4 SQL injection defense layers, match_field filtering (any/source_config/target_config/message_body), strip-last-segment fallback, and correct response shape per spec.
- Task 2: Implemented `SessionAgent.Test.FindSessionsUsingClassTest` with 10 test methods covering all ACs; fixture-based approach seeding synthetic `Ens.MessageHeader` rows across 4 scenarios (basic shape, match_field filter, time_window, limit clamp).
- Task 3: Both classes compile cleanly; 10/10 new tests pass per SQL ground-truth probe; regression sweep 509/509/0 (baseline 499 + 10 new).
- Task 4: sprint-status.yaml and story Status updated to "review".

### Completion Notes

**AC-1 verified:** `find_sessions_using_class` appears in `Tool.Registry.ListTools` output with non-empty Description: "Find Ens sessions that reference a given class name in SourceConfigName, TargetConfigName, or MessageBodyClassName within a configurable time window. Useful for blast-radius assessment before retiring or repairing a class."

**AC-2 verified (SQL injection 4-layer defense):**
- Layer (a): `GetInputSchema()` `class_name.description` contains "Pass the class name only — do not include method names"
- Layer (b): `$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$")` blocks `"'; DROP TABLE Ens_MessageHeader; --"` → `isError=1, "invalid class_name format"`
- Layer (c): `class_name` bound via `?` placeholder in `RunQuery` classmethod; never concatenated. For `match_field="any"`: 3 placeholders bound; for specific field: 1 placeholder.
- Layer (d): Reviewer must confirm all three implementation layers.

**AC-3 verified:** `SessionAgent.Sample.BP.OrderRouter` with `time_window_hours=168` returns 20 sessions (limit=20), each with `session_id`, `first_seen` (ISO-Z 20-char), `last_seen` (ISO-Z 20-char), `msg_count`, `matched_via`.

**AC-4 verified:** `FIXTURETGTCLASS` with `match_field="source_config"` returns 0 sessions; same class with `match_field="target_config"` returns > 0.

**AC-5 verified:** 10-day-old fixture rows excluded by 24h window; fresh row included.

**AC-6 verified:** `limit=3` returns at most 3 sessions.

**AC-7 verified:** `Totally.Unknown.Class.FSUC9999` → `sessions=[], session_count=0, render_strategy="ok"`, no `isError`.

**AC-8 verified:**
- Positive: `SessionAgent.Sample.BP.OrderRouter.OnProcessInput` auto-corrects to `SessionAgent.Sample.BP.OrderRouter`; response contains `class_name_auto_corrected_from="SessionAgent.Sample.BP.OrderRouter.OnProcessInput"`, `session_count=20`.
- Negative: `Totally.Unknown.FSUC9998.SomeMethod` → `sessions=[]`, `candidate_class_name="Totally.Unknown.FSUC9998"`.

**AC-9 verified:** `GetInputSchema().properties.class_name.description` = "Full package-qualified class name to search for in Ens.MessageHeader columns (e.g. 'SessionAgent.Sample.BP.OrderRouter'). Pass the class name only — do not include method names. Searched against SourceConfigName, TargetConfigName, and/or MessageBodyClassName per match_field."

**AC-10 verified:** Regression sweep via canonical numerical-MAX SQL probe: **Total=509, Passed=509, Failed=0** (baseline 499 Story 13.3 + 10 new tests = 509).

**BoundedWhereInvariantTest:** 6/6 pass — `GetIndexedLeadColumns()` returns `["SourceConfigName", "TargetConfigName", "MessageBodyClassName"]`, all in the documented indexed set.

**Key design decision — positional `%GetData(n)` in RunQuery:** Used `tRs.%GetData(1..4)` not `tRs.%Get("colname")` because `%EXACT(mh.SessionId) AS sid` causes alias resolution issues with IRIS SQL (known pattern from Story 13.3 carry-forward).

**Key design decision — RunQuery classmethod:** Extracted the SQL execution into a separate `RunQuery` classmethod to support the strip-last-segment retry (AC-8) without code duplication. The classmethod is not `Private` so it's testable if needed.

### File List

- `src/SessionAgent/Tool/Search/FindSessionsUsingClass.cls` (new)
- `src/SessionAgent/Test/FindSessionsUsingClassTest.cls` (new)
- `_bmad-output/implementation-artifacts/13-5-find-sessions-using-class-tool.md` (status updated)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status updated)

### Review Findings

- [x] [Review][Patch] MEDIUM — Missing canonical `EnsureIsErrorOnPrepareFailure` envelope on RunQuery prepare failure [`src/SessionAgent/Tool/Search/FindSessionsUsingClass.cls:137-139`] — **FIXED.** The `Invoke` error handler for `$$$ISERR(tSCSub)` was replacing `pResult` with a raw `{"isError":1, ...}` object instead of using the Story 11.2 centralized `EnsureIsErrorOnPrepareFailure` helper (used by all 10 other search tools). This caused the canonical `render_strategy:"prepare_error"` shape to be absent from the error envelope on SQL prepare failures. Fixed by replacing the raw assignment with `Do ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCSub, ..#ToolName)`. Recompiled; 10/10 tests still pass.

- [x] [Review][AC-2 Layer (d) Confirmation] SQL injection 4-layer defense — reviewer confirms all three implementation layers present:
  - **(a) Schema description:** `GetInputSchema()` `class_name.description` contains "Pass the class name only — do not include method names" ✓ (line 63 of `FindSessionsUsingClass.cls`)
  - **(b) Server-side `$Match` regex:** `If '$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$")` blocks malformed input before any SQL ✓ (lines 99-102)
  - **(c) Parameterized `?` placeholder:** `class_name` is always bound via `?` in `RunQuery`; never concatenated into SQL text ✓ (lines 226-235)
  - All three implementation layers confirmed present by reviewer. AC-2 fully satisfied.

### Change Log

- 2026-05-09: Story 13.5 implemented. New tool `find_sessions_using_class` with 4-layer SQL injection defense, match_field filtering, strip-last-segment fallback. 10 unit tests. Regression sweep 509/509/0.
- 2026-05-09: Code review complete. 1 MEDIUM finding (missing `EnsureIsErrorOnPrepareFailure` pattern) fixed in-place. Layer (d) AC-2 SQL injection defense confirmed by reviewer. Story status: done.
