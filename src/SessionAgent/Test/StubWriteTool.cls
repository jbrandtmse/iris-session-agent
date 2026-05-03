/// <p>Test fixture — write-capable stub tool used by
/// <CLASS>SessionAgent.Test.ToolRegistryTest</CLASS> to verify that
/// <method>SessionAgent.Tool.Registry.Dispatch</method> rejects any
/// dispatch where <parameter>MutatesState=1</parameter> (FR36 / NFR-S1
/// Layer-2 read-only enforcement).</p>
///
/// <p>The <method>Invoke</method> body MUST never run during normal
/// dispatch — the registry blocks the call before it reaches us. We
/// raise an exception here so the test can prove the body was not
/// executed (if the registry ever called us, the test would see a
/// thrown exception instead of a clean read-only-policy envelope).</p>
Class SessionAgent.Test.StubWriteTool Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "test_write_tool";

Parameter Description As %String = "Test fixture — declares MutatesState=1; the registry MUST block this.";

Parameter MutatesState As %Boolean = 1;

ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {},
        "required": [],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    ; Should never execute — Registry.Dispatch blocks at L2 enforcement.
    ; Throw so any test that accidentally dispatches us fails loudly.
    Throw ##class(%Exception.General).%New("StubWriteTool", 5001, , "StubWriteTool.Invoke must never be called by Registry.Dispatch — the L2 read-only gate failed to block the dispatch.")
}

}
