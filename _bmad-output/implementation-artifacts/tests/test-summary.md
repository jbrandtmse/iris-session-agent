# Test Automation Summary — Story 14.0 (qa-generate-e2e-tests stage, 2026-06-11; updated by code-review triage same day)

## Scope

Gap coverage for the Story 14.0 `EnsureIsErrorOnExecuteFailure` retrofit, complementing the
dev-authored `SessionAgent.Test.ExecuteFailureGateTest` (6 methods: helper unit tests +
Inspection `session_timeline` end-to-end — restaged by the code-review pass as a
graceful-skip assertion, see below). Framework: IRIS `%UnitTest`
(project standard — no JS test framework applies to ObjectScript backend stories).

**Code-review update (2026-06-11):** SessionTimeline's span DATEDIFF and EventLog's
severity-count statements were re-classified best-effort (graceful-skip on execute
failure) by the review pass, and FSUC's Invoke now classifies RunQuery failures via
`ShapeRunQueryErrorEnvelope` (execute marker → `render_strategy="execute_error"`).
This file's test inventory reflects the post-review state: 5 methods in
`ExecuteFailureAdaptedSitesTest`, and `ExecuteFailureGateTest`'s e2e renamed to
`TestSessionTimelineSpanFailureGracefulSkip`.

## Generated Tests

### ObjectScript %UnitTest (adapted-guard sites)

- [x] `src/SessionAgent/Test/ExecuteFailureAdaptedSitesTest.cls` — 5 methods, all passing:
  - `TestRunQueryReturnsErrorStatusOnExecuteFailure` — drives a REAL runtime `%Execute`
    failure (constant scalar `(SELECT DATEDIFF('ms','garbage-a','garbage-b')) >= 0`
    subquery in a table-context WHERE; empirically probed `prep=1 afterExecute=-400`,
    data-independent) through `FindSessionsUsingClass.RunQuery` and asserts the Story 14.0
    adapted guard returns an error `%Status` carrying
    `"SQL execute failed for find_sessions_using_class"` + a generic negative `"SQLCODE -"`
    (review fix: literal -400 was engine-version brittle) — proving the
    guard fires before `%Next()` instead of falling through to a silent zero-row success.
  - `TestRunQueryCleanColFilterSucceeds` — sanity sibling proving the failure above is
    caused by the guard, not the direct-call fixture shape.
  - `TestShapeRunQueryErrorEnvelopeExecuteMarker` (review fix) — execute-marker %Status →
    canonical `render_strategy="execute_error"` envelope (corrected taxonomy; the
    pre-review code mislabeled execute failures `prepare_error` with contradictory
    "prepare failed: ... execute failed" text).
  - `TestShapeRunQueryErrorEnvelopeNonMarkerFallsBack` (review fix) — non-marker %Status
    keeps the Story 11.2 `prepare_error` shape (classifier does not over-label).
  - `TestInvokeConvertsRunQueryErrorToCanonicalEnvelope` — validation arm: a RunQuery
    error `%Status` (staged deterministically via `time_window_hours = -5` →
    `BuildBoundedWhereClause` TimeWindowTooSmall) is converted by `Invoke` into the
    canonical envelope (`isError=1`, `render_strategy="prepare_error"`,
    operator-readable `content[0].text`, `structuredContent.error_text`) with `Invoke`
    returning `$$$OK` per the envelope-based error contract.

## Coverage Decisions (gap assessment, not duplication)

- **Single-call public-Invoke e2e returning `render_strategy="execute_error"`: not
  stageable post-review.** All Search-family statements are table-context
  (`FROM Ens.MessageHeader` / `Ens_Config.SearchTableProp` /
  `SessionAgent_Search.UserVocabulary`); per the Story 14.0 Task-4 probes, table-context
  predicates are silently coerced, and the one in-repo shape failing AT `%Execute`
  (SessionTimeline's scalar no-FROM DATEDIFF) is best-effort post-review (graceful skip,
  covered by `TestSessionTimelineSpanFailureGracefulSkip`). The AC-3c execute_error
  evidence is therefore the FSUC two-link chain: real runtime `%Execute` failure →
  marker `%Status` (`TestRunQueryReturnsErrorStatusOnExecuteFailure`, real engine
  SQLCODE) → canonical `execute_error` envelope
  (`TestShapeRunQueryErrorEnvelopeExecuteMarker`).
- **`GetBusinessProcessInstance` graceful-skip: existing coverage sufficient.**
  `BusinessProcessIntrospectionTest.TestInstanceLiveSessionReturnsBp` and
  `TestInstanceNoBpReturnsHasBpFalse` already lock both envelope shapes through the
  adapted augmentation guards; the failure arm (`%SQLCODE < 0` on the Ens_BP.Context /
  Thread probes) is not stageable for the same table-context-coercion reason. No
  redundant test added.
- **Golden-questions doc artifact (AC-6): skipped** — not testable in `%UnitTest`
  (doc artifact; consumed by Story 14.5 eval run).
- **Locale note:** IRIS error-text prefixes are localized on this server (localized
  "#5001" prefix observed); all assertions target locale-independent substrings authored
  by project code.

## Verification (verbatim evidence)

- QA stage (pre-review): `iris_execute_tests` class-level
  `{"total":3,"passed":3,"failed":0,"skipped":0}`; full-suite SQL ground-truth
  aggregate Total=518 / Passed=518 / Failed=0 (= dev baseline 515 + 3 new).
- Post-review-triage (2026-06-11): `iris_execute_tests` class-level
  `{"total":5,"passed":5,"failed":0,"skipped":0}` for
  `ExecuteFailureAdaptedSitesTest`; `{"total":6,"passed":6,"failed":0,"skipped":0}` for
  `ExecuteFailureGateTest` (incl. `TestSessionTimelineSpanFailureGracefulSkip`).
- Canonical SQL ground-truth probe (numerical-MAX form, per
  `.claude/rules/object-script-testing.md`), post-review full-suite latest-run
  aggregate: **Total=520 / Passed=520 / Failed=0** (= 518 + 2 new classifier tests).
- `SessionAgent.Test.Util:RegressionSweepCount()` (direct invocation): `sc=1`; counts
  per SQL probe above (Output args not surfaced via MCP).
- Rule 8 discoverability: class lives in `SessionAgent.Test`, extends
  `%UnitTest.TestCase`, methods are `Test*` with no underscores, no `Property Test*`,
  `%OnNew(initvalue)` implemented — discovered by the default per-class suite sweep.

## Next Steps

- Lead's per-story smoke gate runs after code review; this class participates in the
  Epic 14 per-class regression sweep (now 62 test classes).
