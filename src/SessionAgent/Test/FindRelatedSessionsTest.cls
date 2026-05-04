/// <p>Unit tests for the Story 4.5 inspection tool —
/// <CLASS>SessionAgent.Tool.Inspection.FindRelatedSessions</CLASS>. Five
/// Test* methods cover Story 4.5 AC-1 through AC-4:</p>
///
/// <p><b>FindRelatedSessions (4):</b></p>
/// <ol>
/// <li><b>TestRelatedSessionsFindsTwoOthers</b> — fixture: 3 sessions
/// (FIXTURESESSIONIDA / B / C) sharing super-session key
/// <code>"TEST-SUPER-SHARED"</code>. Tool invoked for session A; expects
/// <code>related_count=2</code> with both B and C present in
/// <code>related_sessions</code> array; <code>render_strategy</code> =
/// <code>"related_sessions"</code>; <code>super_session_key</code>
/// matches the fixture key. Each related entry has populated
/// <code>time_created</code> (20-char ISO-Z), <code>source_config_name</code>,
/// <code>target_config_name</code>, and <code>message_count &gt;= 1</code>.</li>
/// <li><b>TestNoSuperSessionReturnsEmptyArray</b> — fixture session
/// FIXTURESESSIONIDD with NO <code>Ens.SuperSessionIndex</code> row.
/// Asserts <code>render_strategy="no_super_session"</code>,
/// <code>related_sessions=[]</code>, <code>related_count=0</code>, and
/// NO <code>isError:1</code> flag. Summary text mentions
/// "stands alone (NOT an error)".</li>
/// <li><b>TestEmptySuperSessionStringReturnsEmpty</b> — Per Task 0, the
/// <code>SuperSession</code> column is declared <code>[Required]</code> +
/// <code>NOT NULL</code> in the schema; we cannot directly insert
/// <code>SuperSession=""</code>. Instead we reproduce the equivalent
/// shape: a session whose lookup query returns the empty result set
/// (i.e., MessageHeader rows exist but no matching SuperSessionIndex
/// row) using FIXTURESESSIONIDE — a header row WITHOUT a corresponding
/// SuperSessionIndex row. The Step 1 lookup query
/// <code>WHERE mh.SessionId = ?</code> returns no rows, the empty-key
/// short-circuit fires, and the envelope is the same shape the
/// no_super_session test asserts. This documents the
/// "<code>SuperSession=""</code>" guard in
/// <CLASS>SessionAgent.Tool.Inspection.FindRelatedSessions</CLASS> as
/// defense-in-depth even though the column-level invariant prevents the
/// row from existing in practice.</li>
/// <li><b>TestMissingSessionIdReturnsError</b> — FR37 envelope
/// (empty input → <code>isError:1</code> + "missing session_id").</li>
/// </ol>
///
/// <p><b>Registry (1):</b></p>
/// <ol>
/// <li><b>TestRegistryListToolsIncludesFindRelatedSessions</b> —
/// <method>SessionAgent.Tool.Registry.ListTools</method> output contains
/// <code>find_related_sessions</code> with the AC-2 schema (one required
/// property: <code>session_id</code>; <code>additionalProperties</code>
/// false).</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds rows into
/// <CLASS>Ens.MessageHeader</CLASS> and <CLASS>Ens.SuperSessionIndex</CLASS>
/// via parameterized SQL INSERT — the latter requires the FK to a real
/// MessageHeader row (per <code>irislib/Ens/SuperSessionIndex.cls</code>
/// <code>ForeignKey ... References Ens.MessageHeader [OnDelete=cascade]</code>).
/// Captured row IDs in process-private global
/// <code>^||SessionAgentTest45HeaderIds</code> for guaranteed cleanup.
/// <method>OnAfterAllTests</method> deletes by SessionId — the FK cascade
/// removes SuperSessionIndex rows automatically.</p>
Class SessionAgent.Test.FindRelatedSessionsTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONIDA As %Integer = 999951;

Parameter FIXTURESESSIONIDB As %Integer = 999952;

Parameter FIXTURESESSIONIDC As %Integer = 999953;

Parameter FIXTURESESSIONIDD As %Integer = 999954;

Parameter FIXTURESESSIONIDE As %Integer = 999955;

Parameter FIXTURESUPERSESSION As %String = "TEST-SUPER-SHARED";

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed fixture rows. Plan:</p>
/// <ul>
/// <li>3 sessions (A, B, C), each gets one <code>Ens.MessageHeader</code>
/// row with <code>SuperSession="TEST-SUPER-SHARED"</code>, plus a
/// matching <code>Ens.SuperSessionIndex</code> row referencing that
/// header. Distinct <code>SourceConfigName</code> /
/// <code>TargetConfigName</code> per session so the enrichment columns
/// can be asserted.</li>
/// <li>Session D: NO <code>Ens.SuperSessionIndex</code> rows at all
/// (and no header rows either — the lookup returns empty).</li>
/// <li>Session E: ONE <code>Ens.MessageHeader</code> row with
/// <code>SuperSession=""</code>, no SuperSessionIndex row. Step 1
/// lookup returns empty → no_super_session envelope.</li>
/// </ul>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest45HeaderIds

    ; Defensive sweep — cascade removes SuperSessionIndex rows.
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId IN (?, ?, ?, ?, ?)")) {
        Do tCleanup.%Execute(..#FIXTURESESSIONIDA, ..#FIXTURESESSIONIDB, ..#FIXTURESESSIONIDC, ..#FIXTURESESSIONIDD, ..#FIXTURESESSIONIDE)
    }

    Set tInsertHdr = ##class(%SQL.Statement).%New()
    Set tSC = tInsertHdr.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, SuperSession, SourceConfigName, TargetConfigName, TimeCreated, Type, Priority, Status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    If $$$ISERR(tSC) Quit tSC
    Set tInsertSsi = ##class(%SQL.Statement).%New()
    Set tSC2 = tInsertSsi.%Prepare("INSERT INTO Ens.SuperSessionIndex (MessageHeader, SuperSession) VALUES (?, ?)")
    If $$$ISERR(tSC2) Quit tSC2

    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)
    Set tRows = $ListBuild( $ListBuild(..#FIXTURESESSIONIDA, ..#FIXTURESUPERSESSION, "AlphaIn", "AlphaOut", 1), $ListBuild(..#FIXTURESESSIONIDB, ..#FIXTURESUPERSESSION, "BravoIn", "BravoOut", 1), $ListBuild(..#FIXTURESESSIONIDC, ..#FIXTURESUPERSESSION, "CharlieIn", "CharlieOut", 1), $ListBuild(..#FIXTURESESSIONIDE, "", "EchoIn", "EchoOut", 0))

    Set tCount = $ListLength(tRows)
    For tIdx = 1:1:tCount {
        Set tRow = $ListGet(tRows, tIdx)
        Set tSession = $ListGet(tRow, 1)
        Set tSuper = $ListGet(tRow, 2)
        Set tSrc = $ListGet(tRow, 3)
        Set tTgt = $ListGet(tRow, 4)
        Set tWantSsi = $ListGet(tRow, 5)
        Set tShiftedSecs = tBaseSecs + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tTime = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tRsHdr = tInsertHdr.%Execute(tSession, tSuper, tSrc, tTgt, tTime, 1, 1, 1)
        If tRsHdr.%SQLCODE < 0 Quit
        Set tHdrId = tRsHdr.%ROWID
        Set ^||SessionAgentTest45HeaderIds(tIdx) = tHdrId
        ; Insert matching SuperSessionIndex row only when fixture row asks
        ; for it (i.e., not for session E which simulates missing-index).
        If tWantSsi {
            Set tRsSsi = tInsertSsi.%Execute(tHdrId, tSuper)
            If tRsSsi.%SQLCODE < 0 Quit
        }
    }

    ; Add a SECOND header row to session A to verify message_count > 1
    ; works (and that the enrichment query picks the earliest by
    ; TimeCreated ASC).
    Set tShiftedSecsA2 = tBaseSecs + 100
    Set tShiftedHorologA2 = $Select(tShiftedSecsA2 >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecsA2 - 86400), 1: tBaseDate _ "," _ tShiftedSecsA2)
    Set tTimeA2 = $ZDateTime(tShiftedHorologA2, 3, 1, 0)
    Set tRsHdrA2 = tInsertHdr.%Execute(..#FIXTURESESSIONIDA, ..#FIXTURESUPERSESSION, "AlphaIn", "AlphaOut", tTimeA2, 1, 1, 1)
    If tRsHdrA2.%SQLCODE >= 0 {
        Set ^||SessionAgentTest45HeaderIds("A2") = tRsHdrA2.%ROWID
    }

    Quit $$$OK
}

/// <p>Cleanup — delete fixture MessageHeader rows by SessionId. The FK
/// cascade on <CLASS>Ens.SuperSessionIndex</CLASS> removes related index
/// rows automatically.</p>
Method OnAfterAllTests() As %Status
{
    Set tDel = ##class(%SQL.Statement).%New()
    If $$$ISOK(tDel.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId IN (?, ?, ?, ?, ?)")) {
        Do tDel.%Execute(..#FIXTURESESSIONIDA, ..#FIXTURESESSIONIDB, ..#FIXTURESESSIONIDC, ..#FIXTURESESSIONIDD, ..#FIXTURESESSIONIDE)
    }
    Kill ^||SessionAgentTest45HeaderIds
    Quit $$$OK
}

/// <p>Build a CallerContext with sane defaults for tool invocation.</p>
ClassMethod BuildCtx(pSessionId As %Integer) As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = pSessionId
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-3 happy path — query for sibling sessions of A; expect 2
/// (B + C). Verify super-session key + enrichment columns + ISO-Z
/// timestamp shape.</p>
Method TestRelatedSessionsFindsTwoOthers()
{
    Set tCtx = ..BuildCtx(..#FIXTURESESSIONIDA)
    Set tArgs = {"session_id": (..#FIXTURESESSIONIDA)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindRelatedSessions).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "FindRelatedSessions.Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "related_sessions", "render_strategy = related_sessions")
    Do $$$AssertEquals(tSc.%Get("super_session_key"), ..#FIXTURESUPERSESSION, "super_session_key matches fixture")
    Do $$$AssertEquals(+tSc.%Get("related_count"), 2, "related_count = 2 (B + C)")
    Set tRelated = tSc.%Get("related_sessions")
    Do $$$AssertEquals(tRelated.%Size(), 2, "related_sessions array has 2 entries")

    ; Collect related session ids into a flat list for membership assertion.
    Set tFoundB = 0
    Set tFoundC = 0
    Set tBSeen = 0
    Set tCSeen = 0
    Set tIter = tRelated.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = ..#FIXTURESESSIONIDB {
            Set tFoundB = 1
            Set tBSeen = tEntry
        }
        If tSid = ..#FIXTURESESSIONIDC {
            Set tFoundC = 1
            Set tCSeen = tEntry
        }
        ; Every entry has populated enrichment columns.
        Set tTC = tEntry.%Get("time_created")
        Do $$$AssertEquals($Length(tTC), 20, "time_created is 20 chars (got: " _ tTC _ ")")
        Do $$$AssertEquals($Extract(tTC, 11), "T", "time_created char 11 = 'T'")
        Do $$$AssertEquals($Extract(tTC, 20), "Z", "time_created char 20 = 'Z'")
        Do $$$AssertTrue(+tEntry.%Get("message_count") >= 1, "message_count >= 1 for sibling")
    }
    Do $$$AssertTrue(tFoundB, "session B is in related_sessions")
    Do $$$AssertTrue(tFoundC, "session C is in related_sessions")

    ; Spot-check source/target names match fixture.
    If $IsObject(tBSeen) {
        Do $$$AssertEquals(tBSeen.%Get("source_config_name"), "BravoIn", "session B source_config_name = BravoIn")
        Do $$$AssertEquals(tBSeen.%Get("target_config_name"), "BravoOut", "session B target_config_name = BravoOut")
    }
    Quit
}

/// <p>AC-3 no-super-session path — session D has no header rows at all.
/// Step 1 lookup returns empty; envelope is no_super_session, NOT
/// isError. Summary text wording matches AC-3.</p>
Method TestNoSuperSessionReturnsEmptyArray()
{
    Set tCtx = ..BuildCtx(..#FIXTURESESSIONIDD)
    Set tArgs = {"session_id": (..#FIXTURESESSIONIDD)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindRelatedSessions).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "FindRelatedSessions.Invoke OK")
    ; %DynamicObject %Get returns "" (empty string) for missing keys; +"" = 0.
    ; Don't wrap in $Get — that's array-only and triggers <INVALID CLASS>.
    Set tIsError = +tResult.%Get("isError")
    Do $$$AssertEquals(tIsError, 0, "isError NOT set (no_super_session is normal, not an error)")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "no_super_session", "render_strategy = no_super_session")
    Do $$$AssertEquals(tSc.%Get("super_session_key"), "", "super_session_key = empty string")
    Do $$$AssertEquals(+tSc.%Get("related_count"), 0, "related_count = 0")
    Set tRelated = tSc.%Get("related_sessions")
    Do $$$AssertEquals(tRelated.%Size(), 0, "related_sessions = []")
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "stands alone", "summary text mentions 'stands alone' (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "NOT an error", "summary text reassures 'NOT an error' (got: " _ tSummary _ ")")
    Quit
}

/// <p>AC-3 empty-super-session path — session E has a header row but no
/// SuperSessionIndex row. The Step 1 JOIN returns empty (no SSI row to
/// JOIN to), the empty-key short-circuit fires, envelope is the same
/// shape as the no_super_session test. Documents the
/// <code>SuperSession=""</code> defense-in-depth guard in the tool.</p>
Method TestEmptySuperSessionStringReturnsEmpty()
{
    Set tCtx = ..BuildCtx(..#FIXTURESESSIONIDE)
    Set tArgs = {"session_id": (..#FIXTURESESSIONIDE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindRelatedSessions).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "FindRelatedSessions.Invoke OK")
    Set tIsError = +tResult.%Get("isError")
    Do $$$AssertEquals(tIsError, 0, "isError NOT set for empty-super-session case")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "no_super_session", "render_strategy = no_super_session for empty-key case")
    Do $$$AssertEquals(tSc.%Get("super_session_key"), "", "super_session_key = empty string")
    Do $$$AssertEquals(+tSc.%Get("related_count"), 0, "related_count = 0")
    Quit
}

/// <p>AC-3 validation path — empty <code>session_id</code> → FR37
/// envelope.</p>
Method TestMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx("")
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.FindRelatedSessions).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>AC-4 registry discovery — <code>find_related_sessions</code>
/// appears in <method>Tool.Registry.ListTools</method> with the AC-2
/// schema (one required property: <code>session_id</code>;
/// <code>additionalProperties</code> false).</p>
Method TestRegistryListToolsIncludesFindRelatedSessions()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tCandidate) {
        If tCandidate.%Get("name") = "find_related_sessions" {
            Set tFound = 1
            Set tEntry = tCandidate
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'find_related_sessions'")

    If $IsObject(tEntry) {
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "schema.required has one entry")
        Do $$$AssertEquals(tRequired.%Get(0), "session_id", "schema.required[0] = 'session_id'")
        Do $$$AssertEquals(+tSchema.%Get("additionalProperties"), 0, "schema.additionalProperties = false")
    }
    Quit
}

}
