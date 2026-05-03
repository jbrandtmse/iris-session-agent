/// <p>Test fixture — read-only stub tool whose
/// <method>Invoke</method> throws an unhandled exception. Used by
/// <CLASS>SessionAgent.Test.ToolRegistryTest</CLASS> to verify that
/// <method>SessionAgent.Tool.Registry.Dispatch</method>'s outer
/// Try/Catch (defense-in-depth per architecture line 600) wraps the
/// thrown exception into the standard MCP error envelope and routes
/// the stack trace into <property>SessionAgent.Audit.ToolCall.ErrorText</property>
/// only — operator-readable <code>content[0].text</code> never
/// receives a raw stack trace (architecture line 476).</p>
///
/// <p><parameter>MutatesState=0</parameter> — passes the L2 read-only
/// gate so the dispatcher actually invokes us; this lets the safety
/// net catch fire.</p>
Class SessionAgent.Test.StubThrowingTool Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "test_throwing_tool";

Parameter Description As %String = "Test fixture — Invoke raises <UNDEFINED> to exercise Registry.Dispatch's outer Catch.";

Parameter MutatesState As %Boolean = 0;

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
    ; Provoke <UNDEFINED> deliberately — reading an undefined local.
    ; The reference to %Garbage triggers <UNDEFINED> at runtime; the
    ; registry's outer Catch must wrap this into an MCP error envelope.
    Set pResult = {}
    Set tX = %Garbage
    Quit $$$OK
}

}
