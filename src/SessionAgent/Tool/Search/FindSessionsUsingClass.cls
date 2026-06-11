/// <p>Search tool — find Ens sessions whose
/// <CLASS>Ens.MessageHeader</CLASS> rows reference a given class name
/// in any of the three class-name columns:
/// <code>SourceConfigName</code>, <code>TargetConfigName</code>, or
/// <code>MessageBodyClassName</code>. Enables operators to assess the
/// blast radius when a class needs repair or retirement.</p>
///
/// <p><b>Tool name:</b> <code>find_sessions_using_class</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>SQL injection defense (AC-2).</b> All four layers from
/// project rule §"SQL Injection Defense in ObjectScript" are present:</p>
/// <ol>
/// <li><b>Layer (a)</b> — schema <code>class_name</code> description warns
///   "Pass the class name only — do not include method names."</li>
/// <li><b>Layer (b)</b> — server-side <code>$Match</code> regex
///   <code>^[A-Za-z%][A-Za-z0-9%._]*$</code> blocks malformed input.</li>
/// <li><b>Layer (c)</b> — <code>class_name</code> is bound as a
///   parameterized <code>?</code> placeholder; never concatenated into
///   SQL text.</li>
/// <li><b>Layer (d)</b> — reviewer confirms all three implementation
///   layers in Review Findings.</li>
/// </ol>
///
/// <p><b>Strip-last-segment fallback (AC-8).</b> When the initial query
/// returns zero rows, the tool strips the last dot-delimited segment from
/// <code>class_name</code> and retries once. If the stripped name returns
/// rows the response includes <code>class_name_auto_corrected_from</code>.
/// If still zero rows the response includes <code>candidate_class_name</code>
/// (the stripped form) as a search hint.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md">tool-catalog-expansion-2026-05-09.md</a> TOOL-5.</li>
/// <li><a href="../../../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a> §"SQL Injection Defense in ObjectScript".</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS>.</li>
/// </ul>
Class SessionAgent.Tool.Search.FindSessionsUsingClass Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "find_sessions_using_class";

Parameter Description As %String = "Find Ens sessions that reference a given class name in SourceConfigName, TargetConfigName, or MessageBodyClassName within a configurable time window. Useful for blast-radius assessment before retiring or repairing a class.";

Parameter MutatesState As %Boolean = 0;

/// <p>Indexed lead columns for AR11 invariant: all three class-name
/// columns searched by this tool.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["SourceConfigName", "TargetConfigName", "MessageBodyClassName"]
}

/// <p>JSON Schema (AC-9 — schema includes anti-method-suffix warning in
/// <code>class_name</code> description; Layer (a) of SQL injection
/// defense).</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "class_name": {"type": "string", "description": "Full package-qualified class name to search for in Ens.MessageHeader columns (e.g. 'SessionAgent.Sample.BP.OrderRouter'). Pass the class name only — do not include method names. Searched against SourceConfigName, TargetConfigName, and/or MessageBodyClassName per match_field."},
            "match_field": {"type": "string", "description": "Which column(s) to search. 'any' (default) = all three; 'source_config' = SourceConfigName only; 'target_config' = TargetConfigName only; 'message_body' = MessageBodyClassName only.", "enum": ["any", "source_config", "target_config", "message_body"]},
            "time_window_hours": {"type": "integer", "description": "TimeCreated window in hours. Default 24, max 168.", "minimum": 1, "maximum": 168},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 20, max 100.", "minimum": 1, "maximum": 100}
        },
        "required": ["class_name"],
        "additionalProperties": false
    }
}

ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        ; --- Extract arguments ---
        Set tClassName = ""
        Set tMatchField = "any"
        Set tWindowHours = 0
        Set tLimit = 20
        If $IsObject($Get(pJsonArgs)) {
            Set tClassName = pJsonArgs.%Get("class_name")
            Set tMatchArg = pJsonArgs.%Get("match_field")
            If (tMatchArg'=$$$NULLOREF) && (tMatchArg'="") { Set tMatchField = tMatchArg }
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tClassName=$$$NULLOREF tClassName = ""

        ; Layer (b) — server-side $Match regex validation (AC-2, SQL injection defense)
        If tClassName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing class_name"}]}
            Quit
        }
        If '$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid class_name format — must be a valid ObjectScript class name (e.g. 'SessionAgent.Sample.BP.OrderRouter')"}]}
            Quit
        }

        ; Clamp limits (AC-5, AC-6)
        If (tLimit < 1) Set tLimit = 20
        If (tLimit > 100) Set tLimit = 100

        ; max 168h for this tool (AC-5)
        If tWindowHours > 168 {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"time_window_hours exceeds maximum allowed 168 for this tool"}]}
            Quit
        }

        ; --- Build column filter (AC-4) ---
        ; Layer (c) — class_name is always a ? placeholder, never concatenated
        If tMatchField = "source_config" {
            Set tColFilter = "%EXACT(mh.SourceConfigName) = ?"
            Set tMatchedVia = "source_config"
        } ElseIf tMatchField = "target_config" {
            Set tColFilter = "%EXACT(mh.TargetConfigName) = ?"
            Set tMatchedVia = "target_config"
        } ElseIf tMatchField = "message_body" {
            Set tColFilter = "%EXACT(mh.MessageBodyClassName) = ?"
            Set tMatchedVia = "message_body"
        } Else {
            Set tColFilter = "(%EXACT(mh.SourceConfigName) = ? OR %EXACT(mh.TargetConfigName) = ? OR %EXACT(mh.MessageBodyClassName) = ?)"
            Set tMatchedVia = "any"
        }

        ; --- Execute query (returns 0 or more sessions) ---
        Set tSessions = ""
        Set tCount = 0
        Set tAutoCorrectFrom = ""
        Set tCandidateClassName = ""

        Set tSCSub = ..RunQuery(tClassName, tColFilter, tMatchField, tWindowHours, tLimit, .tSessions, .tCount, .tMatchedVia)
        If $$$ISERR(tSCSub) {
            ; Story 14.0 review fix — classify the RunQuery failure: a
            ; runtime %Execute failure renders as the canonical
            ; render_strategy:"execute_error" envelope; validation/prepare
            ; failures keep the Story 11.2 "prepare_error" shape.
            Do ..ShapeRunQueryErrorEnvelope(pResult, tSCSub)
            Quit
        }

        ; --- Strip-last-segment fallback (AC-8) ---
        If tCount = 0 {
            ; Try stripping the last dot-delimited segment once
            Set tLastDot = $Length(tClassName, ".") - 1
            If tLastDot > 0 {
                Set tStripped = $Piece(tClassName, ".", 1, tLastDot)
                ; Validate the stripped form passes the regex too
                If $Match(tStripped, "^[A-Za-z%][A-Za-z0-9%._]*$") {
                    Set tSessions2 = ""
                    Set tCount2 = 0
                    Set tMatchedVia2 = tMatchedVia
                    Set tSCSub2 = ..RunQuery(tStripped, tColFilter, tMatchField, tWindowHours, tLimit, .tSessions2, .tCount2, .tMatchedVia2)
                    If $$$ISOK(tSCSub2) {
                        If tCount2 > 0 {
                            ; Use corrected results
                            Set tAutoCorrectFrom = tClassName
                            Set tClassName = tStripped
                            Set tSessions = tSessions2
                            Set tCount = tCount2
                            Set tMatchedVia = tMatchedVia2
                        } Else {
                            ; Still no results — surface candidate
                            Set tCandidateClassName = tStripped
                        }
                    } Else {
                        ; Story 14.0 review fix — a fallback-query failure
                        ; must surface as an error envelope, not as a
                        ; success-shaped "No sessions found" (the discarded
                        ; tSCSub2 was a NEW silent-masking path introduced
                        ; by the strip-last-segment retry).
                        Do ..ShapeRunQueryErrorEnvelope(pResult, tSCSub2)
                        Quit
                    }
                }
            }
        }

        ; --- Compute window used ---
        Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)

        ; --- Build response (AC-3, AC-7) ---
        Set tSC2 = pResult.structuredContent.%Set("class_name", tClassName)
        Set tSC2 = pResult.structuredContent.%Set("match_field", tMatchedVia)
        Set tSC2 = pResult.structuredContent.%Set("time_window_hours", tWindowUsed, "number")
        Set tSC2 = pResult.structuredContent.%Set("session_count", tCount, "number")
        Set tSC2 = pResult.structuredContent.%Set("sessions", tSessions)
        Set tSC2 = pResult.structuredContent.%Set("truncated", (tCount = tLimit), "boolean")
        Set tSC2 = pResult.structuredContent.%Set("render_strategy", "ok")

        If tAutoCorrectFrom '= "" {
            Set tSC2 = pResult.structuredContent.%Set("class_name_auto_corrected_from", tAutoCorrectFrom)
        }
        If tCandidateClassName '= "" {
            Set tSC2 = pResult.structuredContent.%Set("candidate_class_name", tCandidateClassName)
        }

        If tCount = 0 {
            Set pResult.content.%Get(0).text = "No sessions found referencing class '" _ tClassName _ "' in the last " _ tWindowUsed _ " hour(s)."
        } ElseIf tAutoCorrectFrom '= "" {
            Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) referencing class '" _ tClassName _ "' (auto-corrected from '" _ tAutoCorrectFrom _ "') in the last " _ tWindowUsed _ " hour(s) via " _ tMatchedVia _ "."
        } Else {
            Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) referencing class '" _ tClassName _ "' in the last " _ tWindowUsed _ " hour(s) via " _ tMatchedVia _ "."
        }

        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

/// <p>Story 14.0 review fix — classify a <method>RunQuery</method> error
/// <code>%Status</code> and shape the matching canonical envelope.
/// <method>RunQuery</method> has no <code>pResult</code> in scope, so its
/// adapted execute guard returns a <code>%Status</code> whose text carries
/// the marker <code>"SQL execute failed for find_sessions_using_class: "</code>.
/// When the marker is present, this method shapes the canonical
/// <code>render_strategy="execute_error"</code> envelope (mirroring
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnExecuteFailure</method>'s
/// mutation contract) so runtime execute failures are NOT mislabeled
/// <code>prepare_error</code> with contradictory "prepare failed: ...
/// execute failed" text. Every other RunQuery error (validation,
/// prepare) keeps the Story 11.2 prepare gate shape.</p>
ClassMethod ShapeRunQueryErrorEnvelope(pResult As %DynamicObject, pStatus As %Status)
{
    Set tFullText = $System.Status.GetErrorText(pStatus)
    Set tMarker = "SQL execute failed for find_sessions_using_class: "
    Set tIdx = $Find(tFullText, tMarker)
    If tIdx > 0 {
        ; Runtime %Execute failure — canonical execute_error shape. The
        ; tail after the marker is "SQLCODE <n>: <%Message>".
        Set tErrText = $Extract(tFullText, tIdx, *)
        Do pResult.%Set("isError", 1, "boolean")
        Do pResult.%Get("content").%Get(0).%Set("text", "Tool '" _ ..#ToolName _ "' SQL execute failed: " _ tErrText)
        Do pResult.structuredContent.%Set("render_strategy", "execute_error")
        Do pResult.structuredContent.%Set("error_text", tErrText)
        Quit
    }
    Do ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, pStatus, ..#ToolName)
    Quit
}

/// <p>Execute the bounded-WHERE query for <code>pClassName</code> against
/// the given column filter. Populates <var>pSessions</var> (%DynamicArray)
/// and <var>pCount</var>. Layer (c) of the SQL injection defense: the
/// <code>pClassName</code> value is always bound via <code>?</code>
/// placeholders — it is NEVER concatenated into the SQL text.</p>
ClassMethod RunQuery(pClassName As %String, pColFilter As %String, pMatchField As %String, pTimeWindowHours As %Integer, pLimit As %Integer, Output pSessions As %DynamicArray, Output pCount As %Integer, ByRef pMatchedVia As %String) As %Status
{
    Set pSessions = []
    Set pCount = 0
    Set tSC = $$$OK

    Set tParams = []
    Set tErr = ""
    Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(pTimeWindowHours, .tParams, .tErr, "mh", pColFilter)
    If $IsObject(tErr) && (tErr.%Size() > 0) {
        Quit $$$ERROR($$$GeneralError, tErr.%Get("message"))
    }

    ; Layer (c) — class_name bound as ? placeholder(s), never concatenated
    If pMatchField = "any" {
        Do tParams.%Push(pClassName)
        Do tParams.%Push(pClassName)
        Do tParams.%Push(pClassName)
    } Else {
        Do tParams.%Push(pClassName)
    }

    Set tSql = "SELECT DISTINCT TOP ? %EXACT(mh.SessionId) AS sid, MIN(mh.TimeCreated) AS first_seen, MAX(mh.TimeCreated) AS last_seen, COUNT(*) AS msg_count FROM Ens.MessageHeader mh WHERE " _ tFragment _ " GROUP BY mh.SessionId ORDER BY MAX(mh.TimeCreated) DESC"

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare(tSql)
    If $$$ISERR(tSCp) {
        Quit $$$ERROR($$$GeneralError, "SQL prepare failed for find_sessions_using_class: " _ $System.Status.GetErrorText(tSCp))
    }

    ; Variadic %Execute via multi-dim local-array apply.
    Kill tArgs
    Set tArgs(1) = pLimit
    Set tArgIdx = 1
    Set tBindIter = tParams.%GetIterator()
    While tBindIter.%GetNext(.tBindKey, .tBindVal) {
        Set tArgIdx = tArgIdx + 1
        Set tArgs(tArgIdx) = tBindVal
    }
    Set tArgs = tArgIdx
    Set tRs = tStmt.%Execute(tArgs...)
    ; Story 14.0 — execute-failure check ADAPTED to this helper's %Status
    ; error contract (no pResult in scope; the Invoke call-site converts
    ; the returned error %Status into the canonical error envelope). See
    ; Completion Notes (adapted-guard sites).
    If '$IsObject($Get(tRs)) || (tRs.%SQLCODE < 0) {
        If '$IsObject($Get(tRs)) {
            Quit $$$ERROR($$$GeneralError, "SQL execute failed for find_sessions_using_class: %Execute returned a non-object result")
        }
        Quit $$$ERROR($$$GeneralError, "SQL execute failed for find_sessions_using_class: SQLCODE " _ tRs.%SQLCODE _ ": " _ tRs.%Message)
    }

    While tRs.%Next() {
        ; Use positional %GetData() — %EXACT() in SELECT causes alias issues (Story 13.3 note)
        Set tEntry = {}
        Do tEntry.%Set("session_id", +tRs.%GetData(1), "number")
        Do tEntry.%Set("first_seen", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%GetData(2)))
        Do tEntry.%Set("last_seen", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%GetData(3)))
        Do tEntry.%Set("msg_count", +tRs.%GetData(4), "number")
        Do tEntry.%Set("matched_via", pMatchedVia)
        Do pSessions.%Push(tEntry)
        Set pCount = pCount + 1
    }

    Quit tSC
}

}
