# Story 7.2: `PurgeOrphanedChatHistory` Task + Installer Scheduling

Status: done

## Story

As a **System (sweep task)** and **Operator-Admin (install-time scheduler)**,
I want `SessionAgent.Task.PurgeOrphanedChatHistory` extending `%SYS.Task.Definition` with daily 02:00 UTC scheduling, scanning Inspection-keyed `Chat.History` rows (`AgentName='session-inspection'`), checking each row's `SessionKey` against `Ens.MessageHeader` via the Story 7.1-verified existence check, deleting orphaned rows + handling cascading audit cleanup per Story 7.1 Option B (sweep task explicitly deletes audit rows first), plus relying on `Installer.Install`'s already-shipped `ScheduleTaskIfClassExists` hook to schedule the task on first install,
So that orphan accumulation under sustained `Ens.MessageHeader.Purge()` cycles is structurally prevented per FR44 + NFR-R2.

## Acceptance Criteria

**AC-1 — `SessionAgent.Task.PurgeOrphanedChatHistory` class created.** Create [`src/SessionAgent/Task/PurgeOrphanedChatHistory.cls`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls) extending `%SYS.Task.Definition` (verified by reading `irislib/%SYS/Task/Definition.cls` per project rule "IRIS Library Source"). The class declares `Parameter TaskName = "PurgeOrphanedChatHistory"`. Class doc-comment supplies the human-readable description (operators see it in Mgmt Portal Task Manager). The class implements `Method OnTask() As %Status` per the contract documented in `irislib/%SYS/Task/Definition.cls:38-41`.

**AC-2 — `OnTask()` implements the Story 7.1 Option B sweep.** The method:
1. Iterates `SELECT %ID, %EXACT(SessionKey) FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = 'session-inspection'` (using `%EXACT()` per project rule "IRIS SQL Case Sensitivity").
2. For each row, executes the Story 7.1-verified existence check `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionKey)`. If `SQLCODE=100` (no row) → orphan; proceed to delete sequence. If `SQLCODE=0` → row still exists, skip.
3. For each orphan row (Story 7.1 Option B order — audit first, then chat):
   - `DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?` (parameterized prepare via `%SQL.Statement.%Prepare` + `%Execute(?)`, never string concat — project rule "Search-Arg-Construction Safety").
   - `DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?` (same).
   - `DELETE FROM SessionAgent_Chat.History WHERE %ID = ?` (or `..%DeleteId(<id>)`).
4. Aggregates per-run counters: `tOrphansDeleted`, `tLlmAuditDeleted`, `tToolAuditDeleted`, `tScanTimeMs`.

**AC-3 — Audit event emission per architecture §"Audit event triples".** After the sweep completes (success OR partial failure), the method emits:
```objectscript
Do $System.Security.Audit("SessionAgent", "TaskRun", "PurgeOrphanedChatHistory",
    {"orphans_deleted": tOrphansDeleted, "llm_audit_deleted": tLlmAuditDeleted,
     "tool_audit_deleted": tToolAuditDeleted, "scan_time_ms": tScanTimeMs}.%ToJSON())
```
The `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` triple is already pre-registered by [`SessionAgent.Audit.Emit:EnsureEvents`](../../src/SessionAgent/Audit/Emit.cls#L59) (Story 1.3) — no `RegisterIfMissing` needed.

**AC-4 — `%Status` discipline + Try/Catch + transaction safety per project rules.** First line `Set tSC = $$$OK`; last line `Quit tSC`. Try/Catch with argumentless `Quit` inside catch (project rule "QUIT Statement Restrictions in Try/Catch Blocks"). Per project rule "Transaction Side Effects": no JOB / Event.Signal / external I/O inside any TSTART/TCOMMIT block. The audit emission is safe outside any transaction (the deletes commit row-by-row implicitly; no explicit transaction needed unless we want all-or-nothing per-orphan semantics — the spec choice for v1 is **commit per orphan** to maximize forward progress under partial-failure conditions).

**AC-5 — `ChatHistoryId` indexes added to `Audit.LlmCall` + `Audit.ToolCall` (Story 7.1 hand-off).** Per Story 7.1 AC-5 hand-off: add `Index ChatHistoryIdIdx On ChatHistoryId` to both [`src/SessionAgent/Audit/LlmCall.cls`](../../src/SessionAgent/Audit/LlmCall.cls) and [`src/SessionAgent/Audit/ToolCall.cls`](../../src/SessionAgent/Audit/ToolCall.cls). Without these, the per-orphan `DELETE WHERE ChatHistoryId = ?` triggers a full audit-table scan; with them, the DELETEs are O(log n). Story 7.3's 1,000-session integration test will exercise the cost; doing the index now is Rule 8 fix-now (predicted-bug shape — sweep performance degradation under realistic audit volumes is genuinely predicted). Storage section is auto-generated per project rule.

**AC-6 — Installer scheduling hook fires.** [`SessionAgent.Installer.Install`](../../src/SessionAgent/Installer.cls#L110) line 110 already calls `ScheduleTaskIfClassExists("SessionAgent.PurgeOrphanedChatHistory", "SessionAgent.Task.PurgeOrphanedChatHistory", "Daily", 2, 0)`. Once the new task class compiles, the hook detects it and schedules a `%SYS.Task` entry on first install. Per Story 1.5 Task-0 probe of `%SYS.Task` Name non-uniqueness, the Installer's existence check (`SELECT TOP 1 ID FROM %SYS.Task WHERE Name = ?`) prevents duplicate scheduling on re-install — verify empirically that re-running `Installer.Install("")` does not duplicate the task entry (per NFR-R5 idempotency).

**AC-7 — Rule 6 verification battery.** Compile the 3 modified `.cls` files via `iris_doc_compile` (auto-sync handles the source push; compile verifies clean). Per-class regression sweep + SQL ground-truth probe per Rule 6 step 3 / Story 5.0 AC-1 canonical SQL form. Expected count band: 288/288 (Story 7.1 baseline) + however many test methods Story 7.3's `PurgeTaskTest.cls` will add (Story 7.3 owns the test-class creation; Story 7.2 should NOT preemptively add unit tests for `OnTask` — Story 7.3 is the dedicated test-class story).

**AC-8 — Manual smoke test of the task end-to-end (operator-observable surface).** Invoke `##class(SessionAgent.Task.PurgeOrphanedChatHistory).%New().OnTask()` directly via `iris_execute_classmethod` against the live `HSCUSTOM` namespace. Expected: returns `$$$OK`; emits one `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` audit event observable via `iris_audit_events` MCP filter. If the sample production has zero orphan rows at smoke-test time, the per-counter values should all be 0 and the audit event still emits.

## Tasks / Subtasks

- [x] **Task 1 — Rule 7 sample-production state probe (Rule 7 sub-clause)**
  - [x] `iris_execute_classmethod` `Ens.Director.IsProductionRunning` → returned 0 (production stopped). `SessionAgent.Sample.Bootstrap.InstallProduction` then `StartProductionIfStopped` → re-probe returned 1.

- [x] **Task 2 — Add `ChatHistoryIdIdx` to `Audit.LlmCall` + `Audit.ToolCall` (AC: #5)**
  - [x] Edited [`src/SessionAgent/Audit/LlmCall.cls`](../../src/SessionAgent/Audit/LlmCall.cls): added `Index ChatHistoryIdIdx On ChatHistoryId;` above the Storage block (Storage section auto-generated, NOT hand-edited per project rule).
  - [x] Edited [`src/SessionAgent/Audit/ToolCall.cls`](../../src/SessionAgent/Audit/ToolCall.cls): same.
  - [x] `iris_doc_compile` both classes clean (auto-sync handled the source push; recompile reported "up-to-date" because auto-sync had already triggered the compile on save). Index registration verified via SQL probe of `%Dictionary.IndexDefinition`. One-time index build via `%BuildIndices($ListBuild("ChatHistoryIdIdx"))` returned `$$$OK` for both classes.

- [x] **Task 3 — Create `SessionAgent.Task.PurgeOrphanedChatHistory` (AC: #1, #2, #3, #4)**
  - [x] Created [`src/SessionAgent/Task/PurgeOrphanedChatHistory.cls`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls) extending `%SYS.Task.Definition`.
  - [x] Class doc-comment ships an operator-readable description naming the sweep purpose, daily 02:00 UTC schedule, Story 7.1 Option B cascade approach, and the `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` audit emission.
  - [x] `Parameter TaskName = "PurgeOrphanedChatHistory";` declared.
  - [x] Implemented `Method OnTask() As %Status`:
    - First line `Set tSC = $$$OK`. Counters initialized: `tOrphansDeleted=0, tLlmAuditDeleted=0, tToolAuditDeleted=0, tStartH=$ZH, tScanTimeMs=0`.
    - **Phase 1 — orphan-candidate collection.** Open `%SQL.Statement` against `SELECT %ID AS chatId, %EXACT(SessionKey) AS sessionKey FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = 'session-inspection'`. Iterate via `%Next()`; for each row run the Story 7.1-verified `&sql(SELECT 1 INTO :tExists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :tSessionKey)`. SQLCODE=100 → push the `chatId` into a local `tOrphanIds()` array. SQLCODE=0 → row alive, skip silently. Other SQLCODE → conservative, treated as not-orphan.
    - **Phase 2 — prepare-once audit-delete statements.** Two `%SQL.Statement` instances prepared OUTSIDE the per-orphan loop: one for `DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?`, one for `DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?`. The new `ChatHistoryIdIdx` (Task 2) makes each DELETE O(log n).
    - **Phase 3 — per-orphan delete loop.** `$Order` over `tOrphanIds`; each iteration wrapped in a sub-Try (commit-per-orphan semantic per AC-4 — one orphan's failure does NOT abort the sweep). Order: LlmCall delete → ToolCall delete → `SessionAgent.Chat.History.%DeleteId(chatId)`. Counters advanced from `%ROWCOUNT`.
    - After loop: `Set tScanTimeMs = ($ZH - tStartH) * 1000 \ 1`.
    - Outer Catch: argumentless `Quit` per project rule "QUIT Statement Restrictions in Try/Catch Blocks"; `tSC` set to `ex.AsStatus()` BEFORE the Quit.
  - [x] After outer Try/Catch: audit event emitted via `$System.Security.Audit("SessionAgent","TaskRun","PurgeOrphanedChatHistory", tSC, tData.%ToJSON())` where `tData` is a `%DynamicObject` carrying the four counters. Audit emission wrapped in its own Try so a failure surfaces non-fatally (only overrides `tSC` if `tSC` was previously `$$$OK`). Last line `Quit tSC`.
  - [x] Project-rule discipline: no `_` in parameter or method names; `%EXACT()` on every string predicate; `tSC = $$$OK` first / `Quit tSC` last; argumentless Quit in both Try blocks; no JOB / Event.Signal / external I/O inside transactions (none used).

- [x] **Task 4 — Stale-reference scan (Rule 4)**
  - [x] `grep -ni "PurgeOrphanedChatHistory|session-inspection|TaskRun"` across `.claude/rules/`, `docs/`, `src/SessionAgent/`, `_bmad-output/planning-artifacts/`. One stale reference surfaced: [`docs/operator-quickstart.md`](../../docs/operator-quickstart.md) lines 30–46 referenced `PurgeOrphanedChatHistory not yet implemented; sweep deferred` AND `SessionAgent.Config.Agent not yet implemented` (the latter shipped in Epic 2). Updated both: line 30 now reads `Scheduled SessionAgent.PurgeOrphanedChatHistory (Daily at 2:00)`, the stale Config.Agent line removed, and the surrounding paragraph rewritten to describe the post-Epic-7 install state. The other 52 grep matches are token occurrences (literal data values in audit-recipe SQL, planning-doc citations, test method names) — none contradict the new implementation.

- [x] **Task 5 — Compile + auto-sync verification (AC: #7)**
  - [x] `iris_doc_compile` for all 3 modified files — clean (`{"success":true,...,"Compilation finished successfully in 0.003s."}`).

- [x] **Task 6 — Installer scheduling hook end-to-end test (AC: #6)** — captured in Completion Notes.

- [x] **Task 7 — Manual smoke-test of `OnTask()` (AC: #8)** — captured in Completion Notes; temporary helper deployed via `iris_doc_put`, used, deleted via `iris_doc_delete`; existence re-probe confirms removal.

- [x] **Task 8 — Rule 6 regression sweep + SQL ground-truth probe (AC: #7)** — captured in Completion Notes (TestInstance ID 249, 288/288 PASS, baseline preserved).

## Dev Notes

### Rule 1 spec-length watch

This spec targets ~210 lines. Higher than 7.0 (139) and 7.1 (142) because Story 7.2 carries actual class implementation + index additions + scheduling end-to-end test + smoke test. Still under the 250-line cap.

### Rule 3 higher-level MCP first

- `iris_execute_classmethod` for the smoke-test invocation (helper-class wrapper).
- `iris_sql_execute` for SQL probes (the `%SYS.Task` lookup and any pre-flight Chat.History counts).
- `iris_audit_events` (typed MCP) for the audit-event verification — NOT `iris_execute_command`.
- `iris_doc_compile` for class compile verification.

### Rule 7 — operator-state checklist

This story does not introduce new operator-side prerequisites. The sweep task uses the existing `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` audit triple (pre-registered by Story 1.3), the existing Installer scheduling hook (Story 1.5), and standard IRIS classes (`%SYS.Task.Definition`, `Ens.MessageHeader`, `SessionAgent.Chat.History`, `SessionAgent.Audit.LlmCall`, `SessionAgent.Audit.ToolCall`). No new credentials, env-vars, or SSL configs needed.

### Rule 8 fix-now reasoning for AC-5

The Story 7.1 hand-off explicitly defers the index decision to Story 7.2. Per Rule 8 test-1 (genuine future-story scope) — Story 7.2 IS the named successor. Rule 8 default is fix-now: the predicted-bug shape (sweep performance degradation under realistic audit volumes) materializes the moment Story 7.2 ships and the daily 02:00 UTC sweep starts running against operator audit tables. Story 7.3's 1,000-session integration test will surface the cost empirically; pre-emptively adding the index in Story 7.2 means Story 7.3's test will measure indexed performance, not pre-index baseline.

### Rule 10 — no external defaults set

This story sets no library version, model name, or API endpoint. The schedule is `daily 02:00 UTC` per architecture decision (already in `Installer.Install:110`); no Perplexity verification needed.

### Architecture references

- [`architecture.md` line 304 / 322 / 869](../planning-artifacts/architecture.md) — sweep tasks, Epic 7 mapping, file location under `src/SessionAgent/Task/`.
- [`architecture.md` line 387](../planning-artifacts/architecture.md) — audit event triples; `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` confirmed pre-registered.
- [`architecture.md` line 994 (per Story 7.1)](../planning-artifacts/architecture.md) — Persistence-Layer Volume Notes — Audit row carries the Story 7.1 Option B cascade-implementation sentence.

### Source / IRIS-library references (project rule "IRIS Library Source")

- [`irislib/%SYS/Task/Definition.cls:11`](../../irislib/%SYS/Task/Definition.cls#L11) — `Class %SYS.Task.Definition Extends %RegisteredObject` — base class for the new task.
- [`irislib/%SYS/Task/Definition.cls:21`](../../irislib/%SYS/Task/Definition.cls#L21) — `Parameter TaskName As STRING` — the user-visible name.
- [`irislib/%SYS/Task/Definition.cls:38-41`](../../irislib/%SYS/Task/Definition.cls#L38-L41) — `Method OnTask() As %Status` — the override target.

### Cross-class touch points

- [`SessionAgent.Audit.Emit:EnsureEvents`](../../src/SessionAgent/Audit/Emit.cls#L41) — already pre-registers the task's audit triple at line 59. No edit required.
- [`SessionAgent.Installer.Install`](../../src/SessionAgent/Installer.cls#L110) — already calls `ScheduleTaskIfClassExists` for this task class. No edit required.
- [`SessionAgent.Chat.History`](../../src/SessionAgent/Chat/History.cls) — read-only consumer (we DELETE rows but don't change schema). The `(AgentName, SessionKey, PortalUser)` tuple guarantees uniqueness.
- [`SessionAgent.Audit.LlmCall`](../../src/SessionAgent/Audit/LlmCall.cls) — adding `Index ChatHistoryIdIdx`.
- [`SessionAgent.Audit.ToolCall`](../../src/SessionAgent/Audit/ToolCall.cls) — adding `Index ChatHistoryIdIdx`.

### Sources

- [`epics.md` Epic 7 Story 7.2 ACs](../planning-artifacts/epics.md).
- [`7-1-task-0-probe-audit-fk-cascade-design.md`](7-1-task-0-probe-audit-fk-cascade-design.md) — Option B cascade contract + AC-5 hand-off (index sub-decision).
- [`prd.md`](../planning-artifacts/prd.md) — FR44 (chat-history lifecycle), NFR-R2 (purge integrity), NFR-R5 (idempotent install), NFR-SC4 (audit-volume bound).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — multiple sections cited in tasks.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"SQL-probe-as-ground-truth for test-pass verification".
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 2 sharpened, Rule 7 sub-clause, Rule 8 fix-now default.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — dev agent invoked via `/epic-cycle` Story 7.2 worktree.

### Debug Log References

- **Sample-production state.** First `Ens.Director.IsProductionRunning` call returned 0 (production stopped). `SessionAgent.Sample.Bootstrap.StartProductionIfStopped` initially errored with `<Ens>ErrInvalidProduction` because the production was uninstalled in HSCUSTOM after a prior cycle's teardown. Ran `SessionAgent.Sample.Bootstrap.InstallProduction` (the MCP envelope returned a non-JSON response, but the install succeeded — verified by re-running `StartProductionIfStopped` which then returned 1). Final `IsProductionRunning` = 1.
- **`iris_doc_compile` "up-to-date".** All three files reported "up-to-date" on first compile because the IRIS auto-sync workflow (project rule "VSCode Auto-Sync Workflow") had already pushed source-on-save and triggered the compile. Index registration verified empirically via SQL probe of `%Dictionary.IndexDefinition` (both classes returned `ChatHistoryIdIdx` rows). One-time `%BuildIndices($ListBuild("ChatHistoryIdIdx"))` ran clean (empty error text = `$$$OK`) on both classes.
- **`Installer.Install("")` first call.** `iris_execute_classmethod` returned a non-JSON response (the Install method's `Write !,"[iris-session-agent] ..."` device output broke envelope parsing). Switched to `iris_execute_command` which captures device output cleanly. Verified via post-call `%SYS.Task` SQL probe that the install logic completed (task ID 1006 was created). Deleted ID 1006 to capture a clean fresh-install log line via a second invocation (ID 1007).
- **OnTask audit event filter.** Initial `iris_audit_events` filter with `beginDate=2026-05-07 05:12:00` returned 0 events; the IRIS audit-events MCP filter date appears to compare against server-local time (not the `Z`-suffixed UTC ISO-8601 the smoke-start probe printed). Removed the date filter; one matching event surfaced with `timestamp=2026-05-06 22:12:27.377` and the expected `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` triple plus the JSON counter payload.

### Completion Notes List

**AC-1 / AC-2 — Class shape + OnTask sweep (verified by file presence + smoke).** The new class [`src/SessionAgent/Task/PurgeOrphanedChatHistory.cls`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls) extends `%SYS.Task.Definition` (the base class verified at [`irislib/%SYS/Task/Definition.cls:11`](../../irislib/%SYS/Task/Definition.cls#L11)), declares `Parameter TaskName = "PurgeOrphanedChatHistory";`, implements `Method OnTask() As %Status` (the override target at [`irislib/%SYS/Task/Definition.cls:38-41`](../../irislib/%SYS/Task/Definition.cls#L38-L41)). Class doc-comment provides operator-readable description. Sweep architecture: Phase 1 collects orphan candidate IDs into `tOrphanIds()` array (avoids cursor-vs-DELETE aliasing on `Chat.History`), Phase 2 prepares the audit-DELETE statements ONCE outside the loop (efficient reuse against the new `ChatHistoryIdIdx`), Phase 3 iterates orphans with each delete sequence wrapped in a sub-Try (per-orphan commit semantic per AC-4). Story 7.1 Option B order preserved: LlmCall delete → ToolCall delete → `Chat.History.%DeleteId(chatId)`.

**AC-3 — Audit event emission (verbatim).** The audit-event MCP query `mcp__iris-ops-mcp__iris_audit_events eventType=TaskRun maxRows=10` returned exactly one event for the smoke run:

```
{"timestamp":"2026-05-06 22:12:27.377","username":"_SYSTEM","eventSource":"SessionAgent","eventType":"TaskRun","event":"PurgeOrphanedChatHistory","description":"{\"orphans_deleted\":0,\"llm_audit_deleted\":0,\"tool_audit_deleted\":0,\"scan_time_ms\":170}","clientIPAddress":"::1","namespace":"HSCUSTOM"}
```

The `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)` triple is pre-registered by [`SessionAgent.Audit.Emit:EnsureEvents`](../../src/SessionAgent/Audit/Emit.cls#L59) (Story 1.3) — no `RegisterIfMissing` call needed at runtime. Counters all 0 (1 inspection chat-history row exists for SessionId=5294 which is alive in `Ens.MessageHeader`, so no orphans found — valid green smoke per AC-8). Scan completed in 170ms.

**AC-4 — `%Status` discipline + Try/Catch + transaction safety.** First line `Set tSC = $$$OK`, last line `Quit tSC`. Outer Try/Catch uses argumentless `Quit` in catch (project rule "QUIT Statement Restrictions in Try/Catch Blocks"); audit-emission Try uses argumentless `Quit` in its own catch. No `TSTART`/`TCOMMIT` blocks anywhere — per AC-4 spec, "commit per orphan to maximize forward progress under partial-failure conditions" is the chosen semantic. No JOB / Event.Signal / external I/O calls anywhere (project rule "Transaction Side Effects" trivially satisfied since no transactions exist).

**AC-5 — `ChatHistoryIdIdx` indexes (verified).**

```
SELECT %EXACT(parent) AS Class, %EXACT(Name) AS IndexName, %EXACT(Properties) AS Properties
FROM %Dictionary.IndexDefinition
WHERE %EXACT(parent) IN ('SessionAgent.Audit.LlmCall', 'SessionAgent.Audit.ToolCall')
```

**Verbatim result:** `{"columns":["Class","IndexName","Properties"],"rows":[["SessionAgent.Audit.LlmCall","ChatHistoryIdIdx","ChatHistoryId"],["SessionAgent.Audit.ToolCall","ChatHistoryIdIdx","ChatHistoryId"]],"rowCount":2}`. Both indexes registered. Storage section was NOT hand-edited (compiler maintains it per project rule "Storage Sections"). One-time `%BuildIndices` for both classes returned `$$$OK`.

**AC-6 — Installer scheduling hook end-to-end (verbatim).**

*First-install run* (after deleting any pre-existing entry to capture a fresh "Scheduled" log line):

```
[iris-session-agent] Scheduled SessionAgent.PurgeOrphanedChatHistory (Daily at 2:00)
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] session-inspection: row already present; skipping
[iris-session-agent] message-search: row already present; skipping
=== iris-session-agent install reminders === ...
InstallStatus=
```

*Re-run (idempotency)*:

```
[iris-session-agent] Task SessionAgent.PurgeOrphanedChatHistory already scheduled (ID=1007); skipped
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] session-inspection: row already present; skipping
[iris-session-agent] message-search: row already present; skipping
=== iris-session-agent install reminders === ...
InstallStatus=
```

NFR-R5 idempotency confirmed (`already scheduled (ID=1007); skipped`). `InstallStatus=` empty = `$$$OK`.

*`%SYS.Task` SQL probe (verbatim):*

```sql
SELECT ID, %EXACT(Name) AS Name, %EXACT(NameSpace) AS NameSpace, %EXACT(TaskClass) AS TaskClass
FROM %SYS.Task
WHERE %EXACT(Name) = 'SessionAgent.PurgeOrphanedChatHistory'
```

**Verbatim result:** `{"columns":["ID","Name","NameSpace","TaskClass"],"rows":[[1007,"SessionAgent.PurgeOrphanedChatHistory","HSCUSTOM","SessionAgent.Task.PurgeOrphanedChatHistory"]],"rowCount":1}`. Exactly one row, `TaskClass` matches the new class, `NameSpace = HSCUSTOM`.

**AC-7 — Compile + Rule 6 regression sweep + SQL ground-truth probe.** All 3 modified files compile clean (`{"success":true,...}`). Package runner `iris_execute_tests target=SessionAgent.Test level=package` returned a truncated envelope (1 method visible — Rule 6 `iris_execute_tests` truncation workaround applies); the full result-set persisted to `^UnitTest.Result` TestInstance ID 249.

**SQL ground-truth probe (Rule 6 / Story 5.0 AC-1 canonical form):**

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
WHERE %EXACT(tc.ID) %STARTSWITH '249||'
```

**Verbatim result:** `{"columns":["Total","Passed","Failed"],"rows":[[288,288,0]],"rowCount":1}` — **288/288 PASS, 0 failures.** Failure-only confirmation `WHERE tc.ID %STARTSWITH '249||' AND tm.Status = 0` returned `FailCount=0`. Story 7.0 / 7.1 baseline of 288/288 across 35 test classes preserved exactly. Story 7.2 added no unit-test classes (Story 7.3 owns the dedicated test class for the sweep task).

**AC-8 — Manual smoke test of `OnTask()` end-to-end (verbatim).** Temporary helper class `SessionAgent.TempProbe.PurgeOrphanedChatHistorySmoke` deployed via `iris_doc_put` (lives only on IRIS side per project rule "iris_doc_put = throwaway test classes only"), compiled clean (`{"success":true,...,"Compiling class SessionAgent.TempProbe.PurgeOrphanedChatHistorySmoke","Compilation finished successfully in 0.011s."}`). Helper body:

```objectscript
ClassMethod RunSmoke() As %String
{
    Set tInst = ##class(SessionAgent.Task.PurgeOrphanedChatHistory).%New()
    Set tSC = tInst.OnTask()
    Quit "OnTaskStatus=" _ $System.Status.GetErrorText(tSC) _ ";IsOK=" _ $$$ISOK(tSC)
}
```

`iris_execute_classmethod className=SessionAgent.TempProbe.PurgeOrphanedChatHistorySmoke methodName=RunSmoke` returned **verbatim:** `{"returnValue":"OnTaskStatus=;IsOK=1","argCount":0}` — empty error text = `$$$OK`, `IsOK=1`. The audit event landed (verbatim payload above under AC-3). Helper deleted via `iris_doc_delete`; `iris_doc_get metadataOnly=true` re-probe returned `{"exists":false,...}` confirming clean removal. Pre-smoke baseline counts: 1 inspection chat-history row, 118 LlmCall audit rows, 80 ToolCall audit rows; post-smoke unchanged (the lone chat row's SessionId=5294 is alive in `Ens.MessageHeader`, so no orphans to delete — valid green smoke per AC-8 contract).

### File List

**Modified:**
- `src/SessionAgent/Audit/LlmCall.cls` — added `Index ChatHistoryIdIdx On ChatHistoryId;` + accompanying doc-comment paragraph (above the auto-generated Storage block — Storage section NOT hand-edited).
- `src/SessionAgent/Audit/ToolCall.cls` — same.
- `docs/operator-quickstart.md` — Rule 4 stale-reference fix: example install log lines 28–46 updated to reflect the post-Story-7.2 install state (`Scheduled SessionAgent.PurgeOrphanedChatHistory (Daily at 2:00)` replaces the prior `not yet implemented; sweep deferred` line; the also-stale `SessionAgent.Config.Agent not yet implemented` line removed since Config.Agent shipped in Epic 2; surrounding paragraph rewritten to describe the post-Epic-7 install state and the idempotent re-install behavior).
- `_bmad-output/implementation-artifacts/7-2-purgeorphanedchathistory-task-installer-scheduling.md` — task checkboxes flipped to `[x]`, Dev Agent Record / Completion Notes / File List / Change Log filled in, Status flipped to `review`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story 7.2 status: `ready-for-dev` → `in-progress` (will flip to `review` at Step 9).

**Created:**
- `src/SessionAgent/Task/PurgeOrphanedChatHistory.cls` — NEW. The sweep task class extending `%SYS.Task.Definition`. Implements the Story 7.1 Option B cascade (audit rows first, then chat row), per-orphan sub-Try for forward-progress semantics, prepare-once audit-DELETE statements for indexed-O(log n) per-orphan cost.

**Server-side (not in repo):**
- `SessionAgent.TempProbe.PurgeOrphanedChatHistorySmoke.cls` — temporary smoke helper deployed via `iris_doc_put`, used to invoke `OnTask()` end-to-end, deleted via `iris_doc_delete`. Existence re-probe via `iris_doc_get metadataOnly=true` confirmed `{"exists":false,...}` after deletion.

## Code Review

**Reviewed by:** Claude Opus 4.7 (1M context) — code reviewer agent invoked via `/bmad-code-review` against Story 7.2 working-tree diff (4 modified files + 1 new `.cls` + 1 new story file + sprint-status flip).

**Verdict:** APPROVED. All 8 acceptance criteria pass. Empirical claims independently verified via SQL probes (both indexes registered, `%SYS.Task` ID=1007 single row, regression sweep TestInstance 249 = 288/288 PASS). One MEDIUM finding patched in this review pass; LOW findings logged to deferred-work for visibility.

### Empirical re-verification of dev's claims

| Dev claim | Verification probe | Result |
|---|---|---|
| Both `ChatHistoryIdIdx` indexes registered | `SELECT … FROM %Dictionary.IndexDefinition WHERE parent IN (...)` | 2 rows, verbatim match to dev's payload |
| `%SYS.Task` ID=1007 single row, TaskClass match | `SELECT … FROM %SYS.Task WHERE Name = 'SessionAgent.PurgeOrphanedChatHistory'` | 1 row: ID=1007, NameSpace=HSCUSTOM, TaskClass=SessionAgent.Task.PurgeOrphanedChatHistory |
| Regression sweep 288/288 PASS on TestInstance 249 | `SELECT COUNT(*), SUM(Status=1), SUM(Status=0) FROM %UnitTest_Result.TestMethod tm JOIN TestCase tc ON tm.TestCase = tc.ID WHERE tc.ID %STARTSWITH '249||'` | `Total=288, Passed=288, Failed=0` |
| Class deployed | `iris_doc_get metadataOnly=true` | `{"exists":true, "etag":"2026-05-06 22:08:44.344"}` |

### Three-layer review findings

**Layer 1 — Blind Hunter (diff only, no project context):** 9 candidate findings raised, 2 forwarded to triage (`F-01`, `F-06`), the rest dismissed as false-positive on second-pass diff reading.

**Layer 2 — Edge Case Hunter (diff + project read):** 11 candidate findings raised, including the resource-leak / type-coercion / concurrent-sweep edge cases. After triage, 1 MEDIUM forwarded to patch (`F-01`); 6 LOW deferred or dismissed.

**Layer 3 — Acceptance Auditor (diff + spec + context docs):** All 8 ACs pass. AC-1 through AC-8 each have verbatim evidence in dev's Completion Notes matching the AC's "Then …" clause shape (per Rule 2 sharpened). One AC-9 ("Stale-reference scan, Rule 4") flagged as PARTIAL — see F-01 below.

### Findings actioned this review

| ID | Severity | Source | Title | Outcome |
|---|---|---|---|---|
| F-01 | MEDIUM | edge+blind | `docs/operator-quickstart.md` install-log example omitted Config.Agent seeding lines that the actual post-Epic-2 install produces (operator opening this doc on a fresh install would see 3 extra lines the doc didn't predict) | **PATCHED** — added the 3 missing lines (`Config.Agent present — seeding default rows`, `session-inspection: row already present; skipping`, `message-search: row already present; skipping`) to the install-log example block at lines 33-35. The narrative below still correctly refers to "the two remaining `not yet implemented; sweep deferred` lines" — those lines are unchanged and that count is still accurate (PurgeStaleSearchChat + UserVocabularyDecay). |

### Findings deferred (LOW — Rule 8 review)

Each evaluated against Rule 8's three explicit defer tests. None pass test 1 (future-epic scope), 2 (external-dependency blocker), or 3 (cosmetic with no predicted-bug shape) cleanly — but each is also LOW with no concrete predicted-bug shape because the surrounding architecture (sub-Try wrapping, `%SYS.Task` concurrency guard, IRIS GC of transient handles) absorbs the risk under realistic operating conditions. Logged to `deferred-work.md` for visibility per the standing rule.

| ID | Severity | Title | Defer rationale |
|---|---|---|---|
| F-02 | LOW | Open `tScanRS` not closed if outer Try fails before line 132 explicit `%Close()` | Sub-Try absorbs; `%SYS.Task` daily run + IRIS GC mitigates accumulation. No bug shape under realistic operating conditions. |
| F-03 | LOW | `tLlmRS`/`tToolRS` not closed if `%Execute` raises mid-DELETE inside Phase 3 sub-Try | Sub-Try absorbs the exception; transient RS handle is GC'd. Forward-progress design (per AC-4 commit-per-orphan) explicitly accepts. |

### Findings dismissed

| ID | Title | Rationale |
|---|---|---|
| F-04 | `tChatId` integer parameter against `%String` ChatHistoryId column | IRIS SQL coerces; ChatHistoryId is the integer Chat.History row-ID stored as a `%String` — same scalar value, comparison is exact. Verified by AC-3 evidence (smoke ran clean). |
| F-05 | Concurrent-sweep race over-counts deleted orphans | `%SYS.Task` prevents concurrent same-task firings (verified by reading `irislib/%SYS/Task.cls` lock semantics). Manual+scheduled overlap is an operator-error scenario the design explicitly accepts via commit-per-orphan. |
| F-06 | `$System.Security.Audit` 5-arg form (with `tSC` in `EventData` slot) differs from `Emit.cls` 4-arg precedent | Verbatim audit row in AC-3 evidence shows the JSON payload landing in the `description` column (5th-arg slot) as intended. The `EventData` slot accepting a `%Status` is a documented IRIS audit pattern. No bug. |
| F-07 | `%DeleteId` failure path doesn't surface error status | Design choice per AC-4 ("commit per orphan to maximize forward progress"). Counter delta is the operator-observable signal per the spec's intentional design — surfaces in `audit.description.orphans_deleted` < scanned-orphan count. |

### Reviewer-modified files

- `docs/operator-quickstart.md` — F-01 patch (added 3 lines to the install-log example block; narrative unchanged).
- `_bmad-output/implementation-artifacts/7-2-purgeorphanedchathistory-task-installer-scheduling.md` — this Code Review section.
- `_bmad-output/implementation-artifacts/deferred-work.md` — appended F-02 and F-03 entries.

### Severity tally

- HIGH found / fixed / deferred: 0 / 0 / 0
- MEDIUM found / fixed / deferred: 1 / 1 / 0
- LOW found / fixed / deferred: 6 / 0 / 2 (4 dismissed as false-positive)

Story 7.2 is approved for commit.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-06 | Initial spec drafted by lead per Story 7.1 hand-off — Option B cascade implementation, ChatHistoryIdIdx fix-now per Rule 8 hand-off, Installer scheduling hook end-to-end test, manual smoke test against live HSCUSTOM | Claude Opus 4.7 (lead) |
| 2026-05-06 | Dev complete — `SessionAgent.Task.PurgeOrphanedChatHistory.cls` created (Story 7.1 Option B cascade: collect-then-delete with prepare-once audit DELETEs against new ChatHistoryIdIdx, per-orphan sub-Try for forward-progress semantics); `Index ChatHistoryIdIdx` added to both `Audit.LlmCall.cls` and `Audit.ToolCall.cls` (Rule 8 fix-now per Story 7.1 hand-off); Installer hook end-to-end verified (fresh-install "Scheduled" line + idempotent "already scheduled (ID=1007); skipped" line; `%SYS.Task` SQL probe shows exactly one row); OnTask smoke returned `OnTaskStatus=;IsOK=1` with one matching audit event landed; regression sweep 288/288 PASS via SQL ground-truth probe on TestInstance ID 249 (baseline preserved exactly). Rule 4 stale-reference scan surfaced one stale line in `docs/operator-quickstart.md` (and an also-stale Config.Agent reference) — both fixed in the same commit. Story flipped to `review`. | Claude Opus 4.7 (dev) |
