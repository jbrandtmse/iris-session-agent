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

/// <p>Story 3.0 AC-2 helper — normalize an Ens ODBC TIMESTAMP string
/// (e.g. <code>"2026-05-03 19:30:45"</code> or
/// <code>"2026-05-03 19:30:45.123"</code>) to the canonical 20-character
/// ISO-8601 UTC Z form (<code>"2026-05-03T19:30:45Z"</code>) the audit
/// ledger and chat-panel renderer both expect. Truncates any
/// fractional-second tail before appending <code>Z</code>.</p>
///
/// <p><b>Why no <code>$ZDateTimeH</code> roundtrip:</b>
/// <CLASS>Ens.DataType.UTC</CLASS> stores values in UTC ODBC form
/// already (per <code>irislib/Ens/DataType/UTC.cls</code>). Going through
/// <code>$ZDateTimeH(value, 3, 1)</code> + <code>$ZDateTime(h, 3, 1)</code>
/// re-applies the same UTC interpretation and is more expensive than
/// string surgery, so the helper sticks to <code>$Translate</code> +
/// <code>$Extract</code>.</p>
///
/// <p>Empty input returns the empty string (degrades gracefully — a
/// row with no <code>TimeCreated</code> is malformed but should not
/// crash the tool).</p>
ClassMethod NormalizeIsoZ(pOdbcTimestamp As %String) As %String [ CodeMode = expression ]
{
$Select(pOdbcTimestamp="":"",1:$Translate($Extract(pOdbcTimestamp,1,19)," ","T")_"Z")
}

/// <p>Story 3.0 AC-2 helper — convert an ISO-8601 UTC Z input string
/// (<code>"2026-05-03T19:30:45Z"</code>) to the ODBC TIMESTAMP form
/// (<code>"2026-05-03 19:30:45"</code>) that
/// <code>%SQL.Statement.%Execute</code> binds against an
/// <CLASS>Ens.DataType.UTC</CLASS> column. Returns the empty string
/// for empty input. Returns the special sentinel <code>"INVALID"</code>
/// when the input does not parse as the canonical 20-char ISO-8601 UTC
/// Z form — callers detect this and surface a structured error envelope
/// per AC-2 ("from_time must be ISO-8601 UTC, e.g. 2026-05-03T19:30:00Z").</p>
///
/// <p><b>Validation rules.</b> Length exactly 20, char 11 must be
/// <code>'T'</code>, char 20 must be <code>'Z'</code>. Anything else
/// (no Z suffix, no T separator, sub-second precision, missing Z, etc.)
/// returns <code>"INVALID"</code>. The strictness matches the canonical
/// shape <CLASS>SessionAgent.Audit.LlmCall</CLASS> /
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> store and the form
/// <method>NormalizeIsoZ</method> emits.</p>
ClassMethod IsoZToOdbc(pIsoZ As %String) As %String
{
    If pIsoZ = "" Quit ""
    If $Length(pIsoZ) '= 20 Quit "INVALID"
    If $Extract(pIsoZ, 11) '= "T" Quit "INVALID"
    If $Extract(pIsoZ, 20) '= "Z" Quit "INVALID"
    ; Strip the Z, replace T with space.
    Quit $Translate($Extract(pIsoZ, 1, 19), "T", " ")
}

/// <p>Story 4.7 AC-7 helper (Story 4.5 R-4 closure) — strip IRIS-internal
/// prefixes from <code>pEx.DisplayString()</code> and return an
/// operator-friendly trailing message. Used uniformly by every concrete
/// inspection-tool's outer Catch block so the operator-readable
/// <code>content[0].text</code> never leaks raw stack-trace prefixes
/// while still surfacing the actual cause.</p>
///
/// <p><b>What we strip.</b>
/// <code>%Exception.AbstractException::DisplayString()</code> emits text
/// of the form <code>"ERROR #5002: ObjectScript error: &lt;UNDEFINED&gt;zMyMethod+12^MyClass.1 ^xVar"</code>.
/// The leading <code>"ERROR #&lt;num&gt;: ObjectScript error: "</code>
/// is internal noise — operators want the trailing
/// <code>&lt;UNDEFINED&gt; ^xVar</code> portion to feed into
/// <code>explain_error</code>. We also strip the deepest source-frame
/// suffix (<code>+&lt;line&gt;^&lt;routine&gt;.&lt;num&gt;</code>) which
/// is debug detail not useful to a non-developer operator. The full
/// <code>DisplayString()</code> still flows to
/// <code>SessionAgent.Audit.ToolCall.ErrorText</code> via
/// <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch — operator-text and
/// audit-text deliberately diverge here per architecture line 476.</p>
///
/// <p><b>Defensive degradation.</b> If the input is the empty string
/// (defensive — should never happen given the Catch contract) or the
/// regex/extract logic fails, return the original
/// <code>DisplayString()</code> unchanged. Better to leak a stack frame
/// than to lose the cause.</p>
ClassMethod FormatExceptionForOperator(pEx As %Exception.AbstractException) As %String
{
    Set tRaw = ""
    Try {
        If '$IsObject($Get(pEx)) Quit
        Set tRaw = pEx.DisplayString()
    }
    Catch innerEx {
        Set tRaw = ""
    }
    If tRaw = "" Quit ""
    Set tStripped = tRaw

    ; ---- Strip leading "ERROR #<num>: ObjectScript error: " noise. ----
    Set tMarker = "ObjectScript error: "
    Set tIdx = $Find(tStripped, tMarker)
    If tIdx > 0 {
        Set tStripped = $Extract(tStripped, tIdx, *)
    } Else {
        ; Some exceptions emit "ERROR #<num>: <message>" without the
        ; "ObjectScript error:" infix — strip the leading "ERROR #<num>: "
        ; tag in that case.
        If $Extract(tStripped, 1, 7) = "ERROR #" {
            Set tColon = $Find(tStripped, ": ")
            If tColon > 0 {
                Set tStripped = $Extract(tStripped, tColon, *)
            }
        }
    }

    ; ---- Strip trailing "+<line>^<routine>.<num> <hint>" frame suffix. ----
    ; Pattern is the form "<UNDEFINED>zMyMethod+12^MyPackage.MyClass.1 ^xVar".
    ; We want to keep the leading "<UNDEFINED>...zMyMethod" and the trailing
    ; " ^xVar" hint, but drop the "+12^MyPackage.MyClass.1" debug suffix.
    ; Find the FIRST "+" after the closing ">" of the error tag and remove
    ; up to the next space (which separates the frame from the hint).
    ; $Find returns the position immediately AFTER the closing ">", so
    ; tCloseTag-1 is the position OF ">". To preserve the ">" in the
    ; emitted operator text we slice [1..tCloseTag-1] (inclusive on the
    ; ">"), then append everything-after-the-">" minus the frame suffix.
    Set tCloseTag = $Find(tStripped, ">")
    If tCloseTag > 0 {
        Set tTail = $Extract(tStripped, tCloseTag, *)
        Set tPlusIdx = $Find(tTail, "+")
        If tPlusIdx > 0 {
            Set tBeforePlus = $Extract(tTail, 1, tPlusIdx - 2)
            Set tAfterPlus = $Extract(tTail, tPlusIdx - 1, *)
            ; Find the first space terminating the frame suffix.
            Set tSpaceIdx = $Find(tAfterPlus, " ")
            If tSpaceIdx > 0 {
                Set tHint = $Extract(tAfterPlus, tSpaceIdx - 1, *)
                Set tStripped = $Extract(tStripped, 1, tCloseTag - 1) _ tBeforePlus _ tHint
            } Else {
                ; No trailing space — the frame suffix runs to end of string. Drop it entirely.
                Set tStripped = $Extract(tStripped, 1, tCloseTag - 1) _ tBeforePlus
            }
        }
    }

    ; Defensive — if our stripping produced empty output, fall back to the raw text.
    If $ZStrip(tStripped, "<>W") = "" Quit tRaw
    Quit tStripped
}

}
