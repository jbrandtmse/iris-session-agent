/// <p>Unit tests for the three Story 2.11 inspection tools —
/// <CLASS>SessionAgent.Tool.Inspection.SessionSummary</CLASS>,
/// <CLASS>SessionAgent.Tool.Inspection.SessionTimeline</CLASS>, and
/// <CLASS>SessionAgent.Tool.Inspection.MessageHeaders</CLASS>.</p>
///
/// <p>Nine Test* methods cover Story 2.11 AC-1 through AC-4:</p>
/// <ol>
/// <li><b>TestSessionSummaryReturnsExpectedCounts</b> — happy path
/// (5 fixture rows, 2 errors).</li>
/// <li><b>TestSessionSummaryMissingSessionIdReturnsError</b> —
/// validation error envelope.</li>
/// <li><b>TestSessionTimelineReturnsChronologicalOrder</b> — ordering
/// + 5 events.</li>
/// <li><b>TestSessionTimelineMissingSessionIdReturnsError</b> —
/// validation error envelope.</li>
/// <li><b>TestMessageHeadersReturnsAllRows</b> — 5 headers.</li>
/// <li><b>TestMessageHeadersMinSeverityErrorReturnsErrorRowsOnly</b> —
/// IsError filter cuts to 2.</li>
/// <li><b>TestAllThreeToolsConformToMcpEnvelope</b> — content[0] +
/// structuredContent shape across all three.</li>
/// <li><b>TestAllThreeToolsAreReadOnly</b> — MutatesState=0 on all
/// three (FR36 / NFR-S1).</li>
/// <li><b>TestRegistryDiscoversAllThreeTools</b> — the three names
/// appear in <method>SessionAgent.Tool.Registry.ListTools</method>.</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds 5
/// <CLASS>Ens.MessageHeader</CLASS> rows with a deterministic shape:
/// <code>SessionId=999911</code> (a numeric session id well outside
/// the range of any realistic Ens production value to avoid collision),
/// 2 of which have <code>IsError=1</code>. Row IDs captured in
/// process-private global <code>^||SessionAgentTest211Ids</code> for
/// guaranteed cleanup. <method>OnAfterAllTests</method> deletes by ID.</p>
///
/// <p><b>Note on fixture session-id type.</b>
/// <property>Ens.MessageHeader.SessionId</property> is declared
/// <code>%Integer</code> per <code>irislib/Ens/MessageHeaderBase.cls</code>
/// line 43, so the fixture uses an integer (999911) and tests pass the
/// stringified integer through the JSON args (consistent with how the
/// AgentLoop will surface session ids).</p>
Class SessionAgent.Test.InspectionToolTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONID As %Integer = 999911;

/// <p>Constructor — accepts <code>initvalue</code> from
/// <CLASS>%UnitTest.TestCase</CLASS> and forwards via <code>##super</code>
/// (project rule §"Critical Constructor Requirements"). No
/// <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed 5 deterministic <CLASS>Ens.MessageHeader</CLASS> fixture
/// rows for <code>SessionId = 999911</code>. Two rows carry
/// <code>IsError = 1</code>. Captures the row IDs in
/// <code>^||SessionAgentTest211Ids</code> for cleanup.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest211Ids
    Set tSession = ..#FIXTURESESSIONID
    ; Defensive — sweep any prior-run debris so the seeded count is
    ; deterministic even if a prior OnAfterAllTests didn't fire.
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tCleanup.%Execute(tSession)
    }
    ; Use $Horolog (date,seconds) for deterministic integer-second math —
    ; $ZDateTimeH cannot parse fractional-second $ZDateTime output, so
    ; build the base from $Horolog directly and increment by seconds.
    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)
    For tIdx = 1:1:5 {
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tSession
        Set tHdr.SourceConfigName = "TestSource_" _ tIdx
        Set tHdr.TargetConfigName = "TestTarget_" _ tIdx
        Set tHdr.MessageBodyClassName = $Case(tIdx, 1: "Test.RootRequest", : "Test.FollowupMessage_" _ tIdx)
        ; Distinct timestamps — increment seconds so chronological
        ; ordering is deterministic across runs. Use ODBC-format string
        ; (yyyy-mm-dd hh:mm:ss) which Ens.DataType.UTC accepts.
        Set tShiftedSecs = tBaseSecs + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tHdr.TimeCreated = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tHdr.IsError = $Case(tIdx, 3: 1, 5: 1, : 0)
        Set tSaveSC = tHdr.%Save()
        If $$$ISERR(tSaveSC) Quit
        Set ^||SessionAgentTest211Ids(tIdx) = tHdr.%Id()
    }
    Quit $$$OK
}

/// <p>Cleanup — delete the 5 fixture rows by ID and clear the
/// process-private global. Mandatory cleanup so re-running the test
/// suite never accumulates fixture rows in the
/// <code>Ens.MessageHeader</code> table.</p>
Method OnAfterAllTests() As %Status
{
    ; Belt-and-suspenders cleanup. Delete by captured IDs first (the
    ; common path), then sweep ANY rows whose SessionId matches the
    ; fixture id — covers the case where a prior test run died before
    ; cleanup, leaving stale rows that would otherwise poison the next
    ; OnBeforeAllTests count.
    For tIdx = 1:1:5 {
        Set tId = $Get(^||SessionAgentTest211Ids(tIdx))
        If tId '= "" {
            Do ##class(Ens.MessageHeader).%DeleteId(tId)
        }
    }
    Kill ^||SessionAgentTest211Ids
    ; Sweep any straggler fixture rows. Parameterized DELETE.
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")
    If $$$ISOK(tSC) Do tStmt.%Execute(..#FIXTURESESSIONID)
    Quit $$$OK
}

/// <p>Build a CallerContext with sane defaults for tool invocation
/// in tests. Tools should not crash on partially-populated contexts —
/// they only read PortalUser/Namespace/IrisSessionId fields.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#FIXTURESESSIONID
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-1 happy path. Asserts message_count=5, error_count=2, and
/// root_message_class is non-empty (specifically "Test.RootRequest"
/// per the fixture).</p>
Method TestSessionSummaryReturnsExpectedCounts()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SessionSummary).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SessionSummary.Invoke returns $$$OK")
    Do $$$AssertTrue($IsObject(tResult), "pResult populated as object")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("message_count"), 5, "message_count = 5 (5 fixture rows)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("error_count"), 2, "error_count = 2 (rows 3 + 5)")
    Do $$$AssertNotEquals(tResult.structuredContent.%Get("root_message_class"), "", "root_message_class is non-empty")
    Do $$$AssertEquals(tResult.structuredContent.%Get("root_message_class"), "Test.RootRequest", "root_message_class = 'Test.RootRequest' (first by ID asc)")
    Quit
}

/// <p>AC-1 validation path — empty pJsonArgs returns the standard
/// MCP error envelope, NOT an exception.</p>
Method TestSessionSummaryMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SessionSummary).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK even on validation failure (error in envelope, not %Status)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>AC-2 happy path. Asserts event_count=5 and chronological
/// ordering — each event's TimeCreated must be &gt;= the previous
/// event's TimeCreated (string comparison works because TIMESTAMP
/// values are lexicographically sortable).</p>
Method TestSessionTimelineReturnsChronologicalOrder()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SessionTimeline).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SessionTimeline.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("event_count"), 5, "event_count = 5")
    Set tEvents = tResult.structuredContent.%Get("events")
    Do $$$AssertEquals(tEvents.%Size(), 5, "events array has 5 entries")
    Set tPrevTime = ""
    Set tIter = tEvents.%GetIterator()
    Set tOrderingOk = 1
    While tIter.%GetNext(.tKey, .tEvent) {
        Set tThisTime = tEvent.%Get("time")
        If (tPrevTime '= "") && (tThisTime ]] tPrevTime = 0) && (tThisTime '= tPrevTime) {
            ; ]] is "follows in collation" — if tThisTime does NOT follow
            ; tPrevTime AND is not equal, the ordering is broken.
            Set tOrderingOk = 0
        }
        Set tPrevTime = tThisTime
    }
    Do $$$AssertTrue(tOrderingOk, "events sorted ASC by TimeCreated")
    Quit
}

/// <p>AC-2 validation path.</p>
Method TestSessionTimelineMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SessionTimeline).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>AC-3 happy path — all 5 fixture rows returned (no severity
/// filter).</p>
Method TestMessageHeadersReturnsAllRows()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.MessageHeaders).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "MessageHeaders.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("header_count"), 5, "header_count = 5")
    Set tHeaders = tResult.structuredContent.%Get("headers")
    Do $$$AssertEquals(tHeaders.%Size(), 5, "headers array has 5 entries")
    Quit
}

/// <p>AC-3 filter path — min_severity=error trims to the 2
/// IsError=1 rows.</p>
Method TestMessageHeadersMinSeverityErrorReturnsErrorRowsOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID), "min_severity": "error"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.MessageHeaders).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "MessageHeaders.Invoke with min_severity=error returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("header_count"), 2, "header_count = 2 (only IsError=1 rows)")
    ; Sanity — every row in the result has is_error = true.
    Set tAllErr = 1
    Set tIter = tResult.structuredContent.%Get("headers").%GetIterator()
    While tIter.%GetNext(.tKey, .tHdr) {
        ; Boolean values come back from %DynamicObject as 1/0; coerce
        ; with '+' to handle the JSON-true / JSON-false projection.
        If +tHdr.%Get("is_error") '= 1 Set tAllErr = 0
    }
    Do $$$AssertTrue(tAllErr, "every returned header has is_error = true")
    Quit
}

/// <p>AC-4 envelope conformance — all three tools return MCP success
/// envelopes with the expected shape: content[0].type='text',
/// content[0].text non-empty, structuredContent is a %DynamicObject.</p>
Method TestAllThreeToolsConformToMcpEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}

    For tClass = "SessionAgent.Tool.Inspection.SessionSummary", "SessionAgent.Tool.Inspection.SessionTimeline", "SessionAgent.Tool.Inspection.MessageHeaders" {
        Set tResult = ""
        Set tSC = $ClassMethod(tClass, "Invoke", tCtx, tArgs, .tResult)
        Do $$$AssertStatusOK(tSC, tClass _ ".Invoke returns $$$OK")
        Do $$$AssertTrue($IsObject(tResult), tClass _ " populated pResult as object")
        Do $$$AssertEquals(tResult.content.%Get(0).type, "text", tClass _ " content[0].type = 'text'")
        Do $$$AssertNotEquals(tResult.content.%Get(0).text, "", tClass _ " content[0].text non-empty")
        Do $$$AssertTrue($IsObject(tResult.structuredContent), tClass _ " structuredContent is %DynamicObject")
    }
    Quit
}

/// <p>AC-4 read-only invariant. Asserts MutatesState=0 on all three
/// classes via <code>%Dictionary.ParameterDefinition</code> rows
/// (matches the same reflection contract used by
/// <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch's L2 enforcement).</p>
Method TestAllThreeToolsAreReadOnly()
{
    For tClass = "SessionAgent.Tool.Inspection.SessionSummary", "SessionAgent.Tool.Inspection.SessionTimeline", "SessionAgent.Tool.Inspection.MessageHeaders" {
        Set tParam = ##class(%Dictionary.ParameterDefinition).%OpenId(tClass _ "||MutatesState")
        Do $$$AssertTrue($IsObject(tParam), tClass _ " has MutatesState parameter row")
        Do $$$AssertEquals(+tParam.Default, 0, tClass _ " MutatesState = 0 (read-only)")
    }
    Quit
}

/// <p>AC-4 registry discovery. Asserts that
/// <method>SessionAgent.Tool.Registry.ListTools</method> surfaces all
/// three tool names. Order-independent comparison; allows any number
/// of additional tools (e.g., the Story 2.10 stub fixtures) to coexist.</p>
Method TestRegistryDiscoversAllThreeTools()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFoundSummary = 0
    Set tFoundTimeline = 0
    Set tFoundHeaders = 0
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tName = tEntry.%Get("name")
        If tName = "session_summary" Set tFoundSummary = 1
        If tName = "session_timeline" Set tFoundTimeline = 1
        If tName = "message_headers" Set tFoundHeaders = 1
    }
    Do $$$AssertTrue(tFoundSummary, "Registry surfaces 'session_summary'")
    Do $$$AssertTrue(tFoundTimeline, "Registry surfaces 'session_timeline'")
    Do $$$AssertTrue(tFoundHeaders, "Registry surfaces 'message_headers'")
    Quit
}

}
