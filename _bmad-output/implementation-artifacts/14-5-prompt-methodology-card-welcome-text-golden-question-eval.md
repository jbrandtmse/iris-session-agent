# Story 14.5: Prompt Methodology Card + Welcome Text + Golden-Question Eval Pass (FR64)

Status: done

**Source:** `sprint-change-proposal-2026-06-10.md` Â§4.1 FR64, Â§3.2 principles 2/6, Â§4.4. Precedents: `src/SessionAgent/Config/AgentDefaults.cls` `GetSystemPrompt()` (prompt assembly; per-row `SystemPromptOverride` semantics unchanged), `static/chat-panel.js` `renderWelcomeMessage()` (~line 679; verbatim before-state captured in Story 14.0 AC-5 Completion Notes), `_bmad-output/implementation-artifacts/epic-14-golden-questions.md` (13 GQ entries), Story 12.6 `node -c` syntax-check precedent.

## Story

As an **operator asking analytical questions**, I want both agents' system prompts to carry the dialect-trap methodology card and the chat panel to advertise the new capabilities, so that the agents use the Epic 14 toolchain correctly by default and operators know they can ask the new question classes.

## Acceptance Criteria

**AC-1 â€” Methodology card in both system prompts.** `AgentDefaults.GetSystemPrompt()` appends a static "query methodology & dialect card" to BOTH agents' prompts containing: (a) the discoverâ†’knowledgeâ†’buildâ†’executeâ†’validate loop directive; (b) the cardinal dialect traps as a genuinely-static taxonomy (TOP not LIMIT; integer-enum predicates â€” never quote integer enums; `%EXTERNAL`/`%ODBCOUT` decode choice; headerâ†”body joins need id+class; always time-bound exploratory queries; TOP-N preview habit; `ID = SessionId` session anchor); (c) the FR64-mandated directives: consult `get_query_knowledge` and `get_schema_notes` BEFORE authoring SQL, save durable discoveries via `save_schema_note`, and **disclose executed SQL in answers**; (d) the read-only covenant line. Content is STATIC â€” no runtime-state enumeration (tool-catalog lists, counts, provider names, namespaces are all FORBIDDEN in the card per the LLM Prompt Construction rule; the three FR64-named tool references above are the PRD-mandated exception and the only tool names allowed). `SystemPromptOverride` per-row semantics unchanged (override replaces the default INCLUDING the card â€” document this; the card is part of the default prompt, not a separate channel).

> **Then** `GetSystemPrompt("session-inspection")` and `GetSystemPrompt("message-search")` both contain the card verbatim-identically; output is deterministic across repeated calls (byte-identical â€” NFR-P6); no runtime-derived values appear in it (test asserts no digits that change run-to-run, no tool-count claims).

**AC-2 â€” Welcome-text capability update (Rule 4 watch-item closure).** Update BOTH `renderWelcomeMessage()` branches in `static/chat-panel.js` from the Story 14.0-captured before-state: add the new capability areas in operator phrasing â€” analytical/statistics questions answered with read-only SQL (disclosed in the answer), schema discovery for unfamiliar message types, and remembered per-namespace schema notes. Use capability-AREA phrasing with one or two example questions (e.g. "what's the error rate by target in the last 24 hours?"); do NOT enumerate tool names or counts (the Epic 4â†’8 stale-enumeration class). Keep the existing `Â·` example-separator style, readable English, read-only reassurance retained.

> **Then** rendered welcome text for BOTH agents captured (browser `textContent` paste or screenshot â€” Rule 12 content-correctness evidence) and human-read: readable English, no mojibake (`Ã‚`, `Ã¢â‚¬â„¢`), no tool-name enumeration, new capability areas present; `node -c` (syntax check) on the modified `chat-panel.js` exits 0 (Story 12.6 precedent).

**AC-3 â€” Prompt-cache stability (NFR-P6).** The card rides INSIDE the cached `system` segment (static, deterministic) â€” the existing cache-stability tests (incl. the Story 14.4 extension) still pass; a new assertion locks `GetSystemPrompt` determinism (two calls, byte-identical) for both agents.

> **Then** cache-stability + AgentLoop injection tests green; determinism test added and green.

**AC-4 â€” Mock-matrix golden-question run.** For each of the 13 GQ entries in `epic-14-golden-questions.md`, execute the entry's "expected agent behavior" tool chain mechanically via real `Tool.Registry.Dispatch` against the live sample production (e.g., GQ-1 daily counts â†’ `execute_readonly_sql` with the cookbook recipe SQL; GQ-5 active body types â†’ `list_active_body_types`; GQ-6 describe + pivot â†’ `describe_message_class` then `execute_readonly_sql`; GQ-10 trap â†’ run BOTH the trapped form and the corrected form, demonstrating the silent-wrong-results delta; schema-note GQ â†’ save then re-read). Record per-GQ results (tool(s) dispatched, envelope outcome, row counts, pass/fail vs the entry's pass criteria) in a new section appended to `epic-14-golden-questions.md` ("Mock-matrix run â€” Story 14.5, <date>"). This validates the toolchain mechanics; the LLM-driven pass is the epic-end user-led walkthrough (Rule 6 bullet 5).

> **Then** all 13 entries have a recorded outcome; any failure is fixed (Rule 8) or explicitly blocked-documented; GQ-10's delta is shown with verbatim row counts (trap returns wrong/empty result silently; corrected form returns truth).

**AC-5 â€” README finishing pass.** Knowledge-subsystem section covers corpus + schema notes + guarded SQL + prompts story; tool catalog reconciled at 35; welcome-text + prompt-card capabilities described for operators.

**AC-6 â€” Tests.** New/extended: card presence both agents + determinism (AC-1/3); welcome-text content assertions in the existing chat-panel JS test class (enumerate-all-replace-each-then-grep per the substring-grep binding â€” assert new capability phrases present AND stale-enumeration absent); `SystemPromptOverride` replacement semantics (incl. `$Char(0)` sentinel normalization on the override read site â€” verify the existing read site handles it; add the check if missing). NO EXPECTEDTOOLCOUNT change (stays 35) â€” assert unchanged. Full sweep = baseline 616 + new, 0 failures (verbatim ground-truth probe).

**AC-7 â€” Spec â‰¤ 250 lines.**

## Integration ACs

In-story: AC-4 exercises the full Epic 14 toolchain (14.1+14.2+14.3+14.4 deliverables) through the real registry against live data â€” the epic's integration seam. AC-1's card is consumed by both agents' live turns (verified at the epic-end user-led walkthrough with the capability-enumeration turn per the LLM Prompt Construction rule's runtime check).

## Consumed-by

- Epic-end Rule 6 battery â€” bullet 5 user-led golden-question chat-panel walkthrough builds directly on AC-4's mock-matrix results.
- Story 14.6 (stretch) â€” card gains an EXPLAIN guidance line only if 14.6 ships.

## Tasks / Subtasks

- [x] **Task 0 â€” Pre-flight:** read `AgentDefaults.cls` `GetSystemPrompt` (current prompts + override semantics + any `$Char(0)` handling), `static/chat-panel.js` lines ~670â€“700 (both welcome branches; reconcile against the 14.0-captured before-state), `epic-14-golden-questions.md` (all 13 entries), existing chat-panel JS test class + cache-stability tests (names + shapes). Capture pre-state `GetSystemPrompt` outputs verbatim.
- [x] **Task 1 â€” Methodology card** (AC-1); compile; capture post-state prompts.
- [x] **Task 2 â€” Welcome text** (AC-2); `node -c` evidence; rendered-text capture + human-read note.
- [x] **Task 3 â€” Cache-stability + determinism** (AC-3).
- [x] **Task 4 â€” Mock-matrix GQ run** (AC-4); append results section; fix-now any toolchain failure surfaced.
- [x] **Task 5 â€” README** (AC-5).
- [x] **Task 6 â€” Tests** (AC-6); ground-truth sweep verbatim.
- [x] **Task 7 â€” Completion Notes + File List; `wc -l` â‰¤ 250.**

### Review Findings

Code review 2026-06-11 (3 layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). 0 decision-needed, 7 patch (all applied), 1 defer, 9 dismissed.

- [x] [Review][Patch][HIGH] SystemPromptOverride mutated on live Config.Agent rows with no exception-safe restore â€” both new tests inline-restored on the straight-line path only (`OnAfterOneTest` restored only Enabled/Provider â€” verified); the card-channel test additionally mutated+saved the inspection row BEFORE validating the message-search row, so a missing search row early-`Quit` left the inspection override wiped. Six `%Save()` statuses were also discarded. Fixed: `OrigInspOverride`/`OrigSearchOverride` (MAXLEN="") snapshot/restore added to `OnBeforeOneTest`/`OnAfterOneTest`; both-rows-validated-before-either-mutated ordering; `$$$AssertStatusOK` on all 7 mutating `%Save()` calls. [src/SessionAgent/Test/AgentLoopSchemaDigestTest.cls]
- [x] [Review][Patch][MED] `GoldenQuestionDriver.RunTool` hardcoded `AgentName="session-inspection"` and never set `SearchSessionKey` â€” search-side dispatches in the epic-end battery would mis-attribute audit `ChatHistoryId` (Registry.Dispatch `$Case` on AgentName). Fixed: `pAgentName` 4th parameter (default `"session-inspection"` â€” AC-4 matrix results unaffected); message-search routes `pSessionId` â†’ `SearchSessionKey`. Note: tool *resolution* is agent-agnostic (`ListTools()` is a flat 35-tool catalog â€” verified), so only attribution/context was affected. [src/SessionAgent/Test/GoldenQuestionDriver.cls]
- [x] [Review][Patch][MED] Completion Notes + File List were stale vs the post-QA diff (claimed 5 new tests / 621 sweep / 1 new AgentLoopSchemaDigestTest test; omitted GetQueryKnowledgeTest.cls + SearchAgentRenderTest.cls). Corrected below; reviewer re-verified ground-truth sweep. [this file]
- [x] [Review][Patch][LOW] Served-asset HTTP guard accepted any >10KB non-login 200 body as the asset (gateway error page / auth interstitial â†’ spurious hard failure). Fixed: positive marker `renderWelcomeMessage` required. [src/SessionAgent/Test/SearchAgentRenderTest.cls]
- [x] [Review][Patch][LOW] Search half of `TestMethodologyCardRidesSystemSegmentBothAgents` was vacuous-pass-prone (no positive assertion the digest rode the search USER block). Fixed: positive-control assertion added. [src/SessionAgent/Test/AgentLoopSchemaDigestTest.cls]
- [x] [Review][Patch][LOW] Driver smoke's `isError=0` assertion passed spuriously on `driverError` envelopes (`+""=0`). Fixed: early `Quit` when `driverError` non-empty. [src/SessionAgent/Test/GetQueryKnowledgeTest.cls]
- [x] [Review][Patch][LOW] README Â§Status said "All 13 planning + implementation epics complete" while the same file now advertises three Epic 14 capability rows (Rule 4 operator-facing stale text). Fixed: Epic-14-in-progress clause added. [README.md:506]
- [x] [Review][Defer][LOW] Served-asset test silently degrades to file-on-disk fallback with no skip/fallback marker, and hardcodes `/csp/hscustom` + `_SYSTEM/SYS` â€” pre-existing pattern shared verbatim with Story 10.2's `TestChatPanelAssetServesNewBytes`; a proper fix (fallback marker + namespace/prefix-aware URL) should change both tests together â€” deferred, pre-existing. [src/SessionAgent/Test/SearchAgentRenderTest.cls]

Dismissed (9, with verification evidence): (1) seeded `ztest-al-card-chan` note cleanup â€” handled by `SweepFixtures` â†’ `SchemaNoteToolTest.DeleteFixtureRows` (`ztest-` prefix DELETE), which runs in BOTH `OnBeforeOneTest` and `OnAfterOneTest` (verified in source); (2) Dev-Notes "plus `execute_readonly_sql`" wording vs AC-1's three-names rule â€” Dev Notes granted an allowance the dev did not use; AC-1 is the contract, satisfied and test-locked (`TestMethodologyCardStaticContent` asserts the name absent); (3) README 23+11+1=35 accounting â€” verified: `Registry.ListTools()` is a flat catalog (no per-agent scoping), partition sums to 35 = EXPECTEDTOOLCOUNT, search-row prose correctly acknowledges runtime sharing; (4) determinism test "tautological" â€” it implements AC-3's exact Then-clause and serves as a regression tripwire; (5) `gq-driver` audit rows â€” NFR-S4 unconditional audit emit is by design, rows are honest records; (6) file-global tool-name absence assertions â€” intentional per AC-2/AC-6 stale-enumeration enforcement; (7) driver `<MAXSTRING>` on oversized envelopes â€” bounded by Story 14.3 row caps, and the error text is surfaced verbatim (not swallowed); (8) AC-2 browser-rendered capture deferred to lead smoke â€” explicitly authorized by this story's Dev Notes; the lead's post-review smoke is the remaining Rule 12 browser gate; (9) hardcoded dev-instance credentials â€” accepted suite pattern with graceful fallback (overlaps the defer above for the structural fix).

**Reviewer verification (Rule 2 evidence):** ground-truth sweep re-run post-patch â€” see addendum in AC-6 note below; `GetMethodologyCard` invoked live via `iris_execute_classmethod` and human-read (zero digits confirmed by `$Translate` inspection of the verbatim return; only `get_query_knowledge`/`get_schema_notes`/`save_schema_note` tool names; read-only covenant present; ~1.4 KB â‰ˆ 300 tokens â€” acceptable weight for the cached system segment); welcome strings human-read from source + diff (readable English, `Â·` separators intact, no mojibake, no tool names); `$Char(0)` normalization confirmed pre-existing at AgentLoop.cls:218 with the override read at lines 350-355; `node -c static/chat-panel.js` exit 0 (re-run); card dialect-trap statements verified against `docs/iris-query-guide/` Â§00/Â§01/Â§02 by the Acceptance Auditor (all factually consistent); GQ-matrix arithmetic cross-checked (223 = GQ-5 sum 124+66+33; 27 = GQ-2 = GQ-3 error counts; GQ-6 pivot 68+52+4 = 124 = GQ-12 router count); `GoldenQuestionDriver` extends `%RegisteredObject` in `SessionAgent.Test.*` â€” doubly excluded from registry discovery (Super-filter + Test-prefix exclusion verified in `ListTools` SQL); no `Test*` properties or underscore method names introduced.

## Dev Notes

- **LLM Prompt Construction rule is load-bearing here** (Epic 3 AI-15; commit `768be17` incident): the card must NOT enumerate the tool catalog, counts, providers, or any runtime-seeded state. The three FR64-named tools (`get_query_knowledge`, `get_schema_notes`, `save_schema_note`) plus `execute_readonly_sql` referenced as the disclosure subject are the only permitted tool names â€” they are PRD-contract references, not a capability list. The dialect-trap list is a genuinely-static taxonomy (allowed).
- **Do not cite envelope field names in the card** (e.g., `has_additional_info` â€” its rename is an open deferral; coupling the prompt to envelope internals creates drift).
- **Welcome text is operator-facing UI** (Rule 12): content-correctness evidence (textContent paste acceptable; screenshot better); ASCII-vs-UTF-8 â€” the existing `Â·` separators are correct UTF-8 since fix `ebde251`; keep the file's existing encoding, no new exotic characters.
- **chat-panel.js is a class-served asset** â€” verify how it ships (`SessionAgent.UI.ChatPanelAsset` stream) and whether an IRIS-side recompile/reload is needed for the new text to serve; capture the served bytes if cheap (HTTP GET) for the evidence.
- **Helper callout (14.0 Carry-Forward)** applies to any new ObjectScript SQL in tests/probes: prepare/execute helpers, no raw isError objects.
- **Mock-matrix run mechanics:** use a temporary driver classmethod or test methods; if a GQ's recipe SQL trips a real dialect trap during the run, that is the system working â€” record the hint-bearing envelope and the corrected query per the GQ's pass criteria. Clean up any rows the schema-note GQ writes (`ztest-` prefix + delete).
- **Substring-grep binding (Epic 12 AI-5)** for the welcome-text assertions: enumerate ALL expected phrases, assert each, then assert absence of the stale before-state phrasing where it should have changed.
- **`$Char(0)` rule:** `SystemPromptOverride` is a Config.Agent `%String` column with a SQL-UPDATE write path (Zen form) â€” its read site in `GetSystemPrompt` MUST normalize `$Char(0)` â†’ `""` (verify existing handling; fix-now if missing â€” this is the canonical grep-target).
- **Rule 10:** no external defaults â€” N/A.
- **Subagent refs:** `irislib/` N/A mostly; `docs/iris-query-guide/00-query-methodology.md` (card content source); chrome-devtools MCP available to the LEAD for rendered-text capture â€” the dev may use HTTP GET + textContent-equivalent extraction; the lead's smoke covers the browser pass.

### References

- [Source: sprint-change-proposal-2026-06-10.md Â§4.1 FR64, Â§4.4]
- [Source: epics.md Â§Epic 14 â€” 14.5 bullet]
- [Source: 14-0 story Completion Notes AC-5 â€” verbatim welcome-message before-state]
- [Source: .claude/rules/iris-objectscript-basics.md Â§"LLM Prompt Construction" + Â§"$Char(0) sentinel"]
- [Source: _bmad-output/implementation-artifacts/epic-14-golden-questions.md]

## Dev Agent Record

### Agent Model Used

claude-fable-5[1m] (Claude Fable 5)

### Debug Log References

- Package-level `iris_execute_tests` created orphaned work-queue runs (TestInstance 234/240, 0 recorded methods) and one transient interference failure in `SchemaNoteIntegrationTest:TestCrossConversationSaveThenDigestInjection` (run 235 â€” concurrent in-flight package execution swept the `ztest-` fixture mid-test); 6/6 green on isolated re-run (run 239). Per-class invocation + SQL ground-truth probe used throughout per the codified workaround.

### Completion Notes List

- **AC-1.** `GetMethodologyCard()` added to `AgentDefaults`; appended (single space joiner) to BOTH agents' default prompts; unknown-agent fallthrough still returns `""`. Card content: loop directive, 7 cardinal dialect traps, the 3 FR64-named tool directives + SQL-disclosure, read-only covenant. Zero digit characters by construction (locks "no run-to-run numeric drift / no tool-count claims"); no tool names beyond the 3 FR64 references (verified by test: `session_summary` / `execute_readonly_sql` / `list_active_body_types` / provider names all asserted absent). Post-state prompts captured verbatim via `iris_execute_classmethod` â€” both end with the identical card text "Query methodology and dialect card: â€¦ Read-only covenant: you may only ever SELECT â€” never write, update, delete, or alter anything."
- **AC-1/AC-6 â€” `$Char(0)` + override semantics.** The read-site normalization ALREADY EXISTS at `AgentLoop.cls:218` (Story 6.0) â€” verified, no fix needed. New test `AgentLoopSchemaDigestTest:TestSystemPromptOverrideReplacesDefaultIncludingCard` locks both: non-empty override reaches the provider-bound system prompt and does NOT contain the card (override replaces default INCLUDING card); `$Char(0)` sentinel normalizes to `""` â†’ default WITH card used, no NUL leaks. Status=1 verbatim in run 233.
- **AC-2.** Both `renderWelcomeMessage()` branches extended with the shared capability sentence ("I can also answer analytics and statistics questions with read-only SQL (I always show the SQL I ran), describe unfamiliar message types, and remember schema notes for this namespace.") + one analytic example each ("what's the error rate by target in the last 24 hours?" / "how many messages per day went through the order router this month?"); stale examples ("find sessions matching X", "which messages had OrderRequest bodies") replaced; `Â·` separators kept. `node -c` exit 0. Served-bytes evidence: HTTP 200 GET `/csp/hscustom/SessionAgent.UI.ChatPanelAsset.cls` (98,313 bytes, UTF-8) â€” capability sentence Ã—2, both examples present, stale examples 0 occurrences, `errors? Â· what's the error rate` renders with a real U+00B7. Human-read note (Rule 12 content-correctness): both strings read as natural English; no mojibake (`Ã‚`/`Ã¢â‚¬â„¢` absent); no tool-name enumeration. No IRIS-side reload needed â€” `ChatPanelAsset` streams the repo file at request time (`TranslateTable=UTF8`); `SearchAgentRenderTest:ChatPanelAssetServesNewBytes` independently re-confirmed post-change.
- **AC-3.** Card is static â†’ deterministic. New `AgentDefaultsTest:TestGetSystemPromptDeterminism` (two calls byte-identical, both agents) green. Existing cache-stability tests green post-change: `AgentLoopVocabDigestTest` 6/6 (run 232), `AgentLoopSchemaDigestTest` 8/8 incl. the Story 14.4 inspection-agent extension (run 233).
- **AC-4.** Mock-matrix run appended to `epic-14-golden-questions.md` Â§"Mock-matrix run â€” Story 14.5, 2026-06-11": **13/13 PASS + schema-note round-trip PASS, zero toolchain failures** (nothing to fix-now). All dispatches through real `Tool.Registry.Dispatch` via new `SessionAgent.Test.GoldenQuestionDriver.RunTool` against the live sample production (`IsProductionRunning=1`). GQ-10 trap delta verbatim: window total **223**; trapped `WHERE Status != 'Completed'` â†’ **223** (every row silently matched, SQLCODE 0); corrected `%EXTERNAL(Status) != 'Completed'` â†’ **27**. Two walkthrough notes recorded: Arabic NLS severity label in `%ODBCOUT` rendering (server-side, identical via direct SQL); SELECT-list case folding without `%EXACT`.
- **AC-5.** README: per-agent counts in the v1.0.4 summary table reconciled to the 35-tool catalog (23 + 11 + 1 shared); new summary row for Story 14.5; new Â§"Query methodology card + welcome text (Epic 14 â€” Story 14.5, FR64)" documenting card content, NFR-P6 determinism, override-replaces-card semantics (operators who override should copy the card), and the operator-visible welcome capability areas.
- **AC-6.** 5 new dev-stage tests: `TestMethodologyCardPresentBothAgents`, `TestMethodologyCardStaticContent`, `TestGetSystemPromptDeterminism` (AgentDefaultsTest), `TestWelcomeMessageEpic14Capabilities` (ChatPanelJsTest â€” enumerate-all-then-grep-stale per Epic 12 AI-5), `TestSystemPromptOverrideReplacesDefaultIncludingCard` (AgentLoopSchemaDigestTest). EXPECTEDTOOLCOUNT unchanged at 35 â€” `InspectionSuiteVerificationTest:TestRegistryListsExpectedToolCount` Status=1 verbatim (run 238). Dev-stage ground-truth sweep: 621/621/0 = baseline 616 + 5. **[Review correction 2026-06-11]** QA stage added 3 further tests (`TestMethodologyCardRidesSystemSegmentBothAgents` â€” AgentLoopSchemaDigestTest; `TestChatPanelAssetServesEpic14CapabilitySentence` â€” SearchAgentRenderTest; `TestGoldenQuestionDriverSmoke` â€” GetQueryKnowledgeTest), so the story total is **8 new tests**; **final ground-truth sweep (canonical numeric-MAX SQL probe, re-run by reviewer post-review-patches): Total 624 / Passed 624 / Failed 0** = baseline 616 + 8. Every class reading the changed surfaces re-ran green post-change.
- **AC-7.** Story file `wc -l` = 84 pre-record; re-verified â‰¤ 250 at sign-off.
- **Decision:** `GoldenQuestionDriver` retained (not deleted) as the epic-end Rule 6 bullet-5 battery's mechanical dispatch helper â€” documented in its class banner; it is not a `%UnitTest.TestCase` and adds no test methods.

### File List

- src/SessionAgent/Config/AgentDefaults.cls (modified â€” methodology card + GetSystemPrompt restructure)
- static/chat-panel.js (modified â€” both welcome branches, AC-2)
- src/SessionAgent/Test/AgentDefaultsTest.cls (modified â€” 3 new tests)
- src/SessionAgent/Test/ChatPanelJsTest.cls (modified â€” 1 new test)
- src/SessionAgent/Test/AgentLoopSchemaDigestTest.cls (modified â€” 2 new tests + review fix: override snapshot/restore in OnBefore/OnAfterOneTest)
- src/SessionAgent/Test/SearchAgentRenderTest.cls (modified â€” 1 new QA test: served-asset Epic 14 sentence + review fix: positive asset marker)
- src/SessionAgent/Test/GetQueryKnowledgeTest.cls (modified â€” 1 new QA test: GoldenQuestionDriver smoke + review fix: driverError early-quit)
- src/SessionAgent/Test/GoldenQuestionDriver.cls (new â€” AC-4 dispatch driver; review fix: pAgentName parameter + SearchSessionKey attribution)
- _bmad-output/implementation-artifacts/epic-14-golden-questions.md (modified â€” mock-matrix results section)
- README.md (modified â€” AC-5 finishing pass)
- _bmad-output/implementation-artifacts/14-5-prompt-methodology-card-welcome-text-golden-question-eval.md (this file â€” record sections)
- _bmad-output/implementation-artifacts/sprint-status.yaml (status flip)
