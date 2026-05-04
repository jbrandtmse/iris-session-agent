# Story 3.9: Sample Interoperability Production + Walkthrough Re-Run on Rich Data

Status: done

## Story

As **the maintainer + pilot operator validating the agent against richer data than the dev install's 4-message-zero-error baseline**,
I want a purpose-built `SessionAgent.Sample.*` interoperability solution — adapterless Business Service callable via a public ClassMethod, ≥2 Business Processes, ≥2 Business Operations, configurable error injection, rich enough message bodies for the agent to answer multi-step diagnostic questions — installed separately from the IPM `<Resource>` so it's clearly a test fixture not runtime,
So that PRD MVP Exit Criterion #2's "real diagnosis through the agent" portion is empirically reproducible AND Epic 4's Story 4.7 ("comprehensive read-only suite verification") has rich data to inspect against.

Added to Epic 3 via Sprint Change Proposal 2026-05-03.

## Acceptance Criteria

### AC-1 — Sample production package + adapterless BS

**Given** the developer is implementing the sample-production scaffolding
**When** they ship the `SessionAgent.Sample.*` package
**Then** the package contains an adapterless Business Service `SessionAgent.Sample.BS.OrderIngest` (extends `Ens.BusinessService`) with a public `ClassMethod RunScenario(pErrorMode As %String = "none") As %Status` where `pErrorMode ∈ {"none", "businessProcessFailure", "businessOperationFailure", "partialSuccess"}` (subset of the proposal's list — `providerError` is excluded since it's an LLM-side concern, not interop-trace concern).
**And** `RunScenario` instantiates a `Sample.Msg.OrderRequest`, populates it with rich realistic data (see AC-3), then dispatches via `..SendRequestAsync()` to the routing BP.
**And** Each invocation produces a fresh Ens session with a multi-step trace ending in the corresponding outcome.

### AC-2 — Business Processes + Business Operations

**Given** the developer is wiring the production graph
**When** they ship the BP/BO classes
**Then** the package contains ≥ 2 Business Processes:
  - `Sample.BP.OrderRouter` (BPL or simple `Ens.BusinessProcess` — routes by order type; sends to validator + persist; returns response)
  - `Sample.BP.OrderValidator` (validates line items + total; emits inline events; returns OK or rejection; injection point for `businessProcessFailure` mode)

**And** the package contains ≥ 2 Business Operations:
  - `Sample.BO.SqlPersist` (writes order to a `Sample.Persist.OrderRow` persistent class — adapter-less or stub adapter; injection point for `businessOperationFailure` mode)
  - `Sample.BO.FilePublish` (writes a stub file payload to a temp dir — second injection point for `businessOperationFailure`)

**And** the routing BP dispatches synchronously to validator first, then async to both BOs.

### AC-3 — Rich message bodies

**Given** the developer is shipping the message-class definitions
**When** they create `Sample.Msg.OrderRequest` (extends `Ens.Request`) and `Sample.Msg.OrderResponse` (extends `Ens.Response`)
**Then** `OrderRequest` has at least 5 properties: `OrderId %String`, `CustomerName %String`, `OrderTimestamp %TimeStamp`, `LineItems %ListOfDataTypes` (each item: `sku|qty|price`), `TotalAmount %Numeric` — plus optional `Notes %String(MAXLEN=1000)` for richer narrative
**And** `OrderResponse` has `OrderId`, `Status %String("Approved,Rejected,PartialApproval")`, `RejectionReason %String`, `ProcessedTimestamp %TimeStamp`, `PersistedRowId %Integer`
**And** `Sample.Persist.OrderRow` (the SqlPersist target) is a `%Persistent` class with the same shape so SQL queries work for the agent.

### AC-4 — Operator-invoked bootstrap

**Given** the developer is implementing the install path
**When** the operator runs `Do ##class(SessionAgent.Sample.Bootstrap).InstallProduction()`
**Then** the helper creates an Ens production `SessionAgent.Sample.Production` containing all BS/BP/BO items configured + sets `AutoStart=1` (or leaves disabled with a clear console log instructing the operator to start it manually)
**And** the helper is idempotent — re-running on an existing install does not duplicate or break anything
**And** the helper logs a one-line operator instruction: *"Sample production installed. Run scenarios via: Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario(\"none\")"*
**And** a sibling `UninstallProduction()` helper exists for cleanup

### AC-5 — Excluded from IPM `<Resource>`

**Given** the developer is wiring module.xml
**When** they edit module.xml
**Then** the `Sample.*` classes are NOT included in `<Resource Name="SessionAgent.PKG"/>` — the package is excluded from the IPM install path so it's clearly a test fixture, not runtime
**And** the README explains the rationale + the operator-invoked install path
**And** verification: running `Status` on `^oddDEF` (or equivalent class-load probe) confirms `SessionAgent.Sample.*` classes load fine in dev (auto-sync workflow handles compile) but `zpm install iris-session-agent` would NOT compile them on a fresh install (acceptable — they're operator-invoked)

### AC-6 — Walkthrough re-run via chrome-devtools-mcp

**Given** the maintainer re-runs the Story 3.7 chrome-devtools-mcp walkthrough against the sample production
**When** they exercise at least one scenario WITH errors (e.g., `pErrorMode="businessOperationFailure"`)
**Then** the agent dispatches multiple tools across the multi-step trace
**And** the agent's final answer references real error context (status codes, error text, source/target config names from the sample production)
**And** the walkthrough closes the partial portion of PRD MVP Exit Criterion #2 ("≥1 operator self-reports a real diagnosis happening through the agent" — capability demonstrated against real-shape data)
**And** transcript captured in story Completion Notes (lead-driven AC-6 execution, post-commit)

### AC-7 — Tests

**Given** the developer ships the test class
**When** they add `SessionAgent.Test.SampleProductionTest`
**Then** at least 3 unit tests are present:
  - `TestSampleProductionStarts` — invokes `Bootstrap.InstallProduction` + verifies the production exists + can be started; cleanup via `UninstallProduction`
  - `TestScenariosProduceExpectedMessageCounts` — invokes `RunScenario("none")` + asserts ≥4 Ens.MessageHeader rows produced for the new session id (BS → BP → 2 BOs minimum)
  - `TestErrorInjectionProducesExpectedIsErrorCounts` — invokes `RunScenario("businessOperationFailure")` + asserts ≥1 Ens.MessageHeader row with IsError=1 in the new session

**And** per-class compile sweep is clean
**And** authoritative test count grows by ≥ 3

### AC-8 — Compile + regression intact

- `iris_doc_compile` clean for all `SessionAgent.Sample.*` classes + `SessionAgent.Test.SampleProductionTest`
- Story 3.8's `AgentLoopGuardsTest.RunTurnAppendsCrossSessionNotice` still PASS (unrelated change — sanity check)
- Authoritative test count via SQL: 158 + ≥3 = **161+**
- Sample production CAN start + RunScenario("none") completes successfully on the dev install (operator-invoked verification)

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight surface probe (Rule 4)**
  - [x] Confirm `Ens.BusinessService`, `Ens.BusinessProcess`, `Ens.BusinessOperation`, `Ens.Request`, `Ens.Response` are reachable via `iris_doc_get` — all five exist (etag 2025-06-04). `Ens.Production` + `Ens.Director` also confirmed.
  - [x] Read sibling adapterless BS example from `irislib/Ens/Director.cls` — canonical pattern is `Ens.Director.CreateBusinessService(pTargetDispatchName, .pBS)` (line 1401). It instantiates the BS with proper `tConfigName` context + handles SuperSession + checks `IsProductionRunning()` + `ConfigIsEnabled(tConfigName)` first. After that, the BS exposes `..SendRequestSync()` / `..SendRequestAsync()` (line 135 / 177 of `Ens.BusinessService`). Method signatures verified: BS `OnProcessInput(pInput,Output pOutput,ByRef pHint) As %Status`, BP `OnRequest(request, Output response) As %Status` + `OnResponse(...)` + `OnComplete(...)`, BO `OnMessage(pRequest,Output pResponse) As %Status`.
  - [x] Confirmed `<Resource Name="SessionAgent.PKG"/>` is a single all-inclusive package resource — it WILL pick up `SessionAgent.Sample.*` automatically. Per spec Dev Notes, accept option (c) — Sample classes load + compile via auto-sync / zpm, but no production runs unless operator explicitly invokes `Bootstrap.InstallProduction()`. That is the intended posture; no exclusion mechanism needed since the Production class itself is dormant until registered via `Ens.Config.Production.LoadFromClass()`.

- [x] **Task 1 — Implement message classes (AC: #3)**
  - [x] `src/SessionAgent/Sample/Msg/OrderRequest.cls` — extends Ens.Request; OrderId/CustomerName/OrderTimestamp/LineItems/TotalAmount/Notes (6 properties — exceeds AC-3 minimum of 5).
  - [x] `src/SessionAgent/Sample/Msg/OrderResponse.cls` — extends Ens.Response; OrderId/Status (VALUELIST)/RejectionReason/ProcessedTimestamp/PersistedRowId.
  - [x] `src/SessionAgent/Sample/Persist/OrderRow.cls` — %Persistent; OrderId/CustomerName/OrderTimestamp/TotalAmount/SkuList/Status/PersistedAt + OrderIdIdx + StatusIdx; storage auto-generated by compiler. All three compile clean (`iris_doc_compile` 358ms).

- [x] **Task 2 — Implement Business Operations (AC: #2)**
  - [x] `src/SessionAgent/Sample/BO/SqlPersist.cls` — extends Ens.BusinessOperation; OnMessage receives OrderRequest, persists to OrderRow, returns OrderResponse (Status + PersistedRowId). Reads `pRequest.ErrorMode` (carried on the message body — see Empirical-Discovery note below) and throws `$$$EnsErrGeneral` under "businessOperationFailure". Includes XData MessageMap binding OrderRequest → OnMessage. Compiles clean.
  - [x] `src/SessionAgent/Sample/BO/FilePublish.cls` — extends Ens.BusinessOperation; writes stub file under `$System.Util.ManagerDirectory()/Temp/` via `%Stream.FileCharacter` (deterministic location, no env-var dependency). Throws under both "businessOperationFailure" and "partialSuccess" error modes (so partialSuccess persists SQL row but fails the file publish, producing a mixed-IsError trace). Compiles clean.

- [x] **Task 3 — Implement Business Processes (AC: #2)**
  - [x] `src/SessionAgent/Sample/BP/OrderValidator.cls` — extends Ens.BusinessProcess; `OnRequest(pRequest, Output pResponse)`; validates line-item count, total > 0, qty > 0 per item; emits `$$$LOGINFO`/`$$$LOGWARNING`; returns OrderResponse; reads `pRequest.ErrorMode` for businessProcessFailure injection. Compiles clean.
  - [x] `src/SessionAgent/Sample/BP/OrderRouter.cls` — extends Ens.BusinessProcess with persistent OrderId/FinalStatus/FailureNotes/PersistedRowId/Persist*Done/Persist*Failed properties; `OnRequest` validates synchronously then fans out async to both BOs with completion keys "persist"/"publish"; `OnResponse` + `OnError` accumulate per-child outcomes; `OnComplete` derives Approved/Rejected/PartialApproval from flags. Compiles clean.

- [x] **Task 4 — Implement adapterless Business Service (AC: #1)**
  - [x] `src/SessionAgent/Sample/BS/OrderIngest.cls` — extends Ens.BusinessService; `OnProcessInput` returns `$$$NotImplemented` (adapterless); `ClassMethod RunScenario(pErrorMode, pConfigName, Output pSessionId) As %Status` validates pErrorMode against {"none","businessProcessFailure","businessOperationFailure","partialSuccess"}, calls `Ens.Director.CreateBusinessService` to obtain the BS instance, builds the OrderRequest with the `ErrorMode` property tagged (see Empirical-Discovery note), dispatches via `tBS.SendRequestAsync` to `SessionAgent.Sample.BP.OrderRouter`. Returns the assigned SessionId via output param so tests can probe `Ens.MessageHeader`. Compiles clean.
  - [x] Scenario-driven shape variation: `none`→3 line items, `partialSuccess`→5, `businessOperationFailure`→1, `businessProcessFailure`→2. OrderId is `ORD-NNNNNN` from `$Increment(^SessionAgent.Sample.OrderCounter)`. Customer drawn from a 5-name roster (Acme/Globex/Initech/Umbrella/Stark); SKU drawn from a 10-product catalog.

- [x] **Task 5 — Implement Bootstrap (AC: #4)**
  - [x] `src/SessionAgent/Sample/Production.cls` — Ens.Production subclass with XData ProductionDefinition listing all 5 items (BS, OrderRouter, OrderValidator, SqlPersist, FilePublish), all Enabled=true.
  - [x] `src/SessionAgent/Sample/Bootstrap.cls` — `Include Ensemble`; `InstallProduction()` checks the Production class compiled then calls `Ens.Config.Production.LoadFromClass()` (idempotent — LoadFromClass deletes + re-creates the row); `UninstallProduction()` stops if running + deletes Ens.Config.Production row; `StartProductionIfStopped()` helper for tests + walkthrough use; logs operator instructions to current device. All compile clean.

- [x] **Task 6 — Update module.xml + README (AC: #5)**
  - [x] Per Task 0 probe + Dev Notes "module.xml exclusion" section, accepted option (c): Sample.* classes WILL load via `<Resource Name="SessionAgent.PKG"/>` (no IPM exclusion mechanism needed for the package-prefix wildcard) but the production is dormant until operator explicitly invokes Bootstrap. AC-5 verification clause acknowledges this: *"acceptable — they're operator-invoked"*. module.xml not modified.
  - [x] README: added "Sample interoperability production for testing" section after the Browser-support block, with the production graph, the operator workflow (InstallProduction → StartProduction → RunScenario → optional UninstallProduction), and a 4-row scenario / outcome matrix.

- [x] **Task 7 — Implement tests (AC: #7)**
  - [x] `src/SessionAgent/Test/SampleProductionTest.cls` — 3 test methods: TestSampleProductionStarts, TestScenariosProduceExpectedMessageCounts, TestErrorInjectionProducesExpectedIsErrorCounts. `Include Ensemble` for `$$$eProductionStateRunning` macro. `%OnNew(initvalue)` calls `##super(initvalue)`.
  - [x] OnBeforeAllTests calls `Bootstrap.InstallProduction` + `StartProductionIfStopped`; OnAfterAllTests calls `UninstallProduction` for clean state restore.
  - [x] Helpers `waitForTrace` (polls Ens.MessageHeader, hangs in 0.5s increments up to 15s), `countTraceRows`, `countIsErrorRows` for SQL probes by SessionId.
  - [x] Tests verified individually: SampleProductionStarts PASS (0.8ms), ScenariosProduceExpectedMessageCounts PASS (505ms), ErrorInjectionProducesExpectedIsErrorCounts PASS (516ms). Class-level run reports 2 of 3 (consistent with documented MCP test-runner truncation pattern in `AgentLoopTestBase` doc); each test class-level call also runs OnBeforeAllTests/OnAfterAllTests, confirming the install/uninstall cycle is clean.

- [x] **Task 8 — Compile + regression sweep (AC: #8)**
  - [x] `iris_doc_compile ck` clean for all 9 new classes (3 messages/persist + 2 BPs + 2 BOs + Production + Bootstrap) + 1 test class.
  - [x] Adjacent regression intact: AgentLoopGuardsTest 3/3 PASS (RunTurnAppendsCrossSessionNotice PASS — Story 3.8 sanity check satisfied), VisualTraceTest 7/7 PASS, InspectionToolTest 15/15 PASS.
  - [x] Authoritative test count via SQL: `SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE parent %STARTSWITH 'SessionAgent.Test.' AND %EXACT(Name) %STARTSWITH 'Test'` = **161** (exactly matches spec target 158 + 3).
  - [x] Operator-invoked verification (live):
    - `InstallProduction()` succeeded; logged operator instructions to console.
    - `StartProductionIfStopped()` succeeded; `Ens.Director.GetProductionStatus` returned `state=1` (Running), `running="SessionAgent.Sample.Production"`.
    - `RunScenario("none")` → SessionId=258, **7 Ens.MessageHeader rows** (≥4 satisfied), 0 IsError rows.
    - `RunScenario("businessOperationFailure")` → SessionId=265, **7 rows total, 2 IsError=1 rows** (rows 270 + 271 — the BO→Router error responses; ≥1 satisfied).

- [~] **Task 9 — Lead-driven walkthrough re-run (AC: #6)** — partial; spec note "lead-driven AC-6 execution, post-commit". The dev agent does NOT drive chrome-devtools-mcp (per delegation; lead drives this after the commit lands). Sample production is verified live and ready for the lead's walkthrough run against the businessOperationFailure SessionId.

## Dev Notes

### Why "adapterless" BS

A standard Business Service uses an inbound adapter (file-watch, TCP listen, REST endpoint) to trigger work. For this sample, we don't want to require operator setup of inbound infrastructure — instead, the BS exposes a `RunScenario` ClassMethod that operators invoke directly. The BS still extends `Ens.BusinessService` so it participates in the production graph + audit trail, but its `OnProcessInput` is never called by an adapter; instead `RunScenario` calls `..SendRequestAsync` directly. This is a documented Ensemble pattern (see Ensemble docs §"Adapterless Business Services").

### Error-injection mechanism (revised during dev — Empirical-Discovery)

**Original spec:** use a process-private global `^||SessionAgentSampleErrorMode` set by `RunScenario` before dispatch + read by BPs/BOs.

**Empirical reality (caught during Task 8 verification):** Ensemble BPs and BOs run in their own dedicated job processes (PoolSize=1), separate from the operator-invoked process that calls `RunScenario`. Process-private globals (`^||...`) are scoped to a single process — the BPs/BOs cannot see them. The first live RunScenario("businessOperationFailure") run produced the expected 7 message-header rows but **0 IsError=1 rows** because the BOs never read the injected error mode and ran the happy path.

**Fix applied in same dev cycle:** added an `ErrorMode As %String(MAXLEN = 64)` property to `SessionAgent.Sample.Msg.OrderRequest` (default "none"). The signal travels with the message body itself, so it survives the cross-process dispatch + persists across the OnRequest/OnResponse async cycle. BPs/BOs read `pRequest.ErrorMode` instead of the process-private global. Re-verification post-fix: businessOperationFailure produced 7 rows with **2 IsError=1 rows** (rows 270 + 271 in the empirical run — the BO error responses back to OrderRouter). Class-level test run confirms `TestErrorInjectionProducesExpectedIsErrorCounts` passes (1 of 1 IsError row asserted; got 2).

This is a textbook case of Rule 5 (one-liner check before deferring) saving the day — the Task 8 empirical battery caught the mismatch between spec assumption and runtime reality, the fix was a 4-line change (add property + read it in 3 BP/BO files), no deferral needed.

### Sample data richness

OrderRequest needs 5–10 fields rich enough that:
- `session_summary` produces a non-trivial output (mentions order id, customer, status)
- `session_timeline` shows multi-step progression with timestamps
- `message_headers` filtered by `min_severity=error` returns the right rows when an error scenario runs

Make the seed data deterministic-but-realistic (e.g., `OrderId = "ORD-" _ $Increment(^Sample.OrderCounter)`, `CustomerName = "Acme Corp"` or one of 5 hardcoded values, line items chosen from a 10-product catalog).

### Architecture: where do Sample.* classes live in the source tree

Mirror the production structure: `src/SessionAgent/Sample/{BS,BP,BO,Msg,Persist}/`. Per the project rule §"Naming Conventions" — all custom classes under `SessionAgent.*`. Sample is a sub-package, fits cleanly.

### Module.xml exclusion

Probably the simplest path is a code-level marker (the package is named Sample.* + README warns operators) rather than a complex IPM exclude-pattern. The classes will compile when zpm loads them, but they don't AUTO-START because no production references them at install time. Operators must explicitly run Bootstrap. This is acceptable — the production stays dormant until invoked.

If a stricter exclusion is desired, IPM supports `<ExcludeMatching>` patterns — investigate during dev if Task 6 finds the auto-load is problematic.

### Order of operations

1. Task 0 probe.
2. Tasks 1-4 (data → BO → BP → BS) — bottom-up.
3. Task 5 Bootstrap.
4. Task 6 module.xml + README.
5. Task 7 tests + Task 8 sweep.
6. Task 9 lead walkthrough re-run (post-commit).

### Sources

- [`epics.md`](../planning-artifacts/epics.md) §"Story 3.9" — full ACs.
- [`sprint-change-proposal-2026-05-03.md`](../planning-artifacts/sprint-change-proposal-2026-05-03.md) §"Change 4.3" — story scope.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Ensemble Architecture Guidance" — BS/BP/BO method-signature rules.
- Story 2.11's existing inspection tools (`session_summary` / `session_timeline` / `message_headers`) — verified to dispatch against the new sessions.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 2, 3, 4, 8.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m]

### Completion Notes List

**Task 0 — Pre-flight surface probe outputs (Rule 4):**
- `iris_doc_get` confirmed all five Ens.* base classes exist (etag 2025-06-04 18:37): Ens.BusinessService, Ens.BusinessProcess, Ens.BusinessOperation, Ens.Request, Ens.Response. Ens.Production + Ens.Director also confirmed.
- Adapterless BS pattern verified in `irislib/Ens/Director.cls` lines 1397-1473 — canonical entry is `Ens.Director.CreateBusinessService(pTargetDispatchName, .pBS) As %Status`. After successful create, the BS instance exposes `..SendRequestSync()` (line 135) + `..SendRequestAsync()` (line 177) of `irislib/Ens/BusinessService.cls`. Method signatures confirmed: BS `OnProcessInput(pInput, Output pOutput, ByRef pHint) As %Status`; BP `OnRequest(request, Output response) As %Status` + `OnResponse(...)` + `OnComplete(...)`; BO `OnMessage(pRequest, Output pResponse) As %Status`.
- Production-class registration: `Ens.Config.Production.LoadFromClass(pClassName)` (line 167) parses XData ProductionDefinition + saves the production + child Ens.Config.Item rows; idempotent because LoadFromClass first deletes any existing row.
- module.xml exclusion: `<Resource Name="SessionAgent.PKG"/>` is a single all-inclusive package wildcard. Per Dev Notes acceptance, Sample.* classes load via the resource but the production stays dormant until operator invokes Bootstrap.

**Empirical-Discovery during Task 8 — Error-injection mechanism revised:**
The original spec used a process-private global `^||SessionAgentSampleErrorMode` set by RunScenario before dispatch. Live verification revealed this does NOT work: BPs/BOs run in their own dedicated jobs (separate processes), so process-private globals from the operator-invoked process are invisible to them. First boFail run produced 7 rows but 0 IsError rows. Fix: added `ErrorMode As %String` property to OrderRequest so the signal travels with the message body itself across the cross-process dispatch boundary. Re-verification post-fix: 2 IsError rows as expected. Rule 5 win — caught + fixed in same dev cycle, no deferral.

**Operator-invoked verification (live, post all fixes):**
- `Bootstrap.InstallProduction()` succeeded — logged operator instructions to console.
- `Bootstrap.StartProductionIfStopped()` succeeded; `Ens.Director.GetProductionStatus()` returned state=1 (Running).
- `RunScenario("none")` → SessionId=**327**, status=$$$OK, **7 Ens.MessageHeader rows** (≥4 AC threshold satisfied), 0 IsError rows.
- `RunScenario("businessOperationFailure")` → SessionId=**334**, status=$$$OK, **7 rows total, 2 IsError=1 rows** (the BO→Router error responses; ≥1 AC threshold satisfied).
- `Bootstrap.UninstallProduction()` succeeded — dev install returned to baseline.

**Authoritative test count via SQL:** `SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE parent %STARTSWITH 'SessionAgent.Test.' AND %EXACT(Name) %STARTSWITH 'Test'` = **161** (matches spec target 158 + 3 = 161+).

**Test results:**
- New tests: SampleProductionTest 3/3 PASS individually (TestSampleProductionStarts 0.8ms; TestScenariosProduceExpectedMessageCounts 505ms; TestErrorInjectionProducesExpectedIsErrorCounts 516ms). Class-level run reports 2 of 3 — known MCP test-runner truncation pattern documented in `AgentLoopTestBase` (the 0.5s `Hang` polling loops in two of the three tests likely trip the runner's per-class budget). All three pass when executed individually; production install/uninstall cycles in OnBefore/OnAfter run cleanly each time.
- Adjacent regression intact: AgentLoopGuardsTest 3/3 PASS (RunTurnAppendsCrossSessionNotice — Story 3.8 sanity check satisfied), VisualTraceTest 7/7 PASS, InspectionToolTest 15/15 PASS.

**module.xml strategy (AC-5):** Per Dev Notes acceptance of option (c), classes load via `<Resource Name="SessionAgent.PKG"/>` but production stays dormant until operator runs Bootstrap. No exclusion mechanism added; README documents the operator workflow + the test-fixture posture.

**AC-6 walkthrough re-run:** post-commit, lead-driven via chrome-devtools-mcp. The dev agent does not drive the browser; sample production is verified live and operational, ready for the lead's walkthrough run against a businessOperationFailure SessionId after the commit lands.

### File List

**New files (10):**
- `src/SessionAgent/Sample/Msg/OrderRequest.cls` — Ens.Request subclass (6 properties + ErrorMode signal carrier)
- `src/SessionAgent/Sample/Msg/OrderResponse.cls` — Ens.Response subclass (5 properties)
- `src/SessionAgent/Sample/Persist/OrderRow.cls` — %Persistent storage class with OrderId + Status indices
- `src/SessionAgent/Sample/BS/OrderIngest.cls` — adapterless Ens.BusinessService with `RunScenario(pErrorMode, pConfigName, Output pSessionId) As %Status`
- `src/SessionAgent/Sample/BP/OrderValidator.cls` — Ens.BusinessProcess; validates line items + total
- `src/SessionAgent/Sample/BP/OrderRouter.cls` — Ens.BusinessProcess; sync→Validator + async→{Persist,Publish} with per-child OnResponse + OnError + OnComplete state machine
- `src/SessionAgent/Sample/BO/SqlPersist.cls` — Ens.BusinessOperation; persists to OrderRow
- `src/SessionAgent/Sample/BO/FilePublish.cls` — Ens.BusinessOperation; writes stub file under mgr/Temp/
- `src/SessionAgent/Sample/Production.cls` — Ens.Production with XData ProductionDefinition listing all 5 items
- `src/SessionAgent/Sample/Bootstrap.cls` — InstallProduction + UninstallProduction + StartProductionIfStopped helpers
- `src/SessionAgent/Test/SampleProductionTest.cls` — 3 unit tests per AC-7 + waitForTrace helper

**Modified files (2):**
- `_bmad-output/implementation-artifacts/3-9-sample-interoperability-production-and-walkthrough-rerun.md` — task checkboxes, completion notes, file list, status flip to "review"
- `README.md` — added "Sample interoperability production for testing" section (operator workflow + scenario/outcome matrix) between Browser-support and What-it-does sections

**module.xml: NOT modified** — AC-5 accepted option (c) (classes load via SessionAgent.PKG resource but production is dormant until operator-invoked).

### Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-03 | Story 3.9 implementation complete — 9 new sample-production classes + 1 test class (3 tests) + README operator section. All compiles clean (`iris_doc_compile ck`); authoritative test count = 161 (target 161+); operator-invoked InstallProduction + RunScenario("none") (SessionId 327, 7 rows) + RunScenario("businessOperationFailure") (SessionId 334, 7 rows / 2 IsError) verified live; UninstallProduction returns dev install to baseline. AC-6 lead-driven walkthrough deferred to post-commit (lead's responsibility per spec). Empirical-Discovery: error-injection signal switched from `^||SessionAgentSampleErrorMode` process-private global to `OrderRequest.ErrorMode` property (BPs/BOs run in dedicated jobs and cannot see caller's process-private globals). | dev (claude-opus-4-7) |
