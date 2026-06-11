/// <p>Unit tests for Story 11.4 — smart suffix detection in
/// <method>SessionAgent.LLM.OpenAICompatProvider.NormalizeChatCompletionsLocation</method>.</p>
///
/// <p><b>Background.</b> Story 10.13 walkthrough V2 surfaced HTTP 404 from
/// the openai-compatible code path when the operator-supplied EndpointUrl
/// did not contain the canonical <code>/chat/completions</code> suffix
/// (e.g., the operator gave the Ollama / vLLM base URL like
/// <code>http://localhost:11434/v1</code>). The pre-fix
/// <method>SessionAgent.LLM.OpenAICompatProvider.IssueHttpsPost</method>
/// posted to whatever <code>Location</code> the centralized
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> returned —
/// <code>/v1</code> in that case — which OpenAI-compatible servers
/// answer with HTTP 404. The fix introduces
/// <method>NormalizeChatCompletionsLocation</method> which appends
/// <code>/chat/completions</code> when absent, preserves it when present,
/// and handles trailing-slash forms cleanly.</p>
///
/// <p><b>AC-3 coverage (3 methods):</b></p>
/// <ol>
/// <li><b>TestUrlConstructionAppendsSuffixWhenAbsent</b> — endpoint
/// <code>http://localhost:11434/v1</code> → constructed Location is
/// <code>/v1/chat/completions</code>.</li>
/// <li><b>TestUrlConstructionUsesAsIsWhenSuffixPresent</b> — endpoint
/// <code>https://api.openai.com/v1/chat/completions</code> → constructed
/// Location is <code>/v1/chat/completions</code> (no double-suffix).</li>
/// <li><b>TestUrlConstructionHandlesTrailingSlash</b> — endpoint
/// <code>http://localhost:11434/v1/</code> → constructed Location is
/// <code>/v1/chat/completions</code> (one slash, not two).</li>
/// </ol>
///
/// <p>The tests exercise the helper directly via classmethod call —
/// <method>NormalizeChatCompletionsLocation</method> is pure (no instance
/// state, no HTTP) so end-to-end mock-HTTP indirection is unnecessary
/// here. The downstream wiring through
/// <method>IssueHttpsPost</method> is already covered by
/// <CLASS>SessionAgent.Test.OpenAICompatProviderTest</CLASS> and the live
/// matrix in <CLASS>SessionAgent.Test.OpenAICompatProviderLive</CLASS>.</p>
Class SessionAgent.Test.OpenAICompatUrlConstructionTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-3 #1 — operator supplies the Ollama / vLLM base URL form.
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> returns
/// <code>Location=/v1</code>; the helper must append
/// <code>/chat/completions</code> so the POST hits the canonical
/// OpenAI-compatible Chat Completions path.</p>
Method TestUrlConstructionAppendsSuffixWhenAbsent()
{
    ; Step 1 — confirm the parser returns Location=/v1 for the base URL.
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("http://localhost:11434/v1")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1", "ParseEndpointUrl yields /v1 for Ollama base URL")

    ; Step 2 — the helper appends the canonical suffix.
    Set tNorm = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation(tParsed.%Get("location"))
    Do $$$AssertEquals(tNorm, "/v1/chat/completions", "NormalizeChatCompletionsLocation appends /chat/completions when absent")
    Quit
}

/// <p>Epic 14 walkthrough fix (2026-06-11) — operator supplies a BARE
/// host:port URL (e.g. <code>http://192.168.0.123:11434</code>, no path).
/// The parser returns an empty/root Location; the helper must produce
/// <code>/v1/chat/completions</code> (NOT <code>/chat/completions</code>,
/// which 404s on Ollama / LM Studio / vLLM — verified live against
/// Ollama: "404 page not found").</p>
Method TestUrlConstructionBareHostGetsV1Path()
{
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("http://192.168.0.123:11434")
    Set tNorm = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation(tParsed.%Get("location"))
    Do $$$AssertEquals(tNorm, "/v1/chat/completions", "bare host:port endpoint normalizes to /v1/chat/completions")
    ; Root-slash form behaves identically.
    Set tNorm2 = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation("/")
    Do $$$AssertEquals(tNorm2, "/v1/chat/completions", "root-slash location normalizes to /v1/chat/completions")
    Quit
}

/// <p>AC-3 #2 — operator supplies the OpenAI-canonical full URL form
/// (path already includes <code>/chat/completions</code>).
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> returns
/// <code>Location=/v1/chat/completions</code>; the helper must pass it
/// through unchanged. Without this branch, a naive append would produce
/// <code>/v1/chat/completions/chat/completions</code> → HTTP 404.</p>
Method TestUrlConstructionUsesAsIsWhenSuffixPresent()
{
    ; Step 1 — confirm the parser returns the full path verbatim.
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("https://api.openai.com/v1/chat/completions")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1/chat/completions", "ParseEndpointUrl yields /v1/chat/completions for OpenAI canonical URL")

    ; Step 2 — the helper passes through unchanged (no double-suffix).
    Set tNorm = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation(tParsed.%Get("location"))
    Do $$$AssertEquals(tNorm, "/v1/chat/completions", "NormalizeChatCompletionsLocation passes through when suffix already present")

    ; Defensive: ensure no double-suffix even if called twice.
    Set tDouble = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation(tNorm)
    Do $$$AssertEquals(tDouble, "/v1/chat/completions", "NormalizeChatCompletionsLocation is idempotent — double-call yields same result")
    Quit
}

/// <p>AC-3 #3 — operator supplies the Ollama / vLLM base URL with a
/// trailing slash (e.g., <code>http://localhost:11434/v1/</code>).
/// <method>SessionAgent.LLM.Provider.ParseEndpointUrl</method> returns
/// <code>Location=/v1/</code>; the helper must strip the trailing slash
/// before appending so the result has exactly one separator
/// (<code>/v1/chat/completions</code>) instead of a doubled one
/// (<code>/v1//chat/completions</code>).</p>
Method TestUrlConstructionHandlesTrailingSlash()
{
    ; Step 1 — confirm the parser returns Location=/v1/ (with trailing slash).
    Set tParsed = ##class(SessionAgent.LLM.Provider).ParseEndpointUrl("http://localhost:11434/v1/")
    Do $$$AssertEquals(tParsed.%Get("location"), "/v1/", "ParseEndpointUrl preserves trailing slash on Ollama base URL")

    ; Step 2 — the helper produces /v1/chat/completions (one slash).
    Set tNorm = ##class(SessionAgent.LLM.OpenAICompatProvider).NormalizeChatCompletionsLocation(tParsed.%Get("location"))
    Do $$$AssertEquals(tNorm, "/v1/chat/completions", "NormalizeChatCompletionsLocation strips trailing slash before appending — one separator only")
    Quit
}

}
