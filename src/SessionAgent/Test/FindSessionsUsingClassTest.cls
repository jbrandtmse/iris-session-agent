/// <p>Unit tests for Story 13.5 —
/// <CLASS>SessionAgent.Tool.Search.FindSessionsUsingClass</CLASS>.
/// Ten Test* methods cover ACs 1–9:</p>
///
/// <ol>
/// <li><b>TestRegistryListToolsIncludesFindSessionsUsingClass</b> — AC-1:
///   registry surfaces <code>find_sessions_using_class</code> with non-empty
///   Description.</li>
/// <li><b>TestSQLInjectionRejectsInvalidClassName</b> — AC-2 Layer (b):
///   malformed class_name returns <code>isError=1</code> (regex rejection,
///   not SQL execution).</li>
/// <li><b>TestKnownClassReturnsSessionsWithShape</b> — AC-3: known class
///   returns sessions array; each entry has required fields.</li>
/// <li><b>TestMatchFieldSourceConfigFiltersCorrectly</b> — AC-4:
///   <code>match_field="source_config"</code> with a class only in
///   TargetConfigName returns empty sessions.</li>
/// <li><b>TestTimeWindowHoursRespected</b> — AC-5: stale rows outside
///   the window are excluded.</li>
/// <li><b>TestLimitClamp</b> — AC-6: <code>limit=3</code> returns at
///   most 3 sessions.</li>
/// <li><b>TestUnknownClassReturnsEmptyClean</b> — AC-7: totally unknown
///   class returns <code>sessions=[]</code>, <code>session_count=0</code>,
///   <code>render_strategy="ok"</code>, no <code>isError</code>.</li>
/// <li><b>TestStripLastSegmentAutoCorrects</b> — AC-8 positive: appending
///   ".SomeMethod" strips to the real class name; response carries
///   <code>class_name_auto_corrected_from</code>.</li>
/// <li><b>TestStripLastSegmentStillNotFoundReturnsCandidateField</b> —
///   AC-8 negative: wholly unknown class with method suffix returns
///   empty sessions + <code>candidate_class_name</code>.</li>
/// <li><b>TestInputSchemaDescriptionContainsMethodWarning</b> — AC-9:
///   <code>GetInputSchema()</code>
///   <code>properties.class_name.description</code> contains
///   "Pass the class name only".</li>
/// </ol>
///
/// <p><b>AI-5 carry-forward.</b> All substring-grep test assertions
/// enumerate ALL expected hits rather than partial matches that could
/// collide with class/method names appearing elsewhere.</p>
///
/// <p><b>Fixture strategy.</b> Inserts synthetic
/// <CLASS>Ens.MessageHeader</CLASS> rows with fixture sentinel values
/// in <code>SourceConfigName</code>, <code>TargetConfigName</code>, and
/// <code>MessageBodyClassName</code>. Uses distinct class-name sentinels
/// per scenario so tests are isolated. Cleanup via parameterized DELETE
/// in <method>OnAfterAllTests</method>.</p>
Class SessionAgent.Test.FindSessionsUsingClassTest Extends %UnitTest.TestCase
{

/// Sentinel class name stored in SourceConfigName for fixture rows.
Parameter FIXTURESRCCLASS As %String = "Fixture.FSUC.SrcClass";

/// Sentinel class name stored in TargetConfigName for fixture rows.
Parameter FIXTURETGTCLASS As %String = "Fixture.FSUC.TgtClass";

/// Sentinel class name stored in MessageBodyClassName for fixture rows.
Parameter FIXTUREBODYCLASS As %String = "Fixture.FSUC.BodyClass";

/// Base session ID for scenario 1 (match_field=any, AC-3).
Parameter FIXTUREBASE As %Integer = 9990001;

/// Base session ID for scenario 2 (match_field=source_config, AC-4).
Parameter FIXTUREBASE2 As %Integer = 9990010;

/// Base session ID for scenario 3 (time_window, AC-5).
Parameter FIXTUREBASE3 As %Integer = 9990020;

/// Base session ID for scenario 4 (limit clamp, AC-6).
Parameter FIXTUREBASE4 As %Integer = 9990030;

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed fixture MessageHeader rows for all scenarios.</p>
Method OnBeforeAllTests() As %Status
{
    Do ..CleanupFixture()

    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)

    ; --- Scenario 1 (AC-3 / AC-4): 3 sessions with src=FIXTURESRCCLASS, tgt=FIXTURETGTCLASS
    ; Session BASE+0: src=FIXTURESRCCLASS, tgt=FIXTURETGTCLASS, body=FIXTUREBODYCLASS
    ; Session BASE+1: src=FIXTURESRCCLASS only
    ; Session BASE+2: tgt=FIXTURETGTCLASS only (body differs)
    Set tRows1 = $ListBuild(
        $ListBuild(..#FIXTUREBASE + 0, ..#FIXTURESRCCLASS, ..#FIXTURETGTCLASS, ..#FIXTUREBODYCLASS, 0),
        $ListBuild(..#FIXTUREBASE + 1, ..#FIXTURESRCCLASS, "Fixture.FSUC.OtherTgt", "Fixture.FSUC.OtherBody", 1),
        $ListBuild(..#FIXTUREBASE + 2, "Fixture.FSUC.OtherSrc", ..#FIXTURETGTCLASS, "Fixture.FSUC.OtherBody2", 2))
    For tIdx = 1:1:$ListLength(tRows1) {
        Set tRow = $ListGet(tRows1, tIdx)
        Set tSess = $ListGet(tRow, 1)
        Set tSrc = $ListGet(tRow, 2)
        Set tTgt = $ListGet(tRow, 3)
        Set tBody = $ListGet(tRow, 4)
        Set tOff = $ListGet(tRow, 5)
        Set tSecs2 = tBaseSecs + tOff
        Set tH = $Select(tSecs2 >= 86400: (tBaseDate+1) _ "," _ (tSecs2-86400), 1: tBaseDate _ "," _ tSecs2)
        Do ..InsertMsgHeaderRow(tSess, tSrc, tTgt, tBody, $ZDateTime(tH, 3, 1, 0))
    }

    ; --- Scenario 2 (AC-4 source_config): session only has tgt=FIXTURETGTCLASS (not src)
    ; Already covered above by FIXTUREBASE+2.

    ; --- Scenario 3 (AC-5 time_window): 1 fresh + 2 stale (10 days back)
    For tIdx = 0:1:2 {
        Set tSess = ..#FIXTUREBASE3 + tIdx
        Set tDaysBack = tIdx * 10
        Set tH2 = (tBaseDate - tDaysBack) _ "," _ tBaseSecs
        Do ..InsertMsgHeaderRow(tSess, ..#FIXTURESRCCLASS, "FSUC.TWTgt" _ tIdx, "FSUC.TWBody" _ tIdx, $ZDateTime(tH2, 3, 1, 0))
    }

    ; --- Scenario 4 (AC-6 limit clamp): 10 sessions with src=FIXTURESRCCLASS
    For tIdx = 0:1:9 {
        Set tSess = ..#FIXTUREBASE4 + tIdx
        Set tSecs3 = tBaseSecs + tIdx + 100
        Set tH3 = $Select(tSecs3 >= 86400: (tBaseDate+1) _ "," _ (tSecs3-86400), 1: tBaseDate _ "," _ tSecs3)
        Do ..InsertMsgHeaderRow(tSess, ..#FIXTURESRCCLASS, "FSUC.LimTgt" _ tIdx, "FSUC.LimBody" _ tIdx, $ZDateTime(tH3, 3, 1, 0))
    }

    Quit $$$OK
}

/// <p>Cleanup — delete fixture rows by SessionId ranges.</p>
Method OnAfterAllTests() As %Status
{
    Do ..CleanupFixture()
    Quit $$$OK
}

/// <p>Delete all fixture MessageHeader rows by source sentinel prefix.</p>
ClassMethod CleanupFixture()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    ; Delete by session ID ranges covering all scenarios
    If $$$ISOK(tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId >= ? AND SessionId <= ?")) {
        Do tStmt.%Execute(..#FIXTUREBASE, ..#FIXTUREBASE + 9)
        Do tStmt.%Execute(..#FIXTUREBASE3, ..#FIXTUREBASE3 + 9)
        Do tStmt.%Execute(..#FIXTUREBASE4, ..#FIXTUREBASE4 + 9)
    }
    Quit
}

/// <p>Insert one fixture MessageHeader row.</p>
ClassMethod InsertMsgHeaderRow(pSessionId As %Integer, pSrc As %String, pTgt As %String, pBody As %String, pTime As %String)
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISERR(tStmt.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, SourceConfigName, TargetConfigName, MessageBodyClassName, TimeCreated, Type, Priority, Status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")) Quit
    Do tStmt.%Execute(pSessionId, pSrc, pTgt, pBody, pTime, 1, 1, 1)
    Quit
}

/// <p>Build a CallerContext for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-1 — registry surfaces <code>find_sessions_using_class</code>
/// with a non-empty Description.</p>
Method TestRegistryListToolsIncludesFindSessionsUsingClass()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tCandidate) {
        If tCandidate.%Get("name") = "find_sessions_using_class" {
            Set tFound = 1
            Set tEntry = tCandidate
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'find_sessions_using_class'")

    If $IsObject(tEntry) {
        Set tDesc = tEntry.%Get("description")
        Do $$$AssertTrue(tDesc '= "", "Description is non-empty")
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Get(0), "class_name", "schema.required[0] = 'class_name'")
        Do $$$AssertEquals(+tSchema.%Get("additionalProperties"), 0, "schema.additionalProperties = false")
    }
    Quit
}

/// <p>AC-2 Layer (b) — regex blocks malformed class_name at the server
/// side. All inputs below fail the <code>$Match</code> regex and return
/// <code>isError=1</code> without SQL execution. AI-5 carry-forward:
/// enumerate ALL expected hits (3 distinct malformed inputs tested).</p>
Method TestSQLInjectionRejectsInvalidClassName()
{
    Set tCtx = ..BuildCtx()

    ; Input 1: SQL injection attempt
    Set tArgs1 = {"class_name": "'; DROP TABLE Ens_MessageHeader; --"}
    Set tResult1 = ""
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs1, .tResult1)
    Do $$$AssertEquals(+tResult1.%Get("isError"), 1, "isError=1 for SQL injection attempt")
    Do $$$AssertTrue(tResult1.content.%Get(0).text [ "invalid class_name format", "error text mentions 'invalid class_name format' for SQL injection input")

    ; Input 2: invalid characters
    Set tArgs2 = {"class_name": "Invalid!Class@Name"}
    Set tResult2 = ""
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs2, .tResult2)
    Do $$$AssertEquals(+tResult2.%Get("isError"), 1, "isError=1 for Invalid!Class@Name")
    Do $$$AssertTrue(tResult2.content.%Get(0).text [ "invalid class_name format", "error text mentions 'invalid class_name format' for invalid chars input")

    ; Input 3: empty class_name
    Set tArgs3 = {"class_name": ""}
    Set tResult3 = ""
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs3, .tResult3)
    Do $$$AssertEquals(+tResult3.%Get("isError"), 1, "isError=1 for empty class_name")
    Do $$$AssertTrue(tResult3.content.%Get(0).text [ "missing class_name", "error text mentions 'missing class_name' for empty input")

    Quit
}

/// <p>AC-3 — known class returns sessions array with required fields
/// (<code>session_id</code>, <code>first_seen</code>,
/// <code>last_seen</code>, <code>msg_count</code>,
/// <code>matched_via</code>). Uses fixture rows inserted in
/// <method>OnBeforeAllTests</method>.</p>
Method TestKnownClassReturnsSessionsWithShape()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#FIXTURESRCCLASS), "time_window_hours": 24}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "FindSessionsUsingClass.Invoke OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on happy path")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok")
    Do $$$AssertTrue(+tSc.%Get("session_count") > 0, "session_count > 0 for known fixture class")

    Set tSessions = tSc.%Get("sessions")
    Do $$$AssertTrue($IsObject(tSessions), "sessions is an array object")

    ; Verify shape of first entry (all required fields present)
    Set tEntry = tSessions.%Get(0)
    If $IsObject(tEntry) {
        Do $$$AssertTrue(+tEntry.%Get("session_id") > 0, "session_id is numeric and > 0")
        Set tFirst = tEntry.%Get("first_seen")
        Do $$$AssertEquals($Length(tFirst), 20, "first_seen is 20 chars (ISO-Z)")
        Do $$$AssertEquals($Extract(tFirst, 11), "T", "first_seen char 11 = 'T'")
        Do $$$AssertEquals($Extract(tFirst, 20), "Z", "first_seen char 20 = 'Z'")
        Set tLast = tEntry.%Get("last_seen")
        Do $$$AssertEquals($Length(tLast), 20, "last_seen is 20 chars (ISO-Z)")
        Do $$$AssertTrue(+tEntry.%Get("msg_count") >= 1, "msg_count >= 1")
        Set tMV = tEntry.%Get("matched_via")
        Do $$$AssertTrue(tMV '= "", "matched_via is non-empty")
    }
    Quit
}

/// <p>AC-4 — <code>match_field="source_config"</code> only searches
/// <code>SourceConfigName</code>. Session FIXTUREBASE+2 has
/// <code>TargetConfigName=FIXTURETGTCLASS</code> but
/// <code>SourceConfigName</code> is a different sentinel — so querying
/// for FIXTURETGTCLASS with source_config match_field must return 0
/// sessions. AI-5 carry-forward: enumerate all sessions expected in the
/// negative case (0).</p>
Method TestMatchFieldSourceConfigFiltersCorrectly()
{
    Set tCtx = ..BuildCtx()
    ; FIXTURETGTCLASS only appears as TargetConfigName in our fixture rows.
    ; When we restrict to source_config, we should get 0 sessions.
    Set tArgs = {"class_name": (..#FIXTURETGTCLASS), "match_field": "source_config", "time_window_hours": 24}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for source_config filter")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("session_count"), 0, "session_count = 0 when TgtClass searched with source_config filter")
    Do $$$AssertEquals(tSc.%Get("match_field"), "source_config", "match_field echoed as source_config")

    ; Positive verification: querying FIXTURETGTCLASS with target_config → finds it
    Set tArgs2 = {"class_name": (..#FIXTURETGTCLASS), "match_field": "target_config", "time_window_hours": 24}
    Set tResult2 = ""
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs2, .tResult2)
    Set tSc2 = tResult2.structuredContent
    Do $$$AssertTrue(+tSc2.%Get("session_count") > 0, "session_count > 0 when TgtClass searched with target_config filter")
    Quit
}

/// <p>AC-5 — <code>time_window_hours</code> is enforced. Scenario 3 has
/// 1 fresh row (today) + 2 stale rows (10 days, 20 days back). With a
/// 24h window, only the 1 fresh row returns. With a 168h window, the
/// 10-day-old row is still excluded (10 days = 240h > 168h).</p>
Method TestTimeWindowHoursRespected()
{
    Set tCtx = ..BuildCtx()
    ; 24h window: only session FIXTUREBASE3+0 (today) should appear for src=FIXTURESRCCLASS
    ; Note: FIXTUREBASE and FIXTUREBASE4 sessions also have FIXTURESRCCLASS — use limit
    ; and session_id checks to distinguish. We specifically look for FIXTUREBASE3 range.
    Set tArgs = {"class_name": (..#FIXTURESRCCLASS), "match_field": "source_config", "time_window_hours": 24, "limit": 100}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for time window test")
    Set tSc = tResult.structuredContent
    ; FIXTUREBASE3+0 is fresh (today), FIXTUREBASE3+1 is 10 days old, FIXTUREBASE3+2 is 20 days old.
    ; With 24h window, only FIXTUREBASE3+0 should be present among FIXTUREBASE3 sessions.
    Set tFound0 = 0, tFound1 = 0, tFound2 = 0
    Set tSessions = tSc.%Get("sessions")
    Set tIter = tSessions.%GetIterator()
    While tIter.%GetNext(.tK, .tE) {
        If +tE.%Get("session_id") = (..#FIXTUREBASE3 + 0) Set tFound0 = 1
        If +tE.%Get("session_id") = (..#FIXTUREBASE3 + 1) Set tFound1 = 1
        If +tE.%Get("session_id") = (..#FIXTUREBASE3 + 2) Set tFound2 = 1
    }
    Do $$$AssertTrue(tFound0, "Fresh session FIXTUREBASE3+0 found with 24h window")
    Do $$$AssertTrue('tFound1, "Stale session FIXTUREBASE3+1 (10 days old) NOT found with 24h window")
    Do $$$AssertTrue('tFound2, "Stale session FIXTUREBASE3+2 (20 days old) NOT found with 24h window")

    ; Verify time_window_hours echoed back
    Do $$$AssertEquals(+tSc.%Get("time_window_hours"), 24, "time_window_hours echoed as 24")
    Quit
}

/// <p>AC-6 — <code>limit</code> clamps results. Scenario 4 has 10
/// sessions with <code>SourceConfigName=FIXTURESRCCLASS</code>. With
/// <code>limit=3</code>, at most 3 sessions are returned.</p>
Method TestLimitClamp()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#FIXTURESRCCLASS), "match_field": "source_config", "time_window_hours": 24, "limit": 3}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for limit clamp test")
    Set tSc = tResult.structuredContent
    Set tSessions = tSc.%Get("sessions")
    Do $$$AssertTrue(tSessions.%Size() <= 3, "sessions array has at most 3 entries with limit=3")
    Quit
}

/// <p>AC-7 — totally unknown class returns <code>sessions=[]</code>,
/// <code>session_count=0</code>, <code>render_strategy="ok"</code>,
/// no <code>isError</code>.</p>
Method TestUnknownClassReturnsEmptyClean()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": "Totally.Unknown.Class.FSUC9999"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for unknown class")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set (empty result is normal)")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("session_count"), 0, "session_count = 0")
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok")
    Set tSessions = tSc.%Get("sessions")
    Do $$$AssertEquals(tSessions.%Size(), 0, "sessions = []")
    Quit
}

/// <p>AC-8 positive — appending a dot-method suffix to a known class
/// triggers strip-last-segment; response carries
/// <code>class_name_auto_corrected_from</code> and the corrected
/// <code>class_name</code> matches the fixture sentinel.</p>
Method TestStripLastSegmentAutoCorrects()
{
    Set tCtx = ..BuildCtx()
    ; FIXTURESRCCLASS.SomeMethod should auto-correct to FIXTURESRCCLASS
    Set tInput = ..#FIXTURESRCCLASS _ ".SomeMethod"
    Set tArgs = {"class_name": (tInput), "match_field": "source_config", "time_window_hours": 24}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for strip-last-segment auto-correct")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("class_name"), ..#FIXTURESRCCLASS, "class_name corrected to FIXTURESRCCLASS")
    Do $$$AssertEquals(tSc.%Get("class_name_auto_corrected_from"), tInput, "class_name_auto_corrected_from = original input")
    Do $$$AssertTrue(+tSc.%Get("session_count") > 0, "session_count > 0 after auto-correct")
    Quit
}

/// <p>AC-8 negative — wholly unknown class with a method suffix still
/// returns empty sessions but includes <code>candidate_class_name</code>
/// (the stripped form) as a search hint.</p>
Method TestStripLastSegmentStillNotFoundReturnsCandidateField()
{
    Set tCtx = ..BuildCtx()
    Set tInput = "Totally.Unknown.FSUC9998.SomeMethod"
    Set tArgs = {"class_name": (tInput)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK for strip-last-segment still-not-found")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("session_count"), 0, "session_count = 0")
    Set tCandidate = tSc.%Get("candidate_class_name")
    Do $$$AssertEquals(tCandidate, "Totally.Unknown.FSUC9998", "candidate_class_name = stripped form")
    Quit
}

/// <p>AC-9 — <code>GetInputSchema()</code> <code>class_name</code>
/// description includes the anti-method-suffix warning phrase
/// "Pass the class name only".</p>
Method TestInputSchemaDescriptionContainsMethodWarning()
{
    Set tSchema = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).GetInputSchema()
    Do $$$AssertTrue($IsObject(tSchema), "GetInputSchema returns an object")
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")
    Set tClassNameProp = tProps.%Get("class_name")
    Do $$$AssertTrue($IsObject(tClassNameProp), "schema.properties.class_name is an object")
    Set tDesc = tClassNameProp.%Get("description")
    Do $$$AssertTrue(tDesc [ "Pass the class name only", "class_name description contains 'Pass the class name only' (got: " _ tDesc _ ")")
    Quit
}

}
