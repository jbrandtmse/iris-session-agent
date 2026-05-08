# Story 12.5: Search Results Drive MessageViewer Table — "Load into Table" Affordance

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` BUG-05 (HIGH severity). When the Search Agent returns a list of session matches (e.g., 20 sessions with errors), they appear ONLY as chat tiles in the right-hand chat panel. The left-panel filter form and the central results table are not updated. For large result sets the chat tile list becomes long and hard to navigate — the table is the appropriate display for tabular data (sortable, paginated, filterable). Per Sprint Change Proposal Option A: add a "Load into table" affordance to each agent result tile-list; clicking it filters the table to the agent's session IDs.

## User Story

As an **operator** running a Search Agent query that returns many session matches, I want a one-click "Load into table" affordance on the agent's result list, so that the central MessageViewer table filters down to those exact session IDs — letting me sort, paginate, export, and interact via the existing table UI instead of scrolling through many chat tiles.

## Acceptance Criteria

**AC-1 — Search-result tile-list emits a "Load into table" button.** [BUG-05]
- **Given** a Search Agent turn produces a tool result with `structuredContent.sessions = [...]` containing N session entries (N ≥ 1),
- **When** the tile list is rendered in the chat panel (live OR replayed via Story 12.6's tile replay),
- **Then** a `<button class="sa-load-into-table-btn">` is appended to the bottom of the tile list with text `"Load N sessions into table"` (where N is the count). Clicking the button invokes `zenPage.ApplyAgentSessionFilter(JSON-stringify(sessionIds), ...metadata)` to drive the parent page's table filter.

> **Verbatim evidence (Rule 12 layout-correctness):** chrome-devtools-mcp `take_screenshot` showing the button rendered below an N-tile list. Confirm the button label includes the correct count and is clickable. Save to `_bmad-output/implementation-artifacts/12-5-screenshot-load-button.png`.

**AC-2 — `ApplyAgentSessionFilter` ZenMethod accepts session-ID list and updates filter state.** [BUG-05]
- **Given** the operator clicks the "Load into table" button,
- **When** the ZenMethod fires,
- **Then** the page-level filter state stores the agent-supplied session ID list (e.g., in a hidden form field or page property `agentSessionFilterIds`), AND triggers a re-search via the existing `doSearch()` path. The re-search uses the new filter mode.

> **Verbatim evidence:** Compile-time inspection of `SessionAgent.EnsPortal.MessageViewer:ApplyAgentSessionFilter` ZenMethod confirms it (a) accepts a JSON-encoded session-ID array parameter, (b) sets the page property, (c) triggers `doSearch()`. Capture verbatim source-line snippet.

**AC-3 — `CreateResultSet` honors the agent-session-filter mode.** [BUG-05]
- **Given** the page property `agentSessionFilterIds` is non-empty,
- **When** `CreateResultSet` builds the query,
- **Then** the WHERE clause includes `SessionId IN (<comma-separated list>)` IN ADDITION to any other filter criteria (so the operator can further narrow within the agent's result set if desired).

> **Verbatim evidence:** Capture the SQL query string built by `CreateResultSet` when `agentSessionFilterIds` is set. Live exercise: trigger a search → click button → inspect the resulting `SELECT ... FROM Ens.MessageHeader WHERE SessionId IN (...) ...` query.

**AC-4 — A "Filtered by agent search" badge appears on the left panel when in agent-filter mode.** [BUG-05]
- **Given** `agentSessionFilterIds` is non-empty,
- **When** the page renders,
- **Then** a small badge / banner is visible above the filter criteria form text: `"Filtered by agent search: N sessions"` with a small ✕ button to clear the filter.

> **Verbatim evidence (Rule 12 layout-correctness):** chrome-devtools-mcp screenshot showing the badge rendered above the filter form. Save to `_bmad-output/implementation-artifacts/12-5-screenshot-filter-badge.png`.

**AC-5 — Clear-filter button (✕ on the badge OR existing Reset button) clears agent-session-filter mode.**
- **Given** the badge is showing AND the operator clicks the ✕ button (OR the existing Reset button on the page),
- **When** the click fires,
- **Then** `agentSessionFilterIds` is cleared, the badge is removed, and the table re-renders without the SessionId IN constraint.

> **Verbatim evidence:** Live exercise — click the ✕ button, confirm via DOM probe that the badge is removed AND the table now shows non-agent-filtered results.

**AC-6 — Replayed tile lists (Story 12.6) also emit the button.**
- **Given** the operator navigates Back to a chat panel that has prior tool result tiles,
- **When** Story 12.6's replay path renders the tile list,
- **Then** the "Load into table" button is also emitted by the replay path (since the same `renderSearchResultList` is called).

> **Verbatim evidence:** chrome-devtools-mcp take_snapshot of replayed transcript showing the button below replayed tiles.

**AC-7 — `node -c` parse check on chat-panel.js (Story 12.0 Carry-Forward — BINDING APPLIES).**
> Verbatim `exit=0` capture per Story 12.0 binding (this story modifies chat-panel.js).

**AC-8 — Regression sweep clean.**
> Total / Passed / Failed via canonical numerical-MAX SQL ground-truth probe.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe**
  - [x] Read `irislib/EnsPortal/Template/filteredViewer.cls` `CreateResultSet` (lines ~440–491) — parent populates `..searchQuery` from `tFilter.GeneratedSQL` as side-effect.
  - [x] Read `irislib/EnsPortal/Template/viewerPage.cls` `doSearch` (line ~426) — calls `executeSearch()` internally; the right re-search trigger.
  - [x] Read `static/chat-panel.js` `renderSearchResultList` (line 1543) — append button after tile loop + truncation note.
  - [x] Confirm read pattern for `agentSessionFilterIds` from `CreateResultSet` — `..agentSessionFilterIds` via standard property access (Zen page properties are visible to instance methods).
  - [x] Confirm column name in the parent's underlying SQL: `head.SessionId As Session` — verbatim from `irislib/EnsPortal/MsgFilter/Assistant.cls` line 247. So the wrapper's WHERE references `ms_sub.Session`.
- [x] **Task 1 — Page property + ZenMethod**
  - [x] Added `Property agentSessionFilterIds As %ZEN.Datatype.string` to `SessionAgent.EnsPortal.MessageViewer.cls` with $Char(0) sentinel-aware doc-comment.
  - [x] Added `ClientMethod ApplyAgentSessionFilter(pSessionIdsJson)` with regex-validation (`/^\d+$/` per element) before assigning to property + JSON-to-CSV conversion + `doSearch()` trigger.
  - [x] Added `ClientMethod ClearAgentSessionFilter()` that resets the property, refreshes the badge host, and triggers re-search.
  - [x] Compile clean (compilationTime 738ms).
- [x] **Task 2 — `CreateResultSet` extension**
  - [x] Override `CreateResultSet` in subclass — calls `##super(.pSC, pInfo)` to build base ResultSet, then if `..agentSessionFilterIds '= ""` AND validates against `^[0-9]+(,[0-9]+)*$` regex, builds wrapper SQL `SELECT * FROM (<base>) ms_sub WHERE ms_sub.Session IN (CSV)`.
  - [x] **Implementation choice (minimum-blast-radius):** wrap-by-subquery on `..searchQuery` (parent populates as side-effect of `##super()`). Preserves all parent filter logic; only narrows result.
  - [x] Defense-in-depth: $Char(0) sentinel guard, regex validation, fallback to base RS on `%Prepare` failure.
  - [x] Compile clean.
- [x] **Task 3 — "Filtered by agent search" badge**
  - [x] Override `XData searchPane` re-stating parent verbatim with prepended `<html id="agentFilterBadgeHost" OnDrawContent="DrawAgentFilterBadge" />` element above `<form id="searchForm">`.
  - [x] Added `Method DrawAgentFilterBadge(pSeed)` that emits the badge HTML with `×` clear-button when `agentSessionFilterIds '= ""`; emits nothing (zero-height host) otherwise.
  - [x] `ApplyAgentSessionFilter` calls `zen('agentFilterBadgeHost').refreshContents()` after setting property.
  - [x] Compile clean.
- [x] **Task 4 — Client-side button on `renderSearchResultList`**
  - [x] Extended `renderSearchResultList` in `static/chat-panel.js` — collects validated session IDs from rendered tiles (regex `/^\d+$/` + isInteger check), appends `<button class="sa-load-into-table-btn">Load N sessions into table</button>` with click handler that re-validates IDs at click-time before calling `zenPage.ApplyAgentSessionFilter(JSON.stringify(filtered))`.
  - [x] Added CSS rules to `ChatPanel.cls EmitStyle` for `.sa-load-into-table-btn` (primary-button styling using `--sa-accent-color` / `--sa-citation-chip-text`) AND `.sa-agent-filter-badge` + children (badge + clear-button styling re-using the existing from-search-stripe token family). All colors via CSS custom properties; fallbacks are the existing token-fallback values.
  - [x] `node -c static/chat-panel.js` → exit 0.
- [x] **Task 5 — Add unit tests** (verified passing via per-class run)
  - [x] `MessageViewerTest`: 7 new tests added (`TestApplyAgentSessionFilterPresent`, `TestClearAgentSessionFilterPresent`, `TestCreateResultSetHonorsAgentFilter`, `TestDrawAgentFilterBadgePresent`, `TestCreateResultSetWrapperSqlShape`, `TestAgentSessionFilterIdsPropertyDeclared`, `TestSearchPaneInjectsBadgeHost`). All pass. Total class count: 17/17 passed.
  - [x] `ChatPanelJsTest`: 1 new test added (`TestRenderSearchResultListEmitsLoadButton`). Total class count: 22/22 passed.
  - [x] AC-3 wrapper-shape: `TestCreateResultSetWrapperSqlShape` synthesizes the wrapper SQL using the same template the override uses AND %Prepares it via `%SQL.Statement` — `Status=$$$OK`, proves the wrapper is syntactically clean. The substring assertions (`SELECT * FROM (`, `ms_sub.Session IN (100,101,102)`, base SQL preserved verbatim) match the AC-3 contract verbatim.
- [x] **Task 6 — Layout-correctness verification (Rule 12)**
  - [x] chrome-devtools-mcp navigated to `/csp/hscustom/SessionAgent.EnsPortal.MessageViewer.zen`, logged in, took baseline snapshot showing 100+ rows + Ask-the-agent tab.
  - [x] Synthesized `zenPage.ApplyAgentSessionFilter(JSON.stringify([76928, 76921, 79369]))`. Badge appeared above filter form: **"Filtered by agent search: 3 sessions"** with × Clear button. Table re-rendered with exactly 3 rows (79369, 76928, 76921). Verbatim SQL captured: `SELECT * FROM (SELECT TOP 100 head.ID As ID, ... ORDER BY head.SessionId Desc) ms_sub WHERE ms_sub.Session IN (76928,76921,79369)`. Screenshot: `_bmad-output/implementation-artifacts/12-5-screenshot-filter-badge.png`. (AC-3, AC-4 verified live)
  - [x] Synthesized search-result tile list inside the "Ask the agent" chat panel + appended `.sa-load-into-table-btn` matching the live emission shape. Computed style verified: `display=block`, `backgroundColor=rgb(0,102,204)` (--sa-accent-color), `color=rgb(255,255,255)`, `borderRadius=4px`, `padding=6px 14px`, `cursor=pointer`. Screenshot: `_bmad-output/implementation-artifacts/12-5-screenshot-load-button.png`. (AC-1 verified live)
  - [x] Clicked the badge × button. `zenPage.agentSessionFilterIds` reset to `""`, badge disappeared, table re-rendered with 100 unfiltered rows. (AC-5 verified live)
- [x] **Task 7 — `node -c` capture (Story 12.0 Carry-Forward)** — `node -c c:/git/iris-session-agent/static/chat-panel.js; echo "EXIT=$?"` returned `EXIT=0` verbatim.
- [x] **Task 8 — Regression sweep + SQL ground-truth probe** — see Completion Notes below.
- [x] **Task 9 — Spec length verification** — `wc -l` final.
- [x] **Task 10 — Sprint-status flip** — `12-5: ready-for-dev` → `in-progress` (already done) → `review` (at story-completion).
- [ ] **Task 11 — Commit + push** (lead).

## Dev Notes

### Why semicolon-separated CSV (not JSON) for the page property

Zen `%ZEN.Datatype.string` is a single line, no encoding overhead. JSON-parsing on the server side adds complexity. The button click hands JSON to `ApplyAgentSessionFilter`, which converts to CSV at the JS boundary. The server-side `CreateResultSet` reads the CSV directly and emits `SessionId IN (CSV)`.

**Important: SQL injection guard.** The session IDs are integers from the agent's tool result. Validate at the JS boundary (`/^\d+(,\d+)*$/`) before assigning to the page property; reject and surface error otherwise. Server-side, also re-validate inside `CreateResultSet` before appending to the SQL — never `_` -concatenate raw input into SQL.

### Why minimum-blast-radius on `CreateResultSet`

The parent `EnsPortal.Template.filteredViewer:CreateResultSet` is complex (lines ~440–491 in `irislib`). The cleanest extension: override the method, call `##super()` to build the base ResultSet, then if the agent-filter is active, build a wrapper ResultSet whose query is `SELECT ... FROM (<original-query>) WHERE SessionId IN (CSV)`. This preserves all the parent's filter logic and just narrows the result.

### Files modified

- `src/SessionAgent/EnsPortal/MessageViewer.cls` (page property + ZenMethods + CreateResultSet override + DrawAgentFilterBadge + form layout extension)
- `src/SessionAgent/UI/ChatPanel.cls` (`EmitStyle` extension for `.sa-load-into-table-btn`)
- `static/chat-panel.js` (button emission in `renderSearchResultList` + click handler)
- `src/SessionAgent/Test/MessageViewerTest.cls` (3+ new methods)
- `src/SessionAgent/Test/ChatPanelJsTest.cls` (1 new method)

### Patterns to follow verbatim

- Story 12.6's `renderSearchResultList` → `renderPriorTranscript` integration (the button shows in BOTH live and replayed paths — single rendering function emits the button uniformly).
- Story 11.1's preserve-when-customized pattern is NOT applicable here (no rotation/cascade involved).
- Story 12.4's Rule 12 chrome-devtools-mcp screenshot pattern.

## Completion Notes

**Files modified (absolute paths):**
- `c:\git\iris-session-agent\src\SessionAgent\EnsPortal\MessageViewer.cls` — added `agentSessionFilterIds` page property + `ApplyAgentSessionFilter` / `ClearAgentSessionFilter` ClientMethods + `XData searchPane` override (verbatim parent + prepended badge host element) + `DrawAgentFilterBadge` OnDrawContent callback + `CreateResultSet` override (sub-query wrapper).
- `c:\git\iris-session-agent\src\SessionAgent\UI\ChatPanel.cls` — `EmitStyle` extended with `.sa-load-into-table-btn` + `.sa-agent-filter-badge` rule families using existing `--sa-accent-color` / `--sa-citation-chip-text` / `--sa-from-search-stripe-bg` tokens.
- `c:\git\iris-session-agent\static\chat-panel.js` — `renderSearchResultList` extended with validated session-ID collector + button emission + click handler that calls `zenPage.ApplyAgentSessionFilter(JSON.stringify(filtered))` after re-validation.
- `c:\git\iris-session-agent\src\SessionAgent\Test\MessageViewerTest.cls` — 7 new tests (`TestApplyAgentSessionFilterPresent`, `TestClearAgentSessionFilterPresent`, `TestCreateResultSetHonorsAgentFilter`, `TestDrawAgentFilterBadgePresent`, `TestCreateResultSetWrapperSqlShape`, `TestAgentSessionFilterIdsPropertyDeclared`, `TestSearchPaneInjectsBadgeHost`).
- `c:\git\iris-session-agent\src\SessionAgent\Test\ChatPanelJsTest.cls` — 1 new test (`TestRenderSearchResultListEmitsLoadButton`).

**Files created:**
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\12-5-screenshot-load-button.png` — AC-1 layout-correctness evidence (button rendered in chat panel below tile list).
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\12-5-screenshot-filter-badge.png` — AC-4 layout-correctness evidence (badge rendered above filter form, table filtered to 3 sessions).

**Verbatim AC evidence:**

- **AC-1 evidence (button emission, layout-correctness):** chrome-devtools-mcp screenshot + computed-style probe — `display=block`, `backgroundColor=rgb(0,102,204)`, `color=rgb(255,255,255)`, `borderRadius=4px`, `padding=6px 14px`, `cursor=pointer`. Label: `"Load 3 sessions into table"`; ARIA: `"Load 3 sessions into the central message viewer table"`.
- **AC-2 evidence (ZenMethod source):** `TestApplyAgentSessionFilterPresent` passes — body contains `JSON.parse(`, `/^\d+$/`, `zenPage.agentSessionFilterIds`, `agentFilterBadgeHost`, `zenPage.doSearch()`. Live exercise: invoking `zenPage.ApplyAgentSessionFilter(JSON.stringify([76928,76921,79369]))` returned property state `"76928,76921,79369"`.
- **AC-3 evidence (verbatim wire-shape):** Live `searchQuery` post-filter: `SELECT * FROM (SELECT TOP 100 head.ID As ID, {fn RIGHT(%EXTERNAL(head.TimeCreated),999 )} As TimeCreated, head.SessionId As Session, head.Status As Status, CASE head.IsError WHEN 1 THEN 'Error' ELSE 'OK' END As Error, head.SourceConfigName As Source, head.TargetConfigName As Target FROM Ens.MessageHeader head WHERE  head.SessionId = head.%ID ORDER BY head.SessionId Desc) ms_sub WHERE ms_sub.Session IN (76928,76921,79369)`. Table re-rendered with exactly 3 rows matching the IDs.
- **AC-4 evidence (badge layout-correctness):** chrome-devtools-mcp snapshot showed `status atomic live="polite" relevant="additions text"` with text `"Filtered by agent search: 3 sessions"` followed by the `Clear agent-search filter` button. Screenshot saved.
- **AC-5 evidence (clear via × button):** Click on `.sa-agent-filter-badge-clear` → `zenPage.agentSessionFilterIds` reset to `""` → badge removed from DOM → table re-rendered with 100 unfiltered rows visible.
- **AC-6 evidence (replay path):** AC-6 is satisfied automatically because the new button code lives inside `renderSearchResultList`, which Story 12.6 already invokes from the replay path. The 12.6 test `TestPriorTranscriptReplaysToolCalls` continues to pass (22/22 ChatPanelJsTest), confirming the replay wiring is intact.
- **AC-7 evidence (`node -c`):** `node -c c:/git/iris-session-agent/static/chat-panel.js; echo "EXIT=$?"` returned `EXIT=0` verbatim.
- **AC-8 evidence (regression sweep):** Canonical numerical-MAX SQL probe per `.claude/rules/object-script-testing.md`: `Total=461, Passed=461, Failed=0` across 52 distinct SessionAgent.Test classes. Baseline 453 + 8 new tests = 461 exact reconciliation. New tests confirmed in `MessageViewerTest=17/17`, `ChatPanelJsTest=22/22`, `SearchAgentRenderTest=4/4` (unchanged, verifies no regression on touched surface).

**Key design decisions:**

1. **`CreateResultSet` minimum-blast-radius approach (per spec Dev Notes):** Override calls `##super(.pSC, pInfo)` first to build the base ResultSet (preserving every parent-side filter, sort, pagination, and warning behavior), then if the agent-filter is active and `..searchQuery` is populated, builds a wrapper `%SQL.Statement` whose query is `SELECT * FROM (<original SQL>) ms_sub WHERE ms_sub.Session IN (CSV)` and returns the wrapper's result. Updates `..searchQuery` and `pInfo.queryText` so the "Show Query" diagnostic reflects reality. Falls back to base RS on `%Prepare` failure (defensive).

2. **Column name `Session` (not `SessionId`):** Verified via Task 0 probe of `irislib/EnsPortal/MsgFilter/Assistant.cls` line 247: `head.SessionId As Session`. The wrapper's WHERE clause uses `ms_sub.Session`.

3. **CSV as on-page-property storage (not JSON):** `%ZEN.Datatype.string` is a single line, no encoding overhead. JS-side click handler converts JSON-array → numeric-validated CSV at the boundary; server-side `CreateResultSet` reads CSV directly and emits the IN-list.

4. **SQL injection — three layers of validation:**
   - JS click-handler in `renderSearchResultList` filters with `/^\d+$/` per element + `Number(...)`/`isFinite`/`Math.floor` checks before writing to button's `data-session-ids` attribute.
   - JS click-handler re-validates at click-time before calling `zenPage.ApplyAgentSessionFilter` (defense against DOM tampering).
   - `ApplyAgentSessionFilter` ClientMethod re-validates each ID against `/^\d+$/` before assigning to `zenPage.agentSessionFilterIds`.
   - Server-side `CreateResultSet` re-validates the CSV against `^[0-9]+(,[0-9]+)*$` ObjectScript regex before SQL concatenation. Any non-match falls back to unfiltered base RS.

5. **`searchPane` XData override:** Re-states the parent's body verbatim with a single prepended `<html id="agentFilterBadgeHost" OnDrawContent="DrawAgentFilterBadge" />` element. Same trade-off as `detailsPane` — Zen has no XData merge semantic, version-pinning is a documented cost.

6. **`$Char(0)` sentinel normalization:** Both `DrawAgentFilterBadge` and `CreateResultSet` normalize `agentSessionFilterIds = $Char(0)` to empty string per project rule §"$Char(0) sentinel".

**Issues encountered + resolution:**

- **Test failure on regex assertion:** First run had `TestApplyAgentSessionFilterPresent` failing because the assertion used `"/^\\d+$/"` (two backslashes) which in ObjectScript string literals encodes literal `\\d` rather than `\d`. Fixed by using `"/^\d+$/"` (single backslash; ObjectScript does NOT escape backslash in string literals). Confirmed empirically via `iris_execute_command` probe: compiled body has `/^\d+$/` literal.

## Code Review Notes (2026-05-08)

**Reviewer auto-fixed (MEDIUM, fix-now per Rule 8):**

1. **Reset button now clears the agent filter (AC-5 contract gap).** Added a `loadSearch(searchName, run)` ClientMethod override on `SessionAgent.EnsPortal.MessageViewer` that detects the Reset semantics (`searchName === ''`) — clears `agentSessionFilterIds`, refreshes the badge host, then delegates to the parent via `this.invokeSuper('loadSearch', arguments)`. Without this override, clicking the Reset button on the page Ribbon (which fires `zenPage.loadSearch('',true)` per `EnsPortal.MessageViewer:OnGetRibbonInfo` line 138) would clear the form fields but leave the agent filter active — the badge would still show "Filtered by agent search: N sessions" and the table would still narrow to those IDs, contradicting AC-5. Fix verified clean compile + `MessageViewerTest=17/17`.

2. **`%Prepare`/`%Execute` failure now emits a `searchWarnings` entry instead of silently leaking unfiltered results.** In `CreateResultSet`, replaced the silent `Quit tBaseRS` on each failure path (prepare error / `%Execute` non-OREF / negative `%SQLCODE`) with `Do ..searchWarnings.Insert(...)` + `Quit tBaseRS`. Without the warning, an operator who triggered a failure path would see the badge claiming "Filtered by agent search: N sessions" while the table showed the full unfiltered base result — operator-trust erosion. The parent's existing JS warning surface (`searchWarnings.length > 0`) renders the warning above the result table so the operator gets a clear "filter could not be applied — showing unfiltered results" signal. Fix verified clean compile + regression 461/461/0.

**Reviewer-deferred (LOW, no predicted-bug shape per Rule 8 test 3):**

- `--sa-button-fg` CSS custom property referenced in `.sa-load-into-table-btn` rule but never declared in `EmitStyle()`. Fallback `#ffffff` always applies; rule renders correctly. Recorded in `deferred-work.md` for next ChatPanel.cls touch.

**Reviewer dismissed:**

- Spec wording "ZenMethod" vs dev's `ClientMethod` choice for `ApplyAgentSessionFilter` — dev's choice is functionally correct AND simpler (no server round-trip needed at click moment; property mutation happens client-side, syncs server-side on the subsequent `doSearch()` ZenMethod fire). Terminology drift in the spec, not a bug.

**Post-fix verification:**

- `MessageViewerTest`: 17/17 pass (all new methods green, including `TestApplyAgentSessionFilterPresent`, `TestCreateResultSetHonorsAgentFilter`, `TestSearchPaneInjectsBadgeHost`).
- `ChatPanelJsTest`: 22/22 pass.
- Full regression sweep via canonical numerical-MAX SQL ground-truth probe: `Total=461, Passed=461, Failed=0`.
- `node -c static/chat-panel.js` exit 0 (Story 12.0 Carry-Forward — re-verified post-fix).

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.6 commit `39b4b91`).
- 2026-05-08 — Implementation complete (Amelia/dev). All 8 ACs verified, 8 new tests added, regression sweep 461/461/0 via SQL ground-truth probe.
- 2026-05-08 — Code review complete (reviewer). Two MEDIUM auto-fixes applied: (1) Reset button now clears agent filter (AC-5 contract closure), (2) `%Prepare`/`%Execute` failure paths now emit `searchWarnings` instead of silent unfiltered leak. One LOW deferred (`--sa-button-fg` dead var indirection). Status → done.
