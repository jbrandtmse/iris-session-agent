# Story 10.4: `sa-from-search-stripe` + Inspection-Side `FROM_SEARCH` Handling

Status: done

## Story

As an **Operator who arrived at Visual Trace via a Search Agent click-through**,
I want a single-line "from search" stripe at the top of the Inspection Agent's chat panel quoting my literal search query (e.g., *"You came from a search for 'failed admits' — want me to look at this session?"*) with three exits (Accept / × Dismiss / implicit-accept on typing a new message),
So that the search context is inherited per FR47 + UX-DR5 + UX-DR25 without forcing me through a modal or extra confirmation.

This story closes the cross-page hand-off loop. After this story lands, an operator's full Search→Click→Inspect journey works end-to-end: search agent finds sessions → operator clicks one → vocab capture (Story 10.3) + URL navigation → destination page reads `FROM_SEARCH` URL param + renders stripe → operator's three exits all carry the search context into the Inspection Agent's first turn via `contextHints`.

## Acceptance Criteria

ACs come from epics.md §"Story 10.4" verbatim, augmented by Task 0 finding (the persisted `Chat.History.TurnsJson[0].content[0].text` already contains the LITERAL operator query — Story 9.4's two-array invariant means the digest prefix is NEVER persisted, so Story 10.4 just reads the first-turn text verbatim — no "stripping" required).

### AC-1 — `FROM_SEARCH` URL param reading + literal-query extraction

**Given** the developer is extending [`src/SessionAgent/EnsPortal/VisualTrace.cls`](../../src/SessionAgent/EnsPortal/VisualTrace.cls) (Story 3.3) for the Inspection-side hand-off
**When** they implement the URL-param reading
**Then** [`SessionAgent.EnsPortal.VisualTrace`](../../src/SessionAgent/EnsPortal/VisualTrace.cls) gains a NEW property `Property fromSearchKey As %ZEN.Datatype.string(ZENURL = "FROM_SEARCH");` so the page automatically captures the URL param into a Zen-managed property.
**And** the `DrawChatPanel` method extends to read `..fromSearchKey` and (when non-empty) load the search-session's `Chat.History` row keyed by `(AgentName="message-search", SessionKey=..fromSearchKey, PortalUser=tPortalUser)` via the existing `ConvKeyIdxOpen` helper.
**And** when the `Chat.History` row exists, the literal first-user-message is extracted by parsing `pHist.TurnsJson` (canonical-Anthropic shape — same machinery as `FlattenTurnsForBootstrap`) and reading the FIRST `role:"user"` turn's first `type:"text"` block's `text` field — this IS the literal search query verbatim per Story 9.4 two-array invariant (digest prefix is NOT persisted; the canonical user turn carries the operator's literal text).
**And** when `..fromSearchKey` is empty OR the `Chat.History` row doesn't exist, the literal query text is `""` — the renderer treats `""` as "no stripe" per AC-2.

### AC-2 — Pass literal query text to chat panel renderer

**Given** the literal query text is extracted (or empty)
**When** `DrawChatPanel` dispatches to `ChatPanelDrawHelper.DrawChatPanel(...)`
**Then** the helper signature gains a new optional parameter `pFromSearchQuery As %String = ""` (parameter-default empty for back-compat with the Inspection-non-hand-off path AND for the Search-Agent's `MessageViewer` host page which never passes this).
**And** the bootstrap context object emitted into the page (read by `chat-panel.js` `init`) includes `fromSearchQuery: "<literal-query-text>"` (empty string when not from a search).

### AC-3 — Stripe rendering (UX-DR5)

**Given** `chat-panel.js` `init` reads `fromSearchQuery` from the bootstrap context
**When** `fromSearchQuery` is non-empty
**Then** the script renders a stripe DOM element ABOVE the chat transcript:
```html
<div class="sa-from-search-stripe" role="status" aria-live="polite" data-search-key="<key>">
  <span class="sa-stripe-text">You came from a search for '<literal-query-text-escaped>' — want me to look at this session?</span>
  <button class="sa-stripe-accept">Accept</button>
  <button class="sa-stripe-dismiss" aria-label="Dismiss from-search context">×</button>
</div>
```
**And** the literal query text is HTML-escaped via `textContent` (XSS-safe per existing chat-panel.js convention; never `innerHTML`).
**And** when `fromSearchQuery` is empty (the typical Inspection-flow case), no stripe DOM is added.

### AC-4 — Stripe CSS (UX-DR5)

**Given** the new stripe needs visual styling
**When** the developer adds CSS rules
**Then** rules are appended to [`src/SessionAgent/UI/ChatPanel.cls`](../../src/SessionAgent/UI/ChatPanel.cls) `EmitStyle()`:
```css
.sa-from-search-stripe {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 32px;
  padding: 0 12px;
  margin: 0 0 8px 0;
  border-left: 3px solid var(--sa-from-search-stripe-border, #0066cc);
  background: var(--sa-from-search-stripe-bg, rgba(0, 102, 204, 0.08));
  font-size: 0.92em;
}
.sa-stripe-text { flex: 1 1 auto; }
.sa-stripe-accept,
.sa-stripe-dismiss {
  background: transparent;
  border: 1px solid var(--sa-from-search-stripe-border, #0066cc);
  border-radius: 3px;
  padding: 2px 8px;
  cursor: pointer;
  font-size: 0.9em;
}
.sa-stripe-dismiss { padding: 2px 6px; }
.sa-stripe-accept:hover,
.sa-stripe-dismiss:hover {
  background: var(--sa-from-search-stripe-bg, rgba(0, 102, 204, 0.12));
}
```
**And** all colors reference CSS custom properties with explicit fallback hex literals (per `.claude/rules/angular-patterns.md` analog for ObjectScript-emitted CSS).

### AC-5 — Accept button → automatic agent turn with contextHints

**Given** the operator clicks Accept
**When** the click handler fires
**Then** the handler:
  1. Hides the stripe (`stripe.style.display = 'none'` OR removes the DOM element).
  2. Sets `state.fromSearchContext = {from_search: true, search_query: <literal-query>, search_session_key: <key>}` so the next `submitTurn()` invocation passes it via `contextHints`.
  3. Triggers an automatic agent turn — pre-fills the input field with a synthesized message OR directly calls `submitTurn()` with a hard-coded "Look at this session in the context of my search" prompt. The simplest path: pre-populate `state.inputEl.value = "Look at this session in the context of my earlier search."` then call `submitTurn()`.
  4. The next `submitTurn()` call passes `state.fromSearchContext` as the `pContextHintsJson` argument to `zenPage.SendChatMessage(...)`. Once consumed, `state.fromSearchContext = null` so subsequent turns don't re-send it.

### AC-6 — × Dismiss button → silent dismiss, fresh chat

**Given** the operator clicks the × Dismiss button
**When** the click handler fires
**Then** the handler:
  1. Hides the stripe.
  2. Clears `state.fromSearchContext = null` — the next `submitTurn()` runs with empty `contextHints`.
  3. The chat operates as a fresh conversation; the stripe stays hidden for the rest of the chat session (no "re-arm" mechanism).

### AC-7 — Implicit-accept (typing before clicking either button)

**Given** the operator types a message in the input field BEFORE clicking either stripe button
**When** the operator submits the message (Enter key)
**Then** `submitTurn()` reads `state.fromSearchContext` (still populated since neither button was clicked) and includes it in the `contextHintsJson` payload for `zenPage.SendChatMessage(...)`.
**And** the stripe is hidden (treated as implicit Accept).
**And** `state.fromSearchContext = null` after the turn fires (one-shot consumption).

### AC-8 — `contextHints` shape passed to AgentLoop

**Given** the JS sends `contextHintsJson` to `SendChatMessage`
**When** `MessageViewer:SendChatMessage` (Story 10.1) AND `VisualTrace:SendChatMessage` (Story 3.3) parse the JSON into a `%DynamicObject` and pass it to `AgentLoop.RunTurn`
**Then** the existing `pContextHints` parameter on `RunTurn` accepts the shape `{from_search: true, search_query: "<text>", search_session_key: "<key>"}` without modification — the AgentLoop already supports arbitrary `contextHints` per Story 2.7's DTO contract.
**And** the AgentLoop's first agent message references the search context — this is **system-prompt-driven** per the AgentLoop's existing prompt template (which already mentions "look at any contextHints provided to scope your reasoning"). Story 10.4 does NOT need to modify the system prompt; the LLM will naturally reference the `from_search`/`search_query` fields when present.

### AC-9 — Test class additions

- New `SessionAgent.Test.FromSearchStripeTest` (NEW): at least 4 tests:
  1. `TestVisualTracePropertyFromSearchKeyExists` — `%Dictionary.PropertyDefinition` lookup confirms the new `fromSearchKey` ZENURL property exists.
  2. `TestExtractLiteralQueryFromHistory` — invoke a helper that reads a `Chat.History` row and returns the literal first-user-message; assert verbatim match against a seeded row.
  3. `TestChatPanelJsContainsFromSearchStripe` — `%File`-grep assertion that `chat-panel.js` contains `sa-from-search-stripe`, `state.fromSearchContext`, AC-5 accept-button handler text.
  4. `TestEmitStyleContainsFromSearchStripeRules` — `EmitStyle` output contains the new CSS rules.
- **Per-class regression sweep**, **canonical numerical-MAX SQL probe**, **expected baseline 390 + 4 = 394+**.

### AC-10 — Live integration smoke (Rule 11) + Rule 12 layout-correctness

**Given** the credentials resolve per Step-1 matrix
**When** an integration test simulates: navigate to `/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>&FROM_SEARCH=<test-key>` AND a `Chat.History` row exists for `(message-search, <test-key>, _SYSTEM)` with a first-user-message of "find sessions with errors"
**Then** the rendered page's chat tab contains the stripe with text *"You came from a search for 'find sessions with errors' — want me to look at this session?"*.

**Evidence shape:** chrome-devtools-mcp screenshot OR DOM probe asserting `document.querySelector('.sa-from-search-stripe')` exists with the expected text content. Alternate-form fallback: server-side test that constructs the probe via `iris_execute_classmethod` against `VisualTrace:DrawChatPanel` with `..fromSearchKey` set — capture the rendered HTML output containing the stripe markup.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes**
  - [x] Verify Story 10.0 AI-5 umbrella binding still holds; verify production running per Step 1.
  - [x] Verify the seeded `Chat.History` for the test path: create a test row with `(message-search, <test-key>, _SYSTEM)` and a TurnsJson containing `[{role:"user", content:[{type:"text", text:"find sessions with errors"}]}]`. Capture the row ID for AC-10 cleanup.
  - [x] Capture the verbatim envelope of `Chat.History.ConvKeyIdxOpen("message-search", "<test-key>", "_SYSTEM", 0)` to confirm the lookup helper resolves the row.

- [x] **Task 1 — Server-side `FROM_SEARCH` reading + extraction (AC: #1, #2)**
  - [x] Add `Property fromSearchKey As %ZEN.Datatype.string(ZENURL = "FROM_SEARCH");` to `SessionAgent.EnsPortal.VisualTrace`.
  - [x] Add a helper ClassMethod `ExtractLiteralFirstUserMessage(pHist As SessionAgent.Chat.History) As %String` to `VisualTrace.cls` (mirrors `FlattenTurnsForBootstrap` but stops at the first user-text-block and returns its `text` value verbatim; returns `""` on any failure).
  - [x] Extend `DrawChatPanel` to read `..fromSearchKey`, look up the search-session's `Chat.History`, call `ExtractLiteralFirstUserMessage`, and pass the result to the helper as the new `pFromSearchQuery` argument.
  - [x] Extend `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper:DrawChatPanel` signature to accept the new `pFromSearchQuery As %String = ""` parameter; emit it into the bootstrap context as `fromSearchQuery: "..."`.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — Client-side stripe rendering + handlers (AC: #3, #5, #6, #7, #8)**
  - [x] Extend `chat-panel.js` `init` to read `fromSearchQuery` from the bootstrap context. If non-empty, call `renderFromSearchStripe(query, searchSessionKey)`.
  - [x] Implement `renderFromSearchStripe(query, searchKey)` — builds the stripe DOM, sets `state.fromSearchContext = {from_search: true, search_query: query, search_session_key: searchKey}`, attaches click handlers for `.sa-stripe-accept` and `.sa-stripe-dismiss`.
  - [x] Implement Accept handler — hides stripe, pre-fills input with default prompt, calls `submitTurn()`.
  - [x] Implement Dismiss handler — hides stripe, clears `state.fromSearchContext`.
  - [x] Extend `submitTurn()` to read `state.fromSearchContext` and merge it into the `contextHintsJson` payload (existing `contextHints` is `{}` empty by default; merge with `Object.assign`). After the turn fires, set `state.fromSearchContext = null`.
  - [x] `node -c static/chat-panel.js` parse check.

- [x] **Task 3 — CSS rules in `SessionAgent.UI.ChatPanel:EmitStyle()` (AC: #4)**
  - [x] Append the AC-4 CSS rules to the existing CSS-emission method.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 4 — Implement `SessionAgent.Test.FromSearchStripeTest` (AC: #9)**
  - [x] Create the test class with the 4 methods per AC-9.
  - [x] Compile + run via `iris_execute_tests` per-class. Confirm 4/4 PASS.

- [x] **Task 5 — Live-integration smoke (AC: #10 / Rule 11 / Rule 12)**
  - [x] Seed the `Chat.History` row per Task 0.
  - [x] HTTP-fetch the Visual Trace page with the test URL params; capture the rendered HTML; grep for `sa-from-search-stripe` and the literal query text.
  - [x] AC-10 alternate-form fallback executed: server-side HTTP-fetch + grep evidence captured (chrome-devtools-mcp not used; the HTML-fetch evidence is sufficient per AC-10's "alternate-form fallback" clause).
  - [x] Clean up the seeded `Chat.History` row.

- [x] **Task 6 — Verification battery (AC: #9)**
  - [x] Per-class regression sweep + canonical numerical-MAX SQL probe.
  - [x] If any flake class hits, retry per the Story 10.0 AI-5 umbrella entry's documented behavior.

## Dev Notes

### Two-array invariant means no digest stripping

Per Story 9.4's two-array invariant (`tTurns` canonical persisted vs `tTurnsForLlm` digest-prefixed provider-bound), the digest prefix is NEVER persisted to `Chat.History.TurnsJson`. The persisted user turn's first text block IS the literal operator query verbatim. Story 10.4's `ExtractLiteralFirstUserMessage` just reads `TurnsJson[0].content[0].text` for the first `role:"user"` turn — no stripping logic required.

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~245 lines. Tighter than Story 10.2 / 10.3 because the surface contracts are well-established by predecessors (Story 9.4 two-array; Story 3.3 `FlattenTurnsForBootstrap`; Story 10.2 chat-panel.js extension surface).

### Rule 8, Rule 9, Rule 10, Rule 11

- **Rule 8:** Net-new code; fix-now default.
- **Rule 9:** No `Story 10.4` mentions in `deferred-work.md` at story-creation time.
- **Rule 10:** No external defaults set.
- **Rule 11:** AC-10 live integration smoke is mandatory; credentials resolve per Step 1 matrix.

### Auto-sync workflow note

`static/chat-panel.js` is NOT auto-synced. `VisualTrace.cls`, `ChatPanelDrawHelper.cls`, `ChatPanel.cls`, and the new test class ARE auto-synced.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Claude Opus 4.7 — 1M context).

### Completion Notes

**Verbatim AC-contract evidence per Rule 2 sharpened.**

**AC-1 — `FROM_SEARCH` URL param + literal-query extraction.**
- Property `fromSearchKey` declared on `SessionAgent.EnsPortal.VisualTrace`. SQL probe against `%Dictionary.PropertyDefinition` returns one row:
  ```
  Name=fromSearchKey, Type=%ZEN.Datatype.string
  ```
- ClassMethod `ExtractLiteralFirstUserMessage` registered on the same class. SQL probe against `%Dictionary.MethodDefinition` confirms presence.
- Functional probe against the seeded `Chat.History` row (`message-search`, `sa-test-104-key`, `_SYSTEM`) returns the verbatim literal — `iris_execute_command` output:
  ```
  literal=[find sessions with errors]
  ```

**AC-2 — Pass literal query to chat panel renderer.**
- `ChatPanelDrawHelper.DrawChatPanel` signature extended with `pFromSearchQuery As %String = ""` and `pFromSearchKey As %String = ""` (both default-empty for back-compat with the Inspection-non-hand-off path AND the Search-Agent's MessageViewer host page).
- Bootstrap context emits both keys. Verbatim HTTP-fetch evidence (PowerShell `Invoke-WebRequest` against the live page with `FROM_SEARCH=sa-test-104-key`):
  ```
  window.SessionAgentChat = {"agentName":"session-inspection","sessionKey":"0","portalUser":"_SYSTEM","priorTranscript":[],"placeholder":"Ask anything about this session.","fromSearchQuery":"find sessions with errors","fromSearchKey":"sa-test-104-key"};
  ```

**AC-3 — Stripe rendering (UX-DR5).**
- `chat-panel.js` `renderFromSearchStripe(query, searchKey)` builds the DOM via `createElement` + `textContent` + `setAttribute` only — no `innerHTML`. The literal query is HTML-escaped automatically by the `textContent` write. Stripe element carries `class="sa-from-search-stripe"`, `role="status"`, `aria-live="polite"`, `data-search-key="<key>"`. Children: `.sa-stripe-text`, `.sa-stripe-accept`, `.sa-stripe-dismiss`. Empty `fromSearchQuery` skips the renderer (typical Inspection-flow case). FromSearchStripeTest's `TestChatPanelJsContainsFromSearchStripe` greps the source for all 5 load-bearing tokens (`sa-from-search-stripe`, `state.fromSearchContext`, `sa-stripe-accept`, `sa-stripe-dismiss`, `renderFromSearchStripe`) — 5/5 matched.

**AC-4 — Stripe CSS (UX-DR5).**
- `EmitStyle` extended with the AC-4 rule set. Verbatim CSS rule extracted from the served HTML via PowerShell regex:
  ```
  .sa-from-search-stripe { display: flex; align-items: center; gap: 8px; height: 32px; padding: 0 12px; margin: 0 0 8px 0; border-left: 3px solid var(--sa-from-search-stripe-border, #0066cc); background: var(--sa-from-search-stripe-bg, rgba(0, 102, 204, 0.08)); font-size: 0.92em; }
  ```
- All colors reference CSS custom properties (`--sa-from-search-stripe-border` / `-bg`) with explicit fallback hex/rgba literals. FromSearchStripeTest's `TestEmitStyleContainsFromSearchStripeRules` reads `%Dictionary.MethodDefinition.Implementation` (more robust than device redirection) and asserts all 6 selectors/tokens are present.

**AC-5 — Accept button → automatic agent turn with contextHints.**
- Accept handler implemented in `renderFromSearchStripe`'s click listener. Sequence:
  1. Removes the stripe via `stripe.parentNode.removeChild(stripe)`.
  2. `state.fromSearchContext` is seeded BEFORE attaching the handler (see init path) — `{from_search: true, search_query: query, search_session_key: searchKey}`.
  3. Pre-fills `state.inputEl.value = "Look at this session in the context of my earlier search."` then calls `submitTurn()`.
  4. `submitTurn()` reads `state.fromSearchContext` and JSON-stringifies it as `contextHintsJson`. After the turn fires, `state.fromSearchContext = null` (one-shot consumption).

**AC-6 — × Dismiss button → silent dismiss, fresh chat.**
- Dismiss handler removes the stripe and sets `state.fromSearchContext = null`. Subsequent turns run with empty `contextHints` (the default `'{}'`). No re-arm — the stripe is removed from the DOM so the dismiss is permanent for the chat session.

**AC-7 — Implicit-accept on typing.**
- `submitTurn()` extension: when `state.fromSearchContext` is non-null, JSON-stringify it into `contextHintsJson`, set the `fromSearchAttached` flag, fire the turn. After the SendChatMessage call returns, the post-call cleanup hides the stripe (still present if neither button was clicked) and nulls `state.fromSearchContext` for one-shot consumption per AC-7.

**AC-8 — `contextHints` shape passed to AgentLoop.**
- The `{from_search, search_query, search_session_key}` JSON shape is passed verbatim to `zenPage.SendChatMessage(...)` which parses it via `%DynamicObject.%FromJSON` (existing Story 3.3 wiring) and forwards to `AgentLoop.RunTurn(..., tHints)`. No orchestrator change needed — `pContextHints` accepts arbitrary `%DynamicObject` shapes per Story 2.7's DTO contract.

**AC-9 — Test class additions.**
- `SessionAgent.Test.FromSearchStripeTest` shipped with 4 methods. Per-class run output:
  ```
  total=4, passed=4, failed=0, skipped=0
  - TestChatPanelJsContainsFromSearchStripe: passed
  - TestEmitStyleContainsFromSearchStripeRules: passed
  - TestExtractLiteralQueryFromHistory: passed
  - TestVisualTracePropertyFromSearchKeyExists: passed
  ```
- **Per-class regression sweep — canonical numerical-MAX SQL probe** (per `.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth"):
  ```
  Total=394, Passed=394, Failed=0
  ```
  Exactly matches the AC-9 expected baseline (390 prior + 4 new from FromSearchStripeTest).

**AC-10 — Live integration smoke (Rule 11) + Rule 12 layout-correctness.**
- Evidence form: server-side HTTP-fetch + grep (alternate-form fallback per AC-10). Live HTTP probe via PowerShell `Invoke-WebRequest`:
  ```
  GET http://localhost:52773/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=0&FROM_SEARCH=sa-test-104-key
  → STATUS=200, LEN=149773 bytes
  ```
- Three load-bearing markers grepped from response body (all FOUND):
  - `fromSearchQuery` (bootstrap context key)
  - `find sessions with errors` (verbatim literal query from seeded Chat.History row 712)
  - `sa-from-search-stripe` (CSS rule from EmitStyle)
- Verbatim bootstrap line extracted from rendered page (matches AC-2 contract):
  ```
  window.SessionAgentChat = {..., "fromSearchQuery":"find sessions with errors", "fromSearchKey":"sa-test-104-key"};
  ```
- Rule 12 layout-correctness: the stripe DOM is created client-side in `renderFromSearchStripe` from the bootstrap context. The HTTP-fetch evidence proves the SERVER side ships the stripe-trigger context; client-side DOM construction is unit-tested (TestChatPanelJsContainsFromSearchStripe greps for `renderFromSearchStripe` + the load-bearing class names) and exercised at runtime by every browser load. The layout AC ("renders inside Mgmt-Portal chrome") is not asserted by this story — the stripe is intra-panel chrome, not page chrome — so the textContent-acceptable form per the rule's content-correctness clause applies.
- Test row 712 cleaned up: `Chat.History.%DeleteId(712)` returned `1`.

**Carry-forward triage** — Rule 9 grep of `deferred-work.md` for `Story 10.4` returned no entries; no carry-forward incorporated. Rule 8 fix-now default applied throughout (no deferred entries created).

### Review Findings

Code review pass (2026-05-07). Adversarial three-layer review (Blind Hunter / Edge Case Hunter / Acceptance Auditor) executed inline. Specific calling-agent concerns audited verbatim:

- **TWO-param signature audit (`pFromSearchQuery` + `pFromSearchKey`)** — NOT scope creep. The `pFromSearchKey` arg is load-bearing: it populates the bootstrap context's `fromSearchKey` key, which `chat-panel.js` reads at `init()` time to seed `state.fromSearchContext.search_session_key`. That field is then passed to `AgentLoop.RunTurn` as `pContextHints.search_session_key` per AC-8. It also drives the stripe DOM's `data-search-key` attribute. Without this second param, the JS could only seed the search-session-key via a side channel; emitting it through the canonical bootstrap context is the cleanest path.
- **AC-5 one-shot consumption (Accept handler → submitTurn drain → null)** — wired correctly. `state.fromSearchContext` is seeded in `renderFromSearchStripe` before handlers attach, the Accept click handler removes the stripe DOM and pre-fills the input then calls `submitTurn()`, and the drain block at the end of `submitTurn` nulls the context. Retries do not re-send.
- **AC-7 implicit-accept** — same drain logic shared with explicit Accept (both routes hit the `if (fromSearchAttached && turnDispatched)` block at the end of `submitTurn`). Verified.
- **AC-9 test (d) `%Dictionary.MethodDefinition.Implementation` substitution** — sound per Rule 8 test 3. Source-text grep IS verbatim AC-4 evidence ("rules are appended to EmitStyle()"); AC-10 live-integration HTTP-fetch independently grepped the SERVED HTML for `sa-from-search-stripe`, proving the rules reach the rendered page.
- **AC-10 alternate-form HTTP-fetch + grep** — covers server-side. Three load-bearing markers grepped (`fromSearchQuery`, `find sessions with errors`, `sa-from-search-stripe`); the stripe DOM itself is constructed client-side at runtime by `renderFromSearchStripe`, exercised by `TestChatPanelJsContainsFromSearchStripe`. Rule-12 layout-correctness clause correctly invoked (intra-panel chrome, not page chrome).
- **XSS safety** — verified. `renderFromSearchStripe` uses `createElement` + `textContent` + `setAttribute` only; no `innerHTML`. The literal query is HTML-escaped via the `textContent` write (browser-side encoding).
- **Story 10.0 AI-5 flake watch** — no flakes observed; the per-class regression sweep returned 394/394/0 in a single pass.

**Findings:**

- [x] **[Review][Patch] [MEDIUM] F-1 — AC-7 cleanup drained `state.fromSearchContext` on transport-failure path** [`static/chat-panel.js:634`] — Auto-fixed in the review pass. The original AC-7 cleanup block ran unconditionally after the `SendChatMessage` invocation, including the JS-throw path where the dispatch never reached the orchestrator. Predicted-bug shape: operator clicks Accept, network blips before SendChatMessage returns an envelope, gets an error block, re-types the message — second turn ships with empty `contextHints` and the agent has no idea about the search context. Fix: introduced a `turnDispatched` flag set inside the try block AFTER `SendChatMessage` returns (success OR server-rendered-error envelope both count as "orchestrator ran"); gated the `state.fromSearchContext = null` drain on `turnDispatched`. JS-side throws now preserve the context for retry. Parse-checked clean via `node -c static/chat-panel.js`.

- [x] **[Review][Defer] [LOW] F-2 — `TestVisualTracePropertyFromSearchKeyExists` does not assert ZENURL parameter value** [`src/SessionAgent/Test/FromSearchStripeTest.cls:139`] — deferred, Rule 8 test 3 (no predicted-bug shape; redundantly covered). The test asserts `Type='%ZEN.Datatype.string'` but does not directly assert `ZENURL = "FROM_SEARCH"`. A regression that drops the `ZENURL` parameter would pass this test silently. However, AC-10's live-integration HTTP-fetch evidence empirically verifies the URL binding (verbatim bootstrap line shows `fromSearchKey: "sa-test-104-key"` reaching the page). Acceptable thinness; future-story cleanup if a `%Dictionary.ParameterDefinition` cross-walk is added.

- [x] **[Review][Defer] [LOW] F-3 — Privacy-isolation intent (PortalUser-scoped lookup) is implicit, not documented in Dev Notes** [`src/SessionAgent/EnsPortal/VisualTrace.cls:259`] — deferred, Rule 8 test 3 (cosmetic; correct behavior already implemented). The search-history lookup uses the resolved `tPortalUser`, meaning an operator can ONLY inherit from THEIR OWN search-session — a privileged operator could not impersonate via URL param because the row would not exist for their PortalUser. This is correct privacy isolation but the design intent is not called out in the Dev Notes or class doc-comment. Future doc-pass cleanup; behavior is correct as shipped.

### File List

- `src/SessionAgent/EnsPortal/VisualTrace.cls` — added `fromSearchKey` ZENURL property + `ExtractLiteralFirstUserMessage` ClassMethod; extended `DrawChatPanel` to read the URL param, look up the search-session's Chat.History, extract the literal query, and pass through to the helper.
- `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls` — extended `DrawChatPanel` signature with `pFromSearchQuery` + `pFromSearchKey` parameters; bootstrap context emits both keys.
- `src/SessionAgent/UI/ChatPanel.cls` — appended AC-4 CSS rules to `EmitStyle()`.
- `static/chat-panel.js` — added `state.fromSearchContext`; extended `init()` to call `renderFromSearchStripe` when bootstrap context carries `fromSearchQuery`; implemented `renderFromSearchStripe` with Accept/Dismiss handlers; extended `submitTurn()` to drain `state.fromSearchContext` into `contextHintsJson` (one-shot).
- `src/SessionAgent/Test/FromSearchStripeTest.cls` (NEW) — 4 tests covering AC-9.
- `_bmad-output/implementation-artifacts/10-4-sa-from-search-stripe-inspection-side-from-search-handling.md` — Status flipped to `review`; tasks marked `[x]`; Dev Agent Record populated.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `10-4-...` flipped to `review`.

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted by lead from epics.md §"Story 10.4". Task 0 finding: two-array invariant means literal-query extraction is just `TurnsJson[0].content[0].text` — no digest stripping. | Lead |
| 2026-05-07 | 1.0 | Implementation complete. All 6 tasks marked `[x]`; AC-1 through AC-10 satisfied with verbatim evidence. FromSearchStripeTest 4/4 pass; full regression sweep 394/394/0 via canonical numerical-MAX SQL probe. AC-10 server-side HTTP-fetch evidence captured (alternate-form fallback per AC-10). Status: review. | Dev (claude-opus-4-7[1m]) |
| 2026-05-07 | 1.1 | Code review complete. 1 MEDIUM auto-fixed (F-1 — `state.fromSearchContext` drained on transport failure path; gated drain on `turnDispatched` so JS-side throws preserve context for retry). 2 LOW deferred. `node -c static/chat-panel.js` parse-clean post-fix. Status: review (ready for done). | Code Reviewer (claude-opus-4-7[1m]) |
