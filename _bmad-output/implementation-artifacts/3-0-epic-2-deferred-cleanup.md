# Story 3.0: Epic 2 Deferred Cleanup

Status: ready-for-dev

## Story

As the **lead** entering Epic 3,
I want every Epic 2 retro-flagged carry-forward item plus the Tier 1 / Tier 2 / Tier 3 deferred-work items locked into a single cleanup story under the new Rule 8 ("fix now is the default") regime,
so that Epic 3's first-delight UI work (Story 3.1 onward) builds on a backend hardened against the predicted-bug-shape gaps that Epic 2's review pipeline flagged but didn't close.

This is the **mandatory Epic-N retrospective-review gate** per [`docs/epic-cycle-teams.md` §"Retrospective Review & Story X.0 Creation"](../../docs/epic-cycle-teams.md#retrospective-review--story-x0-creation-mandatory-gate). The Epic 2 retrospective at [`epic-2-retro-2026-05-03.md`](epic-2-retro-2026-05-03.md) §"Story 3.0 (Epic 3 cleanup)" supplied the explicit triage decisions.

## Acceptance Criteria

ACs are grouped into three tiers per the Epic 2 retro Story 3.0 must-fix table.

### Tier 1 — must-fix (operator-visible bug shape OR Epic 3 blocker)

**AC-1 (item A) — `^||` no-OREF-preserve rule codified.** Append a new subsection to `.claude/rules/iris-objectscript-basics.md` titled "Process-Private Globals (^||) and OREF Storage" stating: process-private globals do NOT preserve `%RegisteredObject` / `%Persistent` OREFs across access — `Set ^||X = oref` then `Write $IsObject(^||X)` returns 0 (the OREF round-trips as the string `"oref@<class>"`). For test or back-channel state that needs to survive a `^||` round-trip, store class-name + `%DynamicObject.%ToJSON()` config and re-instantiate on read. Cite Story 2.9 as the originating empirical finding (commit `f84fd07`).

**AC-2 (item B) — Inspection tools normalize `Ens.MessageHeader.TimeCreated` to ISO-8601 UTC Z.** All three tools (`SessionSummary`, `SessionTimeline`, `MessageHeaders`) must convert the server-local ODBC timestamp string into the same ISO-8601 UTC format the audit ledger uses (`$Translate($ZDateTime($ZTimeStampH(<value>),3,1)," ","T")_"Z"` or equivalent). Output shape contract: any timestamp field in `structuredContent` is exactly 20 characters, ends with `"Z"`, has `"T"` at character 11. `SessionTimeline.from_time` / `to_time` input args MUST also accept the same ISO-8601 UTC Z format and convert internally; if an operator passes a naive ODBC string, return a structured error envelope ("from_time must be ISO-8601 UTC, e.g. 2026-05-03T19:30:00Z").

**AC-3 (item C) — `MessageHeaders.min_severity` filter is case-insensitive.** Lowercase both sides of the comparison (or use IRIS SQL `%LOWER()`/`%UPPER()` wrapping). Acceptable input values: `info`, `warning`, `error` in any case; whitespace-trimmed. Unknown values return a structured error envelope listing accepted values, NOT a silent no-op.

**AC-4 (item D) — `SessionSummary` returns "session not found" envelope for nonexistent `session_id`.** Add a count-of-rows pre-check via `SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ?`. If count is 0, return `{isError:0, content:[{type:text, text:"Session <id> has no rows in Ens.MessageHeader (it may not exist or may have been purged)"}], structuredContent:{message_count:0, error_count:0, session_exists:false, root_message_class:""}}`. Add a new top-level boolean `session_exists` to `SessionSummary`'s output shape so the LLM can distinguish "missing" from "empty". Update Dev Notes for the LLM (system prompt or tool description) so the model knows to interpret `session_exists:false` as "no such session".

### Tier 2 — should-fix (Rule 8 fix-now defaults; predicted-bug shape)

**AC-5 (item E) — `Chat.History.LoadOrCreate` validates non-empty parameters.** If any of `pAgentName`, `pSessionKey`, `pPortalUser` is empty, return `$$$NULLOREF` with `pStatus = $$$ERROR($$$GeneralError, "LoadOrCreate: pAgentName / pSessionKey / pPortalUser must all be non-empty")`. Existing callers (test fixtures, AgentLoop) all pass real values so backward-compat preserved.

**AC-6 (item F) — `Tool.Registry.Dispatch` validates `pCallerCtx`.** If `pCallerCtx` is `$$$NULLOREF` or not an instance of `SessionAgent.Agent.CallerContext`, populate `pResult` with `{isError:1, content:[{type:text, text:"Internal: dispatch invoked without CallerContext"}]}`, write the audit row with `IsError=1` per Rule 8 Fix #5 (always-audit semantics still hold), and return `$$$OK` (envelope-based). NEVER throw.

**AC-7 (item G) — AgentLoop defends against malformed `tool_use` blocks from the provider.** When iterating `tProvResp.Content` for `tool_use` blocks (per `AgentLoop.cls:241-296`), skip blocks where `id` is empty/missing OR `input` is not a `%DynamicObject` — append a `tool_result` block with `isError:1` content describing the malformed block, and continue the loop. Don't crash the turn; don't dispatch with garbage args.

### Tier 3 — codify (free)

**AC-8 (item H) — Process-private global subscript naming rule codified.** Append to `.claude/rules/iris-objectscript-basics.md` (alongside AC-1's new subsection): process-private global subscripts must follow ObjectScript identifier rules — letters, digits, `%`, no hyphens (`-` is the concatenation operator). Pattern: camelCase or snake_case for multi-word subscripts. Cite Story 2.11's `^||SessionAgentTest2-11Ids` failure as the originating finding.

**AC-9 (item I) — `docs/audit-sql-recipes.md` lexical-vs-temporal note.** Append a one-paragraph operator note to the recipe doc's intro: `Audit.LlmCall.Timestamp` and `Audit.ToolCall.Timestamp` are stored as `%String` (not `%TimeStamp`), so `WHERE Timestamp >= ?` performs a lexical (string) comparison. The recipes work correctly only when the parameter is in the same fixed-width 20-character ISO-8601 form the rows use (`YYYY-MM-DDTHH:MM:SSZ`). A non-padded form like `2026-5-3T00:00:00Z` sorts incorrectly. Use `$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"` to construct.

### AC-10 — Compile + tests + regression intact

- `mcp__iris-dev-mcp__iris_doc_compile` clean for all modified classes (3 inspection tools + Chat.History + Tool.Registry + AgentLoop + InspectionToolTest + ChatHistoryTest + ToolRegistryTest + AgentLoopTest).
- New tests added per AC (see Tasks below): expect ≥ 9 net new tests across the affected test classes.
- Per-class regression sweep: 117 + 9 = **126/126** total.
- Live OpenAI multi-tool turn against Ens session 1 still works (the integration the Epic 2 retro proved out).

## Tasks / Subtasks

- [ ] **Task 1 — Tier 1 must-fix (AC: #1, #2, #3, #4)**
  - [ ] AC-1: Update `.claude/rules/iris-objectscript-basics.md` with new "Process-Private Globals (^||) and OREF Storage" subsection
  - [ ] AC-2: Update `SessionSummary.cls`, `SessionTimeline.cls`, `MessageHeaders.cls` to normalize `TimeCreated` to ISO-8601 UTC Z. Add ISO-8601 input parsing on `from_time`/`to_time` to `SessionTimeline`
  - [ ] AC-3: Update `MessageHeaders.cls` to lowercase both sides of `min_severity` comparison + return error envelope on unknown value
  - [ ] AC-4: Update `SessionSummary.cls` with count-of-rows pre-check + new `session_exists` boolean in `structuredContent`
  - [ ] Add tests to `InspectionToolTest.cls`: `TestSessionSummaryUnknownSessionReturnsNotFound`, `TestSessionSummaryTimestampIsoFormat`, `TestMessageHeadersMinSeverityCaseInsensitive`, `TestMessageHeadersMinSeverityUnknownValueReturnsError`, `TestSessionTimelineFromTimeIsoParsed`

- [ ] **Task 2 — Tier 2 should-fix (AC: #5, #6, #7)**
  - [ ] AC-5: `Chat.History.LoadOrCreate` empty-string validation. Add `TestLoadOrCreateRejectsEmptyArgs` to `ChatHistoryTest.cls`
  - [ ] AC-6: `Tool.Registry.Dispatch` null-pCallerCtx guard. Add `TestDispatchRejectsNullCallerCtx` to `ToolRegistryTest.cls`
  - [ ] AC-7: `AgentLoop` malformed-`tool_use`-block defense. Add `TestRunTurnSurvivesMalformedToolUseBlocks` to `AgentLoopTest.cls` (or `AgentLoopGuardsTest.cls` per the existing split)

- [ ] **Task 3 — Tier 3 codify (AC: #8, #9)**
  - [ ] AC-8: Append global-subscript naming rule to `iris-objectscript-basics.md` (one paragraph)
  - [ ] AC-9: Append lexical-vs-temporal Timestamp note to `docs/audit-sql-recipes.md` intro

- [ ] **Task 4 — Compile + per-class regression sweep (AC: #10)**
  - [ ] `iris_doc_compile` for all modified .cls files
  - [ ] Per-class `iris_execute_tests` for each affected test class — capture counts in Completion Notes
  - [ ] Sum to 126/126 total
  - [ ] Live OpenAI smoke turn (Rule 11): re-run the Epic 2 retro empirical battery's gpt-4.1-mini multi-tool prompt, confirm answer still grounds in real Ens data

- [ ] **Task 5 — Stale-reference grep (Rule 4)**
  - [ ] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly\|gpt-4o" src/SessionAgent/` → expect 0 (we already cleaned `gpt-4o` post-Epic-2; this is the regression gate)

## Dev Notes

### Rule 8 application — this story is the test

This is the first story under the new Rule 8 regime. Items E/F/G in particular ARE the predicted-bug-shape pattern Rule 8 was designed to catch. If the dev/reviewer pipeline successfully fixes them in this story (instead of deferring again), Rule 8 is working. If any of E/F/G ends up re-deferred in this story's review, the rule is failing in its first application — escalate to user immediately.

### Rule 1 spec-length watch

This spec is approaching the 250-line cap. If implementation requires more spec elaboration (e.g., AC-2's timestamp normalization details), trim Tier 3 first (those are the cheapest to defer to Story 4.0).

### Auto-sync workflow + typed MCPs

Same as all Epic 2 stories. Edit/Write the .cls files locally; auto-sync pushes; `iris_doc_compile` to capture errors; `iris_execute_tests` per-class.

### Order of operations recommended

1. AC-1 + AC-8 first (codification — touches one rule file, low risk, prevents future re-discovery).
2. AC-2 / AC-3 / AC-4 next (inspection tool changes — Tier 1 operator-visible).
3. AC-5 / AC-6 (boundary guards — independent of each other).
4. AC-7 (AgentLoop defense — has its own outer Try/Catch as backstop, so safest to land last).
5. AC-9 last (doc-only).
6. Empirical battery (Task 4) at end.

### Sources

- [`epic-2-retro-2026-05-03.md`](epic-2-retro-2026-05-03.md) §"Story 3.0 (Epic 3 cleanup)" — explicit 9-item triage table.
- [`deferred-work.md`](deferred-work.md) — the original review entries with full context per item.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 8 — defer threshold raised; Rule 9 — predicted-bug deferrals binding; Rule 11 — live integration smoke test mandatory.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — target file for AC-1 + AC-8 codifications.
- [`docs/audit-sql-recipes.md`](../../docs/audit-sql-recipes.md) — target for AC-9 codification.

## Dev Agent Record

### Agent Model Used

(to be filled by dev agent)

### Debug Log References

(none expected)

### Completion Notes List

(to be filled — must include compile output, per-class test counts (target 126/126), live OpenAI smoke transcript, Task 5 grep result)

### File List

(to be filled — expected: 3 inspection tools (UPDATE), Chat.History (UPDATE), Tool.Registry (UPDATE), AgentLoop (UPDATE), 4 test classes (UPDATE), iris-objectscript-basics.md (UPDATE), audit-sql-recipes.md (UPDATE))

### Change Log

(to be filled by dev + reviewer)
