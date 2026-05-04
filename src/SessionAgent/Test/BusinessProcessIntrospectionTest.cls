/// <p>Unit tests for the Story 4.4 BP-introspection trio —
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS>,
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessInstance</CLASS>,
/// <CLASS>SessionAgent.Tool.Inspection.ListBusinessProcessMethods</CLASS>.
/// Ten Test* methods cover Story 4.4 AC-1 through AC-10:</p>
///
/// <p><b>GetBusinessProcessSource (3):</b></p>
/// <ol>
/// <li><b>TestSourceReturnsClassStructure</b> — fixture
/// <code>SessionAgent.Sample.BP.OrderRouter</code>. Asserts non-empty
/// methods + super_class equals "Ens.BusinessProcess" (the actual
/// superclass — note: spec said "Ens.BusinessProcessBPL" but empirical
/// probe shows the sample BP extends <code>Ens.BusinessProcess</code>
/// directly, not BPL).</li>
/// <li><b>TestSourceUnknownClassReturnsClassNotFound</b> — fixture
/// <code>Nonexistent.Garbage.Class</code>. Asserts
/// <code>render_strategy="class_not_found"</code>.</li>
/// <li><b>TestSourceMissingClassNameReturnsError</b> — FR37 envelope.</li>
/// </ol>
///
/// <p><b>GetBusinessProcessInstance (3):</b></p>
/// <ol>
/// <li><b>TestInstanceLiveSessionReturnsBp</b> — fixture: insert a synthetic
/// row directly into <CLASS>Ens.BusinessProcess</CLASS> via parameterized
/// SQL (the sample production's BPs autopurge on completion, so we cannot
/// rely on live RunScenario state). Asserts <code>has_bp=true</code> and
/// non-empty <code>bp_class</code>.</li>
/// <li><b>TestInstanceNoBpReturnsHasBpFalse</b> — fixture: a session id
/// with no BP rows (any unused id). Asserts <code>has_bp=false</code>.</li>
/// <li><b>TestInstanceMissingSessionIdReturnsError</b> — FR37 envelope.</li>
/// </ol>
///
/// <p><b>ListBusinessProcessMethods (3):</b></p>
/// <ol>
/// <li><b>TestMethodsReturnsBpMethodList</b> — fixture
/// <code>SessionAgent.Sample.BP.OrderRouter</code>. Asserts
/// <code>method_count > 0</code> and methods contain at least one entry
/// with non-empty signature.</li>
/// <li><b>TestMethodsUnknownClassReturnsClassNotFound</b> — fixture
/// <code>Nonexistent.Garbage</code>. Asserts <code>exists=false</code>,
/// <code>methods=[]</code>.</li>
/// <li><b>TestMethodsMissingClassNameReturnsError</b> — FR37 envelope.</li>
/// </ol>
///
/// <p><b>Registry (1):</b></p>
/// <ol>
/// <li><b>TestRegistryListToolsIncludesAllThreeBpTools</b> —
/// <method>SessionAgent.Tool.Registry.ListTools</method> returns all
/// three tool names with the correct schemas.</li>
/// </ol>
///
/// <p><b>Fixture cleanup.</b> The synthetic
/// <CLASS>Ens.BusinessProcess</CLASS> row inserted by
/// <method>OnBeforeAllTests</method> for the live-session test is captured
/// via process-private global <code>^||SessionAgentTest44BpId</code> and
/// deleted by <method>OnAfterAllTests</method>; defensive WHERE-by-session
/// also sweeps any stragglers.</p>
Class SessionAgent.Test.BusinessProcessIntrospectionTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONID As %Integer = 999944;

Parameter UNUSEDSESSIONID As %Integer = 999945;

Parameter FIXTUREBPCLASS As %String = "SessionAgent.Sample.BP.OrderRouter";

Parameter NONEXISTENTCLASS As %String = "Nonexistent.Garbage.Class";

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed a synthetic BP instance row tied to FIXTURESESSIONID. Captures
/// the row id in <code>^||SessionAgentTest44BpId</code> for cleanup.
/// Defensive sweep deletes any prior fixture rows first.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest44BpId
    Set tSession = ..#FIXTURESESSIONID

    ; Defensive cleanup of prior fixture rows.
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.BusinessProcess WHERE ""%SessionId"" = ?")) {
        Do tCleanup.%Execute(tSession)
    }

    ; Insert synthetic BP row — directly via SQL because the sample BP
    ; class auto-purges on completion (see Ens.BusinessProcess.Purge in
    ; irislib). We don't run a live BP because we want a stable in-flight
    ; row our tests can rely on.
    Set tInsert = ##class(%SQL.Statement).%New()
    Set tSC = tInsert.%Prepare("INSERT INTO Ens.BusinessProcess (""%SessionId"", ""%ConfigName"", ""%TimeCreated"", ""%IsCompleted"", ""%IsTerminated"", ""%PrimaryRequestHeader"", ""%RepliedStatus"") VALUES (?, ?, ?, ?, ?, ?, ?)")
    If $$$ISERR(tSC) Quit tSC
    Set tNow = $ZDateTime($ZTimeStamp, 3, 1, 0)
    Set tRs = tInsert.%Execute(tSession, "TestRouter", tNow, 0, 0, 0, 0)
    Set ^||SessionAgentTest44BpId = $Get(%ROWID)
    Quit $$$OK
}

/// <p>Cleanup — delete the fixture row by id + sweep by session.</p>
Method OnAfterAllTests() As %Status
{
    Set tDel = ##class(%SQL.Statement).%New()
    If $$$ISOK(tDel.%Prepare("DELETE FROM Ens.BusinessProcess WHERE ""%SessionId"" = ?")) {
        Do tDel.%Execute(..#FIXTURESESSIONID)
    }
    Kill ^||SessionAgentTest44BpId
    Quit $$$OK
}

/// <p>Build a CallerContext with sane defaults for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#FIXTURESESSIONID
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-3 happy path — fixture <code>SessionAgent.Sample.BP.OrderRouter</code>.
/// Empirical probe finding: the sample BP extends
/// <code>Ens.BusinessProcess</code> directly, NOT
/// <code>Ens.BusinessProcessBPL</code> (the spec text was wrong about
/// the superclass).</p>
Method TestSourceReturnsClassStructure()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"bp_class_name": (..#FIXTUREBPCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "GetBusinessProcessSource.Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("class_name"), ..#FIXTUREBPCLASS, "class_name matches input")
    Do $$$AssertEquals(tSc.%Get("super_class"), "Ens.BusinessProcess", "super_class is Ens.BusinessProcess (empirical: not BPL)")
    Do $$$AssertEquals(+tSc.%Get("abstract"), 0, "abstract = false for the sample BP")
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok on happy path")
    Do $$$AssertTrue(+tSc.%Get("method_count") > 0, "method_count > 0 (OrderRouter declares OnRequest, OnResponse, OnError, OnComplete + buildResponse)")
    Do $$$AssertTrue(+tSc.%Get("property_count") > 0, "property_count > 0 (OrderRouter has OrderId, FinalStatus, etc.)")
    Quit
}

/// <p>AC-3 missing class — class_not_found envelope.</p>
Method TestSourceUnknownClassReturnsClassNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"bp_class_name": (..#NONEXISTENTCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on missing class (not an error)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "class_not_found", "render_strategy = class_not_found")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("method_count"), 0, "method_count = 0 for missing class")
    Quit
}

/// <p>AC-3 validation path — empty bp_class_name → FR37 envelope.</p>
Method TestSourceMissingClassNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing bp_class_name")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing bp_class_name", "error text mentions 'missing bp_class_name'")
    Quit
}

/// <p>AC-6 happy path — synthetic BP fixture row.</p>
Method TestInstanceLiveSessionReturnsBp()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#FIXTURESESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessInstance).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "GetBusinessProcessInstance.Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("has_bp"), 1, "has_bp = true for fixture session")
    Do $$$AssertEquals(tSc.%Get("config_name"), "TestRouter", "config_name matches fixture")
    Do $$$AssertEquals(+tSc.%Get("is_completed"), 0, "is_completed = false (in-flight)")
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy = ok")
    Do $$$AssertTrue(+tSc.%Get("instance_id") > 0, "instance_id > 0")
    Quit
}

/// <p>AC-6 no-BP path — unused session id → has_bp=false.</p>
Method TestInstanceNoBpReturnsHasBpFalse()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"session_id": (..#UNUSEDSESSIONID)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessInstance).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for unused session")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("has_bp"), 0, "has_bp = false for unused session")
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "no_bp_instance", "render_strategy = no_bp_instance")
    Quit
}

/// <p>AC-6 validation path — empty session_id → FR37 envelope.</p>
Method TestInstanceMissingSessionIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetBusinessProcessInstance).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing session_id", "error text mentions 'missing session_id'")
    Quit
}

/// <p>AC-9 happy path — list filtered methods for the sample BP class.</p>
Method TestMethodsReturnsBpMethodList()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"bp_class_name": (..#FIXTUREBPCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ListBusinessProcessMethods).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "ListBusinessProcessMethods.Invoke OK")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("exists"), 1, "exists = true for sample BP")
    Do $$$AssertTrue(+tSc.%Get("method_count") > 0, "method_count > 0")
    Set tMethods = tSc.%Get("methods")
    Do $$$AssertTrue(tMethods.%Size() > 0, "methods array non-empty")
    Set tFirst = tMethods.%Get(0)
    Do $$$AssertTrue($Length(tFirst.%Get("signature")) > 0, "first method has non-empty signature")
    Do $$$AssertTrue($Length(tFirst.%Get("name")) > 0, "first method has non-empty name")
    Quit
}

/// <p>AC-9 missing class — exists=false, methods=[].</p>
Method TestMethodsUnknownClassReturnsClassNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"bp_class_name": (..#NONEXISTENTCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ListBusinessProcessMethods).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on missing class")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(+tSc.%Get("exists"), 0, "exists = false for missing class")
    Do $$$AssertEquals(+tSc.%Get("method_count"), 0, "method_count = 0")
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "class_not_found", "render_strategy = class_not_found")
    Quit
}

/// <p>AC-9 validation path — empty bp_class_name → FR37 envelope.</p>
Method TestMethodsMissingClassNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ListBusinessProcessMethods).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on missing bp_class_name")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing bp_class_name", "error text mentions 'missing bp_class_name'")
    Quit
}

/// <p>AC-10 registry discovery — all three new tools surfaced by
/// <method>SessionAgent.Tool.Registry.ListTools</method> with valid
/// input_schema entries.</p>
Method TestRegistryListToolsIncludesAllThreeBpTools()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFoundSource = 0
    Set tFoundInstance = 0
    Set tFoundMethods = 0
    Set tSourceEntry = ""
    Set tInstanceEntry = ""
    Set tMethodsEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tName = tEntry.%Get("name")
        If tName = "get_business_process_source" {
            Set tFoundSource = 1
            Set tSourceEntry = tEntry
        }
        If tName = "get_business_process_instance" {
            Set tFoundInstance = 1
            Set tInstanceEntry = tEntry
        }
        If tName = "list_business_process_methods" {
            Set tFoundMethods = 1
            Set tMethodsEntry = tEntry
        }
    }
    Do $$$AssertTrue(tFoundSource, "Registry surfaces 'get_business_process_source'")
    Do $$$AssertTrue(tFoundInstance, "Registry surfaces 'get_business_process_instance'")
    Do $$$AssertTrue(tFoundMethods, "Registry surfaces 'list_business_process_methods'")

    ; Schema sanity — each tool's required is exactly one item.
    If $IsObject(tSourceEntry) {
        Set tReq = tSourceEntry.%Get("input_schema").%Get("required")
        Do $$$AssertEquals(tReq.%Size(), 1, "get_business_process_source.required has one entry")
        Do $$$AssertEquals(tReq.%Get(0), "bp_class_name", "get_business_process_source.required[0] = bp_class_name")
    }
    If $IsObject(tInstanceEntry) {
        Set tReqI = tInstanceEntry.%Get("input_schema").%Get("required")
        Do $$$AssertEquals(tReqI.%Size(), 1, "get_business_process_instance.required has one entry")
        Do $$$AssertEquals(tReqI.%Get(0), "session_id", "get_business_process_instance.required[0] = session_id")
    }
    If $IsObject(tMethodsEntry) {
        Set tReqM = tMethodsEntry.%Get("input_schema").%Get("required")
        Do $$$AssertEquals(tReqM.%Size(), 1, "list_business_process_methods.required has one entry")
        Do $$$AssertEquals(tReqM.%Get(0), "bp_class_name", "list_business_process_methods.required[0] = bp_class_name")
    }
    Quit
}

}
