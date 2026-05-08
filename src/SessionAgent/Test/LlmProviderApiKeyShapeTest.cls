/// <p>Unit tests for the <method>SessionAgent.LLM.Provider.IsApiKeyShapeValid</method>
/// virtual hook + per-concrete overrides (Epic 9 demo hardening,
/// 2026-05-07). Validates that cloud providers (OpenAI / Anthropic /
/// Gemini) reject malformed API keys (Windows PATH, missing prefix)
/// BEFORE the network round-trip, while OpenAICompat preserves the
/// Story 5.3 optional-auth idiom (accept-anything) so Ollama-no-auth
/// keeps working unchanged.</p>
///
/// <p><b>Originating finding.</b> Dev-install drift on this IRIS instance
/// set <code>Config.Agent.session-inspection</code> to
/// <code>EnvVarName=PATH, Provider=openai</code>; the resolved API key
/// became the entire Windows PATH (multi-hundred chars containing
/// <code>\</code>, <code>;</code>, drive letters), which bypassed the
/// credential-missing guard and fed garbage into the OpenAI
/// <code>Authorization</code> header. OpenAI rejected with HTTP 401 and
/// the chat panel echoed the bare 401-error-text including the leaked
/// PATH. The shape check rejects the malformed key BEFORE it leaves
/// IRIS, surfacing a clear error envelope instead.</p>
Class SessionAgent.Test.LlmProviderApiKeyShapeTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>OpenAI accepts <code>sk-</code> prefix (legacy).</p>
Method TestOpenAIAcceptsSkPrefix()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("sk-abc123"), "OpenAI accepts sk- prefix")
    Quit
}

/// <p>OpenAI accepts <code>sk-proj-</code> modern prefix (the prefix
/// check is just <code>sk-</code> so this passes naturally).</p>
Method TestOpenAIAcceptsSkProjPrefix()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("sk-proj-xyz789"), "OpenAI accepts sk-proj- prefix")
    Quit
}

/// <p>OpenAI rejects Windows PATH (the originating-finding shape —
/// multi-hundred chars with <code>;</code> separators and <code>\</code>
/// path delimiters).</p>
Method TestOpenAIRejectsWindowsPathShape()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Set tWindowsPath = "C:\Python313\;C:\Program Files\Common Files\Oracle\Java\;C:\Windows\system32\;C:\Windows\;C:\Users\Josh\AppData\Local\Microsoft\WindowsApps"
    Do $$$AssertTrue('tProv.IsApiKeyShapeValid(tWindowsPath), "OpenAI rejects Windows PATH shape")
    Quit
}

/// <p>OpenAI rejects Anthropic key shape (sk-ant- starts with sk- so
/// would pass a naive prefix check; this verifies the OpenAI check
/// allows ANY sk- but Anthropic-shaped keys would never reach
/// OpenAIProvider in practice — the test documents the contract that
/// OpenAI's check is the loosest of the three sk- providers).</p>
Method TestOpenAIAcceptsAnthropicShapedKey()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("sk-ant-api03-something"), "OpenAI accepts any sk- prefix (Anthropic shape passes — the discriminator is Provider config, not shape)")
    Quit
}

/// <p>Anthropic accepts <code>sk-ant-</code> prefix.</p>
Method TestAnthropicAcceptsSkAntPrefix()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("sk-ant-api03-bUmiB-2vdF6ycc"), "Anthropic accepts sk-ant- prefix")
    Quit
}

/// <p>Anthropic rejects bare OpenAI <code>sk-</code> key (without ant-).</p>
Method TestAnthropicRejectsBareSkKey()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Do $$$AssertTrue('tProv.IsApiKeyShapeValid("sk-proj-openai-key"), "Anthropic rejects bare sk- (without ant-)")
    Quit
}

/// <p>Anthropic rejects Windows PATH shape.</p>
Method TestAnthropicRejectsWindowsPathShape()
{
    Set tProv = ##class(SessionAgent.LLM.AnthropicProvider).%New()
    Do $$$AssertTrue('tProv.IsApiKeyShapeValid("C:\Python313\;C:\Program Files\Common Files"), "Anthropic rejects Windows PATH shape")
    Quit
}

/// <p>Gemini accepts <code>AIzaSy</code> prefix. Fixture is an
/// obviously-fake placeholder — never a real-looking key shape — so
/// secret-scanning bots (Google AI Studio anti-abuse, GitHub secret
/// scanning) don't flag this committed source. Story 10.9 close
/// (2026-05-07): a prior real-shaped fixture was scanned + revoked
/// out-of-band; replaced with the placeholder form below.</p>
Method TestGeminiAcceptsAIzaSyPrefix()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("AIzaSy_TEST_FIXTURE_NOT_REAL"), "Gemini accepts AIzaSy prefix")
    Quit
}

/// <p>Gemini rejects sk- prefix (OpenAI/Anthropic shape).</p>
Method TestGeminiRejectsSkPrefix()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Do $$$AssertTrue('tProv.IsApiKeyShapeValid("sk-ant-api03-something"), "Gemini rejects sk- prefix")
    Quit
}

/// <p>Gemini rejects Windows PATH shape.</p>
Method TestGeminiRejectsWindowsPathShape()
{
    Set tProv = ##class(SessionAgent.LLM.GeminiProvider).%New()
    Do $$$AssertTrue('tProv.IsApiKeyShapeValid("C:\Python313\;C:\Program Files"), "Gemini rejects Windows PATH shape")
    Quit
}

/// <p>OpenAICompat accepts ANY shape (preserves Story 5.3 optional-auth
/// idiom). The `EnvVarName=PATH, CredentialName=""` pattern for
/// Ollama-no-auth resolves the Windows PATH as a non-empty sentinel;
/// CallMessages then clears `..ApiKey` when CredentialName="" so no
/// Authorization header is sent. Shape check must NOT block this path.</p>
Method TestOpenAICompatAcceptsWindowsPathShape()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAICompatProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("C:\Python313\;C:\Program Files"), "OpenAICompat accepts Windows PATH (Story 5.3 Ollama-no-auth idiom)")
    Quit
}

/// <p>OpenAICompat accepts any sk- key too (vLLM / LM Studio / etc. may
/// use OpenAI-compatible auth schemes with various key shapes).</p>
Method TestOpenAICompatAcceptsAnyShape()
{
    Set tProv = ##class(SessionAgent.LLM.OpenAICompatProvider).%New()
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("sk-anything"), "OpenAICompat accepts sk- shape")
    Do $$$AssertTrue(tProv.IsApiKeyShapeValid("custom-bearer-token-xyz"), "OpenAICompat accepts arbitrary token")
    Quit
}

}
