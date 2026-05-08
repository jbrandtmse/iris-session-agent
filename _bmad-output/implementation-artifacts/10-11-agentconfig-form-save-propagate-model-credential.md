# Story 10.11: AgentConfig Form Save — Propagate Model + CredentialName on Provider Rotation

Status: done

## Story

As an **Operator-Admin rotating an agent's Provider via the AgentConfig form**,
I want the form's Save handler to also propagate `Model` and `CredentialName` to the new provider's defaults — so a single Save persists a coherent (Provider, Model, CredentialName) triple,
So that I don't have to manually fix-up Model + Credential after every Provider rotation, and the operator-facing "configure → ask" loop ships a usable round-trip.

## Background — surfaced by Story 10.10's UI walkthrough

Story 10.10's 4-provider verification used the operator UI surface (`SessionAgent.UI.AgentConfig` Zen form) for Provider rotation per the user's `feedback_use_config_screens_not_sql.md` rule. The walkthrough exposed:

> Form quirk: AgentConfig form saves `Provider` correctly via the form, but `Model` + `CredentialName` don't propagate on the same Save cycle. Pre-existing AgentConfig form behavior, not introduced by Story 10.10.

Concretely: the operator opens AgentConfig, picks an agent, changes Provider from `openai` → `anthropic`, clicks Save. Post-Save the row has `Provider='anthropic'` but `Model='gpt-4.1-mini'` (still openai's default) and `CredentialName='SessionAgentOpenAI'` (still openai's credential). The agent then fails to dispatch (model/credential mismatch).

Reviewer recommends fix-now in Story 10.11 (≤ 100-line spec) since operators will hit this immediately on first provider rotation via the form. Operationally, this is a v1.0.0 release-impact issue: it actively impedes the user's hard-feedback rule ("use the screens, not SQL UPDATE") because the screens don't actually work for the most common operator workflow.

## Acceptance Criteria

### AC-1 — Empirical reproduction

**Given** the AgentConfig form is loaded against `message-search` agent with `Provider=openai`
**When** the operator changes Provider to `anthropic` and clicks Save
**Then** the dev confirms via SQL probe that post-Save the `Config.Agent.message-search` row has `Provider='anthropic'` AND `Model='claude-haiku-4-5-20251001'` (or whichever the AgentDefaults canonical is for anthropic) AND `CredentialName='SessionAgentAnthropic'` AND `EnvVarName='ANTHROPIC_API_KEY'`.

The pre-state should be documented (verbatim SQL probe output of the pre-Save row); post-state should be documented (verbatim SQL probe output of the post-Save row); and the deltas should match the AgentDefaults provider-canonical values for the new provider.

### AC-2 — Root-cause investigation

**Given** the form-quirk reproduces empirically
**When** the dev investigates the Save flow
**Then** the dev probes:
- `SessionAgent.UI.AgentConfig:saveConfig()` ClientMethod (or its server-side counterpart `SaveAgentConfig` ZenMethod) — does it read all 11 fields from the form OR only the modified ones?
- The form's `onChangeAgent` ClientMethod — when an agent is loaded, does it pre-populate `Model` + `CredentialName` from the row's current values OR from the AgentDefaults provider-canonical values?
- The form's `onChangeProvider` (if exists) — when Provider changes, does it cascade-update Model + CredentialName + EnvVarName fields in the form's UI?

The likely root cause is one of:
1. **Form lacks `onChangeProvider` cascade** — picking a new Provider doesn't update the Model/CredentialName/EnvVarName fields in the UI, so Save persists the OLD values for those fields. Fix: add ClientMethod that reads `Config.AgentDefaults.GetCanonicalDefaults(provider)` and populates the dependent fields.
2. **Save handler reads only Provider + Enabled** — Save handler ignores Model/CredentialName/EnvVarName from the form. Fix: extend Save signature + body.
3. **Save handler reads from form but form's stale fields override the new Provider's defaults** — combination of both.

Document the root cause verbatim in Completion Notes.

### AC-3 — Apply the fix (root-cause-driven)

**Given** the root cause is identified
**When** the dev applies the fix
**Then** the fix is the minimum-blast-radius change needed. Most likely shape:
1. Add an `onChangeProvider(value)` ClientMethod to `SessionAgent.UI.AgentConfig`.
2. Hook the Provider field's `onchange` attribute to invoke `zenPage.onChangeProvider(zenThis.value);`.
3. The handler invokes a NEW `[ZenMethod]` `LoadProviderDefaults(pProvider)` that returns the AgentDefaults canonical triple as JSON `{model, credentialName, envVarName}`.
4. The handler updates the in-form fields via `zen('agentModel').setValue(...)`, `zen('agentCredentialName').setValue(...)`, `zen('agentEnvVarName').setValue(...)`.
5. When the operator clicks Save, the values from the form (now refreshed for the new Provider) are persisted by the existing Save handler.

If the actual root cause is different, the fix shape adapts but stays within `SessionAgent.UI.AgentConfig.cls` (one file).

### AC-4 — Verify the fix via UI walkthrough

**Given** the fix is applied
**When** the dev re-runs the AC-1 reproduction
**Then** post-Save the row has the coherent (Provider, Model, CredentialName, EnvVarName) triple matching the new provider's defaults. Verify for at least 2 transitions:
- `openai → anthropic`
- `anthropic → gemini`

Capture verbatim SQL probe rows for each. Capture chrome-devtools-mcp screenshots showing the form's pre-Save state with new Model + Credential populated automatically.

### AC-5 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.UI.AgentConfig`.
- New test in `SessionAgent.Test.AgentConfigTest`: `TestProviderRotationCascadesModelCredential` — invoke the new `LoadProviderDefaults` ZenMethod for each of the 4 providers, assert the returned triple matches `AgentDefaults.GetCanonicalDefaults`. (Or test the Save-with-rotation path more directly.)
- **Per-class regression sweep + canonical numerical-MAX SQL probe**. **Expected baseline 417 + 1 = 418+**.

## Tasks / Subtasks

- [x] **Task 0 — Reproduce + investigate (AC: #1, #2)**
  - [x] Open `SessionAgent.UI.AgentConfig` in chrome-devtools-mcp.
  - [x] Capture pre-Save SQL row for `message-search`.
  - [x] Toggle Provider via the form, click Save.
  - [x] Capture post-Save SQL row.
  - [x] Document the form-quirk reproduction verbatim.
  - [x] Read `SessionAgent.UI.AgentConfig.cls` Save handler + onChangeAgent + (any) onChangeProvider; identify the root cause.

- [x] **Task 1 — Apply the fix (AC: #3)**
  - [x] Implement the smallest-blast-radius change in `AgentConfig.cls`.
  - [x] Compile via `iris_doc_compile`.

- [x] **Task 2 — Verify via UI walkthrough (AC: #4)**
  - [x] Re-run the openai → anthropic transition; verify coherent triple.
  - [x] Run the anthropic → gemini transition; verify coherent triple.
  - [x] Capture screenshots + SQL probe rows.

- [x] **Task 3 — Test class extension (AC: #5)**
  - [x] Add 1 new test to `SessionAgent.Test.AgentConfigTest`. Compile + run per-class.

- [x] **Task 4 — Verification battery**
  - [x] Per-class regression sweep + canonical numerical-MAX SQL probe.

## Review Findings

- [x] [Review][Defer] Test asserts only `model` for unknown-provider fallthrough (not `credentialName` / `envVarName`) [src/SessionAgent/Test/AgentConfigTest.cls:725-727] — deferred, LOW: defense-in-depth branch; the current single-key assertion proves the fallthrough path returns openai-canonical. A future story tightening the unknown-fallthrough contract should extend the assertions.
- [x] [Review][Defer] Test never asserts `endpointUrl=""` for any of the four canonical providers [src/SessionAgent/Test/AgentConfigTest.cls:693-728] — deferred, LOW: every canonical row CORRECTLY ships `endpointUrl=""` (only openai-compatible operators populate this field, and even there the canonical default is empty per the operator-supplied UX). The `GetCanonicalDefaults` doc-comment pins the contract; a future regression that populates a non-empty endpointUrl for any branch would still surface in operator UX (cascade overwrites the field) but not in the test.
- [x] [Review][Defer] Cascade leaves `credType=env` + empty `envVarText` on rotation TO openai-compatible, which fails Save validation Rule 5 [src/SessionAgent/UI/AgentConfig.cls:694-697] — deferred, LOW: pre-existing constraint surfaced by cascade. The validation correctly rejects the empty env-var (operator must populate). The cascade's choice to flip to `credType=env` for openai-compatible matches the doc-comment ("operator typically uses OLLAMA_API_KEY or leaves it empty for unauth Ollama"). UX friction only — operator must type the env-var name OR flip to creds before Save. No regression introduced; documented behavior.

## Dev Notes

### Rule 1 / Rule 8 / Rule 11

- **Rule 1:** Spec ~110 lines.
- **Rule 8:** Pre-existing bug surfaced by Story 10.10 walkthrough; fix-now per the reviewer's recommendation.
- **Rule 11:** AC-4 UI walkthrough exercises 2 provider transitions live; satisfies the live-integration-smoke contract.

### Feedback applied

- `feedback_use_config_screens_not_sql.md` — AC-4 verification uses the form, NOT direct SQL UPDATE.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context)

### Completion Notes

#### AC-1 — Empirical reproduction of the form-quirk (verbatim SQL rows)

Pre-Save state (operator opened the form against `message-search` with the
operator-supplied `creds`-path baseline):

```
| AgentName     | Provider | Model         | EnvVarName | CredentialName     |
| message-search | openai  | gpt-4.1-mini  |            | SessionAgentOpenAI |
```

Save handler invoked with operator's intended Provider rotation
(`Provider=anthropic`) but with the form's stale Model + CredentialName
values still showing `gpt-4.1-mini` + `SessionAgentOpenAI` (which is what
the form passed to `SaveAgentConfig` because the OLD `providerChanged()`
handler did not cascade-update those field values):

```
SaveAgentConfig("message-search", "anthropic", "gpt-4.1-mini", "", "creds",
                "", "SessionAgentOpenAI", "32000", "0.1", "", "1", "30")
→ {"success":true,"message":"Saved"}
```

Post-Save SQL probe — the form-quirk persisted an incoherent triple:

```
| AgentName     | Provider  | Model         | EnvVarName | CredentialName     |
| message-search | anthropic | gpt-4.1-mini |            | SessionAgentOpenAI |
```

Provider rotated correctly to `anthropic`, but Model still says `gpt-4.1-mini`
(openai's default) and CredentialName still says `SessionAgentOpenAI` (openai's
credential). Operator would then see the agent fail to dispatch
(model/credential mismatch) on the next chat turn.

#### AC-2 — Root-cause documentation (verbatim)

The bug lives in `SessionAgent.UI.AgentConfig:providerChanged()` (lines
609–706 of the pre-fix file). On Provider rotation, that handler:

- Updates `modelCombo.valueList` / `displayList` (the SUGGESTION DROPDOWN
  options), so the operator sees the right candidate models in the dropdown.
- Toggles `endpointUrlText` visibility (visible iff openai-compatible).
- Updates `envVarText.setValue(...)` — but ONLY when the current value
  matches a known stale-canonical default (the stale-canonical guard
  preserves operator-typed custom values).
- Updates `maxTokensText.setValue(...)` — same stale-canonical guard.

It does NOT call:
- `modelCombo.setValue(...)` — so the model VALUE never changes when the
  operator picks a new Provider; only the dropdown's autocomplete
  suggestion list changes.
- `credCombo.setValue(...)` — so the CredentialName field value never
  changes either.

When `saveConfig()` reads `zen('modelCombo').getValue()` and
`zen('credCombo').getValue()`, both return the OLD provider's values, and
those are persisted to the row alongside the new Provider — yielding the
incoherent (Provider, Model, CredentialName) triple from AC-1.

#### AC-3 — Fix applied (root-cause-driven)

The minimum-blast-radius fix lives in two files:

1. **`src/SessionAgent/Config/AgentDefaults.cls`** — added pure
   `ClassMethod GetCanonicalDefaults(pProvider) As %DynamicObject` that
   returns `{model, credentialName, envVarName, endpointUrl}` for each
   of the four supported providers (openai canonical-fallthrough for
   unknown). This co-locates the canonical mapping with `GetSeedConfig`
   (already used at install time), so the per-provider canonical values
   live in one place. Per-provider triple:

   - openai → `gpt-4.1-mini`, `SessionAgentOpenAI`, `OPENAI_API_KEY`
   - anthropic → `claude-haiku-4-5-20251001`, `SessionAgentAnthropic`,
     `ANTHROPIC_API_KEY` (per Story 5.1 Rule 10 research)
   - gemini → `gemini-2.5-flash`, `SessionAgentGemini`, `GEMINI_API_KEY`
     (per README pricing table)
   - openai-compatible → `qwen2.5:32b`, `""`, `""` (operator-supplied)

2. **`src/SessionAgent/UI/AgentConfig.cls`** — added two methods:
   - `[ZenMethod] LoadProviderDefaults(pProvider) As %String` —
     server-side helper that JSON-serializes
     `AgentDefaults.GetCanonicalDefaults(pProvider)` for the
     client. Never-throw envelope on exception.
   - `ClientMethod onChangeProvider(value)` — provider-rotation
     cascade. Calls `LoadProviderDefaults`, sets `modelCombo` /
     `credCombo` / `envVarText` / `endpointUrlText` field values from
     the canonical triple, flips `credTypeRadio` to `creds` (when the
     canonical credential is non-empty — hyperscaler shape) or `env`
     (openai-compatible — operator-supplied), then calls existing
     `providerChanged()` + `credTypeChanged()` so suggestion list,
     endpoint visibility, and credential-source visibility still
     update consistently.
   - Updated the `<select id="providerSelect">` `onchange` attribute
     to invoke `zenPage.onChangeProvider(zenThis.value)` (was
     `zenPage.providerChanged()`).

#### AC-4 — Verification via chrome-devtools-mcp UI walkthrough

**Transition 1 — openai → anthropic (form-driven):**

Pre-cascade form state (operator on message-search after baseline reset):

```json
{"agent":"message-search","provider":"openai","model":"gpt-4.1-mini",
 "envVar":"OPENAI_API_KEY","cred":"SessionAgentOpenAI","credType":"creds"}
```

After dropdown change `providerSelect` → `anthropic` triggers
`onChangeProvider('anthropic')` cascade:

```json
{"provider":"anthropic","model":"claude-haiku-4-5-20251001",
 "envVar":"ANTHROPIC_API_KEY","cred":"SessionAgentAnthropic","credType":"creds"}
```

Post-Save SQL probe (after operator clicks Save and sees
"Saved" status indicator):

```
| AgentName     | Provider  | Model                     | EnvVarName | CredentialName        |
| message-search | anthropic | claude-haiku-4-5-20251001 |            | SessionAgentAnthropic |
```

Coherent triple — Model + CredentialName both match the new provider's
canonical defaults. Screenshot:
`_bmad-output/implementation-artifacts/walkthrough-10-11-rotation-1-openai-to-anthropic.png`.

**Transition 2 — anthropic → gemini (form-driven):**

After dropdown change `providerSelect` → `gemini` triggers
`onChangeProvider('gemini')` cascade:

```json
{"provider":"gemini","model":"gemini-2.5-flash","envVar":"GEMINI_API_KEY",
 "cred":"SessionAgentGemini","credType":"creds"}
```

Post-Save SQL probe:

```
| AgentName     | Provider | Model              | EnvVarName | CredentialName     |
| message-search | gemini  | gemini-2.5-flash   |            | SessionAgentGemini |
```

Coherent triple. Screenshot:
`_bmad-output/implementation-artifacts/walkthrough-10-11-rotation-2-anthropic-to-gemini.png`.

#### AC-5 — Compile + tests + regression

- `iris_doc_compile` clean for both `SessionAgent.Config.AgentDefaults`
  and `SessionAgent.UI.AgentConfig` (and the touched
  `SessionAgent.Test.AgentConfigTest`).
- New test `TestProviderRotationCascadesModelCredential` added to
  `SessionAgent.Test.AgentConfigTest` — invokes `LoadProviderDefaults`
  for each of the 4 providers + the unknown-provider fallthrough,
  asserts each canonical-triple element matches expectations.
- Per-class regression sweep run via `SessionAgent.Test.SweepRunner.RunAll()`
  + manual `RunOneTestCase` for `AgentLoopTest` + `AgentLoopGuardsTest`
  (which extend `AgentLoopTestBase` and so escape the SweepRunner's
  `Super [ '%UnitTest.TestCase'` predicate).

**Canonical numerical-MAX SQL probe (ground truth):**

```
| Total | Passed | Failed |
|   418 |    418 |      0 |
```

Pre-state baseline 417 + 1 new test = 418 expected; 418 passed exactly.
Zero failures across all 52 distinct `SessionAgent.Test.*` classes.

#### Operator state restoration

Pre-test message-search baseline restored via `SaveAgentConfig`:
`(openai, gpt-4.1-mini, OPENAI_API_KEY, "")` (env-path baseline). Form
state matches the start-of-story snapshot.

### File List

- `src/SessionAgent/Config/AgentDefaults.cls` (modified — added
  `GetCanonicalDefaults` ClassMethod)
- `src/SessionAgent/UI/AgentConfig.cls` (modified — added
  `LoadProviderDefaults` ZenMethod, `onChangeProvider` ClientMethod,
  re-wired `providerSelect.onchange` to invoke the new cascade)
- `src/SessionAgent/Test/AgentConfigTest.cls` (extended — added
  `TestProviderRotationCascadesModelCredential` test method)
- `_bmad-output/implementation-artifacts/walkthrough-10-11-rotation-1-openai-to-anthropic.png` (new screenshot)
- `_bmad-output/implementation-artifacts/walkthrough-10-11-rotation-2-anthropic-to-gemini.png` (new screenshot)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status flip)
- `_bmad-output/implementation-artifacts/10-11-agentconfig-form-save-propagate-model-credential.md` (this file)

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-08 | 0.1 | Initial spec drafted by lead from Story 10.10 walkthrough form-quirk finding + reviewer recommendation. | Lead |
| 2026-05-08 | 1.0 | Implementation complete — provider-rotation cascade adds GetCanonicalDefaults + LoadProviderDefaults + onChangeProvider; AC-1 reproduction + AC-4 form walkthrough captured; 1 new test (TestProviderRotationCascadesModelCredential); regression sweep 418/418/0. Status → review. | Dev |
