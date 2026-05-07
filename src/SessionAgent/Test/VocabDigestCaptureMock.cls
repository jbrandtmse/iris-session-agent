/// <p>Story 9.4 capture-and-delegate mock provider used by
/// <CLASS>SessionAgent.Test.AgentLoopVocabDigestTest</CLASS> to verify
/// (a) the digest-prefixed user-block text reaches the LLM-bound array
/// (AC-3 rows 1–3, 5), and (b) the cached <code>system + tools</code>
/// prefix is byte-identical across turns (AC-4 — Anthropic prompt-cache
/// preservation).</p>
///
/// <p>Subclasses <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS>
/// and overrides <method>Invoke</method> to stash three pieces of state
/// into process-private globals BEFORE delegating to <code>##super</code>:
/// </p>
/// <ul>
/// <li><code>^||SessionAgentVocabDigestCapture</code> — the
/// concatenated text content of the LAST user turn in
/// <var>pCanonicalHistory</var> (i.e., the user-block text the AgentLoop
/// just composed for this turn). The AgentLoop's two-array invariant
/// puts the digest-prefixed text on the LLM-bound array, so capturing
/// the last user turn here directly reads what the provider would
/// receive.</li>
/// <li><code>^||SessionAgentVocabDigestCaptureSystem</code> —
/// <var>pSystemPrompt</var> verbatim (AC-4 cached-prefix check).</li>
/// <li><code>^||SessionAgentVocabDigestCaptureTools</code> —
/// <var>pToolDefs.%ToJSON()</var> (AC-4 cached-prefix check).</li>
/// </ul>
///
/// <p><b>Why process-private globals.</b> The AgentLoop's
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// constructs a fresh provider OREF on every iteration of the
/// orchestration loop — instance Properties would not persist across
/// turns. PPGs round-trip plain string state losslessly within the
/// process. Per project rule §"Process-Private Globals (^||) and OREF
/// Storage" the OREF identity issue does not apply here — we capture
/// strings only.</p>
Class SessionAgent.Test.VocabDigestCaptureMock Extends SessionAgent.Test.AgentLoopMockProvider
{

/// <p>Override — capture the last user turn's text content,
/// <var>pSystemPrompt</var>, and <var>pToolDefs.%ToJSON()</var> into
/// process-private globals, then delegate to the parent mock's full
/// <method>Invoke</method> implementation. Capture happens BEFORE
/// delegation so even if the parent's Invoke errors the test can still
/// inspect what the AgentLoop sent.</p>
///
/// <p>Multi-turn capture replaces the prior values rather than
/// appending — the test orchestration explicitly clears the PPGs
/// between turns when it wants to verify per-turn state. Replacement
/// keeps the AC-4 turn-to-turn comparison straightforward (capture
/// turn 1, snapshot, capture turn 2, compare).</p>
Method Invoke(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As SessionAgent.Config.Agent, pCallerCtx As SessionAgent.Agent.CallerContext, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    ; ---- Capture user-block text (AC-3 rows 1-3, 5).
    ; Walk the history backwards to find the most recent user turn —
    ; for a fresh first turn this is index 0; for a multi-turn case
    ; (AC-4 turn 2) this is the latest user turn. Concatenate any
    ; text-block content within that turn.
    Set tUserText = ""
    If $IsObject(pCanonicalHistory), pCanonicalHistory.%Size() > 0 {
        Set tIdx = pCanonicalHistory.%Size() - 1
        Set tFound = 0
        While (tIdx >= 0) && (tFound = 0) {
            Set tTurn = pCanonicalHistory.%Get(tIdx)
            If $IsObject(tTurn), tTurn.%Get("role") = "user" {
                Set tFound = 1
                Set tContent = tTurn.%Get("content")
                If $IsObject(tContent) {
                    Set tBlockIter = tContent.%GetIterator()
                    While tBlockIter.%GetNext(.tBidx, .tBlock) {
                        If '$IsObject(tBlock) Continue
                        If tBlock.%Get("type") '= "text" Continue
                        Set tUserText = tUserText _ tBlock.%Get("text")
                    }
                }
            }
            Set tIdx = tIdx - 1
        }
    }
    Set ^||SessionAgentVocabDigestCapture = tUserText

    ; ---- Capture system prompt + tools JSON (AC-4 cached-prefix check).
    Set ^||SessionAgentVocabDigestCaptureSystem = pSystemPrompt
    Set tToolsJson = ""
    If $IsObject(pToolDefs) {
        Set tToolsJson = pToolDefs.%ToJSON()
    }
    Set ^||SessionAgentVocabDigestCaptureTools = tToolsJson

    ; Delegate to the parent mock's Invoke for canned-response dispatch.
    Quit ##super(.pCanonicalHistory, .pToolDefs, .pSystemPrompt, .pCacheConfig, .pConfigAgent, .pCallerCtx, .pProviderResponse)
}

}
