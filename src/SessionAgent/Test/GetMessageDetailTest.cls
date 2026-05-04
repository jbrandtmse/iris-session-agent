/// <p>Unit tests for <CLASS>SessionAgent.Tool.Inspection.GetMessageDetail</CLASS>
/// — Story 4.3's one-shot single-message readout that composes
/// header (Story 2.11 pattern) + body (Story 4.2 GetMessageBody direct
/// call) + rule decisions (Story 4.1 RuleLog column mapping). Six
/// named tests cover Story 4.3 AC-3 and AC-4.</p>
///
/// <ol>
/// <li><b>TestFullPayloadHeaderBodyRuleDecisions</b> — fixture: header
/// + <CLASS>SessionAgent.Test.GmbFixtureEnsBody</CLASS> body (reused
/// from Story 4.2) + 2 <CLASS>Ens.Rule.Log</CLASS> rows whose
/// <code>CurrentHeaderId</code> matches the header id. Asserts
/// header populated, <code>body_render_strategy="ens_message_body"</code>,
/// <code>rule_decision_count=2</code>.</li>
/// <li><b>TestNoBodyReturnsEmptyBodyRepr</b> — header with empty
/// <code>MessageBodyId</code>. Asserts <code>body_render_strategy=
/// "no_body"</code>, <code>body_repr=""</code>, summary text notes
/// the absence.</li>
/// <li><b>TestNoRuleDecisionsReturnsEmptyArray</b> — header with no
/// matching <code>Ens.Rule.Log</code> rows. Asserts
/// <code>rule_decisions=[]</code>, <code>rule_decision_count=0</code>.</li>
/// <li><b>TestMissingMessageIdReturnsError</b> — FR37 envelope.</li>
/// <li><b>TestUnknownMessageIdReturnsHeaderNotFound</b> — non-existent
/// header id → <code>render_strategy="header_not_found"</code>.</li>
/// <li><b>TestRegistryListToolsIncludesGetMessageDetail</b> —
/// <method>SessionAgent.Tool.Registry.ListTools</method> includes
/// <code>get_message_detail</code> with the AC-2 schema.</li>
/// </ol>
///
/// <p><b>Fixture access pattern.</b> <method>OnBeforeAllTests</method>
/// seeds bodies + headers + rule-log rows; tests look up the seeded
/// header IDs via SQL on the <code>SourceConfigName</code> marker (each
/// fixture row carries a distinct marker like <code>"Gmd43SrcEns"</code>)
/// inside each Test* method. Same pattern as
/// <CLASS>SessionAgent.Test.GetMessageBodyTest</CLASS>.</p>
Class SessionAgent.Test.GetMessageDetailTest Extends %UnitTest.TestCase
{

Parameter FIXTURESESSIONID As %Integer = 999943;

/// <p>Constructor — accepts <code>initvalue</code> per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed body + header + rule-log fixture rows. Each fixture header
/// carries a distinct <code>SourceConfigName</code> marker so tests can
/// look up the seeded header id via SQL inside the test method
/// (decoupled from process-private global lifetime). Captures body IDs
/// and rule-log IDs in <code>^||SessionAgentTest43*</code> for
/// cleanup.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentTest43BodyIds
    Kill ^||SessionAgentTest43RuleLogIds

    ; Defensive sweep — remove any stragglers from a prior dirty run.
    Set tSweepHdr = ##class(%SQL.Statement).%New()
    If $$$ISOK(tSweepHdr.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tSweepHdr.%Execute(..#FIXTURESESSIONID)
    }
    Set tSweepRule = ##class(%SQL.Statement).%New()
    If $$$ISOK(tSweepRule.%Prepare("DELETE FROM Ens_Rule.Log WHERE SessionId = ?")) {
        Do tSweepRule.%Execute(..#FIXTURESESSIONID)
    }

    ; --- Body fixture (reuse Story 4.2 GmbFixtureEnsBody) ---
    Set tEnsBody = ##class(SessionAgent.Test.GmbFixtureEnsBody).%New()
    Set tEnsBody.Subject = "detail-test-subject"
    Set tEnsBody.Amount = 123.45
    Set tEnsBody.Note = "Story 4.3 detail fixture"
    Set tSC = tEnsBody.%Save()
    If $$$ISERR(tSC) Quit tSC
    Set ^||SessionAgentTest43BodyIds("ens") = tEnsBody.%Id()
    Set tEnsBodyId = tEnsBody.%Id()

    ; --- Header rows. Each fixture has a distinct SourceConfigName marker.
    Set tInsHdr = ##class(%SQL.Statement).%New()
    Set tSC = tInsHdr.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, ?, ?, ?, 'TestTgt', 1, ?, 1, 3)")
    If $$$ISERR(tSC) Quit tSC
    Set tNow = $ZDateTime($Horolog, 3, 1, 0)

    ; Header A — full-payload (body + rule decisions).
    Do tInsHdr.%Execute(..#FIXTURESESSIONID, "SessionAgent.Test.GmbFixtureEnsBody", tEnsBodyId, "Gmd43SrcEns", tNow)

    ; Header B — empty body (MessageBodyId="").
    Set tInsEmpty = ##class(%SQL.Statement).%New()
    Set tSC = tInsEmpty.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName, Status, TimeCreated, Type, Priority) VALUES (?, '', '', 'Gmd43SrcEmpty', 'TestTgt', 1, ?, 1, 3)")
    If $$$ISOK(tSC) {
        Do tInsEmpty.%Execute(..#FIXTURESESSIONID, tNow)
    }

    ; Header C — body + NO rule decisions (separate from A so the empty-array
    ; test can't be confused with the full-payload test).
    Set tBodyC = ##class(SessionAgent.Test.GmbFixtureEnsBody).%New()
    Set tBodyC.Subject = "no-rules-subject"
    Set tBodyC.Amount = 1.0
    Set tBodyC.Note = "no-rules"
    Set tSCC = tBodyC.%Save()
    If $$$ISOK(tSCC) {
        Set ^||SessionAgentTest43BodyIds("noRules") = tBodyC.%Id()
        Do tInsHdr.%Execute(..#FIXTURESESSIONID, "SessionAgent.Test.GmbFixtureEnsBody", tBodyC.%Id(), "Gmd43SrcNoRules", tNow)
    }

    ; --- Rule log rows targeting Header A (the full-payload header) ---
    ; Look up the seeded header A id first.
    Set tHdrAId = ..LookupHdrSeed("Gmd43SrcEns")
    If tHdrAId '= "" {
        ; Use the canonical Ens.Rule.Log.Log() helper if signature allows;
        ; simpler to INSERT directly via SQL with explicit column list.
        Set tInsRule = ##class(%SQL.Statement).%New()
        Set tSCprep = tInsRule.%Prepare("INSERT INTO Ens_Rule.Log (SessionId, TimeExecuted, RuleName, RuleSet, ActivityName, Reason, ReturnValue, ErrorMsg, IsError, ConfigName, CurrentHeaderId) VALUES (?, ?, ?, ?, ?, ?, ?, '', 0, ?, ?)")
        If $$$ISOK(tSCprep) {
            Do tInsRule.%Execute(..#FIXTURESESSIONID, tNow, "Gmd43.RuleAlpha", "v1", "Eval", "matched alpha condition", "alpha", "Gmd43.OrderRouter", tHdrAId)
            ; Capture inserted IDs for cleanup. We rely on the post-insert
            ; lookup by SessionId+RuleName since INSERT...VALUES doesn't
            ; return the id directly.
            Do tInsRule.%Execute(..#FIXTURESESSIONID, tNow, "Gmd43.RuleBeta", "v1", "Eval", "matched beta condition", "beta", "Gmd43.OrderRouter", tHdrAId)
        }
    }

    Quit $$$OK
}

/// <p>Helper used inside <method>OnBeforeAllTests</method> only — the
/// full <method>LookupHdr</method> needs to be reusable across
/// before-all and per-test contexts so a separate ClassMethod variant
/// keeps the seed-time lookup self-contained.</p>
Method LookupHdrSeed(pMarker As %String) As %String
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ?")
    If $$$ISERR(tSC) Quit ""
    Set tRs = tStmt.%Execute(..#FIXTURESESSIONID, pMarker)
    If tRs.%Next() Quit tRs.%Get("ID")
    Quit ""
}

/// <p>Cleanup — delete fixture headers + bodies + rule-log rows.</p>
Method OnAfterAllTests() As %Status
{
    Set tDelHdr = ##class(%SQL.Statement).%New()
    If $$$ISOK(tDelHdr.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tDelHdr.%Execute(..#FIXTURESESSIONID)
    }
    Set tDelRule = ##class(%SQL.Statement).%New()
    If $$$ISOK(tDelRule.%Prepare("DELETE FROM Ens_Rule.Log WHERE SessionId = ?")) {
        Do tDelRule.%Execute(..#FIXTURESESSIONID)
    }

    Set tKey = ""
    For  {
        Set tKey = $Order(^||SessionAgentTest43BodyIds(tKey), 1, tBodyId)
        Quit:tKey=""
        Try { Do ##class(SessionAgent.Test.GmbFixtureEnsBody).%DeleteId(tBodyId) } Catch ex { }
    }
    Kill ^||SessionAgentTest43BodyIds
    Kill ^||SessionAgentTest43RuleLogIds
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
/// <code>SourceConfigName</code> marker.</p>
ClassMethod LookupHdr(pMarker As %String) As %String
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ?")
    If $$$ISERR(tSC) Quit ""
    Set tRs = tStmt.%Execute(..#FIXTURESESSIONID, pMarker)
    If tRs.%Next() Quit tRs.%Get("ID")
    Quit ""
}

/// <p>AC-3 + AC-4 #1 — full-payload composition. Header has body,
/// rule decisions trigger on this header id.</p>
Method TestFullPayloadHeaderBodyRuleDecisions()
{
    Set tHdrId = ..LookupHdr("Gmd43SrcEns")
    Do $$$AssertNotEquals(tHdrId, "", "Gmd43SrcEns header fixture seeded (got: '" _ tHdrId _ "')")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageDetail).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on full-payload header")

    Set tInner = tResult.structuredContent
    Do $$$AssertTrue($IsObject(tInner), "structuredContent populated")

    ; Header populated.
    Set tHdr = tInner.%Get("header")
    Do $$$AssertTrue($IsObject(tHdr), "header is an object")
    Do $$$AssertEquals(+tHdr.%Get("id"), +tHdrId, "header.id matches fixture")
    Do $$$AssertEquals(tHdr.%Get("source_config_name"), "Gmd43SrcEns", "header.source_config_name = Gmd43SrcEns")
    Do $$$AssertEquals(tHdr.%Get("target_config_name"), "TestTgt", "header.target_config_name = TestTgt")
    Do $$$AssertEquals(+tHdr.%Get("session_id"), ..#FIXTURESESSIONID, "header.session_id matches fixture session")
    Do $$$AssertEquals(tHdr.%Get("body_class"), "SessionAgent.Test.GmbFixtureEnsBody", "header.body_class matches fixture")

    ; Body summary — render strategy = ens_message_body.
    Do $$$AssertEquals(tInner.%Get("body_render_strategy"), "ens_message_body", "body_render_strategy='ens_message_body'")
    Do $$$AssertEquals(tInner.%Get("body_class"), "SessionAgent.Test.GmbFixtureEnsBody", "body_class mirrored to top level")
    Do $$$AssertNotEquals(tInner.%Get("body_summary"), "", "body_summary non-empty")
    Do $$$AssertNotEquals(tInner.%Get("body_repr"), "", "body_repr non-empty")

    ; Rule decisions — exactly 2 with our seeded fixture rows.
    Set tDecisions = tInner.%Get("rule_decisions")
    Do $$$AssertTrue($IsObject(tDecisions), "rule_decisions is an array")
    Do $$$AssertEquals(+tInner.%Get("rule_decision_count"), 2, "rule_decision_count=2")
    Do $$$AssertEquals(tDecisions.%Size(), 2, "rule_decisions array length = 2")
    ; Spot-check the first decision's columns map correctly.
    Set tD0 = tDecisions.%Get(0)
    Do $$$AssertTrue($IsObject(tD0), "decision[0] is an object")
    Set tName = tD0.%Get("rule_name")
    Do $$$AssertTrue((tName = "Gmd43.RuleAlpha") || (tName = "Gmd43.RuleBeta"), "decision[0].rule_name is one of the seeded rules (got: '" _ tName _ "')")
    Do $$$AssertEquals(tD0.%Get("component"), "Gmd43.OrderRouter", "decision[0].component = ConfigName mapped")
    Quit
}

/// <p>AC-4 #2 — empty body returns empty body_repr +
/// render_strategy="no_body".</p>
Method TestNoBodyReturnsEmptyBodyRepr()
{
    Set tHdrId = ..LookupHdr("Gmd43SrcEmpty")
    Do $$$AssertNotEquals(tHdrId, "", "Empty header fixture seeded (got: '" _ tHdrId _ "')")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageDetail).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on empty-body header")

    Set tInner = tResult.structuredContent
    Do $$$AssertEquals(tInner.%Get("body_render_strategy"), "no_body", "body_render_strategy='no_body'")
    Do $$$AssertEquals(tInner.%Get("body_repr"), "", "body_repr empty")

    ; Summary text notes the absence.
    Set tSummaryText = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummaryText [ "no body", "summary text mentions 'no body' (got: '" _ tSummaryText _ "')")
    Quit
}

/// <p>AC-4 #3 — header with no matching rule-log rows.</p>
Method TestNoRuleDecisionsReturnsEmptyArray()
{
    Set tHdrId = ..LookupHdr("Gmd43SrcNoRules")
    Do $$$AssertNotEquals(tHdrId, "", "NoRules header fixture seeded")
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":(tHdrId)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageDetail).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on no-rules header")

    Set tInner = tResult.structuredContent
    Set tDecisions = tInner.%Get("rule_decisions")
    Do $$$AssertTrue($IsObject(tDecisions), "rule_decisions is an array")
    Do $$$AssertEquals(tDecisions.%Size(), 0, "rule_decisions array length = 0")
    Do $$$AssertEquals(+tInner.%Get("rule_decision_count"), 0, "rule_decision_count = 0")
    Quit
}

/// <p>AC-4 #4 — empty <code>message_id</code> returns FR37 envelope.</p>
Method TestMissingMessageIdReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageDetail).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns OK on validation failure")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing message_id")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "missing message_id", "error text mentions 'missing message_id'")
    Quit
}

/// <p>AC-4 #5 — non-existent header id → render_strategy="header_not_found".</p>
Method TestUnknownMessageIdReturnsHeaderNotFound()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_id":"99999999"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetMessageDetail).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke OK on unknown message_id")
    Set tInner = tResult.structuredContent
    Do $$$AssertEquals(tInner.%Get("render_strategy"), "header_not_found", "render_strategy='header_not_found'")
    Do $$$AssertEquals(+tInner.%Get("rule_decision_count"), 0, "rule_decision_count=0 on header_not_found")
    Quit
}

/// <p>AC-4 #6 — registry surfaces <code>get_message_detail</code> with
/// the AC-2 schema.</p>
Method TestRegistryListToolsIncludesGetMessageDetail()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFound = 0
    Set tEntry = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tE) {
        If tE.%Get("name") = "get_message_detail" {
            Set tFound = 1
            Set tEntry = tE
            Quit
        }
    }
    Do $$$AssertTrue(tFound, "Registry surfaces 'get_message_detail'")
    If $IsObject(tEntry) {
        Set tSchema = tEntry.%Get("input_schema")
        Do $$$AssertTrue($IsObject(tSchema), "get_message_detail input_schema is an object")
        Set tRequired = tSchema.%Get("required")
        Do $$$AssertTrue($IsObject(tRequired), "schema.required is an array")
        Do $$$AssertEquals(tRequired.%Size(), 1, "schema.required has one entry")
        Do $$$AssertEquals(tRequired.%Get(0), "message_id", "schema.required[0]='message_id'")
        Set tProps = tSchema.%Get("properties")
        Do $$$AssertTrue($IsObject(tProps), "schema.properties is an object")
        Set tMsgId = tProps.%Get("message_id")
        Do $$$AssertTrue($IsObject(tMsgId), "schema.properties.message_id defined")
        ; AC-2: no optional inputs in v1 — only message_id.
        Set tAddl = tSchema.%Get("additionalProperties")
        Do $$$AssertEquals(+tAddl, 0, "additionalProperties=false")
    }
    Quit
}

}
