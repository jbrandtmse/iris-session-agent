# Test Automation Summary — Story 14.6 stretch (qa-generate-e2e-tests stage, 2026-06-11)

**Env:** IRIS HSCUSTOM (sample production running). Framework: IRIS `%UnitTest` (ObjectScript).
All probes and new tests exercise the real `Tool.Registry.Dispatch` path (via
`SessionAgent.Test.GoldenQuestionDriver.RunTool` for probing, and direct `Invoke` /
`Registry.Dispatch` in the tests, matching the host classes' established patterns).

## Scope

GAP coverage only for Story 14.6 (EXPLAIN plan-reasoning support — small security-adjacent
stretch). The dev battery already locks: EXPLAIN SELECT allowance (bare / lowercase /
comment-prefixed → plan ok-envelope), EXPLAIN-of-write rejection in all smuggling shapes
(bare / comment-interleaved / comment-prefixed / mixed-case / CTE-write / UPDATE /
lowercase-delete) with sentinel write-proofs, the no-mutation invariant, card EXPLAIN-line
assertions, and corpus count 47. Baseline before this stage: ground-truth probe **626/626/0**.

## Gap Assessment (candidates from the stage briefing — each probed live first)

- **(a) nested `EXPLAIN EXPLAIN SELECT` — REAL GAP, added.** Live probe: rejected
  `not_select` (second effective keyword is EXPLAIN, not SELECT). No test locked it.
- **(b) EXPLAIN trailing semicolon / multi-statement tail — REAL GAP, added.** Live probes:
  `EXPLAIN SELECT ...;` → plan ok-envelope (trailing semicolons stripped pre-scan);
  `EXPLAIN SELECT ...; INSERT ...` → `multi_statement` (the semicolon scan fires BEFORE the
  EXPLAIN allowance; the tail INSERT never reaches prepare). Existing semicolon tests cover
  plain SELECT only.
- **(c) EXPLAIN char-budget on a complex plan — MECHANISM-LOCKED via synthetic equivalent.**
  Live probe of a 3-branch multi-join UNION EXPLAIN: plan ≈ 2.2 KB, `%Prepare` ≈ 1.3 s,
  untruncated ok-envelope (plan output demonstrably rides stage 5 unchanged). A real >32 KB
  plan extrapolates to a ~45-branch UNION with a multi-second prepare that risks tripping the
  30 s elapsed guard (flake) and taxes every regression run — rejected as a permanent cost.
  Instead locked the IDENTICAL stage-5 path with the exact shape an oversized plan produces
  (one row, one wide column): live probe `SELECT TOP 1 {fn REPEAT('x', 33000)} ...` →
  `row_count=0`, empty `rows`, `truncated=true`, `truncate_reason='char_budget'`, isError=0,
  6 ms. This single-oversized-cell edge was NOT covered anywhere (the existing
  `TestCharBudgetTruncation` accumulates several under-budget rows before tripping).
- **(d) EXPLAIN CALL / WITH-wrapped SELECT — PARTIAL GAP, added.** Dev's adversarial test
  covers `EXPLAIN WITH ... INSERT` only. Live probes: `EXPLAIN CALL ...` → `not_select`;
  `EXPLAIN (SELECT ...)` → `not_select` (capture ends at `(`); `EXPLAIN WITH ... SELECT`
  (read-only inner shape) → `not_select` — intentional conservative policy, now test-locked
  as policy (not an oversight).
- **(e) corpus plan-reading retrieval — REAL GAP, added.** Dev captured live dispatch
  evidence, but no test locked the amended `cost-vs-runtime` plan-READING guidance through
  retrieval. `KnowledgeCorpusTest` locks count 47 + topic representation only. Live probe:
  `topic=performance keywords='read a plan access path showplan'` → `cost-vs-runtime` ranks
  first with all amendment markers present.

If a case was already dev-locked it was NOT re-tested: EXPLAIN SELECT allowance spellings,
EXPLAIN-of-write shapes, the no-mutation invariant, card determinism/zero-digit assertions,
and corpus count 47 are all explicitly covered by the dev-stage tests.

## Generated Tests

- [x] `src/SessionAgent/Test/ReadOnlySqlAdversarialTest.cls` — `TestExplainEdgeShapes`
  (gaps a+b+d: nested EXPLAIN, EXPLAIN CALL, parenthesized, WITH-SELECT policy lock,
  trailing semicolon ok, multi-statement tail rejection + sentinel write-proof)
- [x] `src/SessionAgent/Test/ReadOnlySqlProofBatteryTest.cls` — `TestOversizedSingleCellCharBudget`
  (gap c: single cell > 32 KB budget → row_count=0 + truncated/char_budget on a success envelope)
- [x] `src/SessionAgent/Test/GetQueryKnowledgeTest.cls` — `TestPerformancePlanReadingGuidanceRetrievable`
  (gap e: Registry-dispatch e2e; cost-vs-runtime ranks first; body markers `<plans>`,
  'Read extent bitmap', 'Read master map', 'temp file', 'only EXPLAIN SELECT is accepted')

## Results

- Per-class runs all green (SQL ground-truth rosters, canonical numeric-MAX form):
  `ReadOnlySqlAdversarialTest` 13/13, `ReadOnlySqlProofBatteryTest` 15/15,
  `GetQueryKnowledgeTest` 12/12 — each +1 over the dev-stage counts; the 3 new methods
  confirmed `Status=1` by name in the roster probe.
- Full-suite ground-truth probe (canonical numeric-MAX form):
  **Total 629 / Passed 629 / Failed 0** = baseline 626 + 3 new.
- Rule 8 discoverability: all 3 tests are `Test*` methods on existing `SessionAgent.Test.*`
  `%UnitTest.TestCase` classes — discovered by the default package sweep (count moved
  626 → 629) and the `LIKE 'SessionAgent.Test.%'` SQL probe; no tags/ignores; no `Test*`
  properties added (shadow-trap rule respected). Class sizes post-change: 397 / 322 / 411
  lines (all ≤ 500 per test-hygiene rule).

## Next Steps

- Epic-end Rule 6 battery: the optional plan-reasoning walkthrough turn can cite
  `TestExplainEdgeShapes` + `TestPerformancePlanReadingGuidanceRetrievable` as the
  structural locks behind the EXPLAIN golden-question behavior.
