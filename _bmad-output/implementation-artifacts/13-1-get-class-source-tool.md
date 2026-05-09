# Story 13.1: get_class_source — Class Source Reader + RegressionSweepCount Helper

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` (TOOL-1).
**AI-2 carry-forward:** This story MUST build `SessionAgent.Test.Util.RegressionSweepCount()` as AC-1.
**AI-5 carry-forward:** All substring-grep test assertions must enumerate ALL expected hits.
**Rule 9 grep:** `grep -ni "Story 13.1\|story-13-1" deferred-work.md` → 0 hits.

## User Story

As the **Inspection Agent**, I want a `get_class_source` tool so that I can read the full
source of any class — including DTL XData, method bodies, and BP logic — enabling me to
explain exactly what a configured item does, not just its structure.

## Acceptance Criteria

**AC-1 — RegressionSweepCount helper.** Class `SessionAgent.Test.Util` gains a ClassMethod
`RegressionSweepCount(Output pTotal As %Integer, Output pPassed As %Integer, Output pFailed As %Integer) As %Status`
that executes the canonical numerical-MAX SQL probe and returns the aggregate counts via ByRef output params.

> **Then** `iris_execute_classmethod SessionAgent.Test.Util RegressionSweepCount` returns
> `Total`, `Passed`, `Failed` matching the SQL probe. Subsequent stories (13.3, 13.5) MUST call
> this helper instead of repeating the SQL inline.

**AC-2 — Tool registered.** `SessionAgent.Tool.Inspection.GetClassSource` compiled and
registered. `Tool.Registry.ListTools` returns `get_class_source` with non-empty Description.
`InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` updated to 26.

> **Then** ListTools envelope contains `"name":"get_class_source"`; EXPECTEDTOOLCOUNT=26 in ISV test.

**AC-3 — Full class source returned.** When `class_name` names a compiled class and `method_name`
is omitted, `source_lines` contains all lines from the class source; `line_count` matches `source_lines` length.

> **Then** `source_lines.%Size()` == `line_count` and `source_lines.%Get(0)` starts with `"Class "`.

**AC-4 — Method-level filtering.** When `method_name` is provided, `source_lines` contains only
the lines from the matching method's signature through its closing `}` (brace-depth tracker).
`line_count` reflects the method-only subset.

> **Then** `source_lines.%Get(0)` contains the method name; the last element is `"}"`.

**AC-5 — include_doc_comments=false.** When false, `///` comment lines are stripped from
`source_lines` before return.

> **Then** no element in `source_lines` starts with `"///"` when `include_doc_comments=false`.

**AC-6 — Truncation guard.** When `method_name` is omitted AND total lines > 2000, return
first 1500 lines with `truncated=true` and a suggestion to use `method_name` filtering.

> **Then** `"truncated":true` in response and `source_lines.%Size()` == 1500 for an oversized class.

**AC-7 — class_not_found envelope.** When `class_name` names a non-existent class, tool
returns `isError=0`, `render_strategy="class_not_found"`.

> **Then** response `render_strategy` is `"class_not_found"` with no `isError=1`.

**AC-8 — Strip-last-segment fallback.** Same pattern as Story 12.2 / existing Inspection tools.
Success → `class_name_auto_corrected_from` field. Still-not-found → `candidate_class_name` field.

> **Then** input `"SessionAgent.Tool.Base.Invoke"` auto-corrects to `"SessionAgent.Tool.Base"`;
> response carries `class_name_auto_corrected_from`.

**AC-9 — Anti-method-suffix warning in schema.** `class_name` description in `GetInputSchema()`
says "Pass the class name only — do not include method names; use `method_name` for method-level filtering."

> **Then** `GetInputSchema()` `properties.class_name.description` contains that warning verbatim.

**AC-10 — Regression sweep.** All pre-existing tests plus new GetClassSourceTest pass.

> **Then** `SessionAgent.Test.Util.RegressionSweepCount()` returns `Total=N, Passed=N, Failed=0`
> where N ≥ 477 (Story 13.2 baseline) + new test count.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight probes (COMPLETE)**
  - `iris_execute_classmethod %Atelier.v1.Utils.TextServices GetTextAsArray ["SessionAgent.Tool.Base.cls",0,"",0]` → `returnValue:1` ($$$OK) ✓
  - `irislib/%Atelier/v1/Utils/TextServices.cls` read — confirms: output `pTextArray(0)=lineCount`, `pTextArray(1..N)=lines` ✓
  - Method signature: `GetTextAsArray(pFullName As %String, pFlags As %Integer = 0, Output pTextArray As %String, pBinary As %Boolean = 0) As %Status`
- [x] **Task 1 — Build `SessionAgent.Test.Util` with `RegressionSweepCount` (AI-2 carry-forward)**
  - File: `src/SessionAgent/Test/Util.cls` (create new or add method to existing)
  - Method must encapsulate the canonical numerical-MAX SQL probe form (see Dev Notes)
  - Return `Total`, `Passed`, `Failed` as ByRef output integers
- [x] **Task 2 — Implement `SessionAgent.Tool.Inspection.GetClassSource`**
  - File: `src/SessionAgent/Tool/Inspection/GetClassSource.cls`
  - Follow pattern from `GetBusinessProcessSource.cls` (TOOLNAME / DESCRIPTION / MUTATESSTATE / GetInputSchema / Invoke)
  - See Dev Notes for IRIS API, method-filter algorithm, truncation guard
- [x] **Task 3 — Implement `SessionAgent.Test.GetClassSourceTest`**
  - File: `src/SessionAgent/Test/GetClassSourceTest.cls`
  - AI-5 carry-forward: enumerate ALL expected hits in any substring-grep test assertion
  - Test methods: full class, method_name filter, include_doc_comments=false, truncation (mock), class_not_found, strip-last-segment
- [x] **Task 4 — Compile + test + regression sweep**
  - `iris_doc_compile` each class; zero compile errors
  - Use `SessionAgent.Test.Util.RegressionSweepCount()` for AC-10 regression sweep
- [x] **Task 5 — Update InspectionSuiteVerificationTest + sprint-status.yaml**
  - Bump `EXPECTEDTOOLCOUNT` 25→26; add `get_class_source` to named-tool list + GetRepresentativeArgs
  - Flip `13-1-get-class-source-tool: ready-for-dev` → `done`

## Dev Notes

**IRIS API — GetTextAsArray:**
```objectscript
Set tSC = ##class(%Atelier.v1.Utils.TextServices).GetTextAsArray(
    tClassName _ ".cls",  ; must append ".cls" — Atelier document name format
    0,                    ; pFlags
    .tTextArray,          ; Output — tTextArray(0)=count, tTextArray(1..N)=lines
    0)                    ; pBinary = false
If $$$ISERR(tSC) { /* handle error */ }
Set tTotalLines = +tTextArray(0)
```

**Method-level filter (brace-depth tracker):**
```objectscript
Set tInMethod = 0, tDepth = 0, tMethodLines = []
For i = 1:1:tTotalLines {
    Set tLine = tTextArray(i)
    If 'tInMethod {
        ; Match "Method Name(" or "ClassMethod Name(" — check name segment
        Set tNorm = $ZStrip(tLine, "<W")
        If (tNorm ? 1"Method ".E) || (tNorm ? 1"ClassMethod ".E) {
            Set tNamePart = $Piece(tNorm, "(", 1)
            Set tLastWord = $Piece(tNamePart, " ", *)
            If tLastWord = tMethodName {
                Set tInMethod = 1
                Do tMethodLines.%Push(tLine)
            }
        }
    } Else {
        Do tMethodLines.%Push(tLine)
        For j = 1:1:$Length(tLine) {
            Set tCh = $Extract(tLine, j)
            If tCh = "{" { Set tDepth = tDepth + 1 }
            ElseIf tCh = "}" {
                Set tDepth = tDepth - 1
                If tDepth = 0 { Quit }
            }
        }
        If tDepth = 0 Quit  ; method complete (closing } found at depth 0)
    }
}
If 'tMethodLines.%Size() {
    ; method_name not found — return class_not_found-style envelope
    Do pResult.structuredContent.%Set("render_strategy", "method_not_found")
}
```
**MEDIUM risk note:** brace-depth counter is fooled by `{`/`}` inside string literals or
comments. This is acceptable for source-inspection use (result may be slightly over/under the
true boundary; operator can re-request with a narrower filter).

**Truncation guard:**
```objectscript
If (tMethodName = "") && (tTotalLines > 2000) {
    Set tTotalLines = 1500
    Do tResult.%Set("truncated", 1, "boolean")
    Do tResult.%Set("truncation_note", "Class exceeds 2000 lines. Use method_name to filter.")
}
```

**include_doc_comments=false strip:**
```objectscript
If 'tIncludeDocs {
    ; Remove lines starting with "///" (after left-strip of whitespace)
    Set tFiltered = []
    For i = 0:1:tMethodLines.%Size()-1 {
        Set tL = tMethodLines.%Get(i)
        If $ZStrip(tL, "<W") '? 1"///"E { Do tFiltered.%Push(tL) }
    }
    Set tMethodLines = tFiltered
}
```

**RegressionSweepCount helper (canonical numerical-MAX form — AI-2 carry-forward):**
```objectscript
ClassMethod RegressionSweepCount(Output pTotal As %Integer, Output pPassed As %Integer, Output pFailed As %Integer) As %Status
{
    Set tSC = $$$OK, pTotal = 0, pPassed = 0, pFailed = 0
    &sql(SELECT COUNT(*), SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END), SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END)
         INTO :pTotal, :pPassed, :pFailed
         FROM %UnitTest_Result.TestMethod tm
         JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
         JOIN (SELECT %EXACT(tc2.Name) AS ClassName, MAX($PIECE(tc2.ID,'||',1)+0) AS MaxRunIdx
               FROM %UnitTest_Result.TestMethod tm2
               JOIN %UnitTest_Result.TestCase tc2 ON tm2.TestCase = tc2.ID
               WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
               GROUP BY %EXACT(tc2.Name)) latest
         ON %EXACT(tc.Name)=latest.ClassName AND ($PIECE(tc.ID,'||',1)+0)=latest.MaxRunIdx
         WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%')
    If SQLCODE < 0 Set tSC = $$$ERROR($$$SQLError, SQLCODE, %msg)
    Quit tSC
}
```

**Strip-last-segment fallback:** copy exactly from `GetBusinessProcessSource.cls` lines 105-156,
changing field names to `class_name_auto_corrected_from` and `candidate_class_name`.

**Response shape (full class, no method_name):**
```json
{
  "class_name": "SessionAgent.Sample.BP.OrderRouter",
  "method_name": "",
  "source_lines": ["Class SessionAgent...", "..."],
  "line_count": 142,
  "truncated": false,
  "render_strategy": "ok"
}
```
Method-filter success: add `method_name` field non-empty; `render_strategy="ok"`.
Method-not-found: `render_strategy="method_not_found"`, `source_lines=[]`, `line_count=0`.
class_not_found: `render_strategy="class_not_found"`, `source_lines=[]`.

**Reference files:**
- `irislib/%Atelier/v1/Utils/TextServices.cls` — API signature
- `src/SessionAgent/Tool/Inspection/GetBusinessProcessSource.cls` — strip-last-segment pattern

## Dev Agent Record

### Implementation Plan

1. Created `SessionAgent.Test.Util` (new class) with `RegressionSweepCount` ClassMethod encapsulating the canonical numerical-MAX SQL probe.
2. Implemented `SessionAgent.Tool.Inspection.GetClassSource` following the `GetBusinessProcessSource` / `GetRuleSource` pattern: `ToolName`, `Description`, `MutatesState=0`, `GetInputSchema()`, `Invoke()`.
3. Key implementation notes:
   - `GetTextAsArray` returns UDL format — class-level doc comments appear BEFORE the `Class` declaration line. First line is `///` not `"Class "` for classes with doc banners.
   - Method-detection uses `$Extract` string comparison instead of `?` pattern operator (the `1"..."E` pattern syntax caused compile error #1025).
   - Doc-comment strip uses `$Extract($ZStrip(line,"<W"), 1, 3) = "///"` (same reason).
   - Strip-last-segment fallback copied exactly from `GetBusinessProcessSource.cls` lines 105-156 with field name changes.
4. Created `SessionAgent.Test.GetClassSourceTest` — 12 test methods covering all ACs.
5. Updated `InspectionSuiteVerificationTest`: EXPECTEDTOOLCOUNT 25→26, added `get_class_source` to named-tool `$ListBuild`, added `get_class_source` branch to `GetRepresentativeArgs`.

### Completion Notes

**AC-1 — RegressionSweepCount helper:**
`SessionAgent.Test.Util.RegressionSweepCount` created and compiled clean. SQL probe returns `Total=489, Passed=489, Failed=0` post-Story 13.1 (baseline was 477/477/0 pre-Story 13.1).

**AC-2 — Tool registered:**
SQL query against `%Dictionary.ClassDefinition` confirms `SessionAgent.Tool.Inspection.GetClassSource` in registry with `MutatesState=0`. `Tool.Registry.ListTools()` returns 26 tools (up from 25). `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT=26`. Named-tool list updated: `get_class_source` added. All 13 ISV test methods pass (Status=1 verified via SQL probe).

**AC-3 — Full class source returned:**
`TestFullClassSourceReturned` passes 12/12. `source_lines` contains the `Class` declaration line; `line_count == source_lines.%Size()`. Note: UDL format places doc-comments before `Class` keyword so first element is `///` not `"Class "` — test updated to scan for `Class` declaration anywhere in source_lines.

**AC-4 — Method-level filtering:**
`TestMethodNameFilterReturnsMethodBody` passes. `source_lines.%Get(0)` contains `"GetInputSchema"` (method signature line). Last element is `"}"`. `TestMethodNotFoundReturnsMethodNotFoundEnvelope` passes: `render_strategy="method_not_found"`, `source_lines=[]`, `line_count=0`.

**AC-5 — include_doc_comments=false:**
`TestIncludeDocCommentsFalseStripsDocLines` passes. No element starts with `"///"` after stripping. Doc-stripped line count < full-class line count confirmed.

**AC-6 — Truncation guard:**
`TestTruncationGuardDoesNotMisfireOnSmallClass` passes (truncated=false for GetClassSource itself). `TestTruncationGuardFiresForOversizedClass` passes using `%Library.Persistent` (returns 1500 lines with `truncated=true`).

**AC-7 — class_not_found envelope:**
`TestClassNotFoundReturnsClassNotFoundEnvelope` passes. `render_strategy="class_not_found"`, `isError` NOT set.

**AC-8 — Strip-last-segment fallback:**
`TestStripLastSegmentAutoCorrects` passes: `"SessionAgent.Tool.Base.Invoke"` → auto-corrects to `"SessionAgent.Tool.Base"`, `class_name_auto_corrected_from` present.
`TestStripLastSegmentStillNotFoundReturnsCandidateField` passes: `candidate_class_name` present.

**AC-9 — Anti-method-suffix warning in schema:**
`TestInputSchemaDescriptionContainsWarning` passes. `properties.class_name.description` contains `"do not include method names"` and `"method_name"`.

**AC-10 — Regression sweep:**
SQL ground-truth probe: `Total=489, Passed=489, Failed=0` (477 pre-existing + 12 new GetClassSourceTest methods).

## File List

- `src/SessionAgent/Test/Util.cls` — CREATED (RegressionSweepCount helper, AI-2 carry-forward)
- `src/SessionAgent/Tool/Inspection/GetClassSource.cls` — CREATED (get_class_source tool)
- `src/SessionAgent/Test/GetClassSourceTest.cls` — CREATED (12 unit tests covering all ACs)
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` — MODIFIED (EXPECTEDTOOLCOUNT 25→26, get_class_source added to named list + GetRepresentativeArgs)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — MODIFIED (13-1 status: ready-for-dev → done)

## Review Findings

Code review completed 2026-05-09 by code-review agent.

- [x] [Review][Defer] Stale "ThirteenTools" in ISV method names/comments — `InspectionSuiteVerificationTest.cls` method names (`TestAllThirteenToolsExerciseAgainstFixture`, etc.) still reference "13 tools" in prose/names, now 26 tools. Pre-existing cosmetic, no bug shape (actual assertions use EXPECTEDTOOLCOUNT=26). Deferred — pure cosmetic per Rule 8 test-3.

**Verdict: APPROVED. 0 HIGH, 0 MEDIUM, 1 LOW (deferred). All AC checks passed.**

Empirical battery:
- Compile: all 4 files clean (79 ms, 0 errors)
- Regression sweep (SQL ground-truth): Total=489, Passed=489, Failed=0
- GetClassSourceTest: 12/12 pass (all Status=1)
- InspectionSuiteVerificationTest: 13/13 pass (all Status=1)
- Tool count: 26 registered (confirmed via %Dictionary.ClassDefinition query)
- RegressionSweepCount: returns $$$OK; SQL probe matches (489/489/0)

## Change Log

- 2026-05-09: Story 13.1 implemented. Created RegressionSweepCount helper (AI-2 carry-forward), get_class_source tool, 12-method test suite. Bumped EXPECTEDTOOLCOUNT 25→26. Regression sweep: 489/489/0 (baseline 477/477/0 + 12 new tests).
- 2026-05-09: Code review APPROVED. 0 HIGH, 0 MEDIUM, 1 LOW deferred (stale "ThirteenTools" method names in ISV — cosmetic, no bug shape).
