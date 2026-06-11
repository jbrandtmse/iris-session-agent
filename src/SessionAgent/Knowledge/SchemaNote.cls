/// <p>One agent-authored learned schema note (Epic 14 FR63 / Story 14.4).
/// Rows are written at runtime by the <code>save_schema_note</code> tool
/// (<CLASS>SessionAgent.Tool.Inspection.SaveSchemaNote</CLASS>) when an
/// agent discovers a durable namespace fact — e.g. which message-body
/// class carries order IDs, which SearchTable is installed, which column
/// is encoded — and read back by <code>get_schema_notes</code>
/// (<CLASS>SessionAgent.Tool.Inspection.GetSchemaNotes</CLASS>) plus the
/// first-turn digest (<CLASS>SessionAgent.Knowledge.SchemaNoteDigest</CLASS>)
/// so discovered facts survive across conversations instead of being
/// re-derived every session.</p>
///
/// <p><b>Upsert key.</b> The unique composite index
/// <code>NsSubjectIdx (Namespace, Subject)</code> makes
/// <method>Upsert</method> overwrite <property>Body</property> and
/// refresh <property>VerifiedAt</property> on an existing pair instead of
/// inserting a duplicate row. <property>VerifiedAt</property> staleness
/// is surfaced to the LLM as <code>age_days</code> at retrieval time so
/// old facts get re-verified.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Knowledge.SchemaNote</code> — the
/// per-property doc-comments below surface as column descriptions in the
/// IRIS SQL Catalog Mgmt-Portal view.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-4-learned-schema-notes-digest-injection.md">Story 14.4</a> — AC-1 source.</li>
/// <li><a href="../Search/UserVocabulary.cls">SessionAgent.Search.UserVocabulary</a> §RecordSuccess — the agent-owned-table write + audit + ByRef <code>pAuditEmitted</code> precedent this class mirrors.</li>
/// </ul>
Class SessionAgent.Knowledge.SchemaNote Extends %Persistent
{

/// <p>The IRIS namespace this note describes. Populated from the
/// trust-boundary <CLASS>SessionAgent.Agent.CallerContext</CLASS> —
/// NEVER from LLM input — so notes cannot be written cross-namespace.</p>
Property Namespace As %String(MAXLEN = 64) [ Required ];

/// <p>Short, stable, operator/LLM-readable note key — e.g.
/// <code>"order-id-location"</code>. Unique per
/// <property>Namespace</property> (the <code>NsSubjectIdx</code> upsert
/// key): re-saving an existing subject overwrites the note.</p>
Property Subject As %String(MAXLEN = 256) [ Required ];

/// <p>The learned fact, free text (ASCII-safe by convention — the
/// digest renderer and chat panel both assume mojibake-free content per
/// the Rule 12 precedent). NUL characters are stripped at the tool
/// boundary so the <code>$Char(0)</code> legacy null sentinel can never
/// collide with stored content.</p>
Property Body As %String(MAXLEN = 4000) [ Required ];

/// <p>UTC timestamp of the last write/verification of this note —
/// <code>$ZDateTime($ZTimeStamp, 3, 1)</code>-derived (ODBC form, UTC
/// per project rule §"Timestamp and Encoding Standards"). Refreshed on
/// every <method>Upsert</method>; retrieval computes <code>age_days</code>
/// from the UTC-to-UTC delta against <code>$ZTimeStamp</code>.</p>
Property VerifiedAt As %TimeStamp [ Required ];

/// <p>Which agent wrote the note (<code>session-inspection</code> or
/// <code>message-search</code> — taken from
/// <property>CallerContext.AgentName</property>), so operators can see
/// provenance in the SQL catalog.</p>
Property SourceAgent As %String(MAXLEN = 64);

/// <p>Unique composite upsert key — one note per (Namespace, Subject)
/// pair. Generates <code>NsSubjectIdxOpen</code> used by
/// <method>Upsert</method>'s probe-then-branch logic.</p>
Index NsSubjectIdx On (Namespace, Subject) [ Unique ];

/// <p>Story 14.4 AC-1/AC-2 — upsert one schema note. Probes the unique
/// <code>(Namespace, Subject)</code> pair: when the row exists, Body is
/// overwritten and VerifiedAt refreshed (no duplicate row); when absent,
/// a fresh row is inserted. Mirrors
/// <method>SessionAgent.Search.UserVocabulary.RecordSuccess</method>
/// (probe → branch → save → audit-emit).</p>
///
/// <p><b>Write status checking (Rule 8 defensive surface b).</b> The
/// <code>%Save()</code> status is checked and propagated — a write
/// failure returns the failure <code>%Status</code> to the caller; the
/// audit emit is skipped (no audit row for a write that did not land).</p>
///
/// <p><b>Audit-emit return capture (Rule 8 defensive surface a —
/// MEDIUM-9.2-F01 precedent).</b> <var>pAuditEmitted</var> ByRef receives
/// the return value of <code>$System.Security.Audit("SessionAgent",
/// "SchemaNoteWrite", "explicit", ...)</code> (1 on success, 0 if the
/// triple is unregistered — the silent-fail path per project rule
/// §"Security.Events Pre-Registration for Audit"). The triple is
/// pre-registered by <CLASS>SessionAgent.Audit.Emit</CLASS>
/// §EnsureEvents (Story 14.4 addition). Callers surface this verbatim as
/// <code>audit_emitted</code> in their envelope so operators can detect
/// registration drift; the row save succeeds regardless — operator data
/// is never lost to audit configuration drift.</p>
///
/// <p><var>pAction</var> ByRef receives <code>"created"</code> or
/// <code>"updated"</code> for envelope shaping.</p>
ClassMethod Upsert(pNamespace As %String, pSubject As %String, pBody As %String, pSourceAgent As %String = "", ByRef pAction As %String = "", ByRef pAuditEmitted As %Integer = 0) As %Status
{
    Set tSC = $$$OK
    Set pAction = ""
    Set pAuditEmitted = 0
    Try {
        ; UTC ODBC timestamp per AC-1 ($ZTimeStamp, NOT $Horolog —
        ; project rule §"Timestamp and Encoding Standards").
        Set tNowOdbc = $ZDateTime($ZTimeStamp, 3, 1)

        ; Probe the unique (Namespace, Subject) pair — concurrency 4
        ; (exclusive) so two concurrent saves of the same subject
        ; serialize at the IRIS lock queue instead of racing the index.
        Set tRow = ..NsSubjectIdxOpen(pNamespace, pSubject, 4)
        If $IsObject(tRow) {
            Set pAction = "updated"
            ; Last-writer-wins includes the Subject's stored casing: the
            ; unique index collates SQLUPPER (case-insensitive match), so
            ; reassign Subject so the stored row matches the envelope echo
            ; (Story 14.4 review fix — case-variant re-save drift).
            Set tRow.Subject = pSubject
        } Else {
            Set tRow = ..%New()
            Set tRow.Namespace = pNamespace
            Set tRow.Subject = pSubject
            Set pAction = "created"
        }
        Set tRow.Body = pBody
        Set tRow.VerifiedAt = tNowOdbc
        Set tRow.SourceAgent = pSourceAgent

        ; Rule 8 defensive surface (b) — check the write status; never
        ; silently discard a write failure (project rule §"Write Status
        ; Checking").
        Set tSaveSC = tRow.%Save()
        If $$$ISERR(tSaveSC) {
            ; Create-create race convergence (Story 14.4 review fix):
            ; the concurrency-4 probe only serializes opens of an
            ; EXISTING row — two concurrent first saves both reach %New,
            ; and the loser fails on the unique NsSubjectIdx. A logically
            ; valid upsert must converge to an update, not surface a
            ; spurious write-failure envelope: re-probe exclusively and
            ; retry once as an update when the row now exists.
            If pAction = "created" {
                Set tRetryRow = ..NsSubjectIdxOpen(pNamespace, pSubject, 4)
                If $IsObject(tRetryRow) {
                    Set pAction = "updated"
                    Set tRetryRow.Subject = pSubject
                    Set tRetryRow.Body = pBody
                    Set tRetryRow.VerifiedAt = tNowOdbc
                    Set tRetryRow.SourceAgent = pSourceAgent
                    Set tSaveSC = tRetryRow.%Save()
                }
            }
            If $$$ISERR(tSaveSC) {
                Set tSC = tSaveSC
                Quit ; argumentless quit out of Try; no audit for a failed write
            }
        }

        ; Audit emit AFTER the successful row write. Triple =
        ; (SessionAgent, SchemaNoteWrite, explicit), pre-registered by
        ; Audit.Emit.EnsureEvents. $System.Security.Audit returns 0 on
        ; an unregistered triple (silent fail) — capture the return into
        ; pAuditEmitted (ByRef) so callers can surface drift detection
        ; (Rule 8 defensive surface a). Body content is NOT copied into
        ; the audit details (the row itself is the durable record);
        ; BodyLength gives the operator a size signal without bloat.
        ; Subject is LLM input and is rendered LAST in the semicolon-
        ; delimited Details string so embedded "; Action=..." text cannot
        ; shadow the real fields an operator parses left-to-right
        ; (Story 14.4 review fix — audit-details field-spoof hardening).
        Set tDetails = "Namespace=" _ pNamespace _ "; Action=" _ pAction _ "; SourceAgent=" _ pSourceAgent _ "; BodyLength=" _ $Length(pBody) _ "; Subject=" _ pSubject
        Set tDesc = "SchemaNote.Upsert: " _ pAction _ " schema note (save_schema_note)"
        ; Inner Try: an audit-emit EXCEPTION (e.g. <PROTECT> under a
        ; restricted process) must not convert a COMMITTED row write into
        ; a "write failed" envelope — the row is saved; report
        ; audit_emitted=0 instead (Story 14.4 review fix).
        Set tAuditRet = 0
        Try {
            Set tAuditRet = $System.Security.Audit("SessionAgent", "SchemaNoteWrite", "explicit", tDetails, tDesc)
        }
        Catch exAudit {
            Set tAuditRet = 0
        }
        Set pAuditEmitted = $Select(tAuditRet = 1: 1, 1: 0)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

Storage Default
{
<Data name="SchemaNoteDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Namespace</Value>
</Value>
<Value name="3">
<Value>Subject</Value>
</Value>
<Value name="4">
<Value>Body</Value>
</Value>
<Value name="5">
<Value>VerifiedAt</Value>
</Value>
<Value name="6">
<Value>SourceAgent</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.KnA5DE.SchemaNoteD</DataLocation>
<DefaultData>SchemaNoteDefaultData</DefaultData>
<IdLocation>^SessionAgent.KnA5DE.SchemaNoteD</IdLocation>
<IndexLocation>^SessionAgent.KnA5DE.SchemaNoteI</IndexLocation>
<StreamLocation>^SessionAgent.KnA5DE.SchemaNoteS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
