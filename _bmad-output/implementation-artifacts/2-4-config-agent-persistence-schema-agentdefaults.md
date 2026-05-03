# Story 2.4: `Config.Agent` Persistence Schema + `AgentDefaults`

Status: done

## Story

As an Operator-Admin (later, via Epic 6 UI),
I want a `SessionAgent.Config.Agent` `%Persistent` class storing per-agent runtime configuration (provider / model / max-tokens / temperature / system-prompt-override / credential-ref / endpoint-URL / enabled flag / search-chat retention),
so that the AgentLoop can read live config on every turn (NFR-O2 hot config change) without the operator restarting IRIS, and so that no API keys are ever persisted in config rows (NFR-S2).

This story ships **three classes** and updates **one existing class** to wire them in:

1. `SessionAgent.Config.Agent` (NEW, `%Persistent`)
2. `SessionAgent.Config.AgentDefaults` (NEW, helper)
3. `SessionAgent.Test.ConfigAgentTest` (NEW, unit tests)
4. `SessionAgent.Installer` (UPDATE — replaces the `SeedDefaultAgentConfigs` deferred placeholder body with real seeding logic)

## Acceptance Criteria

ACs map to the BDD clauses in [epics.md Story 2.4](../planning-artifacts/epics.md#story-24-configagent-persistence-schema--agentdefaults) (lines 798–821) and architecture row OD4 at [architecture.md:308](../planning-artifacts/architecture.md).

**AC-1 — `SessionAgent.Config.Agent` `%Persistent` class shipped at `src/SessionAgent/Config/Agent.cls`** with **exactly these 12 properties** (camel-case names, no underscores per project rule §"Basics"):

| # | Property | Type | Notes |
|---|---|---|---|
| 1 | `AgentName` | `%String` | Key. Values: `session-inspection` \| `message-search` |
| 2 | `Provider` | `%String` | Values: `openai` \| `anthropic` \| `gemini` \| `openai-compatible` |
| 3 | `Model` | `%String` | e.g. `gpt-4o` |
| 4 | `MaxTokens` | `%Integer` | |
| 5 | `Temperature` | `%Numeric` | |
| 6 | `SystemPromptOverride` | `%String(MAXLEN=8192)` | optional; empty by default |
| 7 | `CredentialName` | `%String` | named entry in `Ens.Config.Credentials` |
| 8 | `EnvVarName` | `%String` | env-var key (e.g. `OPENAI_API_KEY`) |
| 9 | `EndpointUrl` | `%String` | for OpenAI-compatible providers |
| 10 | `ReadOnly` | `%Boolean [InitialExpression = 1]` | tools-side L4 invariant |
| 11 | `Enabled` | `%Boolean [InitialExpression = 0]` | operator opts in via Epic 6 UI |
| 12 | `SearchChatRetentionDays` | `%Integer [InitialExpression = 30]` | for search-agent chat purge sweep |

Plus:

- `Index AgentNameIdx On AgentName [Unique]` — O(1) lookup
- **NO `ApiKey` property** (NFR-S2 schema discipline — only references)
- Storage section auto-generated; never hand-authored (project rule §"Storage Sections")

**AC-2 — `SessionAgent.Config.AgentDefaults` helper class shipped at `src/SessionAgent/Config/AgentDefaults.cls`** with two ClassMethods:

- `GetSystemPrompt(pAgentName As %String) As %String` — returns a per-agent default system prompt string. Both prompts are short (≤ 500 chars). Content guidance:
  - **`session-inspection`**: states the read-only invariant (no writes/sends/edits to the IRIS Production); enumerates the 13 inspection-tool affordances by name (`session_summary`, `session_timeline`, `message_headers`, `event_log`, `rule_log`, `find_related_sessions`, `find_sessions_by_body`, `get_message_body`, `get_message_detail`, `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods`, `explain_error`); says "answer in plain English; cite sessions/messages by ID."
  - **`message-search`**: states the bounded-WHERE invariant (every search includes an indexed column + time window); says "return curated lists, not large dumps; favor click-through over verbose summaries."
  - For any other `pAgentName`, returns `""`.
- `GetSeedConfig(pAgentName As %String) As Config.Agent` — returns a populated **un-saved** `Config.Agent` instance with OD4 defaults per [architecture.md:308](../planning-artifacts/architecture.md):
  - Both agents seed with: `Provider = "openai"`, `Model = "gpt-4o"`, `MaxTokens = 4096`, `Temperature = 0.0`, `EnvVarName = "OPENAI_API_KEY"`, `CredentialName = ""`, `EndpointUrl = ""`, `ReadOnly = 1`, `Enabled = 0`, `SearchChatRetentionDays = 30`, `SystemPromptOverride = ""`. (`Enabled = 0` is critical — operator must explicitly opt in via Epic 6 UI.)
  - `AgentName = pAgentName` (caller passes either `"session-inspection"` or `"message-search"`).
  - For unknown `pAgentName`, returns `$$$NULLOREF`.

**AC-3 — `SessionAgent.Installer.SeedDefaultAgentConfigs` updated** to replace the deferred placeholder body with real seeding logic:

- For each of `"session-inspection"` and `"message-search"`:
  - If `##class(SessionAgent.Config.Agent).AgentNameIdxExists(pAgentName)` returns 1 → log "row already present; skipping" and continue (idempotent reinstall).
  - Else: call `##class(SessionAgent.Config.AgentDefaults).GetSeedConfig(pAgentName)` → call `%Save()` on the returned object → check the `%Status` return per project rule §"Write Status Checking"; on failure, log + return error status; on success, log "seeded {pAgentName}".
- Keep the existing outer Try/Catch around the whole method (Story 1.5 pattern).
- Keep the `%Dictionary.ClassDefinition.%ExistsId("SessionAgent.Config.Agent")` guard at the top — it now succeeds on every install, but the guard remains as a safety net. Update the deferred-state log line to "Config.Agent present — seeding default rows" (drop the "deferred to Story 2.4" tail).
- Remove or update the doc-comment paragraph that says "the body below is the v1 reference shape. (Story 2.4 may refine...)" — replace with a one-line "Story 2.4 ships the seeding logic; this method is now live, not a placeholder."

**AC-4 — `SessionAgent.Test.ConfigAgentTest` ships at `src/SessionAgent/Test/ConfigAgentTest.cls`** extending `%UnitTest.TestCase`, ≤ 500 lines. Test methods:

- `TestSchemaPropertiesPresent` — uses `%Dictionary.PropertyDefinition` to verify each of the 12 required properties exists on `SessionAgent.Config.Agent` with the correct type. Catches schema drift early.
- `TestSchemaHasNoApiKey` — asserts `%Dictionary.PropertyDefinition.%ExistsId("SessionAgent.Config.Agent||ApiKey") = 0`. NFR-S2 schema-discipline check.
- `TestAgentNameIdxIsUnique` — asserts `%Dictionary.IndexDefinition.IDKEYGet("SessionAgent.Config.Agent||AgentNameIdx").Unique = 1`.
- `TestGetSeedConfigInspectionDefaults` — calls `AgentDefaults.GetSeedConfig("session-inspection")`; asserts `Provider=openai`, `Model=gpt-4o`, `MaxTokens=4096`, `Temperature=0.0`, `EnvVarName=OPENAI_API_KEY`, `Enabled=0`, `ReadOnly=1`, `SearchChatRetentionDays=30`.
- `TestGetSeedConfigSearchDefaults` — same as above for `"message-search"`.
- `TestGetSeedConfigUnknownAgentReturnsNull` — calls `GetSeedConfig("unknown-agent")`; asserts `$IsObject(result) = 0` (i.e., $$$NULLOREF).
- `TestGetSystemPromptInspectionMentionsToolNames` — calls `GetSystemPrompt("session-inspection")`; asserts result contains at least 5 of the 13 inspection-tool names (loose check; full prompt text is editable).
- `TestGetSystemPromptSearchMentionsBoundedWhere` — calls `GetSystemPrompt("message-search")`; asserts result contains the substring `"bounded"` (case-insensitive) AND `"time window"` (case-insensitive).
- `TestSeedingIsIdempotent` — kills `^SessionAgent.Config.AgentD` global (clean slate). Calls `Installer.SeedDefaultAgentConfigs()` twice. After the first call, asserts `count(*) FROM SessionAgent_Config.Agent = 2`. After the second call, asserts count is still 2 (no duplicates; AgentNameIdx unique enforces). `OnAfterOneTest` cleans up the seeded rows.
- `TestSavedRowRoundTrip` — open `Config.Agent` row by AgentName, mutate `MaxTokens` to 8192, save, re-open, assert mutated value persists. Restore on cleanup.

All assertions via `$$$Assert*` macros; never `..AssertX(...)`. `%OnNew(initvalue As %String = "")` calls `##super(initvalue)`.

**AC-5 — Compile + tests pass + end-to-end install verified.**

- `mcp__iris-dev-mcp__iris_doc_compile` succeeds for `SessionAgent.Config.Agent`, `SessionAgent.Config.AgentDefaults`, `SessionAgent.Installer`, `SessionAgent.Test.ConfigAgentTest` (the Installer compile picks up the updated `SeedDefaultAgentConfigs` body).
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.ConfigAgentTest`: 10/10 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 45/45 passing total (3 audit + 6 RBAC + 9 JSON + 9 retry + 8 envsecret + 10 config-agent).
- **Empirical install check** via `mcp__iris-dev-mcp__iris_execute_classmethod SessionAgent.Installer Install`: capture log output; expect lines "Config.Agent present — seeding default rows", "seeded session-inspection", "seeded message-search". Then re-run; expect "row already present; skipping" twice. Capture both transcripts in Completion Notes.

## Tasks / Subtasks

- [x] **Task 1 — Author `src/SessionAgent/Config/Agent.cls` (AC: #1)**
  - [x] Class extends `%Persistent`. Doc-comment with `///` HTML/DocBook markup naming the NFR-S2 contract
  - [x] All 12 properties per AC-1 table with exact types + InitialExpression where noted
  - [x] `Index AgentNameIdx On AgentName [Unique]`
  - [x] No `ApiKey` property; no `Storage` section authored (compiler auto-generated `Storage Default` on first compile per project rule §"Storage Sections")
  - [x] No `[Language = python]` (NFR-C2)

- [x] **Task 2 — Author `src/SessionAgent/Config/AgentDefaults.cls` (AC: #2)**
  - [x] Class doc-comment with `///`
  - [x] `GetSystemPrompt(pAgentName)` with two case branches + default empty
  - [x] `GetSeedConfig(pAgentName)` per OD4 defaults; returns un-saved instance; `$$$NULLOREF` for unknown agent
  - [x] No Try/Catch needed in either helper (no failure surfaces); both are pure functions

- [x] **Task 3 — Update `src/SessionAgent/Installer.cls` `SeedDefaultAgentConfigs` (AC: #3)**
  - [x] Replace placeholder body with real seeding loop over `("session-inspection", "message-search")`. Extracted per-agent logic to a private `SeedOneAgent` helper for failure-isolation per agent.
  - [x] Use `AgentNameIdxExists(pName)` for idempotency
  - [x] Call `GetSeedConfig(pName).%Save()`; check `$$$ISERR(tSC)` and log + propagate error
  - [x] Update doc-comment paragraph (removed "deferred" language; doc now says "Story 2.4 ships the seeding logic; this method is now live, not a placeholder.")
  - [x] Log lines per AC-3 ("Config.Agent present — seeding default rows", "seeded {name}", "row already present; skipping")
  - [x] Removed `[ Private ]` modifier from `SeedDefaultAgentConfigs` so the test class can invoke it directly (idempotency + round-trip tests). `SeedOneAgent` remains private.

- [x] **Task 4 — Author `src/SessionAgent/Test/ConfigAgentTest.cls` (AC: #4)**
  - [x] Extends `%UnitTest.TestCase`; `%OnNew(initvalue)` calls `##super(initvalue)`
  - [x] Ten `Test*` methods per AC-4 (camel-case names; no underscores)
  - [x] All assertions via `$$$Assert*` macros
  - [x] `OnBeforeOneTest` kills `^SessionAgent.Config.AgentD` and `^...AgentI` (extent + index) so seeding tests start clean; `OnAfterOneTest` repeats the kill in a try-block so a failed mid-test assert doesn't leak state
  - [x] File ≤ 500 lines (final: 251 lines)

- [x] **Task 5 — Compile + tests + install verification (AC: #5)**
  - [x] `iris_doc_compile` for all four classes — clean (see Completion Notes transcripts)
  - [x] `iris_execute_tests SessionAgent.Test.ConfigAgentTest` → 10/10 (see Completion Notes)
  - [x] Full regression: per-class run totals confirmed 45/45 (3 audit + 6 RBAC + 9 JSON + 9 retry + 8 envsecret + 10 config-agent). Package-level run consistently surfaces 35 due to a known `iris_execute_tests level:package` discovery quirk that drops `RetryWithBackoffTest` and `ReadOnlyRoleTest::RoleInstallIdempotent`; per-class invocation independently confirms each class passes. Full empirical evidence in Completion Notes.
  - [x] Empirical install: invoked `SessionAgent.Installer.SeedDefaultAgentConfigs` via `iris_execute_command` (the typed `iris_execute_classmethod` path failed because the helper writes to the principal device, jamming the Atelier JSON envelope — falling back to `iris_execute_command` is the documented capture path). First-run and re-run transcripts captured in Completion Notes; SQL extent verified at 2 rows with correct OD4 defaults.

- [x] **Task 6 — Stale-reference grep (discipline rule 4)**
  - [x] Grep over `src/SessionAgent/Config/*.cls`, `src/SessionAgent/Test/ConfigAgentTest.cls`, and `src/SessionAgent/Installer.cls` for `HSCUSTOMCODE` and `%SessionAgent_ReadOnly` → 0 matches in all three locations.

## Dev Notes

### Why no Task-0 backend-surface probe

`%Persistent`, `%Dictionary.PropertyDefinition`, `%Dictionary.IndexDefinition`, and `%Save`/`%OpenId`/`%DeleteId` are well-established. The Story 1.5 Installer scaffold (commit `03bf178`) already exercises the install lifecycle pattern this story extends — no new backend surface to probe.

### Auto-sync workflow + typed MCPs

Same as Stories 2.1–2.3: edit local files, do NOT call `iris_doc_load`. DO call `iris_doc_compile` and `iris_execute_tests`. For the install verification, prefer `iris_execute_classmethod SessionAgent.Installer Install` (typed MCP) over generic `iris_execute_command`. Discipline rule 3.

### Rule 4 stale-reference scan: Story 1.5 Installer.cls is the canonical seed-config reference

When updating `SeedDefaultAgentConfigs`, do NOT introduce new external dependency names that aren't already verified — the model names (`gpt-4o`, etc.) are confirmed in [architecture.md:308](../planning-artifacts/architecture.md). The credential-resolution mechanism (env-var name `OPENAI_API_KEY`) is also established. No new IRIS class names introduced.

### Property-shape gotcha: `InitialExpression`

ObjectScript `%Persistent` properties get default values from `InitialExpression`, NOT a YAML-style `= 1` after the type. Pattern:

```objectscript
Property ReadOnly As %Boolean [ InitialExpression = 1 ];
Property Enabled As %Boolean [ InitialExpression = 0 ];
Property SearchChatRetentionDays As %Integer [ InitialExpression = 30 ];
```

The `[Final]` modifier is not needed; defaults apply on `%New()` only.

### Constraints (from architecture)

- **Class location:** `src/SessionAgent/Config/Agent.cls` and `src/SessionAgent/Config/AgentDefaults.cls` (per [architecture.md:850](../planning-artifacts/architecture.md))
- **Test location:** `src/SessionAgent/Test/ConfigAgentTest.cls` — note the architecture diagram doesn't enumerate this test file separately (it's lumped under `Config.Agent` validation surface). Naming convention follows `JsonTest.cls`/`EnvSecretTest.cls`.
- **OD4 defaults:** OpenAI `gpt-4o` for both seed agents; alternative providers (Anthropic / Gemini / Ollama-compat) are reachable post-install via Epic 6 UI but not seeded.
- **`Enabled = 0` is critical:** the operator must explicitly opt in via the Epic 6 Zen form. Seeding with `Enabled = 1` would auto-activate agents on install — undesirable.

### Sources

- [epics.md:798–821 §"Story 2.4"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:308 OD4 defaults](../planning-artifacts/architecture.md) — model + provider seeding.
- [architecture.md:850 Config.Agent + AgentDefaults](../planning-artifacts/architecture.md) — class file paths.
- [architecture.md:864–867 Util/EnvSecret/Json/RetryWithBackoff](../planning-artifacts/architecture.md) — sibling utilities (Stories 2.1–2.3) Config.Agent's reference shape.
- [prd.md:602 NFR-S2](../planning-artifacts/prd.md) — credential confinement schema discipline.
- [`src/SessionAgent/Installer.cls` lines 246–288](../../src/SessionAgent/Installer.cls) — current `SeedDefaultAgentConfigs` placeholder body to replace.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Storage Sections", §"Naming Conventions", §"VSCode Auto-Sync Workflow".
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"Available Assertion Macros".

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (dev role via /bmad-dev-story)

### Debug Log References

None — no `^ClineDebug` use needed; all empirical verification went through typed MCPs (`iris_doc_compile`, `iris_execute_tests`, `iris_sql_execute`, `iris_global_kill`, `iris_execute_command`).

### Completion Notes List

**1. Compile transcripts (all 4 classes — clean):**

```
mcp__iris-dev-mcp__iris_doc_compile flags=cuk-d
{
  "success": true,
  "documents": ["SessionAgent.Config.Agent.cls", "SessionAgent.Config.AgentDefaults.cls",
                "SessionAgent.Installer.cls", "SessionAgent.Test.ConfigAgentTest.cls"],
  "compilationTime": "11ms"
}
```

**2. Test results — `SessionAgent.Test.ConfigAgentTest`:**

```
{"total":10,"passed":10,"failed":0,"skipped":0}
  AgentNameIdxIsUnique                       passed
  GetSeedConfigInspectionDefaults            passed
  GetSeedConfigSearchDefaults                passed
  GetSeedConfigUnknownAgentReturnsNull       passed
  GetSystemPromptInspectionMentionsToolNames passed
  GetSystemPromptSearchMentionsBoundedWhere  passed
  SavedRowRoundTrip                          passed
  SchemaHasNoApiKey                          passed
  SchemaPropertiesPresent                    passed
  SeedingIsIdempotent                        passed
```

**3. Full regression — per-class totals confirm 45/45:**

| Test class | Passed/Total |
|---|---|
| SessionAgent.Test.AuditEmitTest | 3/3 |
| SessionAgent.Test.ReadOnlyRoleTest | 6/6 |
| SessionAgent.Test.JsonTest | 9/9 |
| SessionAgent.Test.RetryWithBackoffTest | 9/9 |
| SessionAgent.Test.EnvSecretTest | 8/8 |
| SessionAgent.Test.ConfigAgentTest | 10/10 |
| **Total** | **45/45** |

Note: `iris_execute_tests level:package SessionAgent.Test` consistently reports 35/35 because of a known runner discovery quirk that omits `RetryWithBackoffTest` (9 tests) and `ReadOnlyRoleTest::RoleInstallIdempotent` (1 test) from the package-level run. Per-class invocation independently confirms each class passes — quirk is pre-existing, not introduced by this story.

**4. Schema-shape empirical confirmation (12 properties, correct types):**

```sql
SELECT Name, Type FROM %Dictionary.PropertyDefinition WHERE parent='SessionAgent.Config.Agent'
  ORDER BY SequenceNumber
```

| Name | Type |
|---|---|
| AgentName | %String |
| Provider | %String |
| Model | %String |
| MaxTokens | %Integer |
| Temperature | %Numeric |
| SystemPromptOverride | %String |
| CredentialName | %String |
| EnvVarName | %String |
| EndpointUrl | %String |
| ReadOnly | %Boolean |
| Enabled | %Boolean |
| SearchChatRetentionDays | %Integer |

`%Dictionary.PropertyDefinition.Type` returns the SHORT form (`%String`) not the fully-qualified (`%Library.String`). The first test run failed `TestSchemaPropertiesPresent` because the spec used the long form; corrected to short form to match the empirical truth (single-line edit, no schema change). `ApiKey` property absent — confirmed by `TestSchemaHasNoApiKey` and an independent SQL probe.

**5. Empirical install — first-run transcript (clean install):**

```
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] seeded session-inspection
[iris-session-agent] seeded message-search
```

**6. Empirical install — second-run transcript (idempotent re-install):**

```
[iris-session-agent] Config.Agent present — seeding default rows
[iris-session-agent] session-inspection: row already present; skipping
[iris-session-agent] message-search: row already present; skipping
```

Capture mechanism: `iris_execute_classmethod SessionAgent.Installer Install` failed because the parent `Install()` method writes operator reminders to the principal device, which jams the Atelier JSON envelope on response. `iris_execute_command "Set tSC=##class(SessionAgent.Installer).SeedDefaultAgentConfigs()"` is the documented capture path (it tunnels Write output back to the caller via the captured-I/O envelope). The seed helper's behavior is identical whether invoked via `Install()` or directly.

**7. Post-install row state — SQL extent verification:**

```sql
SELECT %EXACT(AgentName), Provider, Model, MaxTokens, Temperature, %EXACT(EnvVarName),
       Enabled, ReadOnly, SearchChatRetentionDays
FROM SessionAgent_Config.Agent ORDER BY AgentName
```

| AgentName | Provider | Model | MaxTokens | Temperature | EnvVarName | Enabled | ReadOnly | SearchChatRetentionDays |
|---|---|---|---|---|---|---|---|---|
| message-search | openai | gpt-4o | 4096 | 0 | OPENAI_API_KEY | false | true | 30 |
| session-inspection | openai | gpt-4o | 4096 | 0 | OPENAI_API_KEY | false | true | 30 |

Two rows, both with OD4 defaults. `Enabled=false` confirms the operator-opt-in invariant; `ReadOnly=true` confirms the L4 invariant.

**8. Stale-reference grep (Task 6, discipline rule 4):**

```
Grep over src/SessionAgent/Config/*.cls + src/SessionAgent/Test/ConfigAgentTest.cls
       + src/SessionAgent/Installer.cls
Pattern: HSCUSTOMCODE | %SessionAgent_ReadOnly
Matches: 0
```

**9. Design decisions worth noting:**

- **Storage section auto-generated on compile.** I authored `Agent.cls` without a Storage block per project rule §"Storage Sections"; the IRIS compiler (via the active VSCode auto-sync) added `Storage Default` on first compile. The class file now contains the auto-generated section — this is the correct steady-state and was NOT hand-authored.
- **`SeedDefaultAgentConfigs` made non-Private.** The original placeholder was `[ Private ]`. The new test class needs to invoke this method directly to exercise the idempotency + round-trip ACs; reflective invocation via `%ClassMethodCall` does not bypass `Private`. Removed the modifier from `SeedDefaultAgentConfigs` only; the new inner per-agent helper `SeedOneAgent` retains `[ Private ]` because it's a pure implementation detail.
- **`SeedOneAgent` extraction.** The spec showed a single in-line loop. I extracted per-agent logic to a `SeedOneAgent(pName)` private classmethod so a `%Save` failure on one agent (a) logs the agent name precisely, (b) returns the failing status to the caller without retrying the second agent, and (c) keeps the outer loop short and easy to read. Behavior matches the spec exactly; structure is slightly cleaner.

### File List

- `src/SessionAgent/Config/Agent.cls` (NEW) — `%Persistent` schema, 12 properties + unique `AgentNameIdx`. Storage section auto-generated by compiler.
- `src/SessionAgent/Config/AgentDefaults.cls` (NEW) — `GetSystemPrompt(name)` + `GetSeedConfig(name)` ClassMethods.
- `src/SessionAgent/Installer.cls` (UPDATE) — replaced `SeedDefaultAgentConfigs` placeholder body with real seeding loop; added private `SeedOneAgent(pName)` helper; updated doc comment to drop "deferred" language; removed `[ Private ]` from `SeedDefaultAgentConfigs` so tests can invoke it directly.
- `src/SessionAgent/Test/ConfigAgentTest.cls` (NEW) — 10 `Test*` methods per AC-4; ~251 lines; `OnBeforeOneTest`/`OnAfterOneTest` kill the data + index globals so seeding tests are isolated.

### Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-03 | Story 2.4 implementation: 3 NEW classes (`Config.Agent`, `Config.AgentDefaults`, `Test.ConfigAgentTest`) + Installer update. 10/10 ConfigAgentTest passing; 45/45 regression confirmed via per-class runs; empirical install transcripts captured (first-run seeds 2 rows; re-run idempotent skip). Schema discipline NFR-S2 verified (no `ApiKey` property). | dev (claude-opus-4-7[1m]) |
| 2026-05-03 | Code review: 0 HIGH / 0 MEDIUM / 1 LOW (deferred — package-level test runner discovery quirk extension to existing Story 2.3 entry) / 5 dismissed. ACs 1-5 all verified empirically (10/10 ConfigAgentTest, 45/45 regression sum). Storage section in `Agent.cls` verified as compiler-auto-generated per dev Completion Note #9 — not hand-authored, project rule honored. `SeedDefaultAgentConfigs` made non-Private + `SeedOneAgent` extraction both reviewed and accepted (matches spec failure-isolation behavior). Status remains `review` per single-task agent directive. | code-review (claude-opus-4-7[1m]) |

### Review Findings

- [x] [Review][Defer] Package-level test runner discovery quirk continues — extends existing Story 2.3 deferred entry with the Story 2.4 data point (now 35/45 at package level vs. 45/45 at per-class). Miss-list is consistent across stories (RetryWithBackoff entire class + ReadOnlyRole::RoleInstallIdempotent), ruling out a stale-metadata cause. Deferred, pre-existing.
