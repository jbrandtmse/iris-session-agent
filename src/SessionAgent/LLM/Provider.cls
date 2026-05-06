/// <p>Abstract base class for SessionAgent LLM provider adapters. Each
/// concrete subclass (Story 2.9 <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>,
/// Story 5.1 <CLASS>SessionAgent.LLM.AnthropicProvider</CLASS>, Story 5.2
/// <CLASS>SessionAgent.LLM.GeminiProvider</CLASS>, Story 5.3
/// <CLASS>SessionAgent.LLM.OpenAICompatProvider</CLASS>) overrides the four
/// abstract methods with provider-specific HTTP wire logic; the
/// non-abstract <method>Invoke</method> template orchestrates the
/// cross-cutting concerns (credential resolution, latency capture, audit
/// emit, structured-error envelope) so concretes can stay narrowly focused
/// on the wire shape.</p>
///
/// <p><b>FR28 5th-provider extensibility contract.</b> Adding a new
/// provider requires <b>(a)</b> one new subclass that implements the four
/// abstract methods + <b>(b)</b> one entry in the provider registry the
/// AgentLoop consults at dispatch time. <b>No edits</b> to this abstract
/// base, no edits to <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> /
/// <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS>, no edits to
/// <CLASS>SessionAgent.Util.RetryWithBackoff</CLASS>, no edits to
/// <CLASS>SessionAgent.Audit.Emit</CLASS>. The plug-in point is the
/// abstract method set defined here; everything else is shared
/// infrastructure.</p>
///
/// <p><b>Concrete responsibilities (CONCRETE-CLASS contract).</b></p>
/// <ul>
/// <li><b>HTTP timeout:</b> set <code>%Net.HttpRequest.Timeout = 90</code>
/// inside <method>CallMessages</method> per FR29 90-second per-call
/// budget. The abstract template does not own HTTP — concretes do.</li>
/// <li><b>Retry wrapping:</b> the concrete owns wrapping its own
/// <method>CallMessages</method> in
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method> via a
/// static <code>WrappedCallMessages</code> fixture method on the concrete
/// class. <code>RetryWithBackoff</code> requires a fully-qualified
/// <code>Class.Method</code> string and dispatches via
/// <code>$ClassMethod</code>, which is incompatible with instance-method
/// virtual dispatch from this abstract — so the static fixture lives on
/// each concrete. Story 2.9 implements
/// <code>OpenAIProvider.WrappedCallMessages</code> as the reference.</li>
/// <li><b>Canonical translation:</b> use
/// <method>SessionAgent.LLM.Util.MessageAdapter.CanonicalToProvider</method>
/// to convert canonical Anthropic-shape history into the provider's wire
/// shape before HTTP send, and
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// to convert the provider's response into the canonical
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS> shape before
/// returning. Use
/// <method>SessionAgent.LLM.Util.ToolDefAdapter.CanonicalToProvider</method>
/// for tool definitions.</li>
/// <li><b>NEVER-LOG INVARIANT (NFR-S3):</b> the resolved API key MUST NOT
/// appear in <CLASS>SessionAgent.Audit.LlmCall.ErrorText</CLASS>, in
/// any <code>Write</code> output, in any <code>^ClineDebug</code> entry,
/// or in any other persisted surface. Concretes that build the
/// <code>Authorization</code> header keep the key inside the local
/// stack frame and never copy it elsewhere.</li>
/// </ul>
///
/// <p><b>Template flow (<method>Invoke</method>).</b></p>
/// <ol>
/// <li>Capture start time via <code>$ZHorolog</code> (sub-second
/// precision) for latency calculation.</li>
/// <li>Resolve API key via
/// <method>SessionAgent.Util.EnvSecret.Resolve</method> using
/// <property>Config.Agent.EnvVarName</property> +
/// <property>Config.Agent.CredentialName</property>.</li>
/// <li>If the key is empty, populate
/// <CLASS>pProviderResponse</CLASS> with a structured error envelope
/// (<code>StopReason = "error"</code>, <code>Content = [{type:"text",
/// text:"Credential resolution failed for agent <name>"}]</code>),
/// emit one <CLASS>SessionAgent.Audit.LlmCall</CLASS> row with
/// <code>IsError = 1</code>, return <code>$$$OK</code>. The structured
/// envelope is the FR-aligned UX surface — the AgentLoop renders it
/// to the chat panel without conflating "credential missing" (operator
/// problem) with "provider 5xx" (upstream problem).</li>
/// <li>Call <method>..CallMessages</method> (the abstract; concrete
/// fills). Virtual dispatch resolves to the concrete subclass —
/// standard ObjectScript <code>..MethodName</code> dispatch. The
/// concrete owns the HTTP, the retry wrapping, and the
/// canonical-translation calls.</li>
/// <li>Compute latency in milliseconds (<code>$ZHorolog</code> end -
/// start, multiply by 1000, integer truncate).</li>
/// <li>Emit one <CLASS>SessionAgent.Audit.LlmCall</CLASS> row via
/// <method>SessionAgent.Audit.Emit.LogLlmCall</method> with the
/// 11-arg signature: <code>(ChatHistoryId, Provider, Model,
/// RequestMessageCount, RequestTokens, ResponseTokens, LatencyMs,
/// StopReason, CacheHitTokens, IsError, ErrorText)</code>. The
/// concrete populated <CLASS>pProviderResponse.Usage</CLASS> with
/// the four canonical token-accounting keys; this method maps them
/// to the audit row's typed columns.</li>
/// </ol>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.8</a> (lines 917–948) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Provider abstraction" (lines 113, 809–815) — class layout.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR28 (5th-provider extensibility), FR29 (90s timeout), NFR-S3
/// (never-log invariant), NFR-S4 (audit-row 100% completeness).</li>
/// <li><a href="../../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a>
/// §"Abstract Methods in ObjectScript" — abstract methods MUST have
/// curly-brace bodies returning the appropriate type.</li>
/// </ul>
Class SessionAgent.LLM.Provider Extends %RegisteredObject [ Abstract ]
{

/// <p>Abstract — concrete subclass implements provider-specific HTTP send.
/// The concrete is responsible for: setting
/// <code>%Net.HttpRequest.Timeout = 90</code> (FR29), wrapping the call in
/// <method>SessionAgent.Util.RetryWithBackoff.Execute</method> via a static
/// <code>WrappedCallMessages</code> fixture method, calling
/// <method>SessionAgent.LLM.Util.MessageAdapter.CanonicalToProvider</method>
/// /
/// <method>SessionAgent.LLM.Util.ToolDefAdapter.CanonicalToProvider</method>
/// to translate inputs to the provider wire shape, calling
/// <method>SessionAgent.LLM.Util.MessageAdapter.ProviderToCanonical</method>
/// to translate the response to canonical, and populating
/// <CLASS>pProviderResponse</CLASS> with
/// <property>Content</property> / <property>StopReason</property> /
/// <property>Usage</property>.</p>
///
/// <p><b>NEVER-LOG INVARIANT.</b> The resolved API key (passed in via the
/// concrete's <code>WrappedCallMessages</code> fixture's args object) MUST
/// stay confined to the HTTP-build stack frame; never copy it into
/// <CLASS>pProviderResponse</CLASS>, never embed in error text, never
/// emit to logs.</p>
Method CallMessages(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status [ Abstract ]
{
    Quit $$$OK
}

/// <p>Abstract — return the provider's HTTP endpoint URL. For
/// <code>openai-compatible</code> concretes the URL comes from
/// <property>Config.Agent.EndpointUrl</property> (passed to the concrete's
/// constructor or stored on an instance property); for canonical providers
/// the concrete returns a hardcoded canonical URL
/// (e.g., <code>https://api.openai.com/v1/chat/completions</code>).</p>
Method GetEndpointUrl() As %String [ Abstract ]
{
    Quit ""
}

/// <p>Abstract — return the HTTP <code>Authorization</code> header value
/// for the given API key. Each provider has its own format
/// (<code>Bearer &lt;key&gt;</code> for OpenAI / OpenAI-compat / Gemini;
/// <code>x-api-key: &lt;key&gt;</code> as a separate header for Anthropic).
/// The concrete decides whether the return value is the
/// <code>Authorization</code> header value or a different header name's
/// value — see Anthropic concrete (Story 5.1) for the sentinel form.</p>
///
/// <p><b>NEVER-LOG INVARIANT.</b> The returned string carries the API key.
/// Callers (the concrete's HTTP-build code) MUST set this directly on
/// <code>%Net.HttpRequest</code> headers and never persist or log it.</p>
Method GetAuthHeader(pApiKey As %String) As %String [ Abstract ]
{
    Quit ""
}

/// <p>Abstract — return the provider's canonical name as it appears in
/// <property>Config.Agent.Provider</property> and as the audit-event
/// <code>Name</code> dimension. Values: <code>openai</code>,
/// <code>anthropic</code>, <code>gemini</code>,
/// <code>openai-compatible</code>. Used by <method>Invoke</method> when
/// emitting the audit row so the audit dashboard can pivot by provider.</p>
Method GetProviderName() As %String [ Abstract ]
{
    Quit ""
}

/// <p>Template method — orchestrates one LLM round-trip. See class
/// doc-comment §"Template flow" for the 6-step flow. Concretes do NOT
/// override this method.</p>
///
/// <p>Always returns <code>$$$OK</code>. Errors surface via
/// <CLASS>pProviderResponse</CLASS> (<code>StopReason = "error"</code>,
/// <code>Content[0].text</code> carries an operator-readable error
/// message). The audit row carries <code>IsError = 1</code> and the same
/// error text in <property>ErrorText</property>. This decouples the
/// AgentLoop's flow control from try/catch — the AgentLoop checks
/// <code>StopReason</code> and renders the chat-panel error envelope.</p>
Method Invoke(pCanonicalHistory As %DynamicArray, pToolDefs As %DynamicArray, pSystemPrompt As %String, pCacheConfig As %DynamicObject, pConfigAgent As SessionAgent.Config.Agent, pCallerCtx As SessionAgent.Agent.CallerContext, Output pProviderResponse As SessionAgent.Agent.ProviderResponse) As %Status
{
    Set tSC = $$$OK

    ; Step 1 — capture start time. $ZHorolog returns a fractional-second
    ; high-resolution counter (whole seconds + microseconds). Diff at end
    ; multiplied by 1000 yields milliseconds for the audit row.
    Set tStart = $ZHorolog

    ; Always create the response envelope so the caller sees a valid
    ; object even on the credential-missing fast path.
    If '$IsObject(pProviderResponse) {
        Set pProviderResponse = ##class(SessionAgent.Agent.ProviderResponse).%New()
    }

    Try {
        ; Step 2 — resolve API key via the EnvSecret three-rung ladder.
        ; Story 4.0 codification: $Char(0) is IRIS's legacy %String null
        ; sentinel — operators clearing these via SQL UPDATE see the column
        ; come back as $Char(0) instead of "". Treat both as empty so the
        ; intentional-no-auth path (openai-compatible / Ollama) bypasses the
        ; fast-path credential gate. Bug-1 surfaced 2026-05-06.
        Set tEnvVarName = pConfigAgent.EnvVarName
        Set tCredName = pConfigAgent.CredentialName
        If tEnvVarName = $Char(0) Set tEnvVarName = ""
        If tCredName = $Char(0) Set tCredName = ""
        Set tApiKey = ##class(SessionAgent.Util.EnvSecret).Resolve(tEnvVarName, tCredName)

        ; Step 3 — credential-missing structured-error envelope. Bypass for
        ; the intentional-no-auth case (both EnvVarName AND CredentialName
        ; empty — typically Ollama/openai-compatible). Concrete decides
        ; whether empty-key is acceptable; canonical providers will raise
        ; a structured error inside their CallMessages.
        If (tApiKey = "") && ((tEnvVarName '= "") || (tCredName '= "")) {
            Do ..PopulateCredentialError(pProviderResponse, pConfigAgent.AgentName)
            Set tLatency = ..ComputeLatencyMs(tStart)
            ; Audit-emit at boundary; IsError=1.
            ; ChatHistoryId is unknown at this layer (the AgentLoop owns
            ; the lookup); use the AgentName as a stable correlation key.
            Do ##class(SessionAgent.Audit.Emit).LogLlmCall(
                ..ResolveChatHistoryId(pCallerCtx),
                ..GetProviderName(),
                pConfigAgent.Model,
                pCanonicalHistory.%Size(),
                0, 0,
                tLatency,
                "error",
                0, 1,
                "Credential resolution failed for agent " _ pConfigAgent.AgentName)
            ; Argumentless quit — return after Try/Catch per project rule.
            Quit
        }

        ; Step 4 — virtual dispatch to the concrete's CallMessages. The
        ; concrete owns: setting HTTP timeout = 90s (FR29), wrapping in
        ; RetryWithBackoff.Execute via its WrappedCallMessages fixture,
        ; canonical translation, populating pProviderResponse.
        ;
        ; Note: the API key is NOT in this method's signature — the
        ; concrete reads it via its own EnvSecret.Resolve call inside
        ; CallMessages. This keeps the abstract template ignorant of
        ; provider-specific auth-header construction (NFR-S3 — the key
        ; never leaves the concrete's HTTP-build stack frame).
        Set tCallSC = ..CallMessages(pCanonicalHistory, pToolDefs, pSystemPrompt, pCacheConfig, .pProviderResponse)
        If $$$ISERR(tCallSC) {
            ; Concrete returned a hard %Status error (rare — most failures
            ; surface via pProviderResponse.StopReason = "error" with the
            ; concrete already having populated Content). Treat as
            ; structured error so the AgentLoop sees a uniform shape.
            Do ..PopulateGenericError(pProviderResponse, $System.Status.GetErrorText(tCallSC))
            Set tLatency = ..ComputeLatencyMs(tStart)
            Do ##class(SessionAgent.Audit.Emit).LogLlmCall(
                ..ResolveChatHistoryId(pCallerCtx),
                ..GetProviderName(),
                pConfigAgent.Model,
                pCanonicalHistory.%Size(),
                0, 0,
                tLatency,
                "error",
                0, 1,
                $System.Status.GetErrorText(tCallSC))
            Quit
        }

        ; Step 5 — compute latency.
        Set tLatency = ..ComputeLatencyMs(tStart)

        ; Step 6 — emit audit row at the boundary. Pull token counts from
        ; the canonical Usage object the concrete populated.
        Set tInputTokens = 0
        Set tOutputTokens = 0
        Set tCacheHitTokens = 0
        If $IsObject(pProviderResponse.Usage) {
            If pProviderResponse.Usage.%IsDefined("input_tokens") {
                Set tInputTokens = +pProviderResponse.Usage.%Get("input_tokens")
            }
            If pProviderResponse.Usage.%IsDefined("output_tokens") {
                Set tOutputTokens = +pProviderResponse.Usage.%Get("output_tokens")
            }
            If pProviderResponse.Usage.%IsDefined("cache_read_input_tokens") {
                Set tCacheHitTokens = +pProviderResponse.Usage.%Get("cache_read_input_tokens")
            }
        }
        Set tIsError = 0
        Set tErrorText = ""
        If pProviderResponse.StopReason = "error" {
            Set tIsError = 1
            ; Pull the first text block as the error text — the concrete
            ; populated it with an operator-readable message.
            If $IsObject(pProviderResponse.Content) && (pProviderResponse.Content.%Size() > 0) {
                Set tBlock = pProviderResponse.Content.%Get(0)
                If $IsObject(tBlock) && tBlock.%IsDefined("text") {
                    Set tErrorText = tBlock.%Get("text")
                }
            }
        }

        Do ##class(SessionAgent.Audit.Emit).LogLlmCall(
            ..ResolveChatHistoryId(pCallerCtx),
            ..GetProviderName(),
            pConfigAgent.Model,
            pCanonicalHistory.%Size(),
            tInputTokens,
            tOutputTokens,
            tLatency,
            pProviderResponse.StopReason,
            tCacheHitTokens,
            tIsError,
            tErrorText)
    }
    Catch ex {
        ; Hard exception — populate structured error so the AgentLoop
        ; never crashes mid-turn. Audit-emit may itself fail here; if so,
        ; surface that as the outer status (NFR-S4 — never silently
        ; swallow audit failures).
        Set tEx = ex.AsStatus()
        Do ..PopulateGenericError(pProviderResponse, $System.Status.GetErrorText(tEx))
        Try {
            Do ##class(SessionAgent.Audit.Emit).LogLlmCall(
                ..ResolveChatHistoryId(pCallerCtx),
                ..GetProviderName(),
                pConfigAgent.Model,
                pCanonicalHistory.%Size(),
                0, 0,
                ..ComputeLatencyMs(tStart),
                "error",
                0, 1,
                $System.Status.GetErrorText(tEx))
        }
        Catch auditEx {
            Set tSC = auditEx.AsStatus()
        }
    }
    Quit tSC
}

/// <p>Internal helper — populate <CLASS>pResp</CLASS> with the
/// credential-missing structured-error envelope. The text is operator-
/// readable and names the agent so the operator knows which row in the
/// Story 6 Zen form to fix.</p>
ClassMethod PopulateCredentialError(pResp As SessionAgent.Agent.ProviderResponse, pAgentName As %String) [ Internal ]
{
    Set pResp.StopReason = "error"
    Set pResp.Content = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", "Credential resolution failed for agent " _ pAgentName)
    Do pResp.Content.%Push(tBlock)
    Set pResp.Usage = ##class(%DynamicObject).%New()
    Do pResp.Usage.%Set("input_tokens", 0)
    Do pResp.Usage.%Set("output_tokens", 0)
    Do pResp.Usage.%Set("cache_creation_input_tokens", 0)
    Do pResp.Usage.%Set("cache_read_input_tokens", 0)
    Quit
}

/// <p>Internal helper — populate <CLASS>pResp</CLASS> with a generic
/// structured-error envelope carrying <var>pMsg</var> verbatim. Used for
/// the catch-all paths (concrete returned a hard %Status error, or the
/// template caught an exception). Keeps the response shape uniform so the
/// AgentLoop renders the chat-panel error envelope without knowing the
/// failure class.</p>
ClassMethod PopulateGenericError(pResp As SessionAgent.Agent.ProviderResponse, pMsg As %String) [ Internal ]
{
    Set pResp.StopReason = "error"
    Set pResp.Content = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", pMsg)
    Do pResp.Content.%Push(tBlock)
    If '$IsObject(pResp.Usage) {
        Set pResp.Usage = ##class(%DynamicObject).%New()
        Do pResp.Usage.%Set("input_tokens", 0)
        Do pResp.Usage.%Set("output_tokens", 0)
        Do pResp.Usage.%Set("cache_creation_input_tokens", 0)
        Do pResp.Usage.%Set("cache_read_input_tokens", 0)
    }
    Quit
}

/// <p>Internal helper — return the audit FK
/// (<code>SessionAgent.Audit.LlmCall.ChatHistoryId</code>) for the
/// in-flight turn. Prefers <property>pCallerCtx.ChatHistoryId</property>
/// (set by the AgentLoop after <method>Chat.History.LoadOrCreate</method>),
/// and falls back to <property>pCallerCtx.AgentName</property> for the
/// pre-AgentLoop fast paths (e.g., the Story 2.9 OpenAIProvider tests
/// which exercise the abstract template directly without a Chat.History
/// row in scope). Empty / NULLOREF context returns the empty string —
/// the audit-row FK is NOT NULL-constrained, so we substitute "" rather
/// than crashing the never-throw template invariant (FR37).</p>
ClassMethod ResolveChatHistoryId(pCallerCtx As SessionAgent.Agent.CallerContext) As %String [ Internal ]
{
    If '$IsObject(pCallerCtx) {
        Quit ""
    }
    If pCallerCtx.ChatHistoryId '= "" {
        Quit pCallerCtx.ChatHistoryId
    }
    Quit pCallerCtx.AgentName
}

/// <p>Internal helper — compute latency in milliseconds from a
/// <code>$ZHorolog</code> start counter. Returns the integer-rounded
/// (via <code>$Normalize</code>) millisecond delta. Negative values
/// (clock-skew edge cases) clamp to 0 so the audit row never carries a
/// non-physical negative latency.</p>
ClassMethod ComputeLatencyMs(pStart As %Numeric) As %Integer [ Internal ]
{
    Set tDelta = $ZHorolog - pStart
    If tDelta < 0 {
        Quit 0
    }
    Quit $Normalize(tDelta * 1000, 0)
}

/// <p>Internal — parse an HTTP endpoint URL into its constituent
/// <CLASS>%Net.HttpRequest</CLASS> properties. Returns a
/// <CLASS>%DynamicObject</CLASS> with:</p>
/// <ul>
/// <li><code>server</code> — bare host (no port suffix), e.g.
/// <code>api.openai.com</code> or <code>192.168.0.123</code>.</li>
/// <li><code>port</code> — explicit port as an integer, or <code>0</code>
/// when the URL has no <code>:port</code> suffix (caller should leave
/// <code>%Net.HttpRequest.Port</code> at its default for the scheme).</li>
/// <li><code>location</code> — path component beginning with
/// <code>/</code>, e.g. <code>/v1/chat/completions</code>.</li>
/// <li><code>https</code> — <code>1</code> for <code>https://</code> URLs,
/// <code>0</code> for <code>http://</code> URLs (Story 5.3 Ollama needs
/// HTTP-only support; OpenAI/Anthropic/Gemini are HTTPS).</li>
/// </ul>
///
/// <p><b>Story 5.3 R-3 closure.</b> Centralized here on the abstract base
/// to fix the Story 5.1 bug where <code>server</code> retained the
/// <code>:port</code> suffix and <code>https</code> was hardcoded at the
/// call site. Per the canonical OpenAI / Anthropic / Gemini deployments
/// (HTTPS, port 443) the bug never bit; Ollama
/// (<code>http://192.168.0.123:11434/v1/chat/completions</code>) is the
/// first concrete that exercises both edges. All three pre-existing
/// concretes inherit this method (their previous duplicates were removed
/// in the same Story 5.3 commit per Rule 8 fix-now).</p>
///
/// <p>Examples:</p>
/// <ul>
/// <li><code>https://api.openai.com/v1/chat/completions</code> →
/// <code>{server:"api.openai.com", port:0, location:"/v1/chat/completions",
/// https:1}</code>.</li>
/// <li><code>http://192.168.0.123:11434/v1/chat/completions</code> →
/// <code>{server:"192.168.0.123", port:11434,
/// location:"/v1/chat/completions", https:0}</code>.</li>
/// <li><code>https://example.com:8443/v1/messages</code> →
/// <code>{server:"example.com", port:8443, location:"/v1/messages",
/// https:1}</code>.</li>
/// </ul>
ClassMethod ParseEndpointUrl(pUrl As %String) As %DynamicObject [ Internal ]
{
    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("server", "")
    Do tOut.%Set("port", 0, "number")
    Do tOut.%Set("location", "/")
    Do tOut.%Set("https", 1, "number")

    If $Get(pUrl) = "" Quit tOut

    ; Step 1 — scheme detection. Default https=1 if no scheme present
    ; (defensive — the historic OpenAI/Anthropic/Gemini call sites always
    ; supply a scheme, so this branch is unreachable in production but
    ; safe).
    Set tStripped = pUrl
    Set tHttps = 1
    If $Find(tStripped, "://") {
        Set tScheme = $Piece(tStripped, "://", 1)
        Set tStripped = $Piece(tStripped, "://", 2, 99)
        If $ZConvert(tScheme, "L") = "http" Set tHttps = 0
    }
    Do tOut.%Set("https", tHttps, "number")

    ; Step 2 — split host[:port] and /path. tSlashPos = index of first
    ; "/" + 1 per $Find semantics (or 0 if not found).
    Set tHostPort = tStripped
    Set tLocation = "/"
    Set tSlashPos = $Find(tStripped, "/")
    If tSlashPos > 0 {
        Set tHostPort = $Extract(tStripped, 1, tSlashPos - 2)
        Set tLocation = $Extract(tStripped, tSlashPos - 1, *)
    }

    ; Step 3 — split host and port from the host[:port] piece.
    Set tServer = tHostPort
    Set tPort = 0
    If tHostPort [ ":" {
        Set tServer = $Piece(tHostPort, ":", 1)
        Set tPortStr = $Piece(tHostPort, ":", 2)
        ; Defensive — only treat as a port if all chars are digits. URLs
        ; with IPv6 brackets or other oddities pass through as a single
        ; server string (port = 0).
        Set tIsAllDigits = (tPortStr '= "")
        Set tCi = 1
        While tCi <= $Length(tPortStr) {
            Set tCh = $Extract(tPortStr, tCi)
            If (tCh < "0") || (tCh > "9") {
                Set tIsAllDigits = 0
                Quit
            }
            Set tCi = tCi + 1
        }
        If tIsAllDigits {
            Set tPort = +tPortStr
        } Else {
            ; Bracketed/odd host — restore the full host:port verbatim
            ; into server so the HTTP layer can fail visibly rather than
            ; silently dropping the port.
            Set tServer = tHostPort
            Set tPort = 0
        }
    }

    Do tOut.%Set("server", tServer)
    Do tOut.%Set("port", tPort, "number")
    Do tOut.%Set("location", tLocation)
    Quit tOut
}

}
