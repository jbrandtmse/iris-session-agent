Include Ensemble

/// <p>Story 3.9 unit tests for the sample interop production. Three tests
/// per AC-7:</p>
/// <ol>
///   <li><b>TestSampleProductionStarts</b> — InstallProduction +
///       StartProductionIfStopped, verify Ens.Director sees it running.</li>
///   <li><b>TestScenariosProduceExpectedMessageCounts</b> — RunScenario("none")
///       produces ≥4 Ens.MessageHeader rows for the new session.</li>
///   <li><b>TestErrorInjectionProducesExpectedIsErrorCounts</b> —
///       RunScenario("businessOperationFailure") produces ≥1
///       IsError=1 row.</li>
/// </ol>
///
/// <p>Test isolation: <method>OnBeforeAllTests</method> installs the
/// production + starts it (idempotent if a previous run already started
/// it). <method>OnAfterAllTests</method> stops + uninstalls so the dev
/// install returns to its baseline shape.</p>
Class SessionAgent.Test.SampleProductionTest Extends %UnitTest.TestCase
{

Parameter PRODUCTIONNAME As %String = "SessionAgent.Sample.Production";

/// Maximum wait (in seconds) for the async trace to complete after
/// dispatching a scenario.
Parameter TRACEWAITSECS As %Integer = 15;

/// Constructor — required initvalue forwarding per project rule
/// "Critical Constructor Requirements".
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// Class-level setup — install + start the production once. Skip with
/// $$$OK if any step fails so per-test code can short-circuit + assert
/// the install worked.
Method OnBeforeAllTests() As %Status
{
    Set tInstSC = ##class(SessionAgent.Sample.Bootstrap).InstallProduction()
    If $$$ISERR(tInstSC) Quit tInstSC
    Set tStartSC = ##class(SessionAgent.Sample.Bootstrap).StartProductionIfStopped()
    If $$$ISERR(tStartSC) Quit tStartSC
    Quit $$$OK
}

/// Class-level teardown — stop + uninstall. Best-effort; an error here
/// should not fail tests that already passed.
Method OnAfterAllTests() As %Status
{
    Do ##class(SessionAgent.Sample.Bootstrap).UninstallProduction()
    Quit $$$OK
}

/// Test 1 — Production registers + starts cleanly.
Method TestSampleProductionStarts()
{
    Set tProdName = ..#PRODUCTIONNAME

    Do $$$AssertTrue(##class(Ens.Config.Production).%ExistsId(tProdName), "Ens.Config.Production row exists for "_tProdName)

    Set tStatusSC = ##class(Ens.Director).GetProductionStatus(.tRunningName, .tState)
    Do $$$AssertStatusOK(tStatusSC, "Ens.Director.GetProductionStatus succeeded")
    Do $$$AssertEquals(tRunningName, tProdName, "Currently running production matches sample production name")
    Do $$$AssertEquals(tState, $$$eProductionStateRunning, "Production state is Running")
}

/// Test 2 — RunScenario("none") produces ≥4 Ens.MessageHeader rows for
/// the returned session id.
Method TestScenariosProduceExpectedMessageCounts()
{
    Set tSessionId = ""
    Set tSC = ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("none", "SessionAgent.Sample.BS.OrderIngest", .tSessionId)
    Do $$$AssertStatusOK(tSC, "RunScenario(""none"") returned OK")
    Do $$$AssertNotEquals(tSessionId, "", "RunScenario produced a non-empty session id")

    Set tCount = ..waitForTrace(tSessionId, ..#TRACEWAITSECS, 4)
    Do $$$AssertTrue(tCount >= 4, "Ens.MessageHeader rows for session "_tSessionId_" >= 4 (got "_tCount_")")
}

/// Test 3 — RunScenario("businessOperationFailure") produces ≥1
/// IsError=1 Ens.MessageHeader row.
Method TestErrorInjectionProducesExpectedIsErrorCounts()
{
    Set tSessionId = ""
    Set tSC = ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario("businessOperationFailure", "SessionAgent.Sample.BS.OrderIngest", .tSessionId)
    Do $$$AssertStatusOK(tSC, "RunScenario(""businessOperationFailure"") returned OK on dispatch")
    Do $$$AssertNotEquals(tSessionId, "", "RunScenario produced a non-empty session id")

    ; Wait for the trace to grow, then count IsError rows.
    Do ..waitForTrace(tSessionId, ..#TRACEWAITSECS, 4)
    Set tErrCount = ..countIsErrorRows(tSessionId)
    Do $$$AssertTrue(tErrCount >= 1, "Ens.MessageHeader IsError=1 rows for session "_tSessionId_" >= 1 (got "_tErrCount_")")
}

/// Helper — poll Ens.MessageHeader for the given session id until the
/// row count reaches pTargetCount or pMaxSecs elapses. Returns the
/// final row count. Hangs in 0.5-second increments.
ClassMethod waitForTrace(pSessionId As %String, pMaxSecs As %Integer = 15, pTargetCount As %Integer = 4) As %Integer
{
    Set tStart = $ZH
    Set tCount = 0
    While ($ZH - tStart) < pMaxSecs {
        Set tCount = ..countTraceRows(pSessionId)
        If tCount >= pTargetCount Quit
        Hang 0.5
    }
    Quit tCount
}

/// Helper — count Ens.MessageHeader rows for a given session id via
/// %SQL.Statement.
ClassMethod countTraceRows(pSessionId As %String) As %Integer [ Internal ]
{
    Set tCount = 0
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS C FROM Ens.MessageHeader WHERE SessionId = ?")
    If $$$ISERR(tPrepSC) Quit 0
    Set tRS = tStmt.%Execute(pSessionId)
    If tRS.%Next() {
        Set tCount = tRS.%Get("C")
    }
    Quit tCount
}

/// Helper — count Ens.MessageHeader rows where IsError=1 for a given
/// session id.
ClassMethod countIsErrorRows(pSessionId As %String) As %Integer [ Internal ]
{
    Set tCount = 0
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS C FROM Ens.MessageHeader WHERE SessionId = ? AND IsError = 1")
    If $$$ISERR(tPrepSC) Quit 0
    Set tRS = tStmt.%Execute(pSessionId)
    If tRS.%Next() {
        Set tCount = tRS.%Get("C")
    }
    Quit tCount
}

}
