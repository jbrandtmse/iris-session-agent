/// <p>Per-agent default values for <CLASS>SessionAgent.Config.Agent</CLASS>:
/// system-prompt strings and the <method>%Save</method>-able seed-row
/// shape that <method>SessionAgent.Installer.SeedDefaultAgentConfigs</method>
/// inserts at install time.</p>
///
/// <p>Two helpers, both pure (no globals, no I/O, no exceptions):</p>
/// <ul>
/// <li><method>GetSystemPrompt</method> returns the per-agent default
/// system-prompt string. Used by the AgentLoop on every turn unless the
/// row's <code>SystemPromptOverride</code> property is non-empty.</li>
/// <li><method>GetSeedConfig</method> returns a populated
/// <i>un-saved</i> <CLASS>SessionAgent.Config.Agent</CLASS> instance with
/// the OD4 default shape (provider=openai, model=gpt-4.1-mini, max-tokens=4096,
/// temperature=0.0, env-var=OPENAI_API_KEY, enabled=0, read-only=1,
/// retention=30 days). Caller is responsible for <method>%Save</method>
/// and <code>%Status</code> checking.</li>
/// </ul>
///
/// <p><b>Unknown agent name</b> behavior is the contract the Installer
/// relies on for safety: <method>GetSystemPrompt</method> returns
/// <code>""</code>; <method>GetSeedConfig</method> returns
/// <code>$$$NULLOREF</code>. The Installer only ever passes
/// <code>session-inspection</code> or <code>message-search</code>, but
/// the unknown-agent fallthroughs let the Story 6 UI / future stories
/// safely call these helpers without a defensive caller-side guard.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../planning-artifacts/epics.md">epics.md Story 2.4</a>
/// (lines 798–821) — AC source.</li>
/// <li><a href="../planning-artifacts/architecture.md">architecture.md</a>
/// row OD4 (line 308) — provider/model/seed defaults; class file path
/// (line 850).</li>
/// </ul>
Class SessionAgent.Config.AgentDefaults Extends %RegisteredObject
{

/// <p>Returns the per-agent default system prompt. The strings here are
/// the v1 reference shape — operators may override per-row via
/// <code>Config.Agent.SystemPromptOverride</code>.</p>
///
/// <p>Returns <code>""</code> for any unknown <var>pAgentName</var>.</p>
ClassMethod GetSystemPrompt(pAgentName As %String) As %String
{
    If pAgentName = "session-inspection" {
        Quit "You are the SessionAgent Session-Inspection assistant. " _
            "Read-only invariant: you MUST NOT make any writes, sends, or edits to the IRIS Production. " _
            "The set of inspection tools available to you is provided to you separately as a typed tool list " _
            "by the runtime — use only the tools in that list, do not invent tool names or describe " _
            "capabilities you don't actually have. " _
            "Answer in plain English; cite sessions by their numeric SessionId and individual messages by " _
            "their numeric ObjectId (also called Message ID or header ID — NOT the SessionId, which identifies the whole session). " _
            "When emitting citation chips like [message:N], N is the per-message ObjectId from the " _
            "Ens.MessageHeader row, not the SessionId."
    }
    If pAgentName = "message-search" {
        Quit "You are the SessionAgent Message-Search assistant. " _
            "Bounded-WHERE invariant: every search MUST include an indexed column AND a time window — " _
            "never issue an unbounded scan. Return curated lists (typically 5–20 hits), not large dumps; " _
            "favor click-through over verbose summaries so the operator can drill into the Visual Trace " _
            "for full context."
    }
    Quit ""
}

/// <p>Returns a populated <i>un-saved</i>
/// <CLASS>SessionAgent.Config.Agent</CLASS> instance with the OD4 default
/// shape. The caller (Installer) calls <method>%Save</method> and checks
/// the returned <code>%Status</code>.</p>
///
/// <p>Returns <code>$$$NULLOREF</code> for any unknown
/// <var>pAgentName</var>.</p>
ClassMethod GetSeedConfig(pAgentName As %String) As SessionAgent.Config.Agent
{
    If (pAgentName '= "session-inspection") && (pAgentName '= "message-search") {
        Quit $$$NULLOREF
    }

    Set tAgent = ##class(SessionAgent.Config.Agent).%New()
    Set tAgent.AgentName = pAgentName
    Set tAgent.Provider = "openai"
    Set tAgent.Model = "gpt-4.1-mini"
    ; Hyperscaler-class default (Manual-test 2026-05-06): 4096 was an
    ; Ollama-class holdover that silently truncated mid-response on
    ; tool-call-heavy turns against gpt-4.1 / claude-sonnet-4-5 /
    ; gemini-2.5-pro. 32000 matches the AC-1 form validator cap and
    ; covers practical hyperscaler answer lengths. The Story 6.1 form's
    ; providerChanged() handler downshifts to 4096 if the operator
    ; switches provider to openai-compatible (Ollama / vLLM tier).
    Set tAgent.MaxTokens = 32000
    Set tAgent.Temperature = 0.0
    Set tAgent.SystemPromptOverride = ""
    Set tAgent.CredentialName = ""
    Set tAgent.EnvVarName = "OPENAI_API_KEY"
    Set tAgent.EndpointUrl = ""
    Set tAgent.ReadOnly = 1
    Set tAgent.Enabled = 0
    Set tAgent.SearchChatRetentionDays = 30
    Quit tAgent
}

}
