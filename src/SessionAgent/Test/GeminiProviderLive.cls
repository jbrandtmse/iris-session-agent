/// <p><b>Story 5.2 Rule 11 LIVE smoke test.</b> One-shot classmethod that
/// invokes the production <CLASS>SessionAgent.LLM.GeminiProvider</CLASS>
/// against the real Gemini API
/// (<code>generativelanguage.googleapis.com</code>) using the
/// <code>SessionAgentGemini</code> credential, with a one-tool-turn
/// scenario against sample-production session 2114 (rich-data session
/// with errors per <code>epic-5-operator-state.md</code>).</p>
///
/// <p>This is NOT a <CLASS>%UnitTest.TestCase</CLASS> subclass — it's a
/// standalone classmethod invoked manually for the epic-end empirical
/// battery. Skipped automatically if the credential is not resolvable
/// (so CI without credentials still passes per Rule 11
/// "credential-presence check that skips gracefully").</p>
///
/// <p>The end-to-end live verification:</p>
/// <ol>
/// <li>Probes credential resolvability via
/// <method>SessionAgent.Util.EnvSecret.IsResolvable</method>; aborts
/// with a "skipped" return if false.</li>
/// <li>Builds a transient <CLASS>SessionAgent.Config.Agent</CLASS> with
/// <code>Provider="gemini"</code>,
/// <code>Model="gemini-2.5-flash"</code>,
/// <code>CredentialName="SessionAgentGemini"</code>.</li>
/// <li>Builds a canonical history with one user message asking what
/// errors happened in session 2114; provides the canonical 13-tool
/// catalog so Gemini can pick <code>event_log</code>.</li>
/// <li>Invokes <method>SessionAgent.LLM.GeminiProvider.Invoke</method>
/// (the abstract template — exercises full audit-emit + retry +
/// canonical translation).</li>
/// <li>Captures the resulting
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS> + the latest
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> row id for the caller to
/// SQL-probe verbatim.</li>
/// </ol>
Class SessionAgent.Test.GeminiProviderLive Extends %RegisteredObject
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
    Set tResolvable = ##class(SessionAgent.Util.EnvSecret).IsResolvable("", "SessionAgentGemini")
    If 'tResolvable {
        Do tOut.%Set("skipped", 1)
        Do tOut.%Set("reason", "SessionAgentGemini credential not resolvable — Rule 11 graceful skip")
        Quit tOut
    }

    ; Step 2 — transient ConfigAgent.
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "story-5-2-live-test"
    Set tCfg.Provider = "gemini"
    Set tCfg.Model = "gemini-2.5-flash"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1024
    Set tCfg.EnvVarName = ""
    Set tCfg.CredentialName = "SessionAgentGemini"
    Set tCfg.EndpointUrl = ""
    Set tCfg.Enabled = 1
    Set tCfg.ReadOnly = 1

    ; Step 3 — canonical history asking about errors in session 2114.
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", "What errors happened in session 2114? Use the event_log tool to look it up.")
    Do tContent.%Push(tBlock)
    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)

    ; Step 4 — minimal canonical tool def (just event_log) so Gemini
    ; sees one tool option. The full 13-tool catalog isn't required
    ; for the wire-shape proof.
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

    ; Step 5 — capture audit-row baseline so we can identify the new row.
    &sql(SELECT MAX(ID) INTO :tBaseline FROM SessionAgent_Audit.LlmCall)
    If $Get(tBaseline) = "" Set tBaseline = 0

    ; Step 6 — invoke the provider via the abstract template.
    Set tProvider = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Set tProvider.ConfigAgent = tCfg

    Set tCallerCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCallerCtx.AgentName = "story-5-2-live-test"
    Set tCallerCtx.IrisSessionId = "2114"
    Set tCallerCtx.PortalUser = $UserName
    Set tCallerCtx.Namespace = $Namespace

    Set tProvResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tCacheCfg = ##class(%DynamicObject).%New()

    Set tInvokeSC = tProvider.Invoke(tHistory, tToolDefs, tSystemPrompt, tCacheCfg, tCfg, tCallerCtx, .tProvResp)

    ; Step 7 — populate the result envelope.
    Do tOut.%Set("invokeStatus", $Select($$$ISOK(tInvokeSC):"OK", 1:$System.Status.GetErrorText(tInvokeSC)))
    Do tOut.%Set("stopReason", tProvResp.StopReason)

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
