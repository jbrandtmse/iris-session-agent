/// <p>Story 8.7 — search-agent tool that lets the operator manage their
/// own per-portal-user vocabulary (FR21) via the agent itself. Three
/// modes — <code>list</code>, <code>save</code>, <code>search</code> —
/// dispatch on the required <code>mode</code> input. Operates against
/// the <CLASS>SessionAgent.Search.UserVocabulary</CLASS> table seeded
/// in Story 8.1.</p>
///
/// <p><b>Tool name:</b> <code>vocab_lookup</code>. The 10th and final
/// search-agent tool, closing the Epic 8 acceptance gate (per
/// <a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.7</a>'s final clause).</p>
///
/// <p><b>Read-only invariant — <parameter>MutatesState</parameter>=0.</b>
/// Mode <code>save</code> DOES write to
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS>, but
/// <parameter>MutatesState</parameter> is the FR31 / NFR-S1 Layer 2
/// flag for <code>Ens.*</code> mutation specifically.
/// <code>UserVocabulary</code> is iris-session-agent's own data, NOT
/// <code>Ens.*</code>, so <parameter>MutatesState</parameter>=0 is
/// correct per the FR31 contract. The <code>(SessionAgent, VocabWrite,
/// explicit)</code> audit emit (per AC-4) is the authoritative record
/// of the write — NOT the <parameter>MutatesState</parameter> flag.
/// <b>Future readers: do NOT flip the flag.</b></p>
///
/// <p><b>Bounded-WHERE invariant.</b> This tool does NOT query
/// <code>Ens.*</code> — it queries
/// <code>SessionAgent_Search.UserVocabulary</code>. The bounded-WHERE
/// invariant (FR19, AR11) is satisfied by the <code>PortalUser</code>
/// keyed-lookup mode (<code>WHERE %EXACT(PortalUser) = ?</code>) — no
/// <code>TimeCreated</code> window applies because vocabulary queries
/// are user-scoped, not time-bounded. The
/// <method>BuildBoundedWhereClause</method> helper is invoked with the
/// <code>KeyedLookupSentinel</code> (<code>-1</code>) to suppress the
/// time-window predicate.
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> validates
/// the invariant by reading <method>GetIndexedLeadColumns</method>; this
/// story extends <method>BoundedWhereInvariantTest.BuildIndexedColumnSet</method>
/// to add <code>"PortalUser"</code> as an accepted lead column.</p>
///
/// <p><b>Audit emit — <code>(SessionAgent, VocabWrite, explicit)</code>.</b>
/// Mode <code>save</code> emits a native audit event via
/// <code>$System.Security.Audit("SessionAgent","VocabWrite","explicit",...)</code>.
/// The triple is pre-registered by
/// <CLASS>SessionAgent.Audit.Emit</CLASS> §EnsureEvents (Story 1.3 line
/// 56) at install time. Per project rule §"Security.Events
/// Pre-Registration for Audit", an unregistered triple makes the audit
/// call return <code>0</code> silently; the implementation
/// defensive-checks the return and surfaces <code>audit_emitted=0|1</code>
/// in the success envelope. The save itself succeeds regardless of
/// audit-emit success — operator data is never lost to an audit
/// configuration drift.</p>
///
/// <p><b>Aliases-field absence on UserVocabulary.</b> Story 8.1's
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS> has only an
/// <code>Alias</code> field (singular) — the <code>Aliases</code>
/// field lives on <CLASS>SessionAgent.Search.SeedVocabulary</CLASS>
/// and <CLASS>SessionAgent.Search.NamespaceVocabulary</CLASS>. The
/// <code>search</code> mode therefore filters on <code>Alias LIKE ?</code>
/// only (the epic spec's <code>Aliases LIKE</code> predicate doesn't
/// apply here; documented deviation per Story 8.7 dev notes).</p>
///
/// <p><b>Save mode probe / unique-index reconciliation
/// (review-fix HIGH).</b> Story 8.1's UserVocabulary declares
/// <code>Index UserAliasIdx On (PortalUser, Alias) [ Unique ]</code> —
/// the unique constraint is over the <i>pair</i> not the triple. The
/// epic spec's AC-4 sub-step 2 prescribed a composite-key probe over
/// <code>(PortalUser, Alias, MessageBodyClass)</code>, but a triple
/// probe drifts from the schema's pair uniqueness: a second save with
/// the same <code>(PortalUser, Alias)</code> but different
/// <code>MessageBodyClass</code> would skip the increment branch (probe
/// misses) and try to INSERT — hitting a unique-constraint violation
/// on <code>(PortalUser, Alias)</code> at <code>%Save()</code> time.
/// Resolution: the implementation probes by the pair only (matching
/// the schema's unique index) and updates the existing row's
/// <code>MessageBodyClass</code> if the operator passes a new value
/// for an existing alias. A future story (Epic 9) may add per-class
/// vocabulary refinement to UserVocabulary as a separate row family,
/// at which point the schema's unique index would migrate to include
/// MessageBodyClass; until then, pair-uniqueness is the contract.</p>
///
/// <p><b>Description input — captured in audit details, NOT in
/// UserVocabulary row (review-fix HIGH).</b> The
/// <code>description</code> input parameter is operator-readable
/// commentary about what the alias means. Story 8.1's UserVocabulary
/// schema does not declare a <code>Description</code> column — the
/// implementation persists the operator's <code>description</code>
/// into the <code>(SessionAgent, VocabWrite, explicit)</code> audit
/// row's <code>EventData</code> string so it remains durable + queryable
/// via <code>%SYS.Audit</code> / <code>iris_audit_events</code>, but is
/// NOT readable back via <code>list</code> or <code>search</code>
/// modes. Future readers: do not assume <code>description</code> round-trips
/// through the row; if a column-level persistence is needed, extend
/// the UserVocabulary schema in a follow-up story.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.7</a> — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// FR21, FR31, NFR-S1 Layer 1/2.</li>
/// <li><CLASS>SessionAgent.Search.UserVocabulary</CLASS> (Story 8.1) —
/// schema target for read/write.</li>
/// <li><CLASS>SessionAgent.Audit.Emit</CLASS> §EnsureEvents (Story 1.3) —
/// audit-event triple pre-registration.</li>
/// <li>Saved memory <code>project_search_agent_body_search_refinement.md</code>
/// — per-class <code>MessageBodyClass</code> refinement key.</li>
/// </ul>
Class SessionAgent.Tool.Search.VocabLookup Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "vocab_lookup";

Parameter Description As %String = "List, save, or search the operator's saved vocabulary aliases.";

/// <p>FR31 / NFR-S1 Layer 2 flag — <code>Ens.*</code>-mutation only.
/// vocab_lookup mode='save' writes to UserVocabulary (project's own
/// table), NOT to Ens.*. Do NOT flip this flag — see class doc-comment
/// §"Read-only invariant" for the rationale.</p>
Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>PortalUser</code>
/// (the <code>UserAliasIdx</code> on UserVocabulary leads with
/// PortalUser per Story 8.1 schema). Story 8.7 extends
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS>'s
/// <method>BuildIndexedColumnSet</method> to add <code>"PortalUser"</code>.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["PortalUser"]
}

/// <p>Locked-subset JSON Schema (AC-2). XOR semantics around
/// <code>alias</code> (required for save/search; ignored for list) is
/// enforced at <method>Invoke</method> time — the locked subset cannot
/// express conditional <code>required</code>.</p>
///
/// <p>Optional <code>limit</code> caps the list-mode page size — default
/// 50, max 200, per AC-3.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "mode": {"type": "string", "description": "One of 'list' (show user's vocabulary), 'save' (record explicit alias), 'search' (substring-match aliases).", "enum": ["list", "save", "search"]},
            "alias": {"type": "string", "description": "Required for save/search; ignored for list. The operator-confirmed natural-language alias text."},
            "description": {"type": "string", "description": "Optional free-text description of what this alias means; persisted to the (SessionAgent, VocabWrite, explicit) audit-event details by save mode (NOT readable back via list/search; UserVocabulary has no description column)."},
            "message_body_class": {"type": "string", "description": "Optional per-class refinement key (e.g., 'EnsLib.HL7.Message'). Empty means cross-class."},
            "limit": {"type": "integer", "description": "List/search mode page size — default 50 for list, 20 for search; cap 200."}
        },
        "required": ["mode"],
        "additionalProperties": false
    }
}

/// <p>Dispatch on <code>mode</code>:
/// <code>list</code> → <method>InvokeList</method>;
/// <code>save</code> → <method>InvokeSave</method>;
/// <code>search</code> → <method>InvokeSearch</method>.</p>
///
/// <p><b>Caller-context contract.</b>
/// <property>pCallerCtx.PortalUser</property> is the per-row scope key
/// for every mode. If empty (e.g., a non-CSP test context), returns a
/// structured error envelope so the caller can re-invoke with a
/// populated context.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tMode = ""
        Set tAlias = ""
        Set tDescription = ""
        Set tBodyClass = ""
        Set tLimit = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tMode = pJsonArgs.%Get("mode")
            Set tAlias = pJsonArgs.%Get("alias")
            Set tDescription = pJsonArgs.%Get("description")
            Set tBodyClass = pJsonArgs.%Get("message_body_class")
            Set tLimit = pJsonArgs.%Get("limit")
        }
        Set:tMode=$$$NULLOREF tMode = ""
        Set:tAlias=$$$NULLOREF tAlias = ""
        Set:tDescription=$$$NULLOREF tDescription = ""
        Set:tBodyClass=$$$NULLOREF tBodyClass = ""
        Set:tLimit=$$$NULLOREF tLimit = ""

        ; Caller-context guard — PortalUser MUST be present.
        Set tPortalUser = ""
        If $IsObject($Get(pCallerCtx)) Set tPortalUser = pCallerCtx.PortalUser
        If tPortalUser = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"vocab_lookup requires authenticated PortalUser"}]}
            Quit
        }

        ; Mode dispatch.
        If tMode = "list" {
            Do ..InvokeList(tPortalUser, tLimit, .pResult)
        } ElseIf tMode = "save" {
            ; XOR — alias required.
            If tAlias = "" {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":"vocab_lookup mode='save' requires non-empty 'alias'"}]}
                Quit
            }
            Do ..InvokeSave(tPortalUser, tAlias, tDescription, tBodyClass, .pResult)
        } ElseIf tMode = "search" {
            If tAlias = "" {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":"vocab_lookup mode='search' requires non-empty 'alias'"}]}
                Quit
            }
            Do ..InvokeSearch(tPortalUser, tAlias, tLimit, .pResult)
        } Else {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("vocab_lookup mode must be one of 'list' | 'save' | 'search'; got: '" _ tMode _ "'")}]}
            Quit
        }
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

/// <p>Mode <code>list</code> (AC-3) — return all UserVocabulary rows for
/// <var>pPortalUser</var> ordered by <code>Confidence DESC, LastUsed
/// DESC</code>. Default limit 50, max 200 (operator's full personal
/// vocabulary; <var>pLimit</var> empty / 0 / unset selects the default).
/// Bounded-WHERE invariant satisfied via the <code>PortalUser</code>
/// keyed-lookup predicate (no time window applies; vocabulary is
/// user-scoped not time-bounded).</p>
ClassMethod InvokeList(pPortalUser As %String, pLimit As %String, ByRef pResult As %DynamicObject)
{
    Set tParams = []
    Set tErr = ""
    Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "%EXACT(PortalUser) = ?")
    If $IsObject(tErr) && (tErr.%Size() > 0) {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
        Quit
    }
    ; Page-size — default 50, cap 200, ignore non-numeric / non-positive.
    Set tLimit = 50
    If $Get(pLimit) '= "", +pLimit > 0 {
        Set tLimit = +pLimit
        If tLimit > 200 Set tLimit = 200
    }
    Set tSql = "SELECT TOP ? %EXACT(Alias) AS al, %EXACT(MessageBodyClass) AS bc, Confidence AS cf, %EXACT(LastUsed) AS lu, %EXACT(CreatedAt) AS ca, %EXACT(CreatedVia) AS cv, SuccessCount AS sc, FailureCount AS fc FROM SessionAgent_Search.UserVocabulary WHERE " _ tFragment _ " ORDER BY Confidence DESC, %EXACT(LastUsed) DESC"
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare(tSql)
    If $$$ISERR(tSCp) {
        Set tErrText = $System.Status.GetErrorText(tSCp)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
        Quit
    }

    ; Variadic %Execute via multi-dim local-array apply.
    Kill tArgs
    Set tArgs(1) = tLimit
    Set tArgIdx = 1
    Set tBindIter = tParams.%GetIterator()
    While tBindIter.%GetNext(.tBindKey, .tBindVal) {
        Set tArgIdx = tArgIdx + 1
        Set tArgs(tArgIdx) = tBindVal
    }
    Set tArgs(2) = pPortalUser
    Set tArgs = $Select(tArgIdx<2:2, 1:tArgIdx)
    Set tRs = tStmt.%Execute(tArgs...)

    Set tVocab = []
    Set tCount = 0
    Set tConfidenceSum = 0
    While tRs.%Next() {
        Set tEntry = {}
        Do tEntry.%Set("alias", tRs.%Get("al"))
        Do tEntry.%Set("message_body_class", tRs.%Get("bc"))
        Do tEntry.%Set("confidence", +tRs.%Get("cf"), "number")
        Do tEntry.%Set("last_used", tRs.%Get("lu"))
        Do tEntry.%Set("created_at", tRs.%Get("ca"))
        Do tEntry.%Set("created_via", tRs.%Get("cv"))
        Do tEntry.%Set("success_count", +tRs.%Get("sc"), "number")
        Do tEntry.%Set("failure_count", +tRs.%Get("fc"), "number")
        Do tVocab.%Push(tEntry)
        Set tConfidenceSum = tConfidenceSum + (+tRs.%Get("cf"))
        Set tCount = tCount + 1
    }

    Do pResult.structuredContent.%Set("mode", "list")
    Do pResult.structuredContent.%Set("portal_user", pPortalUser)
    Do pResult.structuredContent.%Set("vocabulary", tVocab)
    Do pResult.structuredContent.%Set("count", tCount, "number")
    Do pResult.structuredContent.%Set("indexed_lead_column", "PortalUser")

    If tCount = 0 {
        Set pResult.content.%Get(0).text = "You have no saved vocabulary aliases yet."
    } Else {
        Set tAvg = tConfidenceSum / tCount
        Set pResult.content.%Get(0).text = "You have " _ tCount _ " saved vocabulary alias(es) (avg confidence " _ $Number(tAvg, 2) _ ")."
    }
    Quit
}

/// <p>Mode <code>save</code> (AC-4) — explicit alias save. Probes the
/// schema's unique <code>(PortalUser, Alias)</code> pair (matching
/// <code>UserAliasIdx</code>'s declared uniqueness — see class
/// doc-comment §"Save mode probe / unique-index reconciliation"). When
/// the operator supplies a new <var>pBodyClass</var> for an existing
/// alias row, the row's <code>MessageBodyClass</code> is updated
/// alongside the increment.</p>
///
/// <p>If row exists: increment <code>SuccessCount</code>, update
/// <code>LastUsed</code> (and <code>MessageBodyClass</code> if changed),
/// save. If new: create row with <code>CreatedVia="explicit"</code>,
/// <code>CreatedAt</code> ISO-8601 UTC Z, <code>SuccessCount=1</code>,
/// initial <code>Confidence=0</code> at insert time. Story 9.2's
/// <code>%OnAfterSave</code> trigger then recomputes
/// <code>Confidence = Success / (Success + Failure + 1)</code> via
/// direct SQL UPDATE before the save returns — so the post-save
/// observable value is <code>0.5</code> on first insert
/// (<code>1 / (1+0+1)</code>). The <method>InvokeSave</method>
/// implementation delegates to
/// <method>SessionAgent.Search.UserVocabulary.RecordSuccess</method>
/// (Story 9.2 AC-4 refactor) — that ClassMethod owns the probe →
/// branch → save → audit-emit logic.</p>
///
/// <p><b>Audit emit defensive check.</b>
/// <code>$System.Security.Audit</code> returns <code>0</code> if the
/// triple is unregistered (silent fail per project rule
/// §"Security.Events Pre-Registration"). The Story 9.2 refactor
/// delegates audit emission to
/// <method>SessionAgent.Search.UserVocabulary.RecordSuccess</method>
/// which returns the audit-emit return value via the new
/// <var>pAuditEmitted</var> ByRef parameter (review fix
/// MEDIUM-9.2-F01). <method>InvokeSave</method> surfaces this verbatim
/// as <code>audit_emitted=0|1</code> in the envelope so operators /
/// reviewers can detect a registration drift; the row save succeeds
/// regardless. The operator-supplied <var>pDescription</var> is
/// captured in the audit-event details string so the operator's
/// commentary about the alias is durably retained alongside the row
/// save (per class doc-comment §"Description input — captured in
/// audit details").</p>
///
/// <p><b>Envelope <code>description_persisted</code> field (Story 9.2
/// additive — review fix LOW-9.2-F04).</b> The Story 9.2 refactor adds
/// a new structured-content field <code>description_persisted</code>
/// (1 if <var>pDescription</var> was non-empty, 0 otherwise) to let
/// operators / chat panels detect whether their description text made
/// it to the audit row. This is an ADDITIVE change to the envelope
/// shape — not a "preservation" of pre-9.2 behavior. Pre-9.2 callers
/// that don't read this field continue to work; new callers can
/// observe the description-persistence signal.</p>
ClassMethod InvokeSave(pPortalUser As %String, pAlias As %String, pDescription As %String, pBodyClass As %String, ByRef pResult As %DynamicObject)
{
    ; ---- Pre-probe to detect created vs incremented action — same pair-
    ; unique probe RecordSuccess uses internally. Done BEFORE delegation so
    ; the envelope's "action" field can distinguish a fresh insert from an
    ; increment of an existing row (downstream callers depend on this for
    ; the rendered text differentiation).
    Set tFoundIdBefore = ""
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    If $$$ISERR(tPrepSC) {
        Set tErrText = $System.Status.GetErrorText(tPrepSC)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Set tRsBefore = tStmt.%Execute(pPortalUser, pAlias)
    If tRsBefore.%Next() Set tFoundIdBefore = tRsBefore.%Get("ID")
    Set tAction = $Select(tFoundIdBefore '= "": "incremented", 1: "created")

    ; ---- Story 9.2 AC-4 delegation. RecordSuccess handles the probe →
    ; branch → save → audit-emit logic + Confidence recompute via
    ; %OnAfterSave trigger. pCreatedVia="explicit" preserves the pre-9.2
    ; behavior (the row's CreatedVia field is the originating provenance,
    ; only set on the insert path; an existing row's CreatedVia is NOT
    ; overwritten by RecordSuccess). The ByRef tAuditEmitted captures the
    ; $System.Security.Audit return value (review fix MEDIUM-9.2-F01) so
    ; the envelope's audit_emitted field can detect triple-registration
    ; drift (matches pre-refactor 8.7 defensive surface).
    Set tAuditEmitted = 0
    Set tSC = ##class(SessionAgent.Search.UserVocabulary).RecordSuccess(pPortalUser, pAlias, pBodyClass, "explicit", pDescription, .tAuditEmitted)
    If $$$ISERR(tSC) {
        Set tErrText = $System.Status.GetErrorText(tSC)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }

    ; ---- Re-probe to read post-save SuccessCount for envelope shaping.
    ; Surface a prep failure rather than silently defaulting to 0 (review
    ; fix LOW-9.2-F03) — drift would otherwise be invisible to callers.
    Set tNewSuccessCount = 0
    Set tStmt2 = ##class(%SQL.Statement).%New()
    Set tPrepSC2 = tStmt2.%Prepare("SELECT TOP 1 SuccessCount FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    If $$$ISERR(tPrepSC2) {
        Set tErrText = $System.Status.GetErrorText(tPrepSC2)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Set tRsAfter = tStmt2.%Execute(pPortalUser, pAlias)
    If tRsAfter.%Next() Set tNewSuccessCount = +tRsAfter.%Get("SuccessCount")

    Do pResult.structuredContent.%Set("mode", "save")
    Do pResult.structuredContent.%Set("portal_user", pPortalUser)
    Do pResult.structuredContent.%Set("alias", pAlias)
    Do pResult.structuredContent.%Set("message_body_class", pBodyClass)
    Do pResult.structuredContent.%Set("action", tAction)
    Do pResult.structuredContent.%Set("new_success_count", tNewSuccessCount, "number")
    Do pResult.structuredContent.%Set("audit_emitted", tAuditEmitted, "number")
    Do pResult.structuredContent.%Set("description_persisted", $Select(pDescription'="": 1, 1: 0), "number")
    Do pResult.structuredContent.%Set("indexed_lead_column", "PortalUser")

    If tAction = "created" {
        Set pResult.content.%Get(0).text = "Saved new vocabulary alias '" _ pAlias _ "' for portal user '" _ pPortalUser _ "'."
    } Else {
        Set pResult.content.%Get(0).text = "Vocabulary alias '" _ pAlias _ "' already existed; success_count incremented to " _ tNewSuccessCount _ "."
    }
    Quit
}

/// <p>Mode <code>search</code> (AC-5) — substring search on
/// <code>Alias</code> for <var>pPortalUser</var>. Pattern wraps the
/// operator-supplied alias in <code>'%' _ pAlias _ '%'</code>;
/// default limit 20, cap 200 (substring searches are bounded by the
/// operator's per-user vocabulary size which the schema doesn't cap).</p>
///
/// <p><b>Aliases-field absence deviation.</b> Story 8.1's UserVocabulary
/// has only an <code>Alias</code> field. The epic spec's
/// <code>Aliases LIKE</code> predicate is dropped — see class
/// doc-comment §"Aliases-field absence on UserVocabulary".</p>
ClassMethod InvokeSearch(pPortalUser As %String, pAlias As %String, pLimit As %String, ByRef pResult As %DynamicObject)
{
    Set tPattern = "%" _ pAlias _ "%"
    Set tParams = []
    Set tErr = ""
    Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "%EXACT(PortalUser) = ? AND %EXACT(Alias) LIKE ?")
    If $IsObject(tErr) && (tErr.%Size() > 0) {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
        Quit
    }
    ; Page-size — default 20, cap 200, ignore non-numeric / non-positive.
    Set tLimit = 20
    If $Get(pLimit) '= "", +pLimit > 0 {
        Set tLimit = +pLimit
        If tLimit > 200 Set tLimit = 200
    }
    Set tSql = "SELECT TOP ? %EXACT(Alias) AS al, %EXACT(MessageBodyClass) AS bc, Confidence AS cf, %EXACT(LastUsed) AS lu, %EXACT(CreatedAt) AS ca, %EXACT(CreatedVia) AS cv, SuccessCount AS sc, FailureCount AS fc FROM SessionAgent_Search.UserVocabulary WHERE " _ tFragment _ " ORDER BY Confidence DESC, %EXACT(LastUsed) DESC"
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare(tSql)
    If $$$ISERR(tSCp) {
        Set tErrText = $System.Status.GetErrorText(tSCp)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
        Quit
    }

    Kill tArgs
    Set tArgs(1) = tLimit
    Set tArgs(2) = pPortalUser
    Set tArgs(3) = tPattern
    Set tArgs = 3
    Set tRs = tStmt.%Execute(tArgs...)

    Set tMatches = []
    Set tCount = 0
    While tRs.%Next() {
        Set tEntry = {}
        Do tEntry.%Set("alias", tRs.%Get("al"))
        Do tEntry.%Set("message_body_class", tRs.%Get("bc"))
        Do tEntry.%Set("confidence", +tRs.%Get("cf"), "number")
        Do tEntry.%Set("last_used", tRs.%Get("lu"))
        Do tEntry.%Set("created_at", tRs.%Get("ca"))
        Do tEntry.%Set("created_via", tRs.%Get("cv"))
        Do tEntry.%Set("success_count", +tRs.%Get("sc"), "number")
        Do tEntry.%Set("failure_count", +tRs.%Get("fc"), "number")
        Do tMatches.%Push(tEntry)
        Set tCount = tCount + 1
    }

    Do pResult.structuredContent.%Set("mode", "search")
    Do pResult.structuredContent.%Set("portal_user", pPortalUser)
    Do pResult.structuredContent.%Set("alias_pattern", pAlias)
    Do pResult.structuredContent.%Set("matches", tMatches)
    Do pResult.structuredContent.%Set("count", tCount, "number")
    Do pResult.structuredContent.%Set("indexed_lead_column", "PortalUser")

    If tCount = 0 {
        Set pResult.content.%Get(0).text = "No vocabulary aliases match '" _ pAlias _ "'."
    } Else {
        Set pResult.content.%Get(0).text = "Found " _ tCount _ " vocabulary alias(es) matching '" _ pAlias _ "'."
    }
    Quit
}

}
