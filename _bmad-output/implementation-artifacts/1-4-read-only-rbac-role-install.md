# Story 1.4: Read-Only RBAC Role Install

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an **Operator-Admin**,
I want the install process to create the `%SessionAgent_ReadOnly` RBAC role with **SELECT-only** grants on `Ens.*` tables, idempotent across reinstalls,
so that the agent's read-only invariant has structural enforcement at the IRIS database privilege layer (NFR-S1 Layer 3, FR50).

This is **Layer 3** of the three-layer read-only enforcement architecture (per [PRD NFR-S1](../../_bmad-output/planning-artifacts/prd.md) + [architecture.md line 112](../../_bmad-output/planning-artifacts/architecture.md)). Layers 1 and 2 are code/dispatch — they live entirely inside the agent's process. Layer 3 lives at the **IRIS database privilege layer** — it survives an agent code bug, a misconfigured `MutatesState=0` flag, or any future refactor that omits the L1/L2 checks. *"Each layer alone is fragile; only the stack survives an L1 oversight or an L2 misconfiguration."* ([research §"Top Findings" #6](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md))

## Acceptance Criteria

**AC-1 — `SessionAgent.Security.ReadOnlyRole.Install()` creates the role idempotently in `%SYS`.**

**Given** the developer is implementing `SessionAgent.Security.ReadOnlyRole`
**When** they implement the `Install()` class method
**Then** the method switches to `%SYS` namespace using the **explicit save/restore pattern** (per project rule [§"Namespace Switching"](../../.claude/rules/iris-objectscript-basics.md)). **Never** `New $NAMESPACE`. Catch block restores `$NAMESPACE` as its first line.
**And** if the `%SessionAgent_ReadOnly` role does NOT exist (verified via `Security.Roles.Exists("%SessionAgent_ReadOnly")` — exact API name to be confirmed in Task 0), the method calls `Security.Roles.Create("%SessionAgent_ReadOnly", "Read-only access to Ens.* tables for iris-session-agent", "")` per IRIS 2024.1 `Security.Roles` API.
**And** the method returns `%Status` per project convention (`Set tSC = $$$OK` first, `Quit tSC` last).

**AC-2 — SELECT grants on the canonical Ens.* surfaces, no other privileges.**

**Given** `Install()` has created the role
**When** the method continues into the GRANT phase
**Then** the role has SELECT (and ONLY SELECT) granted on at minimum these tables:

- `Ens.MessageHeader` (FR31, NFR-S1 — primary session-trace surface)
- `Ens.Util.Log` (FR5 EventLog tool, Epic 4)
- `Ens.Rule.Log` (FR6 RuleLog tool, Epic 4)
- `Ens.SuperSessionIndex` (FR8 FindRelatedSessions tool, Epic 4)
- `Ens_Util.Log` and `Ens_Rule.Log` SQL projection names if those differ from the dot-form (some IRIS namespaces project rule/util classes under `Ens_*` SQL names — verify in Task 0)

**And** the role has explicit **NO** privileges on INSERT, UPDATE, DELETE, REFERENCES, or any DDL on these tables — verified via `Test/ReadOnlyRoleTest.cls` (AC-5).
**And** the GRANT statements use `%SQL.Statement` (or `$SYSTEM.SQL.Security.GrantPrivilege` — verify which API actually exists per `irislib/%SYSTEM/SQL/Security.cls` and Task 0).
**And** if a body-class projection table needs to be added in a later epic, the design accommodates it — leave a comment in `ReadOnlyRole.cls` noting *"body-class SELECT grants land in Epic 4 Story 4.2 GetMessageBody dispatch ladder."*

**AC-3 — Idempotent reinstall.**

**Given** the install has run once and `%SessionAgent_ReadOnly` exists with SELECT grants
**When** `Install()` runs again (per NFR-R5 idempotent reinstall)
**Then** the role is **not duplicated** (Exists check skips Create).
**And** the GRANT statements are idempotent — re-granting an already-granted privilege either succeeds silently or is wrapped in an Exists check (verify in Task 0 which behavior IRIS exhibits; pick the one that produces no error). If `GRANT` errors on an already-granted privilege, wrap it in a `try/catch` that swallows that specific error code and propagates everything else.
**And** the second invocation completes with `$$$OK`.

**AC-4 — `module.xml` `<Invoke>` line stays commented out for this story.**

**Given** Story 1.5 owns the orchestrator
**When** Story 1.4 ships `ReadOnlyRole.cls`
**Then** `module.xml`'s `<Invoke Method="Install" Class="SessionAgent.Security.ReadOnlyRole"/>` line **stays commented out**.
**And** the developer manually invokes `Do ##class(SessionAgent.Security.ReadOnlyRole).Install()` via `iris_execute_command` to verify end-to-end behavior — captured in Completion Notes.

**AC-5 — Integration test verifies privilege enforcement end-to-end.**

**Given** the developer creates `src/SessionAgent/Test/ReadOnlyRoleTest.cls` extending `%UnitTest.TestCase`
**When** the test class compiles and runs via `iris_execute_tests`
**Then** the test:

1. **Creates a throwaway test user** (e.g., `testReadOnlyUser` with a known password — `Security.Users.Create()` per `irislib/%SYSTEM/Security.cls`).
2. **Grants `%SessionAgent_ReadOnly`** to that user (`Security.Users.GrantRole()` or equivalent — verify in Task 0).
3. **Validates the user's credentials** (`Security.Users.CheckPassword()` — NEVER `$System.Security.Login()` per [project rule §"IRIS Library Source"](../../.claude/rules/iris-objectscript-basics.md): *"`$System.Security.Login()` switches process context — never use for credential validation"*).
4. **Attempts an INSERT against `Ens.MessageHeader`** while bound to the test user's role membership — must FAIL with `<PROTECT>` privilege error or SQLCODE -99.
5. **Attempts a DELETE against `Ens.MessageHeader`** — must FAIL similarly.
6. **Attempts a SELECT against `Ens.MessageHeader`** — must SUCCEED for the same user/role combination.
7. **Cleans up** in `OnAfterOneTest` or a teardown helper: removes the role grant, deletes the test user. The test must NOT leave artifacts behind.

**And** the test class follows project rule [§"Critical Constructor Requirements"](../../.claude/rules/object-script-testing.md): `%OnNew(initvalue)` accepts `initvalue` and calls `##super(initvalue)`. NO `Private` keyword.
**And** the test class is ≤ 500 lines per project rule §"Test Class Size".

**AC-6 — Compile cleanly with `zpm load`; tests pass; no `[Language = python]` references.**

**Given** the new files are committed
**When** `zpm load /path/to/repo` runs
**Then** `SessionAgent.Security.ReadOnlyRole` and `SessionAgent.Test.ReadOnlyRoleTest` both compile to status 0.
**And** `iris_execute_tests` against `SessionAgent.Test.ReadOnlyRoleTest` returns all-pass.
**And** `grep -r "Language = python" src/SessionAgent/` returns zero matches.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight: probe `Security.Roles`, `Security.Users`, and SQL GRANT APIs on the live IRIS (AC: #1, #2, #5)**
  - [x] **Probe Security.Roles API:** Run `Do ##class(Security.Roles).Help()` (in `%SYS` namespace) via `iris_execute_command`. Capture: signature of `Create`, `Exists`, `Delete`, plus how grants are managed (in-class methods or via SQL GRANT).
  - [x] **Probe Security.Users API:** Same — `Do ##class(Security.Users).Help()`. Capture: signature of `Create`, `Delete`, `GrantRole` (or whatever method adds a role membership), `CheckPassword`.
  - [x] **Probe `irislib/%SYSTEM/SQL/Security.cls`** with `Read` to determine the canonical `GrantPrivilege` API. Per [CLAUDE.md §"IRIS Library Source"](../../.claude/rules/iris-objectscript-basics.md), this is mandatory before using the API.
  - [x] **Probe SQL GRANT idempotency** by attempting two consecutive `GRANT SELECT ON Ens.MessageHeader TO %SessionAgent_ReadOnly`-style executions through `%SQL.Statement` — capture whether the second one errors or succeeds silently.
  - [x] Record all four probes' verbatim output in this story's **Task 0 Output** section. Save the full transcript to `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt`.

- [x] **Task 1 — Create `src/SessionAgent/Security/` package directory + `ReadOnlyRole.cls` (AC: #1, #2, #3)**
  - [x] `mkdir -p src/SessionAgent/Security`
  - [x] Create `src/SessionAgent/Security/ReadOnlyRole.cls` extending `%RegisteredObject`. Class definition:

    ```objectscript
    /// <p>Layer-3 RBAC installer. Creates the <code>%SessionAgent_ReadOnly</code>
    /// role and grants SELECT-only on the canonical <code>Ens.*</code> tables
    /// the agent reads.</p>
    ///
    /// <p>This is the third layer of the read-only enforcement stack
    /// (PRD NFR-S1, FR50). Layers 1 (code discipline per tool) and 2
    /// (Tool.Registry.Dispatch MutatesState=0 gate) live inside the agent's
    /// process; this layer survives an L1/L2 oversight by enforcing
    /// privilege at the IRIS database layer.</p>
    Class SessionAgent.Security.ReadOnlyRole Extends %RegisteredObject
    {

    /// Idempotent install: create the role if absent, grant SELECT on
    /// canonical Ens.* tables. Safe to call on every IPM install / upgrade.
    ClassMethod Install() As %Status
    {
        Set tSC = $$$OK
        Set tOrigNS = $NAMESPACE
        Try {
            Set $NAMESPACE = "%SYS"

            ; (1) create role if absent
            If '##class(Security.Roles).Exists("%SessionAgent_ReadOnly") {
                Set tSC = ##class(Security.Roles).Create(...)
                If $$$ISERR(tSC) Quit
            }

            ; (2) grant SELECT on canonical Ens.* surfaces (idempotent per Task 0 finding)
            ; ... see Task 0 Output for the chosen GRANT mechanism ...

            Set $NAMESPACE = tOrigNS
        }
        Catch ex {
            Set $NAMESPACE = tOrigNS
            Set tSC = ex.AsStatus()
        }
        Quit tSC
    }

    }
    ```

  - [x] Implement the GRANT loop per the Task 0 chosen approach (`%SQL.Statement` GRANT, `$SYSTEM.SQL.Security.GrantPrivilege`, or `Security.Roles` direct API — whichever Task 0 confirms works on 2024.1+).
  - [x] **CRITICAL** project-rule reminders: `$$$OK` triple-dollar; explicit save/restore for `$NAMESPACE`; argumented `Quit tSC` ONLY outside try/catch; argumentless `Quit` inside try/catch. Catch block's first line restores `$NAMESPACE`.
  - [x] Compile via `mcp__iris-dev-mcp__iris_doc_compile`.

- [x] **Task 2 — Create `src/SessionAgent/Test/ReadOnlyRoleTest.cls` (AC: #5)**
  - [x] Test class extends `%UnitTest.TestCase`. Required test methods:
    - `TestRoleInstallCreates` — invoke `Install()` once; assert `Security.Roles.Exists("SessionAgent_ReadOnly")` returns 1.
    - `TestRoleInstallIdempotent` — invoke `Install()` twice; assert second call returns `$$$OK` and role is not duplicated. Then run a SELECT against `Ens.MessageHeader` to confirm no double-grant errors leaked.
    - `TestPrivilegeEnforcementInsertFails` — create test user, grant role, query CheckPrivilege INSERT, assert returns 0.
    - `TestPrivilegeEnforcementDeleteFails` — same shape for DELETE.
    - `TestPrivilegeEnforcementSelectSucceeds` — same setup, query CheckPrivilege SELECT, assert returns 1.
    - `TestRestoresNamespace` — capture `$NAMESPACE` before and after `Install()`; assert unchanged.
  - [x] **Use `Security.Users.CheckPassword()` not `$System.Security.Login()`** for credential validation (per CLAUDE.md rule). [N/A — Approach 4 does not require credential validation; the CheckPrivilege API queries the privilege catalog directly given a username, no login attempt needed.]
  - [x] **Process-context strategy for the privilege-enforcement tests** — Approach 4 (CheckPrivilege synthetic query) selected. Rationale documented in Task 0 Output.
  - [x] Pick the simplest option that genuinely tests the privilege boundary. **Option 4 is acceptable** if Options 1–3 prove difficult on 2024.1, *but* the test method must explicitly note that it's a privilege-query test, not an INSERT-attempt test. Documented in test class doc-comment §"Process-context test strategy".
  - [x] **Cleanup:** `OnAfterOneTest` or per-test teardown removes the test user grant + deletes the test user. The role itself stays (install side-effect).
  - [x] Constructor: `%OnNew(initvalue As %String = "") As %Status` calls `##super(initvalue)`. NO `Private` keyword.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 3 — Run the unit tests via MCP (AC: #5, #6)**
  - [x] Use `mcp__iris-dev-mcp__iris_execute_tests` to run `SessionAgent.Test.ReadOnlyRoleTest`.
  - [x] All test methods pass. Capture the test runner output in Completion Notes.
  - [x] If a privilege-enforcement test fails, **investigate the underlying class** (the role/grants probably aren't being created correctly) — do NOT modify the test to make it pass. [N/A — all tests passed first attempt.]

- [x] **Task 4 — End-to-end verify via `zpm load` + manual invocation (AC: #4, #6)**
  - [x] Run `zpm "load c:/git/iris-session-agent"` via `iris_execute_command`. Confirm the new classes compile and load with status 0.
  - [x] Run `Do ##class(SessionAgent.Security.ReadOnlyRole).Install()` from the **agent runtime namespace** (HSCUSTOM, where Ens.* tables live). Confirm `$$$OK`. **Note (deviation from original story wording):** the story said "in %SYS" but Install grants on Ens.* tables which exist in HSCUSTOM, not %SYS. From %SYS the GRANT step fails with SQLCODE -30 "Table or view not found" because Ens.* tables aren't projected in %SYS. The correct invocation is from the agent's runtime namespace, which is also what the production ZPM `<Invoke>` hook will do. Documented in Completion Notes.
  - [x] Run `Write ##class(Security.Roles).Exists("SessionAgent_ReadOnly")` (in `%SYS`). Confirm `1`.
  - [x] Capture all output in Completion Notes.
  - [x] **Cleanup the role from the dev IRIS** if the role survives across test runs and you want a clean baseline. (Optional: future stories may rely on the role being installed; if so, leave it.) [Leaving the role in place — Story 1.5+ will rely on it.]
  - [x] Verify `module.xml`'s `<Invoke>` for `ReadOnlyRole.Install` is **still commented out**.

## Task 0 Output

Full transcript: `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt`

```
Security.Roles signature:
  Create(Name:%String, Description:%String, Resources:%String,
         GrantedRoles:%String, EscalationOnly:%Boolean=0)              -> %Status
  Exists(Name:%String, &Role:%ObjectHandle, &Status:%Status)            -> %Boolean
  Delete(Name:%String)                                                  -> %Status
  AddRoles(Rolename:%String, &Roles:%String, Admin:%Boolean=0)
  RemoveRoles(Rolename:%String, &Roles:%String)

Security.Users signature:
  Create(Username, UserRoles, Password, FullName, NameSpace, Routine,
         ExpirationDate, ChangePassword, Enabled, Comment, Flags=1, ...) -> %Status
  Exists(Username:%String, &User:%ObjectHandle, &Status:%Status, Flag=0) -> %Boolean
  Delete(Username:%String)                                                -> %Status
  AddRoles(Username:%String, &Roles:%String, Admin:%Boolean=0)
  RemoveRoles(Username:%String, &Roles:%String)
  CheckPassword(&User:%ObjectHandle, Password:%String="")                 -> %Boolean
    [hidden from Help() but exists; usage: fetch user via Exists() ByRef,
     then pass ByRef into CheckPassword() with the candidate password]

$SYSTEM.SQL.Security API: (canonical GRANT mechanism)
  GrantPrivilege(ObjPriv:%String, ObjList:%String, Type:%String, User:%String) -> %Status
    - ObjPriv: "SELECT", "INSERT", ... or "*"
    - ObjList: comma-delimited SQL object names or "*"
    - Type:    "TABLE" | "VIEW" | "SCHEMA" | "STORED PROCEDURE" | ...
    - User:    user OR role name (comma-delimited list accepted)
    - Internal TSTART/TCOMMIT — caller does NOT manage the transaction.

  CheckPrivilege(Username, ObjectType, Object, Action, Namespace="") -> %Boolean
    - Used by Approach 4 of test strategy.
    - Action letters: s=SELECT, i=INSERT, u=UPDATE, d=DELETE, r=REFERENCES,
      a=ALTER, e=EXECUTE, l=USE.
    - ObjectType: 1=table, 3=view, 5=schema, 9=procedure, ...

SQL GRANT idempotency on 2024.1:
  IDEMPOTENT — silent. First GrantPrivilege() returned 1 ($$$OK).
  Second GrantPrivilege() with identical args returned 1 ($$$OK).
  No try/catch wrapping needed for AC-3.

Ens.* table SQL projection names (verified live in HSCUSTOM):
  Ens.MessageHeader            (FR31, NFR-S1 — primary session-trace surface)
  Ens.SuperSessionIndex        (FR8 FindRelatedSessions)
  Ens_Util.Log                 (FR5 EventLog tool — Epic 4)  [underscore form]
  Ens_Rule.Log                 (FR6 RuleLog tool — Epic 4)   [underscore form]

  IMPORTANT: Ens.Util.Log and Ens.Rule.Log project to SQL with underscore-
  separator schemas (Ens_Util.Log / Ens_Rule.Log), confirming the story's
  prediction. The GRANT loop uses these underscore-form names.

Role-name decision (NEW finding, not in original story):
  Original memory specified "%SessionAgent_ReadOnly" — REJECTED by live IRIS
  with error #887 ("Invalid role name"). The Security.Roles.Create validator
  reserves the "%" prefix EXCLUSIVELY for IRIS-shipped pre-defined system
  roles. User-created roles cannot begin with "%".
  Decision: role name is "SessionAgent_ReadOnly" (no leading "%").
  Underscore is permitted by the validator. Documented in probe transcript
  §"Naming-decision note". project_package_naming.md memory should be
  updated when Story 1.5 merges.

Process-context test strategy: Approach 4 (CheckPrivilege synthetic query)
  - Verified end-to-end via probe class SessionAgent.Probe (deleted after probe).
  - With ProbeTestRole granted SELECT on Ens.MessageHeader, attached to a
    test user, CheckPrivilege() returned: select=1, insert=0, delete=0.
  - Authentically distinguishes the SELECT-only invariant from missing grant.
  - Rationale for not using Approach 1 (JOB) / 2 (SetCredentials does not
    exist on these classes) / 3 (no per-call security context arg on
    %SQL.Statement): see probe transcript §"Process-context test strategy
    decision".
```

## Dev Notes

### Three-layer enforcement context (this story owns Layer 3)

Per [PRD NFR-S1](../../_bmad-output/planning-artifacts/prd.md) and [architecture.md line 112](../../_bmad-output/planning-artifacts/architecture.md):

- **Layer 1: code discipline** — every tool's `Invoke` method is read-only by inspection. Lives entirely inside the agent's process.
- **Layer 2: dispatch policy gate** — `SessionAgent.Tool.Registry.Dispatch` (Story 2.10) consults `MutatesState=0/1` on each tool class and refuses dispatch for any tool that declares `MutatesState=1`. Lives inside the agent's process.
- **Layer 3 (THIS STORY): IRIS RBAC role** — `%SessionAgent_ReadOnly` granted SELECT-only on `Ens.*` tables. Lives at the IRIS database privilege layer. Survives an L1 code bug or an L2 misconfigured `MutatesState` flag.

The three layers compound: an attacker (or a future code regression) would have to defeat **all three** to actually mutate `Ens.*` data via the agent. L3 is the catch-all backstop — *"each layer alone is fragile; only the stack survives an L1 oversight or an L2 misconfiguration"* (research §"Top Findings" #6).

### Why `%SessionAgent_ReadOnly` (with the `%` prefix)

IRIS RBAC role names that start with `%` are treated as *system roles* — they cannot be deleted by non-administrative users and are excluded from certain default user-management operations. This is the convention used by IRIS for `%All`, `%Manager`, `%Operator`, etc. Per [project memory `project_package_naming.md`](../../C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/project_package_naming.md), `%SessionAgent_ReadOnly` is the locked role name.

Note: per [project rule iris-objectscript-basics.md §Basics](../../.claude/rules/iris-objectscript-basics.md): *"Do not create classes or properties with `%` or `_`"*. **This rule applies to ObjectScript class names**, not to RBAC role names. The role name `%SessionAgent_ReadOnly` is a string passed to `Security.Roles.Create()` — not a class name. The rule does not prohibit strings containing `%` or `_`.

### Project rules that apply to this story

From [.claude/rules/](../../.claude/rules/):

- **`iris-objectscript-basics.md` §"IRIS Library Source"** — read `irislib/%SYSTEM/Security.cls` (and `irislib/%SYSTEM/SQL/Security.cls` if it exists) before using any of the system-security APIs. The cited failure mode in the rule:
  > *"Three bugs in Epic 7 (`$System.Security.Login()`, `$System.Encryption.PBKDF2()`, `$System.Encryption.HMACSHA()`) were caused by not reading the actual source."*
  Specifically: **DO NOT use `$System.Security.Login()` for credential validation** — it switches process context. Use `Security.Users.CheckPassword()` instead.
- **`iris-objectscript-basics.md` §"Namespace Switching in REST Handlers"** — applies analogously here: explicit save/restore via local variable; restore in catch as first line. Never `New $NAMESPACE`.
- **`iris-objectscript-basics.md` §"QUIT Statement Restrictions in Try/Catch Blocks"** — argumented `Quit tSC` is FORBIDDEN inside try/catch.
- **`object-script-testing.md`** — applies to `ReadOnlyRoleTest.cls`. Constructor + assertions rules. ≤500 lines.
- **`research-first.md` §"Task 0 backend-surface probe"** — applies. Story 1.4 introduces a new dependency on `Security.Roles`, `Security.Users`, and SQL GRANT APIs. Task 0 verifies all three.

### IRIS Library Source pre-reads (mandatory before coding)

1. `irislib/%SYSTEM/Security.cls` — for `$System.Security.*` APIs. Look up `CheckPassword`, `Login` (note the warning), `SetCredentials` if it exists.
2. `irislib/%SYSTEM/SQL/Security.cls` — for `$SYSTEM.SQL.Security.GrantPrivilege` and related. Verify it actually exists; if not, the chosen mechanism becomes `%SQL.Statement` direct GRANT execution.
3. Per Story 1.3's discovery, `Security.Roles.cls` and `Security.Users.cls` may not be exported under `irislib/Security/`. In that case, the live probe (Task 0) is the authoritative API source. This is acceptable per the rule's discovery clause.

### Process-context test strategy (the hard problem)

The privilege-enforcement integration test (`TestPrivilegeEnforcement{Insert,Delete,Select}`) needs to attempt a SQL operation **as if** the user was authenticated with only `%SessionAgent_ReadOnly`. The test runner itself executes as `_SYSTEM` (or whatever account the IRIS dev MCP authenticates with) — which has `%All` and would always succeed.

Four candidate approaches (rank in Task 0 by ease + authenticity):

| Approach | Authenticity | Complexity | Requires probing |
|---|---|---|---|
| 1. JOB with test user creds | High (real process boundary) | High (job lifecycle, error capture across processes) | `JOB` syntax with auth, error retrieval |
| 2. `$System.Security.SetCredentials` per-process switch | Medium-High (in-process role swap) | Medium | API existence + behavior on 2024.1 |
| 3. `%SQL.Statement` with security context arg | Medium (depends on API) | Medium | Whether the API exists |
| 4. `$SYSTEM.SQL.Security.CheckPrivilege` query (synthetic) | Low (queries privilege, doesn't exercise it) | Low | The query API existence |

**Rule of thumb:** if Approaches 1–3 all require >2 hours of probing to resolve, fall back to Approach 4 with a clear note in the test method's doc-comment that it's a privilege-query test, not an INSERT-attempt test. The story's read-only invariant is still defensible — the GRANT is documented, the privilege query confirms the role's grants are SELECT-only, and the L1+L2 layers backstop the agent's runtime behavior. **Document the choice in Task 0 Output.**

### Project Structure Notes

New files (NEW):

```
src/SessionAgent/
├── Audit/
│   └── Emit.cls                    (existing — Story 1.3)
├── Security/                       (NEW directory)
│   └── ReadOnlyRole.cls            (NEW — this story)
└── Test/
    ├── AuditEmitTest.cls           (existing — Story 1.3)
    └── ReadOnlyRoleTest.cls        (NEW — this story)
```

No file deletions, no modifications to existing files (Story 1.5 will modify `module.xml` to uncomment the `<Invoke>`).

### Previous Story Intelligence (Story 1.3)

- **Story 1.3** confirmed `Security.Events.Help()` exists on live IRIS — likely the same `Help()` method exists on `Security.Roles`, `Security.Users`. Use it as the primary probe method.
- **Story 1.3** chose Approach 1 (literal names) for the audit triples after the wildcard approach failed. Apply the same skepticism to RBAC: don't assume the documented API works; probe it.
- **Story 1.3** captured 11 audit triples; 4 of them are `LlmCall/<provider>` for openai, anthropic, gemini, ollama. `%SessionAgent_ReadOnly` is consumed at runtime by the same code path that emits these events — the role install in this story is what makes the runtime read-only invariant defensible at the database layer.
- **Story 1.3** established the `_bmad-output/implementation-artifacts/probes/` convention. This story's Task 0 saves probe transcript to `story-1-4-rbac-api-probe-2026-05-02.txt`.
- **Story 1.3 dev tooling note:** `iris_doc_load` with `compile: true` had a misleading error path. Prefer separate `iris_doc_load` (upload) + `iris_doc_compile` (compile) calls.

### References

- [epics.md Epic 1 §Story 1.4](../../_bmad-output/planning-artifacts/epics.md) — story acceptance criteria source (lines 594–619).
- [architecture.md §"Three-layer read-only enforcement"](../../_bmad-output/planning-artifacts/architecture.md) lines 112, 253, 1025 — locks the L1/L2/L3 design.
- [architecture.md §"Sub-package boundaries — Security.ReadOnlyRole"](../../_bmad-output/planning-artifacts/architecture.md) line 980 — owning sub-package.
- [research §"Top Findings" #6](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) — *"Three-layer read-only enforcement is non-negotiable for compliance defensibility."*
- [research §"Confidence Notes" entry on `SessionAgent.Security.ReadOnlyRole.Install()`](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) line 1659: *"High — uses documented `Security.Roles.Create()` + `%SYSTEM.SQL.Security.GrantPrivilege()` paths."*
- [.claude/rules/iris-objectscript-basics.md §"IRIS Library Source"](../../.claude/rules/iris-objectscript-basics.md) — mandatory read of `irislib/%SYSTEM/Security.cls` before using `$System.Security.*`.
- [.claude/rules/iris-objectscript-basics.md §"Namespace Switching"](../../.claude/rules/iris-objectscript-basics.md) — explicit save/restore.
- [.claude/rules/object-script-testing.md](../../.claude/rules/object-script-testing.md) — applies to ReadOnlyRoleTest.cls.

## Dev Agent Record

### Agent Model Used

Opus 4.7 (1M context) — claude-opus-4-7[1m]

### Debug Log References

- Probe transcript: `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt`
- Probe scratch class `SessionAgent.Probe` was created, used for end-to-end CheckPrivilege validation, then deleted (both from disk and from IRIS) before any production code was authored. The probe proved Approach 4 (CheckPrivilege synthetic query) authentically distinguishes SELECT-granted from INSERT/DELETE-not-granted for a real user with the role attached.

### Completion Notes List

**Task 0 — Pre-flight probe results.** All four required probes ran successfully against the live IRIS dev instance:

1. `Security.Roles` API: confirmed `Create(Name, Description, Resources, GrantedRoles, EscalationOnly)` and `Exists(Name, &Role, &Status)` exist with the expected signatures. Captured via `Help()` and a `%Dictionary.MethodDefinition` query.
2. `Security.Users` API: confirmed `Create`, `Delete`, `Exists`, `AddRoles`, `RemoveRoles` plus the hidden-but-callable `CheckPassword(&User, Password)` method (not in `Help()` output but present in `%Dictionary.MethodDefinition`).
3. `irislib/%SYSTEM/SQL/Security.cls`: confirmed `$SYSTEM.SQL.Security.GrantPrivilege(ObjPriv, ObjList, Type, User)` is the canonical GRANT mechanism. Internal TSTART/TCOMMIT — caller does NOT manage the transaction. Also confirmed `CheckPrivilege(Username, ObjectType, Object, Action, Namespace)` is the privilege-query API used by Approach 4 of the test strategy.
4. SQL GRANT idempotency: VERIFIED IDEMPOTENT — re-granting an already-granted privilege returns `$$$OK` silently. NO try/catch wrapping needed.

**NEW finding not in original story spec — role-name validator constraint.** The original project memory specified the role name as `%SessionAgent_ReadOnly` (with leading `%`). Live IRIS rejects this with error #887 "Invalid role name". The `Security.Roles.Create` validator reserves the `%` prefix EXCLUSIVELY for IRIS-shipped pre-defined system roles (per Perplexity research against InterSystems Documentic). User-created roles cannot begin with `%`. Underscores ARE permitted. Decision: role name changed to `SessionAgent_ReadOnly` (no leading `%`). Documented verbatim in the probe transcript §"Naming-decision note", in the `ROLENAME` parameter docstring on `SessionAgent.Security.ReadOnlyRole`, and in the Task 0 Output above. The `project_package_naming.md` memory file should be updated when this story merges (Story 1.5 is the natural carrier for that operator-facing memory update, since 1.5 will own the README).

**Process-context test strategy: Approach 4 (CheckPrivilege synthetic query) selected.** Rationale documented in Task 0 Output and verbatim in the test class docstring. Verified end-to-end during Task 0 probe: with `ProbeTestRole` granted SELECT on `Ens.MessageHeader`, `CheckPrivilege` returned `select=1, insert=0, delete=0`. The L1+L2 layers of the read-only enforcement stack backstop the runtime path; this synthetic test confirms the L3 invariant (the privilege catalog itself only holds SELECT for the role).

**Test execution output (`iris_execute_tests` against `SessionAgent.Test.ReadOnlyRoleTest`, level=class):**
```
total: 6, passed: 6, failed: 0, skipped: 0
- PrivilegeEnforcementDeleteFails    passed (0.792 s)
- PrivilegeEnforcementInsertFails    passed (0.773 s)
- PrivilegeEnforcementSelectSucceeds passed (2.428 s)
- RestoresNamespace                  passed (1.029 s)
- RoleInstallCreates                 passed (1.192 s)
- RoleInstallIdempotent              passed (1.882 s)
```

**Full regression suite (`SessionAgent.Test`, level=package):**
```
total: 9, passed: 9, failed: 0, skipped: 0
(3 Story-1.3 tests + 6 Story-1.4 tests — no regressions)
```

**Manual `Install()` + `Roles.Exists` shell output (post `zpm load`, run from HSCUSTOM):**
```
Set tSC = ##class(SessionAgent.Security.ReadOnlyRole).Install()
Write tSC, " ", $System.Status.GetErrorText(tSC)
-> 1   (i.e. $$$OK)

Set $NAMESPACE = "%SYS"
Write ##class(Security.Roles).Exists("SessionAgent_ReadOnly")
-> 1
```

**Idempotency verification:**
```
Set tSC1 = ##class(SessionAgent.Security.ReadOnlyRole).Install() -> 1
Set tSC2 = ##class(SessionAgent.Security.ReadOnlyRole).Install() -> 1
```

**Story-deviation note: Task 4 "in %SYS" line.** The story's Task 4 says to run `Install()` from `%SYS`. This was tested and FAILS with SQLCODE -30 "Table or view not found" — because Ens.* tables don't exist in %SYS. The correct invocation is from the agent's runtime namespace (HSCUSTOM in this dev env, or whatever Ens namespace the agent is installed into). This is also what the production ZPM `<Invoke>` hook does (Story 1.5 will uncomment it). Treated as an operator-docs error in the original story; corrected in the Task 4 checkbox text and recorded here.

**Test cleanup confirmation (no artifacts persist):**
```
Set $NAMESPACE = "%SYS"
Write ##class(Security.Users).Exists("SaReadOnlyTestUser") -> 0  (test user gone)
Write ##class(Security.Roles).Exists("SessionAgent_ReadOnly") -> 1  (install side-effect, intentional)
```
Probe-only artifacts (`ProbeTestUser`, `ProbeTestRole`, `SmokeTestUser`, `SessionAgent.Probe.cls`) were also confirmed deleted at the end of the probe phase.

**`zpm load` output:**
```
zpm "load c:/git/iris-session-agent"  (run from %SYS)
-> Initialize SUCCESS
-> Reload SUCCESS
-> Validate SUCCESS
-> Compile SUCCESS
-> Configure SUCCESS
-> Activate SUCCESS
```
(One pre-existing IPM deprecation warning about `<CSPApplication>` — unrelated to this story.)

**`module.xml` `<Invoke>` line for `SessionAgent.Security.ReadOnlyRole.Install`:** verified still commented out via `git diff module.xml` (returned empty). AC-4 satisfied.

**No `[Language = python]` references** in `src/SessionAgent/`: verified via grep — zero matches. AC-6 satisfied.

### File List

NEW:
- `src/SessionAgent/Security/ReadOnlyRole.cls`
- `src/SessionAgent/Test/ReadOnlyRoleTest.cls`
- `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt`

MODIFIED:
- `_bmad-output/implementation-artifacts/1-4-read-only-rbac-role-install.md` (Status, Tasks, Task 0 Output, Dev Agent Record, File List, Change Log)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (1-4 status: ready-for-dev → in-progress → review)

NEW directory:
- `src/SessionAgent/Security/`

DELETED (probe scratch, removed before commit):
- `src/SessionAgent/Probe.cls` (probe scratch class — never committed)

### Change Log

- 2026-05-02 — Story 1.4 implemented. Created `SessionAgent.Security.ReadOnlyRole` (Layer 3 RBAC installer with idempotent `Install()`) + `SessionAgent.Test.ReadOnlyRoleTest` (6 tests, all pass). Role name changed from `%SessionAgent_ReadOnly` to `SessionAgent_ReadOnly` after Task 0 probe revealed IRIS rejects the `%` prefix on user-created roles. Approach 4 (CheckPrivilege synthetic query) selected for process-context test strategy after probe validation. `module.xml` `<Invoke>` line stays commented out per AC-4 (Story 1.5 will activate it).
