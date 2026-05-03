# Story 2.10: `Tool.Base` Abstract + `Tool.Registry` + Task-0 Probe

Status: done

## Story

As a developer adding the first three Inspection tools (Story 2.11),
I want `SessionAgent.Tool.Base` abstract base class enforcing the FR55–FR58 dispatch contract, plus `SessionAgent.Tool.Registry` with reflection-based tool enumeration (`%Dictionary.MethodDefinition`) and the L2 dispatch policy gate (`MutatesState=0` check) plus audit interceptor,
so that tool implementations follow a uniform pure-dispatch contract and the read-only invariant (NFR-S1 Layer 2) is structurally enforced.

This story ships **2 NEW classes** + **2 test classes** + the **first Task-0 probe** in Epic 2 (per architecture §"Carry-forward Task-0 probes" Epic 2). Story 2.0 carry-forward: ToolCall lazy registration via `Audit.Emit.RegisterIfMissing` (already shipped Story 2.5) — this story's `Tool.Registry.Dispatch` calls it on first emit per tool name.

## Acceptance Criteria

ACs map to [epics.md Story 2.10](../planning-artifacts/epics.md#story-210-toolbase-abstract--toolregistry--task-0-probe) (lines 991–1023).

**AC-0 (Task-0 probe — MANDATORY per architecture §"Carry-forward Task-0 probes" Epic 2):**

- Execute `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` against the live IRIS instance.
- Capture the returned object's `%ClassName(1)` + a sampling of property values (e.g., `Name`, `ClassName`, `FormalSpec`, `ReturnType`) in the story's Completion Notes verbatim.
- **If the probe returns `$$$NULLOREF` or throws**, the story is **escalated for re-design** — `Tool.Registry.ListTools` reflection depends on `%Dictionary.MethodDefinition` being available. STOP and report.
- Probe context: this validates the reflection mechanism the registry will use to enumerate tool subclasses' methods. (Note: `ListTools` actually uses `%Dictionary.ClassDefinition` for the subclass scan; the probe samples the parallel API to confirm reflection availability.)

**AC-1 — `SessionAgent.Tool.Base` abstract class shipped at `src/SessionAgent/Tool/Base.cls`** marked `[Abstract]`:

Class Parameters:

- `ToolName As %String` (default empty; concrete overrides; e.g. `"session_summary"`)
- `Description As %String` (default empty; concrete overrides)
- `MutatesState As %Boolean = 0` (FR56; concrete may override to 1 for write tools — but L2 enforcement rejects MutatesState=1 in v1)

Abstract methods (with curly-brace bodies returning correct types per project rule §"Abstract Methods in ObjectScript"):

- `GetInputSchema() As %DynamicObject [ Abstract ]` — body `{ Quit {} }`. Concrete returns `{type: "object", properties: {...}, required: [...], additionalProperties: false}` per architecture §"Tool input JSON Schema subset".
- `Invoke(pCallerCtx As Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status [ Abstract ]` — body `{ Quit $$$OK }`. Concrete returns the MCP envelope per architecture §"MCP tool-result envelope" (success: `{content:[...], structuredContent:{...}}`; error: `{isError:1, content:[...]}`).

Doc-comment explicitly enumerates the **seven anti-patterns** (FR55, NFR-S6) — no `%session.Data`, no `%request`, no Zen state, no `%CSP.Response.Write`, no `$NAMESPACE` side effects, no exceptions as error signals, no `Write !,...` streaming.

**AC-2 — `SessionAgent.Tool.Registry` shipped at `src/SessionAgent/Tool/Registry.cls`** with two ClassMethods:

- `ListTools() As %DynamicArray` — introspects `%Dictionary.ClassDefinition` for all subclasses of `SessionAgent.Tool.Base` in the current namespace. For each subclass, returns `{name: <ToolName>, description: <Description>, input_schema: <subclass.GetInputSchema()>}`. Returns `[]` if no subclasses (or only the abstract base). Skips abstract classes via `%Dictionary.ClassDefinition.Abstract = 1` filter. (FR57 — MCP-introspectable.)

- `Dispatch(pToolName As %String, pCallerCtx As Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status` — orchestrates per architecture §"Tool dispatch contract":
  1. **Lookup**: scan `%Dictionary.ClassDefinition` for the subclass whose `Parameter ToolName = pToolName`. Use `%Dictionary.ParameterDefinition.%OpenId("<class>||ToolName").Default` to read. If not found, set `pResult = {isError:1, content:[{type:text, text:"unknown tool: "_pToolName}]}` and return `$$$OK`.
  2. **L2 read-only enforcement** (FR36): read the subclass's `Parameter MutatesState` value. If `=1`, set `pResult = {isError:1, content:[{type:text, text:"Tool blocked by read-only policy"}]}` and return `$$$OK`. NEVER invoke a mutating tool.
  3. **Latency timer**: capture `$ZH` start.
  4. **Lazy register audit triple** (Story 2.0 carry-forward): `##class(SessionAgent.Audit.Emit).RegisterIfMissing("SessionAgent","ToolCall",pToolName)`. Already-registered triples short-circuit.
  5. **Invoke** the concrete via `$ClassMethod(<full-class-name>, "Invoke", pCallerCtx, pJsonArgs, .pResult)` inside an outer Try/Catch. **If the tool throws** (defense-in-depth — tools should pre-surface their own errors), set `pResult = {isError:1, content:[{type:text, text: ex.DisplayString()}]}` (NEVER stack trace to operator; full stack goes in `Audit.ToolCall.ErrorText`).
  6. **Compute latency**: `$ZH - tStart` × 1000, integer-rounded via `$Normalize`.
  7. **Audit emit** (NFR-S4 100% completeness): always call `##class(SessionAgent.Audit.Emit).LogToolCall(pCallerCtx.IrisSessionId|pCallerCtx.SearchSessionKey, pToolName, pJsonArgs.%ToJSON(), pResult.%ToJSON(), tLatencyMs, ($Get(pResult.isError)=1), $Get(ex.DisplayString(),""), "", "", "")`. (The 4 trailing args — `pResultSetSize`, `pQueryTemplate`, `pIndexUsed` — are search-agent enrichment, empty for inspection tools.)
  8. Return `$$$OK` (envelope-based; status reflects orchestration health, not tool result).

**AC-3 — Test classes ship at:**

- `src/SessionAgent/Test/ToolBaseTest.cls` (≤ 500 lines):
  - `TestToolBaseHasExpectedClassParameters` — verifies `ToolName`, `Description`, `MutatesState` parameters declared.
  - `TestAbstractMethodsHaveCurlyBodies` — verifies `GetInputSchema` and `Invoke` are `[Abstract]` with bodies (compile must succeed).
  - `TestStubSubclassConcreteCallable` — define a private stub class `SessionAgent.Test.StubReadOnlyTool` (in test-class-as-fixture, OR in a sidecar `.cls` per dev preference) that overrides `MutatesState=0` and returns a fixed envelope. Call `..GetInputSchema()` and `..Invoke()` directly; assert returns expected envelope.

- `src/SessionAgent/Test/ToolRegistryTest.cls` (≤ 500 lines):
  - `TestListToolsIncludesStubReadOnlyTool` — assert the stub class appears in `Registry.ListTools()` output.
  - `TestListToolsExcludesAbstractBase` — assert `SessionAgent.Tool.Base` itself does NOT appear (Abstract filter).
  - `TestDispatchSuccessReturnsResultAndEmitsAudit` — call `Dispatch("test_readonly_tool", ...)`; assert returned `pResult` is the stub's envelope; assert `count(*) FROM SessionAgent_Audit.ToolCall WHERE ToolName='test_readonly_tool'` increases by 1.
  - `TestDispatchRejectsMutatesStateOne` — define stub `SessionAgent.Test.StubWriteTool` with `MutatesState=1`; call `Dispatch("test_write_tool", ...)`; assert `pResult.isError = 1` AND `pResult.content[0].text` contains "read-only policy"; assert NO `Audit.ToolCall` row created (or row created with `IsError=1` — implementation choice; document).
  - `TestDispatchExceptionWrappedAsErrorEnvelope` — define stub `SessionAgent.Test.StubThrowingTool` whose `Invoke` raises `<UNDEFINED>`. Call `Dispatch("test_throwing_tool", ...)`; assert `pResult.isError = 1`; assert `pResult.content[0].text` contains the exception message (NOT a raw stack trace per architecture line 476); assert `Audit.ToolCall.ErrorText` row contains the stack trace info.
  - `TestDispatchUnknownToolReturnsErrorEnvelope` — call `Dispatch("does_not_exist", ...)`; assert `pResult.isError = 1`, text contains "unknown tool".
  - `TestRegisterIfMissingFiresOnFirstDispatch` — clean slate (`Security.Events.Delete("SessionAgent","ToolCall","test_readonly_tool")`); call `Dispatch("test_readonly_tool", ...)`; assert `Security.Events.Exists("SessionAgent","ToolCall","test_readonly_tool") = 1` post-dispatch.
  - `TestEvery DispatchEmits ExactlyOneAuditRow` — call `Dispatch` 5 times against the success stub; assert `count(*) FROM SessionAgent_Audit.ToolCall WHERE ToolName='test_readonly_tool'` increased by exactly 5 (NFR-S4 100% completeness).

All assertions via `$$$Assert*` macros. `%OnNew(initvalue)` calls `##super(initvalue)`. `OnAfterOneTest` cleanup: clear stub-tool audit rows + delete test-only Security.Events triples.

**AC-4 — Compile + tests + regression intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` clean for `Tool.Base`, `Tool.Registry`, stub tool classes, `Test.ToolBaseTest`, `Test.ToolRegistryTest`.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.ToolBaseTest`: 3/3 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.ToolRegistryTest`: 7/7 passing.
- Per-class regression sweep: 97/97 total (current 87 + 3 + 7).

## Tasks / Subtasks

- [x] **Task 0 — irislib + reflection probe (AC: #0, MANDATORY)**
  - [x] Run `mcp__iris-dev-mcp__iris_execute_classmethod %Dictionary.MethodDefinition %OpenId "Ens.BusinessProcess||OnRequest"` (or via `iris_execute_command` if classmethod-call shape doesn't accept the compound ID). Capture VERBATIM output (object class name + at least 4 property values).
  - [x] If `$$$NULLOREF` or exception → STOP and surface to lead for re-design. (Probe returned a valid `<Object:%Dictionary.MethodDefinition>` — no escalation needed.)
  - [x] Read `irislib/%Dictionary/ClassDefinition.cls` to confirm: (a) the `Abstract` property exists; (b) the iteration pattern for subclass enumeration. Capture in Completion Notes.
  - [x] Read `irislib/%Dictionary/ParameterDefinition.cls` to confirm `Default` property contains the parameter value. Capture.

- [x] **Task 1 — Author `src/SessionAgent/Tool/Base.cls` (AC: #1)**
  - [x] `[Abstract]` class with 3 Class Parameters + 2 abstract methods + curly-brace bodies
  - [x] Doc-comment enumerates 7 anti-patterns
  - [x] No Storage section; no `[Language = python]`

- [x] **Task 2 — Author `src/SessionAgent/Tool/Registry.cls` (AC: #2)**
  - [x] `ListTools` uses `%Dictionary.ClassDefinition` subclass scan + `Abstract` filter
  - [x] `Dispatch` 8-step orchestration per AC-2
  - [x] `RegisterIfMissing` call on first emit per tool name (Story 2.0 carry-forward) — delegated through `Audit.Emit.LogToolCall`, which calls `RegisterIfMissing` internally before the row save (Story 2.5 already wires this path; `Tool.Registry.Dispatch` only needs to call `LogToolCall`).
  - [x] Audit emit on EVERY dispatch (success + error paths) — except blocked-at-policy / unknown-tool cases where no real tool was invoked (documented inline as `tDispatchAttempted=0`).

- [x] **Task 3 — Author stub-tool fixture classes** (location chosen: `src/SessionAgent/Test/Stub*.cls` standalone files — follows the Story 2.9 `MockOpenAIProvider.cls` precedent for clean separation; inner-class pattern not available in ObjectScript anyway.)
  - [x] `StubReadOnlyTool` (`MutatesState=0`, returns fixed `{content:[{type:text, text:"ok"}], structuredContent:{stub:"readonly"}}`)
  - [x] `StubWriteTool` (`MutatesState=1`; `Invoke` body throws an explicit `%Exception.General` to make it loud if Registry.Dispatch ever bypasses the L2 gate)
  - [x] `StubThrowingTool` (`Invoke` raises `<UNDEFINED>` via `Set tX = %Garbage`)

- [x] **Task 4 — Author test classes (AC: #3)**
  - [x] `src/SessionAgent/Test/ToolBaseTest.cls` — 3 Test* methods
  - [x] `src/SessionAgent/Test/ToolRegistryTest.cls` — 7 Test* methods
  - [x] `OnAfterOneTest` cleanup: kill stub-tool audit rows + delete test triples
  - [x] Both files ≤ 500 lines (ToolBaseTest = 110 lines, ToolRegistryTest = 240 lines)

- [x] **Task 5 — Compile + tests (AC: #4)**
  - [x] `iris_doc_compile` for all classes (Base, Registry, 3 stubs, 2 tests) — clean
  - [x] `iris_execute_tests SessionAgent.Test.ToolBaseTest` → 3/3
  - [x] `iris_execute_tests SessionAgent.Test.ToolRegistryTest` → 7/7 (verified via `^UnitTest.Result` global; MCP response truncates to 5–6 details due to a read-timing window — see Completion Notes)
  - [x] Per-class regression sweep → 97/97 total (87 prior + 10 new)

- [x] **Task 6 — Stale-reference grep (discipline rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly" src/SessionAgent/Tool/ src/SessionAgent/Test/Stub*.cls src/SessionAgent/Test/Tool*Test.cls` → 0 hits in the new files. (One pre-existing comment-only mention in `src/SessionAgent/Security/ReadOnlyRole.cls:31` is intentional historical documentation, not introduced by this story.)

### Review Findings

Code review 2026-05-03 — three review layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor) inline. AC-0 through AC-4 verified pass. All 7 anti-patterns enumerated. `[Abstract]` curly-brace bodies present. `RegisterIfMissing` integration end-to-end via `LogToolCall`. `ex.AsStatus()` fix for `ex.Location` MultiDimensional verified clean. Operator-vs-audit error split (concern #2) confirmed correct per architecture line 476. Audit-emit ordering (concern #1) — dev's choice to skip emit on blocked-by-policy and unknown-tool dispatches is **explicitly permitted by the spec** (AC-3 #4 allows "NO row created OR row created with IsError=1 — implementation choice; document"); the choice is documented inline (`Tool/Registry.cls:168–173`), tested (`TestDispatchRejectsMutatesStateOne` line 156 asserts no row), and defensible (an attacker could spam unknown-tool requests to fill the ledger). Dismissed as a deliberate, spec-aligned design decision.

- [x] [Review][Defer] Discovery query is direct-subclass-only — transitive subclasses invisible to `ListTools`/`ResolveToolName` [`src/SessionAgent/Tool/Registry.cls:54,234`] — deferred, no v1 impact (all v1 tools extend `Tool.Base` directly).
- [x] [Review][Defer] No defensive guard against null `pCallerCtx` in audit-emit branch [`src/SessionAgent/Tool/Registry.cls:175`] — deferred, no shipped caller path produces null; defense-in-depth gap only.
- [x] [Review][Defer] MCP `iris_execute_tests` truncation recurrence on `ToolRegistryTest` — deferred, addendum to existing Story 2.4 tooling-quirk entry.

**Triage:** 0 patches, 0 decision-needed, 3 deferred to `deferred-work.md`, 3 dismissed (latency-timer position deviation, `tInvokeSC`-failure operator text, audit-emit-on-block design choice). Status remains `review` per lead's auto-resolution policy.

## Dev Notes

### Why Task-0 is mandatory for Story 2.10

`Tool.Registry.ListTools` and `Tool.Registry.Dispatch` both depend on `%Dictionary.ClassDefinition` and `%Dictionary.ParameterDefinition` reflection. If these reflection APIs are unavailable or behave differently on this IRIS install, the registry breaks silently. The Task-0 probe samples a known IRIS class (`Ens.BusinessProcess.OnRequest`) and verifies the API returns expected metadata.

### Story 2.0 carry-forward

`SessionAgent.Audit.Emit.RegisterIfMissing` shipped in Story 2.5 (planted there per Story 2.0 triage). This story's `Dispatch` calls it on first emit per tool name. The Story 2.0 cleanup is now fully closed.

### Auto-sync workflow + typed MCPs

Same as previous Epic 2 stories. Discipline rule 3.

### Constraints

- **Class locations:** `src/SessionAgent/Tool/Base.cls`, `src/SessionAgent/Tool/Registry.cls` (per [architecture.md:818–820](../planning-artifacts/architecture.md))
- **Stub classes:** `src/SessionAgent/Test/Stub*.cls` (test-only fixtures — naming follows `MockOpenAIProvider.cls` precedent from Story 2.9)

### Sources

- [epics.md:991–1023 §"Story 2.10"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:451–476 §"MCP tool-result envelope"](../planning-artifacts/architecture.md) — envelope shape.
- [architecture.md:582–592 §"Tool dispatch contract — seven anti-patterns"](../planning-artifacts/architecture.md) — anti-pattern enumeration.
- [architecture.md:688–740 §"Pattern Examples"](../planning-artifacts/architecture.md) — canonical tool skeleton.
- Story 2.5 `Audit.Emit.RegisterIfMissing` (already shipped).
- Story 2.7 `Agent.CallerContext` (already shipped).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Abstract Methods in ObjectScript", §"VSCode Auto-Sync Workflow", §"IRIS Library Source".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (single-task agent dispatched by `/epic-cycle` lead).

### Debug Log References

One MCP-side quirk surfaced (not a defect, but worth flagging for reviewer):

- `mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test.ToolRegistryTest` consistently reports `total: 5–6` while the underlying `^UnitTest.Result` global captures all 7 method results with `status=1`. This is a read-timing window in the MCP server — the response is read before the runner finishes writing the trailing entries. Verified via a temporary `SessionAgent.Test.TempProbe` class (now deleted) that walked `^UnitTest.Result(<lastIdx>, <suite>, "SessionAgent.Test.ToolRegistryTest", *)` and dumped `[status, dur, msg]` for every entry — output confirmed all 7 tests passed with `status=1` and non-zero durations. The faster `ToolBaseTest` (sub-2ms per method) does not hit the window.

### Completion Notes List

**Task 0 probe — verbatim output (AC-0).** Probe ran on the live HSCUSTOM namespace.

```
Class: %Dictionary.MethodDefinition
Name: OnRequest
ClassName (from md.parent.Name): Ens.BusinessProcess
FormalSpec: request:%Library.Persistent,*response:%Library.Persistent
ReturnType: %Status
Description: Handle a 'Request'
Abstract: 0
```

The probe returned a valid `<Object:%Dictionary.MethodDefinition>` (NOT `$$$NULLOREF`), and at least 6 properties were sampled successfully. **Reflection API confirmed available — no escalation required.**

**irislib findings (AC-0).**
- `irislib/%Dictionary/ClassDefinition.cls:30` — `Property Abstract As %Boolean [ InitialExpression = 0 ]` confirmed. Used by `Tool.Registry.ListTools` SQL filter (`WHERE Abstract = 0`) to exclude abstract subclasses.
- `irislib/%Dictionary/ClassDefinition.cls:198` — `Property Super As %RawString` confirmed. Used by the SQL discovery query (`WHERE %EXACT(Super) = 'SessionAgent.Tool.Base'`) for direct-subclass enumeration. (`%Dictionary.ClassDefinitionQuery` provides indexed lookups but a one-shot SQL query is sufficient and self-documenting.)
- `irislib/%Dictionary/ParameterDefinition.cls:21` — `Property Default As %RawString [ SqlFieldName = _Default ]` confirmed. The Default property holds the parameter's compile-time literal value (e.g., `"test_readonly_tool"` for `Parameter ToolName = "test_readonly_tool"`). Used by `Tool.Registry.GetParameterValue` and the registry's reverse lookup `ResolveToolName`.

**Compile (AC-4).** All 7 new classes compile clean via `iris_doc_compile` with `flags='cuk'`:

```
SessionAgent.Tool.Base.cls           → up-to-date
SessionAgent.Tool.Registry.cls       → up-to-date
SessionAgent.Test.StubReadOnlyTool.cls   → up-to-date
SessionAgent.Test.StubWriteTool.cls      → up-to-date
SessionAgent.Test.StubThrowingTool.cls   → up-to-date
SessionAgent.Test.ToolBaseTest.cls       → up-to-date
SessionAgent.Test.ToolRegistryTest.cls   → up-to-date
```

**Test counts (AC-3, AC-4).**
- `SessionAgent.Test.ToolBaseTest` — 3/3 passing.
- `SessionAgent.Test.ToolRegistryTest` — 7/7 passing per the underlying `^UnitTest.Result` global. (See Debug Log References for the MCP truncation note.)
- Per-class regression sweep across all 12 prior test classes — 87/87 passing, zero regressions. **Total: 97/97.**

**Stub-class-location decision (Task 3).** Standalone `.cls` files under `src/SessionAgent/Test/` (one file per stub), following the Story 2.9 `MockOpenAIProvider.cls` precedent. Inline-inside-test-class is not available in ObjectScript (no inner-class facility), so this is the only sensible option for shared fixtures. The three files (`StubReadOnlyTool.cls`, `StubWriteTool.cls`, `StubThrowingTool.cls`) keep concerns separate — each stub exercises one specific code path the registry must handle.

**Story 2.0 carry-forward closure.** `Audit.Emit.RegisterIfMissing` was planted in Story 2.5 and is now exercised end-to-end by `TestRegisterIfMissingFiresOnFirstDispatch`. The cleanup is fully closed — no `RegisterIfMissing` call lives directly in `Tool.Registry.Dispatch`; the registry calls `LogToolCall`, which calls `RegisterIfMissing` internally before the row save (the canonical path Story 2.5 already established). This avoids a redundant double-registration and keeps the audit-emit logic in one place.

**Implementation note on `tInvokeSC` handling.** `Tool.Registry.Dispatch` checks both the returned `%Status` from the inner `$ClassMethod(... "Invoke" ...)` call AND inspects `pResult.isError = 1` post-invocation. If the tool returns a failure `%Status` without populating an envelope, the registry synthesizes the envelope so downstream consumers always see the standard shape. This keeps the architecture invariant "tools NEVER throw to the operator; everything becomes an envelope" robust against tools that accidentally surface a raw `%Status`.

**Operator-readable vs audit-only error text.** When the outer Catch fires (defense-in-depth), the operator-facing `pResult.content[0].text` gets only `ex.DisplayString()` (a clean one-line message); the audit row's `ErrorText` gets `ex.DisplayString() _ " | AsStatus: " _ $System.Status.GetErrorText(ex.AsStatus())`, which preserves the failure-status chain for post-mortem analysis. Per architecture line 476, raw stack traces NEVER reach the operator; this implementation honors that.

**Bug found and fixed mid-implementation.** Initial draft of `Registry.Dispatch` tried to read `ex.Location` directly to build the audit ErrorText. `Location` is declared `MultiDimensional` on `%Exception.SystemException`, which raised `<OBJECT DISPATCH>...Property 'Location' must be MultiDimensional` at runtime. Fixed by replacing the `ex.Location` reference with `ex.AsStatus()` + `$System.Status.GetErrorText` — both are scalar, both preserve the failure-status chain, neither requires multidim subscripting.

**Task 6 grep.** Zero `HSCUSTOMCODE` or `%SessionAgent_ReadOnly` matches in any new file. One pre-existing match in `src/SessionAgent/Security/ReadOnlyRole.cls:31` (a comment documenting the historical Story 1.4 rejection of the bad name) is intentional historical documentation and not flagged.

### File List

NEW (all 7 files):

- `src/SessionAgent/Tool/Base.cls` — abstract base class with `[Abstract]` keyword, 3 Class Parameters (`ToolName`, `Description`, `MutatesState`), 2 abstract methods with curly-brace bodies, doc-comment enumerating the seven anti-patterns.
- `src/SessionAgent/Tool/Registry.cls` — `ListTools` (FR57 MCP enumeration), `Dispatch` (FR55–FR58 + FR36 + NFR-S4 8-step orchestration), plus `GetParameterValue` and `ResolveToolName` helpers.
- `src/SessionAgent/Test/StubReadOnlyTool.cls` — `MutatesState=0` happy-path fixture.
- `src/SessionAgent/Test/StubWriteTool.cls` — `MutatesState=1` blocked-by-policy fixture; `Invoke` throws if ever called.
- `src/SessionAgent/Test/StubThrowingTool.cls` — `MutatesState=0` fixture whose `Invoke` raises `<UNDEFINED>` to exercise the registry's defense-in-depth Catch.
- `src/SessionAgent/Test/ToolBaseTest.cls` — 3 `Test*` methods (AC-1).
- `src/SessionAgent/Test/ToolRegistryTest.cls` — 7 `Test*` methods (AC-2 + AC-3) plus `OnAfterOneTest` cleanup hook.

MODIFIED:

- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story key flipped `ready-for-dev` → `in-progress` → `review`; `last_updated` advanced.

### Change Log

| Date       | Author         | Change                                                                                                                                                                                                                                                                                            |
|------------|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 2026-05-03 | Dev (Opus 4.7) | Story 2.10 implementation: `Tool.Base` abstract, `Tool.Registry` reflection-based discovery + L2-enforced dispatch + audit interceptor, 3 stub-tool fixtures, 2 test classes (10 new tests, 97/97 total). Task-0 probe confirmed `%Dictionary.MethodDefinition` reflection available on this IRIS install. Story 2.0 carry-forward (`Audit.Emit.RegisterIfMissing` lazy registration) closed end-to-end. |
