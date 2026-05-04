# Chrome DevTools MCP Smoke Test — Inspection Agent Chat Panel

> **Authoritative MVP smoke runbook.** Story 3.6 (2026-05-03). Replaces the
> original Epic 3 cross-browser sweep with a Chrome-only automated runbook
> driven via the [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp)
> server. Firefox / Safari / Edge sweeps are deferred — see
> [`deferred-work.md`](../../_bmad-output/implementation-artifacts/deferred-work.md)
> entry "Deferred from: Story 3.6 (cross-browser scope reduction)".

This runbook is **executed by the project lead at story-commit time** AND
re-run as part of every Epic 3+ epic-end empirical battery (per discipline
[Rule 6](../../.claude/rules/epic-cycle-discipline.md) and
[Rule 11](../../.claude/rules/epic-cycle-discipline.md)). Each step
specifies the exact `mcp__chrome-devtools-mcp__*` tool name + arguments,
expected output, pass criterion, and (where applicable) skip condition.

The runbook is paired with the static-file validator
`SessionAgent.Test.ChatPanelJsTest`, which guards the JS-side XSS / CDN /
inner-HTML invariants in code review. The two layers together provide
defense-in-depth: the validator catches static drift; this runbook catches
integration regressions that pass code review.

---

## Operator prerequisites

Verified at Epic 3 sprint planning. Runbook will fail without all of these
in place — verify before executing.

1. **IRIS running on `localhost:52773`.** The runbook's URLs assume the
   default Web Gateway port. Adjust if your install uses a different port.
2. **`Config.Agent.session-inspection.Enabled = 1`.** Verify from a
   `HSCUSTOM` shell:
   ```
   Write ##class(SessionAgent.Config.Agent).%OpenId("session-inspection").Enabled
   ```
   Expected: `1`. If `0` or the row does not exist, the chat panel renders
   the config-empty prompt instead of the live transcript and the runbook
   cannot proceed.
3. **`Ens.Config.Credentials` row `SessionAgentOpenAI` exists** with a
   valid OpenAI API key. Verify from a `HSCUSTOM` shell:
   ```
   Write ##class(Ens.Config.Credentials).%ExistsId("SessionAgentOpenAI")
   ```
   Expected: `1`.
4. **`Security.SSLConfigs` row `DefaultSSL` exists** in `%SYS`. See
   [`README.md`](../../README.md) §"7. SSL/TLS configuration for outbound
   HTTPS to the LLM provider".
5. **Operator account has `%All` role** for the duration of the smoke (so
   the EnsPortal subclass loads without RBAC redirects). Production
   operators only need `%EnsRole_Administrator` + `SessionAgent_ReadOnly`,
   but the runbook does not differentiate.
6. **`chrome-devtools-mcp` server reachable** from the Claude Code
   harness. Verify by listing pages: `mcp__chrome-devtools-mcp__list_pages`
   returns at least one page (or an empty list — both indicate the server
   is reachable).

---

## URL templates

Both the HealthShare-style URL (used on the current dev install) and the
plain-IRIS URL (used by operators with non-HealthShare deployments) target
the same `SessionAgent.EnsPortal.VisualTrace.zen` page:

- **Plain IRIS / HSCUSTOM (the canonical URL on this dev install):**
  `http://localhost:52773/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=1`
- **HealthShare-namespace deployment** (only if a `/csp/healthshare/<ns>/` web app
  is registered for HSCUSTOM — most IRIS-for-Health installs do NOT register
  one for HSCUSTOM and use `/csp/hscustom/` instead):
  `http://localhost:52773/csp/healthshare/<ns>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=1`

Verify the correct prefix on your install via `iris_webapp_list` (look for the
HSCUSTOM entry; on a stock IRIS-for-Health 2025.1 it appears as `/csp/hscustom`,
not `/csp/healthshare/HSCUSTOM`). The Story 3.6 lead-driven smoke (2026-05-03)
discovered the original `/csp/healthshare/HSCUSTOM/...` prescription was wrong
on this install — corrected here.

Substitute `SESSIONID=1` with any known-existing Ens session id on the
target install. Session 1 is the default expectation (the lowest-numbered
session usually exists on any non-empty install). If session 1 has been
purged, pick any session visible in
`SELECT TOP 1 ID FROM Ens.MessageHeader ORDER BY ID`.

---

## The 10 steps

Each step is a verbatim `chrome-devtools-mcp` tool call followed by the
pass criterion. Execute in order; do not reorder.

### Step 1 — Navigate to a known Ens session

**Tool:** `mcp__chrome-devtools-mcp__navigate_page`

**Args:**
```json
{
  "url": "http://localhost:52773/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=1"
}
```

**Expected output:** Page loads with HTTP 200. The browser title contains
"Visual Trace". The Web Gateway login prompt appears once per session — if
prompted, supply the operator's IRIS credentials and re-run this step.

**Pass criterion:** No HTTP error in the page load. The navigation
completes within the Web Gateway timeout (300s — see
[`README.md`](../../README.md) §"3. Web Gateway timeout").

### Step 2 — Capture initial DOM

**Tool:** `mcp__chrome-devtools-mcp__take_snapshot`

**Args:** *(none)*

**Expected output:** A snapshot containing the parent EnsPortal Visual
Trace surface — at minimum a `<svg>` element (the trace diagram) and the
parent's tab strip (Header / Body / Trace / etc.). The snapshot includes
uid references for every element which subsequent click steps use.

**Pass criterion:**
- Snapshot includes a `<svg>` element.
- Snapshot includes at least one `<a>` or tab-like element matching the
  parent's tab strip.
- The "Ask the agent" tab is present (text node "Ask the agent" or
  similar — exact label is set by the Story 3.3 subclass).

### Step 3 — Click the "Ask the agent" tab

**Tool:** `mcp__chrome-devtools-mcp__click`

**Args:** `{ "uid": "<uid of the 'Ask the agent' tab from step 2 snapshot>" }`

**Expected output:** Tab activates; the chat panel becomes visible. No
console errors. No network errors.

**Pass criterion:** The click resolves without error. The active tab
visually changes (tab CSS state flips).

### Step 4 — Verify the chat panel renders with correct DOM + ARIA

**Tool:** `mcp__chrome-devtools-mcp__take_snapshot`

**Args:** *(none)*

**Expected output:** A second snapshot that now includes the chat panel
shell. Confirm the following selectors and attributes — every one of them
is emitted by `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper.cls` (see
"Implementation references" below for line citations):

| Selector / attribute | Required value | Source |
|---|---|---|
| `section.sa-chat-panel` | present | `ChatPanelDrawHelper.cls:170,179` |
| `aria-label="Agent chat panel"` on `.sa-chat-panel` | present | `ChatPanelDrawHelper.cls:170,179` |
| `role="region"` on `.sa-chat-panel` | present | `ChatPanelDrawHelper.cls:170,179` |
| `div.sa-message-transcript` | present | `ChatPanelDrawHelper.cls:171,180` |
| `div.sa-status-text` | present | `ChatPanelDrawHelper.cls:172,181` |
| `aria-live="polite"` on `.sa-status-text` | present | `ChatPanelDrawHelper.cls:172,181` |
| `form.sa-input-area` | present | `ChatPanelDrawHelper.cls:173,182` |
| `textarea.sa-input-field` | present | `ChatPanelDrawHelper.cls:174,183` |
| `aria-label="Ask anything about this session"` on `.sa-input-field` | present | `ChatPanelDrawHelper.cls:174,183` |

The transcript should already contain either:
- A welcome `div.sa-message-block.sa-msg-agent` (first-time operator on
  this session), OR
- One or more `div.sa-message-block` entries (returning operator —
  prior conversation surfacing per Story 3.3 AC-3).

**Pass criterion:** All 9 rows above match. If any are missing the
underlying production code has drifted from the runbook — update both per
[discipline rule 8](../../.claude/rules/epic-cycle-discipline.md) (fix-now
is the default).

### Step 5 — Fill the input

**Tool:** `mcp__chrome-devtools-mcp__fill`

**Args:**
```json
{
  "uid": "<uid of textarea.sa-input-field from step 4 snapshot>",
  "value": "What happened in this session? Be brief."
}
```

**Expected output:** The textarea now contains the prompt text. No console
errors.

**Pass criterion:** A subsequent `take_snapshot` confirms the textarea's
value reflects the entered text. The status text remains empty.

> **Why this prompt:** the prompt is intentionally tame to keep token cost
> low and to maximize the chance the agent invokes 1–3 tools (so step 7
> has at least one tool card to assert against). Avoid exotic phrasing
> that would push the LLM into low-confidence mode.

### Step 6 — Press Enter to submit

**Tool:** `mcp__chrome-devtools-mcp__press_key`

**Args:**
```json
{
  "uid": "<uid of textarea.sa-input-field>",
  "key": "Enter"
}
```

**Expected output:**
- The operator's question echoes immediately as a
  `div.sa-message-block.sa-msg-operator` in the transcript
  (`chat-panel.js:314-317`).
- The status text changes to `"Thinking..."` (`chat-panel.js:321`).
- The input is cleared and disabled (`chat-panel.js:320,322`).
- A network request fires to the Zen hyperevent endpoint (typically
  `/csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen` with
  `?Action=run` or similar — verify via
  `mcp__chrome-devtools-mcp__list_network_requests`).

**Pass criterion:** Status text reads `"Thinking..."`; the operator turn
is rendered; one outbound POST request is in flight.

### Step 7 — Wait for the agent's response and verify tool cards rendered

**Tool A — wait:** `mcp__chrome-devtools-mcp__wait_for`

**Args:**
```json
{
  "text": "session"
}
```

The wait succeeds when any text matching "session" appears in the page
DOM — typically inside the agent's answer or one of the tool-card result
blocks. Default timeout is fine; the AgentLoop honors a 90s per-call cap
plus the iteration cap (architecture.md max_iter=10), so a reasonable
upper bound is ~3 minutes for a tame prompt.

**Tool B — capture:** `mcp__chrome-devtools-mcp__take_snapshot`

**Args:** *(none)*

**Expected output:** A third snapshot. Verify:
- Status text is empty again (`chat-panel.js:407`); input is re-enabled
  (`chat-panel.js:408`).
- At least one
  `<details class="sa-tool-call-card sa-tool-card-status-complete">` is
  present in the transcript (`chat-panel.js:484` — the DTO `status="ok"`
  maps to the `complete` CSS modifier).
- An `<details class="sa-tool-call-card sa-tool-card-status-error">` may
  also be present if the agent hit a tool error mid-turn — both shapes
  pass.
- A final `div.sa-message-block.sa-msg-agent` containing the assistant's
  answer text.

**Pass criterion:** ≥ 1 tool-call card in the transcript; final agent
message present; status text cleared; input re-enabled.

> **Skip condition:** If the agent answers the prompt without invoking
> any tools (it has the answer in its training data — unlikely for a
> session-specific question but possible), step 7's tool-card assertion
> downgrades to "0 tool cards is acceptable IF a final
> `div.sa-message-block.sa-msg-agent` is present". Document the actual
> tool-call count in the lead's commit-time evidence.

### Step 8 — Click a tool-call card and verify it expands

**Tool:** `mcp__chrome-devtools-mcp__click`

**Args:** `{ "uid": "<uid of the first tool card's <summary> from step 7 snapshot>" }`

**Expected output:** The native `<details>` element opens — its `open`
attribute is now present. The `args` and `result` `<pre><code>` blocks
become visible.

**Pass criterion:** A subsequent `take_snapshot` confirms the
`<details>` element has `open` attribute set. The args + result blocks
are visible in the snapshot.

### Step 9 — (Optional) click a citation chip and verify parent-tab integration

**Tool:** `mcp__chrome-devtools-mcp__click`

**Args:** `{ "uid": "<uid of the first .sa-citation-chip from step 7 snapshot>" }`

**Expected output (when chips are present):** The parent EnsPortal Visual
Trace surface receives the click — the click dispatches to
`zenPage.onCitationClick(type, id, klass)` (`chat-panel.js:276`), which
delegates to the parent's `selectItem`/`updateTabs` per Story 3.4. The
parent's Header tab updates to show the cited row.

**Pass criterion (when chips present):** The click resolves without
console error. The parent surface visibly updates. A subsequent
`list_console_messages` shows no errors.

> **Skip condition:** Citation chips are emitted only when the agent's
> answer text contains a citation pattern matching `CITE_RE`
> (`chat-panel.js:45`) — e.g., `[message:42]`, `[rule_log:7]`,
> `[event_log:3]`, `[ack:5]`, `[iolog:2]`, `[tool:list_sessions]`. The
> tame prompt in step 5 may yield no chips. **If no
> `.sa-citation-chip` elements are present in the step 7 snapshot, this
> step is INFORMATIONAL** — log "no chips emitted" in the lead's
> commit-time evidence and proceed to step 10. Do not fail the runbook
> for absence of chips.

### Step 10 — Lighthouse accessibility audit

**Tool:** `mcp__chrome-devtools-mcp__lighthouse_audit`

**Args:**
```json
{
  "category": "accessibility"
}
```

**Expected output:** Lighthouse runs against the current page state. The
accessibility category score is returned along with per-audit detail.

**Pass criterion:** Accessibility score ≥ **0.9** (90%) per UX-DR22
best-effort inherited posture. The Mgmt Portal Zen wrapper is the
dominant contributor to the score — the chat panel inherits its tab
chrome, focus management, and color contrast. The runbook is not
asserting WCAG 2.1 AA compliance for the entire Mgmt Portal; only that
the chat-panel additions do not regress the parent's score.

> **Diagnostic mode:** If the score is between 0.85 and 0.9, the lead
> can capture per-audit details via
> `mcp__chrome-devtools-mcp__performance_analyze_insight` and decide
> whether the regression is chat-panel-induced or pre-existing in the
> parent shell. A pre-existing parent-shell regression is logged but
> does not block the story.

---

## Implementation references

Cross-references between runbook assertions and the production code
emitting them, captured in Story 3.6 Task 4 dry-run (2026-05-03):

| Runbook step | Production source (line range) | Selector / attribute / behavior |
|---|---|---|
| 4 (panel shell) | `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls:170-187` (stream path) and `:179-186` (`&html` path) | `<section role="region" aria-label="Agent chat panel" class="sa-chat-panel">` plus the four child elements |
| 4 (transcript element) | `ChatPanelDrawHelper.cls:171,180` | `<div class="sa-message-transcript">` |
| 4 (status text + aria-live) | `ChatPanelDrawHelper.cls:172,181` | `<div class="sa-status-text" aria-live="polite">` |
| 4 (input form + textarea) | `ChatPanelDrawHelper.cls:173-174,182-183` | `<form class="sa-input-area">` containing `<textarea class="sa-input-field" aria-label="Ask anything about this session">` |
| 5 (input fill) | `static/chat-panel.js:126,176-177` | `state.inputEl = document.querySelector('.sa-input-field')`; auto-focused on init |
| 6 (Enter submit) | `static/chat-panel.js:138-139,235-249` | `keydown` handler; Enter (not Shift+Enter) calls `submitTurn()` |
| 6 (operator turn echo) | `static/chat-panel.js:314-317` | `<div class="sa-message-block sa-msg-operator">` |
| 6 ("Thinking..." status) | `static/chat-panel.js:321` | `state.statusEl.textContent = 'Thinking...'` |
| 6 (input cleared + disabled) | `static/chat-panel.js:320,322` | `state.inputEl.value = ''; state.inputEl.disabled = true` |
| 7 (tool card status modifier) | `static/chat-panel.js:481-484` | `statusVal === 'error' ? 'error' : 'complete'` → `class="sa-tool-call-card sa-tool-card-status-{complete|error}"` |
| 7 (tool card structure) | `static/chat-panel.js:483-541` | `<details>` with `<summary>` + status indicator + name + args/result `<pre><code>` blocks |
| 7 (status cleared, input re-enabled) | `static/chat-panel.js:405-412` | `finishTurn()` resets `statusEl`, re-enables `inputEl`, refocuses |
| 7 (final agent message) | `static/chat-panel.js:391-394` | `<div class="sa-message-block sa-msg-agent">` rendered via `renderMarkdownFallback` |
| 8 (tool card expand) | `static/chat-panel.js:483` | Native `<details>` element — clicking `<summary>` toggles `open` attr |
| 9 (citation chip) | `static/chat-panel.js:642-665` | `<a class="sa-citation-chip {modifier}">` with `data-cite-type`, `data-cite-id`, optional `data-cite-klass`, `aria-label` |
| 9 (chip click delegation) | `static/chat-panel.js:152,261-298` | Single delegated `click` listener on `.sa-message-transcript` calls `zenPage.onCitationClick(type, id, klass)` |
| 10 (Lighthouse / a11y posture) | `ChatPanelDrawHelper.cls:170,179` (`role="region"`, `aria-label`); `:172,181` (`aria-live="polite"`); `:174,183` (`aria-label` on input) | All ARIA attributes the audit grades the panel against |

The static-file validator
(`src/SessionAgent/Test/ChatPanelJsTest.cls`) provides the static-time
guard for these same selectors / attributes — the runbook is the
runtime-time guard. Both layers are required.

---

## Why Chrome only for MVP

The original Epic 3 spec called for sweeps across "the latest two versions
of Chrome, Firefox, Safari, and Edge" plus screen-reader and WCAG
contrast checks. Per project-lead direction 2026-05-03, MVP scope is
reduced to Chrome via `chrome-devtools-mcp` because:

- `chrome-devtools-mcp` gives programmatic access to DOM / network /
  Lighthouse / click flows directly from inside Claude Code — no
  Selenium / Playwright / CI bring-up cost.
- Mgmt Portal Zen + standards-compliant DOM + ARIA gives reasonable
  confidence that Firefox / Safari / Edge will behave equivalently. The
  failure modes that matter (XSS, accessibility regressions, broken
  citation-chip clicks) are detectable in Chrome.
- Manual cross-browser sweeps consume operator time at every release cut
  — out of scope for a hobby-project release model.
- Future cross-browser hardening is a discrete future-epic concern. See
  the deferral entry in
  [`deferred-work.md`](../../_bmad-output/implementation-artifacts/deferred-work.md).

---

## Lead-driven execution model

Per [discipline rule 6](../../.claude/rules/epic-cycle-discipline.md)
(epic-end empirical battery transcript precondition for retro), the lead
drives this runbook execution:

1. At Story 3.6 commit time — the runbook's first execution. Pass
   evidence (snapshot uids, Lighthouse score, tool cards rendered,
   citation-chip behavior if exercised) is captured in Story 3.6's
   Completion Notes and the commit message.
2. As part of every Epic 3+ epic-end empirical battery (rule 6 step 4 —
   "live integration test"). The runbook is the standing live integration
   surface for the Inspection Agent UI; future epics that touch the UI
   (5, 6, 10) re-run the runbook unchanged unless their stories
   explicitly extend it.

The dev agent who authors / updates the runbook does **not** drive
execution — that is the lead's responsibility. Per AC-5 of Story 3.6,
all 10 steps must pass empirically at commit time.
