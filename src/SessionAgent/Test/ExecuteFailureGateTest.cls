/// <p>Story 14.0 AC-3 — unit + end-to-end coverage for the
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnExecuteFailure</method>
/// centralized execute-failure gate (deferred-work cr-13-3 closure).</p>
///
/// <p><b>Empirical premises (captured in Story 14.0 Task 0/4 probes).</b></p>
/// <ul>
/// <li>Per <code>irislib/%SQL/StatementResult.cls</code> lines 210–222:
/// <code>%SQLCODE &lt; 0</code> = runtime error, <code>0</code> = success,
/// <code>100</code> = no-more-data (NOT an error; only set after
/// <code>%Next()</code> exhausts the cursor).</li>
/// <li>A scalar no-FROM <code>SELECT DATEDIFF('ms', ?, ?)</code> with a
/// non-timestamp second argument fails with <code>%SQLCODE = -400</code>
/// <b>immediately at %Execute time</b> (probe:
/// <code>afterExecute=-400</code>). Table-context predicates
/// (<code>WHERE SessionId = ?</code> with 'abc',
/// <code>TimeCreated &gt;= ?</code> with garbage, <code>TOP ?</code> with
/// 'abc') are all silently coerced by IRIS and do NOT produce runtime
/// errors — which is why the end-to-end test below poisons stored
/// <code>TimeCreated</code> data via <code>UPDATE %NOCHECK</code> to
/// reach <CLASS>SessionAgent.Tool.Inspection.SessionTimeline</CLASS>'s
/// scalar DATEDIFF statement (the one in-repo statement shape that
/// fails at %Execute).</li>
/// </ul>
///
/// <p><b>Story 14.0 review restage.</b> SessionTimeline's span DATEDIFF
/// is a best-effort enrichment whose execute failure now gracefully
/// skips (review fix — a poisoned span no longer nukes the
/// successfully-built timeline). The end-to-end here therefore asserts
/// the GRACEFUL-SKIP contract (success envelope, span_ms=0). The
/// AC-3c <code>render_strategy="execute_error"</code> taxonomy is
/// covered by <CLASS>SessionAgent.Test.ExecuteFailureAdaptedSitesTest</CLASS>
/// (find_sessions_using_class two-link chain: real runtime %Execute
/// failure → marker %Status → canonical execute_error envelope).</p>
///
/// <p><b>Fixture hygiene.</b> The end-to-end test seeds two synthetic
/// <CLASS>Ens.MessageHeader</CLASS> rows under the project-reserved
/// synthetic session id 9799914014, poisons their TimeCreated, and
/// deletes them at the end of the method (idempotent DELETE — also run
/// defensively at test start AND in <method>OnAfterOneTest</method> so
/// a mid-test throw cannot leak poisoned rows).</p>
Class SessionAgent.Test.ExecuteFailureGateTest Extends %UnitTest.TestCase
{

/// <p>Synthetic session id well outside any realistic Ens production
/// range (sibling of InspectionSuiteVerificationTest's 9799911).</p>
Parameter SYNTHETICSESSIONID As %Integer = 9799914014;

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Story 14.0 review fix — ensured cleanup path: a mid-test throw or
/// assertion-failure abort can no longer leak the poisoned synthetic
/// Ens.MessageHeader fixture rows (DeleteSyntheticRows is idempotent;
/// harmless for the unit-test methods that seed nothing).</p>
Method OnAfterOneTest() As %Status
{
    Do ..DeleteSyntheticRows()
    Quit $$$OK
}

/// <p>Success-shape envelope matching the Tool.Base mutation contract —
/// callers pre-initialize pResult before invoking the helper.</p>
ClassMethod BuildSuccessShapeResult() As %DynamicObject
{
    Quit {"content":[{"type":"text","text":""}], "structuredContent":{}}
}

/// <p>CallerContext fixture — same shape as InspectionSuiteVerificationTest.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#SYNTHETICSESSIONID
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-3(a) — helper returns 0 and leaves pResult untouched for a
/// successful result set (%SQLCODE = 0 immediately after %Execute).</p>
Method TestHelperReturnsZeroOnSuccessfulResultSet()
{
    Set tResult = ..BuildSuccessShapeResult()
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT 1 AS one")
    Do $$$AssertStatusOK(tSC, "probe SELECT prepares clean")
    Set tRS = tStmt.%Execute()
    Do $$$AssertEquals(tRS.%SQLCODE, 0, "successful %Execute leaves %SQLCODE = 0")
    Set tRet = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(tResult, tRS, "test_tool")
    Do $$$AssertEquals(tRet, 0, "helper returns 0 on success")
    Do $$$AssertTrue('tResult.%IsDefined("isError"), "pResult.isError NOT added on success")
    Do $$$AssertEquals(tResult.content.%Get(0).text, "", "content[0].text untouched on success")
    Do $$$AssertTrue('tResult.structuredContent.%IsDefined("render_strategy"), "render_strategy NOT added on success")
    Do $$$AssertTrue('tResult.structuredContent.%IsDefined("error_text"), "error_text NOT added on success")
    Quit
}

/// <p>AC-3(b) — helper returns 1 and shapes the canonical execute_error
/// envelope when a REAL runtime-failing SELECT sets %SQLCODE &lt; 0 at
/// %Execute time. Vehicle: scalar no-FROM DATEDIFF with a non-timestamp
/// second argument (empirically %SQLCODE = -400 immediately after
/// %Execute — see class doc-comment).</p>
Method TestHelperShapesEnvelopeOnRealRuntimeFailure()
{
    Set tResult = ..BuildSuccessShapeResult()
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT DATEDIFF('ms', ?, ?) AS span_ms")
    Do $$$AssertStatusOK(tSC, "DATEDIFF SELECT prepares clean (failure is runtime, not prepare)")
    Set tRS = tStmt.%Execute("not-a-timestamp", "also-garbage")
    Do $$$AssertTrue(tRS.%SQLCODE < 0, "runtime failure sets %SQLCODE < 0 at %Execute (got " _ tRS.%SQLCODE _ ")")
    Set tRet = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(tResult, tRS, "test_tool")
    Do $$$AssertEquals(tRet, 1, "helper returns 1 on runtime failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1")
    ; Story 14.0 review fix — assert a generic negative SQLCODE rather
    ; than the engine-version-brittle literal -400.
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "Tool 'test_tool' SQL execute failed: SQLCODE -", "content[0].text carries tool name + negative SQLCODE (got: " _ tResult.content.%Get(0).text _ ")")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "execute_error", "render_strategy = 'execute_error'")
    Do $$$AssertTrue(tResult.structuredContent.%Get("error_text") [ "SQLCODE -", "error_text carries a negative SQLCODE")
    Quit
}

/// <p>AC-3(b) companion — stub %SQL.StatementResult with hand-set
/// %SQLCODE/%Message proves the envelope shaping is driven purely by
/// the documented %SQLCODE contract (deterministic, engine-independent).</p>
Method TestHelperShapesEnvelopeOnStubSqlcode()
{
    Set tResult = ..BuildSuccessShapeResult()
    Set tRS = ##class(%SQL.StatementResult).%New()
    Set tRS.%SQLCODE = -99
    Set tRS.%Message = "stub privilege violation"
    Set tRet = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(tResult, tRS, "stub_tool")
    Do $$$AssertEquals(tRet, 1, "helper returns 1 on stub %SQLCODE = -99")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1")
    Do $$$AssertEquals(tResult.content.%Get(0).text, "Tool 'stub_tool' SQL execute failed: SQLCODE -99: stub privilege violation", "content[0].text exact canonical shape")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "execute_error", "render_strategy = 'execute_error'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("error_text"), "SQLCODE -99: stub privilege violation", "error_text exact canonical shape")
    Quit
}

/// <p>%SQLCODE = 100 (no-more-data) is NOT an error — per
/// irislib/%SQL/StatementResult.cls lines 210–222 the successful
/// completion values are 0 and 100. Guard must return 0.</p>
Method TestHelperTreatsSqlcode100AsSuccess()
{
    Set tResult = ..BuildSuccessShapeResult()
    Set tRS = ##class(%SQL.StatementResult).%New()
    Set tRS.%SQLCODE = 100
    Set tRet = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(tResult, tRS, "test_tool")
    Do $$$AssertEquals(tRet, 0, "%SQLCODE = 100 (no-more-data) is NOT an error")
    Do $$$AssertTrue('tResult.%IsDefined("isError"), "pResult untouched for %SQLCODE = 100")
    Quit
}

/// <p>Defensive — a non-object pRS (e.g. a code path that never assigned
/// the result set) shapes the same canonical envelope rather than
/// throwing &lt;INVALID OREF&gt;.</p>
Method TestHelperReturnsOneOnNonObjectResult()
{
    Set tResult = ..BuildSuccessShapeResult()
    Set tRet = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(tResult, "", "test_tool")
    Do $$$AssertEquals(tRet, 1, "helper returns 1 on non-object pRS")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on non-object pRS")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "execute_error", "render_strategy = 'execute_error' on non-object pRS")
    Do $$$AssertTrue(tResult.structuredContent.%Get("error_text") [ "non-object", "error_text names the non-object cause")
    Quit
}

/// <p>END-TO-END (Story 14.0 review restage): SessionTimeline's
/// best-effort span DATEDIFF gracefully skips on a runtime execute
/// failure — the successfully-built timeline is returned with
/// <code>time_span_ms = 0</code> instead of an error envelope. The
/// runtime failure is staged by seeding two synthetic Ens.MessageHeader
/// rows and poisoning their TimeCreated via UPDATE %NOCHECK — the
/// tool's first SELECT fetches the garbage values cleanly (logical-mode
/// read), and its SECOND statement (scalar
/// <code>SELECT DATEDIFF('ms', ?, ?)</code> over the fetched endpoint
/// values) fails at %Execute with a negative %SQLCODE, which the
/// adapted best-effort guard skips (mirroring the statement's graceful
/// prepare handling). The AC-3c execute_error e2e taxonomy lives in
/// <CLASS>SessionAgent.Test.ExecuteFailureAdaptedSitesTest</CLASS>.</p>
Method TestSessionTimelineSpanFailureGracefulSkip()
{
    ; Defensive pre-clean (idempotent).
    Do ..DeleteSyntheticRows()

    ; ---- Seed 2 rows with valid timestamps, then poison both. ----
    Set tSeedSC = ..SeedPoisonedRows()
    Do $$$AssertStatusOK(tSeedSC, "synthetic poisoned fixture rows seeded")
    If $$$ISERR(tSeedSC) {
        Do ..DeleteSyntheticRows()
        Quit
    }

    ; ---- Drive the tool end-to-end. ----
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SessionTimeline).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertTrue($IsObject(tResult), "pResult populated")
    Do $$$AssertTrue(+tResult.%Get("isError") '= 1, "NOT an error envelope — span failure is best-effort (graceful skip)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("event_count"), 2, "both seeded events returned despite poisoned span endpoints")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("time_span_ms"), 0, "time_span_ms degrades to 0 when the span DATEDIFF fails at %Execute")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "2 events", "content[0].text reports the timeline (got: " _ tResult.content.%Get(0).text _ ")")

    ; ---- Cleanup. ----
    Do ..DeleteSyntheticRows()
    Quit
}

/// <p>Seed two Ens.MessageHeader rows for the synthetic session, then
/// poison TimeCreated via UPDATE %NOCHECK (bypasses %TimeStamp
/// validation; empirically verified in Story 14.0 Task 4 probe). The
/// two garbage values sort 'a' &lt; 'b' under ORDER BY TimeCreated ASC
/// so the DATEDIFF second argument is 'garbage-ts-140b'.</p>
Method SeedPoisonedRows() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tStmtIns = ##class(%SQL.Statement).%New()
        Set tSC = tStmtIns.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, TimeCreated, SourceConfigName, TargetConfigName, Status, IsError, MessageBodyClassName) VALUES (?, ?, ?, ?, 1, 0, ?)")
        If $$$ISERR(tSC) Quit
        Set tRs1 = tStmtIns.%Execute(..#SYNTHETICSESSIONID, "2026-06-10 12:00:00", "Story140Src", "Story140Tgt", "Story140.ProbeBody")
        If tRs1.%SQLCODE < 0 Set tSC = $$$ERROR($$$GeneralError, "seed insert 1 failed: SQLCODE " _ tRs1.%SQLCODE _ ": " _ tRs1.%Message) Quit:$$$ISERR(tSC)
        Set tRs2 = tStmtIns.%Execute(..#SYNTHETICSESSIONID, "2026-06-10 12:00:05", "Story140Src", "Story140Tgt", "Story140.ProbeBody")
        If tRs2.%SQLCODE < 0 Set tSC = $$$ERROR($$$GeneralError, "seed insert 2 failed: SQLCODE " _ tRs2.%SQLCODE _ ": " _ tRs2.%Message) Quit:$$$ISERR(tSC)

        ; Poison: distinct garbage per row so ORDER BY ASC yields a
        ; deterministic (first, last) pair.
        Set tStmtUpd = ##class(%SQL.Statement).%New()
        Set tSC = tStmtUpd.%Prepare("UPDATE %NOCHECK Ens.MessageHeader SET TimeCreated = ? WHERE ID = (SELECT MIN(ID) FROM Ens.MessageHeader WHERE SessionId = ?)")
        If $$$ISERR(tSC) Quit
        Set tRsU1 = tStmtUpd.%Execute("garbage-ts-140a", ..#SYNTHETICSESSIONID)
        If tRsU1.%SQLCODE < 0 Set tSC = $$$ERROR($$$GeneralError, "poison update 1 failed: SQLCODE " _ tRsU1.%SQLCODE _ ": " _ tRsU1.%Message) Quit:$$$ISERR(tSC)
        Set tStmtUpd2 = ##class(%SQL.Statement).%New()
        Set tSC = tStmtUpd2.%Prepare("UPDATE %NOCHECK Ens.MessageHeader SET TimeCreated = ? WHERE ID = (SELECT MAX(ID) FROM Ens.MessageHeader WHERE SessionId = ?)")
        If $$$ISERR(tSC) Quit
        Set tRsU2 = tStmtUpd2.%Execute("garbage-ts-140b", ..#SYNTHETICSESSIONID)
        If tRsU2.%SQLCODE < 0 Set tSC = $$$ERROR($$$GeneralError, "poison update 2 failed: SQLCODE " _ tRsU2.%SQLCODE _ ": " _ tRsU2.%Message) Quit:$$$ISERR(tSC)
        Quit
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Quit
    }
    Quit tSC
}

/// <p>Idempotent fixture cleanup for the synthetic session rows.</p>
Method DeleteSyntheticRows()
{
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")
        If $$$ISOK(tSC) {
            Do tStmt.%Execute(..#SYNTHETICSESSIONID)
        }
        Quit
    }
    Catch ex {
        Quit
    }
    Quit
}

}
