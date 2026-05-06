/// <p><b>Story 5.3 retroactive Rule 11 LIVE smoke test (Story 5.2 R-1
/// closure).</b> One-shot classmethod that invokes the production
/// <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS> against the real
/// Anthropic Messages API (<code>api.anthropic.com</code>) using the
/// <code>SessionAgentAnthropic</code> credential, with a one-tool-turn
/// scenario against a sample-production session with errors (the freshest
/// available session id is selected at run time).</p>
///
/// <p>This is NOT a <CLASS>%UnitTest.TestCase</CLASS> subclass — it's a
/// standalone classmethod invoked manually for the epic-end empirical
/// battery. Skipped automatically if the credential is not resolvable
/// (so CI without credentials still passes per Rule 11
/// "credential-presence check that skips gracefully"). Mirrors
/// <CLASS>SessionAgent.Test.GeminiProviderLive</CLASS> /
/// <CLASS>SessionAgent.Test.OpenAICompatProviderLive</CLASS> — the three
/// standing live-test classes after Story 5.3 (Story 2.9 OpenAIProvider
/// has its own pre-existing live test).</p>
///
/// <p>The end-to-end live verification:</p>
/// <ol>
/// <li>Probes credential resolvability via
/// <method>SessionAgent.Util.EnvSecret.IsResolvable</method>; aborts
/// with a "skipped" return if false.</li>
/// <li>Builds a transient <CLASS>SessionAgent.Config.Agent</CLASS> with
/// <code>Provider="anthropic"</code>,
/// <code>Model="claude-haiku-4-5-20251001"</code>,
/// <code>CredentialName="SessionAgentAnthropic"</code>.</li>
/// <li>Builds a canonical history with one user message asking what
/// errors happened in a sample-prod session; provides one tool
/// (<code>event_log</code>) so Anthropic can pick it.</li>
/// <li>Invokes
/// <method>SessionAgent.LLM.AnthropicProvider.Invoke</method> (the
/// abstract template — exercises full audit-emit + retry +
/// canonical-passthrough).</li>
/// <li>Captures the resulting
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS> + the latest
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> row id for the caller to
/// SQL-probe verbatim.</li>
/// </ol>
Class SessionAgent.Test.AnthropicProviderLive Extends %RegisteredObject
{

/// <p>One-shot live invocation. Returns a
/// <CLASS>%DynamicObject</CLASS> with
/// <code>{skipped, stopReason, contentSummary, inputTokens,
/// outputTokens, model, auditRowId}</code>. Caller SQL-probes the
/// audit row id to capture the verbatim Audit.LlmCall row.</p>
ClassMethod Invoke() As %DynamicObject
{
    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("skipped", 0)

    ; Step 1 — credential check (Rule 11 graceful skip).
    Set tResolvable = ##class(SessionAgent.Util.EnvSecret).IsResolvable("", "SessionAgentAnthropic")
    If 'tResolvable {
        Do tOut.%Set("skipped", 1)
        Do tOut.%Set("reason", "SessionAgentAnthropic credential not resolvable — Rule 11 graceful skip")
        Quit tOut
    }

    ; Step 2 — pick a fresh sample-prod session with errors. Falls back
    ; to 2613 (current freshest as of 2026-05-06) if SQL probe fails.
    Set tSessionId = 2613
    &sql(SELECT TOP 1 SessionId INTO :tSid FROM Ens_Util.Log
         WHERE Type IN (1,2) AND SessionId > 0
         GROUP BY SessionId ORDER BY MAX(ID) DESC)
    If $Get(tSid) > 0 Set tSessionId = +tSid

    ; Step 3 — transient ConfigAgent.
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "story-5-3-anthropic-live-test"
    Set tCfg.Provider = "anthropic"
    Set tCfg.Model = "claude-haiku-4-5-20251001"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1024
    Set tCfg.EnvVarName = ""
    Set tCfg.CredentialName = "SessionAgentAnthropic"
    Set tCfg.EndpointUrl = ""
    Set tCfg.Enabled = 1
    Set tCfg.ReadOnly = 1

    ; Step 4 — canonical history asking about errors in the chosen session.
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", "What errors happened in session " _ tSessionId _ "? Use the event_log tool to look it up.")
    Do tContent.%Push(tBlock)
    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)

    ; Step 5 — minimal canonical tool def (just event_log).
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tDef = ##class(%DynamicObject).%New()
    Do tDef.%Set("name", "event_log")
    Do tDef.%Set("description", "Return the IRIS event log entries for an Ensemble session. Returns ErrorText / Severity / DateTime per entry.")
    Set tSchema = ##class(%DynamicObject).%New()
    Do tSchema.%Set("type", "object")
    Set tProps = ##class(%DynamicObject).%New()
    Set tSidProp = ##class(%DynamicObject).%New()
    Do tSidProp.%Set("type", "integer")
    Do tSidProp.%Set("description", "Ensemble session id")
    Do tProps.%Set("sessionId", tSidProp)
    Do tSchema.%Set("properties", tProps)
    Set tRequired = ##class(%DynamicArray).%New()
    Do tRequired.%Push("sessionId")
    Do tSchema.%Set("required", tRequired)
    Do tDef.%Set("input_schema", tSchema)
    Do tToolDefs.%Push(tDef)

    Set tSystemPrompt = "You are an inspection assistant. Use the event_log tool when asked about errors in a session."

    ; Step 6 — capture audit-row baseline so we can identify the new row.
    &sql(SELECT MAX(ID) INTO :tBaseline FROM SessionAgent_Audit.LlmCall)
    If $Get(tBaseline) = "" Set tBaseline = 0

    ; Step 7 — invoke the provider via the abstract template.
    Set tProvider = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Set tProvider.ConfigAgent = tCfg

    Set tCallerCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCallerCtx.AgentName = "story-5-3-anthropic-live-test"
    Set tCallerCtx.IrisSessionId = tSessionId
    Set tCallerCtx.PortalUser = $UserName
    Set tCallerCtx.Namespace = $Namespace

    Set tProvResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tCacheCfg = ##class(%DynamicObject).%New()
    ; Anthropic prompt-caching plan (NFR-P6, Story 5.1) — enable cache_control
    ; on system + last tool to mirror production AgentLoop behavior.
    Do tCacheCfg.%Set("SystemEnabled", 1)
    Do tCacheCfg.%Set("ToolsEnabled", 1)

    Set tInvokeSC = tProvider.Invoke(tHistory, tToolDefs, tSystemPrompt, tCacheCfg, tCfg, tCallerCtx, .tProvResp)

    ; Step 8 — populate the result envelope.
    Do tOut.%Set("invokeStatus", $Select($$$ISOK(tInvokeSC):"OK", 1:$System.Status.GetErrorText(tInvokeSC)))
    Do tOut.%Set("stopReason", tProvResp.StopReason)
    Do tOut.%Set("targetSessionId", tSessionId)
    Do tOut.%Set("model", tCfg.Model)

    ; Content summary — first block's type + text/name.
    Set tSummary = "(empty)"
    If $IsObject(tProvResp.Content) && (tProvResp.Content.%Size() > 0) {
        Set tBlock0 = tProvResp.Content.%Get(0)
        If $IsObject(tBlock0) {
            Set tType = ""
            If tBlock0.%IsDefined("type") Set tType = tBlock0.%Get("type")
            If tType = "tool_use" {
                Set tName = ""
                If tBlock0.%IsDefined("name") Set tName = tBlock0.%Get("name")
                Set tInputJson = ""
                If tBlock0.%IsDefined("input"), $IsObject(tBlock0.%Get("input")) {
                    Set tInputJson = tBlock0.%Get("input").%ToJSON()
                }
                Set tSummary = "type=tool_use name=" _ tName _ " input=" _ tInputJson
            } ElseIf tType = "text" {
                Set tTextStr = ""
                If tBlock0.%IsDefined("text") Set tTextStr = tBlock0.%Get("text")
                Set tSummary = "type=text text=" _ $Extract(tTextStr, 1, 200)
            } Else {
                Set tSummary = "type=" _ tType
            }
        }
    }
    Do tOut.%Set("contentSummary", tSummary)
    Do tOut.%Set("contentBlockCount", $Select($IsObject(tProvResp.Content):tProvResp.Content.%Size(), 1:0))

    ; Token counts.
    Set tIn = 0
    Set tOutTokens = 0
    If $IsObject(tProvResp.Usage) {
        If tProvResp.Usage.%IsDefined("input_tokens") {
            Set tIn = +tProvResp.Usage.%Get("input_tokens")
        }
        If tProvResp.Usage.%IsDefined("output_tokens") {
            Set tOutTokens = +tProvResp.Usage.%Get("output_tokens")
        }
    }
    Do tOut.%Set("inputTokens", tIn)
    Do tOut.%Set("outputTokens", tOutTokens)

    ; Audit row id — the new row should have ID > tBaseline.
    &sql(SELECT MAX(ID) INTO :tNewId FROM SessionAgent_Audit.LlmCall)
    If $Get(tNewId) = "" Set tNewId = 0
    Do tOut.%Set("auditBaselineId", tBaseline)
    Do tOut.%Set("auditNewId", tNewId)

    Quit tOut
}

}
