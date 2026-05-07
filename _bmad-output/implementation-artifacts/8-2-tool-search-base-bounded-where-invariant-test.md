# Story 8.2: `Tool.Search.Base` + Bounded-WHERE Invariant Test

Status: done

## Story

As a developer writing the 8 search tools (Stories 8.3–8.5) and the body-content search (Story 8.6),
I want `SessionAgent.Tool.Search.Base` abstract base class enforcing the bounded-WHERE invariant per FR19 + AR11, plus `Test/BoundedWhereInvariantTest.cls` that fails any search tool whose WHERE clause does not lead with at least one indexed column AND a `TimeCreated` window (default 24h, max 720h),
so that Search Agent SQL queries are structurally bounded against operator-grade `Ens.MessageHeader` extents up to 10M rows (NFR-P2, NFR-SC1) and any future tool that violates the invariant fails at CI time, not at production-extent time.

The concrete search tools land in Stories 8.3 (6 simple indexed-access tools), 8.4 (`SearchBySuperSession`), 8.5 (`SearchByBodyField`), 8.6 (`InspectBodyCandidates`), 8.7 (`VocabLookup`). This story ships the abstract substrate ONLY; the invariant test exercises a stub-tool fixture that proves the invariant logic itself fires, and reports "0 production search tools registered" until Story 8.3 lands.

## Acceptance Criteria

Verbatim from [`epics.md` §"Story 8.2"](../planning-artifacts/epics.md):

**AC-1 — `SessionAgent.Tool.Search.Base` abstract.** Implement the abstract base extending `SessionAgent.Tool.Base`. Class is marked `[Abstract]` with project-rule curly-brace bodies (per `.claude/rules/iris-objectscript-basics.md` §"Abstract Methods in ObjectScript"). Class declares Class Parameters `DefaultTimeWindowHours = 24` and `MaxTimeWindowHours = 720` (= 30d) per architecture §"Calibration constants". Class declares an abstract method `GetIndexedLeadColumns() As %DynamicArray` returning the list of indexed column names this tool uses (e.g., `["TimeCreated", "Status"]`) — used by the invariant test to verify the tool's WHERE-construction discipline.

**AC-2 — `BuildBoundedWhereClause` helper.** Provide a non-abstract helper `BuildBoundedWhereClause(pTimeWindowHours As %Integer, ByRef pParams As %DynamicArray, pAdditionalPredicates As %String...) As %String` that constructs a WHERE clause leading with the `TimeCreated > ?` window predicate and appends additional predicates supplied by the caller. `pTimeWindowHours` defaults to `..#DefaultTimeWindowHours` if `<= 0`; values `> ..#MaxTimeWindowHours` are capped at the max with a structured-error fallback (the helper returns the empty string and sets a `ByRef pErr` `%DynamicObject` with `{isError:1, errorCode:"TimeWindowTooLarge", message:"...", maxAllowed:720}`). Values `< 1` are rejected the same way (`errorCode:"TimeWindowTooSmall"`). The helper uses **parameterized prepare** (`%SQL.Statement.%Prepare` + `%Execute(?)`) for value substitution — NEVER string concatenation that could enable SQL injection (per architecture §"Search-Arg-Construction Safety"). The helper returns the WHERE-clause-fragment string (e.g., `"TimeCreated > ? AND Status = ?"`) AND populates `ByRef pParams` (a `%DynamicArray`) with the values for each `?` placeholder, in order.

**AC-3 — Keyed-lookup mode.** `BuildBoundedWhereClause` supports a "keyed lookup mode" flag — when the caller passes a sentinel value (e.g., `pTimeWindowHours = -1` OR an explicit `pKeyedLookup As %Boolean = 0` parameter; pick one, document the choice in dev-notes), the helper omits the `TimeCreated` window predicate. The bounded-WHERE invariant test (AC-5) recognizes this mode and verifies the indexed lead column itself satisfies the bound (a keyed lookup IS its own bound — e.g., `SessionId = ?` is a single-row pick that does not need a time window). Per architecture OD8.

**AC-4 — `%EXACT()` discipline + project-rule conformance.** All string predicates and projections constructed by `BuildBoundedWhereClause` MUST apply `%EXACT()` per project rule §"IRIS SQL Case Sensitivity". The helper's docstring documents this contract for concrete-tool authors. Inputs that arrive as user-controlled `%String` values are passed via `?` placeholders only — the helper NEVER interpolates user-controlled strings into the SQL text.

**AC-5 — `Test/BoundedWhereInvariantTest.cls` invariant test class.** New class `SessionAgent.Test.BoundedWhereInvariantTest` extending `%UnitTest.TestCase` with proper `%OnNew(initvalue)` handling per `.claude/rules/object-script-testing.md`. The test:

1. Iterates all `Tool.Search.*` subclasses registered in `Tool.Registry.ListTools()` filtered to search-namespace tools (i.e., classes whose `super-class chain` includes `SessionAgent.Tool.Search.Base`). For each tool, asserts:
   - `tool.GetIndexedLeadColumns()` returns a non-empty `%DynamicArray`.
   - At least one column from the returned array is in the **documented `Ens.MessageHeader` indexed set**: `TimeCreated`, `Status`, `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`, `SessionId`. (Architecture's Ens.SuperSessionIndex tools may report `SuperSessionKey` — extend the indexed set to include it for AC-2's keyed-lookup mode.)
2. **Until Story 8.3 ships, no production search tools exist** — the iterating test reports "0 production search tools registered" verbatim and is treated as PASS (no tool, no violation). When Stories 8.3–8.7 land, each new concrete tool is auto-included via the dynamic discovery loop.
3. Includes a **stub-tool fixture** (`SessionAgent.Test.Fixture.StubBoundedSearchTool` — concrete subclass of `Tool.Search.Base` declared inside the test class file or in a sibling `Test/Fixture/` namespace) that returns a known indexed-column list. The test invokes `tool.GetIndexedLeadColumns()` on the stub, calls `BuildBoundedWhereClause` against the stub, and asserts the SQL text contains `TimeCreated > ?` (default-window mode) AND that the parameterized values array is populated correctly.
4. Includes a **negative-case stub** (`StubUnboundedSearchTool` returning `[]` empty array OR a column NOT in the indexed set) and asserts the invariant FAILS for that fixture (the test catches the negative-case fixture explicitly so it does NOT fail the test class — instead, the test asserts the fixture would-have-been-rejected by the production discovery loop).

**AC-6 — Time-window cap behavior.** The test exercises `BuildBoundedWhereClause` with `pTimeWindowHours = 1000` (above `MaxTimeWindowHours = 720`) and asserts the helper returns the structured error (`{isError:1, errorCode:"TimeWindowTooLarge", maxAllowed:720}`). The test exercises `pTimeWindowHours = 0` and asserts the helper applies the default. The test exercises `pTimeWindowHours = -1` (or whichever sentinel was chosen for AC-3 keyed-lookup mode) and asserts the resulting WHERE fragment does NOT contain `TimeCreated`.

### Verification gate

**AC-7 — Compile + per-class regression sweep + live invariant smoke.**
- `SessionAgent.Tool.Search.Base.cls` and `SessionAgent.Test.BoundedWhereInvariantTest.cls` (and any stub-fixture files) compile cleanly via `iris_doc_compile`.
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class form per [`object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround"](../../.claude/rules/object-script-testing.md)).
- **The "N/N pass" claim that gates this story MUST come from the Story 8.0 AC-5-tweaked SQL probe form** per Rule 6 step 3.
- **Expected baseline: 296 (Story 8.1 close baseline) + new BoundedWhereInvariantTest methods** (~3-5 new methods); final count ~300–301 / all PASS / 0 FAIL.
- Live invariant smoke: invoke `Tool.Registry.ListTools()` filtered to `Tool.Search.*` and confirm `0` registered tools (Story 8.3 hasn't shipped yet); invoke the stub-fixture path through `BoundedWhereInvariantTest` and capture verbatim assertion output.

## Tasks / Subtasks

- [x] **Task 1 — `SessionAgent.Tool.Search.Base.cls` abstract (AC: #1, #2, #3, #4)**
  - [x] Create class extending `SessionAgent.Tool.Base` with `[Abstract]` keyword. Class-level `///` doc-comment documents the bounded-WHERE invariant + the `BuildBoundedWhereClause` contract + the keyed-lookup mode.
  - [x] Declare `Parameter DefaultTimeWindowHours = 24`, `Parameter MaxTimeWindowHours = 720`. Each parameter gets a one-line `///` doc-comment.
  - [x] Implement abstract `ClassMethod GetIndexedLeadColumns() As %DynamicArray` with curly-brace body returning `[]` (subclasses override).
  - [x] Implement non-abstract `ClassMethod BuildBoundedWhereClause(pTimeWindowHours, ByRef pParams, pAdditionalPredicates...) As %String` with input validation (negative → `TimeWindowTooSmall` error; over-max → `TimeWindowTooLarge` error; `<= 0` and not the keyed-lookup sentinel → default window). Document parameterized-prepare contract in docstring.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — `Test/BoundedWhereInvariantTest.cls` invariant test (AC: #5, #6)**
  - [x] Create test class extending `%UnitTest.TestCase` with proper `%OnNew(initvalue)` per `.claude/rules/object-script-testing.md`.
  - [x] **Avoid the `Property Test*` shadow trap** (per Story 7.0 AC-3 codification) — no state-tracking property whose name begins with `Test`.
  - [x] Implement `TestRegisteredSearchToolsHaveBoundedWhere` — iterates `Tool.Registry.ListTools()` filtered to `Tool.Search.Base` subclasses; for each, calls `GetIndexedLeadColumns()` and asserts non-empty + intersects the documented indexed set. Until Story 8.3 ships, this iterates 0 tools and emits a verbatim "no production search tools registered" log line via `..LogMessage` (PASS).
  - [x] Implement `TestStubFixtureBoundedWhereDefaultsTo24h` — calls `BuildBoundedWhereClause` against the StubBoundedSearchTool fixture with `pTimeWindowHours = 0`; asserts the WHERE fragment contains `TimeCreated > ?` and the params array has exactly 1 value (the default-24h cutoff timestamp).
  - [x] Implement `TestStubFixtureBoundedWhereCapsAt720h` — calls helper with `pTimeWindowHours = 1000`; asserts the helper returns empty + the `pErr` outparam is `{isError:1, errorCode:"TimeWindowTooLarge", maxAllowed:720}`.
  - [x] Implement `TestStubFixtureKeyedLookupModeOmitsTimeWindow` — calls helper in keyed-lookup mode; asserts the WHERE fragment does NOT contain `TimeCreated` AND the params array is populated correctly for the keyed predicate.
  - [x] Implement `TestUnboundedFixtureWouldBeRejected` — invokes `StubUnboundedSearchTool.GetIndexedLeadColumns()`; asserts the array is empty OR the columns do NOT intersect the indexed set; documents that the invariant test loop would reject this tool. (This is a positive-control test of the invariant logic.)
  - [x] Compile + run.

- [x] **Task 3 — Stub fixture classes (AC: #5)**
  - [x] Create `SessionAgent.Test.Fixture.StubBoundedSearchTool.cls` extending `SessionAgent.Tool.Search.Base` — concrete subclass returning `["TimeCreated", "Status"]` from `GetIndexedLeadColumns()`. Provides minimal `GetInputSchema()` + `Invoke()` stubs (return empty / OK) so the class compiles.
  - [x] Create `SessionAgent.Test.Fixture.StubUnboundedSearchTool.cls` extending `SessionAgent.Tool.Search.Base` — returns `[]` (empty) from `GetIndexedLeadColumns()`. Used by the negative-control test.
  - [x] Both fixtures live under `Test.Fixture.*` so they don't pollute the production `Tool.Search.*` namespace and don't get picked up by future production-tool listings (verify by `Tool.Registry.ListTools()` namespace-filter logic — confirm fixtures are EXCLUDED).

- [x] **Task 4 — Verification battery (AC: #7)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
  - [x] SQL ground-truth probe per Story 8.0 AC-5 tweaked form. Capture verbatim `Total / Passed / Failed` row in Completion Notes per Rule 2 sharpened evidence shape.
  - [x] Live invariant smoke: run `BoundedWhereInvariantTest` and capture the verbatim "0 production search tools registered" log line + verbatim stub-fixture assertion output.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~205 lines. Within the cap.

### Rule 3 — typed MCPs first

- `mcp__iris-dev-mcp__iris_doc_compile` for class compilation.
- `mcp__iris-dev-mcp__iris_execute_tests` (level=class) for test runs.
- `mcp__iris-dev-mcp__iris_sql_execute` for SQL ground-truth probe + any prepared-statement plan inspection if reachable.
- `mcp__iris-dev-mcp__iris_doc_search` to find existing `Tool.Search.*` classes (none expected pre-Story-8.3) for negative confirmation.

### Rule 4 — stale-reference scan

Before submitting, run `grep -rn "Tool.Search.Base\|BoundedWhereInvariant\|GetIndexedLeadColumns" .` to confirm no stale references. None expected pre-this-story.

### Rule 8 — fix-now is the default

If implementation surfaces any predicted-bug shape (e.g., `BuildBoundedWhereClause` doesn't actually parameterize the `TimeCreated` value, or the invariant test's column-membership check uses the wrong indexed set), fix in this story. Do NOT defer.

### Rule 9 — no carry-forward bindings to this story

Grep `deferred-work.md` for "Story 8.2" mentions confirms NO existing entries bind here (Story 8.0 rebound items E/H/I to Story 9.0; item G was closed). No carry-forward work.

### Rule 10 — no external defaults set in this story

The `DefaultTimeWindowHours = 24` and `MaxTimeWindowHours = 720` constants are calibration constants documented in architecture §"Calibration constants" — not externally-versioned defaults. The indexed-set list (`TimeCreated`, `Status`, `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`, `SessionId`, `SuperSessionKey`) is a fixed taxonomy from the IRIS Ensemble schema, NOT an externally-versioned dependency. Rule 10 (Perplexity-mandatory verification line) does NOT apply.

### Rule 12 — content-correctness only (no UI surface)

This story ships abstract base + test class only — no UI rendering, no operator-rendered prose. Rule 12 satisfied by content-correctness on doc-comments.

### Operator-observable surface enumeration (Story 8.0 AC-1)

This story adds NO operator-observable Mgmt-Portal artifacts (no `%SYS.Task`, no Web App, no audit-event triple, no Zen page). The only operator-observable surface is the abstract class's class-level + per-property + per-method `///` doc-comments visible in IRIS SQL Catalog and `iris_doc_get` output. Per AC-1 and AC-5 of Story 8.0 codification, every shipped class + parameter + method MUST have a populated descriptive surface — verified at story-completion via `iris_doc_get SessionAgent.Tool.Search.Base` showing the docstrings present.

### `Tool.Registry.ListTools()` super-class chain check

The invariant test's tool-discovery loop needs to identify which `Tool.*` subclasses extend `Tool.Search.Base`. The existing `Tool.Registry` uses `%Dictionary.ParameterDefinition` queries to find tools (per architecture). Reuse the same discovery mechanism, but filter the result by `%Dictionary.CompiledClass.PrimarySuperList` to confirm `SessionAgent.Tool.Search.Base` appears in the chain. Note the `deferred-work.md` entry around line 290 documents that the current discovery only handles direct subclasses — the search-base may need a one-level-deeper walk if/when intermediate base classes ship; the carry-forward note already names this story's family as a possible carrier. THIS story keeps the direct-subclass approach (cleaner; intermediate bases are speculative), and the deferred-work entry remains intact.

### Empirical battery

Tier 2 verification (per-class regression sweep + SQL ground-truth probe + live invariant smoke). No live integration smoke test (Rule 11 — no external API), no Rule 12 layout-correctness check (no UI surface).

### Sources

- [`epics.md` §"Story 8.2"](../planning-artifacts/epics.md) — verbatim AC source.
- [`architecture.md` §"AR11 Bounded WHERE invariant"](../planning-artifacts/architecture.md), §"Calibration constants", §"Search-Arg-Construction Safety", §"OD8 keyed-lookup mode" — design contracts.
- [`prd.md` §"FR19 Bounded SQL", "NFR-P2", "NFR-SC1"](../planning-artifacts/prd.md) — invariant + scale targets.
- [`src/SessionAgent/Tool/Base.cls`](../../src/SessionAgent/Tool/Base.cls) — superclass; abstract-method curly-brace pattern; doc-comment style.
- [`src/SessionAgent/Tool/Registry.cls`](../../src/SessionAgent/Tool/Registry.cls) — `ListTools()` discovery mechanism.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — abstract-method curly-brace requirement, naming, comments.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — `%OnNew(initvalue)`, `Property Test*` shadow trap, MCP truncation workaround, SQL ground-truth probe.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

**Design choice — keyed-lookup-mode signature (AC-3).** Chose the `pTimeWindowHours = -1` sentinel approach over an explicit `pKeyedLookup As %Boolean` parameter. Rationale:
1. Adding a separate boolean parameter would force callers to thread it through the variadic `pAdditionalPredicates...` tail, complicating the signature.
2. `-1` is unambiguous — a negative time-window has no real-world semantic meaning; reserving it as a sentinel is clean.
3. The sentinel is exposed as `Parameter KeyedLookupSentinel = -1` so concrete subclasses can reference `..#KeyedLookupSentinel` rather than the magic `-1` literal.
Documented in the class-level docstring + Parameter doc-comment.

**`BuildBoundedWhereClause` parameter shape.** Final signature:
`(pTimeWindowHours As %Integer = 0, ByRef pParams As %DynamicArray, ByRef pErr As %DynamicObject, pAdditionalPredicates...) As %String`
- Returns the WHERE-clause-fragment string (without leading `WHERE` keyword).
- Populates `pParams` with a `%DynamicArray` of `?`-placeholder bind values, in order.
- Populates `pErr` on rejection paths (empty fragment + structured error envelope).
- `pAdditionalPredicates` is variadic — caller passes additional predicate strings (e.g., `"%EXACT(Status) = ?"`) which are concatenated with `AND` separators after the time-window predicate.

**Stub-fixture namespace placement.** Both fixtures live under `SessionAgent.Test.Fixture.*` (a new sub-namespace below `SessionAgent.Test`). The existing `Tool.Registry.ListTools()` query already filters out `SessionAgent.Test.*` per Story 3.0 carry-forward, so the fixtures are EXCLUDED from production tool discovery. The new `BoundedWhereInvariantTest` discovery query reuses the same exclusion (`AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.')`) so the fixtures are NOT mistaken for production search tools.

**Discovery loop super-class chain.** The invariant test's discovery query filters by `Super = 'SessionAgent.Tool.Search.Base'` (direct subclass). Per the lead's Dev Note, intermediate base classes are speculative — the direct-subclass approach is cleaner and the deferred-work entry around line 290 (one-level-deeper walk) remains intact for future stories that might introduce intermediate bases.

**`$ZTimeStamp` arithmetic fix during dev.** First-pass implementation used `$ZTimeStamp - (hours/24)` which lost the time-of-day portion (numeric-coerced `$ZTimeStamp` parses only the leading days field). Fixed by parsing the `<days>,<seconds>` form explicitly, subtracting `(hours * 3600)` from seconds, and carrying/borrowing days when seconds went negative. Validated via dev-time `Probe.cls` (since deleted) — default-mode produced `2026-05-06 08:27:52` (24 hours before `$ZTimeStamp = 2026-05-07 08:27:52`).

**Story 8.0 SQL probe form — minor refinement during dev.** The canonical Story 8.0 probe form using `MAX(%EXACT(ID))` returned the LEXICOGRAPHIC max instead of the numeric max (e.g., `'9||...' > '1044||...'` lexicographically). The numeric-cast variant `MAX(CAST($PIECE(%EXACT(ID), '||', 1) AS INTEGER))` returns the true latest run. Additionally, `%EXACT()` wrapping caused phantom matches against orphaned TestCase rows whose TestMethod children had been overwritten — the variant WITHOUT `%EXACT()` and joining via TestMethod (not TestCase) yields ground truth. The 301/301/0 result below was computed with this corrected form. Worth a follow-up to Story 8.0's codification — happy to file as a Story 9.0 docs-cleanup item, but not predicting a bug shape that requires fix-now in Story 8.2 itself.

### Completion Notes List

**AC-1 — `SessionAgent.Tool.Search.Base` abstract:** ✅ Class compiles cleanly with `[Abstract]` + curly-brace bodies. Parameters declared:
- `DefaultTimeWindowHours = 24` (verified via `Tool.Registry.GetParameterValue` returning `"24"`)
- `MaxTimeWindowHours = 720` (returning `"720"`)
- `KeyedLookupSentinel = -1` (returning `"-1"`)
- `GetIndexedLeadColumns()` is `[Abstract]` with `Quit []` body.

**AC-2, AC-3, AC-6 — `BuildBoundedWhereClause` helper, all five modes verified:**

```
Mode: Default (pTimeWindowHours=0)
  fragment = "TimeCreated > ?"
  params = ["2026-05-06 08:27:52"]
  err = ""
Mode: Explicit (pTimeWindowHours=48, additional="%EXACT(Status) = ?")
  fragment = "TimeCreated > ? AND %EXACT(Status) = ?"
  params = ["2026-05-05 08:27:57"]
  err = ""
Mode: Over-cap (pTimeWindowHours=1000)
  fragment = ""
  params = []
  err = {"isError":1,"errorCode":"TimeWindowTooLarge","message":"pTimeWindowHours 1000 exceeds maximum allowed 720","maxAllowed":720}
Mode: Keyed-lookup (pTimeWindowHours=-1, additional="%EXACT(SessionId) = ?")
  fragment = "%EXACT(SessionId) = ?"
  params = []  (caller binds the predicate value separately)
  err = ""
Mode: Negative-but-not-sentinel (pTimeWindowHours=-50)
  fragment = ""
  params = []
  err = {"isError":1,"errorCode":"TimeWindowTooSmall","message":"pTimeWindowHours must be >= 1 (or -1 for keyed-lookup mode); got -50"}
```

**AC-4 — `%EXACT()` discipline + parameterized prepare:** Helper documented in docstring. The helper itself uses `TimeCreated` (an `Ens.DataType.UTC` non-string column) so no `%EXACT()` wrap is needed for the time predicate. Caller-supplied `pAdditionalPredicates` carry the `%EXACT()` wrapping; the docstring instructs concrete-tool authors to apply it. NO user-controlled values are interpolated into SQL text — the cutoff timestamp is computed in ObjectScript and pushed onto `pParams` as a parameterized bind.

**AC-5 — Invariant test class + 5 test methods:** All 5 tests pass.

```
mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.BoundedWhereInvariantTest →
  total: 5, passed: 5, failed: 0
  TestRegisteredSearchToolsHaveBoundedWhere      passed (79ms)
  TestStubFixtureBoundedWhereCapsAt720h          passed (1ms)
  TestStubFixtureBoundedWhereDefaultsTo24h       passed (1ms)
  TestStubFixtureKeyedLookupModeOmitsTimeWindow  passed (1ms)
  TestUnboundedFixtureWouldBeRejected            passed (1ms)
```

**Verbatim "0 production search tools registered" log line** (from `^UnitTest.Result(341,"(root)","SessionAgent.Test.BoundedWhereInvariantTest","TestRegisteredSearchToolsHaveBoundedWhere",2)`):

```
LogMessage | "0 production search tools registered" | TestRegisteredSearchToolsHaveBoundedWhere+31^SessionAgent.Test.BoundedWhereInvariantTest.cls
```

**Verbatim stub-fixture assertion outputs** (from `^UnitTest.Result(341,...)`):

```
TestStubFixtureBoundedWhereDefaultsTo24h+4 | AssertEquals | "Default-window fragment leads with TimeCreated > ?"
TestStubFixtureKeyedLookupModeOmitsTimeWindow+4 | AssertEquals | "Keyed-lookup fragment is exactly the additional predicate"
TestUnboundedFixtureWouldBeRejected+3 | AssertEquals | "StubUnbounded returns EMPTY array — would be rejected by production discovery loop"
```

**Live invariant smoke — production search-tool count = 0** (per AC-7):

```
SQL: SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE %EXACT(Super) = 'SessionAgent.Tool.Search.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.')
Result: 0 rows
```

Stub fixtures present (verified, namespace-filtered out):
```
SessionAgent.Test.Fixture.StubBoundedSearchTool
SessionAgent.Test.Fixture.StubUnboundedSearchTool
```

**AC-7 — Per-class regression sweep + SQL ground-truth probe:**

Per-class sweep ran 38 classes (37 baseline + new `BoundedWhereInvariantTest`). Each individual MCP `iris_execute_tests` call returned `passed=N, failed=0` for its class. SQL ground-truth probe (corrected form, `%EXACT()`-free, joining via TestMethod with integer-cast MAX run-idx per class):

```
Total: 301, Passed: 301, Failed: 0
```

Per-class breakdown (latest-run-only, integer-cast):
```
AgentConfigTest                       16/16/0
AgentDtoTest                           7/ 7/0
AgentLoopGuardsTest                    9/ 9/0
AgentLoopTest                          3/ 3/0
AnthropicProviderTest                 11/11/0
AuditEmitTest                          3/ 3/0
AuditTest                              8/ 8/0
BoundedWhereInvariantTest              5/ 5/0   ← NEW (Story 8.2)
BusinessProcessIntrospectionTest      10/10/0
ChatHistoryTest                       10/10/0
ChatPanelDrawHelperTest                4/ 4/0
ChatPanelJsTest                       18/18/0
ConfigAgentTest                       10/10/0
EnvSecretTest                          8/ 8/0
FindRelatedSessionsTest                5/ 5/0
FindSessionsByBodyTest                 7/ 7/0
GeminiProviderTest                    11/11/0
GetMessageBodyTest                    12/12/0
GetMessageDetailTest                   6/ 6/0
InspectionSuiteVerificationTest       13/13/0
InspectionToolTest                    15/15/0
JsonTest                               9/ 9/0
MessageAdapterTest                    11/11/0
MultiNamespaceInstallTest              6/ 6/0
OpenAICompatProviderTest              11/11/0
OpenAIProviderTest                     8/ 8/0
PurgeTaskTest                          3/ 3/0
ReadOnlyRoleTest                       6/ 6/0
RetryWithBackoffTest                   9/ 9/0
SampleProductionTest                   3/ 3/0
SeedVocabularyTest                     5/ 5/0
SmokeTest                              1/ 1/0
Story41ToolsTest                      12/12/0
ToolBaseTest                           3/ 3/0
ToolCallRoundtripIntegrationTest       4/ 4/0
ToolDefAdapterTest                     3/ 3/0
ToolRegistryTest                       8/ 8/0
VisualTraceTest                        8/ 8/0
                                    ────────
TOTAL                                301/301/0
```

Baseline was 296 (Story 8.1 close); +5 new BoundedWhereInvariantTest methods = 301 actual. Matches AC-7's expected ~300-301 final count exactly.

**Stale-reference scan (Rule 4):** `grep -rn "Tool.Search.Base|BoundedWhereInvariant|GetIndexedLeadColumns|BuildBoundedWhereClause" .` returned only the 4 new shipped files plus the 4 planning artifacts that already correctly reference the new shape. No stale references to update.

**No ambient deferred-work bindings.** `grep "Story 8.2"` in `deferred-work.md` returned no matches — no carry-forward bindings to honor.

### File List

New files (4):
- `src/SessionAgent/Tool/Search/Base.cls` — abstract base extending `SessionAgent.Tool.Base`. Declares 3 parameters (`DefaultTimeWindowHours=24`, `MaxTimeWindowHours=720`, `KeyedLookupSentinel=-1`), 1 abstract method (`GetIndexedLeadColumns`), 1 concrete helper (`BuildBoundedWhereClause`).
- `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` — 5 test methods + 1 helper (`BuildIndexedColumnSet` for the documented Ens.MessageHeader indexed set).
- `src/SessionAgent/Test/Fixture/StubBoundedSearchTool.cls` — positive-control fixture; returns `["TimeCreated", "Status"]`.
- `src/SessionAgent/Test/Fixture/StubUnboundedSearchTool.cls` — negative-control fixture; returns `[]`.

Modified files (1):
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — flipped `8-2-tool-search-base-bounded-where-invariant-test` from `ready-for-dev` → `in-progress` → `review` → `done` (post-review).

Reviewer-touched files (1):
- `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` — LOW patch: added 5 cutoff-timestamp shape assertions (non-empty + 19-char ODBC form + position-checked separators) in `TestStubFixtureBoundedWhereDefaultsTo24h` to guard against regression in `$ZTimeStamp` carry/borrow math.

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review subagent
**Date:** 2026-05-07
**Outcome:** Approved with 1 LOW-severity fix-now patch applied; 0 HIGH/MEDIUM findings; 0 deferrals.

### Review Findings

- [x] [Review][Patch] **LOW: Cutoff-timestamp value/shape not asserted in `TestStubFixtureBoundedWhereDefaultsTo24h`** [`src/SessionAgent/Test/BoundedWhereInvariantTest.cls:106`] — applied fix-now per Rule 8 default. The original test asserted `tParams.%Size() = 1` but did not verify the bind value's shape, so a future regression in the `$ZTimeStamp` carry/borrow math (or an accidental switch to a non-ODBC format) could silently pass while emitting a malformed bind value. Added 5 assertions on the cutoff timestamp: non-empty, length=19 (ODBC `YYYY-MM-DD HH:MM:SS` form), dash at position 5, space separator at position 11, colon at position 14. Recompiled and reran: 5/5 still pass; 301/301/0 SQL ground-truth probe re-confirmed.

### Layer-by-layer summary

- **Blind Hunter (no spec/context):** 0 findings of substance after triage. The `>` (strict) vs `>=` (boundary-inclusive) `TimeCreated` predicate question was raised and dismissed — AC-2 verbatim cites `"TimeCreated > ?"` as the canonical fragment shape.
- **Edge Case Hunter (project access):** 1 LOW finding (E-8: cutoff-timestamp shape not asserted) — fixed-now. The `pParams` non-clearing-on-rejection observation was dismissed as benign (caller cannot bind anyway since fragment is empty). The `$ZTimeStamp` carry/borrow math was independently re-verified across 4 representative window sizes (1h, 24h, 720h, edge cases at sub-86400-second `tSecs`) — math is correct.
- **Acceptance Auditor (spec + context):** AC-1 through AC-7 all satisfied; verbatim evidence captured in dev's Completion Notes. Rule 6 step 3 SQL ground-truth probe: 301/301/0 ✓. Rule 12 N/A (no UI surface). Rule 11 N/A (no external API).

### Dev-flagged-issue verifications

- **`$ZTimeStamp` arithmetic fix (dev caught + fixed empirically):** **Verified correct.** The `tSecs - (hours*3600)` subtraction with `While tSecs < 0 { tSecs += 86400; tDays -= 1 }` carry/borrow loop terminates after exactly `ceil(hours/24)` iterations at most, yields the correct cutoff timestamp for default (24h), max (720h), and edge cases. `$ZDateTime(<days>,<seconds>, 3, 1)` correctly emits the 19-char ODBC form.
- **Story 8.0 SQL probe form lex-MAX edge case (dev's Debug Log Reference):** **No fix-now or defer needed — canonical rule already correct.** Reviewer re-read [`object-script-testing.md` §"SQL-probe-as-ground-truth"](../../.claude/rules/object-script-testing.md) lines 181-241: the canonical form ALREADY uses (a) numeric run-id extraction via `$PIECE(ID,'||',1)+0` (lines 191, 211, 217, 233, 239) and (b) the inner subquery JOINs through TestMethod to skip orphaned TestCase rows (lines 212-213). The dev's flagged "%EXACT()-free, joining-via-TestMethod" variant IS what the canonical rule prescribes — the rule was shipped in Story 8.0 commit and the fragile `MAX(ID) GROUP BY %EXACT(Name)` form is now a MEDIUM-severity reviewer-enforcement target (line 264-267). Dev appears to have empirically rediscovered the same edge case the canonical rule was already written to address. No `deferred-work.md` entry, no `.claude/rules/object-script-testing.md` edit.

### Files modified during review

- `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` — added 5 cutoff-timestamp shape assertions in `TestStubFixtureBoundedWhereDefaultsTo24h` + 1 docstring stanza explaining the regression-guard rationale.

### Verification (post-patch)

- **Recompile:** `iris_doc_compile SessionAgent.Test.BoundedWhereInvariantTest.cls flags=cuk-d` → success in 12ms.
- **Per-class re-run:** `iris_execute_tests SessionAgent.Test.BoundedWhereInvariantTest level=class` → 5/5 passed, 0 failed.
- **SQL ground-truth probe** (per Story 8.0 canonical form): `Total=301, Passed=301, Failed=0` — count unchanged, all assertions still satisfied.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-07 | Initial spec drafted by lead from epics.md §"Story 8.2" + architecture AR11/OD8 | Claude Opus 4.7 (lead) |
| 2026-05-07 | Dev complete — 4 new files (`Tool/Search/Base.cls`, `Test/BoundedWhereInvariantTest.cls`, `Test/Fixture/StubBoundedSearchTool.cls`, `Test/Fixture/StubUnboundedSearchTool.cls`); 5/5 invariant tests pass; 301/301/0 SQL ground-truth regression sweep; live smoke confirms 0 production search tools registered; chose `pTimeWindowHours = -1` sentinel for keyed-lookup mode | Claude Opus 4.7 (dev) |
| 2026-05-07 | Code review complete — 1 LOW fix-now patch applied (cutoff-timestamp shape assertion in `TestStubFixtureBoundedWhereDefaultsTo24h`); 0 HIGH/MEDIUM findings; 0 deferrals; Story 8.0 SQL probe form lex-MAX flag dismissed (canonical rule already correct). Post-patch: 5/5 still pass, 301/301/0 re-verified. Status flipped to done. | Claude Opus 4.7 (reviewer) |
