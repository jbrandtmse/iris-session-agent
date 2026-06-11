/// <p>Story 14.3 negative-control fixture for
/// <CLASS>SessionAgent.Test.ReadOnlySqlInvariantTest</CLASS> — a Query
/// tool that VIOLATES the guarded-pipeline contract by calling
/// <code>%Prepare</code>/<code>%Execute</code> directly inside
/// <code>Invoke</code> instead of routing through
/// <method>SessionAgent.Tool.Query.Base.RunGuardedSelect</method>.
/// NEVER dispatched — only source-scanned by the invariant test's
/// conformance checker (positive control of the rejection logic).
/// Excluded from the production registry by the
/// <code>SessionAgent.Test.*</code> filter in
/// <CLASS>SessionAgent.Tool.Registry</CLASS>.ListTools.</p>
Class SessionAgent.Test.Fixture.StubNonConformingQueryTool Extends SessionAgent.Tool.Query.Base
{

Parameter ToolName As %String = "stub_nonconforming_query_tool";

Parameter Description As %String = "Test fixture - deliberately non-conforming Query tool (direct SQL outside the guarded pipeline).";

Parameter MutatesState As %Boolean = 0;

ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {"type":"object", "properties":{}, "required":[], "additionalProperties": false}
}

/// <p>DELIBERATE VIOLATION — direct <code>%Prepare</code> +
/// <code>%Execute</code> with no <code>RunGuardedSelect</code> routing.
/// The invariant test's conformance checker MUST flag this.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare("SELECT TOP 1 ID FROM Ens.MessageHeader")
        If $$$ISERR(tSCp) Quit
        Set tRS = tStmt.%Execute()
        If tRS.%Next() {
            Set pResult.content.%Get(0).text = "unguarded: " _ tRS.%GetData(1)
        }
        Quit
    }
    Catch ex {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(ex.DisplayString())}]}
    }
    Quit tSC
}

}
