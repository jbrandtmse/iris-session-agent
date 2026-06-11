/// <p>Story 14.3 QA gap battery — ADVERSARIAL read-only-bypass coverage for
/// <CLASS>SessionAgent.Tool.Query.ExecuteReadonlySql</CLASS> /
/// <CLASS>SessionAgent.Tool.Query.Base</CLASS>. This is the SECURITY story's
/// gap layer: the dev battery
/// (<CLASS>SessionAgent.Test.ReadOnlySqlProofBatteryTest</CLASS>) proves the
/// bare INSERT/UPDATE/DELETE/CALL/EXPLAIN cases; this class proves the
/// statementType compiler gate (L2) holds against the adversarial INPUT
/// shapes an LLM (or a prompt-injected operator request) can emit to try to
/// smuggle a write past it — comment prefixes, case variation, leading
/// control characters, CTE-wrapping, DDL/DCL leading keywords — and that
/// legitimate SELECT shapes (string literals containing SQL keywords, CTEs,
/// UNIONs, parameter markers, very long input) are NOT false-rejected and
/// never crash the tool.</p>
///
/// <p><b>Write-proof technique.</b> Every mutation-attempt test targets
/// <code>Ens_Util.Log</code> with a UNIQUE sentinel ConfigName and asserts
/// the sentinel row count is 0 after the dispatch — robust against
/// concurrent production writes to the same table (a plain
/// before/after total count would flake under a running production).</p>
///
/// <p><b>Probed live on HSCUSTOM 2026-06-11</b> (qa-generate-e2e-tests
/// stage) before locking semantics — see the test-summary doc.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md">Story 14.3</a> — FR60 / AC-6 read-only proof.</li>
/// <li><CLASS>SessionAgent.Test.ReadOnlySqlProofBatteryTest</CLASS> — the dev battery this class extends.</li>
/// </ul>
Class SessionAgent.Test.ReadOnlySqlAdversarialTest Extends %UnitTest.TestCase
{

/// Sentinel ConfigName value that must NEVER appear in Ens_Util.Log —
/// every write-attempt test uses it as the would-be-written value.
Parameter SENTINEL As %String = "qa143-adversarial-sentinel-never";

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
    Set tCtx.IrisSessionId = 9799913
    Set tCtx.PortalUser = "qa-adversarial"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Invoke <code>execute_readonly_sql</code> with the given SQL and
/// return the envelope.</p>
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

/// <p>Count of <code>Ens_Util.Log</code> rows carrying the sentinel
/// ConfigName — the write-proof predicate (must stay 0).</p>
ClassMethod SentinelCount() As %Integer
{
    Set tCount = -1
    Set tSentinel = ..#SENTINEL
    &sql(SELECT COUNT(*) INTO :tCount FROM Ens_Util.Log WHERE ConfigName = :tSentinel)
    If SQLCODE '= 0 Quit -1
    Quit tCount
}

/// <p>Assert a non-SELECT dispatch was rejected pre-execution with the
/// <code>not_select</code> render strategy. Instance method (assertion
/// macros expand to instance calls).</p>
Method AssertNotSelect(pResult As %DynamicObject, pLabel As %String)
{
    Do $$$AssertEquals(+pResult.%Get("isError"), 1, pLabel _ ": isError=1")
    Do $$$AssertEquals(pResult.structuredContent.%Get("render_strategy"), "not_select", pLabel _ ": render_strategy='not_select'")
}

/// <p>GAP — comment-prefixed write shapes (<code>/* */ INSERT</code>
/// and <code>-- line</code> + newline + INSERT) must STILL be rejected
/// by the statementType gate (the leading-keyword validation is NOT the
/// security control — the compiler gate is). Write-proof: the sentinel
/// row never lands.</p>
Method TestCommentPrefixedWriteRejectedWithProof()
{
    Do $$$AssertEquals(..SentinelCount(), 0, "pre: sentinel absent")

    Set tBlock = "/* harmless looking */ INSERT INTO Ens_Util.Log (ConfigName) VALUES ('" _ ..#SENTINEL _ "')"
    Set tResult = ..RunTool(tBlock)
    Do ..AssertNotSelect(tResult, "block-comment INSERT")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "INSERT", "block-comment: rejected type INSERT")

    Set tLine = "-- just a comment" _ $Char(10) _ "INSERT INTO Ens_Util.Log (ConfigName) VALUES ('" _ ..#SENTINEL _ "')"
    Set tResult = ..RunTool(tLine)
    Do ..AssertNotSelect(tResult, "line-comment INSERT")

    Do $$$AssertEquals(..SentinelCount(), 0, "WRITE-PROOF: sentinel row never written by comment-prefixed INSERTs")
    Quit
}

/// <p>GAP — case-insensitive write keywords (<code>iNsErT</code>,
/// <code>UpDaTe</code>, <code>delete</code>) are rejected: the
/// statementType gate is case-independent (it inspects the compiled
/// metadata, not the literal text). Write-proof on the INSERT.</p>
Method TestCaseInsensitiveWriteRejected()
{
    Do $$$AssertEquals(..SentinelCount(), 0, "pre: sentinel absent")

    Set tResult = ..RunTool("iNsErT INTO Ens_Util.Log (ConfigName) VALUES ('" _ ..#SENTINEL _ "')")
    Do ..AssertNotSelect(tResult, "mixed-case INSERT")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "INSERT", "mixed-case: rejected type INSERT")

    Set tResult = ..RunTool("UpDaTe Ens.MessageHeader SET Status = 1 WHERE ID = -1")
    Do ..AssertNotSelect(tResult, "mixed-case UPDATE")

    Set tResult = ..RunTool("delete from Ens.MessageHeader where ID = -1")
    Do ..AssertNotSelect(tResult, "lowercase DELETE")

    Do $$$AssertEquals(..SentinelCount(), 0, "WRITE-PROOF: sentinel never written by mixed-case INSERT")
    Quit
}

/// <p>GAP — leading whitespace / control characters before a write
/// keyword do not slip a mutation past the gate; and the SAME leading
/// whitespace before a legitimate SELECT does NOT cause a false
/// rejection (the SELECT executes).</p>
Method TestLeadingWhitespaceControlChars()
{
    Do $$$AssertEquals(..SentinelCount(), 0, "pre: sentinel absent")

    ; Newlines + tabs + spaces ahead of an UPDATE — still rejected.
    Set tResult = ..RunTool($Char(10) _ $Char(9) _ "  UPDATE Ens.MessageHeader SET Status = 1 WHERE ID = -1")
    Do ..AssertNotSelect(tResult, "whitespace-led UPDATE")

    ; Newlines + tabs + spaces ahead of an INSERT — still rejected, no write.
    Set tResult = ..RunTool($Char(13, 10, 9) _ "INSERT INTO Ens_Util.Log (ConfigName) VALUES ('" _ ..#SENTINEL _ "')")
    Do ..AssertNotSelect(tResult, "whitespace-led INSERT")
    Do $$$AssertEquals(..SentinelCount(), 0, "WRITE-PROOF: whitespace-led INSERT wrote nothing")

    ; Same leading whitespace ahead of a legit SELECT — must pass.
    Set tResult = ..RunTool("   " _ $Char(10) _ "  SELECT TOP 1 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "whitespace-led SELECT succeeds (no false reject)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "whitespace-led SELECT render_strategy='ok'")
    Quit
}

/// <p>GAP — DDL / DCL leading keywords (DROP, CREATE, TRUNCATE, GRANT,
/// TUNE) are each rejected pre-execution by the statementType gate, even
/// though only INSERT/UPDATE/DELETE/CALL/EXPLAIN were in the dev battery.
/// Proves the gate is a deny-by-default allow-list (only type 1 passes),
/// not a deny-list of known-bad keywords. Write-proof: the target table
/// survives the DROP attempt.</p>
Method TestDdlAndDclLeadingKeywordsRejected()
{
    Set tResult = ..RunTool("DROP TABLE Ens.MessageHeader")
    Do ..AssertNotSelect(tResult, "DROP TABLE")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "DROP TABLE", "DROP named")

    Set tResult = ..RunTool("CREATE TABLE SessionAgent_Qa.Tmp143 (X INT)")
    Do ..AssertNotSelect(tResult, "CREATE TABLE")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "CREATE TABLE", "CREATE named")

    ; IRIS classifies TRUNCATE TABLE as a DELETE (statementType=4) — still rejected.
    Set tResult = ..RunTool("TRUNCATE TABLE Ens.MessageHeader")
    Do ..AssertNotSelect(tResult, "TRUNCATE TABLE")

    ; GRANT (DCL) — rejected though the type code is not in the friendly-name map.
    Set tResult = ..RunTool("GRANT SELECT ON Ens.MessageHeader TO _PUBLIC")
    Do ..AssertNotSelect(tResult, "GRANT")

    ; TUNE TABLE (statistics, statementType=52) — rejected.
    Set tResult = ..RunTool("TUNE TABLE Ens.MessageHeader")
    Do ..AssertNotSelect(tResult, "TUNE TABLE")

    ; Write-proof for the DROP: the table is still queryable.
    Set tProbe = ..RunTool("SELECT TOP 1 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tProbe.%Get("isError"), 0, "WRITE-PROOF: Ens.MessageHeader survived the DROP attempt")
    Quit
}

/// <p>GAP — the canonical bypass: a CTE-wrapped INSERT
/// (<code>WITH t AS (SELECT ...) INSERT INTO ...</code>). IRIS compiles
/// the whole statement as statementType=2 (INSERT), so the gate catches
/// it — the SELECT-looking prefix does NOT smuggle the write through.
/// Write-proof on the sentinel.</p>
Method TestCteWrappedInsertRejected()
{
    Do $$$AssertEquals(..SentinelCount(), 0, "pre: sentinel absent")
    Set tSql = "WITH t AS (SELECT 1 AS X) INSERT INTO Ens_Util.Log (ConfigName) SELECT '" _ ..#SENTINEL _ "' FROM t"
    Set tResult = ..RunTool(tSql)
    Do ..AssertNotSelect(tResult, "CTE-wrapped INSERT")
    Do $$$AssertEquals(tResult.structuredContent.%Get("rejected_statement_type"), "INSERT", "CTE-wrapped: rejected type INSERT")
    Do $$$AssertEquals(..SentinelCount(), 0, "WRITE-PROOF: CTE-wrapped INSERT wrote nothing")
    Quit
}

/// <p>GAP / false-positive guard — a legitimate SELECT whose STRING
/// LITERAL contains SQL metacharacters and keywords
/// (<code>'; DROP TABLE x</code>) must NOT be rejected: the literal is
/// data, the statement is a single SELECT. Proves the single-statement
/// scanner honors string-literal boundaries (no naive keyword/semicolon
/// matching inside quotes).</p>
Method TestStringLiteralWithSqlKeywordsNotFalseRejected()
{
    Set tSql = "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SourceConfigName = '''; DROP TABLE x' ORDER BY ID"
    Set tResult = ..RunTool(tSql)
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "legit SELECT with keyword-bearing literal is NOT rejected")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' for keyword-in-literal SELECT")

    ; And the literal value itself round-trips as data, not interpreted.
    Set tEcho = ..RunTool("SELECT TOP 1 '; DELETE FROM t' AS Lit FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tEcho.%Get("isError"), 0, "literal-only SELECT succeeds")
    Do $$$AssertEquals(tEcho.structuredContent.rows.%Get(0).%Get(0), "; DELETE FROM t", "literal value round-trips verbatim")
    Quit
}

/// <p>GAP — <code>SELECT ... INTO :hostvar</code> (host-variable target,
/// invalid in dynamic SQL) is rejected at <code>%Prepare</code> with the
/// canonical <code>prepare_error</code> envelope — it never reaches
/// execution and never throws.</p>
Method TestSelectIntoHostVarRejected()
{
    Set tResult = ..RunTool("SELECT ID INTO :x FROM Ens.MessageHeader WHERE ID = -1")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "SELECT INTO host var returns isError=1")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "prepare_error", "render_strategy='prepare_error'")
    Quit
}

/// <p>GAP — an unbound parameter marker (<code>?</code>) in the SQL: no
/// parameters are bound (L3 — the operator's SQL is executed
/// parameterless), so IRIS fails the execute with a graceful
/// <code>execute_error</code> envelope rather than crashing the tool.
/// Locks the envelope shape.</p>
Method TestUnboundParameterMarkerGracefulEnvelope()
{
    Set tResult = ..RunTool("SELECT TOP 1 ID FROM Ens.MessageHeader WHERE ID = ?")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "unbound ? returns isError=1 (no crash)")
    Set tStrategy = tResult.structuredContent.%Get("render_strategy")
    Do $$$AssertTrue((tStrategy = "execute_error") || (tStrategy = "prepare_error"), "unbound ? -> execute_error/prepare_error (got '" _ tStrategy _ "')")
    Do $$$AssertTrue($IsObject(tResult.content), "envelope still carries a content array")
    Quit
}

/// <p>GAP — very long SQL input (~40000 chars, a single huge string
/// literal) does not trip a MAXLEN error or throw: the tool accepts the
/// input, executes, and the OUTPUT char budget caps the result. Proves
/// the <code>sql</code> arg path tolerates large input.</p>
Method TestVeryLongSqlInputHandled()
{
    Set tLit = ""
    For i = 1:1:4000 { Set tLit = tLit _ "abcdefghij" }
    Do $$$AssertTrue($Length(tLit) >= 40000, "literal built to >= 40000 chars (got " _ $Length(tLit) _ ")")
    Set tResult = ..RunTool("SELECT TOP 1 '" _ tLit _ "' AS LongLit FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "very-long-SQL input does not error/crash")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "very-long-SQL render_strategy='ok'")
    Quit
}

/// <p>GAP / read-only-invariant lock — comment-prefixed EXPLAIN
/// (<code>/* c */ EXPLAIN SELECT ...</code>) bypasses the stage-1
/// leading-keyword check (the first token is the comment, not EXPLAIN)
/// and IRIS compiles it as statementType=1, so it executes and returns
/// a query plan. This is NOT a read-only violation — EXPLAIN produces a
/// plan, mutates nothing — but it DOES leak past the EXPLAIN-rejection
/// nicety. This test locks the SECURITY-meaningful invariant: regardless
/// of whether the keyword check catches it, the dispatch mutates NO
/// state. (Bare-keyword <code>EXPLAIN</code>, lower/upper, IS still
/// rejected — covered in the dev battery; see the test-summary finding
/// for the comment-prefix gap.)</p>
Method TestCommentPrefixedExplainStaysReadOnly()
{
    Do $$$AssertEquals(..SentinelCount(), 0, "pre: sentinel absent")
    ; This path is read-only whether accepted (plan) or rejected — assert
    ; only the security-meaningful truth (no mutation), so the test holds
    ; under either a future keyword-check fix or the 14.6 EXPLAIN allowance.
    Set tResult = ..RunTool("/* peek */ EXPLAIN SELECT TOP 1 ID FROM Ens.MessageHeader")
    Do $$$AssertTrue($IsObject(tResult), "EXPLAIN-comment dispatch returns an envelope (no crash)")
    Do $$$AssertEquals(..SentinelCount(), 0, "WRITE-PROOF: comment-prefixed EXPLAIN mutated nothing")
    ; Bare EXPLAIN keyword (no comment prefix) remains rejected at validation.
    Set tBare = ..RunTool("EXPLAIN SELECT TOP 1 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tBare.%Get("isError"), 1, "bare EXPLAIN still rejected")
    Do $$$AssertEquals(tBare.structuredContent.%Get("render_strategy"), "not_select", "bare EXPLAIN render_strategy='not_select'")
    Quit
}

/// <p>GAP — legitimate read-only compositions the LLM will emit (CTE and
/// UNION) are NOT false-rejected: both compile as statementType=1 and
/// execute. Guards against an over-eager future tightening of the
/// single-statement / keyword validation.</p>
Method TestLegitCteAndUnionPass()
{
    Set tResult = ..RunTool("WITH t AS (SELECT TOP 3 ID FROM Ens.MessageHeader) SELECT * FROM t")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "CTE SELECT succeeds")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "CTE render_strategy='ok'")

    Set tResult = ..RunTool("SELECT TOP 2 ID FROM Ens.MessageHeader UNION SELECT TOP 2 ID FROM Ens.MessageHeader")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "UNION SELECT succeeds")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "UNION render_strategy='ok'")
    Quit
}

}
