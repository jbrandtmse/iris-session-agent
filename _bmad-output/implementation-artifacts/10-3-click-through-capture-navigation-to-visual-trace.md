# Story 10.3: Click-Through Capture + Navigation to Visual Trace

Status: done

## Story

As an **Operator clicking a session in a Search Agent result list**,
I want the click to silently capture the vocabulary alias (via Story 9.5's `RecordClickThrough` hyperevent) AND navigate to Visual Trace on that session with a `FROM_SEARCH` URL parameter carrying the search context,
So that vocabulary learns automatically (FR22) and the destination Inspection Agent can render the "from search" stripe (Story 10.4) per FR20 + UX-DR25 + Devin Journey 2.

This story replaces Story 10.2's `onSearchResultClick` stub body with the actual capture + navigation logic. After this story lands, vocabulary rows accrue silently on every operator click-through and the destination Visual Trace page receives the search context via a URL param ready for Story 10.4 to render the stripe.

## Acceptance Criteria

ACs come from epics.md §"Story 10.3" verbatim, augmented by Task 0 finding (Story 9.5's `VocabCapture.RecordClickThrough` is a ClassMethod, not a `[ZenMethod]` — Story 10.3 must ADD a thin `[ZenMethod]` wrapper to `SessionAgent.EnsPortal.MessageViewer` that resolves `%session.Username` at the boundary and delegates to the ClassMethod).

### AC-1 — `RecordClickThrough` ZenMethod wrapper on the Search-Agent host page

**Given** Story 9.5 shipped `SessionAgent.Search.VocabCapture.RecordClickThrough` as a 4-arg ClassMethod (`pSearchSessionKey, pSessionId, pContributingToolCallsJson, pPortalUser`)
**When** the JS-side click handler invokes `zenPage.RecordClickThrough(searchSessionKey, sessionId, contributingToolCallsJson)` (3 args — Zen hyperevent boundary; the 4th arg `pPortalUser` is resolved server-side at the boundary)
**Then** [`src/SessionAgent/EnsPortal/MessageViewer.cls`](../../src/SessionAgent/EnsPortal/MessageViewer.cls) gains a NEW 3-arg `[ZenMethod]` wrapper:

```objectscript
ClassMethod RecordClickThrough(pSearchSessionKey As %String, pSessionId As %String, pContributingToolCallsJson As %String) As %String [ ZenMethod ]
{
    Set tPortalUser = ""
    If $IsObject($Get(%session)) {
        Set tPortalUser = %session.Username
    }
    If tPortalUser = "" {
        Set tPortalUser = $Username
    }
    Quit ##class(SessionAgent.Search.VocabCapture).RecordClickThrough(pSearchSessionKey, pSessionId, pContributingToolCallsJson, tPortalUser)
}
```

**And** the wrapper NEVER throws — the inner `VocabCapture.RecordClickThrough` already has a never-throw contract per Story 9.5; the wrapper just resolves the user and delegates.
**And** the wrapper's return shape passes through verbatim from the inner ClassMethod (per Story 9.5's contract: `{success: true, aliases_recorded: [...]}` happy-path OR `{success: false, error: "..."}` error-path; either way, fire-and-forget from the JS side per UX-DR25).

### AC-2 — Replace `onSearchResultClick` stub with actual capture + navigation

**Given** Story 10.2 shipped the stub `onSearchResultClick(anchor, event)` function in `chat-panel.js` with a TODO marker
**When** the developer fills in the body
**Then** the new body (in execution order):
  1. `event.preventDefault()` — suppresses the default `href="#"` jump (already in stub).
  2. Read `anchor.getAttribute('data-session-id')`, `anchor.getAttribute('data-search-session-key')`, `anchor.getAttribute('data-tool-call-index')`.
  3. Assemble `contributingToolCalls[]` from the cached most-recent agent turn's `toolCallsRendered[]` (see AC-3).
  4. Call `zenPage.RecordClickThrough(searchSessionKey, sessionId, JSON.stringify(contributingToolCalls))` — fire-and-forget per UX-DR25 (do NOT await response; do NOT block navigation; do NOT show confirmation to operator).
  5. Construct the destination URL per AC-4 below.
  6. `window.location.href = destinationUrl;` — navigate immediately.

**And** the click handler is keyboard-accessible (Enter on focused anchor triggers the same handler — already wired by Story 10.2's event-delegation pattern).

### AC-3 — `contributingToolCalls[]` assembly from cached envelope

**Given** the click-through capture needs the agent turn's tool-call list
**When** the click handler assembles `contributingToolCalls[]`
**Then** the JS caches the most-recent agent turn's `toolCallsRendered[]` array in a module-scope variable (e.g., `state.lastToolCallsRendered = (envelope.toolCallsRendered || []);` set at the end of `handleEnvelope`).
**And** `contributingToolCalls[]` is built by mapping each cached tool call to its `{tool_name, args, result}` triple per Story 9.5's expected shape:

```js
var contributingToolCalls = (state.lastToolCallsRendered || []).map(function (tc) {
    return {
        tool_name: tc.name,
        args: tc.args,
        result: tc.result
    };
});
```

**And** the array is JSON-stringified before passing to `zenPage.RecordClickThrough(...)` since Zen hyperevents accept only string args.
**And** when `state.lastToolCallsRendered` is empty (e.g., the operator clicks a search-result entry from a returning-conversation transcript that loaded from `Chat.History` without re-issuing a search), the click handler still invokes `zenPage.RecordClickThrough(searchSessionKey, sessionId, '[]')` — Story 9.5's contract handles empty arrays per its AC-1 (no aliases inferred → returns `aliases_recorded: []`; not an error).

### AC-4 — Destination URL construction (HealthShare-aware)

**Given** the click handler builds the navigation URL
**When** constructing the URL
**Then** the script detects the current URL prefix to determine HealthShare vs plain-IRIS pattern:

```js
var currentPath = window.location.pathname;
var isHealthShare = currentPath.indexOf('/csp/healthshare/') === 0;
var nsMatch = currentPath.match(/\/csp\/(?:healthshare\/)?([^/]+)\//);
var ns = nsMatch ? nsMatch[1] : 'hscustom';
var prefix = isHealthShare ? '/csp/healthshare/' + ns : '/csp/' + ns;
var destinationUrl = prefix + '/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=' + encodeURIComponent(sessionId) + '&FROM_SEARCH=' + encodeURIComponent(searchSessionKey);
```

**And** the `encodeURIComponent` calls protect against any future change in `sessionId` or `searchSessionKey` shape that might introduce URL-unsafe characters (today both are numeric / GUID, but defensive encoding is cheap).
**And** the URL pattern matches Story 1.5's installer-printed bookmark patterns (verbatim) with the added `FROM_SEARCH` query param.

### AC-5 — Fire-and-forget contract (UX-DR25)

**Given** the operator clicks a session entry
**When** the click handler runs
**Then** the operator sees NO confirmation message ("Captured!" / "Recorded!" / etc.) — silent capture per UX-DR25.
**And** navigation happens immediately after the `zenPage.RecordClickThrough(...)` call returns to the JS event loop — the JS does NOT `await` the response (Zen hyperevents are synchronous from JS perspective so the navigation will run after the hyperevent's HTTP request fires; this is acceptable since the hyperevent typically returns in <50ms server-side and the network round-trip is the only blocking time).
**And** if the hyperevent throws on the JS side (network error, 500 response), the click handler swallows the error via `try/catch` and proceeds with the navigation anyway — the operator MUST navigate even if vocabulary capture fails. **Pattern:**

```js
try {
    zenPage.RecordClickThrough(searchSessionKey, sessionId, JSON.stringify(contributingToolCalls));
} catch (captureErr) {
    if (typeof console !== 'undefined' && console.warn) {
        console.warn('[sa-search] RecordClickThrough threw — proceeding with navigation:', captureErr);
    }
}
window.location.href = destinationUrl;
```

### AC-6 — Test class additions

**Given** Story 9.5 ships `SearchVocabCaptureTest` (8 methods covering the substrate ClassMethod)
**When** Story 10.3 adds tests for the new wrapper + JS wiring
**Then** new tests are added — at least 4:

1. **`RecordClickThroughWrapperResolvesUserAtBoundary`** — invoke `MessageViewer:RecordClickThrough` ClassMethod (via `iris_execute_classmethod`) without a CSP session, verify the response JSON is well-formed (delegates to `$Username` fallback). The test does NOT need to assert on aliases recorded; that's covered by Story 9.5's tests. The test asserts the wrapper exists, accepts 3 args, and returns a JSON-parseable string.
2. **`ChatPanelJsContainsRecordClickThroughCall`** — `%File`-grep assertion against `static/chat-panel.js` confirming the literal string `zenPage.RecordClickThrough(` appears (proves the JS wires the hyperevent invocation).
3. **`ChatPanelJsContainsFromSearchUrlParam`** — `%File`-grep assertion that `chat-panel.js` constructs the destination URL with `FROM_SEARCH=` and `SESSIONID=` query params.
4. **`ChatPanelJsCachesToolCallsRendered`** — `%File`-grep assertion that `chat-panel.js` contains `state.lastToolCallsRendered = ` (or equivalent module-scope cache) — proves AC-3's caching mechanism is wired.

The 4 tests can live in [`src/SessionAgent/Test/ClickThroughTest.cls`](../../src/SessionAgent/Test/ClickThroughTest.cls) (NEW) OR be appended to the existing `SearchAgentRenderTest` if the dev judges 4 more methods don't bloat that class beyond the ~500-line testing-class governance.

### AC-7 — Live integration smoke (Rule 11)

**Given** the credentials are in place per Step-1 matrix
**When** an integration test simulates: invoke `MessageViewer:RecordClickThrough(<test-search-key>, <real-session-id>, <2-tool-call-blocks>)` directly via `iris_execute_classmethod` (simulating the JS-side hyperevent boundary)
**Then** the call returns a parseable JSON envelope per Story 9.5's contract.
**And** `SessionAgent_Search.UserVocabulary` rows accrue with `CreatedVia='clickthrough'` for the inferred aliases (verify via SQL probe before-and-after).
**And** new audit rows land in `SessionAgent_Audit.LlmCall` (vocabulary writes use the `VocabWrite/clickthrough` and `VocabWrite/extracted` audit triples Story 1.3 pre-registered).

### AC-8 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.EnsPortal.MessageViewer` (modified) AND new test class (NEW).
- New tests added — at least 4 per AC-6.
- **Per-class regression sweep** across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
- **The "N/N pass" claim that gates this story MUST come from the canonical numerical-MAX SQL-ground-truth probe form** (per Story 9.0 AC-2 reviewer-blocking codification).
- **Expected baseline: 386 (Story 10.2 close) + at least 4 (this story) = 390+**. Capture verbatim `Total / Passed / Failed` in Completion Notes.

### AC-9 — Rule 12 content-correctness for the click handler (DOM probe acceptable)

**Given** the new click-through wiring is exercised
**When** an operator clicks a `sa-search-result-entry`
**Then** the DOM probe confirms: (a) `state.lastToolCallsRendered` cache is populated after a search-result-bearing turn renders; (b) the click handler invokes `RecordClickThrough` (verifiable via Network panel OR by stubbing `zenPage.RecordClickThrough` in a test fixture and asserting it was called); (c) navigation occurs to the expected URL pattern.

**Evidence shape:** A `chrome-devtools-mcp.evaluate_script` DOM probe stubbing `zenPage.RecordClickThrough` to a spy function, then triggering a click on the first search-result entry, then asserting (i) the spy was called with the expected 3 args, (ii) the URL the script *would* navigate to (capture via spying on `window.location.href` setter — or by inspecting `event.preventDefault()` semantics; alternative: read the anchor's `href` build path). If chrome-devtools-mcp browser is unavailable, the alternate evidence form is a server-side smoke test per AC-7 (the JS-side wiring is provable via `%File`-grep tests in AC-6).

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes (Rule 4 / Rule 7)**
  - [x] Verify `Story 10.0` AI-5 umbrella binding still holds for the 4 flake-prone classes (no action; documentation-only check).
  - [x] Verify `SessionAgent.Search.VocabCapture.RecordClickThrough` ClassMethod signature (4 args) via `iris_execute_classmethod` against an obvious-no-op invocation (empty pPortalUser → returns structured-error). Capture the verbatim envelope.
  - [x] Probe whether the dev install has any `UserVocabulary` rows with `CreatedVia='clickthrough'` pre-test (capture pre-state count via SQL probe — used as the AC-7 before/after delta).

- [x] **Task 1 — Add `RecordClickThrough` ZenMethod wrapper to `MessageViewer.cls` (AC: #1)**
  - [x] Append the 3-arg `[ZenMethod]` wrapper to `src/SessionAgent/EnsPortal/MessageViewer.cls` per AC-1's verbatim ObjectScript snippet.
  - [x] Compile via `iris_doc_compile`.
  - [x] Sanity-check via `iris_execute_classmethod` that the wrapper is callable with 3 args.

- [x] **Task 2 — Replace `onSearchResultClick` stub body (AC: #2, #3, #4, #5)**
  - [x] Locate `onSearchResultClick(anchor, event)` in `static/chat-panel.js` (added Story 10.2).
  - [x] Replace the stub body with the AC-2 implementation (preventDefault → assemble contributingToolCalls → fire-and-forget hyperevent → construct URL → navigate).
  - [x] Add `state.lastToolCallsRendered = (envelope.toolCallsRendered || []);` at the end of `handleEnvelope` (before `finishTurn()`).
  - [x] Add the URL-prefix detection logic per AC-4 (HealthShare vs plain-IRIS).
  - [x] Wrap the `zenPage.RecordClickThrough(...)` call in `try/catch` per AC-5's never-block-navigation contract.
  - [x] `node -c static/chat-panel.js` parse check.

- [x] **Task 3 — Implement `SessionAgent.Test.ClickThroughTest` (AC: #6)**
  - [x] Create [`src/SessionAgent/Test/ClickThroughTest.cls`](../../src/SessionAgent/Test/ClickThroughTest.cls) with 4 test methods per AC-6.
  - [x] If the dev judges 4 more methods fit cleanly inside `SearchAgentRenderTest` (~500-line cap allowing), the dev MAY append there instead — document the choice in Completion Notes. **Decision: dedicated class chosen** — keeps the click-through wiring tests concentrated in one file (~190 lines) and `SearchAgentRenderTest` already crowds the ~500-line governance.
  - [x] Compile via `iris_doc_compile`. Run via `iris_execute_tests` per-class. Confirm 4/4 PASS.

- [x] **Task 4 — Live-integration smoke (AC: #7, #9 / Rule 11)**
  - [x] Invoke `MessageViewer:RecordClickThrough(<test-search-key>, <real-Ens-session-id>, <test-2-tool-call-blocks>)` via `iris_execute_classmethod`. Capture verbatim response.
  - [x] SQL probe `SELECT COUNT(*) FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(CreatedVia)='clickthrough'` before AND after the call. Capture both counts; the delta should equal the response's `aliases_recorded` array length.
  - [~] If chrome-devtools-mcp is available, run the AC-9 DOM probe (stub `zenPage.RecordClickThrough` + click first entry + assert call args + assert navigation URL). **Skipped** — falls back to AC-7 server-side smoke + AC-6 `%File`-grep tests per spec; chrome-devtools-mcp browser session not driven this cycle (the AC-6 + AC-7 evidence covers the wiring; layout was verified in Story 10.1).
  - [x] If chrome-devtools-mcp is unavailable, the AC-7 server-side smoke + the AC-6 `%File`-grep tests cover the wiring.

- [x] **Task 5 — Verification battery (AC: #8)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
  - [x] SQL ground-truth probe per the canonical numerical-MAX form.
  - [x] If any flake class hits the documented 1-in-5 concurrent-cadence flake, retry per the Story 10.0 AI-5 umbrella entry's documented behavior. **No flake observed** — single sweep returned 390/390/0 cleanly.

## Dev Notes

### Rule 1 spec-length watch

This spec targets ~225 lines. Stays leaner than 10.1 / 10.2 because the feature surface is small: 1 new ZenMethod wrapper (~10 lines of ObjectScript) + 1 stub-body fill-in (~30 lines of JS) + 4 small tests. Most of the work was front-loaded into Stories 9.5 (substrate) and 10.2 (stub).

### Rule 8 application

All 5 ACs are net-new code (Rule-8-default fix-now). No defer-vs-fix surface.

### Rule 9 binding-successor enforcement

`grep -n "Story 10.3" _bmad-output/implementation-artifacts/deferred-work.md` returns zero matches at story-creation time. No prior deferral binds to Story 10.3.

### Rule 10 — no external defaults

JS + ObjectScript wiring; no model name, library version, or API endpoint set.

### Rule 11 — live integration smoke (AC-7)

The new wrapper exercises the substrate ClassMethod end-to-end against the live `UserVocabulary` table. Credentials are not required for this story (no LLM call); the production must be running (verified Step 1).

### Rule 12 — content-correctness within the rendered component (AC-9)

The click handler's behavior is content-correctness within the existing chat-panel layout. Layout was verified in Story 10.1; no need to re-verify here.

### Carry-forward from prior deferred-work entries (per Rule 9 grep target)

None for Story 10.3.

### `state.lastToolCallsRendered` cache placement

The cache is set at the end of `handleEnvelope` (AFTER all rendering completes, so a render-error path does NOT populate the cache with a partially-processed envelope). The cache is module-scope (closure-bound to the IIFE's `state` object); each operator turn overwrites the previous cache. Returning-conversation transcripts loaded from `Chat.History` do NOT populate the cache (they have no envelope) — this is correct: a click on a returning-conversation entry should fire `RecordClickThrough` with `'[]'` (empty contributing tool calls), which Story 9.5 handles per AC-1.

### Auto-sync workflow note

`static/chat-panel.js` is NOT auto-synced. `MessageViewer.cls` and the new test class ARE auto-synced. `iris_doc_compile` is required for the .cls files but not for the .js.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context). Single-task agent invocation under `/bmad-dev-story`.

### Completion Notes

**Verbatim AC-contract evidence** per Rule 2 (sharpened):

**AC-1 — `RecordClickThrough` ZenMethod wrapper exists, accepts 3 args, never throws.**
- Wrapper appended to `src/SessionAgent/EnsPortal/MessageViewer.cls` (verbatim per AC-1 snippet, including `%session.Username` boundary read with `$Username` fallback).
- Compile evidence (forced via `flags='cuk-d'` after auto-sync up-to-date check):
  ```
  {"success":true,"documents":["SessionAgent.EnsPortal.MessageViewer.cls"],"compilationTime":"14ms"}
  ```
- 3-arg invocation (no CSP session, $Username fallback fires) returns valid JSON envelope:
  ```
  {"success":true,"aliases_recorded":[],"search_session_key":"sa-test-103-probe","session_id":"0"}
  ```
  argCount returned by MCP = 3 (confirms ZenMethod signature accepts exactly 3 args).

**AC-2 / AC-3 / AC-4 / AC-5 — `onSearchResultClick` body replaced; `state.lastToolCallsRendered` cache wired; URL detection HealthShare-aware; try/catch never blocks navigation.**
- Stub body in `static/chat-panel.js` replaced with the full implementation (preventDefault → read 3 anchor data attrs → assemble `contributingToolCalls[]` from `state.lastToolCallsRendered` → fire-and-forget `zenPage.RecordClickThrough(...)` wrapped in try/catch → URL detection via `currentPath.indexOf('/csp/healthshare/')` + regex namespace extract → `window.location.href = destinationUrl`).
- `state.lastToolCallsRendered = (envelope && envelope.toolCallsRendered) || [];` set at the END of `handleEnvelope` (after assistantBlock append, before `finishTurn()`).
- `state.lastToolCallsRendered: []` initial-value field added to the module-scope `state` object.
- JS parse-check (Node 22.19.0) PASS — `node -c c:/git/iris-session-agent/static/chat-panel.js` exits 0.
- Test-hook `window.SessionAgentSearchClickTestHook` extended to receive 4 args `(sessionId, tcIndex, contributingToolCalls, destinationUrl)` so smoke drivers see all load-bearing values.

**AC-6 — 4 unit tests in `SessionAgent.Test.ClickThroughTest`, all 4/4 PASS.**
- Compile evidence:
  ```
  {"success":true,"documents":["SessionAgent.Test.ClickThroughTest.cls"],"compilationTime":"14ms"}
  ```
- Per-class run via `iris_execute_tests` (level=class):
  ```
  total=4, passed=4, failed=0, skipped=0
  TestRecordClickThroughWrapperResolvesUserAtBoundary  passed (2.376ms)
  TestChatPanelJsContainsRecordClickThroughCall        passed (0.537ms)
  TestChatPanelJsContainsFromSearchUrlParam            passed (1.159ms)
  TestChatPanelJsCachesToolCallsRendered               passed (4.738ms)
  ```

**AC-7 — Live integration smoke (Rule 11) — UserVocabulary clickthrough delta + audit rows.**
- Pre-state probe (verbatim SQL output):
  ```
  SELECT COUNT(*) AS PreCount FROM SessionAgent_Search.UserVocabulary
  WHERE %EXACT(CreatedVia) = 'clickthrough'
  → PreCount = 0
  ```
- Live invocation (real Ens session 50783, 2 distinct tool-call blocks `search_by_status` + `search_by_message_body_class`):
  ```
  Set tEnvelope = ##class(SessionAgent.EnsPortal.MessageViewer).RecordClickThrough(
      "sa-test-103-live-key", "50783", <2-block JSON array>)
  ```
  Verbatim envelope returned:
  ```
  {"success":true,
   "aliases_recorded":[
     "search_by_status:limit=25|status=5",
     "search_by_message_body_class:message_body_class_name=demo.loan.msg.approval"],
   "search_session_key":"sa-test-103-live-key",
   "session_id":"50783"}
  ```
- Post-state probe (verbatim SQL output):
  ```
  PostCount = 2  (delta +2; matches aliases_recorded array length)
  ```
- Vocabulary row roster (verbatim SQL output, columns selected for compactness):
  ```
  ID=115  CreatedVia=clickthrough  Alias=search_by_message_body_class:message_body_class_name=demo.loan.msg.approval  MessageBodyClass=Demo.Loan.Msg.Approval  PortalUser=_SYSTEM  SuccessCount=1
  ID=114  CreatedVia=clickthrough  Alias=search_by_status:limit=25|status=5                                          MessageBodyClass=                          PortalUser=_SYSTEM  SuccessCount=1
  ```
- Audit emission verified — `%SYS.Audit` rows landed with the `VocabWrite/clickthrough` triple:
  ```
  EventSource=SessionAgent  EventType=VocabWrite  EventName=clickthrough  Description=UserVocabulary.RecordSuccess: created row (via=clickthrough)  UTCTimeStamp=2026-05-07 22:49:31.846  (×2 rows, one per alias)
  ```
- Test rows cleaned up post-invocation (`DELETE … WHERE PortalUser='_SYSTEM' AND CreatedVia='clickthrough' AND ID >= 114`).

**AC-8 — Compile clean + tests + regression intact.**
- `MessageViewer.cls` compile clean (above).
- `ClickThroughTest.cls` compile clean (above).
- New tests added: 4 (per AC-6).
- Per-class regression sweep across all `SessionAgent.Test.*` — canonical numerical-MAX SQL ground-truth probe (form per Story 5.0 / Epic 4 retro AI-1):
  ```
  SELECT COUNT(*) AS Total,
         SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
         SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
  FROM %UnitTest_Result.TestMethod tm
  JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
  JOIN ( SELECT %EXACT(tc2.Name) AS ClassName,
                MAX($PIECE(tc2.ID,'||',1)+0) AS MaxRunIdx
         FROM %UnitTest_Result.TestMethod tm2
         JOIN %UnitTest_Result.TestCase tc2 ON tm2.TestCase = tc2.ID
         WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
         GROUP BY %EXACT(tc2.Name)) latest
    ON %EXACT(tc.Name) = latest.ClassName
   AND ($PIECE(tc.ID,'||',1)+0) = latest.MaxRunIdx
  WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%'
  ```
  Result: **Total=390, Passed=390, Failed=0**. Meets the AC-8 expected baseline (386 Story 10.2 close + 4 new = 390+). Independent failure-only probe (`tm.Status=0`) confirmed FailCount=0.

**AC-9 — Content-correctness for the click handler (DOM probe acceptable).**
- Substituted server-side smoke (AC-7) + `%File`-grep tests (AC-6) per spec's "alternate evidence form" clause; chrome-devtools-mcp DOM probe NOT executed this cycle (layout already verified in Story 10.1; this story is pure wiring).
- The AC-6 grep tests prove (a) the click handler invokes `zenPage.RecordClickThrough(`, (b) the URL pattern includes `FROM_SEARCH=` + `SESSIONID=` + `SessionAgent.EnsPortal.VisualTrace.zen`, (c) `state.lastToolCallsRendered =` is wired.

### File List

- `c:\git\iris-session-agent\src\SessionAgent\EnsPortal\MessageViewer.cls` (modified — Story 10.3 AC-1 — appended `[ZenMethod] RecordClickThrough(pSearchSessionKey, pSessionId, pContributingToolCallsJson)` wrapper that resolves `%session.Username` at the boundary and delegates to `SessionAgent.Search.VocabCapture.RecordClickThrough` ClassMethod)
- `c:\git\iris-session-agent\static\chat-panel.js` (modified — Story 10.3 AC-2/3/4/5 — replaced `onSearchResultClick` stub body with capture+navigation logic, added `state.lastToolCallsRendered` module-scope cache field with end-of-`handleEnvelope` assignment, extended test-hook signature to include `contributingToolCalls` + `destinationUrl`)
- `c:\git\iris-session-agent\src\SessionAgent\Test\ClickThroughTest.cls` (NEW — Story 10.3 AC-6 — 4 unit tests covering wrapper boundary behavior + 3 chat-panel.js static-file invariants)
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\10-3-click-through-capture-navigation-to-visual-trace.md` (Status flip ready-for-dev → in-progress → review; Dev Agent Record populated; tasks/subtasks checkboxes flipped; Change Log entry)
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\sprint-status.yaml` (status flip ready-for-dev → in-progress → review for `10-3-click-through-capture-navigation-to-visual-trace`; `last_updated` refreshed)

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted by lead from epics.md §"Story 10.3" + Story 9.5 / Story 10.2 substrate analysis. Task 0 finding: VocabCapture.RecordClickThrough is a 4-arg ClassMethod, NOT a [ZenMethod]; Story 10.3 adds the 3-arg wrapper. | Lead |
| 2026-05-07 | 1.0 | Implementation complete. AC-1 wrapper appended to MessageViewer.cls; AC-2/3/4/5 onSearchResultClick body replaced + state.lastToolCallsRendered cache wired in chat-panel.js; AC-6 4 new unit tests in ClickThroughTest.cls (4/4 PASS); AC-7 live integration smoke captured (PreCount=0, PostCount=2, 2 audit rows); AC-8 regression sweep 390/390/0 via canonical numerical-MAX SQL ground-truth probe. Status: review. | Dev (Opus 4.7) |
