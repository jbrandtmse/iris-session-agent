/// <p>Inspection tool — returns chronological message events in an Ens
/// session as <code>(source → target)</code> pairs with timestamps.
/// Second of the three reference inspection tools shipped by Story 2.11.</p>
///
/// <p><b>Tool name:</b> <code>session_timeline</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{session_id (required), from_time?, to_time?}</code>.
/// Optional <code>from_time</code>/<code>to_time</code> are ISO-8601 UTC
/// bounds applied as inclusive <code>TimeCreated &gt;= ?</code> /
/// <code>&lt;= ?</code> filters.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{events:[{src, tgt, time, status, body_class}, ...], event_count, time_span_ms}</code>.
/// Events are sorted ASC by <code>TimeCreated</code> then by <code>ID</code>
/// (deterministic ordering for sessions where multiple headers share a
/// timestamp resolution).</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on string projections
/// (<code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>); plain comparison on
/// <code>SessionId</code> (%Integer per
/// <code>irislib/Ens/MessageHeaderBase.cls</code>) and
/// <code>TimeCreated</code> (TIMESTAMP). Parameterized via
/// <code>%SQL.Statement.%Prepare</code> + <code>%Execute(?, ...)</code>
/// — NEVER string concat.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.11</a> (lines 1028–1062) — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Pattern Examples — canonical tool implementation skeleton".</li>
/// </ul>
Class SessionAgent.Tool.Inspection.SessionTimeline Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "session_timeline";

Parameter Description As %String = "Return chronological message events in an Ens session — sender to receiver pairs with timestamps.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. <code>session_id</code> required;
/// <code>from_time</code>/<code>to_time</code> optional ISO-8601 UTC
/// bounds. <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id"},
            "from_time": {"type": "string", "description": "Optional ISO-8601 UTC lower bound (inclusive)."},
            "to_time": {"type": "string", "description": "Optional ISO-8601 UTC upper bound (inclusive)."}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Pre-validates <code>session_id</code> non-empty (returns MCP
/// error envelope on validation failure). Builds the SQL dynamically
/// based on which optional time bounds are supplied — but ALL values
/// pass through parameterized <code>?</code> placeholders, NEVER concat.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"events":[]}}
    Try {
        Set tSessionId = ""
        Set tFromTime = ""
        Set tToTime = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tFromTime = pJsonArgs.%Get("from_time")
            Set tToTime = pJsonArgs.%Get("to_time")
            Set:tFromTime=$$$NULLOREF tFromTime = ""
            Set:tToTime=$$$NULLOREF tToTime = ""
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Story 3.0 AC-2 — parse ISO-8601 UTC Z input bounds into ODBC
        ; TIMESTAMP form for SQL bind. Empty values pass through; the
        ; sentinel "INVALID" surfaces as a structured error envelope.
        Set tFromOdbc = ##class(SessionAgent.Tool.Base).IsoZToOdbc(tFromTime)
        If tFromOdbc = "INVALID" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"from_time must be ISO-8601 UTC, e.g. 2026-05-03T19:30:00Z"}]}
            Quit
        }
        Set tToOdbc = ##class(SessionAgent.Tool.Base).IsoZToOdbc(tToTime)
        If tToOdbc = "INVALID" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"to_time must be ISO-8601 UTC, e.g. 2026-05-03T19:30:00Z"}]}
            Quit
        }

        ; Build SQL with optional time bounds. ?-bound parameters appended
        ; in order matching the predicate composition.
        Set tSql = "SELECT %EXACT(SourceConfigName) AS src, %EXACT(TargetConfigName) AS tgt, TimeCreated AS event_time, Status AS status, %EXACT(MessageBodyClassName) AS body_class FROM Ens.MessageHeader WHERE SessionId = ?"
        If tFromOdbc '= "" {
            Set tSql = tSql _ " AND TimeCreated >= ?"
        }
        If tToOdbc '= "" {
            Set tSql = tSql _ " AND TimeCreated <= ?"
        }
        Set tSql = tSql _ " ORDER BY TimeCreated ASC, ID ASC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare(tSql)
        ; Story 4.7 AC-7 — emit isError envelope on prepare failure
        ; (Story 4.5 R-1 carry-forward fix).
        If $$$ISERR(tSC) {
            Set tErr = $System.Status.GetErrorText(tSC)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErr)}}
            Quit
        }

        ; Dispatch the right %Execute arity based on which bounds we appended.
        If (tFromOdbc = "") && (tToOdbc = "") {
            Set tRs = tStmt.%Execute(tSessionId)
        } ElseIf (tFromOdbc '= "") && (tToOdbc = "") {
            Set tRs = tStmt.%Execute(tSessionId, tFromOdbc)
        } ElseIf (tFromOdbc = "") && (tToOdbc '= "") {
            Set tRs = tStmt.%Execute(tSessionId, tToOdbc)
        } Else {
            Set tRs = tStmt.%Execute(tSessionId, tFromOdbc, tToOdbc)
        }

        Set tEvents = []
        Set tFirstTime = ""
        Set tLastTime = ""
        Set tCount = 0
        While tRs.%Next() {
            Set tEvent = {}
            ; Story 3.0 AC-2 — normalize TimeCreated to canonical ISO-8601 UTC Z.
            Set tT = ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("event_time"))
            Do tEvent.%Set("src", tRs.%Get("src"))
            Do tEvent.%Set("tgt", tRs.%Get("tgt"))
            Do tEvent.%Set("time", tT)
            Do tEvent.%Set("status", +tRs.%Get("status"), "number")
            Do tEvent.%Set("body_class", tRs.%Get("body_class"))
            Do tEvents.%Push(tEvent)
            If tCount = 0 Set tFirstTime = tRs.%Get("event_time")
            Set tLastTime = tRs.%Get("event_time")
            Set tCount = tCount + 1
        }

        ; Time span via SQL DATEDIFF on the two endpoint values. We could
        ; have computed this in the loop, but a single DATEDIFF query
        ; defers the TIMESTAMP arithmetic to the engine.
        Set tSpanMs = 0
        If (tFirstTime '= "") && (tLastTime '= "") && (tCount > 1) {
            Set tStmt2 = ##class(%SQL.Statement).%New()
            Set tSC2 = tStmt2.%Prepare("SELECT DATEDIFF('ms', ?, ?) AS span_ms")
            If $$$ISOK(tSC2) {
                Set tRs2 = tStmt2.%Execute(tFirstTime, tLastTime)
                If tRs2.%Next() {
                    Set tSpanMs = +tRs2.%Get("span_ms")
                }
            }
        }

        Do pResult.structuredContent.%Set("events", tEvents)
        Do pResult.structuredContent.%Set("event_count", tCount, "number")
        Do pResult.structuredContent.%Set("time_span_ms", tSpanMs, "number")

        Set pResult.content.%Get(0).text = "Session " _ tSessionId _ ": " _ tCount _ " events spanning " _ tSpanMs _ "ms."
        Quit
    }
    Catch ex {
        ; Story 4.7 AC-7 — operator-friendly catch text (Story 4.5 R-4).
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

}
