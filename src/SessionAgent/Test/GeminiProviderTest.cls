/// <p>Unit tests for <CLASS>SessionAgent.LLM.GeminiProvider</CLASS>
/// (Story 5.2). Locks the Gemini generateContent wire contract: model-in-URL
/// substitution, single <code>x-goog-api-key</code> header, payload shape
/// (contents + tools.functionDeclarations + systemInstruction +
/// generationConfig), MessageAdapter back-translation of
/// <code>parts[].functionCall</code> → canonical <code>tool_use</code>,
/// finishReason mapping, response-body retry-delay parsing
/// (Gemini-specific — no Retry-After header), exp-backoff fallback when
/// retryDelay is missing, usage-token mapping, and AgentLoop routing.</p>
///
/// <p><b>AC-8 method coverage (11 methods):</b></p>
/// <ol>
/// <li><b>TestProviderNameIsGemini</b></li>
/// <li><b>TestEndpointModelSubstitution</b></li>
/// <li><b>TestEndpointAgentOverride</b></li>
/// <li><b>TestAuthHeaderShape</b></li>
/// <li><b>TestPayloadShapeContentsAndTools</b></li>
/// <li><b>TestParseResponseFunctionCallToCanonicalToolUse</b></li>
/// <li><b>TestTranslateFinishReasonAllValues</b></li>
/// <li><b>TestParseGeminiRetryDelayHonors429Body</b></li>
/// <li><b>TestRetryFallsBackToExpBackoffOnMissingRetryDelay</b></li>
/// <li><b>TestUsagePopulatesCounts</b></li>
/// <li><b>TestRegistryListProvidersIncludesGemini</b></li>
/// </ol>
///
/// <p><b>Mock-HTTP strategy.</b> Same as
/// <CLASS>SessionAgent.Test.OpenAIProviderTest</CLASS> /
/// <CLASS>SessionAgent.Test.AnthropicProviderTest</CLASS> — subclass
/// <CLASS>SessionAgent.Test.MockGeminiProvider</CLASS> overrides
/// <method>IssueHttpsPost</method>; production class is unchanged.</p>
Class SessionAgent.Test.GeminiProviderTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-8 #1 — <method>GetProviderName</method> returns
/// <code>"gemini"</code>.</p>
Method TestProviderNameIsGemini()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Do $$$AssertEquals(tProv.GetProviderName(), "gemini", "GetProviderName returns gemini")
    Quit
}

/// <p>AC-8 #2 — <method>GetEndpointUrl</method> substitutes the
/// <code>{model}</code> placeholder in the default template with
/// <property>ConfigAgent.Model</property>.</p>
Method TestEndpointModelSubstitution()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.Model = "gemini-2.5-flash"
    Set tCfg.EndpointUrl = ""
    Set tProv.ConfigAgent = tCfg

    Set tUrl = tProv.GetEndpointUrl()
    Do $$$AssertEquals(tUrl, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", "{model} substituted with gemini-2.5-flash")

    ; Different model → different URL.
    Set tCfg.Model = "gemini-2.5-pro"
    Set tUrl2 = tProv.GetEndpointUrl()
    Do $$$AssertEquals(tUrl2, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent", "{model} substituted with gemini-2.5-pro")
    Quit
}

/// <p>AC-8 #3 — when <property>ConfigAgent.EndpointUrl</property> is set
/// to a non-empty value, it wins over the default-template substitution
/// (operator override path).</p>
Method TestEndpointAgentOverride()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.Model = "gemini-2.5-flash"
    Set tCfg.EndpointUrl = "https://proxy.example.com/v1/gemini:generateContent"
    Set tProv.ConfigAgent = tCfg

    Set tUrl = tProv.GetEndpointUrl()
    Do $$$AssertEquals(tUrl, "https://proxy.example.com/v1/gemini:generateContent", "EndpointUrl override wins")
    Quit
}

/// <p>AC-8 #4 — <method>GetAuthHeader</method> returns a single string of
/// the form <code>"x-goog-api-key: &lt;key&gt;"</code>. Diverges from
/// AnthropicProvider's $ListBuild list and OpenAIProvider's Bearer
/// format.</p>
Method TestAuthHeaderShape()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Set tHeader = tProv.GetAuthHeader("test-key")

    Do $$$AssertEquals(tHeader, "x-goog-api-key: test-key", "Single-string header line")

    ; NFR-S3 — the api key appears in the header line.
    Do $$$AssertTrue(tHeader [ "test-key", "Key appears in header line")
    Quit
}

/// <p>AC-8 #5 — payload has <code>contents</code>,
/// <code>tools.functionDeclarations[]</code>,
/// <code>systemInstruction.parts[]</code>, and
/// <code>generationConfig.maxOutputTokens</code> +
/// <code>generationConfig.temperature</code>.</p>
Method TestPayloadShapeContentsAndTools()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ..BuildThreeCanonicalTools()
    Set tCfg = ..BuildTransientConfigAgent()

    Set tPayload = tProv.BuildPayload(tHistory, tToolDefs, "you are X", tCfg)

    ; contents
    Do $$$AssertTrue(tPayload.%IsDefined("contents"), "Payload has contents key")
    Set tContents = tPayload.%Get("contents")
    Do $$$AssertTrue($IsObject(tContents), "contents is an array")
    Do $$$AssertEquals(tContents.%Size(), 1, "contents has 1 message (the user)")
    Set tMsg0 = tContents.%Get(0)
    Do $$$AssertEquals(tMsg0.%Get("role"), "user", "contents[0].role = user")
    Do $$$AssertTrue(tMsg0.%IsDefined("parts"), "contents[0] has parts")
    Set tParts = tMsg0.%Get("parts")
    Do $$$AssertEquals(tParts.%Get(0).%Get("text"), "hi", "contents[0].parts[0].text = hi")

    ; tools — Gemini wraps ALL tools in ONE element with functionDeclarations[]
    Do $$$AssertTrue(tPayload.%IsDefined("tools"), "Payload has tools key")
    Set tTools = tPayload.%Get("tools")
    Do $$$AssertEquals(tTools.%Size(), 1, "tools has 1 wrapper element (Gemini-specific)")
    Set tWrapper = tTools.%Get(0)
    Do $$$AssertTrue(tWrapper.%IsDefined("functionDeclarations"), "tools[0] has functionDeclarations")
    Set tDecls = tWrapper.%Get("functionDeclarations")
    Do $$$AssertEquals(tDecls.%Size(), 3, "functionDeclarations has 3 entries (per BuildThreeCanonicalTools)")
    Do $$$AssertEquals(tDecls.%Get(0).%Get("name"), "event_log", "functionDeclarations[0].name = event_log")

    ; systemInstruction
    Do $$$AssertTrue(tPayload.%IsDefined("systemInstruction"), "Payload has systemInstruction")
    Set tSysInstr = tPayload.%Get("systemInstruction")
    Do $$$AssertTrue(tSysInstr.%IsDefined("parts"), "systemInstruction has parts")
    Set tSysParts = tSysInstr.%Get("parts")
    Do $$$AssertEquals(tSysParts.%Get(0).%Get("text"), "you are X", "systemInstruction.parts[0].text = system prompt")

    ; generationConfig
    Do $$$AssertTrue(tPayload.%IsDefined("generationConfig"), "Payload has generationConfig")
    Set tGenCfg = tPayload.%Get("generationConfig")
    Do $$$AssertEquals(+tGenCfg.%Get("maxOutputTokens"), tCfg.MaxTokens, "generationConfig.maxOutputTokens from cfg")
    Do $$$AssertEquals(+tGenCfg.%Get("temperature"), tCfg.Temperature, "generationConfig.temperature from cfg")

    ; NFR-S3 — no api key in payload.
    Set tJson = tPayload.%ToJSON()
    Do $$$AssertTrue('(tJson [ "x-goog-api-key"), "Payload JSON does NOT contain x-goog-api-key marker")
    Quit
}

/// <p>AC-8 #6 — feed a stubbed 200 response carrying a
/// <code>parts[].functionCall</code>; assert
/// <code>pProviderResponse.Content</code> is the canonical
/// <code>[{type:"tool_use", id, name, input}]</code> shape via the
/// MessageAdapter back-translation.</p>
Method TestParseResponseFunctionCallToCanonicalToolUse()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockGeminiProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    ; Gemini 200 response carrying a functionCall part.
    Set tMock.MockBodyJson = "{""candidates"":[{""content"":{""role"":""model"",""parts"":[{""functionCall"":{""name"":""event_log"",""args"":{""sessionId"":2114}}}]},""finishReason"":""TOOL_CALLS""}],""usageMetadata"":{""promptTokenCount"":100,""candidatesTokenCount"":20,""totalTokenCount"":120}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("what errors")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK on 200")
    Do $$$AssertEquals(tResp.StopReason, "tool_use", "StopReason = tool_use (TOOL_CALLS → tool_use)")
    Do $$$AssertTrue($IsObject(tResp.Content), "Content is an object")
    Do $$$AssertEquals(tResp.Content.%Size(), 1, "Content has 1 block")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "tool_use", "Content[0].type = tool_use (canonical, translated)")
    Do $$$AssertEquals(tBlock.%Get("name"), "event_log", "Content[0].name = event_log (translated from functionCall.name)")
    Set tInput = tBlock.%Get("input")
    Do $$$AssertEquals(+tInput.%Get("sessionId"), 2114, "Content[0].input.sessionId = 2114 (translated from functionCall.args)")
    ; The MessageAdapter auto-generates "gemini-call-N" ids since Gemini
    ; doesn't return tool_use ids on the wire.
    Do $$$AssertTrue(tBlock.%Get("id") [ "gemini-call-", "Content[0].id has gemini-call- prefix")
    Quit
}

/// <p>AC-8 #7 — <method>TranslateFinishReason</method> maps every Gemini
/// finishReason value to the canonical stopReason vocabulary:
/// STOP→end_turn, MAX_TOKENS→max_tokens, SAFETY→stop_sequence,
/// RECITATION→stop_sequence, OTHER→stop_sequence, TOOL_CALLS→tool_use.</p>
Method TestTranslateFinishReasonAllValues()
{
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("STOP"), "end_turn", "STOP → end_turn")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("MAX_TOKENS"), "max_tokens", "MAX_TOKENS → max_tokens")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("SAFETY"), "stop_sequence", "SAFETY → stop_sequence")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("RECITATION"), "stop_sequence", "RECITATION → stop_sequence")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("OTHER"), "stop_sequence", "OTHER → stop_sequence")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("TOOL_CALLS"), "tool_use", "TOOL_CALLS → tool_use")
    ; Unknown values pass through.
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).TranslateFinishReason("UNKNOWN_FUTURE"), "UNKNOWN_FUTURE", "Unknown values pass through")
    Quit
}

/// <p>AC-8 #8 — <method>ParseGeminiRetryDelay</method> extracts the
/// integer seconds from
/// <code>{"error":{"details":[{"retryDelay":"45s"}]}}</code>.</p>
Method TestParseGeminiRetryDelayHonors429Body()
{
    Set tBody1 = "{""error"":{""code"":429,""message"":""Resource exhausted"",""details"":[{""retryDelay"":""45s""}]}}"
    Set tDelay1 = ##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay(tBody1)
    Do $$$AssertEquals(tDelay1, 45, "Extracts 45 from retryDelay:45s")

    ; Different value to lock the parsing logic, not just the constant.
    Set tBody2 = "{""error"":{""details"":[{""retryDelay"":""3s""}]}}"
    Set tDelay2 = ##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay(tBody2)
    Do $$$AssertEquals(tDelay2, 3, "Extracts 3 from retryDelay:3s")

    ; Missing retryDelay → 0 (fallback to exp backoff).
    Set tBody3 = "{""error"":{""code"":429,""message"":""Resource exhausted"",""details"":[{""reason"":""quota""}]}}"
    Set tDelay3 = ##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay(tBody3)
    Do $$$AssertEquals(tDelay3, 0, "Missing retryDelay returns 0")

    ; No error block → 0.
    Set tBody4 = "{""candidates"":[]}"
    Set tDelay4 = ##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay(tBody4)
    Do $$$AssertEquals(tDelay4, 0, "Body without error block returns 0")

    ; Empty / unparseable → 0.
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay(""), 0, "Empty body returns 0")
    Do $$$AssertEquals(##class(SessionAgent.LLM.GeminiProvider).ParseGeminiRetryDelay("not json"), 0, "Unparseable body returns 0")
    Quit
}

/// <p>AC-8 #9 — when a 429 response BODY has no
/// <code>retryDelay</code> field, the inline retry loop falls back to
/// exp-backoff. Sequenced mock returns 429 (no retryDelay) once, then
/// 200; provider retries and succeeds; CallCount = 2.</p>
Method TestRetryFallsBackToExpBackoffOnMissingRetryDelay()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockGeminiProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    ; Sequence: attempt 1 = 429 with body LACKING retryDelay; attempt 2 = 200.
    Set tMock.SequencedStatusCodes = $ListBuild(429, 200)
    Set tMock.SequencedBodies = $ListBuild(
        "{""error"":{""code"":429,""message"":""rate limited"",""details"":[]}}",
        "{""candidates"":[{""content"":{""role"":""model"",""parts"":[{""text"":""recovered""}]},""finishReason"":""STOP""}],""usageMetadata"":{""promptTokenCount"":50,""candidatesTokenCount"":5,""totalTokenCount"":55}}"
    )

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK after 429-then-200 retry")
    Do $$$AssertEquals(tResp.StopReason, "end_turn", "StopReason = end_turn after recovery (STOP → end_turn)")
    Do $$$AssertEquals(tMock.CallCount, 2, "Mock invoked 2 times (initial + 1 retry)")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "text", "Content[0].type = text")
    Do $$$AssertEquals(tBlock.%Get("text"), "recovered", "Content[0].text = recovered (second-attempt body)")
    Quit
}

/// <p>AC-8 #10 — mock returns
/// <code>usageMetadata.promptTokenCount=100, candidatesTokenCount=20</code>;
/// <code>pProviderResponse.Usage.input_tokens=100,
/// output_tokens=20</code>, cache-tokens=0 (Gemini context-caching out
/// of v1 scope).</p>
Method TestUsagePopulatesCounts()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockGeminiProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""candidates"":[{""content"":{""role"":""model"",""parts"":[{""text"":""ok""}]},""finishReason"":""STOP""}],""usageMetadata"":{""promptTokenCount"":100,""candidatesTokenCount"":20,""totalTokenCount"":120}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK")
    Do $$$AssertTrue($IsObject(tResp.Usage), "Usage is an object")
    Do $$$AssertEquals(+tResp.Usage.%Get("input_tokens"), 100, "Usage.input_tokens = 100 (promptTokenCount)")
    Do $$$AssertEquals(+tResp.Usage.%Get("output_tokens"), 20, "Usage.output_tokens = 20 (candidatesTokenCount)")
    Do $$$AssertEquals(+tResp.Usage.%Get("cache_creation_input_tokens"), 0, "Usage.cache_creation = 0 (Gemini context-caching out of v1 scope)")
    Do $$$AssertEquals(+tResp.Usage.%Get("cache_read_input_tokens"), 0, "Usage.cache_read = 0 (Gemini context-caching out of v1 scope)")
    Quit
}

/// <p>AC-8 #11 — verify <code>gemini</code> is wired into the AgentLoop's
/// provider registry (the
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// switch). Story 5.2 extends the dispatch to include
/// <code>"gemini" -&gt; SessionAgent.LLM.GeminiProvider</code>;
/// this test is the regression lock for AC-9.</p>
Method TestRegistryListProvidersIncludesGemini()
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.Provider = "gemini"
    Set tCfg.AgentName = "gemini-routing-test"
    Set tCfg.Model = "gemini-2.5-flash"

    Set tProv = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfg)

    Do $$$AssertTrue($IsObject(tProv), "InstantiateProvider returns an object for Provider = gemini")
    Do $$$AssertEquals($ClassName(tProv), "SessionAgent.LLM.GeminiProvider", "Returned class is GeminiProvider")

    ; Sanity — anthropic + openai still resolve correctly (no regression
    ; on AC-9 wiring or Story 5.1).
    Set tCfgA = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgA.Provider = "anthropic"
    Set tCfgA.AgentName = "anthropic-routing-sanity"
    Set tProvA = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgA)
    Do $$$AssertEquals($ClassName(tProvA), "SessionAgent.LLM.AnthropicProvider", "anthropic dispatch unchanged")

    Set tCfgO = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgO.Provider = "openai"
    Set tCfgO.AgentName = "openai-routing-sanity"
    Set tProvO = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgO)
    Do $$$AssertEquals($ClassName(tProvO), "SessionAgent.LLM.OpenAIProvider", "openai dispatch unchanged")

    ; Unknown provider → NULLOREF.
    Set tCfgX = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgX.Provider = "no-such-thing"
    Set tCfgX.AgentName = "unknown-routing"
    Set tProvX = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgX)
    Do $$$AssertTrue('$IsObject(tProvX), "Unknown provider returns NULLOREF")
    Quit
}

/// <p>Story 12.2 BUG-02 (AC-1) — when <method>IssueHttpsPost</method>
/// throws (mid-flight HTTP failure), the resulting envelope's message
/// MUST carry both the generic "mid-flight failure" framing AND the
/// captured exception text separated by ": ".</p>
Method TestMidFlightFailureCarriesExceptionText()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockGeminiProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockThrowText = "Connection timed out: read timeout"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hello")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returns OK on mid-flight (envelope-based error)")
    Do $$$AssertEquals(tResp.StopReason, "error", "StopReason = error on mid-flight failure")
    Set tBlock = tResp.Content.%Get(0)
    Set tText = tBlock.%Get("text")
    Do $$$AssertTrue(tText [ "mid-flight failure", "Envelope text contains 'mid-flight failure' framing (got: " _ tText _ ")")
    Do $$$AssertTrue(tText [ ": ", "Envelope text contains ': ' separator (got: " _ tText _ ")")
    Do $$$AssertTrue(tText [ "Connection timed out", "Envelope text carries exception substring (got: " _ tText _ ")")
    Do $$$AssertEquals(tMock.CallCount, 1, "Mock invoked once — mid-flight does NOT retry")
    Quit
}

/// <p>Helper — build a single-message canonical history with one user
/// text block.</p>
ClassMethod BuildSimpleUserHistory(pText As %String) As %DynamicArray [ Internal ]
{
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", pText)
    Do tContent.%Push(tBlock)
    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)
    Quit tHistory
}

/// <p>Helper — build a 3-tool canonical tool-defs array (matches the
/// AnthropicProviderTest helper for cross-provider symmetry).</p>
ClassMethod BuildThreeCanonicalTools() As %DynamicArray [ Internal ]
{
    Set tDefs = ##class(%DynamicArray).%New()
    Set tNames = $ListBuild("event_log", "rule_log", "explain_error")
    Set tI = 1
    While tI <= $ListLength(tNames) {
        Set tName = $ListGet(tNames, tI)
        Set tDef = ##class(%DynamicObject).%New()
        Do tDef.%Set("name", tName)
        Do tDef.%Set("description", "Test tool " _ tName)
        Set tSchema = ##class(%DynamicObject).%New()
        Do tSchema.%Set("type", "object")
        Set tProps = ##class(%DynamicObject).%New()
        Do tProps.%Set("sessionId", ##class(%DynamicObject).%FromJSON("{""type"":""integer""}"))
        Do tSchema.%Set("properties", tProps)
        Do tDef.%Set("input_schema", tSchema)
        Do tDefs.%Push(tDef)
        Set tI = tI + 1
    }
    Quit tDefs
}

/// <p>Helper — build a transient (in-memory, never %Save'd)
/// <CLASS>SessionAgent.Config.Agent</CLASS> for the mock-driven tests.
/// Sets EnvVarName=PATH so EnvSecret.Resolve returns a non-empty value
/// and the credential-missing fast path is not engaged.</p>
ClassMethod BuildTransientConfigAgent() As SessionAgent.Config.Agent [ Internal ]
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "test-gemini-agent"
    Set tCfg.Provider = "gemini"
    Set tCfg.Model = "gemini-2.5-flash"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1000
    Set tCfg.EnvVarName = "PATH"
    Set tCfg.CredentialName = ""
    Set tCfg.EndpointUrl = ""
    Set tCfg.Enabled = 1
    Set tCfg.ReadOnly = 1
    Quit tCfg
}

}
