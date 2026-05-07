/// <p>Search tool — return Ens sessions whose
/// <CLASS>Ens.MessageHeader</CLASS> rows match one or more
/// <code>Status</code> values (e.g., <code>Error</code>,
/// <code>Suspended</code>, <code>Completed</code>). The lead indexed
/// column is <code>Status</code>; combined with the helper's
/// <code>TimeCreated</code> window it satisfies the bounded-WHERE
/// invariant (Story 8.2 / AR11 / FR19 / NFR-P2).</p>
///
/// <p><b>Tool name:</b> <code>search_by_status</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>Input (AC-2).</b> <code>status_in</code> is an array of
/// <CLASS>Ens.DataType.MessageStatus</CLASS> display values
/// (case-insensitive: <code>Created</code>, <code>Queued</code>,
/// <code>Delivered</code>, <code>Discarded</code>,
/// <code>Suspended</code>, <code>Deferred</code>, <code>Aborted</code>,
/// <code>Error</code>, <code>Completed</code>). Internally translated to
/// the integer codes 1..9 used by the underlying <code>Status</code>
/// column (per <code>irislib/Ens/DataType/MessageStatus.cls</code>).</p>
///
/// <p><b>SQL discipline.</b> The <code>Status IN (?, ?, ...)</code>
/// placeholder count is synthesized at call time — one <code>?</code>
/// per array element, with values pushed onto the params array in
/// lockstep with the placeholder string (NEVER concatenates user input
/// into SQL text). Combined with the helper's
/// <code>TimeCreated &gt; ?</code> window so the WHERE leads with an
/// indexed column AND is time-bounded.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-2.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS>.</li>
/// <li><a href="../../../../irislib/Ens/DataType/MessageStatus.cls">irislib/Ens/DataType/MessageStatus.cls</a> — VALUELIST/DISPLAYLIST mapping.</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchByStatus Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_status";

Parameter Description As %String = "Find Ens sessions whose messages match one or more Status values (Error, Suspended, Completed, etc.) within an optional TimeCreated window.";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>Status</code>.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["Status"]
}

/// <p>Locked-subset JSON Schema (AC-S2). Required <code>status_in</code>
/// array of accepted status enum strings; optional
/// <code>time_window_hours</code> (default 24, max 720) and
/// <code>limit</code> (default 50, max 500).</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "status_in": {"type": "array", "description": "Status values: Created, Queued, Delivered, Discarded, Suspended, Deferred, Aborted, Error, Completed (case-insensitive).", "items": {"type": "string"}, "minItems": 1, "maxItems": 9},
            "time_window_hours": {"type": "integer", "description": "TimeCreated window in hours. Default 24, max 720.", "minimum": 1, "maximum": 720},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500.", "minimum": 1, "maximum": 500}
        },
        "required": ["status_in"],
        "additionalProperties": false
    }
}

/// <p>Translate a single <CLASS>Ens.DataType.MessageStatus</CLASS>
/// display value to its integer code. Returns 0 when the value does
/// not appear in the DISPLAYLIST. Case-insensitive on input.</p>
ClassMethod StatusDisplayToCode(pDisplay As %String) As %Integer
{
    Set tNorm = $ZConvert($ZStrip(pDisplay, "<>W"), "L")
    Quit $Case(tNorm,
        "created":1,
        "queued":2,
        "delivered":3,
        "discarded":4,
        "suspended":5,
        "deferred":6,
        "aborted":7,
        "error":8,
        "completed":9,
        :0)
}

/// <p>Build the bounded-WHERE fragment plus a synthesized
/// <code>Status IN (?, ?, ...)</code> clause. Placeholder count
/// matches the <code>status_in</code> array length; values pushed onto
/// <var>tParams</var> in lockstep.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        Set tStatusIn = ""
        Set tWindowHours = 0
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tStatusIn = pJsonArgs.%Get("status_in")
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        If '$IsObject(tStatusIn) || (tStatusIn.%Size() = 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"status_in must be a non-empty array of status values"}]}
            Quit
        }

        ; Clamp limit.
        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        ; ---- Synthesize "Status IN (?, ?, ...)" placeholder string.
        ; Loop the input array; for each entry, translate display→code,
        ; reject unknown values via structured envelope, and append "?,"
        ; to the placeholder string while pushing the integer code onto
        ; tStatusValues (a parallel list bound after the helper's cutoff).
        Set tInClause = ""
        Set tStatusValues = []
        Set tIter = tStatusIn.%GetIterator()
        Set tBadValue = ""
        While tIter.%GetNext(.tKey, .tDisp) {
            Set tCode = ..StatusDisplayToCode(tDisp)
            If tCode = 0 {
                Set tBadValue = tDisp
                Quit
            }
            If tInClause = "" {
                Set tInClause = "?"
            } Else {
                Set tInClause = tInClause _ ",?"
            }
            Do tStatusValues.%Push(tCode)
        }
        If tBadValue '= "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("status_in contains unknown value: '" _ tBadValue _ "' — accepted: Created, Queued, Delivered, Discarded, Suspended, Deferred, Aborted, Error, Completed")}]}
            Quit
        }

        ; Build the bounded WHERE — helper emits "TimeCreated > ?" + cutoff,
        ; then we AND in our IN clause.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(tWindowHours, .tParams, .tErr, "", "Status IN (" _ tInClause _ ")")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }

        ; Append status code values onto tParams in lockstep.
        Set tValIter = tStatusValues.%GetIterator()
        While tValIter.%GetNext(.tValKey, .tVal) {
            Do tParams.%Push(tVal)
        }

        Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)

        Set tSql = "SELECT DISTINCT TOP ? mh.SessionId AS sid, MIN(mh.TimeCreated) AS tc, MIN(%EXACT(mh.SourceConfigName)) AS src, MIN(%EXACT(mh.TargetConfigName)) AS tgt, MIN(%EXACT(mh.MessageBodyClassName)) AS bc, MIN(mh.Status) AS st FROM Ens.MessageHeader mh WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MIN(mh.TimeCreated) DESC"
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCp) {
            Set tErrText = $System.Status.GetErrorText(tSCp)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
            Quit
        }

        ; Variadic %Execute via multi-dim local-array apply (the
        ; %DynamicArray... unpack form does not bind correctly — see
        ; SearchByTime.cls for the originating finding).
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
        Do pResult.structuredContent.%Set("indexed_lead_column", "Status")

        Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) matching the requested status values in the last " _ tWindowUsed _ " hour(s)."
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
