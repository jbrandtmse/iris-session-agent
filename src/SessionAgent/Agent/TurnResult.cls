/// <p>Typed result of one full AgentLoop turn (potentially many
/// provider calls + tool roundtrips). Returned by
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> (Story 2.12)
/// and serialized to JSON for the browser via
/// <method>ToJson</method>.</p>
///
/// <p><b>Shape (Story 2.7 AC-3).</b></p>
/// <ul>
/// <li><property>AssistantMarkdown</property> — final rendered
/// answer (markdown text); MAXLEN 65536.</li>
/// <li><property>UsageRollup</property> — turn-level token totals
/// summed across every provider call in the turn.</li>
/// <li><property>DurationMs</property> — wall-clock duration of the
/// turn, in milliseconds.</li>
/// <li><property>ToolCallsRendered</property> — per-card UI payloads
/// of <code>{name, args, result, status}</code> for browser
/// rendering of the tool-call audit trail beneath the assistant
/// answer.</li>
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
Class SessionAgent.Agent.TurnResult Extends %RegisteredObject
{

/// <p>Final rendered assistant answer in markdown. MAXLEN 65536
/// accommodates a long single-turn answer without forcing a stream
/// backing store on the per-turn DTO.</p>
Property AssistantMarkdown As %String(MAXLEN = 65536);

/// <p>Turn-level token totals summed across every provider call in
/// the turn. Same key-set as
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>'s
/// <property>Usage</property>:
/// <code>{input_tokens, output_tokens,
/// cache_creation_input_tokens, cache_read_input_tokens}</code>.</p>
Property UsageRollup As %DynamicObject;

/// <p>Wall-clock duration of the turn, in milliseconds.</p>
Property DurationMs As %Integer;

/// <p>Per-card UI payloads for browser rendering of the tool-call
/// audit trail beneath the assistant answer. Each element shape:
/// <code>{name, args, result, status}</code>.</p>
Property ToolCallsRendered As %DynamicArray;

/// <p>Build the JSON payload that the ZenMethod hyperevent returns
/// to the browser. Constructs a <CLASS>%DynamicObject</CLASS> with
/// keys <code>assistantMarkdown</code>, <code>usageRollup</code>,
/// <code>durationMs</code>, <code>toolCallsRendered</code> and
/// returns its <method>%ToJSON</method> string.</p>
///
/// <p>Empty <property>ToolCallsRendered</property> arrays are
/// preserved as <code>"toolCallsRendered":[]</code> in the output
/// (the JSON shape is stable for the browser-side renderer).</p>
Method ToJson() As %String
{
    Set tObj = ##class(%DynamicObject).%New()
    Set tObj.assistantMarkdown = ..AssistantMarkdown
    ; Default empty UsageRollup to {} so the browser always sees an
    ; object (never null) at this key.
    If $IsObject(..UsageRollup) {
        Set tObj.usageRollup = ..UsageRollup
    } Else {
        Set tObj.usageRollup = ##class(%DynamicObject).%New()
    }
    Set tObj.durationMs = ..DurationMs
    ; Default empty ToolCallsRendered to [] so the browser always
    ; sees an array (never null) at this key.
    If $IsObject(..ToolCallsRendered) {
        Set tObj.toolCallsRendered = ..ToolCallsRendered
    } Else {
        Set tObj.toolCallsRendered = ##class(%DynamicArray).%New()
    }
    Quit tObj.%ToJSON()
}

}
