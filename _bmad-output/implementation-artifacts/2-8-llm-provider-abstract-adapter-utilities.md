# Story 2.8: `LLM.Provider` Abstract + Adapter Utilities

Status: done

## Story

As a developer adding the first concrete LLM provider (Story 2.9),
I want `SessionAgent.LLM.Provider` abstract base class plus `LLM.Util.MessageAdapter` and `LLM.Util.ToolDefAdapter` utility classes that establish the canonical Anthropic wire shape and the adapter pattern,
so that the FR28 "5th-provider extensibility" contract has its plug-in point defined before the first concrete provider lands (Story 2.9).

This story ships **3 NEW classes** + **2 test classes** — the LLM-side trust-boundary surface. Stories 2.9 (`OpenAIProvider`), 5.1 (`AnthropicProvider`), 5.2 (`GeminiProvider`), and 5.3 (`OpenAICompatProvider`) will subclass `Provider` and reuse the adapters for canonical↔provider wire translation.

## Acceptance Criteria

ACs map to [epics.md Story 2.8](../planning-artifacts/epics.md#story-28-llmprovider-abstract--adapter-utilities) (lines 917–948).

**AC-1 — `SessionAgent.LLM.Provider` abstract class shipped at `src/SessionAgent/LLM/Provider.cls`** marked `[Abstract]`. Per project rule §"Abstract Methods in ObjectScript", abstract methods MUST have curly-brace bodies returning the appropriate type:

- `CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As Agent.ProviderResponse) As %Status [ Abstract ]` — body `{ Quit $$$OK }`
- `GetEndpointUrl() As %String [ Abstract ]` — body `{ Quit "" }`
- `GetAuthHeader(pApiKey As %String) As %String [ Abstract ]` — body `{ Quit "" }`
- `GetProviderName() As %String [ Abstract ]` — body `{ Quit "" }`

Plus a non-abstract template method:

- `Invoke(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As Config.Agent, pCallerCtx As Agent.CallerContext, Output pProviderResponse As Agent.ProviderResponse) As %Status` — orchestrates:
  1. Capture start time (`$ZHorolog` in seconds + microseconds for `LatencyMs`).
  2. Resolve API key via `##class(SessionAgent.Util.EnvSecret).Resolve(pConfigAgent.EnvVarName, pConfigAgent.CredentialName)`. If empty, return structured error (set `pProviderResponse.StopReason = "error"`, `pProviderResponse.Content = [{type:text, text:"Credential resolution failed for agent " _ pConfigAgent.AgentName}]`, write `Audit.LlmCall` with `IsError=1`, return `$$$OK`).
  3. Build the `pCallable` string for `Util.RetryWithBackoff.Execute`: `..%ClassName(1) _ ".CallMessages"` — instance-method dispatch wraps as `$ClassMethod` ladder, OR (simpler) define a static-style fixture method `WrappedCallable` that takes `pCallArgs` (a `%DynamicObject` packing all 5 inputs + the API key) and returns `pResponse` (a `%DynamicObject` with `statusCode`, `headers`, `body`). The fixture deserializes args, calls `..CallMessages` (now the concrete subclass), serializes the response. Then `Util.RetryWithBackoff.Execute(...)` is called.
  4. Enforce 90s per-call timeout (FR29) via `%Net.HttpRequest.Timeout=90` set inside the concrete `CallMessages` (documented in this method's doc-comment as a CONCRETE-CLASS responsibility — the abstract template doesn't own HTTP).
  5. Write `Audit.LlmCall` row via `##class(SessionAgent.Audit.Emit).LogLlmCall(...)` with all 11 args (Story 2.5 signature). Include the latency, the cache-hit-tokens (from response usage), error/text fields if `IsError=1`.
  6. Return `pProviderResponse` populated by the concrete via `MessageAdapter.ProviderToCanonical` (concrete may call this before populating `pProviderResponse`).

The class doc-comment explicitly states the FR28 "one new subclass + one registry entry, no shared-infra edits" contract.

**AC-2 — `SessionAgent.LLM.Util.MessageAdapter` shipped at `src/SessionAgent/LLM/Util/MessageAdapter.cls`** with two ClassMethods:

- `CanonicalToProvider(pProviderName As %String, pCanonicalHistory As %DynamicArray) As %DynamicArray` — translates canonical Anthropic-shape history (an array of `{role: "user"|"assistant"|"tool", content: [{type, text|tool_use|tool_result, ...}]}` objects) into the provider's wire shape:
  - **`anthropic`**: passthrough (canonical IS Anthropic).
  - **`openai`**: flatten to OpenAI Chat Completions shape — `{role, content}` for text-only messages; `tool_calls: [{id, type:"function", function:{name, arguments: <stringified-JSON>}}]` for assistant tool_use; `{role:"tool", tool_call_id, content:<JSON or string>}` for tool_result. Critically: `arguments` is a **string** in OpenAI (not an object).
  - **`gemini`**: convert to `{role: "user"|"model", parts: [{text}|{functionCall:{name, args}}|{functionResponse:{name, response}}]}` shape. Map roles: `assistant`→`model`, `tool`→`user` (Gemini doesn't have a separate tool role; tool responses go in `user` parts as `functionResponse`).
  - **`openai-compatible`**: same as `openai`.
  - For unknown `pProviderName`, return passthrough with no transformation.
- `ProviderToCanonical(pProviderName As %String, pProviderResponseRaw As %DynamicObject) As %DynamicObject` — reverse direction: takes the provider's raw response object (the `body` from the HTTP wire) and returns a `%DynamicObject` in the canonical shape: `{role: "assistant", content: [...], stopReason, usage}`. Rules:
  - **`openai`**: extract `choices[0].message.content` (string → wrap in `{type:text, text}`); extract `tool_calls[]` → array of `{type:"tool_use", id, name, input: <%FromJSON of arguments string>}`. Extract `usage.prompt_tokens` → `input_tokens`, `usage.completion_tokens` → `output_tokens`.
  - **`anthropic`**: passthrough (already canonical).
  - **`gemini`**: extract `candidates[0].content.parts[]` and remap each part. `parts[].text` → `{type:text, text}`; `parts[].functionCall` → `{type:tool_use, id:<auto-gen>, name, input:args}`. Map `usageMetadata.promptTokenCount` → `input_tokens`, etc.
  - **`openai-compatible`**: same as `openai`.

Class doc-comment includes the canonical block-types list: `text`, `tool_use`, `tool_result`.

**AC-3 — `SessionAgent.LLM.Util.ToolDefAdapter` shipped at `src/SessionAgent/LLM/Util/ToolDefAdapter.cls`** with one ClassMethod:

- `CanonicalToProvider(pProviderName As %String, pCanonicalToolDefs As %DynamicArray) As %DynamicArray` — converts canonical `{name, description, input_schema}` triples into the provider's expected tool-definition wire shape:
  - **`anthropic`**: passthrough (canonical IS Anthropic).
  - **`openai`**: wrap each tool in `{type:"function", function:{name, description, parameters:<input_schema>}}` per OpenAI Chat Completions spec.
  - **`gemini`**: wrap all tools in a single `{functionDeclarations: [{name, description, parameters:<input_schema>}]}` object per Gemini generateContent spec.
  - **`openai-compatible`**: same as `openai`.

**AC-4 — Test classes ship at:**

- `src/SessionAgent/Test/MessageAdapterTest.cls` (≤ 500 lines) with these `Test*` methods:
  - `TestCanonicalAnthropicPassthrough` — feed canonical history with text + tool_use + tool_result; assert OUTPUT identical to INPUT for anthropic provider.
  - `TestCanonicalToOpenAiToolUseStringifiesArgs` — feed canonical assistant message with `tool_use` block having an OBJECT `input`; assert OpenAI output has `tool_calls[0].function.arguments` as a STRING (not object).
  - `TestCanonicalToGeminiRoleMapping` — feed history with `assistant` and `tool` roles; assert Gemini output has `model` and `user` (with functionResponse parts) respectively.
  - `TestRoundTripOpenAi` — `CanonicalToProvider("openai", canon)` → `ProviderToCanonical("openai", openaiResp)`. Construct an OpenAI-shaped response with `tool_calls`; round-trip; assert canonical block ordering + tool args (object form, parsed back from string) preserved.
  - `TestRoundTripAnthropic` — passthrough both ways.
  - `TestRoundTripGemini` — round-trip preserves text + functionCall semantic.
  - `TestProviderToCanonicalOpenAiUsageMapping` — assert `usage.prompt_tokens` → canonical `input_tokens`.
- `src/SessionAgent/Test/ToolDefAdapterTest.cls` (≤ 500 lines):
  - `TestCanonicalToOpenAiWraps` — feed `[{name, description, input_schema}]`; assert each output element is `{type:"function", function:{name, description, parameters:<input_schema>}}`.
  - `TestCanonicalToGeminiSingleObject` — assert all tools wrapped in ONE `{functionDeclarations:[...]}` object (not per-tool).
  - `TestCanonicalToAnthropicPassthrough` — assert input == output for anthropic.

All assertions via `$$$Assert*` macros. `%OnNew(initvalue)` calls `##super(initvalue)`.

**AC-5 — Compile + tests + regression intact.**

- `mcp__iris-dev-mcp__iris_doc_compile` clean for `LLM.Provider`, `LLM.Util.MessageAdapter`, `LLM.Util.ToolDefAdapter`, `Test.MessageAdapterTest`, `Test.ToolDefAdapterTest`.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.MessageAdapterTest`: 7/7 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.ToolDefAdapterTest`: 3/3 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 79/79 total (current 69 + 7 + 3).

## Tasks / Subtasks

- [x] **Task 1 — Author `src/SessionAgent/LLM/Provider.cls` (AC: #1)**
  - [x] `[Abstract]` class with 4 abstract methods + curly-brace bodies returning appropriate types (`$$$OK`, `""`)
  - [x] `Invoke` template method: API-key resolve → response-shape error envelope on key-missing → call `..CallMessages` (the abstract; concrete fills) → audit-emit at boundary
  - [x] Doc-comment names FR28 contract
  - [x] No Storage section; no `[Language = python]`

- [x] **Task 2 — Author `src/SessionAgent/LLM/Util/MessageAdapter.cls` (AC: #2)**
  - [x] `CanonicalToProvider` with 4-provider switch
  - [x] `ProviderToCanonical` with 4-provider switch
  - [x] Inline doc-comment for canonical block-type list

- [x] **Task 3 — Author `src/SessionAgent/LLM/Util/ToolDefAdapter.cls` (AC: #3)**
  - [x] `CanonicalToProvider` with 4-provider switch (Gemini wraps all in single object)

- [x] **Task 4 — Author `src/SessionAgent/Test/MessageAdapterTest.cls` (AC: #4)**
  - [x] 7 `Test*` methods per AC-4
  - [x] All assertions via `$$$Assert*` macros
  - [x] No persistent rows touched; no cleanup needed
  - [x] File ≤ 500 lines (370 lines)

- [x] **Task 5 — Author `src/SessionAgent/Test/ToolDefAdapterTest.cls` (AC: #4)**
  - [x] 3 `Test*` methods
  - [x] File ≤ 500 lines (135 lines)

- [x] **Task 6 — Compile + run via typed MCPs (AC: #5)**
  - [x] `iris_doc_compile` for the 5 classes — all clean
  - [x] `iris_execute_tests SessionAgent.Test.MessageAdapterTest` → 7/7
  - [x] `iris_execute_tests SessionAgent.Test.ToolDefAdapterTest` → 3/3
  - [x] Per-class regression sweep → 79/79 total

- [x] **Task 7 — Stale-reference grep (discipline rule 4)**
  - [x] Grep for `HSCUSTOMCODE|%SessionAgent_ReadOnly` against `src/SessionAgent/LLM/` + the two new test files → 0 matches

## Dev Notes

### `Provider.Invoke` template method calls the concrete via `..CallMessages`

Standard ObjectScript abstract-method dispatch. Concrete subclass (Story 2.9 `OpenAIProvider`) overrides `CallMessages`. Template method calls `..CallMessages(...)` — virtual dispatch resolves to the concrete. NO need for `$ClassMethod` indirection from the template; that's only needed for the `RetryWithBackoff.Execute` callable path.

### How `Invoke` wraps `CallMessages` in `RetryWithBackoff.Execute`

The cleanest pattern: `Invoke` builds `pCallArgs` (a `%DynamicObject` packing the 5 input args) and passes `pCallable = "<concrete-class-name>.WrappedCallMessages"`. `WrappedCallMessages` is a static fixture method on each concrete subclass that deserializes args + calls `..CallMessages` + packages the HTTP-shape response. Story 2.9 owns `OpenAIProvider.WrappedCallMessages`. Document this contract in `Provider`'s doc-comment so future concretes know the shape.

ALTERNATIVELY (simpler for this story): `Invoke` calls `..CallMessages` directly without retry wrapping; document the retry-wrapping path as Story 2.9's responsibility (since RetryWithBackoff calls a static callable, not an instance method, and the abstract Provider can't easily host the static fixture). **Pick whichever is cleaner.** The AC accepts both per "wraps in `Util.RetryWithBackoff.Execute`" — the wrapping can live in Story 2.9's concrete with a documented hook point.

### Canonical-shape inline doc

Document inside `MessageAdapter`:

```
Canonical (Anthropic) message shape:
  {role: "user"|"assistant"|"tool", content: [<block>...]}
  where <block> is one of:
    {type: "text", text: "..."}
    {type: "tool_use", id: "...", name: "...", input: {...}}
    {type: "tool_result", tool_use_id: "...", content: "..."|[{type:text,text:...}]}
```

### Auto-sync workflow + typed MCPs

Same as previous Epic 2 stories. Discipline rule 3.

### Constraints

- **Class locations:** `src/SessionAgent/LLM/Provider.cls`, `src/SessionAgent/LLM/Util/MessageAdapter.cls`, `src/SessionAgent/LLM/Util/ToolDefAdapter.cls` (per [architecture.md:809–815](../planning-artifacts/architecture.md))
- **Test locations:** `src/SessionAgent/Test/MessageAdapterTest.cls`, `src/SessionAgent/Test/ToolDefAdapterTest.cls` (per [architecture.md:883–884](../planning-artifacts/architecture.md))

### Sources

- [epics.md:917–948 §"Story 2.8"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:113, :809–815](../planning-artifacts/architecture.md) — provider abstraction layout.
- Story 2.2 `Util.RetryWithBackoff` for the retry pattern (already shipped).
- Story 2.3 `Util.EnvSecret` for the API-key resolution (already shipped).
- Story 2.5 `Audit.Emit.LogLlmCall` for the audit-row emit (already shipped, 11-arg signature).
- Story 2.7 `Agent.ProviderResponse`, `Agent.CallerContext` for the typed I/O DTOs (already shipped).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Abstract Methods in ObjectScript".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (dev agent)

### Debug Log References

(none — no `^ClineDebug` traces required)

### Completion Notes List

**Compile (Task 6, AC-5).** All 5 classes compile clean via `iris_doc_compile` against namespace `HSCUSTOM`:
- `SessionAgent.LLM.Provider.cls` — 0.001s
- `SessionAgent.LLM.Util.MessageAdapter.cls` — 0.001s
- `SessionAgent.LLM.Util.ToolDefAdapter.cls` — 0.001s
- `SessionAgent.Test.MessageAdapterTest.cls` — 0.001s
- `SessionAgent.Test.ToolDefAdapterTest.cls` — 0.001s

**One compile-loop iteration on Provider.cls.** First write used object-literal shorthand `{"text": pMsg}` inside `Push()` calls in two helper methods (`PopulateCredentialError`, `PopulateGenericError`); IRIS reported `ERROR #1033: Expected literal` because the shorthand requires literal values, not variables. Fix: replace with explicit `%New() + %Set("text", pMsg) + %Push(tBlock)` pattern. Recompile clean. No second iteration needed.

**Test results (Task 6, AC-5).**
- `iris_execute_tests SessionAgent.Test.MessageAdapterTest` (class level): `total:7, passed:7, failed:0, skipped:0` (CanonicalAnthropicPassthrough, CanonicalToGeminiRoleMapping, CanonicalToOpenAiToolUseStringifiesArgs, ProviderToCanonicalOpenAiUsageMapping, RoundTripAnthropic, RoundTripGemini, RoundTripOpenAi).
- `iris_execute_tests SessionAgent.Test.ToolDefAdapterTest` (class level): `total:3, passed:3, failed:0, skipped:0` (CanonicalToAnthropicPassthrough, CanonicalToGeminiSingleObject, CanonicalToOpenAiWraps).
- Per-class regression sweep across all 11 test classes: AgentDto 7 + AuditEmit 3 + Audit 8 + ChatHistory 9 + ConfigAgent 10 + EnvSecret 8 + Json 9 + ReadOnlyRole 6 + RetryWithBackoff 9 + **MessageAdapter 7 + ToolDefAdapter 3** = **79/79 passing, zero regressions**. (Story spec estimated 69 baseline + 10 new = 79; actual baseline was 68, so the per-class fan-out reads 7 for AgentDtoTest where the spec had it at 6 — the discrepancy is one extra `TurnResultToJsonHandlesUnsetDynamicProps` test that landed in AgentDtoTest after the Story 2.7 spec was authored. Total still hits 79.)

**Stale-reference grep (Task 7, discipline rule 4).** Grep for `HSCUSTOMCODE|%SessionAgent_ReadOnly` against `src/SessionAgent/LLM/` + the two new test files (`MessageAdapterTest.cls`, `ToolDefAdapterTest.cls`) → 0 matches in all three targets.

**Design decisions.**

1. **Retry-wrapping placement → option (a) per Dev Notes.** `Provider.Invoke` calls `..CallMessages` directly via standard ObjectScript virtual dispatch; the `Util.RetryWithBackoff.Execute` wrapping is documented in `Provider`'s class doc-comment as a **CONCRETE-CLASS responsibility** (Story 2.9's `OpenAIProvider` will own its own static `WrappedCallMessages` fixture method that `RetryWithBackoff.Execute` dispatches to via `$ClassMethod`). Rationale: `RetryWithBackoff.Execute` requires a fully-qualified `Class.Method` string and dispatches via `$ClassMethod`, which is fundamentally incompatible with instance-method virtual dispatch from an abstract base. Pushing the static-fixture pattern onto each concrete keeps the abstract minimal (one virtual `CallMessages` method, no static-callable scaffolding) and avoids forcing the abstract to host a method that conceptually belongs to the concrete's HTTP-build code. The class doc-comment names this contract explicitly so Story 2.9 / 5.x dev agents see the expectation when subclassing.

2. **Structured-error envelope, not exception throwing.** Both the credential-missing path and the catch-all path populate `pProviderResponse` with `StopReason="error"` + a single text block carrying the operator-readable error message; `Invoke` always returns `$$$OK`. This decouples the AgentLoop's flow control from try/catch — the AgentLoop checks `StopReason` once and renders the chat-panel error envelope without knowing whether the failure was credential / network / parse / 5xx. Audit row emits with `IsError=1` and the same error text in `ErrorText` (NFR-S4 — never silently swallow audit failures, but also never confuse "missing credential" with "provider 5xx" at the UX layer).

3. **Three internal helper methods on Provider** (`PopulateCredentialError`, `PopulateGenericError`, `ComputeLatencyMs`) carry the cross-cutting envelope-construction so both error paths emit identical shape, and the `[Internal]` keyword signals they are not part of the abstract's plug-in contract — concretes do not override or extend them.

4. **Adapter constants on each adapter class.** Both `MessageAdapter` and `ToolDefAdapter` declare the same four `Parameter PROVIDER*` constants (anthropic / openai / gemini / openai-compatible). Could have been centralized; kept duplicated so each adapter is self-contained and the constant naming matches `Config.Agent.Provider` values 1:1. If a fifth provider lands, both adapters add one constant — that is the FR28 cost (one new entry in the registry + the constants), explicitly accepted in the AC.

5. **Gemini tool_result naming convention.** Canonical `tool_result` carries `tool_use_id` but not the original function name. Gemini's `functionResponse` part requires a `name`. v1 stores the `tool_use_id` value as the `name` field on `functionResponse` — round-trip is locked by `TestCanonicalToGeminiRoleMapping`. Story 5.2 (GeminiProvider concrete) may carry a name-lookup table if Gemini rejects this convention in real wire tests; for now the adapter contract is consistent.

6. **OpenAI tool_calls.arguments STRING contract is locked by two assertions.** `TestCanonicalToOpenAiToolUseStringifiesArgs` directly asserts the forward-direction stringification (using `'$IsObject(tArgs)`); `TestRoundTripOpenAi` asserts the reverse direction parses the string back into an object. Both fail loudly if a future "optimization" replaces the `%ToJSON` call with passthrough.

### File List

- `src/SessionAgent/LLM/Provider.cls` (NEW) — `[Abstract]` base; 4 abstract methods (`CallMessages`, `GetEndpointUrl`, `GetAuthHeader`, `GetProviderName`) + non-abstract `Invoke` template + 3 internal helpers (`PopulateCredentialError`, `PopulateGenericError`, `ComputeLatencyMs`); 287 lines.
- `src/SessionAgent/LLM/Util/MessageAdapter.cls` (NEW) — 4-provider canonical↔provider message-history translation; public `CanonicalToProvider` + `ProviderToCanonical`; 4 internal per-provider helpers (`CanonicalToOpenAi`, `OpenAiToCanonical`, `CanonicalToGemini`, `GeminiToCanonical`) + 2 finish-reason mappers; 384 lines.
- `src/SessionAgent/LLM/Util/ToolDefAdapter.cls` (NEW) — 4-provider canonical→provider tool-definition translation; public `CanonicalToProvider`; 2 internal per-provider helpers (`CanonicalToOpenAi`, `CanonicalToGemini`); 117 lines.
- `src/SessionAgent/Test/MessageAdapterTest.cls` (NEW) — 7 `Test*` methods + 1 internal helper (`BuildMixedCanonicalHistory`); 370 lines.
- `src/SessionAgent/Test/ToolDefAdapterTest.cls` (NEW) — 3 `Test*` methods + 1 internal helper (`BuildTwoToolDefs`); 135 lines.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED) — `2-8-llm-provider-abstract-adapter-utilities: ready-for-dev` → `in-progress` → `review`; `last_updated` field bumped.
- `_bmad-output/implementation-artifacts/2-8-llm-provider-abstract-adapter-utilities.md` (MODIFIED) — Status flip; Tasks/Subtasks all `[x]`; Dev Agent Record sections filled; Change Log entry added.

### Change Log

| Date | Author | Change |
|---|---|---|
| 2026-05-03 | dev (claude-opus-4-7[1m]) | Initial implementation: 3 LLM-layer classes (`Provider` abstract + `MessageAdapter` + `ToolDefAdapter`) + 2 test classes (10 `Test*` methods total). All 5 classes compile clean; 7/7 + 3/3 new tests pass first run after one object-literal-shorthand compile fix on `Provider.cls`; 79/79 total package tests pass per-class fan-out (zero regressions across the 9 prior test classes). Status set to review. Retry-wrapping placement decision: option (a) — `Invoke` calls `..CallMessages` directly; `RetryWithBackoff.Execute` wrapping is documented as a Story 2.9 concrete-class responsibility via static `WrappedCallMessages` fixture. |
