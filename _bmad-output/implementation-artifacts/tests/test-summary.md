# Test Automation Summary — Story 14.5 (qa-generate-e2e-tests stage, 2026-06-11)

**Env:** IRIS HSCUSTOM (sample production running). Framework: IRIS `%UnitTest` (ObjectScript).
New tests exercise the real `SessionAgent.Agent.AgentLoop.RunTurn` runtime (VocabDigestCaptureMock
provider override), the real served-asset HTTP path (`%Net.HttpRequest` against
`SessionAgent.UI.ChatPanelAsset`), and the real `Tool.Registry.Dispatch` path via
`GoldenQuestionDriver`.

## Scope

GAP coverage only for Story 14.5 (methodology card + welcome text + GQ eval). The dev battery
(5 tests: card presence both agents, static-content zero-digits, determinism, welcome-text
capability phrases + stale-absence, override-replaces-default-including-card) already locks the
AC matrix. Baseline before this stage: ground-truth probe **621/621/0**.

## Gap Assessment (candidates from the stage briefing)

- **(a) card AND digest cache-channel coexistence — REAL GAP (negatives missing), added.**
  14.4's `TestAnthropicCachedPrefixUnchangedInspectionAgent` proves the system segment is
  turn-stable, but a digest wrongly riding the system segment would be byte-identical across
  turns and slip past it. Nothing asserted digest-ABSENT-from-SYSTEM or card-ABSENT-from-USER.
  Added a first-turn test (note seeded, digest live) asserting card-in-SYSTEM,
  digest-not-in-SYSTEM (schema + vocab), digest-in-USER, card-not-in-USER.
- **(b) provider-bound card at AgentLoop runtime — REAL GAP for message-search, added.**
  The dev's override test covers session-inspection only; message-search card coverage was
  AgentDefaults-unit-level. The same new test runs BOTH agents through `RunTurn` and asserts
  the card reaches each provider-bound system prompt (overrides cleared + restored in-test).
- **(c) welcome text in the SERVED asset — REAL GAP, added.** `ChatPanelJsTest` reads the
  filesystem; the existing HTTP-path test (`SearchAgentRenderTest:TestChatPanelAssetServesNewBytes`)
  asserts only Story 10.2 identifiers, not the Epic 14 sentence. Added an HTTP-fetch test (same
  auth/login-page-guard/file-fallback pattern, loop-read for the ~98 KB body since the welcome
  branches sit near the tail) locking the capability sentence, SQL-disclosure reassurance, the
  inspection-branch analytic example, and stale-example absence in the served bytes.
- **(d) GoldenQuestionDriver smoke — REAL GAP, added.** The driver gates the epic-end Rule 6
  battery but is not a TestCase; nothing would catch signature drift or envelope-serialization
  break. Added ONE cheap GQ (`get_query_knowledge`, `topic=dialect` — corpus read, no
  trace-table SQL, corpus seeded by the host class's `OnBeforeOneTest`) asserting parseable
  JSON, no `driverError`, `isError=0`, `render_strategy='ok'`, `article_count >= 1`.

## Generated Tests

- [x] `src/SessionAgent/Test/AgentLoopSchemaDigestTest.cls` — `TestMethodologyCardRidesSystemSegmentBothAgents` (gaps a+b)
- [x] `src/SessionAgent/Test/SearchAgentRenderTest.cls` — `TestChatPanelAssetServesEpic14CapabilitySentence` (gap c)
- [x] `src/SessionAgent/Test/GetQueryKnowledgeTest.cls` — `TestGoldenQuestionDriverSmoke` (gap d)

## Results

- Per-class runs all green (SQL ground-truth rosters): `AgentLoopSchemaDigestTest` 9/9,
  `SearchAgentRenderTest` 5/5, `GetQueryKnowledgeTest` 11/11.
- Full-suite ground-truth probe (canonical numeric-MAX form): **Total 624 / Passed 624 / Failed 0**
  = baseline 621 + 3 new.
- Rule 8 discoverability: all 3 tests are `Test*` methods on existing `SessionAgent.Test.*`
  `%UnitTest.TestCase` classes — discovered by the default per-class sweep and the
  `LIKE 'SessionAgent.Test.%'` SQL probe; no tags/ignores. Class sizes post-change:
  464 / 363 / 375 lines (all ≤ 500 per test-hygiene rule).

## Next Steps

- Epic-end Rule 6 battery: the bullet-5 user-led walkthrough builds on `GoldenQuestionDriver`
  (now smoke-locked) and the AC-4 mock-matrix results in `epic-14-golden-questions.md`.
