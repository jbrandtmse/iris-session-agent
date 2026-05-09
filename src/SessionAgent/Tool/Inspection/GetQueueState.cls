/// <p>Inspection tool — reports the depth and oldest-message age of a named
/// Ensemble queue, helping operators diagnose stuck productions. Returns
/// <code>queue_depth</code>, <code>oldest_message_id</code>,
/// <code>oldest_message_age_seconds</code>, and an optional
/// <code>oldest_message_ids</code> array (up to 5 IDs).</p>
///
/// <p><b>Tool name:</b> <code>get_queue_state</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{config_item_name (required), include_oldest_messages (optional bool)}</code>.
/// <code>config_item_name</code> is an Ensemble config-item name
/// (e.g., <code>"MyBusinessOperation"</code>) — NOT a class name, so no
/// qualified-name stripping is applied.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{config_item_name, queue_depth, oldest_message_id,
/// oldest_message_age_seconds, oldest_message_ids, render_strategy}</code>.
/// <code>render_strategy</code> is always <code>"matched"</code>.
/// Absent or empty queue is NOT an error — all depth/ID fields return
/// zero-state (<code>queue_depth:0, oldest_message_id:"",
/// oldest_message_age_seconds:0, oldest_message_ids:[]</code>).</p>
///
/// <p><b>CRITICAL — Ens.Queue is NOT a SQL class.</b> Uses only the
/// ObjectScript API: <code>Ens.Queue.Exists(name)</code>,
/// <code>Ens.Queue.GetCount(name)</code>, and the
/// <code>Ens.Queue:EnumerateItem</code> named query via
/// <code>%ResultSet</code>. The <code>^Ens.Queue</code> global stores
/// queue state; there is no <code>FROM Ens.Queue</code> SQL table.</p>
///
/// <p><b>oldest_message_age_seconds</b> is computed from
/// <code>Ens.MessageHeader.TimeCreated</code> via
/// <code>$ZDateTimeH(TimeCreated, 3, 1)</code> + <code>$ZTimeStamp</code>
/// arithmetic (seconds = diff * 86400). Capped at 0 if negative.</p>
///
/// <p><b>No throws.</b> Outer Try/Catch around all steps; any unexpected
/// exception → <code>{isError:1, error_text:...}</code>. Exceptions
/// never escape <method>Invoke</method>.</p>
///
/// <p><b>AvgWaitSeconds dropped</b> — not stored in the queue global; not
/// included in this tool's response shape.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/13-4-get-queue-state-tool.md">
/// Story 13.4</a> — AC source.</li>
/// <li><a href="../../../../irislib/Ens/Queue.cls">irislib/Ens/Queue.cls</a>
/// — API definitions verified (Exists, GetCount, EnumerateItem).</li>
/// <li><a href="GetMessageDetail.cls">GetMessageDetail.cls</a>
/// — tool class pattern reference.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetQueueState Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_queue_state";

Parameter Description As %String = "Return the depth and oldest-message age of a named Ensemble queue — use this to diagnose stuck or backed-up productions by checking how many messages are waiting and how long the oldest one has been queued.";

Parameter MutatesState As %Boolean = 0;

/// <p>JSON Schema — required: <code>config_item_name</code>; optional:
/// <code>include_oldest_messages</code>. No additional properties.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "config_item_name": {
                "type": "string",
                "description": "Ensemble config item name (e.g. MyBusinessOperation) whose queue to inspect"
            },
            "include_oldest_messages": {
                "type": "boolean",
                "description": "When true, oldest_message_ids array is populated with up to 5 message IDs from the queue head. Default false."
            }
        },
        "required": ["config_item_name"],
        "additionalProperties": false
    }
}

/// <p>Read-only queue state readout. Extracts <code>queue_depth</code>,
/// <code>oldest_message_id</code>, <code>oldest_message_age_seconds</code>,
/// and optionally <code>oldest_message_ids</code> (up to 5). Absent queue
/// is never an error.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; ---- Pre-validation ----
        Set tName = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tName = pJsonArgs.%Get("config_item_name")
            Set:tName=$$$NULLOREF tName = ""
        }
        If tName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing config_item_name"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing config_item_name"}}
            Quit
        }

        ; ---- Read include_oldest_messages flag ----
        Set tIncludeIds = 0
        If $IsObject($Get(pJsonArgs)) {
            Set tFlag = pJsonArgs.%Get("include_oldest_messages")
            If (tFlag '= "") && (tFlag '= $$$NULLOREF) Set tIncludeIds = ''tFlag
        }

        ; ---- Check queue existence ----
        If '##class(Ens.Queue).Exists(tName) {
            ; Absent queue is not an error — return zero-state.
            Do pResult.structuredContent.%Set("config_item_name", tName)
            Do pResult.structuredContent.%Set("queue_depth", 0, "number")
            Do pResult.structuredContent.%Set("oldest_message_id", "")
            Do pResult.structuredContent.%Set("oldest_message_age_seconds", 0, "number")
            Do pResult.structuredContent.%Set("oldest_message_ids", [])
            Do pResult.structuredContent.%Set("render_strategy", "matched")
            Set pResult.content.%Get(0).text = "Queue '" _ tName _ "' does not exist or is empty (depth=0)."
            Quit
        }

        ; ---- Get queue depth ----
        Set tDepth = ##class(Ens.Queue).GetCount(tName)
        If tDepth = "" Set tDepth = 0

        ; ---- Enumerate oldest message IDs (up to 5) ----
        Set tOldestId = ""
        Set tOldestIds = []
        Set tAgeSeconds = 0

        Set tRS = ##class(%ResultSet).%New("Ens.Queue:EnumerateItem")
        Set tSCEnum = tRS.Execute(tName)
        ; Columns: 1=Priority, 2=Index, 3=MessageId
        Set tCount = 0
        While tRS.Next() && (tCount < 5) {
            Set tMsgId = tRS.GetData(3)
            If tCount = 0 Set tOldestId = tMsgId
            If tIncludeIds {
                Do tOldestIds.%Push(tMsgId)
            }
            Set tCount = tCount + 1
        }

        ; ---- Compute oldest_message_age_seconds ----
        If tOldestId '= "" {
            Set tHdr = ##class(Ens.MessageHeader).%OpenId(tOldestId)
            If $IsObject(tHdr) && (tHdr.TimeCreated '= "") {
                ; TimeCreated is ODBC format "YYYY-MM-DD HH:MM:SS.mmm"
                Set tCreatedH = $ZDateTimeH(tHdr.TimeCreated, 3, 1)
                Set tAgeSeconds = ($ZTimeStamp - tCreatedH) * 86400
                If tAgeSeconds < 0 Set tAgeSeconds = 0
            }
        }

        ; ---- Compose structuredContent ----
        Do pResult.structuredContent.%Set("config_item_name", tName)
        Do pResult.structuredContent.%Set("queue_depth", +tDepth, "number")
        Do pResult.structuredContent.%Set("oldest_message_id", tOldestId)
        Do pResult.structuredContent.%Set("oldest_message_age_seconds", +tAgeSeconds, "number")
        Do pResult.structuredContent.%Set("oldest_message_ids", tOldestIds)
        Do pResult.structuredContent.%Set("render_strategy", "matched")

        ; ---- Compose content[0].text ----
        Set tText = "Queue '" _ tName _ "': depth=" _ tDepth
        If tOldestId '= "" {
            Set tText = tText _ ", oldest_message_id=" _ tOldestId _ ", age=" _ $FN(tAgeSeconds, "", 1) _ "s"
        } Else {
            Set tText = tText _ ", no messages in queue."
        }
        Set pResult.content.%Get(0).text = tText
        Quit
    }
    Catch ex {
        ; No-throw guarantee — any escaping exception returns an isError envelope.
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"server_fault", "error_text":(tErrText)}}
    }
    Quit tSC
}

}
