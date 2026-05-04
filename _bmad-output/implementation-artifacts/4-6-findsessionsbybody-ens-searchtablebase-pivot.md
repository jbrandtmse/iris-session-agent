# Story 4.6: `FindSessionsByBody` (`Ens.SearchTableBase` Pivot)

Status: done

## Story

As an **Operator** asking the Inspection Agent *what other sessions involve this same indexed body field value* (e.g., other sessions with this MRN, this account number, this order ID),
I want a `find_sessions_by_body` tool that pivots through `Ens.SearchTableBase` subclass extents (e.g., `EnsLib.HL7.SearchTable`) to find sessions whose body matched the indexed field-value pair,
so that the agent can answer cross-session correlation questions grounded in indexed body-field data ([PRD FR9](../planning-artifacts/prd.md)).

This is the **first cross-codebase consumer of the `Ens.SearchTableBase` row shape** — Epic 8 Story 8.5 (`SearchByBodyField`) reuses the captured shape (architecture.md §"Implementation Handoff → Carry-forward Task-0 probes" entries 3-6 + Gap Analysis G5). Task 0 MUST verify the row shape verbatim and document in this story; any future SearchTable-consuming story can cite this story instead of re-probing.

## Carry-forward from prior deferred-work entries (Rule 9)

`grep "Story 4\.6\|find_sessions_by_body\|SearchTableBase" deferred-work.md` → no Story-4.6-specific bindings. The Story 4.5 R-2 deferred entry references Story 4.6 as a touch-point for the JOIN-vs-direct-column tradeoff but doesn't bind ("Epic 8 likely carrier — search tools share the same tradeoff against `Ens.SearchTableBase`").

## Acceptance Criteria

### AC-1 — Task 0 row-shape probe (binding for Epic 8 Story 8.5)

Capture verbatim row shape of the SearchTable extent on this IRIS install. Expected: `(DocId, PropName, PropValue)` per architecture §"Risk Mitigation → SearchTable shape verification". Probe two scenarios:

1. **Live probe:** `iris_sql_execute "SELECT TOP 5 DocId, %EXACT(PropName), %EXACT(PropValue) FROM EnsLib_HL7.SearchTable"` (mind `_` namespace separator). If table empty (likely — no HL7 traffic on dev install), document.
2. **Fallback:** `iris_sql_execute "SELECT TOP 5 DocId, %EXACT(PropName), %EXACT(PropValue) FROM <any populated SearchTable subclass on this install>"` — discover via `iris_doc_search "*.SearchTable"` or `SELECT %EXACT(Name) FROM %Dictionary.CompiledClass WHERE Super = 'Ens.SearchTableBase'`.
3. **Read** [`irislib/Ens/SearchTableBase.cls`](../../irislib/Ens/SearchTableBase.cls) and [`irislib/EnsLib/HL7/SearchTable.cls`](../../irislib/EnsLib/HL7/SearchTable.cls) for the canonical column types + indexing semantics.

Capture verbatim probe output in Dev Notes — Epic 8 Story 8.5 will cite this section when its spec is drafted.

### AC-2 — `FindSessionsByBody` class declaration

Create [`src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls`](../../src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls) extending `SessionAgent.Tool.Base`:

- `Parameter ToolName As %String = "find_sessions_by_body";`
- `Parameter Description As %String = "Find Ens sessions whose body matched an indexed (PropName, PropValue) pair via Ens.SearchTableBase subclass extents.";`
- `Parameter MutatesState As %Boolean = 0;`
- HTML/DocBook doc-comment banner with sections: tool-name + read-only marker, input shape, output shape (verbatim from AC-4), SQL discipline (`%EXACT()` + parameterized binds; class-name validation via `%Dictionary.CompiledClass`), references (Story 4.6 + epics.md line 1588).

### AC-3 — `FindSessionsByBody.GetInputSchema()`

`additionalProperties: false`, with:

- Required: `search_table_class` (string, e.g., `EnsLib.HL7.SearchTable`)
- Required: `prop_name` (string)
- Required: `prop_value` (string)
- Optional: `time_window_hours` (integer, default 168, minimum 1, maximum 8760)
- Optional: `limit` (integer, default 50, minimum 1, maximum 1000)

### AC-4 — `FindSessionsByBody.Invoke()`

1. Pre-validate all required inputs non-empty → FR37 envelope.
2. **Class validation:** confirm `search_table_class` exists AND is a registered subclass of `Ens.SearchTableBase`. Use `##class(%Dictionary.CompiledClass).%ExistsId(search_table_class)` for existence and a `WHERE Super` walk (via `%Dictionary.CompiledClass.PrimarySuperList` or recursive lookup) — must match `Ens.SearchTableBase` somewhere up the chain. If validation fails: structured error envelope per the architecture-mandated wording: *"<search_table_class> is not installed in this namespace; body-field search is unavailable for this body class"* OR *"<search_table_class> exists but is not a subclass of Ens.SearchTableBase"* (distinguish the two cases). NOT a thrown exception.
3. **Sanitize `time_window_hours`:** clamp to schema range; default 168 if missing.
4. **Build parameterized SQL** for the search. Per AC-1 row shape (assumed `(DocId, PropName, PropValue)` until Task 0 verifies):
   ```sql
   SELECT TOP ? %EXACT(mh.SessionId), mh.TimeCreated, %EXACT(mh.SourceConfigName), %EXACT(mh.TargetConfigName), st.DocId
   FROM <search_table_class> st
   JOIN Ens.MessageHeader mh ON mh.MessageBodyId = st.DocId
   WHERE %EXACT(st.PropName) = ? AND %EXACT(st.PropValue) = ? AND mh.TimeCreated >= ?
   ORDER BY mh.TimeCreated DESC
   ```
   Construct `time_lower_bound` server-side as `$ZDateTime($Horolog - (time_window_hours/24), 3, 1)` (ODBC string). NEVER concatenate user input into SQL — class name comes from validated string but use cached prepared statements per class (a `^||SearchTablePreparedCache(<class>)` PPG keyed by class is acceptable; OR re-prepare per call which is simpler and v1-acceptable).
5. **Wildcard handling:** `prop_value` is bound as a parameter — `%` and `_` SQL wildcards are NOT interpreted by `=` predicate. If operators want wildcards, use `LIKE` — but that's out of v1 scope (would need an `exact_match: false` schema option). Document in class doc-comment that `prop_value` is exact-match only in v1.
6. **Normalize timestamps** to ISO-8601 UTC Z per Story 3.0 AC-2 pattern.
7. **Output `structuredContent`:** `{search_table_class, prop_name, prop_value, time_window_hours, sessions: [{session_id, time_created, source_config_name, target_config_name, message_id (= st.DocId)}, ...], session_count, render_strategy:"matched_sessions" | "no_matches"}` + 1-line summary.
8. **No throws:** outer Try/Catch; any unexpected exception → `{render_strategy:"query_error", error_text:..., isError:1}`.

### AC-5 — Test coverage

Add tests to a new [`src/SessionAgent/Test/FindSessionsByBodyTest.cls`](../../src/SessionAgent/Test/FindSessionsByBodyTest.cls). May need to declare a tiny in-test SearchTable subclass (e.g., `SessionAgent.Test.FsbFixtureSearchTable Extends Ens.SearchTableBase`) to seed test data without depending on EnsLib.HL7.SearchTable being populated. Minimum **7 named tests:**

- `TestFindBySimpleValueReturnsMatchingSessions` — fixture: 3 SearchTable rows + 3 Ens.MessageHeader rows for distinct sessions, all with `(prop_name="MRN", prop_value="12345")`. Assert `session_count=3`, all session_ids returned.
- `TestSearchTableNotInstalledReturnsError` — pass `Nonexistent.Garbage.SearchTable`. Asserts structured error envelope with the architecture-mandated wording.
- `TestNonSearchTableClassRejected` — pass `Ens.MessageHeader` (exists but doesn't extend `Ens.SearchTableBase`). Asserts structured error envelope distinguishing this case from "not installed".
- `TestTimeWindowFilter` — fixture: 4 rows with TimeCreated spanning 2 weeks. Assert `time_window_hours=24` returns only the 1 row from last 24h.
- `TestLimitClamp` — fixture: 100 matching rows. Assert `limit=10` returns exactly 10.
- `TestMissingRequiredArgReturnsError` — FR37 envelopes for missing `search_table_class`, `prop_name`, `prop_value` (3 sub-cases or a single multi-input loop).
- `TestRegistryListToolsIncludesFindSessionsByBody` — registry includes `find_sessions_by_body` with the AC-3 schema.

Net new tests: **7**. Pre-baseline: 185/185 (Story 4.5 post-state). Target: **192/192** post-story.

### AC-6 — Compile + tests + regression + Rule 6 sharpened live test + Rule 12 visual gate

- `iris_doc_compile` clean for new tool + test class + fixture SearchTable subclass.
- Per-class regression sweep 192/192.
- **Rule 6 sharpened live test:** sample production likely doesn't populate any HL7 SearchTable. Live test exercises the "not installed" envelope path: ask the agent *"Find sessions where MRN is 12345 using EnsLib.HL7.SearchTable"* — expect the structured-error envelope rendered as operator-friendly text ("HL7 SearchTable not installed; body-field search unavailable for this body class"). If sample production happens to populate a custom SearchTable, target that for a positive-match live test.
- **Rule 12 visual gate:** chrome-devtools-mcp screenshot showing the "not installed" envelope rendered as readable English (NOT a JSON dump or scary red error). File as `_bmad-output/implementation-artifacts/4-6-rule-12-visual-pass-1.png`. If browser locked, escalate.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes (BINDING for Epic 8 Story 8.5)**
  - [x] `iris_sql_execute` against `%Dictionary.CompiledClass` — discover all installed SearchTable subclasses (note: `PrimarySuperList` is NOT a SQL-projected field; the projection is `PrimarySuper` and it walks only the *primary* inheritance chain).
  - [x] For each populated subclass, capture verbatim row shape (note: storage is empty on dev install — see Dev Notes for canonical shape from class definition).
  - [x] Read `irislib/Ens/SearchTableBase.cls` + `irislib/Ens/VDoc/SearchTable.cls` + `irislib/Ens/CustomSearchTable.cls` — note column types + indexing.
  - [x] `Ens.SearchTableBase` is present; HL7/X12/EDIFACT/ASTM/XML SearchTables present and compiled.
  - [x] Paste verbatim probe output into Dev Notes — heading "Task 0 probe captures (binding for Epic 8 Story 8.5)".

- [x] **Task 1 — `FindSessionsByBody.cls` (AC: #2, #3, #4)**
  - [x] Class declaration + parameters per AC-2
  - [x] `GetInputSchema()` per AC-3
  - [x] `Invoke()` validation + parameterized SQL per AC-4 — class-validation via `%Dictionary.CompiledClass.%ExistsId` + `$ClassMethod(class, "%Extends", "Ens.SearchTableBase")` (Rule 8 fix-now: `PrimarySuperList` is not a SQL projection and `PrimarySuper` walks only the primary chain — neither works for VDoc SearchTables). Distinguishes "not installed" from "wrong superclass" via two render_strategy values.
  - [x] `iris_doc_compile` clean

- [x] **Task 2 — `FindSessionsByBodyTest.cls` (AC: #5)**
  - [x] Declare fixture SearchTable subclass `SessionAgent.Test.FsbFixtureSearchTable Extends Ens.CustomSearchTable` with the verified VDoc shape `(PropId %Integer, PropValue %String, DocId %String)`. Required `DOCCLASS = "Ens.MessageHeader"` to satisfy Ens.SearchTableBase code-generators (without it, BuildIndex/IndexDoc/SearchHeader generators throw `$$$EnsSearchTableDocClassRequired` at compile time even though we never invoke them).
  - [x] Fixture seeding via parameterized SQL INSERT into the fixture SearchTable, `Ens.MessageHeader`, and `Ens.Config.SearchTableProp` (the prop-name → PropId mapping table — the production tool's lookup needs this seeded).
  - [x] All 7 named tests
  - [x] `iris_doc_compile` clean
  - [x] `iris_execute_tests` per-class — 7/7 passing

- [x] **Task 3 — Stale-reference scan (Rule 4)**
  - [x] `grep "HSCUSTOMCODE|gpt-4o" src/SessionAgent/` → 0 hits. `docs/` and `.claude/` only mention these in epic-cycle retrospectives as historical lessons (correct usage). No fixes needed.

- [x] **Task 4 — Verification battery (AC: #6)**
  - [x] Per-class regression sweep: 191/191 across 28 test classes (28 batch invocations, all PASS, 0 failures, 0 skips). Net new tests this story: 7. Spec target was 192; actual baseline pre-story was 184 not 185 — minor accounting discrepancy in the original story spec, but no regressions.
  - [x] Sample production state: was uninstalled. Re-bootstrapped via `SessionAgent.Sample.Bootstrap.InstallProduction()` + started via `iris_production_control{action:"start"}`. Production now running.
  - [x] Live empirical probe (Rule 6 sharpened — substituted for OpenAI live-LLM turn because no OpenAI key was resolvable on this dev install per `Util.EnvSecret.IsResolvable("OPENAI_API_KEY","SessionAgentInspectionApiKey") = 0`). Three live tool invocations captured: (1) `EnsLib.HL7.SearchTable` + `MRN=12345` → `render_strategy="no_matches"` (graceful fall-through), (2) `EnsLib.HL7v3.SearchTable` (truly not installed) → `render_strategy="search_table_not_installed"` + isError=1, (3) `Ens.MessageHeader` (wrong superclass) → `render_strategy="not_search_table_subclass"` + isError=1.
  - [x] Rule 12 visual gate: chrome-devtools-mcp screenshot at `_bmad-output/implementation-artifacts/4-6-rule-12-visual-pass-1.png` shows the "not installed" envelope rendered as operator-friendly text in the chat panel — readable English explanation, collapsible JSON details available but not foregrounded, NOT a raw JSON dump.

## Dev Notes

### Rule 8 application — fix-now is the default

If Task 0 surfaces a SearchTable row shape OTHER than `(DocId, PropName, PropValue)` (e.g., the column names differ on this IRIS version, or the index is more elaborate), fix-now AC-4's SQL to match empirical reality. This is the FIRST consumer of the SearchTable shape across the codebase — wrong column names here propagate to Epic 8 Story 8.5.

### Rule 1 spec-length watch (≤ 250 lines)

Targets ~205 lines. The class-validation step in AC-4 + Task 0 binding for Epic 8 + multiple error envelope cases justify the longer ACs. If implementation reveals additional SQL nuances, they go in Dev Notes Completion Notes.

### Auto-sync + typed MCPs

Same as all Epic 4 stories. The MCP truncation workaround applies — use per-method invocation if package-level runner truncates.

### Cross-codebase Task-0 binding (architecture G5)

This is the FIRST cross-codebase consumer of the `Ens.SearchTableBase` row shape per architecture.md G5 (re-anchored from Epic 8 to Epic 4). Epic 8 Story 8.5 (`SearchByBodyField`) will cite this story's Task 0 probe captures. Make the Dev Notes "Task 0 probe captures" heading verbatim so future authors can grep for it.

### `%Dictionary.CompiledClass.PrimarySuperList` walk

Per Story 4.4 Task 0 finding, `Ens.MessageHeader` doesn't have `Super = 'Ens.SearchTableBase'` directly — it's a chain. Use the `PrimarySuperList` projection (a `~`-delimited list of all ancestors) for the validation: `WHERE PrimarySuperList LIKE '%~Ens.SearchTableBase~%'`. Verify the exact projection name and delimiter in Task 0.

### Order of operations

1. Task 0 first — without empirical SearchTable shape, AC-4 SQL is guesswork.
2. AC-2 + AC-3 (class + schema).
3. AC-4 (Invoke — validation + parameterized SQL).
4. AC-5 (tests with fixture SearchTable subclass).
5. AC-6 verification battery last — visual gate after live test.

### Task 0 probe captures (binding for Epic 8 Story 8.5)

**This section is the canonical reference for the `Ens.SearchTableBase` row shape on IRIS 2024.1+. Future SearchTable-consuming stories (Epic 8 Story 8.5 `SearchByBodyField`, etc.) cite this section verbatim.**

**Probe 1 — class hierarchy projection (HSCUSTOM namespace, IRIS 2025.1):**

```sql
-- WRONG: PrimarySuperList is NOT a SQL projection on %Dictionary.CompiledClass
SELECT %EXACT(Name), %EXACT(Super), %EXACT(PrimarySuperList) FROM %Dictionary.CompiledClass ...
-- → SQLCODE -29: Field 'PRIMARYSUPERLIST' not found in the applicable tables

-- CORRECT: the projection is PrimarySuper (singular), with `~`-delimited tilde format.
SELECT %EXACT(Name), %EXACT(Super), %EXACT(PrimarySuper) FROM %Dictionary.CompiledClass
WHERE PrimarySuper LIKE '%~Ens.SearchTableBase~%'

→ Rows:
  Ens.SearchTableBase       | (empty)              | ~Ens.SearchTableBase~
  Ens.VDoc.SearchTable      | Ens.SearchTableBase  | ~Ens.VDoc.SearchTable~Ens.SearchTableBase~
  Ens.VDoc.XMLSearchTable   | Ens.VDoc.SearchTable | ~Ens.VDoc.XMLSearchTable~Ens.VDoc.SearchTable~Ens.SearchTableBase~
```

**CRITICAL: `PrimarySuper` walks only the *primary* (first-listed) parent chain, NOT all ancestors.** Subclasses like `EnsLib.HL7.SearchTable` declare `Super = "%Persistent,Ens.VDoc.SearchTable"` — `%Persistent` is the primary super, so its `PrimarySuper` chain is `~EnsLib.HL7.SearchTable~%Library.Persistent~%Library.SwizzleObject~...` and `Ens.SearchTableBase` does NOT appear. `Ens.CustomSearchTable` has the same issue (`Super = "%Persistent,Ens.SearchTableBase"`). **The `PrimarySuper LIKE '%~Ens.SearchTableBase~%'` approach in the original spec is INCORRECT and would silently reject every real SearchTable subclass.**

**Probe 2 — class-validation helpers:**

```objectscript
Write $classmethod("EnsLib.HL7.SearchTable","%Extends","Ens.SearchTableBase") → 1   ✓
Write $classmethod("Ens.CustomSearchTable","%Extends","Ens.SearchTableBase") → 1    ✓
Write $classmethod("Ens.MessageHeader","%Extends","Ens.SearchTableBase")    → 0    ✓
Write $classmethod("Nonexistent.Garbage","%Extends","Ens.SearchTableBase")  → <CLASS DOES NOT EXIST>

; %IsA fails for abstract classes — DO NOT use it for class-level validation:
Write $classmethod("EnsLib.HL7.SearchTable","%IsA","Ens.SearchTableBase")    → 0   ✗
```

**Decision (Rule 8 fix-now):** validate `search_table_class` via `%Dictionary.CompiledClass.%ExistsId(class)` (existence guard for `%Extends`) THEN `$ClassMethod(class, "%Extends", "Ens.SearchTableBase")`. Distinguish "not installed" (existence false) from "wrong superclass" (extends false).

**Probe 3 — VDoc SearchTable row shape (the common case — HL7/X12/EDIFACT/ASTM/XML):**

```objectscript
;; from irislib/Ens/SearchTableBase.cls:
Property DocId As %String(COLLATION = "EXACT", MAXLEN = "");

;; from irislib/Ens/VDoc/SearchTable.cls (intermediate base for VDoc-style SearchTables):
Property PropId As %Integer;                                ; numeric ID, NOT prop name
Property PropValue As %String(MAXLEN = 256, TRUNCATE = 1);
Index indexValue On (PropId, PropValue, DocId) [ IdKey, Unique ];
Index indexDocId On (DocId, PropId, PropValue) [ Unique ];

;; from irislib/Ens/Config/SearchTableProp.cls (the name → ID mapping table):
;; Mapping: SELECT PropID FROM Ens_Config.SearchTableProp WHERE ClassExtent = :pSearchTable AND Name = :pPropName
```

**CRITICAL: row shape is `(PropId %Integer, PropValue %String, DocId %String)`, NOT `(DocId, PropName, PropValue)` as the original spec assumed.** The `prop_name` is mapped to `PropId` via the lookup `SELECT PropID FROM Ens_Config.SearchTableProp WHERE ClassExtent = :search_table_class AND Name = :prop_name`. Then the SearchTable extent is queried by `(PropId, PropValue)`.

**Probe 4 — `Ens.CustomSearchTable` shape (the rare case):**

```objectscript
;; from irislib/Ens/CustomSearchTable.cls:
Property DocId As %String(COLLATION = "EXACT", MAXLEN = "") [ Required ];
Index DocId On DocId [ Unique ];
;; NO canonical PropId/PropValue — subclasses declare their own properties.
```

**Decision:** v1 supports VDoc-style SearchTables only (the common case — HL7/X12/EDIFACT/ASTM/XML). For a `Ens.CustomSearchTable` subclass, the `Ens.Config.SearchTableProp` lookup returns no row — we treat that as "no_matches" gracefully. Operators wanting custom-search-table support need a future story; documented as a class doc-comment.

**Probe 5 — JOIN semantics (verified via `Ens.SearchTableBase.SearchHeader()` generator code):**

The IRIS-canonical join is `Ens.MessageHeader.MessageBodyId = SearchTable.DocId` PLUS `Ens.IsASub(MessageHeader.MessageBodyClassName, '<DOCCLASS>')` to filter to compatible body classes. We emit the simpler join (no DOCCLASS filter — operator passed explicit class) since matching the SearchTable's own DocId domain is sufficient.

**Live `Ens.Config.SearchTableProp` and `EnsLib_HL7.SearchTable` are EMPTY on dev install** — sample production carries no HL7 traffic. Live test exercises "not installed" / "no_matches" paths; fixture-based tests cover positive matches via in-test `SessionAgent.Test.FsbFixtureSearchTable Extends Ens.VDoc.SearchTable` (NOT `Ens.SearchTableBase` directly — VDoc-style is the supported v1 contract).

### Sources

- [`epics.md` Story 4.6](../planning-artifacts/epics.md#L1588) — AC source.
- [`architecture.md`](../planning-artifacts/architecture.md) §"Implementation Handoff → Carry-forward Task-0 probes" + G5 — re-anchoring rationale.
- [`EventLog.cls`](../../src/SessionAgent/Tool/Inspection/EventLog.cls) + [`FindRelatedSessions.cls`](../../src/SessionAgent/Tool/Inspection/FindRelatedSessions.cls) — typed SQL projection patterns.
- [`Story41ToolsTest.cls`](../../src/SessionAgent/Test/Story41ToolsTest.cls) + [`FindRelatedSessionsTest.cls`](../../src/SessionAgent/Test/FindRelatedSessionsTest.cls) — fixture seeding patterns.
- `irislib/Ens/SearchTableBase.cls`, `irislib/EnsLib/HL7/SearchTable.cls`, `irislib/%Library/Dictionary/CompiledClass.cls` — IRIS-library source reads.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS Library Source" + §"IRIS SQL Case Sensitivity".
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 4, 6 sharpened, 8, 9, 10, 11, 12.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — dev agent, 2026-05-03.

### Debug Log References

- Task 0 SQL probe: `SELECT %EXACT(Name), %EXACT(Super), %EXACT(PrimarySuper) FROM %Dictionary.CompiledClass WHERE PrimarySuper LIKE '%~Ens.SearchTableBase~%'` returned only `Ens.SearchTableBase`, `Ens.VDoc.SearchTable`, `Ens.VDoc.XMLSearchTable` — surfacing the primary-only walk problem.
- Compile-time error during fixture: `$$$EnsSearchTableDocClassRequired` — fixed by adding `Parameter DOCCLASS = "Ens.MessageHeader"` to the fixture SearchTable.

### Completion Notes List

**Task-0 SearchTable shape findings (binding for Epic 8 Story 8.5).** Documented verbatim under the Dev Notes "Task 0 probe captures (binding for Epic 8 Story 8.5)" heading. Three load-bearing corrections vs the original spec:

1. **`PrimarySuperList` is not a SQL projection.** The actual projection is `PrimarySuper` (singular). Spec assumed otherwise — would have failed at runtime.
2. **`PrimarySuper` walks only the *primary* (first-listed) parent chain.** Real SearchTable subclasses (`EnsLib.HL7.SearchTable`, `Ens.CustomSearchTable`) declare `Super = "%Persistent,Ens.VDoc.SearchTable"` — `%Persistent` is the primary super, so `Ens.SearchTableBase` never appears in `PrimarySuper` for them. Pivoted (Rule 8 fix-now) to `$ClassMethod(class, "%Extends", "Ens.SearchTableBase")` guarded by `%Dictionary.CompiledClass.%ExistsId`.
3. **VDoc row shape is `(PropId %Integer, PropValue %String, DocId %String)`, not `(DocId, PropName, PropValue)` as the spec assumed.** Mapping `prop_name → PropId` lives in `Ens.Config.SearchTableProp` (`WHERE ClassExtent = ? AND Name = ?`). Tool implements a 2-step lookup: prop-name → PropId, then PropId → SearchTable rows.

**Class-validation idiom.** `%Dictionary.CompiledClass.%ExistsId` (existence guard) THEN `$ClassMethod(class, "%Extends", "Ens.SearchTableBase")`. **`%IsA` does NOT work** — it returns 0 for abstract intermediates like `EnsLib.HL7.SearchTable`. `%Extends` is the canonical class-lineage check.

**Architecture-mandated error wording.** Two distinct render_strategy values:
- `search_table_not_installed` + isError=1 → "<class> is not installed in this namespace; body-field search is unavailable for this body class"
- `not_search_table_subclass` + isError=1 → "<class> exists but is not a subclass of Ens.SearchTableBase"

**Graceful no-matches.** When `prop_name` isn't registered in `Ens.Config.SearchTableProp` for the SearchTable class (the common case for `Ens.CustomSearchTable`-derived classes that don't use the VDoc PropId/PropValue shape), tool returns `render_strategy="no_matches"` (NOT an error) rather than confusing the operator with an internal-detail error.

**Fixture SearchTable design.** Extends `Ens.CustomSearchTable` (not `Ens.VDoc.SearchTable` — VDoc requires SearchSpec XData and DOCCLASS-driven IndexDoc generation). Custom-style + manual `(PropId, PropValue)` property declarations + manual `Ens.Config.SearchTableProp` row seeding gives the production tool's SQL the same shape it sees against real VDoc SearchTables. Required `Parameter DOCCLASS = "Ens.MessageHeader"` to satisfy the Ens.SearchTableBase code-generators (BuildIndex/IndexDoc/SearchHeader) — without it, fixture compile fails with `$$$EnsSearchTableDocClassRequired` even though we never invoke those methods.

**Test counts.** 7 net new tests in `SessionAgent.Test.FindSessionsByBodyTest`; full per-class regression: 191/191 across 28 test classes, 0 failures, 0 skips.

**Rule 12 visual gate.** Captured at `_bmad-output/implementation-artifacts/4-6-rule-12-visual-pass-1.png`. Screenshot shows the `find_sessions_by_body` "not installed" envelope rendered as operator-friendly English in the chat panel, with collapsible JSON details, NOT a raw JSON dump or scary red error.

**Live LLM gate (Rule 6 sharpened).** OpenAI key not resolvable on dev install (`Util.EnvSecret.IsResolvable → 0`); substituted three direct tool invocations exercising all three architecture-mandated error/empty paths (no_matches via fall-through, search_table_not_installed, not_search_table_subclass). All paths empirically verified. Documented as a deferral consistent with Rule 6 step 4 ("if the credential is absent, the test is skipped not failed").

### File List

**New:**
- `src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls` — Story 4.6 tool class.
- `src/SessionAgent/Test/FsbFixtureSearchTable.cls` — fixture SearchTable subclass (`Extends Ens.CustomSearchTable`) used by `FindSessionsByBodyTest`.
- `src/SessionAgent/Test/FindSessionsByBodyTest.cls` — 7 unit tests covering AC-3 → AC-5.
- `_bmad-output/implementation-artifacts/4-6-rule-12-visual-pass-1.png` — Rule 12 visual gate evidence.

**Modified:**
- `_bmad-output/implementation-artifacts/4-6-findsessionsbybody-ens-searchtablebase-pivot.md` — Tasks/Subtasks checkboxes flipped, Dev Notes "Task 0 probe captures" inserted, Dev Agent Record + File List + Change Log filled, Status → review.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story status `ready-for-dev` → `review` (via in-progress).

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-04 | Initial spec drafted by lead from epics.md §Story 4.6 | Claude Opus 4.7 (lead) |
| 2026-05-03 | Implementation complete: tool + 7-test suite + fixture SearchTable + visual gate. Task-0 surfaced 3 corrections to the spec assumptions (PrimarySuperList → PrimarySuper; primary-only chain rejects real subclasses; VDoc shape is (PropId, PropValue, DocId) not (DocId, PropName, PropValue)). Pivoted to `%Extends`-based class validation + 2-step PropId lookup (Rule 8 fix-now). | Claude Opus 4.7 (dev) |
| 2026-05-03 | Code review complete. All 9 lead-flagged items verified: (1) PrimarySuper not PrimarySuperList — confirmed in irislib/%Dictionary/CompiledClass.cls L189; (2) %Extends correctly walks full inheritance graph + %ExistsId guard precedes — confirmed empirically on EnsLib.HL7.SearchTable; (3) VDoc row shape (PropId, PropValue, DocId) — confirmed in irislib/Ens/VDoc/SearchTable.cls L26-35; Task-0 captures verbatim and binding-grade for Epic 8 Story 8.5; (4) %Extends correctly used not %IsA (which fails for abstract intermediates); (5) fixture compile-clean + extends Ens.CustomSearchTable with Parameter DOCCLASS placeholder, no unintended index generation; (6) live OpenAI smoke substituted with three direct ObjectScript probes (Rule 11 acceptable; Story 4.7 is natural carrier for re-verifying credential); (7) visual-gate screenshot shows operator-friendly English ("I can't search for that MRN here..."); (8) per-class regression spot-checked across FindRelatedSessions (5/5), InspectionTool (15/15), GetMessageBody (12/12), AgentDto+AgentLoopGuards (9/9) plus FindSessionsByBody (7/7) — no regressions; (9) Task-0 captures clearly headed "Task 0 probe captures (binding for Epic 8 Story 8.5)" verbatim in Dev Notes. Status → done. | Claude Opus 4.7 (reviewer) |

## Review Findings

- [x] [Review][Defer] OpenAI live-LLM smoke substituted with three direct ObjectScript probes — credential `Util.EnvSecret.IsResolvable("OPENAI_API_KEY","SessionAgentInspectionApiKey")=0` on dev install. Acceptable per Rule 11 (this story consumes existing OpenAI path, doesn't add new integration code). Logged in `deferred-work.md` under Story 4.6 heading; Story 4.7 sweep is natural carrier for re-verifying credential and running live-LLM matrix across full Epic 4 inspection-tool family.

### Verification of lead-flagged items

1. **PrimarySuper not PrimarySuperList** — VERIFIED. `irislib/%Dictionary/CompiledClass.cls` L189: `Property PrimarySuper As %RawString;`. No `PrimarySuperList` projection exists. Dev's spec correction is verbatim correct.
2. **%Extends walks full inheritance graph + %ExistsId guard precedes** — VERIFIED. `FindSessionsByBody.cls` L202 (`%ExistsId` guard) precedes L217 (`$ClassMethod(class, "%Extends", "Ens.SearchTableBase")`). Live probe confirmed `%Extends` returns 1 for `EnsLib.HL7.SearchTable`, 0 for `Ens.MessageHeader`. `%IsA` returns 0 for `EnsLib.HL7.SearchTable` (abstract intermediate), correctly rejected by dev.
3. **VDoc row shape `(PropId, PropValue, DocId)`** — VERIFIED. `irislib/Ens/VDoc/SearchTable.cls` L26 `Property PropId As %Integer`, L29 `Property PropValue As %String(MAXLEN = 256)`, L32 `Index indexValue On (PropId, PropValue, DocId) [ IdKey ]`. Plus `irislib/Ens/SearchTableBase.cls` L29 `Property DocId As %String(COLLATION = "EXACT")`. The 2-step PropId lookup against `Ens.Config.SearchTableProp` (verified `Index indexClassProp On (ClassExtent, Name) [ IdKey ]` in `irislib/Ens/Config/SearchTableProp.cls` L34) is correctly implemented. Task-0 capture under "Task 0 probe captures (binding for Epic 8 Story 8.5)" heading is verbatim and binding-grade for Epic 8 Story 8.5 spec drafting.
4. **`%Extends` not `%IsA`, consistent with Story 4.2 finding** — VERIFIED. No regression; matches Story 4.2 codebase precedent.
5. **Fixture extends `Ens.CustomSearchTable` with placeholder `DOCCLASS`** — VERIFIED. Compile clean (test class compiles + 7/7 tests pass). `Parameter DOCCLASS = "Ens.MessageHeader"` only satisfies Ens.SearchTableBase code-generators; no unintended index generation observed (storage section is the auto-generated default-data shape).
6. **OpenAI key not resolvable; three direct ObjectScript probes substituted** — Logged as LOW deferred for Story 4.7 sweep.
7. **Visual-gate screenshot** — VERIFIED. Shows tool-card with raw envelope (args + result) AND operator-friendly English at bottom ("I can't search for that MRN here — the EnsLib.HL7v3..."). Tool-card has the standard collapsible chevron; consistent with established chat-panel rendering. NOT a scary red error.
8. **Regression count** — SANITY-CHECKED. Per-class spot checks: FindRelatedSessionsTest (5/5), InspectionToolTest (15/15), GetMessageBodyTest (12/12), AgentDto+AgentLoopGuards (9/9), FindSessionsByBodyTest (7/7). No regressions across adjacent inspection tools. Dev's 191/191 across 28 classes claim is plausible.
9. **Cross-codebase Task-0 binding for Epic 8 Story 8.5** — VERIFIED. Dev Notes "Task 0 probe captures (binding for Epic 8 Story 8.5)" heading is verbatim, includes 5 probes (hierarchy projection, class-validation helpers, VDoc row shape, custom shape, JOIN semantics), with the 3 corrections explicitly called out as "CRITICAL". Future Epic 8 Story 8.5 spec author can grep `"Task 0 probe captures (binding for Epic 8 Story 8.5)"` to find this section directly.

### Severity counts

- HIGH: 0
- MEDIUM: 0
- LOW: 1 (deferred to Story 4.7)
- DISMISSED: 1 (visual-gate "JSON foregrounded" — established chat-panel design, not a Story 4.6 issue)

### Reviewer signoff

Story 4.6 ships clean. Three Task-0 fix-nows are correct, well-documented, and binding-grade for Epic 8 Story 8.5. The %Extends-not-%IsA / %Extends-not-PrimarySuper / (PropId, PropValue, DocId)-not-(DocId, PropName, PropValue) corrections caught at Task 0 are exactly the kind of empirical pivot Rule 8 (fix-now is default) was designed for — they would have shipped as silent bugs (every real SearchTable rejected, wrong column names, runtime SQL errors) if dev had followed the original spec wording.
