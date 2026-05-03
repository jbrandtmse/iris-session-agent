/// <p>Typed wrapper for one LLM provider call's response. Returned by
/// <method>SessionAgent.LLM.Provider.CallMessages</method> (Story 2.8)
/// and consumed by the AgentLoop (Story 2.12). Pure data carrier — no
/// business logic.</p>
///
/// <p><b>Shape (Story 2.7 AC-2).</b></p>
/// <ul>
/// <li><property>Content</property> — canonical Anthropic content
/// array of <code>{type: "text" | "tool_use", ...}</code> blocks.</li>
/// <li><property>StopReason</property> — one of <code>end_turn</code>,
/// <code>max_tokens</code>, <code>stop_sequence</code>,
/// <code>tool_use</code>.</li>
/// <li><property>Usage</property> — token-accounting object
/// <code>{input_tokens, output_tokens, cache_creation_input_tokens,
/// cache_read_input_tokens}</code>.</li>
/// </ul>
///
/// <p><b>Base.</b> <CLASS>%RegisteredObject</CLASS> — transient
/// request-scoped data carrier; never stored as a standalone row.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.7</a> (lines 891–915) — AC source.</li>
/// </ul>
Class SessionAgent.Agent.ProviderResponse Extends %RegisteredObject
{

/// <p>Canonical Anthropic content array of
/// <code>{type: "text" | "tool_use", ...}</code> blocks. Held as a
/// <CLASS>%DynamicArray</CLASS> so callers can iterate blocks without
/// re-parsing JSON.</p>
Property Content As %DynamicArray;

/// <p>Provider stop reason. Values: <code>end_turn</code>,
/// <code>max_tokens</code>, <code>stop_sequence</code>,
/// <code>tool_use</code>.</p>
Property StopReason As %String;

/// <p>Token-accounting object
/// <code>{input_tokens, output_tokens, cache_creation_input_tokens,
/// cache_read_input_tokens}</code>. Held as a
/// <CLASS>%DynamicObject</CLASS> for direct field access by the
/// usage-rollup logic in <CLASS>SessionAgent.Agent.AgentLoop</CLASS>
/// (Story 2.12).</p>
Property Usage As %DynamicObject;

}
