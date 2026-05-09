# Story 13.3: get_production_config_item — Ensemble Config Item Reader

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` (TOOL-3).
**Rule 9 grep:** `grep -ni "Story 13.3\|story-13-3" deferred-work.md` → 0 hits.

## User Story

As the **Inspection Agent**, I want a `get_production_config_item` tool so that I can read the
adapter class, pool size, enabled flag, and explicit settings of any named config item in an
Ensemble production, helping operators diagnose config-related failures (wrong file path,
wrong credentials, pool=0, scheduler disabled).

## Acceptance Criteria

**AC-1 — Tool registered.** Class `SessionAgent.Tool.Inspection.GetProductionConfigItem`
compiled and registered. `Tool.Registry.ListTools` returns `get_production_config_item` with
non-empty Description. `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` updated to 27.

> **Then** ListTools envelope contains `"name":"get_production_config_item"`; EXPECTEDTOOLCOUNT=27.

**AC-2 — Item found.** When invoked with a valid `(production_name, config_item_name)`,
response includes `class_name`, `adapter_class`, `enabled`, `pool_size`, `comment`,
`host_settings`, `adapter_settings`, and `render_strategy="ok"`.

> **Then** response `class_name` matches `Ens_Config.Item.ClassName`; `enabled` and `pool_size`
> match live item values; `render_strategy="ok"`.

**AC-3 — Settings split by Target.** Explicitly configured settings are split into
`host_settings` (Target="Host") and `adapter_settings` (Target="Adapter"). If no settings are
configured, both arrays are `[]`.

> **Then** a live item with no configured settings returns `"host_settings":[],"adapter_settings":[]`.

**AC-4 — Production not found.** When `production_name` names a non-existent production,
returns `render_strategy="production_not_found"` with no `isError=1`.

> **Then** response has `"render_strategy":"production_not_found"`; `isError` absent.

**AC-5 — Item not found.** When `config_item_name` is not found in the production, returns
`render_strategy="item_not_found"` with no `isError=1`.

> **Then** response has `"render_strategy":"item_not_found"`; `isError` absent.

**AC-6 — Strip-last-segment fallback on production_name.** When `production_name` has a
trailing method-name segment that causes a not-found, strip and retry once. Success → normal
envelope + `production_name_auto_corrected_from`. Still-not-found → `production_not_found` +
`candidate_production_name`.

> **Then** passing `SessionAgent.Sample.Production.OnRequest` auto-corrects to
> `SessionAgent.Sample.Production`; response carries `production_name_auto_corrected_from`.

**AC-7 — Anti-method-suffix warnings in schema.** Both `production_name` and
`config_item_name` descriptions in `GetInputSchema()` include "Pass the class name only."

> **Then** `GetInputSchema()` `properties.production_name.description` and
> `properties.config_item_name.description` each contain "Pass the class name only".

**AC-8 — Regression sweep.** All pre-existing tests plus new `GetProductionConfigItemTest` pass.

> **Then** `SessionAgent.Test.Util.RegressionSweepCount()` returns `Total=N, Passed=N, Failed=0`
> where N ≥ 489 (Story 13.1 baseline) + new test count.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight probes (COMPLETE)**
  - `Ens.Config.Item.NameKeyOpen()` → `<METHOD DOES NOT EXIST>` — spec API invalid.
  - `Ens.Config.Item.NameOpen()` → `<METHOD DOES NOT EXIST>` — index-generated method does not exist.
  - SQL `SELECT ID, Name, ClassName FROM Ens_Config.Item WHERE Production = 'SessionAgent.Sample.Production'` → 5 items (IDs 766–770). ✓
  - `Ens.Config.Item.%OpenId(770)` → `<Object:Ens.Config.Item>` ✓ 
  - `Ens.Config.Production.%OpenId("SessionAgent.Sample.Production")` → `<Object:Ens.Config.Production>` ✓
  - `Ens_Config.Setting` SQL → `Table 'ENS_CONFIG.SETTING' not found` — `Ens.Config.Setting` is a `%SerialObject` embedded in Item, accessed via `tItem.Settings.GetAt(i)`.
  - Item 770 (FilePublish): Name=ClassName="SessionAgent.Sample.BO.FilePublish"; Comment="Writes stub file to mgr/Temp/"; Enabled=1; PoolSize=1; Settings=[] (no explicit settings configured — uses all defaults).
  - **Implication:** Sample production items have empty Settings lists. Tests for AC-3 must accept `[]` as correct output.
- [x] **Task 1 — Implement `SessionAgent.Tool.Inspection.GetProductionConfigItem`**
  - File: `src/SessionAgent/Tool/Inspection/GetProductionConfigItem.cls`
  - Follow pattern from `GetQueueState.cls` (TOOLNAME / DESCRIPTION / MUTATESSTATE / GetInputSchema / Invoke)
  - See Dev Notes for corrected IRIS API
- [x] **Task 2 — Implement `SessionAgent.Test.GetProductionConfigItemTest`**
  - File: `src/SessionAgent/Test/GetProductionConfigItemTest.cls`
  - Use live sample production items (no fixture needed — SQL + %OpenId work)
  - AI-5 carry-forward: enumerate ALL expected hits in any substring-grep assertion
- [x] **Task 3 — Bump InspectionSuiteVerificationTest**
  - File: `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls`
  - `EXPECTEDTOOLCOUNT` 26 → 27
  - Add `get_production_config_item` to `tExpected` list and `GetRepresentativeArgs`
- [x] **Task 4 — Compile, test, regression sweep**
  - Compile all changed classes; zero errors
  - Run per-class tests; canonical SQL probe via `RegressionSweepCount()`
- [x] **Task 5 — Update sprint-status.yaml**
  - Flip `13-3-get-production-config-item-tool: ready-for-dev` → `review`

## Dev Notes

**CRITICAL API corrections (spec had wrong methods):**

`Ens.Config.Item.NameKeyOpen()` and `NameOpen()` do NOT exist. Correct lookup:
```objectscript
; Step 1: Verify production exists
Set tProd = ##class(Ens.Config.Production).%OpenId(pProductionName)
If '$IsObject(tProd) { /* production_not_found envelope */ }

; Step 2: Find item by parameterized SQL (NO string concat — injection safe)
Set tStmt = ##class(%SQL.Statement).%New()
Set tSC = tStmt.%Prepare("SELECT %EXACT(ID), %EXACT(ClassName), Enabled, PoolSize, %EXACT(Comment) FROM Ens_Config.Item WHERE %EXACT(Production) = ? AND %EXACT(Name) = ?")
Set tRS = tStmt.%Execute(pProductionName, pConfigItemName)
If 'tRS.%Next() { /* item_not_found envelope */ }
Set tItemID = tRS.%Get("ID")
Set tItem = ##class(Ens.Config.Item).%OpenId(tItemID)

; Step 3: Adapter class
Set tAdapterClass = tItem.AdapterClassName()

; Step 4: Settings split by Target
Set tHostSettings = [], tAdapterSettings = []
Set tKey = ""
For { Set tSetting = tItem.Settings.GetNext(.tKey)  Quit:tKey=""
    If tSetting.Target = "Host" {
        Do tHostSettings.%Push({"name":(tSetting.Name), "value":(tSetting.Value)})
    } ElseIf tSetting.Target = "Adapter" {
        Do tAdapterSettings.%Push({"name":(tSetting.Name), "value":(tSetting.Value)})
    }
}
```

**Ens.Config.Setting is a %SerialObject.** There is no `Ens_Config.Setting` SQL table.
Settings are embedded in Item's data node and accessed ONLY via the `tItem.Settings` list.

**Strip-last-segment on production_name only** (config_item_name is not a class name):
```objectscript
Set tOrigProductionName = pProductionName
Set tAutoCorrected = 0, tStrippedName = ""
If '$IsObject(tProd), pProductionName [ "." {
    Set tSegCount = $Length(pProductionName, ".")
    If tSegCount > 1 {
        Set tStrippedName = $Piece(pProductionName, ".", 1, tSegCount - 1)
        Set tProd = ##class(Ens.Config.Production).%OpenId(tStrippedName)
        If $IsObject(tProd) { Set pProductionName = tStrippedName  Set tAutoCorrected = 1 }
    }
}
```

**production_name validation:** validate against `^[A-Za-z%][A-Za-z0-9%._]*$` before use (cross-cutting requirement). Return `isError=1` for invalid format.

**Response shape:**
```json
{
  "production_name": "SessionAgent.Sample.Production",
  "config_item_name": "SessionAgent.Sample.BO.FilePublish",
  "class_name": "SessionAgent.Sample.BO.FilePublish",
  "adapter_class": "EnsLib.File.OutboundAdapter",
  "enabled": true,
  "pool_size": 1,
  "comment": "Writes stub file to mgr/Temp/",
  "host_settings": [],
  "adapter_settings": [],
  "render_strategy": "ok"
}
```

**Test approach** (live sample production — no fixture needed):
- Positive: `production_name="SessionAgent.Sample.Production"`, `config_item_name="SessionAgent.Sample.BP.OrderRouter"` → verify ClassName="SessionAgent.Sample.BP.OrderRouter", enabled=true, render_strategy="ok"
- Empty settings: verify `host_settings=[]`, `adapter_settings=[]` (all live items use defaults)
- production_not_found: `production_name="Nonexistent.Production"` → render_strategy="production_not_found"
- item_not_found: `config_item_name="NoSuchItem"` in valid production → render_strategy="item_not_found"
- Strip-last-segment: `production_name="SessionAgent.Sample.Production.OnRequest"` → auto-corrects; response has `production_name_auto_corrected_from`
- Schema warning: `GetInputSchema()` descriptions contain "Pass the class name only"
- Registry: ListTools includes "get_production_config_item" with non-empty description

**Reference files:**
- `src/SessionAgent/Tool/Inspection/GetQueueState.cls` — Invoke pattern, isError convention
- `src/SessionAgent/Tool/Inspection/GetBusinessProcessSource.cls` — strip-last-segment pattern (lines 105-156)
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` — EXPECTEDTOOLCOUNT bump pattern

**Regression sweep call:** use `SessionAgent.Test.Util.RegressionSweepCount()` (built in 13.1).

## Dev Agent Record

### Implementation Plan

1. Task 1: Implement `GetProductionConfigItem.cls` following the `GetQueueState.cls` pattern.
   - Used parameterized SQL via `%SQL.Statement` against `Ens_Config.Item` for injection-safe lookup.
   - Discovered that `%EXACT()` wrapping changes column name aliases — must use `%GetData(n)` positional access, not `%Get("colName")`. Fixed after first test run surfaced `<PROPERTY DOES NOT EXIST>` error.
   - Settings iteration uses `tItem.Settings.GetNext(.tKey)` loop (serial object collection, no SQL table).
   - `AdapterClassName()` returns empty string for Business Process items (BPs have no adapter).
   - Strip-last-segment fallback implemented for `production_name` only (not `config_item_name`).

2. Task 2: Implemented 10-test class `GetProductionConfigItemTest.cls` using live sample production.
   - All tests use live HSCUSTOM data — no fixture seeding required.
   - AC-3 confirmed: all 5 sample production items have empty Settings lists (Task 0 pre-flight finding).

3. Task 3: Bumped `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` from 26 → 27.
   - Added `get_production_config_item` to `tExpected` $ListBuild in `TestRegistryListsExactlyThirteenTools`.
   - Added representative args in `GetRepresentativeArgs` (uses live sample production, returns "ok" envelope).

4. Task 4: All 3 classes compile clean. `GetProductionConfigItemTest` 10/10 pass. `InspectionSuiteVerificationTest` 13/13 pass (SQL ground-truth probe). Regression sweep: 499/499 pass.

### Completion Notes

- **AC-1 verified:** `Tool.Registry.ListTools` includes `get_production_config_item` with non-empty Description. `EXPECTEDTOOLCOUNT=27`. Evidence: `TestRegistryListToolsIncludesGetProductionConfigItem` passed; `TestRegistryListsExactlyThirteenTools` passed (SQL probe: 13/13).
- **AC-2 verified:** Live probe: `production_name="SessionAgent.Sample.Production"`, `config_item_name="SessionAgent.Sample.BP.OrderRouter"` → `class_name="SessionAgent.Sample.BP.OrderRouter"`, `enabled=true`, `pool_size=1`, `render_strategy="ok"`. Test `TestPositiveItemFound` passed.
- **AC-3 verified:** Live probe confirms all sample production items use default settings only → `host_settings=[]`, `adapter_settings=[]`. Test `TestEmptySettingsArraysReturned` passed.
- **AC-4 verified:** `production_name="Nonexistent.Production.Never.Exists"` → `render_strategy="production_not_found"`, no `isError=1`. Test `TestProductionNotFound` passed.
- **AC-5 verified:** Valid production + `config_item_name="NoSuchConfigItem.Never.Exists"` → `render_strategy="item_not_found"`, no `isError=1`. Test `TestItemNotFound` passed.
- **AC-6 verified:** `production_name="SessionAgent.Sample.Production.OnRequest"` → auto-corrects; response carries `production_name_auto_corrected_from`. Still-not-found → `candidate_production_name`. Tests `TestStripLastSegmentAutoCorrects` and `TestStripLastSegmentStillNotFoundReturnsCandidateField` passed.
- **AC-7 verified:** `GetInputSchema()` `properties.production_name.description` contains "Pass the class name only"; `properties.config_item_name.description` contains "Pass the class name only". Test `TestInputSchemaDescriptionsContainPassClassNameOnly` passed.
- **AC-8 verified:** SQL ground-truth probe: `Total=499, Passed=499, Failed=0`. Baseline was 489 (Story 13.1) + 10 new tests = 499.

### Key Bug Found and Fixed

- **`%EXACT()` column alias issue:** The SQL `SELECT %EXACT(ID), %EXACT(ClassName), ...` wraps columns in the `%EXACT()` function which changes the column name aliases in the result set. `tRS.%Get("ID")` returns `""` (column not found) instead of the ID value. Fixed by switching to positional `tRS.%GetData(1)`, `tRS.%GetData(2)`, etc. column access, which is always reliable regardless of column alias changes.

## File List

- `src/SessionAgent/Tool/Inspection/GetProductionConfigItem.cls` (new)
- `src/SessionAgent/Test/GetProductionConfigItemTest.cls` (new)
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` (modified — EXPECTEDTOOLCOUNT 26→27, added get_production_config_item to tExpected list and GetRepresentativeArgs)

## Review Findings

**Reviewer:** Code Review Agent — 2026-05-09

**Verdict: CLEAN — 0 HIGH, 0 MEDIUM, 0 PATCH findings. 1 DEFER (pre-existing). 3 DISMISS (noise/pre-existing).**

- [x] [Review][Defer] `%Execute()` SQLCODE not checked after execution — `GetProductionConfigItem.cls:156`. A runtime SQL execution error (SQLCODE < 0) would silently appear as `render_strategy="item_not_found"` rather than a server fault envelope. **Pre-existing project-wide pattern across all 15+ inspection tools; not introduced by Story 13.3.** Deferred — Rule 8 test 1 (pre-existing, not caused by this change). Would require a project-wide sweep story to fix consistently.

- [x] [Review][Dismiss] `If tAdapterClass = $$$NULLOREF` guard (line 179) — uses OREF-null comparison on a `%String`-typed return from `AdapterClassName()`. In ObjectScript string context `$$$NULLOREF` coerces to `""`, so the guard correctly catches empty-string returns from BPs. Functionally correct; unusual idiom only.

- [x] [Review][Dismiss] `$Char(0)` normalization not applied to `tClassName` (line 167) — `ClassName` is a mandatory Ensemble config field; empty-or-NUL values not physically possible from Ensemble's own schema. No bug shape.

- [x] [Review][Dismiss] `TestAllThirteenToolsExerciseAgainstFixture` / `TestRegistryListsExactlyThirteenTools` method names stale (count is now 27) — pre-existing, previously deferred at Story 13.1 review. Not introduced by Story 13.3.

## Change Log

- 2026-05-09: Story 13.3 implemented. New tool `get_production_config_item` registered. New test class `GetProductionConfigItemTest` (10 tests). `InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` bumped 26→27. Regression sweep: 499/499 pass.
- 2026-05-09: Code review complete — CLEAN. 0 HIGH / 0 MEDIUM / 0 PATCH. 1 deferred (pre-existing %Execute SQLCODE pattern). 3 dismissed as noise. Status → done.
