# Story 2.11: Three Example Inspection Tools

Status: done

## Story

As a developer building the AgentLoop smoke test (Story 2.12),
I want three concrete Inspection tools implemented per the FR55–FR58 contract — `SessionSummary`, `SessionTimeline`, `MessageHeaders` — each reading `Ens.MessageHeader` for a given session id with `%EXACT()` SQL discipline and structured tool-result envelopes,
so that the AgentLoop has a working set of tools to dispatch against during end-to-end smoke testing (and as reference implementations for the remaining 10 tools in Epic 4).

This story ships **3 NEW concrete tool classes** + **1 NEW test class**. They subclass `SessionAgent.Tool.Base` (Story 2.10), discoverable via `Tool.Registry.ListTools` and dispatchable via `Tool.Registry.Dispatch`. The reference implementation pattern matches architecture's canonical skeleton.

## Acceptance Criteria

ACs map to [epics.md Story 2.11](../planning-artifacts/epics.md#story-211-three-example-inspection-tools) (lines 1028–1062). Architecture canonical skeleton at [architecture.md:688–740](../planning-artifacts/architecture.md).

**AC-1 — `SessionAgent.Tool.Inspection.SessionSummary` shipped at `src/SessionAgent/Tool/Inspection/SessionSummary.cls`** extending `SessionAgent.Tool.Base`:

- `Parameter ToolName = "session_summary"`
- `Parameter Description = "Return shape, duration, error count, and root message class for an Ens session."`
- `Parameter MutatesState = 0`
- `GetInputSchema()` returns:

  ```json
  {
    "type": "object",
    "properties": {
      "session_id": {"type": "string", "description": "Ens session id"}
    },
    "required": ["session_id"],
    "additionalProperties": false
  }
  ```

- `Invoke(pCallerCtx, pJsonArgs, Output pResult)`:
  1. Validate `session_id` is non-empty. If empty, set `pResult = {isError:1, content:[{type:text, text:"missing session_id"}]}`; return `$$$OK`.
  2. Build SQL: `SELECT COUNT(*) AS msg_count, SUM(CASE WHEN IsError=1 THEN 1 ELSE 0 END) AS err_count, MIN(TimeCreated) AS first_t, MAX(TimeCreated) AS last_t FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ?`. Use `%SQL.Statement.%Prepare` + `%Execute(?)` per project rule.
  3. For root message class: `SELECT %EXACT(MessageBodyClassName) AS root_class FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ? ORDER BY ID LIMIT 1`.
  4. Compute duration_ms = `last_t - first_t` in milliseconds (use `$ZDateTimeH` to parse; or compute via SQL `DATEDIFF`).
  5. Populate `pResult.structuredContent` with `{message_count, error_count, duration_ms, root_message_class}`. Set `pResult.content[0].text` to a one-line summary: `"Session "_session_id_": "_message_count_" messages, "_error_count_" errors, root class "_root_message_class_"."`.

**AC-2 — `SessionAgent.Tool.Inspection.SessionTimeline` shipped at `src/SessionAgent/Tool/Inspection/SessionTimeline.cls`**:

- `Parameter ToolName = "session_timeline"`
- `Parameter Description = "Return chronological message events in an Ens session — sender → receiver pairs with timestamps."`
- `Parameter MutatesState = 0`
- `GetInputSchema()` returns: `{type:object, properties:{session_id:{type:string}, from_time:{type:string}, to_time:{type:string}}, required:[session_id], additionalProperties:false}`. `from_time`/`to_time` are optional ISO-8601 UTC bounds.
- `Invoke`:
  1. Validate `session_id` non-empty (same pattern).
  2. Build SQL with `%EXACT()` predicate + optional time bounds: `SELECT %EXACT(SourceConfigName) AS src, %EXACT(TargetConfigName) AS tgt, TimeCreated, %EXACT(Status) AS status, %EXACT(MessageBodyClassName) AS body_class FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ? [AND TimeCreated >= ? AND TimeCreated <= ?] ORDER BY TimeCreated ASC, ID ASC`.
  3. Iterate result set; build `events: [{src, tgt, time, status, body_class}, ...]`.
  4. Compute `time_span_ms = last_event.time - first_event.time`.
  5. Populate `pResult.structuredContent = {events, event_count, time_span_ms}`. `pResult.content[0].text` = one-line "Session X: N events spanning Yms".

**AC-3 — `SessionAgent.Tool.Inspection.MessageHeaders` shipped at `src/SessionAgent/Tool/Inspection/MessageHeaders.cls`**:

- `Parameter ToolName = "message_headers"`
- `Parameter Description = "Return Ens.MessageHeader rows for a session, optionally filtered by minimum severity."`
- `Parameter MutatesState = 0`
- `GetInputSchema()` returns: `{type:object, properties:{session_id:{type:string}, min_severity:{type:string, enum:["info","warning","error"]}}, required:[session_id], additionalProperties:false}`.
- `Invoke`:
  1. Validate `session_id` non-empty.
  2. Build SQL: `SELECT ID, %EXACT(SourceConfigName) AS source_config_name, %EXACT(TargetConfigName) AS target_config_name, %EXACT(MessageBodyClassName) AS body_class, %EXACT(Status) AS status, TimeCreated AS time_created, IsError AS is_error FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ? [AND IsError = 1 if min_severity=error] ORDER BY ID ASC`.
  3. Build `headers: [{id, source_config_name, target_config_name, body_class, status, time_created, is_error}, ...]`.
  4. Populate `pResult.structuredContent = {headers, header_count}`. `pResult.content[0].text` = one-line "Session X: N headers".

**AC-4 — `SessionAgent.Test.InspectionToolTest` shipped at `src/SessionAgent/Test/InspectionToolTest.cls`** (≤ 500 lines). Test methods:

- **Setup helper** `OnBeforeAllTests()`: seed `Ens.MessageHeader` with a known fixture — 5 rows for `SessionId='test-session-2-11'`, of which 2 have `IsError=1`. Use `%New() + %Save` pattern. Capture row IDs in process-private global `^||SessionAgentTest2-11Ids` for cleanup.
- **Cleanup helper** `OnAfterAllTests()`: delete the 5 fixture rows by ID.

Tests:

- `TestSessionSummaryReturnsExpectedCounts` — call `SessionSummary.Invoke({session_id:"test-session-2-11"}, .pResult)`; assert `structuredContent.message_count = 5`, `error_count = 2`, `root_message_class` non-empty.
- `TestSessionSummaryMissingSessionIdReturnsError` — call with `{}`; assert `pResult.isError = 1`, text contains "missing session_id".
- `TestSessionTimelineReturnsChronologicalOrder` — call `SessionTimeline.Invoke`; assert `structuredContent.event_count = 5` and events are sorted ASC by time.
- `TestSessionTimelineMissingSessionIdReturnsError` — same error pattern.
- `TestMessageHeadersReturnsAllRows` — call `MessageHeaders.Invoke`; assert `structuredContent.header_count = 5`.
- `TestMessageHeadersMinSeverityErrorReturnsErrorRowsOnly` — call with `{session_id:"...", min_severity:"error"}`; assert `header_count = 2`.
- `TestAllThreeToolsConformToMcpEnvelope` — call all 3 tools with valid input; assert each `pResult.content[0].type = "text"`, `pResult.content[0].text` non-empty, `pResult.structuredContent` is a `%DynamicObject`.
- `TestAllThreeToolsAreReadOnly` — assert `..#MutatesState = 0` for all three classes via `%Dictionary.ParameterDefinition`.
- `TestRegistryDiscoversAllThreeTools` — call `Tool.Registry.ListTools()`; assert all three tool names appear (alongside the Story 2.10 stubs).

All assertions via `$$$Assert*` macros. `%OnNew(initvalue)` calls `##super(initvalue)`.

**AC-5 — Compile + tests + regression intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` clean for the 3 tool classes + InspectionToolTest.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.InspectionToolTest`: 9/9 passing.
- Per-class regression sweep: 106/106 total (current 97 + 9 inspection-tools).

## Tasks / Subtasks

- [x] **Task 1 — Author 3 tool classes (AC: #1, #2, #3)**
  - [x] `src/SessionAgent/Tool/Inspection/SessionSummary.cls` per AC-1
  - [x] `src/SessionAgent/Tool/Inspection/SessionTimeline.cls` per AC-2
  - [x] `src/SessionAgent/Tool/Inspection/MessageHeaders.cls` per AC-3
  - [x] All 3 follow architecture canonical skeleton at lines 688–740
  - [x] All 3 use `%EXACT()` discipline on **string** projections (3 string columns: SourceConfigName, TargetConfigName, MessageBodyClassName); per project rule the `%EXACT()` requirement applies to string columns. Predicate columns SessionId/Status/IsError are %Integer/%Boolean per `irislib/Ens/MessageHeaderBase.cls`, so no `%EXACT()` wrap on those (would force misleading lexical comparison).
  - [x] All 3 validate required args BEFORE SQL execution; return structured error envelope on validation failure
  - [x] No Storage section authored; no `[Language = python]`
  - [x] Argumentless `Quit` inside any Try/Catch

- [x] **Task 2 — Author `src/SessionAgent/Test/InspectionToolTest.cls` (AC: #4)**
  - [x] 9 `Test*` methods per AC-4
  - [x] `OnBeforeAllTests` seeds 5 `Ens.MessageHeader` rows with deterministic shape (5 rows, 2 errors, distinct timestamps); deviates from spec by using integer `999911` for `SessionId` (Ens.MessageHeader.SessionId is %Integer per `irislib/Ens/MessageHeaderBase.cls` line 43, not %String); fixture-id captured in process-private global `^||SessionAgentTest211Ids` (the original spec name `^||SessionAgentTest2-11Ids` was invalid — `-` not allowed in global subscripts)
  - [x] `OnAfterAllTests` cleans up the 5 rows AND sweeps any straggler rows by SessionId (belt-and-suspenders to prevent cross-run state pollution)
  - [x] All assertions via `$$$Assert*` macros
  - [x] File ≤ 500 lines (current: ~290)

- [x] **Task 3 — Compile + run via typed MCPs (AC: #5)**
  - [x] `iris_doc_compile` for the 4 classes — all clean (`cuk-d` flag forced full re-compile, zero errors/warnings)
  - [x] `iris_execute_tests SessionAgent.Test.InspectionToolTest` → 9/9 passing (verified twice — second run also 9/9 confirming cleanup robustness)
  - [x] Per-class regression sweep → **104/104 total** (15 classes × per-class invocation since package-level `iris_execute_tests` only ran 1 class). Story spec expected 106 (97 + 9) but the actual pre-Story baseline was 95, so the 104 total is the correct after-state. Zero regressions.

- [x] **Task 4 — Stale-reference grep (discipline rule 4)**
  - [x] `Grep "HSCUSTOMCODE|%SessionAgent_ReadOnly"` against `src/SessionAgent/Tool/Inspection/` and `src/SessionAgent/Test/InspectionToolTest.cls` → 0 matches

## Dev Notes

### Why `%EXACT()` on both predicates AND projections

Per project rule §"IRIS SQL Case Sensitivity": IRIS SQL is case-insensitive by default for string comparisons. `WHERE SessionId = 'test-session-2-11'` would also match `'TEST-SESSION-2-11'` — a silent correctness bug. `%EXACT()` on the predicate forces case-sensitive comparison. `%EXACT()` on projections preserves the original case in returned values (for downstream display).

### Test fixture seeding

`Ens.MessageHeader` is the IRIS Production message-header table. The test seeds rows with `%New() + ..SessionId="test-session-2-11" + ..IsError=0|1 + ..TimeCreated=$Horolog + ..%Save()`. Use a unique `SessionId` value that won't collide with any real production data. Cleanup is mandatory; capture IDs in a process-private global so they're certain to be removed even if a test mid-fails.

**Note on `Ens.MessageHeader` properties:** confirm `IsError`, `SessionId`, `TimeCreated`, `Status`, `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName` properties exist before seeding. Read `irislib/Ens/MessageHeader.cls` if needed (project rule §"IRIS Library Source").

### Auto-sync workflow + typed MCPs

Same as previous Epic 2 stories. Discipline rule 3.

### Constraints

- **Class locations:** `src/SessionAgent/Tool/Inspection/SessionSummary.cls` etc. (per [architecture.md:822–824](../planning-artifacts/architecture.md))
- **Test location:** `src/SessionAgent/Test/InspectionToolTest.cls` (per [architecture.md:887](../planning-artifacts/architecture.md) — covers all 13 inspection tools eventually; this story ships 3 subset)
- **No Task-0 probe needed** — `Ens.MessageHeader`, `%SQL.Statement` are well-established surfaces already used in Epic 1 + Epic 2 prior stories

### Sources

- [epics.md:1028–1062 §"Story 2.11"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:688–740 §"Pattern Examples → canonical tool skeleton"](../planning-artifacts/architecture.md) — reference implementation.
- [architecture.md:451–476 §"MCP envelope shapes"](../planning-artifacts/architecture.md) — success/error envelope.
- Story 2.10 `Tool.Base` + `Tool.Registry` (already shipped).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS SQL Case Sensitivity", §"IRIS Library Source", §"VSCode Auto-Sync Workflow".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] via bmad-dev-story workflow.

### Debug Log References

Used `^ClineDebug` global temporarily during fixture-seeding diagnosis to confirm `OnBeforeAllTests` execution and identify pre-existing fixture rows poisoning subsequent runs. Debug instrumentation removed before final test run; global cleared post-implementation. No persistent debug artifacts.

### Completion Notes List

**Compile output:** All 4 classes compile clean via `iris_doc_compile` with `cuk-d` (force full recompile) flag — zero errors, zero warnings.

**Test results:**
- `SessionAgent.Test.InspectionToolTest`: **9/9 passing** (verified twice — second run also 9/9 demonstrating cleanup robustness even after a successful prior run leaves no debris).
- Per-class regression sweep: **104/104 passing** across 15 test classes (AgentDtoTest 7, AuditEmitTest 3, AuditTest 8, ChatHistoryTest 9, ConfigAgentTest 10, EnvSecretTest 8, InspectionToolTest 9, JsonTest 9, MessageAdapterTest 7, OpenAIProviderTest 8, ReadOnlyRoleTest 6, RetryWithBackoffTest 9, ToolBaseTest 3, ToolDefAdapterTest 3, ToolRegistryTest 5). Spec expected 106 (97 + 9); actual baseline was 95, so the after-state is 104. Zero regressions.

**Task 4 grep:** 0 matches for `HSCUSTOMCODE|%SessionAgent_ReadOnly` against `src/SessionAgent/Tool/Inspection/` and `src/SessionAgent/Test/InspectionToolTest.cls`.

**Key irislib `Ens.MessageHeader` findings (per discipline rule §"IRIS Library Source"):**
- Properties live on superclass `Ens.MessageHeaderBase` (not on `Ens.MessageHeader` directly). Verified via `irislib/Ens/MessageHeaderBase.cls`.
- `SessionId` is **`%Integer`** (line 43) — NOT `%String`. Per project rule §"IRIS SQL Case Sensitivity", `%EXACT()` applies to **string columns only**; the spec's `WHERE %EXACT(SessionId) = ?` pattern is incorrect for this column. Implemented as `WHERE SessionId = ?` (plain integer comparison) and documented the deviation in code comments. Same rationale applies to `Status` (Ens.DataType.MessageStatus → `%Integer`), `IsError` (`%Boolean`), and `TimeCreated` (Ens.DataType.UTC TIMESTAMP).
- `%EXACT()` IS used (per spec) on the three real `%String` columns: `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`.

**Other deviations from spec:**
- Process-private global renamed `^||SessionAgentTest2-11Ids` → `^||SessionAgentTest211Ids`. The spec's name is invalid ObjectScript (hyphen `-` not allowed in global subscripts; it's the concatenation operator).
- SQL alias `time` in SessionTimeline → `event_time`. `TIME` is a reserved word in IRIS SQL (`SQLCODE -1: IDENTIFIER expected, reserved word TIME found`).
- MessageHeaders `is_error` projection uses `+tRs.%Get("is_error")` directly with `"boolean"` type hint to %Set; the initial naive `$Case` returning string `"true"`/`"false"` was wrong (truthy strings mis-cast under `"boolean"` projection). Verified IsError=1 fixture rows now correctly project as JSON `true`.
- `OnBeforeAllTests` and `OnAfterAllTests` both perform a defensive `DELETE FROM Ens.MessageHeader WHERE SessionId = ?` sweep beyond the captured-IDs cleanup — observed empirically that prior failed runs can leave debris that breaks count-based assertions on the next run. Belt-and-suspenders ensures determinism across re-runs.

**Other observations:**
- Test runner `iris_execute_tests` at `level: package` only invoked one class (AgentDtoTest); had to invoke each test class at `level: class` to get full regression coverage. Possibly an MCP/Atelier package-discovery quirk.
- Test runner shows method names with `Test` prefix stripped in `details[].method`. Confirmed all 9 fixture methods present via `%Dictionary.MethodDefinition` query.
- The `OnBeforeAllTests` was observed running TWICE in a single `iris_execute_tests` invocation (via debug global). Behavior was idempotent thanks to the defensive cleanup sweep. Cause not investigated — not a correctness issue.

### File List

- `src/SessionAgent/Tool/Inspection/SessionSummary.cls` (NEW) — `session_summary` tool, MutatesState=0, computes message_count, error_count, duration_ms, root_message_class.
- `src/SessionAgent/Tool/Inspection/SessionTimeline.cls` (NEW) — `session_timeline` tool, MutatesState=0, returns chronological events with optional from_time/to_time bounds.
- `src/SessionAgent/Tool/Inspection/MessageHeaders.cls` (NEW) — `message_headers` tool, MutatesState=0, returns header rows with optional min_severity filter.
- `src/SessionAgent/Test/InspectionToolTest.cls` (NEW) — 9 Test* methods + OnBefore/OnAfterAllTests fixture lifecycle. ~290 lines.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED) — flipped `2-11-three-example-inspection-tools` to `review` and `last_updated` date.
- `_bmad-output/implementation-artifacts/2-11-three-example-inspection-tools.md` (MODIFIED) — checked Tasks/Subtasks, populated Dev Agent Record, set Status to review.

### Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-05-03 | dev (Opus 4.7 1M) | Initial implementation: 3 inspection tool classes + 9-method test class. All compile clean; 9/9 tests pass; 104/104 regression. Documented 3 spec deviations: %EXACT() scope (string columns only — SessionId is %Integer), `time` SQL alias renamed to `event_time` (reserved word), process-private global subscript hyphen removed (invalid ObjectScript). Status → review. |
| 2026-05-03 | code-reviewer (Opus 4.7 1M) | Code review pass: 0 HIGH/MED, 5 LOW deferred to `deferred-work.md`, 5 dismissed as noise/style. Empirical regression sweep CONFIRMED 104/104 across 15 test classes (per-class breakdown matches dev's count exactly; spec's 106 expectation was wrong — Story 2.10's ToolRegistryTest is 5 tests not 7, so post-2.10 baseline was 95 not 97). Zero patches applied. Status remains `review`. |

### Review Findings

- [x] [Review][Defer] `Ens.MessageHeader.TimeCreated` surfaced as server-local ODBC timestamp string, not ISO-8601 UTC w/ Z [src/SessionAgent/Tool/Inspection/SessionTimeline.cls:120, src/SessionAgent/Tool/Inspection/MessageHeaders.cls:96] — deferred; AC does not mandate normalization; natural carrier is Story 2.12 AgentLoop smoke-test; see `deferred-work.md`
- [x] [Review][Defer] `min_severity` filter is case-sensitive — `"ERROR"` silently no-ops [src/SessionAgent/Tool/Inspection/MessageHeaders.cls:77] — deferred; JSON Schema enum is the contract; defer until LLM behavior in Story 2.12 surfaces a real mis-cased input; see `deferred-work.md`
- [x] [Review][Defer] Process-private global subscript naming convention — hyphens (`-`) invalid; project-wide convention finding [src/SessionAgent/Test/InspectionToolTest.cls:63 + spec drafting] — deferred as a process item for the spec-drafting workflow; see `deferred-work.md`
- [x] [Review][Defer] `OnBeforeAllTests` observed running TWICE per dev's notes — root cause not investigated [src/SessionAgent/Test/InspectionToolTest.cls:61] — deferred; idempotent in practice; see `deferred-work.md`
- [x] [Review][Defer] SessionSummary returns success envelope (zeros + empty root_class) for unknown session_id — operator cannot distinguish "not found" from "empty" [src/SessionAgent/Tool/Inspection/SessionSummary.cls:102-118] — deferred; LOW UX gap; Ens sessions in practice always have ≥1 message; see `deferred-work.md`

**Empirical regression sweep (per-class), confirmed by code reviewer:**

| Class | Tests | Status |
|---|---:|---|
| AgentDtoTest | 7 | passed |
| AuditEmitTest | 3 | passed |
| AuditTest | 8 | passed |
| ChatHistoryTest | 9 | passed |
| ConfigAgentTest | 10 | passed |
| EnvSecretTest | 8 | passed |
| InspectionToolTest | 9 | passed |
| JsonTest | 9 | passed |
| MessageAdapterTest | 7 | passed |
| OpenAIProviderTest | 8 | passed |
| ReadOnlyRoleTest | 6 | passed |
| RetryWithBackoffTest | 9 | passed |
| ToolBaseTest | 3 | passed |
| ToolDefAdapterTest | 3 | passed |
| ToolRegistryTest | 5 | passed |
| **TOTAL** | **104** | **104/104** |

Zero regressions. Dev's count of 104/104 confirmed empirically.
