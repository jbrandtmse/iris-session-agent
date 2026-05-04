# Story 4.3: `GetMessageDetail`

Status: done

## Story

As an **Operator** asking the Inspection Agent for a full single-message readout,
I want a `get_message_detail` tool that bundles a message's `Ens.MessageHeader` row + a body summary (via the `get_message_body` rendering pathway) + linked rule-log decisions,
so that the agent has a one-shot tool for single-message deep-dives without dispatching three separate tools ([PRD FR3 supplemental](../planning-artifacts/prd.md)) and answers about a specific message arrive in fewer agent iterations.

This composes Stories 4.1 (`RuleLog`) and 4.2 (`GetMessageBody`) — the body-rendering path is reused via direct ClassMethod call into `GetMessageBody.Invoke`. Per architecture G2, ladder extraction to a shared `SessionAgent.Body.DispatchLadder` helper is deferred to Epic 8 Story 8.6; for Story 4.3 the direct call is the cleanest reuse path with no premature abstraction (Rule 8).

## Carry-forward from prior deferred-work entries (Rule 9)

`grep "Story 4\.3" deferred-work.md` → no matches. No binding carry-forwards.

## Acceptance Criteria

### AC-1 — `GetMessageDetail` class declaration

Create [`src/SessionAgent/Tool/Inspection/GetMessageDetail.cls`](../../src/SessionAgent/Tool/Inspection/GetMessageDetail.cls) extending `SessionAgent.Tool.Base`. Class must declare:

- `Parameter ToolName As %String = "get_message_detail";`
- `Parameter Description As %String = "Return full message header + body summary + linked rule-log decisions for a single message.";`
- `Parameter MutatesState As %Boolean = 0;`
- HTML/DocBook doc-comment banner per [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Comments".

### AC-2 — `GetMessageDetail.GetInputSchema()`

`additionalProperties: false`, with:

- Required: `message_id` (string)

(No optional inputs in v1 — the tool is a one-shot readout.)

### AC-3 — `GetMessageDetail.Invoke()` — three-part composition

1. **Pre-validation:** `message_id` non-empty → structured error envelope per FR37.
2. **Header read (Step 1):** parameterized `SELECT ID, %EXACT(MessageBodyClassName), MessageBodyId, %EXACT(SourceConfigName), %EXACT(TargetConfigName), Status, TimeCreated, IsError, SessionId FROM Ens.MessageHeader WHERE ID = ?`. If no row → `{render_strategy:"header_not_found", header:{}, body_summary:"", body_repr:"", rule_decisions:[]}` envelope. Normalize `TimeCreated` to ISO-8601 UTC Z (Story 3.0 AC-2 pattern).
3. **Body read (Step 2):** call `Do ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, pBodyArgs, .tBodyResult)` where `pBodyArgs = {"message_id": pJsonArgs.%Get("message_id"), "format": "summary"}`. Extract from `tBodyResult.structuredContent`: `body_class`, `body_id`, `render_strategy`, `body_repr`, `truncated`. Mirror them into the response with prefix `body_` (e.g., `body_render_strategy`). If `tBodyResult.isError` is true (validation failure inside GetMessageBody — should not happen since pre-validation already passed, but defense-in-depth), surface its `content[0].text` into a `body_error` field but DON'T fail the whole detail call.
4. **Rule decisions read (Step 3):** parameterized `SELECT ID, %EXACT(RuleName), %EXACT(Component), %EXACT(ReturnValue), TimeExecuted, %EXACT(Reason) FROM Ens_Rule.Log WHERE TriggeringMessageHeader = ?` (or whatever the actual column is — verify via Task 0 probe). Apply LIMIT 100. Normalize `TimeExecuted` to ISO-8601 UTC Z. Each row populates `{id, rule_name, component, return_value, time_executed, reason}`.
5. **Compose `structuredContent`:** `{message_id, header: {id, source_config_name, target_config_name, status, time_created, is_error, session_id, body_class, body_id}, body_summary: (text from tBodyResult.content[0].text), body_repr: (...), body_render_strategy: (...), body_truncated: (...), body_class: (...), body_id: (...), rule_decisions: [...], rule_decision_count: N}`.
6. **Compose `content[0].text`:** 2–3 line operator summary like *"Message <id> from <source_config_name> to <target_config_name> (status: <status>, errored: yes/no). Body: <body_render_strategy>, <body_summary>. <N> rule decision(s) triggered."*
7. **No throws:** outer Try/Catch around all three steps; any unexpected exception → `{render_strategy:"composition_error", error_text:...}` with `isError:1`.

### AC-4 — Test coverage

Add tests to a new [`src/SessionAgent/Test/GetMessageDetailTest.cls`](../../src/SessionAgent/Test/GetMessageDetailTest.cls). Minimum 6 named tests:

- `TestFullPayloadHeaderBodyRuleDecisions` — fixture: a message with header + Ens.MessageBody-derived body + 2 fixture rule-log rows for that triggering message. Asserts header populated, body_render_strategy="ens_message_body", rule_decision_count=2.
- `TestNoBodyReturnsEmptyBodyRepr` — fixture: header with `MessageBodyId=""`. Asserts `body_render_strategy="no_body"`, `body_repr=""`, summary text notes the absence.
- `TestNoRuleDecisionsReturnsEmptyArray` — fixture: header without any rule-log rows. Asserts `rule_decisions` is `[]`, `rule_decision_count=0`.
- `TestMissingMessageIdReturnsError` — FR37 envelope.
- `TestUnknownMessageIdReturnsHeaderNotFound` — Asserts `render_strategy="header_not_found"`.
- `TestRegistryListToolsIncludesGetMessageDetail` — `Tool.Registry.ListTools()` includes `get_message_detail` with the AC-2 schema.

Net new tests: **6**. Pre-baseline: 169/169 (Story 4.2 reviewer per-class sweep). Target: **175/175** post-story.

### AC-5 — Compile + tests + regression + Rule 6 sharpened live test + Rule 12 visual gate

- `iris_doc_compile` clean for `GetMessageDetail.cls` + `GetMessageDetailTest.cls`. Per-class regression sweep 175/175.
- **Rule 6 sharpened live test:** sample production must have a real header reachable. Run a turn against session 528 asking *"Tell me everything about message N — header, body, and any rules that fired"*. Verify the agent dispatches `get_message_detail` (NOT three separate tools) and grounds the answer in the composed structuredContent.
- **Rule 12 visual gate:** chrome-devtools-mcp screenshot of the rendered tool-card for `get_message_detail` against a real sample-production message. Verify the composed envelope renders cleanly (header fields visible in expanded card, body_summary readable, rule_decisions list rendered without overflow). File as `_bmad-output/implementation-artifacts/4-3-rule-12-visual-pass-1.png`. If browser locked, escalate (do NOT substitute).

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes**
  - [x] `iris_sql_execute` probe — `TriggeringMessageHeader` is **NOT** the column name (SQLCODE -29 "Field 'TRIGGERINGMESSAGEHEADER' not found"). Per `irislib/Ens/Rule/Log.cls` line 62, the actual column is **`CurrentHeaderId`** (`%String(MAXLEN=128)`). Story 4.1's `RuleLog.cls` already maps it via `%EXACT(CurrentHeaderId) AS triggering_message_id`.
  - [x] Read `irislib/Ens/Rule/Log.cls` — 15 columns: ID, ActivityName, ConfigName, CurrentHeaderId, DebugId, EffectiveBegin, EffectiveEnd, ErrorMsg, IsError, Reason, ReturnValue, RuleName, RuleSet, SessionId, TimeExecuted. Spec's `Component` maps to `ConfigName` per Story 4.1 precedent.
  - [x] Read `GetMessageBody.cls` Invoke signature — `Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status`. Direct-call shape matches spec — pass `pCallerCtx` straight through, build `pBodyArgs` as a literal `%DynamicObject` with `message_id` + `format:"summary"`, capture output `%DynamicObject`.

- [x] **Task 1 — `GetMessageDetail.cls` (AC: #1, #2, #3)**
  - [x] Class declaration + parameters per AC-1
  - [x] `GetInputSchema()` per AC-2
  - [x] `Invoke()` three-part composition per AC-3 — kept helper-method-free; the three SQL/dispatch steps inlined. `Component` mapped to `ConfigName`, `TriggeringMessageHeader` mapped to `CurrentHeaderId` per Task 0.
  - [x] `iris_doc_compile` clean (smoke probe verified composition: header 741 → ens_message_body body, 0 rule decisions; missing id 99999999 → header_not_found envelope).

- [x] **Task 2 — `GetMessageDetailTest.cls` (AC: #4)**
  - [x] Fixture seeding via parameterized SQL INSERT — Ens.MessageHeader + Ens.Rule.Log rows; reused `SessionAgent.Test.GmbFixtureEnsBody` from Story 4.2. Fixture session id = 999943 (distinct from Story 4.2's 999942).
  - [x] All 6 named tests per AC-4
  - [x] `iris_doc_compile` clean
  - [x] `iris_execute_tests` per-class — 6/6 passing.

- [x] **Task 3 — Stale-reference scan (Rule 4)**
  - [x] `grep "HSCUSTOMCODE|gpt-4o" src/ docs/ .claude/` — clean. `src/` has 0 matches; `docs/epic-cycle-teams.md` references HSCUSTOMCODE only as a historical epic-cycle correction precedent (line 252). All `_bmad-output/` matches are historical retro/research notes and are correct artifacts of Epic 2 retro Rule 10.

- [x] **Task 4 — Verification battery (AC: #5)**
  - [x] Per-class regression sweep: 169 → **175/175** passing (per-class iteration over 25 SessionAgent.Test.* test classes; package-level still truncates per project rule).
  - [x] Sample production state: re-Bootstrapped + started (`iris_production_control start`); fresh scenario `RunScenario("none")` produced session 850 with messages 850–856.
  - [x] Live OpenAI smoke turn (Rule 6 sharpened) against **session 850 / message 854** (session 528 was stale): agent dispatched `get_message_detail` (primary) + `rule_log` (1 follow-up call to confirm session-wide rules) — 2 tool calls total, NOT 3 separate calls. Answer correctly grounded: header (BP.OrderRouter → BO.FilePublish, status 9, no error), body (OrderRequest 7 properties, Stark Enterprises, ORD-000045), rule_decision_count=0. Wall clock 5.1s.
  - [x] Rule 12 visual gate captured: `_bmad-output/implementation-artifacts/4-3-rule-12-visual-pass-1.png`. Tool card `get_message_detail` rendered cleanly with full structuredContent envelope (header object, body_summary, body_repr, body_render_strategy, body_truncated, body_class, body_id, rule_decisions:[]) — no overflow, all fields visible in expanded card.

## Dev Notes

### Rule 8 application — fix-now is the default

If Task 0 surfaces an Ens.Rule.Log column-name mismatch with epics.md AC-3 (e.g., `TriggeringMessageHeader` is actually `TriggeringHeader`), fix-now in this story.

### Rule 1 spec-length watch (≤ 250 lines)

Targets ~140 lines. Cited by reference (Stories 4.1 + 4.2 patterns); ACs are tight.

### Auto-sync + typed MCPs

Same as Stories 4.0–4.2. The MCP truncation workaround (Story 4.0 AC-4) applies — use per-method invocation if package-level runner truncates.

### Body-rendering reuse strategy

Story 4.3 calls `##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(...)` directly — the dispatch ladder lives in GetMessageBody (architecture G2 inline decision confirmed by Story 4.2 review). Story 4.3 takes the structuredContent fields it needs (body_class, body_id, render_strategy, body_repr, truncated) and folds them into its own envelope under a `body_*` prefix. **DO NOT refactor the ladder out of GetMessageBody for Story 4.3** — that's deferred to Epic 8 Story 8.6 if cross-package reuse materializes.

### Order of operations

1. Task 0 — probe Ens.Rule.Log column for `TriggeringMessageHeader` and confirm GetMessageBody Invoke signature.
2. AC-1, AC-2, AC-3 — implement straight through (the composition is short).
3. AC-4 — tests.
4. AC-5 — verification battery + Rule 12 visual gate last.

### Sources

- [`epics.md` Story 4.3](../planning-artifacts/epics.md#L1514) — AC source.
- [`GetMessageBody.cls`](../../src/SessionAgent/Tool/Inspection/GetMessageBody.cls) — body-render dispatch (Story 4.2).
- [`EventLog.cls`](../../src/SessionAgent/Tool/Inspection/EventLog.cls) + [`RuleLog.cls`](../../src/SessionAgent/Tool/Inspection/RuleLog.cls) — Story 4.1 reference patterns.
- [`Story41ToolsTest.cls`](../../src/SessionAgent/Test/Story41ToolsTest.cls) + [`GetMessageBodyTest.cls`](../../src/SessionAgent/Test/GetMessageBodyTest.cls) — recent test-class precedents (separate class for non-trivial new tools, parameterized SQL INSERT fixture pattern).
- [`irislib/Ens/Rule/Log.cls`](../../irislib/Ens/Rule/Log.cls) — IRIS-library source read.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — ObjectScript syntax + LLM Prompt Construction subsection.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 4, 6 sharpened, 8, 9, 11, 12.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — bmad-dev-story execution, 2026-05-04.

### Debug Log References

- Task 0 SQL probe `SELECT TOP 5 ... TriggeringMessageHeader ...` returned SQLCODE -29 ("Field not found"). Per `irislib/Ens/Rule/Log.cls` line 62, the actual column is `CurrentHeaderId`. Spec acknowledged this possibility (AC-3 step 4 "or whatever the actual column is — verify via Task 0 probe"); applied Rule 8 fix-now in this story.
- Compilation: first build of `Invoke()` used bare-keyword `If/ElseIf` chain → ERROR #1026 "Invalid command : 'ElseIf'" at line Invoke+152. Fixed by switching to braced `If {} ElseIf {}` form.
- Smoke probe via temporary `SessionAgent.Test.Probe43` class verified composition end-to-end (header 741 → ens_message_body, 0 rule decisions) before tests were authored. Probe class deleted after use.

### Completion Notes List

- AC-1 ✅ — Class declared with all four parameters + HTML/DocBook banner.
- AC-2 ✅ — `GetInputSchema()` returns locked-subset schema with `message_id` required, `additionalProperties: false`.
- AC-3 ✅ — Three-part composition implemented:
  - Step 1 — parameterized `SELECT ... FROM Ens.MessageHeader WHERE ID = ?` with `%EXACT()` on string columns; ISO-8601 normalization via `SessionAgent.Tool.Base.NormalizeIsoZ()`; null-sentinel `$Char(0)` normalization (Story 4.2 precedent).
  - Step 2 — direct `##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, {message_id, format:"summary"}, .tBodyResult)` call. Reuses dispatch ladder without extracting it (per architecture G2; Epic 8 Story 8.6 deferral preserved).
  - Step 3 — parameterized `SELECT ... FROM Ens_Rule.Log WHERE %EXACT(CurrentHeaderId) = ?` with `%EXACT(ConfigName) AS component` (NOT `Component`) and `%EXACT(CurrentHeaderId) AS triggering_message_id` mapping per Story 4.1 RuleLog precedent. LIMIT 100 via `Parameter RuleDecisionLimit`. Returns `[]` for headers with no rule decisions.
  - Composition produces all spec-required fields: `message_id`, `header.{id, source_config_name, target_config_name, status, time_created, is_error, session_id, body_class, body_id}`, `body_summary`, `body_repr`, `body_render_strategy`, `body_truncated`, `body_class`, `body_id`, `rule_decisions[]`, `rule_decision_count`, optional `body_error`.
  - 2-3 line operator summary text composed at `content[0].text`.
  - Outer Try/Catch — composition_error envelope on unexpected exception. No throws escape.
- AC-4 ✅ — All 6 named tests passing in `SessionAgent.Test.GetMessageDetailTest` (FullPayload, NoBody, NoRuleDecisions, MissingMessageId, UnknownMessageId, RegistryListTools).
- AC-5 ✅ — Compile clean, regression 175/175, sample production re-bootstrapped + scenario run, live OpenAI smoke turn dispatched `get_message_detail` (primary), Rule 12 visual gate captured at `_bmad-output/implementation-artifacts/4-3-rule-12-visual-pass-1.png`.
- Test count: 169 → 175 (+6) — matches AC-4 target exactly.

### File List

New files:
- `src/SessionAgent/Tool/Inspection/GetMessageDetail.cls` (one-shot composition tool)
- `src/SessionAgent/Test/GetMessageDetailTest.cls` (6 tests)
- `_bmad-output/implementation-artifacts/4-3-rule-12-visual-pass-1.png` (Rule 12 visual gate screenshot)

Modified files:
- `_bmad-output/implementation-artifacts/4-3-getmessagedetail.md` (this story file — Tasks/Subtasks, Dev Agent Record, Status)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (story status: ready-for-dev → in-progress → review)

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-04 | Initial spec drafted by lead from epics.md §Story 4.3 | Claude Opus 4.7 (lead) |
| 2026-05-03 | Story implemented end-to-end. Task 0 corrected `TriggeringMessageHeader` → `CurrentHeaderId` (Rule 8 fix-now). 6 new tests added; per-class regression 175/175. Live smoke turn dispatched `get_message_detail` as primary tool. Rule 12 visual gate captured. | Claude Opus 4.7 (dev) |
| 2026-05-03 | Code review (Opus 4.7). 1 MEDIUM auto-fixed (silent `%Prepare` failure on Step 3 → propagate to outer `composition_error` envelope, matching RuleLog.cls Story 4.1 precedent). 2 LOW deferred (Bootstrap.cls `Write` operator-output blocks `iris_execute_classmethod` smoke calls; `get_message_detail` description tightening to dampen redundant `rule_log` follow-ups — owner Story 4.7). 6/6 tests still pass post-fix. | Claude Opus 4.7 (reviewer) |

## Review Findings

- [x] [Review][Patch] Step 3 `%Prepare` failure silently swallowed (rule_decision_count=0 indistinguishable from "no rules fired") [src/SessionAgent/Tool/Inspection/GetMessageDetail.cls:212] — auto-fixed to surface as `composition_error` envelope, matching RuleLog.cls Story 4.1 precedent. 6/6 tests still pass post-fix.
- [x] [Review][Defer] `get_message_detail` description sharpening to dampen redundant `rule_log` follow-up [src/SessionAgent/Tool/Inspection/GetMessageDetail.cls:71] — deferred to Story 4.7 (comprehensive read-only suite verification). Rationale: live test observed agent dispatching `get_message_detail` (correct primary) + `rule_log` (broader session scope) — 2 calls instead of 1. Lead leans toward (b): description-level disambiguation rather than ship-blocker. LOW severity; not a Story 4.3 regression.
- [x] [Review][Defer] Bootstrap.cls `Write` statements block `iris_execute_classmethod` smoke calls [src/SessionAgent/Sample/Bootstrap.cls:49-54, 93, 97] — deferred (Bootstrap class hygiene, Story 3.9 carry-over; not a Story 4.3 regression). Operator workaround (`iris_production_control start`) is the canonical alternate path. LOW severity. No predicted bug shape — Write statements are intentional operator-facing console output for `iris session` interactive shell use.

## Code Reviewer Verification of Lead's Eight Flagged Items

1. **Column-name fix-ups (Rule 8 fix-now)** — VERIFIED. `GetMessageDetail.Invoke` uses `%EXACT(CurrentHeaderId) = ?` (line 212) and `%EXACT(ConfigName) AS component` (line 212). Task 0 probe captured in story Tasks/Subtasks line 68 and Debug Log References. Matches Story 4.1 RuleLog.cls precedent.
2. **Direct GetMessageBody.Invoke call** — VERIFIED. Line 169: `Do ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, tBodyArgs, .tBodyResult)` with `pCallerCtx` passed straight through. No `SessionAgent.Body.DispatchLadder` helper extracted. Architecture G2 deferral preserved.
3. **Defensive `body_error` field** — VERIFIED CORRECT. Lines 173-177: `tBodyError` populated from `tBodyResult.content[0].text` only. Outer envelope still composes successfully (lines 228-241); `body_error` field added conditionally at line 237-239 only when non-empty. NO `isError:1` propagation to GetMessageDetail's outer envelope.
4. **Bootstrap.cls Write statements** — Lines 49-54, 93, 97 in `src/SessionAgent/Sample/Bootstrap.cls`: Write statements ARE intentional operator-facing console output for `iris session` interactive shell. NOT debug remnants. Logged as LOW deferral (Bootstrap class hygiene; not blocking; pre-existing from Story 3.9).
5. **Live-test observation: redundant `rule_log` follow-up** — Agree with lead's lean toward (b). Description tightening could dampen the redundant call (`rule_log` is genuinely broader scope, but `get_message_detail.rule_decisions` already covers per-message scope). Logged as LOW finding for Story 4.7 — not a Story 4.3 ship blocker.
6. **Visual-gate screenshot** — VERIFIED. `4-3-rule-12-visual-pass-1.png` shows rendered tool-card for `get_message_detail` against session 850 / message 854: header object with all 9 keys (id, source_config_name, target_config_name, status, time_created, is_error, session_id, body_class, body_id), body_summary readable, body_repr present, body_render_strategy="ens_message_body", body_truncated=true, body_class, body_id, rule_decisions:[]. No UTF-8 mojibake. No overflow.
7. **Regression-count delta 175/175** — Trusted per dev report. Reviewer did not independently re-run full per-class sweep (would require 25+ tool calls in single-task agent). Per-class re-run of GetMessageDetailTest after MEDIUM fix: 6/6 pass.
8. **Test fixture reuse (`GmbFixtureEnsBody`)** — VERIFIED CLEAN. `GmbFixtureEnsBody.cls` is a standalone class file (`src/SessionAgent/Test/GmbFixtureEnsBody.cls`). Story 4.2's `GetMessageBodyTest.OnAfterAllTests` only `%DeleteId`s rows; does NOT drop the class definition. Cross-test-class dependency is safe — Story 4.3's reuse will not be torn down by Story 4.2 cleanup.
