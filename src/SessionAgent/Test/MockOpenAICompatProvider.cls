/// <p>Test-only mock subclass of
/// <CLASS>SessionAgent.LLM.OpenAICompatProvider</CLASS>. Overrides
/// <method>IssueHttpsPost</method> to inject canned HTTP responses
/// (statusCode + bodyJson) without engaging the network. Mirrors
/// <CLASS>SessionAgent.Test.MockOpenAIProvider</CLASS> /
/// <CLASS>SessionAgent.Test.MockGeminiProvider</CLASS> — Story 2.9
/// mock-HTTP design choice C.</p>
///
/// <p>Captures the in-flight payload JSON, auth header, and endpoint URL
/// for tests to assert on. Production
/// <method>SessionAgent.LLM.OpenAICompatProvider.IssueHttpsPost</method>
/// is unchanged; the test surface is the override hook.</p>
Class SessionAgent.Test.MockOpenAICompatProvider Extends SessionAgent.LLM.OpenAICompatProvider
{

/// <p>Canned HTTP status code returned by the override.</p>
Property MockStatusCode As %Integer [ InitialExpression = 200 ];

/// <p>Canned HTTP body returned by the override (already JSON-serialized
/// — no further encoding).</p>
Property MockBodyJson As %String(MAXLEN = 65535);

/// <p>Counts how many times <method>IssueHttpsPost</method> was invoked.
/// Tests assert this is 0 on the endpoint-validation / credential-misconfig
/// fast paths, and >=1 on the happy-path tests.</p>
Property CallCount As %Integer [ InitialExpression = 0 ];

/// <p>When <code>1</code>, the retry-param hooks return small values
/// (BaseDelay=0, MaxDelay=0) so the orchestrator's Hang is a no-op.</p>
Property UseFastRetryParams As %Boolean [ InitialExpression = 0 ];

/// <p>Captured payload JSON from the most-recent
/// <method>IssueHttpsPost</method> invocation. Tests inspect this to
/// assert payload shape (model / messages / tools / max_tokens / temperature).</p>
Property LastPayloadJson As %String(MAXLEN = 65535);

/// <p>Captured auth header from the most-recent invocation. Empty when
/// the credential-less Ollama path was exercised; non-empty
/// "Bearer &lt;key&gt;" when CredentialName was set.</p>
Property LastAuthHeader As %String(MAXLEN = 4096);

/// <p>Captured endpoint URL from the most-recent invocation.</p>
Property LastEndpointUrl As %String(MAXLEN = 1024);

/// <p>Captured Https flag (parsed from EndpointUrl scheme). Tests assert
/// 0 for http:// endpoints, 1 for https:// endpoints. Set during
/// IssueHttpsPost via the centralized parser.</p>
Property LastHttps As %Integer [ InitialExpression = -1 ];

/// <p>Captured Port (parsed from EndpointUrl). Tests assert 11434 for
/// the Ollama URL, 8443 for the HTTPS-with-port URL.</p>
Property LastPort As %Integer [ InitialExpression = -1 ];

/// <p>Captured Server (parsed from EndpointUrl).</p>
Property LastServer As %String(MAXLEN = 512);

/// <p>Override — return the canned response set by the test, increment
/// <property>CallCount</property>, capture the payload + auth header +
/// endpoint URL + parsed Server/Port/Https for assertion.</p>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set ..CallCount = ..CallCount + 1
    Set ..LastPayloadJson = pPayloadJson
    Set ..LastAuthHeader = pAuthHeader
    Set ..LastEndpointUrl = pEndpointUrl

    ; Parse the URL the same way the production code does and capture the
    ; result so tests can assert on Https / Port / Server independently.
    Set tParsed = ..ParseEndpointUrl(pEndpointUrl)
    Set ..LastHttps = +tParsed.%Get("https")
    Set ..LastPort = +tParsed.%Get("port")
    Set ..LastServer = tParsed.%Get("server")

    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", ..MockStatusCode)
    Do tResp.%Set("bodyText", ..MockBodyJson)
    Do tResp.%Set("headers", ##class(%DynamicObject).%New())
    Quit tResp
}

/// <p>Override — when <property>UseFastRetryParams</property> is set,
/// collapse BaseDelay to 0.</p>
Method GetBaseDelaySec() As %Integer
{
    If ..UseFastRetryParams Quit 0
    Quit ##super()
}

/// <p>Override — when <property>UseFastRetryParams</property> is set,
/// collapse MaxDelay to 0.</p>
Method GetMaxDelaySec() As %Integer
{
    If ..UseFastRetryParams Quit 0
    Quit ##super()
}

}
