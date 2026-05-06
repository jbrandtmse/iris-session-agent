/// <p>Test-only mock subclass of
/// <CLASS>SessionAgent.LLM.GeminiProvider</CLASS>. Overrides
/// <method>IssueHttpsPost</method> to inject canned HTTP responses
/// (statusCode + bodyJson) without engaging the network. Overrides
/// <method>GetBaseDelaySec</method> / <method>GetMaxDelaySec</method>
/// to <code>0</code> when <property>UseFastRetryParams</property> is set
/// so the
/// <method>SessionAgent.LLM.GeminiProvider.CallMessages</method> retry
/// loop's <code>Hang</code> is a no-op.</p>
///
/// <p>Mirrors <CLASS>SessionAgent.Test.MockOpenAIProvider</CLASS> /
/// <CLASS>SessionAgent.Test.MockAnthropicProvider</CLASS> — Story 2.9
/// mock-HTTP design choice C. Production
/// <method>SessionAgent.LLM.GeminiProvider.IssueHttpsPost</method> is
/// unchanged; the test surface is the override hook.</p>
///
/// <p><b>Sequenced responses.</b> When
/// <property>SequencedStatusCodes</property> /
/// <property>SequencedBodies</property> are set
/// (each is a <code>$ListBuild</code> list), the override returns the
/// nth-attempt response. Used by AC-8
/// <method>TestRetryFallsBackToExpBackoffOnMissingRetryDelay</method>
/// which needs attempt 1 = 429 (no retryDelay) and attempt 2 = 200.</p>
///
/// <p><b>No header-based Retry-After.</b> Gemini does NOT emit a
/// <code>Retry-After</code> header — the retry-delay info lives inside
/// the 429 body. The single-shot
/// <property>MockBodyJson</property> + sequenced
/// <property>SequencedBodies</property> hooks are how tests inject the
/// retry-delay payload.</p>
Class SessionAgent.Test.MockGeminiProvider Extends SessionAgent.LLM.GeminiProvider
{

/// <p>Canned HTTP status code returned by the override (single-shot
/// path).</p>
Property MockStatusCode As %Integer [ InitialExpression = 200 ];

/// <p>Canned HTTP body returned by the override (already JSON-serialized
/// — no further encoding).</p>
Property MockBodyJson As %String(MAXLEN = 65535);

/// <p>Counts how many times <method>IssueHttpsPost</method> was invoked.</p>
Property CallCount As %Integer [ InitialExpression = 0 ];

/// <p>When <code>1</code>, the retry-param hooks return small values
/// (BaseDelay=0, MaxDelay=0) so the orchestrator's Hang is a no-op.
/// MaxAttempts stays at 4.</p>
Property UseFastRetryParams As %Boolean [ InitialExpression = 0 ];

/// <p>Optional sequenced status codes ($ListBuild list). When non-empty,
/// the override returns <code>$ListGet(SequencedStatusCodes, CallCount)</code>
/// for each attempt.</p>
Property SequencedStatusCodes As %String;

/// <p>Optional sequenced response bodies ($ListBuild list). When non-empty,
/// the override returns <code>$ListGet(SequencedBodies, CallCount)</code>
/// for each attempt.</p>
Property SequencedBodies As %String(MAXLEN = 65535);

/// <p>Captured payload JSON from the most-recent
/// <method>IssueHttpsPost</method> invocation. Tests inspect this to
/// assert payload shape (e.g.,
/// <method>TestPayloadShapeContentsAndTools</method>).</p>
Property LastPayloadJson As %String(MAXLEN = 65535);

/// <p>Captured auth header from the most-recent invocation. Tests assert
/// it carries the <code>x-goog-api-key</code> header line.</p>
Property LastAuthHeader As %String(MAXLEN = 4096);

/// <p>Captured endpoint URL from the most-recent invocation. Tests can
/// assert that <code>{model}</code> substitution happened.</p>
Property LastEndpointUrl As %String(MAXLEN = 1024);

/// <p>Override — return the canned response set by the test, increment
/// <property>CallCount</property>, capture the payload + auth header +
/// endpoint URL for assertion.</p>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set ..CallCount = ..CallCount + 1
    Set ..LastPayloadJson = pPayloadJson
    Set ..LastAuthHeader = pAuthHeader
    Set ..LastEndpointUrl = pEndpointUrl

    Set tStatusCode = ..MockStatusCode
    Set tBodyJson = ..MockBodyJson

    ; Sequenced path overrides single-shot when populated.
    If ..SequencedStatusCodes '= "" {
        Set tSeq = ..SequencedStatusCodes
        Set tIdx = ..CallCount
        If tIdx > $ListLength(tSeq) Set tIdx = $ListLength(tSeq)
        Set tStatusCode = $ListGet(tSeq, tIdx)
    }
    If ..SequencedBodies '= "" {
        Set tSeq = ..SequencedBodies
        Set tIdx = ..CallCount
        If tIdx > $ListLength(tSeq) Set tIdx = $ListLength(tSeq)
        Set tBodyJson = $ListGet(tSeq, tIdx)
    }

    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", tStatusCode)
    Do tResp.%Set("bodyText", tBodyJson)
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
