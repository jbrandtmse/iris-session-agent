/// <p>Inspection tool — returns the raw <code>Ens.MessageHeader</code> rows
/// for an Ens session, optionally filtered by minimum severity. Third of
/// the three reference inspection tools shipped by Story 2.11.</p>
///
/// <p><b>Tool name:</b> <code>message_headers</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{session_id (required), min_severity?}</code>.
/// <code>min_severity</code> is an enum: <code>info | warning | error</code>.
/// v1 implements the only meaningful filter — <code>error</code> reduces
/// the result set to rows with <code>IsError = 1</code>; <code>info</code>
/// and <code>warning</code> are accepted but currently no-op (Ens has no
/// distinct warning-vs-info column at the header level — that distinction
/// lives in <code>Ens.Util.Log</code>, surfaced by the
/// <code>event_log</code> tool shipped in Story 4.1
/// — see <CLASS>SessionAgent.Tool.Inspection.EventLog</CLASS>).</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{headers:[{id, source_config_name, target_config_name,
/// body_class, status, time_created, is_error}, ...], header_count}</code>.</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on the three
/// <code>%String</code> projections; plain comparison on
/// <code>SessionId</code> (%Integer) and <code>IsError</code> (%Boolean)
/// per <code>irislib/Ens/MessageHeaderBase.cls</code>. Parameterized
/// via <code>%SQL.Statement.%Prepare</code> + <code>%Execute(?)</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.11</a> (lines 1028–1062) — AC source.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.MessageHeaders Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "message_headers";

Parameter Description As %String = "Return Ens.MessageHeader rows for a session, optionally filtered by minimum severity.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema with an <code>enum</code>-constrained
/// optional property. <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id"},
            "min_severity": {"type": "string", "description": "Minimum severity filter.", "enum": ["info", "warning", "error"]}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Pre-validates <code>session_id</code> non-empty. Builds SQL with
/// optional <code>IsError = 1</code> filter when
/// <code>min_severity = "error"</code>. All input flows through
/// parameterized <code>?</code>-binds — never string concat.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"headers":[]}}
    Try {
        Set tSessionId = ""
        Set tMinSev = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tMinSev = pJsonArgs.%Get("min_severity")
            Set:tMinSev=$$$NULLOREF tMinSev = ""
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Story 3.0 AC-3 — case-insensitive min_severity filter + structured
        ; error on unknown values. Trim whitespace, lowercase, then validate
        ; against the accepted set. The previous Story 2.11 implementation
        ; matched only the exact string "error" silently — operators passing
        ; "ERROR" / "Error" / "warning " got silent no-ops with no signal.
        Set tMinSevNormalized = $ZConvert($ZStrip(tMinSev, "<>W"), "L")
        If (tMinSevNormalized '= "") && (tMinSevNormalized '= "info") && (tMinSevNormalized '= "warning") && (tMinSevNormalized '= "error") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":("min_severity must be one of: info, warning, error (got: " _ tMinSev _ ")")}]}
            Quit
        }

        Set tSql = "SELECT ID AS id, %EXACT(SourceConfigName) AS source_config_name, %EXACT(TargetConfigName) AS target_config_name, %EXACT(MessageBodyClassName) AS body_class, Status AS status, TimeCreated AS time_created, IsError AS is_error FROM Ens.MessageHeader WHERE SessionId = ?"
        If tMinSevNormalized = "error" {
            Set tSql = tSql _ " AND IsError = 1"
        }
        Set tSql = tSql _ " ORDER BY ID ASC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare(tSql)
        ; Story 11.2 — centralized prepare-failure gate.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName) Quit
        Set tRs = tStmt.%Execute(tSessionId)
        ; Story 14.0 — centralized execute-failure gate (cr-13-3).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRs, ..#ToolName) Quit

        Set tHeaders = []
        Set tCount = 0
        While tRs.%Next() {
            Set tHdr = {}
            Do tHdr.%Set("id", +tRs.%Get("id"), "number")
            Do tHdr.%Set("source_config_name", tRs.%Get("source_config_name"))
            Do tHdr.%Set("target_config_name", tRs.%Get("target_config_name"))
            Do tHdr.%Set("body_class", tRs.%Get("body_class"))
            Do tHdr.%Set("status", +tRs.%Get("status"), "number")
            ; Story 3.0 AC-2 — normalize TimeCreated to canonical ISO-8601 UTC Z.
            Do tHdr.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("time_created")))
            Do tHdr.%Set("is_error", +tRs.%Get("is_error"), "boolean")
            Do tHeaders.%Push(tHdr)
            Set tCount = tCount + 1
        }

        Do pResult.structuredContent.%Set("headers", tHeaders)
        Do pResult.structuredContent.%Set("header_count", tCount, "number")

        Set pResult.content.%Get(0).text = "Session " _ tSessionId _ ": " _ tCount _ " headers."
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
