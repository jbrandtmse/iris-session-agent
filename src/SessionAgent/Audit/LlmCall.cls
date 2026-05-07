/// <p>Audit row for one LLM provider round-trip — request issued, response
/// received (or error raised). One row per <method>SessionAgent.Audit.Emit.LogLlmCall</method>
/// invocation; the AgentLoop calls <code>LogLlmCall</code> exactly once per
/// LLM request, so the per-request count is also the row count (NFR-S4 100%
/// completeness — N invocations → N rows; never silently dropped).</p>
///
/// <p><b>FR contract.</b> Implements the LLM half of FR32 / FR33 / FR34
/// (per-call telemetry: provider, model, token usage, latency, stop reason,
/// error, optional cache-hit accounting). Operators query this table via
/// the recipes in <a href="../../docs/audit-sql-recipes.md">audit-sql-recipes.md</a>
/// — no separate audit UI exists (FR35, NFR-O3).</p>
///
/// <p><b>NFR-S3 — credential safety.</b> The <property>ErrorText</property>
/// property carries operator-readable failure context (status text + tail of
/// stack trace). It must NEVER carry API key material. The
/// <method>SessionAgent.Audit.Emit.LogLlmCall</method> caller is responsible
/// for passing only redacted text; this row class does not perform redaction
/// itself (the LLM call has no caller-supplied JSON payload that could leak
/// keys — provider headers are managed inside the LLM adapter).</p>
///
/// <p><b>FK shape.</b> <property>ChatHistoryId</property> holds the row ID
/// of the parent <code>SessionAgent.Chat.History</code> row as a
/// <code>%String</code>. Story 2.6 introduces the <code>Chat.History</code>
/// class; this story uses <code>%String</code> (not a typed reference) to
/// avoid a forward compile dependency on a class that does not yet exist.
/// Story 2.6 may add a calculated property or relationship to navigate the
/// link without changing this storage shape.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.5</a> (lines 823–860) — AC source.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// row at line 236 — audit persistence row shape.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR32–FR34, NFR-S3, NFR-S4.</li>
/// <li><a href="../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a>
/// §"Timestamp and Encoding Standards", §"Write Status Checking".</li>
/// </ul>
Class SessionAgent.Audit.LlmCall Extends %Persistent
{

/// <p>ISO-8601 UTC timestamp of the request (or completion). Built by the
/// caller via
/// <code>$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"</code> — UTC
/// because of the trailing <code>Z</code>. <code>$ZTimeStamp</code> is UTC;
/// using <code>$Horolog</code> would produce semantically wrong values on
/// non-UTC servers (project rule §"Timestamp and Encoding Standards").</p>
Property Timestamp As %String;

/// <p>Foreign key to <code>SessionAgent.Chat.History</code> (row ID, stored
/// as a string). Story 2.6 ships the <code>Chat.History</code> class; this
/// story uses <code>%String</code> to avoid a forward dependency. See class
/// doc-comment for the rationale.</p>
Property ChatHistoryId As %String;

/// <p>LLM provider key. Values: <code>openai</code>, <code>anthropic</code>,
/// <code>gemini</code>, <code>openai-compatible</code>. Matches the
/// <code>SessionAgent.Config.Agent.Provider</code> column so cross-table
/// joins work without translation.</p>
Property Provider As %String;

/// <p>Provider model identifier (e.g., <code>gpt-4.1-mini</code>,
/// <code>claude-sonnet-4-5</code>). Free-form pass-through from
/// <code>SessionAgent.Config.Agent.Model</code>.</p>
Property Model As %String;

/// <p>Number of messages in the request (system + user + assistant turns
/// the AgentLoop assembled before posting). Used by the recipe for the
/// "what's our average prompt size?" report.</p>
Property RequestMessageCount As %Integer;

/// <p>Provider-reported prompt-token count for the request (input tokens).
/// Source: provider response usage block. Used for the "tokens spent
/// yesterday" recipe.</p>
Property RequestTokens As %Integer;

/// <p>Provider-reported completion-token count for the response (output
/// tokens). Source: provider response usage block.</p>
Property ResponseTokens As %Integer;

/// <p>Wall-clock latency from request issue to response receipt, in
/// milliseconds. Computed by the AgentLoop wrapper around the provider
/// call. Used by the "p95 latency" / "any timeouts today?" recipes.</p>
Property LatencyMs As %Integer;

/// <p>Provider-reported stop reason for the response. Common values:
/// <code>stop</code>, <code>length</code>, <code>tool_use</code>,
/// <code>error</code>. Free-form string — the provider key universe is
/// open and we don't enforce a closed enum.</p>
Property StopReason As %String;

/// <p>Anthropic prompt-cache reporting — number of input tokens served
/// from the prompt cache (zero when cache miss or when the provider does
/// not report a cache layer). Defaults to <code>0</code> for providers
/// without a cache reporting (OpenAI, Gemini, Ollama-compatible).</p>
Property CacheHitTokens As %Integer [ InitialExpression = 0 ];

/// <p>Set to <code>1</code> when the LLM call failed (transport error,
/// provider-returned error envelope, or timeout). When <code>1</code>,
/// <property>ErrorText</property> carries the human-readable detail.</p>
Property IsError As %Boolean [ InitialExpression = 0 ];

/// <p>Operator-readable error message + stack-trace tail when
/// <property>IsError</property> is <code>1</code>. NEVER contains API key
/// material (NFR-S3) — caller is responsible for passing only redacted
/// text. <code>MAXLEN=4096</code> accommodates a multi-line stack-trace
/// tail without forcing a stream backing store.</p>
Property ErrorText As %String(MAXLEN = 4096);

/// <p>Index on <property>ChatHistoryId</property> — added in Story 7.2 to
/// support the <code>SessionAgent.Task.PurgeOrphanedChatHistory</code>
/// sweep's per-orphan
/// <code>DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?</code>
/// (Story 7.1 Option B audit-cascade implementation). Without this index the
/// sweep degrades to a full audit-table scan per orphan; with it the DELETE
/// is O(log n). Story 7.3's 1,000-session integration test exercises the
/// indexed path. Storage section is auto-generated per project rule
/// "Storage Sections" — do NOT hand-edit the Storage block to reflect this
/// index; the compiler maintains it.</p>
Index ChatHistoryIdIdx On ChatHistoryId;

Storage Default
{
<Data name="LlmCallDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Timestamp</Value>
</Value>
<Value name="3">
<Value>ChatHistoryId</Value>
</Value>
<Value name="4">
<Value>Provider</Value>
</Value>
<Value name="5">
<Value>Model</Value>
</Value>
<Value name="6">
<Value>RequestMessageCount</Value>
</Value>
<Value name="7">
<Value>RequestTokens</Value>
</Value>
<Value name="8">
<Value>ResponseTokens</Value>
</Value>
<Value name="9">
<Value>LatencyMs</Value>
</Value>
<Value name="10">
<Value>StopReason</Value>
</Value>
<Value name="11">
<Value>CacheHitTokens</Value>
</Value>
<Value name="12">
<Value>IsError</Value>
</Value>
<Value name="13">
<Value>ErrorText</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.Audit.LlmCallD</DataLocation>
<DefaultData>LlmCallDefaultData</DefaultData>
<IdLocation>^SessionAgent.Audit.LlmCallD</IdLocation>
<IndexLocation>^SessionAgent.Audit.LlmCallI</IndexLocation>
<StreamLocation>^SessionAgent.Audit.LlmCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
