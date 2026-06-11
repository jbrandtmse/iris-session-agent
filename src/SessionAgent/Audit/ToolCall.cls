/// <p>Audit row for one tool dispatch — agent invoked a registered tool,
/// received a result (or error). One row per
/// <method>SessionAgent.Audit.Emit.LogToolCall</method> invocation; the
/// AgentLoop calls <code>LogToolCall</code> exactly once per tool-call turn,
/// so the per-call count is also the row count (NFR-S4 100% completeness).</p>
///
/// <p><b>FR contract.</b> Implements the tool half of FR32 / FR33 / FR34.
/// Operators query this table via the recipes in
/// <a href="../../docs/audit-sql-recipes.md">audit-sql-recipes.md</a>
/// (FR35, NFR-O3). Search-agent dispatches additionally populate
/// <property>ResultSetSize</property> / <property>QueryTemplate</property> /
/// <property>IndexUsed</property> for the search-tool-specific recipes.</p>
///
/// <p><b>NFR-S3 — credential safety via redaction.</b>
/// <property>ArgsJson</property> and <property>ResultJson</property> are
/// JSON strings the agent passed to / received from the tool. They MAY
/// contain credential-like keys (operator-supplied tool args; tool
/// implementations that surface back-end secrets). The
/// <method>SessionAgent.Audit.Emit.LogToolCall</method> caller MUST redact
/// both via
/// <method>SessionAgent.Util.Json.Redact</method> with the project-standard
/// key list (<code>api_key,Authorization,authorization,password,secret,bearer,access_token</code>)
/// BEFORE the row is persisted. The tests in
/// <CLASS>SessionAgent.Test.AuditTest</CLASS> assert the literal credential
/// material does not appear in the persisted row.</p>
///
/// <p><b>FK shape.</b> Same as <CLASS>SessionAgent.Audit.LlmCall</CLASS> —
/// <property>ChatHistoryId</property> stores the parent
/// <code>SessionAgent.Chat.History</code> row ID as a <code>%String</code>
/// (forward-dependency avoidance; Story 2.6 ships
/// <code>Chat.History</code>).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.5</a> (lines 823–860) — AC source.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// row at line 236 — audit persistence row shape.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR32–FR35, NFR-S3, NFR-S4.</li>
/// </ul>
Class SessionAgent.Audit.ToolCall Extends %Persistent
{

/// <p>ISO-8601 UTC timestamp of the tool dispatch. Built per project rule
/// §"Timestamp and Encoding Standards":
/// <code>$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"</code>.</p>
Property Timestamp As %String;

/// <p>Foreign key to <code>SessionAgent.Chat.History</code> (row ID). See
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> for the
/// <code>%String</code>-not-typed-reference rationale (forward dependency
/// on Story 2.6).</p>
Property ChatHistoryId As %String;

/// <p>Tool name. Examples: <code>session_summary</code>,
/// <code>find_related_sessions</code>, <code>find_sessions_by_body</code>.
/// Used as the <code>Name</code> dimension of the
/// <code>(SessionAgent, ToolCall, &lt;ToolName&gt;)</code> triple in
/// <code>%SYS Security.Events</code> registry. Lazy-registered on first
/// emit per tool by
/// <method>SessionAgent.Audit.Emit.RegisterIfMissing</method>.</p>
Property ToolName As %String;

/// <p>JSON string of the args the agent passed to the tool — REDACTED via
/// <method>SessionAgent.Util.Json.Redact</method> before this row was
/// persisted. <code>MAXLEN=32768</code> (parity with
/// <property>ResultJson</property>) accommodates a non-trivial Mango
/// selector, a vocabulary-keys array, or — since Story 14.3 — the
/// free-text <code>sql</code> arg of <code>execute_readonly_sql</code>,
/// the first tool whose primary arg is unbounded operator/LLM-authored
/// SQL. Before Story 14.3 every tool carried small structured args that
/// never approached the prior <code>8192</code> ceiling; a >8 KB SQL
/// query executed but its audit row silently failed to persist
/// (<code>%Save</code> DATATYPE overflow swallowed by the Dispatch
/// audit-emit path), violating FR60 100% ToolCall audit. Bumped to
/// close that reachable gap (Story 14.3 review fix cr-14-3-C).</p>
Property ArgsJson As %String(MAXLEN = 32768);

/// <p>JSON string of the result the tool returned — REDACTED via the same
/// helper. <code>MAXLEN=32768</code> accommodates a 50-row session-summary
/// payload (typical search-agent result envelope).</p>
Property ResultJson As %String(MAXLEN = 32768);

/// <p>Wall-clock latency from dispatch issue to result receipt, in
/// milliseconds.</p>
Property LatencyMs As %Integer;

/// <p>Set to <code>1</code> when the tool dispatch failed (validation
/// error, tool runtime exception, downstream-service timeout).</p>
Property IsError As %Boolean [ InitialExpression = 0 ];

/// <p>Operator-readable error context when
/// <property>IsError</property> is <code>1</code>. Caller's responsibility
/// to keep credential-clean (NFR-S3).</p>
Property ErrorText As %String(MAXLEN = 4096);

/// <p>Number of result rows produced by the tool — populated only for
/// search-agent dispatches where the row count is meaningful (and is the
/// principal "did the tool find anything?" signal). Nullable; LLM-only
/// tools leave this empty.</p>
Property ResultSetSize As %Integer;

/// <p>Search-agent enrichment — the symbolic query template that drove
/// this dispatch (e.g., <code>SearchByBody:WHERE PatientId=?</code>).
/// Nullable; non-search tools leave empty. <code>MAXLEN=2048</code> covers
/// the longest expected template string.</p>
Property QueryTemplate As %String(MAXLEN = 2048);

/// <p>Search-agent enrichment — the IRIS index name the search tool's
/// query plan used (per the bounded-WHERE invariant audit). Nullable;
/// non-search tools leave empty.</p>
Property IndexUsed As %String;

/// <p>Index on <property>ChatHistoryId</property> — added in Story 7.2 to
/// support the <code>SessionAgent.Task.PurgeOrphanedChatHistory</code>
/// sweep's per-orphan
/// <code>DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?</code>
/// (Story 7.1 Option B audit-cascade implementation). Without this index the
/// sweep degrades to a full audit-table scan per orphan; with it the DELETE
/// is O(log n). Story 7.3's 1,000-session integration test exercises the
/// indexed path. Storage section is auto-generated per project rule
/// "Storage Sections" — do NOT hand-edit the Storage block to reflect this
/// index; the compiler maintains it.</p>
Index ChatHistoryIdIdx On ChatHistoryId;

Storage Default
{
<Data name="ToolCallDefaultData">
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
<Value>ToolName</Value>
</Value>
<Value name="5">
<Value>ArgsJson</Value>
</Value>
<Value name="6">
<Value>ResultJson</Value>
</Value>
<Value name="7">
<Value>LatencyMs</Value>
</Value>
<Value name="8">
<Value>IsError</Value>
</Value>
<Value name="9">
<Value>ErrorText</Value>
</Value>
<Value name="10">
<Value>ResultSetSize</Value>
</Value>
<Value name="11">
<Value>QueryTemplate</Value>
</Value>
<Value name="12">
<Value>IndexUsed</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.Audit.ToolCallD</DataLocation>
<DefaultData>ToolCallDefaultData</DefaultData>
<IdLocation>^SessionAgent.Audit.ToolCallD</IdLocation>
<IndexLocation>^SessionAgent.Audit.ToolCallI</IndexLocation>
<StreamLocation>^SessionAgent.Audit.ToolCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
