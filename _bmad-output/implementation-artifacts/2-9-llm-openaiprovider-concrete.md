# Story 2.9: `LLM.OpenAIProvider` Concrete

Status: done

## Story

As an Operator-Admin who has configured OpenAI as the active provider,
I want `SessionAgent.LLM.OpenAIProvider` to issue OpenAI Chat Completions API calls per-call-90s-timeout-capped, with full audit logging, retry/backoff on 429+5xx, and credential resolution via the documented ladder,
so that the AgentLoop (Story 2.12) has a working LLM backend that exercises the canonical-wire adapter (FR27) and the provider abstraction (FR28) hardest from day one (per architecture OD4 OpenAI-first ship priority).

This is the **first concrete LLM provider**. Stories 5.1 (Anthropic), 5.2 (Gemini), and 5.3 (OpenAICompat) follow the same pattern. The OpenAIProvider proves the abstract pattern Story 2.8 established + the adapter pattern Story 2.8's MessageAdapter/ToolDefAdapter ship.

## Acceptance Criteria

ACs map to [epics.md Story 2.9](../planning-artifacts/epics.md#story-29-llmopenaiprovider-concrete) (lines 950–983).

**AC-1 — `SessionAgent.LLM.OpenAIProvider` shipped at `src/SessionAgent/LLM/OpenAIProvider.cls`** as a concrete subclass of `SessionAgent.LLM.Provider`:

- `GetEndpointUrl(pConfigAgent As Config.Agent) As %String` — returns `pConfigAgent.EndpointUrl` if non-empty; else `https://api.openai.com/v1/chat/completions`. **NOTE:** the abstract signature on `Provider` is `GetEndpointUrl() As %String` (no parameter); this concrete may either ignore its config dependency by reading from a class-level constant default (and Story 2.12 sets the URL another way) OR override with a parameterized variant. Pick the cleanest path; the AC's intent is "honor `EndpointUrl` if set, fall back to OpenAI default" — the mechanism is the dev's choice. Document.
- `GetAuthHeader(pApiKey As %String) As %String` — returns `"Authorization: Bearer "_pApiKey`.
- `GetProviderName() As %String` — returns `"openai"`.
- `CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As Agent.ProviderResponse) As %Status` — the concrete implementation:
  1. Build OpenAI request body via `MessageAdapter.CanonicalToProvider("openai", pCanonicalHistory)` and `ToolDefAdapter.CanonicalToProvider("openai", pToolDefs)`.
  2. Add `model` (from caller-passed config), `temperature`, `max_tokens`, `messages`, `tools` keys. If `pSystemPrompt '= ""`, prepend `{role:"system", content:pSystemPrompt}` to `messages`.
  3. Issue HTTPS POST via `%Net.HttpRequest`: `Https=1`, `SSLConfiguration="DefaultSSL"`, `Timeout=90` (FR29), `Server="api.openai.com"`, `Location="/v1/chat/completions"`. Set `Authorization` header from `..GetAuthHeader(pApiKey)`. Set `Content-Type: application/json`. Body via `request.EntityBody.Write(payload.%ToJSON())`.
  4. Inspect `request.HttpResponse.StatusCode`. On 200: parse response body via `MessageAdapter.ProviderToCanonical("openai", responseBody)` and populate `pProviderResponse`. Translate `finish_reason`: `stop`→`end_turn`, `length`→`max_tokens`, `tool_calls`→`tool_use`, `content_filter`→`stop_sequence`.
  5. On non-2xx: populate `pProviderResponse.StopReason="error"` and `Content=[{type:text,text:"OpenAI HTTP "_status_": "_responseBody}]`. Return `$$$OK` (envelope-based error surfacing — `Provider.Invoke` audit-emits with `IsError=1`).
  6. **NOTE re. dev choice from Story 2.8**: dev picked design (a) — `Provider.Invoke` calls `..CallMessages` directly, no retry wrapping at the abstract. This story may either: (i) ship `WrappedCallMessages` as a static fixture and route `Invoke` through `RetryWithBackoff.Execute(pCallable="SessionAgent.LLM.OpenAIProvider.WrappedCallMessages", ...)` — requires Story 2.8 `Provider.Invoke` to be updated, OR (ii) handle retries inline inside `CallMessages` by calling `RetryWithBackoff.Execute` directly with the per-attempt closure (tighter to OpenAI specifics). **Pick the cleaner path; document.**

**AC-2 — Request payload contract** (verified by unit test):

- Contains `model`, `messages`, `tools`, `temperature`, `max_tokens` keys.
- Does NOT contain the API key in any field (auth is in the `Authorization` header only).
- Does NOT contain `cache_control` markers (OpenAI auto-caches ≥1024 tokens; no per-call control needed).

**AC-3 — `SessionAgent.Test.OpenAIProviderTest` shipped at `src/SessionAgent/Test/OpenAIProviderTest.cls`** (≤ 500 lines). Test methods (camel-case; `$$$Assert*` macros):

- `TestGetProviderNameReturnsOpenai` — assert `..GetProviderName() = "openai"`.
- `TestGetAuthHeaderFormat` — assert `..GetAuthHeader("sk-abc") = "Authorization: Bearer sk-abc"`.
- `TestBuildPayloadShape` — call a private helper `BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, pConfigAgent) As %DynamicObject` (extracted from `CallMessages` for testability); assert returned object has the 5 required keys + does NOT contain any `apiKey`/`api_key` field + does NOT contain `cache_control`.
- `TestSystemPromptPrependedAsSystemRoleMessage` — assert when `pSystemPrompt = "you are X"`, the `messages[0]` is `{role:"system", content:"you are X"}`.
- `TestCallMessagesWith200Response` — feed a stubbed 200 response (use either: (a) a mock `%Net.HttpRequest` subclass, OR (b) a static-method dependency injection point `OverrideHttpClient` that the test sets to a fixture). Assert `pProviderResponse.Content[0].type = "text"`, `pProviderResponse.StopReason = "end_turn"`.
- `TestCallMessagesWith429TriggersRetryEnvelope` — feed a stubbed 429 response. If the dev's design choice was (i) — outer retry wrapper via `Provider.Invoke` — assert the structured-failure envelope after `MaxAttempts=4`. If choice (ii) — inline retry inside `CallMessages` — assert same envelope. Either is AC-compliant.
- `TestFinishReasonTranslation` — feed responses with `finish_reason` of `stop`, `length`, `tool_calls`, `content_filter`; assert canonical `stopReason` = `end_turn`, `max_tokens`, `tool_use`, `stop_sequence` respectively.
- `TestNoLanguagePythonInClass` — `%Dictionary.MethodDefinition` query asserting no method on `OpenAIProvider` has `Language = "python"` (NFR-C2 schema-level enforcement).

All assertions via `$$$Assert*` macros. `%OnNew(initvalue)` calls `##super(initvalue)`.

**AC-4 — Compile + tests + regression intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` clean for `OpenAIProvider`, `Test.OpenAIProviderTest`.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.OpenAIProviderTest`: 8/8 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 87/87 total (current 79 + 8 OpenAIProvider).
- **NOTE: `TestCallMessagesWith200Response` and `TestCallMessagesWith429TriggersRetryEnvelope` MUST NOT make a real network call.** Use a mock `%Net.HttpRequest` subclass OR stub the HTTP client via a class-level override. If neither is feasible without too much scaffolding, mark these specific tests `[~]` (blocked by mock infrastructure) and defer to Story 2.12's smoke-test infrastructure work. Document.

## Tasks / Subtasks

- [x] **Task 0 — irislib API verification (project rule)**
  - [x] Read `irislib/%Net/HttpRequest.cls` to confirm: (a) `Https`, `SSLConfiguration`, `Timeout`, `Server`, `Location` properties; (b) `EntityBody` write API; (c) `HttpResponse` read API. Captured in Completion Notes.

- [x] **Task 1 — Author `src/SessionAgent/LLM/OpenAIProvider.cls` (AC: #1)**
  - [x] Extends `SessionAgent.LLM.Provider`. Doc-comment names FR27/FR28/FR29 contract + the chosen retry-wrapping design.
  - [x] 4 method overrides + `BuildPayload` helper (extracted for test) + `IssueHttpsPost` (mock seam) + `WrappedCallMessages` removed in final design.
  - [x] No `Storage` section; no `[Language = python]`.
  - [x] Argumentless `Quit` inside any Try/Catch; init return var BEFORE Try.

- [x] **Task 2 — Author `src/SessionAgent/Test/OpenAIProviderTest.cls` (AC: #3)**
  - [x] 8 `Test*` methods per AC-3.
  - [x] All assertions via `$$$Assert*` macros.
  - [x] Mock-HTTP strategy chosen (option C — extract `IssueHttpsPost` + subclass via `SessionAgent.Test.MockOpenAIProvider`). Documented in Completion Notes.
  - [x] File ≤ 500 lines (267 lines including helpers).

- [x] **Task 3 — Compile + run via typed MCPs (AC: #4)**
  - [x] `iris_doc_compile` for both classes (and the test mock helper).
  - [x] `iris_execute_tests SessionAgent.Test.OpenAIProviderTest` → 8/8 passing.
  - [x] Per-class regression sweep → 87/87 total (matches story estimate; the dev's interim 82/82 figure undercounted AuditTest as 3 — actual is 8. Verified empirically by code review re-running `iris_execute_tests SessionAgent.Test.AuditTest` → 8/8 passed). Class-by-class: AgentDtoTest 7, AuditEmitTest 3, AuditTest 8, ChatHistoryTest 9, ConfigAgentTest 10, EnvSecretTest 8, JsonTest 9, MessageAdapterTest 7, ReadOnlyRoleTest 6, RetryWithBackoffTest 9, ToolDefAdapterTest 3, OpenAIProviderTest 8 (NEW).

- [x] **Task 4 — Stale-reference grep (discipline rule 4)**
  - [x] Grep across the three new files for `HSCUSTOMCODE` / `%SessionAgent_ReadOnly` → 0 occurrences in all three.

## Dev Notes

### Mock-HTTP strategy options

**Option A** — subclass `%Net.HttpRequest` to a `MockHttpRequest` test fixture that intercepts `Post()` and returns a canned response. Requires the production `OpenAIProvider.CallMessages` to instantiate the HTTP client through a factory hook (e.g., `..%New().HttpRequestFactory()`).

**Option B** — class-level override: `OpenAIProvider` reads from a class parameter or a process-private global (`^||SessionAgentTestHttpStub`) when set. Test sets the stub before invocation, clears in `OnAfterOneTest`. Simpler but more invasive in production code.

**Option C** — extract the HTTP-issuing logic into a separate `IssueHttpsPost(pBody, pAuthHeader, pTimeout) As %DynamicObject` method that's mockable via the dev's preferred technique. Cleanest separation.

**Pick whichever the dev finds easiest. Document in Completion Notes.** If none feel clean for a reasonable scope, mark `TestCallMessagesWith200Response` and `TestCallMessagesWith429TriggersRetryEnvelope` `[~]` (blocked) and add a Story 2.12 carry-forward note.

### Auto-sync workflow + typed MCPs

Same as previous Epic 2 stories. Discipline rule 3.

### Constraints

- **Class location:** `src/SessionAgent/LLM/OpenAIProvider.cls` (per [architecture.md:810](../planning-artifacts/architecture.md))
- **Test location:** `src/SessionAgent/Test/OpenAIProviderTest.cls` (architecture diagram lumps under `LlmProviderTest.cls` line 882 — naming follows JsonTest convention)
- **HTTPS only**: `Https=1`, `SSLConfiguration="DefaultSSL"`. Operator must have configured SSL config; this is documented in README §Operator Prerequisites.
- **Timeout 90s**: per FR29.

### Sources

- [epics.md:950–983 §"Story 2.9"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:810, :882, :1010 (FR27/FR28)](../planning-artifacts/architecture.md) — module path + provider abstraction surface.
- Story 2.8 `LLM.Provider`, `MessageAdapter`, `ToolDefAdapter` (already shipped).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS Library Source", §"VSCode Auto-Sync Workflow".
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"Available Assertion Macros".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] via the BMAD `bmad-dev-story` workflow.

### Debug Log References

- Initial test run on first implementation showed 5/8 passing; 3 tests
  failing because the original retry design routed through
  `RetryWithBackoff.Execute` via a `WrappedCallMessages` static fixture
  with the instance passed via a `^||SessionAgentOpenAIInstance`
  process-private global — but `^||` does NOT preserve OREFs (verified
  empirically via `Set ^||X=$This Write $IsObject(^||X)` returning 0).
  Refactored to **inline retry loop** inside `CallMessages` calling
  `..IssueHttpsPost` directly (preserving virtual dispatch); now uses
  `RetryWithBackoff` only for the stateless helpers `IsRetryable` /
  `ParseRetryAfter` / `ExpBackoffSec`. All 8/8 tests pass after
  refactor.

### Completion Notes List

**Task 0 — irislib verification (`irislib/%Net/HttpRequest.cls`):**

- `Property EntityBody As %GlobalBinaryStream` (line 426) — write JSON
  payload via `tReq.EntityBody.Write(payloadJson)`.
- `Property Server As %String [ Calculated ]` (line 558) —
  hostname only; the `Host` header is set automatically.
- `Property Location As %String` (line 605) — URL path
  WITHOUT leading `/` per docs but with `/` works in practice.
- `Property Https As %Boolean` (line 631) and
  `Property SSLConfiguration As %String` (line 633) — both required
  for HTTPS.
- `Property Timeout As %Integer [ InitialExpression = 30 ]` (line 665)
  — overridden to 90 per FR29.
- `Property HttpResponse As %Net.HttpResponse` (line 780) — populated
  after `Post()` returns OK.
- `Method Post(location, test, reset)` (line 986) — returns `%Status`.
- `irislib/%Net/HttpResponse.cls`: `StatusCode` (line 27),
  `Data As %RawString` (line 14) — may be a stream or a string.
  `GetHeader(name)` (line 57) reads response headers.

**Design choice 1 — Retry-wrapping (option (ii) inline):** The
production class uses an inline retry loop inside `CallMessages` that
calls `..IssueHttpsPost` directly (virtual dispatch preserved). The
`RetryWithBackoff` orchestrator's `Execute` method dispatches via
`$ClassMethod` against a fully-qualified `Class.Method` string —
incompatible with instance-method virtual dispatch. The original
design tried to back-channel the instance via a process-private global
but `^||` does not preserve OREFs. The inline loop calls the same
stateless helpers (`IsRetryable`, `ParseRetryAfter`, `ExpBackoffSec`)
that `Execute` uses, so the retry SEMANTICS are identical, but the
wire surface is a virtual call on the test-overridable
`IssueHttpsPost`. Three per-instance hooks — `GetMaxAttempts`,
`GetBaseDelaySec`, `GetMaxDelaySec` — let the mock subclass collapse
the `Hang` to zero so the retry-exhaustion test runs in <1s.

**Design choice 2 — Mock-HTTP strategy (option C):** Extracted
`IssueHttpsPost(payloadJson, authHeader, endpointUrl, timeoutSec) As
%DynamicObject` returning `{statusCode, bodyText, headers}`. Test
mock `SessionAgent.Test.MockOpenAIProvider` (separate file) subclasses
`OpenAIProvider` and overrides `IssueHttpsPost` to inject canned
responses. No process-private global mutation, no factory hook, no
real network. The `MockHeaderRetryAfter` property on the mock lets the
429 test confirm the orchestrator's `Retry-After` integration.

**Task 3 verification:**

- Compile via `mcp__iris-dev-mcp__iris_doc_compile` with `cuk-d` flags
  (force recompile) returned `success:true` for all three files (no
  warnings, no errors).
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.OpenAIProviderTest`
  → 8/8 passing on the final implementation.
- Per-class regression sweep across all 12 SessionAgent.Test classes
  totaled 87/87 passing (matches the story-spec estimate). Note: the
  dev's interim figure of 82/82 was a miscount of AuditTest (recorded
  as 3, actual is 8 — confirmed by code-review re-run of
  `iris_execute_tests SessionAgent.Test.AuditTest`); pre-Story-2.9
  count was 79 (not 74), and Story 2.9 added 8 new tests for the
  correct total of 87.
  Class-by-class: AgentDtoTest 7, AuditEmitTest 3, AuditTest 8,
  ChatHistoryTest 9, ConfigAgentTest 10, EnvSecretTest 8, JsonTest 9,
  MessageAdapterTest 7, ReadOnlyRoleTest 6, RetryWithBackoffTest 9,
  ToolDefAdapterTest 3, OpenAIProviderTest 8 (NEW). All passing, no
  regressions.

**Task 4 verification:**

- Grep across all three new files for `HSCUSTOMCODE` and
  `%SessionAgent_ReadOnly` returned 0 matches.

**NFR-S3 never-log review:** The api key is resolved inside
`CallMessages`, cached on the instance `ApiKey` property, used to
build the `Authorization: Bearer <key>` header (passed to
`IssueHttpsPost` as `pAuthHeader`), and the property is cleared back
to `""` in the finally-equivalent path before `CallMessages` returns.
The key never enters: the request body (verified by
`TestBuildPayloadShape` JSON-substring assertions), error envelopes
(`PopulateErrorEnvelope` only takes a `pMsg` string), or any
`^ClineDebug` write (none exist in the file). The
`TestBuildPayloadShape` test asserts the JSON payload contains
neither `"apiKey"`, `"api_key"`, nor `"Bearer"` substrings.

**Note re. abstract `GetEndpointUrl()` signature:** The abstract
`SessionAgent.LLM.Provider.GetEndpointUrl()` is parameterless. The
concrete keeps the parameterless signature and reads the endpoint
from a per-instance `ConfigAgent` property the AgentLoop sets after
construction; this matches the abstract surface and avoids breaking
the polymorphic dispatch contract. Falls back to the OpenAI canonical
URL when `ConfigAgent.EndpointUrl` is empty (the openai-only path —
openai-compatible providers in Story 5.3 will populate the URL).

### File List

- `src/SessionAgent/LLM/OpenAIProvider.cls` (NEW) — concrete
  OpenAI provider with inline retry loop, `BuildPayload` helper,
  `IssueHttpsPost` mock-seam, three retry-param hooks.
- `src/SessionAgent/Test/OpenAIProviderTest.cls` (NEW) — 8 test
  methods covering all AC-3 behaviors.
- `src/SessionAgent/Test/MockOpenAIProvider.cls` (NEW) — test-only
  subclass overriding `IssueHttpsPost` and the retry-param hooks
  (option C mock strategy).
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
  (MODIFIED) — `2-9-llm-openaiprovider-concrete: ready-for-dev` →
  `review`; `last_updated` updated.

### Change Log

| Date       | Change                                                                                              |
|------------|-----------------------------------------------------------------------------------------------------|
| 2026-05-03 | Story 2.9 implemented. OpenAIProvider concrete + 8-test class + Mock test helper. All ACs met.      |
