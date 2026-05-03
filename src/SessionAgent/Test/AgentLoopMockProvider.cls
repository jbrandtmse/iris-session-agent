/// <p>Test-only multi-turn mock provider for
/// <CLASS>SessionAgent.Test.AgentLoopTest</CLASS> and
/// <CLASS>SessionAgent.Test.SmokeTest</CLASS>. Subclasses
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> and overrides both
/// <method>Invoke</method> (to bypass credential resolution — no env-
/// var SetEnviron API on this IRIS build) and
/// <method>IssueHttpsPost</method> (to return canned response bodies).
/// State (response list, status codes, cursor) lives in
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> process-private
/// globals because <CLASS>SessionAgent.Agent.AgentLoop.InstantiateProvider</CLASS>
/// constructs a fresh mock instance on every turn — instance Properties
/// would not persist across turns.</p>
///
/// <p><b>Why a separate class.</b>
/// <CLASS>SessionAgent.Test.MockOpenAIProvider</CLASS> (Story 2.9) is a
/// single-canned-response mock with per-instance configuration —
/// works for <method>CallMessages</method>-level unit tests but not
/// for the multi-turn <method>RunTurn</method> orchestration tests
/// where each round-trip needs a different response. This class adds
/// the response-list walk via the
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> indirection
/// without breaking the Story 2.9 single-shot mock.</p>
///
/// <p><b>Lifecycle.</b> Configuration installed in
/// <code>OnBeforeOneTest</code> via
/// <method>SessionAgent.Agent.ProviderOverride.SetOverride</method>;
/// cleared in <code>OnAfterOneTest</code> via
/// <method>SessionAgent.Agent.ProviderOverride.ClearOverride</method>.
/// Each call to <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// builds a fresh OREF and configures it from the per-process
/// override.</p>
Class SessionAgent.Test.AgentLoopMockProvider Extends SessionAgent.LLM.OpenAIProvider
{

/// <p>Hook called by
/// <method>SessionAgent.Agent.ProviderOverride.GetOverride</method>
/// after construction. The base mock has no per-instance config to
/// apply (state lives in the per-process override globals), so this
/// is a no-op. Future mock subclasses (e.g., a Smoke-specific mock
/// that overrides specific behaviors) can implement this to consume
/// per-instance JSON config.</p>
Method %InstallOverrideConfig(pConfigJson As %String)
{
    ; No per-instance state to install — the canned response sequence
    ; is read directly from the override globals on each
    ; IssueHttpsPost call.
    Quit
}

/// <p>Override the abstract template — bypass the credential-resolution
/// fast path that <method>SessionAgent.LLM.Provider.Invoke</method>
/// would otherwise trip on (empty env-var → credential-missing
/// envelope, no <method>CallMessages</method> dispatch). The mock
/// fully owns the orchestration so the AgentLoop's
/// <method>RunTurn</method> sees the canned responses without
/// EnvSecret resolution. Mirrors the production
/// <method>SessionAgent.LLM.Provider.Invoke</method> shape — start
/// timer, dispatch <method>CallMessages</method>, compute latency,
/// emit audit row at the boundary — but skips credential resolution
/// (the only delta).</p>
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
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockProvider.Invoke exception: " _ ex.DisplayString())
    }
    Quit tSC
}

/// <p>Override — bypass the production credential-resolution + retry
/// loop entirely. Build the production payload (so the BuildPayload
/// path is still exercised end-to-end), then read the next canned
/// response body + status code from
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> and translate to
/// canonical via <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>.</p>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }
    Try {
        ; Stamp synthetic key so the production payload-build path is
        ; exercised end-to-end.
        Set ..ApiKey = "sk-mock-test"
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()

        ; Pull the next canned response from the override list.
        Set tBodyStr = ##class(SessionAgent.Agent.ProviderOverride).NextCannedResponse()
        Set tStatusCode = ##class(SessionAgent.Agent.ProviderOverride).CurrentStatusCode()

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Do ##class(SessionAgent.LLM.OpenAIProvider).PopulateErrorEnvelope(.pProviderResponse, "OpenAI HTTP " _ tStatusCode _ ": " _ tBodyStr)
            Quit
        }

        Set tBodyObj = ##class(%DynamicObject).%New()
        If tBodyStr '= "" {
            Set tBodyObj = ##class(%DynamicObject).%FromJSON(tBodyStr)
        }
        Set tCanon = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical(..#PROVIDERNAME, tBodyObj)
        Set pProviderResponse.Content = tCanon.%Get("content")
        Set pProviderResponse.StopReason = tCanon.%Get("stopReason")
        Set pProviderResponse.Usage = tCanon.%Get("usage")
    }
    Catch ex {
        Do ##class(SessionAgent.LLM.Provider).PopulateGenericError(pProviderResponse, "AgentLoopMockProvider.CallMessages exception: " _ ex.DisplayString())
    }
    Set ..ApiKey = ""
    Quit tSC
}

}
