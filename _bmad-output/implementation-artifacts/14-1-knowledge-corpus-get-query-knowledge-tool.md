# Story 14.1: Knowledge Corpus + `get_query_knowledge` Tool

Status: done

**Source:** `sprint-change-proposal-2026-06-10.md` Â§4.1 FR62, Â§4.2 item 2 (decision D2 = XData seed), Appendix C (distillation map). Raw knowledge source: `docs/iris-query-guide/` (10 files). Seeding precedent: `src/SessionAgent/Search/SeedVocabulary.cls` + `Installer.Install` wiring (~line 122).

## Story

As an **operator asking analytical questions about message traces**, I want the agents to retrieve distilled IRIS-SQL/Interop expertise on demand via a `get_query_knowledge` tool over an install-seeded corpus, so that generated SQL avoids the dialect's silent-wrong-results traps without bloating the cached system prompt.

## Acceptance Criteria

**AC-1 â€” `SessionAgent.Knowledge.Article` persistent class.** Properties: `Slug` (%String MAXLEN 128, unique index, key for idempotent upsert), `Topic` (%String VALUELIST of the 7 topic enums below), `Title` (%String MAXLEN 256), `Keywords` (%String MAXLEN 1024, comma-separated lowercase), `Body` (%String MAXLEN 16000, ASCII-only â€” no Unicode arrows/dashes per the SeedVocabulary Rule 12 precedent). Class + property doc-comments are operator-readable (they surface in the SQL Catalog portal view).

> **Then** class compiles; `INFORMATION_SCHEMA.COLUMNS` shows the 5 columns; unique Slug index exists.

**AC-2 â€” `SessionAgent.Knowledge.SeedContent` XData corpus, ~35 articles.** A single class carrying the distilled corpus as XData blocks containing JSON arrays (one XData per topic group is acceptable; document the layout). Distill from `docs/iris-query-guide/` per the proposal's Appendix C map: **methodology** (methodology-loop; diagnostic-checklist), **dialect** (top-not-limit; %ID-joins; class-to-table; date-time-functions; decode-functions; integer-string-trap; case-and-%EXACT; list-extraction; stream-reading; groupby-restrictions; reserved-aliases; count-distinct-cost; prefix-match; hint-placement), **message-model** (persistence-projection; inheritance-extents-%CLASSNAME; header-spine; header-body-join; session-model; request-response-correlation; errors-on-response; additionalinfo-pivot), **performance** (cost-vs-runtime; parallel-hint; ignoreindex-pattern; indexing-realities; io-bound-vs-plan-bound; orphan-detection-caveats), **discovery** (custom-table-discovery-workflow; search-table-tip), **reference** (ens-messageheader-card; ens-util-log-card; hs-body-patterns â€” patterns only, names flagged verify-live per guide warning), **cookbook** (~12 parameterizable recipes per guide Â§07: daily-counts, error-rate-by-dimension, latency Ã—3, session-trace, noisy-error-grouping, aggregate-first-join, watermark-scan, doc-count, orphan-screen). The diagnostic-checklist article doubles as the SQLCODEâ†’hint source Story 14.3 will consume â€” structure its body as `SQLCODE <n> / symptom â†’ fix` lines.

> **Then** seeded article count is â‰¥ 33 and the count is locked in a test; every Appendix-C topic above is represented by â‰¥ 1 article; bodies are ASCII-only (test greps for bytes > 127).

**AC-3 â€” Idempotent `Seed()` + Installer wiring (NFR-R5).** `Seed()` parses the XData JSON and upserts by `Slug` (re-run = no duplicates, updated bodies overwrite). `SessionAgent.Installer.Install` invokes it after `SeedVocabulary.Seed()` and logs the post-seed article count to the install log (SeedVocabulary `LogPostSeedVocabularyCount` precedent).

> **Then** test runs `Seed()` twice and asserts stable count; Installer source shows the call + count-log line (grep evidence).

**AC-4 â€” `get_query_knowledge` tool.** New class `SessionAgent.Tool.Inspection.GetQueryKnowledge` extending `SessionAgent.Tool.Base` (registry auto-discovers; exposed to BOTH agents per D1). Args: `topic` (optional, enum of the 7 topics â€” schema `description` enumerates them as a genuinely-static taxonomy), `keywords` (optional free text; lowercase split on whitespace, matched against `Keywords` + `Title` via parameterized LIKE predicates), `max_results` (optional, default 3, hard max 5). At least one of `topic`/`keywords` required â€” else canonical validation-failure envelope. Result: matched articles (Slug, Title, Body) with total char budget â‰ˆ 16 KB and explicit `truncated` marker; `render_strategy:"ok"` with article count. Tool `Description` parameter primes usage: consult BEFORE authoring SQL, names the topic enum.

> **Then** dispatch via `Tool.Registry.Dispatch` returns â‰¥1 article for `topic="dialect", keywords="TOP integer status"`; keyword-only and topic-only calls work; both-empty returns validation failure; results bounded.

**AC-5 â€” Suite-verification updates.** `InspectionSuiteVerificationTest`: **bump `EXPECTEDTOOLCOUNT` 28â†’29 AND add `get_query_knowledge` to the `tExpected` $ListBuild AND add to `GetRepresentativeArgs`.** `ToolCallRoundtripIntegrationTest.TestMatrixCardinalityMatchesCatalog`: bump 112â†’116 (4 providers Ã— 29) and update its comment arithmetic.

> **Then** ISV passes with 29; cardinality test passes with 116; full regression sweep via `RegressionSweepCount()` = baseline 520 + new tests, 0 failures (verbatim Total/Passed/Failed captured).

**AC-6 â€” Tests.** New test class(es) â‰¤ ~500 lines each covering: seed idempotency + count lock; ASCII-body invariant; topic retrieval; keyword retrieval; combined topic+keyword; max_results clamp + char-budget truncation; validation-failure envelope; SQLCODE-hint-shape presence in the diagnostic-checklist article (Story 14.3 consumer contract: body contains at least `-29`, `-37`, `-400` hint lines).

**AC-7 â€” README same-commit update.** README tool catalog gains `get_query_knowledge` + a short "Query Knowledge corpus" subsection (operator-observable: new tool + seeded table + install-log line).

**AC-8 â€” Spec length â‰¤ 250 lines.**

## Integration ACs

Consumer 1 (in-story): `Tool.Registry.Dispatch("get_query_knowledge", ...)` e2e test returns article content (AC-4 "Then"). Consumer 2 (future): Story 14.3's SQLCODEâ†’hint map reads the diagnostic-checklist article (AC-6 locks the contract shape). Consumer 3 (future): Story 14.5 prompt card directs agents to this tool.

## Consumed-by

- Story 14.3 â€” `Tool.Query.Base` error envelopes pull hints from the diagnostic-checklist article body.
- Story 14.5 â€” methodology card names `get_query_knowledge`; golden questions GQ-* expect knowledge consultation.

## Tasks / Subtasks

- [x] **Task 0 â€” Pre-flight reads:** `SeedVocabulary.cls` (idempotent seed + NFR-R5 log), `Installer.Install` (~lines 100â€“130), `Tool.Base.cls` (envelope contract, validation helpers, `EnsureIsErrorOn*` helpers), one Epic 13 tool (e.g. `GetClassSource.cls`) as the registration template, ALL 10 `docs/iris-query-guide/` files (the distillation source). Capture the current `ListTools` count (28) as pre-state.
- [x] **Task 1 â€” `Knowledge.Article`** class (AC-1); compile.
- [x] **Task 2 â€” `Knowledge.SeedContent`** XData corpus (AC-2) + `Seed()` (AC-3). Distillation is the bulk of this story â€” compress each guide concept to a self-contained article body (â‰¤ ~2000 chars typical); cookbook recipes carry runnable parameterized SQL with placeholder markers.
- [x] **Task 3 â€” Installer wiring** + install-log count line (AC-3); compile; run `Seed()` live and capture count.
- [x] **Task 4 â€” `GetQueryKnowledge` tool** (AC-4); compile; live dispatch probe.
- [x] **Task 5 â€” Suite updates** (AC-5): ISV 29 + cardinality 116.
- [x] **Task 6 â€” Tests** (AC-6); per-class runs + ground-truth SQL sweep verbatim evidence.
- [x] **Task 7 â€” README** (AC-7) + story Completion Notes + File List; `wc -l` this file.

### Review Findings

Code review 2026-06-11 (4 parallel layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor, Corpus Content Auditor vs `docs/iris-query-guide/`). 0 HIGH. All MEDIUM + cheap LOW findings auto-resolved inline per Rule 8; 1 LOW deferred; 13 dismissed with rationale. Post-fix regression sweep (SQL ground-truth probe, verbatim): **Total=536 / Passed=536 / Failed=0**.

**SQL-injection 4-layer confirmation (reviewer layer 4, per iris-objectscript-basics.md):** Layer 1 âœ“ â€” `GetInputSchema` descriptions type-hint `topic` (static 7-value enum) and `keywords` (free text, whitespace-separated). Layer 2 âœ“ â€” `topic` validated against the static `$ListBuild` whitelist before any SQL (stronger than regex); `keywords` is free text by design and never reaches SQL text. Layer 3 âœ“ â€” every operator/LLM string binds via `?` placeholders (term patterns in the SELECT-list CASE score, topic in WHERE; binding order matches SQL textual order); the only inlined value is the clamped 1..5 integer `TOP`. Layer 4 âœ“ â€” this confirmation. `%EXACT` appears only in WHERE in the tool (no alias trap); test SELECTs using `%EXACT` carry explicit `AS` aliases. `$Char(0)` normalization N/A â€” no SQL UPDATE write path feeds these args (confirmed).

Resolved (fixed in this review pass, recompiled, re-tested):

- [x] [Review][Patch][MED] README stale FR59 traceability row "28 tools Ã— 4 providers = 112" + "17 tools total" inspection row (Rule 4 stale-reference / AC-7) [README.md:50,57] â€” updated to 18 tools / 29 Ã— 4 = 116 + Story 14.1 citation. (auditor; blind found adjacent prose)
- [x] [Review][Patch][MED] `LogPostSeedKnowledgeCount` missing `%SQLCODE` check after `%Execute` â€” runtime SQL failure logged as misleading "returned no rows" [src/SessionAgent/Installer.cls:636] â€” added `If tRS.%SQLCODE < 0` diagnostic branch. (edge+blind; note: the copied `LogPostSeedVocabularyCount` precedent has the same pre-existing gap, out of this story's diff)
- [x] [Review][Patch][MED] ASCII invariant covered `Body` only; `Title`/`Keywords`/`Slug` are envelope-rendered and were unchecked (Rule 12 mojibake shape) [src/SessionAgent/Test/KnowledgeCorpusTest.cls TestBodiesAsciiOnly] â€” test extended to scan all four text fields; passes (corpus already clean â€” reviewer's own >127-byte scan confirmed XData article rows are pure ASCII; the >127 bytes in SeedContent.cls are doc-comment em-dashes per codebase convention, outside the seeded bodies). (blind)
- [x] [Review][Patch][MED] Story Dev Agent Record carried stale pre-QA numbers (12 tests / 532/532/0) vs post-QA ground truth (16 tests / 536/536/0) â€” QA-stage addendum added to Change Log below (Rule 2 record accuracy). (auditor)
- [x] [Review][Patch][LOW] Keyword tokenizer split on space only â€” tab/newline-separated LLM input became one never-matching term; no length cap on `keywords` echo into envelope/audit row [src/SessionAgent/Tool/Inspection/GetQueryKnowledge.cls] â€” tabs/CR/LF/NUL now normalized to spaces before validation+tokenizing, keywords capped at 512 chars; locked by new assertions in `TestKeywordSpecialCharactersRobust`. (blind+edge)
- [x] [Review][Patch][LOW] `max_results` clamp comment claimed "floor 1" but `<1` resets to default 3; schema type `number` deviated from the family-wide `integer` convention [GetQueryKnowledge.cls] â€” comment corrected, schema type changed to `integer`. (blind+edge+auditor)
- [x] [Review][Patch][LOW] `Set:tX=$$$NULLOREF` no-op null guards removed ( `$$$NULLOREF` expands to `""`; `%Get` already returns `""` for missing/null) [GetQueryKnowledge.cls]. (blind+auditor)
- [x] [Review][Patch][LOW] Test fixture `%Save()` statuses unchecked (Write Status Checking) [GetQueryKnowledgeTest.cls SaveRankFixture + wildcard fixture] â€” helper now returns `%Status`, all 5 call sites assert `$$$AssertStatusOK`. (edge+auditor)
- [x] [Review][Patch][LOW] `TestInstallerWiresKnowledgeSeed` doc-comment claimed "compiled implementation" but reads the UDL source via `%Dictionary.MethodDefinition` [KnowledgeCorpusTest.cls] â€” doc-comment corrected; substring-grep limitation documented (accepted project pattern). (blind)
- [x] [Review][Patch][LOW] Cookbook XData doc-comment omitted 4 placeholders used in bodies (`{BodyTable}`, `{LookupSchema.LookupTable}`, `{Subclass1}`/`{Subclass2}`) [SeedContent.cls] â€” declared. (content auditor F-4)
- [x] [Review][Patch][LOW] `hs-body-patterns` dropped the guide's PSR MIN(ID)-dedupe pattern (06-reference-hs-message-tables.md:71-81) â€” one ASCII sentence restored to the article body; re-seeded live. (content auditor F-5)
- [x] [Review][Patch][LOW] Corpus `diagnostic-checklist` SQLCODE -400 hint line existed in no guide file (corpus-vs-source drift risk; the line itself is accurate IRIS knowledge and a Story 14.3 locked contract) â€” back-ported a `-400` row into `docs/iris-query-guide/00-query-methodology.md` diagnostic table so the guide stays the single source of truth. (content auditor F-1)

Deferred (see deferred-work.md):

- [x] [Review][Defer][LOW] `Seed()`/`UpsertArticle` exists-then-act TOCTOU under concurrent invocation [src/SessionAgent/Knowledge/SeedContent.cls:112-121] â€” deferred, no concurrent invocation path in supported flows.

Dismissed (counted, with rationale): "exposed to BOTH agents" unverified (refuted â€” `AgentLoop` calls unfiltered `Registry.ListTools()` for both agents; discovery is Super-based; live ISV 29-count + dispatch e2e pass); error envelope "missing render_strategy" on validation failures (false positive â€” bare `{isError, content}` IS the canonical validation envelope per sibling tools, e.g. GetClassSource.cls:112; `render_strategy` error variants apply to SQL prepare/execute paths, which route through the Tool.Base `Ensure*` helpers here); `additionalProperties:false` provider-hostility (family convention â€” 47 sibling occurrences, adapters handle it since Epic 5); ISV representative-args order dependency (refuted â€” topic-only dispatch against an unseeded corpus still returns the ok-shape envelope ISV asserts); README "47" in operator prose + v1.0.3 "28 total" release note (accurate today / historical narrative); topic taxonomy duplicated across 6 sites (test-locked: enum-size 7 + topic-representation tests); substring LIKE relevance quality (fuzzy by design; Story 14.5 golden questions measure it); `DeleteFixtureRows` silent catch (defensive cleanup; count-lock test fails loudly); `Seed()` no transaction (idempotent upsert self-heals on retry; install aborts loudly; count-lock guards); first-article truncation branch unreachable at current MAXLEN (defensive; documented); topic case-sensitivity (schema enum is lowercase; validation error names valid topics); exact-count lock environmental assumption (intended AC-2 lock); cycle-log timestamp anomaly (lead-owned artifact, noted to lead); corpus content INFO findings F-2/F-3/F-6/F-7/F-8/F-9/F-10 (unsourced-but-accurate glosses, guide-internal tensions mirrored faithfully, deliberate compression â€” content audit verdict: zero factual contradictions across all 47 articles).

## Dev Notes

- **Helper callout (Story 14.0 Carry-Forward, verbatim):** *"For SQL prepare failures call `##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName)`; for runtime execute failures call `EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName)` immediately after `%Execute` â€” do NOT construct raw `{"isError":1}` objects."*
- **Retrieval SQL:** parameterized `?` placeholders only (SQL-injection rule layers; keyword terms are operator/LLM input). `%EXACT()` in WHERE for case-sensitive Slug ops; for case-insensitive keyword match use `UPPER(Keywords) [ UPPER(?)`-style or LIKE with UPPER both sides. Do NOT put `%EXACT()` in the SELECT list without `AS` alias (rules Â§"%EXACT() in SELECT Changes Column Aliases" â€” prefer positional `%GetData(n)`).
- **Topic enum is a genuinely-static taxonomy** â€” enumerating it in the tool schema description is allowed (LLM Prompt Construction rule reserves enumeration for static taxonomies; this is one). Do NOT enumerate article titles/slugs anywhere in prompts or descriptions (those are runtime-seeded state).
- **XData parsing:** `##class(%Dictionary.CompiledXData)` or `%Dictionary.XDataDefinition` â†’ stream â†’ `%DynamicArray.%FromJSON`. Underscore keys in JSON need quoted property access (`obj."some_key"`).
- **ASCII-only bodies:** use `->`, `<=`, `"` ASCII forms. Mojibake precedent: Story 3.7 `Ã‚Â·` incident.
- **Substring-grep test pattern (Epic 12 AI-5 binding):** for any source-introspection assertion, enumerate ALL expected matches, replace each, then grep for the bare standard form.
- **No EnsPortal/Zen surface** in this story â€” Rule 12 layout evidence N/A; content-correctness only (ASCII test).
- **Method names:** no underscores; camelCase. Test classes â‰¤ ~500 lines â€” split the corpus tests from the tool tests if needed.
- **Subagent refs:** `irislib/%Dictionary/` for XData access APIs; `docs/iris-query-guide/` is the content source of truth; `sources/couchdb/` N/A.
- **Rule 10:** no external-system defaults set in this story (no model names, no endpoints) â€” no verification line required.

### References

- [Source: sprint-change-proposal-2026-06-10.md Â§4.1 FR62, Â§4.2 item 2, Appendix C]
- [Source: epics.md Â§Epic 14 Story 14.1 bullet]
- [Source: src/SessionAgent/Search/SeedVocabulary.cls â€” seed + NFR-R5 precedent]
- [Source: src/SessionAgent/Installer.cls ~lines 100â€“130 â€” wiring point]
- [Source: 14-0 story Â§Carry-Forward â€” helper + EXPECTEDTOOLCOUNT + substring-grep bindings]

## Dev Agent Record

### Agent Model Used

Claude Fable 5 (claude-fable-5[1m]) â€” bmad-dev-story under /epic-cycle, 2026-06-11.

### Debug Log References

- PostToolUse formatter hook reverted the `TestMatrixCardinalityMatchesCatalog` 112â†’116 assertion edit mid-task (story-specific caution confirmed live). Caught by re-grep, re-applied, re-verified: line 800 now asserts 116.
- `iris_execute_tests` envelope truncation observed on every class run (e.g. KnowledgeCorpusTest envelope showed 2 of 5 methods) â€” all pass/fail claims below come from the SQL ground-truth probe per object-script-testing.md.

### Completion Notes List

- **AC-1 (Article class).** Compiled clean. Verbatim `INFORMATION_SCHEMA.COLUMNS` probe: `[["ID","bigint"],["Body","varchar"],["Keywords","varchar"],["Slug","varchar"],["Title","varchar"],["Topic","varchar"]]` (5 property columns + ID). Verbatim `INFORMATION_SCHEMA.INDEXES`: `[["IDKEY","ID",0],["SlugIdx","Slug",0]]` â€” `SlugIdx` NON_UNIQUE=0 (unique).
- **AC-2 (corpus).** 47 articles seeded (â‰¥ 33 floor; locked at 47 in `KnowledgeCorpusTest.EXPECTEDARTICLECOUNT`). Verbatim topic distribution probe: `[["cookbook",12],["dialect",14],["discovery",2],["message-model",8],["methodology",2],["performance",6],["reference",3]]` â€” every Appendix-C topic represented. Body lengths 204â€“2677 chars (MAXLEN 16000). ASCII invariant locked by `TestBodiesAsciiOnly` (per-char `$Ascii > 127` grep over all 47 bodies, pass). Diagnostic-checklist contract probe (verbatim): `SELECT Slug ... WHERE Slug='diagnostic-checklist' AND Body LIKE '%SQLCODE -29 /%' AND Body LIKE '%SQLCODE -37 /%' AND Body LIKE '%SQLCODE -400 /%'` â†’ `[["diagnostic-checklist",2479]]` (1 row).
- **AC-3 (idempotent Seed + Installer).** `Seed()` run live twice: count 47 â†’ 47 (verbatim probes `[[47]]` / `[[47]]`). Installer grep evidence (verbatim): line 131 `Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()`, line 133 `Do ..LogPostSeedKnowledgeCount()`, line 627 `ClassMethod LogPostSeedKnowledgeCount() [ Private ]` â€” emits `"<count> query knowledge articles ensured"` (SeedVocabulary NFR-R5 precedent). Locked by `TestSeedIdempotencyAndCountLock`.
- **AC-4 (tool).** Live `Tool.Registry.Dispatch` envelope for `topic="dialect", keywords="TOP integer status"` (verbatim, bodies elided): `{"content":[{"type":"text","text":"get_query_knowledge: 3 article(s) for topic=dialect keywords='TOP integer status'"}],"structuredContent":{"articles":[{"slug":"integer-string-trap",...},{"slug":"decode-functions",...},{"slug":"top-not-limit",...}],"render_strategy":"ok","topic":"dialect","keywords":"TOP integer status","article_count":3,"truncated":false}}` â€” â‰¥1 article, relevance-ranked (2-term hit first). Topic-only probe returned 2 methodology articles; keyword-only (`"orphan delete"`, max_results=2) returned the 2 orphan articles (bounded); both-empty returned verbatim `{"isError":1,"content":[{"type":"text","text":"at least one of topic or keywords is required (topics: methodology, dialect, message-model, performance, discovery, reference, cookbook)"}]}`. Parameterized `?` LIKE predicates (terms UPPER-matched against Keywords+Title); score computed in a subquery (the corpus's own groupby-restrictions trap); only the clamped 1..5 integer row limit is inlined. Both `EnsureIsErrorOnPrepareFailure` / `EnsureIsErrorOnExecuteFailure` helpers used per the 14.0 carry-forward. Live registry count probe post-add: `[[29]]` (pre-state `[[28]]`).
- **AC-5 (suite bumps).** ISV: `EXPECTEDTOOLCOUNT` 28â†’29, `get_query_knowledge` added to `tExpected` $ListBuild + `GetRepresentativeArgs` (topic-only dialect args). Ground-truth roster: all 13 ISV methods Status=1. Roundtrip: cardinality assertion 112â†’116 + comment arithmetic (4 Ã— 29 = 116; 18 inspection + 11 search); ground-truth roster: all 4 methods Status=1 including `TestMatrixCardinalityMatchesCatalog`.
- **AC-6 (tests).** `KnowledgeCorpusTest` (5 methods) + `GetQueryKnowledgeTest` (7 methods), both â‰¤ 500 lines. Ground-truth rosters verbatim: KnowledgeCorpusTest `TestBodiesAsciiOnly/TestDiagnosticChecklistSqlcodeHintShape/TestEveryTopicRepresented/TestSeedIdempotencyAndCountLock/TestSlugUniqueIndexEnforced` all Status=1; GetQueryKnowledgeTest `TestBothEmptyValidationFailure/TestCharBudgetTruncation/TestCombinedTopicKeywordDispatchE2E/TestInvalidTopicValidationFailure/TestKeywordOnlyRetrieval/TestMaxResultsClamp/TestTopicOnlyRetrieval` all Status=1. Char-budget truncation exercised with two 9000-char `ztest-` fixtures (1 article returned, truncated=true; fixtures cleaned up). **Full regression sweep (SQL ground-truth probe, verbatim): `Total=532 / Passed=532 / Failed=0`** â€” reconciles exactly to the 520 pre-state baseline + 12 new tests.
- **AC-7 (README).** Tool catalog: 28â†’29 header, 17â†’18 inspection, `get_query_knowledge` row added; new "Query Knowledge corpus (Epic 14)" subsection documents the seeded table, idempotent seed, and the install-log verification line. Same commit as the code (lead commits post-smoke).
- **AC-8 (spec length).** Story file â‰¤ 250 lines (`wc -l` captured at sign-off: see Change Log).
- Temp dev probe class `SessionAgent.Test.ZTempProbe141` (used to capture the verbatim dispatch envelopes) deleted from both the namespace and the working tree before sign-off.

### Change Log

- 2026-06-11: Story 14.1 implemented â€” knowledge corpus (47 articles), idempotent Seed + Installer wiring, `get_query_knowledge` tool (29th tool), suite bumps (ISV 29 / cardinality 116), 12 new tests, README catalog + corpus subsection. Regression 532/532/0. Story file line count at sign-off: 119 lines per `wc -l` (â‰¤ 250, AC-8).
- 2026-06-11 (QA stage addendum, recorded at code review): QA added 4 tests â€” `TestInstallerWiresKnowledgeSeed` (KnowledgeCorpusTest now 6 methods), `TestRegistryListToolsIncludesGetQueryKnowledge`, `TestRelevanceRankingDeterministic`, `TestKeywordSpecialCharactersRobust` (GetQueryKnowledgeTest now 10 methods) â€” 16 new tests total this story; post-QA sweep 536/536/0 (520 baseline + 16). The dev-stage "12 new tests / 532/532/0" lines above were accurate pre-QA. QA stage also hit a sample-production drift incident (536/531/5 â†’ re-Bootstrap â†’ 536/536/0); see tests/test-summary.md.
- 2026-06-11 (code review): 0 HIGH; 4 MED + 8 LOW findings auto-fixed inline (README FR59/inspection-count rows, Installer `%SQLCODE` check, ASCII test extended to Title/Keywords/Slug, keyword tab/newline normalization + 512-char cap with new test locks, clamp comment + schema `integer`, `$$$NULLOREF` no-op removal, fixture `%Save` asserts, doc-comment corrections, Cookbook placeholder declarations, `hs-body-patterns` PSR MIN(ID) restoration, guide back-port of the SQLCODE -400 row); 1 LOW deferred (Seed TOCTOU); 13 dismissed. Corpus content audit vs `docs/iris-query-guide/`: zero factual contradictions across all 47 articles. Post-fix sweep (SQL ground-truth, verbatim): Total=536 / Passed=536 / Failed=0. See Review Findings.

### File List

- src/SessionAgent/Knowledge/Article.cls (new)
- src/SessionAgent/Knowledge/SeedContent.cls (new)
- src/SessionAgent/Tool/Inspection/GetQueryKnowledge.cls (new)
- src/SessionAgent/Installer.cls (modified â€” Seed call + LogPostSeedKnowledgeCount)
- src/SessionAgent/Test/KnowledgeCorpusTest.cls (new)
- src/SessionAgent/Test/GetQueryKnowledgeTest.cls (new)
- src/SessionAgent/Test/InspectionSuiteVerificationTest.cls (modified â€” 29 + tExpected + GetRepresentativeArgs)
- src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls (modified â€” 116 cardinality + comment)
- README.md (modified â€” tool catalog + Query Knowledge corpus subsection)
- _bmad-output/implementation-artifacts/14-1-knowledge-corpus-get-query-knowledge-tool.md (this file â€” tasks/record/status)
- _bmad-output/implementation-artifacts/sprint-status.yaml (status flips)
- docs/iris-query-guide/00-query-methodology.md (modified at code review â€” SQLCODE -400 row back-ported into the diagnostic checklist so the guide stays the corpus's single source of truth)
- _bmad-output/implementation-artifacts/deferred-work.md (code-review deferral entry)
