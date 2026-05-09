/// <p>Unit tests for <CLASS>SessionAgent.Tool.Inspection.GetQueueState</CLASS>
/// — Story 13.4 AC-1 through AC-6. Tests cover:</p>
///
/// <ol>
/// <li><b>TestAbsentQueueReturnsZeroState</b> — AC-3: a queue name that does not
///   exist returns <code>isError</code> absent, <code>queue_depth=0</code>,
///   <code>oldest_message_id=""</code>, <code>oldest_message_age_seconds=0</code>,
///   <code>oldest_message_ids=[]</code>, <code>render_strategy="matched"</code>.</li>
/// <li><b>TestExistingQueueDepthMatchesGetCount</b> — AC-2: injects a fake queue
///   entry directly into <code>^Ens.Queue</code>, calls the tool, and asserts
///   <code>queue_depth</code> matches <code>##class(Ens.Queue).GetCount()</code>.</li>
/// <li><b>TestIncludeOldestMessagesFalseReturnsEmptyArray</b> — AC-5: when
///   <code>include_oldest_messages</code> is omitted or false, <code>oldest_message_ids</code>
///   is an empty array (<code>[]</code>).</li>
/// <li><b>TestIncludeOldestMessagesTrueReturnsIds</b> — AC-5: when
///   <code>include_oldest_messages=true</code>, <code>oldest_message_ids</code>
///   contains up to 5 message IDs.</li>
/// <li><b>TestMissingConfigItemNameReturnsError</b> — validation: missing required
///   parameter returns <code>isError=1</code>.</li>
/// <li><b>TestOldestMessageIdMatchesEnumerateItem</b> — AC-4: <code>oldest_message_id</code>
///   equals the first <code>MessageId</code> from <code>Ens.Queue:EnumerateItem</code>.</li>
/// <li><b>TestRegistryListToolsIncludesGetQueueState</b> — AC-1: registry surfaces
///   <code>get_queue_state</code> with a non-empty Description field.</li>
/// </ol>
///
/// <p><b>Fixture strategy.</b> Since <code>Ens.Queue</code> is not a SQL class
/// (it uses the <code>^Ens.Queue</code> global via <code>$$$EnsQueue</code>),
/// test fixtures are injected directly into <code>^Ens.Queue</code> under an
/// isolated test-queue name (<code>SATest134*</code> prefix). Cleanup in
/// <method>OnAfterAllTests</method> kills all injected nodes. Process-private
/// global subscripts use no hyphens per project rules.</p>
Class SessionAgent.Test.GetQueueStateTest Extends %UnitTest.TestCase
{

/// <p>Test queue name prefix — unlikely to collide with real production queues.</p>
Parameter TESTQUEUEPREFIX As %String = "SATest134Queue";

/// <p>Fake message ID injected for queue-depth tests. Must not match a real
/// <code>Ens.MessageHeader</code> row so the age-seconds path gracefully
/// falls back to 0 when <code>%OpenId</code> returns null.</p>
Parameter FAKEMSGID As %String = "9999913401";

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
    Set tCtx.IrisSessionId = 999134
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Return the name of the per-test injected queue.
/// NOTE: method name must NOT begin with "Test" — see
/// .claude/rules/object-script-testing.md §"Property Test* Shadow Trap".</p>
ClassMethod QueueNameFor(pSuffix As %String = "") As %String
{
    Quit ..#TESTQUEUEPREFIX _ pSuffix
}

/// <p>Inject a fake queue entry with <code>pCount</code> messages at priority 3.</p>
ClassMethod InjectQueue(pName As %String, pCount As %Integer = 1) As %Status
{
    Set tSC = $$$OK
    Try {
        Kill ^Ens.Queue(pName)
        Set ^Ens.Queue(pName,0,"count") = pCount
        Set ^Ens.Queue(pName,0,"next") = pCount
        Set ^Ens.Queue(pName,0,"time") = $ZDateTime($Horolog, 3, 1, 0)
        Set tIdx = 0
        For tI = 1:1:pCount {
            Set tIdx = tIdx + 1
            ; Use fake message IDs (string form: base + tI)
            Set ^Ens.Queue(pName, 3, tIdx) = ..#FAKEMSGID + tI
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Remove the injected fake queue entry.</p>
ClassMethod CleanupQueue(pName As %String) As %Status
{
    Kill ^Ens.Queue(pName)
    Quit $$$OK
}

/// <p>Cleanup all injected test queues.</p>
Method OnAfterAllTests() As %Status
{
    ; Kill any SATest134Queue* global nodes injected during tests
    Set tName = $Order(^Ens.Queue(..#TESTQUEUEPREFIX))
    While (tName '= "") && (tName [ ..#TESTQUEUEPREFIX) {
        Kill ^Ens.Queue(tName)
        Set tName = $Order(^Ens.Queue(..#TESTQUEUEPREFIX))
    }
    Quit $$$OK
}

/// <p>AC-3 — absent queue returns zero-state, no error.</p>
Method TestAbsentQueueReturnsZeroState()
{
    Set tQName = ..QueueNameFor("AbsentA")
    ; Ensure queue does not exist before test
    Kill ^Ens.Queue(tQName)
    Do $$$AssertTrue('##class(Ens.Queue).Exists(tQName), "Precondition: queue '" _ tQName _ "' is absent")

    Set tCtx = ..BuildCtx()
    Set tArgs = {"config_item_name":(tQName)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK on absent queue")

    Set tInner = tResult.structuredContent
    Do $$$AssertTrue($IsObject(tInner), "structuredContent is an object on absent queue")

    ; AC-3: no isError=1 on absent queue
    Do $$$AssertNotEquals(+tResult.%Get("isError"), 1, "isError is not 1 on absent queue (IsApiError=0 semantics)")

    ; AC-3: all depth/id fields at zero-state
    Do $$$AssertEquals(+tInner.%Get("queue_depth"), 0, "queue_depth=0 on absent queue")
    Do $$$AssertEquals(tInner.%Get("oldest_message_id"), "", "oldest_message_id='' on absent queue")
    Do $$$AssertEquals(+tInner.%Get("oldest_message_age_seconds"), 0, "oldest_message_age_seconds=0 on absent queue")

    Set tIds = tInner.%Get("oldest_message_ids")
    Do $$$AssertTrue($IsObject(tIds), "oldest_message_ids is an array on absent queue")
    Do $$$AssertEquals(tIds.%Size(), 0, "oldest_message_ids is empty on absent queue")

    ; render_strategy always "matched"
    Do $$$AssertEquals(tInner.%Get("render_strategy"), "matched", "render_strategy='matched' on absent queue")
    Quit
}

/// <p>AC-2 — queue_depth matches ##class(Ens.Queue).GetCount().</p>
Method TestExistingQueueDepthMatchesGetCount()
{
    Set tQName = ..QueueNameFor("DepthB")
    Set tInjectedCount = 3
    Set tSCInj = ..InjectQueue(tQName, tInjectedCount)
    Do $$$AssertStatusOK(tSCInj, "Fixture inject OK")
    Do $$$AssertTrue(##class(Ens.Queue).Exists(tQName), "Precondition: injected queue exists")

    ; Ground-truth from the API
    Set tGetCountValue = ##class(Ens.Queue).GetCount(tQName)
    If tGetCountValue = "" Set tGetCountValue = 0

    Set tCtx = ..BuildCtx()
    Set tArgs = {"config_item_name":(tQName)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK on injected queue")

    Set tInner = tResult.structuredContent
    Do $$$AssertEquals(+tInner.%Get("queue_depth"), +tGetCountValue, "queue_depth matches Ens.Queue.GetCount (expected " _ tGetCountValue _ ")")
    Do $$$AssertEquals(tInner.%Get("render_strategy"), "matched", "render_strategy='matched' on populated queue")

    Do ..CleanupQueue(tQName)
    Quit
}

/// <p>AC-5 — when include_oldest_messages is omitted, oldest_message_ids is [].</p>
Method TestIncludeOldestMessagesFalseReturnsEmptyArray()
{
    Set tQName = ..QueueNameFor("NoIncludeC")
    Do ..InjectQueue(tQName, 2)

    Set tCtx = ..BuildCtx()
    ; Omit include_oldest_messages
    Set tArgs = {"config_item_name":(tQName)}
    Set tResult = ""
    Do ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)

    Set tInner = tResult.structuredContent
    Set tIds = tInner.%Get("oldest_message_ids")
    Do $$$AssertTrue($IsObject(tIds), "oldest_message_ids is an array when include param omitted")
    Do $$$AssertEquals(tIds.%Size(), 0, "oldest_message_ids is empty when include_oldest_messages omitted")

    ; Also explicitly pass false
    Set tArgs2 = {"config_item_name":(tQName), "include_oldest_messages": false}
    Set tResult2 = ""
    Do ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs2, .tResult2)
    Set tInner2 = tResult2.structuredContent
    Set tIds2 = tInner2.%Get("oldest_message_ids")
    Do $$$AssertTrue($IsObject(tIds2), "oldest_message_ids is an array when include_oldest_messages=false")
    Do $$$AssertEquals(tIds2.%Size(), 0, "oldest_message_ids is empty when include_oldest_messages=false")

    Do ..CleanupQueue(tQName)
    Quit
}

/// <p>AC-5 — when include_oldest_messages=true, oldest_message_ids contains up to 5 IDs.</p>
Method TestIncludeOldestMessagesTrueReturnsIds()
{
    Set tQName = ..QueueNameFor("IncludeD")
    Set tMsgCount = 3
    Do ..InjectQueue(tQName, tMsgCount)

    Set tCtx = ..BuildCtx()
    Set tArgs = {"config_item_name":(tQName), "include_oldest_messages": true}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK for include_oldest_messages=true")

    Set tInner = tResult.structuredContent
    Set tIds = tInner.%Get("oldest_message_ids")
    Do $$$AssertTrue($IsObject(tIds), "oldest_message_ids is an array when include_oldest_messages=true")
    Do $$$AssertTrue(tIds.%Size() >= 1, "oldest_message_ids has at least 1 entry (got " _ tIds.%Size() _ ")")
    Do $$$AssertTrue(tIds.%Size() <= 5, "oldest_message_ids has at most 5 entries (got " _ tIds.%Size() _ ")")

    ; Each element must be a non-empty string
    Set tI = 0
    While tI < tIds.%Size() {
        Do $$$AssertNotEquals(tIds.%Get(tI), "", "oldest_message_ids[" _ tI _ "] is non-empty")
        Set tI = tI + 1
    }

    Do ..CleanupQueue(tQName)
    Quit
}

/// <p>Validation — missing required parameter returns isError=1.</p>
Method TestMissingConfigItemNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK even on validation error")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing config_item_name")
    Set tText = tResult.content.%Get(0).text
    Do $$$AssertTrue(tText [ "missing config_item_name", "error text mentions 'missing config_item_name' (got: '" _ tText _ "')")
    Quit
}

/// <p>AC-4 — oldest_message_id equals first MessageId from EnumerateItem query.</p>
Method TestOldestMessageIdMatchesEnumerateItem()
{
    Set tQName = ..QueueNameFor("OldestE")
    Set tMsgCount = 2
    Do ..InjectQueue(tQName, tMsgCount)

    ; Get the expected oldest ID from EnumerateItem directly (ground truth)
    Set tExpectedOldest = ""
    Set tRS = ##class(%ResultSet).%New("Ens.Queue:EnumerateItem")
    Do tRS.Execute(tQName)
    If tRS.Next() Set tExpectedOldest = tRS.GetData(3)

    Do $$$AssertNotEquals(tExpectedOldest, "", "Precondition: EnumerateItem yields at least one MessageId")

    ; Invoke the tool
    Set tCtx = ..BuildCtx()
    Set tArgs = {"config_item_name":(tQName)}
    Set tResult = ""
    Do ##class(SessionAgent.Tool.Inspection.GetQueueState).Invoke(tCtx, tArgs, .tResult)

    Set tInner = tResult.structuredContent
    Do $$$AssertEquals(tInner.%Get("oldest_message_id"), tExpectedOldest, "oldest_message_id matches EnumerateItem first MessageId (expected '" _ tExpectedOldest _ "')")

    ; oldest_message_age_seconds must be >= 0
    Do $$$AssertTrue(+tInner.%Get("oldest_message_age_seconds") >= 0, "oldest_message_age_seconds is non-negative")

    Do ..CleanupQueue(tQName)
    Quit
}

/// <p>AC-1 — registry surfaces get_queue_state with non-empty Description.</p>
Method TestRegistryListToolsIncludesGetQueueState()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")

    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tE) {
        If tE.%Get("name") = "get_queue_state" {
            Set tFound = 1
            Set tEntry = tE
            Quit
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'get_queue_state'")

    If $IsObject(tEntry) {
        ; AC-1: non-empty Description
        Set tDesc = tEntry.%Get("description")
        Do $$$AssertNotEquals(tDesc, "", "get_queue_state has non-empty description (got: '" _ tDesc _ "')")

        ; Schema: required contains config_item_name
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "get_queue_state input_schema is an object")

        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "schema.required has exactly 1 entry")
        Do $$$AssertEquals(tRequired.%Get(0), "config_item_name", "schema.required[0]='config_item_name'")

        Set tProps = tSchema.%Get("properties")
        Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")

        Set tNameProp = tProps.%Get("config_item_name")
        Do $$$AssertTrue($IsObject(tNameProp), "schema.properties.config_item_name defined")

        Set tIncludeProp = tProps.%Get("include_oldest_messages")
        Do $$$AssertTrue($IsObject(tIncludeProp), "schema.properties.include_oldest_messages defined")

        ; additionalProperties: false
        Do $$$AssertEquals(+tSchema.%Get("additionalProperties"), 0, "additionalProperties=false")
    }
    Quit
}

}
