/// <p>Search tool — return Ens sessions whose
/// <CLASS>Ens.MessageHeader</CLASS> rows fall inside a caller-supplied
/// time window. The lead indexed column is <code>TimeCreated</code>;
/// the bounded-WHERE invariant (Story 8.2 / AR11 / FR19 / NFR-P2) is
/// satisfied by the <code>TimeCreated</code> predicate itself — no
/// other indexed column required.</p>
///
/// <p><b>Tool name:</b> <code>search_by_time</code>. Discoverable via
/// <method>SessionAgent.Tool.Registry.ListTools</method>; dispatchable
/// via <method>SessionAgent.Tool.Registry.Dispatch</method>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0 — passes
/// the L2 enforcement gate (FR36, NFR-S1).</p>
///
/// <p><b>Input shapes (AC-1).</b></p>
/// <ul>
/// <li><b>Default window</b> — both <code>from_time</code> and
/// <code>to_time</code> empty (or omitted). The helper's default-window
/// mode applies and the SQL filters
/// <code>TimeCreated &gt; ?</code> with <code>?</code> bound to
/// <code>now - 24h</code>.</li>
/// <li><b>Half-bounded</b> — only <code>from_time</code> supplied →
/// <code>TimeCreated &gt; ?</code>; only <code>to_time</code> →
/// <code>TimeCreated &lt; ?</code>. Both forms invoke the helper in
/// keyed-lookup mode (sentinel <code>-1</code>) so the helper does NOT
/// emit its own default <code>TimeCreated &gt; ?</code>; the explicit
/// predicate IS the bound.</li>
/// <li><b>Range</b> — both supplied →
/// <code>TimeCreated BETWEEN ? AND ?</code>.</li>
/// </ul>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{sessions:[{session_id, time_created, source_config_name,
/// target_config_name, message_body_class_name, status}, ...],
/// result_count, time_window_used, indexed_lead_column:"TimeCreated"}</code>.</p>
///
/// <p><b>SQL discipline.</b> Uses <code>%SQL.Statement.%Prepare</code> +
/// parameterized <code>%Execute(?, ...)</code> per project rule (NEVER
/// string concat into SQL). <code>%EXACT()</code> wraps every string
/// projection. Time inputs validated as 20-char ISO-8601 UTC Z form
/// before binding.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-1.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS> —
/// <method>BuildBoundedWhereClause</method> contract.</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchByTime Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_time";

Parameter Description As %String = "Find Ens sessions whose messages were created in a time window. Inputs from_time/to_time are ISO-8601 UTC Z (e.g. 2026-05-07T00:00:00Z); both empty defaults to the last 24 hours.";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead column for AR11 invariant: <code>TimeCreated</code>.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["TimeCreated"]
}

/// <p>Locked-subset JSON Schema (AC-S2). Optional <code>from_time</code>
/// and <code>to_time</code> ISO-8601 UTC Z strings; optional
/// <code>time_window_hours</code> default 24 max 720; optional
/// <code>limit</code> default 50 max 500. <code>additionalProperties</code>
/// is false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "from_time": {"type": "string", "description": "Lower-bound ISO-8601 UTC Z timestamp (e.g. 2026-05-07T00:00:00Z). Empty = no lower bound (helper default 24h applies if to_time also empty)."},
            "to_time": {"type": "string", "description": "Upper-bound ISO-8601 UTC Z timestamp. Empty = no upper bound."},
            "time_window_hours": {"type": "integer", "description": "Default-window override when both from_time/to_time empty. Default 24, max 720.", "minimum": 1, "maximum": 720},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500.", "minimum": 1, "maximum": 500}
        },
        "required": [],
        "additionalProperties": false
    }
}

/// <p>Build the bounded-WHERE fragment then dispatch via prepared SQL.
/// See class doc-comment for the four input shapes.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        Set tFromIso = ""
        Set tToIso = ""
        Set tWindowHours = 0
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tFromIso = pJsonArgs.%Get("from_time")
            Set tToIso = pJsonArgs.%Get("to_time")
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tFromIso=$$$NULLOREF tFromIso = ""
        Set:tToIso=$$$NULLOREF tToIso = ""

        ; Clamp limit to [1, 500] with default 50.
        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        ; Validate ISO-8601 inputs (when supplied) and convert to ODBC.
        Set tFromOdbc = ""
        Set tToOdbc = ""
        If tFromIso '= "" {
            Set tFromOdbc = ##class(SessionAgent.Tool.Base).IsoZToOdbc(tFromIso)
            If tFromOdbc = "INVALID" {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":"from_time must be ISO-8601 UTC Z (e.g. 2026-05-07T00:00:00Z)"}]}
                Quit
            }
        }
        If tToIso '= "" {
            Set tToOdbc = ##class(SessionAgent.Tool.Base).IsoZToOdbc(tToIso)
            If tToOdbc = "INVALID" {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":"to_time must be ISO-8601 UTC Z (e.g. 2026-05-07T00:00:00Z)"}]}
                Quit
            }
        }

        ; Build the bounded-WHERE fragment + params.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ""
        Set tWindowUsed = 0

        If (tFromOdbc = "") && (tToOdbc = "") {
            ; Default-window mode — helper emits "TimeCreated > ?" + cutoff.
            Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(tWindowHours, .tParams, .tErr, "")
            If $IsObject(tErr) && (tErr.%Size() > 0) {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
                Quit
            }
            Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)
        } Else {
            ; Explicit-bound mode — keyed-lookup sentinel suppresses the
            ; helper's default predicate; we supply the explicit time
            ; predicate(s) as additional predicates and bind the values.
            If (tFromOdbc '= "") && (tToOdbc '= "") {
                Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "TimeCreated BETWEEN ? AND ?")
                Do tParams.%Push(tFromOdbc)
                Do tParams.%Push(tToOdbc)
            } ElseIf (tFromOdbc '= "") {
                Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "TimeCreated > ?")
                Do tParams.%Push(tFromOdbc)
            } Else {
                Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(..#KeyedLookupSentinel, .tParams, .tErr, "", "TimeCreated < ?")
                Do tParams.%Push(tToOdbc)
            }
            ; tWindowUsed reporting for explicit-bound mode: report 0
            ; (caller drove the bound directly; no helper-default applied).
            Set tWindowUsed = 0
        }

        ; Build SQL and execute.
        Set tSql = "SELECT DISTINCT TOP ? mh.SessionId AS sid, MIN(mh.TimeCreated) AS tc, MIN(%EXACT(mh.SourceConfigName)) AS src, MIN(%EXACT(mh.TargetConfigName)) AS tgt, MIN(%EXACT(mh.MessageBodyClassName)) AS bc, MIN(mh.Status) AS st FROM Ens.MessageHeader mh WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MIN(mh.TimeCreated) DESC"
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare(tSql)
        ; Story 11.2 — centralized prepare-failure gate.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit

        ; Bind: limit first, then the cutoff/explicit-bound params already
        ; on tParams. IRIS %SQL.Statement.%Execute requires the variadic
        ; args to be applied via the multi-dim local-array form
        ; (tArgs(N) = val ; tArgs = count ; %Execute(tArgs...)) — the
        ; %DynamicArray... unpack form does NOT bind correctly, returning
        ; 0 rows for what should be matching predicates.
        Kill tArgs
        Set tArgs(1) = tLimit
        Set tArgIdx = 1
        Set tIter = tParams.%GetIterator()
        While tIter.%GetNext(.tKey, .tVal) {
            Set tArgIdx = tArgIdx + 1
            Set tArgs(tArgIdx) = tVal
        }
        Set tArgs = tArgIdx
        Set tRs = tStmt.%Execute(tArgs...)
        ; Story 14.0 — centralized execute-failure gate (cr-13-3).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRs, ..#ToolName) Quit

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
        Do pResult.structuredContent.%Set("indexed_lead_column", "TimeCreated")

        Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) in the requested time window."
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
