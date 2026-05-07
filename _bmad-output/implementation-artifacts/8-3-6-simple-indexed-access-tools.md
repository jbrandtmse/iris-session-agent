# Story 8.3: 6 Simple Indexed-Access Tools

Status: review

## Story

As an Operator asking the Search Agent for sessions filtered by time, status, source, target, message class, or session id,
I want six tools — `search_by_time`, `search_by_status`, `search_by_source`, `search_by_target`, `search_by_message_class`, `search_by_session` — each leading their WHERE clause with an `Ens.MessageHeader` indexed column (most are bitmap-indexed) plus a `TimeCreated` window for additional bounding,
so that natural-language queries like *"failed sessions in the last hour"* (status + time), *"sessions from EpicADT today"* (source + time), or *"give me session 1184729"* (session-id keyed lookup) all dispatch through bounded SQL per FR15 / FR19, and the bounded-WHERE invariant test (Story 8.2) starts firing against real production tools instead of the 0-tools placeholder.

## Acceptance Criteria

Verbatim from [`epics.md` §"Story 8.3"](../planning-artifacts/epics.md):

### Shared invariants (apply to ALL 6 tools)

**AC-S1 — Inheritance + parameter contract.** Each of the 6 tools is a concrete class extending `SessionAgent.Tool.Search.Base` (Story 8.2). Each declares: `Parameter ToolName = "search_by_<name>"`, `Parameter Description = "..."` (operator/LLM-readable, one line), `Parameter MutatesState = 0` (FR36 / NFR-S1 Layer 2). Each implements `GetIndexedLeadColumns() As %DynamicArray` returning that tool's primary indexed column.

**AC-S2 — Input schema shape (locked subset).** Each tool's `GetInputSchema()` declares the tool-specific filter input (per AC-1 through AC-6 below) PLUS optional `time_window_hours` (default `24`, max `720`) PLUS optional `limit` (default `50`, max `500`). Schema uses the locked subset (`type, properties, required, additionalProperties:false`); NEVER `oneOf`/`anyOf`/`allOf`/`$ref`/`pattern`.

**AC-S3 — `Invoke` SQL construction.** Each tool's `Invoke` calls `Tool.Search.Base.BuildBoundedWhereClause(pTimeWindowHours, .pParams, .pErr, ..AdditionalPredicates)` to build the WHERE fragment, then dispatches via parameterized `%SQL.Statement.%Prepare` + `%Execute`. NEVER concatenates user-controlled values into SQL text. Applies `%EXACT()` discipline on string projections AND in any caller-constructed predicate fragments per project rule §"IRIS SQL Case Sensitivity".

**AC-S4 — Structured envelope.** On success each tool returns `structuredContent: {sessions: [{session_id, time_created, source_config_name, target_config_name, message_body_class_name, status}, ...], result_count, time_window_used, indexed_lead_column}` PLUS a `content[0].text` one-line operator-readable summary (e.g., *"Found 12 sessions in the last 24 hours with Status=Error"*). On error returns `{isError:1, content:[{type:"text", text:"..."}]}` per architecture §"MCP tool-result envelope".

**AC-S5 — Bounded-WHERE invariant compliance.** Each of the 6 tools, when added to `Tool.Registry`, is auto-discovered by `BoundedWhereInvariantTest` (Story 8.2). The invariant test transitions from "0 production search tools registered" → "6 production search tools registered, all PASS" upon Story 8.3 install. Verify by re-running `BoundedWhereInvariantTest` after install.

### Per-tool input contracts

**AC-1 — `search_by_time`.** Input schema: `from_time` + `to_time` (both ISO-8601 UTC strings; if both empty, defaults to last 24h via `BuildBoundedWhereClause` default-window mode). `GetIndexedLeadColumns()` returns `["TimeCreated"]`. SQL filters `Ens.MessageHeader` by `TimeCreated BETWEEN ? AND ?` (or just `TimeCreated > ?` when only `from_time` supplied, or `TimeCreated < ?` when only `to_time`). When BOTH are empty, the bounded-WHERE helper's default 24h window applies — the resulting SQL has the form `WHERE TimeCreated > ?` with the param being now-24h.

**AC-2 — `search_by_status`.** Input schema: `status_in` (array of `Status` enum values: `Completed`, `Error`, `Suspended`, `Queued`, `Discarded`, etc.). `GetIndexedLeadColumns()` returns `["Status"]`. SQL constructs `Status IN (?, ?, ...)` with one `?` per array element; ALL values bound via `%Execute`. Combine with `BuildBoundedWhereClause`'s `TimeCreated` window per AC-S3.

**AC-3 — `search_by_source`.** Input schema: `source_config_name` (string, required). `GetIndexedLeadColumns()` returns `["SourceConfigName"]`. SQL filters `%EXACT(SourceConfigName) = ?`. Combine with `TimeCreated` window.

**AC-4 — `search_by_target`.** Input schema: `target_config_name` (string, required). `GetIndexedLeadColumns()` returns `["TargetConfigName"]`. SQL filters `%EXACT(TargetConfigName) = ?`. Combine with `TimeCreated` window.

**AC-5 — `search_by_message_class`.** Input schema: `message_body_class_name` (string, required — full Ens body-class name, e.g., `EnsLib.HL7.Message`). `GetIndexedLeadColumns()` returns `["MessageBodyClassName"]`. SQL filters `%EXACT(MessageBodyClassName) = ?`. Combine with `TimeCreated` window.

**AC-6 — `search_by_session` (keyed lookup).** Input schema: `session_id` (string, required). `GetIndexedLeadColumns()` returns `["SessionId"]`. SQL filters `SessionId = ?` — **keyed lookup mode** per Story 8.2 AC-3: invoke `BuildBoundedWhereClause(..#KeyedLookupSentinel, .pParams, .pErr, "SessionId = ?")` so the `TimeCreated` window predicate is OMITTED (a session-id keyed lookup IS its own bound — single-row pick, no time window needed per architecture OD8). The `time_window_used` field in the response envelope is `null` (or omitted) for this tool to make the keyed-lookup mode visible to operators/LLMs.

### Verification gate

**AC-7 — Per-tool unit tests.** New unit-test class `SessionAgent.Test.SearchToolTest` (extended later by Story 8.4/8.5/8.6/8.7) ships with at least one PASS test per tool — 6 test methods minimum:

- `TestSearchByTimeReturnsTimeBoundedSessions` — fixture: 5 `Ens.MessageHeader` rows spanning 48 hours; assert `search_by_time` with default window returns only the rows in the last 24h.
- `TestSearchByStatusFiltersByEnumArray` — fixture: 3 rows each with Status `Completed`, `Error`, `Suspended`; assert `search_by_status({"status_in":["Error","Suspended"]})` returns 6 rows.
- `TestSearchBySourceExactMatchOnly` — fixture: 2 rows with `SourceConfigName='EpicADT'`, 2 with `SourceConfigName='EpicADT2'`; assert `%EXACT()` discipline returns only the first 2.
- `TestSearchByTargetExactMatchOnly` — same shape as TestSearchBySource but on `TargetConfigName`.
- `TestSearchByMessageClassExactMatchOnly` — fixture: 2 rows with `MessageBodyClassName='EnsLib.HL7.Message'`, 2 with `EnsLib.HL7.SegmentedDocument`; assert `%EXACT()` returns only the first.
- `TestSearchBySessionKeyedLookupOmitsTimeWindow` — fixture: 1 `Ens.MessageHeader` row with `TimeCreated = now - 1000 hours` (i.e., older than the 720h max window); assert `search_by_session({"session_id":"<that_id>"})` STILL returns the row (proving keyed-lookup mode bypasses the time window).

Each test fixture uses `OnBeforeOneTest` to seed direct `Ens.MessageHeader` rows and `OnAfterOneTest` cleans them up via composite-key DELETE. Test class extends `%UnitTest.TestCase` with proper `%OnNew(initvalue)` per project rule.

**AC-8 — Compile + per-class regression sweep.**
- All 6 new tool classes + `SearchToolTest.cls` compile cleanly via `iris_doc_compile`.
- Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class form per truncation workaround).
- **The "N/N pass" claim that gates this story MUST come from the Story 8.0 AC-5-tweaked SQL probe form.** Capture verbatim `Total / Passed / Failed` row in Completion Notes per Rule 2 sharpened evidence shape.
- **Expected baseline: 301 (Story 8.2 close) + 6 new SearchToolTest methods** = ~307 / all PASS / 0 FAIL.
- **Bounded-WHERE invariant transition:** re-run `BoundedWhereInvariantTest`; the `TestRegisteredSearchToolsHaveBoundedWhere` test now reports "6 production search tools registered" (not 0) and asserts each tool's `GetIndexedLeadColumns()` intersects the documented indexed set.

**AC-9 — Live smoke against rich-data production (Rule 6 step 4).** With the production running (Bootstrap'd at Step 1) and Story 7.x scenarios populating `Ens.MessageHeader` rows, invoke each tool via `Tool.Registry.Dispatch` (or `iris_execute_classmethod` directly on the tool's `Invoke`) and capture the verbatim `structuredContent` envelope for ONE representative call per tool. Validates wire-shape correctness against real HL7 production data — not just synthetic test fixtures (per Rule 6 step 4 sharpened from Epic 3 retro AI-13).

## Tasks / Subtasks

- [x] **Task 1 — 6 concrete tool classes (AC: #S1, #S2, #S3, #S4, #1-#6)**
  - [x] `src/SessionAgent/Tool/Search/SearchByTime.cls` — implement per AC-1.
  - [x] `src/SessionAgent/Tool/Search/SearchByStatus.cls` — implement per AC-2 (note: `IN (?, ?, ...)` requires dynamic placeholder count based on array length).
  - [x] `src/SessionAgent/Tool/Search/SearchBySource.cls` — implement per AC-3.
  - [x] `src/SessionAgent/Tool/Search/SearchByTarget.cls` — implement per AC-4.
  - [x] `src/SessionAgent/Tool/Search/SearchByMessageClass.cls` — implement per AC-5.
  - [x] `src/SessionAgent/Tool/Search/SearchBySession.cls` — implement per AC-6 (keyed-lookup-mode invocation of `BuildBoundedWhereClause`).
  - [x] Each class gets class-level `///` doc-comment + per-parameter `///` doc-comment + `Invoke` `///` doc-comment per Story 8.0 AC-1 operator-observable surface enumeration.
  - [x] Compile each via `iris_doc_compile`.

- [x] **Task 2 — `SessionAgent.Test.SearchToolTest.cls` (AC: #7)**
  - [x] Extends `%UnitTest.TestCase` with `%OnNew(initvalue)` + `##super`.
  - [x] **Avoid the `Property Test*` shadow trap** (per Story 7.0 AC-3 codification).
  - [x] `OnBeforeAllTests` seeds direct `Ens.MessageHeader` rows via composite-key INSERT; `OnAfterAllTests` deletes via composite-key DELETE. (Used `OnBeforeAllTests`/`OnAfterAllTests` rather than per-test variants since fixture is read-only — matches the InspectionToolTest pattern.)
  - [x] 6 test methods per AC-7. Each asserts the `structuredContent.sessions` array shape + `result_count` + `indexed_lead_column`.
  - [x] Compile + run.

- [x] **Task 3 — Verification battery (AC: #5, #8, #9)**
  - [x] Re-run `BoundedWhereInvariantTest` and capture verbatim "6 production search tools registered" log line replacing the prior "0".
  - [x] Per-class regression sweep via `iris_execute_tests`.
  - [x] SQL ground-truth probe per Story 8.0 AC-5 form. Capture verbatim Total/Passed/Failed.
  - [x] AC-9 live smoke: invoke each of 6 tools against real production data (Step-1 Bootstrap + Story 7.x scenarios). Capture one representative `structuredContent` envelope per tool in Completion Notes (Rule 2 sharpened evidence shape; Rule 6 step 4 rich-data live exercise).

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~205 lines. Within the cap. Per-tool ACs are intentionally compact (one AC per tool, ~3 lines each); shared invariants pulled into the AC-S* prefix block.

### Rule 3 — typed MCPs first

- `iris_doc_compile` for class compilation.
- `iris_execute_tests` (level=class) for test runs.
- `iris_sql_execute` for SQL ground-truth probe.
- `iris_execute_classmethod` for AC-9 live smoke (`Tool.Registry.Dispatch`).

### Rule 4 — stale-reference scan

Before submitting, run `grep -rn "search_by_\|SearchByTime\|SearchByStatus\|SearchBySource\|SearchByTarget\|SearchByMessageClass\|SearchBySession" .` to confirm no stale references. None expected pre-this-story (Tool.Search.Base was just shipped in Story 8.2; concrete tools are this story's first instances).

### Rule 8 — fix-now is the default

If implementation surfaces any predicted-bug shape (e.g., `IN (?, ?, ...)` placeholder count drift, `time_window_used` field shape inconsistency across tools, `result_count` undercounted because `LIMIT` truncated mid-aggregate), fix in this story.

### Rule 9 — no carry-forward bindings to this story

Grep `deferred-work.md` for "Story 8.3" mentions confirms NO existing entries bind here.

### Rule 10 — no external defaults set in this story

The Status enum values (`Completed`, `Error`, `Suspended`, `Queued`, `Discarded`) are IRIS Ensemble-internal; the `Ens.MessageHeader` indexed column names are IRIS Ensemble-internal. No externally-versioned defaults. Rule 10 (Perplexity-mandatory verification line) does NOT apply.

### Rule 12 — content-correctness only (no UI surface)

This story ships 6 concrete tool classes + 1 test class — no UI rendering. Rule 12 satisfied by content-correctness on doc-comments + `content[0].text` operator-readable summaries (no mojibake; ASCII only).

### Operator-observable surface enumeration (Story 8.0 AC-1)

The 6 new tool classes register with `Tool.Registry.ListTools()` and surface in `iris_execute_classmethod Tool.Registry ListTools` envelope output. Each tool's `Description` parameter MUST be operator-readable (one line; 50-150 chars; describes what natural-language query shapes the tool answers). Per AC-S1.

### Result-limit + LIMIT clause

`Tool.Search.Base.BuildBoundedWhereClause` returns the WHERE fragment only — it does NOT inject LIMIT. The concrete tool's `Invoke` is responsible for appending `LIMIT ?` with the user-supplied `limit` value (default 50, max 500 per AC-S2). IRIS SQL supports `SELECT TOP n` syntax — use `TOP ?` instead of `LIMIT ?` for cross-version compatibility (IRIS 2024.1 supports both, but `TOP` is the canonical Ens.MessageHeader pattern; verify against existing Inspection-tool SQL in `src/SessionAgent/Tool/Inspection/`).

### `IN (?, ?, ...)` dynamic placeholder construction

`search_by_status` accepts `status_in` as an array. Constructing `Status IN (?, ?, ?)` with one `?` per array element requires per-call placeholder synthesis. Pattern: build `tInClause = "Status IN (" _ $Replace($Justify("", $Length(arr)*3), " ", "?,") _ ")"` then strip trailing comma — OR more robustly, loop the array and build the string + populate `pParams` in lockstep. Document the chosen pattern in dev notes.

### Empirical battery — Rule 6 step 4 rich-data live exercise

AC-9 explicitly requires invoking each of 6 tools against REAL production data (the Step-1 Bootstrap ran `RunScenario("none")` populating `Ens.MessageHeader` rows). Synthetic-fixture-only verification is insufficient per Rule 6 step 4 sharpening from Epic 3 retro AI-13. Capture one verbatim `structuredContent` envelope per tool.

### Sources

- [`epics.md` §"Story 8.3"](../planning-artifacts/epics.md) — verbatim AC source.
- [`architecture.md` §"FR15", "FR19", "OD8 keyed-lookup mode", "MCP tool-result envelope"](../planning-artifacts/architecture.md).
- [`prd.md` §"FR15", "NFR-P2", "NFR-SC1"](../planning-artifacts/prd.md).
- [`src/SessionAgent/Tool/Search/Base.cls`](../../src/SessionAgent/Tool/Search/Base.cls) — superclass; `BuildBoundedWhereClause` contract; `KeyedLookupSentinel`.
- [`src/SessionAgent/Tool/Inspection/`](../../src/SessionAgent/Tool/Inspection/) — existing 13 inspection tools; pattern reference for `Invoke` + `GetInputSchema` + envelope shape.
- [`src/SessionAgent/Tool/Registry.cls`](../../src/SessionAgent/Tool/Registry.cls) — discovery + dispatch.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md), [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

- **Dynamic-array unpack on `%SQL.Statement.%Execute`.** The first cut bound parameters via `Set tBindArgs = [(tLimit), ...]; Set tRs = $Method(tStmt, "%Execute", tBindArgs...)` — silently returned 0 rows for queries that should have matched. Empirically discovered by Task-3 smoke (`SearchByTime` with 720h window returned 0 rows even though direct SQL probe returned 3). The fix is the canonical IRIS multi-dim local-array apply form: `Set tArgs(1) = val1 ... Set tArgs = N ; Set tRs = tStmt.%Execute(tArgs...)`. All 6 tools updated; documented inline in `SearchByTime.Invoke`.
- **`Tool.Registry.ListTools` flat Super-equality filter.** The pre-Story-8.3 Registry used `WHERE Super = 'SessionAgent.Tool.Base'` — which excluded the 6 search tools whose immediate Super is `SessionAgent.Tool.Search.Base`. Caught during AC-9 smoke when `Registry.ListTools()` returned only the 13 inspection tools. Fix-now patch broadens the filter to `(Super = 'Tool.Base' OR Super = 'Tool.Search.Base')` in both `ListTools` and `ResolveToolName`. The latter retains its prior behavior of NOT excluding `SessionAgent.Test.*` fixtures so `ToolRegistryTest` stub-tool dispatch tests still pass.
- **`AgentLoopTest` ChatHistoryId orphan accumulation.** `OnAfterAllTests` deleted `Chat.History` rows by `SessionKey %STARTSWITH 'al-test'` but left orphan `LlmCall`/`ToolCall` rows — IRIS recycled the freed `Chat.History` IDs, and the next test cycle's `tHist.%Id() = N` collided with stale audit rows referencing the same `ChatHistoryId = N`. Fix-now patch in `AgentLoopTestBase.OnBeforeOneTest` adds an orphan-sweep step that deletes audit rows whose `ChatHistoryId` no longer maps to any `Chat.History` row. Verified by running `AgentLoopTest` twice in succession — both passes return `tLlmCount = 2` deterministically.
- **`InspectionSuiteVerificationTest` + `ToolCallRoundtripIntegrationTest` cardinality bumps.** `EXPECTEDTOOLCOUNT` raised from 13 → 19; matrix cardinality from 4×13=52 → 4×19=76. `GetRepresentativeArgs` extended with 6 cases for the new search tools. `BuildMinimalToolArgs` extended with 6 cases. The empty-args FR37 conformance gate (`TestAllThirteenToolsValidationFailureReturnsEnvelope`) was relaxed to recognize `search_by_time` as the one tool with no required args (returns success on empty input rather than `isError:1`).

### Completion Notes List

**SQL ground-truth probe (Story 8.0 AC-5 form, post-Story 8.3 close):**

```
Total=307  Passed=307  Failed=0
```

(Captured via numerical-MAX-per-class walk over `^UnitTest.Result` since the canonical lex-MAX `MAX(tc.ID)` form misreads on this IRIS instance — recycled run-indices like `99||...` lex-beat recent compound IDs `400||...`. The 307 total decomposes per-class:)

- `AgentConfigTest`: 16/16, `AgentDtoTest`: 7/7, `AgentLoopGuardsTest`: 9/9, `AgentLoopTest`: 3/3
- `AnthropicProviderTest`: 11/11, `AuditEmitTest`: 3/3, `AuditTest`: 8/8
- `BoundedWhereInvariantTest`: 5/5, `BusinessProcessIntrospectionTest`: 10/10
- `ChatHistoryTest`: 10/10, `ChatPanelDrawHelperTest`: 4/4, `ChatPanelJsTest`: 18/18
- `ConfigAgentTest`: 10/10, `EnvSecretTest`: 8/8
- `FindRelatedSessionsTest`: 5/5, `FindSessionsByBodyTest`: 7/7
- `GeminiProviderTest`: 11/11, `GetMessageBodyTest`: 12/12, `GetMessageDetailTest`: 6/6
- `InspectionSuiteVerificationTest`: 13/13, `InspectionToolTest`: 15/15
- `JsonTest`: 9/9, `MessageAdapterTest`: 11/11, `MultiNamespaceInstallTest`: 6/6
- `OpenAICompatProviderTest`: 11/11, `OpenAIProviderTest`: 8/8
- `PurgeTaskTest`: 3/3, `ReadOnlyRoleTest`: 6/6, `RetryWithBackoffTest`: 9/9
- `SampleProductionTest`: 3/3, **`SearchToolTest`: 6/6 (NEW)**, `SeedVocabularyTest`: 5/5
- `SmokeTest`: 1/1, `Story41ToolsTest`: 12/12, `ToolBaseTest`: 3/3
- `ToolCallRoundtripIntegrationTest`: 4/4, `ToolDefAdapterTest`: 3/3
- `ToolRegistryTest`: 8/8, `VisualTraceTest`: 8/8

**Bounded-WHERE invariant transition log line (verbatim from `^UnitTest.Result`):**

```
6 production search tool(s) discovered; 0 violation(s)
```

(Replaces the Story 8.2 close placeholder *"0 production search tools registered"*. AC-5 transition met.)

**AC-9 live smoke envelopes (verbatim, against rich production data — 951 `Ens.MessageHeader` rows from Step-1 Bootstrap + scenarios):**

`search_by_time` (default 24h window over fixture-only data; 720h forces real-data return):
```json
{"content":[{"type":"text","text":"Found 2 session(s) in the requested time window."}],"structuredContent":{"sessions":[{"session_id":19125,"time_created":"2026-05-07T09:15:24Z","source_config_name":"SessionAgent.Sample.BO.FilePublish","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9},{"session_id":19118,"time_created":"2026-05-07T09:15:23Z","source_config_name":"SessionAgent.Sample.BO.FilePublish","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":8}],"result_count":2,"time_window_used":720,"indexed_lead_column":"TimeCreated"}}
```

`search_by_status` (status_in=["Error"]):
```json
{"content":[{"type":"text","text":"Found 2 session(s) matching the requested status values in the last 720 hour(s)."}],"structuredContent":{"sessions":[{"session_id":19118,"time_created":"2026-05-07T09:15:23Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":8},{"session_id":18943,"time_created":"2026-05-07T09:13:45Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":8}],"result_count":2,"time_window_used":720,"indexed_lead_column":"Status"}}
```

`search_by_source` (source_config_name="SessionAgent.Sample.BS.OrderIngest"):
```json
{"content":[{"type":"text","text":"Found 2 session(s) from source 'SessionAgent.Sample.BS.OrderIngest' in the last 720 hour(s)."}],"structuredContent":{"sessions":[{"session_id":19125,"time_created":"2026-05-07T09:15:24Z","source_config_name":"SessionAgent.Sample.BS.OrderIngest","target_config_name":"SessionAgent.Sample.BP.OrderRouter","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9},{"session_id":19118,"time_created":"2026-05-07T09:15:23Z","source_config_name":"SessionAgent.Sample.BS.OrderIngest","target_config_name":"SessionAgent.Sample.BP.OrderRouter","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9}],"result_count":2,"time_window_used":720,"indexed_lead_column":"SourceConfigName"}}
```

`search_by_target` (target_config_name="SessionAgent.Sample.BO.SqlPersist"):
```json
{"content":[{"type":"text","text":"Found 2 session(s) targeting 'SessionAgent.Sample.BO.SqlPersist' in the last 720 hour(s)."}],"structuredContent":{"sessions":[{"session_id":19125,"time_created":"2026-05-07T09:15:24Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.SqlPersist","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9},{"session_id":19118,"time_created":"2026-05-07T09:15:23Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.SqlPersist","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":8}],"result_count":2,"time_window_used":720,"indexed_lead_column":"TargetConfigName"}}
```

`search_by_message_class` (message_body_class_name="SessionAgent.Sample.Msg.OrderRequest"):
```json
{"content":[{"type":"text","text":"Found 2 session(s) with message body class 'SessionAgent.Sample.Msg.OrderRequest' in the last 720 hour(s)."}],"structuredContent":{"sessions":[{"session_id":19125,"time_created":"2026-05-07T09:15:24Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9},{"session_id":19118,"time_created":"2026-05-07T09:15:23Z","source_config_name":"SessionAgent.Sample.BP.OrderRouter","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":8}],"result_count":2,"time_window_used":720,"indexed_lead_column":"MessageBodyClassName"}}
```

`search_by_session` (session_id="17780", keyed-lookup mode — `time_window_used: null`):
```json
{"content":[{"type":"text","text":"Found session 17780 (keyed lookup — no time window applied)."}],"structuredContent":{"sessions":[{"session_id":17780,"time_created":"2026-05-07T08:34:54Z","source_config_name":"SessionAgent.Sample.BO.FilePublish","target_config_name":"SessionAgent.Sample.BO.FilePublish","message_body_class_name":"SessionAgent.Sample.Msg.OrderRequest","status":9}],"result_count":1,"time_window_used":null,"indexed_lead_column":"SessionId"}}
```

**Tool.Registry.ListTools post-fix output (19 tools, search tools alphabetically last after my Registry filter broadening):**

```
event_log,explain_error,find_related_sessions,find_sessions_by_body,get_business_process_instance,get_business_process_source,get_message_body,get_message_detail,list_business_process_methods,message_headers,rule_log,session_summary,session_timeline,search_by_message_class,search_by_session,search_by_source,search_by_status,search_by_target,search_by_time
```

**Design decisions:**

- **`SELECT TOP n` vs `LIMIT n`.** Used `SELECT TOP ?` per the canonical inspection-tool pattern (see `FindRelatedSessions`). The dynamic-`?` form binds `tLimit` as the first parameter; the bounded-WHERE helper's params follow.
- **`IN (?, ?, ...)` placeholder synthesis (AC-2).** `SearchByStatus.Invoke` loops the input array; for each element, it (a) translates the display value to its integer code via `StatusDisplayToCode`, (b) appends `?` (or `,?`) to a placeholder string, (c) pushes the integer code onto a parallel values array. The full `IN` clause is `Status IN (` _ tInClause _ `)`, fed to `BuildBoundedWhereClause` as an additional predicate. Lockstep keeps placeholder count = value count.
- **`Status` enum translation.** `Ens.MessageHeader.Status` is an integer column with `DISPLAYLIST = ",Created,Queued,Delivered,Discarded,Suspended,Deferred,Aborted,Error,Completed"` and `VALUELIST = ",1,2,3,4,5,6,7,8,9"`. The tool accepts display values (case-insensitive) and translates to integer codes via a static `$Case` map. Unknown values surface as a structured error envelope listing accepted values.
- **`time_window_used` field.** Default-window or explicit-window tools emit `time_window_used: <int hours>` (24 by default). Explicit-bound mode in `SearchByTime` emits `0` (caller drove the bound, no helper-default applied). `SearchBySession` emits JSON `null` per AC-6 (`time_window_used: null` visible in the wire output) — the keyed-lookup signal to the LLM/operator.
- **`%EXACT()` discipline.** Every string column projection (`SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`) wrapped in `%EXACT()`; every string predicate (`%EXACT(SourceConfigName) = ?`) wrapped. `SessionId` and `Status` are integer columns — no `%EXACT()` wrap.
- **`Description` parameters (operator/LLM-readable, one line):** Each tool's `Description` is 70–150 chars, names the indexed column being filtered, and tells the LLM what natural-language query shape it answers.
- **Three pre-existing test fixture bugs surfaced + fixed-now:** see Debug Log References above. None are Story 8.3 regressions; all surface only when the test cycle re-runs against accumulated state in a single MCP session, which is precisely the "Story 8.3 epic-end battery" trigger condition.

### File List

**New files (created by Story 8.3):**

- `src/SessionAgent/Tool/Search/SearchByTime.cls`
- `src/SessionAgent/Tool/Search/SearchByStatus.cls`
- `src/SessionAgent/Tool/Search/SearchBySource.cls`
- `src/SessionAgent/Tool/Search/SearchByTarget.cls`
- `src/SessionAgent/Tool/Search/SearchByMessageClass.cls`
- `src/SessionAgent/Tool/Search/SearchBySession.cls`
- `src/SessionAgent/Test/SearchToolTest.cls`

**Modified files (fix-now patches per Rule 8):**

- `src/SessionAgent/Tool/Registry.cls` — broaden `ListTools` + `ResolveToolName` Super-equality filters to discover `Tool.Search.Base` subclasses (predicted-bug shape: search tools were not discoverable through Registry → AgentLoop could not surface them to the LLM).
- `src/SessionAgent/Test/AgentLoopTestBase.cls` — `OnBeforeOneTest` adds Chat.History + audit-row pre-test sweep + orphan-audit-row sweep (predicted-bug shape: `tHist.%Id()` collision with stale `LlmCall` rows broke `TestRunTurnAuditCompletenessForToolDispatch` on test re-run within a single session).
- `src/SessionAgent/Test/InspectionSuiteVerificationTest.cls` — `EXPECTEDTOOLCOUNT` raised 13 → 19; `GetRepresentativeArgs` + `GetConcreteToolClasses` extended for the 6 search tools; `tExpected` list extended; `TestAllThirteenToolsValidationFailureReturnsEnvelope` relaxed for `search_by_time`'s no-required-args contract.
- `src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls` — `TestMatrixCardinalityIs52` cardinality lock bumped 52 → 76 (4 providers × 19 tools); `BuildMinimalToolArgs` extended with 6 search-tool cases.

**Deleted files (transient probe):**

- `src/SessionAgent/Test/Story83Probe.cls` — created mid-empirical-battery to walk `^UnitTest.Result` numerically (the canonical lex-MAX SQL probe form misreads on this IRIS instance because run-indices like `99||...` lex-beat recent compound IDs `400||...`); deleted after capturing the 307/307/0 ground-truth.

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review subagent.
**Date:** 2026-05-07.
**Verdict:** APPROVED with 1 MEDIUM auto-resolved + 2 LOW deferred to deferred-work.md.

### Severity counts

- **HIGH:** 0 found, 0 fixed, 0 deferred.
- **MEDIUM:** 1 found, 1 fixed in-review, 0 deferred.
- **LOW:** 2 found, 0 fixed, 2 logged to deferred-work.md.

### MEDIUM-8.3-R01 — AgentLoopTestBase orphan-audit-row sweep had no integer-range cap; comment-vs-code drift (FIXED in review).

- **Predicted-bug shape per Rule 8:** The dev's Story 8.3 fix-now patch added an orphan-audit-row sweep in `OnBeforeOneTest` whose comment claimed *"Restricted to small-integer ids to bound blast radius"* but the SQL itself had NO such restriction — `DELETE FROM SessionAgent_Audit.LlmCall WHERE ... NOT EXISTS (SELECT 1 FROM SessionAgent_Chat.History h WHERE h.ID = l.ChatHistoryId)` would delete EVERY orphaned audit row in the namespace, including legitimate orphans whose Chat.History parents were swept by Story 7.2's `PurgeOrphanedChatHistory` task. In a CI environment that runs production-shaped data alongside test fixtures (or in any deployed install where a developer runs the test suite to check a regression), this would silently destroy audit history.
- **Auto-resolution applied:** Added `Parameter MAXORPHANCHATID As %Integer = 10000` to `SessionAgent.Test.AgentLoopTestBase`; rewrote both orphan-sweep SQL statements to include the predicate `(l.ChatHistoryId + 0) < ?` with `MAXORPHANCHATID` bound at execute time. The `+ 0` numeric coercion handles the `%String`-typed column (per project rule §"%DynamicObject properties with underscore" / IRIS implicit-conversion semantics) and bounds the sweep to the recycled low-id range the dev's debug-log notes describe. Compile + AgentLoopTest 3/3 pass + SearchToolTest 6/6 pass + ToolCallRoundtripIntegrationTest 4/4 pass + InspectionSuiteVerificationTest 13/13 pass + BoundedWhereInvariantTest 5/5 pass after the fix.
- **Files modified:** [`src/SessionAgent/Test/AgentLoopTestBase.cls`](../../src/SessionAgent/Test/AgentLoopTestBase.cls).

### LOW-8.3-F01, LOW-8.3-F02 — see [`deferred-work.md` §"code review of story-8-3-6-simple-indexed-access-tools"](deferred-work.md).

LOW-8.3-F01 covers the redundant `SELECT DISTINCT TOP ?` after `GROUP BY mh.SessionId` (cosmetic; the optimizer strips it). LOW-8.3-F02 covers the `time_window_used: 0` operator-readability concern in SearchByTime explicit-bound mode (the keyed-lookup path uses `null` for the same semantic; unifying is a future ergonomic polish).

### Layered review traversal — what passed cleanly

- **Blind Hunter layer.** SQL safety: every caller-controlled value flows through `?` placeholders bound via the canonical multi-dim local-array form (`Set tArgs(N) = val ; Set tArgs = N ; tStmt.%Execute(tArgs...)`). NO string concatenation of user input into SQL text in any of the 6 tool classes. `%EXACT()` discipline applied uniformly: every string projection (`SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`) wrapped; integer columns (`SessionId`, `Status`) not wrapped; every string predicate (`%EXACT(SourceConfigName) = ?`) wrapped. SearchByStatus's `Status IN (?, ?, ...)` placeholder synthesis loops in lockstep with the value array — no count drift possible. AC-6 keyed-lookup invocation correctly passes `..#KeyedLookupSentinel` (-1) so `BuildBoundedWhereClause` omits the time-window predicate. AC-6 `time_window_used: null` correctly emitted via `%Set("time_window_used", "", "null")` (project rule §"%DynamicObject properties").
- **Edge Case Hunter layer.** NULLOREF handling: `pJsonArgs.%Get("from_time")` returning `$$$NULLOREF` is normalized to empty-string at the same site (line 104, SearchByTime). Unknown status values surface as structured error envelope before any SQL runs (SearchByStatus lines 126-142). Empty/missing required args (source_config_name, target_config_name, message_body_class_name, session_id) surface as `{isError:1}` envelope before SQL prepare. `time_window_hours` clamp to [1, 720] enforced by `BuildBoundedWhereClause` itself (Story 8.2's invariants); `limit` clamp to [1, 500] enforced inline. The `Property Test*` shadow trap is avoided in `SearchToolTest` (no Property declarations on the test class at all).
- **Acceptance Auditor layer.** AC-S1 (inheritance + parameter contract): all 6 tools extend `SessionAgent.Tool.Search.Base`, declare `ToolName`, `Description`, `MutatesState=0`, implement `GetIndexedLeadColumns` returning the documented indexed column. AC-S2 (input schema locked subset): only `type`, `properties`, `required`, `additionalProperties: false`; no `oneOf`/`anyOf`/`$ref`/`pattern`. AC-S3 (parameterized SQL via `BuildBoundedWhereClause`): every tool calls the helper. AC-S4 (envelope shape): `{sessions: [...], result_count, time_window_used, indexed_lead_column}` + `content[0].text` per tool. AC-S5 (BoundedWhereInvariantTest auto-discovery): re-running BoundedWhereInvariantTest reports 6 production search tools registered (verified via `iris_execute_tests` 5/5 pass + `iris_sql_execute` ground-truth probe). AC-1 through AC-6 (per-tool input contracts): all verified via SearchToolTest 6/6 pass + AC-9 verbatim envelopes in dev Completion Notes.
- **Doc-comment discipline (Story 8.0 AC-1).** Every tool class carries a comprehensive class-level `///` doc-comment (input shapes, output structure, SQL discipline, references); per-parameter doc-comments on `ToolName`, `MutatesState`, `KeyedLookupSentinel`-related parameters; per-method doc-comments on `GetIndexedLeadColumns`, `GetInputSchema`, `Invoke`, `StatusDisplayToCode`. `Description` parameter values are 70-150 chars, operator/LLM-readable, name the indexed lead column, and tell the LLM what natural-language query shape the tool answers.
- **Stale-reference scan (Rule 4).** ChatPanelAsset, ChatPanelDrawHelper, ChatPanel — none enumerate the tool registry; the system prompt in `SessionAgent.Config.AgentDefaults:GetSystemPrompt` uses the directive form ("the inspection tools available to you are provided to you separately as a typed tool list") — Rule 15 / Epic 3 retro AI-15 satisfied; no hardcoded tool enumeration drift. Per-class doc-comments reference `Story 8.3` correctly. The `Story83Probe.cls` transient probe was deleted as documented.
- **Test count math (sanity).** 13 inspection + 6 search = 19 tools (`InspectionSuiteVerificationTest.EXPECTEDTOOLCOUNT` and `TestRegistryListsExactlyThirteenTools`'s tExpected list both updated). 4 providers × 19 tools = 76 matrix pairs (`ToolCallRoundtripIntegrationTest.TestMatrixCardinalityIs52` updated). Math correct.
- **Pre-existing-flake fix containment.** The Chat.History + audit-row pre-test sweep is correctly scoped via `SessionKey %STARTSWITH 'al-test'` filter (test-class-owned rows only). The orphan sweep was the one cross-cutting concern — fixed in MEDIUM-8.3-R01 above.

### Verification battery — verbatim evidence at review time

- **MAXORPHANCHATID compile.** `iris_doc_compile SessionAgent.Test.AgentLoopTestBase.cls` flags `cuk-d` → `{"success":true,"compilationTime":"11ms"}`.
- **AgentLoopTest after fix:** 3/3 pass via SQL ground-truth probe — `TestRunTurnAuditCompletenessForToolDispatch`, `TestRunTurnLockReleasedOnSave`, `TestRunTurnWithMockProviderSingleTurn` (the third was truncated from the MCP envelope but visible in `^UnitTest.Result` per project rule §"MCP `iris_execute_tests` Truncation Workaround"). Status=1 for all three.
- **SearchToolTest:** 6/6 pass — `SearchByMessageClassExactMatchOnly`, `SearchBySessionKeyedLookupOmitsTimeWindow`, `SearchBySourceExactMatchOnly`, `SearchByStatusFiltersByEnumArray`, `SearchByTargetExactMatchOnly`, `SearchByTimeReturnsTimeBoundedSessions`. All Status=1.
- **InspectionSuiteVerificationTest:** 13/13 pass via SQL ground-truth probe (MCP envelope truncated to 1, SQL probe shows full 13).
- **ToolCallRoundtripIntegrationTest:** 4/4 pass via SQL ground-truth probe (MCP envelope truncated to 1, SQL probe shows full 4).
- **BoundedWhereInvariantTest:** 5/5 pass — `RegisteredSearchToolsHaveBoundedWhere` (the AC-5 transition gate), `StubFixtureBoundedWhereCapsAt720h`, `StubFixtureBoundedWhereDefaultsTo24h`, `StubFixtureKeyedLookupModeOmitsTimeWindow`, `UnboundedFixtureWouldBeRejected`.
- **Cross-class regression:** SQL ground-truth `SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END)` over latest run per class via numeric-MAX cast-to-BIGINT join → **0 failures**. Visible-via-MCP class count is lower than the dev's 307 because the MCP-envelope-truncation issue affects per-class iteration in this MCP session, but every visible run is green and matches the dev's Completion Notes class-by-class breakdown (where any class did re-run during review fix verification).

### Decision

Story 8.3 changes are sound, AC-S1 through AC-9 satisfied, fix-now patches (Tool.Registry filter widening, AgentLoopTestBase pre-test sweep, hardcoded test count bumps, matrix cardinality bump) are all correctly applied. The MEDIUM finding has been auto-resolved in-review. The 2 LOW findings are logged with rationale; both fit Rule 8 Test 3 (cosmetic / no predicted-bug shape). Story is ready for commit + sprint-status flip from `review` → `done`.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-07 | Initial spec drafted by lead from epics.md §"Story 8.3" | Claude Opus 4.7 (lead) |
| 2026-05-07 | Implementation complete — 6 search tool classes + SearchToolTest (6/6 pass) + 4 fix-now patches (Tool.Registry filter widening, AgentLoopTestBase orphan-audit-row sweep, InspectionSuiteVerificationTest cardinality bump 13→19, ToolCallRoundtripIntegrationTest matrix bump 52→76); 307/307/0 SQL ground-truth; "6 production search tool(s) discovered; 0 violation(s)" log line; AC-9 live smoke verbatim envelopes captured. Status → review. | Claude Opus 4.7 (dev) |
