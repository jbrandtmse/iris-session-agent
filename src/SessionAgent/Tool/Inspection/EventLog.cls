/// <p>Inspection tool — returns <CLASS>Ens.Util.Log</CLASS> rows for an
/// Ens session, optionally filtered by <code>message_id</code> and/or
/// minimum severity. First of the two new inspection tools shipped by
/// Story 4.1; the canonical pattern reference is
/// <CLASS>SessionAgent.Tool.Inspection.MessageHeaders</CLASS> (Story
/// 2.11) — same parameterized-SQL + ISO-8601 normalization shape, but
/// adapted to <code>Ens.Util.Log</code>'s richer severity tiers
/// (assert / error / warning / info — four named buckets, plus
/// trace/alert which are excluded from the operator-facing surface).</p>
///
/// <p><b>Tool name:</b> <code>event_log</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{session_id (required), message_id?, min_severity?, limit?}</code>.
/// <code>min_severity</code> is an enum: <code>info | warning | error |
/// assert</code> (case-insensitive — the Story 3.0 AC-3 normalize-and-
/// validate pattern is reused). <code>limit</code> defaults to 100,
/// minimum 1, maximum 1000.</p>
///
/// <p><b>Severity mapping (per <code>irislib/Ens/DataType/LogType.cls</code>
/// VALUELIST/DISPLAYLIST).</b> The IRIS-side <code>Type</code> integer
/// values are <code>1=Assert, 2=Error, 3=Warning, 4=Info, 5=Trace,
/// 6=Alert</code> — LOWER integer means HIGHER severity. The
/// <code>min_severity</code> filter therefore translates to
/// <code>Type &lt;= N</code> (NOT <code>&gt;=</code>), where N is the
/// integer for the requested tier:
/// <code>min_severity='error'</code> → <code>Type &lt;= 2</code>
/// (assert + error); <code>min_severity='warning'</code> →
/// <code>Type &lt;= 3</code> (assert + error + warning); etc. Trace
/// (5) and Alert (6) are always excluded from the result set so the
/// operator-facing surface stays tied to the four severity buckets the
/// LLM reasons about.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{events:[{id, time_logged, severity, source, text, session_id,
/// message_id}, ...], event_count, severity_counts: {info, warning,
/// error, assert}}</code>. <code>severity_counts</code> always has four
/// keys (zero when absent) so the JSON shape is stable. The counts
/// reflect the <b>true distribution</b> over the <code>SessionId</code>
/// + <code>Type&lt;=N</code> + <code>MessageId</code> predicate via a
/// second <code>GROUP BY Type</code> query — they are NOT limited by
/// the <code>TOP ?</code> cap that governs the <code>events</code>
/// array. So a session with 200 errors and a <code>limit=10</code> call
/// returns 10 events and <code>severity_counts.error=200</code>.</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on all
/// <code>%String</code> projections (<code>SourceClass</code>,
/// <code>Text</code>); plain comparison on
/// <code>SessionId</code> (%Integer per
/// <code>irislib/Ens/Util/LogBase.cls</code> line 27),
/// <code>MessageId</code> (%Integer per same line 42), and
/// <code>Type</code> (%Integer). Parameterized via
/// <code>%SQL.Statement.%Prepare</code> + <code>%Execute(?, ...)</code> —
/// NEVER string concat.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.1</a> (lines 1449–1476) — AC source.</li>
/// <li><a href="../../../../irislib/Ens/Util/Log.cls">irislib/Ens/Util/Log.cls</a>
/// + <a href="../../../../irislib/Ens/Util/LogBase.cls">LogBase.cls</a>
/// — column definitions + <code>Type</code> mapping.</li>
/// <li><a href="../../../../irislib/Ens/DataType/LogType.cls">irislib/Ens/DataType/LogType.cls</a>
/// — VALUELIST/DISPLAYLIST integer→label mapping.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.EventLog Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "event_log";

Parameter Description As %String = "Read Ens.Util.Log entries for a session, optionally filtered by message_id or min_severity.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema with optional message_id, optional
/// enum-constrained min_severity, optional bounded limit. Required:
/// <code>session_id</code>. <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id"},
            "message_id": {"type": "string", "description": "Optional Ens.MessageHeader id filter."},
            "min_severity": {"type": "string", "description": "Minimum severity filter (assert is most severe).", "enum": ["info", "warning", "error", "assert"]},
            "limit": {"type": "integer", "description": "Max rows returned. Default 100.", "minimum": 1, "maximum": 1000}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Pre-validates <code>session_id</code> non-empty, normalizes
/// <code>min_severity</code> (trim + lowercase + validate against
/// <code>info/warning/error/assert</code>), clamps <code>limit</code>
/// to <code>[1, 1000]</code> with default 100. Builds parameterized
/// SQL with optional <code>MessageId = ?</code> and <code>Type &lt;= ?</code>
/// predicates — all input via <code>?</code>-binds, NEVER concat.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"events":[]}}
    Try {
        Set tSessionId = ""
        Set tMessageId = ""
        Set tMinSev = ""
        Set tLimit = 100
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tMessageId = pJsonArgs.%Get("message_id")
            Set tMinSev = pJsonArgs.%Get("min_severity")
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tMessageId=$$$NULLOREF tMessageId = ""
            Set:tMinSev=$$$NULLOREF tMinSev = ""
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Story 3.0 AC-3 — case-insensitive min_severity validation.
        ; Trim whitespace, lowercase, then validate against accepted set.
        Set tMinSevNormalized = $ZConvert($ZStrip(tMinSev, "<>W"), "L")
        If (tMinSevNormalized '= "") && (tMinSevNormalized '= "info") && (tMinSevNormalized '= "warning") && (tMinSevNormalized '= "error") && (tMinSevNormalized '= "assert") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("min_severity must be one of: info, warning, error, assert (got: " _ tMinSev _ ")")}]}
            Quit
        }

        ; Map severity label → IRIS Type integer (per irislib
        ; Ens.DataType.LogType — 1=Assert, 2=Error, 3=Warning, 4=Info).
        ; LOWER integer = HIGHER severity, so the predicate is Type <= N.
        Set tMaxType = 4 ; default = include info (and everything more severe)
        If tMinSevNormalized = "assert" Set tMaxType = 1
        If tMinSevNormalized = "error" Set tMaxType = 2
        If tMinSevNormalized = "warning" Set tMaxType = 3
        If tMinSevNormalized = "info" Set tMaxType = 4

        ; Clamp limit to [1, 1000] with default 100.
        If (tLimit < 1) Set tLimit = 100
        If (tLimit > 1000) Set tLimit = 1000

        ; Build SQL. Type filter is ALWAYS applied (excludes Trace=5 +
        ; Alert=6 from the operator-facing surface — they're not in the
        ; four-tier severity hierarchy this tool exposes). MessageId
        ; predicate is conditional.
        Set tSql = "SELECT TOP ? ID AS id, TimeLogged AS time_logged, Type AS type_int, %EXACT(SourceClass) AS source, %EXACT(Text) AS text, SessionId AS session_id, MessageId AS message_id FROM Ens_Util.Log WHERE SessionId = ? AND Type <= ?"
        If tMessageId '= "" {
            Set tSql = tSql _ " AND MessageId = ?"
        }
        Set tSql = tSql _ " ORDER BY ID ASC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare(tSql)
        Quit:$$$ISERR(tSC)

        ; Dispatch %Execute arity — TOP is always first, then SessionId,
        ; then Type cap, then optional MessageId.
        If tMessageId = "" {
            Set tRs = tStmt.%Execute(tLimit, tSessionId, tMaxType)
        } Else {
            Set tRs = tStmt.%Execute(tLimit, tSessionId, tMaxType, tMessageId)
        }

        Set tEvents = []
        Set tCount = 0
        While tRs.%Next() {
            Set tEv = {}
            Set tTypeInt = +tRs.%Get("type_int")
            Set tSeverity = $Case(tTypeInt, 1:"assert", 2:"error", 3:"warning", 4:"info", 5:"trace", 6:"alert", :"unknown")
            Do tEv.%Set("id", +tRs.%Get("id"), "number")
            Do tEv.%Set("time_logged", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("time_logged")))
            Do tEv.%Set("severity", tSeverity)
            Do tEv.%Set("source", tRs.%Get("source"))
            Do tEv.%Set("text", tRs.%Get("text"))
            Do tEv.%Set("session_id", +tRs.%Get("session_id"), "number")
            Do tEv.%Set("message_id", +tRs.%Get("message_id"), "number")
            Do tEvents.%Push(tEv)
            Set tCount = tCount + 1
        }

        ; Severity counts via SECOND query (per spec AC-3 step 8: a SQL
        ; GROUP BY Type over the same WHERE predicate). Counts reflect the
        ; TRUE distribution under the same SessionId / Type<=N / MessageId
        ; filters — NOT just the rows that fit the TOP cap. This matters
        ; when a session has more matching rows than `limit` returns: the
        ; operator sees the real severity distribution rather than a count
        ; truncated by pagination. (Story 4.1 review F-1, 2026-05-03.)
        Set tCntInfo = 0
        Set tCntWarn = 0
        Set tCntErr = 0
        Set tCntAssert = 0
        Set tSqlCount = "SELECT Type AS type_int, COUNT(*) AS cnt FROM Ens_Util.Log WHERE SessionId = ? AND Type <= ?"
        If tMessageId '= "" {
            Set tSqlCount = tSqlCount _ " AND MessageId = ?"
        }
        Set tSqlCount = tSqlCount _ " GROUP BY Type"
        Set tStmtCount = ##class(%SQL.Statement).%New()
        Set tSCcnt = tStmtCount.%Prepare(tSqlCount)
        If $$$ISOK(tSCcnt) {
            If tMessageId = "" {
                Set tRsCount = tStmtCount.%Execute(tSessionId, tMaxType)
            } Else {
                Set tRsCount = tStmtCount.%Execute(tSessionId, tMaxType, tMessageId)
            }
            While tRsCount.%Next() {
                Set tT = +tRsCount.%Get("type_int")
                Set tN = +tRsCount.%Get("cnt")
                If tT = 1 Set tCntAssert = tN
                If tT = 2 Set tCntErr = tN
                If tT = 3 Set tCntWarn = tN
                If tT = 4 Set tCntInfo = tN
            }
        }

        Set tSevCounts = {}
        Do tSevCounts.%Set("info", tCntInfo, "number")
        Do tSevCounts.%Set("warning", tCntWarn, "number")
        Do tSevCounts.%Set("error", tCntErr, "number")
        Do tSevCounts.%Set("assert", tCntAssert, "number")

        Do pResult.structuredContent.%Set("events", tEvents)
        Do pResult.structuredContent.%Set("event_count", tCount, "number")
        Do pResult.structuredContent.%Set("severity_counts", tSevCounts)

        ; Summary text. When the returned `events` array was capped by
        ; the TOP limit (count < sum-of-severity-counts), call out the
        ; truncation so the operator knows there are more rows behind
        ; the limit. Otherwise emit the simple form.
        Set tTotalSev = tCntInfo + tCntWarn + tCntErr + tCntAssert
        If tCount < tTotalSev {
            Set pResult.content.%Get(0).text = tCount _ " of " _ tTotalSev _ " event(s) returned for session " _ tSessionId _ " (limit reached; severity totals: " _ tCntErr _ " error / " _ tCntWarn _ " warning / " _ tCntInfo _ " info / " _ tCntAssert _ " assert)."
        } Else {
            Set pResult.content.%Get(0).text = tCount _ " event(s) for session " _ tSessionId _ " (severity: " _ tCntErr _ " error / " _ tCntWarn _ " warning / " _ tCntInfo _ " info / " _ tCntAssert _ " assert)."
        }
        Quit
    }
    Catch ex {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(ex.DisplayString())}]}
        Quit
    }
    Quit tSC
}

}
