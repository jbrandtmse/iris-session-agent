/// <p>Abstract base class for all SessionAgent tools (Inspection +
/// Search). Concrete subclasses ship under <code>SessionAgent.Tool.Inspection.*</code>
/// (Epic 4) and <code>SessionAgent.Tool.Search.*</code> (Epic 8).</p>
///
/// <p><b>Contract (FR55–FR58, NFR-S6).</b> Every concrete subclass MUST:</p>
/// <ul>
/// <li>Override <parameter>ToolName</parameter> with the symbolic name
/// the LLM uses to invoke the tool (e.g., <code>session_summary</code>).</li>
/// <li>Override <parameter>Description</parameter> with a one-line
/// operator/LLM-readable summary used in MCP tool-list responses and
/// shown in the chat-panel citation chips.</li>
/// <li>Override <parameter>MutatesState</parameter> only if the tool
/// performs writes — v1 inspection + search tools all leave it at
/// <code>0</code>. <CLASS>SessionAgent.Tool.Registry</CLASS> Layer-2
/// enforcement (FR36, NFR-S1) rejects any dispatch where
/// <parameter>MutatesState=1</parameter>.</li>
/// <li>Implement <method>GetInputSchema</method> returning the locked JSON
/// Schema subset (architecture §"Tool input JSON Schema subset").</li>
/// <li>Implement <method>Invoke</method> returning the MCP envelope
/// (architecture §"MCP tool-result envelope") via the
/// <code>Output pResult</code> argument.</li>
/// </ul>
///
/// <p><b>Seven anti-patterns (FR55, NFR-S6, architecture §"Tool dispatch
/// contract").</b> A tool implementation MUST NOT:</p>
/// <ol>
/// <li>Read <code>%session.Data</code> or <code>%request.CgiEnvs</code>
/// from inside <method>Invoke</method>. Caller identity is in
/// <property>pCallerCtx.PortalUser</property>.</li>
/// <li>Assume the caller is a logged-in CSP/portal user. Tools must work
/// when invoked by a non-CSP context (future MCP server export).</li>
/// <li>Return HTML, redirects, or call <code>%CSP.Response.Write()</code>.
/// Output is JSON only via the <code>pResult</code> envelope.</li>
/// <li>Mutate ZenPage fields or rely on Zen page state. Tools have no
/// portal-page coupling.</li>
/// <li>Use ObjectScript exceptions to signal tool errors. Return
/// <code>{isError:1, content:[...]}</code> instead. Exceptions only
/// bubble up to <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch's
/// outer Catch as a defense-in-depth safety net.</li>
/// <li>Hardcode namespace via <code>$NAMESPACE</code>. Tools read
/// <property>pCallerCtx.Namespace</property> instead.</li>
/// <li>Stream output via <code>Write !,...</code> to the device. The
/// device is owned by the portal hyperevent dispatch, not the tool.</li>
/// </ol>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.10</a> (lines 991–1023) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Tool dispatch contract — seven anti-patterns" (lines 582–592),
/// §"MCP tool-result envelope" (lines 451–476),
/// §"Tool input JSON Schema subset" (lines 548–556),
/// §"Pattern Examples — canonical tool implementation skeleton"
/// (lines 688–746).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR36, FR55–FR58, NFR-S1, NFR-S6.</li>
/// </ul>
Class SessionAgent.Tool.Base Extends %RegisteredObject [ Abstract ]
{

/// <p>Symbolic tool name the LLM uses to invoke the tool (e.g.,
/// <code>session_summary</code>, <code>find_related_sessions</code>).
/// MUST be unique across all subclasses in a namespace —
/// <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch resolves
/// <code>pToolName</code> to a concrete class by scanning
/// <code>%Dictionary.ParameterDefinition</code> rows.</p>
Parameter ToolName As %String = "";

/// <p>One-line operator/LLM-readable summary surfaced in the MCP
/// tool-list response and the chat-panel citation chip tooltip.</p>
Parameter Description As %String = "";

/// <p>FR56 — declares whether the tool performs writes. v1 ships only
/// read-only tools; <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch
/// rejects any tool with <parameter>MutatesState=1</parameter> at
/// invocation time (FR36 / NFR-S1 Layer 2 enforcement). The parameter
/// exists so future write-capable tools (post-v1) can be declared
/// truthfully without retrofitting the registry contract.</p>
Parameter MutatesState As %Boolean = 0;

/// <p>Return the JSON Schema describing the tool's input. Concrete
/// subclasses author the schema literal inline (architecture pattern PD1
/// — no fluent builder).</p>
///
/// <p><b>Locked subset (architecture §"Tool input JSON Schema subset").</b>
/// Top level: <code>{type: "object", properties: {...}, required: [...],
/// additionalProperties: false}</code>. Property level:
/// <code>{type, description, enum?, items?, minimum?, maximum?,
/// minItems?, maxItems?}</code>. NEVER use <code>$ref</code>,
/// <code>oneOf</code>, <code>anyOf</code>, <code>allOf</code>,
/// <code>pattern</code>, exotic format keywords — cross-vendor
/// portability constraint.</p>
///
/// <p>Abstract method body returns an empty <code>%DynamicObject</code>;
/// per project rule §"Abstract Methods in ObjectScript" the curly-brace
/// body is REQUIRED for compilation even though concrete subclasses
/// always override.</p>
ClassMethod GetInputSchema() As %DynamicObject [ Abstract ]
{
    Quit {}
}

/// <p>Execute the tool. Concrete subclasses MUST set <code>pResult</code>
/// to either the MCP success envelope
/// <code>{content:[...], structuredContent:{...}}</code> or the MCP error
/// envelope <code>{isError:1, content:[{type:"text", text:"..."}]}</code>
/// (architecture §"MCP tool-result envelope").</p>
///
/// <p><b>Caller-context contract (NFR-S6).</b> Concrete tools read caller
/// identity from <property>pCallerCtx.PortalUser</property>, namespace
/// from <property>pCallerCtx.Namespace</property>, and session targeting
/// from <property>pCallerCtx.IrisSessionId</property> /
/// <property>pCallerCtx.SearchSessionKey</property>. They MUST NEVER
/// touch <code>%session</code>, <code>%request</code>, <code>$NAMESPACE</code>,
/// or any Zen page state directly.</p>
///
/// <p><b>Error contract.</b> Concrete tools should pre-surface validation
/// errors as <code>{isError:1, ...}</code> envelopes inside their own
/// Try/Catch and return <code>$$$OK</code>. Exceptions that escape are
/// caught by <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch's
/// outer-Catch safety net, which converts them to the same envelope
/// shape and stamps the stack trace into
/// <property>SessionAgent.Audit.ToolCall.ErrorText</property> only —
/// raw stack traces NEVER reach the operator-readable
/// <code>content[0].text</code>.</p>
///
/// <p>Abstract method body returns <code>$$$OK</code>; per project rule
/// §"Abstract Methods in ObjectScript" the curly-brace body is REQUIRED
/// for compilation even though concrete subclasses always override.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status [ Abstract ]
{
    Quit $$$OK
}

}
