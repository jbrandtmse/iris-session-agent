/// <p>Concrete <CLASS>SessionAgent.LLM.Provider</CLASS> implementation for
/// Google's Gemini <code>generateContent</code> API. Third cloud provider
/// after Story 2.9 <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS> and Story
/// 5.1 <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS> per architecture
/// OD4 + FR28 5th-provider extensibility.</p>
///
/// <p><b>FR27 canonical-translation (NOT passthrough).</b> Unlike Anthropic
/// (canonical IS Anthropic — passthrough), Gemini's wire shape diverges
/// materially from canonical: <code>contents</code> instead of
/// <code>messages</code>, camelCase keys, role <code>"model"</code> instead
/// of <code>"assistant"</code>, <code>parts[].functionCall</code> instead of
/// <code>content[].tool_use</code>, <code>parts[].functionResponse</code>
/// instead of <code>content[].tool_result</code>, and
/// <code>tools[].functionDeclarations[]</code> wrapping instead of a flat
/// tool-def list. <method>BuildPayload</method> therefore calls
/// <method>SessionAgent.LLM.Util.MessageAdapter.CanonicalToProvider</method>
/// + <method>SessionAgent.LLM.Util.ToolDefAdapter.CanonicalToProvider</method>
/// with the <code>"gemini"</code> dispatch value to translate canonical
/// inputs into Gemini wire shape; <method>CallMessages</method> calls
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// with <code>"gemini"</code> to translate the response back. The Story 2.8
/// adapters own both directions; this concrete is their downstream caller.</p>
///
/// <p><b>FR28 5th-provider extensibility.</b> Adding this concrete required
/// (a) one new subclass implementing the four abstract methods + (b) one
/// new dispatch entry in <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>.
/// No edits to the abstract base, no edits to the
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> /
/// <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS> dispatch tables (they
/// were already populated for <code>gemini</code> by Story 2.8), no edits to
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>, no edits to
/// <CLASS>SessionAgent.Audit.Emit</CLASS>.</p>
///
/// <p><b>FR29 90s timeout.</b> Sets <code>%Net.HttpRequest.Timeout = 90</code>
/// per call via class parameter <code>HTTPTIMEOUTSEC</code>; mirrors the
/// OpenAI / Anthropic precedent so a single regression-test pivot flips
/// all four providers (Story 5.3 added OpenAICompatProvider with the same
/// 90s parameter) if FR29 changes.</p>
///
/// <p><b>NFR-S3 never-log invariant.</b> The resolved API key is fetched
/// inside <method>CallMessages</method> via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> and stays in the
/// local stack frame plus the per-instance <property>ApiKey</property>
/// property (cleared at end). It feeds the <code>x-goog-api-key</code>
/// header (constructed by <method>GetAuthHeader</method>) and is never
/// copied into <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>, error
/// text, audit rows, or any other persisted surface. The
/// <method>BuildPayload</method> helper deliberately accepts the canonical
/// inputs only — the API key is never in its signature, so it cannot be
/// accidentally embedded in the request body.</p>
///
/// <p><b>Model in URL path (unique to Gemini).</b> Gemini is the only
/// provider where the model id is part of the URL path, not the request
/// body. <method>GetEndpointUrl</method> substitutes
/// <property>ConfigAgent.Model</property> into the
/// <code>{model}</code> placeholder of
/// <code>..#DEFAULTENDPOINTTEMPLATE</code> at runtime; the resulting URL is
/// e.g. <code>https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent</code>.</p>
///
/// <p><b>Single-header auth.</b> Gemini uses a single
/// <code>x-goog-api-key</code> header — diverges from Anthropic's two-header
/// list and OpenAI's <code>Authorization: Bearer</code>. Same abstract
/// method, different shape; <method>GetAuthHeader</method> returns a single
/// <code>name: value</code> line per the abstract doc-comment §"Concrete
/// decides whether the return value is the Authorization header value or a
/// different header name's value".</p>
///
/// <p><b>Gemini-specific retry-delay parsing.</b> Gemini does NOT emit a
/// <code>Retry-After</code> HTTP header on 429 responses; instead the JSON
/// response body carries
/// <code>error.details[].retryDelay</code> in the form <code>"45s"</code>.
/// <method>ParseGeminiRetryDelay</method> extracts the integer seconds via
/// regex, returning <code>0</code> when the field is missing — in which
/// case the inline retry loop falls back to
/// <method>SessionAgent.Util.RetryWithBackoff.ExpBackoffSec</method>'s
/// full-jitter computation. <b>Note:</b> a separate context-caching API
/// (<code>generativelanguage.googleapis.com/v1beta/cachedContents</code>)
/// is out of v1 scope — this provider does NOT engage it.
/// <var>pCacheConfig</var> is ignored by <method>BuildPayload</method>.</p>
///
/// <p><b>No prompt-caching wire fields.</b> Unlike Anthropic
/// (<code>cache_control: {type:"ephemeral"}</code> on system + last tool),
/// Gemini's <code>generateContent</code> request body has no per-call
/// caching markers. Their separate context-caching API is intentionally
/// out of v1 scope per the operator-state checklist.</p>
///
/// <p><b>Retry-wrapping design (Story 2.9 dev choice (ii) — inline).</b>
/// <method>CallMessages</method> drives an inline retry loop, calling
/// <method>IssueHttpsPost</method> directly on each attempt and using the
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS> stateless helpers
/// (<method>IsRetryable</method>, <method>ExpBackoffSec</method>) plus the
/// Gemini-specific <method>ParseGeminiRetryDelay</method> helper above.
/// Same <code>MaxAttempts=4</code> cap as OpenAI / Anthropic.</p>
///
/// <p><b>Mock-HTTP design (Story 2.9 dev choice — option C).</b> The HTTP
/// send is extracted into a separate instance method
/// <method>IssueHttpsPost</method> that takes a payload string + auth
/// header line + endpoint URL + timeout and returns a canonical response
/// object <code>{statusCode, bodyText, headers}</code>. Tests subclass
/// <CLASS>SessionAgent.LLM.GeminiProvider</CLASS> and override
/// <method>IssueHttpsPost</method> to inject canned responses without
/// touching the network or any process-private global.</p>
///
/// <p><b>Model default — Rule 10 verification.</b></p>
///
/// <p><i>Verified current as of 2026-05-06 via
/// <code>https://ai.google.dev/gemini-api/docs/pricing</code>:
/// <code>gemini-2.5-flash</code> at $0.30 / $2.50 per MTok recommended as
/// cost-effective default for tool-use agents per the page's "Flash for
/// agentic tasks requiring reasoning" guidance. Optional override
/// <code>gemini-2.5-pro</code> ($1.25-$2.50 / $10-$15) for harder
/// reasoning. Free tier available.</i></p>
///
/// <p>The default value is set in
/// <property>SessionAgent.Config.Agent.Model</property> at agent-config seed
/// time (Story 2.4 / 6.x), not in this class itself. This doc-comment cites
/// the recommended default per Rule 10 spec-time research.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 5.2</a> (line 1708) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"External Integrations → Gemini API" — wire shape; FR27/FR28/FR29
/// per <a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>.</li>
/// <li>Gemini generateContent: <code>https://ai.google.dev/api/generate-content</code>
/// + <code>https://ai.google.dev/api/rest/v1beta/models/generateContent</code>.</li>
/// <li>Gemini pricing: <code>https://ai.google.dev/gemini-api/docs/pricing</code>.</li>
/// <li><a href="../../../irislib/%25Net/HttpRequest.cls">irislib/%Net/HttpRequest.cls</a>
/// — Https/SSLConfiguration/Timeout/Server/Location/EntityBody properties;
/// Post() method; HttpResponse property.</li>
/// </ul>
Class SessionAgent.LLM.GeminiProvider Extends SessionAgent.LLM.Provider
{

/// <p>Provider name as it appears in
/// <property>SessionAgent.Config.Agent.Provider</property> and the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> Provider dimension.</p>
Parameter PROVIDERNAME = "gemini";

/// <p>Default Gemini generateContent endpoint URL template. The literal
/// <code>{model}</code> token is replaced with
/// <property>ConfigAgent.Model</property> at runtime by
/// <method>GetEndpointUrl</method>. Overridden when
/// <property>SessionAgent.Config.Agent.EndpointUrl</property> is set
/// (rare for Gemini; reserved for future Vertex AI or proxy hosts).</p>
Parameter DEFAULTENDPOINTTEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent";

/// <p>Per-call HTTP timeout, in seconds, per FR29.</p>
Parameter HTTPTIMEOUTSEC As INTEGER = 90;

/// <p>SSL configuration name. Operator pre-requisite documented in
/// README §Operator Prerequisites; reuses the same <code>DefaultSSL</code>
/// profile the OpenAI / Anthropic providers use since all three terminate
/// against TLS 1.2+ standard CAs.</p>
Parameter SSLCONFIGURATION = "DefaultSSL";

/// <p>Gemini canonical Server hostname. Used when the configured endpoint
/// URL is the canonical one.</p>
Parameter DEFAULTSERVER = "generativelanguage.googleapis.com";

/// <p>Cached Config.Agent reference. The AgentLoop sets this on the
/// provider instance immediately after construction; the concrete reads
/// it in <method>CallMessages</method> for credential resolution and
/// payload-build (model/temperature/max_tokens come from this row), and
/// in <method>GetEndpointUrl</method> for the model-in-URL substitution.</p>
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

/// <p>Concrete — return the Gemini generateContent endpoint URL with
/// the model id substituted into the <code>{model}</code> placeholder.
/// Reads from the cached <property>ConfigAgent.EndpointUrl</property>
/// when set (taken verbatim — tests / proxy operators are expected to
/// supply a fully-formed URL); otherwise substitutes
/// <property>ConfigAgent.Model</property> into
/// <code>..#DEFAULTENDPOINTTEMPLATE</code>.</p>
Method GetEndpointUrl() As %String
{
    ; Story 4.0 codification: $Char(0) is IRIS's legacy %String null sentinel
    ; for columns whose value was set to "" via SQL UPDATE; treat it as the
    ; empty string so the canonical fallback engages. Bug-1 surfaced 2026-05-06.
    Set tStored = ""
    If $IsObject(..ConfigAgent) Set tStored = ..ConfigAgent.EndpointUrl
    If tStored = $Char(0) Set tStored = ""
    If tStored '= "" Quit tStored
    Set tModel = ""
    If $IsObject(..ConfigAgent) {
        Set tModel = ..ConfigAgent.Model
    }
    Set tUrl = ..#DEFAULTENDPOINTTEMPLATE
    Set tUrl = $Replace(tUrl, "{model}", tModel)
    Quit tUrl
}

/// <p>Concrete — return the single Gemini auth header line as
/// <code>x-goog-api-key: &lt;pApiKey&gt;</code>. Diverges from the
/// AnthropicProvider's two-line $ListBuild and the OpenAIProvider's
/// Bearer-format string — same abstract method, different return shape;
/// per the abstract doc-comment §"Concrete decides whether the return
/// value is the Authorization header value or a different header name's
/// value".</p>
///
/// <p><b>NFR-S3 invariant.</b> The returned string carries the API key.
/// Callers (only <method>CallMessages</method> /
/// <method>IssueHttpsPost</method>) MUST set this directly on
/// <CLASS>%Net.HttpRequest</CLASS> via
/// <method>SetHeader</method> and never persist it.</p>
Method GetAuthHeader(pApiKey As %String) As %String
{
    Quit "x-goog-api-key: " _ pApiKey
}

/// <p>Concrete — return the canonical provider name
/// (<code>gemini</code>).</p>
Method GetProviderName() As %String
{
    Quit ..#PROVIDERNAME
}

/// <p>Concrete — issue one Gemini generateContent round-trip with inline
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
/// <li>Build the Gemini request payload via
/// <method>BuildPayload</method> (which calls MessageAdapter +
/// ToolDefAdapter for canonical → Gemini translation).</li>
/// <li>Drive the inline retry loop: call <method>IssueHttpsPost</method>
/// up to <method>GetMaxAttempts</method> times; on retryable status
/// (429 / 5xx per
/// <method>SessionAgent.Util.RetryWithBackoff.IsRetryable</method>),
/// <code>Hang</code> for
/// <code>MAX(provider hint, exp backoff)</code>; on non-retryable status
/// or exhaustion, exit the loop. <b>Provider hint sourced from the
/// 429 BODY</b> via <method>ParseGeminiRetryDelay</method>, NOT a
/// Retry-After header (Gemini does not emit one).</li>
/// <li>If the final response is non-2xx OR mid-flight, populate
/// pProviderResponse with the structured-error envelope; otherwise
/// parse the body via <method>ParseResponse</method> (which calls
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// for back-translation) and copy Content / StopReason / Usage /
/// Model into pProviderResponse.</li>
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
        ; Step 1 — resolve API key.
        Set tEnvVar = ""
        Set tCredName = ""
        If $IsObject(..ConfigAgent) {
            Set tEnvVar = ..ConfigAgent.EnvVarName
            Set tCredName = ..ConfigAgent.CredentialName
        }
        Set ..ApiKey = ##class(SessionAgent.Util.EnvSecret).Resolve(tEnvVar, tCredName)

        If ..ApiKey = "" {
            ; Credential missing — populate envelope, no retry, no network call.
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Gemini credential resolution failed")
            ; Argumentless quit per project rule §"QUIT Statement Restrictions".
            Quit
        }

        ; Step 2 — build the payload (testable in isolation).
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()
        Set tAuthHeader = ..GetAuthHeader(..ApiKey)
        Set tEndpointUrl = ..GetEndpointUrl()
        Set tTimeoutSec = ..#HTTPTIMEOUTSEC

        ; Step 3 — inline retry loop. Same shape as OpenAI / Anthropic
        ; concretes except retry-delay sourcing diverges (Gemini parses
        ; from response BODY via ParseGeminiRetryDelay).
        Set tMaxAttempts = ..GetMaxAttempts()
        Set tBaseDelaySec = ..GetBaseDelaySec()
        Set tMaxDelaySec = ..GetMaxDelaySec()
        Set tAttempt = 0
        Set tStatusCode = 0
        Set tBodyStr = ""
        Set tMidFlight = 0
        Set tExhausted = 0

        While tAttempt < tMaxAttempts {
            ; Reset the per-attempt response.
            Set tStatusCode = 0
            Set tBodyStr = ""

            Set tHttpFailed = 0
            Try {
                Set tHttpResp = ..IssueHttpsPost(tPayloadJson, tAuthHeader, tEndpointUrl, tTimeoutSec)
                Set tStatusCode = +tHttpResp.%Get("statusCode")
                Set tBodyStr = tHttpResp.%Get("bodyText")
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

            ; MAX(provider hint, exp backoff). Provider hint sourced
            ; from response BODY (Gemini-specific) — NOT a Retry-After
            ; header, which Gemini doesn't emit.
            Set tProviderDelay = ..ParseGeminiRetryDelay(tBodyStr)
            Set tExpDelay = ##class(SessionAgent.Util.RetryWithBackoff).ExpBackoffSec(tAttempt - 1, tBaseDelaySec, tMaxDelaySec)
            Set tDelay = tProviderDelay
            If tExpDelay > tDelay {
                Set tDelay = tExpDelay
            }

            Hang tDelay
        }

        ; Step 4 — classify the final state.
        If tMidFlight {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Gemini mid-flight failure (request may have been processed)")
            Quit
        }

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Set tErrText = "Gemini HTTP " _ tStatusCode _ ": " _ tBodyStr
            If tExhausted {
                Set tErrText = "Gemini retries exhausted (HTTP " _ tStatusCode _ "): " _ tBodyStr
            }
            Do ..PopulateErrorEnvelope(.pProviderResponse, tErrText)
            Quit
        }

        ; 2xx — parse body, translate to canonical, populate envelope.
        Do ..ParseResponse(tBodyStr, .pProviderResponse)
    }
    Catch ex {
        ; Hard exception during build/translate — structured envelope so
        ; the AgentLoop never crashes mid-turn. The Invoke template will
        ; see StopReason = "error" and emit the audit row with IsError=1.
        Do ..PopulateErrorEnvelope(.pProviderResponse, "Gemini CallMessages exception: " _ ex.DisplayString())
    }

    ; Finally-equivalent — clear the api key.
    Set ..ApiKey = ""

    Quit tSC
}

/// <p>Build the Gemini generateContent request payload as a fresh
/// <CLASS>%DynamicObject</CLASS>. Extracted as a separate method (instead
/// of inlined in <method>CallMessages</method>) so unit tests can assert
/// the payload shape without engaging the HTTP / retry infrastructure.</p>
///
/// <p><b>Payload shape (FR27 canonical-translation via MessageAdapter +
/// ToolDefAdapter).</b></p>
/// <pre>
/// {
///   "contents": [&lt;canonical history → gemini parts/role shape&gt;],
///   "tools": [{"functionDeclarations": [&lt;tool defs&gt;]}],
///   "systemInstruction": {"parts": [{"text": &lt;pSystemPrompt&gt;}]},
///   "generationConfig": {
///     "maxOutputTokens": &lt;configAgent.MaxTokens&gt;,
///     "temperature": &lt;configAgent.Temperature&gt;
///   }
/// }
/// </pre>
///
/// <p><b>No model field in body.</b> Gemini puts the model id in the URL
/// path (see <method>GetEndpointUrl</method>); the request body has no
/// <code>model</code> key.</p>
///
/// <p><b>No prompt-caching wire fields.</b> Gemini's separate
/// context-caching API is out of v1 scope; <var>pCacheConfig</var> would
/// be ignored even if passed (the AgentLoop omits it for non-anthropic
/// providers per Story 5.1's decision).</p>
///
/// <p><b>NFR-S3 invariant.</b> The signature deliberately does NOT
/// include the api key; the key never enters the payload.</p>
Method BuildPayload(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pConfigAgent As SessionAgent.Config.Agent) As %DynamicObject
{
    Set tPayload = ##class(%DynamicObject).%New()

    ; contents — translate canonical → Gemini via MessageAdapter (Story 2.8).
    Set tContents = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider(..#PROVIDERNAME, pCanonicalHistory)
    Do tPayload.%Set("contents", tContents)

    ; tools — translate canonical → Gemini via ToolDefAdapter (Story 2.8).
    ; The output is a one-element array carrying a single
    ; {functionDeclarations:[...]} wrapper object per the Gemini
    ; tool-spec invariant.
    Set tTools = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider(..#PROVIDERNAME, pToolDefs)
    Do tPayload.%Set("tools", tTools)

    ; systemInstruction — only when pSystemPrompt non-empty. Gemini's
    ; systemInstruction shape is {parts:[{text:<prompt>}]}.
    If pSystemPrompt '= "" {
        Set tSysInstr = ##class(%DynamicObject).%New()
        Set tSysParts = ##class(%DynamicArray).%New()
        Set tSysPart = ##class(%DynamicObject).%New()
        Do tSysPart.%Set("text", pSystemPrompt)
        Do tSysParts.%Push(tSysPart)
        Do tSysInstr.%Set("parts", tSysParts)
        Do tPayload.%Set("systemInstruction", tSysInstr)
    }

    ; generationConfig — maxOutputTokens + temperature read from config.
    Set tGenCfg = ##class(%DynamicObject).%New()
    Set tTemperature = 0
    Set tMaxTokens = 0
    If $IsObject(pConfigAgent) {
        Set tTemperature = pConfigAgent.Temperature
        Set tMaxTokens = pConfigAgent.MaxTokens
    }
    Do tGenCfg.%Set("maxOutputTokens", +tMaxTokens, "number")
    Do tGenCfg.%Set("temperature", +tTemperature, "number")
    Do tPayload.%Set("generationConfig", tGenCfg)

    Quit tPayload
}

/// <p>Issue one HTTPS POST to the Gemini generateContent endpoint.
/// Returns a <CLASS>%DynamicObject</CLASS> with
/// <code>{statusCode, bodyText, headers}</code>.</p>
///
/// <p><b>Mock-HTTP override hook.</b> Tests subclass
/// <CLASS>SessionAgent.LLM.GeminiProvider</CLASS> and override this method
/// to inject canned responses without engaging the network. The override
/// returns the same shape; production code is unchanged.</p>
///
/// <p><b>Settings.</b></p>
/// <ul>
/// <li><code>Https = 1</code> — HTTPS only, never plain HTTP.</li>
/// <li><code>SSLConfiguration = "DefaultSSL"</code> — operator
/// pre-requisite documented in README §Operator Prerequisites.</li>
/// <li><code>Timeout = pTimeoutSec</code> (90s, FR29).</li>
/// <li>Server / Location parsed from <var>pEndpointUrl</var>; falls back
/// to the canonical Gemini host for the default URL template after
/// <code>{model}</code> substitution.</li>
/// <li><code>x-goog-api-key</code> header set via
/// <method>%Net.HttpRequest.SetHeader</method> from
/// <var>pAuthHeader</var>; plus <code>Content-Type: application/json</code>.</li>
/// </ul>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", 0)
    Do tResp.%Set("bodyText", "")
    Do tResp.%Set("headers", ##class(%DynamicObject).%New())

    Try {
        ; Parse Server + Location + Port + Https from pEndpointUrl (always
        ; non-empty — GetEndpointUrl substitutes the model into the
        ; template). Story 5.3 centralized parser on the abstract base.
        Set tServer = ..#DEFAULTSERVER
        Set tLocation = "/"
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

        ; Split pAuthHeader on the first ": " (header name : header value).
        Set tColon = $Find(pAuthHeader, ": ")
        If tColon > 0 {
            Set tHName = $Extract(pAuthHeader, 1, tColon - 3)
            Set tHValue = $Extract(pAuthHeader, tColon, *)
            Do tReq.SetHeader(tHName, tHValue)
        }

        ; Write the JSON payload to EntityBody.
        Do tReq.EntityBody.Write(pPayloadJson)

        Set tPostSC = tReq.Post(tLocation)
        If $$$ISERR(tPostSC) {
            Throw ##class(%Exception.General).%New("GeminiProvider.IssueHttpsPost",,,$System.Status.GetErrorText(tPostSC))
        }

        Set tHttpResp = tReq.HttpResponse
        Do tResp.%Set("statusCode", +tHttpResp.StatusCode)

        ; Read response body.
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

        ; Gemini does NOT emit Retry-After; the retry-delay info is in
        ; the 429 body. So no header surfacing here — the retry loop
        ; calls ParseGeminiRetryDelay(bodyText) directly.
    }
    Catch ex {
        ; HTTP failure -- bubble up to the inline retry loop in
        ; CallMessages, which classifies the throw as mid-flight.
        Throw ex
    }

    Quit tResp
}

/// <p>Parse the Gemini 200-response body into the canonical
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS> shape via
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// (with <code>"gemini"</code> dispatch). Gemini response shape:</p>
/// <pre>
/// {
///   candidates: [{
///     content: {role:"model", parts:[{text|functionCall, ...}]},
///     finishReason, safetyRatings
///   }],
///   usageMetadata: {promptTokenCount, candidatesTokenCount, totalTokenCount},
///   modelVersion
/// }
/// </pre>
///
/// <p>The MessageAdapter back-translation maps <code>parts[].text</code>
/// → <code>{type:"text",text}</code>; <code>parts[].functionCall</code> →
/// <code>{type:"tool_use", id:"gemini-call-N", name, input:args}</code>;
/// <code>finishReason</code> → canonical <code>stopReason</code>;
/// <code>usageMetadata.promptTokenCount</code> →
/// <code>usage.input_tokens</code>;
/// <code>usageMetadata.candidatesTokenCount</code> →
/// <code>usage.output_tokens</code>. Cache-token keys are zeroed (Gemini's
/// context-caching API is out of v1 scope).</p>
Method ParseResponse(pBodyText As %String, ByRef pProviderResponse As SessionAgent.Agent.ProviderResponse) [ Internal ]
{
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }

    Set tBodyObj = ##class(%DynamicObject).%New()
    If pBodyText '= "" {
        Try {
            Set tBodyObj = ##class(%DynamicObject).%FromJSON(pBodyText)
        } Catch parseEx {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "Gemini response body not parseable JSON: " _ $Extract(pBodyText, 1, 200))
            Quit
        }
    }

    ; Translate Gemini → canonical via the MessageAdapter back-translation.
    Set tCanon = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical(..#PROVIDERNAME, tBodyObj)

    Set pProviderResponse.Content = tCanon.%Get("content")
    Set pProviderResponse.StopReason = tCanon.%Get("stopReason")

    ; Usage — MessageAdapter populates the four canonical keys; cache_*
    ; come back as 0 (Gemini context-caching out of v1 scope).
    Set pProviderResponse.Usage = tCanon.%Get("usage")
    Quit
}

/// <p>Translate Gemini's <code>finishReason</code> string to the canonical
/// <code>stopReason</code> nomenclature. STOP→end_turn,
/// MAX_TOKENS→max_tokens, SAFETY→stop_sequence (and RECITATION+OTHER per
/// the same conservative mapping), TOOL_CALLS→tool_use; unknown values
/// pass through. Mirrors
/// <method>SessionAgent.LLM.Util.MessageAdapter.MapGeminiFinishReason</method>
/// — the same logic, exposed as a public class method here so unit tests
/// can assert mappings without round-tripping through the response
/// adapter.</p>
ClassMethod TranslateFinishReason(pGeminiReason As %String) As %String
{
    If pGeminiReason = "STOP" Quit "end_turn"
    If pGeminiReason = "MAX_TOKENS" Quit "max_tokens"
    If pGeminiReason = "SAFETY" Quit "stop_sequence"
    If pGeminiReason = "RECITATION" Quit "stop_sequence"
    If pGeminiReason = "OTHER" Quit "stop_sequence"
    If pGeminiReason = "TOOL_CALLS" Quit "tool_use"
    Quit pGeminiReason
}

/// <p>Parse Gemini's 429 response body for
/// <code>error.details[].retryDelay</code> (e.g., <code>"45s"</code>) and
/// return the integer seconds. Returns <code>0</code> when the field is
/// missing, the body is unparseable JSON, or the body is empty — in
/// which case the inline retry loop falls back to
/// <method>SessionAgent.Util.RetryWithBackoff.ExpBackoffSec</method>'s
/// full-jitter computation.</p>
///
/// <p><b>Format.</b> Gemini's protobuf-style duration string is the digits
/// followed by an <code>"s"</code>. The simple regex <code>(\d+)s</code>
/// handles the common form. The richer <code>"2m30s"</code> form is rare
/// for retryDelay values (Google's quota-exceeded delays are typically
/// single-unit seconds); when seen, the regex captures the leading integer
/// (the minutes), which is a conservative under-estimate that the
/// exp-backoff fallback caps at <code>tMaxDelaySec</code>.</p>
ClassMethod ParseGeminiRetryDelay(pResponseBody As %String) As %Integer
{
    Set tResult = 0
    If pResponseBody = "" Quit tResult

    Set tBody = ""
    Set tParseFailed = 0
    Try {
        Set tBody = ##class(%DynamicObject).%FromJSON(pResponseBody)
    } Catch parseEx {
        Set tParseFailed = 1
    }
    If tParseFailed Quit tResult

    If '$IsObject(tBody) Quit tResult
    If 'tBody.%IsDefined("error") Quit tResult

    Set tErr = tBody.%Get("error")
    If '$IsObject(tErr) Quit tResult
    If 'tErr.%IsDefined("details") Quit tResult

    Set tDetails = tErr.%Get("details")
    If '$IsObject(tDetails) Quit tResult

    Set tIter = tDetails.%GetIterator()
    Set tFound = ""
    While tIter.%GetNext(.tIdx, .tDetail) {
        If '$IsObject(tDetail) Continue
        If 'tDetail.%IsDefined("retryDelay") Continue
        Set tFound = tDetail.%Get("retryDelay")
        Quit ; argumentless — exits inner While
    }

    If tFound = "" Quit tResult

    ; Extract leading digits — protobuf duration strings have the
    ; numeric value followed by a unit suffix.
    Set tDigits = ""
    Set tI = 1
    While tI <= $Length(tFound) {
        Set tCh = $Extract(tFound, tI)
        If (tCh < "0") || (tCh > "9") Quit ; argumentless — exits inner While
        Set tDigits = tDigits _ tCh
        Set tI = tI + 1
    }
    If tDigits = "" Quit tResult
    Set tResult = +tDigits
    Quit tResult
}

/// <p>Per-instance hook returning MaxAttempts. Defaults to <code>4</code>
/// (mirrors the OpenAI / Anthropic precedent); test subclasses override
/// to collapse the retry loop in the unit-test fast path.</p>
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
/// scoped to the Gemini concrete so this method can be invoked without
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
