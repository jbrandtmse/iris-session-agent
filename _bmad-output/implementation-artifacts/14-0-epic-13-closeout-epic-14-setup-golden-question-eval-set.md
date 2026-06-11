# Story 14.0: Epic 13 Closeout + Epic 14 Setup + Golden-Question Eval Set

Status: done

**Source:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-06-10.md` (APPROVED 2026-06-10; D1 both-agents / D2 XData / D3 stretch / D4 digest-now) opens Epic 14 "Trace Intelligence". This Story 14.0 is the Rule 7 sprint-planning gate + Rule 9 carry-forward closure + golden-question eval-set authoring. PRD FR60â€“FR64 + architecture addendum already landed in the approval commit (`cab2735`) â€” do NOT re-author them.

## Story

As the **lead** running `/epic-cycle 14`, I want every Epic 13 deferred item explicitly triaged, the `%Execute()` SQLCODE defensive sweep landed, and the golden-question eval set authored, so that Stories 14.1â€“14.5 inherit a clean defensive baseline, binding spec callouts, and a concrete epic-end acceptance instrument.

## Acceptance Criteria

**AC-1 â€” Triage table.** This story file contains a triage table mapping every Epic 13 retro open AI (AI-2, AI-3) and all 4 continued deferrals to Include / Defer / Drop with rationale and named successor.

> **Then** the table appears verbatim under "Triage Decisions"; all 6 items represented.

**AC-2 â€” `%Execute()` SQLCODE sweep (deferred-work carrier closure, Rule 9).** A new `ClassMethod EnsureIsErrorOnExecuteFailure(pResult As %DynamicObject, pRS, pToolName As %String) As %Boolean` ships on `SessionAgent.Tool.Base`, mirroring the existing `EnsureIsErrorOnPrepareFailure` (same file, ~line 315): returns 0 when `pRS` is a valid object with `%SQLCODE >= 0`; otherwise mutates `pResult` to `isError=1`, `content[0].text = "Tool '<name>' SQL execute failed: SQLCODE <n>: <%Message>"`, `structuredContent.render_strategy = "execute_error"`, `structuredContent.error_text`, and returns 1. Every `%Execute(` call site across `src/SessionAgent/Tool/Inspection/*.cls` and `src/SessionAgent/Tool/Search/*.cls` (45 sites, 23 files â€” `Registry.cls`'s 2 internal discovery sites excluded, see Dev Notes) is retrofitted with the caller pattern `If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit` immediately after the `%Execute(...)` assignment and before the first `%Next()`.

> **Then** `grep -rn "%Execute(" src/SessionAgent/Tool/Inspection src/SessionAgent/Tool/Search` site count equals the retrofitted-call-site count in Completion Notes (verbatim grep output captured); every site is followed by the helper guard; all classes compile clean.

**AC-3 â€” Helper unit tests.** New tests verify: (a) helper returns 0 and leaves `pResult` untouched for a successful result set; (b) helper returns 1 and shapes the canonical `execute_error` envelope when `%SQLCODE < 0` (drive via a real runtime-failing SELECT â€” e.g., conversion error on a non-numeric string passed to a numeric function â€” or a stub object exposing `%SQLCODE`/`%Message`); (c) at least one retrofitted tool end-to-end returns `render_strategy="execute_error"` (not `*_not_found`) when its statement fails at runtime.

> **Then** new test methods pass; full regression sweep via `SessionAgent.Test.Util:RegressionSweepCount()` shows baseline 509 + new tests, 0 failures (verbatim Total/Passed/Failed captured).

**AC-4 â€” Stale "ThirteenTools" rename (cr-13-1 closure).** In `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls`, rename `TestAllThirteenToolsExerciseAgainstFixture` â†’ `TestAllToolsExerciseAgainstFixture`, `TestAllThirteenToolsValidationFailureReturnsEnvelope` â†’ `TestAllToolsValidationFailureReturnsEnvelope`, `TestRegistryListsExactlyThirteenTools` â†’ `TestRegistryListsExpectedToolCount`; update doc-comment prose referencing "13 tools"/"ThirteenTools".

> **Then** `grep -i "thirteen" InspectionSuiteVerificationTest.cls` returns 0 hits; the 13 ISV tests still pass.

**AC-5 â€” Stale-reference scan (Rule 4).** Grep canonical docs (README.md, architecture.md, prd.md, epics.md, product-brief distillate) for Epic 14 dependency terms (`statementType`, `SessionAgent.Knowledge`, `execute_readonly_sql`, `get_query_knowledge`, tool-count claims like "28 tools") and confirm each matches live state or is an intentional forward reference. Capture the **current verbatim capability text** of `renderWelcomeMessage()` in `static/chat-panel.js` (~line 679) in Completion Notes â€” the update itself is Story 14.5 scope (binding noted there), but the before-state is recorded now.

> **Then** Completion Notes lists scan terms, hit dispositions, and the verbatim welcome-message capability text.

**AC-6 â€” Golden-question eval set authored.** New file `_bmad-output/implementation-artifacts/epic-14-golden-questions.md` with ~12 questions per proposal Â§4.3: daily message+session counts (30d); error rate by `TargetConfigName` (24h); top error-text groups (noisy-text grouping); P95-ish latency for a Business Operation; active body types this week; describe an unknown body class + pivot one AdditionalInfo key; long-running sessions; "why did session N error" (existing-tool regression); custom-table discovery; deliberately-trapped status-string-vs-integer question; plus 2 of the lead's choosing from cookbook Â§07. Each entry: question text, expected agent behavior (which tools/knowledge consulted), pass criteria, trap notes where applicable.

> **Then** the file exists with â‰¥12 entries, each carrying all four fields; the trapped question explicitly names the silent-wrong-results failure mode it guards.

**AC-7 â€” Sprint-status activation.** `sprint-status.yaml`: `epic-14: backlog` â†’ `in-progress`; `14-0-...: backlog` â†’ `ready-for-dev` at story creation, flipped through the pipeline to `done` at commit.

**AC-8 â€” Spec length governance.** This file â‰¤ 250 lines.

## Integration ACs

The `EnsureIsErrorOnExecuteFailure` helper is service-introducing within `Tool.Base`. In-story consumers: the 23 retrofitted tool classes (AC-3c exercises one end-to-end). Future consumers: Stories 14.1/14.2/14.3 new tools (binding in Carry-Forward below).

## Consumed-by

- Stories 14.1, 14.2, 14.3 â€” every new tool's `%Execute` path MUST use `EnsureIsErrorOnExecuteFailure` (and `EnsureIsErrorOnPrepareFailure` for prepare).
- Story 14.5 â€” consumes `epic-14-golden-questions.md` for the mock-matrix eval run; epic-end battery consumes it for the user-led walkthrough.

## Tasks / Subtasks

- [x] **Task 0 â€” Pre-flight reads:** `Tool.Base.cls` (`EnsureIsErrorOnPrepareFailure` shape, lines ~280â€“325), one representative Inspection tool + one Search tool `%Execute` site, `InspectionSuiteVerificationTest.cls`. Capture current `%Execute(` grep roster (45 sites / 23 files expected; reconcile actual).
- [x] **Task 1 â€” Helper:** author `EnsureIsErrorOnExecuteFailure` on `Tool.Base` with full doc-comment banner citing cr-13-3 + this story; compile.
- [x] **Task 2 â€” Sweep:** retrofit all Inspection + Search `%Execute` sites; compile each class via `iris_doc_compile`; document any site where the guard is structurally inapplicable (with rationale) in Completion Notes.
- [x] **Task 3 â€” ThirteenTools rename** (AC-4); run ISV class tests.
- [x] **Task 4 â€” Tests** (AC-3); run full regression sweep via `RegressionSweepCount()`; capture verbatim Total/Passed/Failed.
- [x] **Task 5 â€” Stale-reference scan** (AC-5); capture verbatim welcome-message text.
- [x] **Task 6 â€” Author golden-question file** (AC-6) from `docs/iris-query-guide/07-query-cookbook.md` + proposal Â§4.3.
- [x] **Task 7 â€” Sprint-status + completion notes;** verify spec â‰¤ 250 lines (`wc -l`).

## Triage Decisions

| Source | Item | Decision | Rationale | Successor |
|---|---|---|---|---|
| deferred-work cr-13-3 (LOW) | `%Execute()` SQLCODE unchecked across 15+ tools | **INCLUDE** | Epic 14 is the named "future defensive-sweep" carrier (Rule 9 binding); Epic 14 ships new SQL-running tools that must inherit the corrected pattern from day one. | **This story (14.0)** â€” AC-2/AC-3 |
| Epic 13 retro AI-2 | `EnsureIsErrorOnPrepareFailure` callout in new-tool spec template | **INCLUDE** | Stories 14.1â€“14.3 each ship new tools; the Story 13.5 re-introduction proves the callout must be in the spec, not just the rule file. | Lead: verbatim callout in 14.1/14.2/14.3 specs (Carry-Forward below) |
| Epic 13 retro AI-3 | `EXPECTEDTOOLCOUNT` bump visibility in tool specs | **INCLUDE** | Epic 14 grows the catalog 28 â†’ 33â€“34 across three stories; two misses in Epic 13 prove the bolded callout is needed. | Lead: bolded callout in 14.1/14.2/14.3 specs (Carry-Forward below) |
| deferred-work cr-13-1 (LOW) | Stale "ThirteenTools" ISV method names | **INCLUDE** | Deferral's own future-work note says "on next ISV touch"; Epic 14 touches ISV three times â€” renaming once in 14.0 avoids per-story diff noise. Rule 8 fix-now. | **This story (14.0)** â€” AC-4 |
| Epic 12 AI-3 (re-deferred by 13.0) | AgentConfig `credCombo` JS-set-value gap | **DEFER** | Not Trace Intelligence scope; no Epic 14 story touches the config form; operator workaround stands. | v3 / future walkthrough-bugs collection |
| Epic 12 AI-5 (re-deferred by 13.0) | Substring-grep test pattern tightening | **INCLUDE (Dev Notes binding)** | Same handling as Epic 13: Stories 14.1â€“14.5 use source-introspection assertions; each spec's Dev Notes requires enumerate-all-replace-each-then-grep. | 14.1â€“14.5 specs (Dev Notes) |

**Total:** 6 items. **4 INCLUDE** (2 in-story, 2 spec-binding) + **1 INCLUDE-as-Dev-Notes-binding** + **1 DEFER**. 0 DROP.

## Carry-Forward (Rule 9 binding on named successors)

- **Stories 14.1 / 14.2 / 14.3 specs** MUST each contain this verbatim callout (AI-2 + sweep closure): *"For SQL prepare failures call `##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName)`; for runtime execute failures call `EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName)` immediately after `%Execute` â€” do NOT construct raw `{"isError":1}` objects."*
- **Stories 14.1 / 14.2 / 14.3 specs** MUST each contain (AI-3): **"Bump `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` Nâ†’N+k AND add each tool name to the `tExpected` $ListBuild AND add to `GetRepresentativeArgs`."** (Applies to whichever suite-verification test covers the new tool family; 14.3 also ships `ReadOnlySqlInvariantTest` per the proposal.)
- **Story 14.5 spec** MUST include the `renderWelcomeMessage()` capability-text update (Rule 4 watch-item) using the before-state captured in this story's AC-5.
- **Stories 14.1â€“14.5 specs (Dev Notes)** MUST require the substring-grep pattern: enumerate ALL expected matches, replace each, then grep for the bare standard form (Epic 12 AI-5).

## Dev Notes

- **Helper placement:** `Tool.Base` (not `Tool.Search.Base`) so both families + future `Tool.Query.Base` inherit. Mirror the prepare helper's mutation contract exactly (caller pre-initializes success-shape `pResult`).
- **`Registry.cls` exclusion:** its 2 `%Execute` sites serve internal tool discovery, not tool-result envelopes â€” no `pResult` exists to mutate. Guard inapplicable; document in Completion Notes. If the dev finds a cleaner internal check (log + skip), optional, not required.
- **Caller-pattern caution:** some sites loop `%Next()` across multiple statements (e.g., `SessionSummary` runs 3 statements) â€” guard EACH `%Execute` return, not just the first. Pattern Replication Completeness rule applies (enumerate all sites; checklist, don't copy-paste).
- **`%SQLCODE` semantics:** per `irislib/%SQL/StatementResult.cls`, `%SQLCODE < 0` = runtime error; `0` = success; `100` = no-more-data (NOT an error â€” do not treat 100 as failure). Read the irislib source before implementing (project rule: IRIS Library Source).
- **Search tools' `render_strategy`:** Search.Base envelopes use the same canonical shape post-Story-11.2; `execute_error` is a NEW render_strategy value â€” confirm zero JS UI consumers assert on the closed set of render_strategy values (Story 11.2 review precedent says normalization is safe; re-verify with grep over `static/*.js`).
- **Golden questions:** source recipes from `docs/iris-query-guide/07-query-cookbook.md`; the trapped question must target the integer-enum-vs-string predicate trap (guide Â§01 integer-string-trap). Questions must be answerable against the sample production (`SessionAgent.Sample.Production`, 8+ sessions seeded â€” top up via `SessionAgent.Sample.BS.OrderIngest:RunScenario` if a question needs volume).
- **No new tools, no registry changes, no EXPECTEDTOOLCOUNT change in this story** (count stays 28).
- **Subagent briefing refs:** CouchDB sources N/A; `irislib/` for `%SQL.StatementResult`/`%SQL.Statement`; `sources/` not needed.
- **Testing standards:** `%UnitTest.TestCase` macros ($$$ triple-dollar), per-class `iris_execute_tests` + SQL ground-truth probe via `RegressionSweepCount()` ([Source: .claude/rules/object-script-testing.md]).

### References

- [Source: _bmad-output/planning-artifacts/sprint-change-proposal-2026-06-10.md Â§2.1, Â§4.3 (14.0 row), Â§4.3 golden-question list]
- [Source: _bmad-output/implementation-artifacts/deferred-work.md lines 7â€“17 (cr-13-3), tail (cr-13-1)]
- [Source: _bmad-output/implementation-artifacts/epic-13-retro-2026-05-09.md Â§Action Items AI-2/AI-3]
- [Source: _bmad-output/implementation-artifacts/epic-14-operator-state.md (Rule 7 gate â€” production running, matrix all-resolvable)]
- [Source: src/SessionAgent/Tool/Base.cls EnsureIsErrorOnPrepareFailure ~line 315]

## Operator State (Rule 7 â€” captured at Step 1, 2026-06-10)

See `epic-14-operator-state.md`: production running (`IsProductionRunning=1`), scenario data topped up (50 headers / 8 sessions), credential matrix all-resolvable (OpenAI/Anthropic/Gemini/compat), both Config.Agent rows on `openai`/`gpt-4.1-mini`. Rule 9 grep for "Story 14.0"/"story-14-0" in deferred-work.md: 0 hits (no pre-existing bindings).

## Dev Agent Record

### Agent Model Used

claude-fable-5[1m] (Fable 5) â€” 2026-06-10/11 dev-story run under /epic-cycle.

### Debug Log References

- Audit-visibility probe (same-process): `before=11|auditRet=1|afterImmediate=11|afterApply=11` â€” proves kernel audit-daemon async flush; drove the SweepTaskTest/SearchVocab* poll fixes. `^ClineDebug` instrumentation used in `%SYS` during diagnosis; killed in both namespaces at cleanup.
- DATEDIFF probe: `afterExecute=-400|nextReturn=0|afterNext=-102` (scalar no-FROM SELECT fails AT %Execute); table-context probe `afterExecute=0|nextReturn=1` (coerced silently). Scratch classes `Scratch140Probe` / `Scratch140AuditProbe` created + deleted (server + local).

### Completion Notes List

- **AC-2 evidence (verbatim).** `grep -rc "Set t.*%Execute(" src/SessionAgent/Tool/Inspection src/SessionAgent/Tool/Search` â†’ **45 executable sites / 23 files**; guards: **36** `EnsureIsErrorOnExecuteFailure(pResult, â€¦)` calls + **3 adapted** = all 45 covered. If/else arity branches assigning the SAME result var share one guard placed before the first `%Next()`: EventLog (4 sites/2 guards), RuleLog (2/1), SessionTimeline (5/2). Site checklist: EventLog 163,165,205,207; FindRelatedSessions 122,145,175*,191* (*For-loop sites use `Set tExecFailed=1 Quit` + post-loop `If tExecFailed Quit` â€” bare Quit exits the loop, not the Try); FindSessionsByBody 247,323; GetBusinessProcessInstance 141,190â€ ,209â€ ; GetMessageBody 171; GetMessageDetail 121,221; GetProductionConfigItem 156; ListBusinessProcessMethods 128; MessageHeaders 99; RuleLog 113,115; SessionSummary 122,143,160; SessionTimeline 117â€“123,153; FindSessionsUsingClass 255â€¡; InspectBodyCandidates 315; SearchByBodyField 271,366; SearchByMessageClass 105; SearchBySession 110; SearchBySource 106; SearchByStatus 180; SearchBySuperSession 164,204; SearchByTarget 104; SearchByTime 185; VocabLookup 264,360,389,447. Compile: all 24 classes "Compilation finished successfully" (iris_doc_compile, 2026-06-10 23:13:58).
- **Adapted-guard sites (rationale).** â€  GetBusinessProcessInstance 190/209: best-effort BPL augmentation inner-Try blocks whose PREPARE handling is already graceful-skip (`If $$$ISOK`); mutating pResult there would be clobbered by the success-envelope build â€” adapted to `If $IsObject(tRsâ€¦) && (tRsâ€¦.%SQLCODE >= 0) && tRsâ€¦.%Next()`. â€¡ FindSessionsUsingClass 255 lives in `RunQuery` (no pResult; %Status contract) â€” adapted to `Quit $$$ERROR(...)` which the Invoke call-site already converts to the canonical error envelope.
- **`Registry.cls` exclusion:** its 2 `%Execute` sites (lines 71, 307) serve internal tool discovery â€” no `pResult` envelope exists to mutate; guard inapplicable per Dev Notes.
- **AC-3 evidence (verbatim).** New `ExecuteFailureGateTest`: 6/6 Status=1 (SQL probe). E2e case (c): seeds 2 synthetic `Ens.MessageHeader` rows (SessionId 9799914014), poisons `TimeCreated` via `UPDATE %NOCHECK` (empirically verified), drives `session_timeline` into its scalar `SELECT DATEDIFF('ms',?,?)` (the one in-repo shape that fails AT %Execute â€” table-context predicates coerce silently, e.g. `SessionId='abc'` â†’ rc=0 SQLCODE 0) â†’ asserts `render_strategy="execute_error"`. Full sweep SQL ground-truth probe (canonical numerical-MAX form): **Total=515 / Passed=515 / Failed=0** across 61 classes = baseline 509 + 6 new. `SessionAgent.Test.Util:RegressionSweepCount()` returned %Status=1/OK (Output counts not surfaced via MCP; SQL probe is the evidence). `render_strategy` JS-consumer grep over `static/*.js`: 0 hits â€” `execute_error` value addition is safe.
- **AC-4 evidence.** `grep -i "thirteen" InspectionSuiteVerificationTest.cls` â†’ 0 hits. ISV latest run 13/13 Status=1 (verbatim roster captured incl. `TestAllToolsExerciseAgainstFixture`, `TestAllToolsValidationFailureReturnsEnvelope`, `TestRegistryListsExpectedToolCount`).
- **Rule 8 fix-nows (Epic 13 stale-count incident, found via empirical pre-state).** Pre-state ISV run FAILED 3 methods: registry surfaces **28** tools but `EXPECTEDTOOLCOUNT=27` (Story 13.5 shipped `find_sessions_using_class` without the bump â€” the exact Epic 13 retro AI-3 shape). Fixed: ISV 27â†’28 + `tExpected` + `GetRepresentativeArgs` entry; `SearchToolTest` 10â†’11 search tools (2 asserts + representative args); `ToolCallRoundtripIntegrationTest` matrix lock 92â†’112 (4Ã—28) + perf gate 30sâ†’90s (112-pair matrix measured 64â€“75s on this server; gate was sized for 52 pairs). Dev Notes' "count stays 28" intent preserved â€” no registry change, only stale test locks reconciled.
- **Rule 8 fix-now (audit-daemon visibility flake).** 5 sweep failures (SweepTaskTest Ã—2, SearchVocabularyTest Ã—2, SearchVocabCaptureTest Ã—1) shared one root cause, empirically isolated: `$System.Security.Audit` rows reach `%SYS.Audit` SQL visibility only when the kernel audit daemon flushes (~30â€“60s on this fresh server; `%SYS.Audit:ApplyAuditHeader()` does NOT surface them; no public forced-flush API â€” Perplexity-verified 2026-06-10). Fixed with bounded ~120s polls (`WaitForTaskRunAuditIncrease`, `WaitForAuditRow`, inline poll) that exit on first hit. All three classes now pass (SweepTaskTest 6/6, SearchVocabularyTest 14/14, SearchVocabCaptureTest 8/8 via SQL probe).
- **AC-5 scan dispositions.** `statementType` / `SessionAgent.Knowledge` / `execute_readonly_sql` / `get_query_knowledge`: hits only in prd.md (FR60â€“FR64), architecture.md (Epic 14 addendum), epics.md (Epic 14 section) â€” all intentional forward references landed in approval commit `cab2735`; surfaces correctly do not exist yet. Tool-count claims: README "28 tools" + "28 Ã— 4 = 112" match live state (ListTools=28 verified by SQL + ISV); "13 tools" hits in prd/architecture/epics are historical Epic-4-era milestone records, not live claims; epics.md:460 "23 to 28 â€¦ 92 to 112" matches live state. **Verbatim `renderWelcomeMessage()` capability text (`static/chat-panel.js` lines 679â€“691, captured for Story 14.5 â€” NOT changed here):** search agent: `"Ask me to find sessions across this IRIS instance. I'm read-only â€” I'll search by status, time, source, body content, or any combination. Try: find failed admits in the last hour Â· show me sessions with errors Â· which messages had OrderRequest bodies?"`; inspection agent (else-branch): `"Ask anything about this session OR about other sessions across this IRIS instance. I'm read-only â€” I can't change anything. Try: what happened in this session? Â· which messages had errors? Â· find sessions matching X."`
- **AC-6.** `epic-14-golden-questions.md` authored: 13 entries (10 proposal-mandated + 3 lead's-choice from cookbook Â§07), each with Q / Expected behavior / Pass criteria / Trap notes; GQ-10 is the trapped status-string-vs-integer question and explicitly names the silent-wrong-results failure mode (stringâ†’integer coercion matches everything/nothing with SQLCODE 0).
- **AC-8.** `wc -l` story file = 113 pre-record / â‰¤250 post-record (re-verified at sign-off).
- **Sweep environment notes for reviewer:** package-level `iris_execute_tests` and `SweepRunner.RunAll()` both failed to drive the suite on this install (known traps) â€” sweep executed per-class (61 classes). Atelier worker processes intermittently executed stale class code immediately after recompile (ISV, SearchVocab*); re-runs picked up fresh code; all final counts are post-fresh-code SQL-probe verified. AgentLoopTest/AgentLoopGuardsTest early failures were order-dependent flakes that pass deterministically on re-run (11/11, 3/3) â€” pre-existing, outside this story's diff.

### File List

- src/SessionAgent/Tool/Base.cls (new helper; review fix: non-object error text)
- src/SessionAgent/Tool/Registry.cls (review fix: discovery-query %SQLCODE surfacing in ListTools + ResolveToolName)
- src/SessionAgent/Tool/Inspection/EventLog.cls, FindRelatedSessions.cls, FindSessionsByBody.cls, GetBusinessProcessInstance.cls, GetMessageBody.cls, GetMessageDetail.cls, GetProductionConfigItem.cls, ListBusinessProcessMethods.cls, MessageHeaders.cls, RuleLog.cls, SessionSummary.cls, SessionTimeline.cls (guards; review fix: EventLog severity-count + SessionTimeline span adapted to best-effort graceful-skip)
- src/SessionAgent/Tool/Search/FindSessionsUsingClass.cls, InspectBodyCandidates.cls, SearchByBodyField.cls, SearchByMessageClass.cls, SearchBySession.cls, SearchBySource.cls, SearchByStatus.cls, SearchBySuperSession.cls, SearchByTarget.cls, SearchByTime.cls, VocabLookup.cls (guards; review fixes: FSUC ShapeRunQueryErrorEnvelope execute_error taxonomy + fallback tSCSub2 surfacing; VocabLookup post-save read-back adapted to best-effort with count_read_back_failed marker)
- src/SessionAgent/Test/InspectionSuiteVerificationTest.cls (rename + 27â†’28 reconciliation)
- src/SessionAgent/Test/SearchToolTest.cls (10â†’11 reconciliation)
- src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls (92â†’112; review fix: dynamic per-pair perf gate MAXSECONDSPERPAIR/MINMATRIXGATESECONDS replacing fixed 90s; TestMatrixCardinalityIs52 â†’ TestMatrixCardinalityMatchesCatalog)
- src/SessionAgent/Test/SweepTaskTest.cls, SearchVocabularyTest.cls, SearchVocabCaptureTest.cls (audit-flush poll fixes; review fix: comment contradictions converged on 120s-ceiling statement)
- src/SessionAgent/Test/ExecuteFailureGateTest.cls (NEW â€” AC-3 tests; review fix: e2e restaged as SessionTimeline graceful-skip, OnAfterOneTest cleanup, generic negative-SQLCODE assertions)
- src/SessionAgent/Test/ExecuteFailureAdaptedSitesTest.cls (NEW â€” QA-stage adapted-guard tests; review fix: +2 ShapeRunQueryErrorEnvelope classifier tests)
- _bmad-output/implementation-artifacts/tests/test-summary.md (NEW â€” QA-stage summary, updated by review triage)
- _bmad-output/implementation-artifacts/epic-14-golden-questions.md (NEW â€” AC-6)
- _bmad-output/implementation-artifacts/deferred-work.md (cr-13-3 + cr-13-1 marked CLOSED-by-14.0)
- _bmad-output/implementation-artifacts/14-0-epic-13-closeout-epic-14-setup-golden-question-eval-set.md (this file)
- _bmad-output/implementation-artifacts/sprint-status.yaml (status flip + narrative refresh)

## Review Findings (code-review triage, 2026-06-11)

Verdict: **ACCEPT with fixes applied inline.** 0 HIGH / 8 MED resolved / 8 LOW resolved / 6 dismissed / 0 new deferrals. All fixes recompiled clean; affected classes re-run; final ground-truth sweep **Total=520 / Passed=520 / Failed=0** (canonical numerical-MAX SQL probe; = 518 baseline + 2 new classifier tests).

**Resolved â€” MED (8):**

1. **SessionTimeline span DATEDIFF execute failure was fatal** while its prepare failure was tolerated â€” one poisoned row nuked the whole successfully-built timeline. Adapted to best-effort graceful-skip (`time_span_ms` stays 0), mirroring its own prepare handling and the GBPI adapted guards. Main-statement gate remains fatal.
2. **EventLog severity-count GROUP BY execute failure was fatal** â€” same shape, same fix (counts stay 0; events array preserved).
3. **FSUC execute failures mislabeled `prepare_error`** with contradictory "SQL prepare failed: ... SQL execute failed ..." text, and the QA test cemented it. New `ShapeRunQueryErrorEnvelope` classifier on FindSessionsUsingClass: RunQuery %Status carrying the execute marker now shapes the canonical `render_strategy="execute_error"` envelope; non-marker statuses keep the Story 11.2 prepare gate. Tests updated + 2 added (`TestShapeRunQueryErrorEnvelopeExecuteMarker`, `...NonMarkerFallsBack`).
4. **FSUC strip-last-segment fallback discarded `tSCSub2`** â€” an execute failure on the retry returned a success-shaped "No sessions found". Else branch now surfaces the error envelope via the same classifier.
5. **VocabLookup.InvokeSave post-commit read-back emitted isError for a PERSISTED save** (inviting duplicate retry; early Quit skipped mode:"save" fields). Read-back prepare+execute adapted to best-effort; additive `count_read_back_failed` drift marker; success envelope always emitted post-save.
6. **Registry.cls ListTools/ResolveToolName %Execute failures masked** (highest blast radius of the cr-13-3 class â€” registered tools misreported as "unknown tool"). ResolveToolName: %SQLCODE<0 throws + Catch rethrows so Dispatch's outer Catch emits a server-fault envelope and stamps Audit.ToolCall.ErrorText (Dispatch is the only production caller; 8/8 ToolRegistryTest pass). ListTools: %SQLCODE<0 throws into its documented empty-list degradation (callers' array contract preserved).
7. **Perf gate fixed 90s raise would flake within Epic 14** (140 pairs Ã— 0.57â€“0.67 s/pair observed â‰ˆ 80â€“94s) and the parameter name implied per-roundtrip semantics. Replaced with run-time derived gate `max(MINMATRIXGATESECONDS=30, size Ã— MAXSECONDSPERPAIR=1s)` â€” auto-scales with catalog growth, honest per-pair arithmetic in the doc. Matrix re-run: 4/4 pass under derived gate.
8. **SweepTaskTest contradictory comments**: the CountTaskRunAuditRows comment claimed `ApplyAuditHeader()` was the fix while the dev's own probe (`afterApply=before`) and `irislib/%SYS/Audit.cls` (header-buffer-only apply) disprove it; poll-duration comments said ~5s / ~60s / code=120s. Converged on ONE authoritative statement in `WaitForTaskRunAuditIncrease` doc (240 Ã— 0.5s = 120s ceiling, early exit); `ApplyAuditHeader()` kept as documented best-effort mirror of `%SYS.Audit:List` (Rule 5 investigation: irislib source read settled it, no removal needed).

**Resolved â€” LOW (8):** helper non-object error text ("SQLCODE : ..." empty-slot wording fixed); e2e poisoned-row leak (OnAfterOneTest ensured cleanup, idempotent); engine-version-brittle `SQLCODE -400` substring assertions relaxed to generic `SQLCODE -` (exact -400 kept only where project-authored text is asserted); negative audit for the 5 untouched tools captured (grep verified: ExplainError, GetBusinessProcessSource, GetClassSource, GetQueueState, GetRuleSource = **zero `%Execute(` sites**, guard not applicable); `TestMatrixCardinalityIs52` â†’ `TestMatrixCardinalityMatchesCatalog`; File List updated with QA artifacts; deferred-work.md cr-13-3 + cr-13-1 marked CLOSED-by-14.0; sprint-status.yaml narrative refreshed.

**Dismissed (6, Rule 8 test 3 unless noted):** Completion-Notes site-checklist line numbers are pre-insertion (cosmetic; all 45 sites re-verified present by the verifier â€” kept as historical record); EXPECTEDTOOLCOUNT 27â†’28 letter-vs-intent gap (intent-compatible: live registry already had 28 since Story 13.5; Dev Notes "no EXPECTEDTOOLCOUNT change" meant no registry change â€” recorded as letter-vs-intent note); helper `<PROPERTY DOES NOT EXIST>` on an object lacking %SQLCODE (unreachable â€” every call site passes %SQL.StatementResult; tool outer-Catch + Dispatch outer-Catch are defense-in-depth); WaitForAuditRow class/instance suspicion (verified: `AuditRowExistsForName` IS a ClassMethod â€” no mismatch); GBPI graceful-skip silence (deliberate pre-existing best-effort design, now consistent across all 3 adapted enrichment sites); `TestMatrixCompletes52CombinationsUnderPerfGate` stale name (cosmetic; left as-is because deferred-work.md line ~1261 binding references the name verbatim).

**AC-2 arithmetic post-review (supersedes the Completion-Notes 36+3 split).** Fresh grep `Set t.*%Execute(` over Tool/Inspection + Tool/Search = **45 executable sites** (unchanged). Coverage now: **33 standard `EnsureIsErrorOnExecuteFailure(pResult, â€¦)` guards** (covering 38 sites â€” 5 if/else-arity branches share their statement's guard: EventLog main 2â†’1, RuleLog 2â†’1, SessionTimeline main 4â†’1) **+ 7 adapted sites** (GBPI ctx/thread probes Ã—2, EventLog severity-count Ã—2 sharing one adapted check, SessionTimeline span Ã—1, VocabLookup post-save read-back Ã—1, FSUC RunQuery %Status contract Ã—1). 33 + 5 shared + 7 = 45. (A 34th grep hit on the helper name in FSUC is a doc-comment reference, not a guard.)

**AC-3c restage note.** The dev's execute_error e2e rode SessionTimeline's span statement, which this review re-classified best-effort. AC-3c evidence is restaged as: (a) `TestSessionTimelineSpanFailureGracefulSkip` â€” real runtime %Execute failure via poisoned fixture, timeline returned with span_ms=0; (b) the FSUC two-link chain â€” `TestRunQueryReturnsErrorStatusOnExecuteFailure` (REAL engine %SQLCODE -400 at %Execute through project SQL â†’ marker %Status) + `TestShapeRunQueryErrorEnvelopeExecuteMarker` (marker %Status â†’ canonical `render_strategy="execute_error"` envelope through the production Invoke classifier). No single-call public-Invoke runtime failure remains stageable in-repo (table-context coercion per Task-4 probes) â€” the chain is the strongest available evidence and uses a real runtime failure.

**Re-verification evidence (verbatim).** Compile: all 10 touched classes "Compilation finished successfully" (iris_doc_compile 2026-06-11 00:49). Per-class fresh-code runs (SQL ground truth where the MCP envelope truncated): ExecuteFailureGateTest 6/6; ExecuteFailureAdaptedSitesTest 5/5; ToolRegistryTest 8/8; FindSessionsUsingClassTest 10/10; InspectionToolTest 7/7; Story41ToolsTest 7/7; InspectionSuiteVerificationTest 13/13; SearchToolTest 24/24; SearchVocabularyTest 14/14 (solo re-run 155); SweepTaskTest 6/6 (solo re-run 154); ToolCallRoundtripIntegrationTest 4/4 (run 153, incl. renamed cardinality test + derived perf gate). Full-suite canonical probe: `Total=520 / Passed=520 / Failed=0`. NOTE for the lead: two transient failures during the review run were proven concurrency artifacts of the Atelier work queue double-running classes (runs 150/151/152 overlapped and shared fixtures; solo re-runs 154/155 pass clean) â€” not code regressions.

### Change Log

- 2026-06-10/11 â€” Story 14.0 implemented: `EnsureIsErrorOnExecuteFailure` helper + 45-site sweep (23 files); ThirteenTools rename; Epic 13 stale-count reconciliation (ISV 28, SearchToolTest 11, matrix 112); audit-daemon-flush test hardening; golden-question eval set (13 entries); sweep 515/515 pass 0 fail.
- 2026-06-11 â€” Code-review triage: 8 MED + 8 LOW resolved inline (see Review Findings); 2 tests added; sweep 520/520 pass 0 fail.
