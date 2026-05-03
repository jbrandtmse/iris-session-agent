/// <p>Per-turn caller-context DTO passed across the trust boundary
/// from the portal ZenMethod hyperevent into the AgentLoop, providers,
/// and tools. Captures who the caller is and which session/agent the
/// turn targets. Pure data carrier — no business logic.</p>
///
/// <p><b>Shape (Story 2.7 AC-1).</b></p>
/// <ul>
/// <li><property>AgentName</property> — <code>session-inspection</code>
/// or <code>message-search</code>.</li>
/// <li><property>IrisSessionId</property> — populated only for the
/// inspection agent; empty for the search agent.</li>
/// <li><property>SearchSessionKey</property> — populated only for the
/// search agent; empty for inspection.</li>
/// <li><property>PortalUser</property> — captured from
/// <code>$Username</code> at hyperevent dispatch.</li>
/// <li><property>Namespace</property> — passthrough only. Tools MUST
/// NEVER read <code>$NAMESPACE</code> directly per architecture
/// NFR-S6 (anti-pattern); they read this property instead.</li>
/// </ul>
///
/// <p><b>Base.</b> <CLASS>%RegisteredObject</CLASS>, NOT
/// <CLASS>%Persistent</CLASS> — DTOs are transient request-scoped data
/// carriers and are never stored as standalone rows.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.7</a> (lines 891–915) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// NFR-S6 — tools-never-read-$NAMESPACE anti-pattern.</li>
/// </ul>
Class SessionAgent.Agent.CallerContext Extends %RegisteredObject
{

/// <p>Agent identifier. Values: <code>session-inspection</code> or
/// <code>message-search</code>.</p>
Property AgentName As %String;

/// <p>IRIS Interoperability session id (numeric, stringified) for the
/// session-inspection agent. Empty string when
/// <property>AgentName</property> = <code>message-search</code>.</p>
Property IrisSessionId As %String;

/// <p>Synthetic search-session key for the message-search agent.
/// Empty string when <property>AgentName</property> =
/// <code>session-inspection</code>.</p>
Property SearchSessionKey As %String;

/// <p>Portal user identity captured from <code>$Username</code> at
/// hyperevent dispatch. Used for audit attribution.</p>
Property PortalUser As %String;

/// <p>Namespace the AgentLoop and tools operate against. Passthrough
/// only — tools must read this property and NEVER call
/// <code>$NAMESPACE</code> directly (architecture NFR-S6
/// anti-pattern).</p>
Property Namespace As %String;

/// <p>Row ID of the parent <CLASS>SessionAgent.Chat.History</CLASS>
/// instance for the in-flight turn. Set by
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> immediately
/// after <method>SessionAgent.Chat.History.LoadOrCreate</method>
/// returns the locked OREF, then read by
/// <method>SessionAgent.LLM.Provider.Invoke</method> and
/// <method>SessionAgent.Tool.Registry.Dispatch</method> when emitting
/// the <CLASS>SessionAgent.Audit.LlmCall</CLASS> /
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> rows so the FK
/// (<code>ChatHistoryId</code>) on each audit row references the
/// canonical <code>Chat.History</code> row identifier (Story 2.5
/// schema, FR34). Empty when the AgentLoop has not yet acquired the
/// chat-history row (e.g., the abstract Provider's credential-missing
/// fast path before any history exists).</p>
Property ChatHistoryId As %String;

}
