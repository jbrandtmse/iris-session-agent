/// <p>Inspection tool — one-shot single-message readout that bundles
/// an <CLASS>Ens.MessageHeader</CLASS> row + a body summary (via the
/// <CLASS>SessionAgent.Tool.Inspection.GetMessageBody</CLASS> dispatch
/// ladder) + linked <CLASS>Ens.Rule.Log</CLASS> decisions filtered by
/// <code>CurrentHeaderId = ?</code>. Composes Stories 4.1 (RuleLog) +
/// 4.2 (GetMessageBody) into a single tool-call so the agent answers
/// "tell me everything about message N" in one round-trip rather than
/// dispatching three separate tools.</p>
///
/// <p><b>Tool name:</b> <code>get_message_detail</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{message_id (required)}</code>. No optional
/// inputs in v1 — the tool is a one-shot readout.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{message_id, header:{id, source_config_name, target_config_name,
/// status, time_created, is_error, session_id, body_class, body_id},
/// body_summary, body_repr, body_render_strategy, body_truncated,
/// body_class, body_id, rule_decisions:[{id, rule_name, component,
/// return_value, time_executed, reason}, ...], rule_decision_count}</code>.
/// On a missing header (no <code>Ens.MessageHeader</code> row for the
/// given id), <code>render_strategy="header_not_found"</code>, the
/// <code>header</code> object is empty <code>{}</code>, and
/// <code>rule_decisions</code> is <code>[]</code>.</p>
///
/// <p><b>Body-rendering reuse strategy.</b> Story 4.3 calls
/// <code>##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke()</code>
/// directly with <code>format:"summary"</code> and folds the resulting
/// <code>structuredContent</code> fields (<code>body_class, body_id,
/// render_strategy, body_repr, truncated</code>) into its own envelope
/// under a <code>body_*</code> prefix. The dispatch ladder is NOT
/// extracted to a shared helper — that's deferred to Epic 8 Story 8.6
/// per architecture G2 if cross-package reuse materializes.</p>
///
/// <p><b>Rule-decisions column mapping (Task 0 finding, Rule 8 fix-now).</b>
/// The spec mentioned <code>TriggeringMessageHeader</code> but the
/// <CLASS>Ens.Rule.Log</CLASS> column is <code>CurrentHeaderId</code>
/// (per <code>irislib/Ens/Rule/Log.cls</code> line 62). There is no
/// <code>Component</code> column either; the closest analog is
/// <code>ConfigName</code> (line 57 — "Configured name of the InterSystems
/// IRIS host from which the rule was logged"). This matches Story 4.1's
/// <CLASS>SessionAgent.Tool.Inspection.RuleLog</CLASS> mapping
/// (<code>%EXACT(ConfigName) AS component</code>,
/// <code>%EXACT(CurrentHeaderId) AS triggering_message_id</code>).</p>
///
/// <p><b>No throws.</b> Outer Try/Catch around all three steps; any
/// unexpected exception → <code>{render_strategy:"composition_error",
/// error_text:...}</code> with <code>isError:1</code>. Exceptions never
/// escape <method>Invoke</method>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.3</a> (line 1514) — AC source.</li>
/// <li><a href="../../../../irislib/Ens/Rule/Log.cls">irislib/Ens/Rule/Log.cls</a>
/// — column definitions verified empirically (CurrentHeaderId not
/// TriggeringMessageHeader; ConfigName not Component).</li>
/// <li><a href="../../../../irislib/Ens/MessageHeader.cls">irislib/Ens/MessageHeader.cls</a>
/// — header column definitions.</li>
/// <li><a href="GetMessageBody.cls">GetMessageBody.cls</a> — body-render
/// dispatch (Story 4.2) called directly via <code>##class(...).Invoke()</code>.</li>
/// <li><a href="RuleLog.cls">RuleLog.cls</a> — column-mapping precedent
/// (Story 4.1).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetMessageDetail Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_message_detail";

Parameter Description As %String = "Return full message header + body summary + linked rule-log decisions for a single message.";

Parameter MutatesState As %Boolean = 0;

/// <p>Hard cap on the number of <code>rule_decisions</code> returned for
/// a single message. Per AC-3 step 4. Matches the Story 4.1 default-100
/// shape, applied as a static cap here since the v1 tool has no
/// <code>limit</code> input.</p>
Parameter RuleDecisionLimit As %Integer = 100;

/// <p>Locked-subset JSON Schema. Required: <code>message_id</code>. No
/// optional inputs in v1. <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "message_id": {"type": "string", "description": "Ens.MessageHeader id"}
        },
        "required": ["message_id"],
        "additionalProperties": false
    }
}

/// <p>Three-part composition: header read (Step 1), body read via
/// <CLASS>SessionAgent.Tool.Inspection.GetMessageBody</CLASS>.Invoke
/// (Step 2), rule-decisions read filtered by <code>CurrentHeaderId = ?</code>
/// (Step 3). Outer Try/Catch — exceptions never escape.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; ---- Pre-validation ----
        Set tMessageId = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tMessageId = pJsonArgs.%Get("message_id")
            Set:tMessageId=$$$NULLOREF tMessageId = ""
        }
        If tMessageId = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing message_id"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing message_id"}}
            Quit
        }

        ; ---- Step 1 — header read ----
        Set tStmtHdr = ##class(%SQL.Statement).%New()
        Set tSCprep = tStmtHdr.%Prepare("SELECT ID AS id, %EXACT(MessageBodyClassName) AS body_class, %EXACT(MessageBodyId) AS body_id, %EXACT(SourceConfigName) AS source_config_name, %EXACT(TargetConfigName) AS target_config_name, Status AS status, TimeCreated AS time_created, IsError AS is_error, SessionId AS session_id FROM Ens.MessageHeader WHERE ID = ?")
        If $$$ISERR(tSCprep) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":($System.Status.GetErrorText(tSCprep))}], "structuredContent":{"render_strategy":"composition_error", "error_text":($System.Status.GetErrorText(tSCprep))}}
            Quit
        }
        Set tRsHdr = tStmtHdr.%Execute(tMessageId)
        Set tFound = 0
        Set tHeader = {}
        If tRsHdr.%Next() {
            Set tFound = 1
            Set tBodyClass = tRsHdr.%Get("body_class")
            Set tBodyId = tRsHdr.%Get("body_id")
            ; Normalize legacy %String null sentinel ($Char(0)) — same
            ; convention as GetMessageBody Step 1 normalization.
            If tBodyClass = $Char(0) Set tBodyClass = ""
            If tBodyId = $Char(0) Set tBodyId = ""
            Do tHeader.%Set("id", +tRsHdr.%Get("id"), "number")
            Do tHeader.%Set("source_config_name", tRsHdr.%Get("source_config_name"))
            Do tHeader.%Set("target_config_name", tRsHdr.%Get("target_config_name"))
            Do tHeader.%Set("status", +tRsHdr.%Get("status"), "number")
            Do tHeader.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRsHdr.%Get("time_created")))
            Do tHeader.%Set("is_error", +tRsHdr.%Get("is_error"), "boolean")
            Do tHeader.%Set("session_id", +tRsHdr.%Get("session_id"), "number")
            Do tHeader.%Set("body_class", tBodyClass)
            Do tHeader.%Set("body_id", tBodyId)
        }

        ; If the header isn't found, return the early "header_not_found"
        ; envelope — no body lookup, no rule-log lookup.
        If 'tFound {
            Do pResult.structuredContent.%Set("message_id", tMessageId)
            Do pResult.structuredContent.%Set("render_strategy", "header_not_found")
            Do pResult.structuredContent.%Set("header", {})
            Do pResult.structuredContent.%Set("body_summary", "")
            Do pResult.structuredContent.%Set("body_repr", "")
            Do pResult.structuredContent.%Set("rule_decisions", [])
            Do pResult.structuredContent.%Set("rule_decision_count", 0, "number")
            Set pResult.content.%Get(0).text = "no Ens.MessageHeader row for id " _ tMessageId
            Quit
        }

        ; ---- Step 2 — body read via GetMessageBody.Invoke direct call ----
        Set tBodyArgs = {"message_id": (tMessageId), "format": "summary"}
        Set tBodyResult = ""
        Set tBodySummary = ""
        Set tBodyRepr = ""
        Set tBodyRenderStrategy = ""
        Set tBodyTruncated = 0
        Set tBodyClassOut = tBodyClass
        Set tBodyIdOut = tBodyId
        Set tBodyError = ""
        Try {
            Set tSCBody = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, tBodyArgs, .tBodyResult)
            ; Defense-in-depth — if GetMessageBody returned isError (validation
            ; failure), surface the operator-text into a body_error field but
            ; DON'T fail the whole detail call.
            If $IsObject($Get(tBodyResult)) {
                If (+tBodyResult.%Get("isError") = 1) {
                    If tBodyResult.content.%Size() > 0 {
                        Set tBodyError = tBodyResult.content.%Get(0).text
                    }
                } Else {
                    Set tBodySC = $$$OK
                    Try {
                        Set tBodySC = tBodyResult.content.%Get(0).text
                    }
                    Catch sumEx {
                        Set tBodySC = ""
                    }
                    Set tBodySummary = tBodySC
                    Set tInner = tBodyResult.structuredContent
                    If $IsObject(tInner) {
                        Set tBodyRepr = tInner.%Get("body_repr")
                        Set tBodyRenderStrategy = tInner.%Get("render_strategy")
                        Set tBodyTruncated = +tInner.%Get("truncated")
                        Set tInnerBodyClass = tInner.%Get("body_class")
                        Set tInnerBodyId = tInner.%Get("body_id")
                        If tInnerBodyClass '= "" Set tBodyClassOut = tInnerBodyClass
                        If tInnerBodyId '= "" Set tBodyIdOut = tInnerBodyId
                    }
                }
            }
        }
        Catch bodyEx {
            ; GetMessageBody is supposed to be no-throw, but defense-in-depth
            ; — surface as body_error without failing the whole call.
            Set tBodyError = bodyEx.DisplayString()
            Set tBodyRenderStrategy = "dispatch_error"
        }

        ; ---- Step 3 — rule decisions read ----
        ; Filter by CurrentHeaderId (NOT TriggeringMessageHeader — Task 0).
        ; Match RuleLog.cls (Story 4.1) Prepare-failure semantics — surface
        ; via the outer Try/Catch's composition_error envelope rather than
        ; silently returning rule_decision_count=0 (which is operator-
        ; indistinguishable from "no rules fired"). Code-review fix-now per
        ; Rule 8 (predicted-bug shape: rule-decision-table missing or schema
        ; rename would silently zero out the rule_decisions field).
        Set tRuleDecisions = []
        Set tRuleCount = 0
        Set tStmtRule = ##class(%SQL.Statement).%New()
        Set tSCprepR = tStmtRule.%Prepare("SELECT TOP ? ID AS id, %EXACT(RuleName) AS rule_name, %EXACT(ConfigName) AS component, %EXACT(ReturnValue) AS return_value, TimeExecuted AS time_executed, %EXACT(Reason) AS reason FROM Ens_Rule.Log WHERE %EXACT(CurrentHeaderId) = ? ORDER BY TimeExecuted ASC, ID ASC")
        If $$$ISERR(tSCprepR) {
            Set tPrepErr = $System.Status.GetErrorText(tSCprepR)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tPrepErr)}], "structuredContent":{"render_strategy":"composition_error", "error_text":(tPrepErr)}}
            Quit
        }
        Set tRsRule = tStmtRule.%Execute(..#RuleDecisionLimit, tMessageId)
        While tRsRule.%Next() {
            Set tDec = {}
            Do tDec.%Set("id", +tRsRule.%Get("id"), "number")
            Do tDec.%Set("rule_name", tRsRule.%Get("rule_name"))
            Do tDec.%Set("component", tRsRule.%Get("component"))
            Do tDec.%Set("return_value", tRsRule.%Get("return_value"))
            Do tDec.%Set("time_executed", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRsRule.%Get("time_executed")))
            Do tDec.%Set("reason", tRsRule.%Get("reason"))
            Do tRuleDecisions.%Push(tDec)
            Set tRuleCount = tRuleCount + 1
        }

        ; ---- Compose final structuredContent ----
        Do pResult.structuredContent.%Set("message_id", tMessageId)
        Do pResult.structuredContent.%Set("header", tHeader)
        Do pResult.structuredContent.%Set("body_summary", tBodySummary)
        Do pResult.structuredContent.%Set("body_repr", tBodyRepr)
        Do pResult.structuredContent.%Set("body_render_strategy", tBodyRenderStrategy)
        Do pResult.structuredContent.%Set("body_truncated", ''tBodyTruncated, "boolean")
        Do pResult.structuredContent.%Set("body_class", tBodyClassOut)
        Do pResult.structuredContent.%Set("body_id", tBodyIdOut)
        If tBodyError '= "" {
            Do pResult.structuredContent.%Set("body_error", tBodyError)
        }
        Do pResult.structuredContent.%Set("rule_decisions", tRuleDecisions)
        Do pResult.structuredContent.%Set("rule_decision_count", tRuleCount, "number")

        ; ---- Compose content[0].text ----
        Set tIsError = +tHeader.%Get("is_error")
        Set tErrLabel = $Select(tIsError: "yes", 1: "no")
        Set tStatus = +tHeader.%Get("status")
        Set tSrc = tHeader.%Get("source_config_name")
        Set tTgt = tHeader.%Get("target_config_name")
        Set tBodyDesc = tBodyRenderStrategy
        If tBodyRenderStrategy = "no_body" {
            Set tBodyDesc = "no body"
        } ElseIf tBodyRenderStrategy = "header_not_found" {
            Set tBodyDesc = "header missing for body lookup"
        } ElseIf tBodyRenderStrategy = "body_not_found" {
            Set tBodyDesc = "body could not be opened"
        } ElseIf tBodyRenderStrategy = "" {
            Set tBodyDesc = "body unavailable"
        }
        Set tSummaryText = "Message " _ tMessageId _ " from " _ tSrc _ " to " _ tTgt _ " (status: " _ tStatus _ ", errored: " _ tErrLabel _ "). Body: " _ tBodyDesc
        If tBodySummary '= "" {
            Set tSummaryText = tSummaryText _ ", " _ tBodySummary
        }
        Set tSummaryText = tSummaryText _ ". " _ tRuleCount _ " rule decision(s) triggered."
        Set pResult.content.%Get(0).text = tSummaryText
        Quit
    }
    Catch ex {
        ; No-throw guarantee — convert any escaping exception to the
        ; standard envelope. Step name "composition_error" makes the
        ; failure mode explicit.
        Set tErrText = ex.DisplayString()
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"composition_error", "error_text":(tErrText)}}
    }
    Quit tSC
}

}
