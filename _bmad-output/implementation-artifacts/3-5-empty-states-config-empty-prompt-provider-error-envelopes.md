# Story 3.5: Empty States + Config-Empty Prompt + Provider-Error Envelopes

Status: review

## Story

As an **Operator-Admin (first install) and an Operator (mid-conversation)**,
I want clear empty-state and error-state messaging in the chat panel: when no agent is configured (admin variant of `sa-config-empty-prompt` linking to `SessionAgent.UI.AgentConfig.zen` — though that page lands in Epic 6), and when a provider call times out or fails (operator-readable error envelopes in the transcript with retry hints),
So that I always know what to do next per UX-DR17-MVP-subset and UX-DR18-MVP-subset — never seeing a blank panel or a stack-trace.

This story also closes the Story 3.3 reviewer's binding deferral (F5) — the system prompt now injects the bound IRIS session_id so the LLM grounds tool calls in the right session instead of hallucinating UUIDs. See Carry-Forward section.

## Carry-Forward from Prior Deferred-Work Entries (Rule 9)

Per `.claude/rules/epic-cycle-discipline.md` Rule 9, Story 3.5's spec author grepped `deferred-work.md` for entries naming Story 3.5 and incorporated them:

**Match 1:** `deferred-work.md:436-460` — *"System prompt does NOT inject the bound IRIS session_id; LLM hallucinates session_ids when the operator's text doesn't mention them."*

The Story 3.3 reviewer offered three fix paths; Path 1 (prompt augmentation in `AgentLoop.RunTurn`) was recommended as smallest and matching the existing read-only-invariant-injection pattern.

**Decision: Path 1 — prompt augmentation in `Agent.AgentLoop.RunTurn`.** Resolution implemented in this story (AC-6).

## Acceptance Criteria

ACs come from epics.md §"Story 3.5" verbatim, plus AC-6 (the F5 carry-forward) and AC-7 (compile/test gate).

### AC-1 — No-config detection

**Given** the developer is implementing the no-config detection
**When** the chat tab opens AND no `Config.Agent` row exists for the agent OR `Config.Agent.Enabled=0`
**Then** the chat panel renders an `sa-config-empty-prompt` element replacing the transcript area + disables the input field per UX-DR7-admin.
**And** if the operator has the `%All` role (MVP admin-detection — TBD-confirmed-with-user; Epic 6 will add a `%SessionAgent_Admin` role), the prompt includes a link to `SessionAgent.UI.AgentConfig.zen` — Epic 6's config page (which doesn't exist yet, so MVP renders the link as a placeholder showing the URL but the link target is "not yet implemented — coming in Epic 6").
**And** if the operator does NOT have admin privileges, the prompt text reads *"This agent isn't configured yet. Ask your operator-admin."* with no link.
**And** the prompt has `role="alert"` per UX-DR20-MVP.
**And** the input field has `aria-disabled="true"` plus visual de-emphasis (CSS class `sa-input-field-disabled`) per UX-DR20-MVP.

### AC-2 — Provider-error envelope rendering

**Given** the developer is implementing provider-error envelope rendering in `chat-panel.js`
**When** `Agent.AgentLoop.RunTurn` returns a `TurnResult` with structured error content (e.g., 90s timeout from Story 2.9, 4xx provider auth error, 5xx provider unavailable, no-config caught fallback)
**Then** the chat panel renders an `sa-message-block sa-msg-agent sa-msg-error` block in the transcript with operator-readable text per UX-DR18-MVP-subset:
  - **Provider timeout (90s cap)**: *"The LLM call exceeded 90 seconds. The provider may be overloaded or the question too complex. Try again or simplify."*
  - **Provider network/auth/rate-limit error**: *"Couldn't reach `<provider>`: `<reason>`. Check the provider's status or your API key."*
  - **No-config error** (caught here as fallback if Story 2.12 wasn't loaded): *"This agent isn't configured. An operator-admin needs to set up an LLM provider."*
**And** the input field re-enables after error rendering (operator can retry without page reload).
**And** the audit row written by Story 2.5 captures the full error context (with stack trace in `ErrorText`); the operator-facing message contains NO stack trace per UX-DR18.

### AC-3 — Per-tool error status (mid-turn tool failure)

**Given** a tool dispatch fails mid-turn (one of the dispatched tools returned `{isError:true, ...}`)
**When** the tool-call card renders (Story 3.2's `renderToolCard` already handles `status: "error"` → CSS modifier `sa-tool-card-status-error`)
**Then** the card shows red `×` status indicator + the error reason in the summary slot per UX-DR21 (color + text label, not color alone).
**And** the agent continues processing with degraded context (per architecture §"Concurrent tool errors don't halt the agent" — already in `Agent.AgentLoop` from Story 2.12). Final answer renders below the failed card with a note about the limitation if the LLM mentions it.
**And** the operator does NOT see a panel-level error for tool failures; only per-card status.

### AC-4 — `sa-config-empty-prompt` server-side detection in `DrawChatPanel` callback

**Given** `SessionAgent.EnsPortal.VisualTrace.DrawChatPanel` is the Zen callback that decides what HTML to emit
**When** it queries `Config.Agent` for the bound `pAgentName`
**Then** if no row exists OR `Enabled=0`, the callback emits the `sa-config-empty-prompt` HTML directly (NOT the chat shell) — operator never sees the empty input field. The bootstrap-context script is omitted (no JS init needed in this state).
**And** if a row exists with `Enabled=1`, the callback emits the chat shell as before (per Story 3.3).
**And** the admin-detection uses `$System.Security.Check("%All", "U")` returning 1 → admin variant; otherwise non-admin variant. (TBD-confirmed-with-user: when Epic 6 adds `%SessionAgent_Admin`, this check evolves.)

### AC-5 — Bootstrap envelope shape extension for client-side error kinds

**Given** Story 3.3 already passes through the `error` field from `TurnResult.ToJson()`
**When** the JS `handleEnvelope` function dispatches by `error.kind`
**Then** the handler maps each kind to the AC-2 operator-readable text via a `ERROR_KIND_TO_TEXT` map keyed by `provider_timeout|provider_error|provider_auth|provider_rate_limit|no_config|internal`. Unknown kinds fall back to a generic *"Something went wrong: \<error.message\>"*.
**And** the renderer is `renderErrorBlock(envelope.error)` — already exists in Story 3.2 chat-panel.js (extended in this story to use the new map + per-kind retry hints).

### AC-6 — System-prompt session-id injection (closes F5 carry-forward)

**Given** `SessionAgent.Agent.AgentLoop.RunTurn` constructs the system prompt before calling the provider
**When** the prompt is assembled (after `tSysPrompt = ##class(Config.AgentDefaults).GetSystemPrompt(pAgentName)`)
**Then** the method appends a sentence binding the system prompt to `pSessionKey`: *"The currently-bound IRIS Production Ens session ID for this conversation is `<pSessionKey>`. Use this id verbatim when calling inspection tools unless the operator explicitly asks about a different session."*
**And** the appended sentence is OMITTED when `pSessionKey` is empty (e.g., search-agent contexts where session_id isn't bound — future Epic 8+ usage).
**And** a new test `TestRunTurnInjectsBoundSessionIdIntoSystemPrompt` in `AgentLoopTest.cls` (or `AgentLoopGuardsTest.cls` per existing split) asserts the injection: invoke `RunTurn(...)` with a `MockOpenAIProvider` that captures the system prompt; assert the sentence appears.

### AC-7 — Compile + tests + regression intact (including Rule 11 re-validation)

- `iris_doc_compile` clean for: `SessionAgent.Agent.AgentLoop` (modified per AC-6), `SessionAgent.EnsPortal.VisualTrace` (extended per AC-4), `SessionAgent.UI.ChatPanel` (extended for `sa-config-empty-prompt` CSS + `sa-input-field-disabled` CSS), `static/chat-panel.js` (extended `handleEnvelope` per AC-5), `SessionAgent.Test.AgentLoopTest` or `AgentLoopGuardsTest` (new test per AC-6), `SessionAgent.Test.VisualTraceTest` (new tests per AC-1/AC-4), `SessionAgent.Test.ChatPanelJsTest` (new assertions per AC-5).
- New tests added: at least 5 (config-empty admin, config-empty non-admin, provider-error envelope rendering, ERROR_KIND_TO_TEXT map present, system-prompt session-id injection).
- Per-class regression sweep: 150 + 5 = **155/155** total via `%Dictionary.MethodDefinition` SQL.
- **Rule 11 live OpenAI re-run with the F5 demanding prompt** — re-run the same prompt that surfaced F5: *"Walk me through what happened in this session, then check if any messages had errors..."* against bound session "1". Capture the dispatched tool args. **Expected**: tools now dispatch with `session_id: "1"` (the bound id), NOT a hallucinated UUID. The fix is verified ONLY when this test passes empirically.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight surface probes (Rule 4)**
  - [x] Read `src/SessionAgent/Agent/AgentLoop.cls` — `tSysPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt(pAgentName)` is at **line 184**, inside the `Else` branch of the if/else block at lines 180–185. AC-6 insertion goes immediately after the `}` closing line 185.
  - [x] Read `src/SessionAgent/Config/AgentDefaults.cls` — `GetSystemPrompt(pAgentName)` returns `%String`; for `"session-inspection"` it returns the canonical 4-sentence prompt listing tool names + the read-only invariant; returns `""` for any unknown agent name.
  - [x] Read `src/SessionAgent/EnsPortal/VisualTrace.cls` — `DrawChatPanel(pSeed)` at lines 162–220. Prior-history lookup starts at line 183 (`Set tPriorJson = "[]"`); AC-4 pre-flight insertion goes after the parameter resolution (line 178) and before the prior-history lookup.
  - [x] Confirmed `$System.Security.Check("%All", "U")` returns 1 for `%All`-bearing user, 0 otherwise (2-arg form per `irislib/%SYSTEM/Security.cls` lines 60–76 + empirical probe via `iris_execute_classmethod` returned `1`).

- [x] **Task 1 — Implement AC-6 system-prompt session-id injection (AC: #6)**
  - [x] In `Agent/AgentLoop.cls` `RunTurn` method, after `tSysPrompt = ##class(...).GetSystemPrompt(pAgentName)`: inserted the `If pSessionKey '= "" { ... }` guard with the binding sentence verbatim per spec.
  - [x] Wrote `TestRunTurnInjectsBoundSessionIdIntoSystemPrompt` per AC-6: uses new `SessionAgent.Test.SystemPromptCaptureMock` (subclass of `AgentLoopMockProvider`) that stashes `pSystemPrompt` into a process-private global before delegating to `##super`. Asserts the captured prompt contains `"currently-bound IRIS Production Ens session ID for this conversation is " _ tSessionKey`. PASSES.
  - [x] Added sibling test `TestRunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty` — structural test reading the compiled `RunTurn` body via `%Dictionary.CompiledMethod` (the integration form is unreachable because `Chat.History.LoadOrCreate` rejects empty session keys). Asserts the `If pSessionKey '= ""` guard precedes the binding-sentence concatenation. PASSES.

- [x] **Task 2 — Implement AC-1 + AC-4 server-side no-config detection**
  - [x] In `EnsPortal/VisualTrace.cls` `DrawChatPanel` method: added pre-flight `Config.Agent` lookup via `AgentNameIdxOpen(tAgentName)` (preferred over raw `&sql` to avoid SQL-vs-property-name drift; the spec referenced property name `Name` but the storage column is `AgentName` per Task 0 SQL probe). If no row OR `Enabled=0`, branches to `EmitConfigEmpty(pAgentName, pIsAdmin)` and quits the method.
  - [x] Added `EmitConfigEmpty(pAgentName, pIsAdmin)` ClassMethod to `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`. Emits the `sa-chat-panel` shell containing the `sa-config-empty-prompt` div with `role="alert"` + admin/non-admin variant text + disabled textarea with `aria-disabled="true"` + `sa-input-field-disabled` CSS class. NO bootstrap script.
  - [x] Admin probe: `Set tIsAdmin = $System.Security.Check("%All", "U")` — returns 1 if user has `%All`, 0 otherwise.

- [x] **Task 3 — Implement AC-5 client-side error-envelope rendering**
  - [x] In `static/chat-panel.js`: added `ERROR_KIND_TO_TEXT` module-private map keyed by all six wire-format kinds (`provider_timeout|provider_error|provider_auth|provider_rate_limit|no_config|internal`). Each entry is a `function(error) -> string` so per-kind retry hints + provider/reason interpolation can vary.
  - [x] Extended `renderErrorBlock(error)` to look up `error.kind` in the map; substitutes `error.provider` (default: `"the provider"`) and `error.message` (default: `"unknown error"`) where applicable.
  - [x] Unknown kinds fall back to `"Something went wrong: " + (error.message || "unknown error")` with the legacy `.sa-error-hint` retry cue still attached.

- [x] **Task 4 — Add AC-1 + AC-4 + AC-5 tests**
  - [x] `VisualTraceTest.cls` — added `TestDrawChatPanelConfigEmptyAdmin` + `TestDrawChatPanelConfigEmptyNonAdmin` + helper `CaptureEmitConfigEmpty(pAgentName, pIsAdmin)` that opens a temp file, redirects via `Use`, invokes `EmitConfigEmpty`, restores I/O, reads back the captured HTML. Both tests PASS.
  - [x] `ChatPanelJsTest.cls` — added `TestErrorKindToTextMapPresent` (asserts the map identifier + all 6 kind keys + UX-DR18-MVP-subset verbatim text fragments) and `TestRenderErrorBlockHandlesUnknownKind` (asserts the `"Something went wrong: "` fallback + the `ERROR_KIND_TO_TEXT[kind]` lookup pattern). Both tests PASS.

- [x] **Task 5 — Tile CSS rules (AC: #1, #4)**
  - [x] In `UI/ChatPanel.cls EmitStyle()`: added `.sa-config-empty-prompt { padding: 1em; color: var(--sa-error-text-color); }` and `.sa-input-field-disabled { opacity: 0.6; cursor: not-allowed; }`. Both reference existing tokens from the 10-token MVP set; `.sa-input-field-disabled` uses opacity + cursor only (no color literal — UX-DR26-compliant, no hex/rgba).

- [x] **Task 6 — Compile + per-class regression sweep + Rule 11 re-validation (AC: #7)**
  - [x] `iris_doc_compile` clean for: `SessionAgent.Agent.AgentLoop`, `SessionAgent.EnsPortal.VisualTrace`, `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`, `SessionAgent.UI.ChatPanel`, `SessionAgent.Test.SystemPromptCaptureMock` (NEW), `SessionAgent.Test.AgentLoopGuardsTest`, `SessionAgent.Test.VisualTraceTest`, `SessionAgent.Test.ChatPanelJsTest`. All cuk/up-to-date.
  - [x] Per-class `iris_execute_tests` for all 21 SessionAgent.Test.* classes — every test passes (per-method run for the truncated runs in AgentLoopGuardsTest + ToolRegistryTest + AgentLoopTest, full pass on the others). Story 3.3 live OpenAI smoke (`TestSendChatMessageLiveOpenAI`) PASSES (2041ms — confirms AC-6 didn't break the wire path).
  - [x] Authoritative count via `%Dictionary.MethodDefinition` SQL — **156 total** (baseline 150 + 6 new: `RunTurnInjectsBoundSessionIdIntoSystemPrompt`, `RunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty`, `DrawChatPanelConfigEmptyAdmin`, `DrawChatPanelConfigEmptyNonAdmin`, `ErrorKindToTextMapPresent`, `RenderErrorBlockHandlesUnknownKind`). Spec said "at least 5"; 6 is acceptable — added one extra to cover the structural omission case for AC-6.
  - [x] **Rule 11 demanding-prompt smoke**: invoked `SendChatMessage("session-inspection", "1", "Walk me through what happened in this session, then check if any messages had errors, and if there were errors show me details. Be thorough.", "{}")` via `iris_execute_classmethod`. Dispatched tool args show `session_id: "1"` verbatim (NOT a hallucinated UUID — F5 closure verified empirically). See Completion Notes for full transcript.

- [x] **Task 7 — Stale-reference grep (Rule 4)**
  - [x] `grep -rn "Custom\.EnsPortal\|HSCUSTOMCODE\|gpt-4o" src/SessionAgent/ static/` → 0 matches (clean).

## Dev Notes

### F5 binding closure — surface contract

The Story 3.3 reviewer's F5 deferral entry (`deferred-work.md:436-460`) explicitly identified Path 1 (prompt augmentation in `RunTurn`) as the recommended fix. AC-6 implements Path 1 verbatim. The `deferred-work.md` entry must be tagged `[CLOSED 2026-05-03 by Story 3.5 — Rule 9 binding deferral honored]` after AC-6 lands and the Rule 11 re-validation (Task 6) passes.

### Admin role TBD

The spec text says *"the `%All` role (MVP admin-detection — TBD-confirmed-with-user; Epic 6 will add a `%SessionAgent_Admin` role)"*. This is a deliberate punt: MVP-Inspection-Agent doesn't ship its own admin role; we leverage `%All`. Epic 6 introduces `%SessionAgent_Admin` and adjusts the check. If the user wants a different MVP admin probe (e.g., `%Manager`), surface as a clarification.

### `Config.Agent` SQL probe — case-insensitivity gotcha

`Config.Agent.Name` is a `%String` column. Per `.claude/rules/iris-objectscript-basics.md` §"IRIS SQL Case Sensitivity", string comparisons are case-insensitive by default unless wrapped in `%EXACT()`. AC-4's pre-flight uses `WHERE Name = :pAgentName`. If the spec calls for `"session-inspection"` (lowercase) and a row exists as `"Session-Inspection"`, the query matches. This is acceptable for MVP — we don't expect agent-name case variations — but worth noting.

### Why server-side no-config detection (not client-side)

UX-DR7-admin says no-config replaces the transcript area + disables input. If the JS detected no-config client-side, the operator would see the chat shell flash before the empty-prompt replaces it. Server-side detection in `DrawChatPanel` produces the empty-state HTML directly — no flash, no client-side rewrite, no JS init in the no-config state. Cleaner and faster.

### Tool-error per-card status (AC-3) is already handled

Story 3.2's `renderToolCard` already maps DTO `status: "error"` → CSS modifier `sa-tool-card-status-error` (after Story 3.2 reviewer's `ok|error → complete|error` mapping fix). UX-DR21 requires color + text label (not color alone) — Story 3.2's card body shows the tool-name + summary text, so the text-label requirement is already met. AC-3 is therefore largely a verification: confirm the existing per-card path renders correctly when `status: "error"` arrives.

### Order of operations recommended

1. Task 0 probes (find AgentLoop insertion site + DrawChatPanel structure).
2. Task 1 (AC-6 backend fix — minimal one-line addition + 2 tests) — lands first because it's the F5 closure and the most empirically verifiable.
3. Task 2 + Task 5 (server-side no-config + CSS) — interrelated.
4. Task 3 + Task 4 (client-side error-envelope rendering + tests).
5. Task 6 + Task 7.

### Sources

- [`epics.md`](../planning-artifacts/epics.md) §"Story 3.5" lines 1251–1280.
- [`deferred-work.md`](deferred-work.md) §"Deferred from: code review of story-3-3-..." lines 436–460 (F5 closed by AC-6).
- [`architecture.md`](../planning-artifacts/architecture.md) §"Caller context propagation"; §"Concurrent tool errors don't halt the agent".
- [`ux-design-specification.md`](../planning-artifacts/ux-design-specification.md) UX-DR7-admin (config-empty), UX-DR17-MVP-subset, UX-DR18-MVP-subset (provider-error envelope), UX-DR20-MVP (role/aria), UX-DR21 (status indicator + text), UX-DR26 (no hardcoded color in component CSS).
- Story 2.4's `Config.AgentDefaults.GetSystemPrompt`, Story 2.12's `Agent.AgentLoop.RunTurn` (modified per AC-6).
- Story 2.9's `OpenAIProvider` 90s timeout + provider-error envelope shape.
- Story 3.2's `renderErrorBlock` + `renderToolCard` (extended).
- Story 3.3's `EnsPortal.VisualTrace.DrawChatPanel` callback (extended).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS SQL Case Sensitivity"; §"IRIS Library Source".
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 2, 3, 4, 8, 9, 11.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) via BMAD dev-story skill on 2026-05-03.

### Debug Log References

(none — no debug globals used)

### Completion Notes List

#### Task 0 — Pre-flight surface probes

- **AgentLoop.cls insertion site:** `tSysPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt(pAgentName)` is at line 184, inside the `Else` branch of the if/else block lines 180–185. AC-6 binding-sentence injection added immediately after the closing `}` on line 185.
- **AgentDefaults.GetSystemPrompt signature:** `ClassMethod GetSystemPrompt(pAgentName As %String) As %String` — returns canonical 4-sentence prompt for `"session-inspection"`, returns `""` for unknown agents.
- **DrawChatPanel structure:** `Method DrawChatPanel(pSeed As %String) As %Status` at lines 162–220. Pre-flight no-config detection inserted after parameter resolution (line 178) and before prior-history lookup (line 183).
- **`$System.Security.Check("%All", "U")` return-type confirmation:** Per `irislib/%SYSTEM/Security.cls` lines 60–76: 2-arg form returns 1 if user has the privilege on the resource, 0 otherwise. Note: process holding `%All` always returns 1 for the 2-arg form per line 71. Empirical probe via `iris_execute_classmethod` confirmed: returnValue=1 for the MCP user.
- **Config.Agent SQL probe:** Returns `AgentName=session-inspection, Enabled=true, Provider=openai, Model=gpt-4.1-mini, CredentialName=SessionAgentOpenAI`. Important: storage column is `AgentName` (not `Name` as spec said) — implementation uses `AgentNameIdxOpen()` instead of raw `&sql` for type-safety.
- **Baseline test count:** 150 via `%Dictionary.MethodDefinition` SQL (`SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE %EXACT(parent) %STARTSWITH 'SessionAgent.Test.' AND Name %STARTSWITH 'Test'`).

#### Final test count

- **156 total** (baseline 150 + 6 new). Spec target was 155; added one extra structural test for the empty-pSessionKey omission case because the integration form is unreachable (Chat.History.LoadOrCreate rejects empty session keys).

#### Rule 11 demanding-prompt smoke transcript (verbatim)

Invoked: `iris_execute_classmethod SessionAgent.EnsPortal.VisualTrace::SendChatMessage("session-inspection", "1", "Walk me through what happened in this session, then check if any messages had errors, and if there were errors show me details. Be thorough.", "{}")`

Returned envelope (verbatim):

```json
{
  "assistantMarkdown": "In session 1, there was only 1 message processed. The session had no errors at all. The root message class is not specified, and the session duration was very short (0 ms). Since there were no error messages in this session, there are no error details to show.\n\nIf you want, I can provide a detailed timeline or message content for this session. Would you like me to do that?",
  "usageRollup": {"input_tokens":906, "output_tokens":136, "cache_creation_input_tokens":0, "cache_read_input_tokens":0},
  "durationMs": 3562,
  "toolCallsRendered": [
    {
      "name": "session_summary",
      "args": {"session_id":"1"},
      "result": {"content":[{"type":"text","text":"Session 1: 1 messages, 0 errors, root class ."}], "structuredContent":{"message_count":1, "error_count":0, "duration_ms":0, "root_message_class":"", "session_exists":true}},
      "status": "ok"
    },
    {
      "name": "message_headers",
      "args": {"session_id":"1", "min_severity":"error"},
      "result": {"content":[{"type":"text","text":"Session 1: 0 headers."}], "structuredContent":{"headers":[], "header_count":0}},
      "status": "ok"
    }
  ]
}
```

**PASS criterion met:** `session_id: "1"` (the bound id) appears verbatim in BOTH dispatched tool args. Compare to F5 capture which showed `session_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"` (hallucinated UUID). The fix is verified empirically.

#### F5 carry-forward closure confirmation

The `deferred-work.md` entry at lines 436–460 (Story 3.3 review F5) is tagged **[CLOSED 2026-05-03 by Story 3.5 — Rule 9 binding deferral honored]** with closure mechanism + empirical Rule 11 verification documented inline. See `_bmad-output/implementation-artifacts/deferred-work.md` lines 438–440.

#### Story 3.3 live OpenAI smoke re-run

`SessionAgent.Test.VisualTraceTest:SendChatMessageLiveOpenAI` passes (2041.376ms — full real OpenAI round-trip + 2 tool dispatches + audit-row inserts). Confirms AC-6's 1-line addition didn't break the wire path.

#### Task 7 grep results

`grep -rn "Custom\.EnsPortal|HSCUSTOMCODE|gpt-4o" src/SessionAgent/ static/` → 0 matches (clean).

### File List

- `src/SessionAgent/Agent/AgentLoop.cls` (UPDATE) — AC-6 system-prompt session-id injection (8-line block including comment).
- `src/SessionAgent/EnsPortal/VisualTrace.cls` (UPDATE) — AC-1/AC-4 server-side no-config detection in `DrawChatPanel`.
- `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls` (UPDATE) — added `EmitConfigEmpty(pAgentName, pIsAdmin)` ClassMethod with admin/non-admin variants.
- `src/SessionAgent/UI/ChatPanel.cls` (UPDATE) — added `.sa-config-empty-prompt` + `.sa-input-field-disabled` CSS rules in `EmitStyle()`.
- `src/SessionAgent/Test/SystemPromptCaptureMock.cls` (NEW) — capture-and-delegate mock provider for AC-6 system-prompt verification.
- `src/SessionAgent/Test/AgentLoopGuardsTest.cls` (UPDATE) — +2 tests for AC-6 (`TestRunTurnInjectsBoundSessionIdIntoSystemPrompt`, `TestRunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty`).
- `src/SessionAgent/Test/VisualTraceTest.cls` (UPDATE) — +2 tests for AC-1/AC-4 (`TestDrawChatPanelConfigEmptyAdmin`, `TestDrawChatPanelConfigEmptyNonAdmin`) + helper `CaptureEmitConfigEmpty`.
- `src/SessionAgent/Test/ChatPanelJsTest.cls` (UPDATE) — +2 tests for AC-5 (`TestErrorKindToTextMapPresent`, `TestRenderErrorBlockHandlesUnknownKind`).
- `static/chat-panel.js` (UPDATE) — `ERROR_KIND_TO_TEXT` map + extended `renderErrorBlock` per AC-5.
- `_bmad-output/implementation-artifacts/deferred-work.md` (UPDATE) — F5 entry tagged CLOSED with date + closure mechanism + empirical Rule 11 verification.

### Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-03 | Story 3.5 implemented end-to-end. AC-1/AC-4 server-side config-empty detection + admin/non-admin variants. AC-5 client-side `ERROR_KIND_TO_TEXT` map + extended `renderErrorBlock`. AC-6 system-prompt session-id injection (closes Story 3.3 F5 carry-forward — Rule 11 demanding-prompt smoke verifies tools dispatch with bound `session_id:"1"` not hallucinated UUID). 6 new tests, 156/156 total. F5 in deferred-work.md tagged CLOSED. | Dev (Claude Opus 4.7) |
