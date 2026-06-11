# Code-review addendum — Story 14.2 (code-review stage, 2026-06-11)

Corrections + additions to the QA section below, applied at code review:

- **Line-count claim corrected.** "481 lines" was a `Measure-Object -Line`
  count (excludes blank lines); physical `wc -l` was 517 at QA close and is
  **536 after review fixes** (fixture Try/Catch safety + assertion updates).
  Slightly over the ~500 test-class guideline — accepted (Rule 8 test 3, no
  bug shape); the two review-added tests were split into a NEW class
  `SchemaDiscoveryEdgeTest.cls` (113 lines) to bound further growth.
- **`TestDiscoverTablesMaxResultsSubOneTreatedAsUnset` superseded.** Code
  review adjudicated the QA-flagged divergence in favor of AC-3's
  "clamp 1..200" (consistent with `hours<1`→1 and the published
  GetInputSchema text): code now clamps `max_results<1` → 1; the test was
  renamed `TestDiscoverTablesMaxResultsSubOneClampsToOne` and asserts the
  clamp.
- **New review tests:** `SchemaDiscoveryEdgeTest.TestDescribeMessageClassCharBudgetTrim`
  (16 KB trim path — previously only the negative truncated=false case was
  asserted) + `TestDiscoverTablesDottedFragmentMatchesQualified` (dotted
  fragment fix lock). `TestDiscoverTablesIncludeSystemAndClamp` gained the
  string-`"true"` include_system lock and a strict overflow-based
  `truncated=1` assertion; `TestDescribeMessageClassSampleMsgMapping`
  gained the IDKEY `unique=1` decode lock.
- **Ground truth after review fixes (canonical numeric run-id picker):**
  **Total=554, Passed=554, Failed=0** = QA 552 + 2 new EdgeTest methods.
  Affected-class runs: SchemaDiscoveryToolTest 16/16 (run 181),
  SchemaDiscoveryEdgeTest 2/2 (run 182), InspectionSuiteVerificationTest
  13/13 (run 183), AgentConfigTest 25/25 (run 184),
  ToolCallRoundtripIntegrationTest 4/4 (run 185 — perf gate verbatim
  `"Matrix completed in 85.799606s (derived gate: 128s = 128 pairs x
  1s/pair, floor 30s); regression if over."`), SampleProductionTest 3/3
  (run 186; `Ens.Director.IsProductionRunning` → 1 AFTER the class run —
  restore-prior-state teardown verified).

---

# Test Automation Summary — Story 14.2 (qa-generate-e2e-tests stage, 2026-06-11)

## Scope

Gap coverage for Story 14.2 (FR61 schema-discovery tools), complementing the
dev-authored `SchemaDiscoveryToolTest` (12 methods). Framework: IRIS
`%UnitTest` (project standard — ObjectScript backend story, no UI surface).
All new tests dispatch through the real `Tool.Registry.Dispatch` trust
boundary or the real `Tool.Registry.ListTools` manifest.

## Gap Assessment (5 candidates from the stage briefing)

- **(a) describe_message_class with NO collection properties — REAL GAP.**
  All dev tests used classes WITH collections (OrderRequest/LineItems,
  OrderRouter, Ens.MessageHeader). Verified live that
  `SessionAgent.Sample.Msg.OrderResponse` is persistent with zero
  `%Dictionary.CompiledProperty` Collection rows and zero `OrderResponse_*`
  child tables → one test added.
- **(b) hours-clamp upper bound + empty-window ok-empty envelope — COVERED;
  no test added.** Upper clamp (999999→2160) and lower clamp (0→1) are both
  in `TestListActiveBodyTypesWindowClampAndDefaults`, which also asserts the
  success envelope + `body_types` array presence on the minimum window. A
  *deterministically empty* census cannot be constructed non-destructively:
  the minimum window is 1 hour and the running sample production / sibling
  tests legitimately create headers inside any 1-hour window, so an
  `body_type_count=0` assertion would be sweep-flaky. The ok-empty envelope
  discipline is structurally locked by the existing assertions.
- **(c) discover_tables max_results clamp + include_system=true — MOSTLY
  COVERED; one sub-gap.** `TestDiscoverTablesIncludeSystemAndClamp` covers
  include_system=true (%Dictionary surfaced), 5000→200 clamp, and the
  small-cap truncated flag. Uncovered sub-gap: the lower bound — implemented
  semantic is `max_results<1` → treated as UNSET → default 50 (NOT clamp to
  1; contrast `hours<1`→1 in list_active_body_types). One test added locking
  the implemented semantic (flagged in Decisions for code-review attention).
- **(d) LIKE-wildcard chars in name_fragment — REAL GAP.** The layer-2 regex
  deliberately admits `%`/`_`, and the fragment is bound into LIKE unescaped,
  so SQL wildcard semantics pass through (already documented in the
  GetInputSchema description). Verified live, then locked: `Mes_ageHeader`
  and `Message%Header` both match `Ens.MessageHeader`.
- **(e) ListTools manifest entries for the 3 tools — REAL GAP.** No
  `TestRegistryListToolsIncludes<Tool>` test existed for any of the 3 new
  tools (Story 14.1 precedent). One combined test added.

## Generated Tests

### ObjectScript %UnitTest (gap coverage)

- [x] `src/SessionAgent/Test/SchemaDiscoveryToolTest.cls` — 4 methods + 1
  non-Test-prefixed helper added (now 16 methods, 481 lines ≤ ~500):
  - `TestDescribeMessageClassNoCollectionsGracefulEmpty` — OrderResponse:
    `child_tables:[]` + `collection_properties:[]` present (not omitted),
    `has_additional_info=false`, no `additional_info_keys` field,
    `truncated=false`, columns still populated.
  - `TestDiscoverTablesLikeWildcardSemantics` — `_` (one char) and `%`
    (zero+) wildcards pass the regex gate and apply LIKE semantics; both
    find `Ens.MessageHeader`.
  - `TestDiscoverTablesMaxResultsSubOneTreatedAsUnset` — `max_results:0` →
    default 50 (implemented unset semantic locked).
  - `TestRegistryListToolsIncludesDiscoveryTools` — all 3 tools surfaced
    with non-empty priming Descriptions (`FIRST` / `schema.table` /
    `INFORMATION_SCHEMA` hooks) + input_schema properties/required shape
    (`class_name` sole required arg; the other two declare none).
  - `TablesContain` (ClassMethod helper — non-`Test*` per the
    Property/method discovery-shadow rule).

## Verification (ground-truth SQL probe, canonical numeric run-id picker)

- Per-class run 180: 16/16 `Status=1` (verbatim roster probed from
  `%UnitTest_Result.TestMethod`; the MCP envelope truncated to 1 row —
  envelope is best-effort, SQL is the gate).
- Package-wide aggregate: **Total=552, Passed=552, Failed=0** = 548 baseline
  + 4 new methods.
- Pre-flight: `Ens.Director.IsProductionRunning` → 1 (production left
  running per Rule 7).

## Rule 8 (discoverability)

All 4 methods are `Test*`-prefixed instance methods on a
`%UnitTest.TestCase` subclass in the `SessionAgent.Test` package — picked up
by the default package sweep; no exclusions, no opt-out tags; helper is
deliberately not `Test*`-prefixed.

---

# Test Automation Summary — Story 14.1 (qa-generate-e2e-tests stage, 2026-06-11)

## Scope

Gap coverage for Story 14.1 (knowledge corpus + `get_query_knowledge` tool),
complementing the dev-authored `KnowledgeCorpusTest` (5 methods) and
`GetQueryKnowledgeTest` (7 methods). Framework: IRIS `%UnitTest` (project
standard — ObjectScript backend story, no UI surface).

Dev coverage already included: seed idempotency + 47-count lock, topic
representation, ASCII grep, SQLCODE-hint contract, unique-Slug, topic/keyword/
combined retrieval e2e via `Tool.Registry.Dispatch`, validation envelopes,
max_results clamp, char-budget truncation. The 4 gap candidates were assessed;
all 4 were real gaps and got one test each.

## Generated Tests

### ObjectScript %UnitTest (gap coverage)

- [x] `src/SessionAgent/Test/KnowledgeCorpusTest.cls` — 1 method added (now 6):
  - `TestInstallerWiresKnowledgeSeed` — Installer-integration regression lock:
    reads the compiled `SessionAgent.Installer:Install` implementation via
    `%Dictionary.MethodDefinition` and asserts it contains
    `##class(SessionAgent.Knowledge.SeedContent).Seed()` and
    `LogPostSeedKnowledgeCount`, and that the helper method exists. A live
    re-Install was judged too expensive (per stage scope guidance); the
    source-grep lock catches the predicted-bug shape (future Installer refactor
    drops the seed call → installs ship an empty corpus, breaking the Story
    14.3/14.5 consumer contract).
- [x] `src/SessionAgent/Test/GetQueryKnowledgeTest.cls` — 3 methods added (now 10):
  - `TestRegistryListToolsIncludesGetQueryKnowledge` — ListTools manifest shape
    per the project-wide `TestRegistryListToolsIncludes<Tool>` precedent
    (GetQueryKnowledge was the only tool missing one): name surfaced, non-empty
    Description, Description primes consult-BEFORE-authoring-SQL usage and
    names the topic taxonomy, input_schema present with a 7-entry `topic.enum`
    (static-taxonomy lock) + `keywords` + `max_results` properties.
  - `TestRelevanceRankingDeterministic` — fixture-based multi-term scoring
    order: 4 `ztest-` fixtures with 3/2/1/1 term hits against a 3-term query
    must order strictly by score desc then slug asc (tie pair). The dev's
    combined e2e only pinned position 0 against live corpus content; this
    locks the full ordering deterministically (matters for Story 14.5 golden
    questions).
  - `TestKeywordSpecialCharactersRobust` — keyword-input robustness: single/
    double quotes never error (parameterized binding), pure `%` term acts as
    match-all but stays bounded by max_results, `_` is locked as an accepted
    single-char LIKE wildcard via fixture (`ztrw_marker` query matches stored
    `ztrw-marker`), and a 12-term string beyond the 8-term cap returns a
    success-shape envelope.

## Coverage Decisions (gap assessment, not duplication)

- **Gap (a) Installer integration** — no prior test asserted the wiring (grep
  evidence lived only in dev Completion Notes). Added as cheap source
  introspection; live re-Install intentionally NOT run.
- **Gap (b) ranking determinism** — real gap; added fixture-based test.
- **Gap (c) LIKE wildcard semantics** — assessed the tool: keyword terms bind
  via `?` placeholders (no injection surface), but `%`/`_` are NOT escaped and
  pass through as LIKE wildcards. Judged semantically acceptable (benign
  broadening for an LLM caller, never an error) and LOCKED as documented
  behavior in the test doc-comment rather than "fixed" — if a future story
  decides to escape, this test fails loudly and forces a deliberate decision.
- **Gap (d) ListTools manifest** — real gap (every other tool has the test);
  added per the `GetClassSourceTest` template.

## Verification (verbatim evidence)

- Per-method SQL ground-truth roster (numerical-MAX form): all 16 methods of
  `KnowledgeCorpusTest` (6) + `GetQueryKnowledgeTest` (10) Status=1.
- Full-suite SQL ground-truth aggregate (canonical probe,
  `.claude/rules/object-script-testing.md`): **Total=536 / Passed=536 /
  Failed=0** — reconciles exactly to the 532 dev baseline + 4 new tests.
- Environment incident during the sweep (NOT caused by this story): the
  latest-run aggregate initially showed 536/531/5 — five failures from
  pre-existing run 160 (`AgentConfigTest.TestLoadAgentConfigReturnsSeededRow`
  + 4 `GetProductionConfigItemTest` methods). Probe showed the sample
  production was uninstalled (0 `Ens_Config.Item` rows) — the Rule 7
  watch-item sample-production-state drift. Re-Bootstrapped
  (`SessionAgent.Sample.Bootstrap.InstallProduction` +
  `StartProductionIfStopped`; `Ens.Director.IsProductionRunning` → 1) and
  re-ran both classes: all pass; aggregate then 536/536/0.
- Rule 8 discoverability: both classes live in `SessionAgent.Test`, extend
  `%UnitTest.TestCase`, new methods are `Test*`-prefixed camelCase with no
  underscores, helper `SaveRankFixture` is non-Test-prefixed, no
  `Property Test*`, no opt-out tags. Discovery proven empirically by the
  536-count aggregate including all 4 new methods. Class sizes: 330 / 207
  lines (≤ ~500 rule).

## Next Steps

- Code-review stage inspects these artifacts next; lead's per-story smoke
  follows. The Epic 14 per-class regression sweep baseline is now **536**.
