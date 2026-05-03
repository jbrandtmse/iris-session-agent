/// <p>Per-agent runtime configuration row, read by the AgentLoop on every
/// turn so an operator can change provider / model / token budget /
/// system-prompt-override / credential-ref / endpoint URL / enabled flag /
/// search-chat retention without restarting IRIS (NFR-O2 hot-config-change).</p>
///
/// <p><b>NFR-S2 schema discipline.</b> This class deliberately stores
/// <i>references</i> to credential material — <code>CredentialName</code>
/// (an entry in <code>Ens.Config.Credentials</code>) and
/// <code>EnvVarName</code> (an OS env-var key, typically
/// <code>OPENAI_API_KEY</code>) — and <b>NEVER the API key value itself</b>.
/// There is no <code>ApiKey</code> property on this class. Resolution at
/// runtime is delegated to <CLASS>SessionAgent.Util.EnvSecret</CLASS> which
/// walks the env-var → <code>Ens.Config.Credentials</code> → AES-stub
/// ladder. The schema-discipline check
/// <method>SessionAgent.Test.ConfigAgentTest.TestSchemaHasNoApiKey</method>
/// asserts that no <code>ApiKey</code> property has been added.</p>
///
/// <p><b>Seeding.</b> Two rows are inserted at install time by
/// <method>SessionAgent.Installer.SeedDefaultAgentConfigs</method> (Story
/// 2.4): <code>session-inspection</code> and <code>message-search</code>.
/// Both seed with <code>Enabled=0</code> so the operator must explicitly
/// opt in via the Story 6 Zen form before any agent is callable. Default
/// shape comes from
/// <method>SessionAgent.Config.AgentDefaults.GetSeedConfig</method>.</p>
///
/// <p><b>Lookup.</b> The unique <code>AgentNameIdx</code> index gives O(1)
/// lookup by <code>AgentName</code> via
/// <code>##class(SessionAgent.Config.Agent).AgentNameIdxOpen(name)</code>
/// or the dictionary-generated <code>AgentNameIdxExists(name)</code>
/// predicate the Installer uses for its idempotency check.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../planning-artifacts/epics.md">epics.md Story 2.4</a>
/// (lines 798–821) — AC source.</li>
/// <li><a href="../planning-artifacts/architecture.md">architecture.md</a>
/// row OD4 (line 308) — provider/model/seed defaults; class file path
/// (line 850).</li>
/// <li><a href="../planning-artifacts/prd.md">prd.md</a> NFR-S2 (line 602)
/// — credential-confinement schema discipline.</li>
/// </ul>
Class SessionAgent.Config.Agent Extends %Persistent
{

/// <p>Agent identifier. Values in v1: <code>session-inspection</code> and
/// <code>message-search</code>. The unique <code>AgentNameIdx</code> below
/// enforces single-row-per-agent.</p>
Property AgentName As %String;

/// <p>LLM provider key. Values: <code>openai</code>, <code>anthropic</code>,
/// <code>gemini</code>, <code>openai-compatible</code>. The Story 2.8/2.9
/// LLMProvider abstract dispatches on this value to choose a concrete
/// adapter.</p>
Property Provider As %String;

/// <p>Provider model identifier (e.g., <code>gpt-4.1-mini</code>). Free-form
/// string passed through to the provider; the abstract adapter does not
/// validate model names so operators can adopt new models without an
/// agent-side code change.</p>
Property Model As %String;

/// <p>Per-call max-tokens budget. The AgentLoop passes this to the
/// provider's request shape (e.g., OpenAI's <code>max_tokens</code>).</p>
Property MaxTokens As %Integer;

/// <p>Sampling temperature. v1 ships with <code>0.0</code> per OD4
/// (deterministic answers); operators tuning for more conversational tone
/// can raise via the Story 6 UI.</p>
Property Temperature As %Numeric;

/// <p>Optional override for the per-agent default system prompt that
/// <method>SessionAgent.Config.AgentDefaults.GetSystemPrompt</method>
/// returns. Empty by default (use the helper's default); when non-empty,
/// the AgentLoop substitutes this verbatim. <code>MAXLEN=8192</code>
/// accommodates richly tuned prompts without forcing a stream backing
/// store.</p>
Property SystemPromptOverride As %String(MAXLEN = 8192);

/// <p>Named entry in <code>Ens.Config.Credentials</code> the EnvSecret
/// resolver consults on rung 2 of its three-rung ladder. Empty by default
/// — operators using env-var rung (rung 1, 12-factor) leave this empty.</p>
Property CredentialName As %String;

/// <p>OS environment variable key the EnvSecret resolver consults on rung
/// 1. Default <code>OPENAI_API_KEY</code> for OpenAI-seeded agents; can be
/// overridden via the Story 6 UI when operators host the agent against an
/// OpenAI-compatible provider with a different env-var convention (e.g.,
/// <code>ANTHROPIC_API_KEY</code>).</p>
Property EnvVarName As %String;

/// <p>For <code>openai-compatible</code> providers (Ollama, vLLM,
/// Together, Anyscale, etc.), the base URL where the agent posts
/// completion requests. Empty for OpenAI / Anthropic / Gemini whose
/// concrete adapter knows the canonical endpoint.</p>
Property EndpointUrl As %String;

/// <p><b>L4 read-only invariant flag</b> (PRD NFR-S1, FR50). The tools
/// side checks this before any tool dispatch — when <code>1</code> (the
/// default), only inspection / search tools are reachable; any tool
/// declared as a writer is refused. Stays at <code>1</code> through v1;
/// reserved for future write-capable agents.</p>
Property ReadOnly As %Boolean [ InitialExpression = 1 ];

/// <p>Operator opt-in flag. Defaults to <code>0</code> so a fresh install
/// never auto-activates an agent — the operator opens the Story 6 Zen
/// form, supplies a working API key, then flips this to <code>1</code>.</p>
Property Enabled As %Boolean [ InitialExpression = 0 ];

/// <p>Days of search-agent chat history to retain before the Story 10.6
/// <code>PurgeStaleSearchChat</code> sweep deletes them. Defaults to
/// <code>30</code> per architecture row OD4. Only the
/// <code>message-search</code> agent seed value matters to the sweep —
/// the inspection-agent chat history is bound to the IRIS Production
/// session lifecycle (Story 7) and ignores this column.</p>
Property SearchChatRetentionDays As %Integer [ InitialExpression = 30 ];

/// <p>O(1) lookup by <code>AgentName</code>. The unique constraint
/// enforces single-row-per-agent, so the Installer's idempotency check
/// (<code>AgentNameIdxExists(name)</code>) is sufficient to prevent
/// duplicate seeding on re-install.</p>
Index AgentNameIdx On AgentName [ Unique ];

Storage Default
{
<Data name="AgentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>AgentName</Value>
</Value>
<Value name="3">
<Value>Provider</Value>
</Value>
<Value name="4">
<Value>Model</Value>
</Value>
<Value name="5">
<Value>MaxTokens</Value>
</Value>
<Value name="6">
<Value>Temperature</Value>
</Value>
<Value name="7">
<Value>SystemPromptOverride</Value>
</Value>
<Value name="8">
<Value>CredentialName</Value>
</Value>
<Value name="9">
<Value>EnvVarName</Value>
</Value>
<Value name="10">
<Value>EndpointUrl</Value>
</Value>
<Value name="11">
<Value>ReadOnly</Value>
</Value>
<Value name="12">
<Value>Enabled</Value>
</Value>
<Value name="13">
<Value>SearchChatRetentionDays</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.Config.AgentD</DataLocation>
<DefaultData>AgentDefaultData</DefaultData>
<IdLocation>^SessionAgent.Config.AgentD</IdLocation>
<IndexLocation>^SessionAgent.Config.AgentI</IndexLocation>
<StreamLocation>^SessionAgent.Config.AgentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
