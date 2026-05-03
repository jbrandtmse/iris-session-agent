/// <p>Test fixture — read-only stub tool used by
/// <CLASS>SessionAgent.Test.ToolBaseTest</CLASS> and
/// <CLASS>SessionAgent.Test.ToolRegistryTest</CLASS> to exercise the
/// happy-path dispatch flow without depending on any concrete Epic 4 /
/// Epic 8 tool.</p>
///
/// <p><parameter>MutatesState=0</parameter> — passes the L2 read-only
/// gate. <method>Invoke</method> returns a fixed MCP success envelope.</p>
///
/// <p>Lives under <code>src/SessionAgent/Test/</code> alongside
/// <CLASS>SessionAgent.Test.MockOpenAIProvider</CLASS> (Story 2.9
/// precedent for test-only fixture classes).</p>
Class SessionAgent.Test.StubReadOnlyTool Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "test_readonly_tool";

Parameter Description As %String = "Test fixture — read-only stub used by Story 2.10 dispatch tests.";

Parameter MutatesState As %Boolean = 0;

ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "echo": {"type": "string", "description": "Optional echo string."}
        },
        "required": [],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set pResult = {
        "content": [{"type":"text", "text":"ok"}],
        "structuredContent": {"stub": "readonly"}
    }
    Quit $$$OK
}

}
