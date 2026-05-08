# Story 12.4: AgentLoop MaxIterationsPerTurn Configurable + Richer Fallback Message

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` BUG-06 (MEDIUM). The agent loop's hardcoded 10-iteration ceiling (`Parameter MaxIterationsPerTurn As INTEGER = 10;` in `SessionAgent.Agent.AgentLoop` line 85) is not operator-configurable; the fallback message ("Max iterations reached. Please summarize.") is uninformative — the operator gets a directive without context about what was investigated or how to refocus.

## User Story

As an **operator** running the Inspection Agent against a complex session, I want the iteration cap to be configurable per-agent (so I can raise it for sessions that legitimately need more tool calls), AND I want the fallback message — when the cap is hit — to summarize what tools were called and suggest a follow-up question. So that I can either reconfigure the cap for my workflow OR continue the conversation without losing context.

## Acceptance Criteria

**AC-1 — `MaxIterationsPerTurn` property added to `Config.Agent`.**
- **Given** `src/SessionAgent/Config/Agent.cls` currently has properties for Provider, Model, MaxTokens, Temperature, etc.,
- **When** the property is added,
- **Then** the schema includes `Property MaxIterationsPerTurn As %Integer(MINVAL = 1, MAXVAL = 100) [ InitialExpression = 10 ];` with appropriate doc-comment.

> **Verbatim evidence:** SQL probe `SELECT %EXACT(AgentName), MaxIterationsPerTurn FROM SessionAgent_Config.Agent` returns rows showing the new column (default 10 for existing rows). Capture verbatim.

**AC-2 — `AgentLoop.RunTurn` reads `MaxIterationsPerTurn` from `Config.Agent` (not class parameter).**
- **Given** `AgentLoop.RunTurn` previously read `..#MaxIterationsPerTurn` (class parameter, hardcoded 10),
- **When** the per-agent override is wired,
- **Then** the loop reads `..ConfigAgent.MaxIterationsPerTurn` with `$Char(0)` → `""` normalization (per project rule §"$Char(0) sentinel — grep target for %String reads with SQL UPDATE write paths" — extends to %Integer reads where SQL UPDATE could clear the field; defensive guard against `$Char(0)` ambiguity in case future schema changes shift the type). If the read returns 0 or empty, fall back to the class parameter `..#MaxIterationsPerTurn` as a safety floor.

> **Verbatim evidence:** Compile-time grep of `AgentLoop.RunTurn` shows `..ConfigAgent.MaxIterationsPerTurn` AND a fallback `..#MaxIterationsPerTurn` reference; the loop condition `While (tIter < tMaxIter)` reads `tMaxIter` set from the config. Capture the relevant 5-line snippet.

**AC-3 — AgentConfig Zen form exposes `MaxIterationsPerTurn` field.**
- **Given** `src/SessionAgent/UI/AgentConfig.cls` Zen form currently has fields for MaxTokens, Temperature, SystemPromptOverride, etc.,
- **When** the field is added to the form layout,
- **Then** operators see a labeled numeric input ("Max iterations per turn") with min/max validation (1–100), positioned near the existing Temperature field. Default value populates from `GetCanonicalDefaults` for the selected provider (canonical default 10).

> **Verbatim evidence (Rule 12 layout-correctness):** chrome-devtools-mcp `take_screenshot` of the AgentConfig form post-fix showing the new field. Confirm layout: label + numeric input + helper text describing validation range. Save screenshot to `_bmad-output/implementation-artifacts/12-4-screenshot-agentconfig-maxiter-field.png`.

**AC-4 — Save handler validates and persists `MaxIterationsPerTurn`.**
- **Given** the operator types a value into the new field,
- **When** Save is clicked,
- **Then** the `SaveAgentConfig` ZenMethod validates the value (integer, 1–100) and persists to `Config.Agent.MaxIterationsPerTurn`. Out-of-range values surface a validation error matching the existing field-validation pattern.

> **Verbatim evidence:** Live exercise via the Zen form — set value to 50, click Save, then SQL probe confirms the value persisted. Set value to 200 (out of range), confirm validation error rendered.

**AC-5 — Fallback message when cap is hit is informative.**
- **Given** the loop hits `tMaxIter` with `tStop = 0` (i.e., the model is still issuing tool_use rounds),
- **When** the synthetic fallback turn is emitted,
- **Then** the message is structured: (a) one-line acknowledgment ("I've used my full investigation budget for this turn — N tool calls performed."), (b) bullet list of the tools called and a one-line per-tool result summary (extracted from the tool_result blocks), (c) one-line follow-up suggestion ("Please ask a more focused follow-up question — e.g. about a specific message ID or BP — to continue.").

> **Verbatim evidence:** Live exercise — set `MaxIterationsPerTurn = 2` for the Inspection Agent via the form, ask a question that requires multiple tool calls (e.g. "investigate this session in depth"), capture the resulting fallback turn text via chrome-devtools-mcp `take_snapshot`. Confirm the 3-section structure (acknowledgment + tool list + suggestion). Reset the value to 10 after.

**AC-6 — No regression: existing tests + new tests pass.**
- **When** the per-class regression sweep runs,
- **Then** the canonical numerical-MAX SQL probe reports Failed = 0 and Total ≥ pre-fix baseline + new tests.

> **Verbatim evidence:** SQL probe Total / Passed / Failed row.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe (Rule 3 — typed MCP first)**
  - [x] Read `src/SessionAgent/Config/Agent.cls` — confirmed property declaration patterns (MaxTokens for shape).
  - [x] Read `src/SessionAgent/Agent/AgentLoop.cls` lines 85 (parameter) + loop + fallback message.
  - [x] Read `src/SessionAgent/Config/AgentDefaults.cls` `GetCanonicalDefaults` — noted shape for adding the new key.
  - [x] Read `src/SessionAgent/UI/AgentConfig.cls` Zen form `XData contentPane` — identified insertion point after Temperature.
  - [x] SQL probe baseline: 2 rows in `SessionAgent_Config.Agent`. Regression baseline 441/441/0 via canonical numerical-MAX SQL probe.
- [x] **Task 1 — `Config.Agent.MaxIterationsPerTurn` property**
  - [x] Added property `As %Integer(MAXVAL = 100, MINVAL = 1) [ InitialExpression = 10 ]` with comprehensive doc-comment citing BUG-06.
  - [x] Compile clean (cuk + ckb).
  - [x] Existing rows return "" via OREF getter (not auto-populated; defensive read in AgentLoop normalizes "" → fallback class param).
- [x] **Task 2 — `AgentLoop.RunTurn` config-driven cap**
  - [x] Read `..ConfigAgent.MaxIterationsPerTurn` with `$Char(0)` / `""` / `< 1` normalization → fall back to `..#MaxIterationsPerTurn`.
  - [x] Replaced `..#MaxIterationsPerTurn` with `tMaxIter` in the While condition AND post-iteration check.
  - [x] Compile clean.
- [x] **Task 3 — Richer fallback message**
  - [x] Replaced legacy hardcoded "Max iterations reached. Please summarize." with `BuildMaxIterFallback` helper.
  - [x] Helper walks `tResult.ToolCallsRendered` (each card has `name`, `result`, `status`); for each, extracts first 80 chars of `result.content[0].text` via `ExtractToolResultSummary` helper (truncates with `…` if longer; collapses internal whitespace).
  - [x] 3-section structure: acknowledgment + `**tool_name** → summary` bullet list + follow-up suggestion. Sections separated by `\n\n` (Markdown paragraph breaks).
  - [x] Compile clean.
- [x] **Task 4 — `GetCanonicalDefaults` extension**
  - [x] Added `Do tObj.%Set("maxIterationsPerTurn", 10, "number")` to `GetCanonicalDefaults` (applies to all 4 providers via post-If branch).
  - [x] Compile clean.
- [x] **Task 5 — AgentConfig Zen form field**
  - [x] Added `<text id="maxIterText" size="8" />` after Temperature, before SystemPromptOverride.
  - [x] Set label "Max iterations per turn" + hint "1-100 (default 10)" at runtime in `%OnAfterCreatePage` (MPP5646 workaround).
  - [x] Extended `LoadAgentConfig` to return `MaxIterationsPerTurn` (with $Char(0) / "" / <1 → 10 fallback).
  - [x] Extended `loadAgent()` client to populate the field from `data.MaxIterationsPerTurn`.
  - [x] Extended `SaveAgentConfig` ZenMethod signature with `pMaxIterationsPerTurn As %String = ""`; added Rule 9 validation (integer + 1-100 range, empty → use default 10); persistence falls back to 10 on empty / out-of-range.
  - [x] Extended `saveConfig()` client to read the field and pass to the ZenMethod.
  - [x] Extended `onChangeProvider` cascade with preserve-when-customized heuristic (canonical=10 for all providers; capture pre-cascade value, only stomp to 10 when fresh-state).
  - [x] Extended `clearErrorLabels` field-id list with `maxIterText`.
  - [x] Compile clean (cuk + ckb).
- [x] **Task 6 — `node -c` parse check (Story 12.0 Carry-Forward)**
  - [x] AgentConfig Zen form's JS lives in the .cls (ClientMethod blocks), NOT in `static/chat-panel.js`. Binding does NOT apply per dispatch instructions; skipped `node -c`.
- [x] **Task 7 — Layout-correctness verification (Rule 12)**
  - [x] chrome-devtools-mcp navigated to AgentConfig Zen form, captured screenshot at `_bmad-output/implementation-artifacts/12-4-screenshot-agentconfig-maxiter-field.png` (full page).
  - [x] DOM probe asserted `getElementById('maxIterText')` exists; `rowText` returned "Max iterations per turn\n1-100 (default 10)" (label + hint text rendered).
- [x] **Task 8 — Live AC-4 + AC-5 exercise**
  - [x] AC-4 happy path: form set MaxIterationsPerTurn=50 via Zen form → Save → "Saved" rendered → SQL probe `SELECT %EXACT(AgentName), MaxIterationsPerTurn FROM SessionAgent_Config.Agent` returned `[("session-inspection", 50), ("message-search", 10)]`.
  - [x] AC-4 validation: form set value=200 → Save → inline error "Max iterations per turn must be 1–100" rendered next to the field; SQL probe confirms row UNCHANGED at 50 (validation rejected before persist).
  - [x] AC-5 live: set MaxIterationsPerTurn=2 via form, Save; ran `RunTurn("session-inspection", "76928", "_SYSTEM_TEST_MAX2", "<exhaustive investigation prompt>")` against real Ens session 76928 with OpenAI provider. Resulting `AssistantMarkdown` (verbatim first 1500 chars):
    ```
    I've used my full investigation budget for this turn — 12 tool calls performed.

    - **session_summary** → Session 76928: 7 messages, 0 errors, root class SessionAgent.Sample.Msg.OrderReq…
    - **session_timeline** → Session 76928: 7 events spanning 7ms.
    - **message_headers** → Session 76928: 7 headers.
    - **rule_log** → 0 rule decision(s) for session 76928.
    - **get_business_process_instance** → no BP instance for session 76928 — message routing was straight-through (BS → BO…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderRequest, 7 properties — se…
    [...12 total tool calls listed...]

    Please ask a more focused follow-up question — e.g. about a specific message ID or business process — to continue.
    ```
    — confirms 3-section structure (acknowledgment + bullet list + follow-up suggestion); 12 tool calls dispatched in 2 iterations (one tool_use round-trip can carry multiple tool_use blocks).
  - [x] Reset MaxIterationsPerTurn=10 via Zen form save; SQL probe confirms restoration.
- [x] **Task 9 — Add unit tests**
  - [x] `ConfigAgentTest`: added `TestMaxIterationsPerTurnSchemaShape` (Type=%Integer + InitialExpression=10 + MAXVAL=100 + MINVAL=1) + `TestMaxIterationsPerTurnRoundTrip` (mutate to 50, %Save, re-open, value persists). Updated `TestSchemaPropertiesPresent` expected map.
  - [x] `AgentLoopGuardsTest`: added `TestRunTurnCustomMaxIterationsPerAgent` (set per-agent cap=5, mock 7 tool_use responses, assert only 5 LlmCall rows persisted) + `TestRunTurnMaxIterFallbackHas3Sections` (mock 12 tool_use, assert acknowledgment + bullet + follow-up substrings present, legacy "Please summarize." absent). Updated existing `TestRunTurnMaxIterationsCap` to assert AC-5 acknowledgment substring.
  - [x] `AgentConfigTest`: added `TestSaveAgentConfigPersistsMaxIterationsPerTurn` (Save with maxIter=25 → row persists 25) + `TestSaveAgentConfigRejectsBadMaxIterationsPerTurn` (Save with maxIter=200 → validation error envelope with `field=maxIterText` + range references) + `TestLoadAgentConfigCarriesMaxIterationsPerTurn` (envelope carries the field as positive integer 1-100).
- [x] **Task 10 — Regression sweep + SQL ground-truth probe** — 448/448/0 via canonical numerical-MAX SQL probe (baseline 441 + 7 new tests = 448 exact, Failed=0).
- [x] **Task 11 — Spec length verification** — `wc -l` = 132 ≤ 250.
- [x] **Task 12 — Sprint-status flip** — `12-4-...: ready-for-dev` → `in-progress` (start of dev) → `review` (this commit).
- [ ] **Task 13 — Commit + push** (lead).

## Dev Notes

### Why preserve the class parameter as a safety floor

Removing the class parameter entirely would break installations where `Config.Agent` rows haven't been migrated (e.g., a fresh install before the schema upgrade runs). Keeping `..#MaxIterationsPerTurn = 10` as a fallback means the AgentLoop is robust to a missing or zero-valued config entry.

### Why no auto-correction on the iteration count drift

If the operator sets MaxIterationsPerTurn = 5 and the agent regularly hits the cap, the operator should manually raise it (the AgentConfig form is the right place). No auto-tuning per-turn — that would be a feature, not a bug fix.

### Files modified

- `src/SessionAgent/Config/Agent.cls` (new property)
- `src/SessionAgent/Agent/AgentLoop.cls` (config read + richer fallback message)
- `src/SessionAgent/Config/AgentDefaults.cls` (`GetCanonicalDefaults` extension)
- `src/SessionAgent/UI/AgentConfig.cls` (form field + cascade + save handler)
- `src/SessionAgent/Test/ConfigAgentTest.cls` (or equivalent — new test method)
- `src/SessionAgent/Test/AgentLoopGuardsTest.cls` (extend with custom-cap test)
- `src/SessionAgent/Test/AgentConfigTest.cls` (extend with form save + cascade test)

## File List

**Modified:**
- `src/SessionAgent/Config/Agent.cls` — added `MaxIterationsPerTurn` property (`%Integer(MAXVAL=100, MINVAL=1) [InitialExpression=10]`).
- `src/SessionAgent/Agent/AgentLoop.cls` — read `MaxIterationsPerTurn` from `tConfig` with $Char(0)/""/<1 fallback; replaced 2 `..#MaxIterationsPerTurn` references with `tMaxIter`; replaced legacy fallback string with `BuildMaxIterFallback` helper; added `BuildMaxIterFallback` + `ExtractToolResultSummary` ClassMethods.
- `src/SessionAgent/Config/AgentDefaults.cls` — `GetCanonicalDefaults` returns `maxIterationsPerTurn=10` for all providers.
- `src/SessionAgent/UI/AgentConfig.cls` — added `<text id="maxIterText">` after Temperature; runtime label/hint setter in `%OnAfterCreatePage`; extended `LoadAgentConfig` JSON with `MaxIterationsPerTurn`; extended `loadAgent()` client populate; extended `SaveAgentConfig` ZenMethod signature + Rule 9 validation + persistence; extended `saveConfig()` client read; extended `onChangeProvider` cascade with preserve-when-customized; extended `clearErrorLabels` field-id list.
- `src/SessionAgent/Test/ConfigAgentTest.cls` — extended `tExpected` map with `MaxIterationsPerTurn`; added `TestMaxIterationsPerTurnSchemaShape` + `TestMaxIterationsPerTurnRoundTrip`.
- `src/SessionAgent/Test/AgentLoopGuardsTest.cls` — added `TestRunTurnCustomMaxIterationsPerAgent` + `TestRunTurnMaxIterFallbackHas3Sections`; updated existing `TestRunTurnMaxIterationsCap` substring assertion.
- `src/SessionAgent/Test/AgentConfigTest.cls` — added `TestSaveAgentConfigPersistsMaxIterationsPerTurn` + `TestSaveAgentConfigRejectsBadMaxIterationsPerTurn` + `TestLoadAgentConfigCarriesMaxIterationsPerTurn`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — flipped 12-4 to `in-progress` then `review`.

**Created:**
- `_bmad-output/implementation-artifacts/12-4-screenshot-agentconfig-maxiter-field.png` — Rule 12 layout-correctness screenshot.

### Patterns to follow verbatim

- Story 11.1's preserve-when-customized cascade pattern in AgentConfig form.
- Story 6.1's Zen form field-add pattern for new operator-facing inputs.
- Project rule §"$Char(0) sentinel" for the ConfigAgent.MaxIterationsPerTurn read normalization.

## Completion Notes

**Implementation summary (2026-05-08, dev sign-off).** All 6 ACs satisfied with verbatim evidence per Rule 2; regression sweep 448/448/0 via canonical numerical-MAX SQL probe (baseline 441 + 7 new tests = 448 exact, Failed=0). All compile clean (cuk + ckb).

**Verbatim AC contract evidence:**

- **AC-1 (`MaxIterationsPerTurn` property added):**
  - Schema-shape SQL probe: `SELECT %EXACT(AgentName), MaxIterationsPerTurn FROM SessionAgent_Config.Agent` → `[("session-inspection", 10), ("message-search", 10)]` (post-form-save reset; the round-trip path fully exercised — see AC-4 evidence below).
  - `TestMaxIterationsPerTurnSchemaShape` asserts Type=%Integer, InitialExpression=10, MINVAL=1, MAXVAL=100 (PASS).
  - `TestMaxIterationsPerTurnRoundTrip` asserts mutate→%Save→re-open round-trip (PASS).
- **AC-2 (`AgentLoop.RunTurn` reads from Config.Agent with fallback):**
  - Code path snippet (verbatim from `src/SessionAgent/Agent/AgentLoop.cls` post-edit):
    ```
    Set tMaxIter = tConfig.MaxIterationsPerTurn
    If (tMaxIter = $Char(0)) || (tMaxIter = "") || (+tMaxIter < 1) {
        Set tMaxIter = ..#MaxIterationsPerTurn
    }
    ...
    While (tIter < tMaxIter) && (tStop = 0) {
    ...
    If (tStop = 0) && (tIter >= tMaxIter) {
        Set tHitMaxIter = 1
    }
    ```
  - `TestRunTurnCustomMaxIterationsPerAgent` asserts per-agent cap=5 yields exactly 5 LlmCall rows (NOT class-param 10) (PASS).
- **AC-3 (Zen form field renders):**
  - Screenshot: `_bmad-output/implementation-artifacts/12-4-screenshot-agentconfig-maxiter-field.png` shows new field "Max iterations per turn" with hint "1-100 (default 10)" positioned after Temperature.
  - DOM probe `document.getElementById('maxIterText')` exists; rowText reads "Max iterations per turn\n1-100 (default 10)".
- **AC-4 (Save handler validates + persists):**
  - Live form save value=50 → "Saved" rendered → SQL probe `SELECT %EXACT(AgentName), MaxIterationsPerTurn FROM SessionAgent_Config.Agent` returned `[("session-inspection", 50), ("message-search", 10)]`.
  - Live form save value=200 → inline error "Max iterations per turn must be 1–100" rendered next to the field; SQL probe confirms row UNCHANGED at 50.
  - `TestSaveAgentConfigPersistsMaxIterationsPerTurn` (PASS), `TestSaveAgentConfigRejectsBadMaxIterationsPerTurn` (PASS), `TestLoadAgentConfigCarriesMaxIterationsPerTurn` (PASS).
- **AC-5 (Fallback message structured):**
  - Live exercise: form set MaxIterationsPerTurn=2 → ran exhaustive-investigation query against Ens session 76928 with OpenAI provider. Verbatim result (full):
    ```
    I've used my full investigation budget for this turn — 12 tool calls performed.

    - **session_summary** → Session 76928: 7 messages, 0 errors, root class SessionAgent.Sample.Msg.OrderReq…
    - **session_timeline** → Session 76928: 7 events spanning 7ms.
    - **message_headers** → Session 76928: 7 headers.
    - **rule_log** → 0 rule decision(s) for session 76928.
    - **get_business_process_instance** → no BP instance for session 76928 — message routing was straight-through (BS → BO…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderRequest, 7 properties — se…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderRequest, 7 properties — se…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderResponse, 5 properties — s…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderRequest, 7 properties — se…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderRequest, 7 properties — se…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderResponse, 5 properties — s…
    - **get_message_body** → Ens.MessageBody subclass SessionAgent.Sample.Msg.OrderResponse, 5 properties — s…

    Please ask a more focused follow-up question — e.g. about a specific message ID or business process — to continue.
    ```
  - 3-section structure verified verbatim. 12 tool calls in 2 iterations confirms multi-block tool_use round-trips are correctly aggregated.
  - `TestRunTurnMaxIterFallbackHas3Sections` asserts each section's load-bearing substring (PASS).
- **AC-6 (Regression sweep clean):**
  - Verbatim SQL ground-truth probe row: `[Total=448, Passed=448, Failed=0]` (baseline 441 + 7 new tests = 448 exact).

**Implementation notes:**

- **`InitialExpression` only fires for new %New() instances** — existing `SessionAgent_Config.Agent` rows had `MaxIterationsPerTurn` returning "" (empty string) via the OREF getter after the schema upgrade. The defensive read in `AgentLoop.RunTurn` (`If (tMaxIter = $Char(0)) || (tMaxIter = "") || (+tMaxIter < 1)`) handles this correctly, falling back to the class parameter `..#MaxIterationsPerTurn = 10`. Form-save then overwrites the empty value with 10 on first save (validated AC-4).
- **Fallback message uses `tResult.ToolCallsRendered`** rather than walking `tTurns` — the ToolCallsRendered array is already populated per-tool in Step 7d with `name` + `result` + `status` cards, which is exactly the shape needed for the bullet list. This avoids re-parsing tool_result blocks from the canonical history JSON.
- **Per-provider canonical maxIterationsPerTurn = 10** (uniform across all 4 providers) — the cascade simplifies to "if pre-cascade equals 10 → fresh state, leave 10; else operator-customized, preserve". A future story making this provider-specific need only update `GetCanonicalDefaults`.
- **Story 11.1 preserve-when-customized pattern faithfully replicated** for the new field — pre-cascade capture, OLD canonical compare, fresh-vs-customized branch.
- **Test runner truncation observed** during AgentLoopGuardsTest + AgentConfigTest runs (envelope showed 1 result while SQL probe showed 11 / 25). Per `.claude/rules/object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround", SQL ground-truth probe is authoritative; regression evidence cited above is from the SQL probe.

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.2 commit `0d9e6e3`).
- 2026-05-08 — Dev sign-off. All 6 ACs satisfied with verbatim evidence; regression 448/448/0 via SQL probe; story flipped to `review`.
- 2026-05-08 — Code review pass (reviewer). Three review layers (acceptance auditor + blind hunter + edge case hunter): all 6 ACs verified against the diff; defensive read normalization + class-parameter floor + both `..#MaxIterationsPerTurn` references switched + 3-section fallback + `ExtractToolResultSummary` defensive guards confirmed; Rule 12 layout-correctness screenshot shows Mgmt-Portal chrome + label "Max iterations per turn" + hint "1-100 (default 10)" + correct positioning after Temperature; cascade preserve-when-customized faithfully replicates Story 11.1 pattern; SaveAgentConfig validation rejects out-of-range with per-field error envelope; tests cover schema shape + round-trip + per-agent override + 3-section fallback substring + form-save persistence + form-save validation + form-load envelope (7 new tests). Two LOW-severity findings (whitespace-only result text rendering + test-setup `%Save()` not asserted) deferred to `deferred-work.md` per Rule 8 test 3 (cosmetic, no predicted-bug shape). HIGH/MEDIUM findings: 0/0. Story flipped to `done`.
