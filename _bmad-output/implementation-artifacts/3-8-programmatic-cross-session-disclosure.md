# Story 3.8: Programmatic Cross-Session Disclosure

Status: review

## Story

As an **Operator who may legitimately ask the agent to compare details between sessions**,
I want any cross-session tool dispatch (where `tool_args.session_id` ≠ `chat_tab.bound_session_id`) to produce a deterministic operator-facing notice in the agent's final response — even when the LLM forgets to disclose the cross-session reach itself,
So that I always see when the agent has reached outside the bound session, and the audit ledger + the in-turn UI agree on the scope of the dispatch.

This story closes Story 3.7's binding deferred-work entry per Rule 9 — see Carry-Forward section.

## Carry-Forward from Prior Deferred-Work Entries (Rule 9)

Per `.claude/rules/epic-cycle-discipline.md` Rule 9, Story 3.8's spec author grepped `deferred-work.md` for entries naming Story 3.8:

**Match 1:** `deferred-work.md:518-532` — *"Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03) — system-prompt-only cross-session disclosure unreliable"*. Owner reassigned to Story 3.8 by Sprint Change Proposal 2026-05-03 (Change 4.7). Recommended fix: programmatic enforcement in `Agent.AgentLoop.RunTurn`. After each tool dispatch, inspect args for a `session_id` value; if present AND ≠ `pSessionKey`, set a flag; after the LLM's final response, prepend an automatic notice. The notice is server-side-rendered so the LLM cannot omit it.

**Decision: implement Path 1 (server-side prepend) per the deferred-work recommendation.** The optional UI extension (Story 3.2's chat-panel.js detecting cross-session in renderToolCard) is left to a future story — server-side notice is sufficient for MVP.

## Acceptance Criteria

ACs come from epics.md §"Story 3.8" verbatim.

### AC-1 — Cross-session detection during tool dispatch

**Given** the developer is implementing the cross-session detection in `Agent.AgentLoop.RunTurn`
**When** the iteration loop processes a tool's `args` after dispatch
**Then** the loop inspects `args` for a `session_id` value (when present)
**And** if the value differs from `pSessionKey`, the loop appends to a per-turn collection of distinct session-ids reached outside scope
**And** the inspection handles missing-`session_id` gracefully (most tool calls carry a `session_id` arg; tools that don't are unaffected)

### AC-2 — Server-side notice prepended to final assistant text

**Given** the iteration loop completes
**When** the cross-session collection is non-empty
**Then** the final assistant text emitted by `RunTurn` is server-side-prepended with a deterministic notice: *"Note: this turn dispatched tools against session(s) X (and Y, etc.) outside this chat's bound session N. Audit ledger captured all dispatches."* — followed by a paragraph break + the original assistant text
**And** when the collection has multiple distinct cross-session ids, the notice lists all of them (e.g., `"session(s) 2, 5, 99999"`)
**And** the notice substring is locked by a unit test in `Test/AgentLoopGuardsTest.cls` named `TestRunTurnAppendsCrossSessionNotice`
**And** when the collection is empty (the bound session was the only one dispatched against), the notice is OMITTED — no prepended text — and existing behavior is preserved (verified by an existing-test re-run)

### AC-3 — Audit ledger semantics unchanged

**Given** the audit ledger semantics from Story 2.5
**When** the cross-session notice is appended
**Then** `Audit.LlmCall` and `Audit.ToolCall` rows still contain the bound `pSessionKey` as `ChatHistoryId` linkage (no audit-row schema change)
**And** the cross-session reach is detectable post-hoc via `SELECT %EXACT(Args) FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = N AND %EXACT(Args) [ '"session_id":"M"'` for any `M ≠ N`

### AC-4 — Defense-in-depth with Story 3.7's system-prompt language

**Given** the Story 3.7 system-prompt language already encourages the LLM to disclose cross-session reaches
**When** the LLM does disclose AND the server-side notice is also appended
**Then** the operator sees both — duplicate disclosure is acceptable (defense-in-depth). The LLM's prose disclosure is conversational; the server-side notice is deterministic. They reinforce each other; they don't conflict.

### AC-5 — Empirical re-run of Story 3.7 Turn 5

**Given** the existing 5+ Epic 3 walkthrough turns
**When** an integration test re-runs Story 3.7 Turn 5 (*"Show me what's in session 2"*) against the updated `AgentLoop`
**Then** the final assistant text begins with the *"Note: this turn dispatched..."* sentence
**And** the cross-session reach is operator-visible regardless of LLM compliance with the system-prompt instruction
**And** the lead re-runs the walkthrough via `chrome-devtools-mcp` post-commit and captures the screenshot showing the prepended notice (commit-time evidence)

### AC-6 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.Agent.AgentLoop` (modified per AC-1/AC-2) + `SessionAgent.Test.AgentLoopGuardsTest` (new test per AC-2).
- Authoritative test count via `%Dictionary.MethodDefinition` SQL: **156 + 1 = 157**.
- Story 3.5's `RunTurnInjectsBoundSessionIdIntoSystemPrompt` test still passes (defense-in-depth — system-prompt language unchanged in this story).
- Story 3.7's lead-driven walkthrough still passes end-to-end (the notice prepends but doesn't disrupt) — verifiable via lead-driven re-run.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight surface probe (Rule 4)**
  - [x] Read `src/SessionAgent/Agent/AgentLoop.cls` to find the iteration loop's tool-dispatch site (around line 240–296 per Story 2.12 baseline + Story 3.0 AC-7 malformed-block defense + Story 3.5 AC-6 system-prompt injection). Capture the exact line numbers for the AC-1 detection insertion site + the AC-2 final-assistant-text prepend site.
  - [x] Confirm the `tProvResp.Content[].input` field shape (the `args` object dispatched to the tool) — the cross-session detection inspects `block.input.session_id`.
  - [x] Read `src/SessionAgent/Test/AgentLoopGuardsTest.cls` to find the existing test patterns for `MockOpenAIProvider` mocking + multi-tool turn simulation.

- [x] **Task 1 — Implement AC-1 cross-session detection (AC: #1)**
  - [x] In `AgentLoop.RunTurn`, after each tool-dispatch result is appended to `tConvTurns`, inspect the `tBlockInput` (the `args` %DynamicObject) for a `session_id` property.
  - [x] If present AND `tBlockInput.%Get("session_id") '= pSessionKey`, append the value to a `tCrossSessionList` (use $listbuild or a %DynamicArray — pick whichever is cleaner; the order is dispatch order).
  - [x] Deduplicate: if the same cross-session id appears multiple times in one turn, list it only once in the final notice.
  - [x] Edge cases: handle `tBlockInput` being null, not an object, or missing the `session_id` key — all three should silently skip detection (no exception thrown).

- [x] **Task 2 — Implement AC-2 server-side notice prepend (AC: #2)**
  - [x] After the iteration loop completes (line ~Story-3.5-system-prompt-end + tool-loop-end), check if `tCrossSessionList` is non-empty.
  - [x] If non-empty: build the notice string per the AC-2 template. Format the session-id list as comma-separated.
  - [x] Prepend the notice + a `$Char(10)$Char(10)` paragraph break to `tFinalAssistantText` (the existing variable from Story 2.12 — verify the variable name in Task 0 probe).
  - [x] If empty: leave `tFinalAssistantText` unchanged (existing behavior preserved).

- [x] **Task 3 — Add unit test (AC: #2, #6)**
  - [x] Extend `Test/AgentLoopGuardsTest.cls` with `TestRunTurnAppendsCrossSessionNotice`. Use the existing mock-provider pattern (`MockOpenAIProvider`) to simulate a turn where the LLM dispatches a tool with `args: {"session_id": "999"}` against a bound `pSessionKey = "1"`. Capture the `TurnResult.assistantMarkdown`. Assert it starts with `"Note: this turn dispatched tools against session(s) 999 outside this chat's bound session 1."`.
  - [x] Add `TestRunTurnSkipsNoticeWhenNoCrossSession` — same mock harness but the dispatched tool's `args` use `session_id: "1"`. Assert the assistantMarkdown does NOT start with the notice template.
  - [x] Increment authoritative test count to 157+.

- [x] **Task 4 — Compile + per-class regression sweep (AC: #6)**
  - [x] `iris_doc_compile` for `AgentLoop` + `AgentLoopGuardsTest`.
  - [x] Per-class `iris_execute_tests` for `AgentLoopGuardsTest` (target: all tests pass; the truncated runner may show 2-3 of N; use SQL count for authoritative number).
  - [x] Per-class `iris_execute_tests` for the affected adjacent classes: `AgentLoopTest`, `VisualTraceTest`, `ChatPanelDrawHelperTest`. Confirm no regressions.

- [~] **Task 5 — Lead re-runs Story 3.7 Turn 5 walkthrough (AC: #5)** — DEFERRED to lead (post-commit), per parent-agent direction. The lead drives `chrome-devtools-mcp` at commit time; the dev agent does not own browser automation. AC-5 evidence will be captured by the lead in the commit message + screenshot artifact.
  - [~] Lead invokes `chrome-devtools-mcp` against the chat panel. Submits *"Show me what's in session 2"* (or equivalent).
  - [~] Captures the screenshot showing the agent's response NOW begins with the deterministic notice.
  - [~] Captures the response text in story Completion Notes.

- [x] **Task 6 — Stale-reference grep (Rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|gpt-4o\|csp/static/iris-session-agent" src/SessionAgent/ static/ docs/` → 4 matches found, all intentional historical-commentary references in doc-comments (`UI/ChatPanelAsset.cls` line 7, `EnsPortal/VisualTrace.cls` lines 27/346/368, `docs/epic-cycle-teams.md` line 246). No stale active-code references; no cleanup needed. The Story 3.6 `${cspdir}` workaround intentionally documents the broken `/csp/static/...` path it replaced — that's audit-trail commentary, not stale referential code.

## Dev Notes

### Why server-side notice (not client-side detection)

The deferred-work entry recommended both server-side notice (Path 1) AND optional UI modifier (Path 2 — `.sa-tool-card-cross-session` border). This story implements ONLY the server-side notice. Rationale:

1. **Deterministic behavior**: server-side notice is in the audit-able assistantMarkdown. The audit ledger captures the exact text the operator saw. A client-side modifier would be invisible to audit.
2. **Defense-in-depth**: combined with Story 3.7's system-prompt language (which the LLM SOMETIMES honors), the operator sees the disclosure even when LLM compliance fails.
3. **MVP cost**: server-side notice is ~20 lines of ObjectScript; UI modifier would require chat-panel.js + UI/ChatPanel.cls + new test assertions. Defer the UI modifier to a future story if real-world feedback says the inline-notice isn't visible enough.

### Where the prepend happens

The notice MUST be prepended to the FINAL assistant text returned by the LLM at the end of the iteration loop — NOT to intermediate tool_use blocks. The operator sees one final message; the notice is the leading sentence. Implementation must verify the variable name used by Story 2.12's RunTurn for the final answer (likely `tFinalAssistantText` or similar) — confirm via Task 0 probe.

### Cross-session list deduplication

If the same tool is called twice with the same cross-session id (e.g., `session_summary({"session_id":"2"})` then `session_timeline({"session_id":"2"})`), the notice should list session 2 once, not twice. Use a $listbuild + `$listfind` lookup OR a %DynamicObject with the id as the key for O(1) dedup. Pick whichever is cleaner; the list rarely grows beyond 2-3 entries per turn.

### Notice text — exact wording

The notice template per AC-2:

> *"Note: this turn dispatched tools against session(s) X (and Y, etc.) outside this chat's bound session N. Audit ledger captured all dispatches."*

For 1 cross-session: `"Note: this turn dispatched tools against session(s) 999 outside this chat's bound session 1. Audit ledger captured all dispatches."`

For 2+ cross-sessions: `"Note: this turn dispatched tools against session(s) 2, 5, 999 outside this chat's bound session 1. Audit ledger captured all dispatches."` (comma-separated list)

After the period, two `$Char(10)` characters then the original `tFinalAssistantText`. The Markdown fallback render in chat-panel.js already splits on `\n\n` to produce paragraphs — so the notice gets its own paragraph naturally.

### Sources

- [`epics.md`](../planning-artifacts/epics.md) §"Story 3.8" lines 1357–1395 (or wherever the new section landed).
- [`deferred-work.md`](deferred-work.md) §"Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03)" lines 518–532 — the binding deferral closed by this story.
- [`sprint-change-proposal-2026-05-03.md`](../planning-artifacts/sprint-change-proposal-2026-05-03.md) — the change proposal that scoped this story.
- Story 2.12's `Agent.AgentLoop.RunTurn` — the modified production class.
- Story 3.5 AC-6 system-prompt language — defense-in-depth partner.
- Story 3.7 walkthrough Turn 5 transcript — the empirical evidence that motivated this story.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"%DynamicObject Iterator Safety", §"QUIT Statement Restrictions in Try/Catch Blocks".
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 2, 3, 4, 8, 9.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Claude Code dev agent, 2026-05-03).

### Debug Log References

(none — implementation was straightforward; both new tests passed first-run with no debugging required)

### Completion Notes List

**Task 0 probe outputs (line numbers in pre-edit `AgentLoop.cls`):**

- **Tool-dispatch site (AC-1 detection insertion):** lines 263–343 — the `If tProvResp.StopReason = "tool_use"` branch. Specifically, the dispatch happens at line 315 (`Do ##class(SessionAgent.Tool.Registry).Dispatch(tBlockToolName, tCtx, tBlockInput, .tToolResult)`). The cross-session detection inspects `tBlockInput` (a `%DynamicObject` already validated by the Story 3.0 AC-7 malformed-block guard at lines 295–311). I inserted detection IMMEDIATELY before the dispatch (post-edit lines ~325–346) so the malformed-block guard's `Continue` already short-circuits non-object inputs.
- **Final-assistant-text variable:** `tFinalAssistantText` — declared line 218 (pre-edit), harvested line 357 inside the loop's terminal-stop branch, set by `tHitMaxIter` synthetic at line 369, finally assigned to `tResult.AssistantMarkdown` at line 384. I inserted the AC-2 prepend AFTER the `If tHitMaxIter` block (post-edit lines ~408–428) so the prepend uniformly applies whether the loop ended normally OR hit the max-iter cap.
- **`tBlockInput.session_id` access pattern:** `tBlockInput.%IsDefined("session_id")` then `tBlockInput.%Get("session_id")`. The `%IsDefined` guard avoids reading missing keys; combined with the `$IsObject(tBlockInput)` guard at the start, all three edge cases (null tBlockInput, non-object tBlockInput, missing session_id) silently skip detection per AC-1.

**Implementation summary:**

- AC-1: `tCrossSessionList = ""` declared once before the iteration loop (post-edit line 230). Inside the dispatch branch, `$listfind` checks for prior occurrence; `$listbuild` appends if new. Dedup is O(N) per dispatch but N is rarely > 2-3, so cost is negligible.
- AC-2: After the loop completes (and after the `tHitMaxIter` synthetic if any), `$listlength(tCrossSessionList) > 0` triggers the notice. The list is concatenated comma-separated via `$ListNext` traversal. The notice is prepended with two `$Char(10)` separators per AC-2 wording (chat-panel.js Markdown fallback splits on `\n\n` for paragraph rendering).
- AC-3: NO audit-row schema change. `Audit.LlmCall` and `Audit.ToolCall` rows continue to carry `pSessionKey` as `ChatHistoryId` linkage; cross-session reach is detectable via SQL `WHERE %EXACT(Args) [ '"session_id":"M"'`.
- AC-4: Story 3.7 system-prompt language at lines 205–210 is UNCHANGED. The LLM may also disclose; operator sees both (defense-in-depth — duplicate disclosure is acceptable per AC-4).

**Compile output:**

- `iris_doc_compile SessionAgent.Agent.AgentLoop.cls` → success, 16ms (cuk-d flags — forced recompile).
- `iris_doc_compile SessionAgent.Test.AgentLoopGuardsTest.cls` → success, 14ms.
- Verified the Story 3.8 AC-2 marker is present in the COMPILED method body via `iris_execute_command` reading `%Dictionary.CompiledMethod.Implementation` stream — output `AC2-PRESENT`.

**Authoritative test count (via `%Dictionary.MethodDefinition` SQL):**

```
SELECT COUNT(*) AS cnt FROM %Dictionary.MethodDefinition
WHERE parent->ID %STARTSWITH 'SessionAgent.Test.' AND %EXACT(Name) %STARTSWITH 'Test'
```

- Pre-Story-3.8 baseline: **156** (matches spec § AC-6).
- Post-Story-3.8: **158** (+2 — `TestRunTurnAppendsCrossSessionNotice` + `TestRunTurnSkipsNoticeWhenNoCrossSession`).
- Spec target was "157+" — exceeded.

**Per-class test runs (all PASS):**

- `SessionAgent.Test.AgentLoopGuardsTest` per-method (the package-level runner truncates) — **9 of 9 PASS**:
  1. `RunTurnAppendsCrossSessionNotice` (NEW) — 161.674ms
  2. `RunTurnSkipsNoticeWhenNoCrossSession` (NEW) — 166.569ms
  3. `RunTurnMaxIterationsCap` — 857.371ms
  4. `RunTurnNoExceptionEvenIfProviderErrors` — 77.165ms
  5. `RunTurnDisabledAgentReturnsErrorTurnResult` — 1.375ms
  6. `RunTurnUnconfiguredAgentReturnsErrorTurnResult` — 0.969ms
  7. `RunTurnSurvivesMalformedToolUseBlocks` (Story 3.0 AC-7) — 79.965ms
  8. `RunTurnInjectsBoundSessionIdIntoSystemPrompt` (Story 3.5 AC-6) — 80.923ms
  9. `RunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty` (Story 3.5 AC-6 sibling) — 6.113ms

  **Defense-in-depth confirmation:** Story 3.5 AC-6 system-prompt-injection test (#8) still passes — Story 3.8 did NOT alter the system-prompt language; both system-prompt language AND server-side notice fire (per AC-4).

- `SessionAgent.Test.AgentLoopTest` class — **3 of 3 PASS** (`RunTurnAuditCompletenessForToolDispatch`, `RunTurnLockReleasedOnSave`, `RunTurnWithMockProviderSingleTurn`).
- `SessionAgent.Test.VisualTraceTest` class — **5 of 5 PASS**.
- `SessionAgent.Test.ChatPanelDrawHelperTest` class — **4 of 4 PASS**.

**Task 6 grep results:** 4 matches found across `src/SessionAgent/`, `static/`, `docs/`. All intentional historical-commentary references in doc-comments (Story 3.6 `${cspdir}` workaround documenting the broken `/csp/static/...` path it replaced; `epic-cycle-teams.md` documenting the Story 1.6 HSCUSTOMCODE correction). No stale active-code references; no cleanup needed.

**Rule 9 closure (deferred-work entry):** The Story 3.7 cross-session-disclosure deferred-work entry at `_bmad-output/implementation-artifacts/deferred-work.md` lines ~522 has been tagged **"STATUS: CLOSED 2026-05-03 by Story 3.8 (Programmatic Cross-Session Disclosure)"** with the closure mechanism documented (server-side `RunTurn` prepend; Path 1 from the original entry). The original entry is preserved verbatim below the CLOSED status block for audit trail.

**AC-5 (lead-driven walkthrough re-run):** DEFERRED to the lead post-commit per parent-agent direction. The dev agent does not drive `chrome-devtools-mcp`; the lead captures the AC-5 evidence (screenshot showing the deterministic notice prepended to the response) at commit time. Spec Task 5 sub-items marked `[~]` (partial / blocked-by-design) per Rule 2 §"If verification can't be run, keep `[ ]` and document".

**ACs not satisfied / impossible:** None. AC-1 through AC-4 + AC-6 are fully verified by the dev agent. AC-5 is verifiable only via the lead's chrome-devtools-mcp run (post-commit responsibility). All other ACs satisfied empirically.

### File List

- `src/SessionAgent/Agent/AgentLoop.cls` (UPDATE) — AC-1 cross-session detection inside tool-dispatch loop (post-edit lines ~325–346) + AC-2 server-side notice prepend after iteration-loop end (post-edit lines ~408–428) + `tCrossSessionList` declaration (post-edit line 230). Story 3.7 system-prompt language at lines 205–210 unchanged (defense-in-depth partner).
- `src/SessionAgent/Test/AgentLoopGuardsTest.cls` (UPDATE — +2 tests) — `TestRunTurnAppendsCrossSessionNotice` (AC-2 substring + ordering lock) + `TestRunTurnSkipsNoticeWhenNoCrossSession` (AC-2 negative — notice omitted when no cross-session dispatched).
- `_bmad-output/implementation-artifacts/deferred-work.md` (UPDATE) — Story 3.7 cross-session-disclosure deferred-work entry tagged CLOSED with date + closure mechanism per Rule 9.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (UPDATE) — Story 3.8 status `ready-for-dev` → `in-progress` → `review`.

### Change Log

| Date | Author | Change |
|---|---|---|
| 2026-05-03 | Dev agent (claude-opus-4-7[1m]) | Implemented AC-1 (cross-session detection in `RunTurn` tool-dispatch loop) + AC-2 (server-side deterministic notice prepend to `tFinalAssistantText`) + 2 new unit tests in `AgentLoopGuardsTest`. Test count 156 → 158. Closes Story 3.7 cross-session-disclosure deferred-work entry per Rule 9. AC-5 (lead-driven `chrome-devtools-mcp` walkthrough re-run) deferred to lead post-commit. |
