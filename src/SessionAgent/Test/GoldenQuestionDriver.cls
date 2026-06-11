/// <p><b>Story 14.5 AC-4 — golden-question mock-matrix driver.</b>
/// Dispatches a single tool call through the REAL
/// <CLASS>SessionAgent.Tool.Registry</CLASS> <method>Dispatch</method>
/// path (registry resolution, arg validation, audit emit, envelope
/// shaping) so the Epic 14 golden-question entries in
/// <code>_bmad-output/implementation-artifacts/epic-14-golden-questions.md</code>
/// can be executed mechanically against the live sample production.
/// Retained post-story as the epic-end Rule 6 battery's mechanical
/// dispatch helper (bullet 5 user-led walkthrough builds on the AC-4
/// results this driver produced).</p>
///
/// <p>NOT a <CLASS>%UnitTest.TestCase</CLASS> — it carries no
/// <code>Test*</code> methods and never runs in the regression suite;
/// it is a typed-invocation surface for
/// <code>iris_execute_classmethod</code>.</p>
Class SessionAgent.Test.GoldenQuestionDriver Extends %RegisteredObject
{

/// <p>Dispatch <var>pToolName</var> with <var>pArgsJson</var> (a JSON
/// object string) through the real registry. Returns the full result
/// envelope JSON; on dispatch/driver failure returns
/// <code>{"driverError": "..."}</code> instead of throwing.</p>
///
/// <p><var>pAgentName</var> (Story 14.5 review fix) selects the caller
/// context: <code>"message-search"</code> routes <var>pSessionId</var>
/// into <property>SearchSessionKey</property> (audit attribution per
/// <method>SessionAgent.Tool.Registry.Dispatch</method>'s $Case);
/// anything else routes it into <property>IrisSessionId</property>.
/// Defaults to <code>"session-inspection"</code> — the shape the AC-4
/// mock-matrix run used.</p>
ClassMethod RunTool(pToolName As %String, pArgsJson As %String = "{}", pSessionId As %String = "", pAgentName As %String = "session-inspection") As %String
{
    Set tOut = ""
    Try {
        Set tArgs = ##class(%DynamicObject).%FromJSON(pArgsJson)
        Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
        Set tCtx.AgentName = pAgentName
        If pAgentName = "message-search" {
            Set tCtx.SearchSessionKey = pSessionId
        } Else {
            Set tCtx.IrisSessionId = pSessionId
        }
        Set tCtx.PortalUser = "gq-driver"
        Set tCtx.Namespace = $NAMESPACE
        Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch(pToolName, tCtx, tArgs, .tEnvelope)
        If $$$ISERR(tSC) {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("driverError", $System.Status.GetErrorText(tSC))
            Set tOut = tErr.%ToJSON()
            Quit
        }
        Set tOut = tEnvelope.%ToJSON()
    } Catch ex {
        Set tErr2 = ##class(%DynamicObject).%New()
        Do tErr2.%Set("driverError", ex.DisplayString())
        Set tOut = tErr2.%ToJSON()
    }
    Quit tOut
}

}
