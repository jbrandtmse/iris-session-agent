/// <p>Inspection tool — persists one agent-discovered namespace fact as a
/// timestamped <CLASS>SessionAgent.Knowledge.SchemaNote</CLASS> row
/// (Epic 14 FR63 / Story 14.4). Paired with <code>get_schema_notes</code>
/// (<CLASS>SessionAgent.Tool.Inspection.GetSchemaNotes</CLASS>) and the
/// first-turn digest (<CLASS>SessionAgent.Knowledge.SchemaNoteDigest</CLASS>)
/// so discovered facts survive across conversations.</p>
///
/// <p><b>Tool name:</b> <code>save_schema_note</code>. Exposed to BOTH
/// agents (registry auto-discovery).</p>
///
/// <p><b>Read-only invariant — <parameter>MutatesState</parameter>=0
/// (deliberate deviation from the Story 14.4 AC-2 literal, documented in
/// the story Completion Notes).</b> This tool DOES write — but ONLY to
/// the agent-owned <code>SessionAgent_Knowledge.SchemaNote</code> table,
/// never to <code>Ens.*</code> data. <parameter>MutatesState</parameter>
/// is the FR31 / NFR-S1 Layer-2 flag for <code>Ens.*</code> mutation
/// specifically, and <method>SessionAgent.Tool.Registry.Dispatch</method>
/// hard-blocks any <parameter>MutatesState</parameter>=1 dispatch
/// ("Tool blocked by read-only policy") — a contract locked by
/// <CLASS>SessionAgent.Test.ToolRegistryTest</CLASS> /
/// <CLASS>SessionAgent.Test.StubWriteTool</CLASS> and asserted across
/// every tool by
/// <CLASS>SessionAgent.Test.InspectionSuiteVerificationTest</CLASS>
/// §TestAllToolsDeclareReadOnlyMutatesState. The
/// <code>(SessionAgent, SchemaNoteWrite, explicit)</code> audit emit is
/// the authoritative record of the write — NOT the
/// <parameter>MutatesState</parameter> flag. This mirrors the
/// <CLASS>SessionAgent.Tool.Search.VocabLookup</CLASS> save-mode
/// precedent verbatim. <b>Future readers: do NOT flip the flag.</b></p>
///
/// <p><b>Namespace from CallerContext (NFR-S6).</b> The note's
/// <code>Namespace</code> is taken from
/// <property>pCallerCtx.Namespace</property> — NEVER from LLM input — so
/// the LLM cannot direct a write at another namespace. Subject/note ARE
/// LLM input: lengths are validated server-side and control characters
/// normalized (Story 14.1 keyword-normalization precedent).</p>
///
/// <p><b>Rule 8 defensive surfaces (Story 14.4 AC-2 enumeration):</b>
/// (a) ByRef audit-emitted envelope-correctness — the
/// <method>SessionAgent.Knowledge.SchemaNote.Upsert</method> helper
/// returns the audit-emission outcome via ByRef <var>pAuditEmitted</var>
/// and this envelope reports <code>audit_emitted</code> truthfully;
/// (b) the write path checks the <code>%Save()</code> status inside
/// <method>Upsert</method> and this tool checks the returned
/// <code>%Status</code> — failures are never discarded;
/// (c) failures return the canonical structured error envelope
/// (<code>{isError:1, content:[...]}</code>), never a bare %Status.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-4-learned-schema-notes-digest-injection.md">Story 14.4</a> — AC-2 / AC-3 source.</li>
/// <li><a href="../Search/VocabLookup.cls">SessionAgent.Tool.Search.VocabLookup</a> §InvokeSave — agent-owned-table write + audit + ByRef precedent.</li>
/// <li><a href="../../Audit/Emit.cls">SessionAgent.Audit.Emit</a> §EnsureEvents — (SessionAgent, SchemaNoteWrite, explicit) pre-registration.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.SaveSchemaNote Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "save_schema_note";

Parameter Description As %String = "Persist a timestamped schema note - a durable namespace fact you discovered at runtime (e.g. which body class carries order IDs, which SearchTable is installed, which column is encoded) - so future conversations in this namespace reuse it instead of re-deriving it. Upserts by subject: saving an existing subject overwrites the note and refreshes its verified timestamp. Use short, stable, descriptive subjects (e.g. 'order-id-location').";

/// <p>FR31 / NFR-S1 Layer-2 flag — <code>Ens.*</code>-mutation only.
/// save_schema_note writes to SchemaNote (project's own table), NOT to
/// Ens.*. Do NOT flip this flag — see class doc-comment §"Read-only
/// invariant" for the rationale and the structural locks that enforce
/// it.</p>
Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Both args required; lengths are
/// re-validated server-side (the locked subset cannot express maxLength
/// portably across providers).</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "subject": {"type": "string", "description": "Short, stable note key, max 256 characters (e.g. 'order-id-location'). Re-saving an existing subject overwrites that note and refreshes its verified timestamp."},
            "note": {"type": "string", "description": "The learned fact as free text, max 4000 characters. State it so a future conversation can act on it without re-discovery (name exact classes, tables, columns)."}
        },
        "required": ["subject", "note"],
        "additionalProperties": false
    }
}

/// <p>Validate, normalize, and upsert the schema note for the ACTIVE
/// namespace (<property>pCallerCtx.Namespace</property>). Success
/// envelope carries <code>{render_strategy:"ok", namespace, subject,
/// action:"created"|"updated", verified_at, audit_emitted,
/// source_agent}</code>. All failures return the canonical
/// <code>{isError:1, ...}</code> envelope (Rule 8 surface c).</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Input extraction ---
        Set tSubject = ""
        Set tNote = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tSubject = pJsonArgs.%Get("subject")
            Set tNote = pJsonArgs.%Get("note")
        }
        ; Type guard (Story 14.4 review fix): a non-string JSON value
        ; (nested object/array) comes back from %Get as an OREF whose
        ; string form ("n@%Library.DynamicObject") would otherwise be
        ; persisted as garbage — treat it as missing input.
        If $IsObject(tSubject) Set tSubject = ""
        If $IsObject(tNote) Set tNote = ""
        Set:tSubject=$$$NULLOREF tSubject = ""
        Set:tNote=$$$NULLOREF tNote = ""

        ; --- Control-char normalization (Story 14.1 keyword precedent) ---
        ; Subject is a single-line key: tabs / CR / LF / NUL become
        ; spaces, then trim. Note is free text: NUL is stripped (so the
        ; $Char(0) legacy null sentinel can never collide with stored
        ; content) but tabs/newlines are preserved for readability;
        ; leading/trailing whitespace trimmed.
        Set tSubject = $Translate(tSubject, $Char(9) _ $Char(10) _ $Char(13) _ $Char(0), "    ")
        Set tSubject = $ZStrip(tSubject, "<>W")
        Set tNote = $Translate(tNote, $Char(0), "")
        Set tNote = $ZStrip(tNote, "<>WC")

        ; --- Server-side validation (subject/note are LLM input) ---
        If tSubject = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"save_schema_note requires non-empty 'subject'"}]}
            Quit
        }
        If $Length(tSubject) > 256 {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("save_schema_note 'subject' exceeds 256 characters (got " _ $Length(tSubject) _ ") - use a short stable key")}]}
            Quit
        }
        If tNote = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"save_schema_note requires non-empty 'note'"}]}
            Quit
        }
        If $Length(tNote) > 4000 {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("save_schema_note 'note' exceeds 4000 characters (got " _ $Length(tNote) _ ") - condense the fact")}]}
            Quit
        }

        ; --- Namespace from CallerContext, NEVER from the LLM (NFR-S6).
        ; $Char(0)-normalize defensively per project rule §"$Char(0)
        ; sentinel" (Namespace is not SQL-UPDATE-mutated today, but the
        ; guard below relies on '= "").
        Set tNamespace = ""
        Set tSourceAgent = ""
        If $IsObject($Get(pCallerCtx)) {
            Set tNamespace = pCallerCtx.Namespace
            Set tSourceAgent = pCallerCtx.AgentName
        }
        If tNamespace = $Char(0) Set tNamespace = ""
        If tSourceAgent = $Char(0) Set tSourceAgent = ""
        If tNamespace = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"save_schema_note requires a populated CallerContext.Namespace (trust-boundary contract)"}]}
            Quit
        }

        ; --- Upsert via the SchemaNote helper (Rule 8 surfaces a + b).
        ; tAuditEmitted captures the $System.Security.Audit return ByRef
        ; so the envelope's audit_emitted field reports the true
        ; emission outcome; the %Save status is checked inside Upsert
        ; and the returned %Status checked here — never discarded.
        Set tAction = ""
        Set tAuditEmitted = 0
        Set tWriteSC = ##class(SessionAgent.Knowledge.SchemaNote).Upsert(tNamespace, tSubject, tNote, tSourceAgent, .tAction, .tAuditEmitted)
        If $$$ISERR(tWriteSC) {
            Set tErrText = $System.Status.GetErrorText(tWriteSC)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("save_schema_note write failed: " _ tErrText)}], "structuredContent":{"render_strategy":"write_error","error_text":(tErrText)}}
            Quit
        }

        ; --- Read back VerifiedAt for the envelope (best-effort; the
        ; save already committed — a read-back miss must not flip the
        ; envelope to error, per the Story 14.0 VocabLookup read-back
        ; review-fix precedent).
        Set tVerifiedAt = ""
        Set tRow = ##class(SessionAgent.Knowledge.SchemaNote).NsSubjectIdxOpen(tNamespace, tSubject)
        If $IsObject(tRow) {
            Set tVerifiedAt = ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRow.VerifiedAt)
        }

        ; --- Success envelope ---
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Do pResult.structuredContent.%Set("namespace", tNamespace)
        Do pResult.structuredContent.%Set("subject", tSubject)
        Do pResult.structuredContent.%Set("action", tAction)
        Do pResult.structuredContent.%Set("verified_at", tVerifiedAt)
        Do pResult.structuredContent.%Set("audit_emitted", tAuditEmitted, "number")
        Do pResult.structuredContent.%Set("source_agent", tSourceAgent)
        Set pResult.content.%Get(0).text = "Saved schema note '" _ tSubject _ "' (" _ tAction _ ") for namespace '" _ tNamespace _ "'."
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

}
