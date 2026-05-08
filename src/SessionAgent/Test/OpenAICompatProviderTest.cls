/// <p>Unit tests for <CLASS>SessionAgent.LLM.OpenAICompatProvider</CLASS>
/// (Story 5.3). Locks the openai-compatible wire contract: payload shape
/// (OpenAI Chat Completions — model/messages/tools/max_tokens/temperature),
/// HTTP/HTTPS scheme auto-detection from EndpointUrl, optional-auth
/// handling (empty key ⇒ no Authorization header), endpoint-validation
/// fast path when EndpointUrl is empty, response parsing through the
/// shared MessageAdapter "openai" switch case, AC-7 ParseEndpointUrl
/// non-default-port handling, and AgentLoop registry routing.</p>
///
/// <p><b>AC-8 method coverage (11 methods):</b></p>
/// <ol>
/// <li><b>TestProviderNameIsOpenAICompatible</b></li>
/// <li><b>TestEndpointEmptyReturnsStructuredError</b></li>
/// <li><b>TestEndpointHttpSchemeNoSslConfig</b></li>
/// <li><b>TestEndpointHttpsSchemeWithSslConfig</b></li>
/// <li><b>TestAuthHeaderEmptyKeyOmitsHeader</b></li>
/// <li><b>TestAuthHeaderNonEmptyKeyAddsBearer</b></li>
/// <li><b>TestPayloadShapeOpenAIChatCompletions</b></li>
/// <li><b>TestParseResponseToolCallToCanonicalToolUse</b></li>
/// <li><b>TestUsagePopulatesPromptAndCompletionTokens</b></li>
/// <li><b>TestParseEndpointUrlNonDefaultPort</b></li>
/// <li><b>TestRegistryListProvidersIncludesOpenAICompatible</b></li>
/// </ol>
Class SessionAgent.Test.OpenAICompatProviderTest Extends %UnitTest.TestCase
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
/// <code>"openai-compatible"</code>.</p>
Method TestProviderNameIsOpenAICompatible()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAICompatProvider).%New()
    Do $$$AssertEquals(tProv.GetProviderName(), "openai-compatible", "GetProviderName returns openai-compatible")
    Quit
}

/// <p>AC-8 #2 — when <code>Config.Agent.EndpointUrl=""</code>,
/// <method>CallMessages</method> returns the structured-error envelope
/// with the operator-friendly text (per AC-5 step 1) WITHOUT issuing any
/// network call (CallCount = 0).</p>
Method TestEndpointEmptyReturnsStructuredError()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "" ; explicit

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()
    Set tCacheConfig = ##class(%DynamicObject).%New()

    Set tSC = tMock.CallMessages(tHistory, tToolDefs, "", tCacheConfig, .tResp)

    Do $$$AssertStatusOK(tSC, "CallMessages returns $$$OK (errors flow via envelope)")
    Do $$$AssertEquals(tMock.CallCount, 0, "No network call when EndpointUrl empty")
    Do $$$AssertEquals(tResp.StopReason, "error", "StopReason = error on empty endpoint")
    Set tBlock = tResp.Content.%Get(0)
    Set tText = tBlock.%Get("text")
    Do $$$AssertTrue(tText [ "EndpointUrl", "Error text mentions EndpointUrl")
    Do $$$AssertTrue(tText [ "11434", "Error text includes example URL with port 11434")
    Quit
}

/// <p>AC-8 #3 — endpoint <code>http://localhost:11434/v1/chat/completions</code>
/// triggers <code>Https=0</code> + no SSLConfiguration (the production
/// code path skips SSLConfiguration entirely when scheme is HTTP).</p>
Method TestEndpointHttpSchemeNoSslConfig()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""id"":""x"",""choices"":[{""message"":{""role"":""assistant"",""content"":""hello""},""finish_reason"":""stop""}],""usage"":{""prompt_tokens"":1,""completion_tokens"":1}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()

    Do tMock.CallMessages(tHistory, tToolDefs, "", ##class(%DynamicObject).%New(), .tResp)

    Do $$$AssertEquals(tMock.LastHttps, 0, "Https=0 for http:// scheme")
    Do $$$AssertEquals(tMock.LastPort, 11434, "Port=11434 parsed from URL")
    Do $$$AssertEquals(tMock.LastServer, "localhost", "Server=localhost (no port suffix)")
    Quit
}

/// <p>AC-8 #4 — endpoint <code>https://example.com:8443/v1/chat/completions</code>
/// triggers <code>Https=1</code> + SSLConfiguration is applied.</p>
Method TestEndpointHttpsSchemeWithSslConfig()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "https://example.com:8443/v1/chat/completions"

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""message"":{""role"":""assistant"",""content"":""ok""},""finish_reason"":""stop""}],""usage"":{""prompt_tokens"":1,""completion_tokens"":1}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Set tHistory = ..BuildSimpleUserHistory("hi")
    Set tToolDefs = ##class(%DynamicArray).%New()

    Do tMock.CallMessages(tHistory, tToolDefs, "", ##class(%DynamicObject).%New(), .tResp)

    Do $$$AssertEquals(tMock.LastHttps, 1, "Https=1 for https:// scheme")
    Do $$$AssertEquals(tMock.LastPort, 8443, "Port=8443 parsed from URL")
    Do $$$AssertEquals(tMock.LastServer, "example.com", "Server=example.com (no port suffix)")
    Quit
}

/// <p>AC-8 #5 — <method>GetAuthHeader</method>("") returns empty
/// (Ollama default — no auth required); the production
/// <method>IssueHttpsPost</method> omits the Authorization header
/// entirely. Asserted by inspecting tMock.LastAuthHeader after a 200
/// happy path with CredentialName="" config.</p>
Method TestAuthHeaderEmptyKeyOmitsHeader()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAICompatProvider).%New()
    Do $$$AssertEquals(tProv.GetAuthHeader(""), "", "Empty key returns empty header")

    ; Also verify the no-credential happy path: Config.Agent.CredentialName=""
    ; and the resolved key gets cleared, so the header arrives at
    ; IssueHttpsPost as "".
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"
    Set tCfg.CredentialName = "" ; intentional — Ollama default
    Set tCfg.EnvVarName = "PATH"  ; satisfies abstract template's resolve

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""message"":{""role"":""assistant"",""content"":""hi""},""finish_reason"":""stop""}],""usage"":{""prompt_tokens"":1,""completion_tokens"":1}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Do tMock.CallMessages(..BuildSimpleUserHistory("hi"), ##class(%DynamicArray).%New(), "", ##class(%DynamicObject).%New(), .tResp)

    Do $$$AssertEquals(tMock.LastAuthHeader, "", "LastAuthHeader empty when CredentialName empty (Ollama default)")
    Quit
}

/// <p>AC-8 #6 — <method>GetAuthHeader</method>("test-key-abc") returns
/// <code>Bearer test-key-abc</code> (OpenAI Bearer-token form).</p>
Method TestAuthHeaderNonEmptyKeyAddsBearer()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAICompatProvider).%New()
    Do $$$AssertEquals(tProv.GetAuthHeader("test-key-abc"), "Bearer test-key-abc", "Non-empty key returns Bearer <key>")
    Quit
}

/// <p>AC-8 #7 — payload has model / messages / tools / max_tokens /
/// temperature per OpenAI Chat Completions; system prompt is the FIRST
/// message with role=system (per AC-5 step 3).</p>
Method TestPayloadShapeOpenAIChatCompletions()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"
    Set tCfg.Model = "qwen3:14b"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 512

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""message"":{""role"":""assistant"",""content"":""hi""},""finish_reason"":""stop""}],""usage"":{""prompt_tokens"":5,""completion_tokens"":1}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Do tMock.CallMessages(..BuildSimpleUserHistory("question"), ..BuildOneCanonicalTool(), "You are an inspector.", ##class(%DynamicObject).%New(), .tResp)

    Set tPayload = ##class(%DynamicObject).%FromJSON(tMock.LastPayloadJson)

    Do $$$AssertEquals(tPayload.%Get("model"), "qwen3:14b", "model = qwen3:14b")
    Do $$$AssertEquals(+tPayload.%Get("max_tokens"), 512, "max_tokens = 512")
    Do $$$AssertEquals(+tPayload.%Get("temperature"), 0.0, "temperature = 0.0")
    Do $$$AssertTrue($IsObject(tPayload.%Get("messages")), "messages is an object")
    Do $$$AssertTrue($IsObject(tPayload.%Get("tools")), "tools is an object")

    ; First message must be system role
    Set tMsgs = tPayload.%Get("messages")
    Set tFirst = tMsgs.%Get(0)
    Do $$$AssertEquals(tFirst.%Get("role"), "system", "First message role = system")
    Do $$$AssertEquals(tFirst.%Get("content"), "You are an inspector.", "First message content = system prompt")
    Quit
}

/// <p>AC-8 #8 — mock returns
/// <code>choices[0].message.tool_calls:[...]</code>;
/// pProviderResponse.Content carries the canonical
/// <code>{type:"tool_use", id, name, input}</code> block via the
/// MessageAdapter "openai" switch case (Story 2.9 path).</p>
Method TestParseResponseToolCallToCanonicalToolUse()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    ; OpenAI Chat Completions tool_call response shape:
    Set tMock.MockBodyJson = "{""id"":""x"",""choices"":[{""message"":{""role"":""assistant"",""content"":null,""tool_calls"":[{""id"":""call_1"",""type"":""function"",""function"":{""name"":""event_log"",""arguments"":""{\""sessionId\"":2613}""}}]},""finish_reason"":""tool_calls""}],""usage"":{""prompt_tokens"":50,""completion_tokens"":10}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Do tMock.CallMessages(..BuildSimpleUserHistory("what errors?"), ..BuildOneCanonicalTool(), "", ##class(%DynamicObject).%New(), .tResp)

    Do $$$AssertEquals(tResp.StopReason, "tool_use", "StopReason = tool_use (OpenAI tool_calls translates to canonical tool_use)")
    Do $$$AssertTrue($IsObject(tResp.Content), "Content is an object")
    Do $$$AssertTrue(tResp.Content.%Size() >= 1, "Content has at least 1 block")

    ; Find the tool_use block (translation may also emit a leading text
    ; block when message.content is non-null; tolerate either ordering).
    Set tFoundToolUse = 0
    Set tIter = tResp.Content.%GetIterator()
    While tIter.%GetNext(.tIdx, .tBlock) {
        If '$IsObject(tBlock) Continue
        If tBlock.%Get("type") = "tool_use" {
            Set tFoundToolUse = 1
            Do $$$AssertEquals(tBlock.%Get("name"), "event_log", "tool_use.name = event_log")
            Set tInput = tBlock.%Get("input")
            Do $$$AssertTrue($IsObject(tInput), "tool_use.input is an object")
            Do $$$AssertEquals(+tInput.%Get("sessionId"), 2613, "tool_use.input.sessionId = 2613")
            Quit ; out of While
        }
    }
    Do $$$AssertTrue(tFoundToolUse, "Canonical tool_use block found in Content")
    Quit
}

/// <p>AC-8 #9 — mock returns
/// <code>usage:{prompt_tokens:100, completion_tokens:20}</code>; the
/// adapter populates pProviderResponse.Usage with input_tokens=100 and
/// output_tokens=20 (canonical Anthropic-shape keys).</p>
Method TestUsagePopulatesPromptAndCompletionTokens()
{
    Set tCfg = ..BuildTransientConfigAgent()
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"

    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.UseFastRetryParams = 1
    Set tMock.MockStatusCode = 200
    Set tMock.MockBodyJson = "{""choices"":[{""message"":{""role"":""assistant"",""content"":""ok""},""finish_reason"":""stop""}],""usage"":{""prompt_tokens"":100,""completion_tokens"":20}}"

    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    Do tMock.CallMessages(..BuildSimpleUserHistory("hi"), ##class(%DynamicArray).%New(), "", ##class(%DynamicObject).%New(), .tResp)

    Do $$$AssertTrue($IsObject(tResp.Usage), "Usage is populated")
    Do $$$AssertEquals(+tResp.Usage.%Get("input_tokens"), 100, "Usage.input_tokens = 100")
    Do $$$AssertEquals(+tResp.Usage.%Get("output_tokens"), 20, "Usage.output_tokens = 20")
    Quit
}

/// <p>AC-8 #10 (per AC-7) — the centralized
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> handles
/// non-default ports correctly for both HTTP and HTTPS schemes. Tests
/// the Ollama case (http + port 11434) and the HTTPS-with-custom-port
/// case (https + port 8443). Also verifies regression: canonical
/// no-port URLs (api.openai.com without :443) still parse with port=0
/// (caller leaves Port at the scheme default).</p>
Method TestParseEndpointUrlNonDefaultPort()
{
    ; Ollama HTTP with non-default port
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("http://192.168.0.123:11434/v1/chat/completions")
    Do $$$AssertEquals(tParsed.%Get("server"), "192.168.0.123", "Ollama server (no port suffix)")
    Do $$$AssertEquals(+tParsed.%Get("port"), 11434, "Ollama port=11434")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1/chat/completions", "Ollama path")
    Do $$$AssertEquals(+tParsed.%Get("https"), 0, "http:// scheme detected as https=0")

    ; HTTPS with custom port
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("https://example.com:8443/v1/messages")
    Do $$$AssertEquals(tParsed.%Get("server"), "example.com", "HTTPS+port server (no port suffix)")
    Do $$$AssertEquals(+tParsed.%Get("port"), 8443, "HTTPS+port port=8443")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1/messages", "HTTPS+port path")
    Do $$$AssertEquals(+tParsed.%Get("https"), 1, "https:// scheme detected as https=1")

    ; Regression — canonical OpenAI URL (no port) still parses correctly
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("https://api.openai.com/v1/chat/completions")
    Do $$$AssertEquals(tParsed.%Get("server"), "api.openai.com", "OpenAI canonical server")
    Do $$$AssertEquals(+tParsed.%Get("port"), 0, "OpenAI canonical port=0 (default 443)")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1/chat/completions", "OpenAI canonical path")
    Do $$$AssertEquals(+tParsed.%Get("https"), 1, "OpenAI canonical https=1")

    ; Regression — Anthropic canonical URL still parses correctly
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("https://api.anthropic.com/v1/messages")
    Do $$$AssertEquals(tParsed.%Get("server"), "api.anthropic.com", "Anthropic canonical server")
    Do $$$AssertEquals(+tParsed.%Get("port"), 0, "Anthropic canonical port=0")

    ; Regression — Gemini canonical URL with :generateContent in path
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
    Do $$$AssertEquals(tParsed.%Get("server"), "generativelanguage.googleapis.com", "Gemini canonical server")
    Do $$$AssertEquals(+tParsed.%Get("port"), 0, "Gemini canonical port=0 (path's :generateContent does not split as port)")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1beta/models/gemini-2.5-flash:generateContent", "Gemini canonical path preserves :generateContent suffix")
    Quit
}

/// <p>AC-8 #11 — verify <code>openai-compatible</code> is wired into the
/// AgentLoop's provider registry (the
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// switch). Story 5.3 extends the dispatch with
/// <code>"openai-compatible" -&gt; SessionAgent.LLM.OpenAICompatProvider</code>;
/// also sanity-verifies the existing openai/anthropic/gemini branches
/// still resolve correctly (no regression on AC-10).</p>
Method TestRegistryListProvidersIncludesOpenAICompatible()
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.Provider = "openai-compatible"
    Set tCfg.AgentName = "openai-compat-routing-test"
    Set tCfg.Model = "qwen3:14b"

    Set tProv = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfg)

    Do $$$AssertTrue($IsObject(tProv), "InstantiateProvider returns an object for Provider = openai-compatible")
    Do $$$AssertEquals($ClassName(tProv), "SessionAgent.LLM.OpenAICompatProvider", "Returned class is OpenAICompatProvider")

    ; Sanity — existing openai dispatch unchanged.
    Set tCfgOA = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgOA.Provider = "openai"
    Set tCfgOA.AgentName = "openai-routing-sanity-5-3"
    Set tProvOA = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgOA)
    Do $$$AssertEquals($ClassName(tProvOA), "SessionAgent.LLM.OpenAIProvider", "openai dispatch unchanged")

    ; Sanity — anthropic dispatch unchanged.
    Set tCfgAn = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgAn.Provider = "anthropic"
    Set tCfgAn.AgentName = "anthropic-routing-sanity-5-3"
    Set tProvAn = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgAn)
    Do $$$AssertEquals($ClassName(tProvAn), "SessionAgent.LLM.AnthropicProvider", "anthropic dispatch unchanged")

    ; Sanity — gemini dispatch unchanged.
    Set tCfgGe = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgGe.Provider = "gemini"
    Set tCfgGe.AgentName = "gemini-routing-sanity-5-3"
    Set tProvGe = ##class(SessionAgent.Agent.AgentLoop).InstantiateProvider(tCfgGe)
    Do $$$AssertEquals($ClassName(tProvGe), "SessionAgent.LLM.GeminiProvider", "gemini dispatch unchanged")

    ; Unknown provider → NULLOREF.
    Set tCfgX = ##class(SessionAgent.Config.Agent).%New()
    Set tCfgX.Provider = "no-such-thing"
    Set tCfgX.AgentName = "unknown-routing-5-3"
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
    Set tMock = ##class(SessionAgent.Test.MockOpenAICompatProvider).%New()
    Set tMock.ConfigAgent = tCfg
    Set tMock.MockThrowText = "Connection refused: server not listening"

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
    Do $$$AssertTrue(tText [ "Connection refused", "Envelope text carries exception substring (got: " _ tText _ ")")
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

/// <p>Helper — build a 1-tool canonical tool-defs array (event_log).</p>
ClassMethod BuildOneCanonicalTool() As %DynamicArray [ Internal ]
{
    Set tDefs = ##class(%DynamicArray).%New()
    Set tDef = ##class(%DynamicObject).%New()
    Do tDef.%Set("name", "event_log")
    Do tDef.%Set("description", "Return event log for an Ensemble session.")
    Set tSchema = ##class(%DynamicObject).%New()
    Do tSchema.%Set("type", "object")
    Set tProps = ##class(%DynamicObject).%New()
    Set tSidProp = ##class(%DynamicObject).%New()
    Do tSidProp.%Set("type", "integer")
    Do tProps.%Set("sessionId", tSidProp)
    Do tSchema.%Set("properties", tProps)
    Do tDef.%Set("input_schema", tSchema)
    Do tDefs.%Push(tDef)
    Quit tDefs
}

/// <p>Helper — build a transient (in-memory, never %Save'd)
/// <CLASS>SessionAgent.Config.Agent</CLASS> for the mock-driven tests.
/// Sets EnvVarName=PATH so the abstract template's
/// <method>EnvSecret.Resolve</method> returns a non-empty value (it
/// reads $env:PATH on every workstation), satisfying the credential-
/// missing fast path. The concrete then ignores the resolved key per
/// the optional-auth design when CredentialName is empty.</p>
ClassMethod BuildTransientConfigAgent() As SessionAgent.Config.Agent [ Internal ]
{
    Set tCfg = ##class(SessionAgent.Config.Agent).%New()
    Set tCfg.AgentName = "test-openai-compat-agent"
    Set tCfg.Provider = "openai-compatible"
    Set tCfg.Model = "qwen3:14b"
    Set tCfg.Temperature = 0.0
    Set tCfg.MaxTokens = 1000
    Set tCfg.EnvVarName = "PATH"
    Set tCfg.CredentialName = ""
    Set tCfg.EndpointUrl = "http://localhost:11434/v1/chat/completions"
    Set tCfg.Enabled = 1
    Set tCfg.ReadOnly = 1
    Quit tCfg
}

}
