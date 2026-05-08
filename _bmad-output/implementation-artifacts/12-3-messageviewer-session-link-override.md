# Story 12.3: MessageViewer Session-Link Override to Custom VisualTrace

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` BUG-04 (HIGH severity). Clicking the green session-ID link in the `SessionAgent.EnsPortal.MessageViewer` results table navigates to the standard `EnsPortal.VisualTrace.zen` page (3 tabs: Header / Body / Contents) instead of the custom `SessionAgent.EnsPortal.VisualTrace.zen` (which has the 4th "Ask the agent" tab). This makes the Inspection Agent inaccessible from the Search-Agent results path — operators lose the cross-page hand-off.

## User Story

As an **operator** browsing search results in `SessionAgent.EnsPortal.MessageViewer`, I want clicking any session-ID link to take me to the custom VisualTrace page with the "Ask the agent" tab present, so that I can pivot from search results into per-session inspection without manually rewriting URLs.

## Acceptance Criteria

**AC-1 — `showTrace` ClientMethod overridden in custom MessageViewer subclass.**
- **Given** `SessionAgent.EnsPortal.MessageViewer` extends `EnsPortal.MessageViewer` (`irislib/EnsPortal/MessageViewer.cls` line ~178 defines the parent's `showTrace` ClientMethod that hardcodes `'EnsPortal.VisualTrace.zen?SESSIONID='+sessionId`),
- **When** the operator clicks a green session-ID link in the table,
- **Then** the override fires and navigates to `'SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID='+sessionId` (custom page) — NOT the standard page.

> **Verbatim evidence (Rule 2 sharpened):** Compile-time grep of `SessionAgent.EnsPortal.MessageViewer.cls` for `ClientMethod showTrace` confirms presence; the body contains `'SessionAgent.EnsPortal.VisualTrace.zen'` and does NOT contain the bare standard-page string `'EnsPortal.VisualTrace.zen'` (without the `SessionAgent.` prefix).

**AC-2 — Override preserves parent's behavioral contract.**
- **Given** the parent's `showTrace(sessionId, evt)` cancels the click event bubble and short-circuits when `sessionId == -1`,
- **When** the override fires,
- **Then** both behaviors are preserved (cancel bubble + sessionId guard) — the override differs ONLY in the destination URL prefix.

> **Verbatim evidence:** Source-level diff between override body and parent body shows the only delta is the `'EnsPortal.'` → `'SessionAgent.EnsPortal.'` URL substring change. Bubble cancel + sessionId guard preserved verbatim.

**AC-3 — Live navigation verification via chrome-devtools-mcp.**
- **Given** the override is compiled and the operator is on `/csp/hscustom/SessionAgent.EnsPortal.MessageViewer.zen`,
- **When** the operator clicks a session-ID link (e.g., row 6 session 69659 from the walkthrough),
- **Then** the new tab opens at `/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=69659` (custom URL) and the right-side tab strip shows 4 tabs including "Ask the agent" (NOT just 3 tabs Header/Body/Contents).

> **Verbatim evidence (Rule 12 layout-correctness):** chrome-devtools-mcp evidence form is REQUIRED — either (a) `take_screenshot` of the resulting VisualTrace page showing the 4-tab strip, or (b) `evaluate_script` returning the post-navigation `window.location.href` AND a DOM probe asserting `document.querySelector('#askAgentTab') !== null`. Capture the verbatim probe output in Completion Notes.

**AC-4 — Right-click "Visual Trace" context menu also navigates to custom page.**
- **Given** the parent's `EnsPortal.MessageViewer` `RibbonMenuLight` includes a "Visual Trace" context menu entry that also calls `zenPage.showTrace(...)` (lines ~160 and ~173 of `irislib/EnsPortal/MessageViewer.cls`),
- **When** the operator right-clicks a row and selects "Visual Trace" from the context menu,
- **Then** the same override fires and navigates to the custom VisualTrace page.

> **Verbatim evidence:** The override lives in the ClientMethod that BOTH code paths (column link + context menu) dispatch through, so a single override covers both. Inspect the parent's source to confirm both paths call `zenPage.showTrace`. Document the inspection finding in Completion Notes.

**AC-5 — No regression on existing inherited behavior.**
- **Given** all other parent ClientMethods (`onSelectRow`, `doSearch`, etc.) are NOT modified by this story,
- **When** the operator uses the page (search, filter, paginate, export, etc.),
- **Then** all non-`showTrace` behaviors work identically to pre-fix.

> **Verbatim evidence:** Story 12.3 modifies exactly one method override (`showTrace`); no other parent method is shadowed. Confirmed via `git diff` showing only the override addition.

**AC-6 — Regression sweep clean via SQL ground-truth probe.**
- **When** the per-class regression sweep runs after the override,
- **Then** the canonical numerical-MAX SQL probe against `%UnitTest_Result.TestMethod` reports Failed = 0 and Total ≥ pre-fix baseline.

> **Verbatim evidence:** Capture verbatim Total / Passed / Failed row.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe (Rule 3 — typed MCP first)**
  - [x] Read `irislib/EnsPortal/MessageViewer.cls` lines 175–188 to confirm parent `showTrace` exact body (sessionId guard + bubble-cancel + URL form).
  - [x] Read `irislib/EnsPortal/MessageViewer.cls` lines 155–175 to confirm context-menu callbacks dispatch through `showTrace` (both `pMenu(1)` and `pMenu(2)` should bind to `"zenPage.showTrace"`).
  - [x] Read `src/SessionAgent/EnsPortal/MessageViewer.cls` end-of-file to confirm no existing `showTrace` override (otherwise this is a duplicate).
- [x] **Task 1 — Add `showTrace` override**
  - [x] In `src/SessionAgent/EnsPortal/MessageViewer.cls`, add a new `ClientMethod showTrace(sessionId, evt) [ Language = javascript ]` whose body is verbatim-copied from the parent EXCEPT the URL substring `'EnsPortal.VisualTrace.zen'` is replaced with `'SessionAgent.EnsPortal.VisualTrace.zen'`. Preserve the sessionId guard, bubble-cancel, and `window.open(URI)` call.
  - [x] Add a doc-comment block citing BUG-04, the parent's hardcoded URL, and the operator outcome (Inspection-Agent tab now reachable from Search-Agent results).
- [x] **Task 2 — Compile**
  - [x] `mcp__iris-dev-mcp__iris_doc_compile` against `SessionAgent.EnsPortal.MessageViewer.cls` — confirm clean compile.
- [x] **Task 3 — `node -c` parse check (Rule per Story 12.0 Carry-Forward)**
  - [x] This story does NOT modify `static/chat-panel.js`. Document "binding does not apply" in Completion Notes and skip the actual `node -c` run.
- [x] **Task 4 — Layout-correctness verification via chrome-devtools-mcp** (Rule 12)
  - [x] Navigate to `/csp/hscustom/SessionAgent.EnsPortal.MessageViewer.zen`.
  - [x] Identify a session-ID link in the table (e.g., row 6 session 69659).
  - [x] Click the link via `mcp__chrome-devtools-mcp__click` (or use `evaluate_script` to call `zenPage.showTrace(69659, null)`).
  - [x] Verify the resulting URL via `evaluate_script` returning `window.location.href` — must contain `SessionAgent.EnsPortal.VisualTrace.zen` substring AND `SESSIONID=69659`.
  - [x] Verify the destination DOM contains `#askAgentTab` via `evaluate_script` returning `document.querySelector('#askAgentTab') !== null` → must be `true`.
  - [x] Save the verbatim probe outputs in Completion Notes.
- [x] **Task 5 — Add unit test**
  - [x] Add a test method to `SessionAgent.Test.MessageViewerTest` (or create) that asserts the compiled `showTrace` ClientMethod source contains the `SessionAgent.EnsPortal.VisualTrace.zen` substring AND does NOT contain the bare `EnsPortal.VisualTrace.zen` (without the SessionAgent prefix). Read the override body via `%Dictionary.MethodDefinition.Implementation` (per Story 12.1's `TestEmitStyleEmitsOverflowRules` pattern).
- [x] **Task 6 — Regression sweep + SQL ground-truth probe**
  - [x] Run `mcp__iris-dev-mcp__iris_execute_tests` per-class for `SessionAgent.Test.MessageViewerTest` plus any class touching MessageViewer.
  - [x] Run the canonical numerical-MAX SQL probe; capture Total / Passed / Failed.
- [x] **Task 7 — Spec length verification** — `wc -l` ≤ 250.
- [x] **Task 8 — Sprint-status flip** — `12-3-...: ready-for-dev` → `in-progress` → `review` → `done`. (Dev marks `in-progress` → `review`; lead flips to `done` post-review.)
- [ ] **Task 9 — Commit + push** (lead) — `feat(epic-12): story 12.3 — MessageViewer session-link override to custom VisualTrace`.

## Dev Notes

### The substring grep gotcha

Naive grep for `EnsPortal.VisualTrace.zen` will match BOTH the standard page and the custom-page string (because the latter contains the former as a substring). The unit test must use a more precise check:
- ASSERT presence: `[strContains, "SessionAgent.EnsPortal.VisualTrace.zen"]`
- ASSERT absence: the override body must NOT contain `'EnsPortal.VisualTrace.zen'` *without* the `SessionAgent.` prefix immediately preceding it.

Suggested ObjectScript pattern:
```objectscript
Set tBody = ##class(%Dictionary.MethodDefinition).IDKEYOpen("SessionAgent.EnsPortal.MessageViewer", "showTrace").Implementation
Set tFullStream = "" While 'tBody.AtEnd { Set tFullStream = tFullStream _ tBody.Read(32000) }
; Positive: contains the custom URL
$$$AssertTrue($Find(tFullStream, "SessionAgent.EnsPortal.VisualTrace.zen") > 0, "override navigates to custom page")
; Negative: contains NO bare standard-page reference
; Method: replace the custom URL with empty, then grep for the bare URL — should be 0 hits
Set tStripped = $Replace(tFullStream, "SessionAgent.EnsPortal.VisualTrace.zen", "")
$$$AssertTrue($Find(tStripped, "EnsPortal.VisualTrace.zen") = 0, "override does not navigate to standard page")
```

### Why a method override (not a property override)

Looking at the parent class, there's a `tracePage` property on `EnsPortal.Agents.cls` that some pages use to centralize the URL. But `EnsPortal.MessageViewer` does NOT use `tracePage` — it hardcodes the URL string in `showTrace` itself. So the cleanest fix is to override `showTrace` rather than try to inject a property. This matches the parent's actual code shape.

### Files modified

- `src/SessionAgent/EnsPortal/MessageViewer.cls` — add `ClientMethod showTrace` at end of class.
- `src/SessionAgent/Test/MessageViewerTest.cls` (or NEW) — 1 new test method.

### Patterns to follow verbatim

- Story 12.1's `TestEmitStyleEmitsOverflowRules` test pattern (read method body via `%Dictionary.MethodDefinition.IDKEYOpen` + `.Implementation` stream).
- Story 10.3 / 10.6's chrome-devtools-mcp navigation + DOM-probe layout-correctness pattern.

## Completion Notes

**Dev sign-off — 2026-05-08.** All 7 in-scope tasks complete; Task 9 (commit + push) is lead-owned.

### Files modified

- `src/SessionAgent/EnsPortal/MessageViewer.cls` — appended `ClientMethod showTrace(sessionId, evt) [ Language = javascript ]` (override) at the end of class, immediately before the closing `}`. Body is verbatim-copied from parent `EnsPortal.MessageViewer` lines 178-188 with the URL substring `'EnsPortal.VisualTrace.zen'` → `'SessionAgent.EnsPortal.VisualTrace.zen'` (single substring change). Bubble-cancel + sessionId guard + `window.open(URI)` preserved verbatim.
- `src/SessionAgent/Test/MessageViewerTest.cls` — added `Method TestShowTraceOverridePresent()`. Reads compiled `showTrace` body via `%Dictionary.CompiledMethod.IDKEYOpen` + `.Implementation`, then asserts (a) presence of the custom URL and (b) — using the strip-and-grep precise check — that no bare standard URL remains. Also asserts the 4 behavioral preservation fragments (`evt.cancelBubble = true`, `stopPropagation`, `sessionId != -1`, `window.open`).

### Substring grep gotcha — how it was handled

Per Dev Notes §"The substring grep gotcha", the custom-page URL `SessionAgent.EnsPortal.VisualTrace.zen` contains the standard-page URL `EnsPortal.VisualTrace.zen` as a substring. A naive grep for the standard URL would falsely match the custom URL too.

The precise check used in the unit test:

```objectscript
; Positive — custom URL present
Do $$$AssertTrue($Find(tBody, "SessionAgent.EnsPortal.VisualTrace.zen") > 0, ...)
; Negative — strip the custom URL out, then assert no bare standard URL remains
Set tStripped = $Replace(tBody, "SessionAgent.EnsPortal.VisualTrace.zen", "")
Do $$$AssertTrue($Find(tStripped, "EnsPortal.VisualTrace.zen") = 0, ...)
```

The same pattern was used in the chrome-devtools-mcp probe (Task 4) — capture the URL, then verify `capturedUrl.replace('SessionAgent.EnsPortal.VisualTrace.zen', '').indexOf('EnsPortal.VisualTrace.zen') === -1`.

### Task 3 — `node -c` parse-check binding does not apply

This story does NOT modify `static/chat-panel.js` (the `node -c` parse-check binding from Story 12.0 Carry-Forward applies only to `.js` files in `static/`). All changes are in `.cls` files; compilation verification is via `iris_doc_compile`. Skipped as documented.

### Verbatim evidence per AC

**AC-1 — `showTrace` ClientMethod overridden in custom MessageViewer subclass.**

Compile probe (`iris_doc_compile`):
> `Compilation finished successfully in 0.678s.`

`zenPage.showTrace.toString()` from chrome-devtools-mcp on the live MessageViewer page (post-login, pre-navigation):

```javascript
function(sessionId,evt) {
	if (evt) {
		evt.cancelBubble = true;
		if (evt.stopPropagation) evt.stopPropagation();
	}
	if (sessionId != -1) {
		var URI = zenLink('SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID='+sessionId);
		window.open(URI);
	}
}
```

Body contains `'SessionAgent.EnsPortal.VisualTrace.zen'` (custom URL); strip-and-grep shows no bare standard URL remains.

**AC-2 — Override preserves parent's behavioral contract.**

Diff parent (lines 178-188 of `irislib/EnsPortal/MessageViewer.cls`) vs override body — single delta is the URL substring `'EnsPortal.VisualTrace.zen'` → `'SessionAgent.EnsPortal.VisualTrace.zen'`. The bubble-cancel, `stopPropagation`, `sessionId != -1` guard, and `window.open(URI)` all preserved verbatim. Unit test `TestShowTraceOverridePresent` asserts each fragment is present in the compiled override body.

**AC-3 — Live navigation verification via chrome-devtools-mcp.**

Captured-URL probe (override invoked with `sessionId=69659`, `window.open` stubbed):

```json
{
  "capturedUrl": "SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=69659",
  "containsCustomUrl": true,
  "containsSessionId": true,
  "strippedHasBareStandard": false
}
```

Post-navigation DOM probe at `http://localhost:52773/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=69659`:

```json
{
  "location": "http://localhost:52773/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=69659",
  "hasAskAgentTab": true,
  "askAgentTabType": "DIV",
  "tabIds": ["headerDetails", "bodyDetails", "bodyContents", "askAgentTab"]
}
```

`document.querySelector('#askAgentTab') !== null` returns `true`. The destination has 4 tabs including `askAgentTab` (the custom page) — NOT 3 (the standard page).

**AC-4 — Right-click "Visual Trace" context menu also navigates to custom page.**

Task 0 inspection of `irislib/EnsPortal/MessageViewer.cls`:

- Line 160: `Set pMenu(1) = $LB(cmd(1),title(1),"zenPage.showTrace")` — `%OnGetTableLinkMenu` (column-link).
- Line 173: `Set pMenu(2) = $LB(cmd(2),title(2),"zenPage.showTrace")` — `%OnGetDetailsLinkMenu` (right-click context menu).

Both invocation paths call `zenPage.showTrace`, so the single override covers both — no separate context-menu code path exists in the parent.

**AC-5 — No regression on existing inherited behavior.**

`git diff` shows only one method override added (`showTrace`) and one new test method added (`TestShowTraceOverridePresent`); no other parent method is shadowed. Inherited methods (`onSelectRow`, `doSearch`, etc.) untouched.

**AC-6 — Regression sweep clean via SQL ground-truth probe.**

Canonical numerical-MAX SQL probe against `%UnitTest_Result.TestMethod` joined to `TestCase` (per `.claude/rules/object-script-testing.md`):

| Total | Passed | Failed |
|-------|--------|--------|
| **435** | **435** | **0** |

55 distinct `SessionAgent.Test.*` classes covered; `MessageViewerTest` ran at runIdx=1194 (7 methods, including the new `TestShowTraceOverridePresent`).

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.1 commit `c497425`).
- 2026-05-08 — Dev sign-off — `showTrace` override + unit test + live chrome-devtools-mcp verification + 435/435/0 regression sweep clean. Status `in-progress` → `review`.
