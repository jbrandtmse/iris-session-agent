# Walkthrough Bug Report — 2026-05-08

Bugs found during user-led walkthrough. Do NOT fix until batched into a story.

---

## BUG-01 — Chat panel horizontal scrollbar instead of word wrap

**Screen:** VisualTrace (`SessionAgent.EnsPortal.VisualTrace.zen`) — "Ask the agent" tab (5th tab in detail-pane strip)

**Severity:** MEDIUM

**Description:**
The chat panel content area renders with a horizontal scrollbar at the bottom rather than wrapping long lines to the available panel width. Visible in both the tool-result JSON block and the agent prose response. The panel is constrained to a fixed width inside the Zen tab, but `overflow-x` is allowed to scroll instead of being clipped/wrapped.

**Reproduction:**
1. Open VisualTrace for any session.
2. Click "Ask the agent" tab (5th tab).
3. Ask the agent anything — observe the response renders with a horizontal scrollbar rather than wrapping text to panel width.

**Expected:** Text (both prose and JSON) wraps within the available panel width; no horizontal scrollbar.

**Actual:** Horizontal scrollbar appears; content overflows the panel horizontally.

**Root cause (confirmed):**
Two interacting rules in `src/SessionAgent/UI/ChatPanel.cls` `EmitStyle`:

1. **Line ~330:** `#detailsTabGroup #askAgentTab .sa-chat-panel { min-width: 480px; min-height: 400px; }` — Story 10.13 added this to fix the MessageViewer narrow-pane sizing. When the parent tab cell is narrower than 480px (e.g. VisualTrace right panel), the flex container is forced wider than its parent, and the browser defaults to `overflow-x: auto`, producing the scrollbar.

2. **Line ~189:** `.sa-message-transcript { flex: 1 1 auto; overflow-y: auto; }` — has no `overflow-x` constraint, so horizontal overflow is allowed.

Message content elements (`.sa-message-block`) also have no `word-wrap: break-word` / `overflow-wrap: break-word`, so long lines in JSON tool cards don't soft-wrap.

**Fix:** Add `overflow-x: hidden` to `.sa-message-transcript` and `overflow-wrap: break-word` to message content elements in `ChatPanel.cls` `EmitStyle`. May also need to guard the `min-width: 480px` rule to MessageViewer only (it is already scoped to `#detailsTabGroup #askAgentTab` — check if VisualTrace uses the same IDs).

---

## BUG-02 — "OpenAI mid-flight failure" swallows the underlying HTTP exception — user cannot diagnose why

**Screen:** VisualTrace or MessageViewer — "Ask the agent" tab, any session

**Severity:** MEDIUM

**Description:**
When an HTTP-layer exception occurs while posting to OpenAI (SSL error, timeout, network drop, bad credentials, etc.), the provider catches the exception and emits the generic message "OpenAI mid-flight failure (request may have been processed)" to the chat panel. The actual exception text (`postEx`) is **silently discarded** — it is never included in the error envelope, never written to the Ensemble event log, and never visible to the user or operator. This makes it impossible to diagnose the real cause without attaching a debugger or enabling network traces.

**Reproduction:**
Observed during walkthrough on Session 70843 after the `get_business_process_source` tool call completed and the agent attempted to submit the tool result to OpenAI for the next inference turn.

**Expected:** The error envelope should include the underlying exception message (e.g., "SSL handshake failed", "Connection refused", "Timeout after 90s", "%Net.HttpRequest Post failed: …"). At minimum the exception should be written to `$$$LOGERROR` / `Ens.Util.Log` so an operator can trace it in the Event Log.

**Actual:** User sees only "OpenAI mid-flight failure (request may have been processed)" — no further diagnostic information.

**Root cause (confirmed):**
`src/SessionAgent/LLM/OpenAIProvider.cls` — `IssueHttpsPost` method:

```objectscript
} Catch postEx {
    Set tHttpFailed = 1      ; ← exception object postEx is silently discarded here
}

If tHttpFailed {
    Set tMidFlight = 1
    Quit                     ; ← exits without logging or including postEx.DisplayString()
}
```

The `PopulateErrorEnvelope` call receives only the hardcoded string; `postEx.DisplayString()` is never passed in. The same pattern exists in `AnthropicProvider.cls`, `GeminiProvider.cls`, and `OpenAICompatProvider.cls` — all four providers share the same catch-and-discard shape.

**Fix:** In the `Catch postEx` block, capture `postEx.DisplayString()` and append it to the `PopulateErrorEnvelope` message string, AND write it to `$$$LOGERROR`. All four provider files need the same change.

---

## BUG-03 — `get_business_process_source` returns "class not found" when LLM appends a method name to the class name — `get_business_process_source` returns "class not found" when LLM appends a method name to the class name

**Screen:** VisualTrace / MessageViewer — "Ask the agent" tab, tool call result panel

**Severity:** MEDIUM

**Description:**
The LLM called `get_business_process_source` with `bp_class_name: "SessionAgent.Sample.BP.OrderRouter.OnRequest"` — passing the method name `OnRequest` appended to the real class name `SessionAgent.Sample.BP.OrderRouter`. The tool does a single `%Dictionary.ClassDefinition.%OpenId` lookup on the exact string, finds nothing, and returns `render_strategy: "class_not_found"` with no fallback. The LLM receives a useless result and cannot continue introspecting the BP.

This is a prompt-engineering + tool-robustness dual failure: the tool description doesn't warn against method-name suffixes, and the tool has zero recovery logic.

**Reproduction:**
1. Open any session on VisualTrace.
2. Ask the agent to "show me the source of the OrderRouter business process".
3. Observe agent calls the tool with class+method combined string.
4. Tool returns `class_not_found`.

**Expected:** Tool either (a) strips the last dot-segment and retries the lookup, finding `SessionAgent.Sample.BP.OrderRouter` successfully, or (b) returns a helpful error that includes the candidate stripped class name so the LLM can self-correct.

**Actual:** Tool returns `class_not_found` immediately with no diagnostic hint, leaving the LLM stuck.

**Root cause (confirmed):**
`src/SessionAgent/Tool/Inspection/` — `get_business_process_source` tool class, lookup block:

```objectscript
Set tCls = ##class(%Dictionary.ClassDefinition).%OpenId(tClassName)
; ...
If '$IsObject(tCls) {
    Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
    Quit   ; ← no fallback: does not strip last segment and retry
}
```

The `bp_class_name` argument description provides examples (`SessionAgent.Sample.BP.OrderRouter`) but does not explicitly warn "do not append method names". The LLM infers from context that `OnRequest` might be a sub-class (a reasonable but wrong inference for an IRIS BP).

**Fix (two-part):**
1. **Tool robustness** — after a `class_not_found` miss, check if the name contains a dot; if so, strip the last segment and retry once. If the retry succeeds, use the result and add a note in the response that the class name was auto-corrected. If it still misses, return `class_not_found` with a `"candidate_class_name"` field showing the stripped name.
2. **Argument description** — append to the `bp_class_name` description: `"Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."` Same fix should be applied to any sibling tools that accept class names (`get_business_operation_source`, etc.).

---

## BUG-04 — Session ID link in MessageViewer table navigates to standard `EnsPortal.VisualTrace` (no "Ask the agent" tab) instead of custom `SessionAgent.EnsPortal.VisualTrace`

**Screen:** MessageViewer (`SessionAgent.EnsPortal.MessageViewer.zen`) — session ID hyperlinks in the results table

**Severity:** HIGH

**Description:**
Clicking any session ID link in the MessageViewer results table (the green session badges in the "Session" column) navigates to the standard Ensemble VisualTrace page (`EnsPortal.VisualTrace.zen`) instead of the custom `SessionAgent.EnsPortal.VisualTrace.zen`. The standard page has only 3 tabs (Header / Body / Contents) — the "Ask the agent" tab is absent.

**Reproduction:**
1. Open `SessionAgent.EnsPortal.MessageViewer.zen`.
2. Click any session ID badge in the results table (e.g. row 6, session 69659).
3. Observe navigation goes to VisualTrace with only Header / Body / Contents tabs — no "Ask the agent" tab.

**Expected:** Navigation goes to `SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>`, showing the full 4-tab strip including "Ask the agent".

**Actual:** Navigation goes to the standard `EnsPortal.VisualTrace.zen?SESSIONID=<id>`.

**Root cause (confirmed):**
`irislib/EnsPortal/MessageViewer.cls` — `showTrace` ClientMethod, line 185:

```javascript
ClientMethod showTrace(sessionId, evt) [ Language = javascript ]
{
    var URI = zenLink('EnsPortal.VisualTrace.zen?SESSIONID='+sessionId);
    ...
}
```

`SessionAgent.EnsPortal.MessageViewer` inherits this method from the parent and does NOT override it. The URL is therefore always `EnsPortal.VisualTrace.zen`.

**Fix:** Override `showTrace` in `SessionAgent.EnsPortal.MessageViewer` to substitute `SessionAgent.EnsPortal.VisualTrace.zen`:

```javascript
ClientMethod showTrace(sessionId, evt) [ Language = javascript ]
{
    var URI = zenLink('SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID='+sessionId);
    window.location = URI;
}
```

Also check and override the right-click context menu entries (lines ~160 and ~173 in the parent) which also call `showTrace` — those should be covered by the same override.

---

## BUG-05 — Search Agent results populate only the chat panel; they do not drive the MessageViewer table or left-panel filters

**Screen:** MessageViewer (`SessionAgent.EnsPortal.MessageViewer.zen`) — "Ask the agent" tab

**Severity:** HIGH

**Description:**
When the Search Agent returns results (e.g., "I found 20 sessions with error status"), the sessions are rendered as chat tiles in the right-panel chat transcript. The left-panel filter form is not updated, the results table is not updated, and the operator must manually configure the filters to see the same sessions in the table. For large result sets (20+ sessions) the chat tile list becomes very long and difficult to navigate — the table is the appropriate display surface for tabular result sets.

**Reproduction:**
1. Open `SessionAgent.EnsPortal.MessageViewer.zen`.
2. In the "Ask the agent" tab, type "find sessions with errors in the last hour".
3. Observe: agent returns 20 session tiles in the chat panel.
4. Left panel filter fields are unchanged. Results table is unchanged.

**Expected:** Agent search results update the results table to show the matching sessions, and/or populate the left-panel filter criteria so the operator can see, paginate, sort, and interact with the results in the table UI.

**Actual:** Results are rendered exclusively as chat tiles in the right panel. No table or filter update occurs.

**Root cause (confirmed):**
Two-level gap:

1. **`static/chat-panel.js` `onSearchResultClick`** (line ~1753) — the click handler on each result card immediately navigates to VisualTrace (`window.location.href = destinationUrl`). There is no mechanism to send the result session list back to the parent MessageViewer.

2. **`src/SessionAgent/EnsPortal/MessageViewer.cls`** — has no ZenMethod or client-side API to accept a list of session IDs and drive the table. The table is populated via a SQL `CreateResultSet` path in `irislib/EnsPortal/Template/filteredViewer.cls` that is entirely filter-criteria-driven, not session-list-driven.

**Fix options (pick one; each has different scope):**

- **Option A (pragmatic):** Add a "Load into table" button to each agent result set in the chat transcript. When clicked, it calls a new `ApplyAgentSessionFilter(sessionIds)` ZenMethod that adds a `WHERE ID IN (...)` clause override to `CreateResultSet` and re-runs the query. The left panel shows a "Filtered by agent search" badge. Clicking "Reset" clears back to normal filter mode.

- **Option B (deeper):** After each agent search response, extract the filter criteria the agent used (date range, status, source) and programmatically populate the left-panel form fields and call `doSearch()`. Harder to implement because agent results don't currently return structured filter parameters — requires agent loop changes.

Option A is recommended: smallest blast radius, preserves the existing filter architecture, and directly addresses the UX pain point.

---

## BUG-06 — "Max iterations reached. Please summarize." is a hard-coded ceiling with no operator override and an unhelpful message

**Screen:** VisualTrace / MessageViewer — "Ask the agent" tab

**Severity:** MEDIUM

**Description:**
The Inspection Agent emitted "Max iterations reached. Please summarize." as the final assistant turn on Session 49528, terminating the conversation mid-investigation. The 10-iteration ceiling is a hard-coded class parameter (`SessionAgent.Agent.AgentLoop` `MaxIterationsPerTurn = 10`) with no per-agent override and no operator-facing configuration in the AgentConfig Zen form. The error message itself ("Please summarize") is a directive without context — it doesn't explain what happened, doesn't preserve any partial findings, and doesn't suggest a recovery path the operator can take.

For complex investigations (e.g., a session with many messages where the agent legitimately needs to inspect multiple bodies and BPL rules), 10 iterations may be insufficient. Operators have no way to raise the limit without recompiling.

**Reproduction:**
1. Open a session with many messages (12+ items in the visual trace) on VisualTrace.
2. Ask a broad question that requires multiple tool calls (e.g., "explain everything that happened in this session").
3. Observe the agent issues 10 tool calls and then emits "Max iterations reached. Please summarize."

**Expected:**
- Limit should be configurable per-agent via `Config.Agent.MaxIterationsPerTurn` (with a sensible default like 10).
- The Zen form (`SessionAgent.UI.AgentConfig`) should expose this as an operator field with reasonable bounds (e.g., 5–50).
- The "max iterations" message should be more informative — e.g., explain the tools called so far, summarize what was found, and suggest the operator ask a more focused follow-up question.

**Actual:**
- Limit is hard-coded in `AgentLoop.cls` line 85 (`Parameter MaxIterationsPerTurn As INTEGER = 10;`).
- Message is exactly "Max iterations reached. Please summarize." — no context, no partial summary, no follow-up guidance.
- Operator has to recompile to change the limit.

**Root cause (confirmed):**
`src/SessionAgent/Agent/AgentLoop.cls`:

- **Line 85:** `Parameter MaxIterationsPerTurn As INTEGER = 10;` — class parameter, not a `Property` or read from `Config.Agent`.
- **Line 543:** `Set tFinalAssistantText = "Max iterations reached. Please summarize."` — hardcoded string, no fallback to a richer summary.

`src/SessionAgent/Config/Agent.cls` — has no `MaxIterationsPerTurn` property; the AgentConfig Zen form has no field for it.

**Fix (two-part):**
1. **Configurability** — add a `MaxIterationsPerTurn As %Integer (InitialExpression = 10, MINVAL = 1, MAXVAL = 100)` property to `Config.Agent`, expose it in the AgentConfig Zen form (alongside MaxTokens / Temperature), and have AgentLoop read `..ConfigAgent.MaxIterationsPerTurn` instead of the class parameter (with `$Char(0)` normalization per the project rule).
2. **Better fallback message** — when the cap is hit, generate a synthetic summary turn that lists the tools called and a one-line per-tool result, then ends with: "I've used my full investigation budget for this turn — please ask a more focused follow-up question (e.g., about a specific message or BP) to continue." This gives the operator actionable next steps instead of a directive they can't act on.

---

## BUG-07 — Search result tiles disappear on page reload (Back-button return) — flattener strips tool_use / tool_result blocks from prior transcript

**Screen:** MessageViewer / VisualTrace — "Ask the agent" tab, after returning to the page (Back button, refresh, new tab navigating back, etc.)

**Severity:** HIGH

**Description:**
The Search Agent renders 20 clickable session tiles in the chat panel. Operator clicks one tile → navigates to VisualTrace → hits Back to return to MessageViewer. The chat panel reloads and now shows only the agent's text response ("I found 20 sessions with error status…") — the 20 result tiles are gone. The operator must re-run the search to get the tiles back.

This makes the click-through workflow effectively single-shot: any nav-back loses the result set, forcing a re-search and a new round-trip cost to the LLM.

**Reproduction:**
1. Open MessageViewer.
2. Run a search that returns multiple session tiles (e.g., "find sessions with errors").
3. Click any tile → arrives at VisualTrace.
4. Click browser Back → returns to MessageViewer.
5. Observe: chat shows the agent's text answer; the 20 result tiles are missing.

**Expected:** Returning to the page replays the full prior transcript including tool result tiles — tiles remain clickable, click-through state is preserved, re-search is unnecessary.

**Actual:** Only text turns are replayed. Tool result tiles are dropped.

**Root cause (confirmed):**
The chat history persistence layer DOES save tool_use / tool_result blocks (`SessionAgent.Chat.History.TurnsJson` is the full canonical-Anthropic shape). The page reload path explicitly strips them.

`src/SessionAgent/EnsPortal/MessageViewer.cls` `FlattenTurnsForBootstrap` (lines 311–368) — and the verbatim copy in `SessionAgent/EnsPortal/VisualTrace.cls`:

```objectscript
While tBlockIter.%GetNext(.tBidx, .tBlock) {
    If '$IsObject(tBlock) Continue
    If tBlock.%Get("type") '= "text" Continue   ; ← drops every tool_use / tool_result block
    Set tText = tText _ tBlock.%Get("text")
}

If tText = "" Continue                          ; ← drops the entire turn if it has no text
```

The doc-comment (line ~303–306) explicitly notes this was MVP-scoped: *"Anthropic 'user' turns with only type:'tool_result' blocks → SKIPPED. Anthropic 'assistant' turns with only type:'tool_use' blocks (no text) → SKIPPED."*

The flattened array is passed to `chat-panel.js` `renderPriorTranscript` (lines 582–608), which only handles `{role, content}` text shape — it has no code path to render tool result tiles from prior history.

By contrast, fresh tool-call responses go through `handleEnvelope` → `renderSearchResultList` (lines 985, 1496+) which DOES render the tiles. So the rendering function exists; it's just never called for replayed history.

**Fix (two-part):**
1. **Server-side flattener** — extend `FlattenTurnsForBootstrap` to preserve tool_use / tool_result blocks in the bootstrap shape. Each replayed turn would carry an additional field like `toolCalls: [...]` containing the structured search results, alongside the existing `content` text.
2. **Client-side replay** — extend `renderPriorTranscript` in `chat-panel.js` to call `renderSearchResultList` (and any sibling tile renderers) when a replayed agent turn carries `toolCalls` data.

Both flatteners (`MessageViewer.cls` and `VisualTrace.cls`) need the same fix — they are documented as verbatim copies of each other.

---

## BUG-08 — Inspection Agent calls out "no message body" on errored responses as a notable finding; this is normal Ensemble behavior and should not be flagged

**Screen:** VisualTrace — "Ask the agent" tab, Inspection Agent

**Severity:** LOW (UX / answer quality)

**Description:**
On Session 63745 the Inspection Agent investigated two error messages (IDs 63750 and 63751) and reported: *"The two error messages (IDs 63750 and 63751) in session 63745 do not have any message bodies associated with them. This means there is no content in these messages that could provide further insight into why they errored."* This is dressed up as a notable finding, but it is **normal Ensemble behavior** — error / failed Ensemble responses (NULL response bodies on a BO output, like the [11] and [12] entries in the trace) commonly have no body. Operators familiar with Ensemble will recognize the agent is treating a routine state as suspicious, which reduces trust in the agent's other findings.

**Reproduction:**
1. Navigate to a session where one or more BO operations failed and produced NULL response bodies.
2. Ask the agent to "investigate the errors in this session".
3. Observe: agent calls `get_message_body` on the error responses, finds no body, and surfaces it as a noteworthy result.

**Expected:** Agent treats absent message bodies on errored responses as a normal Ensemble pattern and does not call it out unless it's actually unusual (e.g., a successful response with no body, or an error class that normally produces a structured body). Agent focuses its diagnostic narrative on the parts that are actually informative (event log entries, error texts, BP rule decisions, etc.).

**Actual:** Agent flags the absence as a finding worth reporting.

**Root cause (confirmed):**
The Inspection Agent's default system prompt (`src/SessionAgent/Config/AgentDefaults.cls` `GetSystemPrompt("session-inspection")`, lines 43–64) does not include any Ensemble-specific behavioral knowledge — it only sets the read-only invariant, the tool-list directive, and citation conventions. The agent has no prior on what "normal" looks like in an Ensemble session.

**Fix:** Append a short Ensemble domain-knowledge paragraph to the default Inspection Agent system prompt. Suggested wording:

> "Ensemble domain knowledge: error / failed responses on Business Operations commonly have NULL or empty message bodies — this is normal and not a finding. Focus diagnostic narrative on event log entries, error text, BP rule decisions, and the routing path. Do not surface absent error-response bodies as suspicious unless the operator specifically asks about them."

This fix has minimal risk because:
- The prompt is a directive (not an enumeration), per the project rule against runtime-state enumeration in prompts.
- It is additive — no existing behavior is removed.
- Operators can still override it via `Config.Agent.SystemPromptOverride` (MAXLEN=8192) if their domain has different conventions.

---

## ENH-09 — README needs detailed agent setup + usage instructions and compelling agent-in-action screenshots

**Screen:** `README.md` (project root)

**Severity:** MEDIUM (documentation / first-impression)

**Description:**
The current README (378 lines) is operator-prerequisite-heavy — it covers IRIS versions, IPM, Web Gateway, RBAC, package mapping, API keys, SSL configuration, and so on, but it has no clear "how do I actually use the agents" walkthrough and no screenshots. A first-time visitor reading the README cannot quickly see what the agents do, what a chat looks like, or what kind of prompts get good answers. The scope-complete summary block at the top is a list of capabilities, not a demo.

**What's needed:**

1. **A new top-of-README "Quick start — using the agents" section** (probably between the v1.0.0 scope summary and the Operator Prerequisites). Should cover:
   - "After install, navigate to `Interoperability > Message Viewer + Search Agent`" (with the URL path).
   - "Click the 'Ask the agent' tab on the right."
   - 3–5 example prompts the user can paste verbatim, with a one-line explanation of what each demonstrates. Examples: "Find sessions with errors in the last hour" (search across namespace), "Why did this session fail?" (investigation on a specific session via VisualTrace), "Show me the source of the OrderRouter business process" (BP introspection), etc.
   - A note that clicking a session tile opens VisualTrace with the agent tab pre-loaded for follow-up investigation.

2. **2–3 compelling screenshots** showing the agent in action. Suggested:
   - **Screenshot A:** MessageViewer search-agent panel returning a list of failed-sessions tiles, with a follow-up prompt typed into the input. Caption: *"Search agent finds sessions matching natural-language criteria across the whole namespace."*
   - **Screenshot B:** VisualTrace inspection-agent panel showing a multi-tool investigation in progress on a real session — agent has called `get_message_body` + `get_business_process_source` and is explaining the failure. Caption: *"Inspection agent investigates a single session by calling read-only tools and citing specific message IDs."*
   - **Screenshot C (optional):** AgentConfig form with the per-agent provider/model/credential settings. Caption: *"Per-agent configuration — switch providers without code changes."*

   Test data is acceptable in the screenshots (project lead confirmed). Use the sample interop production's `OrderRouter` failure scenarios (which already produce realistic error sessions) so the screenshots show a plausible operator workflow rather than a contrived demo.

3. **Screenshot images committed to repo** under a documented path (e.g. `documentation/images/readme/`) and referenced in the README via relative paths so they render on GitHub.

4. **Suggest reorganizing the README so the Quick-Start section comes BEFORE Operator Prerequisites** — first-time readers should see what they're getting before they're asked to set up SSL configurations.

**Why this matters:**
The agents are the value of the project. The current README's ratio of "things to install" to "things you can do" is heavily weighted toward installation. A reader who wants to evaluate whether to install will close the README before they hit the "What it does" section on line 290.

**Fix scope:**
- One README edit (~50–100 new lines + reorganization).
- 2–3 screenshot captures from a running instance.
- One commit adding the images and the doc edits together.

---

## ENH-10 — README needs an end-to-end "install + run sample project in a new namespace" walkthrough

**Screen:** `README.md` — currently has §"Sample interoperability production for testing" (line 242) AND §"Multi-Namespace Install" (line 172) as separate sections, but no combined recipe.

**Severity:** MEDIUM (documentation / first-run experience)

**Description:**
A new operator who wants to evaluate the project in a clean dedicated namespace (rather than `HSCUSTOM`) currently has to stitch together two README sections:

1. §"Multi-Namespace Install" tells them how to install the SessionAgent package into a target namespace (create namespace, map `SessionAgent.PKG`, run `InstallIntoNamespace`, configure agents).
2. §"Sample interoperability production for testing" tells them how to install + run the sample production — but the section opens with *"From a terminal session in the namespace where SessionAgent is mapped (typically HSCUSTOM)"*, which is ambiguous when applied to a freshly-created sample namespace.

Result: operators end up either (a) installing the sample into `HSCUSTOM` (their default install namespace) and polluting it with test data, or (b) failing partway through the multi-step recipe because the dependency between the two sections is implicit.

**What's needed:**

A new top-level section — something like §"Try it in a clean namespace (recommended for evaluation)" — that walks through end-to-end as a single linear recipe:

1. **Create the new namespace** (Mgmt Portal → System Configuration → Namespaces → New).  Confirm the "Make this an interoperability-enabled namespace" checkbox is set. (Same prereq §"Multi-Namespace Install" already requires.)

2. **Map `SessionAgent.PKG` to the new namespace** (verbatim from §"Multi-Namespace Install" step 2).

3. **Run `InstallIntoNamespace`** (verbatim from §"Multi-Namespace Install" step 3) — produces RBAC role, `Config.Agent` rows, vendored bundle copy, audit-event registration, daily purge task.

4. **Set up API keys IN THE NEW NAMESPACE** — point at §"6. LLM provider API keys" with the explicit reminder that `Ens.Config.Credentials` rows are per-namespace and must be created in the target namespace.

5. **Configure agents via the Zen form** — `/csp/<lower-NS>/SessionAgent.UI.AgentConfig.zen` (provider, model, credentials, enable).

6. **Install the sample production INTO THE NEW NAMESPACE** — explicit terminal walkthrough:
   ```
   ; From a terminal in the new namespace (zn "OTHERNS")
   Do ##class(SessionAgent.Sample.Bootstrap).InstallProduction()
   Do ##class(Ens.Director).StartProduction("SessionAgent.Sample.Production")
   ```

7. **Run scenarios to populate test data**:
   ```
   Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("none")
   Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("businessProcessFailure")
   Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("businessOperationFailure")
   Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("partialSuccess")
   ```

8. **Open the agent UI in the new namespace** — `/csp/<lower-NS>/SessionAgent.EnsPortal.MessageViewer.zen`. Suggest 2–3 example prompts that exercise the freshly-populated test data ("show me sessions with errors", "what failed in session N?", etc.).

9. **Tear-down recipe** at the end so operators can clean up cleanly when done evaluating:
   ```
   Do ##class(SessionAgent.Sample.Bootstrap).UninstallProduction()
   ; (Optional) drop the namespace via Mgmt Portal once you no longer need it.
   ```

**Why this matters:**
The sample production is the project's primary "show off the agent" data source — but the friction to set it up in a clean namespace today means most evaluators end up running it in `HSCUSTOM` (mixing test data with whatever else lives there) or skipping it entirely. A single linear recipe makes "try this in a clean namespace" a 5-minute exercise instead of a 20-minute scavenger hunt across two sections.

**Fix scope:**
- One new README section (~60–80 lines).
- Cross-references back to existing sections for steps that don't need re-explanation (RBAC, SSL, etc.).
- Pairs naturally with ENH-09 (the screenshots can be taken from this clean-namespace setup).

---

## ENH-11 — README needs explicit "how to launch the Message Viewer + Search Agent screen" instructions

**Screen:** `README.md`

**Severity:** MEDIUM (documentation / discoverability)

**Description:**
The custom `SessionAgent.EnsPortal.MessageViewer` page (Story 10.1 — the Message Viewer + Search Agent surface) is the v1.0.0 search-agent host page, and it does NOT replace the standard Ensemble Message Viewer link in the Mgmt Portal nav. An operator who installs v1.0.0 sees no new menu entry — they have to know the URL or the breadcrumb path to find it.

The README references the page indirectly (e.g. line 218 mentions the chat panel asset URL pattern) but never tells the operator: *"Here is how to open the Search Agent screen after install."* This means a fresh installer can finish the install, configure agents, and never see the search agent because they don't know to look for it.

**What's needed:**

A short subsection (probably as part of the §"Quick start — using the agents" section proposed in ENH-09, or as its own subsection if that one isn't built first) that documents the launch paths:

1. **Direct URL** — `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.MessageViewer.zen`. Note that the namespace path segment must be lowercased (e.g., `/csp/hscustom/...`, not `/csp/HSCUSTOM/...`).

2. **Mgmt Portal breadcrumb path** — *Interoperability → Message Viewer + Search Agent* (the page registers under this breadcrumb per the page's `LOCATOR` parameter). Note: the operator must be in the namespace where SessionAgent is mapped before the breadcrumb resolves; navigate to the namespace first via the namespace switcher in the Mgmt Portal banner.

3. **Sister page (Inspection Agent on VisualTrace)** — `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>`. Note this page is normally reached *via* the Search Agent (clicking a session tile), but the URL is also bookmarkable for direct deep-links to a specific session's inspection thread.

4. **A bookmark-friendly note** — call out that both pages are stable, bookmarkable URLs (they are not transient query-result pages), and that bookmarking the MessageViewer is the recommended way for operators to make it their default landing page.

5. **Cross-reference to BUG-04** — once that bug is fixed, also note that clicking a session ID badge from the MessageViewer table opens the custom VisualTrace (with the agent tab) instead of the standard one.

**Fix scope:**
- ~15–25 new lines in README.
- Should land in or near the §"Quick start — using the agents" section proposed in ENH-09. If ENH-09 hasn't been done yet, this can be a standalone subsection under a new §"Launching the agents" header.

---
