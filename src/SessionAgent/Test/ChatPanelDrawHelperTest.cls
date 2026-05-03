/// <p>Unit tests for <CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS>
/// covering Story 3.1 AC-5 (semantic-structure, bootstrap-context,
/// XSS-injection probe).</p>
///
/// <p><b>Output capture approach.</b> The helper accepts an optional
/// <code>pStream As %Stream.Object</code> for testability — when supplied,
/// the helper writes the rendered HTML to the stream instead of the
/// current device. Each test instantiates a
/// <code>%Stream.GlobalCharacter</code>, passes it to
/// <code>DrawChatPanel</code>, then reads the stream's full contents back
/// for assertion. Chosen over <code>$IO</code> mnemonic-space redirection
/// because the latter is fragile under the test harness's own output
/// capture (per Story 3.1 Dev Notes).</p>
///
/// <p>Per project rule §"Critical Constructor Requirements": this class
/// implements <code>%OnNew(initvalue)</code> and calls
/// <code>##super(initvalue)</code> — the parent
/// <code>%UnitTest.TestCase</code> requires it.</p>
Class SessionAgent.Test.ChatPanelDrawHelperTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (project rule §"Critical Constructor Requirements" — ERROR #5477
/// blocks Private).</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Internal helper — drive <code>DrawChatPanel</code> with the given
/// args, capture rendered HTML via a <code>%Stream.GlobalCharacter</code>,
/// return both the status and the full string contents.</p>
ClassMethod RenderToString(pAgentName As %String, pSessionKey As %String, pPortalUser As %String, Output pStatus As %Status) As %String
{
    Set tStream = ##class(%Stream.GlobalCharacter).%New()
    Set pStatus = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel(pAgentName, pSessionKey, pPortalUser, tStream)
    If $$$ISERR(pStatus) Quit ""
    Do tStream.Rewind()
    Set tOut = ""
    While 'tStream.AtEnd {
        Set tOut = tOut _ tStream.Read(32000)
    }
    Quit tOut
}

/// <p>AC-5 test 1 — semantic structure. Invoke
/// <code>DrawChatPanel("session-inspection", "1184729", "marisol.rivera")</code>
/// and assert the rendered output contains all 5 literal class names from
/// AC-1: <code>sa-chat-panel</code>, <code>sa-message-transcript</code>,
/// <code>sa-status-text</code>, <code>sa-input-area</code>,
/// <code>sa-input-field</code>. Also asserts (a) the
/// <code>role="region"</code> ARIA wrapper is present, (b) the
/// <code>aria-live="polite"</code> on the status div is present, and (c)
/// no <code>onclick=</code> attribute appears anywhere in the output (per
/// AC-5: event wiring lives in chat-panel.js, not the HTML — UX-DR19).</p>
Method TestSemanticStructure()
{
    Set tStatus = ""
    Set tHtml = ..RenderToString("session-inspection", "1184729", "marisol.rivera", .tStatus)
    Do $$$AssertStatusOK(tStatus, "DrawChatPanel returns OK status")

    ; The 5 class names from AC-1 — exact string matches.
    Do $$$AssertTrue(tHtml [ "sa-chat-panel", "output contains sa-chat-panel class")
    Do $$$AssertTrue(tHtml [ "sa-message-transcript", "output contains sa-message-transcript class")
    Do $$$AssertTrue(tHtml [ "sa-status-text", "output contains sa-status-text class")
    Do $$$AssertTrue(tHtml [ "sa-input-area", "output contains sa-input-area class")
    Do $$$AssertTrue(tHtml [ "sa-input-field", "output contains sa-input-field class")

    ; ARIA attributes from AC-1.
    Do $$$AssertTrue(tHtml [ "role=""region""", "outer wrapper has role=region (UX-DR1)")
    Do $$$AssertTrue(tHtml [ "aria-live=""polite""", "status div has aria-live=polite (UX-DR6)")
    Do $$$AssertTrue(tHtml [ "aria-label=""Agent chat panel""", "wrapper has aria-label")
    Do $$$AssertTrue(tHtml [ "placeholder=""Ask anything about this session.""", "input has fixed MVP placeholder")

    ; Per AC-5 / UX-DR19: no inline onclick attributes — event wiring
    ; lives in chat-panel.js (Story 3.2), not the HTML.
    Do $$$AssertTrue('(tHtml [ "onclick="), "output contains no inline onclick attributes (UX-DR19)")
    Quit
}

/// <p>AC-5 test 2 — bootstrap context. Invoke <code>DrawChatPanel</code>,
/// locate the <code>&lt;script&gt;</code> block, extract the JSON
/// payload assigned to <code>window.SessionAgentChat</code>, parse it
/// via <code>{}.%FromJSON()</code>, and assert all three keys carry the
/// values the helper was called with.</p>
Method TestBootstrapContext()
{
    Set tStatus = ""
    Set tHtml = ..RenderToString("session-inspection", "1184729", "marisol.rivera", .tStatus)
    Do $$$AssertStatusOK(tStatus, "DrawChatPanel returns OK status")

    ; Locate the bootstrap assignment. Use $Find to get the position
    ; *after* the literal "window.SessionAgentChat = ", then read up to
    ; the trailing ";</script>".
    Set tNeedle = "window.SessionAgentChat = "
    Set tStart = $Find(tHtml, tNeedle)
    Do $$$AssertTrue(tStart > 0, "rendered HTML contains 'window.SessionAgentChat = ' assignment")
    If tStart = 0 Quit  ; bail if the assignment isn't there — later asserts would crash

    Set tEndMarker = ";</script>"
    Set tEnd = $Find(tHtml, tEndMarker, tStart)
    Do $$$AssertTrue(tEnd > 0, "bootstrap script block has trailing ;</script>")
    If tEnd = 0 Quit

    ; The JSON payload sits between tStart and the position of the ';'
    ; before the </script>. tEnd is *after* ";</script>"; subtract the
    ; needle length to land at the start of the marker.
    Set tJsonLen = tEnd - tStart - $Length(tEndMarker)
    Set tJson = $Extract(tHtml, tStart, tStart + tJsonLen - 1)

    ; Parse and assert. The post-processed </script> escape uses "<\/script>"
    ; which is a JSON-string-valid escape ("\/" is allowed in JSON strings)
    ; — %FromJSON tolerates it.
    Set tCtx = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tCtx.%Get("agentName"), "session-inspection", "agentName parsed back correctly")
    Do $$$AssertEquals(tCtx.%Get("sessionKey"), "1184729", "sessionKey parsed back correctly")
    Do $$$AssertEquals(tCtx.%Get("portalUser"), "marisol.rivera", "portalUser parsed back correctly")
    Quit
}

/// <p>AC-5 test 3 — XSS injection probe. Invoke
/// <code>DrawChatPanel</code> with a malicious <code>pSessionKey</code>
/// containing a <code>&lt;/script&gt;</code> break-out plus an
/// <code>&lt;img onerror=alert(1)&gt;</code> payload. Assert the literal
/// <code>&lt;/script&gt;</code> substring (with the bare slash) does NOT
/// appear unencoded anywhere in the rendered output — the helper's
/// post-processing step replaces it with the JSON-valid escape
/// <code>&lt;\/script&gt;</code>. The injected payload remains as a
/// JSON string value inside the bootstrap object, where it is inert
/// (parsed as data, not HTML).</p>
///
/// <p>Also asserts the bootstrap object still parses cleanly — an
/// over-eager escape that broke JSON validity would be a different bug,
/// caught here.</p>
Method TestXssEscaping()
{
    Set tInjection = "</script><img onerror=alert(1)>x"
    Set tStatus = ""
    Set tHtml = ..RenderToString("session-inspection", tInjection, "user", .tStatus)
    Do $$$AssertStatusOK(tStatus, "DrawChatPanel with injection returns OK status")

    ; The literal "</script>" must NOT appear unencoded — that would be
    ; the script-tag-break-out vector. We tolerate "<\/script>" (the
    ; escaped form, which is JSON-string-valid and HTML-parser-inert).
    Do $$$AssertTrue('(tHtml [ "</script><img"), "output does NOT contain bare </script><img break-out")

    ; The escaped form should be present — proves the escape ran.
    Do $$$AssertTrue(tHtml [ "<\/script>", "output contains the JSON-escaped <\\/script> (proves XSS escape applied)")

    ; The bootstrap object must still parse cleanly — an over-eager
    ; escape would corrupt the JSON. Re-extract and re-parse.
    Set tNeedle = "window.SessionAgentChat = "
    Set tStart = $Find(tHtml, tNeedle)
    Do $$$AssertTrue(tStart > 0, "bootstrap assignment still present after XSS-probe input")
    If tStart = 0 Quit

    Set tEndMarker = ";</script>"
    Set tEnd = $Find(tHtml, tEndMarker, tStart)
    Do $$$AssertTrue(tEnd > 0, "bootstrap script block still has trailing ;</script>")
    If tEnd = 0 Quit
    Set tJsonLen = tEnd - tStart - $Length(tEndMarker)
    Set tJson = $Extract(tHtml, tStart, tStart + tJsonLen - 1)
    Set tCtx = ##class(%DynamicObject).%FromJSON(tJson)

    ; The injected payload should round-trip as a string value (inert
    ; data, not executable HTML).
    Do $$$AssertEquals(tCtx.%Get("sessionKey"), tInjection, "injected payload survives JSON round-trip as inert string data")
    Quit
}

/// <p>AC-1 boundary test — empty <code>pAgentName</code> is the only
/// invariant violation; the helper must return an error status. Empty
/// <code>pSessionKey</code> and <code>pPortalUser</code> are valid
/// (first-install / not-yet-logged-in states). This test locks the
/// validation behavior so a future refactor can't accidentally tighten
/// or loosen it.</p>
Method TestEmptyAgentNameRejected()
{
    Set tStream = ##class(%Stream.GlobalCharacter).%New()
    Set tStatus = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel("", "session-key", "user", tStream)
    Do $$$AssertStatusNotOK(tStatus, "empty pAgentName returns ERROR status")

    ; Empty pSessionKey + pPortalUser are valid — only pAgentName is
    ; invariant. Probe both.
    Set tStream2 = ##class(%Stream.GlobalCharacter).%New()
    Set tStatus2 = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel("session-inspection", "", "", tStream2)
    Do $$$AssertStatusOK(tStatus2, "empty pSessionKey + pPortalUser is valid (returns OK)")
    Quit
}

}
