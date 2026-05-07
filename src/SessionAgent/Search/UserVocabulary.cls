/// <p>Per-portal-user vocabulary mapping for the Search Agent. Each row
/// records an alias the user has confirmed (via clickthrough, explicit
/// teach, extraction, or seeding) maps to a particular concept in the
/// HL7 / ObjectScript / interop domain. The Search Agent reads the
/// matching <code>(PortalUser, Alias)</code> row at search time to
/// translate operator-typed natural-language phrasing into the canonical
/// query primitive (a SearchTable property comparison, an HL7 message
/// type filter, etc.).</p>
///
/// <p><b>Per-class refinement (saved memory <code>project_search_agent_body_search_refinement.md</code>).</b>
/// The optional <code>MessageBodyClass</code> property scopes the
/// alias to a specific body-class taxonomy (e.g.,
/// <code>EnsLib.HL7.Message</code>) so the same alias can carry a
/// different meaning when the user is searching HL7 vs CSV vs JSON
/// traffic. Empty <code>MessageBodyClass</code> means
/// <i>"applies to any class"</i> — the Search Agent's lookup falls back
/// to the empty-class row when no class-specific row is found.</p>
///
/// <p><b>v1 vs Epic 9 boundary on Confidence.</b> The
/// <code>Confidence</code> property is stored as the numeric output of
/// the recursion-safe <code>%OnAfterSave</code> trigger that
/// recomputes from <code>SuccessCount</code> / <code>FailureCount</code>.
/// That trigger ships in <b>Epic 9 Story 9.2</b>; until then, this story
/// (8.1) ships <code>Confidence</code> with default <code>0</code> and
/// every read returns <code>0</code> verbatim. Stories 8.2 – 8.7 do not
/// depend on Confidence — the substrate is in place but inert. Story 9.2
/// will overlay the trigger without schema migration.</p>
///
/// <p><b>NFR-S2 schema discipline.</b> No credential material, no API
/// keys, no PHI body content lives on this class. Aliases and counts
/// only.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Search.UserVocabulary</code> — the
/// per-property doc-comments below surface as column descriptions in
/// the IRIS SQL Catalog Mgmt-Portal view (per Story 8.0 AC-1
/// codification of operator-observable artifact descriptions).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md Story 8.1</a> — AC-1 verbatim source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR19</a> — vocabulary persistence design.</li>
/// <li>Saved memory <code>project_search_agent_body_search_refinement.md</code> — per-class vocabulary refinement.</li>
/// </ul>
Class SessionAgent.Search.UserVocabulary Extends %Persistent
{

/// <p>Portal user (typically the IRIS login name) who confirmed this alias
/// mapping. The unique <code>UserAliasIdx</code> below scopes alias rows
/// per user so two users may map the same alias to different concepts.</p>
Property PortalUser As %String;

/// <p>The natural-language alias the user typed or clicked-through to
/// confirm — e.g., <code>"admit"</code>, <code>"failed"</code>,
/// <code>"MRN search"</code>. <code>MAXLEN=512</code> covers
/// multi-word phrases without forcing a stream backing store.</p>
Property Alias As %String(MAXLEN = 512);

/// <p>Optional body-class scope for per-class vocabulary refinement —
/// e.g., <code>EnsLib.HL7.Message</code>. Empty means
/// <i>"applies to any class"</i> (the cross-class default). Per the
/// saved memory, allowing the same alias to carry different meanings
/// per body class is a v1 design decision.</p>
Property MessageBodyClass As %String(MAXLEN = 128);

/// <p>Count of times the alias mapping resulted in a successful search
/// (clickthrough on a returned hit). Increments via Story 9.2's
/// <code>RecordSuccess</code> path.</p>
Property SuccessCount As %Integer [ InitialExpression = 0 ];

/// <p>Count of times the alias mapping yielded zero useful results
/// (operator typed the alias, results returned, operator did not click
/// any hit). Increments via Story 9.2's <code>RecordFailure</code> path.</p>
Property FailureCount As %Integer [ InitialExpression = 0 ];

/// <p>Numeric confidence score in <code>[0.0, 1.0]</code>, recomputed by
/// Story 9.2's recursion-safe <code>%OnAfterSave</code> trigger from
/// the success / failure counts. Until Story 9.2 ships, the default
/// <code>0</code> is the only legal value — the substrate is in place
/// but inert.</p>
Property Confidence As %Numeric [ InitialExpression = 0 ];

/// <p>ISO-8601 UTC timestamp (e.g., <code>2026-05-07T10:30:00Z</code>) of
/// the most recent successful use of this alias. Stored as
/// <code>%String</code> so the format is operator-readable in the SQL
/// Catalog without horolog conversion.</p>
Property LastUsed As %String;

/// <p>ISO-8601 UTC timestamp of row creation. Set at insert time;
/// never updated.</p>
Property CreatedAt As %String;

/// <p>Provenance — one of <code>clickthrough</code> /
/// <code>explicit</code> / <code>extracted</code> / <code>seed</code>.
/// Lets the Search Agent weight directly-confirmed mappings above
/// extracted-from-conversation mappings when ranking candidate aliases.</p>
Property CreatedVia As %String;

/// <p>Unique index on <code>(PortalUser, Alias)</code> — enforces single
/// vocabulary row per user per alias text. The unique constraint is
/// load-bearing for the Search Agent's lookup contract: a single
/// <code>UserAliasIdxOpen(user, alias)</code> call returns the canonical
/// alias mapping (or null if absent), no de-duplication logic needed.</p>
Index UserAliasIdx On (PortalUser, Alias) [ Unique ];

/// <p>Story 9.2 AC-1 — record a successful alias use (clickthrough,
/// explicit save, extracted from chat, or seed insertion). Probes the
/// schema's unique <code>(PortalUser, Alias)</code> pair via
/// <code>%SQL.Statement</code>; if a row exists, increments
/// <code>SuccessCount</code> and updates <code>LastUsed</code> (and
/// <code>MessageBodyClass</code> when <var>pBodyClass</var> is non-empty).
/// If absent, creates a new row with the supplied
/// <var>pCreatedVia</var>. After <code>%Save()</code> succeeds, emits a
/// <code>(SessionAgent, VocabWrite, pCreatedVia)</code> audit event with
/// the operator's <var>pDescription</var> in the details string.</p>
///
/// <p><b>Caller-context contract.</b> <var>pCreatedVia</var> MUST be one
/// of the four pre-registered triples
/// (<code>clickthrough</code> / <code>explicit</code> /
/// <code>extracted</code> / <code>seed</code>) — see
/// <CLASS>SessionAgent.Audit.Emit</CLASS> §<method>EnsureEvents</method>
/// (Story 1.3 lines 55–58). An unregistered triple will cause
/// <code>$System.Security.Audit</code> to silently return <code>0</code>
/// per project rule §"Security.Events Pre-Registration for Audit"; the
/// row save still succeeds but the audit trail is lost. If a future
/// caller requires a fifth triple, add it to <method>EnsureEvents</method>
/// and re-run <method>SessionAgent.Installer.Install</method>.</p>
///
/// <p><b>Default <var>pCreatedVia</var> = <code>"clickthrough"</code>.</b>
/// The dominant call site (Story 9.5's <code>RecordClickThrough</code>
/// ZenMethod) does not pass the parameter — defaulting matches that
/// expected usage. <code>VocabLookup.InvokeSave</code> (Story 8.7 / 9.2
/// AC-4) overrides to <code>"explicit"</code>.</p>
///
/// <p><b>Confidence recompute.</b> The
/// <method>%OnAfterSave</method> trigger fires exactly once per
/// <code>%Save()</code> on IRIS 2024.1 (verified by
/// <CLASS>SessionAgent.Test.OnAfterSaveRecursionProbe</CLASS> Story 9.1
/// AC-1: <code>fire_count=1</code>) and recomputes <code>Confidence</code>
/// via direct SQL UPDATE — the bypass of the OREF persistence layer's
/// trigger dispatch keeps the trigger non-recursive.</p>
///
/// <p><b>Audit-emit return capture (Story 9.2 review fix MEDIUM-9.2-F01).</b>
/// <var>pAuditEmitted</var> ByRef receives the return value of
/// <code>$System.Security.Audit</code> (1 on success, 0 if the triple is
/// unregistered — the silent-fail path per project rule
/// §"Security.Events Pre-Registration for Audit"). Callers (e.g.,
/// <method>VocabLookup.InvokeSave</method>) surface this in their
/// envelope's <code>audit_emitted</code> field so operators can detect
/// audit-registration drift. Defaults to <code>0</code> so callers that
/// don't pass the parameter still observe the conservative "audit may
/// not have emitted" default.</p>
ClassMethod RecordSuccess(pPortalUser As %String, pAlias As %String, pBodyClass As %String = "", pCreatedVia As %String = "clickthrough", pDescription As %String = "", ByRef pAuditEmitted As %Integer = 0) As %Status
{
    Set tSC = $$$OK
    Try {
        ; ISO-8601 UTC Z timestamp per project rule §"Timestamp and Encoding
        ; Standards" — $ZTimeStamp is UTC, NOT $Horolog (which is local time
        ; and would be incorrect when appending the "Z" suffix).
        Set tNowIso = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"

        ; ---- Pair probe — matches UserAliasIdx unique-index (PortalUser, Alias).
        Set tFoundId = ""
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
        If $$$ISERR(tPrepSC) Set tSC = tPrepSC Quit
        Set tRs = tStmt.%Execute(pPortalUser, pAlias)
        If tRs.%Next() Set tFoundId = tRs.%Get("ID")

        ; ---- Branch: existing row → increment, OR new row → insert.
        Set tAction = ""
        If tFoundId '= "" {
            Set tRow = ##class(SessionAgent.Search.UserVocabulary).%OpenId(tFoundId)
            If '$IsObject(tRow) Set tSC = $$$ERROR($$$GeneralError, "RecordSuccess: existing row " _ tFoundId _ " could not be opened") Quit
            Set tRow.SuccessCount = (+tRow.SuccessCount) + 1
            Set tRow.LastUsed = tNowIso
            ; Don't blank an existing scope — only override if caller passed one.
            If pBodyClass '= "" Set tRow.MessageBodyClass = pBodyClass
            Set tSaveSC = tRow.%Save()
            If $$$ISERR(tSaveSC) Set tSC = tSaveSC Quit
            Set tAction = "incremented"
        } Else {
            Set tRow = ##class(SessionAgent.Search.UserVocabulary).%New()
            Set tRow.PortalUser = pPortalUser
            Set tRow.Alias = pAlias
            Set tRow.MessageBodyClass = pBodyClass
            Set tRow.CreatedVia = pCreatedVia
            Set tRow.CreatedAt = tNowIso
            Set tRow.LastUsed = tNowIso
            Set tRow.SuccessCount = 1
            Set tRow.FailureCount = 0
            Set tRow.Confidence = 0
            Set tSaveSC = tRow.%Save()
            If $$$ISERR(tSaveSC) Set tSC = tSaveSC Quit
            Set tAction = "created"
        }

        ; ---- Audit emit. Triple = (SessionAgent, VocabWrite, pCreatedVia).
        ; Defensive: $System.Security.Audit returns 0 on unregistered triple
        ; (silent fail). Row save already succeeded; audit failure does NOT
        ; flip status — operator data is never lost to audit drift. Capture
        ; the return value into pAuditEmitted (ByRef) so callers can surface
        ; drift detection in their envelopes (review fix MEDIUM-9.2-F01).
        Set tDetails = "PortalUser=" _ pPortalUser _ "; Alias=" _ pAlias _ "; MessageBodyClass=" _ pBodyClass _ "; Action=" _ tAction _ "; Description=" _ pDescription
        Set tDesc = "UserVocabulary.RecordSuccess: " _ tAction _ " row (via=" _ pCreatedVia _ ")"
        Set tAuditRet = $System.Security.Audit("SessionAgent", "VocabWrite", pCreatedVia, tDetails, tDesc)
        Set pAuditEmitted = $Select(tAuditRet=1: 1, 1: 0)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Story 9.2 AC-2 — record a failed alias use (operator typed an alias,
/// the search returned results, the operator did not click any hit).
/// Probes the same unique <code>(PortalUser, Alias)</code> pair as
/// <method>RecordSuccess</method>; if absent, returns <code>$$$OK</code>
/// without inserting (graceful no-op — the operator's failed alias never
/// converted to a stored vocabulary entry, so there is nothing to
/// penalize). If present, increments <code>FailureCount</code>, updates
/// <code>LastUsed</code>, calls <code>%Save()</code>, and emits a
/// <code>(SessionAgent, VocabWrite, extracted)</code> audit event.</p>
///
/// <p><b>Audit-Name triple choice — design rationale.</b> The epic spec
/// originally suggested <code>failure_decrement</code> as a candidate
/// triple Name. After review, <code>extracted</code> (one of the four
/// already-registered <code>VocabWrite</code> Names) is the closest
/// operational match — <code>RecordFailure</code> fires after the
/// operator has moved on without clicking, which is the same shape as
/// "extracted from chat post-action" (a follow-up update to an existing
/// alias, not a primary write or click). Re-using
/// <code>extracted</code> keeps the audit-event surface tight (no fifth
/// triple needs to be added to <method>SessionAgent.Audit.Emit.EnsureEvents</method>
/// and re-deployed). Future operators reading
/// <code>iris_audit_events EventType=VocabWrite EventName=extracted</code>
/// will see BOTH the chat-extraction inserts AND the failure-increment
/// updates; the EventData details string distinguishes them
/// (<code>"Action=failure_increment"</code> vs the chat-extraction
/// caller's details). Story 9.5's dev sees this rationale here.</p>
///
/// <p><b>Audit-emit return capture (Story 9.2 review fix MEDIUM-9.2-F01).</b>
/// <var>pAuditEmitted</var> ByRef receives the return value of
/// <code>$System.Security.Audit</code> (1 on success, 0 if the triple is
/// unregistered — silent fail). Defaults to <code>0</code> for callers
/// that don't pass the parameter.</p>
ClassMethod RecordFailure(pPortalUser As %String, pAlias As %String, ByRef pAuditEmitted As %Integer = 0) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tNowIso = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"

        ; Pair probe.
        Set tFoundId = ""
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
        If $$$ISERR(tPrepSC) Set tSC = tPrepSC Quit
        Set tRs = tStmt.%Execute(pPortalUser, pAlias)
        If tRs.%Next() Set tFoundId = tRs.%Get("ID")

        ; Absent → no-op (graceful per AC-2).
        If tFoundId = "" Quit

        ; Present → increment FailureCount.
        Set tRow = ##class(SessionAgent.Search.UserVocabulary).%OpenId(tFoundId)
        If '$IsObject(tRow) Set tSC = $$$ERROR($$$GeneralError, "RecordFailure: existing row " _ tFoundId _ " could not be opened") Quit
        Set tRow.FailureCount = (+tRow.FailureCount) + 1
        Set tRow.LastUsed = tNowIso
        Set tSaveSC = tRow.%Save()
        If $$$ISERR(tSaveSC) Set tSC = tSaveSC Quit

        ; Audit emit — re-using "extracted" triple per design rationale above.
        ; Capture return value into pAuditEmitted (ByRef) — review fix MEDIUM-9.2-F01.
        Set tDetails = "PortalUser=" _ pPortalUser _ "; Alias=" _ pAlias _ "; Action=failure_increment; NewFailureCount=" _ (+tRow.FailureCount)
        Set tDesc = "UserVocabulary.RecordFailure: incremented FailureCount on existing row"
        Set tAuditRet = $System.Security.Audit("SessionAgent", "VocabWrite", "extracted", tDetails, tDesc)
        Set pAuditEmitted = $Select(tAuditRet=1: 1, 1: 0)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Story 9.2 AC-3 — recursion-safe trigger that recomputes
/// <code>Confidence = Success / (Success + Failure + 1)</code> on every
/// row save. The "+1" denominator term is the smoothing factor (per
/// architecture §"Confidence semantics") — it caps the maximum
/// confidence at slightly less than 1.0 even after many successes,
/// reserving headroom for future failure signals to move the score down.</p>
///
/// <p><b>Recursion avoidance.</b> The trigger uses a direct
/// <code>&amp;sql(UPDATE...)</code> against the same row instead of
/// calling <code>..%Save()</code>. The OREF persistence layer's
/// trigger dispatch fires <code>%OnAfterSave</code> only on
/// <code>%Save()</code>; a direct embedded-SQL UPDATE bypasses that
/// dispatch and therefore does NOT re-fire the trigger.
/// <CLASS>SessionAgent.Test.OnAfterSaveRecursionProbe</CLASS> verified
/// this empirically on IRIS 2024.1 (Story 9.1 AC-1: fire_count=1,
/// recursion_detected=0). The <var>insert</var> parameter is the
/// IRIS-framework signature; this trigger fires identically on insert
/// and update so the parameter is unused.</p>
Method %OnAfterSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    ; Story 9.2 AC-5 test-only opt-in instrumentation. The PPG is NOT
    ; touched in production — only Story 9.2's TestOnAfterSaveFireCountExactlyOne
    ; sets ^||Story92TriggerFireCount = 0 before %Save() to opt in to
    ; fire-count tracking. Reading $Data avoids any production overhead;
    ; if the PPG is undefined, the increment is skipped entirely.
    If $Data(^||Story92TriggerFireCount) {
        Set ^||Story92TriggerFireCount = $Get(^||Story92TriggerFireCount, 0) + 1
    }

    Set tDenom = ..SuccessCount + ..FailureCount + 1
    Set ..Confidence = ..SuccessCount / tDenom
    Set tConfidence = ..Confidence
    Set tId = ..%Id()
    &sql(UPDATE SessionAgent_Search.UserVocabulary
         SET Confidence = :tConfidence
         WHERE %ID = :tId)
    ; Review fix MEDIUM-9.2-F02 — surface SQLCODE failure rather than
    ; swallowing per project rule §"Write Status Checking". SQLCODE=100
    ; (no matching row) is benign here only if the row was deleted by a
    ; concurrent session between %Save() and this trigger; surfacing it
    ; lets the caller observe the failure even though the row save itself
    ; succeeded. SQLCODE<0 indicates a genuine SQL error (constraint
    ; violation, etc.) — propagate as a $$$Status error.
    If SQLCODE < 0 {
        Quit $$$ERROR($$$GeneralError, "UserVocabulary.%OnAfterSave: SQL UPDATE on Confidence failed with SQLCODE=" _ SQLCODE _ " (%msg=" _ $Get(%msg) _ ")")
    }
    Quit $$$OK
}

Storage Default
{
<Data name="UserVocabularyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PortalUser</Value>
</Value>
<Value name="3">
<Value>Alias</Value>
</Value>
<Value name="4">
<Value>MessageBodyClass</Value>
</Value>
<Value name="5">
<Value>SuccessCount</Value>
</Value>
<Value name="6">
<Value>FailureCount</Value>
</Value>
<Value name="7">
<Value>Confidence</Value>
</Value>
<Value name="8">
<Value>LastUsed</Value>
</Value>
<Value name="9">
<Value>CreatedAt</Value>
</Value>
<Value name="10">
<Value>CreatedVia</Value>
</Value>
</Data>
<DataLocation>^SessionAgenC88B.UserVocabularyD</DataLocation>
<DefaultData>UserVocabularyDefaultData</DefaultData>
<IdLocation>^SessionAgenC88B.UserVocabularyD</IdLocation>
<IndexLocation>^SessionAgenC88B.UserVocabularyI</IndexLocation>
<StreamLocation>^SessionAgenC88B.UserVocabularyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
