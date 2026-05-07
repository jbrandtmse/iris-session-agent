# Story 9.4: `AgentLoop` Integration — First-User-Message Prefix Injection

Status: done

## Story

As an Operator using the Search Agent,
I want my first message in each conversation prefixed with my personal vocabulary digest (Story 9.3) — placed in the *uncached* user-message segment per architecture §"Vocabulary digest in *uncached* first-user-message prefix" — so that Anthropic prompt-cache hit rate is preserved (the cached `system + tools` prefix remains stable across turns) while my vocabulary still influences the agent's reasoning (NFR-P6, FR24).

**Story 9.3 substrate this story builds on:** `SessionAgent.Search.VocabularyDigest.Build(pPortalUser)` returns a Markdown digest string (top-N user aliases by Confidence ≥ 0.3 with seed-vocabulary fallback for first-time users). Story 9.4 wires that digest into the AgentLoop's first-user-message path.

**Story 9.5 consumer note:** This story closes the AgentLoop side; Story 9.5 ships the `RecordClickThrough` ZenMethod stub that Epic 10's UI will call to populate `UserVocabulary`. Both pre-conditions must be in place before Epic 10 dispatches.

## Acceptance Criteria

**AC-1 — First-turn detection guard.** Edit [`src/SessionAgent/Agent/AgentLoop.cls`](../../src/SessionAgent/Agent/AgentLoop.cls) `RunTurn` ClassMethod: between the existing Step 4 ("Append user message to TurnsJson") body — specifically AFTER `Set tTurns = ..LoadTurns(tHist)` (line ~180) and BEFORE the `Set tUserTurn = ##class(%DynamicObject).%New()` user-block construction (line ~181) — insert the digest-injection guard:

1. **Search-agent guard:** if `pAgentName '= "message-search"` skip everything below (no digest for inspection-agent or any other agent name). Inspection-agent behavior remains unchanged from Story 2.12 / Story 4.x.
2. **First-turn guard:** if `tTurns.%Size() > 0` (any prior turns exist on this conversation), skip — the digest is first-turn-only.
3. **If both guards pass:** call `Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(pPortalUser)`. Prepend the digest to the local `pUserText` variable using a clear delimiter — recommended: `Set tInjectedUserText = tDigest _ $Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10) _ "User: " _ pUserText`. Use `tInjectedUserText` (NOT `pUserText`) for the `tUserBlock.%Set("text", ...)` call below, so the canonical `pUserText` remains the original operator input for downstream handling (audit, ChatHistory persistence — see AC-2).

**AC-2 — `pUserText` vs `tInjectedUserText` separation.** The persisted `Chat.Turn.UserText` and the audit-row `Tool.Call.UserText` (or whatever the persistence layer captures) MUST keep the original operator-typed text (`pUserText`) — NOT the digest-prefixed form. Only the LLM-bound `tUserBlock.text` carries the prefix. Rationale: the digest is a per-turn provider-bound contextual payload; persisting it on chat-history would cause the digest to be re-injected on every replay AND would balloon storage. The current AgentLoop persistence path saves the canonical `tTurns` array (which includes `tUserBlock.text`) — so the AgentLoop's `tUserBlock.%Set("text", tInjectedUserText)` MUST be paired with one of: (a) a separate `tUserTurnPersist` block carrying `pUserText` that gets pushed to a parallel `tTurnsForPersistence` array, OR (b) a post-LLM strip step that removes the digest prefix from the persisted `tUserBlock.text`. Choose (a) as the cleaner pattern: maintain TWO push paths — `tTurnsForLlm` (the array sent to the provider) carries the digest-prefixed text; `tTurns` (the array persisted to `Chat.History.TurnsJson`) carries the canonical text. Both push the user turn at the same step — only the `text` field differs.

**Implementation hint:** simplest implementation is to construct `tUserBlockPersist` (canonical `pUserText`) and `tUserBlockLlm` (`tInjectedUserText`) as TWO separate `%DynamicObject`s; push the persist version to `tTurns` (Step 4 existing body), push the LLM version to a NEW local `tTurnsForLlm` array that is initialized as a deep clone of `tTurns` UP TO THE USER TURN, then receives `tUserBlockLlm` as its final element. Subsequent provider calls (Step 7+) use `tTurnsForLlm`; persistence (Step 9+ `..PersistTurns`) uses `tTurns`. **Document this two-array invariant in the AgentLoop class doc-comment** so future devs don't re-merge the paths.

If implementation (a) requires too much surgery on the existing AgentLoop body, fall back to (b) — strip the digest prefix from `tUserBlock.text` AFTER the provider call returns and BEFORE `..PersistTurns(tHist, tTurns)`. Use a sentinel-based approach: prepend a marker like `\x00\x00DIGEST\x00\x00` at digest construction time and strip it before persist. The (a) two-array invariant is preferred for code-clarity even if it adds ~10 lines.

**AC-3 — Anthropic prompt-cache preservation test.** Author or extend `src/SessionAgent/Test/AgentLoopVocabDigestTest.cls` (`%UnitTest.TestCase` subclass — fresh class for Story 9.4 to keep `AgentLoopGuardsTest` from inflating further). Required tests:

| Test method | What it asserts |
|---|---|
| `TestSearchAgentFirstTurnReceivesDigest` | Mock or stub `VocabularyDigest.Build("sa-test-94-power")` to return a fixed canned-digest string; invoke `RunTurn("message-search", "sa-test-94-key", "sa-test-94-power", "find me failed admits")`; capture the LLM-bound user-block text via instrumentation (test-mode global, e.g., `^||SessionAgent.AgentLoopTest.LastUserText`). Assert it CONTAINS the canned-digest AND CONTAINS `"User: find me failed admits"` AND CONTAINS the `---` delimiter. |
| `TestSearchAgentSecondTurnDoesNotReinjectDigest` | Continue the same conversation (same SessionKey + PortalUser) for a second `RunTurn` call. Assert the second turn's LLM-bound user-block does NOT contain the canned-digest or `---` delimiter — only the raw `pUserText`. |
| `TestInspectionAgentDoesNotReceiveDigest` | Invoke `RunTurn("session-inspection", "sa-test-94-insp-key", "sa-test-94-power", "what happened")`. Assert the LLM-bound user-block contains ONLY the raw `pUserText` — no digest, no delimiter. |
| `TestPersistedTurnsJsonContainsCanonicalUserText` | After `TestSearchAgentFirstTurnReceivesDigest` runs, load the persisted `Chat.History.TurnsJson` for `(message-search, sa-test-94-key, sa-test-94-power)`; assert the user turn's `text` field matches `pUserText` (`"find me failed admits"`) — NOT the digest-prefixed form. This validates the AC-2 two-array invariant. |
| `TestEmptyDigestStillWiresThrough` | Stub `VocabularyDigest.Build` to return `""`; invoke `RunTurn` for a search-agent first turn; assert the LLM-bound user-block is just `"User: <pUserText>"` (no orphan delimiter or empty-digest leading whitespace). The empty-digest edge case must not break the wiring. |

**AC-4 — Anthropic prompt-cache hit-rate preservation (NFR-P6).** Author one integration test that verifies the cached `system + tools` prefix is bit-identical across turns 1 and 2 of a search-agent conversation. The test:

1. Sets `Config.Agent.message-search.Provider = "anthropic"` (preserve the original via setUp/tearDown).
2. Invokes `RunTurn` twice in succession with the same SessionKey + PortalUser.
3. Captures the provider-bound `system` string + `tools` JSON for each turn via instrumentation.
4. Asserts `$Length(tSystem1) = $Length(tSystem2)` AND `tSystem1 = tSystem2` AND the SHA1 hash of `tTools1.%ToJSON() = tTools2.%ToJSON()`.

If the live Anthropic credential is not resolvable on the dev install, the test SKIPS gracefully (per Rule 11 conformance) — but the structural test (cached-prefix equality) runs against the mock provider regardless. The cached-prefix structural test MUST pass even without a live Anthropic credential; the live-credential-only assertion is the bonus `Audit.LlmCall.CacheHitTokens > 0` check on the second turn. Test name: `TestAnthropicCachedPrefixUnchangedAcrossTurns`.

**AC-5 — Verification battery (Rule 6).**
- `SessionAgent.Agent.AgentLoop` compiles cleanly via `iris_doc_compile`.
- `SessionAgent.Test.AgentLoopVocabDigestTest` compiles cleanly; new test methods PASS via `iris_execute_tests` per-class form (5 + 1 = 6 methods).
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests`. SQL ground-truth probe via canonical numerical-MAX form. Capture verbatim Total/Passed/Failed.
- Expected baseline: **352 (Story 9.3 close) + 6 new AgentLoopVocabDigestTest methods = 358**. Land at 358/358 PASS.
- Two existing regression-guard checks: `AgentLoopGuardsTest` and `ToolCallRoundtripIntegrationTest` MUST still pass — those classes don't touch the new code path but they DO exercise the modified `RunTurn`. Confirm via SQL probe.

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight backend-surface probe (Rule 4 + research-first.md §"Task 0 backend-surface probe")**
  - [x] Confirm `SessionAgent.Search.VocabularyDigest.Build` is callable: `iris_execute_classmethod` against `Build("sa-test-94-noinit-novel")` — expected: seed-fallback Markdown digest. (Verifies Story 9.3 substrate works AND that Build doesn't throw on a never-seen user.) — **Result:** `## Common idioms (no personal aliases yet)` + 5 seed rows; substrate confirmed.
  - [x] Read `src/SessionAgent/Agent/AgentLoop.cls` lines 92–230 fully (Step 4 region) so the surgery point is precise. The user-block construction lives at lines ~180–189; the digest-injection guard inserts BEFORE that block.
  - [x] Stale-reference scan per Rule 4: `grep -rn "VocabularyDigest\|first.user.message\|prompt.cache" src/ docs/ _bmad-output/` — confirm only architecture / epics / Story 9.0–9.3 references exist; no production callers yet. **Result:** clean — only architecture / Story 9.x references.

- [x] **Task 1 — `RunTurn` digest-injection wiring (AC: #1, #2)**
  - [x] Insert the search-agent + first-turn guard logic between `LoadTurns` and `tUserTurn` construction.
  - [x] Implement the two-array pattern (option a): build `tUserBlockPersist` (canonical) and `tUserBlockLlm` (digest-prefixed); push the persist version to `tTurns`; build a parallel `tTurnsForLlm` for the provider call.
  - [x] Document the two-array invariant in the `RunTurn` doc-comment (class-level doc-comment §"Two-array invariant").
  - [x] Compile via `iris_doc_compile` — clean compile.

- [x] **Task 2 — Test class authoring (AC: #3, #4)**
  - [x] Author `src/SessionAgent/Test/AgentLoopVocabDigestTest.cls` with 5 AC-3 tests + 1 AC-4 test.
  - [x] Author `src/SessionAgent/Test/VocabDigestCaptureMock.cls` — extends `AgentLoopMockProvider`, captures user-block text + system prompt + tools JSON into PPGs before delegating to `##super`.
  - [x] Test isolation: `PortalUser` prefix `sa-test-94-` for all test-created rows + Chat.History rows; cleanup pattern uses `LIKE 'sa-test-9%'`.
  - [x] Compile + run — all 6 methods pass.

- [x] **Task 3 — Verification battery (AC: #5)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via canonical numerical-MAX SQL probe.
  - [x] SQL ground-truth probe via canonical numerical-MAX form. **Verbatim Total/Passed/Failed: 358 / 358 / 0.**
  - [x] Expected: 358/358 PASS (352 baseline + 6 new) — landed at 358/358.
  - [x] Confirm `AgentLoopGuardsTest` (9/9) + `ToolCallRoundtripIntegrationTest` (4/4) + `AgentLoopTest` (3/3) still PASS.

- [x] **Task 4 — Story sign-off (Rule 2)**
  - [x] Re-read each AC; confirm Completion Notes contain the verbatim evidence shape matching each "Then ..." clause.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~190–200 lines. Within the cap.

### Rule 3 typed-MCP-first

- `iris_doc_compile` for class compilation.
- `iris_execute_classmethod` for `Build` and `RunTurn` sanity invocations.
- `iris_execute_tests` for `AgentLoopVocabDigestTest` per-class run.
- `iris_sql_execute` for SQL ground-truth probe + Chat.History persistence verification (AC-3 `TestPersistedTurnsJsonContainsCanonicalUserText`).

### Rule 8 / Rule 9 — no carry-forward bindings to address

`grep -i "Story 9\.4" deferred-work.md` returns no entries. Nothing to incorporate.

### Rule 10 — no external defaults set

The digest-prefix delimiter (`---`), the `User: ` prefix, the search-agent name string (`message-search`) are all internal naming choices already locked in by prior stories — not external defaults. Rule 10 does not apply.

### Rule 12 — content-correctness evidence form

The digest-injected user message is consumed by the LLM, not rendered to a UI surface in this story (the rendered UI ships in Epic 10). Story 9.3's `TestVocabularyDigestRowFormatExact` already verifies the digest's rendered shape; Story 9.4 verifies the WIRING (digest → user-block.text), not re-rendering. Capture the AC-3 `TestSearchAgentFirstTurnReceivesDigest` instrumentation output verbatim in Completion Notes — that's the Rule 12 content-correctness evidence shape for this story.

### Two-array invariant (AC-2) — why this matters

Without the two-array separation, the digest gets persisted to `Chat.History.TurnsJson` and re-injected on every replay (because `LoadTurns` reads the persisted text — which now contains the digest). On turn 2, `LoadTurns` returns `[{role:user, text: <digest-prefixed turn-1>}]`, the first-turn guard sees `%Size() > 0` and skips digest injection (correct), BUT the provider call sees turn 1's text bloated with the digest (wrong — it should be the canonical user text + the new turn 2's potential digest). The two-array pattern keeps `tTurns` (persisted, canonical) clean and constructs `tTurnsForLlm` fresh per turn (digest applied once at first turn).

### Anthropic prompt-cache preservation (AC-4)

Per architecture NFR-P6: Anthropic's prompt-cache hashes the `system + tools` prefix; cache hits require bit-identical bytes. Placing the digest in `messages[0].content[0].text` (the user-message segment) keeps `system + tools` stable. The AC-4 test asserts:

- `tSystem1 = tSystem2` (string equality on the system prompt).
- `tTools1.%ToJSON() = tTools2.%ToJSON()` (JSON-canonical equality on the tools array).

If the AnthropicProvider's `BuildPayload` mutates the system/tools between calls (e.g., timestamp injection, dynamic tool filtering), THAT'S a separate bug — flag it inline and either fix-now or escalate to the user. The expected behavior per Story 5.1's review is that `system + tools` is structurally stable across turns.

### Stub provider pattern for AC-3 / AC-4

The cleanest stub pattern uses a class-level `^||SessionAgent.AgentLoopTest.*` PPG that the test class sets before invoking `RunTurn`, the AgentLoop checks for, and uses a mock `Provider.Invoke` that captures inputs + returns canned output. The existing `Agent.ProviderOverride` singleton (if it exists) is the canonical pattern. If it does not exist, build a minimal version inline in this story's test class — do NOT spend the budget refactoring. The dev SHOULD review `src/SessionAgent/Test/MockOpenAIProvider.cls` (Story 2.12 / 5.4) for the existing mock pattern and extend it.

### `Chat.History.TurnsJson` persistence verification (AC-3 row 4)

Use `iris_sql_execute` after the test runs:

```sql
SELECT %EXACT(TurnsJson) FROM SessionAgent_Chat.History
WHERE %EXACT(AgentName) = 'message-search'
  AND %EXACT(SessionKey) = 'sa-test-94-key'
  AND %EXACT(PortalUser) = 'sa-test-94-power'
```

Parse the returned JSON and assert the user turn's text is the canonical `pUserText`, not the digest-prefixed form.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m]

### Completion Notes

**Design decisions:**

- **Two-array pattern (option a, per spec preference)** chosen over option b (strip-before-persist). Diff size was small enough that maintaining `tTurnsForLlm` as a parallel array did not require invasive surgery. Implementation:
  - `tInjectDigest` boolean flag set on the search-agent + first-turn guard branch.
  - When `tInjectDigest = 0`, `tTurnsForLlm = tTurns` (alias — same OREF, zero overhead).
  - When `tInjectDigest = 1`, `tTurnsForLlm` is a fresh `%DynamicArray` containing only the digest-prefixed user turn. The shared-OREF discipline for assistant + tool_result turns lands them in BOTH arrays only when the flag is set; otherwise the dual-push is suppressed (prevents double-write to the same array when the OREFs are aliased).
- **Empty-digest edge case (AC-3 row 5):** `If tDigest '= ""` branches the construction — full digest+delimiter when non-empty; just `"User: "+pUserText` when empty. `tInjectDigest = 1` is set unconditionally inside the guard so the two-array machinery wires through regardless (preserves the AC-2 invariant on the empty-digest path).
- **Test class strategy:** new `AgentLoopVocabDigestTest` class extends `%UnitTest.TestCase` directly (not `AgentLoopTestBase`) because the Story 9.4 prefix (`sa-test-94-`) and the message-search Config.Agent row management (Enabled=1, Provider mutation for AC-4) differ from the base class's `al-test` / inspection-only setup. Self-contained class is ~330 lines; copying the pattern was cleaner than forking a generalized base.
- **Capture mock strategy:** `VocabDigestCaptureMock` extends the existing `AgentLoopMockProvider` and overrides `Invoke` to stash three PPGs (`^||SessionAgentVocabDigestCapture`, `^||SessionAgentVocabDigestCaptureSystem`, `^||SessionAgentVocabDigestCaptureTools`) before delegating via `##super`. Mirrors the `SystemPromptCaptureMock` pattern from Story 3.5 for OREF-identity-safe mock instrumentation across the per-turn `InstantiateProvider` re-construction.
- **AC-4 cached-prefix invariant:** captured on `Invoke` — `pSystemPrompt` (string) and `pToolDefs.%ToJSON()` (JSON canonical). The `ProviderOverride.GetOverride()` short-circuits the production provider switch in `InstantiateProvider`, so `Provider="anthropic"` only affects the `tCacheCfg` flags emitted by the AgentLoop; the actual provider OREF is the mock. The AC-4 contract is preserved: the same `system` and `tools` reach the captured payload across both turns 1 and 2 — byte-identical, asserting the cached prefix is unchanged.

**AC verbatim evidence:**

**AC-1 (digest-injection guard):** Implemented at `src/SessionAgent/Agent/AgentLoop.cls` lines 211–239 (Step 4, between `LoadTurns(tHist)` at line 209 and the canonical user-turn construction at lines 244–252). Guards: `(pAgentName = "message-search") && (tTurns.%Size() = 0)`. Delimiter: `tDigest _ $Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10) _ "User: " _ pUserText` matches spec verbatim.

**AC-2 (two-array invariant) — verbatim SQL probe of `Chat.History.TurnsJson`:**

```
PERSISTED_USER_TEXT={find me failed admits} | TURNS_COUNT=2 | FULL_BLOB=[{"role":"user","content":[{"type":"text","text":"find me failed admits"}]},{"role":"assistant","content":[{"type":"text","text":"Evidence ack."}]}]
```

Persisted user turn's `text` field equals canonical `pUserText` (`"find me failed admits"`) — NOT the digest-prefixed form. No `## Common idioms` header, no `---` delimiter, no `User: ` prefix in the persisted blob. Two-array invariant validated empirically.

**AC-3 (5 test methods) — per-method PASS roster from canonical numerical-MAX SQL probe:**

| Method | Status |
|---|---|
| `TestAnthropicCachedPrefixUnchangedAcrossTurns` | 1 (PASS) |
| `TestEmptyDigestStillWiresThrough` | 1 (PASS) |
| `TestInspectionAgentDoesNotReceiveDigest` | 1 (PASS) |
| `TestPersistedTurnsJsonContainsCanonicalUserText` | 1 (PASS) |
| `TestSearchAgentFirstTurnReceivesDigest` | 1 (PASS) |
| `TestSearchAgentSecondTurnDoesNotReinjectDigest` | 1 (PASS) |

**AC-4 (Anthropic prompt-cache preservation):** `TestAnthropicCachedPrefixUnchangedAcrossTurns` PASS. The test mutates `Config.Agent.message-search.Provider = "anthropic"` (restored by OnAfter), invokes `RunTurn` twice with the same SessionKey + PortalUser, captures `pSystemPrompt` and `pToolDefs.%ToJSON()` per turn, and asserts: `$Length(tSystem1) = $Length(tSystem2)` AND `tSystem1 = tSystem2` AND `$Length(tTools1) = $Length(tTools2)` AND `tTools1 = tTools2`. All 6 assertions pass — the cached prefix is byte-identical across turns. Live Anthropic credential not required (per Rule 11 graceful skip — structural assertion runs unconditionally against the mock).

**AC-5 (Verification battery) — verbatim SQL probe of `%UnitTest_Result.TestMethod`:**

```
Total / Passed / Failed = 358 / 358 / 0
```

Per-class breakdown for the four AgentLoop-touching classes:

| Cls | Total | Passed | Failed |
|---|---|---|---|
| SessionAgent.Test.AgentLoopGuardsTest | 9 | 9 | 0 |
| SessionAgent.Test.AgentLoopTest | 3 | 3 | 0 |
| SessionAgent.Test.AgentLoopVocabDigestTest | 6 | 6 | 0 |
| SessionAgent.Test.ToolCallRoundtripIntegrationTest | 4 | 4 | 0 |

Pre-state baseline (Story 9.3 close): 352. Post-state: 358 (= 352 + 6 new). Reconciliation matches.

**Files modified or created:**

- **Modified:** `src/SessionAgent/Agent/AgentLoop.cls` — class doc-comment §"Two-array invariant" added; `RunTurn` Step 4 expanded with digest-injection guard + two-array fork; Step 7 provider invocation reads `tTurnsForLlm`; assistant-turn and tool_result-turn pushes mirror to `tTurnsForLlm` only when `tInjectDigest = 1`.
- **Created:** `src/SessionAgent/Test/AgentLoopVocabDigestTest.cls` — 6 test methods (5 AC-3 + 1 AC-4) plus OnBefore/OnAfter teardown wiring for both message-search and session-inspection Config.Agent rows.
- **Created:** `src/SessionAgent/Test/VocabDigestCaptureMock.cls` — capture-and-delegate mock provider extending `SessionAgent.Test.AgentLoopMockProvider`.

### File List

- src/SessionAgent/Agent/AgentLoop.cls (modified)
- src/SessionAgent/Test/AgentLoopVocabDigestTest.cls (created)
- src/SessionAgent/Test/VocabDigestCaptureMock.cls (created)
- _bmad-output/implementation-artifacts/9-4-agentloop-integration-first-user-message-prefix-injection.md (modified — Tasks/Subtasks checkboxes, Dev Agent Record, File List, Change Log, Status)

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted from epics.md Story 9.4 + architecture §"Vocabulary digest in *uncached* first-user-message prefix" + Story 9.3 substrate (`VocabularyDigest.Build` ships) | Lead |
| 2026-05-07 | 1.0 | Story 9.4 implementation complete — two-array invariant (option a) wired into AgentLoop Step 4 / Step 7; AgentLoopVocabDigestTest (6 methods) + VocabDigestCaptureMock created; 358/358 regression pass (352 baseline + 6 new) | Dev |
| 2026-05-07 | 1.1 | Code review complete — clean (zero HIGH / MEDIUM / LOW findings, five dismissed observations). Status flipped to done. | Reviewer |

### Review Findings

Clean review — all three layers (Blind Hunter / Edge Case Hunter / Acceptance Auditor) returned zero actionable findings.

**Verification points confirmed against the lead's specific concerns:**

- AC-1 placement verified at `src/SessionAgent/Agent/AgentLoop.cls` lines 211–239 (between `LoadTurns` at line 209 and the canonical user-turn construction at line 244). Search-agent guard literal `pAgentName = "message-search"`, first-turn guard `tTurns.%Size() = 0`, delimiter `tDigest _ $Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10) _ "User: " _ pUserText` — semantically identical to the spec's `$Char(10)*2` form.
- AC-2 two-array invariant verified: `tTurns` carries canonical `pUserText` (line 252 push); `tTurnsForLlm` carries digest-prefixed text (line 282 push under `tInjectDigest=1` branch). When `tInjectDigest=0`, `tTurnsForLlm = tTurns` (line 264 — OREF aliased; provider sees canonical text on non-digest paths). Doc-comment on `RunTurn` documents the invariant at lines 33–60.
- OREF-aliasing dual-push correctness verified: assistant-turn push at lines 400–406 — `tTurns.%Push(tAssistantTurn)` always; `tTurnsForLlm.%Push(tAssistantTurn)` only when `tInjectDigest=1`. When arrays alias (`tInjectDigest=0`), the second push is correctly suppressed — no double-write to the shared OREF. When arrays diverge (`tInjectDigest=1`), both arrays receive the same `tAssistantTurn` OREF — harmless aliasing because nothing mutates the turn after push. Same pattern at lines 517–523 for tool_result turns.
- Terminal exit paths (unsupported provider line 354; `$$$ISERR(tInvokeSC)` line 385; max-iter line 544; cross-session notice line 583) all push to `tTurns` only — `tTurnsForLlm` is never read after these points, so the divergence is benign.
- AC-3 5 verbatim test method names found at `src/SessionAgent/Test/AgentLoopVocabDigestTest.cls` lines 221, 247, 288, 314, 380. Test isolation `sa-test-94-` prefix at line 50; broadened cleanup `sa-test-9%` per dev's documented intent.
- AC-4 `TestAnthropicCachedPrefixUnchangedAcrossTurns` at line 436 captures system + tools via `VocabDigestCaptureMock` PPGs and asserts byte-identity. Provider override short-circuits the actual Anthropic provider construction (so structural assertion runs unconditionally without a live credential).
- AC-2 SQL-probe evidence confirms canonical `pUserText` ("find me failed admits") persists to `Chat.History.TurnsJson` — no digest prefix, no `---` delimiter, no `## Common idioms` header.
- Empty-digest edge case (`TestEmptyDigestStillWiresThrough`): `tInjectDigest=1` is set unconditionally inside the search-agent-first-turn guard at line 238; empty-digest in-band branch at lines 233–237 correctly collapses to `"User: " _ pUserText` with no orphan delimiter.

**Project-rule sweep:** Rule 1 (spec ≤ 250 lines: 217 — within cap). Rule 2 (no `[x]` without verification: dev's Completion Notes contain verbatim AC-contract evidence — SQL probe of TurnsJson, per-method PASS roster, regression count 358/358). Rule 3 (typed-MCP first: `iris_doc_compile`, `iris_execute_tests`, `iris_sql_execute` cited). Rule 6 (epic-end battery: AC-5 ground-truth via canonical numerical-MAX SQL probe). Rule 8 (no deferrals introduced). Rule 12 (no UI rendering in this story; Story 9.3 already covered render shape).

**Dismissed observations (LOW / not actionable):**

1. `tInjectedUserText` initialization at line 224 is dead code in the `tInjectDigest=0` branch (variable never read). Stylistic only — defensive initialization is acceptable.
2. `TestEmptyDigestStillWiresThrough` validates the empty-digest fallback structurally (compiled-method-source grep) rather than empirically (no production hook to stub `Build` returning `""`). Dev acknowledges the tradeoff inline.
3. Test class doesn't extend `AgentLoopTestBase` — adds ~80 lines of duplicated setup but improves test isolation. Dev decision documented in class doc-comment.
4. Test cleanup uses `LIKE 'sa-test-9%'` (broader than `sa-test-94-`) — covers Story 9.3 leftovers; dev intent stated in `OnBeforeOneTest`.
5. AC-4 turn-2 path correctly fires the second-turn-no-digest branch (`tTurns.%Size() > 0` after persistence); cached prefix byte-equality holds because `pSessionKey` is identical across turns and the system prompt is deterministic.
