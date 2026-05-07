/// <p>Search tool — enumerate Ens sessions that share a super-session
/// key (cross-instance / cross-BP fan-out via
/// <CLASS>Ens.SuperSessionIndex</CLASS>). The tool accepts EITHER an
/// explicit <code>super_session_key</code> XOR a <code>seed_session_id</code>
/// from which the super-session key is derived via a Phase-1 lookup —
/// exactly one MUST be provided.</p>
///
/// <p><b>Tool name:</b> <code>search_by_super_session</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>Input (AC-2).</b> Both <code>super_session_key</code> and
/// <code>seed_session_id</code> are declared optional in the JSON Schema
/// because the locked subset (architecture §"Tool input JSON Schema
/// subset") forbids <code>oneOf</code>/<code>anyOf</code>. The XOR
/// semantics is enforced at <method>Invoke</method> time and surfaced
/// via a structured-error envelope on violation. The tool's
/// <parameter>Description</parameter> tells the LLM to provide exactly
/// one.</p>
///
/// <p><b>Two-phase Invoke (AC-3).</b></p>
/// <ol>
/// <li><b>Phase 1</b> (only when <code>seed_session_id</code> provided):
/// resolve super-session key via JOIN of <CLASS>Ens.SuperSessionIndex</CLASS>
/// to <CLASS>Ens.MessageHeader</CLASS> on the seed's SessionId
/// (<code>SELECT TOP 1 %EXACT(ssi.SuperSession) … WHERE mh.SessionId =
/// ?</code>). If no row, return structured error envelope. Same lookup
/// pattern as Story 4.5's
/// <CLASS>SessionAgent.Tool.Inspection.FindRelatedSessions</CLASS>.</li>
/// <li><b>Phase 2</b> (always): keyed-lookup-mode WHERE +
/// JOIN-shape SELECT against the same two tables grouped by
/// <code>SessionId</code>. <method>Tool.Search.Base.BuildBoundedWhereClause</method>
/// is invoked with the keyed-lookup sentinel
/// (<parameter>KeyedLookupSentinel</parameter>) so NO
/// <code>TimeCreated &gt; ?</code> default predicate is emitted —
/// super-session-key lookup IS its own bound (architecture §"OD8
/// keyed-lookup mode").</li>
/// </ol>
///
/// <p><b>Operator-name vs schema-column distinction.</b>
/// <method>GetIndexedLeadColumns</method> returns
/// <code>["SuperSessionKey"]</code> (the operator-readable name matching
/// Story 8.2 <method>BuildIndexedColumnSet</method>'s documented indexed
/// set). The SQL JOIN/WHERE uses the literal schema name
/// <code>ssi.SuperSession</code>. This intentional naming distinction
/// keeps the indexed-set lookup operator-friendly while the SQL stays
/// schema-literal.</p>
///
/// <p><b>Output (structuredContent, AC-5).</b>
/// <code>{super_session_key, sessions: [{session_id, time_created,
/// source_config_name, target_config_name, message_count}, …],
/// session_count, indexed_lead_column: "SuperSessionKey",
/// time_window_used: null}</code>. <code>time_window_used</code> is
/// JSON <code>null</code> (parallel to
/// <CLASS>SessionAgent.Tool.Search.SearchBySession</CLASS>'s
/// keyed-lookup convention from Story 8.3) — operator/LLM-visible
/// signal that no window applied.</p>
///
/// <p><b>SQL safety + %EXACT() discipline.</b> Every <code>%String</code>
/// projection (<code>SuperSession</code>, <code>SourceConfigName</code>,
/// <code>TargetConfigName</code>) wraps <code>%EXACT()</code> per project
/// rule §"IRIS SQL Case Sensitivity". <code>SessionId</code> (%Integer)
/// and <code>ID</code> (%BigInt) are not wrapped. All caller-supplied
/// values bind via <code>%SQL.Statement.%Prepare</code> +
/// <code>%Execute</code> — NEVER concatenated into SQL text
/// (architecture §"Search-Arg-Construction Safety").</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.4</a> — AC source.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS> §"KeyedLookupSentinel".</li>
/// <li><CLASS>SessionAgent.Tool.Inspection.FindRelatedSessions</CLASS>
/// (Story 4.5) — same JOIN/lookup pattern.</li>
/// <li><CLASS>SessionAgent.Tool.Search.SearchBySession</CLASS> (Story 8.3)
/// — sibling keyed-lookup-mode pattern.</li>
/// <li><a href="../../../../irislib/Ens/SuperSessionIndex.cls">irislib/Ens/SuperSessionIndex.cls</a>
/// — verified column structure (no <code>SessionId</code> column on
/// the index; resolution flows through the FK to
/// <CLASS>Ens.MessageHeader</CLASS>).</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchBySuperSession Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_super_session";

Parameter Description As %String = "Enumerate sessions sharing a super-session key (cross-instance / cross-BP fan-out via Ens.SuperSessionIndex). Provide EXACTLY ONE of super_session_key OR seed_session_id (the latter resolves the key from the seed's SuperSessionIndex entry).";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>SuperSessionKey</code>
/// (operator-readable name; the underlying schema column is
/// <code>Ens.SuperSessionIndex.SuperSession</code>). Keyed-lookup mode —
/// single-row pick is its own bound.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["SuperSessionKey"]
}

/// <p>Locked-subset JSON Schema. Both <code>super_session_key</code>
/// and <code>seed_session_id</code> declared optional (the locked
/// subset cannot express XOR via <code>oneOf</code>); XOR is enforced
/// at <method>Invoke</method> time. Optional <code>limit</code>
/// defaults to 50, max 500.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "super_session_key": {"type": "string", "description": "Explicit super-session key (e.g. '2|host:port|123'). Provide EITHER this OR seed_session_id, not both."},
            "seed_session_id": {"type": "string", "description": "Seed Ens SessionId — the tool resolves the super-session key from this session's SuperSessionIndex entry. Provide EITHER this OR super_session_key, not both."},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500.", "minimum": 1, "maximum": 500}
        },
        "required": [],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        ; ---- Argument extraction.
        Set tSuperKey = ""
        Set tSeedId = ""
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tSuperKeyArg = pJsonArgs.%Get("super_session_key")
            Set:tSuperKeyArg'=$$$NULLOREF tSuperKey = tSuperKeyArg
            Set tSeedArg = pJsonArgs.%Get("seed_session_id")
            Set:tSeedArg'=$$$NULLOREF tSeedId = tSeedArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tSuperKey=$$$NULLOREF tSuperKey = ""
        Set:tSeedId=$$$NULLOREF tSeedId = ""

        ; ---- AC-2 XOR enforcement at Invoke-time.
        Set tHasKey = (tSuperKey '= "")
        Set tHasSeed = (tSeedId '= "")
        If 'tHasKey && 'tHasSeed {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"Provide either super_session_key OR seed_session_id, not neither"}]}
            Quit
        }
        If tHasKey && tHasSeed {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"Provide either super_session_key OR seed_session_id, not both"}]}
            Quit
        }

        ; Clamp limit to [1, 500] with default 50.
        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        ; ---- Phase 1 — resolve super-session key from seed_session_id (only when seed provided).
        ; Same JOIN/lookup pattern as Story 4.5 FindRelatedSessions: the index has no
        ; SessionId column; resolution flows through ssi.MessageHeader = mh.ID.
        If tHasSeed {
            Set tSqlLookup = "SELECT TOP 1 %EXACT(ssi.SuperSession) AS super_session FROM Ens.SuperSessionIndex ssi JOIN Ens.MessageHeader mh ON ssi.MessageHeader = mh.ID WHERE mh.SessionId = ?"
            Set tStmtLookup = ##class(%SQL.Statement).%New()
            Set tSCp = tStmtLookup.%Prepare(tSqlLookup)
            If $$$ISERR(tSCp) {
                Set tErrText = $System.Status.GetErrorText(tSCp)
                Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
                Quit
            }
            Set tRsLookup = tStmtLookup.%Execute(tSeedId)
            Set tResolved = ""
            If tRsLookup.%Next() {
                Set tResolved = tRsLookup.%Get("super_session")
            }
            If (tResolved = "") {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":("seed_session_id " _ tSeedId _ " has no super-session entry in Ens.SuperSessionIndex")}], "structuredContent":{"render_strategy":"no_super_session_for_seed", "seed_session_id":(tSeedId)}}
                Quit
            }
            Set tSuperKey = tResolved
        }

        ; ---- Phase 2 — keyed-lookup-mode WHERE + JOIN-shape SELECT.
        ; The keyed-lookup sentinel suppresses the helper's TimeCreated > ?
        ; default; the ssi.SuperSession predicate IS the bound.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "%EXACT(ssi.SuperSession) = ?")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }
        Do tParams.%Push(tSuperKey)

        Set tSql = "SELECT TOP ? mh.SessionId AS sid, MIN(mh.TimeCreated) AS tc, MIN(%EXACT(mh.SourceConfigName)) AS src, MIN(%EXACT(mh.TargetConfigName)) AS tgt, COUNT(*) AS message_count FROM Ens.SuperSessionIndex ssi JOIN Ens.MessageHeader mh ON ssi.MessageHeader = mh.ID WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MIN(mh.TimeCreated) DESC"
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp2 = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCp2) {
            Set tErrText = $System.Status.GetErrorText(tSCp2)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
            Quit
        }

        ; Variadic %Execute via canonical multi-dim local-array apply form.
        Kill tArgs
        Set tArgs(1) = tLimit
        Set tArgIdx = 1
        Set tBindIter = tParams.%GetIterator()
        While tBindIter.%GetNext(.tBindKey, .tBindVal) {
            Set tArgIdx = tArgIdx + 1
            Set tArgs(tArgIdx) = tBindVal
        }
        Set tArgs = tArgIdx
        Set tRs = tStmt.%Execute(tArgs...)

        Set tSessions = []
        Set tCount = 0
        While tRs.%Next() {
            Set tEntry = {}
            Do tEntry.%Set("session_id", +tRs.%Get("sid"), "number")
            Do tEntry.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("tc")))
            Do tEntry.%Set("source_config_name", tRs.%Get("src"))
            Do tEntry.%Set("target_config_name", tRs.%Get("tgt"))
            Do tEntry.%Set("message_count", +tRs.%Get("message_count"), "number")
            Do tSessions.%Push(tEntry)
            Set tCount = tCount + 1
        }

        Do pResult.structuredContent.%Set("super_session_key", tSuperKey)
        Do pResult.structuredContent.%Set("sessions", tSessions)
        Do pResult.structuredContent.%Set("session_count", tCount, "number")
        Do pResult.structuredContent.%Set("indexed_lead_column", "SuperSessionKey")
        ; AC-5: time_window_used is JSON null for keyed-lookup mode (parallel
        ; to Story 8.3 SearchBySession). Per project rule §"%DynamicObject
        ; properties" the type hint "null" produces a JSON null (not the
        ; string "null").
        Do pResult.structuredContent.%Set("time_window_used", "", "null")

        If tCount = 0 {
            Set pResult.content.%Get(0).text = "No sessions found for super-session key '" _ tSuperKey _ "'."
        } Else {
            Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) sharing super-session key '" _ tSuperKey _ "'."
        }
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
        Quit
    }
    Quit tSC
}

}
