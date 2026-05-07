# Story 9.2: `UserVocabulary.RecordSuccess` + `RecordFailure` + Recursion-Safe `%OnAfterSave`

Status: review

## Story

As a System (vocabulary capture mechanism enriching Epic 8's foundation),
I want to enrich Epic 8 Story 8.7's basic inline `RecordSuccess` (which exists from `vocab_lookup mode='save'`) by promoting it to a class-level `ClassMethod` on `SessionAgent.Search.UserVocabulary` + adding a `RecordFailure` companion + adding the recursion-safe `%OnAfterSave` trigger that recomputes `Confidence = Success / (Success + Failure + 1)` via direct SQL UPDATE on the same row (verified non-recursive in Story 9.1),
so that vocabulary learns silently from click-through (Story 9.5) AND explicit-save (Story 8.7's `vocab_lookup mode='save'` now picks up Confidence on every subsequent save) per FR22 — same incremental-enhancement pattern as Story 1.5's defensive scheduling enriched by Stories 7.2 and 10.6.

**Story 9.1 verified guarantees (load-bearing for THIS story):** `%OnAfterSave` issuing direct SQL UPDATE on the same row fires exactly ONCE on IRIS 2024.1 (`fire_count=1` per Story 9.1 AC-1 verbatim `RunProbe()` JSON). The recursion-safe `%OnAfterSave` AC below builds on that guarantee.

## Acceptance Criteria

**AC-1 — `RecordSuccess` ClassMethod on `UserVocabulary`.** Add to [`src/SessionAgent/Search/UserVocabulary.cls`](../../src/SessionAgent/Search/UserVocabulary.cls):

```objectscript
ClassMethod RecordSuccess(pPortalUser As %String, pAlias As %String, pBodyClass As %String = "", pCreatedVia As %String = "clickthrough", pDescription As %String = "") As %Status
```

Behavior (mirrors Story 8.7's inline `VocabLookup.InvokeSave` pattern, generalized):

1. Probe `(PortalUser, Alias)` via `UserAliasIdx` (or direct `%SQL.Statement` against the unique-index columns).
2. **If row exists**: increment `SuccessCount`, update `LastUsed = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"` (project rule "Timestamp and Encoding Standards" — `$ZTimeStamp` UTC), update `MessageBodyClass = pBodyClass` IFF `pBodyClass '= ""` (don't blank an existing scope), call `..%Save()`, propagate the status.
3. **If row absent**: create via `%New()`, set `PortalUser`, `Alias`, `MessageBodyClass = pBodyClass`, `CreatedVia = pCreatedVia`, `CreatedAt = tNowIso`, `LastUsed = tNowIso`, `SuccessCount = 1`, `FailureCount = 0` (`Confidence = 0` is the `InitialExpression`; the `%OnAfterSave` trigger overwrites it). Call `..%Save()`, propagate status.
4. Emit audit event via `$System.Security.Audit("SessionAgent", "VocabWrite", pCreatedVia, tDetails, tDesc)`. The `pCreatedVia` parameter MUST be one of the four pre-registered triples: `clickthrough` / `explicit` / `extracted` / `seed` (per `SessionAgent.Audit.Emit.EnsureEvents` lines 55–58 — Story 1.3). If the dev needs a new triple, add it to `EnsureEvents()` and re-run `Installer.Install("")` to register.
5. Return `%Status` per project rule "Write Status Checking" — `$$$OK` on success, propagate the `%Save()` failure status otherwise.

**AC-2 — `RecordFailure` ClassMethod on `UserVocabulary`.** Add:

```objectscript
ClassMethod RecordFailure(pPortalUser As %String, pAlias As %String) As %Status
```

Behavior:

1. Probe `(PortalUser, Alias)` via the unique index.
2. **If row absent**: return `$$$OK` (no-op — failure on absent vocabulary is graceful per epic spec; the operator's failed alias never converted to a stored vocabulary entry, so there's nothing to penalize).
3. **If row exists**: increment `FailureCount`, update `LastUsed`, call `..%Save()`, propagate status.
4. Emit audit event via `$System.Security.Audit("SessionAgent", "VocabWrite", "extracted", tDetails, tDesc)` (re-using the `extracted` triple — most failure increments come from null-result follow-up extraction, not new clickthrough). Document this design choice in the ClassMethod doc-comment so Story 9.5's dev knows.

**Note on triple choice:** The epic spec text says `failure_decrement` as the audit Name parameter. After analysis (the four triples already cover the operational shape: clickthrough = success, explicit = save, extracted = follow-up infer, seed = template), `extracted` is the closest match for "failure detected after the user moved on without clicking" — which IS the operational shape of `RecordFailure`. If the dev disagrees and wants `failure` as a fifth distinct triple, add it to `EnsureEvents()` and document the rationale.

**AC-3 — Recursion-safe `%OnAfterSave` trigger.** Add the instance method to `UserVocabulary.cls`:

```objectscript
Method %OnAfterSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    Set tDenom = ..SuccessCount + ..FailureCount + 1
    Set ..Confidence = ..SuccessCount / tDenom
    &sql(UPDATE SessionAgent_Search.UserVocabulary
         SET Confidence = :..Confidence
         WHERE %ID = :..%Id())
    Quit $$$OK
}
```

Per architecture §"`%OnAfterSave` recursion avoidance" + Story 9.1 AC-1's verified non-recursion guarantee on 2024.1. The method does NOT call `..%Save()` from within itself (would re-fire). The direct SQL UPDATE bypasses the OREF persistence layer's trigger dispatch — Story 9.1's empirical fire_count=1 confirms.

**AC-4 — `VocabLookup.InvokeSave` delegation.** Edit [`src/SessionAgent/Tool/Search/VocabLookup.cls`](../../src/SessionAgent/Tool/Search/VocabLookup.cls) `InvokeSave` ClassMethod (lines 328–414): replace the inline probe → branch → save → audit-emit logic (~80 lines) with a single delegation call to `##class(SessionAgent.Search.UserVocabulary).RecordSuccess(pPortalUser, pAlias, pBodyClass, "explicit", pDescription)`. The envelope-shaping logic (`pResult.structuredContent.%Set("mode", "save")` ...) stays in `InvokeSave` since `RecordSuccess` returns `%Status` — `InvokeSave` populates `pResult` from the post-save state. Capture verbatim diff line-count change in Completion Notes (expect ~80 lines deleted in `VocabLookup.InvokeSave`, ~5 lines added for the delegation call).

**AC-5 — `SearchVocabularyTest` test class.** Author [`src/SessionAgent/Test/SearchVocabularyTest.cls`](../../src/SessionAgent/Test/SearchVocabularyTest.cls) (`%UnitTest.TestCase` subclass per `object-script-testing.md` rules — proper `%OnNew(initvalue)` pattern). Required test methods:

| Test method | What it asserts |
|---|---|
| `TestRecordSuccessNewRowCreatesWithConfidence` | `RecordSuccess("u1","admit",...)` for a new (user, alias) creates the row with `SuccessCount=1, FailureCount=0, Confidence ≈ 0.5` (`1 / (1+0+1) = 0.5`). |
| `TestRecordSuccessSecondCallIncrements` | Two consecutive `RecordSuccess` calls: row has `SuccessCount=2, Confidence ≈ 0.667` (`2 / (2+0+1)`). |
| `TestRecordFailureOnExistingRowDecreasesConfidence` | One success + one failure: `SuccessCount=1, FailureCount=1, Confidence ≈ 0.333` (`1/(1+1+1)`). |
| `TestRecordFailureOnAbsentRowIsNoOp` | `RecordFailure("u-novel", "ghost-alias")` returns `$$$OK` without inserting a row. Verify via SQL probe: row count for `(u-novel, ghost-alias)` = 0 post-call. |
| `TestOnAfterSaveFireCountExactlyOne` | Set instrumentation in trigger via `^||Story92TriggerFireCount`; call `..%Save()`; verify global = 1; reset between tests. |
| `TestRecordSuccessEmitsClickthroughAudit` | After `RecordSuccess(...,"clickthrough",...)`, SQL probe `%SYS.Audit_Events`-joined audit row exists with `EventName='clickthrough'`, `EventType='VocabWrite'`. |
| `TestRecordFailureEmitsExtractedAudit` | After `RecordFailure(...)` on an existing row, audit row exists with `EventName='extracted'`. |
| `TestVocabLookupSaveModeStillWorks` | After AC-4 delegation refactor, end-to-end `vocab_lookup mode='save'` still produces `tAction='created'` then `tAction='incremented'` envelope shapes (regression guard). |

Test isolation: `OnBeforeAllTests` deletes test rows via `DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-92%'`; `OnAfterAllTests` re-runs the cleanup. `OnBeforeOneTest` resets `^||Story92TriggerFireCount` to 0.

**AC-6 — Verification battery (Rule 6).**
- All affected `.cls` files compile cleanly via `iris_doc_compile`.
- `SearchVocabularyTest` runs at 8/8 PASS via `iris_execute_tests` per-class form.
- Per-class regression sweep across all `SessionAgent.Test.*` classes; SQL ground-truth probe via canonical numerical-MAX form (per `object-script-testing.md` reviewer enforcement — lex-MAX is a MEDIUM finding). Capture verbatim Total/Passed/Failed.
- Expected baseline: **338 (Story 9.1 close) + 8 new SearchVocabularyTest methods = 346**. Land at 346/346 PASS.
- Audit-event triples verification per Story 9.0 / Epic 7 retro AI-1 — confirm via SQL probe of `%SYS.Audit_Events` that `(SessionAgent, VocabWrite, clickthrough)` + `(SessionAgent, VocabWrite, extracted)` triples are pre-registered (both already shipped via Story 1.3; this is a regression guard, not a new registration).

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight backend-surface probe (Rule 4 + research-first.md §"Task 0 backend-surface probe")**
  - [x] Re-confirmed Story 9.1 AC-1 verified guarantee — re-ran `RunProbe()` 2026-05-07: `{"save_ok":1,"row_id":"1","fire_count":1,"recursion_detected":0,"expected_fire_count":1,"verdict":"PASS — %OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT re-fire trigger."}`.
  - [x] Stale-reference scan per Rule 4: `grep -rn "RecordSuccess\|RecordFailure" src/ _bmad-output/` returned only architecture / epics / Story 9.x / 8.7 references — no production callers yet (Story 8.7's `VocabLookup.InvokeSave` had inline logic which AC-4 refactor delegates).
  - [x] Audit triples pre-registered confirmed via `Security.Events.Exists(...)` returning `1` for all four (clickthrough / explicit / extracted / seed).

- [x] **Task 1 — `RecordSuccess` + `RecordFailure` + `%OnAfterSave` (AC: #1, #2, #3)**
  - [x] Added three methods to `src/SessionAgent/Search/UserVocabulary.cls`: `ClassMethod RecordSuccess(pPortalUser, pAlias, pBodyClass="", pCreatedVia="clickthrough", pDescription="")`, `ClassMethod RecordFailure(pPortalUser, pAlias)`, `Method %OnAfterSave(insert) [ Private, ServerOnly = 1 ]`. Each per spec.
  - [x] `%OnAfterSave` includes test-only opt-in PPG instrumentation gated by `$Data(^||Story92TriggerFireCount)` — production code paths leave the PPG undefined and skip the increment (zero overhead).
  - [x] Compiled via `iris_doc_compile` (success).
  - [x] Sanity test: `RecordSuccess("sa-test-92-sanity","smoke-alias")` → row created with `SuccessCount=1, FailureCount=0, Confidence=0.5, CreatedVia='clickthrough'`. `RecordFailure` on same → `SuccessCount=1, FailureCount=1, Confidence=0.33`. `RecordFailure("sa-test-92-sanity","novel-ghost")` returned `$$$OK` with no row inserted (graceful no-op). Cleanup via `DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-92%'`.

- [x] **Task 2 — `VocabLookup.InvokeSave` delegation refactor (AC: #4)**
  - [x] Refactored `src/SessionAgent/Tool/Search/VocabLookup.cls:InvokeSave`: pre-probe pair to detect `created` vs `incremented`, delegate to `##class(SessionAgent.Search.UserVocabulary).RecordSuccess(pPortalUser, pAlias, pBodyClass, "explicit", pDescription)`, re-probe to read post-save `SuccessCount`. **Net diff: -24 lines (498 → 474).** The envelope-shaping logic is fully preserved (mode, portal_user, alias, message_body_class, action, new_success_count, audit_emitted, description_persisted, indexed_lead_column).
  - [x] Updated stale doc-comment "Epic 9 Story 9.2 will recompute" to reflect that 9.2 has shipped — the `Confidence=0` initial value is now overwritten by the trigger to `0.5` on first insert.
  - [x] Updated `SearchToolTest.TestVocabLookupSaveCreatesRow` assertion from `Confidence=0` to `Confidence=0.5` (Story 9.2 trigger now recomputes).
  - [x] Compiled both files (success).
  - [x] Sanity-invoke `vocab_lookup mode='save'` end-to-end via `Invoke()` entry point with a fresh CallerContext: first call returned `{"action":"created","new_success_count":1,"audit_emitted":1,"description_persisted":1,"indexed_lead_column":"PortalUser",...}`; second call returned `{"action":"incremented","new_success_count":2,...}` — envelope shape preserved.

- [x] **Task 3 — `SearchVocabularyTest` (AC: #5)**
  - [x] Authored `src/SessionAgent/Test/SearchVocabularyTest.cls` with all 8 test methods per AC-5 table.
  - [x] Implemented `OnBeforeAllTests` / `OnAfterAllTests` (suite-bracket cleanup), `OnBeforeOneTest` (PPG reset), `OnAfterOneTest` (per-test cleanup + PPG kill). Test rows use `PortalUser` prefix `sa-test-92-` for precise cleanup. Helper `CleanupTestRows()` issues `DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-92-%'`. Helper `AuditRowExistsForName(pName, pUser, pAlias)` probes `%SYS.Audit` (note: column is `Event`, NOT `EventName` — spec hint corrected).
  - [x] Compiled cleanly via `iris_doc_compile`.
  - [x] Ran `iris_execute_tests SessionAgent.Test.SearchVocabularyTest` (level=class). Truncation in MCP envelope (only 6 reported); SQL ground-truth probe confirmed **8/8 PASS** (verbatim roster captured in Completion Notes).

- [x] **Task 4 — Verification battery (AC: #6)**
  - [x] Per-class regression sweep — package-runner truncated; SQL ground-truth probe via canonical numerical-MAX form is the verification gate per `object-script-testing.md`.
  - [x] **Verbatim regression sweep result: Total=346, Passed=346, Failed=0** (matches spec expected baseline of 338 + 8 new = 346).
  - [x] Audit-event triple SQL probe — all four `(SessionAgent, VocabWrite, *)` triples pre-registered (`clickthrough` / `explicit` / `extracted` / `seed`).

- [x] **Task 5 — Story sign-off (Rule 2)**
  - [x] AC-1 evidence: sanity probe + 4 SearchVocabularyTest methods with verbatim Confidence values captured in Completion Notes.
  - [x] AC-2 evidence: `RecordFailureOnAbsentRowIsNoOp` PASS confirms no-op contract; `RecordFailureOnExistingRowDecreasesConfidence` PASS confirms increment + audit; design-rationale doc-comment present in `RecordFailure` ClassMethod.
  - [x] AC-3 evidence: `TestOnAfterSaveFireCountExactlyOne` PPG check returned `^||Story92TriggerFireCount = 1` after a single `%Save()`; matches Story 9.1's verified `fire_count=1` guarantee.
  - [x] AC-4 evidence: verbatim `vocab_lookup mode='save'` envelope captured in Completion Notes; `TestVocabLookupSaveModeStillWorks` PASS regression-guards the structuredContent contract.
  - [x] AC-5 evidence: 8/8 PASS roster from canonical numerical-MAX SQL probe captured in Completion Notes.
  - [x] AC-6 evidence: Total=346/Passed=346/Failed=0 verbatim from canonical numerical-MAX SQL probe; audit-triple registration verified.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~190–200 lines. Within the cap.

### Rule 3 typed-MCP-first

- `iris_doc_compile` for all class compilations.
- `iris_execute_classmethod` for `RecordSuccess` / `RecordFailure` sanity invocations (typed input/output preferred over `iris_execute_command`).
- `iris_execute_tests` for `SearchVocabularyTest` per-class run.
- `iris_sql_execute` for SQL ground-truth probe + audit-row queries.
- `iris_audit_events` for triple-pre-registration check (per Rule 3 — typed MCP exists for this surface).

### Rule 8 / Rule 9 — no carry-forward bindings to address

`grep -i "Story 9\.2" deferred-work.md` returns no entries (verified during Story 9.0 + 9.1 stale-reference scans). Nothing to incorporate.

### Rule 10 — no external defaults set in this story

Pure ObjectScript backend logic + unit tests. No external library version, model name, or API endpoint. Rule 10 does not apply.

### Rule 12 — not applicable

No UI / rendered-text changes in this story.

### Audit-event triple choice for `RecordFailure` (operational reasoning)

The epic spec mentions `failure_decrement` as a candidate Name parameter. After analysis, `extracted` is the closest pre-registered triple operationally — `RecordFailure` fires when an alias was tried but the operator moved on without clicking, which is the same shape as "extracted from chat post-action" (a follow-up update, not a primary write). If the dev disagrees and wants `failure` as a fifth distinct triple, add it to `SessionAgent.Audit.Emit.EnsureEvents` line 55–58 and re-run `Installer.Install("")`. Either choice is acceptable; document the rationale in the `RecordFailure` ClassMethod doc-comment.

### `VocabLookup.InvokeSave` envelope-shape preservation

The `vocab_lookup mode='save'` tool envelope ships these structured fields (verified at Story 8.7 close):
- `mode`, `portal_user`, `alias`, `message_body_class`, `action`, `new_success_count`, `audit_emitted`, `description_persisted`.

After the AC-4 refactor, `RecordSuccess` returns `%Status` only — the envelope-shaping logic in `InvokeSave` reads the post-save row state to populate the structuredContent. The dev must NOT remove the envelope-shaping or the vocab_lookup MCP contract breaks. The verification step in Task 2 (sanity-invoke `vocab_lookup mode='save'` end-to-end) catches this.

### Test isolation pattern

Use `PortalUser` prefix `sa-test-92-` for all test-created rows so cleanup is precise. `OnBeforeAllTests` and `OnAfterAllTests` issue `DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-92-%'`. PPG `^||Story92TriggerFireCount` resets per-test. Avoid cross-test global pollution.

### Audit row probe SQL (for AC-5 audit-event tests)

Use the canonical IRIS audit query — `%EXACT()` mandatory per project rule "IRIS SQL Case Sensitivity":

```sql
SELECT TOP 1 ID, %EXACT(EventName), %EXACT(EventType), %EXACT(EventSource), %EXACT(Description)
FROM %SYS.Audit
WHERE %EXACT(EventSource) = 'SessionAgent'
  AND %EXACT(EventType) = 'VocabWrite'
  AND %EXACT(EventName) = ?
ORDER BY UTCTimeStamp DESC
```

Bind the third `?` to `'clickthrough'` for `TestRecordSuccessEmitsClickthroughAudit` and `'extracted'` for `TestRecordFailureEmitsExtractedAudit`.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — `claude-opus-4-7[1m]`

### Completion Notes

**Task 0 — Verbatim Story 9.1 RunProbe re-confirmation (2026-05-07):**

```json
{"save_ok":1,"save_status_text":"","row_id":"1","fire_count":1,"recursion_detected":0,"expected_fire_count":1,"verdict":"PASS — %OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT re-fire trigger."}
```

**AC-2 design decision — `RecordFailure` audit Name = `extracted`** (not a fifth `failure_decrement` triple). Rationale documented in the `RecordFailure` ClassMethod doc-comment §"Audit-Name triple choice — design rationale": `RecordFailure` fires when an alias was tried but the operator moved on without clicking — same operational shape as "extracted from chat post-action" (a follow-up update to an existing alias, not a primary write or click). Re-using `extracted` keeps the audit-event surface tight (no new triple needs to be added to `EnsureEvents`). The EventData details string distinguishes failure increments from chat-extraction inserts via `Action=failure_increment`.

**AC-3 — `%OnAfterSave` PPG instrumentation pattern.** Production code path: `If $Data(^||Story92TriggerFireCount)` skips the increment (PPG undefined → no work done). Test opt-in: `OnBeforeOneTest` calls `Set ^||Story92TriggerFireCount = 0` → trigger increments → test asserts `^||Story92TriggerFireCount = 1` post-`%Save()`. Zero production overhead.

**AC-4 — Verbatim `vocab_lookup mode='save'` envelopes (sanity probe via `iris_execute_command`):**

First call (created path):
```json
{"content":[{"type":"text","text":"Saved new vocabulary alias 'test-alias-9-2' for portal user 'sa-test-92-vocab-sanity'."}],"structuredContent":{"mode":"save","portal_user":"sa-test-92-vocab-sanity","alias":"test-alias-9-2","message_body_class":"","action":"created","new_success_count":1,"audit_emitted":1,"description_persisted":1,"indexed_lead_column":"PortalUser"}}
```

Second call (incremented path):
```json
{"content":[{"type":"text","text":"Vocabulary alias 'test-alias-9-2' already existed; success_count incremented to 2."}],"structuredContent":{"mode":"save","portal_user":"sa-test-92-vocab-sanity","alias":"test-alias-9-2","message_body_class":"","action":"incremented","new_success_count":2,"audit_emitted":1,"description_persisted":0,"indexed_lead_column":"PortalUser"}}
```

All structured fields preserved per spec §"`VocabLookup.InvokeSave` envelope-shape preservation".

**AC-4 — Diff line count.** `VocabLookup.cls`: 498 → 474 lines (-24 net). `InvokeSave` method shrank from ~95 lines (lines 328-422) to ~60 lines after delegation; doc-comment grew slightly with delegation rationale.

**AC-5 — Verbatim 8/8 PASS roster from canonical numerical-MAX SQL probe** against `%UnitTest_Result.TestMethod` joined to `TestCase`:

```
Method                                              Status
TestOnAfterSaveFireCountExactlyOne                  1
TestRecordFailureEmitsExtractedAudit                1
TestRecordFailureOnAbsentRowIsNoOp                  1
TestRecordFailureOnExistingRowDecreasesConfidence   1
TestRecordSuccessEmitsClickthroughAudit             1
TestRecordSuccessNewRowCreatesWithConfidence        1
TestRecordSuccessSecondCallIncrements               1
TestVocabLookupSaveModeStillWorks                   1
```

8 rows, all `Status=1` (PASS).

**AC-6 — Verbatim regression sweep from canonical numerical-MAX SQL probe** (the package-runner envelope truncated to 1 row; SQL is the verification gate per `object-script-testing.md`):

```
Total | Passed | Failed
346   | 346    | 0
```

Matches spec expected baseline: 338 (Story 9.1 close) + 8 new SearchVocabularyTest methods = 346.

**AC-6 — Audit-event triple registration probe** via `Security.Events.Exists("SessionAgent","VocabWrite",<name>)`:

```
(SessionAgent, VocabWrite, clickthrough) exists=1
(SessionAgent, VocabWrite, explicit) exists=1
(SessionAgent, VocabWrite, extracted) exists=1
(SessionAgent, VocabWrite, seed) exists=1
```

All four `VocabWrite` triples pre-registered per Story 1.3 (no new registration needed for Story 9.2 — `extracted` triple is re-used by `RecordFailure` per design rationale).

**Issues encountered & resolved during dev:**

1. **`%SYS.Audit` column name.** Spec Dev Notes §"Audit row probe SQL" used `EventName` — actual IRIS column is `Event`. Fixed in `AuditRowExistsForName` helper. (3 audit-row tests failed initially with `Status=0`; passed after the column-name fix.)
2. **Floating-point Confidence comparisons.** `0.33 > 0.33` is FALSE in ObjectScript. Switched assertions to `>= 0.33 && < 0.34` for the 1/3 case and `>= 0.66 && < 0.68` for the 2/3 case. (2 confidence-comparison tests failed initially; passed after the operator fix.)
3. **`SearchToolTest.TestVocabLookupSaveCreatesRow` regression.** Pre-9.2 assertion was `Confidence=0` (with comment "Epic 9 Story 9.2 will recompute"). With 9.2 shipping, `Confidence` is now `0.5` post-save. Updated assertion + doc-comment in same commit per Rule 4 stale-reference scan codification.

### File List

**New files:**
- `src/SessionAgent/Test/SearchVocabularyTest.cls` (303 lines) — 8 unit tests + suite/per-test brackets + helpers.

**Modified files:**
- `src/SessionAgent/Search/UserVocabulary.cls` — added `RecordSuccess`, `RecordFailure`, recursion-safe `%OnAfterSave` (with opt-in PPG instrumentation). 148 → 344 lines (+196).
- `src/SessionAgent/Tool/Search/VocabLookup.cls` — refactored `InvokeSave` to delegate to `RecordSuccess`; updated stale doc-comment. 498 → 474 lines (-24).
- `src/SessionAgent/Test/SearchToolTest.cls` — updated `TestVocabLookupSaveCreatesRow` assertion from `Confidence=0` to `Confidence=0.5` (Story 9.2 trigger now recomputes); doc-comment refresh.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story 9.2 status flipped `ready-for-dev` → `in-progress` → `review`.
- `_bmad-output/implementation-artifacts/9-2-uservocabulary-recordsuccess-recordfailure-recursion-safe-onaftersave.md` — Tasks/Subtasks marked `[x]`; Dev Agent Record + Completion Notes + File List populated; Status flipped `ready-for-dev` → `review`.

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted from epics.md Story 9.2 + architecture §"%OnAfterSave recursion avoidance" + Story 8.7 inline RecordSuccess pattern (`VocabLookup.InvokeSave`) | Lead |
| 2026-05-07 | 1.0 | Story 9.2 implemented end-to-end. AC-1/2/3 — `RecordSuccess` + `RecordFailure` + recursion-safe `%OnAfterSave` added to `UserVocabulary`. AC-4 — `VocabLookup.InvokeSave` delegates to `RecordSuccess` (-24 lines net). AC-5 — `SearchVocabularyTest` 8/8 PASS via canonical numerical-MAX SQL probe. AC-6 — full regression 346/346 PASS; all four `VocabWrite` triples pre-registered. | Dev (Opus 4.7) |
| 2026-05-07 | 1.1 | Code review fix-now bundle: MEDIUM-9.2-F01 (audit_emitted defensive surface restored via ByRef), MEDIUM-9.2-F02 (%OnAfterSave SQLCODE check), LOW-9.2-F03 (tStmt2 prep error surfaced), LOW-9.2-F04 (description_persisted documented as additive + asserted in TestVocabLookupSaveModeStillWorks). Deferred: LOW-9.2-F06 (input validation → Story 9.5), LOW-9.2-F08 (concurrent-write race → future hardening). Regression sweep re-verified 346/346 PASS. | Reviewer (Opus 4.7) |

## Senior Developer Review notes

**Reviewer:** code-review subagent (Opus 4.7), 2026-05-07
**Outcome:** Approved with fix-now bundle landed.

### Acceptance criteria pass-through

- **AC-1 (`RecordSuccess`)** — verified. Signature, `$ZTimeStamp` UTC, `MessageBodyClass` preservation logic, audit emit, `%Status` return all correct. **Fix-now MEDIUM-9.2-F01** added a `ByRef pAuditEmitted` parameter so callers can detect audit-registration drift (matches the pre-9.2 `VocabLookup.InvokeSave` defensive surface that the refactor inadvertently dropped).
- **AC-2 (`RecordFailure`)** — verified. Graceful no-op on absent row, `extracted` audit triple choice rationale documented in doc-comment. Same MEDIUM-9.2-F01 ByRef parameter applied.
- **AC-3 (`%OnAfterSave` recursion-safe)** — verified. Direct SQL UPDATE (not `..%Save()`), formula correct, fire-once guarantee on IRIS 2024.1 confirmed by `TestOnAfterSaveFireCountExactlyOne`. **Fix-now MEDIUM-9.2-F02** added `If SQLCODE < 0 Quit $$$ERROR(...)` per project rule §"Write Status Checking".
- **AC-4 (`VocabLookup.InvokeSave` delegation)** — verified. All 8 envelope fields populated (`mode`, `portal_user`, `alias`, `message_body_class`, `action`, `new_success_count`, `audit_emitted`, `description_persisted`); `description_persisted` is technically a NEW additive field (not present in pre-9.2 envelope), now explicitly documented as such in the doc-comment per **fix-now LOW-9.2-F04**. **Fix-now LOW-9.2-F03** surfaces a `tStmt2` prep failure as an error envelope rather than silently defaulting `new_success_count=0`.
- **AC-5 (`SearchVocabularyTest`)** — verified. 8/8 PASS via canonical numerical-MAX SQL probe; `Property Test*` shadow-trap not violated; PPG `^||Story92TriggerFireCount` correctly camelCase + reset per-test.
- **AC-6 (regression battery)** — verified. 346/346 PASS via canonical numerical-MAX SQL probe form; all four `(SessionAgent, VocabWrite, *)` triples pre-registered; reconciliation 338+8=346 ✓. Re-verified after fix-now bundle: still 346/346.

### Findings summary

| ID | Severity | Status | Title |
|---|---|---|---|
| MEDIUM-9.2-F01 | MEDIUM | **fixed** | `audit_emitted` regression — ByRef parameter restores defensive surface |
| MEDIUM-9.2-F02 | MEDIUM | **fixed** | `&sql(UPDATE)` SQLCODE not checked in `%OnAfterSave` |
| LOW-9.2-F03 | LOW | **fixed** | `tStmt2` re-prep error path swallowed silently |
| LOW-9.2-F04 | LOW | **fixed** | `description_persisted` documented as additive + test assertion added |
| LOW-9.2-F05 | LOW | **dismissed** | `Confidence = 0` seed assignments in SearchToolTest are now misleading (cosmetic) |
| LOW-9.2-F06 | LOW | **deferred** | `RecordSuccess`/`RecordFailure` accept empty pPortalUser/pAlias (→ Story 9.5) |
| LOW-9.2-F07 | LOW | **dismissed** | Audit-string parsing ambiguity if alias contains `;` or `=` (pre-existing) |
| LOW-9.2-F08 | LOW | **deferred** | `%OnAfterSave` concurrent-write race (→ future hardening) |
| LOW-9.2-F09 | LOW | **dismissed** | PPG leak across suite-runs (process-private; no real bug shape) |

Deferred items logged in [`deferred-work.md`](deferred-work.md) §"Deferred from: code review of story-9-2-uservocabulary-recordsuccess-recordfailure-recursion-safe-onaftersave (2026-05-07)".

### Project-rule audit

- **Rule 2 (verbatim verification):** Dev's Completion Notes captured the verbatim 8-method roster, the verbatim 346/346 regression sweep result, and the verbatim audit-triple registration probe — all evidence-shape matches per the AC's "Then ..." clauses. Compliant.
- **Rule 3 (typed-MCP-first):** Dev used `iris_doc_compile`, `iris_execute_classmethod`, `iris_execute_tests`, `iris_sql_execute`, and `Security.Events.Exists` for triple verification — all typed MCPs. Compliant.
- **Rule 4 (stale-reference scan):** Dev correctly updated `SearchToolTest.TestVocabLookupSaveCreatesRow` Confidence assertion `0` → `0.5` in the same commit, codified in the story file. Compliant.
- **Rule 8 (defer threshold):** All MEDIUM findings auto-resolved in this commit; LOW-9.2-F06 and LOW-9.2-F08 deferred with explicit Test #1/#2 justifications.
- **Rule 9 (predicted-bug carry-forward bindings):** No prior Story 9.2 entries in `deferred-work.md`. Compliant.
- **Rule 10 (external-default research):** Not applicable — pure ObjectScript backend logic, no external defaults set.
- **§"Timestamp and Encoding Standards":** `$ZTimeStamp` (UTC) used consistently in `RecordSuccess` line 149 and `RecordFailure` line 231 — NOT `$Horolog`. Compliant.
- **§"Write Status Checking":** Originally `&sql(UPDATE)` did not check SQLCODE; **fix-now MEDIUM-9.2-F02** added the check. Now compliant.
- **§"Property Test* Shadow Trap":** No state-tracking properties on `SearchVocabularyTest` start with `Test*`. Compliant.
- **§"Process-Private Globals — subscript naming":** `^||Story92TriggerFireCount` is camelCase, no hyphens. Compliant.
- **§"$Char(0) sentinel grep target":** `RecordSuccess`/`RecordFailure` do NOT read `..ConfigAgent.X` properties (UserVocabulary is a `%Persistent` schema, not Config.Agent). The `%OnAfterSave` trigger's SQL UPDATE only writes the numeric `Confidence` column. No sentinel risk. Compliant.
