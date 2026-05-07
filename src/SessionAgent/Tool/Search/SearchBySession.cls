/// <p>Search tool — single-row keyed lookup by
/// <CLASS>Ens.MessageHeader</CLASS> <code>SessionId</code>. Returns the
/// session's representative envelope (one entry in
/// <code>sessions</code>) regardless of how old the rows are. The
/// time-window predicate is OMITTED — a keyed lookup IS its own bound
/// (architecture §"OD8 keyed-lookup mode") and the
/// <method>BuildBoundedWhereClause</method> helper is invoked with the
/// <code>KeyedLookupSentinel</code> (<code>-1</code>) so it does NOT emit
/// a <code>TimeCreated &gt; ?</code> default predicate.</p>
///
/// <p><b>Tool name:</b> <code>search_by_session</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>Input (AC-6).</b> <code>session_id</code> (required string —
/// the operator-facing Ens session id; underlying column is
/// <code>%Integer</code> so no <code>%EXACT()</code> wrap on the
/// predicate). The <code>time_window_used</code> field in the response
/// envelope is OMITTED for this tool to make keyed-lookup mode visible
/// to operators / LLMs.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-6.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS> §"KeyedLookupSentinel".</li>
/// <li>architecture.md §"OD8 keyed-lookup mode".</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchBySession Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_session";

Parameter Description As %String = "Look up a single Ens session by SessionId — keyed-lookup mode bypasses the time window so old sessions still resolve.";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>SessionId</code>
/// (keyed-lookup mode — single-row pick is its own bound).</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["SessionId"]
}

/// <p>Locked-subset JSON Schema (AC-S2 + AC-6). Required
/// <code>session_id</code>; optional <code>limit</code> (mostly a
/// formality for keyed lookup — multiple headers per session are
/// aggregated into a single result row).</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens SessionId — operator-facing integer surfaced as a string."},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500. (For keyed lookup the result is at most one row.)", "minimum": 1, "maximum": 500}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        Set tSessionId = ""
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tSessionId=$$$NULLOREF tSessionId = ""
        If tSessionId = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        ; ---- Keyed-lookup mode — sentinel -1 suppresses the helper's
        ; TimeCreated > ? default; the SessionId predicate IS the bound.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "SessionId = ?")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }
        Do tParams.%Push(tSessionId)

        Set tSql = "SELECT DISTINCT TOP ? mh.SessionId AS sid, MIN(mh.TimeCreated) AS tc, MIN(%EXACT(mh.SourceConfigName)) AS src, MIN(%EXACT(mh.TargetConfigName)) AS tgt, MIN(%EXACT(mh.MessageBodyClassName)) AS bc, MIN(mh.Status) AS st FROM Ens.MessageHeader mh WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MIN(mh.TimeCreated) DESC"
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
            Do tEntry.%Set("message_body_class_name", tRs.%Get("bc"))
            Do tEntry.%Set("status", +tRs.%Get("st"), "number")
            Do tSessions.%Push(tEntry)
            Set tCount = tCount + 1
        }

        Do pResult.structuredContent.%Set("sessions", tSessions)
        Do pResult.structuredContent.%Set("result_count", tCount, "number")
        ; AC-6: omit time_window_used for keyed-lookup; emit JSON null
        ; (operator-facing signal "no window applied"). Per project rule
        ; §"%DynamicObject properties" the type hint "null" produces a
        ; JSON null, not the string "null".
        Do pResult.structuredContent.%Set("time_window_used", "", "null")
        Do pResult.structuredContent.%Set("indexed_lead_column", "SessionId")

        If tCount = 0 {
            Set pResult.content.%Get(0).text = "Session " _ tSessionId _ " not found in Ens.MessageHeader (it may not exist or may have been purged)."
        } Else {
            Set pResult.content.%Get(0).text = "Found session " _ tSessionId _ " (keyed lookup — no time window applied)."
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

}
