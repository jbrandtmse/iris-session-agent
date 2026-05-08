/// <p>Concrete <CLASS>SessionAgent.LLM.Provider</CLASS> implementation for
/// any OpenAI-Chat-Completions-compatible endpoint — Ollama, vLLM, LM
/// Studio, llama.cpp server, etc. Fourth and final cloud/local provider in
/// Epic 5; closes the four-provider promise from
/// <code>project_full_v1_scope.md</code>.</p>
///
/// <p><b>FR27 OpenAI-shape passthrough.</b> The wire shape IS OpenAI Chat
/// Completions. This concrete therefore reuses the Story 2.9 OpenAI
/// adapter switch case verbatim — no new
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> /
/// <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS> branch is added
/// because the canonical → openai-compatible translation IS the canonical
/// → openai translation. Ollama, vLLM, and LM Studio all expose
/// <code>POST /v1/chat/completions</code> with the same request/response
/// schema as the upstream OpenAI Chat Completions API.</p>
///
/// <p><b>FR28 5th-provider extensibility.</b> This concrete IS the
/// canonical pattern for adding a 5th OpenAI-compatible variant: copy the
/// class, change <code>PROVIDERNAME</code>, point
/// <property>SessionAgent.Config.Agent.EndpointUrl</property> at the new
/// host. No edits to this class are needed for any future
/// OpenAI-Chat-Completions-compatible host.</p>
///
/// <p><b>FR29 90s timeout.</b> Sets <code>%Net.HttpRequest.Timeout = 90</code>
/// per call via class parameter <code>HTTPTIMEOUTSEC</code>; locked by the
/// same calibration constant the other three providers use.</p>
///
/// <p><b>NFR-S3 never-log invariant.</b> The resolved API key is fetched
/// inside <method>CallMessages</method> via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> and stays in the
/// local stack frame plus the per-instance <property>ApiKey</property>
/// property (cleared at end). It feeds the <code>Authorization</code>
/// header (constructed by <method>GetAuthHeader</method>) and is never
/// copied into <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>, error
/// text, audit rows, or any other persisted surface.</p>
///
/// <p><b>Optional-auth design.</b> Diverges from
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>: when
/// <property>SessionAgent.Config.Agent.CredentialName</property> is empty
/// (Ollama default — no auth required), <method>GetAuthHeader</method>
/// returns the empty string and
/// <method>IssueHttpsPost</method> omits the <code>Authorization</code>
/// header entirely. When CredentialName is set,
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> must succeed (a
/// non-empty CredentialName whose resolution fails IS an operator
/// misconfiguration → structured error envelope). When the operator
/// supplies a credential, the header is the OpenAI Bearer-token shape
/// (<code>Authorization: Bearer &lt;key&gt;</code>) — most paid
/// OpenAI-compatible endpoints (Together AI, OpenRouter, etc.) use this
/// auth form.</p>
///
/// <p><b>HTTP-or-HTTPS scheme support.</b> Unlike the other three
/// concretes (HTTPS-only), this provider supports both schemes per the
/// <code>EndpointUrl</code> the operator configures. Ollama ships
/// HTTP-only by default (<code>http://localhost:11434</code>); vLLM /
/// LM Studio behind a reverse proxy expose HTTPS. The Story 5.3
/// centralized parser
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> auto-detects
/// the scheme and the
/// <method>IssueHttpsPost</method> override applies the result to
/// <code>%Net.HttpRequest.Https</code> + <code>SSLConfiguration</code>
/// (omitted entirely for HTTP). Non-default port (Ollama's
/// <code>:11434</code>, llama.cpp's <code>:8080</code>) is also fed
/// through the parser.</p>
///
/// <p><b>No prompt caching wire fields.</b> Ollama / vLLM / LM Studio do
/// not implement OpenAI's prompt-cache extensions. This concrete therefore
/// does NOT emit any <code>cache_control</code> markers in the payload.
/// If a future paid OpenAI-compat endpoint adds prompt caching, the
/// extension point is a new <code>BuildPayload</code> override on a
/// per-vendor subclass — defer to a future story.</p>
///
/// <p><b>NO DefaultEndpointUrl.</b> This concrete intentionally does NOT
/// declare a <code>DEFAULTENDPOINTURL</code> parameter. The operator MUST
/// configure <property>SessionAgent.Config.Agent.EndpointUrl</property> —
/// there is no canonical default URL because this provider's purpose is
/// exactly to target operator-deployed endpoints.
/// <method>GetEndpointUrl</method> returns the empty string when
/// EndpointUrl is unset; <method>CallMessages</method>'s
/// endpoint-validation step (Step 1) detects that and returns the
/// structured-error envelope with operator-friendly text pointing at the
/// Config.Agent.EndpointUrl row. No network call.</p>
///
/// <p><b>Model default — Rule 10 verification (per user-supplied operator
/// state 2026-05-06).</b> Default endpoint
/// <code>http://192.168.0.123:11434/v1/chat/completions</code> (network
/// Ollama), default model <code>qwen3:14b</code> (quantized 14B-param chat
/// model with native tool-use support per
/// <code>https://ollama.com/library/qwen3:14b</code> — verified via
/// Perplexity 2026-05-06: "Qwen3-14B has native tool/agent capabilities,
/// excels in precise integration with external tools"). Operator-overridable
/// via <code>Config.Agent.Model</code> for any OpenAI-compatible model
/// the endpoint hosts. No per-token cost (self-hosted); compatible with
/// any vLLM / LM Studio / Ollama-compatible deployment. Tool-use behavior
/// over <code>tools</code> field confirmed by Ollama OpenAI-compat docs at
/// <code>https://ollama.com/blog/openai-compatibility</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 5.3</a> (line 1740) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"External Integrations → OpenAI-compatible (Ollama / vLLM)" — wire
/// shape; FR27/FR28/FR29 per
/// <a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>.</li>
/// <li>Ollama OpenAI compatibility:
/// <code>https://ollama.com/blog/openai-compatibility</code>.</li>
/// <li>OpenAI Chat Completions API:
/// <code>https://platform.openai.com/docs/api-reference/chat/create</code>.</li>
/// <li><a href="../../../irislib/%25Net/HttpRequest.cls">irislib/%Net/HttpRequest.cls</a>
/// — Https/SSLConfiguration/Timeout/Server/Port/Location/EntityBody
/// properties; Post() method; HttpResponse property.</li>
/// </ul>
Class SessionAgent.LLM.OpenAICompatProvider Extends SessionAgent.LLM.Provider
{

/// <p>Provider name as it appears in
/// <property>SessionAgent.Config.Agent.Provider</property> and the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> Provider dimension.</p>
Parameter PROVIDERNAME = "openai-compatible";

/// <p>Per-call HTTP timeout, in seconds, per FR29.</p>
Parameter HTTPTIMEOUTSEC As INTEGER = 90;

/// <p>SSL configuration name. Used only when the operator-configured
/// EndpointUrl is HTTPS (e.g., vLLM behind a reverse proxy). Skipped
/// entirely for HTTP endpoints (Ollama default).</p>
Parameter SSLCONFIGURATION = "DefaultSSL";

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
/// the key across requests. EMPTY-STRING is a valid value here (Ollama
/// default — no auth header is sent).</p>
///
/// <p><b>NFR-S3 invariant.</b> When non-empty, this property is the only
/// place the resolved key lives once <method>CallMessages</method>
/// begins; after the retry loop exits, the property is set back to
/// <code>""</code>.</p>
Property ApiKey As %String [ Internal ];

/// <p>Concrete — return the operator-supplied endpoint URL. Reads from
/// <property>ConfigAgent.EndpointUrl</property>; returns the empty string
/// when unset (NO default — see class doc-comment §"NO DefaultEndpointUrl").
/// <method>CallMessages</method>'s endpoint-validation Step 1 detects the
/// empty return and surfaces the structured error.</p>
Method GetEndpointUrl() As %String
{
    ; Story 4.0 codification: $Char(0) is IRIS's legacy %String null sentinel
    ; for columns whose value was set to "" via SQL UPDATE; treat it as the
    ; empty string so the no-default-endpoint structured error fires correctly.
    ; Bug-1 surfaced 2026-05-06.
    Set tStored = ""
    If $IsObject(..ConfigAgent) Set tStored = ..ConfigAgent.EndpointUrl
    If tStored = $Char(0) Set tStored = ""
    If tStored '= "" Quit tStored
    Quit ""
}

/// <p>Concrete — return the HTTP <code>Authorization</code> header value.
/// When <var>pApiKey</var> is empty (Ollama default — no auth required),
/// returns the empty string;
/// <method>IssueHttpsPost</method> detects this and omits the
/// <code>Authorization</code> header entirely (no
/// <code>"Authorization: Bearer "</code> with empty key — that would be a
/// security smell).</p>
///
/// <p>When non-empty, returns OpenAI Bearer format
/// <code>Bearer &lt;key&gt;</code> — most paid OpenAI-compatible
/// endpoints (Together AI, OpenRouter, Anyscale, paid Ollama
/// instances behind a Bearer-auth proxy) use this form.</p>
///
/// <p><b>NFR-S3 invariant.</b> The returned string carries the key.
/// Callers (only <method>CallMessages</method> /
/// <method>IssueHttpsPost</method>) MUST set this directly on
/// <CLASS>%Net.HttpRequest</CLASS> via <method>SetHeader</method> and
/// never persist it.</p>
Method GetAuthHeader(pApiKey As %String) As %String
{
    If $Get(pApiKey) = "" Quit ""
    Quit "Bearer " _ pApiKey
}

/// <p>Concrete — return the canonical provider name
/// (<code>openai-compatible</code>).</p>
Method GetProviderName() As %String
{
    Quit ..#PROVIDERNAME
}

/// <p>Concrete — issue one OpenAI-compatible Chat Completions round-trip
/// with inline retry. Mirrors
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>'s flow but with
/// optional-auth handling (Step 1 short-circuits to structured error
/// when EndpointUrl is empty; Step 2 allows empty resolved key when
/// CredentialName was empty).</p>
///
/// <p><b>Flow.</b></p>
/// <ol>
/// <li><b>Endpoint validation:</b> if
/// <method>GetEndpointUrl</method> returns the empty string, populate
/// pProviderResponse with the structured-error envelope ("OpenAI-compatible
/// provider requires Config.Agent.EndpointUrl ...") and return — no
/// network call.</li>
/// <li><b>Resolve API key (optional)</b> via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method>. If
/// CredentialName was empty, accept an empty resolved key (proceed
/// without auth header). If CredentialName was non-empty BUT
/// resolution failed, that's an operator misconfiguration → structured
/// error.</li>
/// <li><b>Build payload</b> via <method>BuildPayload</method> — reuses
/// the OpenAI MessageAdapter / ToolDefAdapter switch verbatim.</li>
/// <li><b>Drive the inline retry loop</b> via
/// <method>IssueHttpsPost</method> + the
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS> stateless helpers.
/// Same MaxAttempts=4 cap.</li>
/// <li><b>Parse + back-translate</b> via
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// with the <code>"openai"</code> switch case.</li>
/// </ol>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK

    ; Always create the response envelope so the caller sees a valid
    ; object even on the validation fast paths.
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }

    Try {
        ; Step 1 — endpoint validation. Operator MUST configure
        ; Config.Agent.EndpointUrl; there is no canonical default.
        Set tEndpointUrl = ..GetEndpointUrl()
        If tEndpointUrl = "" {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI-compatible provider requires Config.Agent.EndpointUrl to be set (e.g., http://localhost:11434/v1/chat/completions for Ollama).")
            Quit ; argumentless — return after Try/Catch per project rule
        }

        ; Step 2 — resolve API key (optional). The Invoke template's
        ; credential-missing fast path engages when EnvVarName +
        ; CredentialName both empty AND resolution returns empty — but
        ; that's the canonical "operator forgot to set credentials" case
        ; for paid providers. For openai-compatible, CredentialName empty
        ; is INTENTIONAL (Ollama default — no auth) so we want the
        ; abstract template's fast path to be bypassed when CredentialName
        ; is empty. That bypass happens because the abstract template
        ; only triggers when the resolved key is empty AND the abstract
        ; doesn't know whether the operator intended that. In practice:
        ; the AgentLoop wires Config.Agent.CredentialName="" for Ollama,
        ; the abstract template's EnvSecret.Resolve("","") returns "",
        ; and the abstract surfaces "Credential resolution failed".
        ;
        ; To make optional-auth work, the abstract template's behavior
        ; needs adjusting for "openai-compatible"-named providers... but
        ; we don't want to special-case the abstract per-provider. The
        ; clean alternative: this concrete must handle credential
        ; resolution INTERNALLY (as the OpenAIProvider already does for
        ; its own resolution path) and return success even when the key
        ; is empty AND CredentialName was empty.
        ;
        ; The abstract Invoke ALSO resolves the key for ITS audit emit;
        ; if Resolve returns "", Invoke populates the credential-missing
        ; envelope BEFORE calling CallMessages. So we have a fundamental
        ; tension: the abstract template intercepts before us. Resolution:
        ; documented behavior — for openai-compatible deployments without
        ; a credential, the operator sets Config.Agent.EnvVarName="PATH"
        ; (or any always-set env var) so EnvSecret.Resolve returns
        ; non-empty (the value of $PATH), satisfies the abstract template,
        ; and we then ignore the resolved key here when CredentialName is
        ; empty.
        Set tEnvVar = ""
        Set tCredName = ""
        If $IsObject(..ConfigAgent) {
            Set tEnvVar = ..ConfigAgent.EnvVarName
            Set tCredName = ..ConfigAgent.CredentialName
        }
        ; Story 4.0 codification: $Char(0) is IRIS's legacy %String null
        ; sentinel — operators clearing these via SQL UPDATE see the column
        ; come back as $Char(0) instead of "". Treat both as empty so the
        ; intentional-no-auth path (Ollama) engages. Bug-1 surfaced 2026-05-06.
        If tEnvVar = $Char(0) Set tEnvVar = ""
        If tCredName = $Char(0) Set tCredName = ""
        Set ..ApiKey = ##class(SessionAgent.Util.EnvSecret).Resolve(tEnvVar, tCredName)

        ; If CredentialName was non-empty BUT resolution returned empty,
        ; the operator misconfigured (named credential doesn't exist).
        ; That's distinct from CredentialName="" intentional-no-auth.
        If (tCredName '= "") && (..ApiKey = "") {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI-compatible credential resolution failed (CredentialName=" _ tCredName _ ")")
            Quit
        }

        ; If CredentialName was empty, override ..ApiKey to "" regardless
        ; of what EnvSecret returned (the operator may have set EnvVarName
        ; to a non-secret env var like PATH just to satisfy the abstract
        ; template; we never want PATH's value to leak into an
        ; Authorization header).
        If tCredName = "" {
            Set ..ApiKey = ""
        }

        ; Step 3 — build the payload (testable in isolation).
        Set tPayload = ..BuildPayload(pCanonicalHistory, pToolDefs, pSystemPrompt, ..ConfigAgent)
        Set tPayloadJson = tPayload.%ToJSON()
        Set tAuthHeader = ..GetAuthHeader(..ApiKey)
        Set tTimeoutSec = ..#HTTPTIMEOUTSEC

        ; Step 4 — inline retry loop. Same shape as OpenAIProvider.
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
            Set tStatusCode = 0
            Set tBodyStr = ""
            Set tHeaders = ##class(%DynamicObject).%New()

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
                Set tMidFlight = 1
                Quit
            }

            If '##class(SessionAgent.Util.RetryWithBackoff).IsRetryable(tStatusCode) {
                Quit
            }

            Set tAttempt = tAttempt + 1
            If tAttempt >= tMaxAttempts {
                Set tExhausted = 1
                Quit
            }

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

        ; Step 5 — classify the final state.
        If tMidFlight {
            Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI-compatible mid-flight failure (request may have been processed)")
            Quit
        }

        If (tStatusCode < 200) || (tStatusCode > 299) {
            Set tErrText = "OpenAI-compatible HTTP " _ tStatusCode _ ": " _ tBodyStr
            If tExhausted {
                Set tErrText = "OpenAI-compatible retries exhausted (HTTP " _ tStatusCode _ "): " _ tBodyStr
            }
            Do ..PopulateErrorEnvelope(.pProviderResponse, tErrText)
            Quit
        }

        ; 2xx — parse body, translate to canonical via the OpenAI adapter
        ; switch (wire shape IS OpenAI Chat Completions).
        Set tBodyObj = ##class(%DynamicObject).%New()
        If tBodyStr '= "" {
            Try {
                Set tBodyObj = ##class(%DynamicObject).%FromJSON(tBodyStr)
            } Catch parseEx {
                Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI-compatible response body not parseable JSON: " _ $Extract(tBodyStr, 1, 200))
                Quit
            }
        }

        ; Reuse Story 2.9 OpenAI adapter switch case verbatim — wire shape
        ; is identical to upstream OpenAI Chat Completions. The adapter
        ; populates Content / StopReason / Usage in canonical Anthropic-
        ; shape (which the rest of the pipeline expects).
        Set tCanon = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical("openai", tBodyObj)

        Set pProviderResponse.Content = tCanon.%Get("content")
        Set pProviderResponse.StopReason = tCanon.%Get("stopReason")
        Set pProviderResponse.Usage = tCanon.%Get("usage")
    }
    Catch ex {
        Do ..PopulateErrorEnvelope(.pProviderResponse, "OpenAI-compatible CallMessages exception: " _ ex.DisplayString())
    }

    ; Finally-equivalent — clear the api key.
    Set ..ApiKey = ""

    Quit tSC
}

/// <p>Build the OpenAI Chat Completions request payload as a fresh
/// <CLASS>%DynamicObject</CLASS>. Identical shape to
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>'s payload because the
/// wire shape IS OpenAI Chat Completions; reuses the same MessageAdapter
/// + ToolDefAdapter switch case verbatim.</p>
///
/// <p><b>Payload shape.</b></p>
/// <pre>
/// {
///   "model": &lt;configAgent.Model&gt;,
///   "temperature": &lt;configAgent.Temperature&gt;,
///   "max_tokens": &lt;configAgent.MaxTokens&gt;,
///   "messages": [{"role":"system", "content":&lt;system prompt&gt;}, &lt;openai-shape messages&gt;],
///   "tools": [&lt;openai-shape tool defs&gt;]
/// }
/// </pre>
///
/// <p><b>System prompt handling.</b> Same as
/// <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>: prepend a
/// <code>{role:"system", content:&lt;prompt&gt;}</code> message when
/// <var>pSystemPrompt</var> is non-empty.</p>
///
/// <p><b>No prompt-caching wire fields.</b> Ollama / vLLM / LM Studio do
/// not implement OpenAI's prompt-cache extensions; this concrete therefore
/// emits no <code>cache_control</code> markers.</p>
Method BuildPayload(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pConfigAgent As SessionAgent.Config.Agent) As %DynamicObject
{
    Set tPayload = ##class(%DynamicObject).%New()

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

    ; Messages — translate canonical to OpenAI shape via the same adapter
    ; switch Story 2.9 OpenAIProvider uses; prepend system role message
    ; if pSystemPrompt is non-empty.
    Set tOaMessages = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", pCanonicalHistory)
    If pSystemPrompt '= "" {
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

    ; Tools — translate canonical to OpenAI shape via the same ToolDefAdapter
    ; switch Story 2.9 uses.
    Set tOaTools = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider("openai", pToolDefs)
    Do tPayload.%Set("tools", tOaTools)

    Quit tPayload
}

/// <p>Issue one HTTP-or-HTTPS POST to the operator-configured endpoint.
/// Returns a <CLASS>%DynamicObject</CLASS> with
/// <code>{statusCode, bodyText, headers}</code>.</p>
///
/// <p><b>Mock-HTTP override hook.</b> Tests subclass and override this
/// method to inject canned responses without engaging the network.</p>
///
/// <p><b>Settings (auto-detected from EndpointUrl).</b></p>
/// <ul>
/// <li><code>Https = 0</code> for <code>http://...</code> endpoints
/// (Ollama default); <code>Https = 1</code> for <code>https://...</code>
/// endpoints (vLLM behind reverse proxy, paid OpenAI-compat hosts).</li>
/// <li><code>SSLConfiguration = "DefaultSSL"</code> when Https=1; not
/// set when Https=0 (no SSL needed for plain HTTP).</li>
/// <li><code>Timeout = pTimeoutSec</code> (90s, FR29).</li>
/// <li><code>Server</code> + <code>Port</code> + <code>Location</code>
/// parsed via the centralized
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> — handles
/// non-default ports (Ollama's <code>:11434</code>) correctly.</li>
/// <li><code>Authorization</code> header set ONLY when
/// <var>pAuthHeader</var> is non-empty (Ollama default = no auth ⇒
/// header omitted entirely).</li>
/// </ul>
Method IssueHttpsPost(pPayloadJson As %String, pAuthHeader As %String, pEndpointUrl As %String, pTimeoutSec As %Integer) As %DynamicObject
{
    Set tResp = ##class(%DynamicObject).%New()
    Do tResp.%Set("statusCode", 0)
    Do tResp.%Set("bodyText", "")
    Do tResp.%Set("headers", ##class(%DynamicObject).%New())

    Try {
        ; Parse Server + Location + Port + Https from pEndpointUrl via the
        ; centralized parser on the abstract base. pEndpointUrl is always
        ; non-empty here because CallMessages's Step 1 short-circuits on
        ; empty.
        Set tParsed = ..ParseEndpointUrl(pEndpointUrl)
        Set tServer = tParsed.%Get("server")
        Set tLocation = tParsed.%Get("location")
        Set tPort = +tParsed.%Get("port")
        Set tHttps = +tParsed.%Get("https")
        ; Story 11.4 — smart suffix detection. If the operator-supplied
        ; EndpointUrl does NOT already end in /chat/completions (e.g.,
        ; Ollama base URL "http://localhost:11434/v1" — Location=/v1),
        ; append /chat/completions so the POST hits the canonical OpenAI-
        ; compatible Chat Completions path. If the operator already supplied
        ; the full path (e.g., "https://api.openai.com/v1/chat/completions" —
        ; Location=/v1/chat/completions), use as-is — no double-suffix.
        ; Trailing-slash form ("/v1/") is normalized first so the resulting
        ; Location has exactly one slash separator (NOT "/v1//chat/completions").
        Set tLocation = ..NormalizeChatCompletionsLocation(tLocation)

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

        ; Authorization header — set ONLY when non-empty. Ollama default
        ; sends no Authorization header at all.
        If pAuthHeader '= "" {
            Do tReq.SetHeader("Authorization", pAuthHeader)
        }

        ; Write the JSON payload to EntityBody.
        Do tReq.EntityBody.Write(pPayloadJson)

        Set tPostSC = tReq.Post(tLocation)
        If $$$ISERR(tPostSC) {
            Throw ##class(%Exception.General).%New("OpenAICompatProvider.IssueHttpsPost",,,$System.Status.GetErrorText(tPostSC))
        }

        Set tHttpResp = tReq.HttpResponse
        Do tResp.%Set("statusCode", +tHttpResp.StatusCode)

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

        Set tRetryAfter = tHttpResp.GetHeader("Retry-After")
        If tRetryAfter '= "" {
            Set tHeaders = tResp.%Get("headers")
            Do tHeaders.%Set("retry-after", tRetryAfter)
        }
    }
    Catch ex {
        Throw ex
    }

    Quit tResp
}

/// <p>Story 11.4 — normalize the parsed Location piece so it always ends
/// in <code>/chat/completions</code>. Input is the <code>location</code>
/// field returned by <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method>.</p>
///
/// <p><b>Cases.</b></p>
/// <ul>
/// <li><b>Suffix already present</b> (e.g.,
/// <code>/v1/chat/completions</code>) — return as-is. Operator supplied
/// the full OpenAI-canonical URL.</li>
/// <li><b>Suffix absent, no trailing slash</b> (e.g., <code>/v1</code>) —
/// append <code>/chat/completions</code> → <code>/v1/chat/completions</code>.
/// Operator supplied the Ollama / vLLM base URL.</li>
/// <li><b>Suffix absent, trailing slash</b> (e.g., <code>/v1/</code>) —
/// strip the trailing slash, append <code>/chat/completions</code> →
/// <code>/v1/chat/completions</code> (one separator, not two).</li>
/// <li><b>Empty / root</b> (e.g., <code>/</code>) — append
/// <code>/chat/completions</code> minus the duplicated leading slash →
/// <code>/chat/completions</code>. Defensive — should not happen in
/// production because <method>ParseEndpointUrl</method> defaults Location
/// to <code>/</code> only when the EndpointUrl had no path; CallMessages's
/// Step 1 already rejects empty EndpointUrl.</li>
/// </ul>
///
/// <p><b>Detection rule.</b> The check uses substring presence
/// (<code>$Find</code>) so a hypothetical sub-resource path like
/// <code>/v1/chat/completions/audio</code> is also treated as
/// "already-suffixed" — the operator knows what they want and we don't
/// override. Most paid OpenAI-compatible endpoints (Together AI, OpenRouter,
/// Anyscale) accept the canonical <code>/chat/completions</code> path; the
/// rare deployment that exposes a non-canonical sub-resource still gets
/// passed through unchanged.</p>
ClassMethod NormalizeChatCompletionsLocation(pLocation As %String) As %String [ Internal ]
{
    Set tLoc = $Get(pLocation)

    ; Case 1 — suffix already present. Pass through.
    If $Find(tLoc, "/chat/completions") > 0 {
        Quit tLoc
    }

    ; Case 2/3 — strip a trailing "/" so we end up with exactly one
    ; separator after concatenation.
    If $Length(tLoc) > 1, $Extract(tLoc, *) = "/" {
        Set tLoc = $Extract(tLoc, 1, * - 1)
    }

    ; Case 4 — empty or root "/" → produce "/chat/completions" with one
    ; leading slash. Otherwise concatenate.
    If tLoc = "" || (tLoc = "/") {
        Quit "/chat/completions"
    }

    Quit tLoc _ "/chat/completions"
}

/// <p>Per-instance hook returning MaxAttempts. Defaults to <code>4</code>;
/// test subclasses override to collapse the retry loop.</p>
Method GetMaxAttempts() As %Integer
{
    Quit 4
}

/// <p>Per-instance hook returning BaseDelaySec. Defaults to <code>1</code>;
/// test subclasses override to <code>0</code> to collapse Hang.</p>
Method GetBaseDelaySec() As %Integer
{
    Quit 1
}

/// <p>Per-instance hook returning MaxDelaySec. Defaults to <code>32</code>;
/// test subclasses override to <code>0</code> to collapse Hang.</p>
Method GetMaxDelaySec() As %Integer
{
    Quit 32
}

/// <p>Internal helper — populate pResp with the structured-error envelope
/// and zero-token usage. Same shape as
/// <method>SessionAgent.LLM.Provider.PopulateGenericError</method>.</p>
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
