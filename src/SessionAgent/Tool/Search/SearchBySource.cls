/// <p>Search tool — return Ens sessions whose
/// <CLASS>Ens.MessageHeader</CLASS> rows have an exact match on
/// <code>SourceConfigName</code> (the config name of the business host
/// that created the message). Lead indexed column is
/// <code>SourceConfigName</code>; combined with the helper's
/// <code>TimeCreated</code> window for a bounded WHERE.</p>
///
/// <p><b>Tool name:</b> <code>search_by_source</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>Input (AC-3).</b> <code>source_config_name</code> (required
/// string). <code>%EXACT()</code> wraps the predicate so case-sensitive
/// comparison fires per project rule §"IRIS SQL Case Sensitivity".</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-3.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS>.</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchBySource Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_source";

Parameter Description As %String = "Find Ens sessions whose messages originate from a given SourceConfigName (exact match) within an optional TimeCreated window.";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>SourceConfigName</code>.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["SourceConfigName"]
}

/// <p>Locked-subset JSON Schema (AC-S2). Required
/// <code>source_config_name</code>; optional
/// <code>time_window_hours</code> (default 24, max 720) and
/// <code>limit</code> (default 50, max 500).</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "source_config_name": {"type": "string", "description": "Exact SourceConfigName to filter on (e.g. 'EpicADT')."},
            "time_window_hours": {"type": "integer", "description": "TimeCreated window in hours. Default 24, max 720.", "minimum": 1, "maximum": 720},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500.", "minimum": 1, "maximum": 500}
        },
        "required": ["source_config_name"],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        Set tSourceName = ""
        Set tWindowHours = 0
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tSourceName = pJsonArgs.%Get("source_config_name")
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tSourceName=$$$NULLOREF tSourceName = ""
        If tSourceName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing source_config_name"}]}
            Quit
        }

        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(tWindowHours, .tParams, .tErr, "%EXACT(SourceConfigName) = ?")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }
        Do tParams.%Push(tSourceName)

        Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)

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
        Do pResult.structuredContent.%Set("time_window_used", tWindowUsed, "number")
        Do pResult.structuredContent.%Set("indexed_lead_column", "SourceConfigName")

        Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) from source '" _ tSourceName _ "' in the last " _ tWindowUsed _ " hour(s)."
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
