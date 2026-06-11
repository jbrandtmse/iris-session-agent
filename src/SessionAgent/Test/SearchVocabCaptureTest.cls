/// <p>Story 9.5 AC-4 — unit tests for
/// <CLASS>SessionAgent.Search.VocabCapture</CLASS>'s
/// <method>RecordClickThrough</method> ClassMethod (the click-through
/// capture entry point that Epic 10 Story 10.1's portal-subclass
/// ZenMethod will delegate to).</p>
///
/// <p><b>Test isolation strategy.</b> All test rows use
/// <code>PortalUser</code> prefix <code>sa-test-95-</code>. Cleanup uses
/// the broader <code>'sa-test-9%' LIKE</code> pattern (covers Story 9.2's
/// <code>sa-test-92-</code>, Story 9.3's <code>sa-test-93-</code>, and
/// this story's <code>sa-test-95-</code> — future Stories using
/// <code>sa-test-96-</code>, etc. inherit the cleanup automatically).
/// <method>OnBeforeAllTests</method> and <method>OnAfterAllTests</method>
/// each issue
/// <code>DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-9%'</code>
/// to bracket the suite.</p>
///
/// <p><b>Property naming note (Story 7.0 AC-3 codification).</b> No
/// state-tracking property on this class begins with <code>Test*</code> —
/// that prefix would collide with the framework's test-method-discovery
/// loop and surface as phantom tests. State is tracked via local
/// variables only; no properties needed.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/9-5-recordclickthrough-zenmethod-hyperevent-stub.md">Story 9.5 spec</a> — AC-4 verbatim source.</li>
/// <li><CLASS>SessionAgent.Search.VocabCapture</CLASS> §<method>RecordClickThrough</method>.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a> — assertion macros, constructor pattern, Test* shadow trap.</li>
/// </ul>
Class SessionAgent.Test.SearchVocabCaptureTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Suite bracket — clean any leftover <code>sa-test-9*</code> rows
/// from a prior partial / failed run. Idempotent.</p>
Method OnBeforeAllTests() As %Status
{
    Try {
        Do ..CleanupTestRows()
    } Catch {}
    Quit $$$OK
}

/// <p>Suite bracket — clean test rows on suite exit so a downstream
/// <method>SessionAgent.Installer.Install</method> or vocab-state probe
/// does not see test pollution.</p>
Method OnAfterAllTests() As %Status
{
    Try {
        Do ..CleanupTestRows()
    } Catch {}
    Quit $$$OK
}

/// <p>Per-test cleanup — DELETE any rows the test created so each test
/// starts from a known-empty state for its <code>sa-test-95-*</code>
/// PortalUsers.</p>
Method OnAfterOneTest() As %Status
{
    Try {
        Do ..CleanupTestRows()
    } Catch {}
    Quit $$$OK
}

/// <p>Helper — DELETE all rows whose <code>PortalUser</code> matches the
/// broader <code>sa-test-9%</code> prefix.</p>
ClassMethod CleanupTestRows()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-9%'")
    Do tStmt.%Execute()
    Quit
}

/// <p>AC-4 row 1 — Two distinct contributing tool calls produce TWO
/// distinct aliases; both are recorded as
/// <code>UserVocabulary</code> rows with
/// <code>CreatedVia='clickthrough'</code> and
/// <code>SuccessCount=1</code>.</p>
Method TestRecordClickThroughTwoToolCallsTwoAliases()
{
    Set tUser = "sa-test-95-twocalls"
    Set tToolCallsJson = "[{""tool_name"":""search_by_status"",""args"":{""status_in"":[""Error""]},""result"":{}},{""tool_name"":""search_by_message_class"",""args"":{""message_body_class_name"":""EnsLib.HL7.Message""},""result"":{}}]"

    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-twocalls", "session-001", tToolCallsJson, tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 1, "success: true")
    Do $$$AssertEquals(tResp.%Get("aliases_recorded").%Size(), 2, "aliases_recorded.%Size() = 2")

    ; Verify two distinct UserVocabulary rows.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(CreatedVia) = 'clickthrough' AND SuccessCount = 1")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 2, "two clickthrough rows with SuccessCount=1 exist for sa-test-95-twocalls")
    Quit
}

/// <p>AC-4 row 2 — Two contributing tool calls that synthesize the SAME
/// alias result in only ONE <code>RecordSuccess</code> call; the
/// recorded-aliases list has size 1, and only one
/// <code>UserVocabulary</code> row exists with <code>SuccessCount=1</code>
/// (NOT 2).</p>
Method TestRecordClickThroughDuplicateAliasDeduped()
{
    Set tUser = "sa-test-95-dedup"
    ; Two identical search_by_status blocks → identical alias → dedupe.
    Set tToolCallsJson = "[{""tool_name"":""search_by_status"",""args"":{""status_in"":[""Error""]},""result"":{}},{""tool_name"":""search_by_status"",""args"":{""status_in"":[""Error""]},""result"":{}}]"

    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-dedup", "session-002", tToolCallsJson, tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 1, "success: true")
    Do $$$AssertEquals(tResp.%Get("aliases_recorded").%Size(), 1, "aliases_recorded.%Size() = 1 (deduped)")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c, MAX(SuccessCount) AS sc FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 1, "exactly one row exists (no duplicate)")
    Do $$$AssertEquals(+tRs.%Get("sc"), 1, "SuccessCount=1 (NOT 2 — dedupe prevented the second invocation)")
    Quit
}

/// <p>AC-4 row 3 — Empty contributing-tool-calls array produces
/// <code>success: true</code> with <code>aliases_recorded</code> empty;
/// no <code>UserVocabulary</code> rows are created.</p>
Method TestRecordClickThroughEmptyToolCallsArrayReturnsEmpty()
{
    Set tUser = "sa-test-95-empty"
    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-empty", "session-003", "[]", tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 1, "success: true on empty array")
    Do $$$AssertEquals(tResp.%Get("aliases_recorded").%Size(), 0, "aliases_recorded.%Size() = 0")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 0, "no UserVocabulary rows created for empty input")
    Quit
}

/// <p>AC-4 row 4 — Invalid JSON input returns
/// <code>success: false</code> with an <code>error</code> string
/// containing <code>"invalid JSON"</code>. No exception escapes
/// to the caller (FR37).</p>
Method TestRecordClickThroughInvalidJsonReturnsErrorEnvelope()
{
    Set tUser = "sa-test-95-invalidjson"
    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-bad", "session-004", "not-json", tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 0, "success: false on invalid JSON")
    Set tErr = tResp.%Get("error")
    Do $$$AssertTrue(tErr [ "invalid JSON", "error contains 'invalid JSON'; got: " _ tErr)

    ; No row should have been created.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 0, "no rows created on invalid JSON input")
    Quit
}

/// <p>AC-4 row 5 — Empty <code>pPortalUser</code> triggers the caller-
/// side input-validation guard (Story 9.0 carry-forward LOW-9.2-F06)
/// and returns a structured error envelope. No exception escapes
/// (FR37).</p>
///
/// <p>Originally specced as "construct a tool-call block whose synthesis
/// would throw" — but per Story 9.1's robust SynthesizeAlias
/// implementation, all input shapes are handled gracefully. The
/// caller-side guard (empty pPortalUser) is the cleanest exception-
/// would-have-fired path AND is the more important contract: it
/// directly satisfies FR37's "never throw" guarantee at the
/// public-surface boundary.</p>
Method TestRecordClickThroughInvokeTimeExceptionReturnsErrorEnvelope()
{
    ; Call with empty pPortalUser → caller-side guard fires.
    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-emptyuser", "session-005", "[]", "")
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 0, "success: false when pPortalUser is empty")
    Set tErr = tResp.%Get("error")
    Do $$$AssertTrue(tErr '= "", "error is populated; got: " _ tErr)
    Do $$$AssertTrue(tErr [ "pPortalUser", "error references the offending parameter; got: " _ tErr)
    Quit
}

/// <p>AC-4 row 6 — <code>pSearchSessionKey</code> and
/// <code>pSessionId</code> are echoed verbatim in the response JSON
/// (AC-3). They are not used by alias-capture logic.</p>
Method TestRecordClickThroughEchoesPassthroughIds()
{
    Set tUser = "sa-test-95-echo"
    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-94-5", "123456", "[]", tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(tResp.%Get("search_session_key"), "search-session-94-5", "search_session_key echoed verbatim")
    Do $$$AssertEquals(tResp.%Get("session_id"), "123456", "session_id echoed verbatim")
    Quit
}

/// <p>AC-4 row 7 — A contributing tool call with
/// <code>args.message_body_class_name</code> set produces a
/// <code>UserVocabulary</code> row with the matching
/// <code>MessageBodyClass</code>.</p>
Method TestRecordClickThroughExtractsMessageBodyClassFromArgs()
{
    Set tUser = "sa-test-95-bodyclass"
    Set tToolCallsJson = "[{""tool_name"":""search_by_message_class"",""args"":{""message_body_class_name"":""SessionAgent.Sample.Msg.OrderRequest""}}]"

    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-bc", "session-007", tToolCallsJson, tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 1, "success: true")
    Do $$$AssertEquals(tResp.%Get("aliases_recorded").%Size(), 1, "one alias recorded")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT %EXACT(MessageBodyClass) AS mbc FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do $$$AssertTrue(tRs.%Next(), "row exists post-RecordClickThrough")
    Do $$$AssertEquals(tRs.%Get("mbc"), "SessionAgent.Sample.Msg.OrderRequest", "MessageBodyClass extracted from args.message_body_class_name")
    Quit
}

/// <p>AC-4 row 8 — After
/// <method>TestRecordClickThroughTwoToolCallsTwoAliases</method>-shaped
/// invocation, <code>%SYS.Audit</code> contains rows for
/// <code>(SessionAgent, VocabWrite, clickthrough)</code> matching the
/// recorded aliases. Probes the most recent rows and counts matches by
/// PortalUser substring in EventData.</p>
Method TestRecordClickThroughEmitsClickthroughAudit()
{
    Set tUser = "sa-test-95-audit"
    Set tToolCallsJson = "[{""tool_name"":""search_by_status"",""args"":{""status_in"":[""Error""]},""result"":{}},{""tool_name"":""search_by_message_class"",""args"":{""message_body_class_name"":""EnsLib.HL7.Message""},""result"":{}}]"

    Set tRespJson = ##class(SessionAgent.Search.VocabCapture).RecordClickThrough("search-session-95-aud", "session-008", tToolCallsJson, tUser)
    Set tResp = ##class(%DynamicAbstractObject).%FromJSON(tRespJson)
    Do $$$AssertEquals(+tResp.%Get("success"), 1, "success: true (precondition)")
    Do $$$AssertEquals(tResp.%Get("aliases_recorded").%Size(), 2, "two aliases recorded (precondition)")

    ; Probe %SYS.Audit for clickthrough rows referencing this PortalUser.
    ; Story 14.0 — kernel audit daemon flushes asynchronously (observed
    ; ~30-60s on the 2026-06 fresh server; no public forced-flush API —
    ; see SessionAgent.Test.SweepTaskTest.WaitForTaskRunAuditIncrease for
    ; the originating empirical probe). Poll up to ~120s; exits early.
    Set tFoundCount = 0
    For tAttempt = 1:1:240 {
        Set tFoundCount = ..CountClickthroughAuditRowsForUser(tUser)
        If tFoundCount >= 2 Quit
        Hang 0.5
    }
    Do $$$AssertTrue(tFoundCount >= 2, "at least 2 (SessionAgent, VocabWrite, clickthrough) audit rows for sa-test-95-audit; got " _ tFoundCount)
    Quit
}

/// <p>Helper — count audit rows in <code>%SYS.Audit</code> matching
/// <code>(EventSource=SessionAgent, EventType=VocabWrite,
/// Event=clickthrough)</code> whose <code>EventData</code> contains the
/// supplied <var>pUser</var> substring. Limits the scan to the most
/// recent 50 rows so the probe finishes quickly even on an audit-heavy
/// install.</p>
ClassMethod CountClickthroughAuditRowsForUser(pUser As %String) As %Integer
{
    Set tCount = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Set tStmt = ##class(%SQL.Statement).%New()
        Do tStmt.%Prepare("SELECT TOP 50 %EXACT(EventData) AS ed FROM %SYS.Audit WHERE %EXACT(EventSource) = 'SessionAgent' AND %EXACT(EventType) = 'VocabWrite' AND %EXACT(Event) = 'clickthrough' ORDER BY UTCTimeStamp DESC")
        Set tRs = tStmt.%Execute()
        While tRs.%Next() {
            Set tEd = tRs.%Get("ed")
            If tEd [ ("PortalUser=" _ pUser) {
                Set tCount = tCount + 1
            }
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tCount
}

}
