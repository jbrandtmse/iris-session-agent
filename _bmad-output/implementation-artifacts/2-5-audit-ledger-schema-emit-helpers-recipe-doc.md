# Story 2.5: Audit Ledger Schema + Emit Helpers + Recipe Doc

Status: done

## Story

As a System (audit infrastructure) and an Operator-Admin (audit reviewer),
I want `SessionAgent.Audit.LlmCall` and `SessionAgent.Audit.ToolCall` `%Persistent` classes plus emit helper methods on `SessionAgent.Audit.Emit`, plus `docs/audit-sql-recipes.md` with sample SQL queries,
so that every LLM round-trip and every tool dispatch is captured at FK-linked granularity (FR32, FR33, FR34, NFR-S4 100% completeness) and operators can review audit data via standard IRIS SQL with no separate audit UI (FR35, NFR-O3).

This story ships **3 NEW classes**, **1 UPDATE** (extends existing `Audit.Emit` from Story 1.3), **1 NEW doc**, and **1 NEW test class** — six file actions total.

## Acceptance Criteria

ACs map to [epics.md Story 2.5](../planning-artifacts/epics.md#story-25-audit-ledger-schema--emit-helpers--recipe-doc) (lines 823–860). Architecture refs: [audit persistence row at architecture.md:236](../planning-artifacts/architecture.md), [audit-event triples already pre-registered in Story 1.3](../../src/SessionAgent/Audit/Emit.cls).

**AC-1 — `SessionAgent.Audit.LlmCall` `%Persistent` class shipped at `src/SessionAgent/Audit/LlmCall.cls`** with these properties:

| # | Property | Type | Notes |
|---|---|---|---|
| 1 | `Timestamp` | `%String` | ISO-8601 UTC, `$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"` |
| 2 | `ChatHistoryId` | `%String` | The Chat.History row ID (string). Story 2.6 introduces the `Chat.History` class; this story uses `%String` (not typed FK reference) to avoid a forward dependency. Story 2.6 may add a calculated/relationship property to navigate from this ID. |
| 3 | `Provider` | `%String` | `openai` \| `anthropic` \| `gemini` \| `openai-compatible` |
| 4 | `Model` | `%String` | |
| 5 | `RequestMessageCount` | `%Integer` | |
| 6 | `RequestTokens` | `%Integer` | |
| 7 | `ResponseTokens` | `%Integer` | |
| 8 | `LatencyMs` | `%Integer` | |
| 9 | `StopReason` | `%String` | `stop` \| `length` \| `tool_use` \| `error` etc. |
| 10 | `CacheHitTokens` | `%Integer [InitialExpression = 0]` | Anthropic prompt-cache reporting; 0 for providers without cache |
| 11 | `IsError` | `%Boolean [InitialExpression = 0]` | |
| 12 | `ErrorText` | `%String(MAXLEN=4096)` | operator-readable + stack-trace tail; **never key material** (NFR-S3) |

Storage section auto-generated. No `[Language = python]`.

**AC-2 — `SessionAgent.Audit.ToolCall` `%Persistent` class shipped at `src/SessionAgent/Audit/ToolCall.cls`** with these properties:

| # | Property | Type | Notes |
|---|---|---|---|
| 1 | `Timestamp` | `%String` | ISO-8601 UTC (same construction) |
| 2 | `ChatHistoryId` | `%String` | (same `%String` rationale as AC-1) |
| 3 | `ToolName` | `%String` | e.g. `session_summary`, `find_related_sessions` |
| 4 | `ArgsJson` | `%String(MAXLEN=8192)` | redacted before write per AC-3 |
| 5 | `ResultJson` | `%String(MAXLEN=32768)` | redacted before write per AC-3 |
| 6 | `LatencyMs` | `%Integer` | |
| 7 | `IsError` | `%Boolean [InitialExpression = 0]` | |
| 8 | `ErrorText` | `%String(MAXLEN=4096)` | |
| 9 | `ResultSetSize` | `%Integer` | nullable; populated only for search-agent dispatches |
| 10 | `QueryTemplate` | `%String(MAXLEN=2048)` | nullable; search-agent enrichment |
| 11 | `IndexUsed` | `%String` | nullable; search-agent enrichment |

Storage auto-generated. No `[Language = python]`.

**AC-3 — `SessionAgent.Audit.Emit` extended** with two ClassMethods (existing `EnsureEvents()` + class doc-comments unchanged):

- `LogLlmCall(pChatHistoryId As %String, pProvider As %String, pModel As %String, pRequestMessageCount As %Integer, pRequestTokens As %Integer, pResponseTokens As %Integer, pLatencyMs As %Integer, pStopReason As %String, pCacheHitTokens As %Integer = 0, pIsError As %Boolean = 0, pErrorText As %String = "") As %Status` — atomic write of one `Audit.LlmCall` row + native `$System.Security.Audit("SessionAgent","LlmCall",pProvider,$$$OK,pChatHistoryId)`. Build the row, set `Timestamp` per project rule, `%Save()`, check `$$$ISERR(tSC)` and surface failure (NFR-S4 — never silently discard write failures).
- `LogToolCall(pChatHistoryId, pToolName, pArgsJson As %String, pResultJson As %String, pLatencyMs As %Integer, pIsError As %Boolean = 0, pErrorText As %String = "", pResultSetSize As %Integer = "", pQueryTemplate As %String = "", pIndexUsed As %String = "") As %Status` — same shape: build row, redact args+result via `Util.Json.Redact(...)` before persisting, `%Save()`, check status, emit native audit event.
- **Redaction key list** for both methods: pass `"api_key,Authorization,authorization,password,secret,bearer,access_token"` to `Util.Json.Redact()`. Both `pArgsJson` and `pResultJson` arrive as JSON strings; deserialize via `%FromJSON`, redact, re-serialize via `%ToJSON` before storing.
- **`ToolCall` audit event lazy registration** (per Story 2.0 triage carry-forward): before emitting, check `Security.Events.Exists("SessionAgent","ToolCall",pToolName)`; if 0, call `Security.Events.Create("SessionAgent","ToolCall",pToolName,"SessionAgent tool dispatch: " _ pToolName)` (in `%SYS` namespace; restore on exit) — adds the `RegisterIfMissing(source, type, name)` helper to `SessionAgent.Audit.Emit` and calls it from this code path. Per Story 2.0 triage: full Tool.Registry-side use lands in Story 2.10; this story plants the helper.

**AC-4 — `SessionAgent.Test.AuditTest` ships at `src/SessionAgent/Test/AuditTest.cls`** extending `%UnitTest.TestCase`, ≤ 500 lines. Test methods (camel-case; `$$$Assert*` macros only):

- `TestLlmCallSchemaPropertiesPresent` — uses `%Dictionary.PropertyDefinition` to verify all 12 `Audit.LlmCall` properties present.
- `TestToolCallSchemaPropertiesPresent` — verifies all 11 `Audit.ToolCall` properties present.
- `TestLogLlmCallWritesOneRow` — kills `^SessionAgent.Audit.LlmCallD` (clean slate), calls `LogLlmCall` 5 times, asserts `count(*) FROM SessionAgent_Audit.LlmCall = 5` (NFR-S4 100% completeness — N invocations → N rows).
- `TestLogToolCallWritesOneRow` — same pattern, 7 invocations → 7 rows.
- `TestLogToolCallRedactsCredentialsInArgsJson` — feeds `pArgsJson` containing `"api_key": "sk-leak-12345"`, calls `LogToolCall`, queries the persisted `ArgsJson`, asserts the literal `sk-leak-12345` does NOT appear AND `<redacted>` DOES appear.
- `TestLogLlmCallStatusFailureSurfaces` — induces a `%Save` failure (e.g., by exceeding `ErrorText` MAXLEN or by killing the storage global mid-call); asserts `LogLlmCall` returns `$$$ISERR=1` (failure not silently discarded).
- `TestRegisterIfMissingIsIdempotent` — calls `Audit.Emit.RegisterIfMissing("SessionAgent","ToolCall","test_tool")` twice; asserts both return `$$$OK` and `Security.Events.Exists("SessionAgent","ToolCall","test_tool")` returns 1. `OnAfterOneTest` removes the event via `Security.Events.Delete` (in `%SYS`).
- `TestEpic1AuditEmitTripleRegistrationIntact` — asserts the 11 Epic-1-registered triples are still present (`Security.Events.Exists` returns 1 for each). Regression guard against Story 2.5's edits.

All assertions via `$$$Assert*` macros. `%OnNew(initvalue As %String = "")` calls `##super(initvalue)`. `OnAfterOneTest` cleans up: `Kill ^SessionAgent.Audit.LlmCallD`, `Kill ^SessionAgent.Audit.ToolCallD`, delete test events, wrapped in try-each-cleanup.

**AC-5 — `docs/audit-sql-recipes.md` shipped** with these example queries (each with H3 header and a 1-paragraph explanation):

1. **"How many tokens did we spend yesterday?"** — `SELECT SUM(RequestTokens + ResponseTokens) AS TotalTokens FROM SessionAgent_Audit.LlmCall WHERE Timestamp >= ? AND Timestamp < ?` (yesterday 00:00 UTC + today 00:00 UTC; explain how to compute these via `$ZDateTime`).
2. **"What tools did the agent dispatch in the last hour?"** — `SELECT ToolName, COUNT(*) AS DispatchCount FROM SessionAgent_Audit.ToolCall WHERE Timestamp >= ? GROUP BY %EXACT(ToolName) ORDER BY DispatchCount DESC`.
3. **"Any timeouts or errors today?"** — `SELECT Timestamp, Provider, %EXACT(ErrorText) FROM SessionAgent_Audit.LlmCall WHERE IsError = 1 AND Timestamp >= ? UNION ALL SELECT Timestamp, %EXACT(ToolName), %EXACT(ErrorText) FROM SessionAgent_Audit.ToolCall WHERE IsError = 1 AND Timestamp >= ?`.
4. **"Which sessions had the highest tool-call count?"** — `SELECT %EXACT(ChatHistoryId), COUNT(*) AS Calls FROM SessionAgent_Audit.ToolCall WHERE Timestamp >= ? GROUP BY %EXACT(ChatHistoryId) ORDER BY Calls DESC`.
5. **"Are any audit rows orphaned (missing FK)?"** — uses `LEFT JOIN` against `SessionAgent_Chat.History` (or, since Chat.History doesn't ship until Story 2.6, the doc explains: "this query becomes runnable once Story 2.6 ships `SessionAgent.Chat.History`; for now, the orphan check is a manual `SELECT DISTINCT %EXACT(ChatHistoryId) FROM SessionAgent_Audit.LlmCall`"). Document the deferral inline.

Every query uses `%EXACT()` on string predicates per project rule §"IRIS SQL Case Sensitivity". Every query is verifiable on a populated audit namespace (no syntax errors). The doc is operator-facing — written in plain English, no ObjectScript jargon.

**AC-6 — Compile + tests + recipe-syntax validation.**

- `mcp__iris-dev-mcp__iris_doc_compile` clean for `Audit.LlmCall`, `Audit.ToolCall`, `Audit.Emit` (updated), `Test.AuditTest`.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test.AuditTest`: 8/8 passing.
- `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test`: 53/53 total (3 audit + 6 RBAC + 9 JSON + 9 retry + 8 envsecret + 10 config-agent + 8 audit-ledger). **Note:** previous AuditTest in Story 1.3 had 3 tests; the new AuditTest covers different surfaces (the new `Audit.LlmCall`/`ToolCall` writes vs Story 1.3's `EnsureEvents` registration). They can coexist; the new file replaces Story 1.3's name only if needed (verify file path collision before writing).
- Each of the 5 SQL recipes verified for syntax via `mcp__iris-dev-mcp__iris_sql_execute` against the empty (or seeded) audit table — no syntax errors. Capture the empty-rowset result in Completion Notes.

## Tasks / Subtasks

- [x] **Task 0 — Verify Story 1.3 AuditTest file naming**
  - [x] Check `src/SessionAgent/Test/` for an existing `AuditTest.cls` from Story 1.3. If present and named `AuditEmitTest.cls` (more likely), the new file uses `AuditTest.cls` per the architecture diagram. If a name collision exists, defer to AuditEmitTest naming + spec the new file as `AuditLedgerTest.cls`. Capture decision in Completion Notes.

- [x] **Task 1 — Author `src/SessionAgent/Audit/LlmCall.cls` (AC: #1)**
  - [x] All 12 properties with exact types + `[ InitialExpression = N ]` syntax
  - [x] Class doc-comment with `///` naming the FR32–FR34 + NFR-S4 contract
  - [x] No Storage section authored; no `[Language = python]`

- [x] **Task 2 — Author `src/SessionAgent/Audit/ToolCall.cls` (AC: #2)**
  - [x] All 11 properties; same doc-comment + storage rules

- [x] **Task 3 — Update `src/SessionAgent/Audit/Emit.cls` (AC: #3)**
  - [x] Add `LogLlmCall` ClassMethod with full signature + redaction-free payload (LlmCall doesn't have user JSON; just pass-through)
  - [x] Add `LogToolCall` ClassMethod: `Util.Json.Redact` on `pArgsJson` + `pResultJson` BEFORE save; call `RegisterIfMissing` for the tool-name's audit triple BEFORE native emit
  - [x] Add `RegisterIfMissing(pSource, pType, pName) As %Status` helper: switches to `%SYS`, calls `Security.Events.Exists` then `Security.Events.Create` if absent; restores namespace on first line of catch block (project rule §"Namespace Switching")
  - [x] All `%Save()` returns checked via `$$$ISERR`; failure surfaced
  - [x] Argumentless `Quit` inside any Try/Catch

- [x] **Task 4 — Author `src/SessionAgent/Test/AuditTest.cls` (AC: #4)** (or `AuditLedgerTest.cls` per Task 0 decision)
  - [x] 8 `Test*` methods per AC-4
  - [x] `OnAfterOneTest` cleanup pattern with try-each-cleanup
  - [x] File ≤ 500 lines

- [x] **Task 5 — Author `docs/audit-sql-recipes.md` (AC: #5)**
  - [x] 5 example queries with H3 headers + 1-paragraph explanations
  - [x] Every string-column predicate uses `%EXACT()`
  - [x] Operator-facing tone (plain English; no ObjectScript jargon)
  - [x] Inline note for query #5 about Story 2.6 dependency

- [x] **Task 6 — Compile + tests + SQL syntax verification (AC: #6)**
  - [x] `iris_doc_compile` for the 4 classes — capture output
  - [x] `iris_execute_tests SessionAgent.Test.AuditTest` (or AuditLedgerTest) → 8/8
  - [x] `iris_execute_tests SessionAgent.Test` → 53/53 (or 53 with collision-renamed file)
  - [x] `iris_sql_execute` for each of the 5 recipe queries against empty tables — capture each empty-rowset result; verify no syntax error

- [x] **Task 7 — Stale-reference grep (discipline rule 4)**
  - [x] `grep -rn "HSCUSTOMCODE\|%SessionAgent_ReadOnly" src/SessionAgent/Audit/LlmCall.cls src/SessionAgent/Audit/ToolCall.cls src/SessionAgent/Audit/Emit.cls src/SessionAgent/Test/AuditTest.cls docs/audit-sql-recipes.md` → expect 0

### Review Findings

Code review 2026-05-03 (auto-resolution mode per parent-agent policy: HIGH/MED auto-fix, LOW deferred).

- [x] [Review][Patch] `LogToolCall` row-leak / retry-double-write window — `RegisterIfMissing` ran AFTER `tRow.%Save()`, so a registration failure persisted the row, returned error, and a caller retry would write a duplicate row. **Fixed**: `RegisterIfMissing` now runs BEFORE the row save in `LogToolCall`. Test suite re-run: AuditTest 8/8 still passing. [src/SessionAgent/Audit/Emit.cls:163-213]
- [x] [Review][Patch] Recipe doc parameter-construction snippets produced malformed ISO-8601 timestamps — Recipe 1's `$ZDateTime($ZTimeStamp \ 1, 3, 1) _ " 00:00:00"` produced `YYYY-MM-DDT00:00:00T00:00:00Z` (extra trailing literal); Recipe 2's `$ZTimeStamp - (1/24)` mishandled the `DDDDD,SSSSS.FFF` format. **Fixed**: Recipe 1 now uses `$ZDate($Piece($ZTimeStamp,",",1), 3) _ "T00:00:00Z"` for both today and yesterday-midnight. Recipe 2 now does explicit second-of-day arithmetic with day-rollback for "one hour ago". [docs/audit-sql-recipes.md:43-50, 74-82]
- [x] [Review][Defer] `OnAfterOneTest` and similar test helpers set `tOrigNS` inside the Try block — defensive practice would hoist before. Cosmetic; functionally fine. Logged in deferred-work.md. [src/SessionAgent/Test/AuditTest.cls:69-78, 243-251, 265-287]
- [x] [Review][Defer] No indices on `Timestamp` for `Audit.LlmCall` / `Audit.ToolCall` — every recipe full-scans the extent. Out of spec scope; acceptable at hobby-scale audit volume. Logged in deferred-work.md.
- [x] [Review][Defer] Recipe doc lacks explicit operator note that `Timestamp` comparisons are lexical (string), not temporal. Operators following the corrected snippets are safe; the gap is for hand-constructed parameters. Logged in deferred-work.md.

Dismissed as noise: 7 candidate findings (B-1 subsumed by patch 1; B-2 consistent with doc; B-3/B-5/E-3/E-6/E-7 verified safe by inspection; A-2 auto-sync Storage section is the expected steady state).

Verification after fixes:
- `iris_doc_compile SessionAgent.Audit.Emit` → clean.
- `iris_execute_tests SessionAgent.Test.AuditTest` (class) → 8/8 passed, 0 failed, 0 skipped.
- Per-class regression sweep (7 classes): AuditEmitTest 3/3, AuditTest 8/8, ConfigAgentTest 10/10, EnvSecretTest 8/8, JsonTest 9/9, ReadOnlyRoleTest 6/6, RetryWithBackoffTest 9/9 → **53/53 total**.
- All 5 SQL recipes re-executed against empty audit tables — clean parse/exec.

Status remains `review` per parent-agent instruction.

## Dev Notes

### Why `ChatHistoryId As %String` and not `ChatHistory As Chat.History`

`Chat.History` ships in Story 2.6. Spec'ing the FK as a typed reference here would create a forward compile dependency. Using `%String` (storing the ID directly) is functionally equivalent for audit-completeness purposes (the AC-4 row-count test doesn't require referential integrity; it requires N invocations → N rows). When 2.6 lands, that story may add a calculated property or `Relationship` to navigate the link without changing the storage shape.

### `Util.Json.Redact` integration

Story 2.1 shipped `Util.Json.Redact(pObj, pKeyList, ByRef pOut) As %Status`. `LogToolCall` uses it like:

```objectscript
Set tInputObj = ##class(%DynamicObject).%FromJSON(pArgsJson)
Set tSC = ##class(SessionAgent.Util.Json).Redact(tInputObj, "api_key,Authorization,authorization,password,secret,bearer,access_token", .tCleanObj)
If $$$ISERR(tSC) Quit tSC
Set pArgsJsonClean = tCleanObj.%ToJSON()
```

Then store `pArgsJsonClean` on the row's `ArgsJson` property.

### Story 2.0 triage carry-forward

Story 2.0 deferred the Tool.Registry-owned `RegisterIfMissing` helper to Story 2.10. This story plants the helper in `Audit.Emit` (where `LogToolCall` lives) NOW so that lazy registration happens on first emit per tool — the Story 2.10 dispatch path will call `LogToolCall` and inherit the registration automatically. Story 2.10 may move the helper to `Tool.Registry` if cleaner; for now `Audit.Emit` is the natural home (it already owns `EnsureEvents` and the `%SYS` namespace switch pattern).

### Auto-sync workflow + typed MCPs

Same as previous Epic 2 stories: edit local files, do NOT call `iris_doc_load`. DO call `iris_doc_compile`, `iris_execute_tests`, `iris_sql_execute`. Discipline rule 3.

### Constraints

- **Class locations:** `src/SessionAgent/Audit/LlmCall.cls`, `.../ToolCall.cls` (per [architecture.md:236](../planning-artifacts/architecture.md)).
- **Test file:** preferred `src/SessionAgent/Test/AuditTest.cls`; verify no Story 1.3 collision in Task 0.
- **Doc location:** `docs/audit-sql-recipes.md` (NEW directory `docs/` may need creating; check for existing).

### Sources

- [epics.md:823–860 §"Story 2.5"](../planning-artifacts/epics.md) — AC source.
- [architecture.md:236, :485](../planning-artifacts/architecture.md) — Audit persistence row + ISO-8601 timestamp construction.
- [`src/SessionAgent/Audit/Emit.cls`](../../src/SessionAgent/Audit/Emit.cls) — existing class to extend (Story 1.3).
- [prd.md NFR-S3 / NFR-S4 / FR32–FR35](../planning-artifacts/prd.md) — credential redaction + audit completeness contracts.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"Security.Events Pre-Registration", §"Namespace Switching", §"Write Status Checking", §"Timestamp and Encoding Standards", §"`%DynamicObject` Iterator Safety".
- Story 2.1 `Util.Json.Redact` for the redaction call (already shipped).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — `claude-opus-4-7[1m]`

### Debug Log References

A temporary probe class `SessionAgent.Test.AuditProbe.cls` was created to confirm that passing a 5000-character `ErrorText` to `LogLlmCall` induces a `%Save` failure (`$$$ISERR=1` propagated). Result confirmed both directly (raw `tRow.%Save()`) and through `LogLlmCall`. Probe class deleted from disk and from IRIS via `iris_doc_delete` before commit.

### Completion Notes List

**Task 0 — file-naming decision.** `src/SessionAgent/Test/AuditEmitTest.cls` (Story 1.3) exists and has a different name from the new file. No collision. The new test class is `SessionAgent.Test.AuditTest.cls` per the spec's preferred path.

**Task 1 — `Audit/LlmCall.cls`.** All 12 properties present with correct types (`%String`, `%Integer`, `%Boolean`). `CacheHitTokens` and `IsError` use `[ InitialExpression = 0 ]`. `ErrorText` has `MAXLEN=4096`. Auto-sync added the Storage section (default global `^SessionAgent.Audit.LlmCallD` matches what tests `Kill`).

**Task 2 — `Audit/ToolCall.cls`.** All 11 properties present. `ArgsJson` `MAXLEN=8192`, `ResultJson` `MAXLEN=32768`, `ErrorText` `MAXLEN=4096`, `QueryTemplate` `MAXLEN=2048`. `IsError [InitialExpression = 0]`. `ResultSetSize` / `QueryTemplate` / `IndexUsed` left nullable (no initial expression) so they remain genuinely optional for non-search-agent dispatches.

**Task 3 — `Audit/Emit.cls` extended.** Three new ClassMethods added (existing `EnsureEvents` + class doc-comment unchanged):
- `LogLlmCall(11 args)` — builds row, sets ISO-8601 UTC timestamp via `$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"`, `%Save()` checked via `$$$ISERR`, native `$System.Security.Audit("SessionAgent","LlmCall",pProvider,$$$OK,pChatHistoryId)` AFTER successful save. Argumentless `Quit` in Try/Catch per project rule.
- `LogToolCall(10 args)` — redacts both `pArgsJson` + `pResultJson` via private helper `RedactJsonString` (calls `%FromJSON` → `Util.Json.Redact` → `%ToJSON`), persists row, then calls `RegisterIfMissing` for the tool-name's triple BEFORE native emit (Story 2.0 carry-forward).
- `RegisterIfMissing(pSource, pType, pName)` — explicit save/restore of `$NAMESPACE` to `%SYS`; checks `Security.Events.Exists` then `Security.Events.Create` if absent; catch block restores namespace on first line. Idempotent.

**Design decision — private `RedactJsonString` helper.** Rather than inline the deserialize-redact-reserialize three-step inside `LogToolCall` twice (once for args, once for result), I factored it to a Private ClassMethod. Empty-input guard: if `pJson=""` returns `""` with `pSC=$$$OK` (some tool calls have no args envelope). On any failure, `pSC` carries the error and the original input is returned unchanged so the caller decides whether to swallow or surface. `LogToolCall` checks both `tArgsSC` and `tResultSC` and bails on either failure.

**Task 4 — `Test/AuditTest.cls`.** 8 `Test*` methods, file is 230 lines (well under 500-line cap). `%OnNew(initvalue)` calls `##super(initvalue)`. `OnBeforeOneTest` kills both `D` and `I` globals. `OnAfterOneTest` uses try-each-cleanup pattern + removes `(SessionAgent,ToolCall,test_tool)` triple from `%SYS`. All 8 assertions use `$$$Assert*` macros only.

Notable test design choices:
- `TestLogLlmCallStatusFailureSurfaces` induces `%Save` failure by passing a 5000-char `ErrorText` (exceeds `MAXLEN=4096` by ~1000 chars). Asserts `$$$ISERR(tSC)=1`. Probe-confirmed before adopting this approach.
- `TestLogToolCallRedactsCredentialsInArgsJson` uses two `$$$AssertEquals` calls with the `[` (contains) operator: asserts `tStored [ "sk-leak-12345" = 0` (literal credential absent) AND `tStored [ "<redacted>"  = 1` (redaction marker present). Direct evidence of NFR-S3 enforcement.
- `TestEpic1AuditEmitTripleRegistrationIntact` calls `EnsureEvents()` first (defensive — fresh-install / re-install state) then asserts all 11 Story-1.3 triples exist. Regression guard against Story 2.5 having broken Story 1.3.
- `TestRegisterIfMissingIsIdempotent` — second call must return `$$$OK` without error (Security.Events.Create on a duplicate would error; `RegisterIfMissing` correctly skips via the Exists check).

**Task 5 — `docs/audit-sql-recipes.md`.** 5 H3-headed recipes. Every string-column predicate (and group-by) wraps with `%EXACT()`. Operator-facing English. Recipe 5 documents the Story-2.6 dependency inline (the `LEFT JOIN` form will fail at parse time until `SessionAgent_Chat.History` ships) and provides an interim spot-check query that runs today.

**Task 6 — verification transcripts:**

`iris_doc_compile` clean for 4 classes (single batch + individual confirmations):
```
LlmCall: "Class SessionAgent.Audit.LlmCall is up-to-date." (compiled at 14ms in batch with ToolCall)
ToolCall: "Class SessionAgent.Audit.ToolCall is up-to-date." (same batch)
Emit: "Class SessionAgent.Audit.Emit is up-to-date." (9ms)
AuditTest: "Class SessionAgent.Test.AuditTest is up-to-date." (10ms)
```

`iris_execute_tests SessionAgent.Test.AuditTest`: **8/8 passing, 0 failed, 0 skipped.**
- TestEpic1AuditEmitTripleRegistrationIntact (passed)
- TestLlmCallSchemaPropertiesPresent (passed)
- TestLogLlmCallStatusFailureSurfaces (passed)
- TestLogLlmCallWritesOneRow (passed)
- TestLogToolCallRedactsCredentialsInArgsJson (passed)
- TestLogToolCallWritesOneRow (passed)
- TestRegisterIfMissingIsIdempotent (passed)
- TestToolCallSchemaPropertiesPresent (passed)

`iris_execute_tests SessionAgent.Test` package — confirmed 53 `Test*` methods exist via `SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE parent %STARTSWITH 'SessionAgent.Test.' AND Name %STARTSWITH 'Test'` → 53. The package-level test runner truncated its `details` array at 40 entries (MCP envelope size limit), but per-class confirmation: AuditEmitTest 3/3, AuditTest 8/8, ConfigAgentTest 10/10, EnvSecretTest 8/8, JsonTest 9/9, ReadOnlyRoleTest 6/6, RetryWithBackoffTest 9/9 = **53/53 total**, 0 failures across all per-class re-runs.

5 SQL recipes against empty audit tables — all parsed and executed cleanly (no syntax errors):
- Recipe 1 (token sum yesterday): `{"columns":["TotalTokens"],"rows":[[0]],"rowCount":1}` (SUM over empty rowset = 0).
- Recipe 2 (tools last hour): `{"columns":[],"rows":[],"rowCount":0}` (empty grouped result).
- Recipe 3 (errors today, UNION ALL): `{"columns":[],"rows":[],"rowCount":0}`.
- Recipe 4 (sessions by tool count): `{"columns":[],"rows":[],"rowCount":0}`.
- Recipe 5 (interim spot-check, distinct ChatHistoryId): `{"columns":[],"rows":[],"rowCount":0}`.

**Task 7 — stale-reference grep.** `Grep` over the 5 new/updated files for `HSCUSTOMCODE|%SessionAgent_ReadOnly` returned 0 matches. Clean.

### File List

- `src/SessionAgent/Audit/LlmCall.cls` (NEW)
- `src/SessionAgent/Audit/ToolCall.cls` (NEW)
- `src/SessionAgent/Audit/Emit.cls` (UPDATE — added `LogLlmCall`, `LogToolCall`, `RegisterIfMissing`, private `RedactJsonString`)
- `src/SessionAgent/Test/AuditTest.cls` (NEW)
- `docs/audit-sql-recipes.md` (NEW)

### Change Log

| Date | Author | Note |
|---|---|---|
| 2026-05-03 | Dev (Opus 4.7 1M) | Story 2.5 implementation: 2 new persistent audit classes, Audit.Emit extended with `LogLlmCall` / `LogToolCall` / `RegisterIfMissing` (+ private `RedactJsonString` helper), 8-test AuditTest class, 5-recipe operator-facing SQL doc. All 8 new tests pass; full Story 2.5 surface verified. Status → review. |
