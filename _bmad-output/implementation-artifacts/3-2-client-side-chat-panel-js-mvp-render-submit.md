# Story 3.2: Client-Side `chat-panel.js` MVP Render & Submit

Status: review

## Story

As an **Operator using the chat tab in Visual Trace**,
I want the client-side `chat-panel.js` to handle: typing in the input field, pressing Enter to submit (Shift+Enter for newline), seeing a "Thinking..." status text appear, watching tool-call cards render in sequence as the agent dispatches tools, reading the final answer with inline citation chips, and clicking a tool-card to expand its raw input/output,
So that I can have a usable conversation with the agent — even though the vendored Markdown bundle (UX-DR13) hasn't shipped yet (per UX-DR14 fallback render path).

This story authors the JS file `static/chat-panel.js`. Story 3.1 emitted the HTML shell + the per-instance `window.SessionAgentChat` bootstrap. Story 3.3 will wire the `<script src="...">` tag (via `OnPageHeadScript`) and ship the `SendChatMessage` ZenMethod hyperevent. Story 3.4 will wire `onclick` for citation chips. **This story builds against shimmed `zenPage.SendChatMessage` and shimmed click handlers** — full integration arrives in 3.3 / 3.4.

## Acceptance Criteria

ACs come from epics.md §"Story 3.2: Client-Side `chat-panel.js` MVP Render & Submit" verbatim.

### AC-1 — Input handlers per UX-DR30

**Given** the developer is authoring `chat-panel.js` for MVP
**When** the file is committed (inline `<script src="/csp/static/iris-session-agent/chat-panel.js">` in the host page during MVP — Story 3.3 wires this; vendored at the same path during Growth tier)
**Then** the script attaches input handlers per UX-DR30: Enter → submit, Shift+Enter → insert newline (default textarea behavior), Esc → cancel mid-flight (MVP no-ops Esc with a `// TODO Story 3.5+` marker per spec — when no turn is in flight Esc does nothing; when one IS in flight Esc is recorded as a TODO).
**And** the script auto-focuses `.sa-input-field` on tab open + after every Enter submission (UX-DR16).
**And** on submit, the script invokes `zenPage.SendChatMessage(agentName, sessionKey, userText, contextHintsJson)` (Story 3.3 wires the ZenMethod), parses the returned JSON `TurnResult`, and renders message blocks + tool-call cards into `.sa-message-transcript`.

### AC-2 — Tool-call card rendering

**Given** the agent dispatches tools during a turn
**When** the response payload contains `toolCallsRendered[]` entries (per `Agent.TurnResult` DTO, Story 2.7)
**Then** the script renders each as `<details class="sa-tool-call-card sa-tool-card-status-{running|complete|error}">` containing `<summary>` (status indicator + monospace tool name + one-line summary text) plus body (tool input args + result rendered as `<pre><code>` blocks for raw inspection) per UX-DR3.
**And** the cards render in dispatch order (the order they appear in `toolCallsRendered[]`).
**And** the operator can expand/collapse cards via native `<details>`/`<summary>` keyboard interaction (UX-DR19).
**And** each card has a `data-tool-call-id` attribute matching its dispatch id (so Story 3.4's `sa-cite-tool` chip handler can look it up).

### AC-3 — Markdown fallback render path (UX-DR14)

**Given** the agent's final answer is a Markdown string (`TurnResult.assistantMarkdown`)
**When** the script renders the answer in MVP fallback mode
**Then** the script applies the simpler render path per UX-DR14:
- paragraph splits on double-newline → wrap each paragraph in `<p>` (text content via `textContent`);
- inline citation-chip patterns matching the regex `\[(rule_log|event_log|message|ack|iolog|tool):([^\]]+)\]` become `<a class="sa-citation-chip sa-cite-{rule|event|message|ack|iolog|tool}" href="#" data-cite-type="..." data-cite-id="...">[type:id]</a>` (rendering only — `onclick` handler lands in Story 3.4);
- code-block patterns (` ```lang\n...\n``` `) become `<pre><code class="language-{lang}">...</code></pre>` (text content via `textContent` for future Prism integration).

**And** the rendering does NOT yet include vendored `marked` or `Prism.js` — that lands in Epic 10 Story 10.7.
**And** the rendering does NOT use `innerHTML` on untrusted strings — uses `textContent` for plain text, `document.createElement` + `setAttribute` for citation chips / code blocks / tool cards (XSS safety in absence of DOMPurify which lands in Story 10.7).

### AC-4 — Provider-error envelope rendering

**Given** the agent dispatch produces a provider error
**When** the response payload contains an `error` field per UX-DR18-MVP-subset (e.g., `{error: {kind: "provider_timeout|provider_error|tool_error|no_config", message: "..."}}`)
**Then** the script renders an `sa-message-block sa-msg-agent sa-msg-error` block with the operator-readable error text + a brief retry hint.
**And** the input field re-enables after error rendering (operator can retry without page reload).
**And** the rendered error text is the operator-friendly `error.message` field — NOT the raw provider stack trace (per UX-DR18 — stack traces never reach the operator surface).

### AC-5 — Status-text mid-flight indicator

**Given** the operator submits a question
**When** the turn is in flight
**Then** the script writes "Thinking..." to `.sa-status-text` (which has `aria-live="polite"` per Story 3.1 AC-1 — screen readers announce it).
**And** the input field is disabled (`disabled = true`) during in-flight; re-enabled on completion or error.
**And** when the turn completes, the status-text element is cleared (`textContent = ""`).

### AC-6 — Static-file validator (test approach)

**Given** the developer wants automated coverage without requiring a headless browser test harness (which Epic 3 deferred to Story 3.6 manual cross-browser smoke)
**When** they author tests
**Then** a new ObjectScript test class `SessionAgent.Test.ChatPanelJsTest` reads the file `static/chat-panel.js` from disk via `%Stream.FileCharacter`, asserts presence of the load-bearing patterns (regex / substring matches):
- exactly one `addEventListener('keydown', ...)` on the input field
- the `Enter`/`Shift` key checks for the submit-vs-newline split
- a `zenPage.SendChatMessage(` call site
- a `JSON.parse(` call site for the returned envelope
- `<details class="sa-tool-call-card` substring (or DOM construction equivalent — verify via `createElement('details')` + `setAttribute('class', 'sa-tool-call-card ...')`)
- a `\\[(rule_log|event_log|message|ack|iolog|tool):` regex literal (citation-chip detection)
- ZERO occurrences of `.innerHTML =` (XSS-safety invariant per AC-3)
- ZERO occurrences of `eval(` or `Function(` (no dynamic code execution)
- ZERO occurrences of CDN URLs (`cdnjs|jsdelivr|unpkg|googleapis`) — vendored only per NFR-C5

The static-validator approach is the same pattern Story 3.6 will reuse for cross-browser test gating. Headless-browser tests are explicitly deferred to a future epic per Rule 8 ("genuine future-epic scope" — JS test infrastructure is its own concern; setting it up now to test ~150 lines of glue would be premature).

### AC-7 — Compile + tests + regression intact

- `static/chat-panel.js` exists at the repo root (so ZPM `<FileCopy Name="static/" ...>` includes it at install time).
- `iris_doc_compile` clean for `SessionAgent.Test.ChatPanelJsTest`.
- New test class adds at least 9 assertions (one per AC-6 bullet).
- Per-class regression sweep: 130 + 1 (new class) = **131/131** total.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight surface probe (Rule 4)**
  - [x] Confirm `static/` directory exists at the repo root (per `module.xml` `<FileCopy Name="static/" ...>` declaration). If missing, create it; the install-time `FileCopy` becomes a no-op when the source dir is empty + the directory is now ready for `chat-panel.js`.
  - [x] Confirm the `Agent.TurnResult` DTO shape from Story 2.7 — read `src/SessionAgent/Agent/TurnResult.cls` to capture exact field names: `assistantMarkdown`, `usageRollup`, `durationMs`, `toolCallsRendered[]`. The JS render code MUST match these field names verbatim — capture them in Completion Notes.
  - [x] Confirm the per-tool-call shape inside `toolCallsRendered[]` — read its `ToJson` method to capture field names (e.g., `id`, `toolName`, `status`, `summary`, `input`, `result`).

- [x] **Task 1 — Author `static/chat-panel.js` (AC: #1, #2, #3, #4, #5)**
  - [x] Create `static/chat-panel.js`. Top-of-file IIFE wrapper (`(function() { ... })();`) so we don't pollute `window`. Inside: read `window.SessionAgentChat` once, store in module-private `state.context`.
  - [x] Initialize on `DOMContentLoaded` (or immediately if document already loaded — handle both). Locate `.sa-input-field`, `.sa-message-transcript`, `.sa-status-text` via `document.querySelector`.
  - [x] Attach `keydown` to the input field — Enter (without Shift) → `event.preventDefault()` + `submitTurn()`; Shift+Enter → default newline; Esc → `// TODO Story 3.5+: cancel in-flight turn`.
  - [x] Auto-focus the input field on init + after every successful render.
  - [x] `submitTurn()`: read input value, clear input, append operator `<div class="sa-message-block sa-msg-operator">` with the question text, write "Thinking..." to status text, disable input, call `zenPage.SendChatMessage(...)` via Zen's synchronous-AJAX hyperevent proxy.
  - [x] On hyperevent return: `JSON.parse(envelope)`. If `error` field present → render error block (AC-4), clear status, re-enable input. Else render `toolCallsRendered[]` cards in order, then render the final `assistantMarkdown` block via the AC-3 fallback path. Clear status, re-enable input, refocus input.
  - [x] Helper functions: `renderToolCard(toolCall)`, `renderMarkdownFallback(markdown)`, `parseInlineCitations(text)`, `parseCodeBlocks(text)`, `appendMessageBlock(role, contentNode)`, `escapeText(text)` (the last is `node.textContent = text` — explicit helper for clarity).

- [x] **Task 2 — Author static-file validator (AC: #6)**
  - [x] Create `src/SessionAgent/Test/ChatPanelJsTest.cls` extending `%UnitTest.TestCase` (per `.claude/rules/object-script-testing.md` — `%OnNew(initvalue)` boilerplate).
  - [x] In `OnBeforeAllTests`, locate the file path: `..%session.GetWorkingDirectory()` is unreliable in unit tests; use `^||TestRoot` set by the runner OR resolve via `$ZSearch("static/chat-panel.js")` from the install root. Document the chosen approach in Completion Notes.
  - [x] Read the file via `%Stream.FileCharacter` into a `%String` (file is small, ~150 lines).
  - [x] Add tests: `TestKeydownListenerAttached`, `TestEnterShiftSplit`, `TestSendChatMessageCalled`, `TestJsonParseUsed`, `TestToolCallCardConstruction`, `TestCitationRegexPresent`, `TestNoInnerHtml`, `TestNoEval`, `TestNoCdnUrls`. Each is a 1–3-line substring or pattern assertion using `[ "..."` or `$Match(line, ".*pattern.*")`.

- [x] **Task 3 — Compile + per-class regression sweep (AC: #7)**
  - [x] `iris_doc_compile` for `ChatPanelJsTest`.
  - [x] Per-class `iris_execute_tests` for `ChatPanelJsTest` plus a sanity sweep — capture authoritative count via `%Dictionary.MethodDefinition` SQL probe per cr-3-1's pattern. Expect 131/131 total.

- [x] **Task 4 — Stale-reference grep (Rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly\|gpt-4o" src/SessionAgent/ static/` → expect 0.
  - [x] `grep -rn "innerHTML\|eval(\|Function(\|cdnjs\|jsdelivr\|unpkg\|googleapis" static/chat-panel.js` → expect 0 (the AC-6 invariants empirically confirmed at the file level too).

## Dev Notes

### Wire format (load-bearing)

The JS code parses `TurnResult.ToJson()` output. Field names MUST match the DTO exactly — capture from Task 0 probe. Anticipated shape:
```json
{
  "assistantMarkdown": "...",
  "usageRollup": {"input": N, "output": N},
  "durationMs": N,
  "toolCallsRendered": [
    {"id": "...", "toolName": "...", "status": "complete|error", "summary": "...", "input": {...}, "result": {...}}
  ],
  "error": {"kind": "provider_timeout|provider_error|tool_error|no_config", "message": "..."}  // optional
}
```

If Task 0 reveals different field names, **use the actual names — do not let the spec text override the code**.

### Why no headless browser test in this story

JS test infrastructure (jsdom, Playwright, Karma) is its own substantial setup with operator dependencies (Node.js install, npm install, CI runner config). Per Rule 8: this is "genuine future-epic scope." MVP test coverage = ObjectScript file-content validator (AC-6) + manual cross-browser smoke in Story 3.6. The static validator catches the load-bearing invariants (event handlers attached, no-innerHTML, no-eval, no-CDN, citation-chip regex present) without bringing up a JS toolchain.

### Render path is XSS-safe by construction

Per AC-3 the script never assigns to `.innerHTML` on untrusted data. Citation chips, code blocks, tool cards are all built via `document.createElement` + `setAttribute` + `textContent`. The `parseInlineCitations` function tokenizes the input string into text + chip segments via regex, then iterates: text segments → `document.createTextNode`, chip segments → `document.createElement('a')` + attributes. The result is appended via `appendChild` — no string-as-HTML ever crosses a DOM boundary.

### `zenPage.SendChatMessage` — Story 3.3 wires this

This story's JS calls `zenPage.SendChatMessage(...)`. The actual ZenMethod ships in Story 3.3 (`SessionAgent.EnsPortal.VisualTrace.SendChatMessage`). For testability, the JS should detect the absence of `zenPage` (e.g., when loaded outside a Zen page in Story 3.6's manual smoke) and surface a console warning rather than throw — but the AC-6 validator confirms the call site exists.

### File location

`static/chat-panel.js` (repo root + relative `static/`) — `module.xml`'s `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>` already wires the install path. Operator-served URL: `/csp/static/iris-session-agent/chat-panel.js`. Story 3.3 references this URL.

### Order of operations recommended

1. Task 0 probe (DTO field names — load-bearing).
2. Task 1 author the JS file (write end-to-end first; refactor for clarity in a second pass).
3. Task 2 ObjectScript test (run incrementally as each pattern lands).
4. Task 3 + 4.

### Sources

- [`epics.md`](../planning-artifacts/epics.md) §"Story 3.2" lines 1141–1176.
- [`architecture.md`](../planning-artifacts/architecture.md) §"Static asset development" line 1114; §"Vendored static-asset distribution" line 117; §"Project Directory Structure" lines 866 + 912 (chat-panel.js placement); §"ZenMethod hyperevents" line 572.
- [`ux-design-specification.md`](../planning-artifacts/ux-design-specification.md) UX-DR3 (tool-call cards), UX-DR14 (Markdown fallback), UX-DR16 (auto-focus), UX-DR18-MVP-subset (error envelopes), UX-DR19 (no inline event handlers), UX-DR30 (input handlers).
- Story 3.1's `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper` — provides the HTML shell + bootstrap context this JS consumes.
- Story 2.7's `Agent.TurnResult` DTO — the wire shape this JS parses.
- [`module.xml`](../../module.xml) — `<FileCopy Name="static/" ...>` wires install-time deployment.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — `%OnNew(initvalue)`, `$$$AssertX` macros, no `..AssertX(...)`.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 2, 3, 4, 8.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context) — bmad-dev-story workflow.

### Debug Log References

None.

### Completion Notes List

**Task 0 — DTO probe (load-bearing, contradicts spec text):**
- `SessionAgent.Agent.TurnResult.cls` ToJson() emits these JSON keys: `assistantMarkdown`, `usageRollup`, `durationMs`, `toolCallsRendered`. Confirmed verbatim against the source.
- Per-tool-call shape inside `toolCallsRendered[]` (built by `AgentLoop.cls` lines 302-316): `{name, args, result, status}`. Status values are `"ok"` or `"error"` (NOT `"running|complete|error"` as the spec anticipated). The DTO does NOT ship `id`, `toolName`, `summary`, or `input` fields — the spec text in Dev Notes was anticipatory and incorrect.
- **Implications applied to JS (per Rule 8 "fix now" + lead's "use reality" instruction):**
  - `data-tool-call-id` is synthesized as `"tc-" + dispatchIndex` (the JSON-array index of the card). Story 3.4's chip handler can lookup by this synthetic id.
  - The CSS modifier becomes `sa-tool-card-status-ok` or `sa-tool-card-status-error` (matching reality).
  - Tool input field reference is `card.args` (NOT `card.input`).
  - The summary text is synthesized: `"called " + card.name`.
  - All five field reads (`name`, `args`, `result`, `status`, plus the synthetic index) are correct against the actual DTO.

**Task 1 — JS file authored, 477 lines:**
- IIFE wrapper, module-private state, init on DOMContentLoaded with already-loaded fallback.
- Helper functions: `init`, `onKeyDown`, `submitTurn`, `handleEnvelope`, `handleEnvelopeError`, `finishTurn`, `renderErrorBlock`, `renderToolCard`, `renderMarkdownFallback`, `parseInlineCitations`, `appendTextWithInlineCode`, `appendMessageBlock`, `escapeText`, `stringifySafe`. (14 functions; spec listed 6 — extras handle internal concerns: hyperevent error path, finish-turn cleanup, mid-paragraph code-block placeholder substitution, JSON safe-stringify.)
- **Optional `window.SessionAgentChatTestHook` shim added** (per the lead's prompt note 4). When `zenPage.SendChatMessage` is unavailable (Story 3.6 manual smoke / non-Zen-page load), the JS checks for `window.SessionAgentChatTestHook` and calls it if installed; otherwise renders an error block. This lets a smoke harness (a single `<script>` block in a fixture page) inject a synthetic envelope without bringing up Zen. Documented in the JS file's source comments.

**Task 2 — Static-file validator authored:**
- `SessionAgent.Test.ChatPanelJsTest.cls` (251 lines, %UnitTest.TestCase subclass with proper `%OnNew(initvalue)`).
- File-locator strategy: tries `$System.CSP.GetFileName('/csp/static/iris-session-agent/chat-panel.js')` first (post-install path), then falls back to repo-source paths `c:\git\iris-session-agent\static\chat-panel.js` (Windows) and `/git/iris-session-agent/static/chat-panel.js` (Linux mirror). Chosen path captured in `..FilePath` and logged in every assertion message.
- 9 test methods, one per AC-6 bullet. Each uses `$$$AssertTrue(content [ "literal", "...")` substring assertions or `$$$AssertTrue('(content [ "..."), "...")` for the ZERO-occurrence checks.
- During implementation, discovered the original docstring banner contained literal substrings `.innerHTML =`, `eval(`, `new Function(` (as descriptive labels in the comment). Reworded to "inner-HTML assignment patterns" / "dynamic-code-execution patterns" so the AC-6 invariants count zero. (Rule 8: caught and fixed in current story.)

**Task 3 — Compile + tests:**
- `iris_doc_compile` for `SessionAgent.Test.ChatPanelJsTest.cls`: clean compile (qualifiers `cuk`, 0.002s).
- `iris_execute_tests` (class level) for ChatPanelJsTest: **9/9 passed**.
- Authoritative test count via `%Dictionary.MethodDefinition` SQL: `SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE Parent %STARTSWITH 'SessionAgent.Test.' AND Name %STARTSWITH 'Test'` returns **139** (baseline 130 + 9 new = 139). The spec said "131/131" but that math was wrong (it counted "+1 class" but the new class adds 9 tests). 139 is the correct authoritative count.
- Per-class regression sweep: ran all 20 SessionAgent.Test.* classes individually. One intermittent `<INVALID OREF>` in `AgentLoopTest:RunTurnWithMockProviderSingleTurn` — re-ran in isolation, passed. Pre-existing intermittent issue unrelated to Story 3.2 (touches no JS or new test class). All other classes 100% pass.

**Task 4 — Stale-reference grep:**
- `HSCUSTOMCODE | %SessionAgent_ReadOnly | gpt-4o` in `src/SessionAgent/` + `static/`: ZERO live-code matches. One historical doc-comment hit in `Security/ReadOnlyRole.cls:31` references the OLD assumed name in a "memory specified" sentence — pre-existing documentation of the corrected naming, not a stale reference.
- `innerHTML | eval( | Function( | cdnjs | jsdelivr | unpkg | googleapis` in `static/chat-panel.js`: only one match — the standalone word "innerHTML" inside a comment "no innerHTML" on line 318. The strict invariant `.innerHTML =` (assignment) has ZERO matches.

### File List

- `static/chat-panel.js` (NEW, 477 lines)
- `src/SessionAgent/Test/ChatPanelJsTest.cls` (NEW, 251 lines)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status flip ready-for-dev → in-progress → review)
- `_bmad-output/implementation-artifacts/3-2-client-side-chat-panel-js-mvp-render-submit.md` (Tasks/Subtasks checkboxes flipped to [x], Dev Agent Record + File List + Change Log filled in, Status flipped to review)

### Change Log

| Date | Change |
|---|---|
| 2026-05-03 | Story 3.2 implemented end-to-end. Authored `static/chat-panel.js` (477 lines, IIFE wrapper, AC-1 through AC-5 satisfied) and `src/SessionAgent/Test/ChatPanelJsTest.cls` (9 tests, AC-6 invariants enforced). Test suite expanded from 130 → 139 (authoritative SQL count). Dev Agent: claude-opus-4-7 (1M context). |
