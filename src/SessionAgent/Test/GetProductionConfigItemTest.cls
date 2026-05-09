/// <p>Unit tests for
/// <CLASS>SessionAgent.Tool.Inspection.GetProductionConfigItem</CLASS>
/// — Story 13.3 AC-1 through AC-8. Tests use the live sample production
/// (<code>SessionAgent.Sample.Production</code>) — no fixture seeding
/// needed; SQL + %OpenId access verified in Task 0 pre-flight.</p>
///
/// <ol>
/// <li><b>TestPositiveItemFound</b> — AC-2: valid production + item returns
///   complete envelope with <code>class_name</code>, <code>enabled</code>,
///   <code>pool_size</code>, <code>render_strategy="ok"</code>.</li>
/// <li><b>TestEmptySettingsArraysReturned</b> — AC-3: live items with all
///   default settings return <code>host_settings=[]</code> and
///   <code>adapter_settings=[]</code>.</li>
/// <li><b>TestProductionNotFound</b> — AC-4: nonexistent production →
///   <code>render_strategy="production_not_found"</code>, no
///   <code>isError=1</code>.</li>
/// <li><b>TestItemNotFound</b> — AC-5: valid production + nonexistent item
///   → <code>render_strategy="item_not_found"</code>, no
///   <code>isError=1</code>.</li>
/// <li><b>TestStripLastSegmentAutoCorrects</b> — AC-6 happy: appending
///   method suffix auto-corrects; response has
///   <code>production_name_auto_corrected_from</code>.</li>
/// <li><b>TestStripLastSegmentStillNotFoundReturnsCandidateField</b> — AC-6
///   negative: totally nonexistent production with suffix →
///   <code>production_not_found</code> + <code>candidate_production_name</code>.</li>
/// <li><b>TestInputSchemaDescriptionsContainPassClassNameOnly</b> — AC-7:
///   both <code>production_name</code> and <code>config_item_name</code>
///   descriptions in <code>GetInputSchema()</code> contain
///   "Pass the class name only".</li>
/// <li><b>TestRegistryListToolsIncludesGetProductionConfigItem</b> — AC-1:
///   registry surfaces <code>get_production_config_item</code> with
///   non-empty Description.</li>
/// <li><b>TestMissingProductionNameReturnsError</b> — validation: missing
///   required field → <code>isError=1</code>.</li>
/// <li><b>TestMissingConfigItemNameReturnsError</b> — validation: missing
///   second required field → <code>isError=1</code>.</li>
/// </ol>
Class SessionAgent.Test.GetProductionConfigItemTest Extends %UnitTest.TestCase
{

Parameter SAMPLEPRODUCTION As %String = "SessionAgent.Sample.Production";

Parameter KNOWNITEM As %String = "SessionAgent.Sample.BP.OrderRouter";

Parameter KNOWNBO As %String = "SessionAgent.Sample.BO.FilePublish";

Parameter NONEXISTENTPRODUCTION As %String = "Nonexistent.Production.Never.Exists";

Parameter NONEXISTENTITEM As %String = "NoSuchConfigItem.Never.Exists";

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Build a CallerContext for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = 9799933
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-2 — valid production + item returns complete envelope with
/// expected fields populated and render_strategy="ok".</p>
Method TestPositiveItemFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"production_name": (..#SAMPLEPRODUCTION), "config_item_name": (..#KNOWNITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on valid item")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError is not 1 on success")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy='ok' on valid item")
    Do $$$AssertEquals(tSc.%Get("class_name"), ..#KNOWNITEM, "class_name matches the item class")
    Do $$$AssertEquals(tSc.%Get("production_name"), ..#SAMPLEPRODUCTION, "production_name echoed in response")
    Do $$$AssertEquals(tSc.%Get("config_item_name"), ..#KNOWNITEM, "config_item_name echoed in response")
    ; enabled and pool_size must be present
    Do $$$AssertTrue(tSc.%IsDefined("enabled"), "enabled field present in response")
    Do $$$AssertTrue(tSc.%IsDefined("pool_size"), "pool_size field present in response")
    Do $$$AssertEquals(tSc.%Get("enabled"), 1, "enabled=true for known active item")
    Do $$$AssertEquals(+tSc.%Get("pool_size"), 1, "pool_size=1 for known item")
    ; host_settings and adapter_settings must be arrays
    Do $$$AssertTrue($IsObject(tSc.%Get("host_settings")), "host_settings is array")
    Do $$$AssertTrue($IsObject(tSc.%Get("adapter_settings")), "adapter_settings is array")
    ; content[0].text must be non-empty operator summary
    Do $$$AssertTrue($Length(tResult.content.%Get(0).text) > 0, "content[0].text non-empty summary")
    Quit
}

/// <p>AC-3 — live items with default settings return both arrays as [].
/// Confirmed via Task 0: all 5 sample production items use defaults only.</p>
Method TestEmptySettingsArraysReturned()
{
    Set tCtx = ..BuildCtx()
    ; Use the FilePublish BO which has Comment populated and Settings=[]
    Set tArgs = {"production_name": (..#SAMPLEPRODUCTION), "config_item_name": (..#KNOWNBO)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on BO item")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Set tHostSettings = tSc.%Get("host_settings")
    Set tAdapterSettings = tSc.%Get("adapter_settings")
    Do $$$AssertTrue($IsObject(tHostSettings), "host_settings is array")
    Do $$$AssertTrue($IsObject(tAdapterSettings), "adapter_settings is array")
    Do $$$AssertEquals(tHostSettings.%Size(), 0, "host_settings=[] when item uses all defaults (AC-3)")
    Do $$$AssertEquals(tAdapterSettings.%Size(), 0, "adapter_settings=[] when item uses all defaults (AC-3)")
    Quit
}

/// <p>AC-4 — nonexistent production_name returns
/// render_strategy="production_not_found", no isError=1.</p>
Method TestProductionNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"production_name": (..#NONEXISTENTPRODUCTION), "config_item_name": (..#KNOWNITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on nonexistent production (not an error)")
    ; isError MUST NOT be 1
    Do $$$AssertNotEquals(+tResult.%Get("isError"), 1, "isError is not 1 on production_not_found (AC-4)")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "production_not_found", "render_strategy='production_not_found' (AC-4)")
    Do $$$AssertEquals(tSc.%Get("production_name"), ..#NONEXISTENTPRODUCTION, "production_name echoed")
    Quit
}

/// <p>AC-5 — valid production + nonexistent config_item_name returns
/// render_strategy="item_not_found", no isError=1.</p>
Method TestItemNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"production_name": (..#SAMPLEPRODUCTION), "config_item_name": (..#NONEXISTENTITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on nonexistent item (not an error)")
    ; isError MUST NOT be 1
    Do $$$AssertNotEquals(+tResult.%Get("isError"), 1, "isError is not 1 on item_not_found (AC-5)")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "item_not_found", "render_strategy='item_not_found' (AC-5)")
    Do $$$AssertEquals(tSc.%Get("production_name"), ..#SAMPLEPRODUCTION, "production_name echoed")
    Do $$$AssertEquals(tSc.%Get("config_item_name"), ..#NONEXISTENTITEM, "config_item_name echoed")
    Quit
}

/// <p>AC-6 happy path — appending ".OnRequest" to the production name
/// triggers strip-last-segment, which succeeds against the sample
/// production. Response carries production_name_auto_corrected_from.</p>
Method TestStripLastSegmentAutoCorrects()
{
    Set tCtx = ..BuildCtx()
    Set tBadProductionName = ..#SAMPLEPRODUCTION _ ".OnRequest"
    Set tArgs = {"production_name": (tBadProductionName), "config_item_name": (..#KNOWNITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for suffix-appended production name")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "ok", "render_strategy='ok' after auto-correction (AC-6)")
    Do $$$AssertEquals(tSc.%Get("production_name"), ..#SAMPLEPRODUCTION, "production_name = corrected (stripped) name")
    Do $$$AssertTrue(tSc.%IsDefined("production_name_auto_corrected_from"), "production_name_auto_corrected_from marker present (AC-6)")
    Do $$$AssertEquals(tSc.%Get("production_name_auto_corrected_from"), tBadProductionName, "production_name_auto_corrected_from = original input")
    Quit
}

/// <p>AC-6 negative — totally nonexistent multi-segment production with
/// suffix yields production_not_found envelope with
/// candidate_production_name field.</p>
Method TestStripLastSegmentStillNotFoundReturnsCandidateField()
{
    Set tCtx = ..BuildCtx()
    Set tBadName = "Totally.NonExistent.Production.FakeMethod"
    Set tArgs = {"production_name": (tBadName), "config_item_name": (..#KNOWNITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on still-missing production")
    Set tSc = tResult.structuredContent
    Do $$$AssertEquals(tSc.%Get("render_strategy"), "production_not_found", "render_strategy='production_not_found' after retry miss (AC-6)")
    Do $$$AssertTrue(tSc.%IsDefined("candidate_production_name"), "candidate_production_name field present on retry-miss (AC-6)")
    Do $$$AssertEquals(tSc.%Get("candidate_production_name"), "Totally.NonExistent.Production", "candidate_production_name = stripped last segment")
    Quit
}

/// <p>AC-7 — GetInputSchema() descriptions for both production_name and
/// config_item_name contain "Pass the class name only".</p>
Method TestInputSchemaDescriptionsContainPassClassNameOnly()
{
    Set tSchema = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).GetInputSchema()
    Do $$$AssertTrue($IsObject(tSchema), "GetInputSchema returns an object")
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")

    ; production_name description
    Set tProdNameProp = tProps.%Get("production_name")
    Do $$$AssertTrue($IsObject(tProdNameProp), "schema.properties.production_name is defined")
    Set tProdDesc = tProdNameProp.%Get("description")
    Do $$$AssertTrue(tProdDesc [ "Pass the class name only", "production_name description contains 'Pass the class name only' (AC-7) — got: '" _ tProdDesc _ "'")

    ; config_item_name description
    Set tItemNameProp = tProps.%Get("config_item_name")
    Do $$$AssertTrue($IsObject(tItemNameProp), "schema.properties.config_item_name is defined")
    Set tItemDesc = tItemNameProp.%Get("description")
    Do $$$AssertTrue(tItemDesc [ "Pass the class name only", "config_item_name description contains 'Pass the class name only' (AC-7) — got: '" _ tItemDesc _ "'")
    Quit
}

/// <p>AC-1 — registry surfaces get_production_config_item with non-empty
/// Description and correct schema shape.</p>
Method TestRegistryListToolsIncludesGetProductionConfigItem()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")

    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tE) {
        If tE.%Get("name") = "get_production_config_item" {
            Set tFound = 1
            Set tEntry = tE
            Quit
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'get_production_config_item' (AC-1)")

    If $IsObject(tEntry) {
        Set tDesc = tEntry.%Get("description")
        Do $$$AssertNotEquals(tDesc, "", "get_production_config_item has non-empty description (AC-1) — got: '" _ tDesc _ "'")
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "get_production_config_item input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 2, "schema.required has exactly 2 entries")
        ; required array must contain both production_name and config_item_name
        Set tRequiredStr = ""
        Set tReqIter = tRequired.%GetIterator()
        While tReqIter.%GetNext(.tRK, .tRV) {
            Set tRequiredStr = tRequiredStr _ "," _ tRV _ ","
        }
        Do $$$AssertTrue(tRequiredStr [ ",production_name,", "schema.required contains 'production_name'")
        Do $$$AssertTrue(tRequiredStr [ ",config_item_name,", "schema.required contains 'config_item_name'")
    }
    Quit
}

/// <p>Validation — missing required production_name returns isError=1.</p>
Method TestMissingProductionNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"config_item_name": (..#KNOWNITEM)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing production_name")
    Set tText = tResult.content.%Get(0).text
    Do $$$AssertTrue(tText [ "missing production_name", "error text mentions 'missing production_name' — got: '" _ tText _ "'")
    Quit
}

/// <p>Validation — missing required config_item_name returns isError=1.</p>
Method TestMissingConfigItemNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"production_name": (..#SAMPLEPRODUCTION)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetProductionConfigItem).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on validation failure (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing config_item_name")
    Set tText = tResult.content.%Get(0).text
    Do $$$AssertTrue(tText [ "missing config_item_name", "error text mentions 'missing config_item_name' — got: '" _ tText _ "'")
    Quit
}

}
