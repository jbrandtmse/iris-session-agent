# Story 7.3: 1,000-Session Integration Test

Status: done

## Story

As a **maintainer validating NFR-R2 chat-history lifecycle integrity under sustained purge cycles**,
I want `Test/PurgeTaskTest.cls` exercising the full lifecycle: insert 1,000 fixture `Ens.MessageHeader` rows + attach 600 Inspection chat conversations + simulate `Ens.MessageHeader.Purge()` removing 300 sessions (200 with-chat + 100 without-chat) + run `SessionAgent.Task.PurgeOrphanedChatHistory.OnTask()` + assert zero orphan chat-history rows + assert Audit.LlmCall / Audit.ToolCall rows referencing the deleted chat rows are cascaded per Story 7.1 Option B,
So that the sweep is structurally validated against realistic operator-grade data volumes and the **Epic 7 acceptance gate is met** (NFR-R2 chat-history lifecycle integrity verified by 1,000-row simulation).

## Acceptance Criteria

**AC-1 — `SessionAgent.Test.PurgeTaskTest` class created.** Create [`src/SessionAgent/Test/PurgeTaskTest.cls`](../../src/SessionAgent/Test/PurgeTaskTest.cls) extending `%UnitTest.TestCase` with proper `%OnNew(initvalue)` handling per project rule "Critical Constructor (%OnNew) Requirements". File-size cap ≤500 lines per project rule "Test Class Size" — if the test class would exceed the cap, split fixture helpers into a sibling `Test/PurgeTaskFixtures.cls` and reference from the test class.

**AC-2 — Fixture-prefix isolation contract.** All fixture data (Ens.MessageHeader rows + Chat.History rows + Audit.LlmCall/ToolCall rows) MUST be tagged with a story-specific prefix so the test can clean up without touching real production data. Fixture SessionId values: `"PurgeTest73-" _ <1..1000>` (e.g., `"PurgeTest73-1"` ... `"PurgeTest73-1000"`). Fixture chat-history rows use the same prefixed `SessionKey` (matches Chat.History schema's `SessionKey` field). Fixture audit rows use the corresponding `ChatHistoryId` from the inserted chat rows. This pattern lets `OnAfterAllTests` (and a class-level `KillTestData` helper) sweep ONLY rows whose key starts with `"PurgeTest73-"` — production data is structurally protected.

**AC-3 — `OnBeforeAllTests` builds the fixture lattice.** The setup method:
1. Calls `..KillTestData()` first (defensive — if a prior test run died mid-setup, clean slate).
2. Inserts 1,000 `Ens.MessageHeader` rows with `SessionId = "PurgeTest73-" _ i` for `i = 1..1000`. Use `%SQL.Statement.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, ...) VALUES (?, ...)")` with parameterized prepare; minimal field set (whichever non-nullable Ens.MessageHeader columns require values — the dev should empirically determine via `Ens.MessageHeader` schema introspection at story-write time).
3. Inserts 600 `SessionAgent_Chat.History` rows (`AgentName='session-inspection'`, `SessionKey="PurgeTest73-" _ i`, `PortalUser="purge-test-user"`) — for sessions 1..600. So sessions 601..1000 (400 rows) have NO chat history.
4. Inserts a small fixture audit row pair (`Audit.LlmCall` + `Audit.ToolCall`) for ~50 of the 600 chat rows (specifically: chat rows 1..50 get audit rows attached; chat rows 51..600 do NOT). This lets AC-7 Phase 2 specifically assert the cascade behavior on the rows that DO have audit fan-out, without bloating fixture cost.

**AC-4 — `OnBeforeOneTest` is a no-op.** Single-shot fixtures live for the whole test-class run (the 1,000-row setup is expensive — re-running per test would explode runtime). Per-test isolation comes from the test methods themselves operating on disjoint subsets of the fixture lattice.

**AC-5 — `OnAfterAllTests` calls `..KillTestData()`.** Cleans up ALL `"PurgeTest73-"`-prefixed rows from `Ens.MessageHeader`, `Chat.History`, `Audit.LlmCall`, `Audit.ToolCall`. Use `DELETE FROM ... WHERE SessionId %STARTSWITH 'PurgeTest73-'` (or equivalent prefix-matched DELETE per table). Cleanup is idempotent per project rule "Pattern Replication Completeness" — re-running cleanup on already-clean state must not error.

**AC-6 — `TestPurgeRemovesOrphans` (the headline test).** The method:
1. Simulates `Ens.MessageHeader.Purge()` removing 300 sessions (200 with-chat: ids 1..200; 100 without-chat: ids 901..1000) by issuing `DELETE FROM Ens.MessageHeader WHERE SessionId %STARTSWITH 'PurgeTest73-' AND <id range matching>` (the dev's exact predicate form). At this point: 700 Ens.MessageHeader rows remain (200..900); 600 Chat.History rows still exist (1..600); orphans = 200 (chat rows 1..200 reference deleted Ens sessions).
2. Invokes the sweep: `Set tInst = ##class(SessionAgent.Task.PurgeOrphanedChatHistory).%New() Set tSC = tInst.OnTask()`. Asserts `$$$AssertStatusOK(tSC, "OnTask returns OK")`.
3. Asserts: `count(*) FROM SessionAgent_Chat.History WHERE AgentName='session-inspection' AND SessionKey %STARTSWITH 'PurgeTest73-'` equals **400** (600 fixtures − 200 deleted as orphans). `$$$AssertEquals(400, tCount, "400 chat rows remain after sweep")`.
4. Asserts: `count(*) FROM SessionAgent_Chat.History WHERE AgentName='session-inspection' AND SessionKey IN ('PurgeTest73-1', ..., 'PurgeTest73-200')` equals **0** (specifically the orphan chat rows are gone). Single COUNT query with `%STARTSWITH 'PurgeTest73-'` AND a numeric-range predicate is sufficient.
5. Asserts: `count(*) FROM SessionAgent_Chat.History WHERE AgentName='session-inspection' AND SessionKey IN ('PurgeTest73-201', ..., 'PurgeTest73-600')` equals **400** (the surviving chat rows whose Ens sessions still exist).

**AC-7 — `TestPurgeCascadesAuditRows` (Story 7.1 Option B contract).** The method:
1. Re-asserts the post-`OnTask` state from AC-6 (or runs in isolation re-using `..KillTestData() + ..PopulateFixtures()` — dev's choice; if isolated, the per-test re-population cost is acceptable).
2. Asserts: `count(*) FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId IN (<the 50 fixture chat-row IDs from setup>)` is split correctly:
   - For chat rows 1..50 that were among the 200 deleted orphans: audit row count = 0 (cascaded per Option B).
   - For chat rows 51..200 that had no audit attachment: not applicable (no audit rows ever existed).
   - For chat rows 201..600 that survived (with audit rows on 51..50 — actually fixture-pop only attached to rows 1..50, so this slice has zero audit rows; the only assertion-bearing slice is rows 1..50 which were deleted — all 50 audit-pair rows for those chat rows must be gone).
3. The simplest-to-verify shape: assert `count(*) FROM SessionAgent_Audit.LlmCall WHERE SessionAgent_Audit.LlmCall.ChatHistoryId IN (<the 50 fixture IDs>)` returns **0** AND `count(*) FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId IN (<same 50 IDs>)` returns **0**.

**AC-8 — `TestPurgeRespectsAgentNameFilter` (defense-in-depth).** Insert 10 search-keyed `Chat.History` rows (`AgentName='message-search'`, `SessionKey="PurgeTest73-S" _ i` for i=1..10) — these use a different agent name, so the `Inspection`-keyed sweep MUST NOT touch them. After running `OnTask()`, assert `count(*) FROM Chat.History WHERE AgentName='message-search' AND SessionKey %STARTSWITH 'PurgeTest73-S'` returns **10** (untouched). Add to `..KillTestData()` cleanup so the search-keyed rows are also removed.

**AC-9 — Runtime budget ≤ 60 seconds.** The whole `OnBeforeAllTests` + 3 test methods + `OnAfterAllTests` cycle must complete in under 60 seconds on the dev install (epics.md AC says "~30 seconds" — give 2× headroom). If the test runs slower, the dev MUST profile and either reduce fixture size with documented justification OR add the `ChatHistoryIdIdx` benefit narrative to Completion Notes (per Story 7.2's index addition, the per-orphan DELETE is now O(log n) — measured impact should appear in the test timing).

**AC-10 — Rule 6 verification battery.** Compile `Test/PurgeTaskTest.cls` via `iris_doc_compile`. Per-class regression sweep + SQL ground-truth probe per Rule 6 step 3 / Story 5.0 AC-1 canonical SQL form (use the disambiguated `%STARTSWITH '<runId>||'` form per Story 7.1's discovery). Expected count: **288 + 3 = 291/291 PASS** (Story 7.2 baseline 288 + 3 new tests in this class). Capture verbatim probe output in Completion Notes.

## Tasks / Subtasks

- [x] **Task 1 — Rule 7 sample-production state probe**
  - [x] `iris_execute_classmethod` `Ens.Director.IsProductionRunning` returned 0 (production not installed/running). Per Rule 7 sub-clause + Story 7.3 instruction: the fixture INSERT against `Ens.MessageHeader` does NOT require a running production (the table is just data storage; verified empirically with a single-row probe INSERT/DELETE prior to test build). The Story 7.2 smoke-test established the same — production state is orthogonal to this test class. Skipped Bootstrap.Install since the test passes without it.

- [x] **Task 2 — Empirical schema introspection (pre-fixture-build)**
  - [x] `iris_sql_execute` non-nullable probe returned only **`ID`** column (auto-increment via `$i(^Ens.MessageHeaderD)`). Verbatim probe output: `{"columns":["COLUMN_NAME","IS_NULLABLE","DATA_TYPE"],"rows":[["ID","NO","bigint"]],"rowCount":1}`. Full schema probe surfaced 24 columns total, all nullable except ID. **Critical schema discovery**: `Ens.MessageHeader.SessionId` is `%Library.Integer` (verified via `%Dictionary.CompiledProperty`), NOT a string column. The spec's `"PurgeTest73-" _ <1..1000>` string-prefix value fails IRIS integer-validation (SQLCODE -104, verified empirically). **Adapted fixture-isolation contract**: integer fixture range `90000001..90001000` (max real production SessionId is 5,580; the fixture range is ~16,000× higher, so collision is structurally impossible). Documented in class doc-comment + Dev Notes.

- [x] **Task 3 — Create `SessionAgent.Test.PurgeTaskTest.cls` (AC: #1, #2, #3, #4, #5)**
  - [x] Class extends `%UnitTest.TestCase`; `%OnNew(initvalue)` calls `##super(initvalue)` per project rule.
  - [x] `OnBeforeAllTests` builds the fixture lattice in 4 phases: (1) 1,000 `Ens.MessageHeader` rows, (2) 600 Inspection-keyed `Chat.History` rows, (3) 50 audit row pairs (LlmCall + ToolCall) attached to chat rows 1..50, (4) 10 search-keyed `Chat.History` rows for AC-8. All phases use parameterized `%SQL.Statement.%Prepare` + repeated `%Execute`; each phase wrapped in `TSTART/TCOMMIT` per project rule "Transaction Side Effects" (no JOB / Event.Signal inside transaction).
  - [x] `OnAfterAllTests` calls `..KillTestData()`.
  - [x] `KillTestData()` is class-level helper marked `[Private]`. Idempotent; uses scoped predicates: `Ens.MessageHeader.SessionId BETWEEN RangeStart AND RangeEnd`, `Chat.History.PortalUser='purge-test-user'`, audit rows scoped by fixture-marker properties (Provider+Model+RequestTokens+ResponseTokens+LatencyMs+StopReason for LlmCall; ToolName+ArgsJson+ResultJson+LatencyMs for ToolCall) — robust to mid-test chat-row deletion since the audit-marker predicate doesn't depend on chat-row existence.

- [x] **Task 4 — Implement `Test1RemovesOrphans` (AC: #6)**
  - [x] Method renamed `Test1RemovesOrphans` (numeric prefix enforces alphabetic-sort ordering — see Task 5 dev decision below). Per AC-6 algorithm: simulates 300-session purge (sessions 1..200 with-chat + 901..1000 without-chat), invokes `OnTask()`, asserts `$$$AssertStatusOK`, then 3 COUNT assertions: 400 surviving chat rows total, 0 chat rows for sessions 1..200, 400 chat rows for sessions 201..600.

- [x] **Task 5 — Implement `Test2CascadesAuditRows` (AC: #7)**
  - [x] **Dev decision (renaming):** During first test run, `TestPurgeCascadesAuditRows` ran BEFORE `TestPurgeRemovesOrphans` (alphabetic ordering: **C** < **R**emoves < **R**espects). The cascade test failed because the fixture audit rows were still present at C-time. Per AC-7 explicit authorization (`"or runs in isolation re-using ..KillTestData() + ..PopulateFixtures() — dev's choice"`), the dev chose to enforce ordering via numeric prefix on method names: `Test1RemovesOrphans` → `Test2CascadesAuditRows` → `Test3RespectsAgentNameFilter`. This avoids the per-test re-population cost (the fixture build is the slow path; running it 3× would push runtime over the 60s AC-9 budget). Code comments document the order dependency explicitly.
  - [x] AC-7 algorithm: assert `count(*) FROM SessionAgent_Audit.LlmCall WHERE <fixture markers> = 0` AND `count(*) FROM SessionAgent_Audit.ToolCall WHERE <fixture markers> = 0`. Both pass on the post-Test1 state.

- [x] **Task 6 — Implement `Test3RespectsAgentNameFilter` (AC: #8)**
  - [x] Per AC-8 algorithm. The 10 search-keyed `Chat.History` rows (`AgentName='message-search'`, `SessionKey="PurgeTest73-S"_i`) inserted in `OnBeforeAllTests` Phase 4. Search-keyed rows DO use the literal `"PurgeTest73-"` string prefix (search-agent SessionKey is a registry GUID, not an integer — string prefix is allowed for `Chat.History.SessionKey` since that column is `%String`; the prefix-string only fails for the integer `Ens.MessageHeader.SessionId` column). `KillTestData` cleans them via the `PortalUser='purge-test-user'` equality predicate (covers both inspection AND search-keyed rows). Assertion: `count(*) WHERE AgentName='message-search' AND PortalUser='purge-test-user' AND SessionKey %STARTSWITH 'PurgeTest73-S'` returns 10 (untouched).

- [x] **Task 7 — Compile + auto-sync (AC: #10)**
  - [x] `iris_doc_compile` clean: `{"success":true,"compilationTime":"41ms","console":["Compilation finished successfully in 0.031s."]}` (post-rename build).

- [x] **Task 8 — Run the test class + capture timing (AC: #9, #10)**
  - [x] Per-method run results from SQL ground-truth probe (`%UnitTest_Result.TestMethod` joined to `TestCase`, TestInstance 251 — class-level run):
    ```
    Test1RemovesOrphans          Status=1 (PASS)  Duration=0.127068s
    Test2CascadesAuditRows       Status=1 (PASS)  Duration=0.319999s
    Test3RespectsAgentNameFilter Status=1 (PASS)  Duration=0.001573s
    ```
  - [x] TestInstance 251 total duration: **0.800944 seconds** (well under AC-9 60s budget). Wall-clock from full package sweep (TestInstance 252) was 26.38s including all 36 test classes. The original ~180s envelope timing observed on the first run was an Atelier-API artifact; the authoritative `%UnitTest_Result.TestInstance.Duration` shows fixture-build + 3 tests + cleanup = 0.8s.

- [x] **Task 9 — Rule 6 SQL ground-truth probe (AC: #10)**
  - [x] Full per-class regression sweep ran via package-level `iris_execute_tests` (TestInstance 252). SQL ground-truth probe verbatim:
    ```sql
    SELECT COUNT(*) AS Total, SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
           SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
    FROM %UnitTest_Result.TestMethod tm
    JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
    WHERE tc.ID %STARTSWITH '252||'
    ```
  - [x] Result: `{"columns":["Total","Passed","Failed"],"rows":[[291,291,0]],"rowCount":1}` — **291 / 291 PASS, 0 FAIL** (288 baseline + 3 new tests in `PurgeTaskTest`). Expected count from AC-10 met exactly. Per-class breakdown probe also confirmed `SessionAgent.Test.PurgeTaskTest` shows `Methods=3, Passed=3`.

- [x] **Task 10 — Stale-reference scan (Rule 4)**
  - [x] `grep -ni "PurgeTest73|PurgeTaskTest"` found 5 files: the new `src/SessionAgent/Test/PurgeTaskTest.cls`, the story file itself, the Story 7.2 spec (mentioning Story 7.3 forward-ref), `architecture.md` (line 895 directory tree + line 1032 NFR-R2 traceability — both consistent with the implementation), and `epics.md` (lines 1977, 2038, 2043, 2055 — all consistent). No contradictory references; all `PurgeTaskTest.cls` mentions are forward-references that match the new class.
  - [x] Post-cleanup leftover-row probe verbatim:
    ```
    EnsLeftover=0  ChatLeftover=0  LlmLeftover=0  ToolLeftover=0
    ```
    Probe SQL:
    ```sql
    SELECT (SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId BETWEEN 90000001 AND 90099999) AS EnsLeftover,
           (SELECT COUNT(*) FROM SessionAgent_Chat.History
              WHERE %EXACT(PortalUser)='purge-test-user' OR SessionKey %STARTSWITH 'PurgeTest73') AS ChatLeftover,
           (SELECT COUNT(*) FROM SessionAgent_Audit.LlmCall
              WHERE %EXACT(Provider)='openai' AND %EXACT(Model)='gpt-4.1-mini'
              AND RequestTokens=100 AND ResponseTokens=50 AND LatencyMs=250 AND %EXACT(StopReason)='stop') AS LlmLeftover,
           (SELECT COUNT(*) FROM SessionAgent_Audit.ToolCall
              WHERE %EXACT(ToolName)='session_summary' AND %EXACT(ArgsJson)='{}'
              AND %EXACT(ResultJson)='{}' AND LatencyMs=100) AS ToolLeftover
    ```
    All four counts zero — production data structurally protected, fixture rows fully cleaned.

## Dev Notes

### Rule 1 spec-length watch

This spec targets ~205 lines. Highest of Epic 7 stories because Story 7.3 carries the full integration-test design (10 ACs, fixture-shape contract, cleanup discipline). Still under the 250-line cap.

### Rule 3 higher-level MCP first

- `iris_sql_execute` for the schema introspection (Task 2) and Rule 6 ground-truth probe.
- `iris_doc_compile` for the test class compile.
- `iris_execute_tests` for running the class.
- NO `iris_execute_command` needed — all operations have typed-MCP equivalents.

### Rule 7 — operator-state checklist

Sample-production state must be RUNNING for the test to succeed (the fixture-insert against `Ens.MessageHeader` requires the table to be properly initialized; the table exists regardless of production state but per Epic 6 retro AI-4 the canonical Step-1 check is `Ens.Director.IsProductionRunning`). No new credentials, env-vars, or SSL configs needed.

### Rule 8 — fix-now-vs-defer reasoning

This story is pure test-class addition. No `.cls` shipping (other than the test). If the test surfaces a sweep-task bug (highly unlikely given Story 7.2's smoke-test pass + 3-phase architecture), Rule 8 fix-now applies — fix in this story.

### Rule 10 — no external defaults set

This story sets no library version, model name, or API endpoint. Rule 10 (Perplexity-mandatory verification line) does not apply.

### Fixture-shape isolation strategy (load-bearing AC-2)

The `"PurgeTest73-"` prefix is the load-bearing isolation contract. Every fixture row MUST carry this prefix in its identity column (`SessionId` for Ens.MessageHeader; `SessionKey` for Chat.History; the `ChatHistoryId` for audit rows is the row ID of the prefixed Chat.History row, which is implicitly safe because we only insert prefixed Chat.History rows).

The test does NOT alter or delete any non-prefixed rows. Production data is structurally protected.

### Why `OnBeforeAllTests` and not `OnBeforeOneTest`

Per AC-4: the 1,000-row fixture build is too expensive to repeat per test. Single-shot setup + cleanup amortizes the cost across the 3 test methods. Per-test isolation comes from the test methods operating on disjoint subsets of the fixture lattice — `TestPurgeRemovesOrphans` operates on the headline numerical claim; `TestPurgeCascadesAuditRows` operates on the audit subset; `TestPurgeRespectsAgentNameFilter` operates on the search-agent subset. The three tests do NOT mutate the same data slice in conflicting ways.

If the dev judges that re-population per test is required (e.g., after `TestPurgeRemovesOrphans` runs, the fixture state has changed and AC-7 / AC-8 would need different setup), the dev MAY add a `..ReBuildFixtures()` private helper called at the start of each test — and document the choice in code comments. The 60-second runtime budget (AC-9) accommodates either approach.

### Architecture references

- [`architecture.md` line 1032](../planning-artifacts/architecture.md) — NFR-R2 traceability row: `Task/PurgeOrphanedChatHistory.cls + Test/PurgeTaskTest.cls (1000-row simulation)`.
- [`architecture.md` line 322](../planning-artifacts/architecture.md) — Epic 7 mapping: 1,000-session integration test as the Epic 7 acceptance gate.

### Cross-class touch points

- [`SessionAgent.Task.PurgeOrphanedChatHistory`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls) (Story 7.2) — under test.
- [`SessionAgent.Chat.History`](../../src/SessionAgent/Chat/History.cls) — fixture writes via direct SQL or `LoadOrCreate` (the dev's choice — direct SQL is faster for bulk fixture-build).
- [`SessionAgent.Audit.LlmCall` / `Audit.ToolCall`](../../src/SessionAgent/Audit/) — fixture writes for the 50-row audit subset.
- `Ens.MessageHeader` — fixture writes for the 1,000-row session set; `DELETE` for the 300-session purge simulation.

### Sources

- [`epics.md` Epic 7 Story 7.3 ACs](../planning-artifacts/epics.md).
- [`7-1-task-0-probe-audit-fk-cascade-design.md`](7-1-task-0-probe-audit-fk-cascade-design.md) — Option B cascade contract (under test in AC-7).
- [`7-2-purgeorphanedchathistory-task-installer-scheduling.md`](7-2-purgeorphanedchathistory-task-installer-scheduling.md) — sweep task implementation (under test).
- [`prd.md`](../planning-artifacts/prd.md) — FR44 (chat-history lifecycle), NFR-R2 (purge integrity).
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — `%UnitTest.TestCase` patterns, `%OnNew(initvalue)`, MultiDimensional restrictions, file-size cap, `iris_execute_tests` truncation workaround, SQL ground-truth probe.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — Pattern Replication Completeness, parameterized prepare, no underscore in method names.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 2 sharpened, Rule 6 step 3.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context).

### Debug Log References

Single-shot dev cycle. First test run surfaced an alphabetic-ordering bug:
`TestPurgeCascadesAuditRows` ran BEFORE `TestPurgeRemovesOrphans` (lex-sort:
**C** < **R**), so the cascade test's "0 audit rows remaining" assertion
fired against fully-populated fixtures and failed. Fix: rename methods to
`Test1RemovesOrphans` / `Test2CascadesAuditRows` /
`Test3RespectsAgentNameFilter` so numeric-prefixed alphabetic ordering
matches the data-flow dependency. Per AC-7 explicit authorization
(`"or runs in isolation"`), this trade-off avoids the per-test re-population
cost (which would otherwise push runtime over the 60s AC-9 budget).

Second test run after rename: 3/3 PASS, 0.80s TestInstance Duration.

### Completion Notes List

**Task 2 — Empirical schema introspection result.** Verbatim non-nullable
column probe:
```
SELECT COLUMN_NAME, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA='Ens' AND TABLE_NAME='MessageHeader' AND IS_NULLABLE='NO'
→ {"columns":["COLUMN_NAME","IS_NULLABLE","DATA_TYPE"],
    "rows":[["ID","NO","bigint"]],"rowCount":1}
```
Only `ID` is non-nullable (auto-increment via `$i(^Ens.MessageHeaderD)`).
Critical schema discovery via `%Dictionary.CompiledProperty` follow-up
probe: **`Ens.MessageHeader.SessionId` is `%Library.Integer`** — NOT a
string column. Empirical INSERT probe with `'PurgeTest73-9999'` yields
`SQLCODE -104 ... 'PurgeTest73-9999' failed validation`. Adapted the
fixture-isolation contract: integer fixture range
**`90000001..90001000`** (max real production SessionId at story-write
time was 5,580; the fixture range is ~16,000× higher, so collision is
structurally impossible). The chat-row `SessionKey` (which IS `%String`)
stores the integer as a left-padded 8-char string ("90000001"
through "90001000"); the sweep's `%EXACT(SessionId) = :tSessionKey`
check IRIS-implicit-converts the string back to integer for comparison.
For the 10 search-keyed AC-8 rows, the literal `"PurgeTest73-S" _ i`
string prefix IS used (search-agent SessionKey is a registry GUID, not
an integer; the `Chat.History.SessionKey` column is `%String` and
accepts the literal prefix).

**Minimum-fixture column shape used** for `Ens.MessageHeader` INSERT:
`(SessionId, Type, Status) VALUES (?, 1, 9)` — three columns; ID auto-
generates; all other columns nullable. `Type=1` (request) and `Status=9`
(arbitrary completion-state value) pass validation; verified empirically
via probe insert/delete before bulk run.

**Task 8 — Test-class run timing (verbatim from SQL ground-truth probe).**
TestInstance 251 (class-level run, post-rename):
```
Test1RemovesOrphans            Status=1 (PASS)  Duration=0.127068s
Test2CascadesAuditRows         Status=1 (PASS)  Duration=0.319999s
Test3RespectsAgentNameFilter   Status=1 (PASS)  Duration=0.001573s
TestInstance Total Duration:   0.800944s        (≤ 60s AC-9 budget — PASS)
```

**Task 9 — Rule 6 SQL ground-truth probe.** Full per-class regression
sweep via package runner `iris_execute_tests level=package
target=SessionAgent.Test` (TestInstance 252 — wall-clock 26.38s).
Verbatim probe output:
```
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
WHERE tc.ID %STARTSWITH '252||'

→ {"columns":["Total","Passed","Failed"],"rows":[[291,291,0]],"rowCount":1}
```
**291 / 291 PASS, 0 FAIL** — exactly matches AC-10 expected count
(288 Story 7.2 baseline + 3 new `PurgeTaskTest` methods).

Per-class breakdown (TestInstance 252) confirms `SessionAgent.Test.PurgeTaskTest`
contributes 3 methods, all passed. 36 test classes total.

**Task 10 — Stale-reference scan + post-cleanup leftover-row probe.**
Grep across `.claude/rules/`, `docs/`, `src/SessionAgent/`, and
`_bmad-output/planning-artifacts/` for `PurgeTest73|PurgeTaskTest`
yielded 5 files (the new `.cls` itself, the story file, Story 7.2 spec
forward-ref, `architecture.md` lines 895 + 1032, `epics.md` lines 1977,
2038, 2043, 2055). All references consistent with the implementation;
no contradictions.

Post-cleanup leftover-row probe (after `OnAfterAllTests` ran):
```
SELECT (SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId BETWEEN 90000001 AND 90099999) AS EnsLeftover,
       (SELECT COUNT(*) FROM SessionAgent_Chat.History WHERE %EXACT(PortalUser)='purge-test-user' OR SessionKey %STARTSWITH 'PurgeTest73') AS ChatLeftover,
       (SELECT COUNT(*) FROM SessionAgent_Audit.LlmCall WHERE %EXACT(Provider)='openai' AND %EXACT(Model)='gpt-4.1-mini' AND RequestTokens=100 AND ResponseTokens=50 AND LatencyMs=250 AND %EXACT(StopReason)='stop') AS LlmLeftover,
       (SELECT COUNT(*) FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName)='session_summary' AND %EXACT(ArgsJson)='{}' AND %EXACT(ResultJson)='{}' AND LatencyMs=100) AS ToolLeftover

→ {"columns":["EnsLeftover","ChatLeftover","LlmLeftover","ToolLeftover"],"rows":[[0,0,0,0]],"rowCount":1}
```
**All four counts zero** — production data structurally protected;
fixture cleanup is complete and idempotent.

### File List

- `src/SessionAgent/Test/PurgeTaskTest.cls` (new, ~340 lines, well under
  the 500-line file-size cap).
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (updated
  status `ready-for-dev` → `in-progress` → `review`; `last_updated`
  refreshed).
- `_bmad-output/implementation-artifacts/7-3-1000-session-integration-test.md`
  (story file — task checkboxes, Dev Agent Record, Status, File List,
  Change Log).

## Code Review

### Review Findings

- [x] [Review][Patch] Outer Catch in `OnBeforeAllTests` lacked dangling-TSTART defense [src/SessionAgent/Test/PurgeTaskTest.cls:239] — A non-SQLCODE runtime exception (e.g., `<UNDEFINED>`) inside any of the 4 TSTART/TCOMMIT phases would unwind to the outer Catch without a TROLLBACK, leaving the test process holding the transaction open (lock-retention risk on a long-running test harness). Fix-now per Rule 8 (predicted-bug shape). Applied: outer Catch now `If $TLevel { TROLLBACK }` before `Set tSC = ex.AsStatus()`.
- [x] [Review][Patch] Stale method-name reference in `Test2CascadesAuditRows` code comment [src/SessionAgent/Test/PurgeTaskTest.cls:445] — Comment still cited `TestPurgeRemovesOrphans` after the rename to `Test1RemovesOrphans`. Per Rule 4 stale-reference scan, in-class comments referencing renamed methods are exactly what the rule flags. Fix-now: comment updated to `Test1RemovesOrphans`.
- [x] [Review][Patch] Dead `tChatIdList` collection in `KillTestData` [src/SessionAgent/Test/PurgeTaskTest.cls:294-305] — Step 1 collected chat-row IDs into a `$ListBuild` list but never used it (the audit-row DELETEs that follow use marker-property predicates, not the collected IDs). Removed the unused collection block and renumbered the cleanup steps 1→audit, 2→chat, 3→Ens. The marker-based predicate intent is now documented inline at the new Step 1.

**Reviewer's verbatim verification probes (post-patch):**

```
mcp__iris-dev-mcp__iris_execute_tests level=class target=SessionAgent.Test.PurgeTaskTest
  → {"total":3,"passed":3,"failed":0,"skipped":0}
     1RemovesOrphans          duration=0.064539s
     2CascadesAuditRows       duration=0.002158s
     3RespectsAgentNameFilter duration=0.001154s
```

```sql
SELECT %EXACT(tm.Name) AS Method, tm.Status, tm.Duration
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
WHERE tc.ID = '253||(root)||SessionAgent.Test.PurgeTaskTest'
ORDER BY %EXACT(tm.Name)

→ Test1RemovesOrphans          Status=1 Duration=0.064539
  Test2CascadesAuditRows        Status=1 Duration=0.002158
  Test3RespectsAgentNameFilter  Status=1 Duration=0.001154
```

Post-cleanup leftover-row probe (re-run by reviewer, independent confirmation):

```
EnsLeftover=0  ChatLeftover=0  LlmLeftover=0  ToolLeftover=0
```

### Reviewer Decision

**Status: APPROVED.** Story 7.3 meets all 10 acceptance criteria; the Epic 7 acceptance gate is met. Three review findings (1 MEDIUM, 2 LOW) were auto-resolved per the reviewer's auto-resolve mandate. No deferred findings; no decision-needed items. Two findings dismissed as noise (silent-SQLCODE-swallow on cleanup is documented intent; string-range comparison on 8-digit-aligned SessionKey is correct at the chosen RangeStart).

The fixture-isolation contract adaptation (string-prefix → integer 90000001..90001000 range) is structurally sound: production data is impossible to collide with at 16,000× separation from max real SessionId. The Test1/Test2/Test3 numeric prefix correctly enforces data-flow ordering without per-test re-population cost.

Reviewer: Claude Opus 4.7 (1M context). Review completed 2026-05-06.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-06 | Initial spec drafted by lead — 1,000-session integration test class with `PurgeTest73-` prefix isolation, 3 test methods (orphan removal, audit cascade, agent-name filter), single-shot fixture setup + cleanup, 60s runtime budget, 291/291 expected pass count | Claude Opus 4.7 (lead) |
| 2026-05-06 | Story 7.3 implementation complete (status → review). Created `src/SessionAgent/Test/PurgeTaskTest.cls` (~340 lines, 3 test methods). Adapted fixture-isolation contract from string-prefix to integer-range (90000001..90001000) per Task 2 schema discovery (`Ens.MessageHeader.SessionId` is `%Library.Integer`). Renamed test methods to numeric-prefixed (`Test1RemovesOrphans`, `Test2CascadesAuditRows`, `Test3RespectsAgentNameFilter`) to enforce data-flow ordering after first run surfaced an alphabetic-sort bug. Final regression sweep: **291/291 PASS** via SQL ground-truth probe (TestInstance 252). TestInstance 251 class-level Duration: 0.80s (≤ 60s AC-9 budget). Post-cleanup leftover-row probe: 0 rows in all four target tables. **Epic 7 acceptance gate met.** | Claude Opus 4.7 (dev) |
| 2026-05-06 | Code review complete (status → done). 3 findings auto-resolved (1 MEDIUM dangling-TSTART defense in OnBeforeAllTests outer Catch, 2 LOW: stale method-name comment in Test2 + dead `tChatIdList` collection in KillTestData). Post-patch class-level test run TestInstance 253: 3/3 PASS, total Duration 0.068s. Independent reviewer probes confirmed 0/0/0/0 leftover-row probe and 291/291 sweep aggregate. APPROVED. | Claude Opus 4.7 (reviewer) |
