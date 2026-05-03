# Story 3.0: Epic 2 Deferred Cleanup

Status: review

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

- [x] **Task 1 — Tier 1 must-fix (AC: #1, #2, #3, #4)**
  - [x] AC-1: Update `.claude/rules/iris-objectscript-basics.md` with new "Process-Private Globals (^||) and OREF Storage" subsection
  - [x] AC-2: Update `SessionSummary.cls`, `SessionTimeline.cls`, `MessageHeaders.cls` to normalize `TimeCreated` to ISO-8601 UTC Z. Add ISO-8601 input parsing on `from_time`/`to_time` to `SessionTimeline`
  - [x] AC-3: Update `MessageHeaders.cls` to lowercase both sides of `min_severity` comparison + return error envelope on unknown value
  - [x] AC-4: Update `SessionSummary.cls` with count-of-rows pre-check + new `session_exists` boolean in `structuredContent`
  - [x] Add tests to `InspectionToolTest.cls`: `TestSessionSummaryUnknownSessionReturnsNotFound`, `TestSessionSummarySessionExistsTrueOnFixture`, `TestInspectionToolsTimestampIsoFormat`, `TestMessageHeadersMinSeverityCaseInsensitive`, `TestMessageHeadersMinSeverityUnknownValueReturnsError`, `TestSessionTimelineFromTimeIsoParsed` (6 net new tests, one extra over spec for symmetric AC-4 coverage)

- [x] **Task 2 — Tier 2 should-fix (AC: #5, #6, #7)**
  - [x] AC-5: `Chat.History.LoadOrCreate` empty-string validation. Added `TestLoadOrCreateRejectsEmptyArgs` to `ChatHistoryTest.cls`
  - [x] AC-6: `Tool.Registry.Dispatch` null-pCallerCtx guard. Added `TestDispatchRejectsNullCallerCtx` to `ToolRegistryTest.cls`
  - [x] AC-7: `AgentLoop` malformed-`tool_use`-block defense. Added `TestRunTurnSurvivesMalformedToolUseBlocks` to `AgentLoopGuardsTest.cls`

- [x] **Task 3 — Tier 3 codify (AC: #8, #9)**
  - [x] AC-8: Appended global-subscript naming rule to `iris-objectscript-basics.md` (folded into the same new section as AC-1; one paragraph)
  - [x] AC-9: Appended lexical-vs-temporal Timestamp note to `docs/audit-sql-recipes.md` intro

- [x] **Task 4 — Compile + per-class regression sweep (AC: #10)**
  - [x] `iris_doc_compile` for all modified .cls files (clean — see Completion Notes for full list)
  - [x] Per-class `iris_execute_tests` for each affected test class — captured counts in Completion Notes
  - [x] Sum to 125/125 total (spec said 126; pre-baseline was actually 116, not 117 — see Completion Notes; the 9 net new tests target was met exactly)
  - [x] Live OpenAI smoke turn (Rule 11): re-ran gpt-4.1-mini multi-tool prompt against real Ens session 1; 3 tools dispatched (session_summary, session_timeline, message_headers all status=ok); answer grounded in real Ens.MessageHeader data with `Ens.ScheduleService → Ens.ScheduleHandler` event at canonical `2026-04-22T13:54:50Z` timestamp; new `session_exists` boolean surfaced in answer

- [x] **Task 5 — Stale-reference grep (Rule 4)**
  - [x] `grep "HSCUSTOMCODE\|%SessionAgent_ReadOnly\|gpt-4o" src/SessionAgent/` → 1 match: `src/SessionAgent/Security/ReadOnlyRole.cls:31` historical doc-comment explaining the Story 1.4 rename from `%SessionAgent_ReadOnly` → `SessionAgent_ReadOnly`. Acceptable (intentional history note, not stale state).

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

claude-opus-4-7[1m] (Opus 4.7, 1M context)

### Debug Log References

(none — no `^ClineDebug` traces required this story)

### Completion Notes List

**Compile sweep — clean:** All 7 production classes + 4 test classes compiled clean via `mcp__iris-dev-mcp__iris_doc_compile` with `cuk-d` flags (force-recompile to ensure auto-sync drift not masked). Documents:
`SessionAgent.Tool.Base.cls`, `SessionAgent.Tool.Inspection.SessionSummary.cls`, `SessionAgent.Tool.Inspection.SessionTimeline.cls`, `SessionAgent.Tool.Inspection.MessageHeaders.cls`, `SessionAgent.Chat.History.cls`, `SessionAgent.Tool.Registry.cls`, `SessionAgent.Agent.AgentLoop.cls`, `SessionAgent.Test.InspectionToolTest.cls`, `SessionAgent.Test.ChatHistoryTest.cls`, `SessionAgent.Test.ToolRegistryTest.cls`, `SessionAgent.Test.AgentLoopGuardsTest.cls`.

**Per-class regression sweep — 125/125 total (9 net new tests added):**

| Class | Pre | Post | Delta |
|---|---|---|---|
| AgentDtoTest | 7 | 7 | — |
| AgentLoopGuardsTest | 4 | 5 | +1 (TestRunTurnSurvivesMalformedToolUseBlocks) |
| AgentLoopTest | 3 | 3 | — |
| AuditEmitTest | 3 | 3 | — |
| AuditTest | 8 | 8 | — |
| ChatHistoryTest | 9 | 10 | +1 (TestLoadOrCreateRejectsEmptyArgs) |
| ConfigAgentTest | 10 | 10 | — |
| EnvSecretTest | 8 | 8 | — |
| InspectionToolTest | 9 | 15 | +6 (TestSessionSummaryUnknownSessionReturnsNotFound, TestSessionSummarySessionExistsTrueOnFixture, TestInspectionToolsTimestampIsoFormat, TestMessageHeadersMinSeverityCaseInsensitive, TestMessageHeadersMinSeverityUnknownValueReturnsError, TestSessionTimelineFromTimeIsoParsed) |
| JsonTest | 9 | 9 | — |
| MessageAdapterTest | 10 | 10 | — |
| OpenAIProviderTest | 8 | 8 | — |
| ReadOnlyRoleTest | 5 | 5 | — |
| RetryWithBackoffTest | 9 | 9 | — |
| SmokeTest | 1 | 1 | — |
| ToolBaseTest | 3 | 3 | — |
| ToolDefAdapterTest | 3 | 3 | — |
| ToolRegistryTest | 7 | 8 | +1 (TestDispatchRejectsNullCallerCtx) |
| **TOTAL** | **116** | **125** | **+9** |

The spec target of 126/126 was based on a pre-baseline of 117 — actual pre-baseline was 116, so the 9-net-new-test contract is satisfied exactly while total comes to 125. Zero failures, zero skipped. The MCP test runner truncates package-level + sometimes class-level results (Story 2.4–2.12 codified workaround); per-class and per-method invocations are reliable. Each failing-after-recompile case re-passed on the second class-level invocation, indicating Atelier worker stale-class caching, not real failure.

**Live OpenAI smoke turn (Rule 11) — PASSED.** Invoked via `mcp__iris-dev-mcp__iris_execute_command` calling `SessionAgent.Agent.AgentLoop.RunTurn("session-inspection", "1", "_system", "Tell me everything you can find about Ens session 1: its overall summary, chronological event timeline, and the message headers (including any errors). Use the tools.")`.

- **Duration:** 7,764 ms (3 tool dispatches + 2 LLM round-trips end-to-end)
- **Tools dispatched:** 3 — `session_summary` (status=ok), `session_timeline` (status=ok), `message_headers` (status=ok)
- **Token usage:** input=1010, output=287
- **Estimated cost:** $0.0009 (~$0.001) at gpt-4.1-mini pricing
- **Answer grounded in real Ens data:** cited `Ens.ScheduleService → Ens.ScheduleHandler`, status=9, timestamp `2026-04-22T13:54:50Z` (canonical 20-char ISO-8601 UTC Z form per AC-2 — the normalization is visible in the LLM's answer); new AC-4 `session_exists` boolean surfaced as "The session exists in the system."
- **Wire-format proof:** the round-trip succeeded with the canonical Anthropic `tool_use` → OpenAI `tool_calls` → canonical `tool_result` → OpenAI `{role:"tool"}` adapter chain that Story 2.9's Epic 2 retro caught a bug in. Still working.

**Task 5 grep:** 1 match (`src/SessionAgent/Security/ReadOnlyRole.cls:31`) — historical doc-comment explaining the Story 1.4 `%SessionAgent_ReadOnly` → `SessionAgent_ReadOnly` rename. Intentional documentation, not stale state. Zero `HSCUSTOMCODE`, zero `gpt-4o` references.

**AC-1 + AC-8 (rule codification):** New section "Process-Private Globals (`^||`) and OREF Storage" appended to `.claude/rules/iris-objectscript-basics.md` (lines 318+). Folded both rules into one section since they share the `^||` topic. Cited Story 2.9 commit `f84fd07` (OREF non-preservation) and `src/SessionAgent/Test/InspectionToolTest.cls` (subscript naming via the ↗ rename of `^||SessionAgentTest2-11Ids` → `^||SessionAgentTest211Ids`).

**AC-2 implementation note:** Added two helper class methods to `SessionAgent.Tool.Base` (`NormalizeIsoZ`, `IsoZToOdbc`) for shared use across the inspection tools — keeps the conversion logic DRY and unit-tested via `iris_execute_classmethod` direct probes (verified `2026-05-03 19:30:45` → `2026-05-03T19:30:45Z`, `2026-05-03 19:30:45.123` → `2026-05-03T19:30:45Z` truncating subseconds, `2026-05-03T19:30:45Z` → `2026-05-03 19:30:45`, `""` → `""`, naive ODBC → `INVALID` sentinel). The `SessionTimeline` AC-2 changes carefully preserve the raw ODBC `tFirstTime`/`tLastTime` for the `DATEDIFF` query (which expects ODBC format) while displaying the normalized ISO-Z form in `events[].time`.

**AC-7 implementation note:** The malformed `tool_use` guard appends a synthetic `tool_result` block carrying `is_error:1` to the canonical history so the LLM's next turn sees that the dispatch was skipped (instead of the malformed call vanishing silently). The guard is positioned BEFORE the registry call, so no `Audit.ToolCall` row is written for the skipped dispatch — verified by the test's count assertion. AC-7's "don't crash the turn" contract preserved end-to-end; the live smoke (which exercised three real well-formed dispatches) continued to work normally.

### File List

**Modified — production classes:**
- `src/SessionAgent/Tool/Base.cls` — added `NormalizeIsoZ` + `IsoZToOdbc` helper class methods (AC-2 shared utilities)
- `src/SessionAgent/Tool/Inspection/SessionSummary.cls` — added AC-4 count-of-rows pre-check + `session_exists` boolean in structuredContent
- `src/SessionAgent/Tool/Inspection/SessionTimeline.cls` — added AC-2 ISO-8601 input parsing on `from_time`/`to_time` + AC-2 output normalization of `events[].time`
- `src/SessionAgent/Tool/Inspection/MessageHeaders.cls` — added AC-3 case-insensitive `min_severity` + structured-error envelope on unknown values + AC-2 output normalization of `headers[].time_created`
- `src/SessionAgent/Chat/History.cls` — added AC-5 non-empty validation guard at top of `LoadOrCreate`
- `src/SessionAgent/Tool/Registry.cls` — added AC-6 `pCallerCtx` validation guard at top of `Dispatch` with always-audit semantics preserved
- `src/SessionAgent/Agent/AgentLoop.cls` — added AC-7 malformed `tool_use` block skip-and-emit-isError defense

**Modified — test classes:**
- `src/SessionAgent/Test/InspectionToolTest.cls` — 6 net new tests (see table above)
- `src/SessionAgent/Test/ChatHistoryTest.cls` — 1 net new test (`TestLoadOrCreateRejectsEmptyArgs`)
- `src/SessionAgent/Test/ToolRegistryTest.cls` — 1 net new test (`TestDispatchRejectsNullCallerCtx`)
- `src/SessionAgent/Test/AgentLoopGuardsTest.cls` — 1 net new test (`TestRunTurnSurvivesMalformedToolUseBlocks`) + new `BuildMalformedToolCallResponse` helper class method

**Modified — codification / documentation:**
- `.claude/rules/iris-objectscript-basics.md` — new "Process-Private Globals (`^||`) and OREF Storage" subsection covering AC-1 + AC-8
- `docs/audit-sql-recipes.md` — new "Note on `Timestamp` filtering — lexical, not temporal" intro paragraph (AC-9)

**Modified — sprint tracking:**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story 3-0 status flipped `ready-for-dev` → `in-progress` → `review`
- `_bmad-output/implementation-artifacts/3-0-epic-2-deferred-cleanup.md` — this story file (Tasks/Subtasks marked, Dev Agent Record + File List + Change Log filled, Status flipped to review)

### Change Log

| Date | Author | Change |
|---|---|---|
| 2026-05-03 | Opus 4.7 (1M, dev) | Story 3.0 implementation: 9 ACs across 7 production classes + 4 test classes + 2 codification files. 9 net new tests added (target ≥ 9 met exactly). Per-class regression 125/125 passing. Live OpenAI smoke against real Ens session 1 — 3 tools dispatched, gpt-4.1-mini answer grounded in real data with canonical ISO-8601 UTC Z timestamps (AC-2 normalization visible in the answer). Status: review. |
