/// <p>Inspection tool — returns shape, duration, error count, and root
/// message class for an Ens Interoperability session. First of the three
/// reference inspection tools shipped by Story 2.11; the remaining 10
/// tools land in Epic 4.</p>
///
/// <p><b>Tool name:</b> <code>session_summary</code>. Discoverable via
/// <method>SessionAgent.Tool.Registry.ListTools</method>; dispatchable
/// via <method>SessionAgent.Tool.Registry.Dispatch</method>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0 — passes
/// the L2 enforcement gate (FR36, NFR-S1).</p>
///
/// <p><b>Input:</b> <code>{session_id: string}</code> (required).</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{message_count, error_count, duration_ms, root_message_class, session_exists}</code>.
/// <code>content[0].text</code> carries a one-line operator-readable
/// summary suitable for chat-panel rendering. The boolean
/// <code>session_exists</code> field (Story 3.0 AC-4) lets the LLM
/// distinguish a row-count of zero "the session was purged" from
/// "the session id does not exist at all".</p>
///
/// <p><b>SQL discipline.</b> Uses <code>%SQL.Statement.%Prepare</code> +
/// parameterized <code>%Execute(?)</code> per project rule (NEVER string
/// concat into SQL). <code>%EXACT()</code> wraps every <i>string</i>
/// projection per project rule §"IRIS SQL Case Sensitivity" — note
/// <property>Ens.MessageHeader.SessionId</property> is <code>%Integer</code>
/// per <code>irislib/Ens/MessageHeaderBase.cls</code>, so no
/// <code>%EXACT()</code> wrap on the predicate (string-comparison
/// semantics on integer columns are misleading).</p>
///
/// <p><b>Story 3.0 AC-2.</b> The two timestamp-bearing fields the original
/// Story 2.11 design omitted — first/last event timestamps for span
/// computation — are now also surfaced indirectly via
/// <code>duration_ms</code>. Where this tool returns a timestamp
/// directly (none in this tool, but cf. <CLASS>SessionAgent.Tool.Inspection.SessionTimeline</CLASS>
/// and <CLASS>SessionAgent.Tool.Inspection.MessageHeaders</CLASS>),
/// the value is normalized to the canonical 20-character ISO-8601
/// UTC Z form (<code>YYYY-MM-DDTHH:MM:SSZ</code>) using
/// <method>NormalizeIsoZ</method>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.11</a> (lines 1028–1062) — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Pattern Examples — canonical tool implementation skeleton"
/// (lines 688–746).</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR55–FR58, NFR-S1, NFR-S6.</li>
/// <li>Story 3.0 §"AC-4 — SessionSummary returns 'session not found'
/// envelope" — adds the count-of-rows pre-check + boolean
/// <code>session_exists</code>.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.SessionSummary Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "session_summary";

Parameter Description As %String = "Return shape, duration, error count, and root message class for an Ens session. structuredContent.session_exists is false when no Ens.MessageHeader rows exist for the requested id (purged or never existed).";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Single required string property
/// <code>session_id</code>; <code>additionalProperties</code> is false
/// (architecture §"Tool input JSON Schema subset").</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id"}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Pre-validates <code>session_id</code> non-empty and returns the
/// MCP error envelope on validation failure (NEVER throws — exceptions
/// are caught by the outer <CLASS>SessionAgent.Tool.Registry</CLASS>
/// Dispatch only as defense-in-depth).</p>
///
/// <p>Story 3.0 AC-4: count-of-rows pre-check. If
/// <code>SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ?</code>
/// returns 0, the structured envelope sets <code>session_exists=false</code>
/// and the operator-facing text says "Session &lt;id&gt; has no rows in
/// Ens.MessageHeader (it may not exist or may have been purged)". The
/// LLM uses this to distinguish a missing session from a purged one.</p>
///
/// <p>Two SQL queries on the existing-session path:</p>
/// <ol>
/// <li>Aggregate: <code>COUNT(*)</code>, error sum, MIN/MAX TimeCreated.</li>
/// <li>Root message class: first row by ID ascending (the request that
/// launched the session — Ens convention).</li>
/// </ol>
///
/// <p>Duration computed via SQL <code>DATEDIFF('ms', first, last)</code>
/// rather than ObjectScript date math — keeps the cast inside the
/// query engine where TIMESTAMP arithmetic is well-defined.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tSessionId = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
        }
        If (tSessionId = "") || ($Get(tSessionId) = $$$NULLOREF) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Story 3.0 AC-4 — count-of-rows pre-check. If zero, return the
        ; "session not found" envelope with session_exists=false so the
        ; LLM can distinguish "missing" from "empty".
        Set tCountStmt = ##class(%SQL.Statement).%New()
        Set tCountSC = tCountStmt.%Prepare("SELECT COUNT(*) AS rc FROM Ens.MessageHeader WHERE SessionId = ?")
        ; Story 4.7 AC-7 — emit isError envelope on prepare failure rather
        ; than silently quitting (Story 4.5 R-1 carry-forward fix).
        If $$$ISERR(tCountSC) {
            Set tErr = $System.Status.GetErrorText(tCountSC)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErr)}}
            Quit
        }
        Set tCountRs = tCountStmt.%Execute(tSessionId)
        Set tRowCount = 0
        If tCountRs.%Next() {
            Set tRowCount = +tCountRs.%Get("rc")
        }
        If tRowCount = 0 {
            Do pResult.structuredContent.%Set("message_count", 0, "number")
            Do pResult.structuredContent.%Set("error_count", 0, "number")
            Do pResult.structuredContent.%Set("session_exists", 0, "boolean")
            Do pResult.structuredContent.%Set("root_message_class", "")
            Set pResult.content.%Get(0).text = "Session " _ tSessionId _ " has no rows in Ens.MessageHeader (it may not exist or may have been purged)"
            Quit
        }

        ; Aggregate query — counts + duration in ms. SessionId is %Integer
        ; so no %EXACT() wrap on the predicate (project rule covers string
        ; columns; see Dev Notes in story file).
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("SELECT COUNT(*) AS msg_count, SUM(CASE WHEN IsError=1 THEN 1 ELSE 0 END) AS err_count, DATEDIFF('ms', MIN(TimeCreated), MAX(TimeCreated)) AS duration_ms FROM Ens.MessageHeader WHERE SessionId = ?")
        If $$$ISERR(tSC) {
            Set tErr = $System.Status.GetErrorText(tSC)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErr)}}
            Quit
        }
        Set tRs = tStmt.%Execute(tSessionId)
        Set tMsgCount = 0
        Set tErrCount = 0
        Set tDurationMs = 0
        If tRs.%Next() {
            Set tMsgCount = +tRs.%Get("msg_count")
            Set tErrCount = +tRs.%Get("err_count")
            Set tDurationMs = +tRs.%Get("duration_ms")
        }

        ; Root message class — first row by ID ascending. %EXACT() on
        ; the string projection so the original case is preserved
        ; (e.g., "MyApp.Request" not "myapp.request").
        Set tStmt2 = ##class(%SQL.Statement).%New()
        Set tSC2 = tStmt2.%Prepare("SELECT TOP 1 %EXACT(MessageBodyClassName) AS root_class FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID ASC")
        If $$$ISERR(tSC2) {
            Set tErr = $System.Status.GetErrorText(tSC2)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErr)}}
            Quit
        }
        Set tRs2 = tStmt2.%Execute(tSessionId)
        Set tRootClass = ""
        If tRs2.%Next() {
            Set tRootClass = tRs2.%Get("root_class")
        }

        Do pResult.structuredContent.%Set("message_count", tMsgCount, "number")
        Do pResult.structuredContent.%Set("error_count", tErrCount, "number")
        Do pResult.structuredContent.%Set("duration_ms", tDurationMs, "number")
        Do pResult.structuredContent.%Set("root_message_class", tRootClass)
        Do pResult.structuredContent.%Set("session_exists", 1, "boolean")

        Set pResult.content.%Get(0).text = "Session " _ tSessionId _ ": " _ tMsgCount _ " messages, " _ tErrCount _ " errors, root class " _ tRootClass _ "."
        Quit
    }
    Catch ex {
        ; Story 4.7 AC-7 — operator-friendly catch text (Story 4.5 R-4
        ; carry-forward fix). Helper strips IRIS-internal prefixes from
        ; ex.DisplayString().
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

}
