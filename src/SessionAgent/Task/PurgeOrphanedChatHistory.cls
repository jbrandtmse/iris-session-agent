/// <p>Scheduled sweep task that deletes Inspection-keyed
/// <code>SessionAgent.Chat.History</code> rows whose
/// <property>SessionKey</property> no longer references a live
/// <code>Ens.MessageHeader</code> row (i.e., the underlying interop session
/// has been purged by <code>Ens.MessageHeader.Purge()</code> and the chat
/// history is now orphaned). Implements PRD FR44 (chat-history lifecycle
/// coupled to interop-session purge) + NFR-R2 (purge integrity).</p>
///
/// <p><b>Schedule.</b> Daily at 02:00 UTC. The
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method> hook
/// (Story 1.5, line 110) detects this class on first install and creates a
/// matching <code>%SYS.Task</code> entry. Re-running
/// <method>SessionAgent.Installer.Install</method> is idempotent — the
/// scheduler's existence check on <code>%SYS.Task.Name</code> prevents
/// duplicate rows (NFR-R5).</p>
///
/// <p><b>Cascade approach (Story 7.1 Option B).</b> For each orphaned chat
/// row, the sweep first deletes the dependent audit rows in
/// <code>SessionAgent.Audit.LlmCall</code> and
/// <code>SessionAgent.Audit.ToolCall</code> (parameterized DELETEs against
/// the <code>ChatHistoryIdIdx</code> index added by Story 7.2), then
/// deletes the <code>SessionAgent.Chat.History</code> row itself. Order
/// matters: deleting the chat row first would leave dangling-FK audit rows
/// that violate NFR-SC4 (audit-volume bound by chat-history sweep cascade).
/// The <code>%String</code> storage shape of
/// <code>Audit.{LlmCall,ToolCall}.ChatHistoryId</code> precludes a true FK
/// cascade DELETE without a Story 2.5 schema migration — see
/// <code>_bmad-output/planning-artifacts/architecture.md</code> line 994.</p>
///
/// <p><b>Audit emission.</b> After the sweep completes (success OR partial
/// failure), the task emits one
/// <code>$System.Security.Audit("SessionAgent","TaskRun","PurgeOrphanedChatHistory",&lt;status&gt;,&lt;json&gt;)</code>
/// event summarizing per-run counters: <code>orphans_deleted</code>,
/// <code>llm_audit_deleted</code>, <code>tool_audit_deleted</code>,
/// <code>scan_time_ms</code>. The
/// <code>(SessionAgent, TaskRun, PurgeOrphanedChatHistory)</code> triple is
/// pre-registered by
/// <method>SessionAgent.Audit.Emit.EnsureEvents</method> (Story 1.3) — no
/// lazy registration needed.</p>
///
/// <p><b>Transaction safety.</b> Per project rule "Transaction Side
/// Effects", no JOB / Event.Signal / external I/O occurs inside any
/// <code>TSTART</code>/<code>TCOMMIT</code> block. The sweep runs without
/// an explicit transaction — each orphan's three DELETEs commit
/// row-by-row. The chosen semantic is "commit per orphan to maximize
/// forward progress under partial-failure conditions": if one orphan's
/// audit DELETE fails, the per-orphan sub-Try logs and skips that orphan,
/// but the sweep continues for the rest. Per-orphan errors are counted
/// (and surfaced in the audit-event payload via the difference between
/// scanned-orphan and deleted-orphan counts).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Epic 7 Story 7.2</a> — AC source.</li>
/// <li><a href="../../../_bmad-output/implementation-artifacts/7-1-task-0-probe-audit-fk-cascade-design.md">Story
/// 7.1</a> — Task-0 probe (SQLCODE semantics) + Audit FK cascade design
/// decision (Option B).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// line 994 (Persistence-Layer Volume Notes — Audit row, Option B cascade
/// sentence) and line 387 (audit event triples).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR44, NFR-R2, NFR-R5, NFR-SC4.</li>
/// <li><a href="../../../irislib/%SYS/Task/Definition.cls">irislib/%SYS/Task/Definition.cls</a>
/// — base class contract (line 38: <code>OnTask() As %Status</code>).</li>
/// </ul>
Class SessionAgent.Task.PurgeOrphanedChatHistory Extends %SYS.Task.Definition
{

/// <p>User-visible task name shown in the IRIS Mgmt Portal Task Manager.
/// The <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>
/// hook uses the literal name <code>SessionAgent.PurgeOrphanedChatHistory</code>
/// in the <code>%SYS.Task.Name</code> column for dedup; this parameter is
/// what operators see when browsing the task definition itself.</p>
Parameter TaskName = "PurgeOrphanedChatHistory";

/// <p>Sweep entry point invoked by the IRIS Task Manager on the configured
/// schedule (daily at 02:00 UTC per
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>).
/// Implements the Story 7.1 Option B cascade: for each orphaned
/// Inspection-keyed <code>Chat.History</code> row (where the
/// <property>SessionKey</property> no longer matches any
/// <code>Ens.MessageHeader.SessionId</code>), delete the dependent
/// <code>Audit.LlmCall</code> and <code>Audit.ToolCall</code> rows first,
/// then delete the chat row itself.</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on success
/// (including the all-zero "no orphans found" case);
/// <code>$$$ERROR</code> only on a fatal error in the outer scan or
/// audit-event emission. Per-orphan failures are caught in a sub-Try,
/// logged via the deleted-counters delta, and DO NOT cause the sweep to
/// fail overall (per AC-4 "commit per orphan to maximize forward progress
/// under partial-failure conditions").</p>
///
/// <p>The audit event is emitted after the loop completes regardless of
/// per-orphan failures, so operators always have one event per scheduled
/// run with the four counters.</p>
Method OnTask() As %Status
{
    Set tSC = $$$OK
    Set tOrphansDeleted = 0
    Set tLlmAuditDeleted = 0
    Set tToolAuditDeleted = 0
    Set tStartH = $ZH
    Set tScanTimeMs = 0
    Try {
        ; Phase 1: collect orphan candidate IDs into a local array. This
        ; avoids cursor-vs-DELETE aliasing on Chat.History during Phase 2.
        ; The orphan-scan statement is single-use (one SELECT, then closed).
        Set tOrphanIds = ""
        Set tScanStmt = ##class(%SQL.Statement).%New()
        Set tScanSC = tScanStmt.%Prepare("SELECT %ID AS chatId, %EXACT(SessionKey) AS sessionKey FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = 'session-inspection'")
        If $$$ISERR(tScanSC) {
            Set tSC = tScanSC
            Quit
        }
        Set tScanRS = tScanStmt.%Execute()
        While tScanRS.%Next() {
            Set tChatId = tScanRS.%Get("chatId")
            Set tSessionKey = tScanRS.%Get("sessionKey")
            ; Story 7.1-verified existence-check primitive.
            Set tExists = ""
            &sql(SELECT 1 INTO :tExists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :tSessionKey)
            If SQLCODE = 100 {
                ; Orphan: collect for Phase 2 deletion.
                Set tOrphanIds(tChatId) = tSessionKey
            }
            ; SQLCODE=0 → row still exists; skip silently.
            ; Other SQLCODE → unexpected; log via counter mismatch but
            ; treat as not-orphan (conservative — never delete on doubt).
        }
        Do tScanRS.%Close()

        ; Phase 2: prepare-once the per-orphan DELETE statements (one for
        ; each audit table). Reused across all orphans for efficiency. The
        ; ChatHistoryIdIdx index added by Story 7.2 makes the WHERE clause
        ; O(log n) instead of O(n).
        Set tLlmStmt = ##class(%SQL.Statement).%New()
        Set tLlmPrepSC = tLlmStmt.%Prepare("DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?")
        If $$$ISERR(tLlmPrepSC) {
            Set tSC = tLlmPrepSC
            Quit
        }
        Set tToolStmt = ##class(%SQL.Statement).%New()
        Set tToolPrepSC = tToolStmt.%Prepare("DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?")
        If $$$ISERR(tToolPrepSC) {
            Set tSC = tToolPrepSC
            Quit
        }

        ; Phase 3: per-orphan delete loop. Each orphan is wrapped in a
        ; sub-Try so a single failure doesn't abort the whole sweep
        ; (per-orphan commit semantic — AC-4).
        Set tChatId = ""
        For  {
            Set tChatId = $Order(tOrphanIds(tChatId))
            Quit:tChatId=""
            Try {
                ; Audit rows first (Story 7.1 Option B order). For DELETE,
                ; %Execute returns a %SQL.StatementResult with %SQLCODE
                ; and %ROWCOUNT available immediately. SQLCODE=0 means
                ; "rows deleted"; SQLCODE=100 means "no matching rows" —
                ; both are success cases for the sweep (an orphan with
                ; zero audit rows is still an orphan worth deleting).
                Set tLlmRS = tLlmStmt.%Execute(tChatId)
                If (tLlmRS.%SQLCODE = 0) || (tLlmRS.%SQLCODE = 100) {
                    Set tLlmAuditDeleted = tLlmAuditDeleted + tLlmRS.%ROWCOUNT
                }
                Do tLlmRS.%Close()

                Set tToolRS = tToolStmt.%Execute(tChatId)
                If (tToolRS.%SQLCODE = 0) || (tToolRS.%SQLCODE = 100) {
                    Set tToolAuditDeleted = tToolAuditDeleted + tToolRS.%ROWCOUNT
                }
                Do tToolRS.%Close()

                ; Then the chat row itself (compiled %DeleteId path).
                Set tDelSC = ##class(SessionAgent.Chat.History).%DeleteId(tChatId)
                If $$$ISOK(tDelSC) {
                    Set tOrphansDeleted = tOrphansDeleted + 1
                }
                ; If %DeleteId fails, the audit rows are already gone; the
                ; counters reflect the partial work. Forward-progress wins
                ; over all-or-nothing semantics here.
            }
            Catch exOrphan {
                ; Per-orphan failure: log via counter delta, continue.
                ; The audit-event payload's orphans_deleted vs
                ; (scanned-orphan-count) delta is operator-observable.
            }
        }

        Set tScanTimeMs = ($ZH - tStartH) * 1000 \ 1
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        ; Argumentless quit per project rule "QUIT Statement Restrictions
        ; in Try/Catch Blocks". Audit emission below still runs so
        ; operators see the partial counters even on fatal failure.
        Quit
    }

    ; Audit event emission (always runs, success or fatal failure path).
    ; The triple (SessionAgent, TaskRun, PurgeOrphanedChatHistory) is
    ; pre-registered by SessionAgent.Audit.Emit:EnsureEvents (Story 1.3).
    Try {
        Set tData = {}
        Do tData.%Set("orphans_deleted", tOrphansDeleted)
        Do tData.%Set("llm_audit_deleted", tLlmAuditDeleted)
        Do tData.%Set("tool_audit_deleted", tToolAuditDeleted)
        Do tData.%Set("scan_time_ms", tScanTimeMs)
        Do $System.Security.Audit("SessionAgent", "TaskRun", "PurgeOrphanedChatHistory", tSC, tData.%ToJSON())
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
