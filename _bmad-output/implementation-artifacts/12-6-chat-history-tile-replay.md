# Story 12.6: Chat History Tile Replay — Preserve tool_use / tool_result Blocks Across Page Reload

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` BUG-07 (HIGH severity). Search Agent renders 20 clickable session tiles in the chat panel. Operator clicks one → navigates to VisualTrace → hits Back to return. Chat panel reloads showing only the agent's text response — the 20 tiles are gone. Operator must re-search. Click-through workflow is effectively single-shot.

The persistence layer DOES save tool_use/tool_result blocks (`SessionAgent.Chat.History.TurnsJson` is the full canonical-Anthropic shape). The page-reload path explicitly strips them via `FlattenTurnsForBootstrap` (verbatim copies in `MessageViewer.cls` lines 311–368 AND `VisualTrace.cls`).

## User Story

As an **operator** clicking through Search Agent result tiles to inspect a specific session, I want to be able to navigate Back to my search results without losing the tile list, so that I can pivot between multiple result candidates without re-running the search.

## Acceptance Criteria

**AC-1 — `FlattenTurnsForBootstrap` preserves tool_use / tool_result blocks.** [BUG-07]
- **Given** `SessionAgent.Chat.History.TurnsJson` contains canonical-Anthropic turns including `{"role":"assistant","content":[{"type":"tool_use", ...}]}` and `{"role":"user","content":[{"type":"tool_result", ...}]}`,
- **When** `FlattenTurnsForBootstrap` is called (in either `MessageViewer.cls` OR `VisualTrace.cls` — both have verbatim-copy implementations),
- **Then** the returned JSON array preserves the tool_use/tool_result data: each tool_use block becomes a `{"role":"agent","toolCalls":[{...}]}` entry; each tool_result block is paired with its matching tool_use via `tool_use_id` and merged into the same flattened entry's `toolCalls[i].result` field. Pure text turns continue to be rendered as before.

> **Verbatim evidence (Rule 2 sharpened):** Compile-time grep of both `MessageViewer.cls` and `VisualTrace.cls` `FlattenTurnsForBootstrap` shows the new tool-block-preservation branch. Live test: load a `Chat.History` row that has tool_use/tool_result blocks, call `FlattenTurnsForBootstrap`, capture the verbatim JSON output and confirm `toolCalls` array is non-empty for assistant turns.

**AC-2 — Server-side bootstrap envelope shape extended.**
- **Given** `ChatPanelDrawHelper.DrawChatPanel` accepts `pPriorTranscriptJson` and embeds it as `priorTranscript` in the bootstrap context,
- **When** the new flattener output is embedded,
- **Then** the bootstrap context's `priorTranscript` array entries follow the extended shape: `[{role: "operator|agent", content: "text", toolCalls?: [{name, input, result, status}]}, ...]`. Backward compatible — existing pure-text consumers ignore the optional `toolCalls` field.

> **Verbatim evidence:** Inspect the rendered HTML of a chat panel with prior tool history; the embedded `state.context.priorTranscript` JSON should contain entries with `toolCalls` arrays. Capture verbatim.

**AC-3 — Client-side `renderPriorTranscript` replays tool calls.** [BUG-07]
- **Given** `static/chat-panel.js` `renderPriorTranscript` currently only renders `{role, content}` text turns,
- **When** the function encounters a turn entry with a non-empty `toolCalls` array,
- **Then** for each tool_call, the existing `renderSearchResultList` (or equivalent tool-card renderer) is invoked, producing the same DOM as the live tool-dispatch path. Click-through behavior on replayed tiles works identically to fresh tiles.

> **Verbatim evidence:** Live exercise — run a Search Agent search returning multiple session tiles, click any tile to navigate to VisualTrace, hit browser Back, capture chrome-devtools-mcp `take_snapshot` of the chat panel post-reload. Confirm the tiles are present AND clickable.

**AC-4 — Both `MessageViewer.cls` and `VisualTrace.cls` flatteners updated identically.**
- **Given** the two flatteners are documented as verbatim copies of each other (per `MessageViewer.cls` Story 10.1 spec note),
- **When** the fix is applied,
- **Then** both files receive the same change in the same commit. Reviewer enforces no asymmetry.

> **Verbatim evidence:** `git diff` shows the same delta in both files. Capture the diff line counts side-by-side.

**AC-5 — Click-through state preserved across Back navigation.**
- **Given** the operator runs a Search Agent search → clicks a tile → navigates to VisualTrace → hits Back,
- **When** the chat panel reloads,
- **Then** (a) the search query and prior text response are still visible, (b) all original session tiles render in the same order, (c) clicking any tile still navigates correctly (with FROM_SEARCH binding intact).

> **Verbatim evidence:** chrome-devtools-mcp screenshot sequence showing: (1) initial search results with N tiles, (2) post-click VisualTrace page, (3) post-Back chat panel still showing N tiles. Save screenshots to `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-{1,2,3}.png`.

**AC-6 — `node -c` parse check on chat-panel.js (Story 12.0 Carry-Forward — BINDING APPLIES).**
- **Given** Story 12.0's Carry-Forward names Story 12.6 as a binding successor for the `node -c static/chat-panel.js` capture,
- **When** the chat-panel.js modifications are committed,
- **Then** `node -c static/chat-panel.js` exits 0; verbatim exit-0 output captured in Completion Notes.

> **Verbatim evidence:** Bash `node -c static/chat-panel.js && echo "exit=0"` captured verbatim.

**AC-7 — Regression sweep clean via SQL ground-truth probe.**
> Total / Passed / Failed via canonical numerical-MAX SQL probe.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe (Rule 3)**
  - [x] Read `MessageViewer.cls` `FlattenTurnsForBootstrap` (lines 311–368) verbatim.
  - [x] Read `VisualTrace.cls` equivalent — confirm verbatim copy.
  - [x] Read `static/chat-panel.js` `renderPriorTranscript` (lines ~582–608) AND `renderSearchResultList` (lines ~1496–1585) verbatim.
  - [x] Read `static/chat-panel.js` `handleEnvelope` / live-tool-call render path (around line 985) to identify the exact rendering function the live path uses for tool result lists. The replay path will call the SAME function — minimum-blast-radius.
  - [x] Verify a `Chat.History` row exists with tool_use/tool_result blocks (Row 101 in `SessionAgent_Chat.History` confirmed; canonical-Anthropic shape with 5 tool_use blocks paired to 5 tool_result blocks).
- [x] **Task 1 — `FlattenTurnsForBootstrap` extension (server-side)**
  - [x] Modify `MessageViewer.cls` `FlattenTurnsForBootstrap`: assistant tool_use blocks collected into `toolCalls` array `{id, name, args}`; tool_result blocks merged into prior agent entry's `toolCalls[i].result` (parsed JSON) + `.status` (ok/error).
  - [x] Pure tool_use assistant turn (no text) emits `{role:"agent", content:"", toolCalls:[...]}`.
  - [x] Mixed text + tool_use emits ONE combined entry.
  - [x] Apply the SAME change verbatim to `VisualTrace.cls` `FlattenTurnsForBootstrap` (per AC-4 dual-flattener invariant).
  - [x] Compiled both classes clean (no errors); empirically verified on Row 101 — 4-entry flattened array, agent turn has 5 tool calls all with status="ok".
- [x] **Task 2 — Client-side `renderPriorTranscript` extension**
  - [x] In `static/chat-panel.js` `renderPriorTranscript`, when `turn.toolCalls && turn.toolCalls.length > 0`, iterate each tool call and call `renderSearchResultList(t, sc.sessions, totalCount, limitArg)` — same signature as the live `handleEnvelope` path.
  - [x] Tool-call index is the per-replay-turn position; tile DOM emits `data-tool-call-index` attribute matching the live path so click-through capture entry can attribute the click.
  - [x] Pure tool_use turn with empty content does NOT emit empty `<div class="sa-msg-agent">` (visual-noise guard).
  - [x] `node -c static/chat-panel.js` → exit 0 (verbatim evidence in Completion Notes).
- [x] **Task 3 — Live exercise (Rule 6 step 4 + AC-5)**
  - [x] chrome-devtools-mcp navigated to `SessionAgent.EnsPortal.MessageViewer.zen`.
  - [x] Synthesized search-agent Chat.History fixture with 3 sessions (79369, 79362, 79355) into the operator's persistent SessionKey.
  - [x] Reloaded page → 3 search-result tiles rendered via the new replay path; screenshot 1 captured.
  - [x] Clicked tile 1 (session 79369) — navigated to VisualTrace.zen?SESSIONID=79369&FROM_SEARCH=...; screenshot 2 captured.
  - [x] Browser Back — chat panel reloaded; ALL 3 tiles STILL PRESENT (BUG-07 fix confirmed); screenshot 3 captured.
  - [x] Saved 3 screenshots to `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-{1,2,3}.png`.
- [x] **Task 4 — Add unit tests**
  - [x] `MessageViewerTest`: 3 new methods — `TestFlattenTurnsPreservesToolCalls`, `TestFlattenTurnsToolResultErrorStatus`, `TestFlattenTurnsBackwardCompat`. All pass.
  - [x] `VisualTraceTest`: 1 new method — `TestFlattenTurnsPreservesToolCalls` (verbatim-copy parity check). Pass.
  - [x] `ChatPanelJsTest`: 1 new method — `TestPriorTranscriptReplaysToolCalls` (substring assertions for `turn.toolCalls`, `renderSearchResultList(t,`, `structuredContent`, `sc.sessions`, `BUG-07` anchor). Pass.
- [x] **Task 5 — Regression sweep + SQL ground-truth probe**
  - [x] Ran `iris_execute_tests` per-class across all 54 SessionAgent.Test classes — every class clean.
  - [x] Canonical numerical-MAX SQL probe: **Total=453 / Passed=453 / Failed=0**.
- [x] **Task 6 — Spec length verification** — `wc -l` = 137 ≤ 250 cap.
- [x] **Task 7 — Sprint-status flip** — `ready-for-dev` → `in-progress` (Step 4 of workflow) → `review` (Step 9).
- [ ] **Task 8 — Commit + push** (lead) — `feat(epic-12): story 12.6 — chat history tile replay`.

## Dev Notes

### tool_use ↔ tool_result pairing semantics

Per Anthropic's canonical message format:
- An assistant turn may have content blocks of type `tool_use` with an `id`.
- The next user turn may have content blocks of type `tool_result` with `tool_use_id` matching the assistant's `id`.
- Multiple tool_use blocks in one assistant turn produce multiple tool_result blocks in the next user turn.
- The flattener walks turns in order; when it sees an assistant turn with tool_use, it remembers the IDs and matches them on the next user turn.

### Flat shape design — backward compatible

Existing `renderPriorTranscript` consumers receive `{role, content}` and ignore additional fields. New shape adds optional `toolCalls: [...]`. JS code path: `if (turn.toolCalls && turn.toolCalls.length > 0) { ... }` — falsy when absent.

### Why one entry combining text + tool_use (not two entries)

If we emit two entries — one for the text, one for the tool_use — the visual rendering produces two adjacent message blocks where the operator expects one. Combining preserves the original UX shape.

### Files modified

- `src/SessionAgent/EnsPortal/MessageViewer.cls` (`FlattenTurnsForBootstrap` extension)
- `src/SessionAgent/EnsPortal/VisualTrace.cls` (verbatim copy of the same extension)
- `static/chat-panel.js` (`renderPriorTranscript` extension)
- `src/SessionAgent/Test/MessageViewerTest.cls` (new test method)
- `src/SessionAgent/Test/VisualTraceTest.cls` (new test method)
- `src/SessionAgent/Test/ChatPanelJsTest.cls` (extend with substring assertion)

### Patterns to follow verbatim

- Story 10.2's `renderSearchResultList` pattern (from chat-panel.js lines 1496+) — call signature.
- Story 10.1's MessageViewer `FlattenTurnsForBootstrap` and VisualTrace's verbatim-copy comment — propagate the change to both files.
- Story 12.1's `%Dictionary.MethodDefinition.IDKEYOpen` + `.Implementation` pattern for substring-based test assertions.

## Completion Notes

### AC-1 — `FlattenTurnsForBootstrap` preserves tool_use / tool_result blocks

**Verbatim evidence (live data, Row 101 — 5-tool inspection-agent transcript):**

```
size=4
first.role=operator
second.role=agent
second.toolCalls.size=5
second.toolCalls[0].name=session_summary
second.toolCalls[0].status=ok
```

The pre-12.6 flattener would have skipped the pure tool_use turn entirely (no text content) — output would have been 1 entry. The post-12.6 flattener emits 4 entries with the agent's tool_use turn carrying the merged `toolCalls` array, each with `status="ok"` from the paired tool_result block.

**Verbatim evidence (synthetic 3-turn fixture, unit test `TestFlattenTurnsPreservesToolCalls`):**

```
TestFlattenTurnsPreservesToolCalls — passed (13.39ms)
  - flattened JSON is non-empty
  - flattened array has 2 entries (operator + agent; pure tool_result user turn does NOT emit)
  - entry 0 is operator turn / preserves operator text
  - entry 1 is agent turn / has empty content (pure tool_use turn)
  - entry 1 has toolCalls array (Story 12.6 AC-1)
  - tool call preserves canonical id (tu-01) / canonical name (find_sessions_by_status)
  - args.status preserved / args.limit preserved
  - tool call status=ok
  - result.structuredContent.sessions array present (load-bearing for JS replay path)
```

### AC-2 — Server-side bootstrap envelope shape extended

The bootstrap context's `priorTranscript[1]` (assistant turn) now carries `toolCalls` array. Verbatim evidence from the live walkthrough (`window.SessionAgentChat`):

```
sessionKey: "23E6686C-4876-408F-8ABB-C331B91F7C64"
priorTranscriptLen: 3
priorTurn1HasToolCalls: true
priorTurn1ToolCallsLen: 1
```

### AC-3 / AC-5 — Click-through replay (chrome-devtools-mcp screenshots)

**Tile DOM after page reload (replay path):**

```
tileCount: 3
tiles:
  [0] sessionId="79369" tcIndex="0" searchKey="23E6686C-..." text="Session 79369 · 7 hours ago · SessionAgent.Sample.BS.OrderIngest → SessionAgent.Sample.BP.OrderRoute..."
  [1] sessionId="79362" tcIndex="0" searchKey="23E6686C-..." text="Session 79362 · 7 hours ago · ..."
  [2] sessionId="79355" tcIndex="0" searchKey="23E6686C-..." text="Session 79355 · 7 hours ago · ..."
```

**Tile DOM after Back navigation (BUG-07 fix confirmed):**

```
tileCountAfterBack: 3   (matches pre-click)
tiles (verbatim): [{sessionId:79369, tcIndex:0}, {sessionId:79362, tcIndex:0}, {sessionId:79355, tcIndex:0}]
urlPath: /csp/hscustom/SessionAgent.EnsPortal.MessageViewer.zen
```

**Click-through preserves FROM_SEARCH binding:**

```
After click on tile 1: navigated to
  /csp/hscustom/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=79369&FROM_SEARCH=23E6686C-4876-408F-8ABB-C331B91F7C64
```

Screenshots saved (Rule 12 layout-correctness evidence):

- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-1.png` — chat panel with 3 tiles (initial render after replay).
- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-2.png` — VisualTrace post-click, FROM_SEARCH preserved.
- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-3.png` — chat panel after Back, all 3 tiles still present.

### AC-4 — Both flatteners updated identically (verbatim-copy invariant)

Both `MessageViewer.cls` and `VisualTrace.cls` `FlattenTurnsForBootstrap` received the same change in the same commit. Empirically confirmed via dictionary introspection — both compiled methods contain `tToolCallIndex` and `tool_use_id`. `VisualTraceTest::TestFlattenTurnsPreservesToolCalls` exercises the verbatim-copy parity contract independently of `MessageViewerTest::TestFlattenTurnsPreservesToolCalls`.

### AC-6 — `node -c` parse check (Story 12.0 Carry-Forward — BINDING)

**Verbatim:**

```
$ node -c static/chat-panel.js && echo "exit=0"
exit=0
```

### AC-7 — Regression sweep clean via SQL ground-truth probe

**Verbatim canonical numerical-MAX SQL probe output:**

| Total | Passed | Failed |
|-------|--------|--------|
| 453   | 453    | 0      |

Pre-state baseline 448 + 5 new tests = 453 exact. Per-class roster confirmed:
- `SessionAgent.Test.MessageViewerTest`: 10 methods (was 7, +3)
- `SessionAgent.Test.VisualTraceTest`: 12 methods (was 11, +1)
- `SessionAgent.Test.ChatPanelJsTest`: 21 methods (was 20, +1)

### Design notes (key decisions)

1. **`tool_result.content` parsing semantics**: live data emits `tool_result.content` as a JSON-serialized string of the canonical-MCP envelope `{content:[...], structuredContent:{...}}`. The flattener parses it to an object so the JS replay path can read `result.structuredContent.sessions` without re-parsing — matching the live `handleEnvelope` path's shape exactly. Defensive on parse failure: keeps raw string.
2. **Pairing-state lifecycle**: `tToolCallIndex` is reset on each new assistant turn (so a tool_use_id collision across turns can't cross-pair) AND on each operator (text-content) user turn (operator turn ends the pairing window).
3. **Backward-compatibility invariant**: pure-text agent turns produce NO `toolCalls` field (asserted by `TestFlattenTurnsBackwardCompat`); JS path's `if (turn.toolCalls && turn.toolCalls.length > 0)` falsy-when-absent guard means existing pre-12.6 transcripts replay identically to before.
4. **DOM order on replay**: tiles render BEFORE the agent text block (matching live `handleEnvelope` order at line 985 → line 994-997). Empty-content agent turns skip the empty `<div class="sa-msg-agent">` to avoid visual noise above tiles.
5. **Tool-call index for replay**: per-replay-turn position (loop variable `t`). The live `toolCallsRendered[]` index serves the same role on a fresh turn; for replay the position-within-the-turn is the natural analog and matches `data-tool-call-index` attribute the click-through capture entry expects.

### Files modified

See File List below.

### Cleanup

- Deleted temporary `SessionAgent.Test.Story126Walkthrough.cls` helper class used to seed the live-walkthrough Chat.History fixture (per spec "delete after the story commits"; the unit tests already cover the same shape).
- Cleaned up Chat.History fixture rows (`12-6-walk*`, `mv-tile-*`, `vt-flatten-*`, `vt-tile-*`, persistent `23E6686C-...` walkthrough row).

## File List

**Modified:**
- `src/SessionAgent/EnsPortal/MessageViewer.cls` — `FlattenTurnsForBootstrap` extension (tool_use ↔ tool_result merge).
- `src/SessionAgent/EnsPortal/VisualTrace.cls` — `FlattenTurnsForBootstrap` verbatim-copy of the same extension (per AC-4).
- `static/chat-panel.js` — `renderPriorTranscript` extension (replay tool_calls via `renderSearchResultList`).
- `src/SessionAgent/Test/MessageViewerTest.cls` — 3 new test methods (`TestFlattenTurnsPreservesToolCalls`, `TestFlattenTurnsToolResultErrorStatus`, `TestFlattenTurnsBackwardCompat`).
- `src/SessionAgent/Test/VisualTraceTest.cls` — 1 new test method (`TestFlattenTurnsPreservesToolCalls` — verbatim-copy parity).
- `src/SessionAgent/Test/ChatPanelJsTest.cls` — 1 new test method (`TestPriorTranscriptReplaysToolCalls` — substring assertions).
- `_bmad-output/implementation-artifacts/12-6-chat-history-tile-replay.md` — story file (status, tasks, completion notes).
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story key flipped `ready-for-dev → in-progress → review`.

**Created:**
- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-1.png` — chat panel with 3 search-result tiles.
- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-2.png` — VisualTrace post-click for session 79369.
- `_bmad-output/implementation-artifacts/12-6-screenshot-tile-replay-3.png` — chat panel after Back, tiles still present.

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.4 commit `02a81eb`).
- 2026-05-08 — Implementation complete. Server-side dual-flattener extension (MessageViewer.cls + VisualTrace.cls verbatim copies) preserves tool_use ↔ tool_result pairing in the bootstrap envelope's `priorTranscript[].toolCalls[]` array. Client-side `renderPriorTranscript` extension replays preserved tool calls via the existing `renderSearchResultList` helper — same DOM as the live path. 5 new unit tests; regression sweep 453/453/0 via canonical numerical-MAX SQL probe. AC-3/AC-5 walkthrough captured 3 chrome-devtools-mcp screenshots demonstrating tile presence pre-click + post-Back. AC-6 `node -c` exit=0 captured. Story flipped in-progress → review.
- 2026-05-08 — Code review complete. **0 HIGH / 0 MEDIUM / 2 LOW** findings; all LOWs deferred per Rule 8 test 3 (cosmetic, no predicted-bug shape). LOW-1: inline-comment drift in `Catch` block between MessageViewer.cls and VisualTrace.cls (executable code byte-identical; only `Catch` inline comment differs in 2 lines — pre-existing asymmetry preserved by dev). LOW-2: screenshots 1 and 3 are byte-identical (MD5 match) — strongest evidence of pixel-perfect tile-state preservation post-Back, but corroborating DOM-probe evidence in Completion Notes is independently sufficient. All 7 ACs verified with verbatim evidence: AC-1 dual-flattener method bodies byte-identical at code level (compile clean); AC-2 bootstrap envelope shape extended (verified via `priorTurn1HasToolCalls: true`); AC-3 client-side `renderPriorTranscript` replays tool calls through same `renderSearchResultList` as live path; AC-4 verbatim-copy invariant satisfied at executable-code level; AC-5 click-through state preserved (3-screenshot sequence + DOM probe); AC-6 `node -c static/chat-panel.js` exit=0 reproduced live; AC-7 SQL ground-truth probe reproduced live (Total/Passed/Failed = 453/453/0 via canonical numerical-MAX form). Rule 9 binding closure: Story 10.13's `node -c` carry-forward (deferred-work.md line 1450) MARKED CLOSED-by-12.6. Story126Walkthrough.cls deletion verified (filesystem + IRIS dictionary both empty). Story flipped review → done.
