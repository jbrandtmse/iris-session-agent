/// <p>Inspection tool — read the persistent BP instance row(s) for a given
/// Ens session id, optionally augmented with <CLASS>Ens.BP.Context</CLASS> /
/// <CLASS>Ens.BP.Thread</CLASS> state when the BP is a BPL state machine.
/// Second of three BP-introspection tools shipped by Story 4.4 (alongside
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS> and
/// <CLASS>SessionAgent.Tool.Inspection.ListBusinessProcessMethods</CLASS>).</p>
///
/// <p><b>Tool name:</b> <code>get_business_process_instance</code>.
/// Read-only (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{session_id (required)}</code>.</p>
///
/// <p><b>Backend reality (Task-0 probe finding, 2026-05-04 — Rule 8 fix-now).</b>
/// The story spec assumed BP runtime state lived in
/// <CLASS>Ens.BP.Context</CLASS> with columns like <code>%SessionId</code>,
/// <code>%BPState</code>, <code>%CurrentResponseId</code>,
/// <code>%AwaitingResponseId</code>. Empirical probe shows otherwise:</p>
/// <ul>
/// <li><CLASS>Ens.BP.Context</CLASS> exposes only <code>%Process</code>,
/// <code>%LastError</code>, <code>%LastFault</code>, <code>%ResponseHandlers</code>
/// — and is populated <b>only for BPL state-machine subclasses</b>
/// (<code>Ens.BusinessProcessBPL</code>). Non-BPL subclasses (those
/// extending <code>Ens.BusinessProcess</code> directly, like the sample
/// production's <CLASS>SessionAgent.Sample.BP.OrderRouter</CLASS>) leave
/// this table empty.</li>
/// <li><CLASS>Ens.BP.Thread</CLASS> stores BPL thread state
/// (<code>%NextState</code>, <code>%PendingResponses</code>,
/// <code>%PendingTimeout</code>, <code>%Status</code>, etc.). Same BPL-only
/// population.</li>
/// <li>The persistent BP instance state — what operators ACTUALLY want — is
/// in <CLASS>Ens.BusinessProcess</CLASS> itself: <code>%SessionId</code>
/// (indexed), <code>%ConfigName</code>, <code>%TimeCreated</code>,
/// <code>%TimeCompleted</code>, <code>%IsCompleted</code>,
/// <code>%StatusCode</code>, <code>%PrimaryRequestHeader</code>,
/// <code>%PrimaryResponseHeader</code>, <code>%RepliedStatus</code>,
/// <code>%responseId</code>, <code>%responseClassName</code>,
/// <code>%IsTerminated</code>, <code>%%CLASSNAME</code>.</li>
/// </ul>
///
/// <p>Implementation queries <CLASS>Ens.BusinessProcess</CLASS> first (works
/// for all BP shapes), then if a row is found and the BP is a BPL subclass
/// joins on <CLASS>Ens.BP.Context</CLASS> + <CLASS>Ens.BP.Thread</CLASS> via
/// the <code>%Process</code> foreign key for the BPL augmentation. Non-BPL
/// BPs return <code>has_bpl_context:false</code> with an empty
/// <code>context</code> / <code>thread</code> sub-objects.</p>
///
/// <p><b>Output (structuredContent):</b></p>
/// <ul>
/// <li><b>Has BP instance:</b> <code>{has_bp:true, session_id, bp_class,
/// instance_id, config_name, is_completed, is_terminated, time_created,
/// time_completed, primary_request_header, primary_response_header,
/// responded_status, has_bpl_context, context:{...}, thread:{...},
/// render_strategy:"ok"}</code>.</li>
/// <li><b>No BP instance:</b> <code>{has_bp:false, session_id,
/// render_strategy:"no_bp_instance"}</code> — straight-through messaging
/// (<code>BS → BO</code> without a BP) or already-purged BP.</li>
/// </ul>
///
/// <p><b>Multi-BP sessions.</b> A single Ens session can have multiple BP
/// instances (e.g., the sample production's <code>OrderRouter</code> calls
/// <code>OrderValidator</code> synchronously — both share the session).
/// The tool returns the first BP found in <code>%SessionId</code> order
/// plus a <code>bp_count</code> field naming how many total BPs were
/// touched in the session. (Operators wanting the second BP should
/// follow up via <code>get_message_headers</code> + body inspection.)</p>
///
/// <p><b>BP autopurge caveat.</b> <CLASS>Ens.BusinessProcess</CLASS> rows
/// are deleted by the BP framework when <code>%IsCompleted=1</code> as
/// part of the message-delivery cycle (see
/// <code>irislib/Ens/BusinessProcess.cls</code> §<code>Purge</code> +
/// <code>finishProcessing</code>). Sessions whose BPs have all completed
/// will return <code>has_bp:false</code>. Live BPs (mid-flight, awaiting
/// async responses, or BPL waiting in a state) DO persist.</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on string columns
/// (<code>%ConfigName</code>, <code>%%CLASSNAME</code>); plain comparison
/// on integer (<code>%SessionId</code>, <code>%IsCompleted</code>,
/// <code>%IsTerminated</code>). Parameterized <code>?</code>-binds.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.4</a> AC-4..6 — AC source.</li>
/// <li><a href="../../../../irislib/Ens/BusinessProcess.cls">irislib/Ens/BusinessProcess.cls</a> —
/// columns, <code>SessionId</code> index, storage at
/// <code>^Ens.BusinessProcessD</code>.</li>
/// <li><a href="../../../../irislib/Ens/BP/Context.cls">irislib/Ens/BP/Context.cls</a>,
/// <a href="../../../../irislib/Ens/BP/Thread.cls">Thread.cls</a> —
/// BPL-only runtime state.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetBusinessProcessInstance Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_business_process_instance";

Parameter Description As %String = "Read the persistent BP instance row(s) for an Ens session from Ens.BusinessProcess. For BPL-state-machine subclasses the result is augmented with Ens.BP.Context / Ens.BP.Thread state; non-BPL BPs return has_bpl_context=false.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Required: <code>session_id</code>.
/// <code>additionalProperties</code> false.</p>
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

/// <p>Query <CLASS>Ens.BusinessProcess</CLASS> for rows matching the
/// session id. If found, join on BPL Context+Thread tables (will be empty
/// for non-BPL BPs). If no BP rows, return <code>has_bp:false</code>.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tSessionId = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set:tSessionId=$$$NULLOREF tSessionId = ""
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Step 1 — query Ens.BusinessProcess for any rows in the session.
        Set tStmt = ##class(%SQL.Statement).%New()
        ; Note: %CLASSNAME (single % — SQL-projected pseudo-column) returns
        ; the row's class name. %%CLASSNAME (double %) is the storage-level
        ; key and is NOT addressable from SQL. Verified empirically Task 0.
        Set tSql = "SELECT TOP 10 ID AS instance_id, %CLASSNAME AS bp_class, %EXACT(""%ConfigName"") AS config_name, ""%TimeCreated"" AS time_created, ""%TimeCompleted"" AS time_completed, ""%IsCompleted"" AS is_completed, ""%IsTerminated"" AS is_terminated, ""%PrimaryRequestHeader"" AS primary_request_header, ""%PrimaryResponseHeader"" AS primary_response_header, ""%RepliedStatus"" AS replied_status FROM Ens.BusinessProcess WHERE ""%SessionId"" = ? ORDER BY ID"
        Set tSCprep = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCprep) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":($System.Status.GetErrorText(tSCprep))}]}
            Quit
        }
        Set tRs = tStmt.%Execute(tSessionId)

        Set tBpFound = 0
        Set tInstanceId = ""
        Set tBpClass = ""
        Set tConfigName = ""
        Set tTimeCreated = ""
        Set tTimeCompleted = ""
        Set tIsCompleted = 0
        Set tIsTerminated = 0
        Set tPrimaryReqHdr = ""
        Set tPrimaryRespHdr = ""
        Set tRepliedStatus = 0
        Set tBpCount = 0

        While tRs.%Next() {
            Set tBpCount = tBpCount + 1
            If 'tBpFound {
                Set tBpFound = 1
                Set tInstanceId = tRs.%Get("instance_id")
                Set tBpClass = tRs.%Get("bp_class")
                Set tConfigName = tRs.%Get("config_name")
                Set tTimeCreated = tRs.%Get("time_created")
                Set tTimeCompleted = tRs.%Get("time_completed")
                Set tIsCompleted = +tRs.%Get("is_completed")
                Set tIsTerminated = +tRs.%Get("is_terminated")
                Set tPrimaryReqHdr = tRs.%Get("primary_request_header")
                Set tPrimaryRespHdr = tRs.%Get("primary_response_header")
                Set tRepliedStatus = +tRs.%Get("replied_status")
            }
        }

        If 'tBpFound {
            Do pResult.structuredContent.%Set("has_bp", 0, "boolean")
            Do pResult.structuredContent.%Set("session_id", tSessionId)
            Do pResult.structuredContent.%Set("render_strategy", "no_bp_instance")
            Set pResult.content.%Get(0).text = "no BP instance for session " _ tSessionId _ " — message routing was straight-through (BS → BO without a BP), or all BP rows have been purged after completion."
            Quit
        }

        ; Step 2 — augment with BPL Context + Thread state when applicable.
        Set tHasBplContext = 0
        Set tCtxObj = {}
        Set tThreadObj = {}
        Try {
            ; Probe Context table for rows whose %Process points to this BP.
            Set tStmtCtx = ##class(%SQL.Statement).%New()
            Set tSCctxPrep = tStmtCtx.%Prepare("SELECT TOP 5 ID AS context_id, ""%LastError"" AS last_error, ""%LastFault"" AS last_fault FROM Ens_BP.Context WHERE ""%Process"" = ?")
            If $$$ISOK(tSCctxPrep) {
                Set tRsCtx = tStmtCtx.%Execute(tInstanceId)
                If tRsCtx.%Next() {
                    Set tHasBplContext = 1
                    Do tCtxObj.%Set("context_id", tRsCtx.%Get("context_id"))
                    Set tLastErrorRaw = tRsCtx.%Get("last_error")
                    Do tCtxObj.%Set("last_error_text", $Select(tLastErrorRaw="":"", 1:$System.Status.GetErrorText(tLastErrorRaw)))
                    Do tCtxObj.%Set("last_fault", tRsCtx.%Get("last_fault"))
                }
            }
        }
        Catch ctxEx {
            Set tHasBplContext = 0
        }

        Try {
            ; Probe Thread table for the BPL thread state.
            Set tStmtThr = ##class(%SQL.Statement).%New()
            Set tSCthrPrep = tStmtThr.%Prepare("SELECT TOP 5 ID AS thread_id, ""%NextState"" AS next_state, ""%Status"" AS run_status, ""%SyncTimedOut"" AS sync_timed_out, ""%PendingTimeout"" AS pending_timeout, ""%PendingAlarmHandle"" AS pending_alarm_handle, ""%SyncName"" AS sync_name FROM Ens_BP.Thread WHERE ""%Process"" = ?")
            If $$$ISOK(tSCthrPrep) {
                Set tRsThr = tStmtThr.%Execute(tInstanceId)
                If tRsThr.%Next() {
                    Set tHasBplContext = 1
                    Do tThreadObj.%Set("thread_id", tRsThr.%Get("thread_id"))
                    Do tThreadObj.%Set("next_state", tRsThr.%Get("next_state"))
                    Do tThreadObj.%Set("run_status", +tRsThr.%Get("run_status"), "number")
                    Do tThreadObj.%Set("sync_timed_out", +tRsThr.%Get("sync_timed_out"), "number")
                    Do tThreadObj.%Set("pending_timeout", tRsThr.%Get("pending_timeout"))
                    Do tThreadObj.%Set("pending_alarm_handle", tRsThr.%Get("pending_alarm_handle"))
                    Do tThreadObj.%Set("sync_name", tRsThr.%Get("sync_name"))
                }
            }
        }
        Catch thrEx {
            ; ignore — has_bpl_context stays as set by ctx step
        }

        ; Build the success envelope.
        Do pResult.structuredContent.%Set("has_bp", 1, "boolean")
        Do pResult.structuredContent.%Set("session_id", tSessionId)
        Do pResult.structuredContent.%Set("bp_class", tBpClass)
        Do pResult.structuredContent.%Set("instance_id", +tInstanceId, "number")
        Do pResult.structuredContent.%Set("bp_count", tBpCount, "number")
        Do pResult.structuredContent.%Set("config_name", tConfigName)
        Do pResult.structuredContent.%Set("is_completed", tIsCompleted, "boolean")
        Do pResult.structuredContent.%Set("is_terminated", tIsTerminated, "boolean")
        Do pResult.structuredContent.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tTimeCreated))
        Do pResult.structuredContent.%Set("time_completed", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tTimeCompleted))
        Do pResult.structuredContent.%Set("primary_request_header", $Select(tPrimaryReqHdr="":"", 1:+tPrimaryReqHdr), $Select(tPrimaryReqHdr="":"string", 1:"number"))
        Do pResult.structuredContent.%Set("primary_response_header", $Select(tPrimaryRespHdr="":"", 1:+tPrimaryRespHdr), $Select(tPrimaryRespHdr="":"string", 1:"number"))
        Do pResult.structuredContent.%Set("replied_status", tRepliedStatus, "number")
        Do pResult.structuredContent.%Set("has_bpl_context", tHasBplContext, "boolean")
        Do pResult.structuredContent.%Set("context", tCtxObj)
        Do pResult.structuredContent.%Set("thread", tThreadObj)
        Do pResult.structuredContent.%Set("render_strategy", "ok")

        Set tCompleteLabel = $Select(tIsCompleted: "completed", 1: "in-flight")
        Set tBplLabel = $Select(tHasBplContext: " (BPL state machine; thread has BPL state)", 1: "")
        Set tCountLabel = $Select(tBpCount > 1: " (" _ tBpCount _ " BP instances total in session)", 1: "")
        Set pResult.content.%Get(0).text = "BP instance " _ tInstanceId _ " of " _ tBpClass _ " for session " _ tSessionId _ " (" _ tCompleteLabel _ ", config=" _ tConfigName _ ")" _ tBplLabel _ tCountLabel
        Quit
    }
    Catch ex {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(ex.DisplayString())}]}
        Quit
    }
    Quit tSC
}

}
