/// <p>Unit tests for <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS>
/// (Story 5.1). Locks the Anthropic Messages wire contract: payload shape
/// (system + tools cache_control placement, no cache_control on user
/// messages — NFR-P6), two-header auth, retry envelope honoring
/// Retry-After, response parsing including the four cache-token usage
/// keys, and the credential-missing fast path.</p>
///
/// <p><b>AC-7 method coverage (11 methods):</b></p>
/// <ol>
/// <li><b>TestProviderNameIsAnthropic</b></li>
/// <li><b>TestEndpointDefaultAndOverride</b></li>
/// <li><b>TestAuthHeaderShape</b></li>
/// <li><b>TestPayloadCacheControlOnSystem</b></li>
/// <li><b>TestPayloadCacheControlOnLastTool</b></li>
/// <li><b>TestPayloadNoCacheControlOnUserMessages</b> — NFR-P6 lock</li>
/// <li><b>TestParseResponseToolUseBlocksPassThrough</b></li>
/// <li><b>TestRetryHonorsRetryAfter429</b></li>
/// <li><b>TestUsagePopulatesCacheTokens</b></li>
/// <li><b>TestAuthFailureReturnsErrorStatus</b></li>
/// <li><b>TestRegistryListProvidersIncludesAnthropic</b></li>
/// </ol>
///
/// <p><b>Mock-HTTP strategy.</b> Same as
/// <CLASS>SessionAgent.Test.OpenAIProviderTest</CLASS> — subclass
/// <CLASS>SessionAgent.Test.MockAnthropicProvider</CLASS> overrides
/// <method>IssueHttpsPost</method>; production class is unchanged.</p>
Class SessionAgent.Test.AnthropicProviderTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-7 #1 — <method>GetProviderName</method> returns
/// <code>"anthropic"</code>.</p>
Method TestProviderNameIsAnthropic()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Do $$$AssertEquals(tProv.GetProviderName(), "anthropic", "GetProviderName returns anthropic")
    Quit
}

/// <p>AC-7 #2 — <method>GetEndpointUrl</method> returns the default
/// canonical Anthropic URL when ConfigAgent.EndpointUrl is empty, and
/// the override when set.</p>
Method TestEndpointDefaultAndOverride()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()

    ; No ConfigAgent — default.
    Do $$$AssertEquals(tProv.GetEndpointUrl(), "https://api.anthropic.com/v1/messages", "Default endpoint when ConfigAgent unset")

    ; ConfigAgent set, EndpointUrl empty — default.
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.EndpointUrl = ""
    Set tProv.ConfigAgent = tCfg
    Do $$$AssertEquals(tProv.GetEndpointUrl(), "https://api.anthropic.com/v1/messages", "Default endpoint when EndpointUrl empty")

    ; Override.
    Set tCfg.EndpointUrl = "https://proxy.example.com/v1/messages"
    Do $$$AssertEquals(tProv.GetEndpointUrl(), "https://proxy.example.com/v1/messages", "EndpointUrl override honored")
    Quit
}

/// <p>AC-7 #3 — <method>GetAuthHeader</method> returns a $ListBuild list
/// of TWO header lines: <code>x-api-key: &lt;key&gt;</code> +
/// <code>anthropic-version: 2023-06-01</code>.</p>
Method TestAuthHeaderShape()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Set tList = tProv.GetAuthHeader("test-key-abc")

    Do $$$AssertEquals($ListLength(tList), 2, "Two header lines returned")
    Do $$$AssertEquals($ListGet(tList, 1), "x-api-key: test-key-abc", "Header 1 = x-api-key + key")
    Do $$$AssertEquals($ListGet(tList, 2), "anthropic-version: 2023-06-01", "Header 2 = anthropic-version: 2023-06-01")

    ; NFR-S3 — the api key is in element 1, never in element 2 / never persisted.
    Do $$$AssertTrue($ListGet(tList, 1) [ "test-key-abc", "Key appears in x-api-key header line")
    Do $$$AssertTrue('($ListGet(tList, 2) [ "test-key-abc"), "Key does NOT appear in anthropic-version line")
    Quit
}

/// <p>AC-7 #4 — payload's <code>system</code> is the array-of-blocks form
/// with <code>cache_control: {type:"ephemeral"}</code> when
/// <code>CacheConfig.SystemEnabled = 1</code>; plain string form when
/// <code>0</code>; absent when system prompt is empty.</p>
Method TestPayloadCacheControlOnSystem()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCfg = ..BuildTransientConfigAgent()

    ; Case A: SystemEnabled=1 — array-of-blocks with cache_control.
    Set tCacheOn = ##class(%DynamicObject).%New()
    Do tCacheOn.%Set("SystemEnabled", 1)
    Set tPayloadOn = tProv.BuildPayload(tHistory, tToolDefs, "you are X", tCacheOn, tCfg)
    Set tSysOn = tPayloadOn.%Get("system")
    Do $$$AssertTrue($IsObject(tSysOn), "SystemEnabled=1: system is object/array (not string)")
    Do $$$AssertEquals(tSysOn.%Size(), 1, "SystemEnabled=1: one system block")
    Set tBlock = tSysOn.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "text", "SystemEnabled=1: block.type = text")
    Do $$$AssertEquals(tBlock.%Get("text"), "you are X", "SystemEnabled=1: block.text = system prompt")
    Do $$$AssertTrue(tBlock.%IsDefined("cache_control"), "SystemEnabled=1: block has cache_control")
    Set tCC = tBlock.%Get("cache_control")
    Do $$$AssertEquals(tCC.%Get("type"), "ephemeral", "SystemEnabled=1: cache_control.type = ephemeral")

    ; Case B: SystemEnabled=0 — plain string form.
    Set tCacheOff = ##class(%DynamicObject).%New()
    Do tCacheOff.%Set("SystemEnabled", 0)
    Set tPayloadOff = tProv.BuildPayload(tHistory, tToolDefs, "you are X", tCacheOff, tCfg)
    Do $$$AssertEquals(tPayloadOff.%Get("system"), "you are X", "SystemEnabled=0: system is plain string")

    ; Sanity — JSON serialization carries no cache_control when SystemEnabled=0.
    Set tJson = tPayloadOff.%ToJSON()
    Do $$$AssertTrue('(tJson [ "cache_control"), "SystemEnabled=0 + no tools: no cache_control in JSON")

    ; Case C: empty system prompt — no system field at all.
    Set tPayloadEmpty = tProv.BuildPayload(tHistory, tToolDefs, "", tCacheOn, tCfg)
    Do $$$AssertTrue('tPayloadEmpty.%IsDefined("system"), "Empty system prompt: no system field")
    Quit
}

/// <p>AC-7 #5 — payload's <code>tools[len-1]</code> carries
/// <code>cache_control</code> when <code>CacheConfig.ToolsEnabled = 1</code>;
/// preceding tools do NOT.</p>
Method TestPayloadCacheControlOnLastTool()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ..BuildThreeCanonicalTools()
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCacheOn = ##class(%DynamicObject).%New()
    Do tCacheOn.%Set("ToolsEnabled", 1)

    Set tPayload = tProv.BuildPayload(tHistory, tToolDefs, "", tCacheOn, tCfg)
    Set tTools = tPayload.%Get("tools")
    Do $$$AssertEquals(tTools.%Size(), 3, "Three tools in payload")

    Set tT0 = tTools.%Get(0)
    Set tT1 = tTools.%Get(1)
    Set tT2 = tTools.%Get(2)
    Do $$$AssertTrue('tT0.%IsDefined("cache_control"), "tools[0] has NO cache_control")
    Do $$$AssertTrue('tT1.%IsDefined("cache_control"), "tools[1] has NO cache_control")
    Do $$$AssertTrue(tT2.%IsDefined("cache_control"), "tools[2] (last) HAS cache_control")
    Set tCC = tT2.%Get("cache_control")
    Do $$$AssertEquals(tCC.%Get("type"), "ephemeral", "tools[2].cache_control.type = ephemeral")

    ; Case B: ToolsEnabled=0 — none have cache_control.
    Set tCacheOff = ##class(%DynamicObject).%New()
    Do tCacheOff.%Set("ToolsEnabled", 0)
    Set tPayloadOff = tProv.BuildPayload(tHistory, tToolDefs, "", tCacheOff, tCfg)
    Set tToolsOff = tPayloadOff.%Get("tools")
    Set tIdx = 0
    While tIdx < tToolsOff.%Size() {
        Set tTool = tToolsOff.%Get(tIdx)
        Do $$$AssertTrue('tTool.%IsDefined("cache_control"), "ToolsEnabled=0: tools[" _ tIdx _ "] has NO cache_control")
        Set tIdx = tIdx + 1
    }
    Quit
}

/// <p>AC-7 #6 — <b>NFR-P6 lock</b>: user messages in the payload's
/// <code>messages[]</code> array carry NO <code>cache_control</code>
/// field. The vocabulary digest (Epic 9) sits in the user-message prefix
/// and is intentionally uncached; this test prevents a future change from
/// silently sticking a marker on a user message and corrupting the cache
/// plan.</p>
Method TestPayloadNoCacheControlOnUserMessages()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("vocab digest + question")
    Set tToolDefs = ..BuildThreeCanonicalTools()
    Set tCfg = ..BuildTransientConfigAgent()

    ; Drive with maximum cache enabled — system + tools both on. Even
    ; with both flags, NO user message should carry cache_control.
    Set tCache = ##class(%DynamicObject).%New()
    Do tCache.%Set("SystemEnabled", 1)
    Do tCache.%Set("ToolsEnabled", 1)

    Set tPayload = tProv.BuildPayload(tHistory, tToolDefs, "you are X", tCache, tCfg)
    Set tMessages = tPayload.%Get("messages")

    Do $$$AssertTrue($IsObject(tMessages), "messages is an array")
    Set tIdx = 0
    While tIdx < tMessages.%Size() {
        Set tMsg = tMessages.%Get(tIdx)
        Do $$$AssertTrue('tMsg.%IsDefined("cache_control"), "messages[" _ tIdx _ "] (role " _ tMsg.%Get("role") _ ") has NO cache_control")

        ; Walk content blocks too — a future regression could put the
        ; marker on a content block (level deeper).
        If tMsg.%IsDefined("content") {
            Set tContent = tMsg.%Get("content")
            If $IsObject(tContent), $ClassName(tContent) [ "DynamicArray" {
                Set tBIdx = 0
                While tBIdx < tContent.%Size() {
                    Set tBlock = tContent.%Get(tBIdx)
                    If $IsObject(tBlock) {
                        Do $$$AssertTrue('tBlock.%IsDefined("cache_control"), "messages[" _ tIdx _ "].content[" _ tBIdx _ "] has NO cache_control")
                    }
                    Set tBIdx = tBIdx + 1
                }
            }
        }
        Set tIdx = tIdx + 1
    }
    Quit
}

/// <p>AC-7 #7 — feed a stubbed 200 response carrying a tool_use block;
/// assert <code>pProviderResponse.Content</code> mirrors the Anthropic
/// content array verbatim (FR27 passthrough — no translation).</p>
Method TestParseResponseToolUseBlocksPassThrough()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockAnthropicProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""id"":""msg_1"",""type"":""message"",""role"":""assistant"",""model"":""claude-haiku-4-5-20251001"",""content"":[{""type"":""tool_use"",""id"":""toolu_42"",""name"":""event_log"",""input"":{""sessionId"":2114}}],""stop_reason"":""tool_use"",""usage"":{""input_tokens"":100,""output_tokens"":20,""cache_creation_input_tokens"":0,""cache_read_input_tokens"":0}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("what errors")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK on 200")
    Do $$$AssertEquals(tResp.StopReason, "tool_use", "StopReason = tool_use (passthrough)")
    Do $$$AssertTrue($IsObject(tResp.Content), "Content is an object")
    Do $$$AssertEquals(tResp.Content.%Size(), 1, "Content has 1 block")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "tool_use", "Content[0].type = tool_use (passthrough)")
    Do $$$AssertEquals(tBlock.%Get("id"), "toolu_42", "Content[0].id passthrough")
    Do $$$AssertEquals(tBlock.%Get("name"), "event_log", "Content[0].name passthrough")
    Set tInput = tBlock.%Get("input")
    Do $$$AssertEquals(+tInput.%Get("sessionId"), 2114, "Content[0].input.sessionId passthrough")
    Quit
}

/// <p>AC-7 #8 — sequenced mock returns 429 with Retry-After:0 once, then
/// 200; provider retries and succeeds; total IssueHttpsPost calls = 2.</p>
Method TestRetryHonorsRetryAfter429()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockAnthropicProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockHeaderRetryAfter = "0"
    ; Sequence: attempt 1 = 429 with rate-limit body; attempt 2 = 200.
    Set tMock.SequencedStatusCodes = $ListBuild(429, 200)
    Set tMock.SequencedBodies = $ListBuild(
        "{""error"":{""type"":""rate_limit_error"",""message"":""rate limited""}}",
        "{""id"":""msg_2"",""type"":""message"",""role"":""assistant"",""model"":""claude-haiku-4-5-20251001"",""content"":[{""type"":""text"",""text"":""recovered""}],""stop_reason"":""end_turn"",""usage"":{""input_tokens"":50,""output_tokens"":5,""cache_creation_input_tokens"":0,""cache_read_input_tokens"":0}}"
    )

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK after 429-then-200 retry")
    Do $$$AssertEquals(tResp.StopReason, "end_turn", "StopReason = end_turn after recovery")
    Do $$$AssertEquals(tMock.CallCount, 2, "Mock invoked 2 times (initial + 1 retry)")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("text"), "recovered", "Content[0].text = recovered (second-attempt body)")
    Quit
}

/// <p>AC-7 #9 — mock returns a usage block carrying all four cache-token
/// keys; <code>pProviderResponse.Usage</code> carries each value.</p>
Method TestUsagePopulatesCacheTokens()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockAnthropicProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""id"":""msg_3"",""type"":""message"",""role"":""assistant"",""model"":""claude-haiku-4-5-20251001"",""content"":[{""type"":""text"",""text"":""ok""}],""stop_reason"":""end_turn"",""usage"":{""input_tokens"":1000,""output_tokens"":50,""cache_creation_input_tokens"":500,""cache_read_input_tokens"":300}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK")
    Do $$$AssertTrue($IsObject(tResp.Usage), "Usage is an object")
    Do $$$AssertEquals(+tResp.Usage.%Get("input_tokens"), 1000, "Usage.input_tokens = 1000")
    Do $$$AssertEquals(+tResp.Usage.%Get("output_tokens"), 50, "Usage.output_tokens = 50")
    Do $$$AssertEquals(+tResp.Usage.%Get("cache_creation_input_tokens"), 500, "Usage.cache_creation_input_tokens = 500")
    Do $$$AssertEquals(+tResp.Usage.%Get("cache_read_input_tokens"), 300, "Usage.cache_read_input_tokens = 300")
    Quit
}

/// <p>AC-7 #10 — when <method>SessionAgent.Util.EnvSecret.Resolve</method>
/// returns empty (env-var unset, no credential), CallMessages returns the
/// structured-error envelope without any network call (CallCount = 0).</p>
Method TestAuthFailureReturnsErrorStatus()
{
    ; Build a config that points at an env-var the OS does NOT have set
    ; AND a credential name that does NOT exist.
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "test-anthropic-noauth"
    Set tCfg.Provider = "anthropic"
    Set tCfg.Model = "claude-haiku-4-5-20251001"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1000
    Set tCfg.EnvVarName = "DOES_NOT_EXIST_ANTHROPIC_KEY_FOR_TEST_5_1"
    Set tCfg.CredentialName = "DoesNotExistCredential511"
    Set tCfg.EndpointUrl = ""

    Set tMock = ##class(SessionAgent.Test.MockAnthropicProvider).%New()
    Set tMock.ConfigAgent = tCfg
    ; If the credential-missing fast path mistakenly issues a network call,
    ; the mock would intercept it; we assert CallCount = 0.

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returns $$$OK (errors flow via envelope)")
    Do $$$AssertEquals(tMock.CallCount, 0, "No network call when credential missing")
    Do $$$AssertEquals(tResp.StopReason, "error", "StopReason = error on credential-missing")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertTrue(tBlock.%Get("text") [ "credential", "Error text mentions credential")
    Quit
}

/// <p>AC-7 #11 — verify <code>anthropic</code> is wired into the
/// AgentLoop's provider registry (the
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// switch). Story 5.1 extends the dispatch to include
/// <code>"anthropic" -&gt; SessionAgent.LLM.AnthropicProvider</code>;
/// this test is the regression lock for AC-9.</p>
Method TestRegistryListProvidersIncludesAnthropic()
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.Provider = "anthropic"
    Set tCfg.AgentName = "anthropic-routing-test"
    Set tCfg.Model = "claude-haiku-4-5-20251001"

    Set tProv = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfg)

    Do $$$AssertTrue($IsObject(tProv), "InstantiateProvider returns an object for Provider = anthropic")
    Do $$$AssertEquals($ClassName(tProv), "SessionAgent.LLM.AnthropicProvider", "Returned class is AnthropicProvider")

    ; Also sanity-verify the existing openai dispatch still resolves to
    ; OpenAIProvider (no regression on AC-9 wiring).
    Set tCfgOA = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgOA.Provider = "openai"
    Set tCfgOA.AgentName = "openai-routing-sanity"
    Set tProvOA = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgOA)
    Do $$$AssertEquals($ClassName(tProvOA), "SessionAgent.LLM.OpenAIProvider", "openai dispatch unchanged")

    ; Unknown provider → NULLOREF (no regression on the "Unsupported provider"
    ; envelope path).
    Set tCfgX = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgX.Provider = "no-such-thing"
    Set tCfgX.AgentName = "unknown-routing"
    Set tProvX = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgX)
    Do $$$AssertTrue('$IsObject(tProvX), "Unknown provider returns NULLOREF (passthrough to unsupported envelope)")
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

/// <p>Helper — build a 3-tool canonical tool-defs array (last-tool
/// cache_control assertion needs &gt;1 tool to be non-trivial).</p>
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
    Set tCfg.AgentName = "test-anthropic-agent"
    Set tCfg.Provider = "anthropic"
    Set tCfg.Model = "claude-haiku-4-5-20251001"
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
