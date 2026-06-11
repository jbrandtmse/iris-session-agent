/// <p>Inspection tool — returns <CLASS>Ens.Rule.Log</CLASS> rows for an
/// Ens session, optionally filtered by <code>rule_class</code>. Second
/// of the two new inspection tools shipped by Story 4.1.</p>
///
/// <p><b>Tool name:</b> <code>rule_log</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{session_id (required), rule_class?, limit?}</code>.
/// <code>limit</code> defaults to 100, minimum 1, maximum 1000.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{decisions:[{id, time_executed, rule_name, rule_set, component,
/// activity_name, return_value, triggering_message_id, reason, is_error,
/// error_msg}, ...], decision_count}</code>. Decisions are sorted ASC
/// by <code>TimeExecuted</code> then by <code>ID</code> for deterministic
/// ordering when multiple decisions share a sub-second timestamp
/// resolution. <code>component</code> mirrors
/// <CLASS>Ens.Rule.Log</CLASS>.<property>ConfigName</property> (the Ens
/// host config name); <code>triggering_message_id</code> mirrors
/// <property>CurrentHeaderId</property>.</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on all
/// <code>%String</code> projections (<code>RuleName</code>,
/// <code>RuleSet</code>, <code>ActivityName</code>, <code>Reason</code>,
/// <code>ReturnValue</code>, <code>ErrorMsg</code>,
/// <code>ConfigName</code>, <code>CurrentHeaderId</code>) per
/// <code>irislib/Ens/Rule/Log.cls</code>; plain comparison on
/// <code>SessionId</code> (%Integer per same line 22) and the
/// <code>IsError</code> %Boolean. Parameterized via
/// <code>%SQL.Statement.%Prepare</code> + <code>%Execute(?, ...)</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.1</a> (lines 1449–1476) — AC source.</li>
/// <li><a href="../../../../irislib/Ens/Rule/Log.cls">irislib/Ens/Rule/Log.cls</a>
/// — column definitions verified empirically + via Task 0 INFORMATION_SCHEMA
/// probe (15 columns: ID, ActivityName, ConfigName, CurrentHeaderId,
/// DebugId, EffectiveBegin, EffectiveEnd, ErrorMsg, IsError, Reason,
/// ReturnValue, RuleName, RuleSet, SessionId, TimeExecuted).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.RuleLog Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "rule_log";

Parameter Description As %String = "Read Ens.Rule.Log decisions for a session — return value, evaluated rule, component, triggering message.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. <code>session_id</code> required;
/// <code>rule_class</code> optional (full rule class name);
/// <code>limit</code> optional (default 100, range [1, 1000]).
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "session_id": {"type": "string", "description": "Ens session id"},
            "rule_class": {"type": "string", "description": "Optional full rule class name (e.g. 'Demo.MyRule') filter. Pass the class name only — do not include method names (e.g. pass 'Demo.MyRule', not 'Demo.MyRule.OnMatch')."},
            "limit": {"type": "integer", "description": "Max rows returned. Default 100.", "minimum": 1, "maximum": 1000}
        },
        "required": ["session_id"],
        "additionalProperties": false
    }
}

/// <p>Pre-validates <code>session_id</code> non-empty, clamps
/// <code>limit</code> to <code>[1, 1000]</code> with default 100.
/// Builds parameterized SQL with optional <code>RuleName = ?</code>
/// predicate. All input via <code>?</code>-binds.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"decisions":[]}}
    Try {
        Set tSessionId = ""
        Set tRuleClass = ""
        Set tLimit = 100
        If $IsObject($Get(pJsonArgs)) {
            Set tSessionId = pJsonArgs.%Get("session_id")
            Set tRuleClass = pJsonArgs.%Get("rule_class")
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tRuleClass=$$$NULLOREF tRuleClass = ""
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        If (tSessionId = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing session_id"}]}
            Quit
        }

        ; Clamp limit to [1, 1000] with default 100.
        If (tLimit < 1) Set tLimit = 100
        If (tLimit > 1000) Set tLimit = 1000

        ; Build SQL. RuleName predicate is conditional. Order by
        ; TimeExecuted ASC, ID ASC for deterministic chronological output.
        Set tSql = "SELECT TOP ? ID AS id, TimeExecuted AS time_executed, %EXACT(RuleName) AS rule_name, %EXACT(RuleSet) AS rule_set, %EXACT(ConfigName) AS component, %EXACT(ActivityName) AS activity_name, %EXACT(ReturnValue) AS return_value, %EXACT(CurrentHeaderId) AS triggering_message_id, %EXACT(Reason) AS reason, IsError AS is_error, %EXACT(ErrorMsg) AS error_msg FROM Ens_Rule.Log WHERE SessionId = ?"
        If tRuleClass '= "" {
            Set tSql = tSql _ " AND %EXACT(RuleName) = ?"
        }
        Set tSql = tSql _ " ORDER BY TimeExecuted ASC, ID ASC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare(tSql)
        ; Story 11.2 — centralized prepare-failure gate.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName) Quit

        ; Dispatch %Execute arity.
        If tRuleClass = "" {
            Set tRs = tStmt.%Execute(tLimit, tSessionId)
        } Else {
            Set tRs = tStmt.%Execute(tLimit, tSessionId, tRuleClass)
        }
        ; Story 14.0 — centralized execute-failure gate (cr-13-3).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRs, ..#ToolName) Quit

        Set tDecisions = []
        Set tCount = 0
        While tRs.%Next() {
            Set tDec = {}
            Do tDec.%Set("id", +tRs.%Get("id"), "number")
            ; Story 3.0 AC-2 — normalize to canonical ISO-8601 UTC Z.
            Do tDec.%Set("time_executed", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("time_executed")))
            Do tDec.%Set("rule_name", tRs.%Get("rule_name"))
            Do tDec.%Set("rule_set", tRs.%Get("rule_set"))
            Do tDec.%Set("component", tRs.%Get("component"))
            Do tDec.%Set("activity_name", tRs.%Get("activity_name"))
            Do tDec.%Set("return_value", tRs.%Get("return_value"))
            Do tDec.%Set("triggering_message_id", tRs.%Get("triggering_message_id"))
            Do tDec.%Set("reason", tRs.%Get("reason"))
            Do tDec.%Set("is_error", +tRs.%Get("is_error"), "boolean")
            Do tDec.%Set("error_msg", tRs.%Get("error_msg"))
            Do tDecisions.%Push(tDec)
            Set tCount = tCount + 1
        }

        Do pResult.structuredContent.%Set("decisions", tDecisions)
        Do pResult.structuredContent.%Set("decision_count", tCount, "number")

        Set pResult.content.%Get(0).text = tCount _ " rule decision(s) for session " _ tSessionId _ "."
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
