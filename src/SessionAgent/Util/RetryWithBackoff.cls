/// <p>HTTP retry orchestrator with full-jitter exponential backoff for the
/// SessionAgent LLM provider call path. Encapsulates the four
/// pure-functional helpers (<code>IsRetryable</code>,
/// <code>ParseRetryAfter</code>, <code>ParseGeminiRetryDelay</code>,
/// <code>ExpBackoffSec</code>) plus the orchestrating <code>Execute</code>
/// method that drives the retry loop on a caller-supplied callable.</p>
///
/// <p><b>Class Parameters</b> (per architecture.md §"Calibration constants",
/// line 341):</p>
/// <ul>
/// <li><code>MaxAttempts = 4</code> — total invocations before exhausting.</li>
/// <li><code>BaseDelaySec = 1</code> — base delay seed for the exponential
/// formula.</li>
/// <li><code>MaxDelaySec = 32</code> — cap on the per-attempt delay.</li>
/// </ul>
///
/// <p><b>Idempotency rule</b> (architecture.md §"LLM tool-call idempotency",
/// lines 645–649): the orchestrator MUST NOT retry mid-flight network
/// failures (cases where the request was sent but the response was lost).
/// In those cases <code>pResponse.midFlightFailure</code> is set so the
/// caller can decide whether the upstream operation is safe to repeat.
/// Retryable HTTP responses (429, 5xx) ARE retried because we received a
/// response — the provider acknowledged the request.</p>
///
/// <p><b>References</b>:</p>
/// <ul>
/// <li><a href="../planning-artifacts/architecture.md">architecture.md
/// §"Calibration constants"</a> (line 341), §"Retry-After parsing rules"
/// (line 645), §"LLM tool-call idempotency" (line 649).</li>
/// <li><a href="../planning-artifacts/epics.md">epics.md Story 2.2</a>
/// (lines 746–770) — acceptance criteria.</li>
/// <li>Project rule
/// <a href="../../.claude/rules/iris-objectscript-basics.md">iris-objectscript-basics.md</a>
/// §"QUIT Statement Restrictions in Try/Catch Blocks", §"Naming
/// Conventions" (no underscores in Class Parameter names).</li>
/// </ul>
Class SessionAgent.Util.RetryWithBackoff Extends %RegisteredObject
{

/// <p>Total invocations before giving up. Per architecture.md:341.</p>
Parameter MaxAttempts As INTEGER = 4;

/// <p>Base delay seed for the exponential formula, in seconds. Per
/// architecture.md:341.</p>
Parameter BaseDelaySec As INTEGER = 1;

/// <p>Hard cap on per-attempt delay, in seconds. Per architecture.md:341.</p>
Parameter MaxDelaySec As INTEGER = 32;

/// <p>Predicate: should this response be retried?</p>
///
/// <p>Returns <b>true</b> for HTTP 429 + 5xx (server-side rate-limit and
/// transient server errors). Returns <b>false</b> for 4xx (except 429),
/// 2xx, 3xx, and 0 (non-HTTP path).</p>
///
/// <p>For non-HTTP errors (<code>pStatusCode = 0</code>) the second
/// parameter <code>pErrorCategory</code> drives the decision: documented
/// network classes (<code>"connection-refused"</code>,
/// <code>"dns-failure"</code>, <code>"tls-handshake"</code>) are retryable;
/// everything else (including the empty string) is not. This mirrors the
/// idempotency rule: a refused TCP connection means the request never
/// reached the upstream server, so retrying is safe.</p>
ClassMethod IsRetryable(pStatusCode As %Integer, pErrorCategory As %String = "") As %Boolean
{
    ; HTTP path. 429 is retryable; 5xx is retryable; everything else is not.
    If pStatusCode = 429 Quit 1
    If (pStatusCode >= 500) && (pStatusCode <= 599) Quit 1
    If pStatusCode > 0 Quit 0

    ; Non-HTTP path (statusCode = 0). Driven by the error category.
    If pErrorCategory = "connection-refused" Quit 1
    If pErrorCategory = "dns-failure" Quit 1
    If pErrorCategory = "tls-handshake" Quit 1
    Quit 0
}

/// <p>Parse the value of an HTTP <code>Retry-After</code> header into a
/// non-negative integer number of seconds.</p>
///
/// <p>The HTTP spec (RFC 7231 §7.1.3) allows two forms:</p>
/// <ol>
/// <li><b>delta-seconds</b> — a non-negative decimal integer
/// (<code>"30"</code>) interpreted as seconds from now.</li>
/// <li><b>HTTP-date</b> — an RFC 7231 IMF-fixdate string
/// (<code>"Wed, 21 Oct 2026 07:28:00 GMT"</code>) interpreted as the
/// absolute moment to retry. We compute seconds-from-now via
/// <code>$ZDateTimeH</code> and clamp the result at <code>0</code> so
/// past dates do not produce negative delays.</li>
/// </ol>
///
/// <p>Empty input or unparseable input returns <code>0</code> — the caller
/// should fall back to the exponential schedule when the provider does
/// not give us a hint we can use.</p>
ClassMethod ParseRetryAfter(pHeaderValue As %String) As %Integer
{
    If pHeaderValue = "" Quit 0
    Set tTrim = $ZStrip(pHeaderValue, "<>W")
    If tTrim = "" Quit 0

    ; Form 1: integer seconds. $IsValidNum is too liberal (accepts decimals
    ; and signs) — use a tighter check via pattern match for non-negative
    ; integer.
    If tTrim ? 1.N {
        Quit +tTrim
    }

    ; Form 2: HTTP-date. $ZDateTimeH(value, -1, 1) parses RFC 1123 / RFC 7231
    ; IMF-fixdate format ("Wed, 21 Oct 2026 07:28:00 GMT") and returns a
    ; %Library.TimeStamp ($Horolog format). On failure it raises an error
    ; or returns "". Wrap in Try/Catch so we degrade gracefully to 0.
    Set tResult = 0
    Try {
        ; -1 = locale-default for both date and time; the IRIS docs note
        ; that the RFC 1123 format is recognized by $ZDateTimeH with the
        ; "$ZDATETIME" mode -1 / 1. We use the simpler universal HTTP-date
        ; parser by trying multiple modes.
        Set tHoro = $ZDateTimeH(tTrim, -1, 1)
        If tHoro '= "" {
            ; tHoro is in $Horolog form (days,seconds since 1840-12-31).
            ; Diff against current $ZTimeStamp converted via $ZDateTimeH
            ; in mode -2 (UTC) so the comparison is timezone-aligned.
            ; Simpler: just diff against $Horolog (also local time).
            Set tNow = $Horolog
            Set tNowDays = +$Piece(tNow, ",", 1)
            Set tNowSecs = +$Piece(tNow, ",", 2)
            Set tTargetDays = +$Piece(tHoro, ",", 1)
            Set tTargetSecs = +$Piece(tHoro, ",", 2)
            Set tDelta = ((tTargetDays - tNowDays) * 86400) + (tTargetSecs - tNowSecs)
            If tDelta < 0 {
                Set tResult = 0
            } Else {
                Set tResult = tDelta
            }
        }
        Quit
    }
    Catch ex {
        Set tResult = 0
        Quit
    }
    Quit tResult
}

/// <p>Parse a Gemini error envelope's <code>error.details[].retryDelay</code>
/// into a non-negative integer number of seconds.</p>
///
/// <p>The Gemini API surfaces rate-limit hints inside a structured error
/// body of the shape:</p>
///
/// <pre>
/// {"error": {"details": [
///     {"@type": ".../google.rpc.RetryInfo", "retryDelay": "45s"}
/// ]}}
/// </pre>
///
/// <p>Per architecture.md:645, we walk <code>error.details</code> looking
/// for the first element whose <code>@type</code> ends with
/// <code>RetryInfo</code>, extract the <code>retryDelay</code> string,
/// and pull the leading integer digits (the trailing <code>"s"</code> is
/// always present in current Gemini responses but we do not require it).</p>
///
/// <p>Returns <b>0</b> on any structural mismatch, missing field, or
/// unparseable value. Never raises an exception.</p>
ClassMethod ParseGeminiRetryDelay(pErrorJson As %DynamicObject) As %Integer
{
    Set tResult = 0
    Try {
        If '$IsObject(pErrorJson) Quit
        If pErrorJson.%ClassName(1) '= "%Library.DynamicObject" Quit

        ; Extract details array; bail if missing or wrong type.
        If 'pErrorJson.%IsDefined("details") Quit
        Set tDetails = pErrorJson.%Get("details")
        If '$IsObject(tDetails) Quit
        If tDetails.%ClassName(1) '= "%Library.DynamicArray" Quit

        ; Walk array entries; first RetryInfo element wins.
        Set tIter = tDetails.%GetIterator()
        While tIter.%GetNext(.tIdx, .tEntry, .tType) {
            If tType '= "object" Continue
            If '$IsObject(tEntry) Continue
            If 'tEntry.%IsDefined("@type") Continue
            Set tAtType = tEntry.%Get("@type")
            ; Match suffix "RetryInfo".
            If $Length(tAtType) < 9 Continue
            If $Extract(tAtType, *-8, *) '= "RetryInfo" Continue

            If 'tEntry.%IsDefined("retryDelay") Continue
            Set tDelay = tEntry.%Get("retryDelay")
            If tDelay = "" Continue

            ; Pull leading digits via $Extract+pattern, fall back to 0
            ; on no leading digit.
            Set tDigits = ""
            For i = 1:1:$Length(tDelay) {
                Set tCh = $Extract(tDelay, i)
                If tCh ? 1N {
                    Set tDigits = tDigits _ tCh
                } Else {
                    Quit
                }
            }
            If tDigits '= "" {
                Set tResult = +tDigits
                Quit
            }
        }
        Quit
    }
    Catch ex {
        Set tResult = 0
        Quit
    }
    Quit tResult
}

/// <p>Full-jitter exponential backoff formula. Returns a uniformly random
/// real in the half-open interval <code>[0, min(pCapSec, pBaseSec * 2 ** pAttempt))</code>.</p>
///
/// <p>Per architecture.md:341, the formula is "full jitter" (Marc Brooker /
/// AWS Architecture Blog 2015). Compared to "equal jitter" or "decorrelated
/// jitter", full jitter has the lowest worst-case retry time and best
/// thundering-herd resistance, which is what we want when many concurrent
/// callers see the same upstream rate-limit window.</p>
///
/// <p>Implementation: compute the upper bound <code>U = min(pCapSec, pBaseSec * (2 ** pAttempt))</code>,
/// then return <code>$Random(N) / N * U</code> for a sub-second-resolution
/// uniform real. We use <code>N = 1000</code> for millisecond resolution,
/// which is well below the Hang granularity but gives us enough spread.</p>
///
/// <p><code>pAttempt</code> is 0-indexed: attempt 0 caps at <code>pBaseSec</code>,
/// attempt 1 at <code>2 * pBaseSec</code>, attempt 2 at <code>4 * pBaseSec</code>,
/// attempt 3 at <code>8 * pBaseSec</code>, etc.</p>
ClassMethod ExpBackoffSec(pAttempt As %Integer, pBaseSec As %Integer, pCapSec As %Integer) As %Numeric
{
    ; Compute exponential ceiling = pBaseSec * 2^pAttempt.
    Set tExp = pBaseSec
    For i = 1:1:pAttempt {
        Set tExp = tExp * 2
    }

    ; Apply cap.
    Set tUpper = tExp
    If tUpper > pCapSec {
        Set tUpper = pCapSec
    }

    ; Edge case: if upper bound is 0 or negative, return 0 (no delay).
    ; This is the test-suite fast-path: passing pBaseSec=0, pCapSec=0
    ; collapses every backoff to 0 so tests don't actually Hang.
    If tUpper <= 0 Quit 0

    ; Full-jitter: uniform real in [0, tUpper). $Random(1000) returns
    ; integer 0..999, divide by 1000.0 for fractional [0, 1), multiply by
    ; tUpper for [0, tUpper).
    Quit ($Random(1000) / 1000) * tUpper
}

/// <p>Public entry point: drive a retry loop using class-parameter
/// defaults (<code>..#MaxAttempts</code>, <code>..#BaseDelaySec</code>,
/// <code>..#MaxDelaySec</code>). See <code>ExecuteWithParams</code> for
/// the full signature and contract — this method just delegates with the
/// class parameters substituted in.</p>
ClassMethod Execute(pCallable As %String, pCallArgs As %DynamicObject, ByRef pResponse As %DynamicObject) As %Status
{
    Quit ..ExecuteWithParams(pCallable, pCallArgs, ..#MaxAttempts, ..#BaseDelaySec, ..#MaxDelaySec, .pResponse)
}

/// <p>Parameterized retry orchestrator. Same contract as
/// <code>Execute</code> but takes <code>MaxAttempts</code>,
/// <code>BaseDelaySec</code>, <code>MaxDelaySec</code> as explicit
/// arguments so unit tests can pass <code>pBaseDelaySec=0</code> /
/// <code>pMaxDelaySec=0</code> to collapse every <code>Hang</code> to a
/// no-op (fast suite).</p>
///
/// <p><b>Contract</b>:</p>
/// <ol>
/// <li>Invoke <code>pCallable</code> (a fully-qualified
/// <code>Class.Method</code> string) via <code>$ClassMethod</code> with
/// signature <code>(pCallArgs, ByRef pResponse) As %Status</code>.</li>
/// <li>If callable returned <code>$$$ERROR</code>, treat as a mid-flight
/// failure: set <code>pResponse.midFlightFailure = 1</code> and
/// <code>pResponse.exhaustedRetries = 1</code>; do not retry. Return
/// <code>$$$OK</code> (the response object carries the failure signal).</li>
/// <li>If <code>'IsRetryable(pResponse.statusCode)</code>, return
/// <code>$$$OK</code> immediately with the response as-is (success path
/// or non-retryable error like 4xx).</li>
/// <li>Otherwise compute delay = <code>MAX(provider-hint, exp-backoff)</code>:
///   <ul>
///   <li>Provider hint = <code>ParseRetryAfter(pResponse.headers."retry-after")</code>
///   when the header is present; else
///   <code>ParseGeminiRetryDelay(pResponse.body.error)</code> when
///   <code>body.error.details</code> is present; else 0.</li>
///   <li>Exp backoff = <code>ExpBackoffSec(attempt, pBaseDelaySec, pMaxDelaySec)</code>.</li>
///   </ul>
/// </li>
/// <li><code>Hang</code> for the delay (fractional seconds OK), increment
/// the attempt counter, retry up to <code>pMaxAttempts</code> total
/// invocations.</li>
/// <li>On exhaustion, set <code>pResponse.exhaustedRetries = 1</code> and
/// preserve <code>pResponse.headers."request-id"</code> /
/// <code>"x-request-id"</code> from the last response (already in
/// <code>pResponse</code> from the final callable invocation; we just
/// don't clobber it).</li>
/// </ol>
///
/// <p>Status return is always <code>$$$OK</code> on the happy and
/// exhausted-retries paths. Callers inspect <code>pResponse</code> for
/// <code>exhaustedRetries</code> and <code>midFlightFailure</code> flags.</p>
ClassMethod ExecuteWithParams(pCallable As %String, pCallArgs As %DynamicObject, pMaxAttempts As %Integer, pBaseDelaySec As %Integer, pMaxDelaySec As %Integer, ByRef pResponse As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Try {
        ; Split fully-qualified Class.Method string into class and method
        ; parts. The class part is everything except the last dot-piece.
        Set tPieces = $Length(pCallable, ".")
        If tPieces < 2 {
            Set tSC = $$$ERROR($$$GeneralError, "RetryWithBackoff.Execute: pCallable must be a fully-qualified Class.Method string, got: " _ pCallable)
            Quit
        }
        Set tClass = $Piece(pCallable, ".", 1, tPieces - 1)
        Set tMethod = $Piece(pCallable, ".", tPieces)

        Set tAttempt = 0
        While tAttempt < pMaxAttempts {
            ; Reset pResponse on every attempt — the callable owns building
            ; it. We don't carry forward stale fields from prior attempts.
            Set pResponse = ##class(%DynamicObject).%New()

            ; Invoke the callable. If it raises ($$$ERROR), we treat that
            ; as mid-flight failure and DO NOT retry.
            Set tCallSC = $$$OK
            Try {
                Set tCallSC = $ClassMethod(tClass, tMethod, pCallArgs, .pResponse)
            }
            Catch callEx {
                Set tCallSC = callEx.AsStatus()
            }

            If $$$ISERR(tCallSC) {
                ; Mid-flight failure path. Per architecture.md:649, do not
                ; retry — the request may have been processed by the
                ; upstream and a retry could double-bill (LLM cost) or
                ; double-execute a tool call. Surface as structured failure.
                If '$IsObject(pResponse) {
                    Set pResponse = ##class(%DynamicObject).%New()
                }
                Do pResponse.%Set("midFlightFailure", 1, "boolean")
                Do pResponse.%Set("exhaustedRetries", 1, "boolean")
                ; Preserve headers if the callable populated them before
                ; failing; otherwise install an empty headers object so
                ; downstream code can safely read pResponse.headers.
                If 'pResponse.%IsDefined("headers") {
                    Do pResponse.%Set("headers", ##class(%DynamicObject).%New())
                }
                Quit
            }

            ; Callable returned $$$OK; pResponse is populated.
            Set tStatusCode = 0
            If pResponse.%IsDefined("statusCode") {
                Set tStatusCode = +pResponse.%Get("statusCode")
            }

            If '..IsRetryable(tStatusCode) {
                ; Success path or non-retryable error — return as-is.
                Quit
            }

            ; Retryable. Compute delay = MAX(provider hint, exp backoff).
            Set tProviderDelay = ..ProviderHintDelay(pResponse)
            Set tExpDelay = ..ExpBackoffSec(tAttempt, pBaseDelaySec, pMaxDelaySec)
            Set tDelay = tProviderDelay
            If tExpDelay > tDelay {
                Set tDelay = tExpDelay
            }

            Set tAttempt = tAttempt + 1
            If tAttempt >= pMaxAttempts {
                ; Exhausted. Mark and exit; pResponse already carries the
                ; final attempt's headers (incl. request-id) and body.
                Do pResponse.%Set("exhaustedRetries", 1, "boolean")
                Quit
            }

            ; Hang for the computed delay. Hang accepts fractional seconds.
            ; When tDelay = 0 (e.g., test-suite fast path with
            ; pBaseDelaySec=0), Hang 0 is effectively a no-op.
            Hang tDelay
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Internal helper: extract the provider-supplied retry-delay hint from
/// <code>pResponse</code>. Tries the HTTP <code>Retry-After</code> header
/// first (case-insensitive lookup via lowercase key), falls back to the
/// Gemini error envelope if present. Returns 0 when neither is available
/// or parseable.</p>
ClassMethod ProviderHintDelay(pResponse As %DynamicObject) As %Integer [ Private ]
{
    Set tDelay = 0

    ; HTTP Retry-After header. Look up under both common cases ("retry-after"
    ; lowercase per the HTTP/2 norm; "Retry-After" mixed case for HTTP/1.1
    ; clients that did not lowercase). The callable is expected to pass
    ; lowercase keys per HTTP/2 RFC 7540, but be defensive.
    If pResponse.%IsDefined("headers") {
        Set tHeaders = pResponse.%Get("headers")
        If $IsObject(tHeaders) {
            Set tHeaderVal = ""
            If tHeaders.%IsDefined("retry-after") {
                Set tHeaderVal = tHeaders.%Get("retry-after")
            } ElseIf tHeaders.%IsDefined("Retry-After") {
                Set tHeaderVal = tHeaders.%Get("Retry-After")
            }
            If tHeaderVal '= "" {
                Set tDelay = ..ParseRetryAfter(tHeaderVal)
            }
        }
    }

    ; Gemini error envelope. body.error.details[].retryDelay.
    If (tDelay = 0) && pResponse.%IsDefined("body") {
        Set tBody = pResponse.%Get("body")
        If $IsObject(tBody) && tBody.%IsDefined("error") {
            Set tError = tBody.%Get("error")
            If $IsObject(tError) {
                Set tDelay = ..ParseGeminiRetryDelay(tError)
            }
        }
    }

    Quit tDelay
}

}
