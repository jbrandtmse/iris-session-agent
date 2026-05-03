/// <p>Value-object representing one turn in a conversation. NOT a
/// persistent class — turns are serialized inside the parent
/// <CLASS>SessionAgent.Chat.History</CLASS>'s
/// <property>TurnsJson</property> stream as a JSON array of canonical
/// Anthropic-shape turn objects, never as standalone rows. This class
/// exists so that ObjectScript code (the AgentLoop, tests) can
/// manipulate one turn as a typed in-memory object before
/// re-serializing the whole array back to the stream.</p>
///
/// <p><b>Canonical Anthropic shape.</b>
/// <code>{"role": "user|assistant|tool", "content": [...], "usage":
/// {...}}</code>. The <property>ContentJson</property> property holds
/// the JSON serialization of the <code>content</code> array
/// (<code>[{"type": "text", "text": "..."}]</code>,
/// <code>[{"type": "tool_use", ...}]</code>,
/// <code>[{"type": "tool_result", ...}]</code>). The
/// <property>UsageJson</property> property holds the optional
/// <code>usage</code> sub-object
/// (<code>{"input_tokens", "output_tokens",
/// "cache_creation_input_tokens", "cache_read_input_tokens"}</code>) or
/// the empty string when the provider did not return usage.</p>
///
/// <p><b>Round-trip helpers.</b> <method>ToCanonical</method> projects a
/// <CLASS>Turn</CLASS> instance into a
/// <CLASS>%DynamicObject</CLASS> ready for inclusion in the parent
/// <property>TurnsJson</property> array; <method>FromCanonical</method>
/// parses such a <CLASS>%DynamicObject</CLASS> back into a
/// <CLASS>Turn</CLASS> instance. The two methods are inverses for any
/// Anthropic-shape turn.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.6</a> (lines 861–889) — AC source.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// line 235 — class file location.</li>
/// </ul>
Class SessionAgent.Chat.Turn Extends %RegisteredObject
{

/// <p>Anthropic role for the turn. Values: <code>user</code>,
/// <code>assistant</code>, or <code>tool</code>.</p>
Property Role As %String;

/// <p>JSON serialization of the canonical
/// <code>content</code> array
/// (<code>[{"type":"text","text":"..."}]</code>,
/// <code>[{"type":"tool_use", ...}]</code>, etc.).
/// <code>MAXLEN=65536</code> accommodates a long single-turn
/// transcript (e.g., a verbose tool-result payload) without forcing a
/// stream backing store on the per-turn value object — the parent
/// <property>TurnsJson</property> on
/// <CLASS>SessionAgent.Chat.History</CLASS> is already a stream and
/// absorbs the cumulative volume.</p>
Property ContentJson As %String(MAXLEN = 65536);

/// <p>Optional JSON serialization of the
/// <code>usage</code> sub-object
/// (<code>{"input_tokens", "output_tokens",
/// "cache_creation_input_tokens", "cache_read_input_tokens"}</code>).
/// Empty string when the provider did not return usage. Only
/// assistant-role turns typically carry usage; user/tool turns leave
/// this empty.</p>
Property UsageJson As %String(MAXLEN = 2048);

/// <p>Project a <CLASS>Turn</CLASS> instance into a canonical
/// Anthropic-shape <CLASS>%DynamicObject</CLASS> ready for inclusion
/// in <CLASS>SessionAgent.Chat.History</CLASS>'s
/// <property>TurnsJson</property> array. <code>content</code> is
/// always emitted as a parsed <CLASS>%DynamicArray</CLASS>;
/// <code>usage</code> is emitted only when
/// <property>UsageJson</property> is non-empty (so the round-trip
/// preserves "no usage" semantics — consumers can distinguish
/// "absent" from "empty object").</p>
ClassMethod ToCanonical(pTurn As SessionAgent.Chat.Turn) As %DynamicObject
{
    Set tObj = ##class(%DynamicObject).%New()
    Set tObj.role = pTurn.Role
    ; content is always parsed; an empty ContentJson becomes [] or {}
    ; depending on caller — default to empty array if blank.
    If pTurn.ContentJson = "" {
        Set tObj.content = ##class(%DynamicArray).%New()
    } Else {
        Set tObj.content = {}.%FromJSON(pTurn.ContentJson)
    }
    ; usage is optional — only emitted when present.
    If pTurn.UsageJson '= "" {
        Set tObj.usage = {}.%FromJSON(pTurn.UsageJson)
    }
    Quit tObj
}

/// <p>Parse a canonical Anthropic-shape
/// <CLASS>%DynamicObject</CLASS> back into a typed
/// <CLASS>Turn</CLASS> instance. Missing <code>usage</code> key
/// produces an empty <property>UsageJson</property> string
/// (round-trip-safe with <method>ToCanonical</method>'s
/// "omit-when-empty" emission).</p>
ClassMethod FromCanonical(pCanonicalTurnObj As %DynamicObject) As SessionAgent.Chat.Turn
{
    Set tTurn = ..%New()
    Set tTurn.Role = pCanonicalTurnObj.role
    ; content -> ContentJson via ToJSON. content may be missing on a
    ; degenerate canonical turn — serialize to empty array in that case.
    If pCanonicalTurnObj.%IsDefined("content") {
        Set tTurn.ContentJson = pCanonicalTurnObj.content.%ToJSON()
    } Else {
        Set tTurn.ContentJson = "[]"
    }
    ; usage is optional — absent key -> empty string.
    If pCanonicalTurnObj.%IsDefined("usage") {
        Set tTurn.UsageJson = pCanonicalTurnObj.usage.%ToJSON()
    } Else {
        Set tTurn.UsageJson = ""
    }
    Quit tTurn
}

}
