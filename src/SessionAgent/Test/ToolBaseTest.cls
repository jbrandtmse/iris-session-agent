/// <p>Unit tests for <CLASS>SessionAgent.Tool.Base</CLASS> — the
/// abstract-base contract shipped by Story 2.10.</p>
///
/// <p>Three Test* methods cover Story 2.10 AC-1:</p>
/// <ol>
/// <li><b>TestToolBaseHasExpectedClassParameters</b> — declares the
/// three Class Parameters (<parameter>ToolName</parameter>,
/// <parameter>Description</parameter>, <parameter>MutatesState</parameter>)
/// with the expected types and default values.</li>
/// <li><b>TestAbstractMethodsHaveCurlyBodies</b> — both
/// <method>GetInputSchema</method> and <method>Invoke</method> are
/// declared <code>[Abstract]</code> AND have curly-brace bodies (per
/// project rule §"Abstract Methods in ObjectScript" — abstract methods
/// MUST have bodies even though concrete subclasses always override).</li>
/// <li><b>TestStubSubclassConcreteCallable</b> — the
/// <CLASS>SessionAgent.Test.StubReadOnlyTool</CLASS> fixture overrides
/// both abstract methods correctly and is callable directly via
/// <code>$ClassMethod</code>.</li>
/// </ol>
Class SessionAgent.Test.ToolBaseTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts <code>initvalue</code> from
/// <CLASS>%UnitTest.TestCase</CLASS> and forwards via <code>##super</code>
/// (project rule §"Critical Constructor Requirements"). No
/// <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-1 — Verify the three Class Parameters are declared on
/// <CLASS>SessionAgent.Tool.Base</CLASS> with the expected default values.</p>
Method TestToolBaseHasExpectedClassParameters()
{
    Set tToolNameParam = ##class(%Dictionary.ParameterDefinition).%OpenId("SessionAgent.Tool.Base||ToolName")
    Do $$$AssertTrue($IsObject(tToolNameParam), "ToolName parameter row exists in %Dictionary.ParameterDefinition")
    Do $$$AssertEquals(tToolNameParam.Default, "", "ToolName default is empty string")
    Do $$$AssertEquals(tToolNameParam.Type, "%String", "ToolName declared as %String")

    Set tDescParam = ##class(%Dictionary.ParameterDefinition).%OpenId("SessionAgent.Tool.Base||Description")
    Do $$$AssertTrue($IsObject(tDescParam), "Description parameter row exists")
    Do $$$AssertEquals(tDescParam.Default, "", "Description default is empty string")
    Do $$$AssertEquals(tDescParam.Type, "%String", "Description declared as %String")

    Set tMutatesParam = ##class(%Dictionary.ParameterDefinition).%OpenId("SessionAgent.Tool.Base||MutatesState")
    Do $$$AssertTrue($IsObject(tMutatesParam), "MutatesState parameter row exists")
    Do $$$AssertEquals(tMutatesParam.Default, 0, "MutatesState default is 0 (read-only)")
    Do $$$AssertEquals(tMutatesParam.Type, "%Boolean", "MutatesState declared as %Boolean")
    Quit
}

/// <p>AC-1 — Verify both abstract methods are declared
/// <code>[Abstract]</code> AND have non-empty bodies (the curly-brace
/// requirement of project rule §"Abstract Methods in ObjectScript").
/// The implicit second guarantee is that the class compiles at all —
/// if either body were missing or wrong, the class would fail to
/// compile and this test class would not load.</p>
Method TestAbstractMethodsHaveCurlyBodies()
{
    Set tGetSchema = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Tool.Base||GetInputSchema")
    Do $$$AssertTrue($IsObject(tGetSchema), "GetInputSchema method row exists")
    Do $$$AssertEquals(tGetSchema.Abstract, 1, "GetInputSchema is declared [Abstract]")
    Do $$$AssertEquals(tGetSchema.ReturnType, "%DynamicObject", "GetInputSchema returns %DynamicObject")
    Do $$$AssertNotEquals(tGetSchema.Implementation.Size, 0, "GetInputSchema has a non-empty body (curly-brace requirement)")

    Set tInvoke = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Tool.Base||Invoke")
    Do $$$AssertTrue($IsObject(tInvoke), "Invoke method row exists")
    Do $$$AssertEquals(tInvoke.Abstract, 1, "Invoke is declared [Abstract]")
    Do $$$AssertEquals(tInvoke.ReturnType, "%Status", "Invoke returns %Status")
    Do $$$AssertNotEquals(tInvoke.Implementation.Size, 0, "Invoke has a non-empty body (curly-brace requirement)")
    Quit
}

/// <p>AC-1 — Verify the <CLASS>SessionAgent.Test.StubReadOnlyTool</CLASS>
/// fixture (a) overrides the three Class Parameters, (b) overrides the
/// two abstract methods with usable concrete bodies, and (c) returns
/// the expected MCP envelope shape on direct invocation.</p>
Method TestStubSubclassConcreteCallable()
{
    ; (a) Class parameters present on the stub
    Do $$$AssertEquals(##class(SessionAgent.Test.StubReadOnlyTool).#ToolName, "test_readonly_tool", "Stub ToolName overridden")
    Do $$$AssertEquals(##class(SessionAgent.Test.StubReadOnlyTool).#MutatesState, 0, "Stub MutatesState=0")

    ; (b) GetInputSchema returns a usable %DynamicObject with the locked subset
    Set tSchema = ##class(SessionAgent.Test.StubReadOnlyTool).GetInputSchema()
    Do $$$AssertTrue($IsObject(tSchema), "GetInputSchema returns an object")
    Do $$$AssertEquals(tSchema.type, "object", "Schema type=object")
    Do $$$AssertEquals(tSchema.additionalProperties, 0, "Schema additionalProperties=false (locked subset)")

    ; (c) Invoke returns OK and populates pResult with the MCP success envelope
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = "test-id-1"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Set tArgs = {"echo": "hello"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Test.StubReadOnlyTool).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Stub Invoke returns OK")
    Do $$$AssertTrue($IsObject(tResult), "pResult populated as object")
    Do $$$AssertEquals(tResult.content.%Get(0).text, "ok", "Stub returns content[0].text='ok'")
    Do $$$AssertEquals(tResult.structuredContent.stub, "readonly", "Stub returns structuredContent.stub='readonly'")
    Quit
}

}
