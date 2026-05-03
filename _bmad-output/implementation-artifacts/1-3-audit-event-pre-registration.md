# Story 1.3: Audit Event Pre-Registration

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As **System (audit infrastructure)**,
I want four audit event types pre-registered in `%SYS` via `Security.Events.Create()` at install time,
so that subsequent `$System.Security.Audit("SessionAgent","<Type>","<Name>", ...)` calls in later epics succeed instead of silently returning 0 (per project rule [§"Security.Events Pre-Registration for Audit"](../../.claude/rules/iris-objectscript-basics.md)).

This is the **first ObjectScript class file in the project** — it establishes the package directory shape, the namespace-switching pattern, and the unit-test shape that subsequent stories will follow. It also makes audit emission viable for every later story (LLM call audit in Epic 2, tool-call audit in Epic 2, vocab-write audit in Epic 9, task-run audit in Epics 7+10) — without this story, every `$System.Security.Audit("SessionAgent",...)` call in those later stories silently fails.

## Acceptance Criteria

**AC-1 — `SessionAgent.Audit.Emit.EnsureEvents()` registers four event triples idempotently in `%SYS`.**

**Given** the developer is implementing `SessionAgent.Audit.Emit`
**When** they implement the `EnsureEvents()` class method
**Then** the method switches to `%SYS` namespace using the **explicit save/restore pattern** (per project rule [§"Namespace Switching"](../../.claude/rules/iris-objectscript-basics.md)) — `Set tOrigNS = $NAMESPACE` / `Set $NAMESPACE = "%SYS"` / `Set $NAMESPACE = tOrigNS`. **Never** `New $NAMESPACE`.
**And** any catch block restores `$NAMESPACE` as **its first line** (`Set $NAMESPACE = tOrigNS`).
**And** for each of these four event triples, the method calls `Security.Events.Exists("SessionAgent","<Type>","<Name>")` first and only calls `Security.Events.Create(...)` if absent (idempotent):

| Source | Type | Name | Future emitter |
|---|---|---|---|
| `SessionAgent` | `LlmCall` | `<provider>` (the wildcard pattern; see Dev Notes below for how to register a wildcard-style triple in IRIS) | `SessionAgent.LLM.Provider.CallMessages` boundary (Epic 2 — Story 2.9, 5.1, 5.2, 5.3) |
| `SessionAgent` | `ToolCall` | `<tool_name>` | `SessionAgent.Tool.Registry.Dispatch` (Epic 2 — Story 2.10) |
| `SessionAgent` | `VocabWrite` | `clickthrough\|explicit\|extracted\|seed` | `SessionAgent.Search.UserVocabulary.RecordSuccess` (Epic 9) |
| `SessionAgent` | `TaskRun` | `<task_name>` | each `SessionAgent.Task.*.OnTask` (Epics 7 + 10) |

**And** the method returns `%Status` per project convention: `Set tSC = $$$OK` first executable line, `Quit tSC` last line.

**AC-2 — Idempotent reinstall: second invocation does NOT duplicate registrations.**

**Given** the install has run once (all four event triples registered)
**When** `EnsureEvents()` is invoked a second time (per NFR-R5 idempotent reinstall)
**Then** `EnsureEvents()` does not duplicate event registrations (the `Exists()` check skips creation for any triple already present)
**And** the second invocation completes with `$$$OK`

**AC-3 — Unit test verifies registration end-to-end + idempotency.**

**Given** the developer creates `src/SessionAgent/Test/AuditEmitTest.cls` extending `%UnitTest.TestCase`
**When** the test class is compiled and run via `iris_execute_tests` (or equivalent MCP tool)
**Then** at least these test methods exist and pass:

- `TestEnsureEventsRegistersAllFour()` — invokes `EnsureEvents()`, then queries `Security.Events.Exists("SessionAgent","<Type>","<Name>")` for each of the four triples. All four return true.
- `TestEnsureEventsIdempotent()` — invokes `EnsureEvents()` twice in succession; second call must return `$$$OK` and **must not** create duplicate entries (a single re-existence check after the second call still shows exactly one entry per triple).
- `TestEnsureEventsRestoresNamespace()` — captures `$NAMESPACE` before the call, invokes `EnsureEvents()`, then verifies `$NAMESPACE` is unchanged after the call (covers the success path of the save/restore pattern).

**And** the test class follows project rule [§"Critical Constructor Requirements"](../../.claude/rules/object-script-testing.md): `%OnNew(initvalue As %String = "")` accepts `initvalue` and calls `##super(initvalue)`. NO `Private` keyword.
**And** assertions use macros (`$$$AssertTrue`, `$$$AssertEquals`, `$$$AssertStatusOK`) — never methods (`..AssertX()` is wrong per the rule).
**And** the test class is ≤ 500 lines per project rule §"Test Class Size".

**AC-4 — `EnsureEvents()` is invocable from the IRIS shell after `zpm load`.**

**Given** Story 1.1's `module.xml` has the `<Invoke Method="EnsureEvents" Class="SessionAgent.Audit.Emit"/>` line **commented out** (because the class didn't exist yet)
**When** Story 1.3 ships and `zpm load` is re-run against this repo
**Then** the developer **manually invokes** `Do ##class(SessionAgent.Audit.Emit).EnsureEvents()` via `iris_execute_command` to verify the method works end-to-end (do NOT uncomment the `<Invoke>` line in `module.xml` — that's Story 1.5's job; this story validates the class works in isolation)
**And** a follow-up `Write ##class(Security.Events).Exists("SessionAgent","LlmCall","openai")` (in `%SYS`) returns 1 for at least one sample triple
**And** the captured shell output is recorded in this story's Completion Notes

**AC-5 — Compile cleanly with `zpm load`; no warnings about unknown classes; no `[Language = python]` references.**

**Given** the new files are committed
**When** `zpm load /path/to/repo` runs
**Then** `SessionAgent.Audit.Emit` and `SessionAgent.Test.AuditEmitTest` both compile to status 0
**And** `grep -r "Language = python" src/SessionAgent/` returns zero matches (NFR-C2 invariant per project rule)

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight: Verify `Security.Events.Create()` API shape on this dev IRIS (AC: #1)**
  - [x] Use `mcp__iris-dev-mcp__iris_execute_command` (in `%SYS` namespace) to verify the `Security.Events.Create()` signature — recommended probe:
    ```
    Do ##class(Security.Events).Help()
    ```
    If `Help()` doesn't exist, run a minimal create against a throwaway triple to confirm the parameter order: `Source, Type, Name, [Description], [Enabled]`.
  - [x] Record the captured signature in this story's **Task 0 Output** section before authoring `Emit.cls`. Per [research-first.md §"Task 0"](../../.claude/rules/research-first.md), this preempts the typical "method exists but parameter order is reversed" trap.
  - [x] **Wildcard event-name registration:** verify whether `Security.Events` accepts a literal `<provider>` placeholder string for the `Name` field (i.e., does the `Name` need to be a concrete value like `openai`, or can it be a wildcard like `<provider>`?). If only concrete names work, the design becomes: register **one event per provider** (`openai`, `anthropic`, `gemini`, `ollama`) at install time, OR register events lazily on first use. Document the chosen approach in Task 0 Output.

- [x] **Task 1 — Create `src/SessionAgent/Audit/` package directory + `Emit.cls` (AC: #1, #5)**
  - [x] `mkdir -p src/SessionAgent/Audit`
  - [x] Create `src/SessionAgent/Audit/Emit.cls` extending `%RegisteredObject`. Class definition shape:

    ```objectscript
    /// <p>Audit event lifecycle helper. Pre-registers all <code>SessionAgent</code>
    /// audit event types in <code>%SYS</code> via <code>Security.Events.Create()</code>
    /// before any code attempts to emit them.</p>
    ///
    /// <p>Without pre-registration, <code>$System.Security.Audit("SessionAgent","Type","Name", ...)</code>
    /// silently returns 0 — see project rule §"Security.Events Pre-Registration for Audit"
    /// in .claude/rules/iris-objectscript-basics.md.</p>
    Class SessionAgent.Audit.Emit Extends %RegisteredObject
    {

    /// Pre-register the four SessionAgent audit event types in %SYS. Idempotent — safe to
    /// call on every install / upgrade.
    ///
    /// Called by the IPM <Invoke> hook in module.xml at install time (Story 1.5
    /// uncomments the hook).
    ClassMethod EnsureEvents() As %Status
    {
        Set tSC = $$$OK
        Set tOrigNS = $NAMESPACE
        Try {
            Set $NAMESPACE = "%SYS"
            ; ... idempotent Exists/Create for each of the four triples ...
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

  - [x] Implement the loop over the four triples per Task 0 Output's chosen approach (literal provider names if wildcards are not supported, or wildcard `<provider>` if they are) — *implemented Approach 1: 11 literal triples (4 LlmCall + 4 VocabWrite + 3 TaskRun); ToolCall deferred to Epic 2 lazy registration per Task 0 finding*
  - [x] **CRITICAL:** never `New $NAMESPACE`. Always explicit save/restore. Catch block restores namespace as **its first line**.
  - [x] **CRITICAL:** triple-dollar `$$$OK` not `$$OK` (per [§"While writing ObjectScript"](../../.claude/rules/iris-objectscript-basics.md))
  - [x] **CRITICAL:** `Quit tSC` not `Return tSC` inside try/catch — argumented `Quit` is forbidden in try/catch blocks (per [§"QUIT Statement Restrictions in Try/Catch Blocks"](../../.claude/rules/iris-objectscript-basics.md)). The `Quit tSC` at the bottom is **outside** the try/catch — that's fine.
  - [x] Compile via `mcp__iris-dev-mcp__iris_doc_compile` (or `mcp__iris-dev-mcp__iris_doc_load` if compile is bundled). Confirm no errors. — *compiled clean: "Compilation finished successfully in 0.045s."*

- [x] **Task 2 — Create `src/SessionAgent/Test/` package directory + `AuditEmitTest.cls` (AC: #3)**
  - [x] `mkdir -p src/SessionAgent/Test`
  - [x] Create `src/SessionAgent/Test/AuditEmitTest.cls` extending `%UnitTest.TestCase`. Class definition shape:

    ```objectscript
    /// Unit tests for SessionAgent.Audit.Emit.
    Class SessionAgent.Test.AuditEmitTest Extends %UnitTest.TestCase
    {

    /// %UnitTest.TestCase requires that subclasses pass the initvalue parameter
    /// to the parent constructor. See .claude/rules/object-script-testing.md
    /// §"Critical Constructor Requirements".
    Method %OnNew(initvalue As %String = "") As %Status
    {
        Set tSC = ##super(initvalue)
        If $$$ISERR(tSC) Quit tSC
        Quit $$$OK
    }

    Method TestEnsureEventsRegistersAllFour()
    {
        Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "EnsureEvents OK")
        ; ... %SYS Security.Events.Exists checks for each of four triples ...
    }

    Method TestEnsureEventsIdempotent()
    {
        Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "first call OK")
        Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "second call OK")
        ; ... assert no duplicates ...
    }

    Method TestEnsureEventsRestoresNamespace()
    {
        Set tBefore = $NAMESPACE
        Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "OK")
        Do $$$AssertEquals($NAMESPACE, tBefore, "namespace restored")
    }

    }
    ```

  - [x] **Test methods need to switch to `%SYS` to query `Security.Events.Exists`.** Use the same explicit save/restore pattern. Do NOT leave the test method's `$NAMESPACE` polluted on exit.
  - [x] **Forbidden:** `$$$AssertFalse` (use `$$$AssertTrue('cond, "...")` instead — per [§"Non-existent Macros"](../../.claude/rules/object-script-testing.md)) — *not used*
  - [x] **Forbidden:** Method names with underscores (`Test_EnsureEvents...` is wrong; `TestEnsureEvents...` is right per [§Naming Patterns](../../_bmad-output/planning-artifacts/architecture.md)) — *all three test methods use camelCase*
  - [x] Compile via `mcp__iris-dev-mcp__iris_doc_compile`. Confirm no errors. — *compiled clean: "Compilation finished successfully in 0.021s."*

- [x] **Task 3 — Run the unit test class via MCP and capture the result (AC: #3)**
  - [x] Use `mcp__iris-dev-mcp__iris_execute_tests` to run `SessionAgent.Test.AuditEmitTest`
  - [x] Confirm 3/3 (or 3+/3+) test methods pass — *3/3 passed, 0 failed*
  - [x] Capture the test runner output snippet in Completion Notes
  - [x] If any test fails: investigate, fix the underlying class (not the test), re-run. Do NOT mark the story `review` until all tests pass. — *no failures*

- [x] **Task 4 — End-to-end verify via `zpm load` + manual `EnsureEvents` invocation (AC: #4, #5)**
  - [x] Run `zpm "load /path/to/repo"` via `iris_execute_command`. Confirm the new classes compile and load with status 0. — *all 6 lifecycle phases SUCCESS (Initialize / Reload / Validate / Compile / Activate / Configure)*
  - [x] Run `Do ##class(SessionAgent.Audit.Emit).EnsureEvents()` via `iris_execute_command` (in `%SYS`). Confirm it returns `$$$OK` (no error). — *invoked in HSCUSTOM (matching install context); returned `$$$OK`*
  - [x] Run `Write ##class(Security.Events).Exists("SessionAgent","LlmCall","openai")` (or whichever literal sample name was chosen in Task 0) — confirm `1`. — *returned `1`*
  - [x] Capture all command output in Completion Notes.
  - [x] Verify `grep -r "Language = python" src/SessionAgent/` still returns zero matches. — *0 matches*
  - [x] Confirm `module.xml`'s three `<Invoke>` lines are STILL COMMENTED OUT (Story 1.5 uncomments them; this story does not). — *all three still inside the `<!-- -->` block, lines 25–29 unchanged*

## Task 0 Output

Captured 2026-05-02 against live IRIS 2025.1 (HealthShare-enabled), namespace `%SYS`. Full transcript saved at `_bmad-output/implementation-artifacts/probes/story-1-3-security-events-api-probe-2026-05-02.txt`.

```
Security.Events.Create signature:  Create(Source, Type, Name, Description, Enabled, Flags) As %Status
Security.Events.Exists signature:  Exists(Source, Type, Name, &Event, &Status) As %Boolean

Wildcard Name acceptable?:          NO
  - Probe registered triple ("ProbeTest","WildcardTest","<provider>"). The
    placeholder string is accepted by Create() and Exists() returns 1 for the
    exact literal "<provider>".
  - But Exists("ProbeTest","WildcardTest","openai") returns 0 (no match), and
    $System.Security.Audit("ProbeTest","WildcardTest","openai", ...) returns
    0 (the silent-failure pattern the project rule warns about).
  - Therefore wildcard-style placeholder Names are NOT honored by the audit
    machinery; only exact-string matches dispatch.

Chosen registration approach:       Approach 1 — literal names per provider/enum/task.
                                    ToolCall deferred to lazy registration in Epic 2+
                                    (tool name universe not known at install time;
                                    Story 2.10's tool registry will register on first emit).

Concrete triples registered by EnsureEvents():
  - ("SessionAgent","LlmCall","openai")        ┐
  - ("SessionAgent","LlmCall","anthropic")     │  Four providers — Epic 2 / Epic 5
  - ("SessionAgent","LlmCall","gemini")        │
  - ("SessionAgent","LlmCall","ollama")        ┘

  - ("SessionAgent","VocabWrite","clickthrough") ┐
  - ("SessionAgent","VocabWrite","explicit")     │  Four enums — Epic 9 vocabulary path
  - ("SessionAgent","VocabWrite","extracted")    │  (concrete enums; no further wildcards)
  - ("SessionAgent","VocabWrite","seed")         ┘

  - ("SessionAgent","TaskRun","PurgeOrphanedChatHistory") ┐
  - ("SessionAgent","TaskRun","PurgeStaleSearchChat")     │  Three tasks — Epic 7 / Epic 10
  - ("SessionAgent","TaskRun","UserVocabularyDecay")      ┘

  Total: 11 triples registered idempotently at install time.

ToolCall: zero triples registered at install time. Future emit sites (Epic 2 Story
2.10 onward) will call a lazy "register-on-first-use" helper, OR Story 2.10 will
extend EnsureEvents() with the then-known tool name universe.

Probe output:                       see probes/story-1-3-security-events-api-probe-2026-05-02.txt
```

## Dev Notes

### Pre-existing reference patterns to leverage

The CLAUDE.md project rule [§"Security.Events Pre-Registration for Audit"](../../.claude/rules/iris-objectscript-basics.md) explicitly documents the `EnsureEvents()` pattern with a sibling-project reference (`IRISCouch.Audit.Emit.EnsureEvents()`):

> *"Pattern reference: `IRISCouch.Audit.Emit.EnsureEvents()` — switches to `%SYS`, iterates all event types, calls `Security.Events.Create()` for any that do not yet exist, then restores the original namespace"*

The dev should (optionally — not required) examine that sibling-project class if available locally (it lives in another repo, not this one) for shape reference. The story's class spec above is sufficient on its own; the sibling reference is supplementary.

### Why the wildcard-name question matters (open in Task 0)

The architecture lists the LlmCall event with `Name=<provider>` and the ToolCall event with `Name=<tool_name>` and the TaskRun event with `Name=<task_name>`. These look like template placeholders, not literal names. IRIS `Security.Events` may or may not support wildcard names — the dev MUST verify in Task 0.

Three concrete approaches to choose from:

1. **Literal names per provider** (most likely): pre-register `("SessionAgent","LlmCall","openai")`, `("SessionAgent","LlmCall","anthropic")`, `("SessionAgent","LlmCall","gemini")`, `("SessionAgent","LlmCall","ollama")`. Same for ToolCall (one per tool — but the tool list isn't fully known until Epic 2+, so register the universe later via lazy registration on first emit). Same for TaskRun (three task names: `PurgeOrphanedChatHistory`, `PurgeStaleSearchChat`, `UserVocabularyDecay`).
2. **Wildcard names** (if IRIS supports it): pre-register four triples with literal `<provider>`, `<tool_name>`, `<task_name>` placeholders. This is what the architecture text reads as.
3. **Lazy registration on first emit**: build a helper `Audit.Emit.RegisterIfMissing(source, type, name)` that the future emitter sites call on first use. This pushes complexity to Epic 2+ but keeps Story 1.3 minimal (only registers what's known at install time — which is none of the LlmCall/ToolCall/VocabWrite names; only the four `TaskRun` task names).

**Default to approach 1** unless Task 0 reveals approach 2 works. Approach 3 is acceptable only if Task 0 reveals approaches 1 and 2 are both infeasible — call out the choice in Task 0 Output.

For VocabWrite, the four name values (`clickthrough`, `explicit`, `extracted`, `seed`) are concrete enums — pre-register all four literally regardless of approach.

### Why the manual invocation in Task 4 (instead of letting the IPM `<Invoke>` hook run it)

Story 1.5 ships `SessionAgent.Installer` and uncomments the three `<Invoke>` lines in `module.xml`. Until then, the only way to run `EnsureEvents()` is manually via `iris_execute_command`. AC-4's "manual invocation" path lets us validate the class in isolation **before** Story 1.5 wires it into the install flow — so when Story 1.5 lands, the install hook is just plumbing and we already know the underlying class works.

The story's Task 4 explicitly **forbids** uncommenting `module.xml`'s `<Invoke>` line in this story, because:
- The other two `<Invoke>` targets (`SessionAgent.Installer.Install`, `SessionAgent.Security.ReadOnlyRole.Install`) still don't exist — uncommenting Audit's hook in isolation would leave the others as broken references and `zpm load` would fail.
- Story 1.5 owns the orchestrator. Splitting the `<Invoke>` uncomment across multiple stories breaks the "one story, one operator-observable change" principle.

### Project rules that apply to this story

From [.claude/rules/](../../.claude/rules/):

- **`iris-objectscript-basics.md`** — applies to every line of `Emit.cls`:
  - §"Basics": no `_` in class/method/parameter names. Class is `SessionAgent.Audit.Emit`. Method is `EnsureEvents` (camelCase, no underscore).
  - §"Abstract Methods" — N/A, this method is concrete.
  - §"While writing ObjectScript" — `Set tSC = $$$OK` first executable line, `Quit tSC` last line. Use `try/catch`. Use `$$$OK` (triple dollar), never `$$OK`.
  - §"Comments" — `///` for class-level and method-level doc comments. Use HTML/DocBook for the class banner.
  - §"QUIT Statement Restrictions in Try/Catch Blocks" — argumented `Quit` is FORBIDDEN inside try/catch. Use argumentless `Quit` inside; argumented `Quit tSC` outside.
  - §"Namespace Switching in REST Handlers" — applies analogously to **any** namespace-switching code: explicit save/restore via local variable; restore in catch as first line. **Never** `New $NAMESPACE`.
  - §"Security.Events Pre-Registration for Audit" — the precise rule this story instantiates.
  - §"IRIS Library Source" — read `irislib/` source for any IRIS system class before using it. `Security.Events.cls` may not be exported to `irislib/` (it's a `%SYS` class) — in that case, use `Help()` or trial against a throwaway triple as the discovery method (Task 0).
- **`object-script-testing.md`** — applies to every line of `AuditEmitTest.cls`:
  - §"Critical Constructor Requirements": `%OnNew(initvalue As %String = "")` accepts `initvalue` and calls `##super(initvalue)`. **NO** `Private` keyword.
  - §"Available Assertion Macros": `$$$AssertEquals`, `$$$AssertTrue`, `$$$AssertStatusOK`. NEVER `..AssertX()`.
  - §"Non-existent Macros": forbidden — `$$$AssertFalse`, `$$$AssertCondition`. Use `$$$AssertTrue('cond, "...")` for negation.
  - §"Test Class Size": ≤500 lines. Story 1.3's test class is small (3 methods); split is not a concern here.
- **`research-first.md`** — Task 0 backend-surface probe applies because this story introduces a new backend dependency on `Security.Events.Create()`. The probe verifies the API shape before the dev authors against it.

### Project Structure Notes

New files (NEW, not UPDATE):

```
src/SessionAgent/
├── Placeholder.cls              (existing — DELETE in this story; replaced by real classes)
├── Audit/
│   └── Emit.cls                 (NEW — this story)
└── Test/
    └── AuditEmitTest.cls        (NEW — this story)
```

**Story 1.3 deletes `Placeholder.cls`.** The Story 1.1 `Placeholder.cls` was a stub to satisfy IPM's `Default.Package` Reload phase (which errors on `.gitkeep` when the `<Resource>` has no `FilenameExtension`). Now that `Emit.cls` and `AuditEmitTest.cls` populate `src/SessionAgent/`, the stub is no longer needed and should be deleted to keep the source tree clean. The `[Hidden]` doc-comment on `Placeholder.cls` named Story 1.3 as the deletion trigger.

The deleted file MUST be confirmed gone via `git status` showing it as deleted, AND the next `zpm load` must still succeed (it should — IPM is happy as long as the directory contains at least one `.cls`).

### Previous Story Intelligence (Stories 1.1, 1.2)

- **Story 1.1** established the package skeleton + `Placeholder.cls` IPM-workaround stub (now slated for deletion in Task 1 of this story per Project Structure Notes above).
- **Story 1.1** confirmed the live IRIS instance is **IRIS for Windows 2025.1** (HealthShare-enabled). The 2024.1 floor is satisfied.
- **Story 1.1** discovered that the `<Resource Name="SessionAgent.PKG">` (no `FilenameExtension`) means IPM's reload phase loads everything, not just `.cls` files. This story's new `.cls` files are fine; just don't create stray non-`.cls` files in `src/SessionAgent/` (no README in the package dir, etc.).
- **Story 1.2** established the `probes/` subdirectory convention for Task-0 probe artifacts. This story's Task 0 captures API-shape output as text in the story file (no screenshot needed) — but if the dev wants to capture an `iris_execute_command` transcript, save it under `_bmad-output/implementation-artifacts/probes/story-1-3-security-events-api-probe-2026-05-02.txt`.
- **Story 1.2** demonstrated the value of the Task-0 probe (caught a label drift between the spec and the live system). This story's Task 0 should be similarly rigorous about verifying `Security.Events.Create()` parameter ORDER and parameter NAMES against the live IRIS, not against documentation alone.

### References

- [epics.md Epic 1 §Story 1.3](../../_bmad-output/planning-artifacts/epics.md) — story acceptance criteria source (lines 569–592).
- [architecture.md §"Audit event source/type/name triples"](../../_bmad-output/planning-artifacts/architecture.md) lines 378–389 — the four event triples canonical source.
- [architecture.md §"Sub-package boundaries" Audit row](../../_bmad-output/planning-artifacts/architecture.md) line 978 — Audit.* depends on `%SYS Security.Events`.
- [.claude/rules/iris-objectscript-basics.md §"Security.Events Pre-Registration for Audit"](../../.claude/rules/iris-objectscript-basics.md) — the project rule this story implements.
- [.claude/rules/iris-objectscript-basics.md §"Namespace Switching in REST Handlers"](../../.claude/rules/iris-objectscript-basics.md) — explicit save/restore pattern; applies analogously to any namespace switch in a non-REST class.
- [.claude/rules/object-script-testing.md](../../.claude/rules/object-script-testing.md) — entire file applies to `AuditEmitTest.cls`.
- [.claude/rules/research-first.md §"Task 0 backend-surface probe"](../../.claude/rules/research-first.md) — frames this story's Task 0.

## Dev Agent Record

### Agent Model Used

Opus 4.7 (1M context) — claude-opus-4-7[1m] — Claude Code subagent dispatched 2026-05-02 by epic-cycle parent agent.

### Debug Log References

No `^ClineDebug` instrumentation needed — implementation was straightforward and the live IRIS round-trip plus the unit test suite gave full coverage of the success path. The story file's Task 0 transcript (`probes/story-1-3-security-events-api-probe-2026-05-02.txt`) is the only debug capture for this story.

### Completion Notes List

**(1) Task 0 probe output — verbatim from live IRIS 2025.1, namespace `%SYS`:**

```
Probe 1 — Security.Events.Help() output (signatures only):
  Create(Source,Type,Name,Description,Enabled,Flags)    Create an Event.
  Delete(Source,Type,Name)                              Delete an Event.
  Exists(Source,Type,Name,&Event,&Status)               Event exists.
  Get(Source,Type,Name,&Properties)                     Get an Events properties.
  Modify(Source,Type,Name,&Properties)                  Modify an Event's properties.

Probe 2 — Wildcard placeholder accepted by Create() but NOT honored by audit:
  Set tSC = ##class(Security.Events).Create("ProbeTest","WildcardTest","<provider>","Probe of wildcard placeholder",1)
  -> Status: $$$OK
  Write ##class(Security.Events).Exists("ProbeTest","WildcardTest","<provider>")
  -> 1

Probe 3 — Definitive: <provider> placeholder does NOT match audit emissions:
  Write ##class(Security.Events).Exists("ProbeTest","WildcardTest","openai")
  -> 0
  Set tAudit = $System.Security.Audit("ProbeTest","WildcardTest","openai","probe test","probe data")
  -> tAudit = 0   (silent-failure pattern — confirms project rule's warning)

Probe 4 — Cleanup successful:
  Set tSC = ##class(Security.Events).Delete("ProbeTest","WildcardTest","<provider>")
  -> $$$OK
  Write ##class(Security.Events).Exists("ProbeTest","WildcardTest","<provider>")
  -> 0
```

**Decision:** Approach 1 (literal names per provider/enum/task). Eleven concrete triples registered at install time; ToolCall family deferred to Epic 2 lazy-registration on first tool dispatch. Full transcript at `_bmad-output/implementation-artifacts/probes/story-1-3-security-events-api-probe-2026-05-02.txt`.

**(2) `iris_execute_tests` output — 3/3 passed, 0 failed, 0 skipped:**

```json
{
  "total": 3, "passed": 3, "failed": 0, "skipped": 0,
  "details": [
    {"class":"SessionAgent.Test.AuditEmitTest","method":"EnsureEventsIdempotent","status":"passed","duration":3.065,"message":""},
    {"class":"SessionAgent.Test.AuditEmitTest","method":"EnsureEventsRegistersAllEleven","status":"passed","duration":1.957,"message":""},
    {"class":"SessionAgent.Test.AuditEmitTest","method":"EnsureEventsRestoresNamespace","status":"passed","duration":0.509,"message":""}
  ]
}
```

**(3) Task 4 manual `EnsureEvents()` + `Security.Events.Exists` shell output:**

```
> zpm "load c:/git/iris-session-agent"   (run in %SYS)
WARNING: The <CSPApplication></CSPApplication> resource tag is deprecated and may be removed in a future release of IPM.
         Please contact the package developer of iris-session-agent to use <WebApplication></WebApplication> instead
Building dependency graph...Done.
[%SYS|iris-session-agent]    Initialize START
[%SYS|iris-session-agent]    Initialize SUCCESS
[%SYS|iris-session-agent]    Reload START (C:\git\iris-session-agent\)
[%SYS|iris-session-agent]    Reload SUCCESS
[iris-session-agent]         Module object refreshed.
[%SYS|iris-session-agent]    Validate START
[%SYS|iris-session-agent]    Validate SUCCESS
[%SYS|iris-session-agent]    Compile START
[%SYS|iris-session-agent]    Compile SUCCESS
[%SYS|iris-session-agent]    Activate START
[%SYS|iris-session-agent]    Configure START
[%SYS|iris-session-agent]    Configure SUCCESS
[%SYS|iris-session-agent]    Activate SUCCESS

> Set tSC = ##class(SessionAgent.Audit.Emit).EnsureEvents()  (run in HSCUSTOM)
> Write "EnsureEvents status: ",$Select(tSC=1:"$$$OK",1:$System.Status.GetErrorText(tSC)),!
EnsureEvents status: $$$OK

> Write ##class(Security.Events).Exists("SessionAgent","LlmCall","openai")  (run in %SYS)
1
```

**(4) Bonus end-to-end audit verification — confirms the whole point of pre-registration:**

```
> Set tAudit = $System.Security.Audit("SessionAgent","LlmCall","openai","story-1.3 sanity check","probe data")
> Write "Audit return for registered triple: ",tAudit,!
Audit return for registered triple: 1
```

(Returns `1` = success, vs the `0` silent-failure that would happen without pre-registration. Validates the entire infrastructure end-to-end.)

**(5) Loose-end housekeeping:**
- `Placeholder.cls` deleted from disk and from the IRIS server (`SessionAgent.Placeholder.cls` removed from `HSCUSTOM`).
- `module.xml` lines 25–29: three `<Invoke>` install hooks remain commented out as Story 1.5 contract requires.
- `grep -r "Language = python" src/SessionAgent/` returns 0 matches (NFR-C2 invariant preserved).
- `mcp__iris-dev-mcp__iris_doc_load` reported a misleading "خطأ #5351: Class 'User.Emit' does not exist" error on the auto-compile step despite the upload succeeding under the correct name. A direct follow-up `mcp__iris-dev-mcp__iris_doc_compile` against `SessionAgent.Audit.Emit.cls` (and `SessionAgent.Test.AuditEmitTest.cls`) succeeded cleanly. Worth filing this as a tooling note for future stories: rely on the explicit-name compile call after `iris_doc_load`, not the auto-compile flag.

### File List

**Created:**
- `src/SessionAgent/Audit/Emit.cls` — the `EnsureEvents()` class method (the implementation).
- `src/SessionAgent/Test/AuditEmitTest.cls` — three-method `%UnitTest.TestCase` covering AC-3 (registers-all, idempotent, restores-namespace).
- `_bmad-output/implementation-artifacts/probes/story-1-3-security-events-api-probe-2026-05-02.txt` — Task 0 probe transcript.

**Deleted:**
- `src/SessionAgent/Placeholder.cls` — Story 1.1's IPM-workaround stub. The package directory is now populated by `Audit/` and `Test/`, so the stub is no longer needed (its `///` doc comment named Story 1.3 as the deletion trigger).

**Modified:**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — flipped `1-3-audit-event-pre-registration` from `ready-for-dev` to `in-progress` then to `review` (final state after this story); `last_updated` line updated.
- `_bmad-output/implementation-artifacts/1-3-audit-event-pre-registration.md` — story file: `Status` flipped through `in-progress` → `review`; Task 0 Output filled; all task checkboxes marked; Dev Agent Record / Completion Notes / File List populated.

### Change Log

| Date | Change | Files |
|---|---|---|
| 2026-05-02 | Story 1.3 implementation: introduced `SessionAgent.Audit.Emit` with idempotent `EnsureEvents()` registering 11 concrete `(Source, Type, Name)` audit triples in `%SYS`. Verified live on IRIS 2025.1 via Task 0 probe (wildcard names not supported by audit dispatch — Approach 1 chosen). Three-method unit-test class verifies registration, idempotency, and namespace restoration. Removed Story 1.1's `Placeholder.cls` IPM-workaround stub. | `src/SessionAgent/Audit/Emit.cls` (NEW), `src/SessionAgent/Test/AuditEmitTest.cls` (NEW), `src/SessionAgent/Placeholder.cls` (DELETED), `_bmad-output/implementation-artifacts/probes/story-1-3-security-events-api-probe-2026-05-02.txt` (NEW) |
