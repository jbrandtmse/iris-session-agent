/// <p>Test-only multi-turn mock provider for the Story 5.4 cross-provider
/// matrix test (<CLASS>SessionAgent.Test.ToolCallRoundtripIntegrationTest</CLASS>).
/// Subclasses <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS> and
/// overrides both <method>Invoke</method> (to bypass credential
/// resolution) and <method>IssueHttpsPost</method> (to read canned
/// response bodies from the
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> per-process queue).
/// Mirrors the OpenAI-flavored
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> exactly — same
/// pattern, different production parent class.</p>
///
/// <p><b>Why a separate class.</b>
/// <CLASS>SessionAgent.Test.MockAnthropicProvider</CLASS> (Story 5.1) is
/// a single-canned-response mock with per-instance configuration. The
/// matrix test needs multi-turn (turn 1 = tool_use, turn 2 = end_turn)
/// dialog, which requires the per-process response queue lifecycle the
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> indirection
/// provides — instance Properties would not survive AgentLoop's
/// per-turn fresh-instance construction.</p>
///
/// <p><b>Lifecycle.</b> Configuration installed in test methods via
/// <method>SessionAgent.Agent.ProviderOverride.SetOverride</method> with
/// class name <code>"SessionAgent.Test.AgentLoopMockAnthropic"</code> and
/// a JSON config carrying <code>{responses:[...]}</code>; cleared via
/// <method>SessionAgent.Agent.ProviderOverride.ClearOverride</method>.
/// Each call to
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// builds a fresh OREF and reads the next canned response from the
/// per-process queue.</p>
Class SessionAgent.Test.AgentLoopMockAnthropic Extends SessionAgent.LLM.AnthropicProvider
{

/// <p>Hook called by
/// <method>SessionAgent.Agent.ProviderOverride.GetOverride</method> after
/// construction. No per-instance state to install — the canned response
/// sequence is read directly from the override globals on each
/// <method>IssueHttpsPost</method> call.</p>
Method %InstallOverrideConfig(pConfigJson As %String)
{
    Quit
}

/// <p>Override the abstract template — bypass the credential-resolution
/// fast path that <method>SessionAgent.LLM.Provider.Invoke</method> would
/// otherwise trip on (empty env-var → credential-missing envelope, no
/// <method>CallMessages</method> dispatch). Mirrors the production
/// <method>SessionAgent.LLM.Provider.Invoke</method> shape — start
/// timer, dispatch <method>CallMessages</method>, compute latency,
/// emit audit row at the boundary — but skips credential resolution.</p>
Method Invoke(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As SessionAgent.Config.Agent, pCallerCtx As SessionAgent.Agent.CallerContext, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK
    Set tStart = $ZHorolog
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }
    Try {
        Set tCallSC = ..CallMessages(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, .pProviderResponse)
        If $$$ISERR(tCallSC) {
            Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, $System.Status.GetErrorText(tCallSC))
        }
        Set tLatency = ##class(SessionAgent.LLM.Provider).ComputeLatencyMs(tStart)

        Set tInputTokens = 0
        Set tOutputTokens = 0
        Set tCacheHitTokens = 0
        If $IsObject(pProviderResponse.Usage) {
            If pProviderResponse.Usage.%IsDefined("input_tokens") {
                Set tInputTokens = +pProviderResponse.Usage.%Get("input_tokens")
            }
            If pProviderResponse.Usage.%IsDefined("output_tokens") {
                Set tOutputTokens = +pProviderResponse.Usage.%Get("output_tokens")
            }
            If pProviderResponse.Usage.%IsDefined("cache_read_input_tokens") {
                Set tCacheHitTokens = +pProviderResponse.Usage.%Get("cache_read_input_tokens")
            }
        }
        Set tIsError = 0
        Set tErrorText = ""
        If pProviderResponse.StopReason = "error" {
            Set tIsError = 1
            If $IsObject(pProviderResponse.Content), pProviderResponse.Content.%Size() > 0 {
                Set tBlock = pProviderResponse.Content.%Get(0)
                If $IsObject(tBlock), tBlock.%IsDefined("text") {
                    Set tErrorText = tBlock.%Get("text")
                }
            }
        }
        Do ##class(SessionAgent.Audit.Emit).LogLlmCall(
            ##class(SessionAgent.LLM.Provider).ResolveChatHistoryId(pCallerCtx),
            ..GetProviderName(),
            pConfigAgent.Model,
            pCanonicalHistory.%Size(),
            tInputTokens, tOutputTokens,
            tLatency,
            pProviderResponse.StopReason,
            tCacheHitTokens, tIsError, tErrorText)
    }
    Catch ex {
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockAnthropic.Invoke exception: " _ ex.DisplayString())
    }
    Quit tSC
}

/// <p>Override — bypass the production credential-resolution + retry
/// loop entirely. Build the production payload (so the BuildPayload path
/// is still exercised end-to-end), then read the next canned response
/// body + status code from
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> and parse via the
/// production <method>ParseResponse</method> (canonical-passthrough per
/// FR27).</p>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }
    Try {
        Set ..ApiKey = "sk-ant-mock-test"
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()

        Set tBodyStr = ##class(SessionAgent.Agent.ProviderOverride).NextCannedResponse()
        Set tStatusCode = ##class(SessionAgent.Agent.ProviderOverride).CurrentStatusCode()

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Anthropic HTTP " _ tStatusCode _ ": " _ tBodyStr)
            Quit
        }

        ; Anthropic IS canonical (FR27 passthrough); use the production
        ; ParseResponse method directly.
        Do ..ParseResponse(tBodyStr, .pProviderResponse)
    }
    Catch ex {
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockAnthropic.CallMessages exception: " _ ex.DisplayString())
    }
    Set ..ApiKey = ""
    Quit tSC
}

}
