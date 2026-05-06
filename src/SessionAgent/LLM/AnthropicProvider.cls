/// <p>Concrete <CLASS>SessionAgent.LLM.Provider</CLASS> implementation for
/// Anthropic's Messages API. Second cloud provider after Story 2.9
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> per architecture OD4 +
/// FR28 5th-provider extensibility.</p>
///
/// <p><b>FR27 canonical-passthrough.</b> The canonical wire shape IS the
/// Anthropic Messages API shape (see
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> doc-comment). This
/// concrete therefore performs <b>no</b> message translation — it simply
/// passes <var>pCanonicalHistory</var> straight into the request payload's
/// <code>messages</code> field. Same for <var>pToolDefs</var>: the canonical
/// tool shape <code>{name, description, input_schema}</code> IS Anthropic's
/// tool-definition shape. <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS>
/// + <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS> both implement
/// <code>anthropic</code> as an explicit passthrough switch case so this
/// class is a stable adapter even though it never invokes them.</p>
///
/// <p><b>FR28 5th-provider extensibility.</b> Adding this concrete required
/// (a) one new subclass implementing the four abstract methods + (b) one
/// new dispatch entry in <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>.
/// No edits to the abstract base, no edits to
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> /
/// <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS>, no edits to
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>, no edits to
/// <CLASS>SessionAgent.Audit.Emit</CLASS>.</p>
///
/// <p><b>FR29 90s timeout.</b> Sets <code>%Net.HttpRequest.Timeout = 90</code>
/// per call via class parameter <code>HTTPTIMEOUTSEC</code>; mirrors the
/// Story 2.9 OpenAIProvider precedent so a single regression-test pivot
/// flips both providers if FR29 changes.</p>
///
/// <p><b>NFR-S3 never-log invariant.</b> The resolved API key is fetched
/// inside <method>CallMessages</method> via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> and stays in the
/// local stack frame plus the per-instance <property>ApiKey</property>
/// property (cleared at end). It feeds the <code>x-api-key</code> header
/// (constructed by <method>GetAuthHeader</method>) and is never copied
/// into <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>, error text,
/// audit rows, or any other persisted surface. The
/// <method>BuildPayload</method> helper deliberately accepts the canonical
/// inputs only — the API key is never in its signature, so it cannot be
/// accidentally embedded in the request body.</p>
///
/// <p><b>NFR-P6 cache plan.</b> The <code>cache_control: {type:"ephemeral"}</code>
/// markers are placed on the <code>system</code> block + the <b>last</b>
/// <code>tools[]</code> entry — and <b>only</b> there. User messages and
/// the per-turn vocabulary digest (Epic 9) sit in the uncached prefix
/// (intentionally — vocabulary content varies per session and would
/// invalidate the cache on every turn). The unit test
/// <CLASS>SessionAgent.Test.AnthropicProviderTest</CLASS>
/// <method>TestPayloadNoCacheControlOnUserMessages</method> is the
/// regression lock for this invariant.</p>
///
/// <p><b>Two-header auth.</b> Anthropic uses two HTTP headers (not a single
/// <code>Authorization</code>): <code>x-api-key: &lt;key&gt;</code> +
/// <code>anthropic-version: 2023-06-01</code>. <method>GetAuthHeader</method>
/// returns a <code>%List</code> of two header lines (<code>name: value</code>
/// each); the production
/// <method>IssueHttpsPost</method> iterates the list with
/// <method>%Net.HttpRequest.SetHeader</method>. Diverges from
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> (which returns a single
/// Bearer-format string) — same abstract method, different return shape;
/// per the abstract doc-comment §"Concrete decides whether the return
/// value is the Authorization header value or a different header name's
/// value".</p>
///
/// <p><b>Retry-wrapping design (Story 2.9 dev choice (ii) — inline).</b>
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
/// instance reference.</p>
///
/// <p><b>Mock-HTTP design (Story 2.9 dev choice — option C).</b> The HTTP
/// send is extracted into a separate instance method
/// <method>IssueHttpsPost</method> that takes a payload string + auth
/// header list + endpoint URL + timeout and returns a canonical response
/// object <code>{statusCode, bodyText, headers}</code>. Tests subclass
/// <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS> and override
/// <method>IssueHttpsPost</method> to inject canned responses without
/// touching the network or any process-private global.</p>
///
/// <p><b>Model default — Rule 10 verification.</b></p>
///
/// <p><i>Verified current as of 2026-05-06 via
/// <code>https://platform.claude.com/docs/en/about-claude/pricing</code>:
/// <code>claude-haiku-4-5-20251001</code> at $1.00 / $5.00 per MTok recommended
/// as cost-effective default for tool-use agents per the page's "Use Haiku
/// for simple tasks" cost-optimization guidance. Optional override
/// <code>claude-sonnet-4-6</code> ($3 / $15) for harder reasoning. Tool-use
/// system prompt overhead 346 tokens (<code>auto</code>/<code>none</code>).</i></p>
///
/// <p>The default value is set in
/// <property>SessionAgent.Config.Agent.Model</property> at agent-config seed
/// time (Story 2.4 / 6.x), not in this class itself. This doc-comment cites
/// the recommended default per Rule 10 spec-time research.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 5.1</a> (line 1666) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"External Integrations → Anthropic Messages API" — wire shape; FR27/FR28/FR29
/// per <a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>.</li>
/// <li>Anthropic Messages API:
/// <code>https://docs.anthropic.com/en/api/messages</code>.</li>
/// <li>Anthropic prompt caching:
/// <code>https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching</code>.</li>
/// <li><a href="../../../irislib/%25Net/HttpRequest.cls">irislib/%Net/HttpRequest.cls</a>
/// — Https/SSLConfiguration/Timeout/Server/Location/EntityBody properties;
/// Post() method; HttpResponse property.</li>
/// </ul>
Class SessionAgent.LLM.AnthropicProvider Extends SessionAgent.LLM.Provider
{

/// <p>Provider name as it appears in
/// <property>SessionAgent.Config.Agent.Provider</property> and the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> Provider dimension.</p>
Parameter PROVIDERNAME = "anthropic";

/// <p>Default Anthropic Messages endpoint URL. Overridden when
/// <property>SessionAgent.Config.Agent.EndpointUrl</property> is set
/// (rare for Anthropic; reserved for future Bedrock-style proxy hosts).</p>
Parameter DEFAULTENDPOINTURL = "https://api.anthropic.com/v1/messages";

/// <p>Anthropic API version pinned in the <code>anthropic-version</code>
/// HTTP header. <code>2023-06-01</code> is the long-stable line per
/// Anthropic's versioning policy (newer Messages API features remain
/// available under this version per backward-compat guarantee, verified
/// via Anthropic docs research 2026-05-06).</p>
Parameter ANTHROPICVERSION = "2023-06-01";

/// <p>Per-call HTTP timeout, in seconds, per FR29.</p>
Parameter HTTPTIMEOUTSEC As INTEGER = 90;

/// <p>SSL configuration name. Operator pre-requisite documented in
/// README §Operator Prerequisites; reuses the same
/// <code>DefaultSSL</code> profile the OpenAIProvider uses since both
/// hosts terminate against TLS 1.2+ standard CAs.</p>
Parameter SSLCONFIGURATION = "DefaultSSL";

/// <p>Anthropic default canonical Server hostname. Used when the
/// configured endpoint URL is the canonical one.</p>
Parameter DEFAULTSERVER = "api.anthropic.com";

/// <p>Anthropic canonical Location path.</p>
Parameter DEFAULTLOCATION = "/v1/messages";

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
/// retry loop exits, the property is set back to <code>""</code>.</p>
Property ApiKey As %String [ Internal ];

/// <p>Concrete — return the Anthropic Messages endpoint URL. Reads from
/// the cached <property>ConfigAgent.EndpointUrl</property> when set; falls
/// back to <code>..#DEFAULTENDPOINTURL</code>.</p>
Method GetEndpointUrl() As %String
{
    If $IsObject(..ConfigAgent), ..ConfigAgent.EndpointUrl '= "" {
        Quit ..ConfigAgent.EndpointUrl
    }
    Quit ..#DEFAULTENDPOINTURL
}

/// <p>Concrete — return the two HTTP headers Anthropic requires as a
/// <code>%List</code> of <code>name: value</code> strings:</p>
/// <ul>
/// <li><code>x-api-key: &lt;pApiKey&gt;</code></li>
/// <li><code>anthropic-version: &lt;..#ANTHROPICVERSION&gt;</code></li>
/// </ul>
///
/// <p>Diverges from
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>'s single-string Bearer
/// return shape — the abstract method's return is opaque per its
/// doc-comment, so each concrete picks the shape that best fits its
/// auth scheme.</p>
///
/// <p><b>NFR-S3 invariant.</b> The first list element carries the key.
/// Callers (only <method>CallMessages</method> /
/// <method>IssueHttpsPost</method>) MUST set both elements directly on
/// <CLASS>%Net.HttpRequest</CLASS> via
/// <method>SetHeader</method> and never persist them.</p>
Method GetAuthHeader(pApiKey As %String) As %String
{
    Quit $ListBuild("x-api-key: " _ pApiKey, "anthropic-version: " _ ..#ANTHROPICVERSION)
}

/// <p>Concrete — return the canonical provider name
/// (<code>anthropic</code>).</p>
Method GetProviderName() As %String
{
    Quit ..#PROVIDERNAME
}

/// <p>Concrete — issue one Anthropic Messages round-trip with inline
/// retry. See class doc-comment for the retry-wrapping design (option (ii)
/// — inline) and mock-HTTP design (option C —
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
/// <li>Build the Anthropic request payload via
/// <method>BuildPayload</method>.</li>
/// <li>Drive the inline retry loop: call <method>IssueHttpsPost</method>
/// up to <method>GetMaxAttempts</method> times; on retryable status
/// (429 / 5xx per
/// <method>SessionAgent.Util.RetryWithBackoff.IsRetryable</method>),
/// <code>Hang</code> for
/// <code>MAX(provider hint, exp backoff)</code>; on non-retryable status
/// or exhaustion, exit the loop.</li>
/// <li>If the final response is non-2xx OR mid-flight, populate
/// pProviderResponse with the structured-error envelope; otherwise
/// parse the body via <method>ParseResponse</method> and copy
/// Content / StopReason / Usage / Model into pProviderResponse.</li>
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
            ; Credential missing — populate envelope, no retry, no
            ; network call. AC-7 TestAuthFailureReturnsErrorStatus locks
            ; this fast path.
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Anthropic credential resolution failed")
            ; Argumentless quit per project rule §"QUIT Statement Restrictions".
            Quit
        }

        ; Step 2 — build the payload (testable in isolation).
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()
        Set tAuthHeaderList = ..GetAuthHeader(..ApiKey)
        Set tEndpointUrl = ..GetEndpointUrl()
        Set tTimeoutSec = ..#HTTPTIMEOUTSEC

        ; Step 3 — inline retry loop. Same shape as OpenAIProvider.
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

            Set tHttpFailed = 0
            Try {
                Set tHttpResp = ..IssueHttpsPost(tPayloadJson, tAuthHeaderList, tEndpointUrl, tTimeoutSec)
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

            If '##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(tStatusCode) {
                ; Success or non-retryable error — exit loop.
                Quit
            }

            Set tAttempt = tAttempt + 1
            If tAttempt >= tMaxAttempts {
                Set tExhausted = 1
                Quit
            }

            ; MAX(provider hint, exp backoff).
            Set tProviderDelay = 0
            If $IsObject(tHeaders), tHeaders.%IsDefined("retry-after") {
                Set tProviderDelay = ##class(SessionAgent.Util.RetryWithBackoff).ParseRetryAfter(tHeaders.%Get("retry-after"))
            }
            Set tExpDelay = ##class(SessionAgent.Util.RetryWithBackoff).ExpBackoffSec(tAttempt - 1, tBaseDelaySec, tMaxDelaySec)
            Set tDelay = tProviderDelay
            If tExpDelay > tDelay {
                Set tDelay = tExpDelay
            }

            Hang tDelay
        }

        ; Step 4 — classify the final state.
        If tMidFlight {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Anthropic mid-flight failure (request may have been processed)")
            Quit
        }

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Set tErrText = "Anthropic HTTP " _ tStatusCode _ ": " _ tBodyStr
            If tExhausted {
                Set tErrText = "Anthropic retries exhausted (HTTP " _ tStatusCode _ "): " _ tBodyStr
            }
            Do ..PopulateErrorEnvelope(.pProviderResponse, tErrText)
            Quit
        }

        ; 2xx — parse body, populate envelope. Anthropic IS canonical
        ; (FR27 passthrough); no MessageAdapter call needed.
        Do ..ParseResponse(tBodyStr, .pProviderResponse)
    }
    Catch ex {
        ; Hard exception during build/parse — structured envelope so the
        ; AgentLoop never crashes mid-turn. The Invoke template will see
        ; StopReason = "error" and emit the audit row with IsError=1.
        Do ..PopulateErrorEnvelope(.pProviderResponse, "Anthropic CallMessages exception: " _ ex.DisplayString())
    }

    ; Finally-equivalent — clear the api key.
    Set ..ApiKey = ""

    Quit tSC
}

/// <p>Build the Anthropic Messages request payload as a fresh
/// <CLASS>%DynamicObject</CLASS>. Extracted as a separate method (instead
/// of inlined in <method>CallMessages</method>) so unit tests can assert
/// the payload shape without engaging the HTTP / retry infrastructure.</p>
///
/// <p><b>Payload shape (FR27 canonical-passthrough — no translation).</b></p>
/// <pre>
/// {
///   "model": &lt;configAgent.Model&gt;,
///   "max_tokens": &lt;configAgent.MaxTokens&gt;,
///   "temperature": &lt;configAgent.Temperature&gt;,
///   "system": &lt;string OR [{type:"text", text:&lt;prompt&gt;, cache_control:{type:"ephemeral"}}]&gt;,
///   "tools": [&lt;canonical tool defs, last entry tagged with cache_control&gt;],
///   "messages": [&lt;canonical history — passthrough&gt;]
/// }
/// </pre>
///
/// <p><b>Cache plan (NFR-P6).</b> When <var>pCacheConfig</var> is an object
/// with <code>SystemEnabled = 1</code>, the <code>system</code> field is
/// emitted as the array-of-blocks form with a
/// <code>cache_control: {type:"ephemeral"}</code> marker on the single
/// text block. When <code>0</code>, the plain string form is emitted (no
/// cache marker). When <var>pCacheConfig.ToolsEnabled = 1</var>, the
/// <i>last</i> entry of <code>tools[]</code> carries
/// <code>cache_control: {type:"ephemeral"}</code> ("cache up to this
/// point" semantics per Anthropic docs); preceding entries do not.
/// <b>User messages NEVER carry <code>cache_control</code>.</b> The
/// per-turn vocabulary digest (Epic 9) sits in the user-message prefix
/// and is intentionally uncached.</p>
///
/// <p><b>NFR-S3 invariant.</b> The signature deliberately does NOT
/// include the api key; the key never enters the payload.</p>
Method BuildPayload(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As SessionAgent.Config.Agent) As %DynamicObject
{
    Set tPayload = ##class(%DynamicObject).%New()

    ; Model / max_tokens / temperature — read from config; sensible
    ; fallbacks so a misconfigured agent does not crash the build.
    Set tModel = ""
    Set tTemperature = 0
    Set tMaxTokens = 0
    If $IsObject(pConfigAgent) {
        Set tModel = pConfigAgent.Model
        Set tTemperature = pConfigAgent.Temperature
        Set tMaxTokens = pConfigAgent.MaxTokens
    }
    Do tPayload.%Set("model", tModel)
    Do tPayload.%Set("max_tokens", +tMaxTokens, "number")
    Do tPayload.%Set("temperature", +tTemperature, "number")

    ; System prompt — array-of-blocks with cache_control when SystemEnabled=1;
    ; plain string otherwise. Skip entirely if empty.
    If pSystemPrompt '= "" {
        Set tSystemEnabled = 0
        If $IsObject(pCacheConfig), pCacheConfig.%IsDefined("SystemEnabled") {
            Set tSystemEnabled = +pCacheConfig.%Get("SystemEnabled")
        }
        If tSystemEnabled = 1 {
            Set tSysArr = ##class(%DynamicArray).%New()
            Set tSysBlock = ##class(%DynamicObject).%New()
            Do tSysBlock.%Set("type", "text")
            Do tSysBlock.%Set("text", pSystemPrompt)
            Set tCC = ##class(%DynamicObject).%New()
            Do tCC.%Set("type", "ephemeral")
            Do tSysBlock.%Set("cache_control", tCC)
            Do tSysArr.%Push(tSysBlock)
            Do tPayload.%Set("system", tSysArr)
        } Else {
            Do tPayload.%Set("system", pSystemPrompt)
        }
    }

    ; Tools — canonical IS Anthropic, so passthrough; tag the last entry
    ; with cache_control when ToolsEnabled=1. Iterate by index so we can
    ; identify "last" without mutating mid-iteration (project rule
    ; §"%DynamicObject Iterator Safety").
    Set tToolsOut = ##class(%DynamicArray).%New()
    If $IsObject(pToolDefs) {
        Set tToolsEnabled = 0
        If $IsObject(pCacheConfig), pCacheConfig.%IsDefined("ToolsEnabled") {
            Set tToolsEnabled = +pCacheConfig.%Get("ToolsEnabled")
        }
        Set tToolSize = pToolDefs.%Size()
        Set tIdx = 0
        While tIdx < tToolSize {
            Set tTool = pToolDefs.%Get(tIdx)
            ; Defensive — skip non-objects (shouldn't happen with canonical
            ; tool defs, but never throw on the hot path).
            If '$IsObject(tTool) {
                Set tIdx = tIdx + 1
                Continue
            }
            ; The last tool gets the cache_control marker when enabled.
            ; Build a fresh dynamic object so we never mutate the caller's
            ; tool def.
            Set tToolCopy = ##class(%DynamicObject).%FromJSON(tTool.%ToJSON())
            If (tToolsEnabled = 1) && (tIdx = (tToolSize - 1)) {
                Set tCC = ##class(%DynamicObject).%New()
                Do tCC.%Set("type", "ephemeral")
                Do tToolCopy.%Set("cache_control", tCC)
            }
            Do tToolsOut.%Push(tToolCopy)
            Set tIdx = tIdx + 1
        }
    }
    Do tPayload.%Set("tools", tToolsOut)

    ; Messages — canonical IS Anthropic; pure passthrough. NEVER call
    ; MessageAdapter here (the doc-comment Story 2.9 OpenAIProvider invokes
    ; CanonicalToProvider; this concrete is the reason CanonicalToProvider
    ; has an explicit anthropic = passthrough switch case).
    If $IsObject(pCanonicalHistory) {
        Do tPayload.%Set("messages", pCanonicalHistory)
    } Else {
        Do tPayload.%Set("messages", ##class(%DynamicArray).%New())
    }

    Quit tPayload
}

/// <p>Issue one HTTPS POST to the Anthropic Messages endpoint.
/// Returns a <CLASS>%DynamicObject</CLASS> with
/// <code>{statusCode, bodyText, headers}</code>.</p>
///
/// <p><b>Mock-HTTP override hook.</b> Tests subclass
/// <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS> and override this
/// method to inject canned responses without engaging the network. The
/// override returns the same shape; production code is unchanged.</p>
///
/// <p><b>Settings.</b></p>
/// <ul>
/// <li><code>Https = 1</code> — HTTPS only, never plain HTTP.</li>
/// <li><code>SSLConfiguration = "DefaultSSL"</code> — operator
/// pre-requisite documented in README §Operator Prerequisites.</li>
/// <li><code>Timeout = pTimeoutSec</code> (90s, FR29).</li>
/// <li>Server / Location parsed from <var>pEndpointUrl</var>; falls back
/// to the canonical Anthropic host/path for the default URL.</li>
/// <li><code>x-api-key</code> + <code>anthropic-version</code> headers set
/// via <method>%Net.HttpRequest.SetHeader</method> by iterating the
/// <code>%List</code> from <method>GetAuthHeader</method>; plus
/// <code>Content-Type: application/json</code>.</li>
/// </ul>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeaderList As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", 0)
    Do tResp.%Set("bodyText", "")
    Do tResp.%Set("headers", ##class(%DynamicObject).%New())

    Try {
        ; Parse Server + Location from pEndpointUrl. Format:
        ;   https://<server>[:port]/<location...>
        Set tServer = ..#DEFAULTSERVER
        Set tLocation = ..#DEFAULTLOCATION
        If pEndpointUrl '= "" {
            Set tParsed = ..ParseEndpointUrl(pEndpointUrl)
            Set tServer = tParsed.%Get("server")
            Set tLocation = tParsed.%Get("location")
        }

        Set tReq = ##class(%Net.HttpRequest).%New()
        Set tReq.Https = 1
        Set tReq.SSLConfiguration = ..#SSLCONFIGURATION
        Set tReq.Timeout = pTimeoutSec
        Set tReq.Server = tServer
        Set tReq.ContentType = "application/json"

        ; Iterate the auth header list and SetHeader each name:value pair.
        Set tCount = $ListLength(pAuthHeaderList)
        Set tI = 1
        While tI <= tCount {
            Set tLine = $ListGet(pAuthHeaderList, tI)
            ; Split on the first ": " (header name : header value).
            Set tColon = $Find(tLine, ": ")
            If tColon > 0 {
                Set tHName = $Extract(tLine, 1, tColon - 3)
                Set tHValue = $Extract(tLine, tColon, *)
                Do tReq.SetHeader(tHName, tHValue)
            }
            Set tI = tI + 1
        }

        ; Write the JSON payload to EntityBody.
        Do tReq.EntityBody.Write(pPayloadJson)

        Set tPostSC = tReq.Post(tLocation)
        If $$$ISERR(tPostSC) {
            Throw ##class(%Exception.General).%New("AnthropicProvider.IssueHttpsPost",,,$System.Status.GetErrorText(tPostSC))
        }

        Set tHttpResp = tReq.HttpResponse
        Do tResp.%Set("statusCode", +tHttpResp.StatusCode)

        ; Read response body. HttpResponse.Data may be a stream or a string.
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

/// <p>Parse the Anthropic 200-response body into the canonical
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS> shape. Anthropic
/// response shape:</p>
/// <pre>
/// {
///   id, type:"message", role:"assistant", model,
///   content: [{type:"text"|"tool_use", ...}],
///   stop_reason, stop_sequence,
///   usage: {input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}
/// }
/// </pre>
///
/// <p>Per FR27 canonical-passthrough, <code>content</code> is copied
/// verbatim into <property>pProviderResponse.Content</property> — the
/// canonical block shape <code>{type, text|...}</code> matches Anthropic's
/// directly. Token counts populate the four Usage keys the abstract
/// template's audit-emit reads.</p>
ClassMethod ParseResponse(pBodyText As %String, ByRef pProviderResponse As SessionAgent.Agent.ProviderResponse) [ Internal ]
{
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }

    Set tBodyObj = ##class(%DynamicObject).%New()
    If pBodyText '= "" {
        Try {
            Set tBodyObj = ##class(%DynamicObject).%FromJSON(pBodyText)
        } Catch parseEx {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Anthropic response body not parseable JSON: " _ $Extract(pBodyText, 1, 200))
            Quit
        }
    }

    ; Content — passthrough (canonical IS Anthropic).
    Set tContent = ##class(%DynamicArray).%New()
    If tBodyObj.%IsDefined("content") {
        Set tRaw = tBodyObj.%Get("content")
        If $IsObject(tRaw) {
            Set tContent = tRaw
        }
    }
    Set pProviderResponse.Content = tContent

    ; StopReason — passthrough.
    Set pProviderResponse.StopReason = ""
    If tBodyObj.%IsDefined("stop_reason") {
        Set pProviderResponse.StopReason = tBodyObj.%Get("stop_reason")
    }

    ; Usage — copy the four Anthropic-shape keys verbatim. The abstract
    ; template's Invoke reads input_tokens / output_tokens / cache_read_input_tokens
    ; off this object; we keep snake_case for that mapping.
    Set tUsage = ##class(%DynamicObject).%New()
    Set tUsageRaw = $$$NULLOREF
    If tBodyObj.%IsDefined("usage") {
        Set tUsageRaw = tBodyObj.%Get("usage")
    }
    Do tUsage.%Set("input_tokens", ..%UsageGet(tUsageRaw, "input_tokens"))
    Do tUsage.%Set("output_tokens", ..%UsageGet(tUsageRaw, "output_tokens"))
    Do tUsage.%Set("cache_creation_input_tokens", ..%UsageGet(tUsageRaw, "cache_creation_input_tokens"))
    Do tUsage.%Set("cache_read_input_tokens", ..%UsageGet(tUsageRaw, "cache_read_input_tokens"))
    Set pProviderResponse.Usage = tUsage

    ; Model — passthrough (the abstract Invoke does not currently store
    ; this on the response; populating the Usage object is the contract.
    ; Reserved for the future ProviderResponse.Model property if added.).
    Quit
}

/// <p>Internal helper — read a numeric key off an optional Anthropic
/// <code>usage</code> object, returning <code>0</code> when the key or
/// the object is missing. Centralizes the $IsObject + %IsDefined dance
/// so <method>ParseResponse</method> stays readable.</p>
ClassMethod %UsageGet(pUsageRaw As %DynamicObject, pKey As %String) As %Integer [ Internal ]
{
    If '$IsObject(pUsageRaw) Quit 0
    If 'pUsageRaw.%IsDefined(pKey) Quit 0
    Quit +pUsageRaw.%Get(pKey)
}

/// <p>Internal — parse <var>pUrl</var> (e.g.,
/// <code>https://api.anthropic.com/v1/messages</code>) into a
/// <CLASS>%DynamicObject</CLASS> with <code>{server, location}</code>.</p>
ClassMethod ParseEndpointUrl(pUrl As %String) As %DynamicObject [ Internal ]
{
    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("server", "")
    Do tOut.%Set("location", "/")

    Set tStripped = pUrl
    If $Find(tStripped, "://") {
        Set tStripped = $Piece(tStripped, "://", 2, 99)
    }

    Set tSlashPos = $Find(tStripped, "/")
    If tSlashPos = 0 {
        Do tOut.%Set("server", tStripped)
        Do tOut.%Set("location", "/")
        Quit tOut
    }

    Do tOut.%Set("server", $Extract(tStripped, 1, tSlashPos - 2))
    Do tOut.%Set("location", $Extract(tStripped, tSlashPos - 1, *))
    Quit tOut
}

/// <p>Per-instance hook returning MaxAttempts. Defaults to <code>4</code>
/// (mirrors <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>'s class
/// parameter); test subclasses override to collapse the retry loop in
/// the unit-test fast path.</p>
Method GetMaxAttempts() As %Integer
{
    Quit 4
}

/// <p>Per-instance hook returning BaseDelaySec. Defaults to <code>1</code>;
/// test subclasses override to <code>0</code> to collapse Hang to a
/// no-op.</p>
Method GetBaseDelaySec() As %Integer
{
    Quit 1
}

/// <p>Per-instance hook returning MaxDelaySec. Defaults to <code>32</code>;
/// test subclasses override to <code>0</code> to collapse Hang to a
/// no-op.</p>
Method GetMaxDelaySec() As %Integer
{
    Quit 32
}

/// <p>Internal helper — populate pResp with the structured-error envelope
/// and zero-token usage. Same shape as
/// <method>SessionAgent.LLM.Provider.PopulateGenericError</method> but
/// scoped to the Anthropic concrete so this method can be invoked without
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
