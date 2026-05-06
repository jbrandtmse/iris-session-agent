/// <p>Test-only multi-turn mock provider for the Story 5.4 cross-provider
/// matrix test (<CLASS>SessionAgent.Test.ToolCallRoundtripIntegrationTest</CLASS>).
/// Subclasses <CLASS>SessionAgent.LLM.GeminiProvider</CLASS> and
/// overrides both <method>Invoke</method> (to bypass credential
/// resolution) and <method>CallMessages</method> (to read canned response
/// bodies from the <CLASS>SessionAgent.Agent.ProviderOverride</CLASS>
/// per-process queue). Mirrors
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> /
/// <CLASS>SessionAgent.Test.AgentLoopMockAnthropic</CLASS> exactly — same
/// pattern, different production parent class.</p>
///
/// <p><b>Lifecycle.</b> Configuration installed in test methods via
/// <method>SessionAgent.Agent.ProviderOverride.SetOverride</method> with
/// class name <code>"SessionAgent.Test.AgentLoopMockGemini"</code>. Each
/// call to
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// builds a fresh OREF and reads the next canned response from the
/// per-process queue.</p>
Class SessionAgent.Test.AgentLoopMockGemini Extends SessionAgent.LLM.GeminiProvider
{

/// <p>Hook called by
/// <method>SessionAgent.Agent.ProviderOverride.GetOverride</method> after
/// construction. No per-instance state to install.</p>
Method %InstallOverrideConfig(pConfigJson As %String)
{
    Quit
}

/// <p>Override the abstract template — bypass the credential-resolution
/// fast path. Mirrors the production
/// <method>SessionAgent.LLM.Provider.Invoke</method> shape but skips
/// credential resolution.</p>
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
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockGemini.Invoke exception: " _ ex.DisplayString())
    }
    Quit tSC
}

/// <p>Override — bypass the production credential-resolution + retry
/// loop entirely. Build the production payload (BuildPayload exercised
/// end-to-end), then read the next canned response from the override
/// queue and translate via the production <method>ParseResponse</method>
/// (which delegates to MessageAdapter.ProviderToCanonical for the
/// Gemini-shape → canonical round-trip per FR27).</p>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }
    Try {
        Set ..ApiKey = "AIza-mock-test"
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()

        Set tBodyStr = ##class(SessionAgent.Agent.ProviderOverride).NextCannedResponse()
        Set tStatusCode = ##class(SessionAgent.Agent.ProviderOverride).CurrentStatusCode()

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Gemini HTTP " _ tStatusCode _ ": " _ tBodyStr)
            Quit
        }

        Do ..ParseResponse(tBodyStr, .pProviderResponse)
    }
    Catch ex {
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockGemini.CallMessages exception: " _ ex.DisplayString())
    }
    Set ..ApiKey = ""
    Quit tSC
}

}
