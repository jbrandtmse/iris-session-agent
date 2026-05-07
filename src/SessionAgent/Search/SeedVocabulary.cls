/// <p>Bootstrap vocabulary for the Search Agent — ships ~10 HL7-idiom
/// alias-to-concept templates that operators see immediately on first
/// install per FR23 / AR19. Unlike <CLASS>SessionAgent.Search.UserVocabulary</CLASS>,
/// SeedVocabulary rows are <i>cross-user</i> reference templates the
/// Search Agent's lookup ladder consults as a fallback when the
/// per-user row is absent.</p>
///
/// <p><b>Idempotent <method>Seed</method> contract.</b> The
/// <method>Seed</method> class method inserts the canonical HL7 idiom
/// list once on first install; re-running on every subsequent install
/// is a no-op. Idempotency is enforced by a composite-key existence
/// probe on <code>(Alias, MessageBodyClass)</code> before each insert.
/// The <CLASS>SessionAgent.Installer</CLASS> orchestrator invokes
/// <method>Seed</method> after the RBAC + audit setup; the
/// post-Seed row count is logged to the install log so operators can
/// confirm seeding occurred (NFR-R5).</p>
///
/// <p><b>Per-class refinement.</b> The optional
/// <code>MessageBodyClass</code> property scopes the seed alias to a
/// specific body-class taxonomy (e.g., <code>EnsLib.HL7.Message</code>).
/// Empty <code>MessageBodyClass</code> means
/// <i>"applies to any class"</i> — the Search Agent's lookup falls back
/// to the empty-class row when no class-specific match is found. The
/// initial seed list ships every template with an empty
/// <code>MessageBodyClass</code> so the Search Agent's body-class-
/// agnostic search-out-of-the-box experience works without per-class
/// refinement; operators add HL7-class-scoped refinements over time.</p>
///
/// <p><b>Description text encoding (Rule 12 / Story 8.1 dev note).</b>
/// The <code>Description</code> field uses ASCII <code>-&gt;</code> as
/// the alias-to-concept connector instead of the Unicode
/// <code>&lt;-&gt;</code> arrow that the epics.md spec uses, to avoid
/// any UTF-8 round-trip mojibake risk through <code>%String</code>
/// storage. The semantics are identical; the rendering is plain ASCII.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Search.SeedVocabulary</code> — the
/// per-property doc-comments below surface as column descriptions in
/// the IRIS SQL Catalog Mgmt-Portal view.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md Story 8.1</a> — AC-2 verbatim source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR19</a> — vocabulary persistence design.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md FR23</a> — operator-immediately-useful seed-vocabulary requirement.</li>
/// </ul>
Class SessionAgent.Search.SeedVocabulary Extends %Persistent
{

/// <p>The natural-language alias the seed template registers — e.g.,
/// <code>"admit"</code>, <code>"discharge"</code>, <code>"failed message"</code>.
/// <code>MAXLEN=512</code> covers multi-word phrases without forcing a
/// stream backing store.</p>
Property Alias As %String(MAXLEN = 512);

/// <p>Optional body-class scope for per-class refinement —
/// e.g., <code>EnsLib.HL7.Message</code>. Empty means
/// <i>"applies to any class"</i> (the cross-class default). The initial
/// seed list ships every template with an empty
/// <code>MessageBodyClass</code> so the out-of-the-box Search Agent
/// experience is body-class-agnostic.</p>
Property MessageBodyClass As %String(MAXLEN = 128);

/// <p>Operator-readable description of what this alias maps to —
/// e.g., <code>"admit -&gt; A01/A04 events"</code>. ASCII
/// <code>-&gt;</code> is the chosen connector (per the class-level
/// note above). <code>MAXLEN=2048</code> accommodates richer multi-clause
/// descriptions for compound concepts.</p>
Property Description As %String(MAXLEN = 2048);

/// <p>Comma-separated synonym list — additional natural-language phrases
/// the operator might type that the Search Agent should treat
/// equivalently to <code>Alias</code>. E.g., for the <code>"admit"</code>
/// template: <code>"admission,admitted,admit event"</code>.
/// <code>MAXLEN=2048</code> covers extensive synonym sets.</p>
Property Aliases As %String(MAXLEN = 2048);

/// <p>Comma-separated example queries that should match this alias —
/// surfaces in operator-facing UI affordances (e.g., a future suggested-
/// query helper) and helps the Search Agent's training surface ground
/// the alias semantics. <code>MAXLEN=2048</code>.</p>
Property Examples As %String(MAXLEN = 2048);

/// <p>Non-unique index on <code>Alias</code> — supports O(log N) lookup
/// when the Search Agent walks the seed-vocabulary fallback ladder.
/// The composite <code>(Alias, MessageBodyClass)</code> existence probe
/// in <method>Seed</method> uses this index for the idempotency check.</p>
Index AliasIdx On Alias;

/// <p>Idempotently inserts the ~10 HL7-idiom seed templates. Safe to
/// invoke on every <CLASS>SessionAgent.Installer</CLASS> run — re-running
/// does NOT duplicate rows because each insert is gated by a composite-
/// key existence probe on <code>(Alias, MessageBodyClass)</code> via
/// <method>FindByAliasAndClass</method>.</p>
///
/// <p><b>Operator-visible Installer log line.</b> After this method
/// returns <code>$$$OK</code>, the Installer queries the post-Seed row
/// count via SQL and emits
/// <code>"&lt;count&gt; seed vocabulary templates ensured"</code> so
/// operators see the seed footprint on every install. On a fresh install
/// the count is the full template list (~10); on a re-install the count
/// is unchanged (idempotency).</p>
///
/// <p><b>Returns</b> <code>$$$OK</code> on full success, otherwise the
/// failing <code>%Status</code> from the underlying <code>%Save</code>
/// call. The Installer propagates the status per the project rule
/// "Write Status Checking".</p>
ClassMethod Seed() As %Status
{
    Set tSC = $$$OK
    Try {
        ; The HL7-idiom seed list — alias / description / synonyms / examples.
        ; All ship with empty MessageBodyClass (cross-class fallback).
        ; Description connector is ASCII "->" per Rule 12 mojibake-avoidance.

        Set tSC = ..InsertIfMissing("admit", "admit -> A01/A04 events", "admission,admitted,admit event,patient admit", "show me admits today,recent admissions,A01 messages")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("discharge", "discharge -> A03 events", "discharged,discharge event,patient discharge", "discharges this week,A03 messages,recent discharges")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("lab order", "lab order -> ORM messages", "lab orders,laboratory order,ORM,test order", "lab orders today,recent ORMs,laboratory test orders")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("lab result", "lab result -> ORU messages", "lab results,laboratory result,ORU,test result", "lab results today,recent ORUs,laboratory test results")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("radiology order", "radiology order -> ORM with OBR-4 imaging codes", "rad order,imaging order,radiology request", "imaging orders today,radiology ORMs,recent imaging requests")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("MRN search", "MRN search -> PID-3", "patient MRN,medical record number,patient ID", "find patient by MRN,search MRN 12345,messages for MRN")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("failed message", "failed message -> Status='Error'", "failed,errored,error message,failed session", "failed messages today,recent errors,sessions in error")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("acknowledgment", "acknowledgment -> ACK messages", "ack,acknowledgement,response ack", "ACKs today,acknowledgments received,recent ACK responses")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("transfer", "transfer -> A02 events", "patient transfer,transferred,transfer event", "transfers today,A02 messages,recent transfers")
        If $$$ISERR(tSC) Quit
        Set tSC = ..InsertIfMissing("cancellation", "cancellation -> A11/A13 events", "canceled,cancel,cancellation event,A11,A13", "cancellations today,A11 messages,canceled admits")
        If $$$ISERR(tSC) Quit
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Composite-key existence probe + insert helper. Returns
/// <code>$$$OK</code> if the row already exists (idempotent skip) or
/// the row was successfully inserted; returns the failing status from
/// <code>%Save</code> on insert failure.</p>
///
/// <p><b>Composite key:</b> <code>(Alias, MessageBodyClass)</code> per
/// AC-2. Empty <code>pMessageBodyClass</code> is the canonical
/// "cross-class" template — the seed list ships these initially and the
/// existence check matches on the empty-string composite key.</p>
ClassMethod InsertIfMissing(pAlias As %String, pDescription As %String, pAliases As %String = "", pExamples As %String = "", pMessageBodyClass As %String = "") As %Status [ Private ]
{
    Set tSC = $$$OK
    Try {
        ; Composite-key existence probe via SQL. Uses %EXACT() per project
        ; rule "IRIS SQL Case Sensitivity" so the comparison is
        ; case-sensitive. The AliasIdx index supports O(log N) prefix lookup;
        ; the second predicate filters within the matched alias set.
        ;
        ; IRIS stores an empty %String value as SQL NULL, NOT as an empty
        ; string literal — so the predicate `MessageBodyClass = ''` returns
        ; zero rows even when the OREF was %Saved with MessageBodyClass = "".
        ; To match the empty-class composite-key contract, the probe branches:
        ;   - empty pMessageBodyClass → use `MessageBodyClass IS NULL`
        ;   - non-empty pMessageBodyClass → use `%EXACT(MessageBodyClass) = ?`
        Set tFound = 0
        Set tStmt = ##class(%SQL.Statement).%New()
        If pMessageBodyClass = "" {
            Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM SessionAgent_Search.SeedVocabulary WHERE %EXACT(Alias) = ? AND MessageBodyClass IS NULL")
            If $$$ISERR(tPrepSC) {
                Set tSC = tPrepSC
                Quit
            }
            Set tRS = tStmt.%Execute(pAlias)
        } Else {
            Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM SessionAgent_Search.SeedVocabulary WHERE %EXACT(Alias) = ? AND %EXACT(MessageBodyClass) = ?")
            If $$$ISERR(tPrepSC) {
                Set tSC = tPrepSC
                Quit
            }
            Set tRS = tStmt.%Execute(pAlias, pMessageBodyClass)
        }
        If tRS.%Next() {
            Set tFound = 1
        }
        If tFound Quit

        ; Not present — insert.
        Set tRow = ##class(SessionAgent.Search.SeedVocabulary).%New()
        Set tRow.Alias = pAlias
        Set tRow.MessageBodyClass = pMessageBodyClass
        Set tRow.Description = pDescription
        Set tRow.Aliases = pAliases
        Set tRow.Examples = pExamples

        Set tSaveSC = tRow.%Save()
        If $$$ISERR(tSaveSC) {
            Set tSC = tSaveSC
            Quit
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

Storage Default
{
<Data name="SeedVocabularyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Alias</Value>
</Value>
<Value name="3">
<Value>MessageBodyClass</Value>
</Value>
<Value name="4">
<Value>Description</Value>
</Value>
<Value name="5">
<Value>Aliases</Value>
</Value>
<Value name="6">
<Value>Examples</Value>
</Value>
</Data>
<DataLocation>^SessionAgenC88B.SeedVocabularyD</DataLocation>
<DefaultData>SeedVocabularyDefaultData</DefaultData>
<IdLocation>^SessionAgenC88B.SeedVocabularyD</IdLocation>
<IndexLocation>^SessionAgenC88B.SeedVocabularyI</IndexLocation>
<StreamLocation>^SessionAgenC88B.SeedVocabularyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
