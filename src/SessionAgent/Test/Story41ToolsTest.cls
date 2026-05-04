/// <p>Unit tests for the Story 4.1 inspection tools —
/// <CLASS>SessionAgent.Tool.Inspection.EventLog</CLASS> and
/// <CLASS>SessionAgent.Tool.Inspection.RuleLog</CLASS>. Twelve Test*
/// methods cover Story 4.1 AC-1 through AC-7 plus the F-1 review fix
/// (severity_counts true-distribution lock):</p>
///
/// <p><b>EventLog (7):</b></p>
/// <ol>
/// <li><b>TestEventLogReturnsAllRowsNoFilter</b> — fixture session with
/// 6 event-log rows (all severity tiers), expects rows for the 4 named
/// tiers (assert/error/warning/info) returned; trace excluded.</li>
/// <li><b>TestEventLogMinSeverityErrorFiltersToErrorAndAssert</b> —
/// fixture with mixed severities, expects only error + assert rows
/// when <code>min_severity='error'</code>.</li>
/// <li><b>TestEventLogMessageIdFilter</b> — fixture with rows for two
/// distinct message_ids, expects only the named one's rows.</li>
/// <li><b>TestEventLogMissingSessionIdReturnsError</b> — confirms FR37
/// envelope shape.</li>
/// <li><b>TestEventLogMinSeverityCaseInsensitive</b> —
/// <code>min_severity='ERROR'</code>, <code>'Error'</code>,
/// <code>'error'</code> all behave identically (Story 3.0 AC-3 pattern).</li>
/// <li><b>TestEventLogTimestampIsoFormat</b> — picks one row, asserts
/// <code>time_logged</code> length=20, ends Z, T at position 11.</li>
/// <li><b>TestEventLogSeverityCountsReflectFullPredicateNotLimit</b> —
/// review F-1 lock: with <code>limit=1</code>, <code>events</code> array
/// is 1 row but <code>severity_counts</code> reflects all 5 fixture
/// rows under the default Type≤4 cap (info=2, warning=1, error=1,
/// assert=1). Catches a regression to per-page severity counting.</li>
/// </ol>
///
/// <p><b>RuleLog (4):</b></p>
/// <ol>
/// <li><b>TestRuleLogReturnsAllDecisionsChronological</b> — fixture
/// with K=3 decisions, expects <code>decision_count=K</code> in
/// <code>TimeExecuted ASC</code> order.</li>
/// <li><b>TestRuleLogRuleClassFilter</b> — fixture with two rule
/// classes, expects only the named one's rows.</li>
/// <li><b>TestRuleLogMissingSessionIdReturnsError</b> — FR37 envelope.</li>
/// <li><b>TestRuleLogTimestampIsoFormat</b> — same shape for
/// <code>time_executed</code>.</li>
/// </ol>
///
/// <p><b>Registry (1):</b></p>
/// <ol>
/// <li><b>TestRegistryListToolsIncludesEventLogAndRuleLog</b> —
/// <method>SessionAgent.Tool.Registry.ListTools</method> output
/// contains both new tool names with the correct schemas.</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds
/// <CLASS>Ens.Util.Log</CLASS> rows for <code>SessionId=999941</code>
/// (one of each severity tier 1..5 — assert, error, warning, info,
/// trace — plus a duplicate info for two distinct message_ids), and
/// <CLASS>Ens.Rule.Log</CLASS> rows (3 decisions across 2 rule
/// classes). All inserted via parameterized SQL because both classes'
/// <code>Log()</code> classmethods are <code>[Internal]</code> and
/// derive <code>SessionId</code>/<code>MessageId</code> from
/// <code>$$$JobSessionId</code> macros which are not set in the test
/// process. Captured row IDs in process-private globals
/// <code>^||SessionAgentTest41EventIds</code> +
/// <code>^||SessionAgentTest41RuleIds</code> for guaranteed cleanup.
/// <method>OnAfterAllTests</method> deletes by ID + sweeps any stragglers.</p>
Class SessionAgent.Test.Story41ToolsTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONID As %Integer = 999941;

Parameter FIXTUREMESSAGEIDA As %Integer = 999941001;

Parameter FIXTUREMESSAGEIDB As %Integer = 999941002;

Parameter FIXTURERULENAMEA As %String = "SessionAgent.Test.Story41.RuleA";

Parameter FIXTURERULENAMEB As %String = "SessionAgent.Test.Story41.RuleB";

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed fixture rows in <CLASS>Ens.Util.Log</CLASS> +
/// <CLASS>Ens.Rule.Log</CLASS>. Uses parameterized SQL INSERT — the
/// classmethod entry points are <code>[Internal]</code> and derive
/// SessionId/MessageId from process macros that are not set in test
/// jobs. Captures row IDs in process-private globals for cleanup.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest41EventIds
    Kill ^||SessionAgentTest41RuleIds
    Set tSession = ..#FIXTURESESSIONID

    ; Defensive sweep — if a prior run died before cleanup we'd otherwise
    ; double-seed.
    Set tCleanupE = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanupE.%Prepare("DELETE FROM Ens_Util.Log WHERE SessionId = ?")) {
        Do tCleanupE.%Execute(tSession)
    }
    Set tCleanupR = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanupR.%Prepare("DELETE FROM Ens_Rule.Log WHERE SessionId = ?")) {
        Do tCleanupR.%Execute(tSession)
    }

    ; --- Ens.Util.Log fixture rows.
    ; Row plan (Type integers per irislib/Ens/DataType/LogType.cls
    ; VALUELIST = ",1,2,3,4,5,6" ; Assert,Error,Warning,Info,Trace,Alert):
    ;   1: Type=4 (info), MessageId=A, "info A"
    ;   2: Type=4 (info), MessageId=B, "info B"  -- distinct msg id
    ;   3: Type=3 (warning), MessageId=A
    ;   4: Type=2 (error), MessageId=A
    ;   5: Type=1 (assert), MessageId=A
    ;   6: Type=5 (trace), MessageId=A   -- excluded from default tier set
    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)
    Set tInsertE = ##class(%SQL.Statement).%New()
    Set tSC = tInsertE.%Prepare("INSERT INTO Ens_Util.Log (SessionId, MessageId, Type, ConfigName, SourceClass, SourceMethod, Text, TimeLogged, Job, StatusValue) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
    If $$$ISERR(tSC) Quit tSC

    Set tRows = $ListBuild( $ListBuild(4, ..#FIXTUREMESSAGEIDA, "info A row"), $ListBuild(4, ..#FIXTUREMESSAGEIDB, "info B row"), $ListBuild(3, ..#FIXTUREMESSAGEIDA, "warning A row"), $ListBuild(2, ..#FIXTUREMESSAGEIDA, "error A row"), $ListBuild(1, ..#FIXTUREMESSAGEIDA, "assert A row"), $ListBuild(5, ..#FIXTUREMESSAGEIDA, "trace A row"))

    Set tCount = $ListLength(tRows)
    For tIdx = 1:1:tCount {
        Set tRow = $ListGet(tRows, tIdx)
        Set tType = $ListGet(tRow, 1)
        Set tMsgId = $ListGet(tRow, 2)
        Set tText = $ListGet(tRow, 3)
        Set tShiftedSecs = tBaseSecs + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tTime = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tRs = tInsertE.%Execute(tSession, tMsgId, tType, "TestConfig", "Test.SrcClass", "Method" _ tIdx, tText, tTime, "0", 1)
        ; Capture %ROWID for cleanup.
        Set ^||SessionAgentTest41EventIds(tIdx) = $Get(%ROWID)
    }

    ; --- Ens.Rule.Log fixture rows.
    ; Row plan: 3 decisions for SessionId=tSession, distinct TimeExecuted,
    ; two of them under FIXTURERULENAMEA, one under FIXTURERULENAMEB.
    Set tInsertR = ##class(%SQL.Statement).%New()
    Set tSC = tInsertR.%Prepare("INSERT INTO Ens_Rule.Log (SessionId, RuleName, RuleSet, ActivityName, Reason, ReturnValue, TimeExecuted, ConfigName, CurrentHeaderId, IsError) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
    If $$$ISERR(tSC) Quit tSC

    Set tRRows = $ListBuild( $ListBuild(..#FIXTURERULENAMEA, "approve", "rule chain matched", ..#FIXTUREMESSAGEIDA), $ListBuild(..#FIXTURERULENAMEB, "review", "amount exceeds threshold", ..#FIXTUREMESSAGEIDA), $ListBuild(..#FIXTURERULENAMEA, "approve", "rule chain matched", ..#FIXTUREMESSAGEIDB))

    Set tRCount = $ListLength(tRRows)
    For tIdx = 1:1:tRCount {
        Set tR = $ListGet(tRRows, tIdx)
        Set tRule = $ListGet(tR, 1)
        Set tRet = $ListGet(tR, 2)
        Set tReason = $ListGet(tR, 3)
        Set tHdrId = $ListGet(tR, 4)
        Set tShiftedSecs = tBaseSecs + 100 + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tTime = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tRs = tInsertR.%Execute(tSession, tRule, "DefaultRuleSet", "Activity_" _ tIdx, tReason, tRet, tTime, "TestRuleConfig", tHdrId, 0)
        Set ^||SessionAgentTest41RuleIds(tIdx) = $Get(%ROWID)
    }
    Quit $$$OK
}

/// <p>Cleanup — delete fixture rows by captured IDs + sweep any
/// stragglers matching the fixture session id.</p>
Method OnAfterAllTests() As %Status
{
    Set tDelE = ##class(%SQL.Statement).%New()
    Set tSCdE = tDelE.%Prepare("DELETE FROM Ens_Util.Log WHERE SessionId = ?")
    If $$$ISOK(tSCdE) {
        Do tDelE.%Execute(..#FIXTURESESSIONID)
    }
    Kill ^||SessionAgentTest41EventIds
    Set tDelR = ##class(%SQL.Statement).%New()
    Set tSCdR = tDelR.%Prepare("DELETE FROM Ens_Rule.Log WHERE SessionId = ?")
    If $$$ISOK(tSCdR) {
        Do tDelR.%Execute(..#FIXTURESESSIONID)
    }
    Kill ^||SessionAgentTest41RuleIds
    Quit $$$OK
}

/// <p>Build a CallerContext with sane defaults for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#FIXTURESESSIONID
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-3 happy path — no filters. Five fixture rows (assert, error,
/// warning, info-A, info-B) match the default Type cap (≤4). Trace
/// row is excluded.</p>
Method TestEventLogReturnsAllRowsNoFilter()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "EventLog.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("event_count"), 5, "event_count = 5 (default Type<=4 cap excludes Trace=5)")
    Set tCounts = tResult.structuredContent.%Get("severity_counts")
    Do $$$AssertEquals(+tCounts.%Get("info"), 2, "severity_counts.info = 2 (info-A + info-B)")
    Do $$$AssertEquals(+tCounts.%Get("warning"), 1, "severity_counts.warning = 1")
    Do $$$AssertEquals(+tCounts.%Get("error"), 1, "severity_counts.error = 1")
    Do $$$AssertEquals(+tCounts.%Get("assert"), 1, "severity_counts.assert = 1")
    Quit
}

/// <p>AC-3 severity cap — <code>min_severity='error'</code> reduces
/// to assert + error rows only (Type ≤ 2).</p>
Method TestEventLogMinSeverityErrorFiltersToErrorAndAssert()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID), "min_severity": "error"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "EventLog.Invoke OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("event_count"), 2, "event_count = 2 (assert + error)")
    Set tIter = tResult.structuredContent.%Get("events").%GetIterator()
    Set tAllSevereOk = 1
    While tIter.%GetNext(.tKey, .tEv) {
        Set tSev = tEv.%Get("severity")
        If (tSev '= "error") && (tSev '= "assert") Set tAllSevereOk = 0
    }
    Do $$$AssertTrue(tAllSevereOk, "every returned event has severity in (error, assert)")
    Quit
}

/// <p>AC-3 message_id filter — filters to rows for one of two distinct
/// message_ids (A=4 rows: assert/error/warning/info-A; B=1 row: info-B).</p>
Method TestEventLogMessageIdFilter()
{
    Set tCtx = ..BuildCtx()

    ; Filter to message id B — should be exactly 1 row (info B).
    Set tArgsB = {"session_id": (..#FIXTURESESSIONID), "message_id": (..#FIXTUREMESSAGEIDB)}
    Set tResultB = ""
    Set tSCB = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgsB, .tResultB)
    Do $$$AssertStatusOK(tSCB, "EventLog.Invoke OK (message_id=B)")
    Do $$$AssertEquals(+tResultB.structuredContent.%Get("event_count"), 1, "event_count = 1 for message_id B")
    Set tEvent0 = tResultB.structuredContent.%Get("events").%Get(0)
    Do $$$AssertEquals(+tEvent0.%Get("message_id"), (..#FIXTUREMESSAGEIDB), "row's message_id matches filter")

    ; Filter to message id A — should be 4 rows (assert/error/warning/info-A).
    Set tArgsA = {"session_id": (..#FIXTURESESSIONID), "message_id": (..#FIXTUREMESSAGEIDA)}
    Set tResultA = ""
    Set tSCA = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgsA, .tResultA)
    Do $$$AssertStatusOK(tSCA, "EventLog.Invoke OK (message_id=A)")
    Do $$$AssertEquals(+tResultA.structuredContent.%Get("event_count"), 4, "event_count = 4 for message_id A (assert/error/warning/info-A)")
    Quit
}

/// <p>AC-3 validation path — empty <code>session_id</code> returns
/// FR37 envelope.</p>
Method TestEventLogMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>Story 3.0 AC-3 case-insensitive — "ERROR", "Error", "error" all
/// reduce to the same 2-row subset.</p>
Method TestEventLogMinSeverityCaseInsensitive()
{
    Set tCtx = ..BuildCtx()

    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, {"session_id":(..#FIXTURESESSIONID), "min_severity":"ERROR"}, .tResult)
    Do $$$AssertStatusOK(tSC, "min_severity=ERROR (uppercase) returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("event_count"), 2, "ERROR (uppercase) reduces to 2 rows")

    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, {"session_id":(..#FIXTURESESSIONID), "min_severity":"Error"}, .tResult2)
    Do $$$AssertStatusOK(tSC2, "min_severity=Error (mixed case) OK")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("event_count"), 2, "Error (mixed case) reduces to 2 rows")

    Set tResult3 = ""
    Set tSC3 = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, {"session_id":(..#FIXTURESESSIONID), "min_severity":"  warning  "}, .tResult3)
    Do $$$AssertStatusOK(tSC3, "min_severity='  warning  ' (whitespace + lowercase) OK")
    Do $$$AssertEquals(+tResult3.structuredContent.%Get("event_count"), 3, "warning reduces to 3 rows (assert + error + warning)")
    Quit
}

/// <p>Story 3.0 AC-2 — <code>time_logged</code> conforms to canonical
/// 20-char ISO-8601 UTC Z form.</p>
Method TestEventLogTimestampIsoFormat()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "EventLog.Invoke OK")
    Set tEvents = tResult.structuredContent.%Get("events")
    Do $$$AssertTrue(tEvents.%Size() > 0, "fixture seeded events present")
    Set tEv = tEvents.%Get(0)
    Set tTL = tEv.%Get("time_logged")
    Do $$$AssertEquals($Length(tTL), 20, "time_logged is exactly 20 chars (got: " _ tTL _ ")")
    Do $$$AssertEquals($Extract(tTL, 11), "T", "time_logged char 11 is 'T'")
    Do $$$AssertEquals($Extract(tTL, 20), "Z", "time_logged char 20 is 'Z'")
    Quit
}

/// <p>AC-6 happy path — 3 fixture decisions returned in
/// <code>TimeExecuted ASC</code> chronological order.</p>
Method TestRuleLogReturnsAllDecisionsChronological()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.RuleLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "RuleLog.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("decision_count"), 3, "decision_count = 3 (3 fixture decisions)")
    Set tDecisions = tResult.structuredContent.%Get("decisions")
    Do $$$AssertEquals(tDecisions.%Size(), 3, "decisions array has 3 entries")
    ; Verify chronological ordering — TimeExecuted ASC.
    Set tPrevTime = ""
    Set tIter = tDecisions.%GetIterator()
    Set tOrderingOk = 1
    While tIter.%GetNext(.tKey, .tDec) {
        Set tThisTime = tDec.%Get("time_executed")
        If (tPrevTime '= "") && (tThisTime ]] tPrevTime = 0) && (tThisTime '= tPrevTime) {
            Set tOrderingOk = 0
        }
        Set tPrevTime = tThisTime
    }
    Do $$$AssertTrue(tOrderingOk, "decisions sorted ASC by TimeExecuted")
    Quit
}

/// <p>AC-6 rule_class filter — fixture has 2 decisions for RuleNameA,
/// 1 for RuleNameB. Filter to RuleNameB → 1 row.</p>
Method TestRuleLogRuleClassFilter()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID), "rule_class": (..#FIXTURERULENAMEB)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.RuleLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "RuleLog.Invoke (rule_class=B) OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("decision_count"), 1, "decision_count = 1 for RuleNameB")
    Set tDec0 = tResult.structuredContent.%Get("decisions").%Get(0)
    Do $$$AssertEquals(tDec0.%Get("rule_name"), (..#FIXTURERULENAMEB), "decision.rule_name matches filter")

    ; Now filter to RuleNameA — 2 rows.
    Set tArgsA = {"session_id": (..#FIXTURESESSIONID), "rule_class": (..#FIXTURERULENAMEA)}
    Set tResultA = ""
    Set tSCA = ##class(SessionAgent.Tool.Inspection.RuleLog).Invoke(tCtx, tArgsA, .tResultA)
    Do $$$AssertStatusOK(tSCA, "RuleLog.Invoke (rule_class=A) OK")
    Do $$$AssertEquals(+tResultA.structuredContent.%Get("decision_count"), 2, "decision_count = 2 for RuleNameA")
    Quit
}

/// <p>AC-6 validation path — FR37 envelope.</p>
Method TestRuleLogMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.RuleLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>Story 3.0 AC-2 — <code>time_executed</code> conforms to canonical
/// 20-char ISO-8601 UTC Z form.</p>
Method TestRuleLogTimestampIsoFormat()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.RuleLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "RuleLog.Invoke OK")
    Set tDecisions = tResult.structuredContent.%Get("decisions")
    Do $$$AssertTrue(tDecisions.%Size() > 0, "fixture seeded decisions present")
    Set tDec = tDecisions.%Get(0)
    Set tTE = tDec.%Get("time_executed")
    Do $$$AssertEquals($Length(tTE), 20, "time_executed is exactly 20 chars (got: " _ tTE _ ")")
    Do $$$AssertEquals($Extract(tTE, 11), "T", "time_executed char 11 is 'T'")
    Do $$$AssertEquals($Extract(tTE, 20), "Z", "time_executed char 20 is 'Z'")
    Quit
}

/// <p>AC-3 step 8 + Story 4.1 review F-1 — <code>severity_counts</code>
/// reflects the TRUE distribution over the WHERE predicate, NOT just the
/// rows returned under <code>TOP ?</code>. Set <code>limit=1</code> with
/// no severity filter; <code>events</code> array has 1 row but
/// <code>severity_counts</code> still reports the full fixture
/// (info=2, warning=1, error=1, assert=1).</p>
Method TestEventLogSeverityCountsReflectFullPredicateNotLimit()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID), "limit": 1}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.EventLog).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "EventLog.Invoke OK with limit=1")
    Set tEvents = tResult.structuredContent.%Get("events")
    Do $$$AssertEquals(tEvents.%Size(), 1, "events array capped at limit=1")
    Set tCounts = tResult.structuredContent.%Get("severity_counts")
    Do $$$AssertEquals(+tCounts.%Get("info"), 2, "severity_counts.info=2 (full predicate, not limited by TOP)")
    Do $$$AssertEquals(+tCounts.%Get("warning"), 1, "severity_counts.warning=1 (full predicate)")
    Do $$$AssertEquals(+tCounts.%Get("error"), 1, "severity_counts.error=1 (full predicate)")
    Do $$$AssertEquals(+tCounts.%Get("assert"), 1, "severity_counts.assert=1 (full predicate)")

    ; Summary text must call out truncation when count < total.
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "1 of 5", "summary text shows '1 of 5' truncation marker (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "limit reached", "summary text mentions 'limit reached' (got: " _ tSummary _ ")")
    Quit
}

/// <p>AC-7 registry discovery — both <code>event_log</code> and
/// <code>rule_log</code> appear in <method>Tool.Registry.ListTools</method>
/// with valid input_schema entries (auto-discovered via dictionary
/// reflection — no explicit registration code).</p>
Method TestRegistryListToolsIncludesEventLogAndRuleLog()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFoundEvent = 0
    Set tFoundRule = 0
    Set tEventEntry = ""
    Set tRuleEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tName = tEntry.%Get("name")
        If tName = "event_log" {
            Set tFoundEvent = 1
            Set tEventEntry = tEntry
        }
        If tName = "rule_log" {
            Set tFoundRule = 1
            Set tRuleEntry = tEntry
        }
    }
    Do $$$AssertTrue(tFoundEvent, "Registry surfaces 'event_log'")
    Do $$$AssertTrue(tFoundRule, "Registry surfaces 'rule_log'")

    ; Schema sanity — event_log schema should require session_id.
    If $IsObject(tEventEntry) {
        Set tSchema = tEventEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "event_log input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "event_log schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "event_log schema.required has one entry")
        Do $$$AssertEquals(tRequired.%Get(0), "session_id", "event_log schema.required[0] = 'session_id'")
    }

    ; Schema sanity — rule_log schema should require session_id.
    If $IsObject(tRuleEntry) {
        Set tSchemaR = tRuleEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchemaR), "rule_log input_schema is an object")
        Set tRequiredR = tSchemaR.%Get("required")
        Do $$$AssertTrue($IsObject(tRequiredR), "rule_log schema.required is an array")
        Do $$$AssertEquals(tRequiredR.%Size(), 1, "rule_log schema.required has one entry")
        Do $$$AssertEquals(tRequiredR.%Get(0), "session_id", "rule_log schema.required[0] = 'session_id'")
    }
    Quit
}

}
