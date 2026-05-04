/// <p>Unit tests for the Story 4.6 inspection tool —
/// <CLASS>SessionAgent.Tool.Inspection.FindSessionsByBody</CLASS>. Seven
/// Test* methods cover Story 4.6 AC-3 through AC-5 + the Registry
/// surface check.</p>
///
/// <p><b>Tests (7):</b></p>
/// <ol>
/// <li><b>TestFindBySimpleValueReturnsMatchingSessions</b> — fixture: 3
/// sessions, each with a <CLASS>Ens.MessageHeader</CLASS> row whose
/// <code>MessageBodyId</code> points at a fixture-SearchTable row with
/// <code>(PropId=N, PropValue="12345")</code>. Asserts
/// <code>session_count=3</code>, all session_ids present, ISO-Z
/// timestamps shaped correctly, source/target config names
/// projected.</li>
/// <li><b>TestSearchTableNotInstalledReturnsError</b> — pass
/// <code>Nonexistent.Garbage.SearchTable</code>. Asserts
/// <code>render_strategy="search_table_not_installed"</code> +
/// <code>isError:1</code> with architecture-mandated wording.</li>
/// <li><b>TestNonSearchTableClassRejected</b> — pass
/// <code>Ens.MessageHeader</code> (exists but not a SearchTable).
/// Asserts <code>render_strategy="not_search_table_subclass"</code>.</li>
/// <li><b>TestTimeWindowFilter</b> — fixture: 4 rows spanning 2 weeks.
/// Asserts <code>time_window_hours=24</code> returns only the 1 fresh
/// row.</li>
/// <li><b>TestLimitClamp</b> — fixture: 100 matching rows. Asserts
/// <code>limit=10</code> returns exactly 10 entries.</li>
/// <li><b>TestMissingRequiredArgReturnsError</b> — FR37 envelopes for
/// each of the 3 required inputs missing.</li>
/// <li><b>TestRegistryListToolsIncludesFindSessionsByBody</b> —
/// <method>SessionAgent.Tool.Registry.ListTools</method> output
/// includes <code>find_sessions_by_body</code> with the AC-3 schema
/// (3 required props, additionalProperties false).</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds:</p>
/// <ul>
/// <li>1 row in <CLASS>Ens.Config.SearchTableProp</CLASS> (PropId=12345
/// for <code>(ClassExtent=fixture-class, Name="MRN")</code>) so the
/// production tool's prop-name → PropId lookup succeeds.</li>
/// <li>~108 rows in
/// <CLASS>SessionAgent.Test.FsbFixtureSearchTable</CLASS> across the
/// matching/time-window/limit-clamp scenarios.</li>
/// <li>~108 matching <CLASS>Ens.MessageHeader</CLASS> rows whose
/// <code>MessageBodyId</code> matches the fixture-SearchTable
/// <code>DocId</code>s.</li>
/// </ul>
///
/// <p><b>Cleanup.</b> <method>OnAfterAllTests</method> deletes by
/// fixture-class extent (SearchTable) + fixture session-id range
/// (MessageHeader) + the seeded SearchTableProp row.</p>
Class SessionAgent.Test.FindSessionsByBodyTest Extends %UnitTest.TestCase
{

Parameter FIXTURECLASS As %String = "SessionAgent.Test.FsbFixtureSearchTable";

Parameter FIXTUREPROPNAME As %String = "MRN";

Parameter FIXTUREPROPVALUE As %String = "12345";

Parameter FIXTUREPROPID As %Integer = 99046001;

/// Sentinel value for <code>SourceConfigName</code> — used to identify
/// fixture <CLASS>Ens.MessageHeader</CLASS> rows for cleanup. Random
/// enough to avoid clashing with any real production row.
Parameter FIXTURESOURCESENTINEL As %String = "FsbFixtureSrc-46";

/// Lower bound of the fixture session ID range — also used in cleanup
/// DELETE.
Parameter FIXTURESESSIONIDBASE As %Integer = 999461;

/// Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// Seed fixture rows. Plan:
/// 1. Defensive cleanup of any prior fixture rows.
/// 2. Insert one Ens.Config.SearchTableProp row for (FIXTURECLASS, "MRN")
///    with explicit PropId=FIXTUREPROPID.
/// 3. Insert 3 SearchTable rows with PropId=FIXTUREPROPID,
///    PropValue=FIXTUREPROPVALUE, distinct DocIds. Insert matching
///    MessageHeader rows whose MessageBodyId points at those DocIds.
///    Sessions: BASE, BASE+1, BASE+2 — used by
///    TestFindBySimpleValueReturnsMatchingSessions.
/// 4. Insert 4 (SearchTable, MessageHeader) pairs for the time-window
///    test — 1 fresh (now), 3 stale (10 days, 12 days, 14 days ago).
///    Sessions: BASE+10..13. Distinct PropValue=FIXTUREPROPVALUE_"-tw"
///    so they don't collide with scenario 3.
/// 5. Insert 100 (SearchTable, MessageHeader) pairs for the limit-clamp
///    test, all with PropValue=FIXTUREPROPVALUE_"-lc". Sessions: BASE+100..199.
Method OnBeforeAllTests() As %Status
{
    ; --- Step 1: defensive cleanup.
    Do ..CleanupFixture()

    ; --- Step 2: seed Ens.Config.SearchTableProp.
    ; ClassDerivation must be the ~-delimited inheritance chain ending in
    ; Ens.SearchTableBase per the irislib comment. For our fixture extending
    ; Ens.CustomSearchTable, the chain is:
    ;   ~SessionAgent.Test.FsbFixtureSearchTable~Ens.CustomSearchTable~Ens.SearchTableBase~
    Set tDerivation = "~" _ ..#FIXTURECLASS _ "~Ens.CustomSearchTable~Ens.SearchTableBase~"
    Set tInsertProp = ##class(%SQL.Statement).%New()
    Set tSC = tInsertProp.%Prepare("INSERT INTO Ens_Config.SearchTableProp (Name, ClassExtent, ClassDerivation, PropId, IsImplicit) VALUES (?, ?, ?, ?, ?)")
    If $$$ISERR(tSC) Quit tSC
    Set tRsp = tInsertProp.%Execute(..#FIXTUREPROPNAME, ..#FIXTURECLASS, tDerivation, ..#FIXTUREPROPID, 0)
    If tRsp.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "fixture SearchTableProp insert SQLCODE=" _ tRsp.%SQLCODE _ " " _ tRsp.%Message)

    ; --- Step 3: scenario 1 — 3 sessions matching the simple value.
    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)

    For tIdx = 0:1:2 {
        Set tSession = ..#FIXTURESESSIONIDBASE + tIdx
        Set tDocId = "FSB-DOC-" _ tSession
        Set tShiftedSecs = tBaseSecs + tIdx + 1
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tTime = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tSrc = ..#FIXTURESOURCESENTINEL _ "-Alpha" _ tIdx
        Set tTgt = ..#FIXTURESOURCESENTINEL _ "-AlphaOut" _ tIdx
        Do ..InsertSearchTableRow(..#FIXTUREPROPID, ..#FIXTUREPROPVALUE, tDocId)
        Do ..InsertMessageHeaderRow(tSession, tDocId, tSrc, tTgt, tTime)
    }

    ; --- Step 4: scenario 2 — time window. 1 fresh + 3 stale.
    Set tTwValue = ..#FIXTUREPROPVALUE _ "-tw"
    Set tTwScenarios = $ListBuild( $ListBuild(0, 1), $ListBuild(10, 0), $ListBuild(12, 0), $ListBuild(14, 0) )
    For tIdx = 1:1:$ListLength(tTwScenarios) {
        Set tEntry = $ListGet(tTwScenarios, tIdx)
        Set tDaysBack = $ListGet(tEntry, 1)
        Set tIsFresh = $ListGet(tEntry, 2)
        Set tSession = ..#FIXTURESESSIONIDBASE + 10 + tIdx
        Set tDocId = "FSB-DOC-TW-" _ tSession
        Set tHorolog = (tBaseDate - tDaysBack) _ "," _ tBaseSecs
        Set tTime = $ZDateTime(tHorolog, 3, 1, 0)
        Set tSrc = ..#FIXTURESOURCESENTINEL _ "-TW"
        Set tTgt = ..#FIXTURESOURCESENTINEL _ "-TWOut"
        Do ..InsertSearchTableRow(..#FIXTUREPROPID, tTwValue, tDocId)
        Do ..InsertMessageHeaderRow(tSession, tDocId, tSrc, tTgt, tTime)
    }

    ; --- Step 5: scenario 3 — limit clamp. 100 matching rows.
    Set tLcValue = ..#FIXTUREPROPVALUE _ "-lc"
    For tIdx = 1:1:100 {
        Set tSession = ..#FIXTURESESSIONIDBASE + 100 + tIdx
        Set tDocId = "FSB-DOC-LC-" _ tSession
        Set tShiftedSecs = tBaseSecs + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tTime = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tSrc = ..#FIXTURESOURCESENTINEL _ "-LC"
        Set tTgt = ..#FIXTURESOURCESENTINEL _ "-LCOut"
        Do ..InsertSearchTableRow(..#FIXTUREPROPID, tLcValue, tDocId)
        Do ..InsertMessageHeaderRow(tSession, tDocId, tSrc, tTgt, tTime)
    }
    Quit $$$OK
}

/// Helper — INSERT one fixture SearchTable row.
ClassMethod InsertSearchTableRow(pPropId As %Integer, pPropValue As %String, pDocId As %String)
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSql = "INSERT INTO SessionAgent_Test.FsbFixtureSearchTable (PropId, PropValue, DocId) VALUES (?, ?, ?)"
    Set tSC = tStmt.%Prepare(tSql)
    If $$$ISERR(tSC) Quit
    Set tRs = tStmt.%Execute(pPropId, pPropValue, pDocId)
    Quit
}

/// Helper — INSERT one fixture MessageHeader row.
ClassMethod InsertMessageHeaderRow(pSessionId As %Integer, pBodyId As %String, pSrc As %String, pTgt As %String, pTime As %String)
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSql = "INSERT INTO Ens.MessageHeader (SessionId, MessageBodyId, SourceConfigName, TargetConfigName, TimeCreated, Type, Priority, Status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    Set tSC = tStmt.%Prepare(tSql)
    If $$$ISERR(tSC) Quit
    Set tRs = tStmt.%Execute(pSessionId, pBodyId, pSrc, pTgt, pTime, 1, 1, 1)
    Quit
}

/// Cleanup — delete fixture rows by class-extent / session-range /
/// SearchTableProp row.
Method OnAfterAllTests() As %Status
{
    Do ..CleanupFixture()
    Quit $$$OK
}

ClassMethod CleanupFixture()
{
    ; SearchTable extent: drop the entire fixture class extent — it's
    ; isolated to this test.
    Set tStmtSt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmtSt.%Prepare("DELETE FROM SessionAgent_Test.FsbFixtureSearchTable")) {
        Do tStmtSt.%Execute()
    }
    ; MessageHeader: delete by SourceConfigName starting with the sentinel.
    Set tStmtMh = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmtMh.%Prepare("DELETE FROM Ens.MessageHeader WHERE %EXACT(SourceConfigName) %STARTSWITH ?")) {
        Do tStmtMh.%Execute(..#FIXTURESOURCESENTINEL)
    }
    ; SearchTableProp row.
    Set tStmtSp = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmtSp.%Prepare("DELETE FROM Ens_Config.SearchTableProp WHERE %EXACT(ClassExtent) = ? AND %EXACT(Name) = ?")) {
        Do tStmtSp.%Execute(..#FIXTURECLASS, ..#FIXTUREPROPNAME)
    }
    Quit
}

/// Build a CallerContext for tool invocation.
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// AC-4 happy path — find 3 sessions matching MRN=12345.
Method TestFindBySimpleValueReturnsMatchingSessions()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": (..#FIXTURECLASS), "prop_name": (..#FIXTUREPROPNAME), "prop_value": (..#FIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "FindSessionsByBody.Invoke OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on happy path")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "matched_sessions", "render_strategy = matched_sessions")
    Do $$$AssertEquals(+tSc.%Get("session_count"), 3, "session_count = 3")
    Set tSessions = tSc.%Get("sessions")
    Do $$$AssertEquals(tSessions.%Size(), 3, "sessions array has 3 entries")

    Set tFound0 = 0, tFound1 = 0, tFound2 = 0
    Set tIter = tSessions.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = (..#FIXTURESESSIONIDBASE + 0) Set tFound0 = 1
        If tSid = (..#FIXTURESESSIONIDBASE + 1) Set tFound1 = 1
        If tSid = (..#FIXTURESESSIONIDBASE + 2) Set tFound2 = 1
        ; Verify ISO-Z time shape.
        Set tTC = tEntry.%Get("time_created")
        Do $$$AssertEquals($Length(tTC), 20, "time_created is 20 chars (got: " _ tTC _ ")")
        Do $$$AssertEquals($Extract(tTC, 11), "T", "time_created char 11 = 'T'")
        Do $$$AssertEquals($Extract(tTC, 20), "Z", "time_created char 20 = 'Z'")
        ; Verify source/target config names projected.
        Set tSrc = tEntry.%Get("source_config_name")
        Do $$$AssertTrue(tSrc [ ..#FIXTURESOURCESENTINEL, "source_config_name carries fixture sentinel (got: " _ tSrc _ ")")
    }
    Do $$$AssertTrue(tFound0, "session BASE+0 returned")
    Do $$$AssertTrue(tFound1, "session BASE+1 returned")
    Do $$$AssertTrue(tFound2, "session BASE+2 returned")
    Quit
}

/// AC-4 — class not installed.
Method TestSearchTableNotInstalledReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": "Nonexistent.Garbage.SearchTable", "prop_name": (..#FIXTUREPROPNAME), "prop_value": (..#FIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing class")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "search_table_not_installed", "render_strategy = search_table_not_installed")
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "is not installed", "summary mentions 'is not installed' (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "body-field search is unavailable", "summary mentions 'body-field search is unavailable'")
    Quit
}

/// AC-4 — class exists but doesn't extend Ens.SearchTableBase.
Method TestNonSearchTableClassRejected()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": "Ens.MessageHeader", "prop_name": (..#FIXTUREPROPNAME), "prop_value": (..#FIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on wrong superclass")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "not_search_table_subclass", "render_strategy = not_search_table_subclass")
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "exists but is not a subclass", "summary mentions 'exists but is not a subclass' (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "Ens.SearchTableBase", "summary names Ens.SearchTableBase")
    Quit
}

/// AC-4 — time_window_hours filter narrows results.
Method TestTimeWindowFilter()
{
    Set tCtx = ..BuildCtx()
    Set tTwValue = ..#FIXTUREPROPVALUE _ "-tw"
    ; time_window_hours=24 → only the 1 fresh row.
    Set tArgs = {"search_table_class": (..#FIXTURECLASS), "prop_name": (..#FIXTUREPROPNAME), "prop_value": (tTwValue), "time_window_hours": 24}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("session_count"), 1, "session_count = 1 with 24h window")
    Do $$$AssertEquals(+tSc.%Get("time_window_hours"), 24, "time_window_hours echoed back as 24")

    ; Wider window → all 4.
    Set tArgs2 = {"search_table_class": (..#FIXTURECLASS), "prop_name": (..#FIXTUREPROPNAME), "prop_value": (tTwValue), "time_window_hours": 720}
    Set tResult2 = ""
    Do ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs2, .tResult2)
    Set tSc2 = tResult2.structuredContent
    Do $$$AssertEquals(+tSc2.%Get("session_count"), 4, "session_count = 4 with 720h window")
    Quit
}

/// AC-4 — limit clamp returns exactly N rows.
Method TestLimitClamp()
{
    Set tCtx = ..BuildCtx()
    Set tLcValue = ..#FIXTUREPROPVALUE _ "-lc"
    Set tArgs = {"search_table_class": (..#FIXTURECLASS), "prop_name": (..#FIXTUREPROPNAME), "prop_value": (tLcValue), "limit": 10}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("session_count"), 10, "session_count = 10 with limit=10")
    Set tSessions = tSc.%Get("sessions")
    Do $$$AssertEquals(tSessions.%Size(), 10, "sessions array has 10 entries")
    Quit
}

/// AC-4 — missing required arguments produce FR37 envelopes.
Method TestMissingRequiredArgReturnsError()
{
    Set tCtx = ..BuildCtx()

    ; Missing search_table_class.
    Set tArgs1 = {"prop_name": (..#FIXTUREPROPNAME), "prop_value": (..#FIXTUREPROPVALUE)}
    Set tRes1 = ""
    Do ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs1, .tRes1)
    Do $$$AssertEquals(+tRes1.%Get("isError"), 1, "isError set on missing search_table_class")
    Do $$$AssertTrue(tRes1.content.%Get(0).text [ "missing search_table_class", "error text mentions missing search_table_class")

    ; Missing prop_name.
    Set tArgs2 = {"search_table_class": (..#FIXTURECLASS), "prop_value": (..#FIXTUREPROPVALUE)}
    Set tRes2 = ""
    Do ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs2, .tRes2)
    Do $$$AssertEquals(+tRes2.%Get("isError"), 1, "isError set on missing prop_name")
    Do $$$AssertTrue(tRes2.content.%Get(0).text [ "missing prop_name", "error text mentions missing prop_name")

    ; Missing prop_value.
    Set tArgs3 = {"search_table_class": (..#FIXTURECLASS), "prop_name": (..#FIXTUREPROPNAME)}
    Set tRes3 = ""
    Do ##class(SessionAgent.Tool.Inspection.FindSessionsByBody).Invoke(tCtx, tArgs3, .tRes3)
    Do $$$AssertEquals(+tRes3.%Get("isError"), 1, "isError set on missing prop_value")
    Do $$$AssertTrue(tRes3.content.%Get(0).text [ "missing prop_value", "error text mentions missing prop_value")
    Quit
}

/// AC-5 registry discovery — tool surfaces with AC-3 schema.
Method TestRegistryListToolsIncludesFindSessionsByBody()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tCandidate) {
        If tCandidate.%Get("name") = "find_sessions_by_body" {
            Set tFound = 1
            Set tEntry = tCandidate
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'find_sessions_by_body'")

    If $IsObject(tEntry) {
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 3, "schema.required has 3 entries")
        Set tRequiredSet = ""
        Set tIterReq = tRequired.%GetIterator()
        While tIterReq.%GetNext(.tIdx, .tName) {
            Set tRequiredSet = tRequiredSet _ "|" _ tName
        }
        Do $$$AssertTrue(tRequiredSet [ "search_table_class", "schema.required includes search_table_class")
        Do $$$AssertTrue(tRequiredSet [ "prop_name", "schema.required includes prop_name")
        Do $$$AssertTrue(tRequiredSet [ "prop_value", "schema.required includes prop_value")
        Do $$$AssertEquals(+tSchema.%Get("additionalProperties"), 0, "schema.additionalProperties = false")
    }
    Quit
}

}
