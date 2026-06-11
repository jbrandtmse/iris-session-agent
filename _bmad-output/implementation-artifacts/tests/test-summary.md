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
