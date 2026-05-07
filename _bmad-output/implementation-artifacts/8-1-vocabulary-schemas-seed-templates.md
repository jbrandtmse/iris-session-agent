# Story 8.1: Vocabulary Schemas + Seed Templates

Status: review

## Story

As a developer preparing the Search Agent foundation,
I want three vocabulary `%Persistent` classes (`SessionAgent.Search.UserVocabulary`, `SessionAgent.Search.SeedVocabulary`, `SessionAgent.Search.NamespaceVocabulary`) plus ~10 HL7-idiom seed templates seeded by `Installer.Install`,
so that the Search Agent can ship with operator-immediately-useful seed vocabulary on first install per FR23 / AR19, and Stories 8.2–8.7 have a stable persistence substrate to build on.

The `EnsLib.HL7.SearchTable` row-shape Task-0 probe needed by Story 8.5 was already captured by Epic 4 Story 4.6 (first cross-codebase consumer of the SearchTable shape per the epic plan). This story does NOT re-probe — Story 8.5 will reuse the captured shape.

## Acceptance Criteria

Verbatim from [`epics.md` §"Story 8.1"](../planning-artifacts/epics.md):

**AC-1 — `SessionAgent.Search.UserVocabulary` schema.** The `%Persistent` class declares properties `PortalUser As %String`, `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable per saved memory `project_search_agent_body_search_refinement.md` — supports per-class vocabulary refinement), `SuccessCount As %Integer`, `FailureCount As %Integer`, `Confidence As %Numeric` (default `0`; the recursion-safe `%OnAfterSave` trigger that recomputes Confidence from Success/Failure counts is added in Epic 9 Story 9.2 — until then, Confidence is stored as `0` and read directly), `LastUsed As %String` (ISO-8601 UTC), `CreatedAt As %String` (ISO-8601 UTC), `CreatedVia As %String` (one of `clickthrough` / `explicit` / `extracted` / `seed`). The class declares `Index UserAliasIdx On (PortalUser, Alias) [Unique]`. Storage section is auto-generated per project rule "Storage Sections" (NEVER hand-edit).

**AC-2 — `SessionAgent.Search.SeedVocabulary` schema.** The `%Persistent` class declares properties `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable), `Description As %String(MAXLEN=2048)`, `Aliases As %String(MAXLEN=2048)` (synonyms, comma-separated), `Examples As %String(MAXLEN=2048)` (example queries that match this alias). The class declares `Index AliasIdx On Alias`. Storage auto-generated. The class provides `ClassMethod Seed() As %Status` that idempotently inserts ~10 HL7-idiom seed templates: `admit ↔ A01/A04 events`, `discharge ↔ A03 events`, `lab order ↔ ORM messages`, `lab result ↔ ORU messages`, `radiology order ↔ ORM with OBR-4 imaging codes`, `MRN search ↔ PID-3`, `failed message ↔ Status='Error'`, `acknowledgment ↔ ACK messages`, `transfer ↔ A02 events`, `cancellation ↔ A11/A13 events`. Idempotency: re-running `Seed()` does NOT duplicate templates — the implementation must check by `Alias` + `MessageBodyClass` composite key before insert (NFR-R5).

**AC-3 — `SessionAgent.Search.NamespaceVocabulary` schema (schema-only per AR19).** The `%Persistent` class declares properties `Alias As %String(MAXLEN=512)`, `MessageBodyClass As %String(MAXLEN=128)` (nullable), `Aliases As %String(MAXLEN=2048)`, `BaselineConfidence As %Numeric`, `BasedOnUsers As %Integer` (count of distinct users contributing to this baseline). Storage auto-generated; the class compiles cleanly but has NO insert/update logic in v1 — operators see an empty table. Population logic is deferred to v1.5 / Vision tier (out of v1 scope per the epics plan).

**AC-4 — `Installer.Install` extension.** Extend `SessionAgent.Installer.Install` (Story 1.5) so the Installer invokes `##class(SessionAgent.Search.SeedVocabulary).Seed()` AFTER the RBAC + audit setup (i.e., after `Security.ReadOnlyRole.Install()` at line ~105, before or after the existing `SeedDefaultAgentConfigs()` block at line ~116 — co-locate with the other defensive-seed helpers for code clarity). The seeding call propagates `%Status` per project rule "Write Status Checking" (`If $$$ISERR(tSC)` handle), and the Installer logs: `<seed_count> seed vocabulary templates ensured` (where `<seed_count>` is the integer count of post-Seed `SeedVocabulary` rows — confirms idempotency on re-run). On a fresh install the count is the full template list (~10); on a re-install the count remains the same because re-runs do not duplicate (per AC-2 idempotency clause).

**AC-5 — Operator-observable surface enumeration (per Story 8.0 AC-1 codification).** Every shipped artifact in this story has a populated descriptive surface — verified at story-spec time and at story-completion time:

- **Class doc-comments**: each of `UserVocabulary`, `SeedVocabulary`, `NamespaceVocabulary` ships with a class-level `///` doc-comment (HTML/DocBook markup per project rule "Comments") describing the class's purpose, the v1 vs v1.5 boundary for `NamespaceVocabulary`, the `MessageBodyClass` nullable per-class refinement design, and which Story+Epic ships the recursion-safe `%OnAfterSave` trigger (Epic 9 Story 9.2).
- **Property doc-comments**: every property MUST have a one-line `///` description (operator-readable) — these surface as column descriptions in the IRIS SQL Catalog Mgmt-Portal view.
- **`SeedVocabulary.Seed()` doc-comment**: documents idempotency semantics + the operator-visible Installer log line.
- **NO operator-observable Mgmt-Portal artifacts beyond the SQL Catalog rows** — no `%SYS.Task` entry, no Web Application, no audit-event triple are added in this story; the surface enumeration is therefore limited to class+property doc-comments.

### Verification gate

**AC-6 — Compile + per-class unit-test sweep.**
- All three `%Persistent` classes compile cleanly via `iris_doc_compile`.
- New unit-test class `SessionAgent.Test.SeedVocabularyTest` verifies: `Seed()` first call inserts ~10 templates; `Seed()` second call inserts 0 additional templates (idempotency); template count matches the documented HL7 seed list; `UserAliasIdx` enforces uniqueness on `(PortalUser, Alias)` (insert two rows with same composite key → second `%Save` returns `$$$ERR_*`).
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class form per [`object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround"](../../.claude/rules/object-script-testing.md)).
- **The "N/N pass" claim that gates this story MUST come from the Story 8.0 AC-5-tweaked SQL probe form** per Rule 6 step 3.
- **Expected baseline: ≥ 291 (Epic 7 close baseline) + new `SeedVocabularyTest` methods** (~3-5 new methods); final count ~295–296 / all PASS / 0 FAIL.

**AC-7 — Live install verification (Rule 6).** Re-run `Installer.Install("")` against `HSCUSTOM`; capture verbatim install-log output showing `<seed_count> seed vocabulary templates ensured` line; confirm `SELECT COUNT(*) FROM SessionAgent_Search.SeedVocabulary` returns the documented seed count. Re-run a second time; confirm the count is unchanged (idempotency live-verified). Capture both probes verbatim in Completion Notes per Rule 2 sharpened evidence shape.

## Tasks / Subtasks

- [x] **Task 1 — `SessionAgent.Search.UserVocabulary.cls` (AC: #1, #5)**
  - [x] Create class with class-level doc-comment + 8 properties (`PortalUser`, `Alias`, `MessageBodyClass`, `SuccessCount`, `FailureCount`, `Confidence`, `LastUsed`, `CreatedAt`, `CreatedVia`) per AC-1.
  - [x] Each property gets a one-line `///` doc-comment (operator-readable).
  - [x] `Index UserAliasIdx On (PortalUser, Alias) [Unique]`.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — `SessionAgent.Search.SeedVocabulary.cls` (AC: #2, #5)**
  - [x] Create class with class-level doc-comment + 5 properties (`Alias`, `MessageBodyClass`, `Description`, `Aliases`, `Examples`).
  - [x] Each property gets a one-line `///` doc-comment.
  - [x] `Index AliasIdx On Alias`.
  - [x] `ClassMethod Seed() As %Status` — idempotently insert the ~10 HL7-idiom templates listed in AC-2. Implementation pattern: composite-key SQL probe via `InsertIfMissing` helper that branches on `MessageBodyClass IS NULL` for empty values (IRIS stores empty %String as SQL NULL, so a simple `= ''` predicate misses; the branch closes that gap). Method's class-level doc-comment documents idempotency semantics.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 3 — `SessionAgent.Search.NamespaceVocabulary.cls` (AC: #3, #5)**
  - [x] Create class with class-level doc-comment that explicitly documents the v1-vs-v1.5 schema-only boundary + 5 properties (`Alias`, `MessageBodyClass`, `Aliases`, `BaselineConfidence`, `BasedOnUsers`).
  - [x] No `Seed()` method, no `%Insert` logic.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 4 — Installer integration (AC: #4)**
  - [x] Edit `src/SessionAgent/Installer.cls` `Install()` method to invoke `SessionAgent.Search.SeedVocabulary.Seed()` after `Security.ReadOnlyRole.Install()` and `SeedDefaultAgentConfigs()` (step 5 in the orchestrator, just before `PrintOperatorReminders`). Status propagated per "Write Status Checking".
  - [x] After `Seed()` returns OK, `LogPostSeedVocabularyCount()` helper queries post-state row count via SQL and emits `[iris-session-agent] <count> seed vocabulary templates ensured`.
  - [x] Compile `Installer.cls` via `iris_doc_compile`.

- [x] **Task 5 — `SessionAgent.Test.SeedVocabularyTest.cls` (AC: #6)**
  - [x] Create test class extending `%UnitTest.TestCase` with proper `%OnNew(initvalue)` per [`object-script-testing.md`](../../.claude/rules/object-script-testing.md).
  - [x] **Avoid the `Property Test*` shadow trap** — no state-tracking property whose name begins with `Test`. Used `Parameter EXPECTEDSEEDCOUNT` instead of property-based state.
  - [x] Test methods: `TestSeedFirstCallInsertsTemplates` (asserts count == 10 after 1st call), `TestSeedSecondCallIdempotent` (count unchanged after 2nd call), `TestSeedTemplateCountMatchesSpec` (asserts count == documented HL7 list size), `TestUserAliasIdxUniqueConstraint` (insert two rows with same `(PortalUser, Alias)` → second `%Save` returns error), plus bonus `TestSeedDescriptionsAreAscii` (asserts ASCII `->` connector + no UTF-8 Unicode arrow bytes — Rule 12 mojibake guard).
  - [x] `OnBeforeOneTest` / `OnAfterOneTest` clean test data per project pattern; `OnAfterAllTests` re-seeds so install state is restored.
  - [x] Compile + run — 5/5 PASS via SQL ground truth.

- [x] **Task 6 — Verification battery (AC: #6, #7)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class).
  - [x] SQL ground-truth probe per Story 8.0 AC-5 tweaked form (modified to use `MAX($PIECE(ID, '||', 1)+0)` to handle the lexicographic-vs-numeric MAX(ID) collation issue + filter to method-bearing runs only). **Total=296 / Passed=296 / Failed=0**.
  - [x] Re-run `Installer.Install("")` twice; both runs show identical log line `[iris-session-agent] 10 seed vocabulary templates ensured`. `SELECT COUNT(*) FROM SessionAgent_Search.SeedVocabulary` returns 10 on both runs (count unchanged = idempotency live-verified).

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~220 lines. Within the cap.

### Rule 3 — typed MCPs first

- Class compilation: `mcp__iris-dev-mcp__iris_doc_compile` (NOT `iris_execute_command` for compile).
- SQL probes: `mcp__iris-dev-mcp__iris_sql_execute` for `COUNT(*)` and ground-truth queries.
- Test execution: `mcp__iris-dev-mcp__iris_execute_tests` (level=class form per truncation workaround).
- Auto-sync: `.cls` files in `src/SessionAgent/` push to IRIS on save (per `.claude/rules/iris-objectscript-basics.md` §"VSCode Auto-Sync Workflow"). Do NOT call `iris_doc_load`; DO call `iris_doc_compile` to surface compile errors.

### Rule 4 — stale-reference scan

Before submitting, run `grep -rn "Search.UserVocabulary\|Search.SeedVocabulary\|Search.NamespaceVocabulary\|SessionAgent_Search\." .` to confirm any pre-existing references match the new class names. None expected (no Search.* classes shipped to date).

### Rule 8 — fix-now is the default

If implementation surfaces any predicted-bug shape (e.g., `Index UserAliasIdx` doesn't enforce uniqueness on insert at the IRIS storage layer; `Seed()` re-run inserts duplicates because the existence probe uses the wrong column), fix in this story. Do NOT defer.

### Rule 10 — no external defaults set in this story

The HL7 seed list (`A01/A04`, `A02`, `A03`, etc.) is a domain-stable taxonomy (HL7 v2.x message types are stable since the 1990s), NOT a versioned external default. Rule 10 (Perplexity-mandatory verification line) does NOT apply. The seed list is internal-domain content, not an external library or model name.

### Rule 12 — content-correctness only (no UI surface)

This story ships `%Persistent` classes only — no UI rendering, no operator-rendered prose. Rule 12 (rendered-text readability) is satisfied by content-correctness on the class doc-comments + property descriptions (mojibake check on `↔` characters in Description fields if Unicode sentinel chosen, OR ASCII alternative `->` if mojibake risk). Recommendation: **use ASCII `->` in `Description` field text** to avoid any UTF-8 round-trip risk through `%String` storage.

### `$Char(0)` sentinel — read-site invariant

Per `.claude/rules/iris-objectscript-basics.md` §"`$Char(0)` sentinel — grep target", any `%String` property write path that includes SQL UPDATE downstream needs read-site normalization. The vocabulary classes' write paths are:
- `Seed()` uses `%New()` + `%Save()` (OREF-graph write, not SQL UPDATE) → no sentinel risk.
- `UserVocabulary.RecordSuccess` (Epic 9 Story 9.2) will use direct-SQL UPDATE for `Confidence` recomputation → that story will need read-site normalization on the relevant fields.

This story (8.1) ships only the schema + Seed; no SQL UPDATE write path is introduced, so no `$Char(0)` read-site normalization is needed yet. Story 9.2 will add it when the recursion-safe `%OnAfterSave` trigger ships.

### `%EXACT()` discipline

Any SQL probe in this story (e.g., the post-Seed count check, the duplicate-detection in `Seed()`) MUST use `%EXACT()` discipline per project rule. Example: `SELECT COUNT(*) FROM SessionAgent_Search.SeedVocabulary WHERE %EXACT(Alias) = ?`.

### `Storage Sections` — never hand-edit

All three classes get auto-generated Storage sections by the IRIS class compiler. Per project rule, NEVER hand-edit Storage sections — the compiler regenerates them and any hand-edits would be lost on next compile.

### Empirical battery — minimal because backend-only schemas

This story's diff is 4 new `.cls` files + 1 `Installer.cls` edit. Tier 2 verification (per-class regression sweep + SQL ground-truth probe + live-install idempotency probe per AC-7) is sufficient. No live integration smoke test (Rule 11 — no external API), no Rule 12 layout-correctness check (no UI surface).

### Sources

- [`epics.md` §"Story 8.1"](../planning-artifacts/epics.md) — verbatim AC source.
- [`architecture.md` §"AR19 Vocabulary Persistence"](../planning-artifacts/architecture.md) — schema design + v1 vs v1.5 boundary on `NamespaceVocabulary`.
- [`prd.md` §"FR23 — Seed vocabulary"](../planning-artifacts/prd.md) — operator-immediately-useful seed-vocabulary requirement.
- Saved memory `project_search_agent_body_search_refinement.md` — `MessageBodyClass` nullable per-class vocabulary refinement.
- [`src/SessionAgent/Installer.cls`](../../src/SessionAgent/Installer.cls) `Install()` ~line 105 — insertion point for AC-4.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — Storage sections, comments, naming conventions.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — `%OnNew(initvalue)`, `Property Test*` shadow trap, MCP truncation workaround, SQL ground-truth probe.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

- **Empirical bug-fix (composite-key probe)**: First implementation of `SeedVocabulary.InsertIfMissing` used `WHERE %EXACT(MessageBodyClass) = ?` with empty-string parameter for the cross-class fallback templates. After the first `Seed()` call inserted 10 rows, a second `Seed()` call inserted another 10 (idempotency broken — total 20). Empirical investigation via `SELECT TOP 5 ID FROM SessionAgent_Search.SeedVocabulary WHERE %EXACT(Alias) = 'admit' AND MessageBodyClass IS NULL` confirmed that IRIS stores empty `%String` values as SQL NULL — the predicate `MessageBodyClass = ''` returns zero rows even when OREF was %Saved with empty string. Fix: branch the SQL probe on the parameter shape — empty parameter → `MessageBodyClass IS NULL`, non-empty → `%EXACT(MessageBodyClass) = ?`. Re-tested: 10 rows after first call, 10 rows after second call. Idempotency verified.
- **MCP envelope truncation**: `mcp__iris-dev-mcp__iris_execute_tests` returned 3/5 SeedVocabularyTest methods on first invocation (truncated tail). SQL ground-truth probe against `%UnitTest_Result.TestMethod` showed all 5/5 recorded with Status=1. Aligns with the documented MCP truncation workaround per `.claude/rules/object-script-testing.md`.
- **MAX(ID) collation issue in ground-truth probe**: Story 8.0's canonical SQL probe form uses `MAX(ID)` (lexicographic). On runs with mixed numeric prefixes (run 9, 99, 100, 1000, 1044, etc.) the lex MAX picks "99" before "1044". Fixed by switching to `MAX($PIECE(ID, '||', 1)+0)` (numeric coerce of the run-number prefix). Additionally, filtered to TestCase rows that have at least one TestMethod child (some runs created TestCase rows but no method rows — likely from interrupted MCP runs).

### Completion Notes List

#### Verbatim per-class regression sweep results

Per-class sweep run via `mcp__iris-dev-mcp__iris_execute_tests` level=class on each of the 37 `SessionAgent.Test.*` `%UnitTest.TestCase`-extending classes during this dev session. Each run recorded into `^UnitTest.Result`.

#### Verbatim SQL ground-truth probe (Rule 6 step 3 / Story 8.0 AC-5 form)

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
JOIN ( SELECT %EXACT(tc2.Name) AS Cls, MAX($PIECE(tc2.ID, '||', 1)+0) AS MaxRun
       FROM %UnitTest_Result.TestCase tc2
       JOIN %UnitTest_Result.TestMethod tm2 ON tm2.TestCase = tc2.ID
       WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
       GROUP BY %EXACT(tc2.Name) ) latest
  ON %EXACT(tc.Name) = latest.Cls
 AND ($PIECE(tc.ID, '||', 1)+0) = latest.MaxRun
```

**Result: Total=296 / Passed=296 / Failed=0.** (Epic 7 baseline 291 + 5 new SeedVocabularyTest methods = 296.)

#### Per-class breakdown (verbatim from SQL)

| Class | Methods | Passed | Failed |
|---|---|---|---|
| AgentConfigTest | 16 | 16 | 0 |
| AgentDtoTest | 7 | 7 | 0 |
| AgentLoopGuardsTest | 9 | 9 | 0 |
| AgentLoopTest | 3 | 3 | 0 |
| AnthropicProviderTest | 11 | 11 | 0 |
| AuditEmitTest | 3 | 3 | 0 |
| AuditTest | 8 | 8 | 0 |
| BusinessProcessIntrospectionTest | 10 | 10 | 0 |
| ChatHistoryTest | 10 | 10 | 0 |
| ChatPanelDrawHelperTest | 4 | 4 | 0 |
| ChatPanelJsTest | 18 | 18 | 0 |
| ConfigAgentTest | 10 | 10 | 0 |
| EnvSecretTest | 8 | 8 | 0 |
| FindRelatedSessionsTest | 5 | 5 | 0 |
| FindSessionsByBodyTest | 7 | 7 | 0 |
| GeminiProviderTest | 11 | 11 | 0 |
| GetMessageBodyTest | 12 | 12 | 0 |
| GetMessageDetailTest | 6 | 6 | 0 |
| InspectionSuiteVerificationTest | 13 | 13 | 0 |
| InspectionToolTest | 15 | 15 | 0 |
| JsonTest | 9 | 9 | 0 |
| MessageAdapterTest | 11 | 11 | 0 |
| MultiNamespaceInstallTest | 6 | 6 | 0 |
| OpenAICompatProviderTest | 11 | 11 | 0 |
| OpenAIProviderTest | 8 | 8 | 0 |
| PurgeTaskTest | 3 | 3 | 0 |
| ReadOnlyRoleTest | 6 | 6 | 0 |
| RetryWithBackoffTest | 9 | 9 | 0 |
| SampleProductionTest | 3 | 3 | 0 |
| **SeedVocabularyTest** | **5** | **5** | **0** |
| SmokeTest | 1 | 1 | 0 |
| Story41ToolsTest | 12 | 12 | 0 |
| ToolBaseTest | 3 | 3 | 0 |
| ToolCallRoundtripIntegrationTest | 4 | 4 | 0 |
| ToolDefAdapterTest | 3 | 3 | 0 |
| ToolRegistryTest | 8 | 8 | 0 |
| VisualTraceTest | 8 | 8 | 0 |
| **TOTAL** | **296** | **296** | **0** |

#### AC-7 — Verbatim install-log output (Run 1)

Invocation: `Set tSC = ##class(SessionAgent.Installer).Install("")` — namespace `HSCUSTOM`.

```
[iris-session-agent] Task SessionAgent.PurgeOrphanedChatHistory already scheduled (ID=1009); skipped
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] session-inspection: row already present; skipping
[iris-session-agent] message-search: row already present; skipping
[iris-session-agent] 10 seed vocabulary templates ensured
=== iris-session-agent install reminders ===
Bookmark URLs (HealthShare):
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
Bookmark URLs (plain IRIS):
  /csp/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
See README "Operator Prerequisites" for one-time setup (Web Gateway timeout 60->300, RBAC role assignment, API key supply).
===========================================
---STATUS---

```

(Empty status line = `$$$OK` returned.) Post-Seed count probe:

```sql
SELECT COUNT(*) AS RowCnt FROM SessionAgent_Search.SeedVocabulary
-- Result: 10
```

#### AC-7 — Verbatim install-log output (Run 2 — idempotency)

Same invocation. Verbatim output identical to Run 1 (operator-visible state unchanged):

```
[iris-session-agent] Task SessionAgent.PurgeOrphanedChatHistory already scheduled (ID=1009); skipped
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] session-inspection: row already present; skipping
[iris-session-agent] message-search: row already present; skipping
[iris-session-agent] 10 seed vocabulary templates ensured
=== iris-session-agent install reminders ===
... (identical reminders block) ...
---STATUS---

```

Post-2nd-Seed count probe:

```sql
SELECT COUNT(*) AS RowCnt FROM SessionAgent_Search.SeedVocabulary
-- Result: 10
```

**Idempotency live-verified — count unchanged on second invocation, log line identical, no errors.**

#### Design decisions

- **ASCII `->` vs Unicode `↔` in Description text**: chose ASCII `->` per Rule 12 / spec Dev Notes recommendation. The Description field contents (`admit -> A01/A04 events`, etc.) survive `%String` storage round-trips with no mojibake risk. Test method `TestSeedDescriptionsAreAscii` empirically asserts the ASCII connector is present and no UTF-8 Unicode arrow bytes (`$Char(226,134,148)`) are present in the stored Description field.
- **Composite-key probe shape**: `(Alias, MessageBodyClass)` per AC-2. The empty-MessageBodyClass case requires `IS NULL` (not `= ''`) because IRIS stores empty `%String` values as SQL NULL. The `InsertIfMissing` helper branches on parameter shape to construct the right SQL; both branches use `%EXACT(Alias)` for case-sensitive matching per project rule "IRIS SQL Case Sensitivity".
- **Insertion point in `Installer.Install`**: placed AFTER `SeedDefaultAgentConfigs()` (at the top of step 5 in the orchestrator), BEFORE `PrintOperatorReminders()`. Co-located with other defensive-seed helpers per the spec's Task 4 instruction. Status is propagated via `If $$$ISERR(tSC) Quit` per project rule "Write Status Checking".
- **`LogPostSeedVocabularyCount` helper**: separate private classmethod handles the post-Seed COUNT(*) query and log emission. Defensive — if the count query fails, logs a diagnostic but does not propagate as an error so the overall install succeeds.
- **`Property Test*` shadow trap avoidance**: used `Parameter EXPECTEDSEEDCOUNT = 10` rather than a state-tracking property. The class compiles cleanly and `%UnitTest_Result.TestMethod` records exactly 5 methods (no phantom datatype-helper methods).

### File List

**New files:**
- `src/SessionAgent/Search/UserVocabulary.cls` — `%Persistent` class with 8 properties + unique `(PortalUser, Alias)` index.
- `src/SessionAgent/Search/SeedVocabulary.cls` — `%Persistent` class with 5 properties + non-unique `Alias` index + `Seed()` classmethod (idempotent, 10 HL7 templates) + `InsertIfMissing` private helper.
- `src/SessionAgent/Search/NamespaceVocabulary.cls` — `%Persistent` class with 5 properties (schema-only per AR19, no insert/update logic in v1).
- `src/SessionAgent/Test/SeedVocabularyTest.cls` — `%UnitTest.TestCase` with 5 test methods.

**Modified files:**
- `src/SessionAgent/Installer.cls` — added step (5) `SessionAgent.Search.SeedVocabulary.Seed()` invocation in `Install()` orchestrator; added `LogPostSeedVocabularyCount()` private helper that emits `[iris-session-agent] <count> seed vocabulary templates ensured`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — marked `8-1-vocabulary-schemas-seed-templates` as `in-progress` then `review`.

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review subagent.
**Date:** 2026-05-07.
**Verdict:** **APPROVED with one fix-now applied during review.**

### Layer summary

- **Blind Hunter** (diff-only): 1 MEDIUM (F-1) + 4 LOW/dismissed.
- **Edge Case Hunter** (diff + project): 1 LOW (F-2 deferred) + 1 confirmed-resolved (empty-MessageBodyClass branch — dev's documented `IS NULL` fix verified empirically).
- **Acceptance Auditor** (vs spec): all 7 ACs verified met. 10/10 seed templates content-verbatim against spec; ASCII `->` connector confirmed across all rows via SQL probe; UserVocabulary 9 properties + unique index; NamespaceVocabulary schema-only with v1-vs-v1.5 boundary documented; Installer integration AC-4 ordering correct; live-install AC-7 evidence verbatim and idempotency-proven (10 rows on both runs).

### Empirical verification at review time

- **All 4 classes compiled cleanly** (verified via `iris_doc_compile` + `%Dictionary.ClassDefinition` membership probe).
- **Seed extent state:** `SELECT COUNT(*) FROM SessionAgent_Search.SeedVocabulary` → 10 rows.
- **Per-row content probe** confirmed all 10 templates present with ASCII `->` connector and empty `MessageBodyClass` (cross-class fallback shape).
- **Regression sweep (SQL ground-truth):** **Total=296 / Passed=296 / Failed=0** — verified at review time post-F-1 fix via the canonical Story 8.0 AC-5 SQL form.
- **`SeedVocabularyTest` per-method ground-truth probe:** all 5 methods Status=1 after F-1 fix.

### Findings & resolutions

#### F-1 (MEDIUM, fix-now applied) — `SeedVocabularyTest` test fixture used hardcoded mangled storage global names

**Location:** [`src/SessionAgent/Test/SeedVocabularyTest.cls`](../../src/SessionAgent/Test/SeedVocabularyTest.cls) `OnBeforeOneTest` / `OnAfterOneTest`.

**Problem:** Both fixtures called `Kill ^SessionAgenC88B.SeedVocabularyD/I` and `Kill ^SessionAgenC88B.UserVocabularyD/I` with literal compiler-generated mangled global names. The names `^SessionAgenC88B.*` are emitted by the IRIS class compiler based on the package hash and would silently change if the class hierarchy were renamed/refactored. A future package rename would cause the `Kill` to no-op against stale globals while leaving the actual extent populated, causing test contamination that surfaces as flaky idempotency assertions long after the rename. Predicted-bug shape per Rule 8.

**Resolution:** Replaced direct global Kills with `##class(X).%KillExtent()` calls — the framework-provided extent-clear helper resolves the storage globals through the Storage section regardless of mangling. Doc-comment updated to explain the resilience rationale.

**Verification:** Class compiled cleanly (`compilationTime: 13ms`, "up-to-date"). Test class still passes 5/5 (verified via SQL probe against `%UnitTest_Result.TestMethod` since the MCP envelope returned only 1/5). Post-test SeedVocabulary extent re-seeded by `OnAfterAllTests` (probed → 10 rows).

#### F-2 (LOW, deferred) — `Seed()` lacks DB-level concurrency guard

Logged to [`deferred-work.md`](deferred-work.md) as **LOW-8.1-F01**. IPM lifecycle is single-threaded; not blocking. Natural carrier is the v1.5 vocabulary hardening pass.

#### Dismissed findings

- **`tRS` not explicitly closed in `LogPostSeedVocabularyCount` and `InsertIfMissing`:** IRIS GC reclaims handles on scope exit; established pattern across the codebase.
- **`OnAfterAllTests` swallows `Seed()` status:** intentional defensive cleanup; failure on suite teardown should not propagate to the runner.
- **Em-dashes (`—`) and en-dashes (`–`) in `///` doc-comments:** established project pattern (39 instances in `Installer.cls` alone); not in the `Description` SQL row data path that the dev's `TestSeedDescriptionsAreAscii` rule guards.
- **Unicode `→` (U+2192) at `SeedVocabulary.cls:165`:** in a `;` developer-only inline comment, not in any operator-rendered text.
- **`Seed()` partial-state on mid-execution failure:** the per-template `InsertIfMissing` idempotency probe handles partial state correctly — re-running picks up where it left off.

### Project-rule compliance

- **Rule 1 (spec ≤ 250 lines):** Spec at 308 lines incl. populated Dev Agent Record/File List/Change Log; net spec body before completion notes is ~145 lines — well within cap.
- **Rule 2 (verbatim AC-contract evidence in Completion Notes):** ✓ — install-log lines verbatim, `SELECT COUNT(*)` probes verbatim, per-class regression breakdown verbatim, MAX(ID) collation issue captured in Debug Log References with the working SQL form.
- **Rule 3 (typed MCPs first):** ✓ — `iris_doc_compile`, `iris_sql_execute`, `iris_execute_tests` used; no `iris_execute_command`.
- **Rule 4 (stale-reference scan):** N/A — first appearance of `SessionAgent.Search.*` in the codebase; no pre-existing references.
- **Rule 5 (one-liner check before deferring):** ✓ — F-1 fixed, F-2 is a deferred-work entry with the three Rule 8 tests evaluated.
- **Rule 6 (epic-end battery):** N/A at story level — this is per-story review, not epic close.
- **Rule 8 (defer threshold raised — fix-now is default):** ✓ — F-1 (MEDIUM) fixed in the same story; F-2 (LOW) explicitly evaluated against the three tests and entered into deferred-work.md.
- **Rule 10 (external-default research):** N/A — HL7 message-type taxonomy is a domain-stable internal taxonomy, not an external versioned default.
- **Rule 11 (live integration smoke):** N/A — no external API touched.
- **Rule 12 (rendered-text readability):** N/A — no UI surface; content-correctness on `Description` field text already verified by dev's `TestSeedDescriptionsAreAscii` test.

### Files modified during review

- `src/SessionAgent/Test/SeedVocabularyTest.cls` — F-1 fix (replaced hardcoded mangled-global `Kill`s with `%KillExtent()`).
- `_bmad-output/implementation-artifacts/deferred-work.md` — appended LOW-8.1-F01 entry.
- `_bmad-output/implementation-artifacts/8-1-vocabulary-schemas-seed-templates.md` — populated Code Review section (this).

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-07 | Initial spec drafted by lead from epics.md §"Story 8.1" + architecture AR19 | Claude Opus 4.7 (lead) |
| 2026-05-07 | Story implementation complete — 4 new .cls files, 1 .cls edit; 296/296/0 SQL ground-truth pass; live install verified twice with identical log lines and unchanged COUNT(*); status flipped to `review` | Claude Opus 4.7 (dev) |
| 2026-05-07 | Code review APPROVED with one MEDIUM fix-now applied (F-1: switched test fixture from hardcoded mangled storage globals to `%KillExtent()`); LOW-8.1-F01 deferred to v1.5 vocabulary hardening pass; 296/296/0 regression preserved post-fix | Claude Opus 4.7 (reviewer) |
