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
            "Ens.MessageHeader row, not the SessionId. " _
            "Ensemble domain knowledge: error / failed responses on Business Operations commonly have NULL or empty message bodies — this is normal and not a finding. Focus diagnostic narrative on event log entries, error text, BP rule decisions, and the routing path. Do not surface absent error-response bodies as suspicious unless the operator specifically asks about them."
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

/// <p><b>Story 10.11.</b> Returns the per-provider canonical default
/// triple (Model, CredentialName, EnvVarName, EndpointUrl) as a
/// <CLASS>%DynamicObject</CLASS>. Used by
/// <CLASS>SessionAgent.UI.AgentConfig</CLASS>'s
/// <method>onChangeProvider</method> client-side cascade to populate the
/// dependent form fields when the operator rotates Provider — without
/// this cascade the form persists an incoherent (Provider, Model,
/// CredentialName) triple on Save (the originating Story 10.11 quirk).</p>
///
/// <p>Returned shape (every key always present, empty-string fallback
/// for the openai-compatible row whose "canonical" defaults are
/// operator-supplied):</p>
/// <pre>
/// {
///   "model": "<provider-canonical model name>",
///   "credentialName": "<canonical Ens.Config.Credentials entry>",
///   "envVarName": "<canonical OS env-var name>",
///   "endpointUrl": "<canonical endpoint URL or empty>"
/// }
/// </pre>
///
/// <p><b>Per-provider canonical values</b> (verified current as of
/// 2026-05-08 — sources cited in <code>README.md</code> §"Provider
/// support" and <code>_bmad-output/implementation-artifacts/epic-5-operator-state.md</code>):</p>
///
/// <ul>
/// <li><b>openai</b> — model <code>gpt-4.1-mini</code> + cred
/// <code>SessionAgentOpenAI</code> + env <code>OPENAI_API_KEY</code></li>
/// <li><b>anthropic</b> — model <code>claude-haiku-4-5-20251001</code>
/// (per Story 5.1 Rule 10 research; cost-effective tool-use default) +
/// cred <code>SessionAgentAnthropic</code> + env <code>ANTHROPIC_API_KEY</code></li>
/// <li><b>gemini</b> — model <code>gemini-2.5-flash</code> (per README
/// pricing table) + cred <code>SessionAgentGemini</code> + env
/// <code>GEMINI_API_KEY</code></li>
/// <li><b>openai-compatible</b> — model <code>qwen2.5:32b</code> (Ollama
/// default per Story 10.13 Rule 10 verification 2026-05-08; mid-tier
/// tool-calling default per Perplexity research — Llama3.3:70B is the
/// stronger alternative, qwen2.5:32b is faster on operator hardware) +
/// empty cred (operator-supplied; Ens.Config.Credentials rotation is
/// rare for local-Ollama) + env <code>OLLAMA_API_KEY</code> (conventional
/// even for unauthenticated local Ollama — operator may set it to a
/// dummy "OLLAMA" value) + endpoint
/// <code>http://localhost:11434/v1</code> (canonical Ollama OpenAI-
/// compatible endpoint per Perplexity research)</li>
/// </ul>
///
/// <p><b>Story 10.13 F-3.</b> The openai-compatible defaults pre-Story 10.13
/// were ALL empty — the AgentConfig form's onChangeProvider cascade
/// populated empty strings into endpointUrl + envVarName, which the
/// SaveAgentConfig validator (Rules 5 + 7) then rejected with two
/// field errors. Verified-current defaults (per Perplexity research
/// 2026-05-08) populate sensible Ollama values so the operator can
/// rotate to openai-compatible and click Save without first re-typing
/// the canonical endpoint + env-var name.</p>
///
/// <p><b>Unknown provider name</b> returns the openai-canonical triple as
/// the safe defaulting shape — the same fallthrough <method>LoadAgentConfig</method>
/// uses for the "no row exists" case. The Story 10.11 form-side caller
/// validates pProvider against the four known values before invoking, so
/// the unknown branch is defense-in-depth only.</p>
ClassMethod GetCanonicalDefaults(pProvider As %String) As %DynamicObject
{
    Set tObj = ##class(%DynamicObject).%New()
    If pProvider = "anthropic" {
        Do tObj.%Set("model", "claude-haiku-4-5-20251001")
        Do tObj.%Set("credentialName", "SessionAgentAnthropic")
        Do tObj.%Set("envVarName", "ANTHROPIC_API_KEY")
        Do tObj.%Set("endpointUrl", "")
    } ElseIf pProvider = "gemini" {
        Do tObj.%Set("model", "gemini-2.5-flash")
        Do tObj.%Set("credentialName", "SessionAgentGemini")
        Do tObj.%Set("envVarName", "GEMINI_API_KEY")
        Do tObj.%Set("endpointUrl", "")
    } ElseIf pProvider = "openai-compatible" {
        ; Story 10.13 F-3 — Ollama-flavored canonical defaults. Per
        ; Perplexity Rule-10 research (2026-05-08): qwen2.5:32b for
        ; mid-tier tool-calling, http://localhost:11434/v1 canonical
        ; Ollama endpoint, OLLAMA_API_KEY conventional env-var name
        ; (set to a dummy value if Ollama runs unauthenticated).
        Do tObj.%Set("model", "qwen2.5:32b")
        Do tObj.%Set("credentialName", "")
        Do tObj.%Set("envVarName", "OLLAMA_API_KEY")
        Do tObj.%Set("endpointUrl", "http://localhost:11434/v1")
    } Else {
        ; openai canonical (also the unknown-fallthrough safe default).
        Do tObj.%Set("model", "gpt-4.1-mini")
        Do tObj.%Set("credentialName", "SessionAgentOpenAI")
        Do tObj.%Set("envVarName", "OPENAI_API_KEY")
        Do tObj.%Set("endpointUrl", "")
    }
    Quit tObj
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
