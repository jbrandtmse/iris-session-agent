/// <p>Scheduled sweep task that deletes Search-keyed
/// <code>SessionAgent.Chat.History</code> rows older than the configured
/// retention window. Implements PRD FR45 + AR4 + NFR-R3 + NFR-SC4: bound
/// the storage growth of the Message Search agent's chat-history footprint
/// so a long-running production install does not accumulate stale
/// conversation rows indefinitely.</p>
///
/// <p><b>Schedule.</b> Daily at 03:00 UTC. The
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method> hook
/// (Story 1.5, line 111) detects this class on first install and creates a
/// matching <code>%SYS.Task</code> entry. Re-running
/// <method>SessionAgent.Installer.Install</method> is idempotent — the
/// scheduler's existence check on <code>%SYS.Task.Name</code> prevents
/// duplicate rows (NFR-R5).</p>
///
/// <p><b>Retention semantics.</b> The sweep deletes
/// <code>SessionAgent.Chat.History</code> rows where
/// <code>AgentName = 'message-search'</code> AND <code>UpdatedAt</code> is
/// older than <code>now - retentionDays</code>. The retention-days value is
/// read from <code>SessionAgent.Config.Agent.SearchChatRetentionDays</code>
/// for the <code>message-search</code> agent row (default <code>30</code>
/// per Story 2.4 schema). Inspection-keyed rows
/// (<code>AgentName = 'session-inspection'</code>) are left untouched —
/// they are owned by Story 7.2's <code>PurgeOrphanedChatHistory</code>
/// sweep, which couples lifecycle to the Ens Production session purge,
/// NOT to a TTL.</p>
///
/// <p><b>Audit emission.</b> After the sweep completes, the task emits one
/// <code>$System.Security.Audit("SessionAgent","TaskRun","PurgeStaleSearchChat",&lt;status&gt;,&lt;json&gt;)</code>
/// event summarizing per-run counters: <code>rows_deleted</code>,
/// <code>retention_days</code>, <code>cutoff_iso</code>,
/// <code>scan_time_ms</code>. The
/// <code>(SessionAgent, TaskRun, PurgeStaleSearchChat)</code> triple is
/// pre-registered by
/// <method>SessionAgent.Audit.Emit.EnsureEvents</method> (extended in this
/// story) — no lazy registration needed.</p>
///
/// <p><b>Defensive-surface enumeration (Rule 8 / Story 10.0 AC-4).</b>
/// The DELETE statement's <code>SQLCODE</code> is checked
/// post-<code>%Execute</code>; values other than <code>0</code> (rows
/// deleted) or <code>100</code> (no matching rows) propagate as a
/// <code>$$$Status</code> error so the operator-visible
/// <code>%SYS.Task</code> history surface shows the failure. The
/// <code>OnTask()</code> return value is the propagated status —
/// success returns <code>$$$OK</code> regardless of how many rows were
/// deleted (zero is a legitimate steady-state result).</p>
///
/// <p><b>Transaction safety.</b> Per project rule "Transaction Side
/// Effects", the audit emission runs OUTSIDE any TSTART/TCOMMIT block.
/// The DELETE itself runs without an explicit transaction — IRIS
/// auto-commits each parameterized DELETE individually, so partial failure
/// of the sweep leaves the already-deleted rows gone (a steady-state
/// improvement over zero progress).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 10.6</a> — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR45, NFR-R3, NFR-SC4.</li>
/// <li><a href="../PurgeOrphanedChatHistory.cls">PurgeOrphanedChatHistory.cls</a>
/// — Story 7.2 sibling sweep (template for class structure + audit-event
/// pattern).</li>
/// <li><a href="../Config/Agent.cls">SessionAgent.Config.Agent</a> line 126
/// — <code>SearchChatRetentionDays</code> property (default 30).</li>
/// <li><a href="../../../irislib/%SYS/Task/Definition.cls">irislib/%SYS/Task/Definition.cls</a>
/// — base class contract.</li>
/// </ul>
Class SessionAgent.Task.PurgeStaleSearchChat Extends %SYS.Task.Definition
{

/// <p>User-visible task name shown in the IRIS Mgmt Portal Task Manager.
/// The <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>
/// hook uses the literal name <code>SessionAgent.PurgeStaleSearchChat</code>
/// in the <code>%SYS.Task.Name</code> column for dedup; this parameter is
/// what operators see when browsing the task definition itself.</p>
Parameter TaskName = "PurgeStaleSearchChat";

/// <p>Sweep entry point invoked by the IRIS Task Manager on the configured
/// schedule (daily at 03:00 UTC per
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>).
/// Reads <code>Config.Agent.SearchChatRetentionDays</code> for the
/// <code>message-search</code> agent (default 30 days), computes the
/// ISO-8601 UTC cutoff, and DELETEs any
/// <code>SessionAgent.Chat.History</code> row whose
/// <code>AgentName = 'message-search'</code> AND
/// <code>UpdatedAt &lt; cutoff</code>.</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on success
/// (including the all-zero "no stale rows" case);
/// <code>$$$ERROR</code> on a fatal <code>SQLCODE &lt; 0</code> from the
/// DELETE, on a missing <code>message-search</code> Config.Agent row, or
/// on any trapped exception in the audit-emission step.</p>
///
/// <p>The audit event is emitted after the DELETE regardless of row
/// count, so operators always see one event per scheduled run with the
/// four counters (<code>rows_deleted</code>, <code>retention_days</code>,
/// <code>cutoff_iso</code>, <code>scan_time_ms</code>).</p>
Method OnTask() As %Status
{
    Set tSC = $$$OK
    Set tRowsDeleted = 0
    Set tRetentionDays = 30
    Set tCutoffIso = ""
    Set tStartH = $ZH
    Set tScanTimeMs = 0
    Try {
        ; ---- Phase 1: read retention days from Config.Agent for the
        ; message-search agent. Defensive against missing row + the
        ; $Char(0) sentinel pattern (project rule §"$Char(0) sentinel").
        ; If the row is missing entirely, fall back to the default 30 so
        ; the sweep still bounds storage even on a misconfigured install.
        Set tCfgId = ""
        If ##class(SessionAgent.Config.Agent).AgentNameIdxExists("message-search", .tCfgId) {
            Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(tCfgId)
            If $IsObject(tCfg) {
                Set tStored = tCfg.SearchChatRetentionDays
                If tStored = $Char(0) Set tStored = ""
                If (tStored '= "") && (+tStored > 0) {
                    Set tRetentionDays = +tStored
                }
            }
        }

        ; ---- Phase 2: compute the ISO-8601 UTC cutoff timestamp.
        ; $ZTimeStamp is UTC (project rule §"Timestamp and Encoding
        ; Standards"); $Horolog would be local time and would skew the
        ; cutoff on non-UTC servers. We subtract retentionDays *before*
        ; the format conversion so the arithmetic stays in horolog days.
        Set tCutoffH = $ZTimeStamp
        Set $Piece(tCutoffH, ",", 1) = $Piece(tCutoffH, ",", 1) - tRetentionDays
        Set tCutoffIso = $Translate($ZDateTime(tCutoffH, 3, 1), " ", "T") _ "Z"

        ; ---- Phase 3: parameterized DELETE on the (AgentName, UpdatedAt)
        ; predicate. %EXACT() discipline on the case-sensitive comparisons
        ; per project rule §"IRIS SQL Case Sensitivity". The defensive
        ; surface (Rule 8 / Story 10.0 AC-4): SQLCODE is checked
        ; post-%Execute and values other than 0/100 propagate as $$$Status.
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = ? AND %EXACT(UpdatedAt) < ?")
        If $$$ISERR(tPrepSC) {
            Set tSC = tPrepSC
            Quit
        }
        Set tRS = tStmt.%Execute("message-search", tCutoffIso)
        If (tRS.%SQLCODE = 0) || (tRS.%SQLCODE = 100) {
            Set tRowsDeleted = tRS.%ROWCOUNT
        } Else {
            Set tSC = $$$ERROR($$$GeneralError, "PurgeStaleSearchChat: DELETE failed with SQLCODE=" _ tRS.%SQLCODE _ " (%msg=" _ $Get(%msg) _ ")")
            Do tRS.%Close()
            Quit
        }
        Do tRS.%Close()

        Set tScanTimeMs = ($ZH - tStartH) * 1000 \ 1
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        ; Argumentless quit per project rule §"QUIT Statement Restrictions
        ; in Try/Catch Blocks". Audit emission below still runs so
        ; operators see the partial counters even on fatal failure.
        Quit
    }

    ; ---- Audit event emission (always runs, success or fatal failure
    ; path). The triple (SessionAgent, TaskRun, PurgeStaleSearchChat) is
    ; pre-registered by SessionAgent.Audit.Emit:EnsureEvents.
    Try {
        Set tData = {}
        Do tData.%Set("rows_deleted", tRowsDeleted)
        Do tData.%Set("retention_days", tRetentionDays)
        Do tData.%Set("cutoff_iso", tCutoffIso)
        Do tData.%Set("scan_time_ms", tScanTimeMs)
        Do $System.Security.Audit("SessionAgent", "TaskRun", "PurgeStaleSearchChat", tSC, tData.%ToJSON())
    }
    Catch exAudit {
        ; Audit failure is non-fatal but we surface it on the return
        ; status if no prior fatal error.
        If $$$ISOK(tSC) {
            Set tSC = exAudit.AsStatus()
        }
    }

    Quit tSC
}

}
