/// <p>Unit tests for <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>.</p>
///
/// <p>Verifies the nine behaviors required by Story 2.2 acceptance
/// criterion AC-3:</p>
/// <ol>
/// <li><b>TestIsRetryableHttpMatrix</b> — 429 + 5xx retryable; other
/// 4xx non-retryable.</li>
/// <li><b>TestIsRetryableNetworkClasses</b> — documented network
/// failure categories retryable; unknown / empty non-retryable.</li>
/// <li><b>TestParseRetryAfterInteger</b> — integer-seconds form parses
/// as expected.</li>
/// <li><b>TestParseRetryAfterHttpDate</b> — RFC 7231 HTTP-date form
/// parses to delta-seconds-from-now within ±5s tolerance.</li>
/// <li><b>TestParseGeminiRetryDelay</b> — extracts integer seconds from
/// the Gemini error envelope; returns 0 on every structural mismatch.</li>
/// <li><b>TestExpBackoffDistribution</b> — bound check on full-jitter
/// formula across 1000 calls.</li>
/// <li><b>TestExecuteRetriesOnRetryableThenSucceeds</b> — 429 → 200
/// transitions correctly with exact retry count.</li>
/// <li><b>TestExecuteExhaustsRetriesAndPreservesRequestId</b> — exhausts
/// at MaxAttempts and keeps the request-id header on the final response.</li>
/// <li><b>TestExecuteDoesNotRetryOnMidFlightFailure</b> — callable
/// $$$ERROR is treated as a non-retryable mid-flight failure.</li>
/// </ol>
///
/// <p><b>Mock callable strategy.</b> Three mock ClassMethods live in this
/// test class and are referenced by their fully-qualified names from the
/// Execute tests. Each mock uses the process-private global
/// <code>^||RetryTestCounter</code> to count invocations; it is cleared in
/// <code>OnAfterOneTest</code>.</p>
///
/// <p><b>Hang strategy.</b> The Execute tests call the parameterized
/// <code>ExecuteWithParams</code> entry point with
/// <code>pBaseDelaySec=0</code> and <code>pMaxDelaySec=0</code>, which
/// collapses every <code>ExpBackoffSec</code> result to 0 so
/// <code>Hang 0</code> is a no-op. This keeps the suite fast (~ms total
/// for retry orchestration) while still exercising the full loop logic
/// (counter increment, attempt-bound check, response carry-through). The
/// mocks deliberately do NOT set a <code>retry-after</code> header so the
/// provider-hint path returns 0 too — the orchestrator falls through to
/// the (also 0) exp-backoff and never actually sleeps.</p>
Class SessionAgent.Test.RetryWithBackoffTest Extends %UnitTest.TestCase
{

/// <p>Constructor — must accept the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, and must call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Per-test cleanup: kill the process-private counter global so each
/// test sees a fresh count.</p>
Method OnAfterOneTest() As %Status
{
    Kill ^||RetryTestCounter
    Quit $$$OK
}

/// <p>AC-3 #1 — Loop over the documented retryable codes (429, 500, 502,
/// 503, 504) and assert each returns 1; loop over documented
/// non-retryable codes (400, 401, 403, 404, 422) and assert each returns
/// 0. Failure messages name the offending code so debugging is easy.</p>
Method TestIsRetryableHttpMatrix()
{
    Set tRetryable = $ListBuild(429, 500, 502, 503, 504)
    Set tPtr = 0
    While $ListNext(tRetryable, tPtr, tCode) {
        Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(tCode), 1, "code " _ tCode _ " is retryable")
    }

    Set tNonRetryable = $ListBuild(400, 401, 403, 404, 422)
    Set tPtr = 0
    While $ListNext(tNonRetryable, tPtr, tCode) {
        Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(tCode), 0, "code " _ tCode _ " is NOT retryable")
    }
    Quit
}

/// <p>AC-3 #2 — Network-class retryability. With statusCode = 0, the
/// error category drives the decision. Documented network classes are
/// retryable; unknown and empty are not.</p>
Method TestIsRetryableNetworkClasses()
{
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(0, "connection-refused"), 1, "connection-refused retryable")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(0, "dns-failure"), 1, "dns-failure retryable")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(0, "tls-handshake"), 1, "tls-handshake retryable")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(0, "unknown"), 0, "unknown category not retryable")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(0, ""), 0, "empty category not retryable")
    Quit
}

/// <p>AC-3 #3 — Integer-seconds form of <code>Retry-After</code>.</p>
Method TestParseRetryAfterInteger()
{
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter("30"), 30, "'30' parses to 30")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter("0"), 0, "'0' parses to 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter(""), 0, "empty parses to 0")
    Quit
}

/// <p>AC-3 #4 — HTTP-date form of <code>Retry-After</code>. Construct
/// the date string for "now + 60 seconds" using the inverse
/// <code>$ZDateTime</code> call so the round-trip is unambiguous, then
/// assert <code>ParseRetryAfter</code> returns within ±5s of 60.</p>
///
/// <p>Why the tolerance: <code>ParseRetryAfter</code> measures
/// "now − $Horolog at parse time" and we built the string at "now − 1ms";
/// jitter from process scheduling between the two calls can shift the
/// result by a second or two. ±5s is generous enough to be reliable
/// across slow CI runners.</p>
Method TestParseRetryAfterHttpDate()
{
    ; Build the IMF-fixdate string for $Horolog + 60 seconds.
    Set tNow = $Horolog
    Set tNowDays = +$Piece(tNow, ",", 1)
    Set tNowSecs = +$Piece(tNow, ",", 2)
    Set tTargetSecs = tNowSecs + 60
    Set tTargetDays = tNowDays
    If tTargetSecs >= 86400 {
        Set tTargetDays = tTargetDays + 1
        Set tTargetSecs = tTargetSecs - 86400
    }
    Set tFutureHoro = tTargetDays _ "," _ tTargetSecs
    ; Format: "Wed, 21 Oct 2026 07:28:00 GMT". Mode -1 with format flag 1
    ; produces RFC 1123 / RFC 7231 IMF-fixdate output.
    Set tHttpDate = $ZDateTime(tFutureHoro, -1, 1)

    Set tParsed = ##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter(tHttpDate)
    Set tDelta = tParsed - 60
    If tDelta < 0 Set tDelta = -tDelta
    Do $$$AssertTrue(tDelta < 5, "HTTP-date Retry-After parses to ~60s; got " _ tParsed _ " (delta=" _ tDelta _ ", input='" _ tHttpDate _ "')")
    Quit
}

/// <p>AC-3 #5 — Gemini error-envelope <code>retryDelay</code> extraction.
/// Four shapes covered:</p>
/// <ol>
/// <li>Well-formed RetryInfo with <code>"45s"</code> → 45.</li>
/// <li>Missing <code>error</code> object → 0.</li>
/// <li>Present RetryInfo but missing <code>retryDelay</code> → 0.</li>
/// <li><code>retryDelay = "abc"</code> (no leading digit) → 0.</li>
/// </ol>
Method TestParseGeminiRetryDelay()
{
    ; Shape 1: well-formed.
    Set tErr1 = {"details": [{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "45s"}]}
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseGeminiRetryDelay(tErr1), 45, "well-formed RetryInfo with '45s' → 45")

    ; Shape 2: pass an empty object so the "missing details" path triggers.
    ; (Story AC says "missing error → 0" — at the call site that means an
    ; absent or empty error envelope. We simulate the error.details branch
    ; both for the empty-object and the malformed-string case.)
    Set tErr2 = {}
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseGeminiRetryDelay(tErr2), 0, "empty object (no details) → 0")

    ; Shape 3: details present but missing retryDelay.
    Set tErr3 = {"details": [{"@type": "type.googleapis.com/google.rpc.RetryInfo"}]}
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseGeminiRetryDelay(tErr3), 0, "missing retryDelay → 0")

    ; Shape 4: retryDelay with no leading digit.
    Set tErr4 = {"details": [{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "abc"}]}
    Do $$$AssertEquals(##class(SessionAgent.Util.RetryWithBackoff).ParseGeminiRetryDelay(tErr4), 0, "non-numeric retryDelay → 0")
    Quit
}

/// <p>AC-3 #6 — Distribution bound check on <code>ExpBackoffSec</code>.
/// Calls <code>ExpBackoffSec(2, 1, 32)</code> 1000 times and asserts every
/// result is in <code>[0, min(32, 1 * 2^2)) = [0, 4)</code>. The contract
/// is the bound, not a statistical distribution shape — the assertion
/// here is strict (max < 4.0 AND min ≥ 0.0 across all 1000 samples).</p>
Method TestExpBackoffDistribution()
{
    Set tMin = 999999
    Set tMax = -1
    For i = 1:1:1000 {
        Set tVal = ##class(SessionAgent.Util.RetryWithBackoff).ExpBackoffSec(2, 1, 32)
        If tVal < tMin Set tMin = tVal
        If tVal > tMax Set tMax = tVal
    }
    Do $$$AssertTrue(tMin >= 0, "min sample (" _ tMin _ ") ≥ 0")
    Do $$$AssertTrue(tMax < 4, "max sample (" _ tMax _ ") < 4 (cap = min(32, 1*2^2) = 4)")
    Quit
}

/// <p>AC-3 #7 — Mock callable returns 429 on attempt 1 then 200 on
/// attempt 2; assert Execute returns the 200 response and the callable
/// was invoked exactly twice. Uses the parameterized
/// <code>ExecuteWithParams</code> entry to drive delays to 0.</p>
Method TestExecuteRetriesOnRetryableThenSucceeds()
{
    Set ^||RetryTestCounter = 0
    Set tArgs = ##class(%DynamicObject).%New()
    Set tResp = ""
    Set tSC = ##class(SessionAgent.Util.RetryWithBackoff).ExecuteWithParams("SessionAgent.Test.RetryWithBackoffTest.MockCallable429ThenOk", tArgs, 4, 0, 0, .tResp)
    Do $$$AssertStatusOK(tSC, "Execute returns OK")
    Do $$$AssertEquals(^||RetryTestCounter, 2, "callable invoked exactly 2 times (429 then 200)")
    Do $$$AssertEquals(+tResp.%Get("statusCode"), 200, "final response statusCode = 200")
    Quit
}

/// <p>AC-3 #8 — Mock callable returns 429 + <code>x-request-id: req-abc</code>
/// on every attempt; assert Execute exhausts at MaxAttempts (4), sets
/// <code>exhaustedRetries = 1</code>, and preserves the request-id header
/// on the final response.</p>
Method TestExecuteExhaustsRetriesAndPreservesRequestId()
{
    Set ^||RetryTestCounter = 0
    Set tArgs = ##class(%DynamicObject).%New()
    Set tResp = ""
    Set tSC = ##class(SessionAgent.Util.RetryWithBackoff).ExecuteWithParams("SessionAgent.Test.RetryWithBackoffTest.MockCallable429Always", tArgs, 4, 0, 0, .tResp)
    Do $$$AssertStatusOK(tSC, "Execute returns OK")
    Do $$$AssertEquals(^||RetryTestCounter, 4, "callable invoked exactly MaxAttempts (4) times")
    Do $$$AssertEquals(+tResp.%Get("exhaustedRetries"), 1, "exhaustedRetries = 1")
    Set tHeaders = tResp.%Get("headers")
    Do $$$AssertTrue($IsObject(tHeaders), "headers object preserved")
    Do $$$AssertEquals(tHeaders.%Get("x-request-id"), "req-abc", "x-request-id preserved on final response")
    Quit
}

/// <p>AC-3 #9 — Mock callable returns
/// <code>$System.Status.Error(5001, "mid-flight: response lost")</code>;
/// assert Execute does NOT retry (callable invoked exactly once), sets
/// <code>midFlightFailure = 1</code> and <code>exhaustedRetries = 1</code>.
/// This is the critical idempotency-preserving path per architecture.md:649.</p>
Method TestExecuteDoesNotRetryOnMidFlightFailure()
{
    Set ^||RetryTestCounter = 0
    Set tArgs = ##class(%DynamicObject).%New()
    Set tResp = ""
    Set tSC = ##class(SessionAgent.Util.RetryWithBackoff).ExecuteWithParams("SessionAgent.Test.RetryWithBackoffTest.MockCallableMidFlight", tArgs, 4, 0, 0, .tResp)
    Do $$$AssertStatusOK(tSC, "Execute returns OK (failure carried in response, not status)")
    Do $$$AssertEquals(^||RetryTestCounter, 1, "mid-flight failure NOT retried; callable invoked exactly 1 time")
    Do $$$AssertEquals(+tResp.%Get("midFlightFailure"), 1, "midFlightFailure = 1")
    Do $$$AssertEquals(+tResp.%Get("exhaustedRetries"), 1, "exhaustedRetries = 1")
    Quit
}

/// <p>Mock callable: increments <code>^||RetryTestCounter</code> each
/// invocation; returns HTTP 429 on the first call, HTTP 200 on the
/// second and beyond.</p>
ClassMethod MockCallable429ThenOk(pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status
{
    Set ^||RetryTestCounter = $Get(^||RetryTestCounter) + 1
    Set pResponse = ##class(%DynamicObject).%New()
    If ^||RetryTestCounter = 1 {
        Do pResponse.%Set("statusCode", 429, "number")
        Do pResponse.%Set("headers", ##class(%DynamicObject).%New())
        Do pResponse.%Set("body", ##class(%DynamicObject).%New())
    } Else {
        Do pResponse.%Set("statusCode", 200, "number")
        Do pResponse.%Set("headers", ##class(%DynamicObject).%New())
        Do pResponse.%Set("body", ##class(%DynamicObject).%New())
    }
    Quit $$$OK
}

/// <p>Mock callable: increments <code>^||RetryTestCounter</code> each
/// invocation; always returns HTTP 429 with an
/// <code>x-request-id: req-abc</code> header. Used to verify retry
/// exhaustion + request-id preservation.</p>
ClassMethod MockCallable429Always(pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status
{
    Set ^||RetryTestCounter = $Get(^||RetryTestCounter) + 1
    Set pResponse = ##class(%DynamicObject).%New()
    Do pResponse.%Set("statusCode", 429, "number")
    Set tHeaders = ##class(%DynamicObject).%New()
    Do tHeaders.%Set("x-request-id", "req-abc")
    Do pResponse.%Set("headers", tHeaders)
    Do pResponse.%Set("body", ##class(%DynamicObject).%New())
    Quit $$$OK
}

/// <p>Mock callable: increments <code>^||RetryTestCounter</code> each
/// invocation; always returns a $$$ERROR status simulating a mid-flight
/// network failure (request sent, response lost). The retry orchestrator
/// MUST NOT retry this case per architecture.md:649.</p>
ClassMethod MockCallableMidFlight(pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status
{
    Set ^||RetryTestCounter = $Get(^||RetryTestCounter) + 1
    Set pResponse = ##class(%DynamicObject).%New()
    Quit $System.Status.Error(5001, "mid-flight: response lost")
}

}
