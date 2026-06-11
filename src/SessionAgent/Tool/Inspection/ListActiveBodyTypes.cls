/// <p>Schema-discovery tool — windowed census of which message body
/// classes are actually flowing through <CLASS>Ens.MessageHeader</CLASS>
/// and at what volume. The most useful first query in any namespace:
/// it tells the agent which body tables have data worth joining to
/// before any SQL is authored (FR61, Story 14.2 AC-1).</p>
///
/// <p><b>Tool name:</b> <code>list_active_body_types</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{hours (optional int, default 168, clamped
/// 1..2160)}</code>.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{hours, window_start, body_types:[{body_class, msg_count}],
/// body_type_count, truncated, render_strategy:"ok"}</code>. The census
/// is TOP-bounded at <parameter>MAXBODYTYPES</parameter> distinct body
/// classes (highest-volume first; <code>truncated:true</code> on
/// overflow) so the envelope stays inside the result-size discipline
/// the sibling discovery tools enforce. Headers with an empty
/// <code>MessageBodyClassName</code> surface as <code>(no body)</code>.
/// An empty census is NOT an error — <code>body_types:[]</code> with
/// <code>render_strategy:"ok"</code> (CouchDB-style envelope discipline;
/// error envelopes are reserved for validation/prepare/execute faults).</p>
///
/// <p><b>TimeCreated window (Task 0 probe, 2026-06-11).</b>
/// <code>Ens.MessageHeader.TimeCreated</code> stores UTC
/// (<CLASS>Ens.DataType.UTC</CLASS>; verified live: latest header row
/// 08:50:56 vs GETUTCDATE() 09:28:17 vs local CURRENT_TIMESTAMP
/// 02:28:17). The window boundary is computed in ObjectScript from
/// <code>$ZTimeStamp</code> (UTC) and bound as a <code>?</code>
/// parameter — date arithmetic is never inlined into the SQL text.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-2-schema-discovery-tools.md">Story 14.2</a> AC-1 — AC source.</li>
/// <li><a href="../../../../docs/iris-query-guide/04-schema-discovery.md">docs/iris-query-guide/04-schema-discovery.md</a> §"Which message body types are actually in use".</li>
/// </ul>
Class SessionAgent.Tool.Inspection.ListActiveBodyTypes Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "list_active_body_types";

Parameter Description As %String = "Census of message body classes active in Ens.MessageHeader within a time window (default 7 days): each body class name with its message count, ordered by volume. Run this FIRST when asked about message types or before authoring SQL against body tables — it shows which body classes actually carry data.";

Parameter MutatesState As %Boolean = 0;

/// <p>Default census window in hours (7 days).</p>
Parameter DEFAULTWINDOWHOURS As %Integer = 168;

/// <p>Maximum census window in hours (90 days).</p>
Parameter MAXWINDOWHOURS As %Integer = 2160;

/// <p>Cap on distinct body-class census rows (highest volume first).
/// Review fix 14.2 — the census was the only unbounded result path in
/// the discovery suite; a 90-day window on a busy multi-app install can
/// group hundreds of distinct body classes.</p>
Parameter MAXBODYTYPES As %Integer = 200;

/// <p>JSON Schema — single optional <code>hours</code> integer.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "hours": {
                "type": "integer",
                "description": "Census window in hours, counted back from now (UTC). Default 168 (7 days). Clamped to 1..2160 (90 days).",
                "minimum": 1,
                "maximum": 2160
            }
        },
        "required": [],
        "additionalProperties": false
    }
}

/// <p>Compute the UTC window boundary in ObjectScript, run the
/// parameterized census, and return the envelope. Empty census returns
/// <code>body_types:[]</code> with <code>render_strategy:"ok"</code>.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"body_types":[]}}
    Try {
        ; --- Extract + clamp hours ---
        Set tHours = ..#DEFAULTWINDOWHOURS
        If $IsObject($Get(pJsonArgs)) {
            ; Type-gated read (review fix 14.2): an object/array-valued
            ; arg must not reach `\ 1` — an OREF stringifies as
            ; "n@%Library.DynamicObject" and would coerce to an arbitrary
            ; small integer. Non-number/string types fall to the default.
            Set tHoursType = pJsonArgs.%GetTypeOf("hours")
            If (tHoursType = "number") || (tHoursType = "string") {
                Set tHoursArg = pJsonArgs.%Get("hours")
                If tHoursArg '= "" Set tHours = tHoursArg \ 1
            }
        }
        If tHours < 1 Set tHours = 1
        If tHours > ..#MAXWINDOWHOURS Set tHours = ..#MAXWINDOWHOURS

        ; --- Compute UTC boundary from $ZTimeStamp (UTC), bind as ? ---
        ; TimeCreated stores UTC per Ens.DataType.UTC (Task 0 probe).
        Set tDays = +$Piece($ZTimeStamp, ",", 1)
        Set tSecs = $Piece($ZTimeStamp, ",", 2) \ 1
        Set tTotalSecs = (tDays * 86400) + tSecs - (tHours * 3600)
        Set tBoundaryH = (tTotalSecs \ 86400) _ "," _ (tTotalSecs # 86400)
        Set tBoundaryOdbc = $ZDateTime(tBoundaryH, 3, 1)

        ; --- Parameterized windowed census ---
        ; %EXACT() preserves case in MessageBodyClassName; positional
        ; %GetData reads per rules §"%EXACT() in SELECT Changes Column
        ; Aliases".
        ; TOP-bounded at MAXBODYTYPES; fetch cap+1 so `truncated`
        ; reflects genuine overflow (review fix 14.2).
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare("SELECT TOP ? %EXACT(MessageBodyClassName) AS body_class, COUNT(*) AS msg_count FROM Ens.MessageHeader WHERE TimeCreated >= ? GROUP BY %EXACT(MessageBodyClassName) ORDER BY COUNT(*) DESC")
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit
        Set tRS = tStmt.%Execute(..#MAXBODYTYPES + 1, tBoundaryOdbc)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        Set tBodyTypes = []
        Set tOverflow = 0
        While tRS.%Next() {
            If tBodyTypes.%Size() >= ..#MAXBODYTYPES { Set tOverflow = 1 Quit }
            Set tBodyClass = tRS.%GetData(1)
            Set:tBodyClass="" tBodyClass = "(no body)"
            Set tEntry = {}
            Do tEntry.%Set("body_class", tBodyClass)
            Do tEntry.%Set("msg_count", +tRS.%GetData(2), "number")
            Do tBodyTypes.%Push(tEntry)
        }
        ; Fetch-time fault gate — a mid-cursor error must not ship partial
        ; rows inside an ok envelope (review fix 14.2).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- Build success envelope (empty census is NOT an error) ---
        Do pResult.structuredContent.%Set("hours", tHours, "number")
        Do pResult.structuredContent.%Set("window_start", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tBoundaryOdbc))
        Do pResult.structuredContent.%Set("body_types", tBodyTypes)
        Do pResult.structuredContent.%Set("body_type_count", tBodyTypes.%Size(), "number")
        Do pResult.structuredContent.%Set("truncated", tOverflow, "boolean")
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Set pResult.content.%Get(0).text = "Found " _ tBodyTypes.%Size() _ " active body type(s) in the last " _ tHours _ " hour(s)" _ $Select(tOverflow:" (truncated at " _ ..#MAXBODYTYPES _ " highest-volume body classes)", 1:"") _ "."
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
