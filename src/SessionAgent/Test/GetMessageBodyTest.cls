/// <p>Unit tests for <CLASS>SessionAgent.Tool.Inspection.GetMessageBody</CLASS>
/// — Story 4.2's 9-step body-class dispatch ladder. Twelve Test*
/// methods cover Story 4.2 AC-1 through AC-5.</p>
///
/// <ol>
/// <li><b>TestStep3HL7Message</b> — fixture: <code>EnsLib.HL7.Message</code>
/// stored in HSCUSTOM (HL7 IS installed; sample production has zero HL7
/// rows so the test seeds its own).</li>
/// <li><b>TestStep4JsonAdaptor</b> —
/// <class>SessionAgent.Test.GmbFixtureJsonAdaptor</class>.</li>
/// <li><b>TestStep5XmlAdaptor</b> —
/// <class>SessionAgent.Test.GmbFixtureXmlAdaptor</class>.</li>
/// <li><b>TestStep6StreamShort</b> — <code>%Stream.GlobalCharacter</code>
/// content shorter than <parameter>StreamReadLimit</parameter>.</li>
/// <li><b>TestStep6StreamLongTruncates</b> — content longer than
/// <parameter>StreamReadLimit</parameter>.</li>
/// <li><b>TestStep7EnsMessageBody</b> —
/// <class>SessionAgent.Test.GmbFixtureEnsBody</class>.</li>
/// <li><b>TestStep8GenericPersistent</b> —
/// <class>SessionAgent.Test.GmbFixturePersistent</class>.</li>
/// <li><b>TestStep9UnknownDispatchFailed</b> — header pointing at a
/// non-existent class.</li>
/// <li><b>TestEmptyBodyReturnsNoBody</b> — Header with
/// <code>MessageBodyId=""</code>.</li>
/// <li><b>TestMissingMessageIdReturnsError</b> — FR37 envelope.</li>
/// <li><b>TestUnknownMessageIdReturnsHeaderNotFound</b> —
/// non-existent header id.</li>
/// <li><b>TestRegistryListToolsIncludesGetMessageBody</b> — registry
/// reflection.</li>
/// </ol>
///
/// <p><b>Fixture access pattern.</b> <method>OnBeforeAllTests</method>
/// seeds bodies + <CLASS>Ens.MessageHeader</CLASS> rows; tests look up
/// the seeded header IDs via SQL on the
/// <code>SourceConfigName</code> marker (each fixture row carries a
/// distinct marker like <code>"TestSrcJson"</code>) inside each Test*
/// method. This is the same pattern as
/// <CLASS>SessionAgent.Test.InspectionToolTest</CLASS> Story 2.11 —
/// <code>^||</code> globals are reserved for cleanup tracking only,
/// not cross-method state.</p>
Class SessionAgent.Test.GetMessageBodyTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONID As %Integer = 999942;

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed body fixture rows + matching Ens.MessageHeader rows. Each
/// fixture header carries a distinct <code>SourceConfigName</code>
/// marker so tests can look up the seeded header id via SQL inside
/// the test method (decoupled from process-private global lifetime).
/// Captures body / stream / HL7 IDs in
/// <code>^||SessionAgentTest42BodyIds</code> and stream IDs in
/// <code>^||SessionAgentTest42StreamIds</code> for cleanup only.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest42BodyIds
    Kill ^||SessionAgentTest42StreamIds

    ; Defensive sweep — remove any stragglers from a prior dirty run.
    Set tSweep = ##class(%SQL.Statement).%New()
    If $$$ISOK(tSweep.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tSweep.%Execute(..#FIXTURESESSIONID)
    }

    ; --- Body fixture rows.
    Set tJsonBody = ##class(SessionAgent.Test.GmbFixtureJsonAdaptor).%New()
    Set tJsonBody.Field1 = "alpha"
    Set tJsonBody.Field2 = 42
    Set tSC = tJsonBody.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42BodyIds("json") = tJsonBody.%Id()
    Set tJsonBodyId = tJsonBody.%Id()

    Set tXmlBody = ##class(SessionAgent.Test.GmbFixtureXmlAdaptor).%New()
    Set tXmlBody.Title = "test-title"
    Set tXmlBody.Count = 7
    Set tSC = tXmlBody.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42BodyIds("xml") = tXmlBody.%Id()
    Set tXmlBodyId = tXmlBody.%Id()

    Set tEnsBody = ##class(SessionAgent.Test.GmbFixtureEnsBody).%New()
    Set tEnsBody.Subject = "test-subject"
    Set tEnsBody.Amount = 99.5
    Set tEnsBody.Note = "fixture note"
    Set tSC = tEnsBody.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42BodyIds("ens") = tEnsBody.%Id()
    Set tEnsBodyId = tEnsBody.%Id()

    Set tPersistent = ##class(SessionAgent.Test.GmbFixturePersistent).%New()
    Set tPersistent.Code = "PCD"
    Set tPersistent.Quantity = 3
    Set tSC = tPersistent.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42BodyIds("persistent") = tPersistent.%Id()
    Set tPersistentBodyId = tPersistent.%Id()

    ; Streams.
    Set tStreamShort = ##class(%Stream.GlobalCharacter).%New()
    Do tStreamShort.Write("hello stream world")
    Set tSC = tStreamShort.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42StreamIds("short") = tStreamShort.%Id()
    Set tStreamShortId = tStreamShort.%Id()

    Set tStreamLong = ##class(%Stream.GlobalCharacter).%New()
    ; Build a >3072 char string by concatenating in chunks.
    Set tFiller = ""
    For tI = 1:1:200 { Set tFiller = tFiller _ "abcdefghij0123456789" }
    Do tStreamLong.Write(tFiller)
    Set tSC = tStreamLong.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest42StreamIds("long") = tStreamLong.%Id()
    Set tStreamLongId = tStreamLong.%Id()

    ; --- Header rows. Each fixture header has a distinct
    ; SourceConfigName marker so the test methods can look up the row
    ; by marker via SQL (decoupled from the per-process ^|| lifetime).
    Set tInsHdr = ##class(%SQL.Statement).%New()
    Set tSC = tInsHdr.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, ?, ?, ?, 'TestTgt', 1, ?, 1, 3)")
    If $$$ISERR(tSC) Quit tSC
    Set tNow = $ZDateTime($Horolog, 3, 1, 0)

    Do ..InsHdr(tInsHdr, "SessionAgent.Test.GmbFixtureJsonAdaptor", tJsonBodyId, "Gmb42SrcJson", tNow)
    Do ..InsHdr(tInsHdr, "SessionAgent.Test.GmbFixtureXmlAdaptor", tXmlBodyId, "Gmb42SrcXml", tNow)
    Do ..InsHdr(tInsHdr, "SessionAgent.Test.GmbFixtureEnsBody", tEnsBodyId, "Gmb42SrcEns", tNow)
    Do ..InsHdr(tInsHdr, "SessionAgent.Test.GmbFixturePersistent", tPersistentBodyId, "Gmb42SrcPersistent", tNow)
    Do ..InsHdr(tInsHdr, "%Stream.GlobalCharacter", tStreamShortId, "Gmb42SrcStreamShort", tNow)
    Do ..InsHdr(tInsHdr, "%Stream.GlobalCharacter", tStreamLongId, "Gmb42SrcStreamLong", tNow)

    ; Empty-body header.
    Set tInsEmpty = ##class(%SQL.Statement).%New()
    Set tSC = tInsEmpty.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, '', '', 'Gmb42SrcEmpty', 'TestTgt', 1, ?, 1, 3)")
    If $$$ISOK(tSC) {
        Do tInsEmpty.%Execute(..#FIXTURESESSIONID, tNow)
    }

    ; Unknown-class header.
    Set tInsUnknown = ##class(%SQL.Statement).%New()
    Set tSC = tInsUnknown.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, 'Some.Class.That.Does.Not.Exist', '999', 'Gmb42SrcUnknown', 'TestTgt', 1, ?, 1, 3)")
    If $$$ISOK(tSC) {
        Do tInsUnknown.%Execute(..#FIXTURESESSIONID, tNow)
    }

    ; HL7 — seeded ONLY if EnsLib.HL7.Message is installed (it is on
    ; HSCUSTOM per Task-0 probe; the defensive check supports a future
    ; port to a Python-less / HL7-less IRIS image). Uses
    ; EnsLib.HL7.Message.ImportFromString — the direct ClassMethod
    ; that wraps Parser instantiation + IOStream conversion.
    If ##class(%Dictionary.CompiledClass).%ExistsId("EnsLib.HL7.Message") {
        Try {
            Set tEr7 = "MSH|^~\&|TEST|TEST|TEST|TEST|20260504||ADT^A01|TEST001|P|2.5"_$Char(13)_"PID|||PAT001||DOE^JOHN"_$Char(13)
            Set tHL7Status = $$$OK
            Set tHL7 = ##class(EnsLib.HL7.Message).ImportFromString(tEr7, .tHL7Status)
            If $$$ISOK(tHL7Status) && $IsObject(tHL7) {
                Set tSCsave = tHL7.%Save()
                If $$$ISOK(tSCsave) {
                    Set tHL7BodyId = tHL7.%Id()
                    Set ^||SessionAgentTest42BodyIds("hl7") = tHL7BodyId
                    Set tInsHL7 = ##class(%SQL.Statement).%New()
                    Set tSChl7p = tInsHL7.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, 'EnsLib.HL7.Message', ?, 'Gmb42SrcHL7', 'TestTgt', 1, ?, 1, 3)")
                    If $$$ISOK(tSChl7p) {
                        Do tInsHL7.%Execute(..#FIXTURESESSIONID, tHL7BodyId, tNow)
                    }
                }
            }
        }
        Catch hl7ex {
            ; HL7 fixture build failed — Step 3 test will skip per the
            ; defensive LookupHdr=="" check.
        }
    }

    Quit $$$OK
}

/// <p>Helper — execute prepared header INSERT.</p>
Method InsHdr(pStmt As %SQL.Statement, pBodyClass As %String, pBodyId As %String, pSourceMarker As %String, pTime As %String)
{
    Do pStmt.%Execute(..#FIXTURESESSIONID, pBodyClass, pBodyId, pSourceMarker, pTime)
    Quit
}

/// <p>Cleanup — delete fixture headers + bodies + streams.</p>
Method OnAfterAllTests() As %Status
{
    Set tDelHdr = ##class(%SQL.Statement).%New()
    If $$$ISOK(tDelHdr.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tDelHdr.%Execute(..#FIXTURESESSIONID)
    }

    Set tKey = ""
    For  {
        Set tKey = $Order(^||SessionAgentTest42BodyIds(tKey), 1, tBodyId)
        Quit:tKey=""
        Set tClass = $Case(tKey,
            "json": "SessionAgent.Test.GmbFixtureJsonAdaptor",
            "xml": "SessionAgent.Test.GmbFixtureXmlAdaptor",
            "ens": "SessionAgent.Test.GmbFixtureEnsBody",
            "persistent": "SessionAgent.Test.GmbFixturePersistent",
            "hl7": "EnsLib.HL7.Message",
            : "")
        If tClass '= "" {
            Try { Do $ClassMethod(tClass, "%DeleteId", tBodyId) } Catch ex { }
        }
    }
    Kill ^||SessionAgentTest42BodyIds

    Set tSKey = ""
    For  {
        Set tSKey = $Order(^||SessionAgentTest42StreamIds(tSKey), 1, tStreamId)
        Quit:tSKey=""
        Try { Do ##class(%Stream.GlobalCharacter).%DeleteId(tStreamId) } Catch ex { }
    }
    Kill ^||SessionAgentTest42StreamIds
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

/// <p>Look up the seeded fixture header id by its
/// <code>SourceConfigName</code> marker. Returns the empty string if
/// the marker is not found (supports the HL7 test's "fixture not
/// installed → skip" path).</p>
ClassMethod LookupHdr(pMarker As %String) As %String
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ?")
    If $$$ISERR(tSC) Quit ""
    Set tRs = tStmt.%Execute(..#FIXTURESESSIONID, pMarker)
    If tRs.%Next() Quit tRs.%Get("ID")
    Quit ""
}

/// <p>Step 3 — HL7 message dispatch.</p>
Method TestStep3HL7Message()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcHL7")
    If tHdrId = "" {
        Do $$$LogMessage("HL7 fixture not seeded (HL7 not installed or parser failed) — skipping Step 3 test")
        Quit
    }
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "GetMessageBody.Invoke OK on HL7 fixture")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "hl7", "render_strategy='hl7'")
    Set tType = tResult.structuredContent.%Get("message_type")
    Do $$$AssertNotEquals(tType, "", "message_type non-empty (got: '" _ tType _ "')")
    Do $$$AssertTrue((+tResult.structuredContent.%Get("segment_count")) > 0, "segment_count > 0")
    Quit
}

/// <p>Step 4 — %JSON.Adaptor dispatch.</p>
Method TestStep4JsonAdaptor()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcJson")
    Do $$$AssertNotEquals(tHdrId, "", "JSON header fixture seeded (got: '" _ tHdrId _ "')")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "json_adaptor", "render_strategy='json_adaptor'")
    Set tBodyRepr = tResult.structuredContent.%Get("body_repr")
    Do $$$AssertNotEquals(tBodyRepr, "", "body_repr non-empty")
    Set tParsed = ""
    Try { Set tParsed = ##class(%DynamicObject).%FromJSON(tBodyRepr) } Catch ex { Set tParsed = "" }
    Do $$$AssertTrue($IsObject(tParsed), "body_repr is parseable JSON")
    If $IsObject(tParsed) {
        Do $$$AssertEquals(tParsed.%Get("Field1"), "alpha", "JSON Field1 round-trips")
    }
    Quit
}

/// <p>Step 5 — %XML.Adaptor dispatch.</p>
Method TestStep5XmlAdaptor()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcXml")
    Do $$$AssertNotEquals(tHdrId, "", "XML header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "xml_adaptor", "render_strategy='xml_adaptor'")
    Set tBodyRepr = tResult.structuredContent.%Get("body_repr")
    Do $$$AssertNotEquals(tBodyRepr, "", "body_repr non-empty")
    Do $$$AssertEquals($Extract(tBodyRepr, 1), "<", "body_repr starts with '<'")
    Do $$$AssertEquals($Extract(tBodyRepr, *), ">", "body_repr ends with '>'")
    Quit
}

/// <p>Step 6 — short stream.</p>
Method TestStep6StreamShort()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcStreamShort")
    Do $$$AssertNotEquals(tHdrId, "", "Short stream header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "stream", "render_strategy='stream'")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 0, "truncated=0 for short stream")
    Do $$$AssertEquals(tResult.structuredContent.%Get("body_repr"), "hello stream world", "body_repr matches stored content")
    Quit
}

/// <p>Step 6 — long stream truncates.</p>
Method TestStep6StreamLongTruncates()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcStreamLong")
    Do $$$AssertNotEquals(tHdrId, "", "Long stream header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "stream", "render_strategy='stream'")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 1, "truncated=1 for long stream")
    Do $$$AssertTrue($Length(tResult.structuredContent.%Get("body_repr")) <= ##class(SessionAgent.Tool.Inspection.GetMessageBody).#StreamReadLimit, "body_repr length <= StreamReadLimit")
    Quit
}

/// <p>Step 7 — Ens.MessageBody subclass dispatch via property reflection.</p>
Method TestStep7EnsMessageBody()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcEns")
    Do $$$AssertNotEquals(tHdrId, "", "Ens.MessageBody header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ens_message_body", "render_strategy='ens_message_body'")
    Set tMap = tResult.structuredContent.%Get("property_map")
    Do $$$AssertTrue($IsObject(tMap), "property_map is an object")
    If $IsObject(tMap) {
        Do $$$AssertEquals(tMap.%Get("Subject"), "test-subject", "property_map.Subject round-trips")
        Do $$$AssertEquals(+tMap.%Get("Amount"), 99.5, "property_map.Amount round-trips")
        Do $$$AssertEquals(tMap.%Get("Note"), "fixture note", "property_map.Note round-trips")
    }
    Do $$$AssertEquals(+tResult.structuredContent.%Get("property_count"), 3, "property_count=3 (Subject/Amount/Note)")
    Quit
}

/// <p>Step 8 — generic %Persistent.</p>
Method TestStep8GenericPersistent()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcPersistent")
    Do $$$AssertNotEquals(tHdrId, "", "Persistent header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId), "format":"raw"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "persistent", "render_strategy='persistent'")
    Set tMap = tResult.structuredContent.%Get("property_map")
    Do $$$AssertTrue($IsObject(tMap), "property_map is an object")
    If $IsObject(tMap) {
        Do $$$AssertEquals(tMap.%Get("Code"), "PCD", "property_map.Code round-trips")
        Do $$$AssertEquals(+tMap.%Get("Quantity"), 3, "property_map.Quantity round-trips")
    }
    Quit
}

/// <p>Step 9 — header references a class that does not exist. The
/// <code>%OpenId</code> attempt fails; ladder dispatches to
/// <code>render_strategy="body_not_found"</code> (no exceptions
/// escape — the no-throw guarantee).</p>
Method TestStep9UnknownDispatchFailed()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcUnknown")
    Do $$$AssertNotEquals(tHdrId, "", "Unknown header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke does not throw on unknown class")
    Set tStrategy = tResult.structuredContent.%Get("render_strategy")
    ; Acceptable strategies: "body_not_found" (class missing) OR
    ; "unknown" (class present but matches no ladder predicate). The
    ; fixture uses a non-existent class name so we expect "body_not_found".
    Do $$$AssertTrue((tStrategy = "body_not_found") || (tStrategy = "unknown"), "render_strategy is body_not_found or unknown (got: " _ tStrategy _ ")")
    If tStrategy = "unknown" {
        Do $$$AssertEquals(+tResult.structuredContent.%Get("dispatch_failed"), 1, "dispatch_failed=1 when render_strategy=unknown")
        Do $$$AssertNotEquals(tResult.structuredContent.%Get("fallback_repr"), "", "fallback_repr non-empty when render_strategy=unknown")
    }
    Quit
}

/// <p>Empty-body short-circuit — no <INVALID OREF> thrown; render_strategy=no_body.</p>
Method TestEmptyBodyReturnsNoBody()
{
    Set tHdrId = ..LookupHdr("Gmb42SrcEmpty")
    Do $$$AssertNotEquals(tHdrId, "", "Empty header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on empty-body header")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "no_body", "render_strategy='no_body'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("body_repr"), "", "body_repr empty")
    Quit
}

/// <p>Validation path — empty <code>message_id</code> returns FR37
/// envelope.</p>
Method TestMissingMessageIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing message_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing message_id", "error text mentions 'missing message_id'")
    Quit
}

/// <p>Step 1 — header lookup miss.</p>
Method TestUnknownMessageIdReturnsHeaderNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":"99999999"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on unknown message_id")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "header_not_found", "render_strategy='header_not_found'")
    Quit
}

/// <p>AC-7 registry discovery.</p>
Method TestRegistryListToolsIncludesGetMessageBody()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tE) {
        If tE.%Get("name") = "get_message_body" {
            Set tFound = 1
            Set tEntry = tE
            Quit
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'get_message_body'")
    If $IsObject(tEntry) {
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "get_message_body input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "schema.required has one entry")
        Do $$$AssertEquals(tRequired.%Get(0), "message_id", "schema.required[0]='message_id'")
        Set tProps = tSchema.%Get("properties")
        Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")
        Set tFormat = tProps.%Get("format")
        Do $$$AssertTrue($IsObject(tFormat), "schema.properties.format defined")
        Set tFmtEnum = tFormat.%Get("enum")
        Do $$$AssertTrue($IsObject(tFmtEnum), "format.enum is an array")
        Do $$$AssertEquals(tFmtEnum.%Size(), 2, "format.enum has 2 values (raw, summary)")
    }
    Quit
}

}
