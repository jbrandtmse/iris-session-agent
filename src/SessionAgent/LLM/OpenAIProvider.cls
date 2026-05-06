/// <p>Concrete <CLASS>SessionAgent.LLM.Provider</CLASS> implementation for
/// OpenAI's Chat Completions API. First concrete LLM provider shipped per
/// architecture OD4 (OpenAI-first ship priority); proves the abstract
/// pattern Story 2.8 established + the
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> /
/// <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS> adapters.</p>
///
/// <p><b>FR27 canonical-wire adapter.</b> All inbound canonical-shape
/// histories pass through
/// <method>SessionAgent.LLM.Util.MessageAdapter.CanonicalToProvider</method>
/// before HTTP send; all outbound provider responses pass through
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// before populating <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>.
/// Concrete OWNS the canonical translation calls per the Provider abstract
/// class doc-comment.</p>
///
/// <p><b>FR28 5th-provider extensibility.</b> Adding a new
/// concrete (Anthropic, Gemini, OpenAICompat in Stories 5.1-5.3) requires
/// no edits to this class; the only intersection point is the canonical
/// adapter and the abstract surface.</p>
///
/// <p><b>FR29 90s timeout.</b> Sets <code>%Net.HttpRequest.Timeout = 90</code>
/// per call; locked by class parameter <code>HTTPTIMEOUTSEC</code> so any
/// regression flips a static-time assertion.</p>
///
/// <p><b>NFR-S3 never-log invariant.</b> The resolved API key is fetched
/// inside <method>CallMessages</method> via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> and stays in the
/// local stack frame. It feeds the <code>Authorization</code> header
/// (constructed by <method>GetAuthHeader</method>) and is never copied
/// into <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>, error text,
/// audit rows, or any other persisted surface. The
/// <method>BuildPayload</method> helper deliberately accepts the canonical
/// inputs only — the API key is never in its signature, so it cannot be
/// accidentally embedded in the request body.</p>
///
/// <p><b>Retry-wrapping design (story 2.9 dev choice (ii) — inline).</b>
/// <method>CallMessages</method> drives an inline retry loop, calling
/// <method>IssueHttpsPost</method> directly on each attempt and using the
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS> stateless helpers
/// (<method>IsRetryable</method>, <method>ExpBackoffSec</method>,
/// <method>ParseRetryAfter</method>) to compute the backoff delay. This
/// keeps virtual dispatch on <method>IssueHttpsPost</method> intact (test
/// subclasses' overrides are honored without any back-channel mechanism)
/// and avoids the
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method>
/// <code>$ClassMethod</code>-static-dispatch path that would lose the
/// instance reference. The abstract template
/// <method>SessionAgent.LLM.Provider.Invoke</method> is unchanged
/// (continues to call <code>..CallMessages</code> directly), so the retry
/// surface lives entirely inside the concrete — no cross-cutting changes
/// to the abstract / future concretes are required.</p>
///
/// <p><b>Mock-HTTP design (story 2.9 dev choice — option C).</b> The HTTP
/// send is extracted into a separate instance method
/// <method>IssueHttpsPost</method> that takes a payload string + auth
/// header + timeout and returns a canonical response object
/// <code>{statusCode, body, headers}</code>. Tests subclass
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> and override
/// <method>IssueHttpsPost</method> to inject canned responses without
/// touching the network or any process-private global.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.9</a> (lines 950-983) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Provider abstraction" line 810 — module path; FR27/FR28/FR29
/// per <a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>.</li>
/// <li>OpenAI Chat Completions API:
/// <code>https://platform.openai.com/docs/api-reference/chat/create</code>.</li>
/// <li><a href="../../../irislib/%25Net/HttpRequest.cls">irislib/%Net/HttpRequest.cls</a>
/// — Https/SSLConfiguration/Timeout/Server/Location/EntityBody properties
/// (lines 426, 558, 605, 631, 633, 665); Post() method (line 986);
/// HttpResponse property (line 780).</li>
/// </ul>
Class SessionAgent.LLM.OpenAIProvider Extends SessionAgent.LLM.Provider
{

/// <p>Provider name as it appears in
/// <property>SessionAgent.Config.Agent.Provider</property> and the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> Provider dimension.</p>
Parameter PROVIDERNAME = "openai";

/// <p>Default OpenAI Chat Completions endpoint URL. Overridden when
/// <property>SessionAgent.Config.Agent.EndpointUrl</property> is set
/// (typically empty for openai; populated for openai-compatible).</p>
Parameter DEFAULTENDPOINTURL = "https://api.openai.com/v1/chat/completions";

/// <p>Per-call HTTP timeout, in seconds, per FR29.</p>
Parameter HTTPTIMEOUTSEC As INTEGER = 90;

/// <p>SSL configuration name. Operator pre-requisite documented in
/// README §Operator Prerequisites.</p>
Parameter SSLCONFIGURATION = "DefaultSSL";

/// <p>OpenAI default canonical Server hostname. Used when the configured
/// endpoint URL is the canonical one; openai-compatible providers in
/// Story 5.3 will override the parsed Server / Location.</p>
Parameter DEFAULTSERVER = "api.openai.com";

/// <p>OpenAI canonical Location path.</p>
Parameter DEFAULTLOCATION = "/v1/chat/completions";

/// <p>Cached Config.Agent reference. The AgentLoop sets this on the
/// provider instance immediately after construction; the concrete reads
/// it in <method>CallMessages</method> for credential resolution and
/// payload-build (model/temperature/max_tokens come from this row).</p>
Property ConfigAgent As SessionAgent.Config.Agent;

/// <p>Cached api key for the in-flight call. Set by
/// <method>CallMessages</method> after
/// <method>SessionAgent.Util.EnvSecret.Resolve</method>; cleared after
/// the retry loop exits. Property scope is per-instance and the AgentLoop
/// instantiates one provider per turn, so this property never persists
/// the key across requests.</p>
///
/// <p><b>NFR-S3 invariant.</b> This property is the only place the
/// resolved key lives once <method>CallMessages</method> begins; after the
/// retry loop exits, the property is set back to <code>""</code> in the
/// caller's finally-equivalent path (after the retry orchestrator returns
/// and before <method>CallMessages</method> returns to
/// <method>Provider.Invoke</method>).</p>
Property ApiKey As %String [ Internal ];

/// <p>Concrete — return the OpenAI Chat Completions endpoint URL. Reads
/// from the cached <property>ConfigAgent.EndpointUrl</property> when set;
/// falls back to <code>..#DEFAULTENDPOINTURL</code>.</p>
///
/// <p>The abstract signature on <CLASS>SessionAgent.LLM.Provider</CLASS>
/// is parameterless; this concrete reads from the per-instance
/// <property>ConfigAgent</property> back-channel set by
/// <method>CallMessages</method> before any URL lookup is needed.</p>
Method GetEndpointUrl() As %String
{
    ; Story 4.0 codification: $Char(0) is IRIS's legacy %String null sentinel
    ; for columns whose value was set to "" via SQL UPDATE; treat it as the
    ; empty string so the canonical fallback engages. Bug-1 surfaced 2026-05-06.
    Set tStored = ""
    If $IsObject(..ConfigAgent) Set tStored = ..ConfigAgent.EndpointUrl
    If tStored = $Char(0) Set tStored = ""
    If tStored '= "" Quit tStored
    Quit ..#DEFAULTENDPOINTURL
}

/// <p>Concrete — return the HTTP <code>Authorization</code> header value
/// for the given API key in OpenAI's Bearer-token format.</p>
///
/// <p><b>NFR-S3 invariant.</b> The returned string carries the key.
/// Callers (only <method>CallMessages</method> /
/// <method>IssueHttpsPost</method>) MUST set this directly on
/// <CLASS>%Net.HttpRequest</CLASS> via
/// <method>SetHeader</method> and never persist it.</p>
Method GetAuthHeader(pApiKey As %String) As %String
{
    Quit "Bearer " _ pApiKey
}

/// <p>Concrete — return the canonical provider name
/// (<code>openai</code>).</p>
Method GetProviderName() As %String
{
    Quit ..#PROVIDERNAME
}

/// <p>Concrete — issue one OpenAI Chat Completions round-trip with inline
/// retry. See class doc-comment for the retry-wrapping design (option
/// (ii) — inline) and mock-HTTP design (option C —
/// <method>IssueHttpsPost</method> override hook).</p>
///
/// <p><b>Flow.</b></p>
/// <ol>
/// <li>Resolve API key via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method>; cache on
/// <property>ApiKey</property> (cleared at end). If empty, populate
/// pProviderResponse with the credential-missing error envelope and
/// return — the retry layer is not engaged because there is no point
/// retrying a missing credential.</li>
/// <li>Build the OpenAI request payload via
/// <method>BuildPayload</method>.</li>
/// <li>Drive the inline retry loop: call <method>IssueHttpsPost</method>
/// up to <method>GetMaxAttempts</method> times; on retryable status
/// (429 / 5xx per
/// <method>SessionAgent.Util.RetryWithBackoff.IsRetryable</method>),
/// <code>Hang</code> for
/// <code>MAX(provider hint, exp backoff)</code>; on non-retryable status
/// or exhaustion, exit the loop. Provider hint = parsed Retry-After
/// header via
/// <method>SessionAgent.Util.RetryWithBackoff.ParseRetryAfter</method>;
/// exp backoff = full-jitter via
/// <method>SessionAgent.Util.RetryWithBackoff.ExpBackoffSec</method>.</li>
/// <li>If the final response is non-2xx OR mid-flight, populate
/// pProviderResponse with the structured-error envelope; otherwise
/// translate the body via
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// and copy Content / StopReason / Usage into pProviderResponse.</li>
/// </ol>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK

    ; Always create the response envelope so the caller sees a valid
    ; object even on the credential-missing fast path.
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }

    Try {
        ; Step 1 — resolve API key. The Invoke template also resolves the
        ; key for its credential-missing fast path; we re-resolve here so
        ; the concrete owns the resolved value (Invoke does not pass it
        ; through to CallMessages — see Provider.cls comment line 228).
        Set tEnvVar = ""
        Set tCredName = ""
        If $IsObject(..ConfigAgent) {
            Set tEnvVar = ..ConfigAgent.EnvVarName
            Set tCredName = ..ConfigAgent.CredentialName
        }
        Set ..ApiKey = ##class(SessionAgent.Util.EnvSecret).Resolve(tEnvVar, tCredName)

        If ..ApiKey = "" {
            ; Credential missing — populate envelope, no retry.
            Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI credential resolution failed")
            ; Argumentless quit per project rule §"QUIT Statement Restrictions".
            Quit
        }

        ; Step 2 — build the payload (testable in isolation).
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()
        Set tAuthHeader = ..GetAuthHeader(..ApiKey)
        Set tEndpointUrl = ..GetEndpointUrl()
        Set tTimeoutSec = ..#HTTPTIMEOUTSEC

        ; Step 3 — inline retry loop. State carried across attempts:
        ; tStatusCode / tBodyStr / tHeaders / tMidFlight / tExhausted.
        Set tMaxAttempts = ..GetMaxAttempts()
        Set tBaseDelaySec = ..GetBaseDelaySec()
        Set tMaxDelaySec = ..GetMaxDelaySec()
        Set tAttempt = 0
        Set tStatusCode = 0
        Set tBodyStr = ""
        Set tHeaders = $$$NULLOREF
        Set tMidFlight = 0
        Set tExhausted = 0

        While tAttempt < tMaxAttempts {
            ; Reset the per-attempt response.
            Set tStatusCode = 0
            Set tBodyStr = ""
            Set tHeaders = ##class(%DynamicObject).%New()

            ; Issue one HTTPS POST. Wrap in Try/Catch so a thrown HTTP
            ; failure is treated as mid-flight (no retry) per
            ; architecture.md:649.
            Set tHttpFailed = 0
            Try {
                Set tHttpResp = ..IssueHttpsPost(tPayloadJson, tAuthHeader, tEndpointUrl, tTimeoutSec)
                Set tStatusCode = +tHttpResp.%Get("statusCode")
                Set tBodyStr = tHttpResp.%Get("bodyText")
                If tHttpResp.%IsDefined("headers") {
                    Set tHeaders = tHttpResp.%Get("headers")
                }
            } Catch postEx {
                Set tHttpFailed = 1
            }

            If tHttpFailed {
                ; Mid-flight — request may have been processed; do NOT retry.
                Set tMidFlight = 1
                Quit
            }

            ; Retryable? Use the stateless helper.
            If '##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(tStatusCode) {
                ; Success or non-retryable error — exit loop, will be
                ; classified below.
                Quit
            }

            Set tAttempt = tAttempt + 1
            If tAttempt >= tMaxAttempts {
                Set tExhausted = 1
                Quit
            }

            ; Compute delay = MAX(provider hint, exp backoff). Provider
            ; hint reads Retry-After from the response headers.
            Set tProviderDelay = 0
            If $IsObject(tHeaders), tHeaders.%IsDefined("retry-after") {
                Set tProviderDelay = ##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter(tHeaders.%Get("retry-after"))
            }
            Set tExpDelay = ##class(SessionAgent.Util.RetryWithBackoff).ExpBackoffSec(tAttempt - 1, tBaseDelaySec, tMaxDelaySec)
            Set tDelay = tProviderDelay
            If tExpDelay > tDelay {
                Set tDelay = tExpDelay
            }

            ; Hang accepts fractional seconds. tDelay = 0 is effectively a no-op.
            Hang tDelay
        }

        ; Step 4 — classify the final state.
        If tMidFlight {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI mid-flight failure (request may have been processed)")
            Quit
        }

        If (tStatusCode < 200) || (tStatusCode > 299) {
            ; Non-2xx — structured error envelope. Includes status code +
            ; body for operator diagnosis. Body may carry the OpenAI
            ; error.message; we surface it verbatim. NEVER include the
            ; api key (it's in the request header, not the body).
            Set tErrText = "OpenAI HTTP " _ tStatusCode _ ": " _ tBodyStr
            If tExhausted {
                Set tErrText = "OpenAI retries exhausted (HTTP " _ tStatusCode _ "): " _ tBodyStr
            }
            Do ..PopulateErrorEnvelope(.pProviderResponse, tErrText)
            Quit
        }

        ; 2xx — parse body, translate to canonical, populate envelope.
        Set tBodyObj = ##class(%DynamicObject).%New()
        If tBodyStr '= "" {
            Try {
                Set tBodyObj = ##class(%DynamicObject).%FromJSON(tBodyStr)
            } Catch parseEx {
                Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI response body not parseable JSON: " _ $Extract(tBodyStr, 1, 200))
                Quit
            }
        }

        Set tCanon = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical(..#PROVIDERNAME, tBodyObj)

        Set pProviderResponse.Content = tCanon.%Get("content")
        Set pProviderResponse.StopReason = tCanon.%Get("stopReason")
        Set pProviderResponse.Usage = tCanon.%Get("usage")
    }
    Catch ex {
        ; Hard exception during build/translate — structured envelope so
        ; the AgentLoop never crashes mid-turn. The Invoke template will
        ; see StopReason = "error" and emit the audit row with IsError=1.
        Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI CallMessages exception: " _ ex.DisplayString())
    }

    ; Finally-equivalent — clear the api key.
    Set ..ApiKey = ""

    Quit tSC
}

/// <p>Build the OpenAI Chat Completions request payload as a fresh
/// <CLASS>%DynamicObject</CLASS>. Extracted as a separate method (instead
/// of inlined in <method>CallMessages</method>) so unit tests can assert
/// the payload shape without engaging the HTTP / retry infrastructure.</p>
///
/// <p><b>Payload shape.</b></p>
/// <pre>
/// {
///   "model": &lt;configAgent.Model&gt;,
///   "temperature": &lt;configAgent.Temperature&gt;,
///   "max_tokens": &lt;configAgent.MaxTokens&gt;,
///   "messages": [&lt;openai-shape messages&gt;],
///   "tools": [&lt;openai-shape tool defs&gt;]
/// }
/// </pre>
///
/// <p><b>System prompt handling.</b> When <var>pSystemPrompt</var> is
/// non-empty, prepend a <code>{role:"system", content:&lt;prompt&gt;}</code>
/// message to <code>messages</code>; canonical history adapter does not
/// inject this because canonical (Anthropic-shape) carries the system
/// prompt out-of-band.</p>
///
/// <p><b>NFR-S3 invariant.</b> The signature deliberately does NOT
/// include the api key; the key never enters the payload. Cache control
/// markers are also not included — OpenAI auto-caches >= 1024 tokens
/// without per-call hints.</p>
Method BuildPayload(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pConfigAgent As SessionAgent.Config.Agent) As %DynamicObject
{
    Set tPayload = ##class(%DynamicObject).%New()

    ; Model / temperature / max_tokens — read from config; sensible
    ; fallbacks so a misconfigured agent does not crash the build (the
    ; HTTP send will surface OpenAI's validation error instead).
    Set tModel = ""
    Set tTemperature = 0
    Set tMaxTokens = 0
    If $IsObject(pConfigAgent) {
        Set tModel = pConfigAgent.Model
        Set tTemperature = pConfigAgent.Temperature
        Set tMaxTokens = pConfigAgent.MaxTokens
    }
    Do tPayload.%Set("model", tModel)
    Do tPayload.%Set("temperature", +tTemperature, "number")
    Do tPayload.%Set("max_tokens", +tMaxTokens, "number")

    ; Messages — translate canonical to OpenAI shape, prepend system role
    ; message if pSystemPrompt is non-empty.
    Set tOaMessages = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider(..#PROVIDERNAME, pCanonicalHistory)
    If pSystemPrompt '= "" {
        ; Build a fresh array with system first, then unshift the rest.
        Set tFinalMessages = ##class(%DynamicArray).%New()
        Set tSystemMsg = ##class(%DynamicObject).%New()
        Do tSystemMsg.%Set("role", "system")
        Do tSystemMsg.%Set("content", pSystemPrompt)
        Do tFinalMessages.%Push(tSystemMsg)
        Set tIter = tOaMessages.%GetIterator()
        While tIter.%GetNext(.tIdx, .tMsg) {
            Do tFinalMessages.%Push(tMsg)
        }
        Do tPayload.%Set("messages", tFinalMessages)
    } Else {
        Do tPayload.%Set("messages", tOaMessages)
    }

    ; Tools — translate canonical to OpenAI shape via ToolDefAdapter.
    Set tOaTools = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider(..#PROVIDERNAME, pToolDefs)
    Do tPayload.%Set("tools", tOaTools)

    Quit tPayload
}

/// <p>Issue one HTTPS POST to the OpenAI Chat Completions endpoint.
/// Returns a <CLASS>%DynamicObject</CLASS> with
/// <code>{statusCode, bodyText, headers}</code>.</p>
///
/// <p><b>Mock-HTTP override hook.</b> Tests subclass
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> and override this method
/// to inject canned responses without engaging the network. The override
/// returns the same shape; production code is unchanged.</p>
///
/// <p><b>Settings.</b></p>
/// <ul>
/// <li><code>Https = 1</code> — HTTPS only, never plain HTTP.</li>
/// <li><code>SSLConfiguration = "DefaultSSL"</code> — operator
/// pre-requisite documented in README §Operator Prerequisites.</li>
/// <li><code>Timeout = ..#HTTPTIMEOUTSEC</code> (90s, FR29).</li>
/// <li>Server / Location parsed from <var>pEndpointUrl</var> when
/// non-canonical (openai-compatible providers); falls back to
/// canonical OpenAI host/path for the default URL.</li>
/// <li><code>Authorization</code> + <code>Content-Type</code> headers
/// set via <method>%Net.HttpRequest.SetHeader</method>.</li>
/// </ul>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", 0)
    Do tResp.%Set("bodyText", "")
    Do tResp.%Set("headers", ##class(%DynamicObject).%New())

    Try {
        ; Parse Server + Location + Port + Https from pEndpointUrl. Story 5.3
        ; centralized parser on the abstract base; returns
        ;   {server, port, location, https}.
        Set tServer = ..#DEFAULTSERVER
        Set tLocation = ..#DEFAULTLOCATION
        Set tPort = 0
        Set tHttps = 1
        If pEndpointUrl '= "" {
            Set tParsed = ..ParseEndpointUrl(pEndpointUrl)
            Set tServer = tParsed.%Get("server")
            Set tLocation = tParsed.%Get("location")
            Set tPort = +tParsed.%Get("port")
            Set tHttps = +tParsed.%Get("https")
        }

        Set tReq = ##class(%Net.HttpRequest).%New()
        Set tReq.Https = tHttps
        If tHttps = 1 {
            Set tReq.SSLConfiguration = ..#SSLCONFIGURATION
        }
        Set tReq.Timeout = pTimeoutSec
        Set tReq.Server = tServer
        If tPort > 0 {
            Set tReq.Port = tPort
        }
        Set tReq.ContentType = "application/json"
        Do tReq.SetHeader("Authorization", pAuthHeader)

        ; Write the JSON payload to EntityBody. EntityBody is a
        ; %GlobalBinaryStream per irislib/%Net/HttpRequest.cls:426.
        Do tReq.EntityBody.Write(pPayloadJson)

        Set tPostSC = tReq.Post(tLocation)
        If $$$ISERR(tPostSC) {
            ; Treat HTTP-layer failures as 0 status; let the retry layer
            ; mark midFlightFailure (we received no response).
            Throw ##class(%Exception.General).%New("OpenAIProvider.IssueHttpsPost",,,$System.Status.GetErrorText(tPostSC))
        }

        Set tHttpResp = tReq.HttpResponse
        Do tResp.%Set("statusCode", +tHttpResp.StatusCode)

        ; Read response body. HttpResponse.Data is %RawString; can be a
        ; stream or a string per irislib/%Net/HttpResponse.cls:14.
        Set tBody = ""
        If $IsObject(tHttpResp.Data) {
            Do tHttpResp.Data.Rewind()
            While 'tHttpResp.Data.AtEnd {
                Set tBody = tBody _ tHttpResp.Data.Read(32000)
            }
        } Else {
            Set tBody = tHttpResp.Data
        }
        Do tResp.%Set("bodyText", tBody)

        ; Surface Retry-After header to the retry orchestrator.
        Set tRetryAfter = tHttpResp.GetHeader("Retry-After")
        If tRetryAfter '= "" {
            Set tHeaders = tResp.%Get("headers")
            Do tHeaders.%Set("retry-after", tRetryAfter)
        }
    }
    Catch ex {
        ; HTTP failure -- bubble up to the inline retry loop in
        ; CallMessages, which classifies the throw as mid-flight.
        Throw ex
    }

    Quit tResp
}

/// <p>Per-instance hook returning the
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method>
/// MaxAttempts param. Defaults to <code>4</code> (mirrors
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>'s class parameter);
/// test subclasses override to collapse the retry loop in the unit-test
/// fast path. The mirror is intentional: the hook is the override seam,
/// keeping the production value bounded by the same architecture.md:341
/// calibration constant the orchestrator uses by default.</p>
Method GetMaxAttempts() As %Integer
{
    Quit 4
}

/// <p>Per-instance hook returning the
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method>
/// BaseDelaySec param. Defaults to <code>1</code> (mirrors
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>'s class parameter);
/// test subclasses override to <code>0</code> to collapse Hang to a
/// no-op.</p>
Method GetBaseDelaySec() As %Integer
{
    Quit 1
}

/// <p>Per-instance hook returning the
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method>
/// MaxDelaySec param. Defaults to <code>32</code> (mirrors
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>'s class parameter);
/// test subclasses override to <code>0</code> to collapse Hang to a
/// no-op.</p>
Method GetMaxDelaySec() As %Integer
{
    Quit 32
}

/// <p>Internal helper — populate pResp with the structured-error envelope
/// and zero-token usage. Same shape as
/// <method>SessionAgent.LLM.Provider.PopulateGenericError</method> but
/// scoped to the OpenAI concrete so this method can be invoked without
/// crossing the abstract.</p>
ClassMethod PopulateErrorEnvelope(ByRef pResp As SessionAgent.Agent.ProviderResponse, pMsg As %String) [ Internal ]
{
    If '$IsObject(pResp) {
        Set pResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }
    Set pResp.StopReason = "error"
    Set pResp.Content = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", pMsg)
    Do pResp.Content.%Push(tBlock)
    Set pResp.Usage = ##class(%DynamicObject).%New()
    Do pResp.Usage.%Set("input_tokens", 0)
    Do pResp.Usage.%Set("output_tokens", 0)
    Do pResp.Usage.%Set("cache_creation_input_tokens", 0)
    Do pResp.Usage.%Set("cache_read_input_tokens", 0)
    Quit
}

}
