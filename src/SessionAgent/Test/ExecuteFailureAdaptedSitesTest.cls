/// <p>Story 14.0 QA gap coverage — behavioral assertions for the
/// <b>adapted</b> execute-failure guard sites that do NOT use the standard
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnExecuteFailure</method>
/// caller pattern (see Story 14.0 Completion Notes, "Adapted-guard sites").
/// Complements <CLASS>SessionAgent.Test.ExecuteFailureGateTest</CLASS>
/// (helper unit tests + SessionTimeline end-to-end), which covers the
/// standard-guard sites.</p>
///
/// <p><b>Target contract.</b>
/// <CLASS>SessionAgent.Tool.Search.FindSessionsUsingClass</CLASS>'s
/// <method>RunQuery</method> has no <code>pResult</code> in scope, so its
/// Story 14.0 execute guard was adapted to a <code>%Status</code> error
/// contract: a runtime <code>%Execute</code> failure returns
/// <code>$$$ERROR</code> with text
/// <code>"SQL execute failed for find_sessions_using_class: SQLCODE &lt;n&gt;: &lt;%Message&gt;"</code>,
/// and the <method>Invoke</method> call-site classifies the failure via
/// <method>ShapeRunQueryErrorEnvelope</method> (Story 14.0 review fix):
/// the execute marker shapes the canonical
/// <code>render_strategy="execute_error"</code> envelope; every other
/// RunQuery error (validation, prepare) keeps the Story 11.2
/// <code>prepare_error</code> shape. Never a success-shaped empty
/// result. This two-link chain (real runtime %Execute failure → marker
/// %Status → canonical execute_error envelope) is the AC-3c
/// execute_error evidence: after the review-fix best-effort adaptations
/// (SessionTimeline span / EventLog severity counts), no in-repo tool
/// statement reachable from a public Invoke fails at %Execute, so the
/// chain is asserted link-by-link.</p>
///
/// <p><b>Empirical premises (probed 2026-06-11, this QA stage).</b></p>
/// <ul>
/// <li>A constant scalar subquery <code>(SELECT DATEDIFF('ms','garbage-a','garbage-b')) &gt;= 0</code>
/// inside a table-context WHERE over <code>Ens.MessageHeader</code> fails
/// <b>at %Execute time</b> with <code>%SQLCODE = -400</code>
/// (probe: <code>prep=1 afterExecute=-400</code>) — evaluated at cursor
/// open regardless of whether any row matches the other predicates, so the
/// vehicle is deterministic and data-independent.</li>
/// <li>No Search-family statement is a scalar no-FROM shape, so a real
/// runtime execute failure CANNOT be staged through any Search tool's
/// public Invoke path (table-context predicates are silently coerced per
/// the Story 14.0 Task 4 probes) — hence these tests drive
/// <method>RunQuery</method> directly with a crafted column filter, plus
/// the Invoke conversion path via a deterministic
/// <code>BuildBoundedWhereClause</code> validation error.</li>
/// <li>IRIS error-text prefixes are locale-dependent on this server
/// (localized "#5001" prefix) — assertions target only the
/// locale-independent substrings authored by project code.</li>
/// </ul>
Class SessionAgent.Test.ExecuteFailureAdaptedSitesTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>CallerContext fixture — same shape as ExecuteFailureGateTest.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-search"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Adapted-guard site (FindSessionsUsingClass.RunQuery lines ~256-262):
/// a REAL runtime %Execute failure (scalar DATEDIFF subquery, %SQLCODE
/// -400 at cursor open) returns an error %Status carrying the documented
/// "SQL execute failed for find_sessions_using_class: SQLCODE" text —
/// proving the guard fires BEFORE %Next() and does not fall through to a
/// silent zero-row success.</p>
Method TestRunQueryReturnsErrorStatusOnExecuteFailure()
{
    Set tColFilter = "%EXACT(mh.SourceConfigName) = ? AND (SELECT DATEDIFF('ms','garbage-a','garbage-b')) >= 0"
    Set tSessions = ""
    Set tCount = -1
    Set tMatchedVia = "source_config"
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).RunQuery("Story140QaNoSuchClass", tColFilter, "source_config", 1, 5, .tSessions, .tCount, .tMatchedVia)
    Do $$$AssertStatusNotOK(tSC, "RunQuery returns error %Status on runtime %Execute failure")
    Set tErrText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tErrText [ "SQL execute failed for find_sessions_using_class", "error text carries the adapted-guard prefix (got: " _ tErrText _ ")")
    ; Story 14.0 review fix — generic negative-SQLCODE assertion (the
    ; literal -400 is engine-version brittle).
    Do $$$AssertTrue(tErrText [ "SQLCODE -", "error text carries a negative runtime SQLCODE")
    Quit
}

/// <p>Story 14.0 review fix — the Invoke-side classifier
/// (<method>ShapeRunQueryErrorEnvelope</method>) converts a RunQuery
/// %Status carrying the execute marker into the canonical
/// <code>render_strategy="execute_error"</code> envelope (NOT the
/// contradictory "SQL prepare failed: ... SQL execute failed ..."
/// prepare_error shape the pre-review code emitted). The marker status
/// is crafted here with the exact text RunQuery's adapted guard emits
/// (proven real by <method>TestRunQueryReturnsErrorStatusOnExecuteFailure</method>),
/// closing the second link of the AC-3c chain.</p>
Method TestShapeRunQueryErrorEnvelopeExecuteMarker()
{
    Set tResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Set tStatus = $$$ERROR($$$GeneralError, "SQL execute failed for find_sessions_using_class: SQLCODE -400: probe message")
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).ShapeRunQueryErrorEnvelope(tResult, tStatus)
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on execute-marker status")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "execute_error", "render_strategy = 'execute_error' (corrected taxonomy — not prepare_error)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("error_text"), "SQLCODE -400: probe message", "error_text carries the marker tail verbatim")
    Do $$$AssertEquals(tResult.content.%Get(0).text, "Tool 'find_sessions_using_class' SQL execute failed: SQLCODE -400: probe message", "content[0].text carries the canonical execute-failed operator text")
    Quit
}

/// <p>Story 14.0 review fix companion — a non-marker %Status (validation /
/// prepare shape) falls through to the Story 11.2 prepare gate, proving
/// the classifier does not over-label every RunQuery error as
/// execute_error.</p>
Method TestShapeRunQueryErrorEnvelopeNonMarkerFallsBack()
{
    Set tResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Set tStatus = $$$ERROR($$$GeneralError, "pTimeWindowHours must be >= 1")
    Do ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).ShapeRunQueryErrorEnvelope(tResult, tStatus)
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on non-marker status")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "prepare_error", "non-marker status keeps the Story 11.2 prepare_error shape")
    Do $$$AssertTrue(tResult.structuredContent.%Get("error_text") [ "pTimeWindowHours must be >= 1", "error_text carries the underlying reason")
    Quit
}

/// <p>Sanity sibling — the same RunQuery call WITHOUT the failing
/// predicate succeeds with a clean %Status and pCount &gt;= 0, proving the
/// failure asserted above is caused by the execute-failure guard, not by
/// the direct-call fixture shape.</p>
Method TestRunQueryCleanColFilterSucceeds()
{
    Set tSessions = ""
    Set tCount = -1
    Set tMatchedVia = "source_config"
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).RunQuery("Story140QaNoSuchClass", "%EXACT(mh.SourceConfigName) = ?", "source_config", 1, 5, .tSessions, .tCount, .tMatchedVia)
    Do $$$AssertStatusOK(tSC, "RunQuery with clean column filter returns OK %Status")
    Do $$$AssertTrue(tCount >= 0, "pCount populated (got " _ tCount _ ")")
    Do $$$AssertTrue($IsObject(tSessions), "pSessions populated as a dynamic array")
    Quit
}

/// <p>Invoke conversion contract (validation arm): when RunQuery returns
/// a NON-execute error %Status (staged deterministically via
/// time_window_hours = -5, which BuildBoundedWhereClause rejects with
/// TimeWindowTooSmall), Invoke converts it into the canonical Story 11.2
/// error envelope — isError=1, render_strategy="prepare_error",
/// operator-readable content[0].text, structuredContent.error_text —
/// and still returns $$$OK per the envelope-based error contract. The
/// execute arm of the classifier is covered by
/// <method>TestShapeRunQueryErrorEnvelopeExecuteMarker</method>.</p>
Method TestInvokeConvertsRunQueryErrorToCanonicalEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Do tArgs.%Set("class_name", "Story140QaNoSuchClass")
    Do tArgs.%Set("time_window_hours", -5, "number")
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.FindSessionsUsingClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK (envelope-based error contract)")
    Do $$$AssertTrue($IsObject(tResult), "pResult populated")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 — RunQuery error %Status is NOT swallowed into a success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "prepare_error", "render_strategy = 'prepare_error' (non-execute status falls through ShapeRunQueryErrorEnvelope to the Story 11.2 prepare gate)")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "Tool 'find_sessions_using_class' SQL prepare failed", "content[0].text carries the canonical operator text (got: " _ tResult.content.%Get(0).text _ ")")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "pTimeWindowHours must be >= 1", "content[0].text carries the underlying RunQuery error reason")
    Do $$$AssertTrue(tResult.structuredContent.%Get("error_text") [ "pTimeWindowHours must be >= 1", "structuredContent.error_text carries the underlying error reason")
    Quit
}

}
