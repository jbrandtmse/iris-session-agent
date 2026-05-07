/// <p>Story 8.2 test fixture — concrete subclass of
/// <CLASS>SessionAgent.Tool.Search.Base</CLASS> used by
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> as a
/// negative-control. Returns an EMPTY indexed-column list, simulating a
/// future search-tool author who forgot to declare any indexed lead
/// columns. The invariant test asserts that this fixture WOULD be
/// rejected by the production discovery loop — the assertion confirms
/// the rejection logic itself fires.</p>
///
/// <p><b>Namespace placement.</b> Lives under
/// <code>SessionAgent.Test.Fixture.*</code> so it does NOT pollute the
/// production <code>SessionAgent.Tool.Search.*</code> namespace and is
/// excluded by the discovery loop's namespace filter.</p>
///
/// <p><parameter>MutatesState=0</parameter> — read-only stub.
/// <method>GetInputSchema</method> returns an empty object.
/// <method>Invoke</method> returns a fixed MCP success envelope. Neither
/// is exercised by the invariant test; both exist so the class
/// compiles.</p>
Class SessionAgent.Test.Fixture.StubUnboundedSearchTool Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "test_unbounded_search_stub";

Parameter Description As %String = "Story 8.2 fixture — negative-control unbounded-WHERE search-tool stub.";

Parameter MutatesState As %Boolean = 0;

/// <p>Negative-control — returns an EMPTY array. The invariant test
/// loop would treat this as a violation of the bounded-WHERE invariant
/// (no indexed lead columns declared) and reject the tool.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit []
}

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
    Set pResult = {
        "content": [{"type":"text", "text":"stub-unbounded-search ok"}],
        "structuredContent": {"stub": "unbounded-search"}
    }
    Quit $$$OK
}

}
