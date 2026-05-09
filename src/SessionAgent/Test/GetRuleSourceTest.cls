/// <p>Unit tests for <CLASS>SessionAgent.Tool.Inspection.GetRuleSource</CLASS>
/// — Story 13.2 AC-1 through AC-8. Tests cover:</p>
///
/// <ol>
/// <li><b>TestRuleXmlReturned</b> — AC-2: fixture class returns non-empty
///   <code>rule_xml</code> containing <code>&lt;ruleDefinition</code>.</li>
/// <li><b>TestParseConstraintsTrueReturnsConstraints</b> — AC-3: with default
///   <code>parse_constraints</code> (true), response includes <code>rule_count &gt; 0</code>
///   and <code>constraints</code> array with <code>name</code>, <code>when</code>,
///   <code>action</code> fields.</li>
/// <li><b>TestParseConstraintsFalseReturnsRawOnly</b> — AC-4: with
///   <code>parse_constraints=false</code>, <code>rule_count=0</code> and
///   <code>constraints=[]</code>.</li>
/// <li><b>TestClassNotFoundReturnsClassNotFoundEnvelope</b> — AC-5: nonexistent
///   class returns <code>render_strategy="class_not_found"</code>, no
///   <code>isError=1</code>.</li>
/// <li><b>TestStripLastSegmentAutoCorrects</b> — AC-6: appending a method suffix
///   auto-corrects to the fixture class; response carries
///   <code>rule_class_auto_corrected_from</code>.</li>
/// <li><b>TestStripLastSegmentStillNotFoundReturnsCandidateField</b> — AC-6
///   negative: totally nonexistent class with suffix yields class_not_found +
///   <code>candidate_rule_class</code> field.</li>
/// <li><b>TestInputSchemaDescriptionContainsPassClassNameOnly</b> — AC-7:
///   <code>GetInputSchema()</code> <code>properties.rule_class.description</code>
///   contains "Pass the class name only".</li>
/// <li><b>TestRegistryListToolsIncludesGetRuleSource</b> — AC-1: registry
///   surfaces <code>get_rule_source</code> with non-empty Description.</li>
/// </ol>
///
/// <p><b>Fixture strategy.</b> HSCUSTOM has no native rule classes with
/// RuleDefinition XData (confirmed by Task 0 probe). The fixture class
/// <CLASS>SessionAgent.Test.Fixture.SampleRule</CLASS> is compiled in
/// <method>OnBeforeAllTests</method> before tests run. No fixture data is
/// persisted to SQL tables — XData is read from the compiled class dictionary
/// and requires no teardown beyond the class existing.</p>
Class SessionAgent.Test.GetRuleSourceTest Extends %UnitTest.TestCase
{

Parameter FIXTURECLASS As %String = "SessionAgent.Test.Fixture.SampleRule";

Parameter NONEXISTENTCLASS As %String = "Nonexistent.Garbage.RuleClass";

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Compile the fixture class before any tests run so
/// <code>%Dictionary.XDataDefinition</code> can find its RuleDefinition
/// block. The VSCode ObjectScript extension auto-syncs on save, but we
/// compile here as a safety net for non-VSCode environments.</p>
Method OnBeforeAllTests() As %Status
{
    Set tSC = $System.OBJ.Compile(..#FIXTURECLASS, "ck")
    If $$$ISERR(tSC) {
        ; Non-fatal: class may already be compiled; proceed and let test assertions fail naturally.
        Set tSC = $$$OK
    }
    Quit tSC
}

/// <p>Build a CallerContext for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = 999132
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-2 happy path — fixture class returns non-empty rule_xml
/// containing the expected root element tag.</p>
Method TestRuleXmlReturned()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"rule_class": (..#FIXTURECLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "GetRuleSource.Invoke returns $$$OK on fixture class")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok on fixture class")
    Set tXml = tSc.%Get("rule_xml")
    Do $$$AssertTrue($Length(tXml) > 0, "rule_xml is non-empty")
    Do $$$AssertTrue(tXml [ "<ruleDefinition", "rule_xml contains '<ruleDefinition'")
    Quit
}

/// <p>AC-3 — parse_constraints=true (default): rule_count &gt; 0 and
/// constraints array entries have name, when, action fields.</p>
Method TestParseConstraintsTrueReturnsConstraints()
{
    Set tCtx = ..BuildCtx()
    ; Omit parse_constraints — should default to true
    Set tArgs = {"rule_class": (..#FIXTURECLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok")
    Do $$$AssertTrue(+tSc.%Get("rule_count") > 0, "rule_count > 0 with parse_constraints default true")
    Set tConstraints = tSc.%Get("constraints")
    Do $$$AssertTrue($IsObject(tConstraints), "constraints is an array")
    Do $$$AssertTrue(tConstraints.%Size() > 0, "constraints array is non-empty")
    ; Each entry must have name, when, action
    Set tFirst = tConstraints.%Get(0)
    Do $$$AssertTrue($IsObject(tFirst), "constraints[0] is an object")
    Do $$$AssertTrue(tFirst.%IsDefined("name"), "constraints[0].name is defined")
    Do $$$AssertTrue(tFirst.%IsDefined("when"), "constraints[0].when is defined")
    Do $$$AssertTrue(tFirst.%IsDefined("action"), "constraints[0].action is defined")
    ; Verify the fixture's rule name surfaced
    Do $$$AssertEquals(tFirst.%Get("name"), "test-rule-1", "constraints[0].name = 'test-rule-1'")
    ; action must contain 'send' or 'return'
    Set tAction = tFirst.%Get("action")
    Do $$$AssertTrue((tAction [ "send") || (tAction [ "return"), "constraints[0].action is 'send ...' or 'return'")
    ; The fixture has 1 rule but 2 actions (send + return), so constraints.%Size() >= rule_count
    Do $$$AssertTrue(tConstraints.%Size() >= +tSc.%Get("rule_count"), "constraints.%Size() >= rule_count (one rule can yield multiple actions)")
    Quit
}

/// <p>AC-4 — parse_constraints=false: constraints=[] and rule_count=0
/// (raw XML only, cheaper for context budget).</p>
Method TestParseConstraintsFalseReturnsRawOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"rule_class": (..#FIXTURECLASS), "parse_constraints": false}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK with parse_constraints=false")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok")
    Do $$$AssertEquals(+tSc.%Get("rule_count"), 0, "rule_count = 0 when parse_constraints=false")
    Set tConstraints = tSc.%Get("constraints")
    Do $$$AssertTrue($IsObject(tConstraints), "constraints is an array when parse_constraints=false")
    Do $$$AssertEquals(tConstraints.%Size(), 0, "constraints is empty when parse_constraints=false")
    ; rule_xml should still be populated even with parse_constraints=false
    Set tXml = tSc.%Get("rule_xml")
    Do $$$AssertTrue($Length(tXml) > 0, "rule_xml is still populated when parse_constraints=false")
    Quit
}

/// <p>AC-5 — nonexistent class returns class_not_found envelope, no isError=1.</p>
Method TestClassNotFoundReturnsClassNotFoundEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"rule_class": (..#NONEXISTENTCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on nonexistent class (not an error)")
    ; isError must NOT be 1
    Do $$$AssertNotEquals(+tResult.%Get("isError"), 1, "isError is not 1 on class_not_found")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "class_not_found", "render_strategy = class_not_found")
    Do $$$AssertEquals(tSc.%Get("rule_xml"), "", "rule_xml = '' on class_not_found")
    Do $$$AssertEquals(+tSc.%Get("rule_count"), 0, "rule_count = 0 on class_not_found")
    Set tConstraints = tSc.%Get("constraints")
    Do $$$AssertTrue($IsObject(tConstraints), "constraints is an array on class_not_found")
    Do $$$AssertEquals(tConstraints.%Size(), 0, "constraints is empty on class_not_found")
    Quit
}

/// <p>AC-6 happy path — appending ".FakeMethodName" to the fixture class
/// triggers strip-last-segment, which succeeds. Response carries
/// <code>rule_class_auto_corrected_from</code>.</p>
Method TestStripLastSegmentAutoCorrects()
{
    Set tCtx = ..BuildCtx()
    Set tBadName = ..#FIXTURECLASS _ ".FakeMethodName"
    Set tArgs = {"rule_class": (tBadName)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK for suffix-appended class name")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok after auto-correction")
    Do $$$AssertEquals(tSc.%Get("rule_class"), ..#FIXTURECLASS, "rule_class = corrected (stripped) name")
    Do $$$AssertTrue(tSc.%IsDefined("rule_class_auto_corrected_from"), "rule_class_auto_corrected_from marker present")
    Do $$$AssertEquals(tSc.%Get("rule_class_auto_corrected_from"), tBadName, "rule_class_auto_corrected_from = original input")
    Do $$$AssertTrue($Length(tSc.%Get("rule_xml")) > 0, "rule_xml non-empty after auto-correction")
    Quit
}

/// <p>AC-6 negative — totally nonexistent multi-segment class yields
/// class_not_found envelope with <code>candidate_rule_class</code> field.</p>
Method TestStripLastSegmentStillNotFoundReturnsCandidateField()
{
    Set tCtx = ..BuildCtx()
    Set tBadName = "Totally.NonExistent.Rule.Name"
    Set tArgs = {"rule_class": (tBadName)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK on still-missing class")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "class_not_found", "render_strategy = class_not_found after retry miss")
    Do $$$AssertEquals(tSc.%Get("rule_class"), tBadName, "rule_class = original input (preserved)")
    Do $$$AssertTrue(tSc.%IsDefined("candidate_rule_class"), "candidate_rule_class field present on retry-miss")
    Do $$$AssertEquals(tSc.%Get("candidate_rule_class"), "Totally.NonExistent.Rule", "candidate_rule_class = stripped last segment")
    Quit
}

/// <p>AC-7 — GetInputSchema() returns a description for rule_class that
/// contains "Pass the class name only".</p>
Method TestInputSchemaDescriptionContainsPassClassNameOnly()
{
    Set tSchema = ##class(SessionAgent.Tool.Inspection.GetRuleSource).GetInputSchema()
    Do $$$AssertTrue($IsObject(tSchema), "GetInputSchema returns an object")
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")
    Set tRuleClassProp = tProps.%Get("rule_class")
    Do $$$AssertTrue($IsObject(tRuleClassProp), "schema.properties.rule_class is defined")
    Set tDesc = tRuleClassProp.%Get("description")
    Do $$$AssertTrue(tDesc [ "Pass the class name only", "rule_class description contains 'Pass the class name only' (got: '" _ tDesc _ "')")
    Quit
}

/// <p>AC-1 — registry surfaces <code>get_rule_source</code> with non-empty
/// Description and correct schema shape.</p>
Method TestRegistryListToolsIncludesGetRuleSource()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")

    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tE) {
        If tE.%Get("name") = "get_rule_source" {
            Set tFound = 1
            Set tEntry = tE
            Quit
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'get_rule_source'")

    If $IsObject(tEntry) {
        Set tDesc = tEntry.%Get("description")
        Do $$$AssertNotEquals(tDesc, "", "get_rule_source has non-empty description (got: '" _ tDesc _ "')")

        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "get_rule_source input_schema is an object")

        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "schema.required has exactly 1 entry")
        Do $$$AssertEquals(tRequired.%Get(0), "rule_class", "schema.required[0]='rule_class'")

        Do $$$AssertEquals(+tSchema.%Get("additionalProperties"), 0, "additionalProperties=false")
    }
    Quit
}

/// <p>Validation path — missing required <code>rule_class</code> returns
/// <code>isError=1</code>.</p>
Method TestMissingRuleClassReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetRuleSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing rule_class")
    Set tText = tResult.content.%Get(0).text
    Do $$$AssertTrue(tText [ "missing rule_class", "error text mentions 'missing rule_class' (got: '" _ tText _ "')")
    Quit
}

}
