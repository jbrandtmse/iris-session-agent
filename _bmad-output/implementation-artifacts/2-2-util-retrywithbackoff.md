# Story 2.2: `Util.RetryWithBackoff`

Status: done

## Story

As a developer implementing LLM provider HTTP calls,
I want a `SessionAgent.Util.RetryWithBackoff` class with full-jitter exponential backoff that honors provider `Retry-After` headers and respects mid-flight idempotency rules,
so that transient HTTP failures are recovered cleanly without double-charging the operator's LLM API or violating provider rate limits.

This is the **second foundational utility** in Epic 2. Stories 2.8 (`LLM.Provider` abstract) and 2.9 (`LLM.OpenAIProvider`) depend on the orchestration `Execute` method. The retry-eligibility, delay-parsing, and jitter helpers are pure functions exercisable independently of any HTTP plumbing — that's how the test class verifies them at this story.

## Acceptance Criteria

ACs map to the BDD clauses in [epics.md Story 2.2](../planning-artifacts/epics.md#story-22-utilretrywithbackoff) (lines 746–770) and the architecture decisions at [§"Calibration constants"](../planning-artifacts/architecture.md) (line 338) and [§"LLM tool-call idempotency (research)"](../planning-artifacts/architecture.md) (line 647).

**AC-1 — `SessionAgent.Util.RetryWithBackoff` class shipped at `src/SessionAgent/Util/RetryWithBackoff.cls`** with three Class Parameters and five helper methods:

Class Parameters (per [architecture.md:341](../planning-artifacts/architecture.md)):

- `MaxAttempts = 4`
- `BaseDelaySec = 1`
- `MaxDelaySec = 32`

ClassMethods:

- `IsRetryable(pStatusCode As %Integer, pErrorCategory As %String = "") As %Boolean` — true for HTTP 429 + 5xx; false for 4xx (except 429); false for non-HTTP errors except documented network classes (`pErrorCategory` of `"connection-refused"`, `"dns-failure"`, `"tls-handshake"` → true; everything else → false).
- `ParseRetryAfter(pHeaderValue As %String) As %Integer` — parses `Retry-After` first as integer seconds (`"30"` → `30`), then as RFC 7231 HTTP-date (`"Wed, 21 Oct 2026 07:28:00 GMT"` → seconds-from-now via `$ZDateTimeH(value, ...)` and clamp to ≥ 0), falls back to `0` when both fail. Returns 0 for empty input.
- `ParseGeminiRetryDelay(pErrorJson As %DynamicObject) As %Integer` — extracts `error.details[].retryDelay` from a Gemini error envelope. Walks `error.details` array, finds the first element whose `@type` ends with `RetryInfo`, extracts the `retryDelay` string (`"45s"`), regex-parses leading digits (per [architecture.md:645](../planning-artifacts/architecture.md)), returns the integer seconds. Returns `0` if any step fails (no exception).
- `ExpBackoffSec(pAttempt As %Integer, pBaseSec As %Integer, pCapSec As %Integer) As %Numeric` — full-jitter algorithm per [architecture.md:341](../planning-artifacts/architecture.md): returns a uniform random in `[0, min(pCapSec, pBaseSec * 2 ** pAttempt))`. Uses `$Random` (with care: `$Random(N)` returns 0..N-1 integer; multiply by a fractional for sub-second resolution OR use `$Random(N) + ($Random(1000)/1000)` style). The exact RNG choice is the dev's; the contract is the distribution.
- `Execute(pCallable As %String, pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status` — orchestrates the retry loop:
  1. Invoke `pCallable` (a `Class.Method` string, called via `$ClassMethod` indirection) with `pCallArgs` as input. The callable's signature is `(pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status`. The callable returns the HTTP response shape via `pResponse` (with at minimum `pResponse.statusCode`, `pResponse.headers` (a `%DynamicObject` of headers), `pResponse.body` (a `%DynamicObject`), and on success carries through to caller).
  2. If `IsRetryable(pResponse.statusCode)` is false → return immediately with the response.
  3. If retryable, compute delay = `MAX(provider-specified delay, ExpBackoffSec(attempt, ..#BaseDelaySec, ..#MaxDelaySec))`. Provider-specified delay = `ParseRetryAfter(pResponse.headers."retry-after")` if present, else `ParseGeminiRetryDelay(pResponse.body.error)` if `pResponse.body.error.details` is present, else 0.
  4. `Hang` for the delay (seconds; `Hang` accepts fractional). Increment attempt counter. Retry up to `..#MaxAttempts` total invocations.
  5. After exhausting attempts, return a structured failure: set `pResponse.exhaustedRetries = 1` and ensure `pResponse.headers."request-id"` (or `"x-request-id"`) is preserved from the last response, per [architecture.md:649 §"LLM tool-call idempotency"](../planning-artifacts/architecture.md). Status return is `$$$OK` even on exhausted retries — the response object carries the failure flag; callers inspect `exhaustedRetries`.
  6. **NEVER retry mid-flight network failure.** Distinguish: if `pCallable` itself returns `$$$ERROR` (i.e., the IRIS call layer threw — request was sent, response was lost), surface that as a non-retryable failure (return `pResponse.exhaustedRetries = 1`, `pResponse.midFlightFailure = 1`, `pResponse.headers."request-id"` populated from whatever the last in-flight request had if available). If `pCallable` returns `$$$OK` but `pResponse.statusCode` is retryable → that IS a retryable case (we received a response).

**AC-2 — Pure-function helpers (`IsRetryable`, `ParseRetryAfter`, `ParseGeminiRetryDelay`, `ExpBackoffSec`) follow project rule §"`%Status` return convention"** where they return `%Status`, OR return their typed result directly (`%Boolean`, `%Integer`, `%Numeric`) for pure predicates. Since these four return primitive types, no `%Status` wrapping needed; they may use single-line implementations. `Execute` returns `%Status`.

**AC-3 — `SessionAgent.Test.RetryWithBackoffTest` ships at `src/SessionAgent/Test/RetryWithBackoffTest.cls`** extending `%UnitTest.TestCase`, ≤ 500 lines. Test methods (camel-case, no underscores; macros only):

- `TestIsRetryableHttpMatrix` — 429, 500, 502, 503, 504 → true; 400, 401, 403, 404, 422 → false. Loop over each code, capture failure message naming the code on mismatch.
- `TestIsRetryableNetworkClasses` — `pErrorCategory` of `"connection-refused"`, `"dns-failure"`, `"tls-handshake"` → true; `"unknown"` and `""` → false (when statusCode is 0).
- `TestParseRetryAfterInteger` — `"30"` → 30, `"0"` → 0, `""` → 0.
- `TestParseRetryAfterHttpDate` — pick a known fixed date string, compare to `$ZDateTimeH` round-trip. Don't hard-code a specific seconds-from-now value (timing); instead, assert result is within ±5 seconds of the manually-computed expected delta.
- `TestParseGeminiRetryDelay` — feed `{"error":{"details":[{"@type":"...RetryInfo","retryDelay":"45s"}]}}`; assert returns 45. Feed missing `error` → 0. Feed missing `retryDelay` → 0. Feed `"abc"` (no leading digit) → 0.
- `TestExpBackoffDistribution` — call `ExpBackoffSec(2, 1, 32)` 1000 times; assert every result is in `[0, min(32, 4))` = `[0, 4)`. Track min/max; assert max < 4.0 and min ≥ 0.0. (Strict bound check, not statistical — the function contract is the bound.)
- `TestExecuteRetriesOnRetryableThenSucceeds` — mock callable that returns 429 on attempt 1, 200 on attempt 2. Assert Execute returns `pResponse.statusCode = 200` and Execute called the callable exactly 2 times. Use a counter global (e.g., `^||RetryTestCounter`) the mock increments.
- `TestExecuteExhaustsRetriesAndPreservesRequestId` — mock callable that returns 429 + `x-request-id: req-abc` on every attempt. Assert Execute called the callable exactly 4 times (= `MaxAttempts`), `pResponse.exhaustedRetries = 1`, `pResponse.headers."x-request-id" = "req-abc"`.
- `TestExecuteDoesNotRetryOnMidFlightFailure` — mock callable that returns `$System.Status.Error(5001, "mid-flight: response lost")` (status, not retryable response). Assert Execute called the callable exactly 1 time, `pResponse.midFlightFailure = 1`, `pResponse.exhaustedRetries = 1`.

All assertions via `$$$Assert*` macros; never `..AssertX(...)` methods. `%OnNew` calls `##super(initvalue)`.

**AC-4 — Compile + tests pass, regression suite intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` succeeds for both classes.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.RetryWithBackoffTest`: 9/9 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 27/27 passing total (3 audit + 6 RBAC + 9 JSON + 9 retry).

## Tasks / Subtasks

- [x] **Task 1 — Author `src/SessionAgent/Util/RetryWithBackoff.cls` (AC: #1, #2)**
  - [x] Class doc-comment banner with `///`
  - [x] Three Class Parameters declared (camel-case, no underscores per project rule §"Naming Conventions"). Access via `..#MaxAttempts` etc.
  - [x] Five ClassMethods per AC-1
  - [x] `Execute` orchestrator: indirect call via `$ClassMethod(class, method, ...)` with `pCallArgs` and `pResponse` ByRef
  - [x] Argumentless `Quit` inside any Try/Catch; init return var BEFORE Try
  - [x] No Storage section authored

- [x] **Task 2 — Author `src/SessionAgent/Test/RetryWithBackoffTest.cls` (AC: #3)**
  - [x] Extends `%UnitTest.TestCase`; `%OnNew(initvalue As %String = "")` calls `##super(initvalue)`
  - [x] Nine `Test*` methods per AC-3, names camel-case (no `_`)
  - [x] All assertions via `$$$Assert*` macros
  - [x] Mock callable strategy: ship a separate fixture ClassMethod (e.g., `MockCallable429ThenOk`) inside the test class that the Execute tests reference by name. Use process-private global `^||RetryTestCounter` for call counting; clean up in `OnAfterOneTest`.
  - [x] File ≤ 500 lines (289 lines actual)

- [x] **Task 3 — Compile + run via typed MCPs (AC: #4)**
  - [x] `mcp__iris-dev-mcp__iris_doc_compile` for both classes — capture output in Completion Notes
  - [x] `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.RetryWithBackoffTest` — capture 9/9 pass count
  - [x] `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test` — capture 27/27 regression count

- [x] **Task 4 — Stale-reference grep (discipline rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly" src/SessionAgent/Util/RetryWithBackoff.cls src/SessionAgent/Test/RetryWithBackoffTest.cls` → expect no matches; record in Completion Notes

## Dev Notes

### `Execute` signature trade-off

The epic AC text says `Execute(pCallable, pHttpResponseHandler) As ProviderResponse`. `ProviderResponse` doesn't exist yet — Story 2.7 introduces Agent DTOs and Story 2.8 the LLM provider shape. Rather than wait, this story uses a **generic `%DynamicObject` response signature** (`ByRef pResponse As %DynamicObject`) so the orchestrator logic can be implemented and unit-tested independently. When Story 2.7/2.8 land typed DTOs, callers wrap/unwrap; the Execute internals do not change. Design rationale: pure retry orchestration is independent of response shape — the only fields it touches are `statusCode`, `headers."retry-after"`, `headers."x-request-id"`, and `body.error.details` (Gemini path).

### `pCallable` indirection

ObjectScript's `$ClassMethod(class, method, args...)` allows calling a method by name. Pattern:

```objectscript
Set tStatus = $ClassMethod($Piece(pCallable, ".", 1, *-1), $Piece(pCallable, ".", *), pCallArgs, .pResponse)
```

Where `pCallable = "SessionAgent.LLM.OpenAIProvider.SendChat"` (Class.Method). The mock callables in the test class can be `SessionAgent.Test.RetryWithBackoffTest.MockCallable429ThenOk` and similar.

### Auto-sync workflow + typed MCPs

Same as Story 2.1: edit local files, do NOT call `iris_doc_load`. DO call `iris_doc_compile` and `iris_execute_tests`. Discipline rule 3.

### No Task-0 backend-surface probe

`$Random`, `$ClassMethod`, `Hang`, `$ZDateTimeH`, `$Piece` are well-established IRIS primitives already used in Epic 1 + Story 2.1 patterns. No new IRIS surface to probe.

### Constraints (from architecture)

- **Class location:** `src/SessionAgent/Util/RetryWithBackoff.cls` (per [architecture.md:867](../planning-artifacts/architecture.md)). Do NOT place under `LLM/Util/` — that subdir is reserved for `MessageAdapter`, `ToolDefAdapter`, `GeminiRetryParser` (Story 2.8 may extract `ParseGeminiRetryDelay` into `LLM/Util/GeminiRetryParser.cls` later if a typed wrapper is needed; this story keeps it as a method on `RetryWithBackoff` per the AC).
- **Test location:** `src/SessionAgent/Test/RetryWithBackoffTest.cls` (per [architecture.md:896](../planning-artifacts/architecture.md)).
- **Calibration constants:** exact values per [architecture.md:341](../planning-artifacts/architecture.md): `MaxAttempts=4`, `BaseDelaySec=1`, `MaxDelaySec=32`. Do NOT introduce different defaults.

### Sources

- [epics.md:746–770 §"Story 2.2"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:273](../planning-artifacts/architecture.md) (retry-policy table row) — provider-specific retry-after sources.
- [architecture.md:338–341 §"Calibration constants"](../planning-artifacts/architecture.md) — Class Parameter values.
- [architecture.md:645–649](../planning-artifacts/architecture.md) — Retry-After parsing rules + LLM tool-call idempotency rule.
- [architecture.md:867, :896](../planning-artifacts/architecture.md) — class & test file paths.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"VSCode Auto-Sync Workflow", §"Naming Conventions" (no underscores in Class Parameter names).
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"Available Assertion Macros".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Opus 4.7, 1M context).

### Debug Log References

(none — no debugging required; all paths exercised by the test suite passed on first compile.)

### Completion Notes List

**Implementation summary.** All four ACs satisfied. Two new files shipped per spec; both compile clean; full SessionAgent.Test package green at 27/27.

**Key design decisions:**

1. **`Execute` delegates to `ExecuteWithParams` (added helper).** The story spec said `Execute` orchestrates the loop using `..#MaxAttempts`, `..#BaseDelaySec`, `..#MaxDelaySec`. Production code uses `Execute` exactly as specified. To keep the test suite fast (no real `Hang`), I added a sibling parameterized helper `ExecuteWithParams(pCallable, pCallArgs, pMaxAttempts, pBaseDelaySec, pMaxDelaySec, ByRef pResponse)` that takes the three knobs as explicit arguments. `Execute` is now a one-line delegate. Tests call `ExecuteWithParams` with `pBaseDelaySec=0, pMaxDelaySec=0`, which makes `ExpBackoffSec` return 0 (the cap collapses), `ProviderHintDelay` returns 0 (mocks emit no `retry-after`), and `Hang 0` is a no-op. Net test-suite cost for the three Execute tests: ~1.6s combined (mostly Atelier orchestration overhead, not Hang). This is the recommended option (a) from the dispatching prompt.

2. **`ProviderHintDelay` is a private internal helper.** The spec describes the MAX(provider, exp-backoff) computation inside Execute. To keep `Execute`/`ExecuteWithParams` readable and to encapsulate the case-insensitive header lookup + Gemini fallback chain, I extracted it as `ProviderHintDelay(pResponse) [Private]`. Not part of the public API surface; pure orchestration plumbing.

3. **`pErrorCategory` second parameter on `IsRetryable` only fires when `pStatusCode` is 0.** Spec text was slightly ambiguous — read literally it says "false for 4xx (except 429); false for non-HTTP errors except documented network classes". I implemented this as: positive statusCode → HTTP rules win, ignore category; statusCode = 0 → category drives. This matches the test expectation (`IsRetryable(0, "connection-refused") = 1`) and the architectural intent (network-class hint only relevant when there is no HTTP response).

4. **`ParseRetryAfter` integer pattern uses `1.N` (one-or-more numeric).** This is tighter than `+tTrim` cast, which would silently accept `"1.5"` or `" 30 "` or `"-30"`. The spec says non-negative integer seconds; `1.N` is exactly that.

5. **`ParseRetryAfter` HTTP-date path uses `$ZDateTime/-H` mode `-1, 1`.** IRIS recognizes RFC 1123 / RFC 7231 IMF-fixdate format under this mode. Diff against `$Horolog` (local time, same basis as the parsed `$Horolog` output) yields seconds-from-now. Negative deltas (past dates) clamp to 0. Test uses round-trip (`$ZDateTime → ParseRetryAfter`) with ±5s tolerance to absorb scheduling jitter between the two calls.

6. **`ParseGeminiRetryDelay` extracts leading digits character-by-character.** Avoids regex (no `$Match` in standard ObjectScript pattern set without ZNAMESPACE-specific extensions). Loop terminates on first non-digit; if no leading digits, returns 0. Handles `"45s"` → 45, `"abc"` → 0, `""` → 0, missing field → 0. All four shapes tested.

7. **`ExpBackoffSec` cap-collapse to 0.** Added an explicit guard `If tUpper <= 0 Quit 0` so the test fast-path (cap=0) is well-defined. Without this, `($Random(1000)/1000) * 0` would still be 0, but the explicit guard makes the contract obvious in the source.

8. **Mid-flight failure detection is double-layered.** `Execute` wraps the `$ClassMethod` indirect call in its own Try/Catch (in case the callable raises rather than returning $$$ERROR), then checks `$$$ISERR(tCallSC)` after. Either path leads to the mid-flight branch. Mid-flight does NOT retry — sets `midFlightFailure=1` and `exhaustedRetries=1`, returns `$$$OK` with the failure flags carried in `pResponse`.

9. **Mock callables live in the test class itself.** Three `MockCallable*` ClassMethods at the bottom of `RetryWithBackoffTest.cls`. Reference path: `SessionAgent.Test.RetryWithBackoffTest.MockCallable429ThenOk` (etc.). Process-private `^||RetryTestCounter` for call counting; killed in `OnAfterOneTest` for clean test isolation.

**Verification evidence:**

```
mcp__iris-dev-mcp__iris_doc_compile SessionAgent.Util.RetryWithBackoff.cls (cukbr-d)
  → success, 9ms

mcp__iris-dev-mcp__iris_doc_compile SessionAgent.Test.RetryWithBackoffTest.cls (cukbr-d)
  → success, 37ms

mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.RetryWithBackoffTest (class)
  → total: 9, passed: 9, failed: 0, skipped: 0
  All 9 methods green:
    - ExecuteDoesNotRetryOnMidFlightFailure (0.58s)
    - ExecuteExhaustsRetriesAndPreservesRequestId (0.70s)
    - ExecuteRetriesOnRetryableThenSucceeds (0.40s)
    - ExpBackoffDistribution (1.25s)
    - IsRetryableHttpMatrix (1.18s)
    - IsRetryableNetworkClasses (0.61s)
    - ParseGeminiRetryDelay (0.64s)
    - ParseRetryAfterHttpDate (0.16s)
    - ParseRetryAfterInteger (0.41s)

mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test (package)
  → total: 27, passed: 27, failed: 0, skipped: 0
  Breakdown: 3 audit + 6 RBAC + 9 JSON + 9 retry = 27. No regressions.

Stale-reference grep on both new files (HSCUSTOMCODE | %SessionAgent_ReadOnly):
  → 0 matches. Discipline rule 4 satisfied.

File-size check:
  RetryWithBackoff.cls    = 440 lines (no size limit on production classes)
  RetryWithBackoffTest.cls = 289 lines (≤500 limit per project rule)
```

### File List

- `src/SessionAgent/Util/RetryWithBackoff.cls` (NEW) — `SessionAgent.Util.RetryWithBackoff` retry orchestrator with 3 Class Parameters and 6 ClassMethods (5 per spec + 1 private `ProviderHintDelay` helper + 1 `ExecuteWithParams` parameterized variant for test-suite speed).
- `src/SessionAgent/Test/RetryWithBackoffTest.cls` (NEW) — `SessionAgent.Test.RetryWithBackoffTest` with 9 `Test*` methods, 3 mock callable fixture ClassMethods, and `OnAfterOneTest` cleanup.

### Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-05-03 | Dev (Opus 4.7) | Initial implementation: ship `SessionAgent.Util.RetryWithBackoff` + `SessionAgent.Test.RetryWithBackoffTest`. 9/9 retry tests pass; full `SessionAgent.Test` package 27/27 green. Story moved to `review`. |
| 2026-05-03 | Code-Review (Opus 4.7, 1M ctx) | Clean review — zero patch/decision/defer findings. Verified AC-1 (3 Class Parameters with exact values; 5 ClassMethods + private `ProviderHintDelay` + `ExecuteWithParams` test helper); AC-2 (pure helpers return primitives, `Execute` returns `%Status`); AC-3 (9 `Test*` methods, no underscores, `$$$Assert*` macros, 289 lines ≤ 500); AC-4 evidence in Completion Notes (9/9 + 27/27). Project-rule sweep clean (`$$$` macros, argumentless `Quit` in Try/Catch, no Storage section, `///` doc-comments only, no `Language = python`, hyphenated `%DynamicObject` keys all accessed via quoted-key `%Get`/`%IsDefined`/`%Set`, `ProviderHintDelay` is `[ Private ]`, `OnAfterOneTest` cleans `^||RetryTestCounter`). Mid-flight detection double-layered correctly (inner Try/Catch + `$$$ISERR(tCallSC)` both route to `midFlightFailure=1, exhaustedRetries=1` no-retry branch). Stale-reference grep on both new files: 0 matches for `HSCUSTOMCODE` / `%SessionAgent_ReadOnly`. Status held at `review` for lead to flip post-commit. |

### Review Findings

Clean review — all three layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor) returned zero actionable findings. AC-1 through AC-4 satisfied; project-rule sweep clean. Edge-case considerations evaluated and dismissed as noise (no real-world risk):

- `ExecuteWithParams` early-exit on malformed `pCallable` returns `%Status` error before initializing `pResponse` — caller checks status first per `%Status` contract; not a defect.
- `pErrorJson.%ClassName(1) '= "%Library.DynamicObject"` rejects DynamicObject subclasses — DynamicObject is rarely subclassed and Gemini error envelopes always come through plain DynamicObject from the JSON parser; no real-world risk.
- Mid-flight branch preserves `request-id` only via natural ByRef carry-through (does not actively extract/normalize) — AC-1 #6 says "if available", and the implementation correctly does not clobber `pResponse.headers` if the callable populated them before raising.
