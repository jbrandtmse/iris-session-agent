# Story 14.6 (Stretch, D3): EXPLAIN Plan-Reasoning Support

Status: done

**Source:** `sprint-change-proposal-2026-06-10.md` Â§4.2 D3 (stretch â€” authorized: 14.0â€“14.5 all landed clean) + Â§4.3 14.6 row. **Empirical premise update (Story 14.3 Task 0):** on this IRIS build `EXPLAIN SELECT` prepares with `statementType=1` (NOT the documented 79) â€” the allowance is therefore implemented at the comment-aware leading-keyword validator, not the statementType gate. Evidence trail: 14.3 story Completion Notes (Task 0 probe table) + 14.3 review cr-14-3-A (comment-aware scanner) + 14.3 QA `TestCommentPrefixedExplainStaysReadOnly` (EXPLAIN mutates nothing â€” write-proof; test designed to survive this allowance).

## Story

As an **operator asking why a query is slow**, I want the agents to run `EXPLAIN` through `execute_readonly_sql` and reason about the plan with `%PARALLEL`/`%IGNOREINDEX` guidance, so that performance questions get plan-grounded answers instead of guesses.

## Acceptance Criteria

**AC-1 â€” Validator EXPLAIN allowance.** `Tool.Query.Base.ValidateSingleStatement` (comment-aware scanner from cr-14-3-A) allows a statement whose first effective keyword is `EXPLAIN` (any case, comment/whitespace-prefixed handled identically to SELECT). The inner statement after EXPLAIN must itself pass the pipeline: prepare â†’ statementType gate (`1` on this build; defensively ALSO accept `79` if a build returns it for EXPLAIN â€” keep the named friendly type) â†’ execute â†’ capped fetch. `EXPLAIN INSERT/UPDATE/DELETE` behavior: Task 0 probes what IRIS does â€” if it prepares/executes as a plan-only operation, decide allow-with-write-proof or reject-by-inner-keyword; the REJECT-inner-write choice is the default unless the probe proves plan-only semantics (document either way; a write-proof test is mandatory if allowed).

> **Then** live dispatch of `EXPLAIN SELECT TOP 5 ID FROM Ens.MessageHeader` returns plan rows (`render_strategy:"ok"`); lowercase + comment-prefixed EXPLAIN behave identically; write-proof retained (no mutation); the EXPLAIN-of-INSERT decision is probed, documented, and test-locked.

**AC-2 â€” Plan-reasoning guidance activation.** The Story 14.1 corpus already seeds `parallel-hint`, `ignoreindex-pattern`, `cost-vs-runtime` (performance topic). This story: (a) verifies those article bodies give actionable plan-reasoning guidance (reading a plan, `%PARALLEL` placement, `%IGNOREINDEX` A/B pattern â€” correct vs `docs/iris-query-guide/03-performance-and-plans.md`; amend bodies if thin/wrong via the SeedContent XData + re-Seed); (b) adds ONE EXPLAIN guidance line to the 14.5 methodology card (static, no digits â€” e.g., *"For slow-query questions, run EXPLAIN on the SELECT and consult get_query_knowledge topic=performance before suggesting hints."*) for BOTH agents (card stays deterministic; determinism + static-content tests updated if the zero-digit assertion needs the new line accounted for).

> **Then** card contains the EXPLAIN line both agents (determinism test green); the 3 performance articles retrievable via `get_query_knowledge topic=performance` with plan-reasoning content (verbatim retrieval evidence); corpus count test updated if bodies changed count (count should stay 47).

**AC-3 â€” Tests.** Update/extend: proof-battery EXPLAIN rejection tests flip to allowance expectations (bare/lowercase/comment-prefixed EXPLAIN SELECT all succeed); adversarial `TestCommentPrefixedExplainStaysReadOnly` keeps its no-mutation invariant; EXPLAIN-of-write decision lock; plan-rows envelope shape (row cap + char budget still apply to plan output); invariant test untouched (EXPLAIN rides the same `RunGuardedSelect` pipeline â€” verify no bypass added). Full sweep = baseline 624 Â± adjusted, 0 failures (verbatim ground-truth probe).

**AC-4 â€” README + tool description.** `execute_readonly_sql` schema `description` mentions EXPLAIN support (one clause); README "Guarded dynamic SQL" subsection updated (EXPLAIN allowed, plan-only, write statements still rejected).

**AC-5 â€” Spec â‰¤ 250 lines.**

## Integration ACs

In-story: real `Tool.Registry.Dispatch` EXPLAIN e2e (AC-1). The epic-end walkthrough MAY include a plan-reasoning turn (optional â€” the golden-question set stays at 13; no GQ addition required for a stretch).

## Consumed-by

- Epic-end battery (optional plan-reasoning turn). No future-story consumers.

## Tasks / Subtasks

- [x] **Task 0 â€” Probes:** (a) `EXPLAIN SELECT ...` full pipeline behavior on this build (prepare type, execute, result shape â€” column name(s), row count for a simple plan); (b) `EXPLAIN INSERT ...` behavior (prepare type? executes? mutates? â€” write-proof probe); (c) comment-prefixed/lowercase variants through the current validator (expect rejection pre-change); (d) performance-article bodies vs guide Â§03 accuracy read. Verbatim outputs to Completion Notes.
- [x] **Task 1 â€” Validator allowance** (AC-1); compile; live dispatch probes.
- [x] **Task 2 â€” Guidance activation** (AC-2): article verification/amendment + card line; re-Seed if XData changed; compile.
- [x] **Task 3 â€” Tests** (AC-3); ground-truth sweep verbatim.
- [x] **Task 4 â€” README + schema description** (AC-4); Completion Notes + File List; `wc -l` â‰¤ 250.

## Dev Notes

- **Helper callout (14.0 Carry-Forward, verbatim):** *"For SQL prepare failures call `##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName)`; for runtime execute failures call `EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName)` immediately after `%Execute` â€” do NOT construct raw `{"isError":1}` objects."*
- **Security posture unchanged:** EXPLAIN is read-only (14.3 QA write-proof). The inner-statement decision (AC-1) is the only new security surface â€” default REJECT for inner writes unless plan-only semantics are empirically proven AND write-proof-tested. The adversarial battery's mutation-rejection tests must all stay green.
- **EXPLAIN result shape:** likely a single wide plan column â€” verify `%SelectMode` interaction and char-budget behavior on a long plan (Task 0a); the 32 KB budget + truncated marker apply unchanged.
- **Card edit re-runs the 14.5 test set:** `TestMethodologyCardStaticContent` asserts zero digits â€” keep the new line digit-free; `TestGetSystemPromptDeterminism` byte-identity unaffected by a static line.
- **Corpus edit mechanics:** body amendments go in `SeedContent` XData; `Seed()` upserts by Slug (idempotent overwrite) â€” re-run Seed live and re-verify count 47 + retrieval.
- **Substring-grep binding (Epic 12 AI-5)** for test assertions on validator source.
- **Rule 10:** no external defaults â€” N/A. **Rule 12:** no UI text changes (card is LLM-facing, not operator-rendered; welcome text untouched) â€” N/A.
- **Subagent refs:** `irislib/%SQL/Statement.cls` (EXPLAIN handling if documented), `docs/iris-query-guide/03-performance-and-plans.md`, 14.3 story file Completion Notes (probe table).

### References

- [Source: sprint-change-proposal-2026-06-10.md Â§4.2 D3, Â§4.3 14.6 row]
- [Source: 14-3 story Completion Notes â€” statementType probe table + EXPLAIN keyword rejection]
- [Source: 14-3 Review Findings cr-14-3-A â€” comment-aware validator]
- [Source: docs/iris-query-guide/03-performance-and-plans.md]

## Dev Agent Record

### Agent Model Used

Claude Fable 5 (claude-fable-5[1m]) via /epic-cycle dev-story stage, 2026-06-11.

### Debug Log References

Scratch probe class `SessionAgent.Scratch146Probe` (deleted locally AND from server via `iris_doc_delete` after evidence capture, per the 14.3 precedent).

### Completion Notes List

- **Task 0 verbatim probes (live HSCUSTOM, 2026-06-11):**
  - (a) `EXPLAIN SELECT TOP 5 ID FROM Ens.MessageHeader` â†’ `{"prepareOK":true,"statementType":1,"columnCount":1,"columns":["Plan"],"executeSQLCODE":0,"rowCount":1,"firstCellLen":514,"firstCellSample":"<plans>\r\n <plan>\r\n   SQL:\r\n    SELECT TOP ? ID FROM Ens . MessageHeader ...\r\n   Cost: 20.2\r\n   Module-FIRST:\r\n     Module-B:\r\n     Read extent bitmap Ens.MessageHeader.Extent, looping on bitmap chunks...",...}` â€” one row, one `Plan` column of XML showplan, 514 chars (well under the 32 KB budget).
  - (b) `EXPLAIN INSERT` write-proof â†’ `{"sentinelBefore":0,"prepareOK":true,"statementType":1,"executeSQLCODE":-481,"rowCount":0,"sentinelAfter":0}` â€” prepares as type 1 (NOT 2), **execute FAILS (SQLCODE âˆ’481), zero rows, sentinel never written**.
  - (b2) `EXPLAIN DELETE` against a MATCHING row (definitive plan-only proof) â†’ `{"insertSQLCODE":0,"rowsBefore":1,"prepareOK":true,"statementType":1,"executeSQLCODE":0,"planRowCount":1,"rowsAfterExplain":1,"cleanupSQLCODE":0,"rowsAfterCleanup":0}` â€” EXPLAIN-of-DELETE executes, returns a plan row, and **the target row SURVIVES** (plan-only on this build). ALL `EXPLAIN <anything>` shapes prepare as statementType=1 (UPDATE/DELETE/WITH-SELECT/parenthesized/lowercase all probed).
  - (c) pre-change validator: all 4 EXPLAIN SELECT variants (bare/lowercase/block-comment/line-comment) rejected with `EXPLAIN is not allowed...` / `not_select` â€” confirming the flip surface.
  - (d) article accuracy vs guide Â§03: `parallel-hint` (placement + helps/hurts) and `ignoreindex-pattern` (placement + verified ~25x A/B case + caveat) faithful and actionable â€” no amendment; `cost-vs-runtime` faithful on cost-semantics but thin on READING a plan â€” amended (see AC-2).
- **AC-1 decision â€” REJECT-inner-write retained (the default).** Although the (b2) probe proves plan-only semantics on THIS build, the allowance stays SELECT-only because: plan-only is a per-build empirical premise (the statementType 1-vs-79 doc drift proves builds vary); `EXPLAIN INSERT` execute-fails with âˆ’481 anyway; the read-only covenant is the core guarantee. Inner `WITH` is also rejected (an `EXPLAIN WITH t AS (...) INSERT ...` CTE-write shape would otherwise need its own per-build proof). Implemented as a comment-aware TWO-token scan in `ValidateSingleStatement` (extends cr-14-3-A): first effective keyword `EXPLAIN` (any case) is allowed iff the second effective keyword is `SELECT`; comments are transparent BETWEEN tokens, so `/* c */ EXPLAIN INSERT`, `EXPLAIN /* c */ INSERT`, and `EXPLAIN/*c*/SELECT` all classify correctly (verbatim 11-shape matrix captured in-session). statementType gate now accepts 1 OR 79 (defensive; named friendly type kept).
- **AC-1 live dispatch envelopes (via `Tool.Registry.Dispatch`):** `EXPLAIN SELECT TOP 5 ID FROM Ens.MessageHeader` â†’ `{"render_strategy":"ok","columns":["Plan"],"rows":[["<plans>..."]],"row_count":1,"truncated":false,"elapsed_ms":132}`; lowercase + comment-prefixed `/* slow query investigation */ explain select ...` â†’ identical ok envelope; `EXPLAIN INSERT ...` dispatch â†’ `{"render_strategy":"not_select","error_text":"EXPLAIN is allowed only for a single SELECT statement (EXPLAIN SELECT ...); EXPLAIN of INSERT/UPDATE/DELETE or any other non-SELECT shape is rejected","isError":true}`.
- **AC-2:** (a) `cost-vs-runtime` body amended in `SeedContent` XData (plan result shape + access-path markers: 'Read extent bitmap' / 'Read index map' / 'Read master map' / temp-file = no short-circuit); `parallel-hint` + `ignoreindex-pattern` verified correct, untouched. Re-Seed â†’ returned 1 ($$$OK); `SELECT COUNT(*)` â†’ **47 total, 6 performance** (count unchanged). Retrieval evidence: `get_query_knowledge topic=performance` dispatch â†’ 3 articles incl. amended `cost-vs-runtime` body verbatim + `ignoreindex-pattern`; `topic=performance keywords='parallel hint'` â†’ `parallel-hint` body verbatim. (b) Card line added before the read-only covenant: *"For slow-query questions, run EXPLAIN on the SELECT and consult get_query_knowledge topic=performance before suggesting hints; only EXPLAIN of a SELECT is accepted."* Live CardCheck probe â†’ `{"hasExplainLine":true,"zeroDigits":true,"inspPromptHasCard":true,"searchPromptHasCard":true}` (both agents; digit-free; determinism + static-content + card-rides-system-segment tests all green in the sweep).
- **AC-3:** battery `TestCallAndExplainRejected` â†’ `TestCallAndExplainOfWriteRejected` (CALL unchanged; EXPLAIN INSERT/UPDATE/DELETE rejected + sentinel write-proof â€” the decision lock); new battery `TestExplainSelectAllowedAllForms` (bare/lowercase/comment-prefixed â†’ ok envelope, `columns=["Plan"]`, `<plans>` cell, untruncated, elapsed_ms â€” plan rows ride the same `RunGuardedSelect` caps); adversarial `TestCommentPrefixedExplainStaysReadOnly` keeps its no-mutation invariant (now also asserts the 14.6 allowance envelope, write-proof on bare + comment-prefixed); new adversarial `TestExplainOfWriteRejectedAllShapes` (bare/comment-interleaved/comment-prefixed/mixed-case/CTE-wrapped/UPDATE/lowercase-delete + sentinel write-proof). `ReadOnlySqlInvariantTest` untouched â€” EXPLAIN rides `RunGuardedSelect`, no bypass added. Per-class SQL ground-truth: battery **14/14**, adversarial **12/12**, AgentDefaultsTest **5/5**. **Full regression sweep (canonical numerical-MAX SQL probe): Total=626, Passed=626, Failed=0** = baseline 624 + 2 new (1 battery + 1 adversarial).
- **AC-4:** `execute_readonly_sql` `Description` parameter + `sql` arg schema description (L1) both gained the EXPLAIN clause (write-statements-under-EXPLAIN named as rejected); README "Guarded dynamic SQL" â€” tool-table row, pipeline step 1 (allowance + plan-only + reject-inner-write), step 2 (1-or-79 gate), and the proof-battery sentence updated.
- **AC-5 / Task 4:** story file `wc -l` â‰¤ 250 (verified at completion).
- **Formatter-hook re-grep at completion:** the hook reverted the `sql` arg description edit once (re-applied + re-verified); all other edits confirmed present by grep after final save.

### File List

- src/SessionAgent/Tool/Query/Base.cls (modified â€” EXPLAIN allowance: two-token comment-aware scanner, 1-or-79 gate, doc updates)
- src/SessionAgent/Tool/Query/ExecuteReadonlySql.cls (modified â€” Description + sql schema description EXPLAIN clause)
- src/SessionAgent/Knowledge/SeedContent.cls (modified â€” cost-vs-runtime body amendment, re-seeded live)
- src/SessionAgent/Config/AgentDefaults.cls (modified â€” digit-free EXPLAIN line on the methodology card, both agents)
- src/SessionAgent/Test/ReadOnlySqlProofBatteryTest.cls (modified â€” EXPLAIN expectation flips + decision lock + new allowance test; review added Registry.Dispatch e2e stanza per cr-14-6-A)
- src/SessionAgent/Test/ReadOnlySqlAdversarialTest.cls (modified â€” allowance flip in no-mutation lock + new EXPLAIN-of-write all-shapes test)
- src/SessionAgent/Test/AgentDefaultsTest.cls (modified â€” card EXPLAIN-line assertions)
- README.md (modified â€” Guarded dynamic SQL subsection + tool-table row)

## Review Findings (code-review stage, 2026-06-11)

**Verdict: APPROVED** â€” 1 MEDIUM auto-resolved, 2 dismissed (no bug shape), 0 deferred. All edits reloaded + compiled clean (198 classes, `iris_doc_load` glob rooted at `src/`); independent ground-truth sweep **629/629/0** (canonical numerical-MAX SQL probe) = baseline 624 + 2 dev + 3 QA.

### Security review (focus 1â€“2)

- **Two-token scanner re-traced line-by-line AND re-probed live** (`ValidateSingleStatement` via `iris_execute_classmethod`, HSCUSTOM 2026-06-11): `EXPLAIN/**/INSERT` â†’ rejected; `EXPLAIN -- c\nINSERT` â†’ rejected; `EXPLAIN(SELECT...)` â†’ rejected (capture ends at `(`, tok2 empty â€” fail-closed); `EXPLAINSELECT 1` â†’ NOT matched as EXPLAIN (single token â‰  "EXPLAIN"; falls to %Prepare which fails); bare `EXPLAIN` â†’ rejected (tok2 empty); `EXPLAIN<tab>SELECT` â†’ allowed (`$ZStrip "*WC"` treats tabs/control chars as separators); `eXpLaIn /*c*/ sElEcT` â†’ allowed; `EXPLAIN 'x' SELECT` â†’ rejected (string-literal ends capture, fail-closed). Inner-keyword check uses the SAME comment-aware state machine (comments transparent between tokens), not a substring. Every ambiguous shape resolves in the REJECT direction; unicode lookalikes form a non-matching token and die at %Prepare (fail-closed, out of scope per briefing).
- **statementType `(1|79)` gate â€” no widening for non-EXPLAIN input.** 79 is the documented EXPLAIN-only type (`irislib/%SQL/StatementMetadata.cls`); writes still prepare 2/3/4/45 and are rejected unchanged (proven by the untouched INSERT/UPDATE/DELETE/CALL battery + adversarial DDL tests, all green). On this build every EXPLAIN prepares as 1, so the 79 branch is dormant defensive surface; on a 79-reporting build only stage-1-approved `EXPLAIN SELECT` could reach it. Friendly name `79: "EXPLAIN"` present in `StatementTypeName`.
- **SQL-injection L4 reviewer confirmation (adapted 4-layer):** L1 schema-description priming updated with the EXPLAIN clause (verified in `%Dictionary.ParameterDefinition` on the server â€” formatter-hook revert did NOT recur); L2 statementType compiler gate `(1|79)` + comment-aware stage-1 keyword policy; L3 parameterless execution, nothing concatenated into operator SQL. All three present.

### Findings triage

- **cr-14-6-A (MEDIUM, RESOLVED â€” Rule 8 fix-now).** The AC-1 "live dispatch via `Tool.Registry.Dispatch`" claim was session-evidence only: every EXPLAIN test entered through `ExecuteReadonlySql.Invoke` directly, so a future Registry-layer change (arg screening, MutatesState gate, ToolCall-audit serialization of the plan-XML envelope) could break EXPLAIN dispatch with zero test failures (skill Rule 3 real-runtime-evidence gap). Fix: Registry.Dispatch e2e stanza appended to `TestExplainSelectAllowedAllForms` (`$$$OK` + ok-envelope + `Plan` column + `<plans>` cell). Battery 15/15 per SQL roster; sweep stays 629/629/0 (assertions added, no new method).
- **cr-14-6-B (LOW, DISMISSED â€” Rule 8 test 3, no bug shape).** Stage-3 rejection text "Only a single SELECT is allowed." omits the EXPLAIN SELECT allowance. Statements reaching that branch are writes/DDL for which the advice is operationally correct; stage-1 EXPLAIN rejections carry their own precise policy text; no test couples to the string. Cosmetic.
- **cr-14-6-C (DISMISSED â€” intentional policy, test-locked).** `EXPLAIN (SELECT ...)`, `EXPLAIN WITH ... SELECT`, and option forms (e.g. `EXPLAIN ALT SELECT`) are rejected by the conservative SELECT-only allowance. Rejection-direction-only behavior, documented in the class doc + error text, and policy-locked by `TestExplainEdgeShapes`. No action.

### Compliance checks

- **Test-intent preservation (focus 5):** `TestCommentPrefixedExplainStaysReadOnly` keeps both sentinel write-proofs and ADDS allowance-envelope assertions; `TestCallAndExplainOfWriteRejected` keeps CALL rejection and strengthens EXPLAIN handling with a sentinel write-proof; all pre-existing mutation-rejection tests untouched and green. Nothing weakened.
- **Card (focus 3):** new line digit-free (zero-digit assertion green), deterministic static literal, both agents (`TestMethodologyCardPresentBothAgents` + determinism green, 5/5 roster), names only `EXPLAIN`/`get_query_knowledge` (the `execute_readonly_sql`-absence assertion still green).
- **Corpus (focus 4):** amended `cost-vs-runtime` cross-checked against `docs/iris-query-guide/03-performance-and-plans.md` â€” plan-as-XML-`<plans>`/single-`Plan`-column, cost-is-estimate, `Read index map`/`Read master map` markers, temp-file no-short-circuit all faithful; `Read extent bitmap` marker matches the live Task 0 showplan verbatim. Live count **47 total / 6 performance**; Seed upsert-by-Slug idempotency preserved; retrieval round-trip locked by `TestPerformancePlanReadingGuidanceRetrievable` (Registry-dispatch e2e).
- **Rule 2 / Rule 9 / Rule 5 / Rule 6:** Completion Notes evidence shapes match each AC's Then-clause and were independently re-verified (compile, %Dictionary probe, scanner probes, per-class SQL rosters 15/13/5/12/4, full sweep 629/629/0); `deferred-work.md` has no entries naming 14.6; no NFR tripwire; ADR registry empty (none-required). README Â§"Guarded dynamic SQL" matches the implemented pipeline exactly (allowance, inner-write rejection, 1-or-79 gate, battery sentence).
