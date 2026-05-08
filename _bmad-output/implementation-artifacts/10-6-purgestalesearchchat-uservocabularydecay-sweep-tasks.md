# Story 10.6: `PurgeStaleSearchChat` + `UserVocabularyDecay` Sweep Tasks

Status: done

## Story

As an **Operator-Admin with a long-running production install**,
I want two sweep tasks running automatically: `PurgeStaleSearchChat` (daily 03:00 UTC, removes Search-keyed `Chat.History` rows older than `Config.Agent.SearchChatRetentionDays` default 30) + `UserVocabularyDecay` (Sunday 04:00 UTC, removes `UserVocabulary` rows where `Confidence < 0.2 AND LastUsed > 90d`),
So that storage doesn't grow unboundedly per FR45 + AR4 + NFR-R3 + NFR-SC4.

This story ships the storage-bound enforcement layer for Search Agent. Today, the Installer (Story 1.5) already calls `ScheduleTaskIfClassExists("SessionAgent.PurgeStaleSearchChat", "SessionAgent.Task.PurgeStaleSearchChat", "Daily", 3, 0)` and `ScheduleTaskIfClassExists("SessionAgent.UserVocabularyDecay", ...)` — but the task classes don't exist yet. This story creates them. After this story lands, both tasks will land in `%SYS.Task` on next install.

## Carry-Forward — AI-4 from Story 10.0 (LOW-9.3-F02)

Per Story 10.0 AC-5, this story's spec author MUST grep `deferred-work.md` for "Story 10.6" mentions. Result:

- **LOW-9.3-F02 — Token-cap branch in `Build` is structurally unreachable under current calibration** (deferred-work.md line ~1232; owner re-bound to Story 10.6 spec author by Story 10.0 AI-4).

**Triage decision (this spec):** Defer **further** to Story 10.9 (PRD v1 Completion Validation Walkthrough). Rationale: Story 10.6 ships sweep tasks (TTL/decay enforcement) but does NOT change the calibration constants (`MaxEntries=20`, `MessageBodyClass MAXLEN=128`) that gate the token-cap branch's reachability. The `UserVocabularyDecay` sweep REMOVES rows but does not add longer-descriptor variants — the token-cap branch's reachability remains unchanged after this story. Story 10.9's PRD-final-validation walkthrough is the natural moment to either (a) confirm the calibration constants stay put for v1 (delete the dead branch) OR (b) widen the constants for v2 (test the byte-count cap path empirically). Updates to `deferred-work.md` per AC-2 below.

## Acceptance Criteria

ACs come from epics.md §"Story 10.6" verbatim, augmented by Task 0 finding (Installer already wires `ScheduleTaskIfClassExists` for both task names; spec just needs the task classes themselves).

### AC-1 — `SessionAgent.Task.PurgeStaleSearchChat` (NEW)

**Given** the developer is implementing the sweep task
**When** they implement the class (parallels Story 7.2's `SessionAgent.Task.PurgeOrphanedChatHistory`)
**Then** [`src/SessionAgent/Task/PurgeStaleSearchChat.cls`](../../src/SessionAgent/Task/PurgeStaleSearchChat.cls) extends `%SYS.Task.Definition`.
**And** `Parameter TaskName = "PurgeStaleSearchChat"`.
**And** the class has the operator-readable doc-comment + `Description` parameter populated per Rule 7 §"Operator-observable surface enumeration" (avoiding the Story 7.2 blank-Description gap).
**And** `OnTask() As %Status` reads `Config.Agent.SearchChatRetentionDays` for the `message-search` agent (default 30 days; per Story 2.4 schema).
**And** the method deletes `Chat.History` rows WHERE `AgentName = 'message-search'` AND `UpdatedAt < <now-retentionDays>` via parameterized prepared SQL (using `%EXACT()` discipline).
**And** the method emits a native IRIS audit event via `$System.Security.Audit("SessionAgent","TaskRun","PurgeStaleSearchChat", JSON-with-{rows_deleted, retention_days})`.
**And** project-rule discipline: first line `Set tSC = $$$OK`, last line `Quit tSC`, transaction side-effects after TCOMMIT (the audit event AND the `Audit.Emit.LogTaskRun` defensive surface enumeration per Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses" — codified Story 10.0 AC-4).

### AC-2 — `SessionAgent.Task.UserVocabularyDecay` (NEW)

**Given** the developer is implementing the vocab decay task
**When** they implement the class
**Then** [`src/SessionAgent/Task/UserVocabularyDecay.cls`](../../src/SessionAgent/Task/UserVocabularyDecay.cls) extends `%SYS.Task.Definition`.
**And** `Parameter TaskName = "UserVocabularyDecay"`.
**And** the class declares Class Parameters `DecayConfidenceThreshold = 0.2` and `DecayLastUsedDays = 90` per architecture §"Calibration constants".
**And** the operator-readable `Description` parameter is populated per Rule 7.
**And** `OnTask() As %Status` deletes `UserVocabulary` rows WHERE `Confidence < ..#DecayConfidenceThreshold` AND `LastUsed < <now - ..#DecayLastUsedDays>` via parameterized prepared SQL.
**And** emits audit event `(SessionAgent, TaskRun, UserVocabularyDecay, JSON-with-{rows_deleted, threshold, last_used_days})`.
**And** project-rule discipline as AC-1.

### AC-3 — Audit-event triple registration

**Given** the new tasks emit audit events
**When** the developer extends `SessionAgent.Audit.Emit:EnsureEvents` (Story 1.3 / Story 7.2 pattern)
**Then** the helper registers the new triples via `Security.Events.Create(...)` if they don't exist:
- `(SessionAgent, TaskRun, PurgeStaleSearchChat)` with operator-readable Description.
- `(SessionAgent, TaskRun, UserVocabularyDecay)` with operator-readable Description.

The `EnsureEvents` method is invoked at install time per Story 1.3's wiring; the new triples land on every fresh install + every upgrade.

### AC-4 — Installer scheduling extension (idempotent)

**Given** Installer (Story 1.5) already calls `ScheduleTaskIfClassExists` for both task names
**When** the developer reviews the existing scheduling
**Then** the existing scheduling lines (Installer.cls lines 111–112) **stay verbatim** — no Installer change required for the daily/weekly schedules. Task 0 confirms both calls are already in place.
**And** if `ScheduleTaskIfClassExists` does NOT support a `pDayOfWeek` parameter for weekly tasks (verify via `iris_doc_get`), AC-4 extends the helper signature with an optional `pDayOfWeek As %String = ""` parameter that maps to `%SYS.Task` `DaysOfWeek` field. The Sunday default is wired into the helper's weekly-frequency branch.
**And** scheduling is idempotent per NFR-R5 (helper checks if a row with the matching `Name` already exists before creating; existing pattern from Story 7.2).

### AC-5 — Integration tests

**Given** the new tasks need integration test coverage
**When** the developer creates a new test class [`src/SessionAgent/Test/SweepTaskTest.cls`](../../src/SessionAgent/Test/SweepTaskTest.cls)
**Then** at least 6 tests are added:
1. `TestPurgeStaleSearchChatDeletesStaleRows` — seed 100 `Chat.History` rows (50 older than retentionDays + 50 newer) with `AgentName='message-search'`. Run `PurgeStaleSearchChat:OnTask()`. Assert 50 stale rows deleted; 50 fresh rows preserved.
2. `TestPurgeStaleSearchChatRetentionDaysFromConfig` — set `Config.Agent.SearchChatRetentionDays = 14`. Seed rows at 10, 15, 20 days old. Assert only the 15+ and 20+ day rows are deleted (boundary check).
3. `TestPurgeStaleSearchChatAuditEvent` — verify `$System.Security.Audit` event landed with the expected `(SessionAgent, TaskRun, PurgeStaleSearchChat)` triple after `OnTask()`.
4. `TestUserVocabularyDecayDeletesStaleRows` — seed 50 `UserVocabulary` rows (10 with `Confidence < 0.2 AND LastUsed > 90d` + 40 fresh). Run `UserVocabularyDecay:OnTask()`. Assert 10 decayed rows deleted; 40 fresh preserved.
5. `TestUserVocabularyDecayThresholdBoundary` — seed rows with `Confidence ∈ {0.19, 0.20, 0.21}`. Assert only 0.19 row deleted (strict < threshold).
6. `TestUserVocabularyDecayAuditEvent` — verify `(SessionAgent, TaskRun, UserVocabularyDecay)` audit triple after `OnTask()`.

Test-class `Property` names follow `FilePath`/`FixtureCount`/etc. — never `Test*` prefix per Story 7.0 / Epic 6 retro AI-3 shadow-trap rule.

### AC-6 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.Task.PurgeStaleSearchChat`, `SessionAgent.Task.UserVocabularyDecay`, modified `SessionAgent.Audit.Emit` (EnsureEvents extension), modified `SessionAgent.Installer` (if `ScheduleTaskIfClassExists` signature extended), new `SessionAgent.Test.SweepTaskTest` (NEW).
- New tests added per AC-5 — at least 6.
- **Per-class regression sweep + canonical numerical-MAX SQL probe**. **Expected baseline 398 + 6 = 404+**.

### AC-7 — Live integration smoke (Rule 11)

**Given** the operator-state is verified per Step-1 matrix
**When** the dev runs `iris_task_list` post-install + `iris_task_history` for both new tasks (or invokes `OnTask()` directly via `iris_execute_classmethod`)
**Then** both tasks appear in `%SYS.Task` with the expected schedule (daily 03:00 UTC for PurgeStaleSearchChat; weekly Sunday 04:00 UTC for UserVocabularyDecay) AND populated Description columns per Rule 7 operator-observable surface enumeration.
**And** running `OnTask()` once on each task succeeds with no errors (capture verbatim status return + audit event row count delta).

### AC-8 — Operator-observable surface (Rule 7)

**Given** the new tasks ship with operator-visible artifacts
**When** the spec verifies operator surfaces
**Then** the lead's pre-retro empirical battery checklist (Story 8.0 / Epic 7 retro AI-3) MUST capture verbatim:
1. `iris_task_list` envelope showing both new tasks with non-empty Description columns.
2. `iris_audit_events` envelope showing the new triples (`SessionAgent/TaskRun/PurgeStaleSearchChat`, `SessionAgent/TaskRun/UserVocabularyDecay`) with non-empty Description fields.

### AC-9 — `deferred-work.md` re-bind for LOW-9.3-F02

**Given** Story 10.0 AI-4 re-bound LOW-9.3-F02 to Story 10.6 spec author
**When** this spec is being authored
**Then** the `Owner:` line of LOW-9.3-F02 in `deferred-work.md` is updated to: *"Story 10.9 (PRD v1 Completion Validation Walkthrough — re-bound by Story 10.6 spec author per the spec's "Carry-Forward — AI-4" section). Rationale: Story 10.6 ships TTL/decay sweeps but does NOT change calibration constants (`MaxEntries=20`, `MessageBodyClass MAXLEN=128`) that gate the token-cap branch's reachability — branch remains unreachable post-Story-10.6. Story 10.9 PRD-final-validation is the natural moment to either delete the dead branch (v1 calibration confirmed) OR widen constants for v2."*
**And** Story 10.9's lead MUST grep `deferred-work.md` for "Story 10.9" mentions (already inherited from Story 9.0 AC-6) and incorporate this entry alongside items E/H/I + the AI-5 umbrella.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes (Rule 4 / Rule 7)**
  - [x] Verify Installer.cls lines 111–112 wire `ScheduleTaskIfClassExists` for both task names (already verified at spec-creation time; confirm no drift).
  - [x] Verify `Config.Agent.SearchChatRetentionDays` property exists with `InitialExpression = 30` (already verified — Config/Agent.cls line 126).
  - [x] Verify `ScheduleTaskIfClassExists` signature (`iris_doc_get` on `SessionAgent.Installer:ScheduleTaskIfClassExists`) — does it support weekly day-of-week? If not, AC-4 extends the helper.
  - [x] Verify `Audit.Emit.EnsureEvents` extension surface (existing triples + insertion pattern).
  - [x] Document any drift inline in working notes; resolve in same commit.

- [x] **Task 1 — Implement `PurgeStaleSearchChat` (AC: #1)**
  - [x] Create the class with `Parameter TaskName`, operator-readable `Description`, `OnTask()` reading `Config.Agent.SearchChatRetentionDays`, parameterized SQL DELETE, audit emission.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — Implement `UserVocabularyDecay` (AC: #2)**
  - [x] Create the class with `Parameter TaskName`, operator-readable `Description`, Class Parameters `DecayConfidenceThreshold = 0.2` + `DecayLastUsedDays = 90`, `OnTask()` parameterized SQL DELETE, audit emission.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 3 — Extend `Audit.Emit:EnsureEvents` (AC: #3)**
  - [x] Add the 2 new audit-event triples to the existing helper.
  - [x] Compile via `iris_doc_compile`.
  - [x] Run `EnsureEvents()` once via `iris_execute_classmethod` to land the triples on the dev install.

- [x] **Task 4 — Installer scheduling verification or extension (AC: #4)**
  - [x] If `ScheduleTaskIfClassExists` already supports the weekly day-of-week parameter, no Installer change required.
  - [x] If extension needed, add the `pDayOfWeek` parameter with backward-compatible default. Compile.
  - [x] Re-run `Installer:Install("")` to verify both tasks land in `%SYS.Task` with the expected schedules.

- [x] **Task 5 — Implement `SweepTaskTest` (AC: #5)**
  - [x] Create the test class with 6 tests per AC-5.
  - [x] Use `OnBeforeOneTest` / `OnAfterOneTest` to seed and clean up test fixtures (avoid the AI-5 umbrella flake pattern by ensuring per-test isolation — direct SQL DELETE in tearDown).
  - [x] Compile + run via `iris_execute_tests` per-class. Confirm 6/6 PASS.

- [x] **Task 6 — Live-integration smoke (AC: #7, #8)**
  - [x] Re-install via `Installer:Install("")`. Confirm both tasks appear in `iris_task_list` with populated Description columns.
  - [x] Confirm both audit-event triples appear in `iris_audit_events` with populated Description.
  - [x] Invoke `OnTask()` once on each task via `iris_execute_classmethod`; capture verbatim status return + audit event row count delta.

- [x] **Task 7 — `deferred-work.md` re-bind (AC: #9)**
  - [x] Update LOW-9.3-F02 Owner line per AC-9 verbatim.

- [x] **Task 8 — Verification battery (AC: #6)**
  - [x] Per-class regression sweep + canonical numerical-MAX SQL probe.
  - [x] If any AI-5 flake class hits, retry per Story 10.0 umbrella entry's documented behavior.

## Dev Notes

### Rule 1 / Rule 8 / Rule 9 / Rule 10 / Rule 11

- **Rule 1:** Spec targets ~225 lines.
- **Rule 8:** Net-new code; fix-now default. AC-9 LOW-9.3-F02 re-bind per Rule 9.
- **Rule 9:** AI-4 carry-forward addressed in §"Carry-Forward — AI-4" + AC-9.
- **Rule 10:** No external defaults set.
- **Rule 11:** AC-7 live-task invocation. No external API touched (TTL sweeps are IRIS-internal).

### Rule 7 §"Operator-observable surface enumeration"

Both task classes ship operator-observable artifacts (`%SYS.Task` rows + `Security.Events` triples). Per Rule 7 / Epic 7 retro AI-1, the spec MUST enumerate the descriptive text fields:
- `%SYS.Task.Description` — populated via Installer's `ScheduleTaskIfClassExists` reading `%Dictionary.ClassDefinition.%OpenId(pTaskClass).Description` (Story 8.0 AC-2 codified pattern). Both new task classes need a non-empty class-level `///` doc-comment that lands as the Description.
- `Security.Events.Description` — populated via `Audit.Emit.EnsureEvents` extension; pass operator-readable text per existing precedent (Story 1.3 / Story 7.2).

### Rule 8 §"Defensive-surface enumeration"

Per Story 10.0 AC-4 codification: AC-1 / AC-2's "propagate the status" obligation enumerates 3 specific defensive surfaces:
- (a) ByRef returns: not applicable here (no envelope-correctness dependency on inner result).
- (b) `If SQLCODE < 0` checks on every `&sql` operation — both DELETE statements MUST check SQLCODE post-execution.
- (c) error-envelope shaping: `OnTask()` returns a `%Status`; on any error, return a status with operator-readable message text via `$$$ERROR($$$GeneralError, "...")` so the `%SYS.Task` history surface shows the error.

### Carry-forward (per Rule 9 grep target)

`grep -n "Story 10.6" _bmad-output/implementation-artifacts/deferred-work.md` returns 1 match: LOW-9.3-F02 (re-bound from Story 10.0 AI-4). Triage decision in §"Carry-Forward — AI-4" above.

### Auto-sync workflow

All `.cls` files auto-sync. `iris_doc_compile` required for compile-error verification.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — claude-opus-4-7[1m].

### Completion Notes

**Task 0 — Backend-surface probes (verbatim findings).**

- Baseline regression (pre-implementation, canonical numerical-MAX SQL probe against `%UnitTest_Result.TestMethod`): `Total=398, Passed=398, Failed=0`.
- `%Dictionary.ClassDefinition.%ExistsId("SessionAgent.Task.PurgeStaleSearchChat") = 0` and `%ExistsId("SessionAgent.Task.UserVocabularyDecay") = 0` — clean slate, both target classes absent at story start.
- `SessionAgent.Config.Agent.AgentNameIdxExists("message-search") = 1` — seed row exists.
- `Config/Agent.cls` line 126: `Property SearchChatRetentionDays As %Integer [ InitialExpression = 30 ];` — default 30 confirmed.
- `Audit/Emit.cls` lines 60-61 already include both new triples (`(SessionAgent, TaskRun, PurgeStaleSearchChat)` + `(SessionAgent, TaskRun, UserVocabularyDecay)`); `Test/AuditEmitTest.cls` lines 59-60 already assert both.
- `Installer.cls` lines 111-112 already invoke `ScheduleTaskIfClassExists` for both names with `Daily 03:00 UTC` and `Weekly 04:00 UTC` respectively; `ScheduleTaskIfClassExists` lines 392-394 implement `Weekly` frequency with `TimePeriod=1, TimePeriodDay=1` (Sunday) — no Installer change required.

**Net result of Task 0:** Tasks 3 + 4 are already implemented in shipped code; this story's net-new code is Tasks 1, 2, 5 (two task classes + one test class) plus the Task 7 deferred-work re-bind.

**AC-1 verification (PurgeStaleSearchChat).** Class compiles clean; `OnTask()` reads `Config.Agent.SearchChatRetentionDays` for the `message-search` agent (default 30) with `$Char(0)` sentinel normalization, computes ISO-8601 UTC cutoff via `$ZTimeStamp` (NOT `$Horolog`), and DELETEs `Chat.History` rows via parameterized prepared SQL with `%EXACT()` discipline. Defensive surface per Rule 8 §"Defensive-surface enumeration": `SQLCODE` checked post-`%Execute`, values other than 0/100 propagate as `$$$Status`. First line `Set tSC = $$$OK`, last line `Quit tSC`, audit emission outside any TSTART/TCOMMIT block.

**AC-2 verification (UserVocabularyDecay).** Class compiles clean; declares `Parameter DecayConfidenceThreshold = 0.2` and `Parameter DecayLastUsedDays = 90`. `OnTask()` DELETEs `UserVocabulary` rows with `Confidence < ..#DecayConfidenceThreshold AND %EXACT(LastUsed) < cutoffIso` via parameterized prepared SQL. Same defensive surface + project-rule discipline.

**AC-3 verification (audit-event triple registration).** Both triples already registered:
- `Security.Events.Exists("SessionAgent","TaskRun","PurgeStaleSearchChat") = 1`
- `Security.Events.Exists("SessionAgent","TaskRun","UserVocabularyDecay") = 1`

**AC-4 verification (Installer scheduling — idempotent).** Verbatim `iris_task_list` envelope shows both tasks scheduled at expected cadence:

| ID | Name | Schedule | Next Run | Description (truncated at MAXLEN=100) | Namespace |
|----|------|----------|----------|---------------------------------------|-----------|
| 1010 | `SessionAgent.PurgeStaleSearchChat` | Once at 03:00:00 (Daily) | 2026-05-08 | `Scheduled sweep task that deletes Search-keyed SessionAgent.Chat.History rows older than the configu` | `HSCUSTOM` |
| 1011 | `SessionAgent.UserVocabularyDecay` | Once at 04:00:00 (Weekly Sunday) | **2026-05-10** (Sunday) | `Scheduled sweep task that deletes low-confidence stale rows from SessionAgent.Search.UserVocabulary.` | `HSCUSTOM` |

Description columns are operator-readable (per Rule 7 §"Operator-observable surface enumeration"); the `StripDocMarkup` helper added in Story 8.0 successfully converted the class-level `///` doc-comments' HTML markup to plain prose. Schedule-cadence assertion: ID 1011 next runs on **Sunday 2026-05-10** confirming weekly Sunday default (Story 1.5's `ScheduleTaskIfClassExists` `TimePeriodDay=1`).

**AC-5 verification (six tests).** Verbatim per-method roster from `%UnitTest_Result.TestMethod` against the latest run:

| Method | Status |
|---|---|
| `TestPurgeStaleSearchChatAuditEvent` | 1 (PASS) |
| `TestPurgeStaleSearchChatDeletesStaleRows` | 1 (PASS) |
| `TestPurgeStaleSearchChatRetentionDaysFromConfig` | 1 (PASS) |
| `TestUserVocabularyDecayAuditEvent` | 1 (PASS) |
| `TestUserVocabularyDecayDeletesStaleRows` | 1 (PASS) |
| `TestUserVocabularyDecayThresholdBoundary` | 1 (PASS) |

`SweepTaskTest = 6/6 PASS`. (The `iris_execute_tests` MCP envelope reported only `total:1` due to truncation — the SQL probe is the ground-truth source per Rule 6 / `object-script-testing.md` §"SQL-probe-as-ground-truth for test-pass verification".)

**AC-6 verification (compile + tests + regression intact).** Canonical numerical-MAX SQL probe against `%UnitTest_Result.TestMethod` (joined to `TestCase` via numeric run-id extraction `$PIECE(ID,'||',1)+0` to avoid lex-MAX drift):

```
Total=404, Passed=404, Failed=0
```

Exact match to expected baseline `398 + 6 = 404`. Zero regressions; all six new tests recorded with `Status=1`.

**AC-7 verification (live integration smoke — Rule 11).** `OnTask()` on both task classes was invoked live during the `SweepTaskTest` test run (six invocations through `##class(...).%New().OnTask()` — the canonical instance-method dispatch path matching `%SYS.Task.Definition`'s contract). Verbatim audit-event evidence captured via `iris_audit_events` after the test suite ran (timestamps 2026-05-07 17:08):

```
2026-05-07 17:08:18.428  SessionAgent/TaskRun/UserVocabularyDecay     {"rows_deleted":1,"threshold":"0.2","last_used_days":90,"cutoff_iso":"2026-02-07T00:08:18Z","scan_time_ms":0}
2026-05-07 17:08:18.425  SessionAgent/TaskRun/UserVocabularyDecay     {"rows_deleted":10,"threshold":"0.2","last_used_days":90,"cutoff_iso":"2026-02-07T00:08:18Z","scan_time_ms":0}
2026-05-07 17:08:18.155  SessionAgent/TaskRun/UserVocabularyDecay     {"rows_deleted":0,"threshold":"0.2","last_used_days":90,"cutoff_iso":"2026-02-07T00:08:18Z","scan_time_ms":37}
2026-05-07 17:08:17.994  SessionAgent/TaskRun/PurgeStaleSearchChat    {"rows_deleted":2,"retention_days":14,"cutoff_iso":"2026-04-24T00:08:17Z","scan_time_ms":0}
2026-05-07 17:08:17.992  SessionAgent/TaskRun/PurgeStaleSearchChat    {"rows_deleted":50,"retention_days":30,"cutoff_iso":"2026-04-08T00:08:17Z","scan_time_ms":1}
2026-05-07 17:08:17.768  SessionAgent/TaskRun/PurgeStaleSearchChat    {"rows_deleted":0,"retention_days":30,"cutoff_iso":"2026-04-08T00:08:17Z","scan_time_ms":51}
```

Six audit rows landed with the operator-readable JSON payload (`rows_deleted`, `retention_days`/`threshold`/`last_used_days`, `cutoff_iso`, `scan_time_ms`) per AC-1/AC-2 contract. Each row's status return was `$$$OK` (the test asserted `$$$AssertStatusOK(tSC, ...)` after each invocation and all 6 tests passed).

**AC-8 verification (operator-observable surface — Rule 7).** Both bullets per Story 8.0 / Epic 7 retro AI-3 captured verbatim above:
1. `iris_task_list` envelope (AC-4 table) — IDs 1010 + 1011 with non-empty Description columns.
2. `iris_audit_events` envelope (AC-7 listing) — both `(SessionAgent, TaskRun, PurgeStaleSearchChat)` and `(SessionAgent, TaskRun, UserVocabularyDecay)` triples landing with non-empty operator-readable JSON description fields.

**AC-9 verification (deferred-work.md re-bind).** `LOW-9.3-F02` Owner line replaced verbatim with the Story 10.9 re-bind text per AC-9. Confirmed via `grep -n "Story 10.9" deferred-work.md` — the new owner line is now present and Story 10.9 inherits this entry alongside items E/H/I + the AI-5 umbrella per AC-9's "And" clause.

**Project rules honored.**
- Rule 1 (spec ≤ 250 lines): spec file ~225 lines per its own §"Dev Notes" target.
- Rule 2 (no `[x]` without verification): every checkbox above corresponds to verbatim empirical evidence in this Completion Notes section.
- Rule 6 (SQL-probe ground truth): `404/404/0` from canonical numerical-MAX SQL probe is the gating verification.
- Rule 7 (operator-observable surface): both `Description` columns populated; both audit triples populated.
- Rule 8 (defensive-surface enumeration): SQLCODE checked, error-envelope shaping via `$$$ERROR($$$GeneralError, ...)`.
- `Property Test*` shadow-trap rule (Story 7.0 / Epic 6 retro AI-3): all properties on `SweepTaskTest` use non-`Test*` prefix (`FixturePortalUser`, `SavedRetentionDays`).
- `$Char(0)` sentinel rule: applied to the `Config.Agent.SearchChatRetentionDays` read in `PurgeStaleSearchChat:OnTask()`.

### File List

- `c:\git\iris-session-agent\src\SessionAgent\Task\PurgeStaleSearchChat.cls` (NEW)
- `c:\git\iris-session-agent\src\SessionAgent\Task\UserVocabularyDecay.cls` (NEW)
- `c:\git\iris-session-agent\src\SessionAgent\Test\SweepTaskTest.cls` (NEW)
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\deferred-work.md` (LOW-9.3-F02 Owner line re-bound to Story 10.9 per AC-9)
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\10-6-purgestalesearchchat-uservocabularydecay-sweep-tasks.md` (this file — checkboxes flipped, Completion Notes populated, Status → review)
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\sprint-status.yaml` (10-6 backlog → in-progress → review)

**No modifications required to** `Audit/Emit.cls` or `Installer.cls` — Task 0 confirmed both are already wired correctly (Tasks 3 and 4 of this story were no-ops on the live code surface).

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted by lead from epics.md §"Story 10.6" + Story 10.0 AI-4 carry-forward triage. | Lead |
| 2026-05-07 | 1.0 | Implementation complete — 2 task classes + 1 test class added, deferred-work re-bound; 9/9 ACs PASS; 6/6 new tests PASS; regression 404/404/0 (baseline 398 + 6). Tasks 3+4 confirmed pre-wired by Task 0 probe. | Dev |
| 2026-05-07 | 1.1 | Code review complete — 0 HIGH, 0 MEDIUM, 1 LOW deferred (hardcoded storage-hash globals in test cleanup; cosmetic, no bug shape). All 9 ACs verified by reviewer via static read + live SQL probes (404/404/0 regression match; both `%SYS.Task` Description columns populated; both `Security.Events` triples present with operator-readable Description). Status → done. | Reviewer |

### Review Findings

- [x] [Review][Defer] LOW-10.6-F01 — Hardcoded storage-hash globals in `SweepTaskTest` cleanup hooks [`src/SessionAgent/Test/SweepTaskTest.cls`:90-95, 113-118] — deferred, cosmetic / latent fragility, no current bug shape (Rule 8 test #3). See `deferred-work.md` "Deferred from: code review of story-10-6-…" entry.

**Reviewer-side empirical verification (verbatim).**

1. **Regression sweep — canonical numerical-MAX SQL probe** (per `object-script-testing.md` §"SQL-probe-as-ground-truth"):

   ```
   Total=404, Passed=404, Failed=0
   ```

   Exact match to dev's claim (baseline 398 + 6 new = 404).

2. **`%SYS.Task` operator-observable Description column** (live `iris_sql_execute` against `%SYS.Task`):

   | Name | Description (truncated) |
   |---|---|
   | `SessionAgent.PurgeOrphanedChatHistory` | `Scheduled sweep task that deletes Inspection-keyed SessionAgent.Chat.History rows whose SessionKey n…` |
   | `SessionAgent.PurgeStaleSearchChat` | `Scheduled sweep task that deletes Search-keyed SessionAgent.Chat.History rows older than the configu…` |
   | `SessionAgent.UserVocabularyDecay` | `Scheduled sweep task that deletes low-confidence stale rows from SessionAgent.Search.UserVocabulary.` |

   All three Descriptions populated and operator-readable per Rule 7.

3. **`Security.Events` audit triples** (live `iris_sql_execute` against `Security.Events`):

   | Source | Type | Name | Description |
   |---|---|---|---|
   | `SessionAgent` | `TaskRun` | `PurgeOrphanedChatHistory` | `SessionAgent scheduled task: purge orphaned chat history` |
   | `SessionAgent` | `TaskRun` | `PurgeStaleSearchChat` | `SessionAgent scheduled task: purge stale search chat` |
   | `SessionAgent` | `TaskRun` | `UserVocabularyDecay` | `SessionAgent scheduled task: user vocabulary decay` |

   All three triples registered with operator-readable Description per AC-3 + AC-8.

4. **Tasks 3+4 no-op claim verified.** `src/SessionAgent/Audit/Emit.cls` lines 60-61 already register both new triples (`(SessionAgent, TaskRun, PurgeStaleSearchChat)` + `(SessionAgent, TaskRun, UserVocabularyDecay)`); `src/SessionAgent/Test/AuditEmitTest.cls` lines 59-60 already assert both. `src/SessionAgent/Installer.cls` lines 110-112 wire all three sweep schedules; `ScheduleTaskIfClassExists` lines 392-394 implement Weekly with `TimePeriod=1, TimePeriodDay=1` (Sunday). Dev's "Tasks 3+4 already shipped" claim is **correct** — no edits required to those files.

5. **Project rules cross-check.**
   - `$Char(0)` sentinel: applied at `PurgeStaleSearchChat.cls:117-118` (the `Config.Agent.SearchChatRetentionDays` read site). ✓
   - `$ZTimeStamp` (UTC) used, not `$Horolog`. ✓
   - First line `Set tSC = $$$OK`, last line `Quit tSC` — both task classes. ✓
   - Argumentless `Quit` inside Try/Catch — both task classes. ✓
   - Audit emission outside any TSTART/TCOMMIT block — both task classes. ✓
   - Defensive surface: `SQLCODE` checked post-`%Execute`; non-0/100 propagates as `$$$ERROR($$$GeneralError, ...)` with operator-readable text — both task classes. ✓
   - `Property Test*` shadow-trap rule: properties named `FixturePortalUser` + `SavedRetentionDays`; no `Test*` prefix on state properties. ✓
   - `%OnNew(initvalue)` calls `##super(initvalue)`; no `Private` keyword. ✓
   - `%EXACT()` discipline on string-column predicates. ✓
   - Test class size: 379 lines (under 500-line cap). ✓

**Result:** All 9 ACs verified. 0 HIGH, 0 MEDIUM, 1 LOW deferred. Story 10.6 ready to ship.
