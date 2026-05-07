# Story 9.1: Task-0 Probes — `%OnAfterSave` Non-Recursion + `SynthesizeAlias` Determinism

Status: review

## Story

As a developer preparing the vocabulary-learning capture mechanism,
I want two verified Task-0 probes: (1) `%OnAfterSave` issuing direct SQL UPDATE on the same row does NOT re-fire on 2024.1, and (2) the `SynthesizeAlias` deterministic stringification holds across ~10 reordering scenarios,
so that Story 9.2's recursion-safe `%OnAfterSave` Confidence recomputation has a verified non-recursion guarantee + the alias capture in Story 9.5 has a verified deterministic key (per [architecture §"Carry-forward Task-0 probes"](../planning-artifacts/architecture.md) Epic 9 entries 5–6 + AR12 + AR13-Epic9).

This is a **probe-only story** — the artifacts produced are: a verified non-recursion guarantee captured verbatim in this story file's Completion Notes (consumed by Story 9.2 spec author + dev), and a `SynthesizeAlias` candidate function + comprehensive determinism unit test class (consumed by Story 9.5 dev). No production-shipped persistence schema or AgentLoop integration in this story.

## Acceptance Criteria

**AC-1 (probe 1) — `%OnAfterSave` non-recursion verification on 2024.1.** Author a small probe class `SessionAgent.Test.OnAfterSaveRecursionProbe` (a `%Persistent` class — NOT a `%UnitTest.TestCase`, since the probe needs persistence-layer behavior, not assertion macros) with: `Property A As %Integer`, `Property B As %Integer`, and `Method %OnAfterSave() As %Status` that:

1. Increments a process-private global counter `^||SessionAgentOnAfterSaveProbeCount` to track fire count (per project rule "ObjectScript Debugging Instructions" — `^||PPG` shape, NOT `^ClineDebug` since that's a global-namespace debug global; the PPG is process-scoped and avoids cross-process collision).
2. Issues `&sql(UPDATE SessionAgent_Test.OnAfterSaveRecursionProbe SET A = :..A WHERE %ID = :..%Id())` (direct SQL UPDATE on the same row that just saved).
3. Returns `$$$OK`.

Companion `ClassMethod RunProbe() As %DynamicObject` instantiates the class via `%New()`, sets `..A = 5, ..B = 10`, calls `..%Save()`, then reads `^||SessionAgentOnAfterSaveProbeCount` and returns the count + status as a structured `%DynamicObject` for verbatim Completion Notes capture. The expected value is **fire count = 1** (`%OnAfterSave` fires once for the original save; the inner direct-SQL UPDATE does NOT re-fire `%OnAfterSave` because direct SQL bypasses the OREF persistence layer's trigger dispatch).

If `RunProbe()` returns count > 1, the probe failed (recursion detected) and Story 9.2's design must be escalated — see Dev Notes §"Escalation path if recursion detected".

**AC-2 (probe 2) — `SynthesizeAlias` deterministic stringification across reordering scenarios.** Author a candidate `SynthesizeAlias` function as a `[Internal] ClassMethod` on a new class `SessionAgent.Search.SynthesizeAlias` (eventual home — Story 9.5 will use it; Story 9.1 ships only the function + tests):

```objectscript
ClassMethod SynthesizeAlias(pToolName As %String, pArgs As %DynamicObject) As %String [ Internal ]
```

The function must produce a deterministic alias string for semantically-equivalent inputs. Required normalizations:

1. **Key-order normalization** — sort the argument keys lexicographically before stringification (e.g., `{status:"Error", source:"EpicADT"}` and `{source:"EpicADT", status:"Error"}` produce the same alias).
2. **Key-case normalization** — lowercase all keys (e.g., `{Status:"Error"}` and `{status:"Error"}` produce the same alias).
3. **Value-case normalization** — apply `$ZConvert(value, "L")` to string values that are categorical (status names, type names) — but preserve case for free-text values (descriptions, IDs). For Story 9.1 scope, lowercase ALL string values (the rougher normalization is acceptable for v1; refinement can come later if false-positive collisions surface).
4. **Tool-name prefix** — prepend the tool name (lowercased) so aliases from different tools never collide: `tool_name + ":" + sorted_normalized_args_blob`.
5. **Array-value handling** — sort array values lexicographically before joining (e.g., `{status_in:["Error","Suspended"]}` and `{status_in:["Suspended","Error"]}` produce the same alias).

Author `SessionAgent.Test.SynthesizeAliasTest` (extends `%UnitTest.TestCase`) with **at least 10 test methods** covering the reordering scenarios; the verbatim list:

| # | Scenario | Input A | Input B | Expected: same alias? |
|---|---|---|---|---|
| 1 | Key-order swap | `{status:"Error",source:"EpicADT"}` | `{source:"EpicADT",status:"Error"}` | yes |
| 2 | Key-case (PascalCase vs camelCase) | `{Status:"Error"}` | `{status:"Error"}` | yes |
| 3 | Value-case (mixed-case status) | `{status:"Error"}` | `{status:"ERROR"}` | yes |
| 4 | Array reorder | `{status_in:["Error","Suspended"]}` | `{status_in:["Suspended","Error"]}` | yes |
| 5 | Tool-name differs | `(search_by_status, {status:"Error"})` | `(search_by_message_class, {status:"Error"})` | NO (different tools → different aliases) |
| 6 | Different keys present | `{status:"Error"}` | `{status:"Error",source:"EpicADT"}` | NO (different argument shapes) |
| 7 | Numeric value | `{limit:50}` | `{limit:"50"}` | yes (or document divergence — Story 9.1 dev choice) |
| 8 | Null/missing value | `{status:"Error"}` | `{status:"Error",source:""}` | NO (presence-of-key matters; empty value is meaningful) |
| 9 | Nested object | `{filters:{a:1,b:2}}` | `{filters:{b:2,a:1}}` | yes (recursive normalization) |
| 10 | Whitespace in values | `{description:"foo bar"}` | `{description:"foo  bar"}` | NO (whitespace is significant; not collapsed) |

Tests assert with `$$$AssertEquals` (or `$$$AssertNotEquals` for the "NO" cases) that `SynthesizeAlias` outputs match the expected verdict.

**AC-3 (verification gate).** Both probes pass. Capture verbatim in Completion Notes:

- AC-1: the verbatim `RunProbe()` `%DynamicObject` JSON output showing fire count.
- AC-2: the verbatim per-method PASS/FAIL output from `iris_execute_tests` for `SessionAgent.Test.SynthesizeAliasTest` (per-class form per truncation workaround), plus the SQL ground-truth probe via canonical numerical-MAX form per `object-script-testing.md` §"SQL-probe-as-ground-truth" (per Story 9.0 AC-2 reviewer-enforcement codification — the `MAX(ID) GROUP BY %EXACT(Name)` lex-sort form is a MEDIUM finding).
- Total regression sweep: capture Total/Passed/Failed for the FULL SessionAgent.Test.* suite (this story adds `SynthesizeAliasTest` so the count moves: Epic 8 close baseline 326 + new test methods).

**AC-4 (escalation gate — Rule 5 "one-liner check before deferring").** If AC-1 fails (recursion detected on 2024.1), the story does NOT defer to Story 9.2 — instead, document the alternate Confidence-recomputation strategy options inline (per architecture: scheduled task, lazy compute on read, two-phase save with explicit re-entry guard) and escalate to the user before sign-off. Per Rule 5, spend 5–15 minutes on root-cause investigation (try the `[Triggers]` keyword variant, try a `%OnAfterSave` with `If $G(^||recursionGuard) { Quit $$$OK }` re-entry guard, try `&sql(UPDATE ... WHERE %ID = ?)` with bind variable instead of literal substitution) before deferring; the architecture's documented expected behavior is "fires once" so any recursion is a 2024.1-specific surprise that needs exact reproducer captured.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight backend-surface probe (Rule 4 + research-first.md §"Task 0 backend-surface probe")**
  - [x] Verify `%Persistent` class compile + `%Save()` lifecycle works on this 2024.1 instance via `iris_execute_classmethod` against `SessionAgent.Search.UserVocabulary.%New` (returned `<Object:SessionAgent.Search.UserVocabulary>` — class instantiable, persistence-layer healthy). Direct one-liner via `iris_execute_command` blocked by `<SYNTAX>Execute` MCP envelope limitation — pivoted to typed classmethod probe per Rule 3.
  - [x] Stale-reference scan per Rule 4: `Grep "SynthesizeAlias|OnAfterSaveRecursionProbe"` returned 8 hits, all in `_bmad-output/` planning + retro artifacts (architecture.md, epics.md, Story 8.x retros, sprint-status.yaml, this story file). Zero `src/` matches — confirming this is the first Story-9 implementation introducing these names. No contradictory wording found.

- [x] **Task 1 — `%OnAfterSave` non-recursion probe (AC: #1, #3)**
  - [x] Authored `src/SessionAgent/Test/OnAfterSaveRecursionProbe.cls` per AC-1 spec — `%Persistent` probe (NOT `%UnitTest.TestCase`); `Property A`, `Property B` (no `Test*` prefix per shadow-trap rule); `%OnAfterSave` increments `^||SessionAgentOnAfterSaveProbeCount` (camelCase PPG subscript per project rule); issues `&sql(UPDATE SessionAgent_Test.OnAfterSaveRecursionProbe SET A = :tA WHERE %ID = :tId)` via bind variables; `RunProbe()` returns `%DynamicObject` with `save_ok / fire_count / recursion_detected / verdict`.
  - [x] Compiled via `iris_doc_compile` (success, 13ms).
  - [x] Invoked `RunProbe()` via `iris_execute_classmethod`; captured verbatim JSON. Re-ran for reproducibility — identical output both times. Verdict: **PASS** — fire_count=1, recursion_detected=0.
  - [x] Cleanup via `..%KillExtent()` at probe end and `Kill ^||SessionAgentOnAfterSaveProbeCount` — verified row_id="1" each run (no accumulation).

- [x] **Task 2 — `SynthesizeAlias` candidate function + determinism tests (AC: #2, #3)**
  - [x] Authored `src/SessionAgent/Search/SynthesizeAlias.cls` with `[Internal] ClassMethod SynthesizeAlias(pToolName, pArgs)` + helpers `NormalizeObject`, `NormalizeArray`, `NormalizeValue`, `SortListBuild`. Pure ObjectScript (no Python). Uses `%GetIterator()` to walk keys, then `SortListBuild` (local-array subscript collation = lexicographic sort, no `$ZSORT` needed). Recursive normalization for nested objects/arrays. Class doc-comment documents AC-2 row 7 design choice: numeric and string-of-number CONVERGE (both stringify via `value _ ""`).
  - [x] Authored `src/SessionAgent/Test/SynthesizeAliasTest.cls` with **12 `Test*` methods** (10 verbatim AC-2 rows + 2 sanity tests: `TestEmptyArgsProducesBareToolPrefix`, `TestToolNameLowercased`). `%OnNew(initvalue As %String = "")` calls `##super(initvalue)` per project rule.
  - [x] Compiled both classes via `iris_doc_compile` (success).
  - [x] Ran `SessionAgent.Test.SynthesizeAliasTest` via `iris_execute_tests` (per-class form). **12/12 PASS.**
  - [x] Sample alias output (sanity probe via `iris_execute_command` against `{"status":"Error","source":"EpicADT"}` + `"search_by_status"`): `search_by_status:source=epicadt|status=error` — keys lowercased, sorted, `|`-joined; values lowercased.

- [x] **Task 3 — Verification battery (AC: #3, Rule 6)**
  - [x] Per-class regression sweep across all 40 `SessionAgent.Test.*` classes via `iris_execute_tests` level=class form. (One pre-existing flake observed in `SessionAgent.Test.AuditTest:LogLlmCallWritesOneRow` on first run — passed on retry; two flakes in `SessionAgent.Test.AgentLoopGuardsTest` — also passed on retry. No Story-9.1-introduced failures.) Note: the runner envelope truncates tail rows for several large classes (SearchToolTest reports 1/24, ToolRegistryTest reports 1/8, etc.) — SQL probe is the ground truth per `object-script-testing.md`.
  - [x] SQL ground-truth probe via canonical numerical-MAX form: **Total=338, Passed=338, Failed=0** (verbatim row below).
  - [x] Baseline math: Story 9.0 close = 326 methods. Story 9.1 adds `SynthesizeAliasTest` (12 methods) = 338. Confirmed.

- [x] **Task 4 — Story sign-off (Rule 2 + AC-3)**
  - [x] AC-1 evidence captured verbatim in Completion Notes (RunProbe JSON output, twice for reproducibility).
  - [x] AC-2 evidence captured verbatim in Completion Notes (12-method PASS roster from `iris_execute_tests`).
  - [x] AC-3 evidence captured verbatim in Completion Notes (`Total=338 / Passed=338 / Failed=0` from canonical numerical-MAX SQL probe).
  - [x] AC-4 escalation gate not triggered — fire_count=1, no recursion detected on 2024.1.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~165–180 lines. Probe stories are inherently tight — two probes + a small candidate function + 10-method test class. Within the cap.

### Rule 3 typed-MCP-first

- `iris_doc_compile` for class compilation (per `iris-objectscript-basics.md` §"VSCode Auto-Sync Workflow" — auto-sync pushes the source; compile surfaces errors).
- `iris_execute_classmethod` for `RunProbe()` invocation (typed input/output; preferred over `iris_execute_command`).
- `iris_execute_tests` for `SynthesizeAliasTest` per-class run (per truncation workaround).
- `iris_sql_execute` for SQL ground-truth probe.

### Rule 5 one-liner-before-deferring

If AC-1 detects recursion: spend 5–15 minutes on empirical investigation BEFORE escalating to a Story 9.2 design change. Try (in order):

1. `irislib/%Library/Persistent.cls` source read for `%OnAfterSave` invocation contract on 2024.1.
2. Variant probe: same class but `%OnAfterSave` issues `&sql(UPDATE Probe SET A = :..A WHERE %ID = ?)` with `tParamId = ..%Id()` bind variable instead of literal substitution. (Different SQL parser path.)
3. Variant probe: `%OnAfterSave` with `If $G(^||recursionGuard) { Quit $$$OK }` re-entry guard set/clear at outer `%Save()` boundary. Documents whether the recursion is intrinsic or guard-able.
4. Perplexity search: *"InterSystems IRIS 2024.1 %OnAfterSave direct SQL UPDATE same row recursion"* — surface forum / docs evidence.

If a fix is found in <15 min, apply it inline (probably via Story 9.2's design template documented in Dev Notes — not via story-scope creep). If genuine 2024.1 surprise: defer per Rule 5 with the investigation findings cited, escalate to user, and propose alternate Confidence-recomputation strategy.

### Rule 8 / Rule 9 — no carry-forward bindings to address

Story 9.0 (just shipped) has no `Story 9.1` mentions in `deferred-work.md` (verified during Story 9.0 stale-reference grep). No items to incorporate.

### Rule 10 — no external defaults set in this story

Pure ObjectScript probes + unit tests. No external library version, model name, or API endpoint. Rule 10 does not apply.

### Rule 12 — not applicable

No UI / rendered-text changes in this story. Probe + unit-test class only.

### Story 9.2 / 9.5 dependencies on this story's outputs

- **Story 9.2** consumes the AC-1 verified non-recursion guarantee. The Completion Notes' verbatim `RunProbe()` JSON output IS the load-bearing evidence Story 9.2's spec author cites when authoring the recursion-safe `%OnAfterSave` AC.
- **Story 9.5** consumes the `SessionAgent.Search.SynthesizeAlias` ClassMethod authored here. Story 9.5's `RecordClickThrough` invokes `SynthesizeAlias(tool_name, args)` per Story 9.1's verified determinism. The `[Internal]` keyword on the ClassMethod signals it's not part of the public API; Story 9.5 calls it via fully-qualified `##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias(...)`.

### Numeric vs string value handling (AC-2 row #7)

The architecture doesn't pin this down. Recommendation: emit the canonical string form (`tool_name:arg1=val1|arg2=val2|...`) where ALL values stringify via `$ZConvert(value, "L") || ""` — so `{limit:50}` and `{limit:"50"}` produce the same alias because both stringify to `"50"`. The function's class doc-comment must document this explicitly so Story 9.5's dev knows the contract.

### Process-private global subscript naming

Per project rule "Process-Private Globals" — subscript names follow ObjectScript identifier rules (letters, digits, `%`, NO hyphens, NO embedded numbers-after-letters that look like operators). Use `^||SessionAgentOnAfterSaveProbeCount` (camelCase, no hyphens). At end of probe, `Kill ^||SessionAgentOnAfterSaveProbeCount` to avoid cross-test pollution.

### Test class location convention

Per project pattern (`SessionAgent.Test.*` naming), the two new test classes are:
- `src/SessionAgent/Test/OnAfterSaveRecursionProbe.cls` (probe-only `%Persistent`, NOT a TestCase — exempt from `%UnitTest`-driven discovery)
- `src/SessionAgent/Test/SynthesizeAliasTest.cls` (`%UnitTest.TestCase` subclass — discovered + run by `iris_execute_tests`)

The `SynthesizeAlias` ClassMethod itself lives at `src/SessionAgent/Search/SynthesizeAlias.cls` (production location — Story 9.5 imports from this path).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Opus 4.7 / 1M context)

### Completion Notes

#### AC-1 evidence — `%OnAfterSave` non-recursion verification (verbatim `RunProbe()` JSON output)

**First invocation:**

```json
{"save_ok":1,"save_status_text":"","row_id":"1","fire_count":1,"recursion_detected":0,"expected_fire_count":1,"verdict":"PASS — %OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT re-fire trigger."}
```

**Second invocation (reproducibility check):**

```json
{"save_ok":1,"save_status_text":"","row_id":"1","fire_count":1,"recursion_detected":0,"expected_fire_count":1,"verdict":"PASS — %OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT re-fire trigger."}
```

**Interpretation.** On IRIS 2024.1 (the build powering this dev instance), `%OnAfterSave` fires exactly **once** for the outer `..%Save()` call. The inner direct SQL UPDATE (`&sql(UPDATE SessionAgent_Test.OnAfterSaveRecursionProbe SET A = :tA WHERE %ID = :tId)`) executed inside the trigger does NOT re-fire `%OnAfterSave` — the persistence-layer trigger dispatch is bypassed by direct SQL DML. **Story 9.2's recursion-safe Confidence-recompute trigger has the verified non-recursion guarantee it depends on.** AC-4 escalation path NOT triggered.

#### AC-2 evidence — `SynthesizeAlias` determinism (verbatim per-method PASS roster from `iris_execute_tests` per-class run)

```
SessionAgent.Test.SynthesizeAliasTest:ArrayReorderProducesSameAlias                  passed (0.411s)
SessionAgent.Test.SynthesizeAliasTest:DifferentKeysPresentProduceDifferentAliases    passed (0.293s)
SessionAgent.Test.SynthesizeAliasTest:DifferentToolNamesProduceDifferentAliases      passed (0.244s)
SessionAgent.Test.SynthesizeAliasTest:EmptyArgsProducesBareToolPrefix                passed (0.370s)
SessionAgent.Test.SynthesizeAliasTest:EmptyValueDistinctFromAbsentKey                passed (0.263s)
SessionAgent.Test.SynthesizeAliasTest:KeyCaseProducesSameAlias                       passed (0.248s)
SessionAgent.Test.SynthesizeAliasTest:KeyOrderSwapProducesSameAlias                  passed (0.281s)
SessionAgent.Test.SynthesizeAliasTest:NestedObjectKeyOrderProducesSameAlias          passed (0.345s)
SessionAgent.Test.SynthesizeAliasTest:NumericValueAndStringValueConverge             passed (0.257s)
SessionAgent.Test.SynthesizeAliasTest:ToolNameLowercased                             passed (0.252s)
SessionAgent.Test.SynthesizeAliasTest:ValueCaseProducesSameAlias                     passed (0.260s)
SessionAgent.Test.SynthesizeAliasTest:WhitespaceInValuesIsSignificant                passed (0.297s)

Class total: 12 / Passed: 12 / Failed: 0 / Skipped: 0
```

**Sample alias output** (sanity-check via `iris_execute_command` against `tArgs = {"status":"Error","source":"EpicADT"}`, tool name `"search_by_status"`):

```
search_by_status:source=epicadt|status=error
```

Keys lowercased + sorted alphabetically (`source` before `status`); values lowercased; `=` separates key/value; `|` joins pairs at top level; `:` separates the lowercased tool name from the args blob.

**AC-2 row 7 design choice (numeric vs string).** The function CONVERGES `{limit:50}` and `{limit:"50"}` to the same alias — both stringify to `"50"` via `value _ ""`. This is documented verbatim in the class doc-comment of `SessionAgent.Search.SynthesizeAlias` rule 6 ("Numeric values: stringify via `value _ ""`") and consumed by Story 9.5 as the click-through-capture key contract.

#### AC-3 evidence — full SessionAgent.Test.* regression sweep (verbatim canonical numerical-MAX SQL probe row)

Query (per `object-script-testing.md` §"SQL-probe-as-ground-truth", numeric-run-id picker, inner JOIN to TestMethod to filter orphan TestCase rows):

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
JOIN (
  SELECT %EXACT(tc2.Name) AS ClassName,
         MAX($PIECE(tc2.ID, '||', 1) + 0) AS MaxRunIdx
  FROM %UnitTest_Result.TestMethod tm2
  JOIN %UnitTest_Result.TestCase tc2 ON tm2.TestCase = tc2.ID
  WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
  GROUP BY %EXACT(tc2.Name)
) latest ON %EXACT(tc.Name) = latest.ClassName
        AND ($PIECE(tc.ID, '||', 1) + 0) = latest.MaxRunIdx
WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%'
```

Verbatim result row:

```
Total | Passed | Failed
------+--------+-------
  338 |    338 |     0
```

**Per-class roster** (40 classes, all latest-runs from this story's per-class sweep):

| ClassName | MethodCount |
|---|---|
| SessionAgent.Test.AgentConfigTest | 16 |
| SessionAgent.Test.AgentDtoTest | 7 |
| SessionAgent.Test.AgentLoopGuardsTest | 9 |
| SessionAgent.Test.AgentLoopTest | 3 |
| SessionAgent.Test.AnthropicProviderTest | 11 |
| SessionAgent.Test.AuditEmitTest | 3 |
| SessionAgent.Test.AuditTest | 8 |
| SessionAgent.Test.BoundedWhereInvariantTest | 6 |
| SessionAgent.Test.BusinessProcessIntrospectionTest | 10 |
| SessionAgent.Test.ChatHistoryTest | 10 |
| SessionAgent.Test.ChatPanelDrawHelperTest | 4 |
| SessionAgent.Test.ChatPanelJsTest | 18 |
| SessionAgent.Test.ConfigAgentTest | 10 |
| SessionAgent.Test.EnvSecretTest | 8 |
| SessionAgent.Test.FindRelatedSessionsTest | 5 |
| SessionAgent.Test.FindSessionsByBodyTest | 7 |
| SessionAgent.Test.GeminiProviderTest | 11 |
| SessionAgent.Test.GetMessageBodyTest | 12 |
| SessionAgent.Test.GetMessageDetailTest | 6 |
| SessionAgent.Test.InspectionSuiteVerificationTest | 13 |
| SessionAgent.Test.InspectionToolTest | 15 |
| SessionAgent.Test.JsonTest | 9 |
| SessionAgent.Test.MessageAdapterTest | 11 |
| SessionAgent.Test.MultiNamespaceInstallTest | 6 |
| SessionAgent.Test.OpenAICompatProviderTest | 11 |
| SessionAgent.Test.OpenAIProviderTest | 8 |
| SessionAgent.Test.PurgeTaskTest | 3 |
| SessionAgent.Test.ReadOnlyRoleTest | 6 |
| SessionAgent.Test.RetryWithBackoffTest | 9 |
| SessionAgent.Test.SampleProductionTest | 3 |
| SessionAgent.Test.SearchToolTest | 24 |
| SessionAgent.Test.SeedVocabularyTest | 5 |
| SessionAgent.Test.SmokeTest | 1 |
| SessionAgent.Test.Story41ToolsTest | 12 |
| SessionAgent.Test.SynthesizeAliasTest | **12 (NEW)** |
| SessionAgent.Test.ToolBaseTest | 3 |
| SessionAgent.Test.ToolCallRoundtripIntegrationTest | 4 |
| SessionAgent.Test.ToolDefAdapterTest | 3 |
| SessionAgent.Test.ToolRegistryTest | 8 |
| SessionAgent.Test.VisualTraceTest | 8 |

Sum = 338. Story 9.0 close baseline = 326. Story 9.1 delta = +12 (`SynthesizeAliasTest`). Math reconciled.

#### Flakes observed during sweep (NOT introduced by this story; pass on retry)

- `SessionAgent.Test.AuditTest:LogLlmCallWritesOneRow` — first run failed (`AssertEquals: 5 LogLlmCall invocations -> 5 rows persisted`); passed on retry. Pre-existing intermittent timing/race condition; unrelated to Story 9.1 scope.
- `SessionAgent.Test.AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` and `:TestRunTurnNoExceptionEvenIfProviderErrors` — first run failed; both passed on retry. Pre-existing intermittent flakes; unrelated to Story 9.1 scope.

#### Design decisions

1. **AC-2 row 7 (numeric vs string convergence) — chose convergence.** `{limit:50}` and `{limit:"50"}` produce the same alias. Rationale: an operator typing the same query in two forms (numeric literal vs JSON-stringified) should land on the same vocabulary row. Documented in `SessionAgent.Search.SynthesizeAlias` class header rule 6.
2. **Sort algorithm — local-array subscript collation, not `$ZSORT`.** ObjectScript's local-array subscript ordering IS canonical lexicographic — building `tBucket(item)` and walking via `$Order` gives a deterministic sort without invoking `$ZSORT` (which has different collation semantics tied to NLS). The `SortListBuild()` helper encapsulates this.
3. **AC-2 row 8 (empty value vs absent key) — DISTINCT.** `{status:"Error"}` and `{status:"Error",source:""}` produce different aliases because the absent-key case is not iterated by `%GetIterator()` (no key emitted), while the empty-value case emits `source=` with empty value. Verified by `TestEmptyValueDistinctFromAbsentKey`.
4. **AC-2 row 10 (whitespace) — significant, NOT collapsed.** `"foo bar"` and `"foo  bar"` produce different aliases. Rationale: whitespace mid-string can be load-bearing in operator queries (multi-word phrases vs accidental double-space) and v1 conservatism prefers preserving the operator's intent.
5. **PPG fire-count subscript naming.** Used `^||SessionAgentOnAfterSaveProbeCount` (camelCase, no hyphens) per project rule "Process-Private Globals" — hyphens parse as concatenation operator and would cause `<SYNTAX>` at the subscript site.
6. **Probe class property names `A`, `B` — no `Test*` prefix.** Per project rule "`Property Test*` Test-Method-Discovery Shadow Trap" — even though this class is `%Persistent` (not `%UnitTest.TestCase`), the safe property-naming discipline avoids any future-cohort confusion.

### File List

**New files:**
- `src/SessionAgent/Search/SynthesizeAlias.cls` — production-location candidate function for Story 9.5 click-through capture key. `[Internal] ClassMethod SynthesizeAlias(pToolName, pArgs)` + private helpers.
- `src/SessionAgent/Test/OnAfterSaveRecursionProbe.cls` — Story 9.1 Task-0 probe verifying `%OnAfterSave` non-recursion on IRIS 2024.1. Self-contained `%Persistent` probe (NOT a `%UnitTest.TestCase`); `RunProbe()` returns structured `%DynamicObject` for verbatim evidence capture.
- `src/SessionAgent/Test/SynthesizeAliasTest.cls` — `%UnitTest.TestCase` subclass with 12 test methods covering AC-2 rows 1–10 plus 2 sanity tests.

**Modified files:**
- `_bmad-output/implementation-artifacts/9-1-task-0-probes-onaftersave-non-recursion-synthesizealias-determinism.md` — task checkboxes, Dev Agent Record, File List, Change Log, Status flip from `ready-for-dev` to `review`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story 9.1 status flipped `ready-for-dev` → `in-progress` → `review`; `last_updated` field bumped.

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted from epics.md Story 9.1 + architecture §"%OnAfterSave recursion avoidance" + §"Carry-forward Task-0 probes" Epic 9 entries 5–6 | Lead |
| 2026-05-07 | 1.0 | Story 9.1 implementation complete. AC-1 verified (fire_count=1, no recursion on 2024.1); AC-2 verified (12/12 SynthesizeAliasTest PASS across all 10 AC-2 rows + 2 sanity tests); AC-3 verified (338/338 full regression sweep via canonical numerical-MAX SQL probe); AC-4 escalation gate not triggered. New files: `SessionAgent.Search.SynthesizeAlias`, `SessionAgent.Test.OnAfterSaveRecursionProbe`, `SessionAgent.Test.SynthesizeAliasTest`. | Dev (Opus 4.7) |
| 2026-05-07 | 1.1 | Code-review pass: APPROVED. Zero HIGH or MEDIUM auto-fixes required (clean review). One MEDIUM finding (pre-existing AuditTest flake) and one LOW finding (boolean-comment drift in SynthesizeAlias.NormalizeValue) logged to `deferred-work.md`. All 4 ACs verified; all Rule 9.0 carry-forward checks pass; pre-existing flakes confirmed not introduced by this story. | Reviewer (Opus 4.7) |

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review pass 2026-05-07.

**Verdict:** **APPROVED — clean review.** Zero HIGH or MEDIUM findings requiring auto-fix. One MEDIUM-severity pre-existing flake observation and one LOW cosmetic finding logged to `deferred-work.md`.

### Findings summary

| Severity | Count | Disposition |
|---|---|---|
| HIGH | 0 | — |
| MEDIUM (auto-fix) | 0 | — |
| MEDIUM (defer to `deferred-work.md`) | 1 | MEDIUM-9.1-F01 — pre-existing `AuditTest:TestLogLlmCallWritesOneRow` flake (not introduced by Story 9.1) |
| LOW (defer) | 1 | LOW-9.1-F02 — `SynthesizeAlias.NormalizeValue` boolean-type comment drift (cosmetic) |
| LOW (dismiss) | 5 | comment drift in `NormalizeObject` Pass 1/Pass 2; `:tA`/`:tId` bind-variable form vs spec's `:..A`/`:..%Id()` (functionally equivalent; Rule 5 variant explicitly allowed); subscript-collation wording mildly imprecise but accurate; key-collision-after-lowercase silent-overwrite (acceptable v1 behavior, documented) |

### Acceptance criteria verification

- **AC-1 (`%OnAfterSave` non-recursion):** ✓ — `OnAfterSaveRecursionProbe.cls` is `%Persistent` (not `%UnitTest.TestCase`); `Property A`, `Property B` (no `Test*` prefix per shadow-trap rule); `%OnAfterSave` issues `&sql(UPDATE SessionAgent_Test.OnAfterSaveRecursionProbe SET A = :tA WHERE %ID = :tId)` (bind-variable variant explicitly allowed by Rule 5 escalation note); `RunProbe()` returns structured `%DynamicObject`; verbatim JSON output captured in Completion Notes shows `fire_count=1`, `recursion_detected=0`, `verdict="PASS"`, reproduced across two invocations.
- **AC-2 (`SynthesizeAlias` determinism):** ✓ — `[Internal] ClassMethod` at `src/SessionAgent/Search/SynthesizeAlias.cls`; all 5 normalization rules (key-order, key-case, value-case, tool-name prefix, array reorder) implemented + nested-object recursion + null-distinct-from-absent + whitespace-significant. 12 test methods (10 AC-2 verbatim rows + 2 sanity) — verbatim PASS roster captured in Completion Notes.
- **AC-2 row 7 design choice (numeric/string convergence):** ✓ — Documented verbatim in `SessionAgent.Search.SynthesizeAlias` class header rule 6 ("Numeric values: stringify via `value _ ""` so `{limit:50}` and `{limit:"50"}` both produce `\"50\"`"); `TestNumericValueAndStringValueConverge` test method exists and asserts equality.
- **AC-3 (verification gate):** ✓ — Regression sweep `Total=338 / Passed=338 / Failed=0` from canonical numerical-MAX SQL probe form (per `object-script-testing.md` §"SQL-probe-as-ground-truth"; uses `MAX($PIECE(tc2.ID, '||', 1) + 0)` numeric run-id picker, NOT fragile lex-MAX); reconciliation 326 baseline + 12 new = 338 ✓.
- **AC-4 (escalation gate):** ✓ — Not triggered (fire_count=1 on first probe; no recursion detected on IRIS 2024.1; Story 9.2 has its verified non-recursion guarantee).

### Rule 9.0 carry-forward checks

- **`Property Test*` shadow-trap (Story 9.0 codification):** ✓ — `OnAfterSaveRecursionProbe.cls` declares `Property A`, `Property B` (no `Test*` prefix); `SynthesizeAliasTest.cls` declares no Properties at all. No phantom-test-method risk.
- **`%UnitTest.TestCase` `%OnNew(initvalue As %String = "")` pattern (Story 9.0 codification):** ✓ — `SynthesizeAliasTest.cls` lines 53-58: accepts `initvalue` param, calls `##super(initvalue)`, no `Private` keyword, returns `$$$OK`.
- **PPG subscript naming (Story 9.0 codification):** ✓ — `^||SessionAgentOnAfterSaveProbeCount` is camelCase, no hyphens, follows ObjectScript identifier rules.

### Rule 12 (rendered-text readability)

Not applicable — no UI / rendered-text changes in this story (probe-only + unit-test-class only).

### Pre-existing-flake analysis

Dev's regression sweep observed three intermittent flakes that all passed on retry:

1. **`SessionAgent.Test.AuditTest:TestLogLlmCallWritesOneRow`** — NOT documented in `deferred-work.md` before this review. Logged as MEDIUM-9.1-F01 with cross-reference to the existing `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` deferral (line 892+) since both have the same root-cause shape (global state leaking under concurrent test cadence). Confirmed not introduced by Story 9.1: `AuditTest.cls` last touched in commit `229f223` (Epic 2 retro), no diff in this story.
2. **`SessionAgent.Test.AgentLoopGuardsTest:TestRunTurnMaxIterationsCap`** — already documented in `deferred-work.md` at line 892+ as a pre-existing carry-forward to Epic 6+ retro health-check.
3. **`SessionAgent.Test.AgentLoopGuardsTest:TestRunTurnNoExceptionEvenIfProviderErrors`** — same root-cause shape; covered by the line 892+ deferral.

None are Story-9.1-introduced; all are environment / cadence-dependent and pass on retry.

### Files reviewed

- `src/SessionAgent/Search/SynthesizeAlias.cls` (NEW; 218 lines incl. doc-comments)
- `src/SessionAgent/Test/OnAfterSaveRecursionProbe.cls` (NEW; 144 lines incl. storage section)
- `src/SessionAgent/Test/SynthesizeAliasTest.cls` (NEW; 192 lines)
- `_bmad-output/implementation-artifacts/9-1-task-0-probes-onaftersave-non-recursion-synthesizealias-determinism.md` (status `review`, Dev Agent Record populated, this Code Review section appended)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (Story 9.1 status flipped to `review`; `last_updated` line refreshed)

### Files modified during review

- `_bmad-output/implementation-artifacts/deferred-work.md` — appended Story 9.1 deferred-work section with MEDIUM-9.1-F01 (AuditTest flake) and LOW-9.1-F02 (boolean comment drift).
- `_bmad-output/implementation-artifacts/9-1-task-0-probes-onaftersave-non-recursion-synthesizealias-determinism.md` — appended this Code Review section + bumped Change Log to v1.1.
