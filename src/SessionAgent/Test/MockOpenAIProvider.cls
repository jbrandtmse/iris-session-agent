/// <p>Test-only mock subclass of
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>. Overrides
/// <method>IssueHttpsPost</method> to inject canned HTTP responses
/// (statusCode + bodyJson + optional Retry-After header) without engaging
/// the network. Overrides <method>GetBaseDelaySec</method> /
/// <method>GetMaxDelaySec</method> to <code>0</code> so the
/// <method>SessionAgent.Util.RetryWithBackoff.ExecuteWithParams</method>
/// loop's <code>Hang</code> is a no-op when
/// <property>UseFastRetryParams</property> is set.</p>
///
/// <p>Story 2.9 dev choice — mock-HTTP option C from the story Dev Notes.
/// Production <method>IssueHttpsPost</method> is unchanged; the test
/// surface is the override hook.</p>
Class SessionAgent.Test.MockOpenAIProvider Extends SessionAgent.LLM.OpenAIProvider
{

/// <p>Canned HTTP status code returned by the override.</p>
Property MockStatusCode As %Integer [ InitialExpression = 200 ];

/// <p>Canned HTTP body returned by the override (already JSON-serialized
/// — no further encoding).</p>
Property MockBodyJson As %String(MAXLEN = 65535);

/// <p>Optional canned <code>Retry-After</code> header value. When
/// non-empty, the mock surfaces it on the response headers; the
/// orchestrator reads it via
/// <method>SessionAgent.Util.RetryWithBackoff.ProviderHintDelay</method>.</p>
Property MockHeaderRetryAfter As %String;

/// <p>Counts how many times <method>IssueHttpsPost</method> was invoked.
/// The retry-exhaustion test asserts this equals
/// <method>GetMaxAttempts</method>.</p>
Property CallCount As %Integer [ InitialExpression = 0 ];

/// <p>When <code>1</code>, the retry-param hooks return small values
/// (BaseDelay=0, MaxDelay=0) so the orchestrator's Hang is a no-op.
/// MaxAttempts stays at 4 so retry-exhaustion tests still drive the
/// real-budget loop.</p>
Property UseFastRetryParams As %Boolean [ InitialExpression = 0 ];

/// <p>Story 12.2 BUG-02 — when non-empty, the override throws an
/// <CLASS>%Exception.General</CLASS> whose <code>DisplayString()</code>
/// surfaces this text. Drives the mid-flight catch path so tests can
/// assert the error envelope carries the captured exception substring.</p>
Property MockThrowText As %String;

/// <p>Override — return the canned response set by the test, increment
/// <property>CallCount</property>. Same return shape as the production
/// method:
/// <code>{statusCode, bodyText, headers}</code>.</p>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set ..CallCount = ..CallCount + 1

    ; Story 12.2 BUG-02 — drive the mid-flight catch path.
    If ..MockThrowText '= "" {
        Throw ##class(%Exception.General).%New("MockThrow",,,..MockThrowText)
    }

    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", ..MockStatusCode)
    Do tResp.%Set("bodyText", ..MockBodyJson)
    Set tHeaders = ##class(%DynamicObject).%New()
    If ..MockHeaderRetryAfter '= "" {
        Do tHeaders.%Set("retry-after", ..MockHeaderRetryAfter)
    }
    Do tResp.%Set("headers", tHeaders)
    Quit tResp
}

/// <p>Override — when <property>UseFastRetryParams</property> is set,
/// collapse BaseDelay to 0 so the orchestrator Hang is a no-op.</p>
Method GetBaseDelaySec() As %Integer
{
    If ..UseFastRetryParams Quit 0
    Quit ##super()
}

/// <p>Override — when <property>UseFastRetryParams</property> is set,
/// collapse MaxDelay to 0 so the orchestrator Hang is a no-op.</p>
Method GetMaxDelaySec() As %Integer
{
    If ..UseFastRetryParams Quit 0
    Quit ##super()
}

}
