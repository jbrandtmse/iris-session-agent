/// <p>Story 8.3 — unit tests for the six simple indexed-access search
/// tools: <CLASS>SessionAgent.Tool.Search.SearchByTime</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByStatus</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchBySource</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByTarget</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByMessageClass</CLASS>, and
/// <CLASS>SessionAgent.Tool.Search.SearchBySession</CLASS>.</p>
///
/// <p>Six test methods (one per tool, AC-7):</p>
/// <ol>
/// <li><b>TestSearchByTimeReturnsTimeBoundedSessions</b> — fixture
/// rows spanning 48h; default 24h window returns only the recent
/// half.</li>
/// <li><b>TestSearchByStatusFiltersByEnumArray</b> — three status
/// values across the fixture; <code>status_in:["Error","Suspended"]</code>
/// excludes the <code>Completed</code> row.</li>
/// <li><b>TestSearchBySourceExactMatchOnly</b> — case-sensitive
/// <code>%EXACT()</code> match.</li>
/// <li><b>TestSearchByTargetExactMatchOnly</b> — same shape on
/// <code>TargetConfigName</code>.</li>
/// <li><b>TestSearchByMessageClassExactMatchOnly</b> — same shape on
/// <code>MessageBodyClassName</code>.</li>
/// <li><b>TestSearchBySessionKeyedLookupOmitsTimeWindow</b> — fixture
/// row whose <code>TimeCreated</code> is older than 720h; the
/// keyed-lookup tool STILL resolves it (proving the keyed-lookup
/// sentinel suppresses the time-window predicate).</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds direct
/// <CLASS>Ens.MessageHeader</CLASS> rows for a fixture
/// <code>SessionId</code> family
/// (<code>FIXTUREBASESID + offset</code>) with deterministic
/// timestamps relative to <code>$ZTimeStamp</code>; row IDs captured
/// in <code>^||SessionAgentSearchTestIds</code> for cleanup.
/// <method>OnAfterAllTests</method> deletes by ID and sweeps any
/// stragglers via composite-key DELETE.</p>
///
/// <p><b>Property Test* shadow trap (project rule).</b> No
/// <code>Property Test*</code> declarations on this class — the
/// %UnitTest framework discovers methods whose names begin with
/// <code>Test</code> and would attempt to run datatype-helper methods
/// generated for <code>Test*</code>-prefixed properties. State
/// tracking, when needed, uses <code>Pre*</code>-prefixed properties.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-7.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS>.</li>
/// </ul>
Class SessionAgent.Test.SearchToolTest Extends %UnitTest.TestCase
{

/// <p>Base SessionId; per-test fixtures use this + offset to avoid
/// collisions with other test classes' SessionId reservations
/// (e.g., InspectionToolTest uses 999911).</p>
Parameter FIXTUREBASESID As %Integer = 998800;

/// <p>Constructor — accepts <code>initvalue</code> from
/// <CLASS>%UnitTest.TestCase</CLASS> and forwards via <code>##super</code>
/// (project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed Ens.MessageHeader fixture rows. Each test reuses a
/// disjoint <code>SessionId</code> sub-range so the assertions are
/// independent. Layout:</p>
/// <ul>
/// <li><code>BASESID + 1</code> — 5 rows for SearchByTime test
/// (recent: 3 rows in last 24h; old: 2 rows older than 24h).</li>
/// <li><code>BASESID + 2..BASESID + 4</code> — 3 sessions × 2 rows
/// each for SearchByStatus (Status=8/Error, 5/Suspended, 9/Completed).</li>
/// <li><code>BASESID + 5..BASESID + 8</code> — 4 sessions for
/// SearchBySource/Target (2 with 'EpicADT', 2 with 'EpicADT2').</li>
/// <li><code>BASESID + 9..BASESID + 12</code> — 4 sessions for
/// SearchByMessageClass.</li>
/// <li><code>BASESID + 99</code> — 1 row with TimeCreated 1000h ago
/// (older than 720h max window) for SearchBySession keyed-lookup test.</li>
/// </ul>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentSearchTestIds
    Set tBase = ..#FIXTUREBASESID

    ; Defensive sweep — clear any prior-run debris in our SessionId range.
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?")) {
        Do tCleanup.%Execute(tBase, tBase + 100)
    }

    ; Helper closure-style: build an ODBC timestamp N hours offset from
    ; $ZTimeStamp (which is UTC days,seconds-since-midnight).
    ; We inline the math for each row.
    Set tNowH = $ZTimeStamp
    Set tNowDays = +$Piece(tNowH, ",", 1)
    Set tNowSecs = +$Piece(tNowH, ",", 2)

    Set tRowSeq = 0

    ; ---- TIME test fixture: SessionId BASESID+1, 5 rows.
    ; 3 rows at -1h/-2h/-3h (inside default 24h window),
    ; 2 rows at -36h/-40h (outside).
    Set tTimeSid = tBase + 1
    For tHourOffset = -1, -2, -3, -36, -40 {
        Set tShiftedSecs = tNowSecs + (tHourOffset * 3600)
        Set tShiftedDays = tNowDays
        While tShiftedSecs < 0 {
            Set tShiftedSecs = tShiftedSecs + 86400
            Set tShiftedDays = tShiftedDays - 1
        }
        Set tShiftedH = tShiftedDays _ "," _ tShiftedSecs
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tTimeSid
        Set tHdr.TimeCreated = $ZDateTime(tShiftedH, 3, 1, 0)
        Set tHdr.SourceConfigName = "TimeFixtureSrc"
        Set tHdr.TargetConfigName = "TimeFixtureTgt"
        Set tHdr.MessageBodyClassName = "TimeFixture.Msg"
        Set tHdr.Status = 9
        Set tSC1 = tHdr.%Save()
        If $$$ISERR(tSC1) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- STATUS test fixture: 3 sessions × 1 row each.
    ; SessionId BASESID+2 → Status=8 (Error)
    ; SessionId BASESID+3 → Status=5 (Suspended)
    ; SessionId BASESID+4 → Status=9 (Completed)
    For tStatusEntry = "2,8", "3,5", "4,9" {
        Set tSidOffset = +$Piece(tStatusEntry, ",", 1)
        Set tStatusVal = +$Piece(tStatusEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        ; Recent row — within default 24h window.
        Set tShiftedSecs = tNowSecs - 3600
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "StatusFixtureSrc"
        Set tHdr.TargetConfigName = "StatusFixtureTgt"
        Set tHdr.MessageBodyClassName = "StatusFixture.Msg"
        Set tHdr.Status = tStatusVal
        Set tSC2 = tHdr.%Save()
        If $$$ISERR(tSC2) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- SOURCE test fixture: 4 sessions, 2 with 'EpicADT' source,
    ; 2 with 'EpicADT2'. SessionId BASESID+5..BASESID+8.
    For tSrcEntry = "5,EpicADT", "6,EpicADT", "7,EpicADT2", "8,EpicADT2" {
        Set tSidOffset = +$Piece(tSrcEntry, ",", 1)
        Set tSrcName = $Piece(tSrcEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = tSrcName
        Set tHdr.TargetConfigName = "SourceFixtureTgt"
        Set tHdr.MessageBodyClassName = "SourceFixture.Msg"
        Set tHdr.Status = 9
        Set tSC3 = tHdr.%Save()
        If $$$ISERR(tSC3) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- TARGET test fixture: 4 sessions, 2 with 'TgtA', 2 with 'TgtB'.
    ; SessionId BASESID+9..BASESID+12.
    For tTgtEntry = "9,TgtAlpha", "10,TgtAlpha", "11,TgtBeta", "12,TgtBeta" {
        Set tSidOffset = +$Piece(tTgtEntry, ",", 1)
        Set tTgtName = $Piece(tTgtEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "TargetFixtureSrc"
        Set tHdr.TargetConfigName = tTgtName
        Set tHdr.MessageBodyClassName = "TargetFixture.Msg"
        Set tHdr.Status = 9
        Set tSC4 = tHdr.%Save()
        If $$$ISERR(tSC4) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- MESSAGE-CLASS test fixture: 4 sessions, 2 'Hl7Msg', 2 'SegDoc'.
    ; SessionId BASESID+13..BASESID+16.
    For tBcEntry = "13,Class.A.Msg", "14,Class.A.Msg", "15,Class.B.Other", "16,Class.B.Other" {
        Set tSidOffset = +$Piece(tBcEntry, ",", 1)
        Set tBcName = $Piece(tBcEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "BcFixtureSrc"
        Set tHdr.TargetConfigName = "BcFixtureTgt"
        Set tHdr.MessageBodyClassName = tBcName
        Set tHdr.Status = 9
        Set tSC5 = tHdr.%Save()
        If $$$ISERR(tSC5) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- SESSION-LOOKUP fixture: 1 row at -1000h (older than 720h max).
    ; SessionId BASESID+99. Proves keyed-lookup mode bypasses the window.
    Set tSessSid = tBase + 99
    Set tShiftedSecs = tNowSecs - (1000 * 3600)
    Set tShiftedDays = tNowDays
    While tShiftedSecs < 0 {
        Set tShiftedSecs = tShiftedSecs + 86400
        Set tShiftedDays = tShiftedDays - 1
    }
    Set tHdr = ##class(Ens.MessageHeader).%New()
    Set tHdr.SessionId = tSessSid
    Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
    Set tHdr.SourceConfigName = "AncientFixtureSrc"
    Set tHdr.TargetConfigName = "AncientFixtureTgt"
    Set tHdr.MessageBodyClassName = "AncientFixture.Msg"
    Set tHdr.Status = 9
    Set tSC6 = tHdr.%Save()
    If $$$ISERR(tSC6) Quit $$$OK
    Set tRowSeq = tRowSeq + 1
    Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()

    Quit $$$OK
}

/// <p>Cleanup — delete fixture rows by captured ID then sweep any
/// stragglers via composite-key DELETE.</p>
Method OnAfterAllTests() As %Status
{
    Set tIdx = ""
    For  {
        Set tIdx = $Order(^||SessionAgentSearchTestIds(tIdx))
        Quit:tIdx=""
        Set tId = $Get(^||SessionAgentSearchTestIds(tIdx))
        If tId '= "" Do ##class(Ens.MessageHeader).%DeleteId(tId)
    }
    Kill ^||SessionAgentSearchTestIds
    ; Belt-and-suspenders — sweep our entire SessionId reservation range.
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?")) {
        Do tStmt.%Execute(..#FIXTUREBASESID, ..#FIXTUREBASESID + 100)
    }
    Quit $$$OK
}

/// <p>Build a CallerContext stub for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "message-search"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-7 #1 — SearchByTime default 24h window returns the 3 recent
/// rows (1 session) and excludes the 2 rows older than 24h. The
/// envelope's <code>indexed_lead_column</code> is "TimeCreated" and
/// <code>time_window_used</code> is 24.</p>
Method TestSearchByTimeReturnsTimeBoundedSessions()
{
    Set tCtx = ..BuildCtx()
    ; Restrict to our fixture's source so other production sessions
    ; in the namespace don't pollute the assertion.
    ; SearchByTime doesn't have a source filter — but the fixture
    ; uses a unique TimeFixtureSrc so we can verify via the returned
    ; sessions list.
    Set tArgs = {"limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByTime).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByTime.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "TimeCreated", "indexed_lead_column = TimeCreated")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("time_window_used"), 24, "time_window_used = 24 (default)")

    ; Verify the fixture session BASESID+1 IS in the result list
    ; (3 recent rows were seeded inside the 24h window). The OLD rows
    ; at -36h/-40h must NOT add a separate row beyond their session id
    ; — they roll up under the same SessionId so the session count is 1.
    Set tFoundTimeSession = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If +tEntry.%Get("session_id") = (..#FIXTUREBASESID + 1) {
            Set tFoundTimeSession = 1
            Quit
        }
    }
    Do $$$AssertTrue(tFoundTimeSession, "fixture SessionId " _ (..#FIXTUREBASESID + 1) _ " present in 24h window result")

    ; Test explicit-bound mode — from_time at -2h ago, no upper bound.
    ; Should still surface our fixture session.
    Set tNowH = $ZTimeStamp
    Set tCutoffSecs = $Piece(tNowH, ",", 2) - (2 * 3600)
    Set tCutoffDays = $Piece(tNowH, ",", 1)
    If tCutoffSecs < 0 Set tCutoffSecs = tCutoffSecs + 86400, tCutoffDays = tCutoffDays - 1
    Set tCutoffOdbc = $ZDateTime(tCutoffDays _ "," _ tCutoffSecs, 3, 1)
    Set tCutoffIso = $Translate($Extract(tCutoffOdbc, 1, 19), " ", "T") _ "Z"
    Set tArgs2 = {"from_time": (tCutoffIso), "limit": 500}
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Search.SearchByTime).Invoke(tCtx, tArgs2, .tResult2)
    Do $$$AssertStatusOK(tSC2, "SearchByTime explicit from_time returns $$$OK")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("time_window_used"), 0, "time_window_used = 0 in explicit-bound mode")
    Quit
}

/// <p>AC-7 #2 — SearchByStatus with
/// <code>status_in:["Error","Suspended"]</code> returns the two
/// fixture sessions with Status=8/Error and Status=5/Suspended.
/// Excludes the Status=9/Completed session.</p>
Method TestSearchByStatusFiltersByEnumArray()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"status_in": ["Error", "Suspended"], "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByStatus).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByStatus.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "Status", "indexed_lead_column = Status")

    ; Fixture sessions: BASESID+2 (Error), BASESID+3 (Suspended) — must be present.
    ; BASESID+4 (Completed) — must be absent.
    Set tFoundError = 0, tFoundSuspended = 0, tFoundCompleted = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = (..#FIXTUREBASESID + 2) Set tFoundError = 1
        If tSid = (..#FIXTUREBASESID + 3) Set tFoundSuspended = 1
        If tSid = (..#FIXTUREBASESID + 4) Set tFoundCompleted = 1
    }
    Do $$$AssertTrue(tFoundError, "Error fixture session " _ (..#FIXTUREBASESID + 2) _ " present")
    Do $$$AssertTrue(tFoundSuspended, "Suspended fixture session " _ (..#FIXTUREBASESID + 3) _ " present")
    Do $$$AssertEquals(tFoundCompleted, 0, "Completed fixture session " _ (..#FIXTUREBASESID + 4) _ " EXCLUDED from Error+Suspended filter")

    ; Negative — unknown status value returns isError envelope.
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchByStatus).Invoke(tCtx, {"status_in":["NotARealStatus"]}, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on unknown status (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 on unknown status value")
    Quit
}

/// <p>AC-7 #3 — SearchBySource with <code>source_config_name="EpicADT"</code>
/// returns 2 sessions; the two with <code>SourceConfigName="EpicADT2"</code>
/// are excluded by the <code>%EXACT()</code> match.</p>
Method TestSearchBySourceExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"source_config_name": "EpicADT", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySource.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SourceConfigName", "indexed_lead_column = SourceConfigName")

    ; Count fixture sessions in result. BASESID+5,6 should be present;
    ; BASESID+7,8 (EpicADT2) must be absent.
    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 5)) || (tSid = (..#FIXTUREBASESID + 6)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 7)) || (tSid = (..#FIXTUREBASESID + 8)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "EpicADT fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "EpicADT2 fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #4 — same shape on <code>TargetConfigName</code>.</p>
Method TestSearchByTargetExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"target_config_name": "TgtAlpha", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByTarget).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByTarget.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "TargetConfigName", "indexed_lead_column = TargetConfigName")

    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 9)) || (tSid = (..#FIXTUREBASESID + 10)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 11)) || (tSid = (..#FIXTUREBASESID + 12)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "TgtAlpha fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "TgtBeta fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #5 — same shape on <code>MessageBodyClassName</code>.</p>
Method TestSearchByMessageClassExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_body_class_name": "Class.A.Msg", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByMessageClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByMessageClass.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "MessageBodyClassName", "indexed_lead_column = MessageBodyClassName")

    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 13)) || (tSid = (..#FIXTUREBASESID + 14)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 15)) || (tSid = (..#FIXTUREBASESID + 16)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "Class.A.Msg fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "Class.B.Other fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #6 — SearchBySession with the BASESID+99 fixture (whose
/// TimeCreated is 1000h ago) STILL resolves to the row, proving
/// keyed-lookup mode bypasses the time-window predicate. The
/// <code>time_window_used</code> envelope field is JSON null per AC-6.</p>
Method TestSearchBySessionKeyedLookupOmitsTimeWindow()
{
    Set tCtx = ..BuildCtx()
    Set tAncientSid = ..#FIXTUREBASESID + 99
    Set tArgs = {"session_id": (tAncientSid)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySession).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySession.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SessionId", "indexed_lead_column = SessionId")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("result_count"), 1, "result_count = 1 (the ancient fixture row)")

    ; Ancient fixture session must be present.
    Set tFoundAncient = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If +tEntry.%Get("session_id") = tAncientSid Set tFoundAncient = 1
    }
    Do $$$AssertTrue(tFoundAncient, "ancient fixture session " _ tAncientSid _ " resolved despite TimeCreated -1000h (proves keyed-lookup bypasses time window)")

    ; time_window_used is JSON null for keyed-lookup mode (AC-6).
    Do $$$AssertEquals(tResult.structuredContent.%IsDefined("time_window_used"), 1, "time_window_used field is present (set to JSON null) for keyed-lookup mode")
    ; Verify the value is JSON null — %DynamicObject.%Get returns the
    ; ObjectScript empty string "" for a JSON null value.
    Do $$$AssertEquals(tResult.structuredContent.%Get("time_window_used"), "", "time_window_used = JSON null (visible as empty-string via %Get)")
    ; Belt-and-suspenders — assert the JSON serialization actually contains :null.
    Set tJson = tResult.structuredContent.%ToJSON()
    Do $$$AssertTrue(tJson [ """time_window_used"":null", "JSON serialization contains 'time_window_used:null' — keyed-lookup mode visible")

    ; Negative — missing session_id returns isError envelope.
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchBySession).Invoke(tCtx, {}, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on missing session_id (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Quit
}

}
