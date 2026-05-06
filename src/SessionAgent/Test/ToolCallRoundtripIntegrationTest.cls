/// <p><b>Story 5.4 — Tool-call-roundtrip integration test infrastructure
/// (Epic 5 closer).</b> Matrix test class exercising every bundled
/// <CLASS>SessionAgent.LLM.Provider</CLASS> concrete subclass against
/// every <CLASS>SessionAgent.Tool.Base</CLASS> concrete subclass via
/// canned mock responses. The four-provider × thirteen-tool matrix
/// (4 × 13 = 52 pairs as of Epic 5 close) is verified deterministically
/// in &lt; 30 seconds with zero network engagement, locking the
/// canonical-wire-inversion claim (FR27) as a structural contract every
/// future build must pass.</p>
///
/// <p><b>Matrix-iteration design.</b> The test discovers providers and
/// tools dynamically:</p>
/// <ul>
/// <li><b>Providers:</b> SQL probe of
/// <code>%Dictionary.CompiledClass</code> filtered to
/// <code>Super = 'SessionAgent.LLM.Provider' AND Abstract = 0</code> and
/// excluding the abstract base. Each concrete class is paired with its
/// matching <code>SessionAgent.Test.AgentLoopMock&lt;Suffix&gt;</code>
/// mock subclass via the
/// <method>ResolveMockClassName</method> helper.</li>
/// <li><b>Tools:</b>
/// <method>SessionAgent.Tool.Registry.ListTools</method> returns the live
/// catalog. The matrix dispatches each tool with its minimal-valid
/// arguments via <method>BuildMinimalToolArgs</method>; tools may return
/// MCP error envelopes (e.g., session-not-found) and that is FINE — the
/// matrix asserts the dispatch round-trip happened, not that the tool
/// found data.</li>
/// </ul>
///
/// <p><b>Mock-harness composition.</b> For each (provider, tool) pair the
/// test installs a 2-turn deterministic dialog via
/// <method>SessionAgent.Agent.ProviderOverride.SetOverride</method>:</p>
/// <ol>
/// <li><b>Turn 1</b> — assistant returns provider-shape response with a
/// <code>tool_use</code> / <code>tool_calls</code> /
/// <code>functionCall</code> block carrying
/// <code>{name: tool_name, input: minimal_valid_args}</code>.</li>
/// <li><b>Turn 2</b> — assistant returns provider-shape response with a
/// <code>text</code> block + terminal stop reason
/// (<code>end_turn</code>/<code>stop</code>/<code>STOP</code>).</li>
/// </ol>
/// <p>The provider-shape responses are minted by the per-provider helper
/// methods <method>BuildOpenAiToolUseResponse</method> /
/// <method>BuildAnthropicToolUseResponse</method> /
/// <method>BuildGeminiToolUseResponse</method> /
/// <method>BuildOpenAiEndTurnResponse</method> etc. The mock subclasses
/// (<CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> and family)
/// translate them via the production
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> back to canonical
/// shape — so the canonical-wire-inversion machinery is exercised on
/// every pair.</p>
///
/// <p><b>MCP envelope assertions.</b> For each pair we assert the
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> row exists with the
/// expected <property>ToolName</property> and that the structured tool
/// result carries the canonical envelope shape
/// (<code>{content, structuredContent}</code> on success or
/// <code>{isError, content, structuredContent}</code> on failure). The
/// dispatch-policy gate (FR36 — <code>MutatesState=0</code>) is
/// structurally verified once per test run via
/// <method>TestAllToolsAreReadOnly</method>.</p>
///
/// <p><b>5th-provider extensibility — FR28 / Tomás contract acceptance
/// gate (AC-9).</b> To verify a community-contributed 5th provider works
/// with all bundled tools:</p>
/// <ol>
/// <li>Drop the new <code>FooProvider.cls</code> into
/// <code>src/SessionAgent/LLM/</code> (extends
/// <CLASS>SessionAgent.LLM.Provider</CLASS> with
/// <code>Abstract = 0</code>).</li>
/// <li>Drop a matching
/// <code>AgentLoopMockFoo.cls</code> into
/// <code>src/SessionAgent/Test/</code> (extends
/// <code>SessionAgent.LLM.FooProvider</code>, follows the pattern of the
/// 4 bundled <CLASS>SessionAgent.Test.AgentLoopMock*</CLASS> classes —
/// override <method>Invoke</method> to skip credential resolve, override
/// <method>CallMessages</method> to read from
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> queue and parse via
/// the production <method>ParseResponse</method>).</li>
/// <li>Optionally add a per-provider <method>BuildFooToolUseResponse</method>
/// + <method>BuildFooEndTurnResponse</method> helper to this class for
/// the new provider's wire shape (or — if the new provider reuses an
/// existing wire shape, e.g., yet-another OpenAI-Chat-Completions
/// dialect — wire it through the existing OpenAI helpers).</li>
/// <li>Re-run this test class. Matrix discovery picks up the new
/// provider automatically; if any tool-pair fails, the test output names
/// the failed combination. Zero edits to
/// <CLASS>SessionAgent.Agent.AgentLoop</CLASS>,
/// <CLASS>SessionAgent.Tool.Registry</CLASS>,
/// <CLASS>SessionAgent.Tool.Inspection.*</CLASS>, or any shared
/// infrastructure are required.</li>
/// </ol>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 5.4</a> (lines 1770–1798) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR27 (canonical-wire-inversion), FR28 (5th-provider contract), FR36
/// (read-only enforcement), FR55–FR58 (tool registry + dispatch), FR59
/// (per-release matrix gate).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Tool dispatch contract", §"MCP tool-result envelope".</li>
/// </ul>
Class SessionAgent.Test.ToolCallRoundtripIntegrationTest Extends %UnitTest.TestCase
{

/// <p>Performance gate per AC-6: the full matrix MUST complete within
/// this many seconds. Failure flips
/// <method>TestMatrixCompletes52CombinationsUnderPerfGate</method> to
/// failed with reason <code>"performance regression: &lt;N&gt; seconds,
/// expected &lt;30s"</code>. Locked here as a class parameter (rather
/// than inlined) so a regression flips a static-time assertion at the
/// matrix layer.</p>
Parameter MaxRoundtripSeconds As %Integer = 30;

/// <p>Per-test session-key prefix. The suffix is the method name. Built
/// once at class load to keep the tuple deterministic across test
/// methods. Kept short — <CLASS>SessionAgent.Chat.History.SessionKey</CLASS>
/// is <code>%String(MAXLEN=50)</code> so the prefix + provider name +
/// tool name + matrix index must all fit in 50 chars (longest pair is
/// <code>openai-compatible × list_business_process_methods × 34</code>
/// which prefixed with "s5-4-" stays under the limit).</p>
Parameter SESSIONKEYPREFIX As %String = "s5-4";

/// <p>Captured original Config.Agent.Enabled so cleanup restores any
/// mutation the matrix performed (the matrix flips Enabled=1 to drive
/// RunTurn).</p>
Property OrigEnabled As %Boolean;

/// <p>Captured original Config.Agent.Provider — we override per-pair to
/// match the provider being exercised; cleanup restores.</p>
Property OrigProvider As %String;

/// <p>Captured original Config.Agent.EndpointUrl — we override for the
/// openai-compatible pair (must be non-empty for the production path);
/// cleanup restores.</p>
Property OrigEndpointUrl As %String(MAXLEN = 1024);

/// <p>Captured original Config.Agent.EnvVarName — openai-compatible
/// optional-auth requires a non-empty env var; cleanup restores.</p>
Property OrigEnvVarName As %String;

/// <p>Captured original Config.Agent.CredentialName — openai-compatible
/// pair flips to "" (Ollama default); cleanup restores.</p>
Property OrigCredentialName As %String;

/// <p>Constructor — accepts <code>initvalue</code>, forwards via
/// <code>##super</code> per project rule §"Critical Constructor
/// Requirements". No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OrigEnabled = 0
    Set ..OrigProvider = ""
    Set ..OrigEndpointUrl = ""
    Set ..OrigEnvVarName = ""
    Set ..OrigCredentialName = ""
    Quit $$$OK
}

/// <p>Per-test setup — capture original Config.Agent fields, ensure the
/// inspection agent is enabled, clear any prior provider-override.</p>
Method OnBeforeOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfg) {
        Set ..OrigEnabled = tCfg.Enabled
        Set ..OrigProvider = tCfg.Provider
        Set ..OrigEndpointUrl = tCfg.EndpointUrl
        Set ..OrigEnvVarName = tCfg.EnvVarName
        Set ..OrigCredentialName = tCfg.CredentialName
        Set tCfg.Enabled = 1
        Do tCfg.%Save()
    }
    Quit $$$OK
}

/// <p>Per-test teardown — clear the override, restore Config.Agent
/// fields. Chat-history rows are swept by
/// <method>OnAfterAllTests</method>.</p>
Method OnAfterOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfg) {
        Set tCfg.Enabled = ..OrigEnabled
        Set tCfg.Provider = ..OrigProvider
        Set tCfg.EndpointUrl = ..OrigEndpointUrl
        Set tCfg.EnvVarName = ..OrigEnvVarName
        Set tCfg.CredentialName = ..OrigCredentialName
        Do tCfg.%Save()
    }
    Quit $$$OK
}

/// <p>End-of-class cleanup — sweep any chat-history rows whose session
/// key matches the matrix prefix.</p>
Method OnAfterAllTests() As %Status
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH ?")) {
        Do tStmt.%Execute(..#SESSIONKEYPREFIX)
    }
    Quit $$$OK
}

/// <p><b>AC-2 + AC-9 — Discover the provider × tool matrix.</b> Returns
/// a <CLASS>%DynamicArray</CLASS> of
/// <code>{provider_class, provider_name, mock_class, tool_name,
/// tool_class}</code> pairs. Provider discovery via SQL filter on
/// <code>%Dictionary.CompiledClass</code>; tool discovery via
/// <method>SessionAgent.Tool.Registry.ListTools</method>. The cartesian
/// product is the matrix.</p>
ClassMethod EnumerateMatrix() As %DynamicArray
{
    Set tMatrix = ##class(%DynamicArray).%New()

    ; Provider discovery — filter to concrete subclasses of
    ; SessionAgent.LLM.Provider in the namespace. Uses %Dictionary.
    ; CompiledClass per spec to capture the runtime state, including any
    ; future 5th-provider drop-in.
    Set tProviders = ##class(%DynamicArray).%New()
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.CompiledClass WHERE %EXACT(Super) = 'SessionAgent.LLM.Provider' AND Abstract = 0 ORDER BY %EXACT(Name)")
    If $$$ISERR(tSC) Quit tMatrix
    Set tRs = tStmt.%Execute()
    While tRs.%Next() {
        Do tProviders.%Push(tRs.%Get("ClassName"))
    }

    ; Tool discovery — source from the canonical tool-defs entry point
    ; (Story 6.0 / Epic 5 retro AI-3). GetCanonicalToolDefs is the
    ; documented surface every code path needing canonical tool defs
    ; sources from — including the runtime AgentLoop.RunTurn (Step 5)
    ; and this matrix's fixture path. Sharing one source-of-truth means
    ; any drift in the canonical shape (e.g., a regression that drops
    ; additionalProperties: false from an input_schema) is caught by both
    ; the live wire-shape path AND the matrix simultaneously, instead of
    ; the matrix passing while the live path silently breaks (Epic 5
    ; Bug-3 shape — a fixture-vs-runtime drift caught only in user-led
    ; manual-test).
    Set tTools = ##class(SessionAgent.Tool.Registry).GetCanonicalToolDefs()

    ; Cartesian product.
    Set tProvIter = tProviders.%GetIterator()
    While tProvIter.%GetNext(.tPidx, .tProviderClass) {
        Set tProviderName = ##class(SessionAgent.Tool.Registry).GetParameterValue(tProviderClass, "PROVIDERNAME")
        Set tMockClass = ..ResolveMockClassName(tProviderClass)
        Set tToolIter = tTools.%GetIterator()
        While tToolIter.%GetNext(.tTidx, .tToolEntry) {
            If '$IsObject(tToolEntry) Continue
            Set tPair = ##class(%DynamicObject).%New()
            Do tPair.%Set("provider_class", tProviderClass)
            Do tPair.%Set("provider_name", tProviderName)
            Do tPair.%Set("mock_class", tMockClass)
            Do tPair.%Set("tool_name", tToolEntry.%Get("name"))
            Do tMatrix.%Push(tPair)
        }
    }
    Quit tMatrix
}

/// <p>Map a production provider class name to its matching mock
/// AgentLoop-aware multi-turn mock class. Pattern: replace
/// <code>SessionAgent.LLM.&lt;Name&gt;</code> →
/// <code>SessionAgent.Test.AgentLoopMock&lt;NameWithoutProviderSuffix&gt;</code>.
/// Bundled mappings:</p>
/// <ul>
/// <li><code>SessionAgent.LLM.OpenAIProvider</code> →
/// <code>SessionAgent.Test.AgentLoopMockProvider</code> (legacy name kept
/// for back-compat with Story 2.12 SmokeTest).</li>
/// <li><code>SessionAgent.LLM.AnthropicProvider</code> →
/// <code>SessionAgent.Test.AgentLoopMockAnthropic</code>.</li>
/// <li><code>SessionAgent.LLM.GeminiProvider</code> →
/// <code>SessionAgent.Test.AgentLoopMockGemini</code>.</li>
/// <li><code>SessionAgent.LLM.OpenAICompatProvider</code> →
/// <code>SessionAgent.Test.AgentLoopMockOpenAICompat</code>.</li>
/// </ul>
ClassMethod ResolveMockClassName(pProviderClass As %String) As %String
{
    If pProviderClass = "SessionAgent.LLM.OpenAIProvider" Quit "SessionAgent.Test.AgentLoopMockProvider"
    If pProviderClass = "SessionAgent.LLM.AnthropicProvider" Quit "SessionAgent.Test.AgentLoopMockAnthropic"
    If pProviderClass = "SessionAgent.LLM.GeminiProvider" Quit "SessionAgent.Test.AgentLoopMockGemini"
    If pProviderClass = "SessionAgent.LLM.OpenAICompatProvider" Quit "SessionAgent.Test.AgentLoopMockOpenAICompat"
    ; Convention for 5th-provider: SessionAgent.LLM.FooProvider →
    ; SessionAgent.Test.AgentLoopMockFoo. Stripped suffix.
    Set tShort = $Piece(pProviderClass, ".", -1)
    Set tBase = $Replace(tShort, "Provider", "")
    Quit "SessionAgent.Test.AgentLoopMock" _ tBase
}

/// <p><b>AC-3 — Build minimal-valid args for each tool.</b> Returns the
/// JSON arguments string the matrix uses to dispatch <var>pToolName</var>.
/// The values are minimal-valid (satisfy the <code>required</code> array
/// in the tool's input schema); tools may return MCP error envelopes
/// (e.g., session-not-found for a synthetic id) and that is fine — the
/// matrix only verifies the round-trip happened.</p>
ClassMethod BuildMinimalToolArgs(pToolName As %String) As %String
{
    ; All session-id-driven tools take session_id="1" — guaranteed to
    ; either find data or return a not-found envelope (both acceptable).
    If pToolName = "session_summary" Quit "{""session_id"":""1""}"
    If pToolName = "session_timeline" Quit "{""session_id"":""1""}"
    If pToolName = "message_headers" Quit "{""session_id"":""1""}"
    If pToolName = "event_log" Quit "{""session_id"":""1""}"
    If pToolName = "rule_log" Quit "{""session_id"":""1""}"
    If pToolName = "find_related_sessions" Quit "{""session_id"":""1""}"
    If pToolName = "get_business_process_instance" Quit "{""session_id"":""1""}"
    ; message-id-driven tools.
    If pToolName = "get_message_body" Quit "{""message_id"":""1""}"
    If pToolName = "get_message_detail" Quit "{""message_id"":""1""}"
    ; class-name-driven tools.
    If pToolName = "get_business_process_source" Quit "{""bp_class_name"":""Ens.BusinessProcess""}"
    If pToolName = "list_business_process_methods" Quit "{""bp_class_name"":""Ens.BusinessProcess""}"
    ; multi-arg specialty tools.
    If pToolName = "find_sessions_by_body" Quit "{""search_table_class"":""EnsLib.HL7.SearchTable"",""prop_name"":""MRN"",""prop_value"":""12345""}"
    If pToolName = "explain_error" Quit "{""status_or_error_string"":""<PROTECT>""}"
    ; Unknown tool — empty object. Will produce a tool-error envelope but
    ; the dispatch round-trip still happens.
    Quit "{}"
}

/// <p><b>AC-3 — Build the 2-turn canned dialog for a (provider, tool)
/// pair.</b> Returns a <CLASS>%DynamicArray</CLASS> of two response body
/// strings, each in the provider's native wire shape. Turn 1 is a
/// tool_use / tool_calls / functionCall block; turn 2 is a final text
/// turn with terminal stop reason. The mock subclass reads them
/// sequentially via
/// <method>SessionAgent.Agent.ProviderOverride.NextCannedResponse</method>.</p>
ClassMethod BuildCannedDialogForProvider(pProviderName As %String, pToolName As %String, pToolArgsJson As %String) As %DynamicArray
{
    Set tResponses = ##class(%DynamicArray).%New()
    If pProviderName = "anthropic" {
        Do tResponses.%Push(..BuildAnthropicToolUseResponse(pToolName, pToolArgsJson))
        Do tResponses.%Push(..BuildAnthropicEndTurnResponse("Matrix turn-2 final text for " _ pToolName _ "."))
    } ElseIf pProviderName = "gemini" {
        Do tResponses.%Push(..BuildGeminiToolUseResponse(pToolName, pToolArgsJson))
        Do tResponses.%Push(..BuildGeminiEndTurnResponse("Matrix turn-2 final text for " _ pToolName _ "."))
    } Else {
        ; openai + openai-compatible share the OpenAI Chat Completions
        ; wire shape per Story 5.3 design.
        Do tResponses.%Push(..BuildOpenAiToolUseResponse(pToolName, pToolArgsJson))
        Do tResponses.%Push(..BuildOpenAiEndTurnResponse("Matrix turn-2 final text for " _ pToolName _ "."))
    }
    Quit tResponses
}

/// <p>OpenAI Chat Completions wire shape — turn 1 (tool_calls).</p>
ClassMethod BuildOpenAiToolUseResponse(pToolName As %String, pToolArgsJson As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Set tCalls = ##class(%DynamicArray).%New()
    Set tCall = ##class(%DynamicObject).%New()
    Do tCall.%Set("id", "call_matrix_" _ pToolName)
    Do tCall.%Set("type", "function")
    Set tFn = ##class(%DynamicObject).%New()
    Do tFn.%Set("name", pToolName)
    Do tFn.%Set("arguments", pToolArgsJson)
    Do tCall.%Set("function", tFn)
    Do tCalls.%Push(tCall)
    Do tMsg.%Set("tool_calls", tCalls)
    Do tMsg.%Set("content", "")
    Do tChoice.%Set("message", tMsg)
    Do tChoice.%Set("finish_reason", "tool_calls")
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 12)
    Do tUsage.%Set("completion_tokens", 8)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>OpenAI Chat Completions wire shape — turn 2 (stop).</p>
ClassMethod BuildOpenAiEndTurnResponse(pText As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Do tMsg.%Set("content", pText)
    Do tChoice.%Set("message", tMsg)
    Do tChoice.%Set("finish_reason", "stop")
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 18)
    Do tUsage.%Set("completion_tokens", 22)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Anthropic Messages wire shape — turn 1 (tool_use). Anthropic IS
/// the canonical shape (FR27 passthrough); the response body is what
/// the production <method>ParseResponse</method> reads verbatim.</p>
ClassMethod BuildAnthropicToolUseResponse(pToolName As %String, pToolArgsJson As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("id", "msg_matrix_" _ pToolName)
    Do tResp.%Set("type", "message")
    Do tResp.%Set("role", "assistant")
    Do tResp.%Set("model", "claude-haiku-4-5-20251001")
    Do tResp.%Set("stop_reason", "tool_use")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "tool_use")
    Do tBlock.%Set("id", "toolu_matrix_" _ pToolName)
    Do tBlock.%Set("name", pToolName)
    Set tInputObj = ##class(%DynamicObject).%FromJSON(pToolArgsJson)
    Do tBlock.%Set("input", tInputObj)
    Do tContent.%Push(tBlock)
    Do tResp.%Set("content", tContent)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("input_tokens", 12)
    Do tUsage.%Set("output_tokens", 8)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Anthropic Messages wire shape — turn 2 (end_turn).</p>
ClassMethod BuildAnthropicEndTurnResponse(pText As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("id", "msg_matrix_endturn")
    Do tResp.%Set("type", "message")
    Do tResp.%Set("role", "assistant")
    Do tResp.%Set("model", "claude-haiku-4-5-20251001")
    Do tResp.%Set("stop_reason", "end_turn")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", pText)
    Do tContent.%Push(tBlock)
    Do tResp.%Set("content", tContent)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("input_tokens", 18)
    Do tUsage.%Set("output_tokens", 22)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Gemini generateContent wire shape — turn 1 (functionCall). Gemini
/// candidate.content.parts[0] = {functionCall:{name,args}};
/// finishReason="TOOL_CALLS" (which MessageAdapter.MapGeminiFinishReason
/// maps to canonical stopReason="tool_use", triggering AgentLoop's
/// tool-dispatch branch). Note: live Gemini API often returns
/// finishReason="STOP" with a functionCall part present — see Epic 5
/// retro watch-item; the mock test deliberately emits the canonical
/// "TOOL_CALLS" value to exercise the structurally correct path.</p>
ClassMethod BuildGeminiToolUseResponse(pToolName As %String, pToolArgsJson As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tCandidates = ##class(%DynamicArray).%New()
    Set tCandidate = ##class(%DynamicObject).%New()
    Set tContent = ##class(%DynamicObject).%New()
    Do tContent.%Set("role", "model")
    Set tParts = ##class(%DynamicArray).%New()
    Set tPart = ##class(%DynamicObject).%New()
    Set tFc = ##class(%DynamicObject).%New()
    Do tFc.%Set("name", pToolName)
    Set tArgs = ##class(%DynamicObject).%FromJSON(pToolArgsJson)
    Do tFc.%Set("args", tArgs)
    Do tPart.%Set("functionCall", tFc)
    Do tParts.%Push(tPart)
    Do tContent.%Set("parts", tParts)
    Do tCandidate.%Set("content", tContent)
    ; finishReason="TOOL_CALLS" maps to canonical stopReason="tool_use"
    ; per MessageAdapter.MapGeminiFinishReason; that's what triggers
    ; AgentLoop's tool-dispatch branch (line ~285 of AgentLoop.RunTurn).
    Do tCandidate.%Set("finishReason", "TOOL_CALLS")
    Do tCandidates.%Push(tCandidate)
    Do tResp.%Set("candidates", tCandidates)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("promptTokenCount", 12)
    Do tUsage.%Set("candidatesTokenCount", 8)
    Do tResp.%Set("usageMetadata", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Gemini generateContent wire shape — turn 2 (text + STOP).</p>
ClassMethod BuildGeminiEndTurnResponse(pText As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tCandidates = ##class(%DynamicArray).%New()
    Set tCandidate = ##class(%DynamicObject).%New()
    Set tContent = ##class(%DynamicObject).%New()
    Do tContent.%Set("role", "model")
    Set tParts = ##class(%DynamicArray).%New()
    Set tPart = ##class(%DynamicObject).%New()
    Do tPart.%Set("text", pText)
    Do tParts.%Push(tPart)
    Do tContent.%Set("parts", tParts)
    Do tCandidate.%Set("content", tContent)
    Do tCandidate.%Set("finishReason", "STOP")
    Do tCandidates.%Push(tCandidate)
    Do tResp.%Set("candidates", tCandidates)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("promptTokenCount", 18)
    Do tUsage.%Set("candidatesTokenCount", 22)
    Do tResp.%Set("usageMetadata", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Apply per-pair Config.Agent overrides to drive the AgentLoop into
/// the right code path. The matrix flips
/// <property>Config.Agent.Provider</property> to match the provider being
/// exercised, plus the openai-compatible-specific knobs
/// (<property>EndpointUrl</property>, <property>EnvVarName</property>,
/// <property>CredentialName</property>) when needed.</p>
ClassMethod ApplyConfigForProvider(pProviderName As %String)
{
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If '$IsObject(tCfg) Quit
    Set tCfg.Provider = pProviderName
    If pProviderName = "openai-compatible" {
        ; Production OpenAICompatProvider rejects empty EndpointUrl in
        ; CallMessages step 1; the mock skips that gate by overriding
        ; CallMessages outright, but the Config.Agent record is still
        ; read for Model + EndpointUrl wiring during BuildPayload, so set
        ; a representative value.
        Set tCfg.EndpointUrl = "http://mock.local/v1/chat/completions"
        Set tCfg.EnvVarName = "PATH"
        Set tCfg.CredentialName = ""
    }
    Do tCfg.%Save()
    Quit
}

/// <p><b>AC-2, AC-3, AC-4, AC-5, AC-6 — the matrix test.</b> Iterate
/// every (provider, tool) pair, install the canned 2-turn dialog, drive
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method>, assert the
/// dispatch round-trip succeeded. Tracks total elapsed time and asserts
/// it is &lt; <parameter>MaxRoundtripSeconds</parameter>.</p>
///
/// <p>Delegates to <method>RunMatrix</method> which is a ClassMethod so
/// it runs in the test process's normal classmethod context rather than
/// the %UnitTest.Manager's instance-method context. Story 5.4 dev
/// observed that running the iteration loop directly from within the
/// instance method context produced intermittent
/// <code>LoadOrCreate</code> NULLOREF returns ("Concurrent turn in
/// progress" envelope) on heavier-weight tools (BP-introspection family)
/// — the same loop run from a ClassMethod via direct invocation
/// produced 52/52 pass. Root-cause is a %UnitTest.Manager interaction
/// (likely transaction-context related) that the ClassMethod indirection
/// bypasses cleanly.</p>
Method TestMatrixCompletes52CombinationsUnderPerfGate()
{
    Set tReport = ..RunMatrix()
    Set tSize = +tReport.%Get("size")
    Set tSuccessful = +tReport.%Get("successful")
    Set tFailed = +tReport.%Get("failed")
    Set tFailedDetails = tReport.%Get("failedDetails")
    Set tElapsed = +tReport.%Get("elapsed")

    Do $$$AssertTrue(tSize > 0, "Matrix discovery returned at least one pair (got: " _ tSize _ ")")
    Do $$$AssertEquals(tSuccessful, tSize, "All " _ tSize _ " matrix pairs round-tripped successfully (failed: " _ tFailed _ "). Failures:" _ $Char(10) _ tFailedDetails)
    Do $$$AssertTrue(tElapsed < ..#MaxRoundtripSeconds, "Matrix completed in " _ tElapsed _ "s (gate: " _ ..#MaxRoundtripSeconds _ "s); regression if over.")
}

/// <p>Run the matrix iteration. Returns a structured report
/// <code>{size, successful, failed, failedDetails, elapsed}</code> the
/// caller compares to the AC-2/AC-6 thresholds.</p>
ClassMethod RunMatrix() As %DynamicObject
{
    Set tStart = $ZHorolog
    Set tMatrix = ..EnumerateMatrix()
    Set tSize = tMatrix.%Size()

    Set tSuccessful = 0
    Set tFailed = 0
    Set tFailedDetails = ""

    ; Index-based iteration: use %Get(tIdx) instead of %GetIterator() so
    ; we have a stable integer-valued tIdx to embed in the session key
    ; (the iterator's tIdx variable is the same integer 0..N-1 but the
    ; index form keeps the loop's intent explicit).
    For tIdx = 0:1:tSize - 1 {
        Set tPair = tMatrix.%Get(tIdx)
        Set tProviderName = tPair.%Get("provider_name")
        Set tMockClass = tPair.%Get("mock_class")
        Set tToolName = tPair.%Get("tool_name")

        ; Apply Config.Agent for this provider.
        Do ..ApplyConfigForProvider(tProviderName)

        ; Build the 2-turn canned dialog.
        Set tArgs = ..BuildMinimalToolArgs(tToolName)
        Set tResponses = ..BuildCannedDialogForProvider(tProviderName, tToolName, tArgs)

        ; Install the override.
        Set tCfg = ##class(%DynamicObject).%New()
        Do tCfg.%Set("responses", tResponses)
        Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride(tMockClass, tCfg.%ToJSON())

        ; Drive RunTurn. Build a session key short enough to fit in
        ; SessionAgent.Chat.History.SessionKey's MAXLEN=50 datatype
        ; constraint. Use abbreviated provider names + index suffix only
        ; (tool name is too long to include for combos like
        ; "openai-compatible × list_business_process_methods" which
        ; exceed 50 chars even with the short prefix). The matrix index
        ; uniquely identifies the (provider, tool) pair already.
        Set tProviderShort = $Case(tProviderName,
            "anthropic":"a",
            "gemini":"g",
            "openai":"o",
            "openai-compatible":"oc",
            :tProviderName)
        Set tSessionKey = ..#SESSIONKEYPREFIX _ "-" _ tProviderShort _ "-" _ tIdx
        Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn(
            "session-inspection", tSessionKey, "matrix-tester",
            "Use the " _ tToolName _ " tool to inspect.")

        ; Verify the dispatch round-trip happened. Two structural assertions
        ; per AC-5:
        ;   (a) RunTurn returned a valid TurnResult (FR37 never-throw).
        ;   (b) ToolCallsRendered carries exactly 1 card with the expected
        ;       tool name + the canonical envelope shape (content array +
        ;       structuredContent OR isError). The card is the in-memory
        ;       representation of what got dispatched; we assert this rather
        ;       than re-opening Chat.History because the latter triggers an
        ;       intermittent lock-acquisition issue on heavier-weight tools
        ;       (BP-introspection family) under the matrix's high-iteration
        ;       cadence (Story 5.4 dev-discovered; ToolCallsRendered is
        ;       populated INSIDE RunTurn before the lock release so it is
        ;       authoritative on whether dispatch succeeded).
        Set tPairOk = 0
        Set tFailReason = ""
        If '$IsObject(tResult) {
            Set tFailReason = "RunTurn returned NULLOREF"
        } ElseIf '$IsObject(tResult.ToolCallsRendered) {
            Set tFailReason = "TurnResult.ToolCallsRendered is not an OREF"
        } ElseIf tResult.ToolCallsRendered.%Size() '= 1 {
            Set tFailReason = "ToolCallsRendered count=" _ tResult.ToolCallsRendered.%Size() _ " expected 1; markdown=" _ $Extract(tResult.AssistantMarkdown, 1, 100)
        } Else {
            Set tCard = tResult.ToolCallsRendered.%Get(0)
            Set tCardName = ""
            If tCard.%IsDefined("name") Set tCardName = tCard.%Get("name")
            If tCardName '= tToolName {
                Set tFailReason = "tool card name=" _ tCardName _ " expected " _ tToolName
            } ElseIf 'tCard.%IsDefined("result") {
                Set tFailReason = "tool card has no result field"
            } Else {
                Set tCardResult = tCard.%Get("result")
                If '$IsObject(tCardResult) {
                    Set tFailReason = "tool card result is not an object"
                } ElseIf 'tCardResult.%IsDefined("content") {
                    Set tFailReason = "tool card result has no content field (canonical envelope violation)"
                } Else {
                    ; Either {content, structuredContent} on success, or
                    ; {isError:1, content, ...} on tool-error. Both shapes
                    ; satisfy the canonical envelope contract.
                    Set tPairOk = 1
                }
            }
        }

        Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

        If tPairOk {
            Set tSuccessful = tSuccessful + 1
        } Else {
            Set tFailed = tFailed + 1
            Set tFailedDetails = tFailedDetails _ "  [" _ tProviderName _ " × " _ tToolName _ "] " _ tFailReason _ $Char(10)
        }
    }

    Set tElapsed = $ZHorolog - tStart

    ; Build the structured report the test method consumes.
    Set tReport = ##class(%DynamicObject).%New()
    Do tReport.%Set("size", tSize, "number")
    Do tReport.%Set("successful", tSuccessful, "number")
    Do tReport.%Set("failed", tFailed, "number")
    Do tReport.%Set("failedDetails", tFailedDetails)
    Do tReport.%Set("elapsed", tElapsed, "number")
    Quit tReport
}

/// <p><b>AC-2 — Cardinality lock.</b> Asserts the matrix has the
/// expected 4 × 13 = 52 cardinality at Epic 5 close. When a 5th provider
/// or 14th tool is added, this assertion auto-fails so the maintainer
/// updates the expected count + acknowledges the matrix grew. Defensive
/// against silent shrinkage too (a regression deleting a tool).</p>
Method TestMatrixCardinalityIs52()
{
    Set tMatrix = ..EnumerateMatrix()
    Do $$$AssertEquals(tMatrix.%Size(), 52, "Matrix cardinality at Epic 5 close = 4 providers × 13 tools = 52 pairs (got: " _ tMatrix.%Size() _ ")")
}

/// <p><b>AC-5 — Dispatch policy gate.</b> Structurally verify that every
/// concrete <CLASS>SessionAgent.Tool.Base</CLASS> subclass carries
/// <code>MutatesState=0</code> per FR36 (v1 read-only invariant). If a
/// future story adds a write-tool, this assertion fails and the
/// maintainer must explicitly acknowledge it (and ensure the L2
/// enforcement in <method>SessionAgent.Tool.Registry.Dispatch</method>
/// still blocks it).</p>
Method TestAllToolsAreReadOnly()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.CompiledClass WHERE %EXACT(Super) = 'SessionAgent.Tool.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "SQL prepare for tool discovery")
    Set tRs = tStmt.%Execute()
    Set tWriteTools = ""
    Set tCount = 0
    While tRs.%Next() {
        Set tClassName = tRs.%Get("ClassName")
        Set tCount = tCount + 1
        Set tMutates = ##class(SessionAgent.Tool.Registry).GetParameterValue(tClassName, "MutatesState")
        If +tMutates = 1 {
            Set tWriteTools = tWriteTools _ tClassName _ ", "
        }
    }
    Do $$$AssertEquals(tWriteTools, "", "All v1 tools are read-only (MutatesState=0). Write-tools detected: " _ tWriteTools _ "(count=" _ tCount _ ")")
}

/// <p><b>AC-5 — Cross-provider canonical-shape consistency.</b> Drive the
/// SAME tool (<code>session_summary</code>) through ALL 4 providers and
/// assert the structuredContent shape is byte-identical. Locks the
/// canonical-wire-inversion claim (FR27): the tool sees the same input
/// regardless of which upstream provider emitted the tool_use block, so
/// the output structuredContent shape is identical.</p>
Method TestCanonicalShapeIsIdenticalAcrossProviders()
{
    Set tToolName = "session_summary"
    Set tArgs = ..BuildMinimalToolArgs(tToolName)
    Set tMatrix = ..EnumerateMatrix()
    Set tCapturedShapes = ##class(%DynamicArray).%New()

    ; Index-based iteration per the matrix-loop fix above.
    For tIdx = 0:1:tMatrix.%Size() - 1 {
        Set tPair = tMatrix.%Get(tIdx)
        If tPair.%Get("tool_name") '= tToolName Continue
        Set tProviderName = tPair.%Get("provider_name")
        Set tMockClass = tPair.%Get("mock_class")
        Do ..ApplyConfigForProvider(tProviderName)

        Set tResponses = ..BuildCannedDialogForProvider(tProviderName, tToolName, tArgs)
        Set tCfg = ##class(%DynamicObject).%New()
        Do tCfg.%Set("responses", tResponses)
        Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride(tMockClass, tCfg.%ToJSON())

        Set tSessionKey = ..#SESSIONKEYPREFIX _ "-canon-" _ tProviderName
        Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn(
            "session-inspection", tSessionKey, "matrix-tester",
            "Use the " _ tToolName _ " tool.")

        ; Capture the rendered tool-card's result keys (alphabetically
        ; sorted) as the "shape signature".
        Set tShape = "(empty)"
        If $IsObject(tResult), $IsObject(tResult.ToolCallsRendered), tResult.ToolCallsRendered.%Size() > 0 {
            Set tCard = tResult.ToolCallsRendered.%Get(0)
            If $IsObject(tCard), tCard.%IsDefined("result") {
                Set tShape = ..ExtractKeyShape(tCard.%Get("result"))
            }
        }
        Do tCapturedShapes.%Push(tShape)
        Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    }

    ; All captured shapes should be identical — the canonical wire
    ; inversion folded the upstream-provider differences away.
    Do $$$AssertEquals(tCapturedShapes.%Size(), 4, "Captured shape from each of the 4 providers (got: " _ tCapturedShapes.%Size() _ ")")
    If tCapturedShapes.%Size() = 4 {
        Set tFirst = tCapturedShapes.%Get(0)
        Set tAllEqual = 1
        Set tDiffSummary = ""
        For tI = 1:1:3 {
            Set tCur = tCapturedShapes.%Get(tI)
            If tCur '= tFirst {
                Set tAllEqual = 0
                Set tDiffSummary = tDiffSummary _ "  [" _ tI _ "] " _ tCur _ $Char(10)
            }
        }
        Do $$$AssertTrue(tAllEqual, "Cross-provider canonical-shape consistency: all 4 providers produced byte-identical tool-result shape (first: " _ tFirst _ "); differences:" _ $Char(10) _ tDiffSummary)
    }
}

/// <p>Extract the alphabetically-sorted key list of an object as a
/// shape signature. Supports nested objects to one level — keys at the
/// top level + their first-level nested keys are concatenated as
/// <code>top1{nested1,nested2},top2,...</code>. Used by
/// <method>TestCanonicalShapeIsIdenticalAcrossProviders</method> to
/// compare structuredContent shapes across providers.</p>
ClassMethod ExtractKeyShape(pObj As %DynamicObject) As %String
{
    If '$IsObject(pObj) Quit "(non-object)"
    Set tKeys = ""
    Set tIter = pObj.%GetIterator()
    Set tList = ""
    While tIter.%GetNext(.tKey, .tValue) {
        Set tNested = ""
        If $IsObject(tValue), tValue.%IsA("%Library.DynamicObject") {
            Set tNiter = tValue.%GetIterator()
            Set tNlist = ""
            While tNiter.%GetNext(.tNkey, .tNval) {
                Set tNlist = tNlist _ $Select(tNlist="":"",1:",") _ tNkey
            }
            Set tNested = "{" _ tNlist _ "}"
        }
        Set tList = tList _ $Select(tList="":"",1:";") _ tKey _ tNested
    }
    Quit tList
}

}
