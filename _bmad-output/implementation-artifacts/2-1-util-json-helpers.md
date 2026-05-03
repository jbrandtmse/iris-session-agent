# Story 2.1: `Util.Json` Helpers

Status: done

## Story

As a developer building tools, providers, and audit emitters across `LLM.*`, `Tool.*`, `Audit.*`, `Search.*`, and `Task.*`,
I want a `SessionAgent.Util.Json` class with helper methods for the `%DynamicObject` operations that recur across the codebase,
so that I don't reinvent JSON-null emission, credential redaction, and deep-merge in every class that touches JSON — and so those operations follow project rule conventions consistently.

This is the **first foundational utility** in Epic 2. Stories 2.2 (`Util.RetryWithBackoff`), 2.3 (`Util.EnvSecret`), 2.5 (audit emit), 2.8/2.9 (LLM providers), and 2.10/2.11 (tool dispatch + tool implementations) all depend on it. Get the contract right now; many downstream callers cite it.

## Acceptance Criteria

ACs map to the BDD clauses in [epics.md Story 2.1](../planning-artifacts/epics.md#story-21-utiljson-helpers) (lines 723–744).

**AC-1 — `SessionAgent.Util.Json` class shipped at `src/SessionAgent/Util/Json.cls`** with five methods:

- `EmitNull(pObj As %DynamicObject, pKey As %String) As %Status` — calls `pObj.%Set(pKey, "", "null")` per project rule §"`%DynamicObject` null emission" ([architecture.md:487–494](../planning-artifacts/architecture.md#dynamicobject-null-emission-project-rule)). The third parameter is the type hint; using `pObj.%Set(pKey, "null", "null")` would emit the string `"null"` — wrong. Returns `%Status` per project rule §"`%Status` return convention" ([architecture.md:496–513](../planning-artifacts/architecture.md#status-return-convention-project-rule)).
- `Redact(pObj As %DynamicObject, pKeyList As %String, ByRef pOut As %DynamicObject) As %Status` — produces a deep-cloned `%DynamicObject` (via `%FromJSON(pObj.%ToJSON())` round-trip OR a manual recursive clone) where every property whose key matches a name in `pKeyList` (a comma-delimited list, e.g. `"api_key,Authorization,password"`) is replaced with the literal string `"<redacted>"`. Recursion descends into nested `%DynamicObject` and `%DynamicArray` values. Used by audit-log writers to scrub credential strings (NFR-S3, [prd.md:603](../planning-artifacts/prd.md)).
- `DeepMerge(pBase As %DynamicObject, pOverlay As %DynamicObject, ByRef pOut As %DynamicObject) As %Status` — returns a new `%DynamicObject` combining `pBase` and `pOverlay` with overlay keys winning at any depth. Type-mismatch rules: overlay JSON `null` overrides base value (whatever its type); overlay scalar overrides base object; overlay array **replaces** base array (does NOT concatenate).
- `IsObject(pValue) As %Boolean` — returns 1 if `pValue` is a `%DynamicObject`, 0 otherwise. Wraps `$IsObject(pValue) && (pValue.%ClassName(1) = "%Library.DynamicObject")`. Pure-functional helper; returns `%Boolean` directly (no `%Status`).
- `IsArray(pValue) As %Boolean` — same shape as `IsObject` but checks for `%Library.DynamicArray`.

**AC-2 — Iterator-safety invariant honored.** Per project rule §"`%DynamicObject` Iterator Safety" ([`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md)): inside `Redact`, **never** call `%Set()` or `%Remove()` on the source object while iterating it with `%GetIterator()`. The implementation either operates on a deep clone (`%FromJSON(%ToJSON())`) — which sidesteps the problem entirely — or collects the keys-to-modify into a `$ListBuild` list during iteration and applies the modifications in a second pass.

**AC-3 — `SessionAgent.Test.JsonTest` ships at `src/SessionAgent/Test/JsonTest.cls`** extending `%UnitTest.TestCase`, ≤ 500 lines per project rule §"Test Class Size" ([`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md)). Test methods (one per behavior; method names without `_` per the same rule):

- `TestEmitNullProducesJsonNullNotString` — builds a `%DynamicObject`, calls `EmitNull(obj, "k")`, asserts `obj.%ToJSON()` contains `"k":null` (regex on the JSON string, NOT `"k":"null"`).
- `TestRedactNestedObjects` — feeds a 3-level-nested object with credential keys (`api_key`, `Authorization`, `password`) at each level; asserts every match is replaced with `"<redacted>"` and non-matching keys are preserved untouched.
- `TestRedactNestedArrays` — feeds an object with `headers: [{name: "Authorization", value: "..."}]`; asserts the array element's `value` is preserved (key is `value`, not in pKeyList) and a different test variant replaces by parent-key matching.
- `TestRedactDoesNotMutateInput` — captures input `%ToJSON()` before and after; asserts unchanged (deep-clone semantics).
- `TestDeepMergeOverlayNullOverrides` — base `{a: "x"}`, overlay `{a: null}`; asserts merged is `{a: null}` (literal JSON null, not the string).
- `TestDeepMergeOverlayScalarOverridesObject` — base `{a: {b: 1}}`, overlay `{a: 2}`; asserts merged is `{a: 2}`.
- `TestDeepMergeOverlayArrayReplacesBaseArray` — base `{a: [1, 2]}`, overlay `{a: [3]}`; asserts merged is `{a: [3]}` (replaces, does NOT concatenate to `[1, 2, 3]`).
- `TestIsObjectAndIsArrayPredicates` — covers `%DynamicObject`, `%DynamicArray`, scalar `%String`, `%Integer`, and `""` (empty); asserts predicates return 1 only for the matching dynamic types.

All assertions use macros (`$$$AssertTrue(...)`, `$$$AssertEquals(...)`) per project rule §"Macro vs Method Distinction" — never `..AssertX(...)` methods.

**AC-4 — Class compiles clean and all tests pass.**

- `mcp__iris-dev-mcp__iris_doc_compile` succeeds for `SessionAgent.Util.Json` and `SessionAgent.Test.JsonTest` (no compile errors, no warnings beyond IRIS defaults).
- `mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test.JsonTest` returns 8/8 passing.
- The Epic 1 baseline regression suite still passes — `SessionAgent.Test` package returns 9 + 8 = 17/17 passing total (3 audit + 6 RBAC + 8 JSON).

## Tasks / Subtasks

- [x] **Task 1 — Author `src/SessionAgent/Util/Json.cls` (AC: #1, #2)**
  - [x] Class doc-comment banner with `///` HTML/DocBook markup per project rule §"Comments"
  - [x] Five methods per AC-1 with parameter-prefix conventions (`p` for params; per project rule §"Naming Conventions")
  - [x] `EmitNull` and `Redact` and `DeepMerge` follow `%Status` convention (`Set tSC = $$$OK` first / `Quit tSC` last); `IsObject` and `IsArray` are pure predicates returning `%Boolean` directly
  - [x] Argumentless `Quit` inside any Try/Catch (project rule §"QUIT Statement Restrictions")
  - [x] `Redact` implementation chooses one of the two iterator-safe patterns (deep-clone-via-JSON OR collect-keys-then-modify) and inline-comments the choice
  - [x] No `Storage` section authored (compiler-generated; project rule §"Storage Sections")

- [x] **Task 2 — Author `src/SessionAgent/Test/JsonTest.cls` (AC: #3)**
  - [x] Extends `%UnitTest.TestCase`; `%OnNew(initvalue)` calls `##super(initvalue)` per project rule §"Critical Constructor (`%OnNew`) Requirements"
  - [x] Eight `Test*` methods per AC-3, names use camel-case (no `_`) per project rule §"Basics"
  - [x] All assertions via `$$$Assert*` macros — never `..AssertX(...)` methods
  - [x] File ≤ 500 lines

- [x] **Task 3 — Compile + run via typed MCPs (AC: #4)**
  - [x] `mcp__iris-dev-mcp__iris_doc_compile` against both classes — capture output in Completion Notes
  - [x] `mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test.JsonTest` — capture 8/8 pass count
  - [x] `mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test` package — capture 17/17 pass count (regression confirms Epic 1 baseline intact)

- [x] **Task 4 — Stale-reference grep (discipline rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly" src/SessionAgent/Util/Json.cls src/SessionAgent/Test/JsonTest.cls` — expect no matches; record in Completion Notes

## Dev Notes

### Why no Task-0 backend-surface probe

Story 2.1 touches only `%DynamicObject`, `%DynamicArray`, `%FromJSON`/`%ToJSON`, `$IsObject`, and `%ClassName` — all well-established IRIS APIs already used in Epic 1's `Audit.Emit.cls`. There's no new IRIS surface to probe. The Task-0 probe rule (per [`.claude/rules/research-first.md`](../../.claude/rules/research-first.md) §"Task 0 backend-surface probe") applies to **Epic 12+ stories whose ACs reference a new or modified backend endpoint or new subprocess / bridge surface** — Story 2.1 is foundational utility code, no probe required.

### Auto-sync workflow

`.vscode/settings.json` has `objectscript.conn.active=true`. Edit `src/SessionAgent/Util/Json.cls` and `src/SessionAgent/Test/JsonTest.cls` locally with the Edit/Write tool — auto-sync pushes to IRIS (HSCUSTOM namespace) on save. **Do NOT call `iris_doc_load`** for these files. **DO call `iris_doc_compile`** afterward to capture compile errors (auto-sync pushes source but does not surface compile output to the agent). Reference: [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"VSCode Auto-Sync Workflow".

### Higher-level MCP preference (discipline rule 3)

Use `iris_doc_compile` (typed) and `iris_execute_tests` (typed) — avoid generic `iris_execute_command` for these operations. They return structured output and shorter responses.

### Implementation hint for `Redact` (non-binding)

The deep-clone-via-JSON approach (`Set tCloneStr = pObj.%ToJSON() Set pOut = ##class(%DynamicObject).%FromJSON(tCloneStr) ; then walk pOut and replace`) is simpler than the collect-keys-then-modify alternative and sidesteps iterator-safety entirely at the cost of one full JSON round-trip. The trade-off is acceptable for audit-log redaction (called once per LLM call, not in a hot loop). Pick whichever the dev finds clearer; document the choice in the inline comment.

### Constraints (from architecture)

- **Class location:** `src/SessionAgent/Util/Json.cls` (per [architecture.md:865](../planning-artifacts/architecture.md)). No deviations.
- **Test location:** `src/SessionAgent/Test/JsonTest.cls` (per [architecture.md:898](../planning-artifacts/architecture.md)).
- **Package prefix:** `SessionAgent.*` (per `project_package_naming.md` auto-memory + project rule §"Package Naming Convention").
- **Method-name underscores:** forbidden. Use camel-case throughout (project rule §"Basics").
- **Class-parameter underscores:** forbidden if any parameters are added. None planned for v1.

### Sources

- [epics.md:723–744 §"Story 2.1: `Util.Json` Helpers"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:487–494 §"`%DynamicObject` null emission (project rule)"](../planning-artifacts/architecture.md) — `EmitNull` mechanism.
- [architecture.md:496–513 §"`%Status` return convention (project rule)"](../planning-artifacts/architecture.md) — return-shape rule.
- [architecture.md:515–533 §"Argumentless `Quit` inside Try/Catch (project rule)"](../planning-artifacts/architecture.md) — Try/Catch shape.
- [architecture.md:865](../planning-artifacts/architecture.md) and [:898](../planning-artifacts/architecture.md) — class & test file paths.
- [prd.md:602–603 NFR-S2 / NFR-S3](../planning-artifacts/prd.md) — credential-confinement + redaction motivation.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"VSCode Auto-Sync Workflow", §"`%DynamicObject` Iterator Safety", §"Naming Conventions".
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"Available Assertion Macros", §"Critical Constructor (`%OnNew`) Requirements", §"Test Class Size".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Anthropic Claude Opus 4.7, 1M context) acting as Dev Agent under BMAD `bmad-dev-story` workflow.

### Debug Log References

None — straight implementation, no debugging required.

### Completion Notes List

**Task 1 — `src/SessionAgent/Util/Json.cls` authored.** Five class methods per AC-1: `EmitNull`, `Redact`, `DeepMerge`, `IsObject`, `IsArray`. Two private recursive helpers (`RedactWalkObject`, `RedactWalkArray`, `MergeWalkObject`) implement the deep-walk logic.

**Redact implementation choice (AC-2 iterator safety).** Deep-clone-via-JSON (`%FromJSON(pObj.%ToJSON())`) per Dev Notes hint — sidesteps iterator safety on the source object entirely (source is never touched after the clone). On the clone itself, the walk is also defensive: each recursive helper does a 2-pass collect-then-modify (Pass 1 collects keys-to-redact and keys-to-recurse-into via `%GetIterator`; Pass 2 applies `%Set` overwrites; Pass 3 recurses into nested structures). This satisfies both halves of the iterator-safety rule.

**DeepMerge implementation.** Deep-clones `pBase` via JSON round-trip (so `pBase` is never mutated), then walks overlay keys via `MergeWalkObject`. Type-mismatch behavior verified by tests:
- Overlay `null` → `pDest.%Set(key, "", "null")` emits literal JSON null.
- Overlay scalar → `pDest.%Set(key, val, type)` overwrites whatever was there (object, array, scalar).
- Overlay array → `pDest.%Set(key, ##class(%DynamicArray).%FromJSON(overlay.%ToJSON()))` REPLACES (deep-cloned to prevent overlay mutation leaking back).
- Overlay object + base object → recurse via `MergeWalkObject` for true deep merge.
- Overlay object + non-object base → replace with deep-clone of overlay object.

**Task 2 — `src/SessionAgent/Test/JsonTest.cls` authored.** Eight `Test*` methods, one per AC-3 behavior. Constructor calls `##super(initvalue)` per project rule. All assertions via `$$$Assert*` macros. Method names camel-case, no underscores. Total file length: 213 lines (well under 500-line cap).

**Code-review follow-up (2026-05-03).** Added a 9th test `TestDeepMergeDoesNotMutateBase` to lock the deep-clone-of-`pBase` invariant in `DeepMerge` (parallels AC-3 #4 `TestRedactDoesNotMutateInput`); marked the three internal recursive helpers (`RedactWalkObject`, `RedactWalkArray`, `MergeWalkObject`) as `[ Private ]` so they match the Dev Agent Record description and are no longer callable from outside the class; refactored the type-detection inside the recursive helpers to call the public `IsObject`/`IsArray` predicates rather than inline `%ClassName(1)` string comparisons (DRY: foundational helpers should use their own predicates internally). Test count: 9/9 JsonTest pass; full `SessionAgent.Test` package: 18/18 pass (3 + 9 + 6).

**Task 3 — Compile + tests via typed MCPs.**

`mcp__iris-dev-mcp__iris_doc_compile` (flags `cuk`):
```
{"success":true,"documents":["SessionAgent.Util.Json.cls","SessionAgent.Test.JsonTest.cls"],"compilationTime":"12ms",
 "console":["Compilation started on 05/03/2026 07:00:36 with qualifiers 'cuk'",
            "Class SessionAgent.Test.JsonTest is up-to-date.",
            "Class SessionAgent.Util.Json is up-to-date.",
            "Compilation finished successfully in 0.001s."]}
```
Clean compile, no errors, no warnings.

`mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test.JsonTest` (level=class) — initial dev pass:
```
total=8, passed=8, failed=0, skipped=0
- DeepMergeOverlayArrayReplacesBaseArray  passed (0.439s)
- DeepMergeOverlayNullOverrides           passed (0.537s)
- DeepMergeOverlayScalarOverridesObject   passed (0.260s)
- EmitNullProducesJsonNullNotString       passed (0.352s)
- IsObjectAndIsArrayPredicates            passed (1.314s)
- RedactDoesNotMutateInput                passed (0.563s)
- RedactNestedArrays                      passed (0.746s)
- RedactNestedObjects                     passed (1.111s)
```
8/8 passing.

`mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test` package (level=package) — post code-review (2026-05-03), includes the new `TestDeepMergeDoesNotMutateBase`:
```
total=18, passed=18, failed=0, skipped=0
- AuditEmitTest:    3/3 passed (Epic 1 baseline)
- JsonTest:         9/9 passed (Story 2.1 + code-review follow-up)
- ReadOnlyRoleTest: 6/6 passed (Epic 1 baseline)
```
18/18 passing — Epic 1 baseline regression intact, JsonTest gained one immutability lock test.

**Task 4 — Stale-reference grep.** Ran rg against both new files for `HSCUSTOMCODE` and `%SessionAgent_ReadOnly` patterns. Result: **no matches** in either file. Story 2.1's narrow scope (foundational utility, no DB/role references) means no canonical-doc cross-reference cleanup is needed.

### File List

- `src/SessionAgent/Util/Json.cls` (NEW) — `SessionAgent.Util.Json` class with five public class methods (`EmitNull`, `Redact`, `DeepMerge`, `IsObject`, `IsArray`) and three `[ Private ]` recursive helpers (`RedactWalkObject`, `RedactWalkArray`, `MergeWalkObject`). 271 lines (after code-review fixes).
- `src/SessionAgent/Test/JsonTest.cls` (NEW) — `SessionAgent.Test.JsonTest` extending `%UnitTest.TestCase` with nine `Test*` methods (eight per AC-3 + one code-review-added `TestDeepMergeDoesNotMutateBase` immutability lock). 238 lines.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED) — `2-1-util-json-helpers` flipped `ready-for-dev` → `review`; `last_updated` field updated.
- `_bmad-output/implementation-artifacts/2-1-util-json-helpers.md` (MODIFIED) — story file updated with task checkboxes, Dev Agent Record, File List, Change Log; status flipped to `review`.

### Change Log

| Date       | Author        | Description                                                                                                                                                      |
|------------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 2026-05-03 | Dev Agent     | Initial implementation. Both classes shipped. Tests 8/8, regression 17/17.                                                                                        |
| 2026-05-03 | Code Reviewer | Added `TestDeepMergeDoesNotMutateBase` (M-1); marked 3 helpers `[ Private ]` (M-2); refactored helpers to call `IsObject`/`IsArray` (M-3). Tests 9/9, package 18/18. |
