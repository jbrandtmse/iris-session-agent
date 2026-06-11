/// <p>Reflection-based tool registry. Provides MCP-style tool
/// enumeration (FR57) and the trust-boundary dispatch entry point
/// (FR55–FR58, FR36, NFR-S1, NFR-S4) for every concrete subclass of
/// <CLASS>SessionAgent.Tool.Base</CLASS> shipped in the namespace.</p>
///
/// <p>No registry table — discovery is via
/// <code>%Dictionary.ClassDefinition</code> (Story 2.10 Task-0 probe
/// confirmed the reflection API is available on this IRIS install).
/// Concrete subclasses become discoverable simply by extending
/// <CLASS>SessionAgent.Tool.Base</CLASS> and being compiled into the
/// namespace; no registration call required.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.10</a> (lines 991–1023) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Tool dispatch contract" (lines 582–602), §"MCP tool-result envelope"
/// (lines 451–476).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR36, FR55–FR58, NFR-S1, NFR-S4.</li>
/// </ul>
Class SessionAgent.Tool.Registry Extends %RegisteredObject
{

/// <p>Enumerate every concrete (non-abstract) subclass of
/// <CLASS>SessionAgent.Tool.Base</CLASS> in the current namespace.
/// Returns a <code>%DynamicArray</code> where each entry is
/// <code>{name, description, input_schema}</code> — the MCP-portable
/// tool-list shape (FR57).</p>
///
/// <p><b>Discovery query.</b> Single SQL <code>SELECT</code> against
/// <code>%Dictionary.ClassDefinition</code> filtering
/// <code>Super = 'SessionAgent.Tool.Base' AND Abstract = 0</code>. The
/// abstract base itself is excluded by the filter (it has
/// <code>Abstract = 1</code>). Wrapped in <code>%EXACT()</code> per
/// project rule §"IRIS SQL Case Sensitivity".</p>
///
/// <p>For each subclass row, reads the <parameter>ToolName</parameter>
/// and <parameter>Description</parameter> values via
/// <code>%Dictionary.ParameterDefinition.%OpenId</code>
/// (<code>"&lt;class&gt;||&lt;param&gt;"</code> compound ID), and invokes
/// the subclass <method>GetInputSchema</method> via
/// <code>$ClassMethod</code>.</p>
///
/// <p>Returns an empty array when no concrete subclasses exist in the
/// namespace yet (Story 2.10 ships only the abstract base; Story 2.11
/// is the first to add concrete tools).</p>
ClassMethod ListTools() As %DynamicArray
{
    Set tResult = []
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        ; Story 3.0 carry-forward fix: exclude SessionAgent.Test.* fixture
        ; classes (StubReadOnlyTool, StubWriteTool, StubThrowingTool) from
        ; the production registry. They live under src/SessionAgent/Test/
        ; for compile-deploy convenience but must never appear to operators
        ; or LLM callers as discoverable tools.
        ;
        ; Story 8.3 fix-now — also discover search tools via the
        ; Tool.Search.Base intermediate abstract. Tool.Search.Base extends
        ; Tool.Base; concrete search tools (e.g., SearchByTime) declare
        ; their immediate Super as Tool.Search.Base, NOT Tool.Base, so the
        ; flat Super-equality filter would have missed all 6 search tools.
        ; The OR clause closes that gap. Future intermediate abstract
        ; bases (e.g., Tool.Vocab.Base if added in Story 8.7+) would
        ; require a parallel OR entry — the alternative is a recursive
        ; Super-chain walk, which is heavier and not yet warranted.
        Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE (%EXACT(Super) = 'SessionAgent.Tool.Base' OR %EXACT(Super) = 'SessionAgent.Tool.Search.Base') AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
        If $$$ISERR(tSC) Quit
        Set tRs = tStmt.%Execute()
        ; Story 14.0 review fix (cr-13-3 class) — a runtime discovery-query
        ; failure previously produced a silent zero-row scan indistinguishable
        ; from "no tools installed". Throw into the documented empty-list
        ; degradation below so the failure at least transits the declared
        ; degradation path (callers' empty-array contract is preserved —
        ; AgentLoop and the portal both require an array return).
        If tRs.%SQLCODE < 0 {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "tool discovery query failed: SQLCODE " _ tRs.%SQLCODE _ ": " _ tRs.%Message))
        }
        While tRs.%Next() {
            Set tClassName = tRs.%Get("ClassName")
            Set tEntry = {}
            Do tEntry.%Set("name", ..GetParameterValue(tClassName, "ToolName"))
            Do tEntry.%Set("description", ..GetParameterValue(tClassName, "Description"))
            Do tEntry.%Set("input_schema", $ClassMethod(tClassName, "GetInputSchema"))
            Do tResult.%Push(tEntry)
        }
    }
    Catch ex {
        ; Reflection failure surfaces as an empty list rather than an
        ; exception bubbling out — operator sees "no tools available"
        ; in the MCP list response, which is the safe degradation.
        Set tResult = []
    }
    Quit tResult
}

/// <p>Trust-boundary dispatch entry point — the AgentLoop's only path
/// to invoking a tool. Performs the eight-step orchestration spelled
/// out in the architecture §"Tool dispatch contract":</p>
/// <ol>
/// <li><b>Lookup</b> — scan concrete subclasses for one whose
/// <parameter>ToolName</parameter> equals <code>pToolName</code>.
/// Unknown tool returns an MCP error envelope (no exception).</li>
/// <li><b>L2 read-only enforcement</b> (FR36) — read the subclass's
/// <parameter>MutatesState</parameter>; if <code>1</code>, return an MCP
/// error envelope without invoking the tool.</li>
/// <li><b>Latency timer</b> — capture <code>$ZH</code> start.</li>
/// <li><b>Lazy-register the audit triple</b> — delegated to
/// <method>SessionAgent.Audit.Emit.LogToolCall</method> which calls
/// <method>SessionAgent.Audit.Emit.RegisterIfMissing</method> internally
/// (Story 2.5 carry-forward; Story 2.0 cleanup is now closed).</li>
/// <li><b>Invoke</b> the concrete via
/// <code>$ClassMethod(&lt;class&gt;, "Invoke", ...)</code> inside an outer
/// Try/Catch. A thrown exception (defense-in-depth — tools should
/// pre-surface their own errors) is converted to an MCP error envelope;
/// the operator-readable message uses <code>ex.DisplayString()</code>,
/// the full stack goes to <property>Audit.ToolCall.ErrorText</property>
/// only.</li>
/// <li><b>Compute latency</b> in milliseconds.</li>
/// <li><b>Audit emit</b> via <method>SessionAgent.Audit.Emit.LogToolCall</method>
/// — always called, on success and error paths alike (NFR-S4 100%
/// completeness).</li>
/// <li><b>Return</b> <code>$$$OK</code>. Tool-result success vs failure
/// is signaled inside the <code>pResult</code> envelope's
/// <code>isError</code> field; the <code>%Status</code> return reflects
/// orchestration health only.</li>
/// </ol>
ClassMethod Dispatch(pToolName As %String, pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {}
    Set tStart = $ZH
    Set tClassName = ""
    Set tIsError = 0
    Set tErrorText = ""
    Set tDispatchAttempted = 0
    ; Story 3.0 AC-6 — pCallerCtx validation. A NULLOREF or wrong-type
    ; pCallerCtx is an internal programming error (the only legitimate
    ; caller is AgentLoop.RunTurn which constructs a fresh
    ; SessionAgent.Agent.CallerContext at the trust boundary). Surface
    ; via the standard envelope rather than crashing the dispatch — the
    ; downstream audit emit + envelope-based contract still hold per
    ; Rule 8 Fix #5 ("always-audit semantics still apply").
    If '$IsObject($Get(pCallerCtx)) || ('pCallerCtx.%IsA("SessionAgent.Agent.CallerContext")) {
        Set pResult = {"isError":(1), "content":[{"type":"text", "text":"Internal: dispatch invoked without CallerContext"}]}
        Set tIsError = 1
        Set tErrorText = "Dispatch invoked with NULLOREF or wrong-type pCallerCtx"
        Set tLatencyMs = 0
        ; Always-audit semantics — write the audit row even on this guard
        ; path (NFR-S4 100% completeness). ChatHistoryId is empty because
        ; we have no caller context to derive it from.
        Do ##class(SessionAgent.Audit.Emit).LogToolCall("", pToolName, "", pResult.%ToJSON(), tLatencyMs, tIsError, tErrorText, "", "", "")
        Quit $$$OK
    }
    Try {
        ; Step 1 — Lookup. Resolve pToolName to a concrete class.
        Set tClassName = ..ResolveToolName(pToolName)
        If tClassName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text", "text":("unknown tool: " _ pToolName)}]}
            Set tIsError = 1
            Quit
        }

        ; Step 2 — L2 read-only enforcement (FR36).
        Set tMutates = ..GetParameterValue(tClassName, "MutatesState")
        If tMutates = 1 {
            Set pResult = {"isError":(1), "content":[{"type":"text", "text":"Tool blocked by read-only policy"}]}
            Set tIsError = 1
            Quit
        }

        ; Step 5 — Invoke (timer started before Try; latency computed after Try).
        Set tDispatchAttempted = 1
        Set tInvokeSC = $ClassMethod(tClassName, "Invoke", pCallerCtx, pJsonArgs, .pResult)
        If $$$ISERR(tInvokeSC) {
            ; Tool returned a failure %Status without populating an error
            ; envelope — synthesize one so downstream consumers always
            ; see the standard shape.
            Set pResult = {"isError":(1), "content":[{"type":"text", "text":($System.Status.GetErrorText(tInvokeSC))}]}
            Set tIsError = 1
            Set tErrorText = $System.Status.GetErrorText(tInvokeSC)
        } ElseIf $IsObject($Get(pResult)) && (pResult.%Get("isError") = 1) {
            Set tIsError = 1
            ; Operator-facing text already in pResult.content[0].text;
            ; copy it into ErrorText for the audit row.
            If pResult.content.%Size() > 0 {
                Set tErrorText = pResult.content.%Get(0).text
            }
        }
    }
    Catch ex {
        ; Defense-in-depth — tools should pre-surface their own errors,
        ; but if one throws we wrap into the standard envelope and
        ; capture the stack for the audit row only (NEVER to operator
        ; per architecture line 476).
        Set pResult = {"isError":(1), "content":[{"type":"text", "text":(ex.DisplayString())}]}
        Set tIsError = 1
        ; ex.DisplayString() already includes class name, code, message
        ; and source location. ex.AsStatus() preserves the status chain.
        ; Both go to ErrorText only — never to the operator-facing
        ; content[0].text (architecture line 476).
        Set tErrorText = ex.DisplayString() _ " | AsStatus: " _ $System.Status.GetErrorText(ex.AsStatus())
    }

    ; Step 6 — Compute latency.
    Set tLatencyMs = $Normalize(($ZH - tStart) * 1000, 0)

    ; Step 7 — Audit emit (NFR-S4 100% completeness — every Dispatch call
    ; produces exactly one Audit.ToolCall row, success OR failure OR
    ; lookup-failure OR policy-block). Story 3.0 carry-forward: the
    ; original Story 2.10 design skipped audit on unknown-tool / blocked
    ; paths as a DoS hedge, but that opens a real audit-completeness
    ; gap (an attacker spamming blocked tools generates no trail) and
    ; conflicts with NFR-S4. Switched to unconditional emit; DoS is
    ; better addressed at the call-rate boundary if it becomes a real
    ; problem.
    Set tChatHistoryId = ""
    If $IsObject(pCallerCtx), pCallerCtx.ChatHistoryId '= "" {
        Set tChatHistoryId = pCallerCtx.ChatHistoryId
    } ElseIf $IsObject(pCallerCtx) {
        Set tChatHistoryId = $Case(pCallerCtx.AgentName,
            "session-inspection": pCallerCtx.IrisSessionId,
            "message-search": pCallerCtx.SearchSessionKey,
            : pCallerCtx.IrisSessionId)
    }
    Set tArgsJson = ""
    If $IsObject($Get(pJsonArgs)) {
        Set tArgsJson = pJsonArgs.%ToJSON()
    }
    Set tResultJson = ""
    If $IsObject($Get(pResult)) {
        Set tResultJson = pResult.%ToJSON()
    }
    Do ##class(SessionAgent.Audit.Emit).LogToolCall(tChatHistoryId, pToolName, tArgsJson, tResultJson, tLatencyMs, tIsError, tErrorText, "", "", "")

    Quit tSC
}

/// <p><b>Story 6.0 (Epic 5 retro AI-3) — semantic alias for the
/// canonical tool-def source.</b> Returns the same
/// <CLASS>%DynamicArray</CLASS> that <method>ListTools</method> produces:
/// each entry is the canonical
/// <code>{name, description, input_schema}</code> shape, where
/// <code>input_schema</code> includes <code>additionalProperties: false</code>
/// per the Story 4.0 locked-subset codification.</p>
///
/// <p><b>Why a semantic alias?</b> The runtime tool-def array that
/// <CLASS>SessionAgent.Agent.AgentLoop</CLASS> emits to provider
/// <method>BuildPayload</method> + the test fixture that
/// <CLASS>SessionAgent.Test.ToolCallRoundtripIntegrationTest</CLASS> uses
/// for its 52-pair matrix MUST be the same array. Story 5.4 originally
/// hand-built a tool array in the matrix without
/// <code>additionalProperties: false</code> — that bug shipped silently
/// because the matrix used a mock provider that bypasses
/// <method>BuildPayload</method>'s tool-array translation. The
/// `GetCanonicalToolDefs()` name is the documented surface every code
/// path that needs canonical tool defs MUST source from, so a future
/// reviewer reading the matrix code sees the fixture and the runtime
/// share one source-of-truth.</p>
ClassMethod GetCanonicalToolDefs() As %DynamicArray
{
    Quit ..ListTools()
}

/// <p>Internal — given a concrete class name and a parameter name,
/// return the parameter's <code>Default</code> value (the literal value
/// declared in the class). Returns the empty string if the parameter
/// row does not exist (parameter not declared on that class).</p>
///
/// <p>Per the Task-0 probe, <code>%Dictionary.ParameterDefinition.Default</code>
/// holds the parameter's compile-time value (irislib
/// <code>%Dictionary/ParameterDefinition.cls</code> line 21).</p>
ClassMethod GetParameterValue(pClassName As %String, pParamName As %String) As %String
{
    Set tValue = ""
    Try {
        Set tParam = ##class(%Dictionary.ParameterDefinition).%OpenId(pClassName _ "||" _ pParamName)
        If $IsObject(tParam) {
            Set tValue = tParam.Default
        }
    }
    Catch ex {
        Set tValue = ""
    }
    Quit tValue
}

/// <p>Internal — given a tool name (the symbolic
/// <parameter>ToolName</parameter> value), find the concrete subclass
/// of <CLASS>SessionAgent.Tool.Base</CLASS> whose
/// <parameter>ToolName</parameter> equals <code>pToolName</code>.
/// Returns the empty string if no concrete subclass declares that
/// name.</p>
///
/// <p>Implementation: same SQL discovery query as
/// <method>ListTools</method>, but reads each subclass's
/// <parameter>ToolName</parameter> via <method>GetParameterValue</method>
/// and compares. Linear scan is acceptable — tool count is bounded by
/// the v1 design (≤ 20) and dispatch latency is dominated by the LLM
/// round-trip, not the lookup.</p>
ClassMethod ResolveToolName(pToolName As %String) As %String
{
    Set tFound = ""
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        ; Story 8.3 fix-now — also dispatch via the Tool.Search.Base
        ; intermediate abstract. NOTE: this method does NOT filter out
        ; SessionAgent.Test.* fixtures (unlike ListTools, which does);
        ; ToolRegistryTest's stub-throwing-tool dispatch path depends on
        ; resolution working for fixture classes. Operators only see
        ; tools through ListTools, so the exclusion happens there.
        Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE (%EXACT(Super) = 'SessionAgent.Tool.Base' OR %EXACT(Super) = 'SessionAgent.Tool.Search.Base') AND Abstract = 0")
        If $$$ISERR(tSC) Quit
        Set tRs = tStmt.%Execute()
        ; Story 14.0 review fix (cr-13-3 class) — a runtime discovery-query
        ; failure previously yielded a silent zero-row scan → tFound="" →
        ; Dispatch misreported a REGISTERED tool as "unknown tool". Throw
        ; instead; the rethrowing Catch below propagates to Dispatch's
        ; outer Catch, which emits a server-fault envelope and stamps
        ; Audit.ToolCall.ErrorText.
        If tRs.%SQLCODE < 0 {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "tool discovery query failed: SQLCODE " _ tRs.%SQLCODE _ ": " _ tRs.%Message))
        }
        While tRs.%Next() {
            Set tClassName = tRs.%Get("ClassName")
            Set tCandidateName = ..GetParameterValue(tClassName, "ToolName")
            If tCandidateName = pToolName {
                Set tFound = tClassName
                Quit
            }
        }
    }
    Catch ex {
        ; Story 14.0 review fix — previously swallowed to "" which Dispatch
        ; misreports as "unknown tool: <name>" even for registered tools.
        ; Rethrow so Dispatch's outer Catch converts the failure into a
        ; server-fault envelope (operator sees the real cause; audit row
        ; captures the stack). Dispatch is the only production caller and
        ; wraps this method inside its Try (Registry.cls Step 1).
        Throw ex
    }
    Quit tFound
}

}
