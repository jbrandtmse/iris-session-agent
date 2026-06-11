/// <p>Story 14.2 AC-5 — schema-discovery tool suite. Exercises the three
/// FR61 discovery tools (<code>list_active_body_types</code>,
/// <code>describe_message_class</code>, <code>discover_tables</code>)
/// through the REAL <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch
/// trust boundary (Integration AC): per-tool happy paths, census window
/// clamping, <code>class_not_found</code> + validation envelopes,
/// extent/subclass enumeration, projected-vs-embedded collection
/// child-table coverage (Epic 13 Pattern B), AdditionalInfo census +
/// graceful absent-property path, and discover_tables fragment +
/// system-schema exclusion.</p>
///
/// <p><b>Fixture strategy.</b> The census happy path seeds ONE synthetic
/// <CLASS>Ens.MessageHeader</CLASS> row (UTC TimeCreated from
/// <code>$ZTimeStamp</code> — TimeCreated stores UTC per the Story 14.2
/// Task 0 probe) and deletes it in the same method. All other assertions
/// run against always-compiled classes (<code>Ens.MessageHeader</code>,
/// <code>SessionAgent.Sample.*</code>, <code>SessionAgent.Tool.Base</code>)
/// so no production scenario data is required.</p>
Class SessionAgent.Test.SchemaDiscoveryToolTest Extends %UnitTest.TestCase
{

/// <p>Synthetic body-class marker for the census fixture row.</p>
Parameter CENSUSFIXTUREBODY As %String = "SchemaDisc.Census142.Body";

/// <p>Synthetic session id well outside realistic Ens ranges.</p>
Parameter SYNTHETICSESSIONID As %Integer = 9799942;

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>CallerContext with sane defaults (same shape as
/// InspectionSuiteVerificationTest.BuildCtx).</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#SYNTHETICSESSIONID
    Set tCtx.PortalUser = "tester-142"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Dispatch helper — real Registry.Dispatch round-trip.</p>
ClassMethod Dispatch(pToolName As %String, pArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set pResult = ""
    Quit ##class(SessionAgent.Tool.Registry).Dispatch(pToolName, ..BuildCtx(), pArgs, .pResult)
}

/// <p>AC-1 happy path — seed one synthetic header inside the window,
/// dispatch with hours=1, assert the synthetic body class appears in the
/// census with count ≥ 1; cleanup the fixture row.</p>
Method TestListActiveBodyTypesCensusHappyPath()
{
    ; Seed — UTC TimeCreated (Ens.DataType.UTC stores UTC; $ZTimeStamp).
    Set tHdr = ##class(Ens.MessageHeader).%New()
    Set tHdr.SessionId = ..#SYNTHETICSESSIONID
    Set tHdr.SourceConfigName = "SchemaDiscFixtureSrc"
    Set tHdr.TargetConfigName = "SchemaDiscFixtureTgt"
    Set tHdr.MessageBodyClassName = ..#CENSUSFIXTUREBODY
    Set tHdr.TimeCreated = $ZDateTime($ZTimeStamp, 3, 1, 0)
    Set tSaveSC = tHdr.%Save()
    Do $$$AssertStatusOK(tSaveSC, "census fixture header saved")
    Set tFixtureId = tHdr.%Id()

    ; Dispatch + assertions inside Try so the fixture row is ALWAYS
    ; cleaned up — an orphaned synthetic header would pollute every
    ; subsequent census window for up to 90 days (review fix 14.2).
    Set tThrown = ""
    Try {
        Set tSC = ..Dispatch("list_active_body_types", {"hours": 1}, .tResult)
        Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
        Do $$$AssertEquals(+tResult.%Get("isError"), 0, "success envelope (no isError)")
        Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok'")
        Do $$$AssertEquals(tResult.structuredContent.%Get("hours"), 1, "hours echoed as 1")
        Set tBodyTypes = tResult.structuredContent.%Get("body_types")
        Do $$$AssertTrue($IsObject(tBodyTypes), "body_types is an array")
        Do $$$AssertEquals(tResult.structuredContent.%Get("body_type_count"), tBodyTypes.%Size(), "body_type_count matches array size")
        ; Find the synthetic body class in the census.
        Set tFoundCount = -1
        Set tIter = tBodyTypes.%GetIterator()
        While tIter.%GetNext(.tKey, .tEntry) {
            If tEntry.%Get("body_class") = ..#CENSUSFIXTUREBODY {
                Set tFoundCount = +tEntry.%Get("msg_count")
            }
        }
        Do $$$AssertTrue(tFoundCount >= 1, "synthetic body class present in census with count >= 1 (got " _ tFoundCount _ ")")
        Do $$$AssertNotEquals(tResult.structuredContent.%Get("window_start"), "", "window_start populated (ISO Z)")
    }
    Catch ex {
        Set tThrown = ex.DisplayString()
    }

    ; Cleanup — always runs; write status checked (project rule).
    Set tDelSC = ##class(Ens.MessageHeader).%DeleteId(tFixtureId)
    Do $$$AssertStatusOK(tDelSC, "census fixture row deleted")
    Do $$$AssertEquals(tThrown, "", "no exception during census dispatch/assertions")
    Quit
}

/// <p>AC-1 — window clamping (1..2160) + empty-args default (168). An
/// empty census is structurally a success envelope, never an error.</p>
Method TestListActiveBodyTypesWindowClampAndDefaults()
{
    ; Empty args — default 168.
    Set tSC = ..Dispatch("list_active_body_types", {}, .tResult)
    Do $$$AssertStatusOK(tSC, "empty-args Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "empty args is a SUCCESS envelope (no required fields)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("hours"), 168, "default window = 168 hours")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' on default window")

    ; Above max — clamped to 2160.
    Set tSC = ..Dispatch("list_active_body_types", {"hours": 999999}, .tResult)
    Do $$$AssertStatusOK(tSC, "oversize-hours Dispatch returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("hours"), 2160, "hours clamped to max 2160")

    ; Below min — clamped to 1.
    Set tSC = ..Dispatch("list_active_body_types", {"hours": 0}, .tResult)
    Do $$$AssertStatusOK(tSC, "zero-hours Dispatch returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("hours"), 1, "hours clamped to min 1")
    Do $$$AssertTrue($IsObject(tResult.structuredContent.%Get("body_types")), "body_types array present even when census may be empty")
    Quit
}

/// <p>AC-2 happy path — sample message class: authoritative schema.table
/// mapping, columns + datatypes, indexes, and the Pattern B
/// embedded-collection distinction (LineItems is a $LIST column, NOT a
/// child table).</p>
Method TestDescribeMessageClassSampleMsgMapping()
{
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "SessionAgent.Sample.Msg.OrderRequest"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "success envelope")
    Set tStruct = tResult.structuredContent
    Do $$$AssertEquals(tStruct.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Do $$$AssertEquals(tStruct.%Get("class_name"), "SessionAgent.Sample.Msg.OrderRequest", "canonical class name echoed")
    Do $$$AssertEquals(tStruct.%Get("class_type"), "persistent", "class_type='persistent'")
    Do $$$AssertEquals(tStruct.%Get("schema_name"), "SessionAgent_Sample_Msg", "schema mapping from %Dictionary.CompiledClass")
    Do $$$AssertEquals(tStruct.%Get("table_name"), "OrderRequest", "table mapping from %Dictionary.CompiledClass")
    Do $$$AssertEquals(tStruct.%Get("qualified_table"), "SessionAgent_Sample_Msg.OrderRequest", "qualified_table composed")
    ; Columns include OrderId varchar.
    Set tFoundOrderId = 0
    Set tIter = tStruct.%Get("columns").%GetIterator()
    While tIter.%GetNext(.tKey, .tCol) {
        If tCol.%Get("name") = "OrderId" {
            Set tFoundOrderId = 1
            Do $$$AssertEquals(tCol.%Get("type"), "varchar", "OrderId column datatype = varchar")
        }
    }
    Do $$$AssertTrue(tFoundOrderId, "columns include OrderId")
    ; Indexes include IDKEY — and its NON_UNIQUE decode locks the flag
    ; semantics (live probe 2026-06-11: INFORMATION_SCHEMA.INDEXES
    ; returns numeric 0/1; IDKEY NON_UNIQUE=0 -> unique=true).
    Set tFoundIdKey = 0
    Set tIter = tStruct.%Get("indexes").%GetIterator()
    While tIter.%GetNext(.tKey, .tIdx) {
        If tIdx.%Get("name") = "IDKEY" {
            Set tFoundIdKey = 1
            Do $$$AssertEquals(+tIdx.%Get("unique"), 1, "IDKEY decoded as unique (NON_UNIQUE=0)")
        }
    }
    Do $$$AssertTrue(tFoundIdKey, "indexes include IDKEY")
    ; Pattern B — LineItems is a list collection with NO child table.
    Set tFoundLineItems = 0
    Set tIter = tStruct.%Get("collection_properties").%GetIterator()
    While tIter.%GetNext(.tKey, .tProp) {
        If tProp.%Get("name") = "LineItems" {
            Set tFoundLineItems = 1
            Do $$$AssertEquals(+tProp.%Get("projects_child_table"), 0, "LineItems is embedded ($LIST) — projects_child_table=false")
            Do $$$AssertEquals(tProp.%Get("child_table"), "", "LineItems child_table empty (not queryable as a table)")
        }
    }
    Do $$$AssertTrue(tFoundLineItems, "collection_properties include LineItems")
    Quit
}

/// <p>AC-2 — Ens.MessageHeader: extent enumeration via the
/// PrimarySuper-chain match returns ≥1 entry (subclass-or-self; self
/// when no subclasses are compiled), and the well-known columns are
/// present.</p>
Method TestDescribeMessageClassEnsMessageHeaderExtent()
{
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "Ens.MessageHeader"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Set tStruct = tResult.structuredContent
    Do $$$AssertEquals(tStruct.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Do $$$AssertEquals(tStruct.%Get("qualified_table"), "Ens.MessageHeader", "Ens.MessageHeader maps to Ens.MessageHeader")
    Set tExtent = tStruct.%Get("extent_classes")
    Do $$$AssertTrue($IsObject(tExtent) && (tExtent.%Size() >= 1), "extent_classes enumerates >= 1 entry (subclass-or-self)")
    Set tFoundSelf = 0
    Set tIter = tExtent.%GetIterator()
    While tIter.%GetNext(.tKey, .tName) {
        If tName = "Ens.MessageHeader" Set tFoundSelf = 1
        ; The naive Super-substring trap would pull Ens.MessageHeaderBase
        ; descendants like Ens.Enterprise.MsgBank.MessageHeader in — the
        ; PrimarySuper tilde match must NOT (Task 0 probe).
        Do $$$AssertNotEquals(tName, "Ens.Enterprise.MsgBank.MessageHeader", "MessageHeaderBase-substring false positive excluded: " _ tName)
    }
    Do $$$AssertTrue(tFoundSelf, "extent_classes include the class itself")
    Do $$$AssertEquals(tStruct.%Get("subclass_count"), tExtent.%Size() - 1, "subclass_count = extent size - 1")
    ; Well-known columns present.
    Set tFoundBodyCol = 0
    Set tIter = tStruct.%Get("columns").%GetIterator()
    While tIter.%GetNext(.tKey, .tCol) {
        If tCol.%Get("name") = "MessageBodyClassName" Set tFoundBodyCol = 1
    }
    Do $$$AssertTrue(tFoundBodyCol, "columns include MessageBodyClassName")
    Quit
}

/// <p>AC-2 (e) — projected collection child tables: the sample
/// OrderRouter BP projects <code>OrderRouter_MessagesReceived</code> /
/// <code>_MessagesSent</code> child tables from its inherited list
/// properties, while sibling list properties (<code>%MessagesReceivedOld</code>)
/// stay embedded — the envelope distinguishes the two.</p>
Method TestDescribeMessageClassChildTableProjection()
{
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "SessionAgent.Sample.BP.OrderRouter"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Set tStruct = tResult.structuredContent
    Do $$$AssertEquals(tStruct.%Get("render_strategy"), "ok", "render_strategy='ok'")
    ; child_tables roster includes the projected collection table.
    Set tFoundChild = 0
    Set tIter = tStruct.%Get("child_tables").%GetIterator()
    While tIter.%GetNext(.tKey, .tName) {
        If tName = "OrderRouter_MessagesReceived" Set tFoundChild = 1
    }
    Do $$$AssertTrue(tFoundChild, "child_tables include OrderRouter_MessagesReceived")
    ; Per-property classification.
    Set (tFoundProjected, tFoundEmbedded) = 0
    Set tIter = tStruct.%Get("collection_properties").%GetIterator()
    While tIter.%GetNext(.tKey, .tProp) {
        If tProp.%Get("name") = "%MessagesReceived" {
            Set tFoundProjected = 1
            Do $$$AssertEquals(+tProp.%Get("projects_child_table"), 1, "%MessagesReceived projects a child table")
            Do $$$AssertEquals(tProp.%Get("child_table"), "OrderRouter_MessagesReceived", "%MessagesReceived child_table named (% prefix stripped in projection)")
        }
        If tProp.%Get("name") = "%MessagesReceivedOld" {
            Set tFoundEmbedded = 1
            Do $$$AssertEquals(+tProp.%Get("projects_child_table"), 0, "%MessagesReceivedOld stays embedded (no child table)")
        }
    }
    Do $$$AssertTrue(tFoundProjected, "collection_properties include %MessagesReceived")
    Do $$$AssertTrue(tFoundEmbedded, "collection_properties include %MessagesReceivedOld")
    Quit
}

/// <p>AC-2 (f) — AdditionalInfo paths. Graceful absent-property path is
/// asserted unconditionally (sample Msg class has no AdditionalInfo →
/// <code>has_additional_info=false</code>, no census field). When
/// <code>HS.Message.XMLMessage</code> is compiled in this namespace
/// (HealthShare-based instances), the positive path is also asserted:
/// <code>has_additional_info=true</code> + census array present.</p>
Method TestDescribeMessageClassAdditionalInfoPaths()
{
    ; Absent-property path — always assertable.
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "SessionAgent.Sample.Msg.OrderRequest"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("has_additional_info"), 0, "sample Msg class: has_additional_info=false")
    Do $$$AssertTrue('tResult.structuredContent.%IsDefined("additional_info_keys"), "no additional_info_keys field when the property is absent")

    ; Positive path — conditional on HS.Message.XMLMessage being compiled.
    If ##class(%Dictionary.CompiledClass).%ExistsId("HS.Message.XMLMessage") {
        Set tSC = ..Dispatch("describe_message_class", {"class_name": "HS.Message.XMLMessage"}, .tResult2)
        Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK for HS.Message.XMLMessage")
        Do $$$AssertEquals(+tResult2.structuredContent.%Get("has_additional_info"), 1, "XMLMessage: has_additional_info=true")
        Do $$$AssertTrue($IsObject(tResult2.structuredContent.%Get("additional_info_keys")), "additional_info_keys census array present (TOP-bounded; may be empty)")
    } Else {
        Do $$$AssertTrue(1, "HS.Message.XMLMessage not compiled in this namespace — positive AdditionalInfo path skipped")
    }
    Quit
}

/// <p>AC-2 — class_not_found envelopes: non-existent class AND
/// existing-but-non-persistent class both return the success-shape
/// <code>render_strategy="class_not_found"</code> (NOT an error).</p>
Method TestDescribeMessageClassNotFoundAndNonPersistent()
{
    ; Non-existent.
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "Totally.Bogus.ClassName142"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK for bogus class")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "class_not_found is NOT an error envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "class_not_found", "render_strategy='class_not_found' for bogus class")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("class_exists"), 0, "class_exists=false for bogus class")

    ; Existing but non-persistent (no SQL projection).
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "SessionAgent.Tool.Base"}, .tResult2)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK for non-persistent class")
    Do $$$AssertEquals(+tResult2.%Get("isError"), 0, "non-persistent is NOT an error envelope")
    Do $$$AssertEquals(tResult2.structuredContent.%Get("render_strategy"), "class_not_found", "render_strategy='class_not_found' for non-persistent class")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("class_exists"), 1, "class_exists=true for compiled non-persistent class")
    Quit
}

/// <p>AC-2 — validation envelopes (SQL-injection layer 2): missing and
/// malformed <code>class_name</code> both return <code>isError=1</code>
/// before any SQL is prepared.</p>
Method TestDescribeMessageClassValidationEnvelopes()
{
    Set tSC = ..Dispatch("describe_message_class", {}, .tResult)
    Do $$$AssertStatusOK(tSC, "missing class_name Dispatch returns $$$OK (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing class_name")

    Set tSC = ..Dispatch("describe_message_class", {"class_name": "Bad Name; DROP TABLE--"}, .tResult2)
    Do $$$AssertStatusOK(tSC, "malformed class_name Dispatch returns $$$OK (envelope-based)")
    Do $$$AssertEquals(+tResult2.%Get("isError"), 1, "isError=1 on malformed class_name ($Match regex gate)")
    Quit
}

/// <p>AC-3 — fragment search finds Ens.MessageHeader.</p>
Method TestDiscoverTablesFragmentFindsEnsMessageHeader()
{
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "MessageHeader"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Set tFound = 0
    Set tIter = tResult.structuredContent.%Get("tables").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If (tEntry.%Get("schema") = "Ens") && (tEntry.%Get("name") = "MessageHeader") Set tFound = 1
    }
    Do $$$AssertTrue(tFound, "fragment 'MessageHeader' finds Ens.MessageHeader")
    Do $$$AssertEquals(tResult.structuredContent.%Get("table_count"), tResult.structuredContent.%Get("tables").%Size(), "table_count matches array size")
    Quit
}

/// <p>AC-3 — default call excludes %-schemas and INFORMATION_SCHEMA;
/// empty args is a success envelope (no required fields).</p>
Method TestDiscoverTablesDefaultExcludesSystemSchemas()
{
    Set tSC = ..Dispatch("discover_tables", {}, .tResult)
    Do $$$AssertStatusOK(tSC, "empty-args Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "empty args is a SUCCESS envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("max_results"), 50, "default max_results = 50")
    Set tIter = tResult.structuredContent.%Get("tables").%GetIterator()
    Set tRowCount = 0
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSchema = tEntry.%Get("schema")
        Set tRowCount = tRowCount + 1
        Do $$$AssertTrue($Extract(tSchema, 1) '= "%", "no %-system schema in default listing (got " _ tSchema _ ")")
        Do $$$AssertNotEquals($ZConvert(tSchema, "U"), "INFORMATION_SCHEMA", "INFORMATION_SCHEMA excluded from default listing")
        ; Cap assertion spam — the exclusion holds for the whole page if
        ; it holds for every returned row; rows are schema-sorted so any
        ; %-schema would sort first.
        If tRowCount >= 50 Quit
    }
    Do $$$AssertTrue(tRowCount >= 1, "default listing returns at least one table")
    Quit
}

/// <p>AC-3 — include_system=true surfaces %-schemas (boolean AND the
/// string form "true" — provider schema drift, Epic 5 history);
/// max_results clamping (1..200) + overflow-based truncated flag.</p>
Method TestDiscoverTablesIncludeSystemAndClamp()
{
    ; include_system=true + fragment that lives in %Dictionary.
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "CompiledClass", "include_system": true}, .tResult)
    Do $$$AssertStatusOK(tSC, "include_system Dispatch returns $$$OK")
    Do $$$AssertTrue(..TablesContain(tResult, "%Dictionary", "CompiledClass"), "include_system=true surfaces %Dictionary.CompiledClass")

    ; String-typed "true" coerces to true (review fix 14.2 — +"true"=0
    ; previously silently dropped the operator's explicit request).
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "CompiledClass", "include_system": "true"}, .tResultS)
    Do $$$AssertStatusOK(tSC, "string include_system Dispatch returns $$$OK")
    Do $$$AssertTrue(..TablesContain(tResultS, "%Dictionary", "CompiledClass"), "include_system='true' (string) surfaces %Dictionary.CompiledClass")

    ; Clamp above max.
    Set tSC = ..Dispatch("discover_tables", {"max_results": 5000}, .tResult2)
    Do $$$AssertStatusOK(tSC, "oversize max_results Dispatch returns $$$OK")
    Do $$$AssertEquals(tResult2.structuredContent.%Get("max_results"), 200, "max_results clamped to 200")

    ; Small cap — overflow-based truncated flag: the namespace always has
    ; more than 3 non-system tables (SessionAgent's own tables), so the
    ; cap genuinely overflows and truncated must be true (review fix
    ; 14.2 — was size=cap inference, a false positive on exact counts).
    Set tSC = ..Dispatch("discover_tables", {"max_results": 3}, .tResult3)
    Do $$$AssertStatusOK(tSC, "small max_results Dispatch returns $$$OK")
    Do $$$AssertEquals(tResult3.structuredContent.%Get("tables").%Size(), 3, "table_count bounded by max_results")
    Do $$$AssertEquals(+tResult3.structuredContent.%Get("truncated"), 1, "truncated=true on genuine overflow")
    Quit
}

/// <p>AC-3 — malformed fragment returns the validation envelope (layer 2
/// regex gate) before any SQL runs.</p>
Method TestDiscoverTablesInvalidFragmentEnvelope()
{
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "bad;fragment' OR 1=1"}, .tResult)
    Do $$$AssertStatusOK(tSC, "malformed fragment Dispatch returns $$$OK (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on malformed name_fragment")
    Quit
}

/// <p>Helper — does the result's <code>tables</code> array contain the
/// schema/name pair? (NOT Test-prefixed — discovery-shadow rule.)</p>
ClassMethod TablesContain(pResult As %DynamicObject, pSchema As %String, pName As %String) As %Boolean
{
    Set tFound = 0
    Set tIter = pResult.structuredContent.%Get("tables").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If (tEntry.%Get("schema") = pSchema) && (tEntry.%Get("name") = pName) Set tFound = 1
    }
    Quit tFound
}

/// <p>QA gap coverage — AC-2 graceful empty sections: a persistent class
/// with NO collection properties (verified live 2026-06-11:
/// %Dictionary.CompiledProperty has zero Collection rows for
/// <code>SessionAgent.Sample.Msg.OrderResponse</code> and no
/// <code>OrderResponse_*</code> child tables exist) returns empty
/// <code>child_tables</code>/<code>collection_properties</code> arrays,
/// <code>has_additional_info=false</code>, and no
/// <code>additional_info_keys</code> field — empty sections are
/// success-shaped and present, never omitted or errored.</p>
Method TestDescribeMessageClassNoCollectionsGracefulEmpty()
{
    Set tSC = ..Dispatch("describe_message_class", {"class_name": "SessionAgent.Sample.Msg.OrderResponse"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "success envelope")
    Set tStruct = tResult.structuredContent
    Do $$$AssertEquals(tStruct.%Get("render_strategy"), "ok", "render_strategy='ok'")
    Do $$$AssertEquals(tStruct.%Get("qualified_table"), "SessionAgent_Sample_Msg.OrderResponse", "qualified_table composed")
    Do $$$AssertTrue($IsObject(tStruct.%Get("columns")) && (tStruct.%Get("columns").%Size() >= 1), "columns still populated")
    Do $$$AssertTrue($IsObject(tStruct.%Get("indexes")), "indexes array present")
    Do $$$AssertTrue($IsObject(tStruct.%Get("child_tables")), "child_tables array present (not omitted)")
    Do $$$AssertEquals(tStruct.%Get("child_tables").%Size(), 0, "child_tables empty — no projected child tables")
    Do $$$AssertTrue($IsObject(tStruct.%Get("collection_properties")), "collection_properties array present (not omitted)")
    Do $$$AssertEquals(tStruct.%Get("collection_properties").%Size(), 0, "collection_properties empty — class has no list/array properties")
    Do $$$AssertEquals(+tStruct.%Get("has_additional_info"), 0, "has_additional_info=false")
    Do $$$AssertTrue('tStruct.%IsDefined("additional_info_keys"), "no additional_info_keys field without AdditionalInfo property")
    Do $$$AssertEquals(+tStruct.%Get("truncated"), 0, "small class well under the 16KB budget — truncated=false")
    Quit
}

/// <p>QA gap coverage — AC-3 LIKE-wildcard semantics lock: the layer-2
/// fragment regex deliberately admits <code>%</code> and <code>_</code>,
/// and the fragment is bound into the LIKE pattern unescaped, so SQL
/// LIKE wildcard semantics pass through (documented in the
/// GetInputSchema description). <code>Mes_ageHeader</code> (one-char
/// wildcard over the elided 's') and <code>Message%Header</code>
/// (zero-plus wildcard) must both find <code>Ens.MessageHeader</code>
/// (both verified live against INFORMATION_SCHEMA.TABLES 2026-06-11
/// before locking).</p>
Method TestDiscoverTablesLikeWildcardSemantics()
{
    ; '_' — exactly one character.
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "Mes_ageHeader"}, .tResult)
    Do $$$AssertStatusOK(tSC, "underscore-wildcard Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "wildcard fragment passes the layer-2 regex (success envelope)")
    Do $$$AssertTrue(..TablesContain(tResult, "Ens", "MessageHeader"), "'Mes_ageHeader' matches Ens.MessageHeader ('_' = one char)")

    ; '%' — zero or more characters.
    Set tSC = ..Dispatch("discover_tables", {"name_fragment": "Message%Header"}, .tResult2)
    Do $$$AssertStatusOK(tSC, "percent-wildcard Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult2.%Get("isError"), 0, "percent fragment passes the layer-2 regex (success envelope)")
    Do $$$AssertTrue(..TablesContain(tResult2, "Ens", "MessageHeader"), "'Message%Header' matches Ens.MessageHeader ('%' = zero+ chars)")
    Quit
}

/// <p>AC-3 max_results lower bound — clamps to 1 (review fix 14.2:
/// code-review adjudicated the QA-flagged divergence in favor of the
/// AC's "clamp 1..200" wording, consistent with <code>hours&lt;1</code>
/// clamping to 1 in list_active_body_types and with the published
/// GetInputSchema description "clamped 1..200").</p>
Method TestDiscoverTablesMaxResultsSubOneClampsToOne()
{
    Set tSC = ..Dispatch("discover_tables", {"max_results": 0}, .tResult)
    Do $$$AssertStatusOK(tSC, "max_results=0 Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "sub-1 max_results is not an error")
    Do $$$AssertEquals(tResult.structuredContent.%Get("max_results"), 1, "max_results<1 clamps to 1 (AC-3 'clamp 1..200')")
    Do $$$AssertTrue(tResult.structuredContent.%Get("tables").%Size() <= 1, "at most 1 row returned at the clamped cap")
    Quit
}

/// <p>QA gap coverage (Story 14.1 precedent
/// TestRegistryListToolsIncludes&lt;Tool&gt;) — ListTools manifest
/// entries for the three FR61 discovery tools: each surfaced with a
/// non-empty priming Description (LLM-side discoverability lock — Epic 8
/// retro AI-4 bug shape) and the expected input_schema
/// properties/required shape.</p>
Method TestRegistryListToolsIncludesDiscoveryTools()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools() returns object")
    Set tEntries = {}
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Do tEntries.%Set(tEntry.%Get("name"), tEntry)
    }

    ; list_active_body_types — run-FIRST priming; optional hours only.
    Set tTool = tEntries.%Get("list_active_body_types")
    Do $$$AssertTrue($IsObject(tTool), "registry surfaces 'list_active_body_types'")
    If $IsObject(tTool) {
        Do $$$AssertTrue(tTool.%Get("description") '= "", "list_active_body_types has non-empty Description")
        Do $$$AssertTrue(tTool.%Get("description") [ "FIRST", "Description primes run-FIRST census usage")
        Set tSchema = tTool.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema) && $IsObject(tSchema.%Get("properties").%Get("hours")), "input_schema carries 'hours' property")
        Set tReq = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tReq) && (tReq.%Size() = 0), "list_active_body_types declares no required args")
    }

    ; describe_message_class — schema.table priming; class_name required.
    Set tTool = tEntries.%Get("describe_message_class")
    Do $$$AssertTrue($IsObject(tTool), "registry surfaces 'describe_message_class'")
    If $IsObject(tTool) {
        Do $$$AssertTrue(tTool.%Get("description") '= "", "describe_message_class has non-empty Description")
        Do $$$AssertTrue(tTool.%Get("description") [ "schema.table", "Description names the authoritative schema.table mapping")
        Set tSchema = tTool.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema) && $IsObject(tSchema.%Get("properties").%Get("class_name")), "input_schema carries 'class_name' property")
        Set tReq = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tReq) && (tReq.%Size() = 1) && (tReq.%Get(0) = "class_name"), "class_name is the single required arg")
    }

    ; discover_tables — INFORMATION_SCHEMA priming; 3 optional properties.
    Set tTool = tEntries.%Get("discover_tables")
    Do $$$AssertTrue($IsObject(tTool), "registry surfaces 'discover_tables'")
    If $IsObject(tTool) {
        Do $$$AssertTrue(tTool.%Get("description") '= "", "discover_tables has non-empty Description")
        Do $$$AssertTrue(tTool.%Get("description") [ "INFORMATION_SCHEMA", "Description names the INFORMATION_SCHEMA source")
        Set tSchema = tTool.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "input_schema present in manifest entry")
        If $IsObject(tSchema) {
            Set tProps = tSchema.%Get("properties")
            Do $$$AssertTrue($IsObject(tProps.%Get("name_fragment")), "name_fragment property present in schema")
            Do $$$AssertTrue($IsObject(tProps.%Get("include_system")), "include_system property present in schema")
            Do $$$AssertTrue($IsObject(tProps.%Get("max_results")), "max_results property present in schema")
        }
    }
    Quit
}

}
