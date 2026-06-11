# Test Automation Summary — Story 14.4 (qa-generate-e2e-tests stage, 2026-06-11)

**Env:** IRIS HSCUSTOM (sample production running). Framework: IRIS `%UnitTest` (ObjectScript
backend story, no UI surface). New tests dispatch through the real `SessionAgent.Tool.Registry.Dispatch`
path and the real `SessionAgent.Agent.AgentLoop.RunTurn` runtime (VocabDigestCaptureMock provider override).

## Scope

GAP coverage only for Story 14.4 (learned schema notes + first-turn digest injection). The dev
battery (28 tests across `SchemaNoteToolTest` 9, `GetSchemaNotesTest` 6, `SchemaNoteDigestTest` 6,
`AgentLoopSchemaDigestTest` 7) already locks the spec's AC matrix: upsert, write+audit+failure
envelope, retrieval/staleness/fragment/clamp, digest unit caps, injection matrix both agents,
manifest locks. Baseline before this stage: ground-truth probe **610/610/0**, SchemaNote table empty.

## Gap Assessment (candidates from the stage briefing)

- **(a) cross-conversation persistence e2e — REAL GAP, added.** The dev injection tests seed
  fixtures via the `SeedNote` helper (direct `Upsert`), never via the actual `save_schema_note`
  tool dispatch — the FR63 core chain (tool-save in conversation 1 → first-turn digest in a
  brand-new conversation 2 → `get_schema_notes` re-read with body intact) was untested end-to-end.
- **(b) namespace isolation — REAL GAP, added.** No test seeded rows under a second Namespace
  value and asserted non-leakage. Locked both directions for both read channels (get tool + digest).
- **(c) upsert unique-index race — sequential shape COVERED, deterministic safety net added.**
  Sequential double-dispatch is covered by `SchemaNoteToolTest.TestSaveToolDispatchPersistsRow`
  (back-to-back dispatches, count stays 1). A true concurrent JOB-based race test was deliberately
  NOT attempted (flaky; same rationale as the Story 14.1 TOCTOU deferral). Instead added a
  deterministic test of the safety net under the race: two un-saved OREFs for the same
  (Namespace, Subject) — the second `%Save` fails on the unique `NsSubjectIdx`, no silent duplicate.
  (Note: `Upsert` opens with concurrency 4, which serializes update-update; the create-create
  outcome is what the unique index must catch — now locked.)
- **(d) exact MAXLEN boundaries — REAL GAP, added.** Dev tests cover only 300/4100 over-limit.
  Added: subject exactly 256 + note exactly 4000 ACCEPTED and persisted at full length
  (`$Length` probes on the stored row); 257 / 4001 rejected with the validation envelope (over-by-one).
- **(e) digest content escaping — REAL GAP, added.** A note body containing the literal
  `\n\n---\n\n` delimiter sequence and a forged `User: ` line cannot break the first-turn block:
  the snippet renderer collapses newlines, so the digest contains no delimiter sequence (unit
  assert) and the AgentLoop first turn carries exactly ONE delimiter block with the real
  `User: <pUserText>` trailer after it and the forged line trapped before it (e2e assert).
- **(f) age_days for an old note — partially covered, SQL-UPDATE shape added.** Dev tests backdate
  via object property write (ages 2/5/7). Added the SQL UPDATE backdate path (30 days): retrieval
  reports `age_days=30` and the digest renders `(verified 30 day(s) ago)` — exercising the
  read paths against a SQL-mutated row ($Char(0) rule does not bite: a real value is set).

## Generated Tests

### `src/SessionAgent/Test/SchemaNoteIntegrationTest.cls` (NEW — 6 methods, all pass)

- [x] `TestCrossConversationSaveThenDigestInjection` — FR63 e2e: dispatch save → new-conversation digest carries subject + fact → fresh get dispatch round-trips body, age_days=0
- [x] `TestNamespaceIsolation` — local/foreign Namespace values isolated in get tool AND digest, both directions
- [x] `TestUniqueIndexRejectsDuplicateCreate` — TOCTOU safety net: second `%Save` on duplicate key fails; SQL probe confirms 1 row, first writer wins
- [x] `TestExactMaxlenBoundaries` — 256/4000 accepted + persisted at full length; 257/4001 rejected
- [x] `TestDigestDelimiterIntegrityWithHostileContent` — hostile `---` / `User:` note content cannot forge the delimiter block; exactly one delimiter e2e
- [x] `TestAgeDaysAfterSqlUpdateBackdate` — SQL UPDATE backdate 30 days → `age_days=30` + digest 30-day marker

Test hygiene per the stage brief: `ztest-` subject fixtures swept per-test via
`SchemaNoteToolTest.DeleteFixtureRows` (Subject-only filter also sweeps the foreign-namespace
isolation fixtures); SessionKey/PortalUser prefix `sa-test-144q-` with chat-history + audit-child
sweep; Config.Agent rows captured/restored in OnBefore/OnAfter; no `Property Test*`; no
underscores in method names; class 360 lines (≤500). Discoverable (Rule 8): `SessionAgent.Test.*`
package, `Test*` methods, no exclusion tags — runs in the default package sweep and is visible to
the `LIKE 'SessionAgent.Test.%'` ground-truth probe.

## Verification (ground-truth SQL probe, canonical numerical-MAX form)

- Per-method roster for `SessionAgent.Test.SchemaNoteIntegrationTest` latest run: 6/6 `Status=1`
  (the `iris_execute_tests` envelope truncated to 1 row — known truncation; SQL probe authoritative).
- Aggregate latest-run-per-class probe after the stage:

```
Total | Passed | Failed
616   | 616    | 0
```

  (= 610 dev baseline + 6 new; zero failures.)
- Pollution probes post-run: `SessionAgent_Knowledge.SchemaNote` rows = 0;
  `sa-test-144q` chat-history rows = 0.

## Coverage

- Story 14.4 surfaces: dev 28 tests (AC matrix) + 6 QA gap tests = 34 tests; all six briefed gap
  candidates assessed, 5 closed with new tests, 1 (concurrent race) documented as deliberately
  deferred with deterministic safety-net lock instead.

## Next Steps

- Epic-end battery: full package re-sweep on final epic code (per Rule 6 step 3) will include this
  class automatically.
- Story 14.5 GQ set covers the cross-conversation re-read at the live-LLM walkthrough tier.
