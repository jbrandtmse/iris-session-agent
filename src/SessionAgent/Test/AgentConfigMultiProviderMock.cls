/// <p>Test-only mock provider for Story 6.2 AC-5
/// (<method>SessionAgent.Test.AgentConfigTest.TestHotConfigChangeAcrossRunTurnInvocations</method>).
/// Subclasses <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> and
/// overrides <method>GetProviderName</method> to return the
/// <var>Config.Agent.Provider</var> value of the row currently in
/// scope, instead of the static <code>..#PROVIDERNAME = "openai"</code>
/// inherited from <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>.</p>
///
/// <p><b>Why a separate mock.</b> The Story 2.12
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> is hard-coded
/// to the OpenAI wire shape (its
/// <method>CallMessages</method> translates via the
/// <code>"openai"</code> branch of
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS>). The Story 6.2
/// AC-5 hot-config-change test does not require a different wire shape —
/// it only needs the audit row's <code>Provider</code> column to track
/// the live <code>Config.Agent.Provider</code> value, so the audit-row
/// SQL probe can prove the AgentLoop re-read the live config and passed
/// the new provider name to the audit emitter on the second turn.</p>
///
/// <p><b>Capture mechanism.</b>
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> sets
/// <code>tProvider.ConfigAgent = tConfig</code> immediately after
/// <method>InstantiateProvider</method> returns. By the time the
/// inherited <method>Invoke</method> runs and reaches the audit-emit
/// boundary call to <method>GetProviderName</method>, the
/// <property>ConfigAgent</property> property carries the live
/// <CLASS>SessionAgent.Config.Agent</CLASS> row. We read
/// <code>..ConfigAgent.Provider</code> directly so the audit
/// row's <code>Provider</code> column tracks whatever
/// <method>SessionAgent.UI.AgentConfig.SaveAgentConfig</method> just
/// wrote — that's the contract this test proves.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 6.2</a> AC-5 + AC-6 — hot-config-change verification + audit
/// provider attribution.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// NFR-O2 — hot-config-change invariant.</li>
/// <li><CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> — parent
/// mock class providing the response-list cursor mechanism.</li>
/// </ul>
Class SessionAgent.Test.AgentConfigMultiProviderMock Extends SessionAgent.Test.AgentLoopMockProvider
{

/// <p>Override the inherited <code>..#PROVIDERNAME = "openai"</code> by
/// returning the live <CLASS>SessionAgent.Config.Agent</CLASS> row's
/// <property>Provider</property> value instead. The
/// <method>Invoke</method> path emits exactly one
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> row per round-trip with
/// this provider name in the <code>Provider</code> column — which is
/// the AC-6 audit-attribution probe target.</p>
Method GetProviderName() As %String
{
    If $IsObject(..ConfigAgent), ..ConfigAgent.Provider '= "" {
        Quit ..ConfigAgent.Provider
    }
    ; Fallback to the inherited static value — should not happen in the
    ; AC-5 test path, but defends against an uninitialized ConfigAgent
    ; on any non-test invocation.
    Quit ##super()
}

}
