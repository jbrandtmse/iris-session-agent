# Story 1.5: Installer Scaffold + `Install` Method

Status: review

## Story

As an **Operator-Admin**,
I want `SessionAgent.Installer.Install()` to orchestrate audit-event pre-registration, RBAC role install, Mgmt Portal bookmark printing, sweep-task scheduling, and operator-reminder printing in a single idempotent install hook,
so that `zpm install iris-session-agent` is a single command that produces a fully-prepared installation (FR48, NFR-R5).

This story closes Epic 1's install-time wiring loop: it ships the orchestrator that connects Stories 1.3 (`Audit.Emit.EnsureEvents`) and 1.4 (`Security.ReadOnlyRole.Install`), provides forward-compatible scaffolding for Stories 7.2 / 10.6 (sweep tasks) and Story 2.4 (`Config.Agent` seeding), and uncomments the three `<Invoke>` hooks in `module.xml` so `zpm load` runs all install-time work in a single command.

## Acceptance Criteria

ACs are mapped 1:1 to the three AC groups in [epics.md Story 1.5](../../_bmad-output/planning-artifacts/epics.md) (lines 621–648). Each AC below cites the originating epic clause.

**AC-1 — `SessionAgent.Installer.Install(pVars) As %Status` orchestrates audit + RBAC + helpers, propagating errors via `%Status`.** *(epic clause 1)*

The method:

- Saves `$NAMESPACE` to `tOrigNS` (explicit save/restore; never `New $NAMESPACE`)
- Calls `##class(SessionAgent.Audit.Emit).EnsureEvents()` — error propagated via `%Status`
- Calls `##class(SessionAgent.Security.ReadOnlyRole).Install()` — error propagated
- Calls private helper `..PrintOperatorReminders()` (writes both bookmark URL patterns + README pointer to install log)
- Calls private helper `..ScheduleTaskIfClassExists(taskName, classFullName, frequency, hour, minute)` for each of three task entries — defensive (logs and continues if class missing)
- Calls private helper `..SeedDefaultAgentConfigs()` — defensive (logs and continues if `SessionAgent.Config.Agent` missing)
- Catch block restores `$NAMESPACE` as **first line**
- Returns `%Status` (argumented `Quit tSC` outside try/catch)
- Method signature exactly: `ClassMethod Install(pVars) As %Status` (matches IPM `<Invoke>` contract; `pVars` accepted but unused in v1)

**AC-2 — `PrintOperatorReminders()` writes BOTH bookmark URL patterns + README pointer with the actual current namespace substituted.** *(epic clause 2)*

Install log contains, after a header:

- HealthShare bookmark URLs: `/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen` with `<NS>` = actual `$NAMESPACE` at install time (e.g., `HSCUSTOM`)
- Plain-IRIS bookmark URLs: `/csp/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`
- One-line README pointer: *"See README ""Operator Prerequisites"" for one-time setup (Web Gateway timeout 60→300, RBAC role assignment, API key supply)."*
- Closing footer line

**AC-3 — `ScheduleTaskIfClassExists` is defensive AND idempotent.** *(epic clause 1, sweep-task sub-clause + clause 3 dedup)*

For each `(SessionAgent.PurgeOrphanedChatHistory|PurgeStaleSearchChat|UserVocabularyDecay, SessionAgent.Task.<className>, frequency, hour, minute)` triple:

- Defensive class check via `##class(%Dictionary.ClassDefinition).%ExistsId(classFullName)`. If the class is absent: log `<className> not yet implemented; sweep deferred` and return `$$$OK`.
- Idempotent task-Name dedup via SQL `SELECT ID FROM %SYS.Task WHERE Name = ?` BEFORE `%Save()`. (Per Task 0 Probe 3 below: `%SYS.Task` does **NOT** enforce `Name` uniqueness — a naive re-save creates a duplicate row with a different ID.)
- On creation: switches to `%SYS`, sets `Name`, `NameSpace=tCallerNS`, `TaskClass`, frequency-derived `TimePeriod` / `TimePeriodEvery` / `TimePeriodDay`, `DailyFrequency=0`, `DailyStartTime` = `(hour*3600 + minute*60)`. Restores namespace at the end.
- Always returns `$$$OK` in v1 — failure modes log to install log but do not propagate.

**AC-4 — `SeedDefaultAgentConfigs` is defensive against missing `SessionAgent.Config.Agent`.** *(epic clause 1, Config.Agent sub-clause)*

- Defensive class check via `%Dictionary.ClassDefinition.%ExistsId("SessionAgent.Config.Agent")`. If absent: log `SessionAgent.Config.Agent not yet implemented; default configs deferred` and return `$$$OK`.
- When the class IS present (Story 2.4+), the helper seeds two rows (`session-inspection`, `message-search`) with `Provider='openai'`, `Model='gpt-4o'`, `MaxTokens=4096`, `Temperature=0.0`, `ReadOnly=1`, `EnvVarName='OPENAI_API_KEY'`, `Enabled=0` — idempotent via `%ExistsId(agentName)` per row. Story 1.5 ships only the defensive shell + one log line; the row-insert body is deferred to Story 2.4 schema land (since Config.Agent's actual property set is owned by 2.4).

**AC-5 — `module.xml` `<Invoke>` lines are uncommented atomically with this story.** *(implicit in epic clause 2)*

All three `<Invoke>` lines active:

```xml
<Invoke Method="Install" Class="SessionAgent.Installer"/>
<Invoke Method="EnsureEvents" Class="SessionAgent.Audit.Emit"/>
<Invoke Method="Install" Class="SessionAgent.Security.ReadOnlyRole"/>
```

The Story 1.1 inline placeholder comment is replaced with a brief line noting Story 1.5 activated the hooks.

**AC-6 — `zpm load` succeeds end-to-end on first install AND on idempotent reinstall.** *(epic clauses 2 + 3)*

First install: all three hooks execute in order without error, install log contains both bookmark URL patterns + reminder + three "deferred" lines (sweep tasks) + one "deferred" line (Config.Agent), exit status 0.

Second install (idempotent reinstall per NFR-R5): no duplicate audit registrations, no duplicate RBAC role grants, no duplicate task entries (the SQL dedup handles this even though `%SYS.Task` does not), no duplicate Config.Agent rows. Returns `$$$OK`.

**AC-7 — Clean compile; full regression suite pass; no `[Language = python]` references.** *(implicit invariants)*

`SessionAgent.Installer` compiles to status 0. `iris_execute_tests` against `SessionAgent.Test` (package level) returns ≥9/9 (3 audit + 6 RBAC, no regressions). `grep -r "Language = python" src/SessionAgent/` returns zero matches.

## Tasks / Subtasks

- [x] **Task 0 — Probe `%SYS.Task` API + `%Dictionary.ClassDefinition.%ExistsId` (AC: #3, #4)**
  - [x] Probe `%Dictionary.ClassDefinition.%ExistsId` against existing + missing classes
  - [x] Probe `%SYS.Task` canonical creation shape via class-dictionary inspection
  - [x] Probe `%SYS.Task` dedup behavior: confirmed naive re-save creates duplicates → explicit SQL existence check is required
  - [x] Probe transcript saved to `_bmad-output/implementation-artifacts/probes/story-1-5-installer-api-probe-2026-05-02.txt`

- [x] **Task 1 — Create `src/SessionAgent/Installer.cls` (AC: #1, #2, #3, #4)**
  - [x] Class extends `%RegisteredObject`
  - [x] `ClassMethod Install(pVars) As %Status` with explicit `tOrigNS` save/restore, catch-block restoring `$NAMESPACE` as first line, argumentless `Quit` inside try/catch + argumented `Quit tSC` outside
  - [x] `ScheduleTaskIfClassExists` private helper with class-existence guard + SQL Name-dedup guard
  - [x] `SeedDefaultAgentConfigs` private helper with class-existence guard (row-seed body deferred to Story 2.4)
  - [x] `PrintOperatorReminders` private helper writing both bookmark URL patterns with substituted `$NAMESPACE`
  - [x] `LogProgress` private helper with `[iris-session-agent]` prefix
  - [x] `Parameter TARGETNAMESPACE = "HSCUSTOM"` for `%SYS`-caller resilience (see Dev Notes)

- [x] **Task 2 — Update `module.xml` to uncomment the three `<Invoke>` lines (AC: #5)**
  - [x] All three `<Invoke>` lines now active
  - [x] Story 1.1 placeholder comment replaced with a one-line "activated in Story 1.5" note

- [x] **Task 3 — `%SYS`-caller resilience patch in `ReadOnlyRole.cls` (cross-story finding)**
  - [x] Added namespace-fallback at the top of `ReadOnlyRole.Install()`: when invoked from `%SYS`, target `HSCUSTOM` for the SQL grant phase. Without this patch, the IPM `<Invoke>` of `Security.ReadOnlyRole.Install` would fail with SQLCODE -30 because `Ens.*` tables aren't projected in `%SYS`.

- [x] **Task 4 — End-to-end verification (AC: #6, #7)**
  - [x] **`zpm load c:/git/iris-session-agent` from HSCUSTOM SUCCEEDS end-to-end** — all six lifecycle phases SUCCESS (Initialize / Reload / Validate / Compile / Configure / Activate). Configure phase fires the orchestrator: 3× sweep "deferred" + 1× Config.Agent "deferred" + bookmark URLs (HSCUSTOM substituted) + README pointer. The single warning emitted (`<CSPApplication>` tag deprecation) is informational, NOT a parse error.
  - [x] **Idempotency verified** — second `zpm load` run produces identical SUCCESS output across all six phases. No duplicates introduced.
  - [x] **`%SYS`-caller resilience path verified separately** — direct `Installer.Install("")` from `%SYS` detects the caller, switches to HSCUSTOM target, returns `$$$OK`, restores `$NAMESPACE` to `%SYS` on exit. Provides defense-in-depth for operators who run the install hooks via mechanisms other than `zpm load` from a target namespace.
  - [x] **Full regression suite 9/9 pass** — `SessionAgent.Test` package level (3 audit + 6 RBAC tests).
  - [x] **Zero `[Language = python]` references** — `Grep "Language = python" src/SessionAgent` → 0 matches.

  **Pre-flight gotcha worth recording:** the first `zpm load` attempt errored with `<CLASS DOES NOT EXIST>DisplayError *%IPM.Repo.UniversalSettings`. **Root cause was operator-environment state**, NOT story logic: IPM was installed in `%SYS` (Story 1.1 dev's bootstrap, version 0.10.6, complete and intact) but had not been **enabled and mapped into HSCUSTOM**. The Configure phase context-switches into the install target namespace, where `%IPM.*` classes weren't visible. Single-line fix from `%SYS`: `zpm "enable -map -globally"`. This finding is propagated into [README §"Operator Prerequisites"](../../README.md) as a structural prerequisite step (per `research-first.md` rule 5: operator-observable state must ride the commit).

## Task 0 Output

```
%Dictionary.ClassDefinition.%ExistsId:
  - Existing class (SessionAgent.Audit.Emit) → 1
  - Missing class  (SessionAgent.Config.Agent / SessionAgent.Task.*) → 0

%SYS.Task properties used:
  Name (NOT unique on its own)
  NameSpace
  TaskClass
  TimePeriod (0=DAILY, 1=WEEKLY)
  TimePeriodEvery (every-N interval)
  TimePeriodDay (Sunday=1 for WEEKLY)
  DailyFrequency (0=ONCE-per-day)
  DailyStartTime ($H seconds-since-midnight)

%SYS.Task dedup strategy:
  Confirmed: %SYS.Task does NOT enforce Name uniqueness. Naive re-save creates
  duplicate rows with different IDs. ScheduleTaskIfClassExists therefore uses
  explicit SQL check (SELECT ID FROM %SYS.Task WHERE Name = ?) before %Save().

Probe transcript:
  _bmad-output/implementation-artifacts/probes/story-1-5-installer-api-probe-2026-05-02.txt
```

## Dev Notes

### `%SYS`-caller resilience (cross-story finding requiring Story 1.4 patch)

When IPM runs the three `<Invoke>` hooks from `module.xml`, each invocation may execute with `$NAMESPACE = "%SYS"` rather than the install target namespace (`HSCUSTOM`). Two consequences:

1. **`Installer.Install`** must detect the `%SYS` caller and switch to `Parameter TARGETNAMESPACE` (default `HSCUSTOM`) before delegating to `ReadOnlyRole.Install()`. Otherwise the chained call's GRANT step fails with SQLCODE -30 because `Ens.*` tables aren't projected in `%SYS`. The orchestrator handles this at the top of its try block.

2. **`ReadOnlyRole.Install` must also handle the `%SYS` caller directly** — because `module.xml` has a separate `<Invoke>` for `Security.ReadOnlyRole.Install` that runs independently of the orchestrator. The fallback patch (`If tOrigNS = "%SYS" Set tOrigNS = "HSCUSTOM"`) is added in `ReadOnlyRole.cls` lines 73–86 as part of this story.

This is a Story 1.4 patch riding on the Story 1.5 commit because it was discovered during Story 1.5's end-to-end zpm-load verification, not during Story 1.4's standalone testing. Logged in deferred-work.md.

### Defensive helpers — why two checks in `ScheduleTaskIfClassExists`

`ScheduleTaskIfClassExists` does **two** independent guards: (a) class exists in dictionary, (b) task with same `Name` doesn't already exist in `%SYS.Task`. Per Task 0 Probe 3, `%SYS.Task` does NOT enforce `Name` uniqueness — a naive re-save creates a duplicate row with a different ID. Without guard (b), every reinstall would pile up phantom task entries. The chosen pattern: SQL `SELECT TOP 1 ID FROM %SYS.Task WHERE Name = ?` returns 1 row → skip insert; 0 rows → insert.

### Why the row-seed body in `SeedDefaultAgentConfigs` is deferred to Story 2.4

`SessionAgent.Config.Agent` doesn't exist yet — it ships in Story 2.4. The class's exact property set (column names, types, defaults) is owned by that story. If Story 1.5 hard-codes a row-insert with assumed property names, Story 2.4 would either have to match Story 1.5's assumptions exactly (constraining the schema design) or rewrite the helper. Cleaner: Story 1.5 ships the defensive shell + a single "seeding deferred to Story 2.4" log line; Story 2.4 adds the row-insert body when it lands the class.

### Dev tooling: auto-sync workflow active for this story

Per the `chore: enable VSCode ObjectScript auto-sync` commit (`fe6277c`):
- `.vscode/settings.json` enables `objectscript.conn.active=true` against `local` server / `HSCUSTOM`
- `objectscript.syncLocalChanges=all` pushes saved files to IRIS automatically
- Dev workflow: Edit/Write → no `iris_doc_load` needed → `iris_doc_compile` to verify clean compile → `iris_execute_tests` for regression
- Higher-level MCPs preferred over `iris_execute_command` where a typed alternative exists (see `.claude/rules/iris-objectscript-basics.md` §"VSCode Auto-Sync Workflow")

### Project rule citations (live in code, not duplicated here)

- `iris-objectscript-basics.md`: `$$$OK` triple-dollar; explicit `$NAMESPACE` save/restore; argumented `Quit` outside try/catch; catch first-line namespace restore; `///` doc-comments
- `research-first.md`: Task 0 backend-surface probe (executed; transcript saved)
- `object-script-testing.md`: N/A for this story (no new test class; integration test = end-to-end zpm load)

### File List

NEW:
- `src/SessionAgent/Installer.cls`
- `_bmad-output/implementation-artifacts/probes/story-1-5-installer-api-probe-2026-05-02.txt`

UPDATE:
- `module.xml` — uncommented the three `<Invoke>` lines
- `src/SessionAgent/Security/ReadOnlyRole.cls` — added `%SYS`-caller resilience patch
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `1-5-...` flipped to `review`

### References

- [epics.md Epic 1 §Story 1.5](../../_bmad-output/planning-artifacts/epics.md) lines 621–648 — original AC source
- [research §"`SessionAgent.Installer.Install()` — Install-Time Work"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) lines 1036–1122 — reference shape (adapted for defensive helpers)
- [.claude/rules/iris-objectscript-basics.md §"VSCode Auto-Sync Workflow"](../../.claude/rules/iris-objectscript-basics.md) — workflow active for this story
- Probe transcript: `_bmad-output/implementation-artifacts/probes/story-1-5-installer-api-probe-2026-05-02.txt`

## Dev Agent Record

### Agent Model Used

Joshua Brandt (manual implementation; no dev agent spawned for this story)

### Completion Notes

- The user implemented this story manually after pausing the autonomous pipeline to address two concerns: (1) over-prescriptive story specs burning tokens, (2) over-use of `iris_execute_command` when typed MCPs exist. Both concerns prompted the workflow infrastructure changes shipped in commit `fe6277c`.
- The `%SYS`-caller resilience finding is genuine and important — it would have surfaced the first time an operator ran `zpm install` from a `%SYS` shell. The patch ships in this story rather than in a separate Story 1.4a.
- Defensive helpers' "deferred" log lines are intentional and informative — they tell the operator what's expected to land in later epics rather than appearing as silent gaps.
- **`zpm load` end-to-end test PASSED after fixing operator-environment state** (`zpm "enable -map -globally"` from `%SYS`). The orchestrator's Configure phase context-switches into the install target namespace (HSCUSTOM), and prior to the enable-globally step, HSCUSTOM had no mapping to the `%IPM.*` classes living in `%SYS` — the missing-class error masked the actual cause. After `enable -map -globally`, the load succeeds end-to-end across all six IPM lifecycle phases on first install AND on idempotent reinstall.
- **The enable-globally step is now documented in README §"Operator Prerequisites" §1** as part of Story 1.5's commit, per `research-first.md` rule 5 (operator-observable state must ride the commit). Operators on a fresh IRIS for Health 2024.1+ install would have hit the same wall; the README change preempts that.

### Verification evidence (run from this lead conversation, not from a dev agent)

```
zpm load (HSCUSTOM, after `zpm "enable -map -globally"` was run from %SYS):
  Initialize SUCCESS / Reload SUCCESS / Validate SUCCESS / Compile SUCCESS /
  Configure SUCCESS / Activate SUCCESS
  Configure phase printed: 3× sweep deferred, 1× Config.Agent deferred, 4× bookmark
  URLs (HSCUSTOM substituted), README pointer. One informational warning about the
  deprecated <CSPApplication> tag (not a parse error).

zpm load idempotent reinstall (HSCUSTOM, second run):
  Identical SUCCESS output across all six lifecycle phases. No duplicates.

Direct Installer.Install("") from %SYS (resilience-patch verification):
  First log: "[iris-session-agent] Detected %SYS caller; switching to install
  target namespace HSCUSTOM"
  Returns $$$OK. Final $NAMESPACE: %SYS (correctly restored on exit).

Full regression: SessionAgent.Test package level — 9/9 pass
  AuditEmitTest:    EnsureEventsIdempotent, EnsureEventsRegistersAllEleven, EnsureEventsRestoresNamespace
  ReadOnlyRoleTest: RoleInstallCreates, RoleInstallIdempotent, RestoresNamespace,
                    PrivilegeEnforcementSelectSucceeds, PrivilegeEnforcementInsertFails,
                    PrivilegeEnforcementDeleteFails

NFR-C2: 0 [Language = python] matches under src/SessionAgent/
```
