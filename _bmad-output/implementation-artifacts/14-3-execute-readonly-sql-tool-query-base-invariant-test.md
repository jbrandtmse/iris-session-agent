# Story 14.3: `execute_readonly_sql` + `Tool.Query.Base` + Invariant Test (FR60)

Status: done

**Source:** `sprint-change-proposal-2026-06-10.md` Â§4.1 FR60, Â§4.2 item 1 (guard pipeline + calibration constants + adapted SQL-injection layers + documented residual risk), Â§2.3 (statementType verification trail), Â§5 handoff (Task 0 MUST empirically probe `statementType` values + `%SelectMode` rendering BEFORE AC authoring â€” research-first rule item 4). Precedents: `src/SessionAgent/Test/BoundedWhereInvariantTest.cls` (invariant-test shape), `src/SessionAgent/Tool/Search/Base.cls` (family base + ResultSetSize audit enrichment), Story 14.1 diagnostic-checklist article (SQLCODEâ†’hint source).

## Story

As an **operator asking open-ended analytical questions**, I want a guarded `execute_readonly_sql` tool that runs LLM-authored SELECT statements under a compiler-level read-only gate with caps and hint-bearing error envelopes, so that the long tail of trace questions becomes answerable without sacrificing the v1 read-only guarantee.

## Acceptance Criteria

**AC-1 â€” `Tool.Query.Base` abstract class** (`src/SessionAgent/Tool/Query/Base.cls`, `SessionAgent.Tool.Query.Base`, Abstract, extends `SessionAgent.Tool.Base`). Owns the guard pipeline as a single protected entry point (e.g., `RunGuardedSelect(pSql, pMaxRows, pResult)`) that every concrete subclass MUST route execution through:
1. **Single-statement validation** â€” reject multi-statement input (semicolon outside string literals; trailing semicolon tolerated) with a structured validation envelope.
2. **`%Prepare`** â€” failure â†’ `EnsureIsErrorOnPrepareFailure` + appended SQLCODE/symptom hint (see AC-4).
3. **`statementType` gate** â€” `%Metadata.statementType '= 1` â†’ `render_strategy:"not_select"` error envelope naming the rejected statement type (verified value table: 1=SELECT per `irislib/%SQL/StatementMetadata.cls`; Task 0 re-verifies empirically).
4. **Execute** â€” `EnsureIsErrorOnExecuteFailure` + hint.
5. **Capped, elapsed-guarded fetch** â€” row cap, total result char budget with explicit `truncated` marker, elapsed check inside the fetch loop, **post-loop fetch-fault gate** (negative `%SQLCODE` after `%Next()` returns 0 â†’ error envelope; `100` = clean done â€” the Story 14.2-review reference pattern).
6. **Envelope shaping** â€” columns array + rows + `row_count`, `truncated`, `elapsed_ms` in `structuredContent` (audit rows inherit them via the ToolCall enrichment path â€” Search.Base ResultSetSize precedent).

Calibration constants as Class Parameters (AR10 pattern): `DEFAULTMAXROWS=50`, `HARDMAXROWS=200`, `RESULTCHARBUDGET=32000`, `DEFAULTELAPSEDGUARDSEC=30`, `HARDELAPSEDGUARDSEC=60`.

> **Then** class compiles Abstract; pipeline stages verifiable in source; constants present with those values.

**AC-2 â€” Registry discovery gains the third base.** `Tool.Registry` discovery SQL matches `Super` âˆˆ {`SessionAgent.Tool.Base`, `SessionAgent.Tool.Search.Base`, `SessionAgent.Tool.Query.Base`} (today it matches the first two). `Tool.Query.Base` itself (Abstract=1) excluded.

> **Then** `ListTools().%Size()` = 33 post-story with `execute_readonly_sql` present; verbatim probe captured.

**AC-3 â€” `execute_readonly_sql` concrete tool** (`SessionAgent.Tool.Query.ExecuteReadonlySql`). Args: `sql` (required string â€” schema description primes: *"A single SQL SELECT statement. Always include a time-window predicate and TOP N on exploratory queries. INSERT/UPDATE/DELETE/CALL are rejected."*), `max_rows` (optional int, default `DEFAULTMAXROWS`, clamp 1..`HARDMAXROWS`). Uses `%SelectMode` ODBC for stable timestamp/decode rendering (Task 0 verifies the rendering shape). Exposed to BOTH agents (D1). `MutatesState=0`.

> **Then** live dispatch of `SELECT TOP 5 ID, SessionId FROM Ens.MessageHeader ORDER BY ID DESC` returns rows with `render_strategy:"ok"`, `row_count<=5`, `elapsed_ms` present; `INSERT INTO ...` dispatch returns `not_select` (and the table is unchanged); `SELECT ... ; DROP ...` returns the single-statement validation envelope; verbatim envelopes captured.

**AC-4 â€” SQLCODEâ†’hint map from the knowledge corpus.** On prepare/execute failure the envelope appends a `hint` drawn from the Story 14.1 `diagnostic-checklist` article (locked contract: `SQLCODE <n> / symptom -> fix` lines incl. âˆ’29, âˆ’37, âˆ’400). Implementation reads the article body at failure time (cheap single-row read; no caching needed) and falls back to a generic "consult get_query_knowledge topic=methodology" hint when no SQLCODE line matches.

> **Then** dispatching `SELECT Name, COUNT(*) FROM Ens.MessageHeader GROUP BY SourceConfigName` (alias-in-GROUP-BY shape â†’ SQLCODE âˆ’29 family) returns an error envelope whose `hint` is the âˆ’29 line from the article; verbatim captured.

**AC-5 â€” `ReadOnlySqlInvariantTest`** (mirrors `BoundedWhereInvariantTest`): discovers every concrete `Tool.Query.*` subclass and asserts (source-introspection) that its `Invoke` routes through the base pipeline entry point â€” no direct `%Prepare`/`%Execute` outside `RunGuardedSelect`. Auto-discovers future Query tools by convention.

> **Then** test passes with 1 discovered tool; deliberately structured so a future non-conforming Query tool fails it.

**AC-6 â€” Read-only PROOF battery (test).** Tests assert: INSERT, UPDATE, DELETE, CALL, and EXPLAIN inputs are all rejected pre-execution (statementType gate or validation), with a SQL probe proving no row was written for the INSERT attempt; row cap + char budget + truncated marker; elapsed_ms presence; ODBC rendering of a timestamp column; hint on seeded âˆ’29 failure; multi-statement rejection; empty-result ok-envelope.

> **Then** all new tests pass; full sweep via ground-truth probe = baseline 554 + new, 0 failures (verbatim).

**AC-7 â€” Suite updates.** ISV: **EXPECTEDTOOLCOUNT 32â†’33 + `execute_readonly_sql` in `tExpected` + `GetRepresentativeArgs`** (representative arg: a TOP-1 SELECT against Ens.MessageHeader). Roundtrip cardinality 128â†’132 + comment arithmetic.

**AC-8 â€” README same-commit update** (tool catalog 33 + a "Guarded dynamic SQL" subsection documenting the guard pipeline, caps, and the documented-accepted residual risk per proposal Â§4.2 item 1).

**AC-9 â€” Spec â‰¤ 250 lines.**

## Integration ACs

In-story consumers: real `Tool.Registry.Dispatch` e2e tests (AC-3/4); `ReadOnlySqlInvariantTest` consumes the base-pipeline contract; the hint path consumes the Story 14.1 article (cross-story integration exercised live in AC-4). Future: Story 14.5 prompt card + golden questions GQ-1..GQ-13 (discoverâ†’query loop); Story 14.6 stretch extends the statementType gate for EXPLAIN.

## Consumed-by

- Story 14.5 â€” methodology card mandates knowledge-then-SQL via this tool; golden-question eval exercises it end-to-end.
- Story 14.6 (stretch) â€” adds `statementType=79` (EXPLAIN) allowance to the AC-1 gate.

## Tasks / Subtasks

- [x] **Task 0 â€” MANDATORY pre-flight probes (verbatim outputs into Completion Notes BEFORE writing tool code):** (a) `statementType` empirical check on live IRIS â€” prepare each of `SELECT...`, `INSERT...`, `UPDATE...`, `DELETE...`, `CALL...`, `EXPLAIN SELECT...` via a scratch probe and record `%Metadata.statementType` for each (expect 1/2/3/4/45/79 per `irislib/%SQL/StatementMetadata.cls` lines ~25/107 â€” verify, do not assume); (b) `%SelectMode` ODBC rendering check â€” same SELECT under mode 0 vs ODBC, record TimeCreated rendering difference; (c) single-statement edge probes â€” semicolon inside a string literal, trailing semicolon; (d) confirm the diagnostic-checklist article's hint-line format via SQL read. Read `irislib/%SQL/Statement.cls` + `StatementMetadata.cls` + `StatementResult.cls` first.
- [x] **Task 1 â€” `Tool.Query.Base`** (AC-1); compile.
- [x] **Task 2 â€” Registry discovery update** (AC-2); compile; ListTools probe.
- [x] **Task 3 â€” `ExecuteReadonlySql`** (AC-3) + hint map (AC-4); compile; live dispatch probes incl. the INSERT-rejection write-proof.
- [x] **Task 4 â€” `ReadOnlySqlInvariantTest`** (AC-5).
- [x] **Task 5 â€” Read-only proof battery + remaining tests** (AC-6).
- [x] **Task 6 â€” Suite updates** (AC-7).
- [x] **Task 7 â€” README** (AC-8); Completion Notes + File List; `wc -l` â‰¤ 250.

## Dev Notes

- **Helper callout (Story 14.0 Carry-Forward, verbatim):** *"For SQL prepare failures call `##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName)`; for runtime execute failures call `EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName)` immediately after `%Execute` â€” do NOT construct raw `{"isError":1}` objects."* The hint append (AC-4) composes AFTER the helper call (helper shapes the canonical envelope; hint enriches it).
- **Adapted SQL-injection 4 layers (the input IS SQL by design â€” proposal Â§4.2 item 1):** L1 = schema description priming (AC-3 wording); L2 = statementType compiler gate (stronger than regex); L3 = parameterless single-statement execution with caps (NEVER concatenate anything into the operator's SQL text; no parameter substitution into it either); L4 = reviewer confirms 1â€“3 explicitly. Layer-2-bypass attempts (CTE-wrapped INSERT? `SELECT ... INTO`?) â€” Task 0 should probe `SELECT ... INTO` if IRIS supports it; document findings.
- **Residual risk (documented, accepted):** a SELECT can invoke SQL-projected class methods with side effects. Mitigations: L3 RBAC (`SessionAgent_ReadOnly`), 100% ToolCall audit (args carry the SQL), read-only prompt covenant. Document verbatim in the class doc-comment + README per proposal Â§4.2; optional future hardening (restricted-privilege job) stays out of scope.
- **Elapsed guard semantics:** in-process dynamic SQL cannot be preempted mid-statement (proposal Â§2.3) â€” the guard fires between fetch iterations; a single long `%Execute` is bounded only by the Web Gateway 300s backstop. State this honestly in the class doc-comment; do NOT claim preemption.
- **Timing:** use `$ZHorolog` deltas for `elapsed_ms` (no `Date.now` analogues in tests that would break determinism; tests assert presence/positivity, not exact values).
- **`%SelectMode`:** set on the `%SQL.Statement` instance pre-`%Prepare` (verify property name in `irislib/%SQL/Statement.cls`).
- **Audit enrichment:** follow `Tool.Search.Base`'s ResultSetSize envelope-enrichment precedent â€” enrich `structuredContent`; the existing ToolCall audit row captures args + outcome already. No new audit triples (read-only tool; `MutatesState=0`; "no audit triples shipped" note for the epic battery).
- **Post-loop fetch-fault gate** is part of the AC-1 pipeline (step 5) â€” the 14.2-review reference implementation lives in `DescribeMessageClass.cls` tail-gates.
- **Substring-grep binding (Epic 12 AI-5):** enumerate-all-replace-each-then-grep for source-introspection assertions (the invariant test is exactly this shape â€” design it accordingly).
- **Naming:** no underscores in method names; test classes â‰¤ ~500 lines (split battery vs invariant if needed).
- **Rule 10:** no external-system defaults â€” N/A.
- **Subagent refs:** `irislib/%SQL/Statement.cls`, `StatementMetadata.cls`, `StatementResult.cls`; `docs/iris-query-guide/08-execution-and-connection.md` (absorbed into the tool contract); `BoundedWhereInvariantTest.cls`.

### References

- [Source: sprint-change-proposal-2026-06-10.md Â§4.1 FR60, Â§4.2 item 1, Â§2.3, Â§5]
- [Source: epics.md Â§Epic 14 â€” 14.3 bullet]
- [Source: 14-0 story Â§Carry-Forward â€” helper + EXPECTEDTOOLCOUNT bindings]
- [Source: src/SessionAgent/Test/BoundedWhereInvariantTest.cls â€” invariant-test precedent]
- [Source: 14-1 story AC-6 â€” diagnostic-checklist hint-line locked contract]

## Dev Agent Record

### Agent Model Used

Claude Fable 5 (claude-fable-5[1m]) via /epic-cycle dev-story stage, 2026-06-11.

### Debug Log References

Scratch probe classes `SessionAgent.Scratch143Probe` / `SessionAgent.Scratch143Dispatch` (deleted locally AND from server via `iris_doc_delete` after evidence capture).

### Completion Notes List

- **Task 0 verbatim probes (live HSCUSTOM, 2026-06-11):**
  - `statementType` per `%Prepare`+`%Metadata`: `SELECT`â†’**1**, `INSERT`â†’**2**, `UPDATE`â†’**3**, `DELETE`â†’**4**, `CALL Ens.MessageHeader_Extent()`â†’**45**, **`EXPLAIN SELECT ...`â†’1 (NOT 79 â€” empirical override of the doc table; EXPLAIN is therefore rejected at the validation stage by leading keyword, per AC-6's "statementType gate or validation")**. Trailing-semicolon SELECT prepares OK (type 1); `SELECT ...; DELETE ...` is rejected by `%Prepare` itself (`SQLCODE: -25 Input (;) encountered after end of query`) â€” our stage-1 validation still pre-empts it with the structured `multi_statement` envelope; `SELECT 'a;b' ...` prepares OK; `SELECT ID INTO :x ...` rejected (SQLCODE -1, host vars not valid in dynamic SQL); `WITH t AS (SELECT ...) SELECT ...` prepares as type 1.
  - `%SelectMode` rendering of `TimeCreated`/`Status`: mode 0 (logical) â†’ `"2026-06-11 10:55:05.838"`/`9`; mode 1 (ODBC) â†’ `"2026-06-11 03:55:05.838"`/`9`; mode 2 (display) â†’ `.../"Completed"`. ODBC selected (stable UTC ODBC timestamps, integer enums un-decoded).
  - Hint-line format confirmed via SQL read of `SessionAgent_Knowledge.Article` slug `diagnostic-checklist`: `\n`-separated `SQLCODE <n> / symptom -> fix` lines incl. -1, -25, -29, -37, -40, -400.
  - Prepare-failure error text contains locale-independent `"SQLCODE: <n>"` marker but a LOCALE-DEPENDENT prefix (this server emits Arabic `Ø®Ø·Ø£ #5540`) â€” `ExtractSqlcodeFromStatus` keys on `"SQLCODE: "`, never `"ERROR #"`.
- **AC-1:** `SELECT Name, Abstract, Super FROM %Dictionary.CompiledClass WHERE Name='SessionAgent.Tool.Query.Base'` â†’ `["SessionAgent.Tool.Query.Base", true, "SessionAgent.Tool.Base"]`; parameter probe â†’ `DEFAULTELAPSEDGUARDSEC=30, DEFAULTMAXROWS=50, HARDELAPSEDGUARDSEC=60, HARDMAXROWS=200, RESULTCHARBUDGET=32000`. All 6 pipeline stages in `RunGuardedSelect` source.
- **AC-2:** live `ListTools()` probe â†’ `{"size":33,"hasExecuteReadonlySql":1,...}` (verbatim names array captured in-session). Both Registry discovery queries (ListTools + ResolveToolName) carry the third `Tool.Query.Base` OR-clause.
- **AC-3 verbatim dispatch envelopes (via `Tool.Registry.Dispatch`):** `SELECT TOP 5 ID, SessionId FROM Ens.MessageHeader ORDER BY ID DESC` â†’ `{"render_strategy":"ok","columns":["ID","SessionId"],"rows":[["6167",6161],...5 rows],"row_count":5,"truncated":false,"elapsed_ms":2}`; INSERT dispatch â†’ `{"render_strategy":"not_select","rejected_statement_type":"INSERT","statement_type_code":2,"isError":true}` with write-proof `Ens_Util.Log` `countBefore=178, countAfter=178`; `SELECT ...; DROP TABLE ...` â†’ `{"render_strategy":"multi_statement", "isError":true}`.
- **AC-4 verbatim:** `SELECT Name, COUNT(*) FROM Ens.MessageHeader GROUP BY SourceConfigName` dispatch â†’ `render_strategy:"prepare_error"`, `hint:"SQLCODE -29 / field not found -> you referenced a SELECT column alias in GROUP BY or ORDER BY; repeat the full expression, or compute it in a subquery and group/order by the alias outside."` â€” the verbatim -29 line from the article. Fallback hint tested on unmapped SQLCODE (-30 family) â†’ generic consult-get_query_knowledge hint.
- **AC-5:** SQL ground-truth probe (latest run) â†’ 4/4 Status=1 (`TestRegisteredQueryToolsRouteThroughGuardedPipeline` discovers 1 tool; `TestNonConformingFixtureWouldBeRejected` proves the negative control flags `%PREPARE`/`%EXECUTE`/missing-`RunGuardedSelect`). MCP envelope truncated to 3 rows; SQL probe is the gate.
- **AC-6:** battery SQL ground-truth probe â†’ 13/13 Status=1 (INSERT write-proof, UPDATE/DELETE/CALL/EXPLAIN rejection, row cap + hard-max clamp, char budget via `{fn REPEAT('x',2000)}`, elapsed_ms presence, ODBC timestamp shape, -29 hint, hint fallback, multi-statement, semicolon edges, empty-result ok, missing-sql envelope). **Full regression sweep (canonical numerical-MAX SQL probe): Total=571, Passed=571, Failed=0** = baseline 554 + 17 new (4 invariant + 13 battery).
- **AC-7:** ISV `EXPECTEDTOOLCOUNT` 32â†’33 + `execute_readonly_sql` in `tExpected` + `GetRepresentativeArgs` (TOP-1 SELECT) + `GetConcreteToolClasses` third-base filter; ISV ground-truth 13/13. Roundtrip cardinality 128â†’132 + comment arithmetic; ground-truth 4/4 incl. `TestMatrixCardinalityMatchesCatalog`.
- **AC-8:** README â€” catalog count 33, new "Guarded dynamic SQL" subsection (pipeline, caps, EXPLAIN empirical note, residual risk verbatim), FR60 row in the feature table.
- **AC-9 / Task 7:** story file `wc -l` = 135 â‰¤ 250.
- **SQL-injection 4 layers (adapted):** L1 schema priming on `sql` arg (AC-3 wording verbatim); L2 statementType gate; L3 parameterless execution â€” operator SQL is never concatenated with anything nor parameter-substituted; L4 owed by reviewer.
- **Formatter-hook re-grep at completion:** all edits verified present (Registry 2 hits, ISV 33-count, roundtrip 132, README 5 hits).

### File List

- src/SessionAgent/Tool/Query/Base.cls (new)
- src/SessionAgent/Tool/Query/ExecuteReadonlySql.cls (new)
- src/SessionAgent/Tool/Registry.cls (modified â€” third-base discovery, both queries)
- src/SessionAgent/Test/ReadOnlySqlInvariantTest.cls (new)
- src/SessionAgent/Test/ReadOnlySqlProofBatteryTest.cls (new)
- src/SessionAgent/Test/Fixture/StubNonConformingQueryTool.cls (new)
- src/SessionAgent/Test/InspectionSuiteVerificationTest.cls (modified â€” 33 + named list + representative args + third-base filter)
- src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls (modified â€” 132 cardinality)
- README.md (modified â€” catalog 33 + Guarded dynamic SQL subsection + FR60 row)
- _bmad-output/implementation-artifacts/sprint-status.yaml (status flips)
- _bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md (this record)

## Review Findings (code review 2026-06-11, security-critical pass)

**Verdict: APPROVE with fix-nows applied.** The read-only covenant holds. The
stage-3 `statementType` compiler gate is a deny-by-default allow-list (only
type 1 = SELECT reaches `%Execute`); no path bypasses it. Verified live that
INSERT / UPDATE / DELETE / CALL / DROP / CREATE / GRANT / TUNE / TRUNCATE /
CTE-wrapped-INSERT / mixed-case / whitespace-led / comment-prefixed writes are
ALL rejected pre-execution with write-proofs. Full regression ground truth
(canonical numerical-MAX `%UnitTest_Result` probe): **582 / 582 / 0**.

**SQL-injection adapted-4-layer confirmation (L4 â€” reviewer):**
- **L1 (schema priming)** â€” `GetInputSchema().sql.description` names the
  expected single-SELECT shape and the rejected verbs. âœ” present.
- **L2 (statementType compiler gate)** â€” stage 3 of `RunGuardedSelect`,
  `If tType '= 1` Quit-rejects before `%Execute`. Stronger than regex;
  verified deny-by-default across 10 mutation shapes live. âœ”
- **L3 (parameterless single-statement + caps)** â€” `tStmt.%Execute()` with no
  args; the operator SQL is passed verbatim to `%Prepare`, never concatenated
  with nor parameter-substituted by any external value. Row cap + char budget
  + elapsed guard present. âœ”
- **L4 (reviewer confirmation)** â€” confirmed L1/L2/L3 present and correct. âœ”

**HIGH/fix-now applied this review:**
- **cr-14-3-A (HIGH, fix-now) â€” comment-prefixed EXPLAIN bypassed the
  stage-1 keyword check.** `/* peek */ EXPLAIN SELECT ...` reached `%Execute`
  (compiles as statementType=1) and returned a plan â€” violating TODAY's
  contract that EXPLAIN is rejected (14.6 stretch owns the future allowance).
  Reproduced live (`ok` before fix). Fixed by making `ValidateSingleStatement`
  comment-aware: a leading `/* */` or `--` comment is skipped transparently
  before the first-token EXPLAIN check. Re-verified: `/* */ EXPLAIN` and
  `-- c\nEXPLAIN` and bare `EXPLAIN` all now `not_select`/rejected. No
  mutation either way (the QA lock test `TestCommentPrefixedExplainStaysReadOnly`
  was written to survive the fix and still passes).
- **cr-14-3-B (MEDIUM, fix-now) â€” semicolon inside a comment false-rejected a
  legit single SELECT.** `SELECT ... /* has ; here */ ORDER BY ID` returned
  `multi_statement` (reproduced live) because the semicolon scanner tracked
  only string literals, not comments. An LLM emitting an inline-comment query
  would hit a baffling multi-statement rejection. Fixed by the same
  comment-aware scanner (semicolons inside `/* */` / `--` are no longer
  statement separators). Defense-in-depth note added: the security control is
  the stage-3 gate + `%Prepare`'s own SQLCODE-25 multi-statement rejection;
  comment-awareness removes false-positives without weakening the gate.
- **cr-14-3-C (MEDIUM, fix-now) â€” >8 KB SQL executed but its audit row
  silently dropped (FR60 / NFR-S4 violation).** `Audit.ToolCall.ArgsJson`
  carried `MAXLEN=8192`; a 15 KB SQL dispatched via real `Registry.Dispatch`
  returned `ok` but wrote NO audit row (`%Save` DATATYPE overflow swallowed by
  the Dispatch audit-emit path; reproduced live â€” 0 rows for the 15 KB case).
  `execute_readonly_sql` is the FIRST tool whose primary arg is unbounded
  free-text SQL, so 14.3 makes this latent ceiling reachable. Bumped
  `ArgsJson MAXLEN` 8192 â†’ 32768 (parity with `ResultJson`). Re-verified: the
  15 KB SQL now persists its audit row (ArgsLen=15053). AuditTest 6/6 green.
- **cr-14-3-D (LOW, fix-now / hardening) â€” invariant-test instantiation
  evasion.** Added `%SQL.STATEMENT` to `ReadOnlySqlInvariantTest`'s forbidden
  tokens (3â†’4) so a non-conforming tool that builds `%Prepare`/`%Execute`
  method names dynamically (slipping the substring greps) is still caught by
  the `%SQL.Statement` instantiation it cannot avoid. A conforming Query tool
  routes all execution through the base and never touches `%SQL.Statement`.
  `TestForbiddenTokenListLocked` updated to assert 4 tokens; 3/3 (probe-shown)
  invariant methods green.
- **cr-14-3-E (LOW, fix-now) â€” `StatementTypeName` friendly-name coverage.**
  Added GRANT(7)/REVOKE(8)/CREATE VIEW(12)/DROP VIEW(14)/GRANT(33)/REVOKE(34)/
  CREATE PROCEDURE(37)/TUNE TABLE(52) so the `not_select` envelope names the
  rejected verb instead of the bare `statementType=N` integer (verified GRANT
  and TUNE TABLE render their names live). Unmapped codes still fall back to
  the generic label (the gate already rejects them regardless).

**Verified-correct (no change needed):**
- Guard-pipeline ordering: validation â†’ %Prepare â†’ statementType gate â†’
  %Execute â†’ capped fetch â†’ post-loop fetch-fault gate â†’ envelope. No path to
  `%Execute` skips the gate.
- Char-budget arithmetic: truncating row is NOT pushed; rows under budget ship;
  `truncate_reason` âˆˆ {row_cap, char_budget, elapsed_guard} consistent with
  `truncated`. Off-by-one correct (`>` boundary).
- Elapsed-guard honesty: class doc + README both state fetch-loop-boundary
  semantics + 300 s Web-Gateway backstop; no preemption claim. âœ”
- Hint path: `AppendSqlcodeHint` is Try/Catch-wrapped, `$IsObject` guards the
  `SlugIdxOpen` read, falls back to the generic hint when the article is
  absent (fresh namespace) â€” no exception path.
- Registry third-base + fixture exclusion: ListTools filters
  `NOT (Name %STARTSWITH 'SessionAgent.Test.')` (package-prefix), so the stub
  fixture cannot leak into the catalog; ListTools = **33** live. ResolveToolName
  intentionally does NOT filter (fixture-dispatch contract).
- FR60 audit enrichment: `row_count` / `truncated` / `elapsed_ms` are captured
  in the persisted `ResultJson` envelope (verified verbatim in the live audit
  row). The denormalized `ResultSetSize` column is 0 â€” but it is 0 for EVERY
  tool family-wide (Dispatch never passes `pResultSetSize`); see deferred-work.

**Doc-accuracy note (no code impact):** the dev Completion-Notes line claims a
554+17 = **571** sweep; that count predates the QA `ReadOnlySqlAdversarialTest`
(+11). Live post-QA ground truth is **582 / 582 / 0** â€” which matches the
review-stage expected baseline. Treat 582 as the authoritative number.

Two pre-existing cross-cutting items recorded in `deferred-work.md`
(audit `ResultSetSize` never populated by Dispatch; audit args > 32768 still
drop under the swallowed-status Dispatch path).
