/// <p>Story 3.5 AC-6 — capture-and-delegate mock provider used by
/// <CLASS>SessionAgent.Test.AgentLoopGuardsTest</CLASS> to verify the
/// system-prompt session-id injection (closes Story 3.3 reviewer's
/// binding deferral F5).</p>
///
/// <p>Subclasses <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS>
/// and overrides <method>Invoke</method> to stash <var>pSystemPrompt</var>
/// into a process-private global (<code>^||SessionAgentSystemPromptCapture</code>)
/// before delegating to <code>##super</code>. The test reads the global
/// after <method>SessionAgent.Agent.AgentLoop.RunTurn</method> returns
/// and asserts the AC-6 binding sentence is present (or absent for the
/// empty-session-key case).</p>
///
/// <p><b>Why a process-private global, not an instance Property.</b>
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// constructs a fresh provider OREF on every iteration of the
/// orchestration loop — instance Properties would not persist across
/// turns (and would be lost when the OREF goes out of scope). The
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> singleton holder
/// is the production solution for OREF identity, but for test capture
/// we just need string state, which globals carry losslessly.</p>
Class SessionAgent.Test.SystemPromptCaptureMock Extends SessionAgent.Test.AgentLoopMockProvider
{

/// <p>Override — stash <var>pSystemPrompt</var> into the process-private
/// global, then delegate to the parent mock's full
/// <method>Invoke</method> implementation (which dispatches the canned
/// response from the override globals). The capture happens on EVERY
/// round-trip; the global accumulates if multiple turns occur (separator
/// is the literal string <code>"||"</code> so the test can split if
/// needed). For Story 3.5 AC-6 the assertion is a substring check on the
/// final value; multi-turn capture is for future stories that may want
/// to assert per-turn prompt evolution.</p>
Method Invoke(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As SessionAgent.Config.Agent, pCallerCtx As SessionAgent.Agent.CallerContext, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    ; Capture before delegation so even if the parent's Invoke errors
    ; the test can still inspect what the AgentLoop sent. Append with a
    ; separator so multi-turn invocations stack into a single inspectable
    ; string.
    Set tPrev = $Get(^||SessionAgentSystemPromptCapture, "")
    If tPrev = "" {
        Set ^||SessionAgentSystemPromptCapture = pSystemPrompt
    } Else {
        Set ^||SessionAgentSystemPromptCapture = tPrev _ "||" _ pSystemPrompt
    }
    Quit ##super(.pCanonicalHistory, .pToolDefs, .pSystemPrompt, .pCacheConfig, .pConfigAgent, .pCallerCtx, .pProviderResponse)
}

}
