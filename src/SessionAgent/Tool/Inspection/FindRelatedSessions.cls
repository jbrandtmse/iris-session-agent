/// <p>Inspection tool — enumerate Ens sessions that share a super-session
/// key with the given <code>session_id</code>, for cross-instance /
/// cross-BP trace. Read-only (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Tool name:</b> <code>find_related_sessions</code>.</p>
///
/// <p><b>Input:</b> <code>{session_id (required), limit?}</code>.
/// <code>limit</code> defaults to 100, minimum 1, maximum 1000.</p>
///
/// <p><b>Output (structuredContent).</b></p>
/// <ul>
/// <li>Happy path: <code>{session_id, super_session_key,
/// related_sessions: [{session_id, time_created, source_config_name,
/// target_config_name, message_count}, ...], related_count,
/// render_strategy:"related_sessions"}</code>.</li>
/// <li>No super-session: <code>{session_id, super_session_key:"",
/// related_sessions:[], related_count:0,
/// render_strategy:"no_super_session"}</code> + 1-line summary
/// "session N has no super-session entry — it stands alone (NOT an
/// error)." NO <code>isError:1</code> flag — this is the common case
/// for single-namespace installs without cross-instance routing.</li>
/// <li>Unexpected exception: <code>{render_strategy:"query_error",
/// error_text:"..."}</code> with <code>isError:1</code>.</li>
/// </ul>
///
/// <p><b>SQL discipline.</b> <CLASS>Ens.SuperSessionIndex</CLASS> has
/// columns <code>ID</code>, <code>MessageHeader</code> (Required FK to
/// <CLASS>Ens.MessageHeader</CLASS>), <code>SuperSession</code> — there
/// is NO <code>SessionId</code> column on the index itself (Task 0
/// empirical finding; the spec's column-name guess was wrong). Resolution
/// of <code>SessionId</code> goes through the JOIN
/// <code>Ens.SuperSessionIndex.MessageHeader = Ens.MessageHeader.ID</code>,
/// from which <code>Ens.MessageHeader.SessionId</code> is the operator-
/// facing identifier. <code>%EXACT()</code> wraps every <code>%String</code>
/// projection and predicate per project rule §"IRIS SQL Case
/// Sensitivity" (<code>SuperSession</code>, <code>SourceConfigName</code>,
/// <code>TargetConfigName</code>); plain comparison on
/// <code>SessionId</code> (%Integer) and <code>ID</code> (%BigInt).
/// Parameterized via <code>%SQL.Statement.%Prepare</code> +
/// <code>%Execute(?, ...)</code>, NEVER string concat.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.5</a> (line 1568) — AC source.</li>
/// <li><a href="../../../../irislib/Ens/SuperSessionIndex.cls">irislib/Ens/SuperSessionIndex.cls</a>
/// — verified column structure + FK cascade-on-delete to
/// <CLASS>Ens.MessageHeader</CLASS>.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.FindRelatedSessions Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "find_related_sessions";

Parameter Description As %String = "Find Ens sessions that share a super-session key with the given session — for cross-instance / cross-BP trace.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. <code>session_id</code> required;
/// <code>limit</code> optional (default 100, range [1, 1000]).
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id whose related sessions you want."},
            "limit": {"type": "integer", "description": "Max related sessions returned. Default 100.", "minimum": 1, "maximum": 1000}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Three SQL steps inlined per AC-3:</p>
/// <ol>
/// <li>Look up super-session key for <code>session_id</code> by JOINing
/// <CLASS>Ens.SuperSessionIndex</CLASS> through to
/// <CLASS>Ens.MessageHeader</CLASS> (the index has no SessionId column).
/// If no row found OR the super-session key is empty,
/// short-circuit to the <code>no_super_session</code> envelope —
/// NOT an error.</li>
/// <li>Find DISTINCT sibling SessionIds sharing that super-session key
/// (excluding the given session). Apply LIMIT.</li>
/// <li>For each sibling, run two small enrichment queries against
/// <CLASS>Ens.MessageHeader</CLASS>: TOP 1 ASC by TimeCreated for the
/// representative row + COUNT(*) for the message count.</li>
/// </ol>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"related_sessions":[]}}
    Try {
        Set tSessionId = ""
        Set tLimit = 100
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Clamp limit to [1, 1000] with default 100.
        If (tLimit < 1) Set tLimit = 100
        If (tLimit > 1000) Set tLimit = 1000

        ; --- Step 1: look up the super-session key for session_id.
        ; Ens.SuperSessionIndex has no SessionId column; it FK's to
        ; Ens.MessageHeader. Join through to discover the super-session
        ; for the input session. TOP 1 ASC by header ID — multiple headers
        ; per session may carry index rows but they all share the same
        ; super-session value (one super-session per session is the
        ; semantic; see irislib/Ens/SuperSessionIndex.cls comment).
        Set tSqlLookup = "SELECT TOP 1 %EXACT(ssi.SuperSession) AS super_session FROM Ens.SuperSessionIndex ssi JOIN Ens.MessageHeader mh ON ssi.MessageHeader = mh.ID WHERE mh.SessionId = ?"
        Set tStmtLookup = ##class(%SQL.Statement).%New()
        Set tSCp = tStmtLookup.%Prepare(tSqlLookup)
        Quit:$$$ISERR(tSCp)
        Set tRsLookup = tStmtLookup.%Execute(tSessionId)
        Set tSuperSession = ""
        If tRsLookup.%Next() {
            Set tSuperSession = tRsLookup.%Get("super_session")
        }

        ; No super-session row found OR empty key → no_super_session envelope.
        If (tSuperSession = "") {
            Do pResult.structuredContent.%Set("session_id", tSessionId)
            Do pResult.structuredContent.%Set("super_session_key", "")
            Do pResult.structuredContent.%Set("related_sessions", [])
            Do pResult.structuredContent.%Set("related_count", 0, "number")
            Do pResult.structuredContent.%Set("render_strategy", "no_super_session")
            Set pResult.content.%Get(0).text = "session " _ tSessionId _ " has no super-session entry — it stands alone (NOT an error)."
            Quit
        }

        ; --- Step 2: find sibling sessions sharing the super-session key.
        Set tSqlSiblings = "SELECT DISTINCT TOP ? mh.SessionId AS session_id FROM Ens.SuperSessionIndex ssi JOIN Ens.MessageHeader mh ON ssi.MessageHeader = mh.ID WHERE %EXACT(ssi.SuperSession) = ? AND mh.SessionId <> ? ORDER BY mh.SessionId ASC"
        Set tStmtSib = ##class(%SQL.Statement).%New()
        Set tSCs = tStmtSib.%Prepare(tSqlSiblings)
        Quit:$$$ISERR(tSCs)
        Set tRsSib = tStmtSib.%Execute(tLimit, tSuperSession, tSessionId)

        ; NOTE: $ListBuild() with no args creates a list of length 1
        ; containing one $$$NULL element — NOT an empty list. Use
        ; an empty string, which is a valid 0-length $List per IRIS docs,
        ; and append via concatenation.
        Set tSiblingIds = ""
        While tRsSib.%Next() {
            Set tSiblingIds = tSiblingIds _ $ListBuild(tRsSib.%Get("session_id"))
        }

        ; --- Step 3: enrich each sibling with one representative MessageHeader
        ; row (earliest TimeCreated ASC) + total message count.
        Set tEnrichRow = ##class(%SQL.Statement).%New()
        Set tSCer = tEnrichRow.%Prepare("SELECT TOP 1 %EXACT(SourceConfigName) AS src, %EXACT(TargetConfigName) AS tgt, TimeCreated AS tc FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY TimeCreated ASC, ID ASC")
        Quit:$$$ISERR(tSCer)
        Set tEnrichCount = ##class(%SQL.Statement).%New()
        Set tSCec = tEnrichCount.%Prepare("SELECT COUNT(*) AS cnt FROM Ens.MessageHeader WHERE SessionId = ?")
        Quit:$$$ISERR(tSCec)

        Set tRelated = []
        Set tRelatedCount = 0
        Set tListLen = $ListLength(tSiblingIds)
        For tIdx = 1:1:tListLen {
            Set tSibSessionId = $ListGet(tSiblingIds, tIdx)
            Set tEntry = {}
            Do tEntry.%Set("session_id", +tSibSessionId, "number")

            ; Earliest header — populates time_created, source, target.
            Set tRsEr = tEnrichRow.%Execute(tSibSessionId)
            If tRsEr.%Next() {
                Do tEntry.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRsEr.%Get("tc")))
                Do tEntry.%Set("source_config_name", tRsEr.%Get("src"))
                Do tEntry.%Set("target_config_name", tRsEr.%Get("tgt"))
            } Else {
                ; Defensive fallback — sibling SessionId came from the
                ; JOIN above, so its MessageHeader rows must exist; but
                ; if a concurrent purge removed them mid-query, emit
                ; empty placeholders rather than crashing.
                Do tEntry.%Set("time_created", "")
                Do tEntry.%Set("source_config_name", "")
                Do tEntry.%Set("target_config_name", "")
            }

            ; Message count.
            Set tRsEc = tEnrichCount.%Execute(tSibSessionId)
            Set tMsgCount = 0
            If tRsEc.%Next() {
                Set tMsgCount = +tRsEc.%Get("cnt")
            }
            Do tEntry.%Set("message_count", tMsgCount, "number")

            Do tRelated.%Push(tEntry)
            Set tRelatedCount = tRelatedCount + 1
        }

        Do pResult.structuredContent.%Set("session_id", tSessionId)
        Do pResult.structuredContent.%Set("super_session_key", tSuperSession)
        Do pResult.structuredContent.%Set("related_sessions", tRelated)
        Do pResult.structuredContent.%Set("related_count", tRelatedCount, "number")
        Do pResult.structuredContent.%Set("render_strategy", "related_sessions")

        Set pResult.content.%Get(0).text = tRelatedCount _ " related session(s) for session " _ tSessionId _ " (super-session key: " _ tSuperSession _ ")."
        Quit
    }
    Catch ex {
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(ex.DisplayString())}]}
        Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(ex.DisplayString())}
        Quit
    }
    Quit tSC
}

}
