/// <p>Unit tests for <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>
/// (Story 2.9). Locks the OpenAI Chat Completions wire contract: payload
/// shape, auth-header format, finish_reason translation, retry envelope,
/// and the NFR-C2 schema-level <code>Language = python</code> ban.</p>
///
/// <p><b>AC-3 method coverage (8 methods):</b></p>
/// <ol>
/// <li><b>TestGetProviderNameReturnsOpenai</b></li>
/// <li><b>TestGetAuthHeaderFormat</b></li>
/// <li><b>TestBuildPayloadShape</b></li>
/// <li><b>TestSystemPromptPrependedAsSystemRoleMessage</b></li>
/// <li><b>TestCallMessagesWith200Response</b> (uses
/// <CLASS>MockOpenAIProvider</CLASS> below)</li>
/// <li><b>TestCallMessagesWith429TriggersRetryEnvelope</b> (uses
/// <CLASS>MockOpenAIProvider</CLASS> below; <code>BaseDelaySec=0</code>
/// fast path via <method>RetryWithBackoff.ExecuteWithParams</method>
/// kept inline within the prod orchestration — accepting the genuine 4
/// invocations within unit-test budget per
/// <method>RetryWithBackoff.ExpBackoffSec</method> jitter caps; no real
/// HTTP because <method>IssueHttpsPost</method> is overridden)</li>
/// <li><b>TestFinishReasonTranslation</b></li>
/// <li><b>TestNoLanguagePythonInClass</b></li>
/// </ol>
///
/// <p><b>Mock-HTTP strategy.</b> Story 2.9 dev choice — option C from the
/// story Dev Notes: extract <method>IssueHttpsPost</method> on the
/// production class, then subclass it in this test file with an override
/// that returns a canned response. No process-private global mutation, no
/// factory hook, no real network.</p>
Class SessionAgent.Test.OpenAIProviderTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-3 #1 — <method>GetProviderName</method> returns
/// <code>"openai"</code>.</p>
Method TestGetProviderNameReturnsOpenai()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Do $$$AssertEquals(tProv.GetProviderName(), "openai", "GetProviderName returns openai")
    Quit
}

/// <p>AC-3 #2 — <method>GetAuthHeader</method> returns
/// <code>"Bearer &lt;key&gt;"</code> format. The Authorization header
/// name is set separately via
/// <method>%Net.HttpRequest.SetHeader</method>; this method returns only
/// the value.</p>
Method TestGetAuthHeaderFormat()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Do $$$AssertEquals(tProv.GetAuthHeader("sk-abc"), "Bearer sk-abc", "GetAuthHeader returns Bearer + key")
    Quit
}

/// <p>AC-3 #3 — <method>BuildPayload</method> produces the 5 required
/// keys (<code>model</code>, <code>temperature</code>,
/// <code>max_tokens</code>, <code>messages</code>, <code>tools</code>),
/// does NOT contain any <code>apiKey</code>/<code>api_key</code> field,
/// and does NOT contain <code>cache_control</code> markers.</p>
Method TestBuildPayloadShape()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("hello")
    Set tToolDefs = ##class(%DynamicArray).%New()

    ; Build a transient Config.Agent (not %Save'd) for the payload-build
    ; pass. BuildPayload reads model/temperature/max_tokens off it.
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.Model = "gpt-4.1-mini"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1000

    Set tPayload = tProv.BuildPayload(tHistory, tToolDefs, "", tCfg)

    Do $$$AssertTrue(tPayload.%IsDefined("model"), "payload has model key")
    Do $$$AssertTrue(tPayload.%IsDefined("temperature"), "payload has temperature key")
    Do $$$AssertTrue(tPayload.%IsDefined("max_tokens"), "payload has max_tokens key")
    Do $$$AssertTrue(tPayload.%IsDefined("messages"), "payload has messages key")
    Do $$$AssertTrue(tPayload.%IsDefined("tools"), "payload has tools key")

    Do $$$AssertEquals(tPayload.%Get("model"), "gpt-4.1-mini", "model = gpt-4.1-mini")
    Do $$$AssertEquals(+tPayload.%Get("max_tokens"), 1000, "max_tokens = 1000")

    ; NFR-S3 — never embed the api key in the payload.
    Do $$$AssertTrue('tPayload.%IsDefined("apiKey"), "payload does NOT have apiKey field")
    Do $$$AssertTrue('tPayload.%IsDefined("api_key"), "payload does NOT have api_key field")

    ; OpenAI auto-caches >= 1024 tokens — no per-call cache_control.
    Do $$$AssertTrue('tPayload.%IsDefined("cache_control"), "payload does NOT have cache_control field")

    ; Sanity — also verify the JSON serialization carries no api key reference.
    Set tJson = tPayload.%ToJSON()
    Do $$$AssertTrue('(tJson [ "apiKey"), "JSON does not contain apiKey substring (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ "api_key"), "JSON does not contain api_key substring (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ "Bearer"), "JSON does not contain Bearer substring")
    Do $$$AssertTrue('(tJson [ "cache_control"), "JSON does not contain cache_control substring")
    Quit
}

/// <p>AC-3 #4 — when <var>pSystemPrompt</var> is non-empty, the first
/// element of <code>messages</code> is
/// <code>{role:"system", content:&lt;prompt&gt;}</code>.</p>
Method TestSystemPromptPrependedAsSystemRoleMessage()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Set tHistory = ..BuildSimpleUserHistory("user message")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.Model = "gpt-4.1-mini"
    Set tCfg.MaxTokens = 1000

    Set tPayload = tProv.BuildPayload(tHistory, tToolDefs, "you are X", tCfg)
    Set tMessages = tPayload.%Get("messages")

    Do $$$AssertTrue(tMessages.%Size() >= 2, "messages has at least 2 entries (system + user)")
    Set tSystem = tMessages.%Get(0)
    Do $$$AssertEquals(tSystem.%Get("role"), "system", "messages[0].role = system")
    Do $$$AssertEquals(tSystem.%Get("content"), "you are X", "messages[0].content = system prompt verbatim")

    Set tUser = tMessages.%Get(1)
    Do $$$AssertEquals(tUser.%Get("role"), "user", "messages[1].role = user (history preserved after system)")
    Quit
}

/// <p>AC-3 #5 — feed a stubbed 200 response through the
/// <CLASS>MockOpenAIProvider</CLASS> override. Assert
/// <code>pProviderResponse.Content[0].type = "text"</code> and
/// <code>StopReason = "end_turn"</code>.</p>
Method TestCallMessagesWith200Response()
{
    Set tCfg = ..BuildTransientConfigAgent()

    Set tMock = ##class(SessionAgent.Test.MockOpenAIProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""finish_reason"":""stop"",""message"":{""role"":""assistant"",""content"":""hi back""}}],""usage"":{""prompt_tokens"":10,""completion_tokens"":3}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hello")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK on 200")
    Do $$$AssertEquals(tResp.StopReason, "end_turn", "StopReason = end_turn (mapped from stop)")
    Do $$$AssertTrue($IsObject(tResp.Content), "Content is an object")
    Do $$$AssertTrue(tResp.Content.%Size() >= 1, "Content has at least 1 block")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "text", "Content[0].type = text")
    Do $$$AssertEquals(tBlock.%Get("text"), "hi back", "Content[0].text preserved")
    Quit
}

/// <p>AC-3 #6 — feed a stubbed 429 response. The retry orchestrator
/// (<method>SessionAgent.Util.RetryWithBackoff.Execute</method>) drives 4
/// attempts (per class parameter MaxAttempts=4); each is intercepted by
/// the mock; on exhaustion <method>CallMessages</method> populates a
/// structured error envelope with <code>StopReason = "error"</code>.</p>
///
/// <p><b>Test budget.</b> RetryWithBackoff backs off with full-jitter
/// exponential up to MaxDelaySec=32s per attempt. Allowing the production
/// schedule to drive 4 attempts could cost up to ~60s in worst case
/// (uniform random over [0, 1+2+4+8]). The mock exits immediately, so
/// the dominant cost is the Hang interval. We accept the variance: the
/// test wall time is bounded by the 32s cap.</p>
Method TestCallMessagesWith429TriggersRetryEnvelope()
{
    Set tCfg = ..BuildTransientConfigAgent()

    Set tMock = ##class(SessionAgent.Test.MockOpenAIProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 429
    Set tMock.MockBodyJson = "{""error"":{""message"":""rate limited""}}"
    ; Set Retry-After to 0 to keep the wall-time bounded — the orchestrator
    ; takes max(provider hint, exp backoff); exp backoff caps at 1s for
    ; attempts 0+1, 2s for attempt 2, 4s for attempt 3 with our overridden
    ; small caps. We override via the BaseDelaySec/MaxDelaySec params
    ; below.
    Set tMock.MockHeaderRetryAfter = "0"
    Set tMock.UseFastRetryParams = 1

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hello")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returned $$$OK even on retry exhaustion (envelope-based error)")
    Do $$$AssertEquals(tResp.StopReason, "error", "StopReason = error after retry exhaustion")
    Do $$$AssertTrue($IsObject(tResp.Content), "Content is an object on error envelope")
    Set tBlock = tResp.Content.%Get(0)
    Do $$$AssertEquals(tBlock.%Get("type"), "text", "Error envelope Content[0].type = text")
    ; The error message identifies HTTP 429 + retries-exhausted.
    Set tText = tBlock.%Get("text")
    Do $$$AssertTrue(tText [ "429", "Error text mentions HTTP 429 (got: " _ tText _ ")")

    ; Verify the mock was invoked the expected MaxAttempts=4 times by
    ; reading the call counter the mock increments inside IssueHttpsPost.
    Do $$$AssertEquals(tMock.CallCount, 4, "Mock invoked 4 times (MaxAttempts) before exhaustion")
    Quit
}

/// <p>AC-3 #7 — finish_reason translation:
/// <code>stop</code>→<code>end_turn</code>;
/// <code>length</code>→<code>max_tokens</code>;
/// <code>tool_calls</code>→<code>tool_use</code>;
/// <code>content_filter</code>→<code>stop_sequence</code>.</p>
///
/// <p>Drives translation through the
/// <method>SessionAgent.LLM.Util.MessageAdapter.MapOpenAiFinishReason</method>
/// helper indirectly, by feeding 4 stub bodies and asserting the
/// resulting <CLASS>SessionAgent.Agent.ProviderResponse.StopReason</CLASS>.</p>
Method TestFinishReasonTranslation()
{
    Do ..AssertFinishReasonMaps("stop", "end_turn", "stop -> end_turn")
    Do ..AssertFinishReasonMaps("length", "max_tokens", "length -> max_tokens")
    Do ..AssertFinishReasonMaps("tool_calls", "tool_use", "tool_calls -> tool_use")
    Do ..AssertFinishReasonMaps("content_filter", "stop_sequence", "content_filter -> stop_sequence")
    Quit
}

/// <p>AC-3 #8 — schema-level enforcement of NFR-C2: no method on
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> declares
/// <code>Language = "python"</code>. Verifies via
/// <CLASS>%Dictionary.MethodDefinition</CLASS> query.</p>
Method TestNoLanguagePythonInClass()
{
    Set tCount = 0
    Set tRS = ##class(%ResultSet).%New("%Dictionary.MethodDefinition:Summary")
    Do tRS.Execute("SessionAgent.LLM.OpenAIProvider")
    While tRS.Next() {
        Set tName = tRS.Get("Name")
        Set tDef = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.LLM.OpenAIProvider||" _ tName)
        If $IsObject(tDef) {
            If $ZConvert(tDef.Language, "L") = "python" {
                Set tCount = tCount + 1
            }
        }
    }
    Do tRS.%Close()
    Do $$$AssertEquals(tCount, 0, "No methods on OpenAIProvider declare Language = python")
    Quit
}

/// <p>Story 12.2 BUG-02 (AC-1) — when <method>IssueHttpsPost</method>
/// throws (mid-flight HTTP failure), the resulting envelope's message
/// MUST carry both the generic "mid-flight failure" framing AND the
/// captured exception text separated by ": ". Drives the catch path
/// via <property>MockThrowText</property>.</p>
Method TestMidFlightFailureCarriesExceptionText()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockOpenAIProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockThrowText = "SSL handshake failed: certificate has expired"

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
    Do $$$AssertTrue(tText [ "SSL handshake failed", "Envelope text carries exception substring (got: " _ tText _ ")")
    Do $$$AssertEquals(tMock.CallCount, 1, "Mock invoked once — mid-flight does NOT retry")
    Quit
}

/// <p>Helper — drives one finish_reason translation through the mock and
/// asserts the canonical stopReason maps as expected.</p>
Method AssertFinishReasonMaps(pFinish As %String, pExpected As %String, pMsg As %String) [ Internal ]
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tMock = ##class(SessionAgent.Test.MockOpenAIProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""finish_reason"":""" _ pFinish _ """,""message"":{""role"":""assistant"",""content"":""ok""}}]}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("x")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()
    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)
    Do $$$AssertStatusOK(tSC, pMsg _ ": CallMessages returned $$$OK")
    Do $$$AssertEquals(tResp.StopReason, pExpected, pMsg)
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

/// <p>Helper — build a transient (in-memory, never %Save'd)
/// <CLASS>SessionAgent.Config.Agent</CLASS> for the mock-driven tests.
/// Sets only the fields BuildPayload + CallMessages read; other fields
/// stay at their property defaults.</p>
ClassMethod BuildTransientConfigAgent() As SessionAgent.Config.Agent [ Internal ]
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "test-agent"
    Set tCfg.Provider = "openai"
    Set tCfg.Model = "gpt-4.1-mini"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1000
    ; Set EnvVarName to a name we know is set, so the api-key resolve
    ; in CallMessages succeeds and the credential-missing fast-path is
    ; not engaged. PATH is universally present.
    Set tCfg.EnvVarName = "PATH"
    Set tCfg.CredentialName = ""
    Set tCfg.EndpointUrl = ""
    Set tCfg.Enabled = 1
    Set tCfg.ReadOnly = 1
    Quit tCfg
}

}
