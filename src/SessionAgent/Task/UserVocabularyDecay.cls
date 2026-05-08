/// <p>Scheduled sweep task that deletes low-confidence stale rows from
/// <code>SessionAgent.Search.UserVocabulary</code>. Implements PRD FR45 +
/// AR4 + NFR-R3 + NFR-SC4 for the Search Agent's vocabulary footprint:
/// rows whose confidence has decayed below the threshold AND that have not
/// been used in over the configured day window are permanently removed so
/// the per-portal-user vocabulary catalog does not accumulate dead aliases
/// indefinitely.</p>
///
/// <p><b>Schedule.</b> Weekly on Sunday at 04:00 UTC. The
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method> hook
/// (Story 1.5, line 112) detects this class on first install and creates a
/// matching <code>%SYS.Task</code> entry. Re-running
/// <method>SessionAgent.Installer.Install</method> is idempotent — the
/// scheduler's existence check on <code>%SYS.Task.Name</code> prevents
/// duplicate rows (NFR-R5). The Sunday-04:00 cadence is intentional — a
/// once-weekly run is sufficient to bound storage growth without burning
/// I/O during business hours, and the relatively quiet Sunday-morning
/// window minimizes operator-observable disruption.</p>
///
/// <p><b>Decay semantics.</b> The sweep deletes
/// <code>SessionAgent.Search.UserVocabulary</code> rows where
/// <code>Confidence &lt; <var>DecayConfidenceThreshold</var></code>
/// (default <code>0.2</code>) AND
/// <code>LastUsed &lt; (now - <var>DecayLastUsedDays</var>)</code>
/// (default <code>90</code>). Both conditions must be true — a low-confidence
/// alias that was used yesterday is preserved (the operator may still be
/// teaching it), and a high-confidence alias that has been dormant for a
/// year is preserved (the operator may return to that domain). The decay
/// targets the intersection: aliases that BOTH performed poorly AND have
/// been dormant.</p>
///
/// <p><b>Calibration constants</b> per architecture §"Calibration
/// constants". The two thresholds are
/// <code>Parameter</code>-level so the calibration is visible in the class
/// surface (<code>%Dictionary.ParameterDefinition</code>) without needing
/// to read the method body. Operator override is intentionally NOT
/// supported in v1 — the constants are a deliberate v1 design decision
/// (per Story 9.3 / Story 10.6 Carry-Forward); a future v2 may widen them
/// via a new <code>Config.Search</code> table. Until then, the constants
/// are the v1 contract.</p>
///
/// <p><b>Audit emission.</b> After the sweep completes, the task emits one
/// <code>$System.Security.Audit("SessionAgent","TaskRun","UserVocabularyDecay",&lt;status&gt;,&lt;json&gt;)</code>
/// event summarizing per-run counters: <code>rows_deleted</code>,
/// <code>threshold</code>, <code>last_used_days</code>,
/// <code>cutoff_iso</code>, <code>scan_time_ms</code>. The
/// <code>(SessionAgent, TaskRun, UserVocabularyDecay)</code> triple is
/// pre-registered by
/// <method>SessionAgent.Audit.Emit.EnsureEvents</method>.</p>
///
/// <p><b>Defensive-surface enumeration (Rule 8 / Story 10.0 AC-4).</b>
/// The DELETE statement's <code>SQLCODE</code> is checked
/// post-<code>%Execute</code>; values other than <code>0</code> (rows
/// deleted) or <code>100</code> (no matching rows) propagate as a
/// <code>$$$Status</code> error so the operator-visible
/// <code>%SYS.Task</code> history surface shows the failure.</p>
///
/// <p><b>Transaction safety.</b> Per project rule "Transaction Side
/// Effects", the audit emission runs OUTSIDE any TSTART/TCOMMIT block.
/// The DELETE itself runs without an explicit transaction — IRIS
/// auto-commits each parameterized DELETE individually.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 10.6</a> — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Calibration constants" — threshold provenance.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR45, NFR-R3, NFR-SC4.</li>
/// <li><a href="../Search/UserVocabulary.cls">SessionAgent.Search.UserVocabulary</a>
/// — schema; Confidence + LastUsed properties.</li>
/// <li><a href="../PurgeOrphanedChatHistory.cls">PurgeOrphanedChatHistory.cls</a>
/// — Story 7.2 sibling sweep (template for class structure).</li>
/// </ul>
Class SessionAgent.Task.UserVocabularyDecay Extends %SYS.Task.Definition
{

/// <p>User-visible task name shown in the IRIS Mgmt Portal Task Manager.
/// The <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>
/// hook uses the literal name <code>SessionAgent.UserVocabularyDecay</code>
/// in the <code>%SYS.Task.Name</code> column for dedup; this parameter is
/// what operators see when browsing the task definition itself.</p>
Parameter TaskName = "UserVocabularyDecay";

/// <p>Confidence threshold below which a vocabulary row is considered
/// decayed. Rows with <code>Confidence &lt; 0.2</code> AND a stale
/// <code>LastUsed</code> are deleted. Strict-less-than comparison: a row
/// at exactly <code>0.2</code> is preserved.</p>
///
/// <p>The threshold is calibrated against architecture §"Calibration
/// constants" — <code>0.2</code> represents
/// <code>SuccessCount / (SuccessCount + FailureCount + 1) &lt; 0.2</code>,
/// i.e., the success ratio fell below 20% with a smoothing-factor of 1.
/// Aliases that hit this threshold are unlikely to ever re-confirm.</p>
Parameter DecayConfidenceThreshold = 0.2;

/// <p>Days-since-LastUsed threshold. A row whose <code>LastUsed</code>
/// is older than <code>now - 90 days</code> (AND below the confidence
/// threshold) is decayed. Strict-less-than comparison.</p>
///
/// <p>The 90-day window aligns with the Search Agent's expected operator
/// activity cycle — an alias dormant for a full quarter has likely been
/// abandoned by the operator's workflow.</p>
Parameter DecayLastUsedDays = 90;

/// <p>Sweep entry point invoked by the IRIS Task Manager on the configured
/// schedule (Sunday 04:00 UTC per
/// <method>SessionAgent.Installer.ScheduleTaskIfClassExists</method>).
/// Computes the ISO-8601 UTC cutoff timestamp for
/// <code>now - <var>DecayLastUsedDays</var></code>, then DELETEs any
/// <code>SessionAgent.Search.UserVocabulary</code> row whose
/// <code>Confidence &lt; <var>DecayConfidenceThreshold</var></code> AND
/// <code>LastUsed &lt; cutoff</code>.</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on success
/// (including the all-zero "no decayed rows" case);
/// <code>$$$ERROR</code> on a fatal <code>SQLCODE &lt; 0</code> from the
/// DELETE or any trapped exception in the audit-emission step.</p>
///
/// <p>The audit event is emitted after the DELETE regardless of row
/// count, so operators always see one event per scheduled run with the
/// five counters (<code>rows_deleted</code>, <code>threshold</code>,
/// <code>last_used_days</code>, <code>cutoff_iso</code>,
/// <code>scan_time_ms</code>).</p>
Method OnTask() As %Status
{
    Set tSC = $$$OK
    Set tRowsDeleted = 0
    Set tCutoffIso = ""
    Set tStartH = $ZH
    Set tScanTimeMs = 0
    Try {
        ; ---- Phase 1: compute the ISO-8601 UTC cutoff timestamp.
        ; $ZTimeStamp is UTC (project rule §"Timestamp and Encoding
        ; Standards"). Subtract DecayLastUsedDays in horolog-day form
        ; before formatting.
        Set tCutoffH = $ZTimeStamp
        Set $Piece(tCutoffH, ",", 1) = $Piece(tCutoffH, ",", 1) - ..#DecayLastUsedDays
        Set tCutoffIso = $Translate($ZDateTime(tCutoffH, 3, 1), " ", "T") _ "Z"

        ; ---- Phase 2: parameterized DELETE on (Confidence, LastUsed).
        ; %EXACT() discipline on LastUsed for case-sensitive ISO-8601
        ; string comparison per project rule §"IRIS SQL Case Sensitivity".
        ; Confidence is a %Numeric — no %EXACT needed.
        ; The defensive surface (Rule 8 / Story 10.0 AC-4): SQLCODE is
        ; checked post-%Execute and values other than 0/100 propagate as
        ; $$$Status.
        Set tThreshold = ..#DecayConfidenceThreshold
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("DELETE FROM SessionAgent_Search.UserVocabulary WHERE Confidence < ? AND %EXACT(LastUsed) < ?")
        If $$$ISERR(tPrepSC) {
            Set tSC = tPrepSC
            Quit
        }
        Set tRS = tStmt.%Execute(tThreshold, tCutoffIso)
        If (tRS.%SQLCODE = 0) || (tRS.%SQLCODE = 100) {
            Set tRowsDeleted = tRS.%ROWCOUNT
        } Else {
            Set tSC = $$$ERROR($$$GeneralError, "UserVocabularyDecay: DELETE failed with SQLCODE=" _ tRS.%SQLCODE _ " (%msg=" _ $Get(%msg) _ ")")
            Do tRS.%Close()
            Quit
        }
        Do tRS.%Close()

        Set tScanTimeMs = ($ZH - tStartH) * 1000 \ 1
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        ; Argumentless quit per project rule §"QUIT Statement Restrictions
        ; in Try/Catch Blocks".
        Quit
    }

    ; ---- Audit event emission (always runs, success or fatal failure).
    Try {
        Set tData = {}
        Do tData.%Set("rows_deleted", tRowsDeleted)
        Do tData.%Set("threshold", ..#DecayConfidenceThreshold)
        Do tData.%Set("last_used_days", ..#DecayLastUsedDays)
        Do tData.%Set("cutoff_iso", tCutoffIso)
        Do tData.%Set("scan_time_ms", tScanTimeMs)
        Do $System.Security.Audit("SessionAgent", "TaskRun", "UserVocabularyDecay", tSC, tData.%ToJSON())
    }
    Catch exAudit {
        If $$$ISOK(tSC) {
            Set tSC = exAudit.AsStatus()
        }
    }

    Quit tSC
}

}
