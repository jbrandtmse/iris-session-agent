/// <p>Story 8.2 test fixture — concrete subclass of
/// <CLASS>SessionAgent.Tool.Search.Base</CLASS> used by
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> as a
/// positive-control. Returns a known indexed-column list
/// (<code>["TimeCreated", "Status"]</code>) so the invariant test can
/// verify <method>BuildBoundedWhereClause</method> emits the expected
/// fragment without depending on any production search tool (none ship
/// until Story 8.3).</p>
///
/// <p><b>Namespace placement.</b> Lives under
/// <code>SessionAgent.Test.Fixture.*</code> so it does NOT pollute the
/// production <code>SessionAgent.Tool.Search.*</code> namespace and is
/// excluded by the discovery loop's namespace filter (analogous to the
/// Story 3.0 <code>SessionAgent.Test.*</code> exclusion in
/// <method>SessionAgent.Tool.Registry.ListTools</method>).</p>
///
/// <p><parameter>MutatesState=0</parameter> — read-only stub.
/// <method>GetInputSchema</method> returns an empty object.
/// <method>Invoke</method> returns a fixed MCP success envelope. Neither
/// is exercised by the invariant test; both exist so the class
/// compiles.</p>
Class SessionAgent.Test.Fixture.StubBoundedSearchTool Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "test_bounded_search_stub";

Parameter Description As %String = "Story 8.2 fixture — positive-control bounded-WHERE search-tool stub.";

Parameter MutatesState As %Boolean = 0;

/// <p>Positive-control — returns two columns from the documented
/// Ens.MessageHeader indexed set (<code>TimeCreated</code>,
/// <code>Status</code>). The invariant test verifies that intersection
/// with the indexed-set list is non-empty.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["TimeCreated", "Status"]
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
        "content": [{"type":"text", "text":"stub-bounded-search ok"}],
        "structuredContent": {"stub": "bounded-search"}
    }
    Quit $$$OK
}

}
