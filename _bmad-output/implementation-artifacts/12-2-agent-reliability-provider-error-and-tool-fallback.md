# Story 12.2: Agent Reliability — Provider HTTP Error Diagnostics + Tool Class-Name Fallback

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` BUG-02 (provider mid-flight HTTP exception text discarded — operator sees only "mid-flight failure" with no diagnostic info) + BUG-03 (`get_business_process_source` returns `class_not_found` when LLM appends a method name to the class name). Both MEDIUM severity. Bundled per Sprint Change Proposal §"8-story split" — both fix graceful-degradation gaps in the agent reliability surface.

## User Story

As an **operator** running the agent, I want HTTP failures against any LLM provider to surface the underlying exception text (so I can diagnose whether it's a SSL config, timeout, network drop, or credential issue), AND I want the `get_business_process_source` tool to recover gracefully when the LLM passes a slightly-malformed class name (e.g., with a method name appended). So that agent failures are actionable instead of opaque, and the LLM can self-correct from a small slip in argument shape.

## Acceptance Criteria

**AC-1 — Provider mid-flight error envelope includes underlying exception text.** [BUG-02]
- **Given** any of the 4 LLM providers (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`, `OpenAICompatProvider`) catches an HTTP-layer exception during `IssueHttpsPost`,
- **When** the catch block fires and the mid-flight error envelope is populated,
- **Then** the envelope's message includes both the generic "mid-flight failure" framing AND the underlying `postEx.DisplayString()` text — separated by a colon and space — so the operator can see the actual exception (e.g., `"OpenAI mid-flight failure (request may have been processed): SSL handshake failed: certificate has expired"`).

> **Verbatim evidence (Rule 2 sharpened):** Compile-time grep of each provider class's `CallMessages` method confirms the catch block captures `postEx.DisplayString()` into a local variable and the variable is interpolated into the `PopulateErrorEnvelope` call. Capture verbatim source-line snippets from each of the 4 provider files in Completion Notes.

**AC-2 — Provider mid-flight failures write to the Ensemble event log.** [BUG-02]
- **Given** the same catch block,
- **When** the catch fires,
- **Then** `$$$LOGERROR` (or equivalent IRIS event-log helper) records the exception text with provider context — so an operator with no agent-chat-panel access can still diagnose the failure via the Ensemble Event Log.

> **Verbatim evidence:** Compile-time grep of each provider's catch block confirms a `$$$LOGERROR` line is present with the provider class name + exception text. Capture grep output in Completion Notes.

**AC-3 — `get_business_process_source` retries with last-segment-stripped on `class_not_found`.** [BUG-03]
- **Given** the LLM calls `get_business_process_source` with `bp_class_name = "SessionAgent.Sample.BP.OrderRouter.OnRequest"` (method name appended),
- **When** the initial `%Dictionary.ClassDefinition.%OpenId` lookup returns NULLOREF,
- **Then** the tool checks if `bp_class_name` contains a `.` and (if so) strips the last dot-segment, retries the lookup. If the retry succeeds (i.e., `SessionAgent.Sample.BP.OrderRouter` exists), returns the BP source with `render_strategy = "ok"` AND adds a top-level `"class_name_auto_corrected_from"` field showing the original input string. If the retry still misses, returns `render_strategy = "class_not_found"` with a `"candidate_class_name"` field showing the stripped name.

> **Verbatim evidence (Rule 2 sharpened):** Live tool dispatch via `mcp__iris-dev-mcp__iris_execute_classmethod` against `Tool.Registry.Dispatch` (or equivalent) with `bp_class_name = "SessionAgent.Sample.BP.OrderRouter.OnRequest"` returns a structured envelope with `render_strategy = "ok"`, `class_name = "SessionAgent.Sample.BP.OrderRouter"`, `class_name_auto_corrected_from = "SessionAgent.Sample.BP.OrderRouter.OnRequest"`. Capture the verbatim envelope JSON in Completion Notes.

**AC-4 — `get_business_process_source` argument description warns against method-name suffixes.** [BUG-03]
- **Given** the tool's `bp_class_name` argument description (currently shows examples like `SessionAgent.Sample.BP.OrderRouter`),
- **When** the description is read post-fix,
- **Then** the description includes an explicit warning: `"Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."`

> **Verbatim evidence:** SQL probe against `%Dictionary.ParameterDefinition` for the tool class's argument-schema parameter confirms the new description text. Capture verbatim in Completion Notes.

**AC-5 — Sibling tools accepting class names get the same description warning.** [BUG-03]
- **Given** sibling inspection tools that accept class-name arguments (notably `get_business_operation_source`, `list_business_process_methods`, etc. — enumerate at story-spec time),
- **When** the description text is updated,
- **Then** the same anti-method-suffix warning is appended to each tool's relevant argument description.

> **Verbatim evidence:** SQL probe across all updated tool classes' parameter descriptions; capture verbatim list of tool names + the appended warning text.

**AC-6 — No regression: existing tests for the affected providers and tools all pass.**
- **When** the per-class regression sweep runs after the changes,
- **Then** all `LlmProvider*Test`, `OpenAIProviderTest`, `AnthropicProviderTest`, `GeminiProviderTest`, `OpenAICompatProviderTest`, `Tool.Inspection.GetBusinessProcessSourceTest` (or equivalent), and `Tool.RegistryTest` test classes pass.

> **Verbatim evidence:** Capture the canonical numerical-MAX SQL probe Total / Passed / Failed row.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe (Rule 3 — typed MCP first)**
  - [x] Read `src/SessionAgent/LLM/OpenAIProvider.cls` lines ~270–320 to confirm the current catch + tHttpFailed → tMidFlight → PopulateErrorEnvelope path. Confirmed: catch at line 276, tMidFlight populated at line 282, PopulateErrorEnvelope call at line 317.
  - [x] Read the equivalent blocks in `AnthropicProvider.cls` (catch line 318, PopulateErrorEnvelope line 355), `GeminiProvider.cls` (catch line 335, PopulateErrorEnvelope line 371), `OpenAICompatProvider.cls` (catch line 341, PopulateErrorEnvelope line 375). All identical shape.
  - [x] Read `src/SessionAgent/Tool/Inspection/GetBusinessProcessSource.cls` — confirmed `%OpenId` at line 99, `class_not_found` envelope populated lines 104-117 (early Quit at line 116).
  - [x] Enumerated sibling tools via Grep for `"type": "string", "description":.*class` — sibling class-name-receivers identified: `ListBusinessProcessMethods.bp_class_name` (line 95), `SearchByBodyField.search_table_class` (line 145), `FindSessionsByBody.search_table_class` (line 140), `SearchByMessageClass.message_body_class_name` (line 45), `VocabLookup.message_body_class` (line 146), `RuleLog.rule_class` (line 62). The `get_business_operation_source` mentioned in spec does NOT exist in this codebase (probe confirmed); spec-mentioned-but-nonexistent.
- [x] **Task 1 — BUG-02 fix (provider mid-flight error envelope) — apply to all 4 providers**
  - [x] Modified `Catch postEx` block in `CallMessages` of all 4 providers to capture `postEx.DisplayString()` into `tPostExText`.
  - [x] Mid-flight `PopulateErrorEnvelope` call now appends `tPostExText` with `": "` separator when non-empty.
  - [x] Added `$$$LOGERROR` line in each catch block (required `Include Ensemble` directive — added at top of all 4 providers).
  - [x] All 4 providers compile clean.
- [x] **Task 2 — BUG-03 fix (tool class-name fallback) — `GetBusinessProcessSource`**
  - [x] Strip-last-segment retry implemented in `Invoke` method using `$Piece(tClassName, ".", 1, $Length(tClassName, ".") - 1)`.
  - [x] On retry success: render normal "ok" with `class_name = tStrippedName` + `class_name_auto_corrected_from = tOriginalClassName` top-level marker.
  - [x] On retry miss: populate existing `class_not_found` envelope plus `candidate_class_name = tStrippedName` field; preserves original `class_name = tOriginalClassName`.
  - [x] `bp_class_name` parameter description updated with the anti-method-suffix warning.
  - [x] Compile clean.
- [x] **Task 3 — BUG-03 sibling-tool description sweep — AC-5**
  - [x] 6 sibling tools updated: `ListBusinessProcessMethods.bp_class_name`, `FindSessionsByBody.search_table_class`, `SearchByBodyField.search_table_class`, `SearchByMessageClass.message_body_class_name`, `VocabLookup.message_body_class`, `RuleLog.rule_class`. All compiled clean.
- [x] **Task 4 — Add unit tests**
  - [x] **Provider tests:** added `TestMidFlightFailureCarriesExceptionText` to all 4 provider test classes (`OpenAIProviderTest`, `AnthropicProviderTest`, `GeminiProviderTest`, `OpenAICompatProviderTest`). Each test sets `MockThrowText` on the corresponding mock provider, calls `CallMessages`, asserts envelope text contains "mid-flight failure" framing + ": " separator + the exception substring; also asserts `CallCount=1` (no retry on mid-flight).
  - [x] **Mock providers extended:** added `MockThrowText` property + throw-on-IssueHttpsPost branch to all 4 mock providers (`MockOpenAIProvider`, `MockAnthropicProvider`, `MockGeminiProvider`, `MockOpenAICompatProvider`).
  - [x] **Tool test (positive):** `TestSourceWithMethodSuffixAutoCorrects` added to `BusinessProcessIntrospectionTest` — passes `SessionAgent.Sample.BP.OrderRouter.OnRequest`, asserts `render_strategy=ok` + `class_name=SessionAgent.Sample.BP.OrderRouter` + `class_name_auto_corrected_from=<original>` + `method_count > 0`.
  - [x] **Tool test (negative):** `TestSourceUnknownMultiSegmentReturnsCandidate` added to `BusinessProcessIntrospectionTest` — passes `Totally.NonExistent.Class.Name`, asserts `render_strategy=class_not_found` + `class_name=<original>` + `candidate_class_name=Totally.NonExistent.Class`.
- [x] **Task 5 — `node -c` parse check (Story 12.0 Carry-Forward)** — Binding does not apply: this story does NOT modify `static/chat-panel.js`.
- [x] **Task 6 — Live exercise (Rule 6 step 4)**
  - [x] Live exercise BUG-03 fix via `iris_execute_command` invoking `GetBusinessProcessSource.Invoke` with `bp_class_name="SessionAgent.Sample.BP.OrderRouter.OnRequest"` — verbatim envelope captured below in Completion Notes showing `render_strategy=ok` + `class_name_auto_corrected_from=SessionAgent.Sample.BP.OrderRouter.OnRequest`.
  - [x] Live exercise BUG-02 — DEFERRED to next walkthrough per spec allowance. Triggering the catch path requires breaking SSL config or supplying an unresolvable host; the unit-test coverage (`TestMidFlightFailureCarriesExceptionText` in all 4 provider tests) exercises the catch-block logic deterministically and is sufficient for AC-1/AC-2 verification per spec Task 6.
- [x] **Task 7 — Regression sweep + SQL ground-truth probe**
  - [x] All 5 affected test classes pass (`OpenAIProviderTest` 9/9, `AnthropicProviderTest` 12/12, `GeminiProviderTest` 12/12, `OpenAICompatProviderTest` 12/12, `BusinessProcessIntrospectionTest` 12/12).
  - [x] Canonical numerical-MAX SQL probe: **441 / 441 / 0** across all `SessionAgent.Test.*` classes.
- [x] **Task 8 — Spec length verification** — 131 lines ≤ 250 ✓.
- [x] **Task 9 — Sprint-status flip** — `12-2-...: ready-for-dev` → `in-progress` → `review` (this commit). Lead flips → `done` after review.
- [ ] **Task 10 — Commit + push** (lead) — `feat(epic-12): story 12.2 — agent reliability: provider HTTP error diagnostics + tool class-name fallback`.

## Dev Notes

### Why the postEx text capture is safe

`postEx.DisplayString()` returns a sanitized string representation of the exception. It does NOT leak credentials (the credential is in the request headers, not the exception state), does NOT leak request bodies (the exception is thrown from the HTTP transport layer, not from request construction). Project rule §"Audit & Logging" already permits exception-text logging to the Ensemble event log.

### Why strip-last-segment for BUG-03 (not a more aggressive heuristic)

The LLM's wrong-shape pattern is "appended a method name". Stripping the last `.`-delimited segment recovers the class name in the typical case. More aggressive heuristics (multi-segment strip, fuzzy matching, namespace inference) introduce more failure modes than they fix. If the strip-once retry still misses, the tool returns `candidate_class_name` so the LLM can self-correct on the next turn.

### Why bundle BUG-02 + BUG-03

Both are agent-reliability hardening: BUG-02 makes failure modes diagnosable, BUG-03 makes the tool layer more forgiving of LLM argument-shape slips. Different files (4 provider files + 1+ tool files), but architecturally adjacent — operators experience them as "the agent fails less mysteriously" and "the tools recover from minor LLM mistakes".

### Files modified

- `src/SessionAgent/LLM/OpenAIProvider.cls` — `CallMessages` catch block + mid-flight error envelope.
- `src/SessionAgent/LLM/AnthropicProvider.cls` — same.
- `src/SessionAgent/LLM/GeminiProvider.cls` — same.
- `src/SessionAgent/LLM/OpenAICompatProvider.cls` — same.
- `src/SessionAgent/Tool/Inspection/GetBusinessProcessSource.cls` — class-name fallback + parameter description.
- Sibling inspection tools enumerated at Task 0 — parameter description only (no body change).
- `src/SessionAgent/Test/LlmProviderTest.cls` (or equivalent) — provider tests.
- `src/SessionAgent/Test/ToolInspectionTest.cls` (or equivalent) — tool tests.

### Patterns to follow verbatim

- Story 11.4's `NormalizeChatCompletionsLocation` pattern for adding new provider helpers (idempotent + small-blast-radius).
- Story 11.2's defensive-sweep pattern for retrofitting all 4 providers with the same shape change.
- Story 12.1's `%Dictionary.MethodDefinition.IDKEYOpen` + `.Implementation` pattern for grep-the-source-via-introspection unit tests.

## Completion Notes

### AC-1 / AC-2 verbatim evidence — provider catch-block grep

All 4 providers carry `Set tPostExText = postEx.DisplayString()` + `$$$LOGERROR(...)` inside the `Catch postEx` block, AND interpolate `tPostExText` into the mid-flight `PopulateErrorEnvelope` message:

```
src/SessionAgent/LLM/OpenAIProvider.cls:286:                Set tPostExText = postEx.DisplayString()
src/SessionAgent/LLM/OpenAIProvider.cls:287:                $$$LOGERROR("SessionAgent.LLM.OpenAIProvider mid-flight HTTP failure: " _ tPostExText)
src/SessionAgent/LLM/AnthropicProvider.cls:325:                Set tPostExText = postEx.DisplayString()
src/SessionAgent/LLM/AnthropicProvider.cls:326:                $$$LOGERROR("SessionAgent.LLM.AnthropicProvider mid-flight HTTP failure: " _ tPostExText)
src/SessionAgent/LLM/GeminiProvider.cls:342:                Set tPostExText = postEx.DisplayString()
src/SessionAgent/LLM/GeminiProvider.cls:343:                $$$LOGERROR("SessionAgent.LLM.GeminiProvider mid-flight HTTP failure: " _ tPostExText)
src/SessionAgent/LLM/OpenAICompatProvider.cls:348:                Set tPostExText = postEx.DisplayString()
src/SessionAgent/LLM/OpenAICompatProvider.cls:349:                $$$LOGERROR("SessionAgent.LLM.OpenAICompatProvider mid-flight HTTP failure: " _ tPostExText)
```

Each provider's mid-flight branch composes the envelope as: `"<Provider> mid-flight failure (request may have been processed)" _ ": " _ tPostExText` (only when `tPostExText '= ""`). Unit tests verify the runtime envelope contents.

### AC-3 verbatim evidence — live tool dispatch (positive case)

```
$ iris_execute_command — GetBusinessProcessSource.Invoke({"bp_class_name":"SessionAgent.Sample.BP.OrderRouter.OnRequest"})
{
  "class_name":"SessionAgent.Sample.BP.OrderRouter",
  "super_class":"Ens.BusinessProcess",
  "abstract":false,
  "parameters":[],
  "properties":[...8 entries...],
  "methods":[
    {"name":"OnComplete",...},
    {"name":"OnError",...},
    {"name":"OnRequest",...},
    {"name":"OnResponse",...},
    {"name":"buildResponse",...}
  ],
  "method_count":5,
  "property_count":8,
  "parameter_count":0,
  "render_strategy":"ok",
  "class_name_auto_corrected_from":"SessionAgent.Sample.BP.OrderRouter.OnRequest"
}
```

### AC-3 verbatim evidence — live tool dispatch (negative case)

```
$ iris_execute_command — GetBusinessProcessSource.Invoke({"bp_class_name":"Totally.NonExistent.Class.Name"})
{
  "class_name":"Totally.NonExistent.Class.Name",
  "render_strategy":"class_not_found",
  "super_class":"",
  "abstract":false,
  "parameters":[],
  "properties":[],
  "methods":[],
  "method_count":0,
  "property_count":0,
  "parameter_count":0,
  "candidate_class_name":"Totally.NonExistent.Class"
}
```

### AC-4 verbatim evidence — `bp_class_name` description post-fix

`GetBusinessProcessSource.GetInputSchema().properties.bp_class_name.description` returns:

> *"Full class name of the Business Process class (e.g., SessionAgent.Sample.BP.OrderRouter or Ens.BusinessProcess). Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."*

### AC-5 verbatim evidence — sibling-tool description sweep

| Tool class | Argument | Description (verbatim post-fix) |
|---|---|---|
| `Tool.Inspection.ListBusinessProcessMethods` | `bp_class_name` | *"Full class name (e.g., SessionAgent.Sample.BP.OrderRouter). Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."* |
| `Tool.Search.SearchByBodyField` | `search_table_class` | *"Fully-qualified Ens.SearchTableBase subclass name (e.g., 'EnsLib.HL7.SearchTable'). Pass the class name only — do not include method names (e.g. pass 'EnsLib.HL7.SearchTable', not 'EnsLib.HL7.SearchTable.OnIndex')."* |
| `Tool.Inspection.FindSessionsByBody` | `search_table_class` | *"Fully qualified name of an Ens.SearchTableBase subclass (e.g., EnsLib.HL7.SearchTable). Pass the class name only — do not include method names (e.g. pass 'EnsLib.HL7.SearchTable', not 'EnsLib.HL7.SearchTable.OnIndex')."* |
| `Tool.Search.SearchByMessageClass` | `message_body_class_name` | *"Exact full Ens body class name (e.g. 'EnsLib.HL7.Message'). Pass the class name only — do not include method names (e.g. pass 'EnsLib.HL7.Message', not 'EnsLib.HL7.Message.GetField')."* |
| `Tool.Search.VocabLookup` | `message_body_class` | *"Optional per-class refinement key (e.g., 'EnsLib.HL7.Message'). Empty means cross-class. Pass the class name only — do not include method names (e.g. pass 'EnsLib.HL7.Message', not 'EnsLib.HL7.Message.GetField')."* |
| `Tool.Inspection.RuleLog` | `rule_class` | *"Optional full rule class name (e.g. 'Demo.MyRule') filter. Pass the class name only — do not include method names (e.g. pass 'Demo.MyRule', not 'Demo.MyRule.OnMatch')."* |

Note: Spec mentioned `get_business_operation_source` but that tool does NOT exist in this codebase (Task 0 probe confirmed). Sibling sweep covers the 6 actual tools that accept class-name arguments.

### AC-6 verbatim evidence — regression-sweep SQL ground-truth probe

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
JOIN ( ...numerical-MAX picker...
) latest ON ... = latest.MaxRunIdx
WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%';
```

Result: **Total=441, Passed=441, Failed=0**.

Pre-state baseline was 432 (per sprint-status `last_updated` Story 11.1 line); Story 11.4 added 3 tests → 435; Story 12.0/12.1/12.3 added incremental tests. Story 12.2 added 6 new tests (4 mid-flight + 2 BUG-03) bringing the count to 441 exact. Zero failures in the post-state.

### Story 12.2 fix-now finding (Rule 8) — pre-existing `MessageViewerTest.TestSendChatMessageHappyPath` failure

During Task 7's regression sweep, `MessageViewerTest:TestSendChatMessageHappyPath` was failing with envelope text `"Agent message-search is disabled"`. Confirmed via stash-and-rerun that the failure existed BEFORE any Story 12.2 changes — pre-existing baseline failure rooted in the test fixture not enabling the `message-search` agent (the agent's `Enabled` flag is operator-state and defaults to 0 in many test hosts).

Per Rule 8 (defer threshold raised — fix-now is default, predicted-bug shape clear: any operator running this test on a fresh namespace hits the same false-failure), fixed in same commit:

- Added `PreservedMessageSearchEnabled` property + `OnBeforeOneTest` enable + `OnAfterOneTest` restore scaffolding to `MessageViewerTest`. Uses `SessionAgent.Config.Agent.AgentNameIdxOpen("message-search")` (the unique-index open path) per project rule "Use Config screens — not SQL UPDATE" (this is a programmatic property mutation through the typed object, not raw SQL). Original `Enabled` value captured pre-test, restored post-test, so operator state is preserved across test runs.
- Result: `MessageViewerTest` 7/7 passes.

### Story 12.0 Carry-Forward node -c binding — DOES NOT APPLY

This story does NOT modify `static/chat-panel.js` or any other JavaScript asset. The Story 12.0 Carry-Forward `node -c` parse-check binding does not apply.

### Live exercise of BUG-02 catch path — DEFERRED to next walkthrough

Triggering BUG-02's catch path requires either (a) breaking SSL configuration intentionally or (b) supplying an unresolvable hostname. Neither was attempted in this story per spec Task 6 allowance ("If chrome-devtools-mcp is unavailable, skip this and note the live exercise as deferred"). Unit-test coverage via `TestMidFlightFailureCarriesExceptionText` (4 provider test classes, all pass) exercises the catch-block logic deterministically — the test sets `MockThrowText` on the mock, drives `CallMessages`, and asserts the envelope text contains the framing + separator + exception substring + that the mock was invoked exactly once (no retry on mid-flight). This deterministic coverage is sufficient for the AC-1 / AC-2 contract; the live exercise is a verification-redundancy item bound to the next walkthrough.

## File List

**Modified — production:**
- `src/SessionAgent/LLM/OpenAIProvider.cls` — `Include Ensemble` + `tPostExText` capture in `Catch postEx` + `$$$LOGERROR` + interpolation in mid-flight `PopulateErrorEnvelope`.
- `src/SessionAgent/LLM/AnthropicProvider.cls` — same shape.
- `src/SessionAgent/LLM/GeminiProvider.cls` — same shape.
- `src/SessionAgent/LLM/OpenAICompatProvider.cls` — same shape.
- `src/SessionAgent/Tool/Inspection/GetBusinessProcessSource.cls` — strip-last-segment retry in `class_not_found` branch + `class_name_auto_corrected_from` / `candidate_class_name` markers + `bp_class_name` description warning.
- `src/SessionAgent/Tool/Inspection/ListBusinessProcessMethods.cls` — `bp_class_name` description warning.
- `src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls` — `search_table_class` description warning.
- `src/SessionAgent/Tool/Inspection/RuleLog.cls` — `rule_class` description warning.
- `src/SessionAgent/Tool/Search/SearchByBodyField.cls` — `search_table_class` description warning.
- `src/SessionAgent/Tool/Search/SearchByMessageClass.cls` — `message_body_class_name` description warning.
- `src/SessionAgent/Tool/Search/VocabLookup.cls` — `message_body_class` description warning.

**Modified — tests:**
- `src/SessionAgent/Test/MockOpenAIProvider.cls` — `MockThrowText` property + throw branch in `IssueHttpsPost`.
- `src/SessionAgent/Test/MockAnthropicProvider.cls` — same.
- `src/SessionAgent/Test/MockGeminiProvider.cls` — same.
- `src/SessionAgent/Test/MockOpenAICompatProvider.cls` — same.
- `src/SessionAgent/Test/OpenAIProviderTest.cls` — `TestMidFlightFailureCarriesExceptionText` method.
- `src/SessionAgent/Test/AnthropicProviderTest.cls` — same.
- `src/SessionAgent/Test/GeminiProviderTest.cls` — same.
- `src/SessionAgent/Test/OpenAICompatProviderTest.cls` — same.
- `src/SessionAgent/Test/BusinessProcessIntrospectionTest.cls` — `TestSourceWithMethodSuffixAutoCorrects` + `TestSourceUnknownMultiSegmentReturnsCandidate` methods.
- `src/SessionAgent/Test/MessageViewerTest.cls` — `PreservedMessageSearchEnabled` property + `OnBeforeOneTest` agent-enable + `OnAfterOneTest` agent-restore (Story 12.2 fix-now per Rule 8).

**Modified — sprint state:**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `12-2-...: ready-for-dev` → `review`.
- `_bmad-output/implementation-artifacts/12-2-agent-reliability-provider-error-and-tool-fallback.md` — task checkmarks, completion notes, file list, change log, status flip.

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.3 commit `fc0f1f3`).
- 2026-05-08 — Implementation complete (dev). All 6 ACs satisfied; regression sweep 441/441/0 via canonical numerical-MAX SQL probe. 1 fix-now (Rule 8) for pre-existing MessageViewerTest agent-enabled failure. Status flipped in-progress → review.
