# Story 2.3: `Util.EnvSecret` Credential Resolution

Status: done

## Story

As an Operator-Admin,
I want `SessionAgent.Util.EnvSecret` to resolve LLM provider API keys via the documented ladder (env-var → `Ens.Config.Credentials` → AES-encrypted custom store) without ever logging the resolved key value,
so that I can supply credentials via my preferred mechanism (containers favor env-var; traditional installs favor `Ens.Config.Credentials`) without changing application code (FR40, NFR-S2, NFR-S3).

This is the **third foundational utility** in Epic 2. Story 2.4 (`Config.Agent`) stores `EnvVarName` + `CredentialName` references (NOT `ApiKey`), Story 2.9 (`OpenAIProvider`) calls `Resolve()` to materialize the actual key for the `Authorization: Bearer ...` header, and Story 2.5 (`Audit.LlmCall`) rows show the key as `<redacted>` (NFR-S3 closing the loop).

## Acceptance Criteria

ACs map to the BDD clauses in [epics.md Story 2.3](../planning-artifacts/epics.md#story-23-utilenvsecret-credential-resolution) (lines 772–796) and the architecture row at [§"Credential storage"](../planning-artifacts/architecture.md) (line 255).

**AC-1 — `SessionAgent.Util.EnvSecret` class shipped at `src/SessionAgent/Util/EnvSecret.cls`** with three ClassMethods:

- `Resolve(pEnvVarName As %String, pCredentialName As %String) As %String` — returns the resolved API key (or empty string if no source resolves) by checking sources in this order:
  1. **Env-var:** if `pEnvVarName '= ""` AND `$SYSTEM.Util.GetEnviron(pEnvVarName)` is non-empty → return that value.
  2. **`Ens.Config.Credentials`:** if `pCredentialName '= ""` AND `##class(Ens.Config.Credentials).%ExistsId(pCredentialName) = 1` → open the row via `%OpenId(pCredentialName, 0)` (concurrency=0; lock-free read), return `.Password`. Wrap the open in Try/Catch — if the open or `.Password` getter fails, fall through to the next ladder rung (do NOT propagate the exception).
  3. **AES custom store (stub):** delegate to internal `ResolveFromAesStore(pCredentialName)` which returns `""` in v1. Comment block above the stub names the deferral: "v1 ships the interface; operators choosing the AES route opt in by extending this class. Full implementation deferred per architecture line 255."
  4. If no source resolves → return `""`. Caller is responsible for surfacing this as a structured error (no exception thrown by `Resolve`).
- `IsResolvable(pEnvVarName As %String, pCredentialName As %String) As %Boolean` — convenience predicate: returns 1 if `Resolve(...)` would return a non-empty value, 0 otherwise. Implemented in terms of `Resolve(...) '= ""`. Provided so callers can probe without materializing the key value into a local variable they then have to be careful about.
- `ResolveFromAesStore(pCredentialName As %String) As %String` — `[ Private ]` stub that returns `""`. Doc-comment names the deferral.

**AC-2 — Never-log invariant.** The implementation MUST NOT:

- Call `Write` on the resolved key value
- Append the key value to `^ClineDebug` or any other persistent global
- Concatenate the key into any string passed to `$System.Status.Error()`, `$$$ERROR(...)`, or any logger
- Embed the key in any string returned outside of `Resolve()`'s direct return value (e.g., no "key looks like '<value>'" debug strings)

This is enforced primarily by **code review** (per architecture §"Pattern Decisions Locked at Architecture-Stage" PD3 spirit) and by **NFR-S2/NFR-S3 contract reading**. The test in AC-3 closes the loop empirically for the surface available at this story (`^ClineDebug`).

**AC-3 — `SessionAgent.Test.EnvSecretTest` ships at `src/SessionAgent/Test/EnvSecretTest.cls`** extending `%UnitTest.TestCase`, ≤ 500 lines. Test methods (camel-case, no underscores; `$$$Assert*` macros only):

- `TestEnvVarPathResolves` — uses `$SYSTEM.Util.SetEnviron("SESSIONAGENT_TEST_KEY", "test-value-abc123")` to set a unique sentinel env-var; calls `Resolve("SESSIONAGENT_TEST_KEY", "")`; asserts return equals `"test-value-abc123"`. `OnAfterOneTest` clears the env-var via `$SYSTEM.Util.SetEnviron("SESSIONAGENT_TEST_KEY", "")` to keep the process clean.
- `TestCredentialPathResolves` — creates `Ens.Config.Credentials` row with `SystemName="SessionAgentTestCred"`, `Username="testuser"`, `Password="cred-value-xyz789"`, saves; calls `Resolve("", "SessionAgentTestCred")`; asserts return equals `"cred-value-xyz789"`. `OnAfterOneTest` deletes the credential row.
- `TestEnvVarTakesPrecedenceOverCredential` — sets BOTH the env-var and the credential row with different values; asserts `Resolve("SESSIONAGENT_TEST_KEY", "SessionAgentTestCred")` returns the env-var value (not the credential). Cleanup in `OnAfterOneTest`.
- `TestNothingResolvesReturnsEmpty` — calls `Resolve("SESSIONAGENT_TEST_KEY_DOES_NOT_EXIST", "SessionAgentTestCredDoesNotExist")` (or `Resolve("", "")`); asserts return is `""`.
- `TestEmptyArgsReturnEmpty` — calls `Resolve("", "")`; asserts `""`.
- `TestIsResolvablePredicate` — verifies `IsResolvable` mirrors `Resolve`'s non-empty / empty return.
- `TestResolveDoesNotMutateClineDebug` — captures `^ClineDebug` before and after a successful `Resolve` call; asserts unchanged. (Empirical NFR-S3 check for the surfaces visible at this story; full audit-row coverage lands in Story 2.5/2.9.)
- `TestAesStoreStubReturnsEmpty` — calls `Resolve("", "AnyName")` after disabling the env-var path AND with no Credentials row matching `AnyName`; asserts `""` (the AES stub returns empty per the deferral). This is the contract test for the v1 stub semantics.

All assertions via `$$$Assert*` macros; never `..AssertX(...)`. `%OnNew(initvalue As %String = "")` calls `##super(initvalue)`.

**AC-4 — Compile + tests pass, regression intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` succeeds for both classes.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.EnvSecretTest`: 8/8 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 35/35 passing total (3 audit + 6 RBAC + 9 JSON + 9 retry + 8 envsecret).

## Tasks / Subtasks

- [x] **Task 0 — irislib API verification (project rule "IRIS Library Source")**
  - [x] Read `irislib/Ens/Config/Credentials.cls` to confirm: (a) `%OpenId(systemName, 0)` is the correct concurrency-free open call; (b) `Password` getter signature; (c) the `SystemName` property is the row key (per the existing read in this file's authoring — confirm during implementation). Capture the verified signature in Completion Notes.
  - [x] Read `irislib/%SYSTEM/Util.cls` (or run `iris_macro_info` on it) to confirm `GetEnviron(name)` and `SetEnviron(name, value)` signatures. Capture in Completion Notes. **`SetEnviron` does NOT exist** — finding documented in Completion Notes; test strategy adapted (use OS-set `PATH` env-var rather than planting a sentinel via `SetEnviron`).

- [x] **Task 1 — Author `src/SessionAgent/Util/EnvSecret.cls` (AC: #1, #2)**
  - [x] Class doc-comment with `///`, naming the FR40/NFR-S2/NFR-S3 contract
  - [x] `Resolve` orchestrator with three-rung ladder; `Try/Catch` around the `Ens.Config.Credentials` open
  - [x] `IsResolvable` predicate
  - [x] `ResolveFromAesStore` `[ Private ]` stub returning `""` with deferral doc-comment
  - [x] Argumentless `Quit` inside any Try/Catch; init return var BEFORE Try
  - [x] No `Storage` section authored

- [x] **Task 2 — Author `src/SessionAgent/Test/EnvSecretTest.cls` (AC: #3)**
  - [x] Extends `%UnitTest.TestCase`; `%OnNew(initvalue)` calls `##super(initvalue)`
  - [x] Eight `Test*` methods per AC-3
  - [x] `OnAfterOneTest` cleans up: Credentials row via `%DeleteId` (env-var cleanup not applicable — no SetEnviron API; tests read OS-set `PATH` instead, no env-var mutation occurs)
  - [x] All assertions via `$$$Assert*` macros
  - [x] File ≤ 500 lines (221 lines)

- [x] **Task 3 — Compile + run via typed MCPs (AC: #4)**
  - [x] `mcp__iris-dev-mcp__iris_doc_compile` for both classes — clean (see Completion Notes)
  - [x] `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.EnvSecretTest` → 8/8 passed
  - [x] `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test` → 35/35 passed (3 audit + 8 envsecret + 9 json + 6 RBAC + 9 retry)

- [x] **Task 4 — Stale-reference + key-leak grep (discipline rule 4 + NFR-S3 spot check)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly" src/SessionAgent/Util/EnvSecret.cls src/SessionAgent/Test/EnvSecretTest.cls` → 0 matches
  - [x] `grep -nE "Write |^ClineDebug" src/SessionAgent/Util/EnvSecret.cls` → 1 match, line 32, inside the never-log invariant docstring (not in code; verified via `^[^/]*\b(Write|\^ClineDebug)\b` pattern → 0 matches in actual code)

## Dev Notes

### Why `%OpenId(systemName, 0)` (concurrency=0)

The Ens.Config.Credentials read is a frequent path during normal LLM operation. Acquiring a row lock per LLM call would serialize all callers. Concurrency=0 (no lock) is the correct read-only access pattern — any concurrent edit by the operator (rare) gets a fresh next-call read. This matches the architecture stance on hot-config-change semantics.

### `IsResolvable` rationale

A future caller (e.g., `Installer.Install` deciding whether to enable an agent) may want to know "is a key resolvable?" without copying the key into a local variable. `IsResolvable` answers without exposure. Implementation is `Quit ..Resolve(pEnv, pCred) '= ""` — yes, internally it does materialize then compare, but the value never escapes the ClassMethod stack frame. Acceptable trade-off; alternative (separately-implemented predicate) would duplicate the ladder logic.

### Test setup/teardown discipline

Each test that mutates env-vars or persistent rows MUST clean up in `OnAfterOneTest`. Use try-around-cleanup so a failed test still runs cleanup. Pattern:

```objectscript
Method OnAfterOneTest() As %Status
{
    Try {
        Do $SYSTEM.Util.SetEnviron("SESSIONAGENT_TEST_KEY", "")
    } Catch {}
    Try {
        Do ##class(Ens.Config.Credentials).%DeleteId("SessionAgentTestCred")
    } Catch {}
    Quit $$$OK
}
```

### Auto-sync workflow + typed MCPs

Same as Stories 2.1/2.2: edit local files, do NOT call `iris_doc_load`. DO call `iris_doc_compile`. Discipline rule 3 prefers typed MCPs.

### No Task-0 backend-surface probe (but DO verify irislib)

`$SYSTEM.Util.GetEnviron`/`SetEnviron` are well-established. `Ens.Config.Credentials.%OpenId` is well-established. The Task 0 step here is a **library source read** (per project rule "IRIS Library Source") to confirm the exact API shapes — NOT a Task-0 probe (which would apply per `research-first.md` only to Epic 12+ stories). The library source read is a one-shot Task-0 step embedded above.

### Constraints (from architecture)

- **Class location:** `src/SessionAgent/Util/EnvSecret.cls` (per [architecture.md:864](../planning-artifacts/architecture.md))
- **Test location:** `src/SessionAgent/Test/EnvSecretTest.cls` (per [architecture.md:897](../planning-artifacts/architecture.md))
- **AES stub:** explicit deferral per architecture line 255 ("custom AES-encrypted store; never in `Config.Agent` row")
- **NFR-S2:** schema discipline — `Config.Agent` stores `EnvVarName` + `CredentialName` only, no `ApiKey`. This story doesn't ship `Config.Agent` (Story 2.4 does) but the `Resolve` interface is shaped so `Config.Agent` can call it directly with no key-handling code

### Sources

- [epics.md:772–796 §"Story 2.3"](../planning-artifacts/epics.md) — AC source.
- [prd.md:556 (FR40), :557 (FR41), :602 (NFR-S2), :603 (NFR-S3)](../planning-artifacts/prd.md) — credential-confinement + resolution motivation.
- [architecture.md:255 (Credential storage row), :864 (file path), :897 (test file path), :1010 (FR40 module path)](../planning-artifacts/architecture.md).
- [`irislib/Ens/Config/Credentials.cls`](../../irislib/Ens/Config/Credentials.cls) — `%OpenId(systemName)` + `.Password` API verification (Task 0 step).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"VSCode Auto-Sync Workflow", §"IRIS Library Source".
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"Available Assertion Macros".
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1–4.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Anthropic Opus 4.7, 1M context) via Claude Code / BMAD `dev-story` skill.

### Debug Log References

(none — implementation was straightforward; one Task 0 finding required spec adaptation, captured below)

### Completion Notes List

**Task 0 — irislib verification (mandatory per project rule §"IRIS Library Source"):**

- `irislib/Ens/Config/Credentials.cls` confirmed:
  - Line 64: `Index SystemName On SystemName [ IdKey, PrimaryKey ]` — `SystemName` is the IdKey, so `%OpenId(<systemName>, ...)` works as expected.
  - Line 18: `Property Password As %CSP.Util.Passwd(...) [ SqlFieldName = PasswordObject ]` — Password is `%CSP.Util.Passwd` with a custom `PasswordGet()` (lines 28-38) that delegates to `%SYS.Ensemble.SecondaryGet`. `%OpenId` is inherited from `%Persistent`; standard signature is `%OpenId(id, concurrency=-1, sc)`, so concurrency=0 is the lock-free read documented in Dev Notes.
  - Line 72: `ClassMethod SetCredential(pName, pUsername, pPassword, pOverwrite=0)` — convenient ClassMethod for tests (used in EnvSecretTest fixtures with `pOverwrite=1`).
  - Empirical round-trip probe: `SetCredential("SessionAgentTestCredProbe","testuser","probe-pwd-456",1)` → SC=1; `%OpenId("SessionAgentTestCredProbe", 0).Password` → `"probe-pwd-456"`; `%DeleteId(...)` → SC=1. **API shapes verified.**

- `irislib/%SYSTEM/Util.cls` finding:
  - Line 86: `ClassMethod GetEnviron(VariableName As %String) As %String` — confirmed.
  - **`SetEnviron` does NOT exist** on this IRIS install. Probe: `$SYSTEM.Util.SetEnviron("X","Y")` → `<METHOD DOES NOT EXIST>` (verified in `iris_execute_command`). `$ZF(-2,name,val)` returns 0 but the value is silently discarded — subsequent `GetEnviron` returns empty. Per Perplexity research summary: env vars are inherited at IRIS process startup; no public IRIS API mutates them visibly within the same process.
  - **Spec adaptation:** the AC-3 tests proposed using `SetEnviron` to plant a sentinel env-var per test. Since that API doesn't exist, tests now read the OS-set `PATH` env-var (always non-empty on a sane test host) as the env-var rung's input. This empirically tests the same code path (the `$SYSTEM.Util.GetEnviron(<non-empty name>)` call returning a non-empty value) without requiring a SetEnviron API. The `OsPathValue` property captures the value at `OnBeforeAllTests` and individual env-var-rung tests assert against the captured fixture. Full rationale documented in the test class doc-comment.

**Compile output (Task 3):**

- `iris_doc_compile SessionAgent.Util.EnvSecret.cls` → success, 10ms.
- `iris_doc_compile SessionAgent.Test.EnvSecretTest.cls` → success, 9ms.

**Test counts (Task 3):**

- `iris_execute_tests SessionAgent.Test.EnvSecretTest` (class level) → **8 / 8 passed, 0 failed, 0 skipped.**
  - AesStoreStubReturnsEmpty (0.299s), CredentialPathResolves (0.427s), EmptyArgsReturnEmpty (0.113s), EnvVarPathResolves (0.223s), EnvVarTakesPrecedenceOverCredential (0.572s), IsResolvablePredicate (1.019s), NothingResolvesReturnsEmpty (0.396s), ResolveDoesNotMutateClineDebug (0.277s).
- `iris_execute_tests SessionAgent.Test` (package level) → **35 / 35 passed.**
  - 3 AuditEmit + 8 EnvSecret + 9 Json + 6 ReadOnlyRole + 9 RetryWithBackoff = 35. Story-spec breakdown said 9/9; verified.

**Task 4 grep results:**

- Stale-reference grep `HSCUSTOMCODE|%SessionAgent_ReadOnly` over both new files → **0 matches.**
- Key-leak grep `Write |^ClineDebug` over `EnvSecret.cls` → 1 match at line 32 inside the never-log invariant docstring; refined regex `^[^/]*\b(Write|\^ClineDebug)\b` (excludes `///` doc lines) → **0 matches in code.** Production class is clean of any Write call or ^ClineDebug mutation.

**Design decisions:**

- Both rung-1 (env-var) and rung-2 (credential) short-circuit on empty argument names — explicitly tested by `TestEmptyArgsReturnEmpty`. This means a caller passing only `pCredentialName` (env-var name = "") gets pure rung-2 behavior, and vice-versa.
- The credential-rung Try/Catch swallows exceptions silently and falls through to rung 3 — per AC-1 (3rd bullet) and the never-log invariant. The `Catch` block sets `tCredValue = ""` rather than re-raising; no exception detail is logged anywhere.
- `IsResolvable` is implemented in terms of `Resolve` rather than walking the ladder twice — accepted trade-off documented in Dev Notes (keeps ladder logic in one place; brief value materialization stays inside the ClassMethod stack frame).
- `ResolveFromAesStore` is `[ Private ]` and returns `""`. Doc-comment names the architecture-line-255 deferral and notes the subclass-override path operators take to opt into AES.

### File List

- `src/SessionAgent/Util/EnvSecret.cls` (NEW, 142 lines)
- `src/SessionAgent/Test/EnvSecretTest.cls` (NEW, 221 lines)

### Change Log

| Date | Author | Change |
|---|---|---|
| 2026-05-03 | Dev (Opus 4.7) | Story 2.3 implementation: `SessionAgent.Util.EnvSecret` three-rung credential resolver + 8-test EnvSecretTest. Task 0 surfaced `$SYSTEM.Util.SetEnviron` does not exist; test strategy adapted to read OS-set `PATH` env-var. All 35 SessionAgent.Test tests passing. Status → review. |
