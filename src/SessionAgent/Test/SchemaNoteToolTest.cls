/// <p>Story 14.4 AC-1 / AC-2 / AC-3 — tests for the
/// <CLASS>SessionAgent.Knowledge.SchemaNote</CLASS> persistent class
/// (upsert semantics) and the <code>save_schema_note</code> tool
/// (<CLASS>SessionAgent.Tool.Inspection.SaveSchemaNote</CLASS>):
/// validation envelopes, e2e Registry dispatch, the forced write-failure
/// envelope, the Rule 8 defensive surfaces (source-introspection per the
/// Epic 12 AI-5 substring-grep binding), the audit-row landing (bounded
/// exit-early poll per the Story 14.0 SweepTaskTest precedent), and the
/// ListTools manifest lock.</p>
///
/// <p>Retrieval-side tests live in
/// <CLASS>SessionAgent.Test.GetSchemaNotesTest</CLASS>; digest tests in
/// <CLASS>SessionAgent.Test.SchemaNoteDigestTest</CLASS> (split per
/// .claude/rules/object-script-testing.md §"Test Class Size").</p>
Class SessionAgent.Test.SchemaNoteToolTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Delete every <code>ztest-</code>-prefixed SchemaNote fixture row
/// (test-fixture subject convention shared with
/// InspectionSuiteVerificationTest / GetSchemaNotesTest). Returns a
/// failure <code>%Status</code> when the DELETE itself fails (Story 14.4
/// review fix — a silently failed sweep poisons the digest-dependent
/// suites; project rule §"Write Status Checking").</p>
ClassMethod DeleteFixtureRows() As %Status
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("DELETE FROM SessionAgent_Knowledge.SchemaNote WHERE %EXACT(Subject) %STARTSWITH 'ztest-'")
    If $$$ISERR(tPrepSC) Quit tPrepSC
    Set tRs = tStmt.%Execute()
    If tRs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SchemaNote fixture sweep DELETE failed: SQLCODE=" _ tRs.%SQLCODE _ " " _ $Get(tRs.%Message))
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Quit ..DeleteFixtureRows()
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Quit ..DeleteFixtureRows()
}

/// <p>CallerContext fixture — same shape as
/// InspectionSuiteVerificationTest.BuildCtx.</p>
ClassMethod BuildCtx(pAgentName As %String = "session-inspection") As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = pAgentName
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-1 — upsert on an existing (Namespace, Subject) overwrites Body
/// and refreshes VerifiedAt without inserting a duplicate row; the
/// ByRef pAction/pAuditEmitted surfaces report truthfully.</p>
Method TestUpsertCreatesThenOverwrites()
{
    Set tAction = ""
    Set tAudit = 0
    Set tSC = ##class(SessionAgent.Knowledge.SchemaNote).Upsert($NAMESPACE, "ztest-upsert-ac1", "first body", "session-inspection", .tAction, .tAudit)
    Do $$$AssertStatusOK(tSC, "first Upsert returns $$$OK")
    Do $$$AssertEquals(tAction, "created", "first Upsert action = 'created'")
    Do $$$AssertEquals(tAudit, 1, "first Upsert audit_emitted = 1 (triple pre-registered)")

    Set tRow1 = ##class(SessionAgent.Knowledge.SchemaNote).NsSubjectIdxOpen($NAMESPACE, "ztest-upsert-ac1")
    Do $$$AssertTrue($IsObject(tRow1), "row exists after first Upsert")
    Set tFirstVerifiedAt = tRow1.VerifiedAt
    Do tRow1.%Close()

    ; Ensure the refresh is observable at 1-second %TimeStamp resolution.
    Hang 1.1

    Set tAction2 = ""
    Set tAudit2 = 0
    Set tSC2 = ##class(SessionAgent.Knowledge.SchemaNote).Upsert($NAMESPACE, "ztest-upsert-ac1", "second body OVERWRITES", "message-search", .tAction2, .tAudit2)
    Do $$$AssertStatusOK(tSC2, "second Upsert returns $$$OK")
    Do $$$AssertEquals(tAction2, "updated", "second Upsert action = 'updated'")

    ; No duplicate row + overwritten body + refreshed VerifiedAt.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tStmt.%Prepare("SELECT COUNT(*) AS Cnt, MAX(%EXACT(Body)) AS Bod, MAX(VerifiedAt) AS Va, MAX(%EXACT(SourceAgent)) AS Sa FROM SessionAgent_Knowledge.SchemaNote WHERE %EXACT(Namespace) = ? AND %EXACT(Subject) = ?"), "probe prepare OK")
    Set tRs = tStmt.%Execute($NAMESPACE, "ztest-upsert-ac1")
    Do $$$AssertTrue(tRs.%Next(), "probe returns a row")
    Do $$$AssertEquals(+tRs.%Get("Cnt"), 1, "exactly 1 row after two upserts (no duplicate)")
    Do $$$AssertEquals(tRs.%Get("Bod"), "second body OVERWRITES", "Body overwritten by second Upsert")
    Do $$$AssertTrue(tRs.%Get("Va") ] tFirstVerifiedAt, "VerifiedAt refreshed (second " _ tRs.%Get("Va") _ " > first " _ tFirstVerifiedAt _ ")")
    Do $$$AssertEquals(tRs.%Get("Sa"), "message-search", "SourceAgent updated by second Upsert")
    Quit
}

/// <p>AC-2 "Then" / in-story Integration AC — e2e
/// <method>SessionAgent.Tool.Registry.Dispatch</method> persists a row;
/// envelope carries action / verified_at / audit_emitted / source_agent;
/// a second dispatch on the same subject reports 'updated' and keeps
/// the row count at 1.</p>
Method TestSaveToolDispatchPersistsRow()
{
    Set tArgs = {"subject":"ztest-save-e2e","note":"e2e dispatch fixture note"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("save_schema_note", ..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope on valid save")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("action"), "created", "action = 'created' on first save")
    Do $$$AssertEquals(tResult.structuredContent.%Get("namespace"), $NAMESPACE, "namespace taken from CallerContext")
    Do $$$AssertEquals(tResult.structuredContent.%Get("source_agent"), "session-inspection", "source_agent from CallerContext.AgentName")
    Do $$$AssertNotEquals(tResult.structuredContent.%Get("verified_at"), "", "verified_at populated")
    Do $$$AssertEquals(tResult.structuredContent.%Get("audit_emitted"), 1, "audit_emitted = 1 (ByRef surface truthful)")

    ; SQL probe — the row landed.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Knowledge.SchemaNote WHERE %EXACT(Namespace) = ? AND %EXACT(Subject) = ?"), "probe prepare OK")
    Set tRs = tStmt.%Execute($NAMESPACE, "ztest-save-e2e")
    Do $$$AssertTrue(tRs.%Next(), "probe returns a row")
    Do $$$AssertEquals(+tRs.%Get("Cnt"), 1, "1 row persisted by the dispatch")

    ; Second dispatch upserts.
    Set tArgs2 = {"subject":"ztest-save-e2e","note":"updated fixture note"}
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Registry).Dispatch("save_schema_note", ..BuildCtx(), tArgs2, .tResult2)
    Do $$$AssertStatusOK(tSC2, "second Dispatch returns $$$OK")
    Do $$$AssertEquals(tResult2.structuredContent.%Get("action"), "updated", "action = 'updated' on re-save")
    Set tRs2 = tStmt.%Execute($NAMESPACE, "ztest-save-e2e")
    Do $$$AssertTrue(tRs2.%Next(), "re-probe returns a row")
    Do $$$AssertEquals(+tRs2.%Get("Cnt"), 1, "still 1 row after upsert")
    Quit
}

/// <p>AC-2 — server-side validation envelopes (FR37 shape): missing
/// subject, over-length subject, missing note, over-length note.</p>
Method TestSaveToolValidationEnvelopes()
{
    ; Missing subject.
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(..BuildCtx(), {"note":"x"}, .tResult), "Invoke $$$OK (missing subject)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing subject")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "non-empty 'subject'", "operator text names missing subject")

    ; Over-length subject (300 chars > 256).
    Set tLongSubject = "ztest-" _ $Translate($Justify("", 300), " ", "s")
    Set tArgs = {} Do tArgs.%Set("subject", tLongSubject) Do tArgs.%Set("note", "x")
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(..BuildCtx(), tArgs, .tResult), "Invoke $$$OK (long subject)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on over-length subject")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "exceeds 256", "operator text names the 256 limit")

    ; Missing note.
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(..BuildCtx(), {"subject":"ztest-v"}, .tResult), "Invoke $$$OK (missing note)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing note")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "non-empty 'note'", "operator text names missing note")

    ; Over-length note (4100 chars > 4000).
    Set tLongNote = $Translate($Justify("", 4100), " ", "n")
    Set tArgs2 = {} Do tArgs2.%Set("subject", "ztest-v2") Do tArgs2.%Set("note", tLongNote)
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(..BuildCtx(), tArgs2, .tResult), "Invoke $$$OK (long note)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on over-length note")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "exceeds 4000", "operator text names the 4000 limit")
    Quit
}

/// <p>AC-2 — namespace comes from the CallerContext ONLY: an empty
/// Namespace returns the trust-boundary error envelope; the LLM cannot
/// supply a namespace argument (locked-subset schema has no such
/// property — also asserted via the manifest lock below).</p>
Method TestSaveToolMissingNamespaceReturnsError()
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = ""
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(tCtx, {"subject":"ztest-ns","note":"x"}, .tResult), "Invoke $$$OK (empty namespace)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on empty CallerContext.Namespace")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "CallerContext.Namespace", "operator text names the trust-boundary contract")
    Quit
}

/// <p>AC-2 "Then" — forced write-failure path: a CallerContext whose
/// Namespace exceeds the SchemaNote.Namespace MAXLEN=64 makes
/// <code>%Save()</code> fail inside <method>Upsert</method>; the tool
/// surfaces the canonical error envelope (Rule 8 surfaces b + c) with
/// <code>render_strategy="write_error"</code> — never a bare %Status,
/// never a silent success.</p>
Method TestSaveToolWriteFailureReturnsErrorEnvelope()
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $Translate($Justify("", 70), " ", "N") ; 70 chars > MAXLEN 64
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(tCtx, {"subject":"ztest-fail","note":"x"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK (envelope-based error contract)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on forced %Save failure")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "write failed", "operator text names the write failure")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "write_error", "render_strategy = 'write_error'")
    Do $$$AssertNotEquals(tResult.structuredContent.%Get("error_text"), "", "error_text carries the %Status detail")
    Quit
}

/// <p>AC-2 — control-char normalization (Story 14.1 keyword precedent):
/// tabs/newlines/NUL in the subject normalize to spaces + trim; NUL in
/// the note is stripped so the $Char(0) sentinel can never collide with
/// stored content.</p>
Method TestSaveToolControlCharNormalization()
{
    Set tArgs = {}
    Do tArgs.%Set("subject", "  ztest-ctl" _ $Char(9) _ "norm" _ $Char(10) _ " ")
    Do tArgs.%Set("note", "line1" _ $Char(0) _ "line2")
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.SaveSchemaNote).Invoke(..BuildCtx(), tArgs, .tResult), "Invoke $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope")
    Set tStoredSubject = tResult.structuredContent.%Get("subject")
    Do $$$AssertEquals(tStoredSubject, "ztest-ctl norm", "subject control chars normalized to spaces + trimmed (got: '" _ tStoredSubject _ "')")
    Set tRow = ##class(SessionAgent.Knowledge.SchemaNote).NsSubjectIdxOpen($NAMESPACE, tStoredSubject)
    Do $$$AssertTrue($IsObject(tRow), "normalized-subject row persisted")
    If $IsObject(tRow) {
        Do $$$AssertTrue(tRow.Body '[ $Char(0), "NUL stripped from stored note body")
        Do $$$AssertEquals(tRow.Body, "line1line2", "note body NUL removed verbatim")
        Do tRow.%Close()
    }
    ; Direct cleanup (the normalized subject still starts with ztest-).
    Quit
}

/// <p>AC-2 — Rule 8 defensive surfaces locked via source-introspection
/// (Epic 12 AI-5 substring-grep binding): (a) the ByRef audit-emitted
/// channel, (b) the %Save status check, (c) the error-envelope shaping
/// are all present in the compiled sources.</p>
Method TestDefensiveSurfacesSourceIntrospection()
{
    ; --- SchemaNote.Upsert: %Save status check + ByRef pAuditEmitted ---
    Set tUpsert = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Knowledge.SchemaNote||Upsert")
    Do $$$AssertTrue($IsObject(tUpsert), "SchemaNote.Upsert is defined")
    If '$IsObject(tUpsert) Quit
    Do tUpsert.Implementation.Rewind()
    Set tBody = ""
    While 'tUpsert.Implementation.AtEnd { Set tBody = tBody _ tUpsert.Implementation.Read(32000) }
    Do $$$AssertTrue(tBody [ "$$$ISERR(tSaveSC)", "Upsert checks the %Save() status (surface b)")
    Do $$$AssertTrue(tBody [ "Set pAuditEmitted = $Select(tAuditRet = 1: 1, 1: 0)", "Upsert captures the audit return into ByRef pAuditEmitted (surface a)")
    Do $$$AssertTrue(tBody [ """SchemaNoteWrite""", "Upsert emits the (SessionAgent, SchemaNoteWrite, explicit) triple")

    ; --- SaveSchemaNote.Invoke: ByRef call + truthful envelope + error shaping ---
    Set tInvoke = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Tool.Inspection.SaveSchemaNote||Invoke")
    Do $$$AssertTrue($IsObject(tInvoke), "SaveSchemaNote.Invoke is defined")
    If '$IsObject(tInvoke) Quit
    Do tInvoke.Implementation.Rewind()
    Set tBody2 = ""
    While 'tInvoke.Implementation.AtEnd { Set tBody2 = tBody2 _ tInvoke.Implementation.Read(32000) }
    Do $$$AssertTrue(tBody2 [ ".tAction, .tAuditEmitted", "Invoke passes the ByRef audit-emitted channel (surface a)")
    Do $$$AssertTrue(tBody2 [ "$$$ISERR(tWriteSC)", "Invoke checks the Upsert %Status (surface b)")
    Do $$$AssertTrue(tBody2 [ """audit_emitted""", "Invoke surfaces audit_emitted in the envelope (surface a)")
    Do $$$AssertTrue(tBody2 [ """write_error""", "Invoke shapes the canonical write-error envelope (surface c)")
    Quit
}

/// <p>AC-3 "Then" — a live save emits a retrievable
/// <code>(SessionAgent, SchemaNoteWrite, explicit)</code> audit event.
/// Bounded exit-early poll per the Story 14.0 audit-daemon-flush
/// pattern (240 × 0.5s = 120s ceiling; daemon lag observed 30–60s).</p>
Method TestSaveAuditRowLands()
{
    Set tBefore = ..CountSchemaNoteAuditRows()
    Set tArgs = {"subject":"ztest-audit-land","note":"audit landing fixture"}
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Registry).Dispatch("save_schema_note", ..BuildCtx(), tArgs, .tResult), "Dispatch $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("audit_emitted"), 1, "envelope reports audit_emitted=1")
    Set tAfter = ..WaitForSchemaNoteAuditIncrease(tBefore)
    Do $$$AssertTrue(tAfter > tBefore, "SchemaNoteWrite audit row count increased; before=" _ tBefore _ " after=" _ tAfter)
    Quit
}

/// <p>Helper — count <code>%SYS.Audit</code> rows for the
/// <code>(SessionAgent, SchemaNoteWrite, explicit)</code> triple.
/// Mirrors SweepTaskTest.CountTaskRunAuditRows (best-effort header
/// apply; the real flake fix is the bounded poll).</p>
ClassMethod CountSchemaNoteAuditRows() As %Integer
{
    Set tCount = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Do ##class(%SYS.Audit).ApplyAuditHeader()
        Set tStmt = ##class(%SQL.Statement).%New()
        Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM %SYS.Audit WHERE %EXACT(EventSource) = 'SessionAgent' AND %EXACT(EventType) = 'SchemaNoteWrite' AND %EXACT(Event) = 'explicit'")
        Set tRs = tStmt.%Execute()
        If tRs.%Next() Set tCount = +tRs.%Get("Cnt")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tCount
}

/// <p>Helper — bounded exit-early poll: 240 × 0.5s = 120s ceiling,
/// exiting on the FIRST observed increase (authoritative bound per
/// SweepTaskTest.WaitForTaskRunAuditIncrease).</p>
ClassMethod WaitForSchemaNoteAuditIncrease(pBefore As %Integer) As %Integer
{
    Set tCount = pBefore
    For tAttempt = 1:1:240 {
        Set tCount = ..CountSchemaNoteAuditRows()
        If tCount > pBefore Quit
        Hang 0.5
    }
    Quit tCount
}

/// <p>ListTools manifest lock (TestRegistryListToolsIncludes*
/// precedent): the registry surfaces <code>save_schema_note</code> with
/// a non-empty priming Description (upsert semantics + durable-fact
/// usage) and an input_schema with exactly subject + note required and
/// NO namespace property (trust-boundary contract — namespace is never
/// an LLM argument).</p>
Method TestRegistryListToolsIncludesSaveSchemaNote()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Set tFound = 0
    Set tDesc = ""
    Set tSchema = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If tEntry.%Get("name") = "save_schema_note" {
            Set tFound = 1
            Set tDesc = tEntry.%Get("description")
            Set tSchema = tEntry.%Get("input_schema")
        }
    }
    Do $$$AssertEquals(tFound, 1, "registry surfaces 'save_schema_note'")
    Do $$$AssertTrue(tDesc '= "", "save_schema_note has non-empty Description")
    Do $$$AssertTrue(tDesc [ "Upserts by subject", "Description primes the upsert-by-subject semantics")
    Do $$$AssertTrue($IsObject(tSchema), "input_schema present")
    If '$IsObject(tSchema) Quit
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps.%Get("subject")), "subject property present")
    Do $$$AssertTrue($IsObject(tProps.%Get("note")), "note property present")
    Do $$$AssertTrue('$IsObject(tProps.%Get("namespace")), "NO namespace property (CallerContext-only, NFR-S6)")
    Set tRequired = tSchema.%Get("required")
    Do $$$AssertTrue($IsObject(tRequired), "required array present")
    If $IsObject(tRequired) Do $$$AssertEquals(tRequired.%Size(), 2, "exactly subject + note required")
    Quit
}

}
