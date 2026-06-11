/// <p>Story 14.3 AC-6 — the read-only PROOF battery for
/// <CLASS>SessionAgent.Tool.Query.ExecuteReadonlySql</CLASS> /
/// <CLASS>SessionAgent.Tool.Query.Base</CLASS>. Asserts every mutation
/// shape (INSERT / UPDATE / DELETE / CALL / EXPLAIN) is rejected
/// PRE-execution (statementType gate or validation), with a SQL probe
/// proving no row was written for the INSERT attempt; plus row cap,
/// char budget + truncated marker, elapsed_ms presence, ODBC timestamp
/// rendering, the seeded −29 hint, multi-statement rejection, and the
/// empty-result ok-envelope.</p>
///
/// <p>Split from <CLASS>SessionAgent.Test.ReadOnlySqlInvariantTest</CLASS>
/// per the ~500-line test-class cap (battery vs invariant).</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md">Story 14.3</a> — AC-6 source.</li>
/// </ul>
Class SessionAgent.Test.ReadOnlySqlProofBatteryTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = 9799911
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Helper — invoke <code>execute_readonly_sql</code> directly with
/// the given SQL (and optional max_rows) and return the envelope.</p>
ClassMethod RunTool(pSql As %String, pMaxRows As %Integer = 0) As %DynamicObject
{
    Set tArgs = {}
    Do tArgs.%Set("sql", pSql)
    If pMaxRows > 0 Do tArgs.%Set("max_rows", pMaxRows, "number")
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Query.ExecuteReadonlySql).Invoke(..BuildCtx(), tArgs, .tResult)
    If $$$ISERR(tSC) Quit {"isError":(1), "content":[{"type":"text","text":"Invoke returned error %Status"}]}
    Quit tResult
}

/// <p>AC-6 — INSERT rejected pre-execution by the statementType gate,
/// with a SQL write-proof: the target table's row count is IDENTICAL
/// before and after the dispatch attempt.</p>
Method TestInsertRejectedWithWriteProof()
{
    Set tBefore = 0, tAfter = 0
    &sql(SELECT COUNT(*) INTO :tBefore FROM Ens_Util.Log)
    Do $$$AssertEquals(SQLCODE, 0, "pre-count probe SQLCODE=0")
    Set tResult = ..RunTool("INSERT INTO Ens_Util.Log (ConfigName) VALUES ('story-14-3-should-never-land')")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "INSERT dispatch returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "not_select", "render_strategy='not_select' for INSERT")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "INSERT", "rejected statement type named INSERT")
    &sql(SELECT COUNT(*) INTO :tAfter FROM Ens_Util.Log)
    Do $$$AssertEquals(SQLCODE, 0, "post-count probe SQLCODE=0")
    Do $$$AssertEquals(tAfter, tBefore, "WRITE-PROOF: Ens_Util.Log row count unchanged (" _ tBefore _ " -> " _ tAfter _ ")")
    Quit
}

/// <p>AC-6 — UPDATE and DELETE rejected pre-execution by the
/// statementType gate, each named in the envelope.</p>
Method TestUpdateAndDeleteRejected()
{
    Set tResult = ..RunTool("UPDATE Ens.MessageHeader SET Status = 1 WHERE ID = -1")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "UPDATE returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "not_select", "UPDATE render_strategy='not_select'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "UPDATE", "rejected type named UPDATE")

    Set tResult = ..RunTool("DELETE FROM Ens.MessageHeader WHERE ID = -1")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "DELETE returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "not_select", "DELETE render_strategy='not_select'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "DELETE", "rejected type named DELETE")
    Quit
}

/// <p>AC-6 — CALL rejected pre-execution (statementType 45 per the
/// Task 0 empirical table) and EXPLAIN rejected at validation (Task 0:
/// EXPLAIN prepares as statementType=1 on this build, so the leading
/// keyword is the honest rejection point).</p>
Method TestCallAndExplainRejected()
{
    Set tResult = ..RunTool("CALL Ens.MessageHeader_Extent()")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "CALL returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "not_select", "CALL render_strategy='not_select'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "CALL", "rejected type named CALL")

    Set tResult = ..RunTool("EXPLAIN SELECT TOP 1 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "EXPLAIN returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "not_select", "EXPLAIN render_strategy='not_select'")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "EXPLAIN", "operator-text names EXPLAIN")
    Quit
}

/// <p>AC-6 — multi-statement input is rejected by the stage-1
/// validation with the structured envelope; the DROP never reaches
/// <code>%Prepare</code>.</p>
Method TestMultiStatementRejected()
{
    Set tResult = ..RunTool("SELECT TOP 1 ID FROM Ens.MessageHeader; DROP TABLE Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "multi-statement returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "multi_statement", "render_strategy='multi_statement'")
    Quit
}

/// <p>Single-statement edge cases (Task 0 probes) — a trailing
/// semicolon is tolerated; a semicolon INSIDE a string literal is not
/// a statement separator.</p>
Method TestSemicolonEdgeCases()
{
    Set tResult = ..RunTool("SELECT TOP 1 ID FROM Ens.MessageHeader;")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "trailing semicolon tolerated (success envelope)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "trailing-semicolon render_strategy='ok'")

    Set tResult = ..RunTool("SELECT TOP 1 'a;b' AS X FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "semicolon inside string literal tolerated")
    Do $$$AssertEquals(tResult.structuredContent.rows.%Get(0).%Get(0), "a;b", "literal value 'a;b' round-trips")
    Quit
}

/// <p>AC-6 — row cap honored with the explicit <code>truncated</code>
/// marker, and a caller-supplied <code>max_rows</code> above the hard
/// ceiling is clamped to <code>HARDMAXROWS</code>.</p>
Method TestRowCapAndHardMaxClamp()
{
    ; Ens.MessageHeader carries thousands of sample-production rows.
    Set tResult = ..RunTool("SELECT ID FROM Ens.MessageHeader", 2)
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "row-cap query succeeds")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("row_count"), 2, "row_count capped at max_rows=2")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 1, "truncated marker set when rows remain")
    Do $$$AssertEquals(tResult.structuredContent.%Get("truncate_reason"), "row_cap", "truncate_reason='row_cap'")

    ; max_rows above the hard ceiling clamps to HARDMAXROWS (200).
    Set tResult = ..RunTool("SELECT ID FROM Ens.MessageHeader", 9999)
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "over-cap query succeeds")
    Do $$$AssertTrue(+tResult.structuredContent.%Get("row_count") <= 200, "row_count clamped to HARDMAXROWS=200 (got " _ tResult.structuredContent.%Get("row_count") _ ")")
    Quit
}

/// <p>AC-6 — total result char budget: wide synthetic rows
/// (<code>{fn REPEAT}</code>, 2000 chars each) trip the 32000-char
/// budget well before the row cap; the envelope carries the explicit
/// <code>truncated</code> marker with <code>char_budget</code> reason.</p>
Method TestCharBudgetTruncation()
{
    Set tResult = ..RunTool("SELECT TOP 50 {fn REPEAT('x', 2000)} AS Wide FROM Ens.MessageHeader", 50)
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "char-budget query succeeds")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 1, "truncated marker set on char-budget trip")
    Do $$$AssertEquals(tResult.structuredContent.%Get("truncate_reason"), "char_budget", "truncate_reason='char_budget'")
    Set tRowCount = +tResult.structuredContent.%Get("row_count")
    Do $$$AssertTrue((tRowCount > 0) && (tRowCount < 17), "row_count stops under the 32000-char budget (2000 chars/row; got " _ tRowCount _ ")")
    Quit
}

/// <p>AC-6 — <code>elapsed_ms</code> is present and non-negative on the
/// ok envelope (presence/positivity only — never exact values, per the
/// determinism dev note).</p>
Method TestElapsedMsPresence()
{
    Set tResult = ..RunTool("SELECT TOP 3 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "query succeeds")
    Do $$$AssertTrue(tResult.structuredContent.%IsDefined("elapsed_ms"), "elapsed_ms present")
    Do $$$AssertTrue(+tResult.structuredContent.%Get("elapsed_ms") >= 0, "elapsed_ms non-negative")
    Quit
}

/// <p>AC-6 — ODBC rendering of a timestamp column (<code>%SelectMode=1</code>
/// set by the base pipeline pre-<code>%Prepare</code>): TimeCreated
/// renders as <code>YYYY-MM-DD HH:MM:SS[.fff]</code> text, not a
/// $Horolog pair.</p>
Method TestOdbcTimestampRendering()
{
    Set tResult = ..RunTool("SELECT TOP 1 TimeCreated FROM Ens.MessageHeader ORDER BY ID DESC")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "timestamp query succeeds")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("row_count"), 1, "one row returned")
    Set tVal = tResult.structuredContent.rows.%Get(0).%Get(0)
    Do $$$AssertTrue($Length(tVal) >= 19, "ODBC timestamp at least 19 chars (got '" _ tVal _ "')")
    Do $$$AssertEquals($Extract(tVal, 5), "-", "dash at position 5 (YYYY-)")
    Do $$$AssertEquals($Extract(tVal, 8), "-", "dash at position 8 (YYYY-MM-)")
    Do $$$AssertEquals($Extract(tVal, 11), " ", "space separator at position 11")
    Do $$$AssertEquals($Extract(tVal, 14), ":", "colon at position 14")
    Quit
}

/// <p>AC-4 / AC-6 — the seeded −29 failure (alias-in-GROUP-BY shape)
/// returns the prepare-error envelope whose <code>hint</code> is the
/// −29 line from the knowledge corpus's diagnostic-checklist article
/// (locked contract: <code>SQLCODE &lt;n&gt; / symptom -&gt; fix</code>).</p>
Method TestHintOnSeededMinus29()
{
    Set tResult = ..RunTool("SELECT Name, COUNT(*) FROM Ens.MessageHeader GROUP BY SourceConfigName")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "seeded -29 returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "prepare_error", "render_strategy='prepare_error'")
    Set tHint = tResult.structuredContent.%Get("hint")
    Do $$$AssertTrue($Extract(tHint, 1, 12) = "SQLCODE -29 ", "hint is the article's -29 line (starts 'SQLCODE -29 '; got '" _ $Extract(tHint, 1, 40) _ "...')")
    Do $$$AssertTrue(tHint [ "GROUP BY", "hint carries the -29 symptom->fix text")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "Hint: SQLCODE -29", "operator-text carries the appended hint")
    Quit
}

/// <p>Hint fallback — a SQLCODE with no matching article line (e.g.
/// −30, table not found — not in the diagnostic checklist) falls back
/// to the generic consult-the-corpus hint.</p>
Method TestHintFallbackOnUnmappedSqlcode()
{
    Set tResult = ..RunTool("SELECT ID FROM SessionAgent_NoSuch.Table143")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "unknown-table prepare failure returns isError=1")
    Set tHint = tResult.structuredContent.%Get("hint")
    Do $$$AssertTrue(tHint [ "get_query_knowledge", "fallback hint points at get_query_knowledge (got '" _ tHint _ "')")
    Quit
}

/// <p>AC-6 — empty-result ok-envelope: zero rows is SUCCESS (not an
/// error), with <code>row_count=0</code>, an empty <code>rows</code>
/// array, populated <code>columns</code>, and no truncation.</p>
Method TestEmptyResultOkEnvelope()
{
    Set tResult = ..RunTool("SELECT ID, SessionId FROM Ens.MessageHeader WHERE ID = -1")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "empty result is a success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("row_count"), 0, "row_count=0")
    Do $$$AssertEquals(tResult.structuredContent.rows.%Size(), 0, "rows array empty")
    Do $$$AssertEquals(tResult.structuredContent.columns.%Size(), 2, "columns array still populated (2 columns)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 0, "truncated=false")
    Quit
}

/// <p>FR37 — missing required <code>sql</code> arg returns the
/// canonical validation envelope (never throws).</p>
Method TestMissingSqlReturnsErrorEnvelope()
{
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Query.ExecuteReadonlySql).Invoke(..BuildCtx(), {}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on missing sql (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing sql")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "sql is required", "operator-text names the missing arg")
    Quit
}

}
