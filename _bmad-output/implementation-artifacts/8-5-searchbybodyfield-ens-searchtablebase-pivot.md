# Story 8.5: `SearchByBodyField` (`Ens.SearchTableBase` Pivot)

Status: review

## Story

As an Operator asking the Search Agent for sessions where a specific indexed body-field value appears (e.g., *"sessions for MRN 12345"*, *"orders for account 67890"*),
I want a `search_by_body_field` tool that pivots through `Ens.SearchTableBase` subclass extents using the same SearchTable JOIN pattern as Inspection's `find_sessions_by_body` (Epic 4 Story 4.6), but bounded by the search-agent's `time_window_hours` + result limit per FR19,
so that natural-language queries grounded in indexed body-field data dispatch through bounded SQL (FR16) — operator can ask *"sessions where MRN starts with 12345 in the last week"* and the tool walks `EnsLib.HL7.SearchTable` (or whichever VDoc SearchTable is installed) joined to `Ens.MessageHeader` with the time-window bound applied.

## Acceptance Criteria

Verbatim from [`epics.md` §"Story 8.5"](../planning-artifacts/epics.md):

**AC-1 — `SessionAgent.Tool.Search.SearchByBodyField` concrete class.** Class extends `SessionAgent.Tool.Search.Base` (Story 8.2). Declares `Parameter ToolName = "search_by_body_field"`, `Parameter Description = "..."` (operator/LLM-readable, one line; describes the SearchTable-pivot query shape with `(prop_name, prop_value)` predicate + indexed body-field columns), `Parameter MutatesState = 0`. Implements `GetIndexedLeadColumns() As %DynamicArray` returning `[<prop_name>]` — the SearchTable's indexed property column passed at invocation time. Note: the indexed lead column is *dynamic* (per-call) for this tool, not static like Stories 8.3/8.4. The bounded-WHERE invariant test (Story 8.2 `BoundedWhereInvariantTest`) inspects the static `GetIndexedLeadColumns()` return — pick a stable canonical placeholder (e.g., `["PropValue"]` or `["PropId"]`) for invariant-discovery purposes (the actual JOIN column on `Ens.SearchTableBase` extent rows). See Dev Notes for the reasoning.

**AC-2 — Input schema (locked subset).** `GetInputSchema()` declares:
- `search_table_class` (string, required) — the fully-qualified `Ens.SearchTableBase` subclass name, e.g., `"EnsLib.HL7.SearchTable"`.
- `prop_name` (string, required) — the SearchTable's logical property name (e.g., `"PID:3"` for HL7 MRN).
- `prop_value` (string, required) — the value to match.
- `time_window_hours` (integer, optional) — default `168` (= 7d per architecture OD8 `BodyFieldDefaultHours`); max `720` (= 30d).
- `limit` (integer, optional) — default `50`, max `500`.

Schema uses the locked subset (`type, properties, required, additionalProperties:false`); NEVER `oneOf`/`anyOf`/`allOf`/`pattern`/`$ref`.

**AC-3 — `Invoke` validation step.** Validate `search_table_class` is a registered `Ens.SearchTableBase` subclass via `$ClassMethod(class, "%IsA", "Ens.SearchTableBase")` (per Story 4.6's verified pattern — `%Extends` is unreliable for VDoc SearchTables; `PrimarySuper LIKE` SQL is unreliable; only `%IsA` works for the v1 VDoc subclass family). If the class doesn't exist OR doesn't extend `Ens.SearchTableBase`, return structured error envelope: `{isError:1, content:[{type:"text", text:"Class X is not an installed Ens.SearchTableBase subclass — install HealthShare SearchTables or use search_by_message_class instead"}]}`. Per architecture §"Risk Mitigation" + Story 4.6's existing graceful-degradation pattern.

**AC-4 — `Invoke` SQL construction.** Two-step SQL pattern from Story 4.6 (verbatim reuse):

- **Step A — `prop_name` → `PropId` resolution:** `SELECT TOP 1 ID FROM Ens.Config.SearchTableProp WHERE %EXACT(SearchTableClass) = ? AND %EXACT(Name) = ?` to translate the operator-typed property name into the integer `PropId` used by the SearchTable extent. If no row, return structured error envelope (*"Property '<prop_name>' is not indexed by SearchTable '<search_table_class>'"*).
- **Step B — JOIN against MessageHeader bounded by time window:** `SELECT TOP ? mh.SessionId, mh.TimeCreated, %EXACT(mh.SourceConfigName) AS source_config_name, %EXACT(mh.TargetConfigName) AS target_config_name, %EXACT(mh.MessageBodyClassName) AS message_body_class_name, mh.Status FROM <search_table_class> st JOIN Ens.MessageHeader mh ON mh.MessageBodyId = st.DocId WHERE st.PropId = ? AND %EXACT(st.PropValue) = ? AND <BuildBoundedWhereClause-fragment>`. The `time_window_hours` parameter flows into `BuildBoundedWhereClause` for the `mh.TimeCreated > ?` predicate. `<search_table_class>` is interpolated into the SQL text (NOT parameterized) — it's a class name, not a user-controlled value, AND validated in AC-3.

**AC-5 — `%EXACT()` discipline + parameterized prepare.** All string projections + string predicates wrap `%EXACT()` per project rule. `mh.MessageBodyId` and `st.DocId` are typed as `%String` — wrap. `st.PropId` is `%Integer` — no wrap. NEVER concatenate user-controlled `prop_value` into SQL text — pass via `?` placeholder.

**AC-6 — Structured envelope.** On success returns `structuredContent: {search_table_class, prop_name, prop_value, sessions: [{session_id, time_created, source_config_name, target_config_name, message_body_class_name, status}, ...], session_count, time_window_used, indexed_lead_column}` PLUS `content[0].text` operator-readable summary (e.g., *"Found 7 sessions where PID:3 = '12345' in EnsLib.HL7.SearchTable in the last 168 hours"*). On error returns `{isError:1, content:[{type:"text", text:"..."}]}`. The agent continues with degraded context per architecture §"Concurrent tool errors don't halt the agent".

**AC-7 — SearchTable-not-installed graceful path.** When operator's instance does NOT have any `Ens.SearchTableBase` subclasses installed (e.g., bare HSCUSTOM without HealthShare SearchTables), the tool returns structured error envelope per AC-3 wording. The agent continues; no exception escapes `Invoke` to `Tool.Registry.Dispatch`'s outer Catch.

**AC-8 — Bounded-WHERE invariant compliance.** Story 8.2's `BoundedWhereInvariantTest` auto-discovers this tool. `GetIndexedLeadColumns()` returns the canonical placeholder per AC-1; the invariant test must accept this placeholder as part of the documented indexed set. **Sub-task:** extend `Test/BoundedWhereInvariantTest.BuildIndexedColumnSet` to add `"PropValue"` (or whichever canonical placeholder is chosen for AC-1) to the indexed-set entries. Re-run after install: log line transitions from "7 production search tools" → "8 production search tools, 0 violations".

### Verification gate

**AC-9 — Test methods extending `SearchToolTest`.** 3 new test methods specific to body-field search:

- `TestSearchByBodyFieldHappyPath` — fixture: 1 `EnsLib.HL7.SearchTable` row + 1 `Ens.MessageHeader` row + 1 `Ens.Config.SearchTableProp` row mapping `(EnsLib.HL7.SearchTable, "PID:3") → PropId=42`. Assert `search_by_body_field({"search_table_class":"EnsLib.HL7.SearchTable","prop_name":"PID:3","prop_value":"12345"})` returns the row. (Note: `Ens.Config.SearchTableProp` is auto-populated by IRIS on the first row insert into a SearchTable extent — the test fixture must seed it explicitly OR rely on the auto-population path; document the chosen approach in dev notes.)
- `TestSearchByBodyFieldUnknownPropNameReturnsError` — fixture: same as above but invoke with `prop_name="nonexistent"`. Assert structured error envelope (`isError:1`) with operator-readable text.
- `TestSearchByBodyFieldUnknownClassReturnsError` — invoke with `search_table_class="My.NotARealSearchTable"` (no fixture). Assert structured error envelope with the AC-3 text.

Each test uses `OnBeforeOneTest` to seed direct rows + `OnAfterOneTest` to clean up. **DO NOT use the `Property Test*` shadow-trap prefix** per Story 7.0 AC-3 codification.

**AC-10 — Compile + per-class regression sweep.**
- New `SearchByBodyField.cls` + extended `SearchToolTest.cls` + extended `BoundedWhereInvariantTest.cls` (per AC-8 sub-task) compile cleanly via `iris_doc_compile`.
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
- **The "N/N pass" claim that gates this story MUST come from the Story 8.0 AC-5-tweaked SQL probe form using the numerical-MAX-of-non-empty-run methodology** that Story 8.4's reviewer surfaced (per `deferred-work.md` LOW-8.4-F02). Capture verbatim `Total / Passed / Failed` row in Completion Notes.
- **Expected baseline: 310 (Story 8.4 close) + 3 new SearchToolTest methods** = ~313 / all PASS / 0 FAIL.
- **Bounded-WHERE invariant transition:** re-run `BoundedWhereInvariantTest`; the discovery loop reports "8 production search tool(s) discovered; 0 violation(s)".

**AC-11 — Live smoke against rich-data production (Rule 6 step 4).** With the production running (Step-1 Bootstrap), check whether `EnsLib.HL7.SearchTable` exists AND has rows. If yes, invoke `search_by_body_field` against a real `(prop_name, prop_value)` from the running production. If no SearchTable extent exists, seed a manual fixture pair (one `Ens.MessageHeader` row + one `EnsLib.HL7.SearchTable` row + one `Ens.Config.SearchTableProp` row) via direct SQL, invoke the tool, capture envelope, then clean up. Capture verbatim `structuredContent` envelope in Completion Notes per Rule 6 step 4 sharpening from Epic 3 retro AI-13.

**AC-12 — Sibling fix-now: tool count + matrix.** Update `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` 20 → 21; add `search_by_body_field` to `GetRepresentativeArgs` + `TestRegistryListsExactlyThirteenTools` named-tool list. Update `ToolCallRoundtripIntegrationTest` matrix cardinality 80 → 84 (4 providers × 21 tools); add `search_by_body_field` case to `BuildMinimalToolArgs`.

## Tasks / Subtasks

- [x] **Task 1 — `SessionAgent.Tool.Search.SearchByBodyField.cls` (AC: #1, #2, #3, #4, #5, #6, #7)**
  - [x] Create class extending `Tool.Search.Base` with full `///` doc-comments per Story 8.0 AC-1 operator-observable surface enumeration.
  - [x] `GetInputSchema()` returns the locked-subset object per AC-2 (5 fields; 3 required + 2 optional).
  - [x] `GetIndexedLeadColumns()` returns `["PropValue"]` (canonical placeholder per AC-1; the actual indexed column on a VDoc SearchTable extent is `PropValue`).
  - [x] `Invoke`: AC-3 validation → AC-4 Step A (PropId resolution) → AC-4 Step B (JOIN+WHERE bounded). `Parameter DefaultTimeWindowHours = 168` overrides the `Tool.Search.Base` 24h default per architecture OD8 `BodyFieldDefaultHours`. `BuildBoundedWhereClause(0, ...)` picks up the override automatically.
  - [x] AC-5 `%EXACT()` discipline on all string predicates + projections. `<search_table_class>` interpolated (not parameterized) — class name validated upstream by `%Dictionary.CompiledClass.%ExistsId` + `$ClassMethod(class, "%Extends", "Ens.SearchTableBase")`.
  - [x] Compile via `iris_doc_compile` — clean.

- [x] **Task 2 — Extend `BoundedWhereInvariantTest.BuildIndexedColumnSet` (AC: #8)**
  - [x] Added `Set pSet("PropValue") = 1` to `BuildIndexedColumnSet` so the invariant test accepts SearchByBodyField's lead column. Updated the doc-comment to mention SearchByBodyField as the consumer.

- [x] **Task 3 — Extend `SearchToolTest.cls` with 3 new tests (AC: #9)**
  - [x] `TestSearchByBodyFieldHappyPath` — fixture: 3 rows in `SessionAgent.Test.FsbFixtureSearchTable` (Ens.CustomSearchTable subclass extending Ens.SearchTableBase) + 3 matching `Ens.MessageHeader` rows + 1 `Ens.Config.SearchTableProp` mapping. Asserts tool returns 3 sessions, `render_strategy=matched_sessions`, `time_window_used=168`, `indexed_lead_column=PropValue`.
  - [x] `TestSearchByBodyFieldUnknownPropNameReturnsError` — same fixture; invoke with `prop_name="NotARegisteredProp"`; assert `isError:1` with `render_strategy=no_matches` and "not indexed" text.
  - [x] `TestSearchByBodyFieldUnknownClassReturnsError` — invoke with `search_table_class="My.NotARealSearchTable"`; assert `isError:1`, `render_strategy=search_table_not_installed`, AC-3 mandated text mentioning `search_by_message_class` fallback.
  - [x] `OnAfterAllTests` extended to delete fixture rows from `SessionAgent_Test.FsbFixtureSearchTable` (by DocId + belt-and-suspenders by PropId), `Ens_Config.SearchTableProp` (by ClassExtent+Name), and the SessionId-range MessageHeader sweep covers BASESID+50..52.

- [x] **Task 4 — Sibling fix-nows (AC: #12)**
  - [x] `InspectionSuiteVerificationTest`: EXPECTEDTOOLCOUNT 20 → 21; `GetRepresentativeArgs` extended with `search_by_body_field` case (synthetic class triggers `search_table_not_installed` envelope); `tExpected` $ListBuild extended with `search_by_body_field`.
  - [x] `ToolCallRoundtripIntegrationTest`: matrix 80 → 84 in `TestMatrixCardinalityIs52`; `BuildMinimalToolArgs` extended with `search_by_body_field` case using real `EnsLib.HL7.SearchTable` class + synthetic `prop_name` (returns `no_matches` envelope, exercises canonical envelope shape).

- [x] **Task 5 — Verification battery (AC: #8, #10, #11)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`.
  - [x] SQL ground-truth probe per **numerical-MAX-of-non-empty-run** form. Verbatim Total/Passed/Failed captured in Completion Notes.
  - [x] `BoundedWhereInvariantTest` reports verbatim "8 production search tool(s) discovered; 0 violation(s)".
  - [x] AC-11 live smoke: invoke `search_by_body_field` against seeded `EnsLib.HL7.SearchTable` fixture data; verbatim envelope captured in Completion Notes; fixture cleaned up.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~190 lines. Within cap.

### `GetIndexedLeadColumns()` for a per-call-dynamic indexed column

Stories 8.3/8.4 tools each have a STATIC indexed lead column (the column doesn't change per invocation). `SearchByBodyField` is different — the indexed column is `<prop_name>`, which the operator supplies at invocation time. Two design choices:

1. **Return a canonical placeholder (CHOSEN):** `GetIndexedLeadColumns()` returns `["PropValue"]` — the SearchTable extent's indexed property-value column. This is technically correct: every SearchTable subclass has `PropValue` as the indexed column, with `PropId` as the discriminator. The bounded-WHERE invariant test accepts `PropValue` per AC-8 sub-task. Operator's actual `prop_name` is the LOGICAL name; `PropValue` is the PHYSICAL indexed column. The `structuredContent.indexed_lead_column` field reports `"PropValue"` for invariant-test consistency, while the per-tool summary text mentions the operator-supplied `prop_name` for operator-readability.

2. **Return the operator-supplied prop_name (REJECTED):** would require dynamic dispatch through a non-classmethod call shape and would bypass the static-set membership check the invariant test depends on.

Document the canonical-placeholder choice in the tool's class-level doc-comment.

### Reuse of Story 4.6 `FindSessionsByBody` patterns

This story reuses three patterns verbatim from `src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls`:
1. `$ClassMethod(class, "%IsA", "Ens.SearchTableBase")` validation (the empirically-correct one — `%Extends` and `PrimarySuper LIKE` both fail on VDoc subclasses).
2. `Ens.Config.SearchTableProp` two-step prop-name → PropId resolution.
3. v1 VDoc-only scope; `Ens.CustomSearchTable` returns "not configured" graceful error.

Do NOT re-implement these — read FindSessionsByBody.cls and copy the validated logic.

### `BuildBoundedWhereClause` `DefaultTimeWindowHours = 168` override

Architecture OD8 `BodyFieldDefaultHours = 168` (= 7d) — different from the 24h default in `Tool.Search.Base`. Two ways to apply:

1. Override `Parameter DefaultTimeWindowHours = 168` in the concrete class. Cleanest; helper picks up the override automatically when `pTimeWindowHours = 0`.
2. Always pass an explicit `pTimeWindowHours = 168` from the caller. More verbose but more visible.

**Recommendation: option 1 (parameter override).** Document in the class doc-comment that this tool's default window is wider than the other search tools because body-field queries are typically less time-bounded than status/source queries.

### Rule 3 — typed MCPs first

- `iris_doc_compile`, `iris_execute_tests`, `iris_sql_execute`, `iris_execute_classmethod` per usual.

### Rule 4 — stale-reference scan

`grep -rn "search_by_body_field\|SearchByBodyField" .` confirms no stale references pre-this-story.

### Rule 8 — fix-now is the default

Predicted-bug shapes to watch:
- `Ens.Config.SearchTableProp` row absence (test fixture must seed; auto-population by IRIS on first SearchTable insert may or may not fire under direct-SQL fixture path — verify empirically).
- `<search_table_class>` interpolation MUST be validated by AC-3 BEFORE the SQL is constructed (otherwise an attacker could supply a malicious class name → SQL injection via class-name interpolation).

### Rule 9 — no carry-forward bindings to this story

Grep `deferred-work.md` for "Story 8.5" mentions confirms NO existing entries bind here.

### Rule 10 — no external defaults set in this story

`Ens.SearchTableBase`, `Ens.Config.SearchTableProp`, `EnsLib.HL7.SearchTable` are all IRIS Ensemble-internal. The `BodyFieldDefaultHours = 168` constant is documented in architecture OD8. Rule 10 (Perplexity-mandatory verification line) does NOT apply.

### Rule 12 — content-correctness only (no UI surface)

Tool class + extended test classes — no UI rendering.

### Sources

- [`epics.md` §"Story 8.5"](../planning-artifacts/epics.md) — verbatim AC source.
- [`architecture.md` §"FR16", "FR19", "OD8 BodyFieldDefaultHours", "Risk Mitigation: SearchTable not installed"](../planning-artifacts/architecture.md).
- [`prd.md` §"FR16"](../planning-artifacts/prd.md).
- [`src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls`](../../src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls) (Story 4.6) — reuse 3 verbatim patterns: `%IsA` validation, PropId resolution, v1 VDoc scope.
- [`src/SessionAgent/Tool/Search/Base.cls`](../../src/SessionAgent/Tool/Search/Base.cls) — superclass; `BuildBoundedWhereClause` contract.
- [`src/SessionAgent/Test/BoundedWhereInvariantTest.cls`](../../src/SessionAgent/Test/BoundedWhereInvariantTest.cls) `BuildIndexedColumnSet` — sub-task extension.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md), [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md).
- [`_bmad-output/implementation-artifacts/deferred-work.md`](deferred-work.md) **LOW-8.4-F02** — numerical-MAX SQL form note for AC-10 verification.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

- Compile clean: all 5 modified/new classes (`SearchByBodyField`, `SearchToolTest`, `BoundedWhereInvariantTest`, `InspectionSuiteVerificationTest`, `ToolCallRoundtripIntegrationTest`) via `iris_doc_compile` flags `cuk`.
- Empirical state probes pre-implementation: `EnsLib.HL7.SearchTable` exists in HSCUSTOM (1 row in `%Dictionary.CompiledClass`); `Ens_Config.SearchTableProp` had 0 rows for that class (auto-population path requires first SearchTable extent insert OR explicit seeding); `EnsLib_HL7.SearchTable` extent had 0 rows.
- Pattern reused VERBATIM from Story 4.6 `FindSessionsByBody.cls`: existence guard `%Dictionary.CompiledClass.%ExistsId(tSearchClass)` THEN `$ClassMethod(tSearchClass, "%Extends", "Ens.SearchTableBase")`. Per Story 4.6's verified Task-0 finding, `%IsA` returns 0 for abstract intermediates like `EnsLib.HL7.SearchTable`; `%Extends` is the class-lineage check that returns 1 for both abstract and concrete hierarchy members. Dev followed the verbatim-reuse instruction over the AC-3 wording for `%IsA` since the spec explicitly says "Read FindSessionsByBody.cls FIRST and copy validated patterns verbatim, do NOT re-derive".

### Completion Notes List

**Compile + class assembly (Task 1, AC-1..7):**
- `SessionAgent.Tool.Search.SearchByBodyField.cls` shipped at ~290 lines with comprehensive `///` doc-comments enumerating the 3 reused patterns from Story 4.6, the indexed-lead-column placeholder rationale (PropValue physical vs prop_name logical), the `DefaultTimeWindowHours = 168` override, and the `Catch ex` operator-friendly text path via `Tool.Base.FormatExceptionForOperator`.
- The `BuildBoundedWhereClause(tWindowHours, .tParams, .tErr, "st.PropId = ?", "%EXACT(st.PropValue) = ?")` invocation emits `TimeCreated > ? AND st.PropId = ? AND %EXACT(st.PropValue) = ?` and the dev applied `$Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")` to qualify the time predicate to the Ens.MessageHeader alias since the JOIN form requires it. (Future generalization candidate — `Tool.Search.Base` could accept an optional alias parameter, but for now the in-tool $Replace is local and well-contained.)

**Verification battery (Task 5, AC-8/10/11):**

**Regression sweep — SQL ground-truth probe (numerical-MAX-of-non-empty-run form per Story 8.4 reviewer correction LOW-8.4-F02):**

```sql
SELECT COUNT(*) AS Total, SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed, SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
JOIN (SELECT %EXACT(tc2.Name) AS ClassName, MAX(CAST($PIECE(tc2.ID, '||', 1) AS INTEGER)) AS MaxRunId
      FROM %UnitTest_Result.TestCase tc2
      WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
        AND EXISTS (SELECT 1 FROM %UnitTest_Result.TestMethod tm2 WHERE tm2.TestCase = tc2.ID)
      GROUP BY %EXACT(tc2.Name)) latest
  ON %EXACT(tc.Name) = latest.ClassName
 AND CAST($PIECE(tc.ID, '||', 1) AS INTEGER) = latest.MaxRunId
```

**Verbatim result row:**
```
Total | Passed | Failed
 313  |   313  |   0
```

Per-class breakdown (39 test classes; ground-truth via SQL; matches and exceeds the spec's predicted ~313 baseline):
- AgentConfigTest 16/16, AgentDtoTest 7/7, AgentLoopGuardsTest 9/9, AgentLoopTest 3/3, AnthropicProviderTest 11/11, AuditEmitTest 3/3, AuditTest 8/8, BoundedWhereInvariantTest 5/5, BusinessProcessIntrospectionTest 10/10, ChatHistoryTest 10/10, ChatPanelDrawHelperTest 4/4, ChatPanelJsTest 18/18, ConfigAgentTest 10/10, EnvSecretTest 8/8, FindRelatedSessionsTest 5/5, FindSessionsByBodyTest 7/7, GeminiProviderTest 11/11, GetMessageBodyTest 12/12, GetMessageDetailTest 6/6, InspectionSuiteVerificationTest 13/13, InspectionToolTest 15/15, JsonTest 9/9, MessageAdapterTest 11/11, MultiNamespaceInstallTest 6/6, OpenAICompatProviderTest 11/11, OpenAIProviderTest 8/8, PurgeTaskTest 3/3, ReadOnlyRoleTest 6/6, RetryWithBackoffTest 9/9, SampleProductionTest 3/3, **SearchToolTest 12/12** (9 prior + 3 new SearchByBodyField methods), SeedVocabularyTest 5/5, SmokeTest 1/1, Story41ToolsTest 12/12, ToolBaseTest 3/3, **ToolCallRoundtripIntegrationTest 4/4** (matrix cardinality test now asserts 84 = 4 × 21), ToolDefAdapterTest 3/3, ToolRegistryTest 8/8, VisualTraceTest 8/8.

**Bounded-WHERE invariant test — verbatim log line (AC-8):** captured from `^UnitTest.Result(516,"(root)","SessionAgent.Test.BoundedWhereInvariantTest","TestRegisteredSearchToolsHaveBoundedWhere",26)`:

```
8 production search tool(s) discovered; 0 violation(s)
```

(Story 8.4 close was "7 production search tool(s)"; Story 8.5 transitions to 8.) The 8 discovered tools alphabetically: `SessionAgent.Tool.Search.SearchByBodyField`, `SearchByMessageClass`, `SearchBySession`, `SearchBySource`, `SearchByStatus`, `SearchBySuperSession`, `SearchByTarget`, `SearchByTime`. Each tool's `GetIndexedLeadColumns()` returns at least one column from the indexed-set (TimeCreated/Status/SourceConfigName/TargetConfigName/MessageBodyClassName/SessionId/SuperSessionKey/PropValue). Zero violations.

**AC-11 live smoke envelope (verbatim from `iris_execute_classmethod` against seeded `EnsLib.HL7.SearchTable` fixture):**

Fixture seeded via temporary classmethod `SessionAgent.Test.Ac11LiveSmokeHelper.SeedFixture()`:
- 1 `Ens_Config.SearchTableProp` row mapping (`EnsLib.HL7.SearchTable`, `AC11LiveSmokeProp`) → `PropID=8505001`
- 1 `EnsLib_HL7.SearchTable` row with `(PropId=8505001, PropValue="AC11LiveValue", DocId="AC11LiveDocId")`
- 1 `Ens.MessageHeader` row with `SessionId=998885, MessageBodyId="AC11LiveDocId", TimeCreated=$ZTimeStamp` (fresh, well within 168h window)

Invocation: `SearchByBodyField.Invoke({"search_table_class":"EnsLib.HL7.SearchTable","prop_name":"AC11LiveSmokeProp","prop_value":"AC11LiveValue"})`

Verbatim envelope JSON returned:

```json
{"content":[{"type":"text","text":"Found 1 session(s) where AC11LiveSmokeProp = 'AC11LiveValue' in EnsLib.HL7.SearchTable in the last 168 hour(s)."}],"structuredContent":{"sessions":[{"session_id":998885,"time_created":"2026-05-07T10:50:17Z","source_config_name":"AC11LiveSmokeSrc","target_config_name":"AC11LiveSmokeTgt","message_body_class_name":"AC11Live.Msg","status":9}],"search_table_class":"EnsLib.HL7.SearchTable","prop_name":"AC11LiveSmokeProp","prop_value":"AC11LiveValue","time_window_used":168,"session_count":1,"indexed_lead_column":"PropValue","render_strategy":"matched_sessions"}}
```

Envelope contract checks per AC-6:
- `render_strategy=matched_sessions` ✓
- `session_count=1` ✓
- `time_window_used=168` (this tool's default override, not the base 24h) ✓
- `indexed_lead_column="PropValue"` (canonical placeholder per AC-1; matches the AC-8 `BuildIndexedColumnSet` extension) ✓
- `sessions[0]` has all 6 expected fields (session_id, time_created, source_config_name, target_config_name, message_body_class_name, status) ✓
- `time_created` is ISO-Z form `2026-05-07T10:50:17Z` (20 chars, T@11, Z@20) ✓
- Operator-readable summary text mentions operator-supplied `prop_name`, `prop_value`, and `search_table_class` — readable English, no mojibake ✓

Fixture cleaned up post-smoke (DELETE statements verified — 0 rows remaining in all 3 fixture extents). Temporary helper class `SessionAgent.Test.Ac11LiveSmokeHelper.cls` removed from filesystem and IRIS server.

**Class-validation pattern note (Rule 8 fix-now consideration):** AC-3 wording in the spec says `$ClassMethod(class, "%IsA", "Ens.SearchTableBase")` BUT the Dev Notes "Reuse 3 patterns verbatim from Story 4.6" instruction overrides — Story 4.6 empirically verified `%IsA` returns 0 for abstract `EnsLib.HL7.SearchTable` (the canonical real-world target), and `%Extends` is the correct check. Dev followed the verbatim-reuse instruction, used `%Extends`. Reviewer note for Story 8.5 review: this is the empirically-correct pattern; AC-3 wording is a minor spec drift that should be reconciled to "%Extends" for future story authors.

**Sibling fix-nows summary (AC-12):**
- `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` 20 → 21 ✓
- `InspectionSuiteVerificationTest.GetRepresentativeArgs` adds `search_by_body_field` case ✓
- `InspectionSuiteVerificationTest.TestRegistryListsExactlyThirteenTools` $ListBuild extended ✓
- `ToolCallRoundtripIntegrationTest.TestMatrixCardinalityIs52` asserts 84 = 4 × 21 ✓
- `ToolCallRoundtripIntegrationTest.BuildMinimalToolArgs` adds `search_by_body_field` case ✓

### File List

**New:**
- `src/SessionAgent/Tool/Search/SearchByBodyField.cls` — concrete `Tool.Search.Base` subclass implementing `search_by_body_field` (Task 1).

**Modified:**
- `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` — `BuildIndexedColumnSet` extended with `PropValue` entry + doc-comment update (Task 2).
- `src/SessionAgent/Test/SearchToolTest.cls` — class header doc-comment extended for Story 8.5; 4 new Parameters (`BFFIXTURECLASS`, `BFFIXTUREPROPNAME`, `BFFIXTUREPROPID`, `BFFIXTUREPROPVALUE`, `BFFIXTURESOURCESENTINEL`); `OnBeforeAllTests` extended with body-field fixture seeding block + body-field cleanup in defensive sweep; `OnAfterAllTests` extended with body-field cleanup; 3 new test methods (`TestSearchByBodyFieldHappyPath`, `TestSearchByBodyFieldUnknownPropNameReturnsError`, `TestSearchByBodyFieldUnknownClassReturnsError`) (Task 3).
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` — `EXPECTEDTOOLCOUNT` 20→21; `GetRepresentativeArgs` extended with `search_by_body_field` case; `TestRegistryListsExactlyThirteenTools` $ListBuild extended (Task 4).
- `src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls` — `BuildMinimalToolArgs` extended with `search_by_body_field` case; `TestMatrixCardinalityIs52` asserts 84 (4×21) (Task 4).
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story status updated.
- `_bmad-output/implementation-artifacts/8-5-searchbybodyfield-ens-searchtablebase-pivot.md` — Tasks/Subtasks marked complete; Dev Agent Record populated.

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) | **Date:** 2026-05-07 | **Verdict:** APPROVED FOR COMMIT

### Methodology

Adversarial three-layer review (Blind Hunter for diff-only correctness, Edge Case Hunter for boundary/branch coverage, Acceptance Auditor for AC compliance), consolidated into structured triage. Diff scope: 1 new file (`SearchByBodyField.cls`, ~414 LOC) + 4 modified test classes + sprint-status flip. Spec-mode: FULL (story file + Story 4.6 reference + Tool.Search.Base + BoundedWhereInvariantTest).

### Verification of focus areas

| Focus area | Status | Evidence |
|---|---|---|
| AC-1 inheritance + canonical placeholder `["PropValue"]` | ✓ | `SearchByBodyField.cls:131`; `BoundedWhereInvariantTest.cls:230` extension placed in `BuildIndexedColumnSet` body with doc-comment citing SearchByBodyField as consumer (lines 211–220). |
| AC-3 `%Extends` empirical pattern (deviates from spec's `%IsA`) | ✓ (deviation correct; spec drift logged as LOW-8.5-F01) | `SearchByBodyField.cls:241` uses `%Extends`; Story 4.6 [`FindSessionsByBody.cls:217`](../../src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls#L217) and its class doc-comment §"Class validation idiom" (lines 37–61) confirm `%Extends` is the empirically-correct probe — `%IsA` returns 0 for abstract `EnsLib.HL7.SearchTable`. Dev correctly followed verbatim-reuse instruction. |
| AC-4 SQL safety order — class validation BEFORE FROM-clause interpolation | ✓ | Validation gates at `SearchByBodyField.cls:227, 241` (Step 3). FROM-clause assembly at line 314 (Step 7). `tSqlSchema`/`tSqlTable` come from `%Dictionary.CompiledClass` projection (line 306), not operator input. |
| AC-4 Step B `BuildBoundedWhereClause` alias-qualification workaround | ✓ functionally correct; refactor candidate logged as MEDIUM-8.5-F02 → Story 8.6 | `SearchByBodyField.cls:336` — `$Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")`. Substring is unique to `BuildBoundedWhereClause`'s output (`Base.cls:205`); no operator input flows through; no aliasing collision possible. |
| AC-5 `%EXACT()` discipline | ✓ | Strings wrapped: `mh.SourceConfigName`, `mh.TargetConfigName`, `mh.MessageBodyClassName` (lines 343–345); `mh.MessageBodyId`/`st.DocId` JOIN (line 348); `st.PropValue` predicate (line 324); `Ens.Config.SearchTableProp.ClassExtent`/`Name` (line 267). Integers correctly unwrapped: `st.PropId` (line 324), `mh.Status` (line 346), `mh.SessionId` (line 342), `TOP ?` (line 342). `mh.TimeCreated` correctly unwrapped (Ens.DataType.UTC). |
| AC-7 graceful path — no exception escapes Invoke to outer Catch on missing SearchTable | ✓ | Both validation gates emit structured envelope + `Quit` Try block. `%ExistsId` returns 0 for uninstalled classes; no exception raised. |
| AC-8 invariant test extension placed in `BuildIndexedColumnSet` body | ✓ | `BoundedWhereInvariantTest.cls:230` — `Set pSet("PropValue") = 1` inside the helper's body. Doc-comment block (lines 203–220) explicitly cites `SessionAgent.Tool.Search.SearchByBodyField` as the consumer. |
| AC-9 test fixtures — seeding + cleanup comprehensive | ✓ | `OnBeforeAllTests` seeds 1 SearchTableProp + 3 fixture-SearchTable + 3 MessageHeader rows (`SearchToolTest.cls:158–229`); pre-seed defensive sweep (lines 178–183) clears prior-run debris in BOTH SearchTable and SearchTableProp extents. `OnAfterAllTests` (lines 441–467) deletes by captured DocIds, by SearchTableProp (ClassExtent+Name), then belt-and-suspenders by PropId; existing SessionId-range MessageHeader sweep covers BASESID+50..52. |
| AC-10 SQL probe form numerical-MAX-of-non-empty-run + 313 total | ✓ | Story spec lines 184–201 — verbatim aggregate form per Story 8.4 reviewer correction LOW-8.4-F02. 310 (Story 8.4 close per sprint-status `last_updated`) + 3 new SearchToolTest methods = 313. Math consistent. |
| AC-11 live smoke envelope shape | ✓ | Verbatim envelope (story spec line 226) contains every contract field: `sessions[1]` with 6 fields, `search_table_class`, `prop_name`, `prop_value`, `session_count=1`, `time_window_used=168` (default override exercised), `indexed_lead_column="PropValue"`, `render_strategy="matched_sessions"`. ASCII-only summary. |
| AC-12 sibling fix-nows — count + matrix | ✓ | `EXPECTEDTOOLCOUNT` 20→21 (`InspectionSuiteVerificationTest.cls:71`); $ListBuild extended (line 317); `BuildMinimalToolArgs` adds case (`ToolCallRoundtripIntegrationTest.cls:337`); matrix 80→84 (line 716). Math: 4 providers × (13 inspection + 8 search) = 84. |
| Operator-observable surface enumeration (Story 8.0 AC-1) | ✓ | Every parameter, classmethod, and the class itself in `SearchByBodyField.cls` carries `///` doc-comments. |
| Process-private global subscript naming (`^||SessionAgentSearchBodyFieldTestIds`) | ✓ | camelCase; no hyphens. Per project rule §"Process-Private Globals". |
| Pre-existing `<INVALID OREF>` flake on `AgentLoopGuardsTest.RunTurnAuditCompletenessForToolDispatch` | Acknowledged; not a blocker; unrelated to Story 8.5. Re-run cleanly per dev report. |

### Findings & severity triage

**HIGH:** 0 findings.

**MEDIUM:** 1 finding (deferred to Story 8.6 with binding carrier per Rule 9).

- **MEDIUM-8.5-F02** — `Tool.Search.Base.BuildBoundedWhereClause` lacks optional alias parameter for JOIN-form callers; the local `$Replace` workaround at `SearchByBodyField.cls:336` is correct but sets a precedent that future search-tool authors will re-inherit. Predicted-bug shape: if `BuildBoundedWhereClause`'s emitted substring drifts in a future Story 8.6+ change, the local `$Replace` will silently fail and surface as `<SQLCODE>` -29 ambiguous-column at runtime. **Binding successor: Story 8.6** (`InspectBodyCandidates`) — also pivots through SearchTable + JOIN, second consumer of the same shape. The refactor (additive optional `pTimeColumnAlias` parameter) is backward-compatible and fits naturally inside Story 8.6's scope. See [`deferred-work.md` MEDIUM-8.5-F02](deferred-work.md) for the full carrier-binding entry per Rule 9.

**LOW:** 4 findings.

- **LOW-8.5-F01** — AC-3 spec wording drift (`%IsA` → `%Extends`). Pure documentation cosmetic; live code is correct (verbatim-reused from Story 4.6). One-line `epics.md` edit. See [`deferred-work.md` LOW-8.5-F01](deferred-work.md).
- **LOW-8.5-F03** — `^||SessionAgentSearchBodyFieldTestIds` subscript naming verified clean (camelCase, no hyphens). No finding.
- **LOW-8.5-F04** — Local `$Replace` is documented inline (`SearchByBodyField.cls:329–335`) explaining WHY it's needed AND noting the future-generalization candidate exists. Documentation is sufficient. No fix required.
- **LOW-8.5-F05** — Pre-existing `<INVALID OREF>` flake on `AgentLoopGuardsTest.RunTurnAuditCompletenessForToolDispatch` is unrelated to Story 8.5; re-ran cleanly. Noted for completeness; no action.

### Auto-resolved findings

None — no HIGH or MEDIUM findings required code edits. All findings either pass verification (✓) or are correctly deferred per Rule 8 (genuine future-epic scope or pure documentation cosmetic with no predicted-bug shape in current code).

### Approve / reject

**APPROVED.** Story 8.5 ships clean: AC-1 through AC-12 satisfied, 313/313/0 SQL ground-truth confirmed, AC-11 live-smoke envelope contract-complete, sibling fix-nows mathematically consistent, operator-observable surface fully doc-commented, no HIGH or MEDIUM blockers in shipped code. Two informational deferred-work entries logged: LOW-8.5-F01 (lead spec-correction; no code) and MEDIUM-8.5-F02 (binding successor: Story 8.6 — refactor candidate per Rule 9).



## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-07 | Initial spec drafted by lead from epics.md §"Story 8.5" | Claude Opus 4.7 (lead) |
| 2026-05-07 | Implementation complete — `SearchByBodyField` shipped + 3 SearchToolTest methods + sibling fix-nows for InspectionSuiteVerificationTest 20→21 and ToolCallRoundtripIntegrationTest 80→84; 313/313/0 SQL ground-truth via numerical-MAX-of-non-empty-run form; "8 production search tool(s) discovered; 0 violation(s)" verbatim log line; AC-11 live smoke against seeded `EnsLib.HL7.SearchTable` fixture returned `render_strategy=matched_sessions` with all envelope contract fields. Status → review. | Claude Opus 4.7 (dev) |
