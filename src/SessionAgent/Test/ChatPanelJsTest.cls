/// <p>Static-file validator for <code>static/chat-panel.js</code>
/// (Story 3.2). Reads the JS file from disk via
/// <CLASS>%Stream.FileCharacter</CLASS> and asserts presence of the
/// load-bearing patterns + absence of XSS-unsafe patterns per Story 3.2
/// AC-6.</p>
///
/// <p><b>File-locator strategy.</b> Tries two locations in order:</p>
/// <ol>
/// <li>The post-install CSP path:
/// <code>${cspdir}static/iris-session-agent/chat-panel.js</code> via
/// <code>$System.CSP.GetFileName</code>-style lookup. Used after
/// <code>zpm load</code> has copied the file into the IRIS install tree.</li>
/// <li>The repo-source path: walks up from <code>$ZSearch</code> common
/// dev locations (<code>c:/git/iris-session-agent/static/chat-panel.js</code>
/// and Linux mirror <code>/git/iris-session-agent/static/chat-panel.js</code>).
/// Used during dev-cycle iterations before <code>zpm load</code>.</li>
/// </ol>
///
/// <p>If neither locates the file, every test asserts the locator
/// failure (so the regression suite surfaces the gap loudly rather than
/// silently passing nothing). The chosen path is captured in the test
/// class's <property>FilePath</property> property + logged at the start
/// of every assertion message.</p>
///
/// <p><b>Why not a headless-browser test.</b> Per Story 3.2 Dev Notes:
/// JS test infrastructure (jsdom, Playwright, Karma) is its own
/// substantial setup. MVP coverage = file-content invariants + Story 3.6
/// manual cross-browser smoke. The static validator catches every
/// load-bearing AC-6 invariant without bringing up a JS toolchain.</p>
///
/// <p>References:</p>
/// <ul>
/// <li>Story 3.2 spec AC-6 (9 explicit invariant checks).</li>
/// <li>Project rule §"Critical Constructor Requirements" —
/// <code>%OnNew(initvalue)</code> must call
/// <code>##super(initvalue)</code>.</li>
/// <li>Project rule §"Available Assertion Macros" — <code>$$$AssertX</code>
/// macros only; no <code>$$$AssertFalse</code> (use
/// <code>$$$AssertTrue('cond, ...)</code>).</li>
/// </ul>
Class SessionAgent.Test.ChatPanelJsTest Extends %UnitTest.TestCase
{

/// <p>The resolved absolute path to <code>chat-panel.js</code>, or the
/// empty string if the locator could not find it. Populated lazily by
/// <method>LoadFile</method>.</p>
Property FilePath As %String;

/// <p>The full text contents of <code>chat-panel.js</code>, populated
/// lazily by <method>LoadFile</method>.</p>
Property FileContents As %String(MAXLEN = 1000000);

/// <p>Constructor — accepts <code>initvalue</code>, forwards via
/// <code>##super</code> per project rule §"Critical Constructor
/// Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..FilePath = ""
    Set ..FileContents = ""
    Quit $$$OK
}

/// <p>Populate <property>FilePath</property> + <property>FileContents</property>
/// once per test instance. Tries the post-install CSP location first
/// (the file as deployed by <code>zpm load</code>'s
/// <code>FileCopy</code>), then falls back to repo-source candidate
/// paths used during dev-cycle iterations.</p>
Method LoadFile() As %Status
{
    Set tSC = $$$OK
    Try {
        ; Already loaded? Reuse.
        If ..FilePath '= "" Quit

        ; Candidate 1: post-install CSP path. Resolve cspdir then append
        ; the static subpath the FileCopy in module.xml uses.
        Set tCspDir = $System.CSP.GetFileName("/csp/static/iris-session-agent/chat-panel.js")
        If tCspDir '= "", ##class(%File).Exists(tCspDir) {
            Set ..FilePath = tCspDir
        }

        ; Candidate 2 + 3: repo-source paths (dev-cycle pre-zpm-load).
        If ..FilePath = "" {
            Set tRepoWin = "c:\git\iris-session-agent\static\chat-panel.js"
            If ##class(%File).Exists(tRepoWin) {
                Set ..FilePath = tRepoWin
            }
        }
        If ..FilePath = "" {
            Set tRepoNix = "/git/iris-session-agent/static/chat-panel.js"
            If ##class(%File).Exists(tRepoNix) {
                Set ..FilePath = tRepoNix
            }
        }

        If ..FilePath = "" {
            Set tSC = $$$ERROR($$$GeneralError, "ChatPanelJsTest: could not locate chat-panel.js in any candidate path")
            Quit
        }

        ; Read the full contents into a single string. File is small
        ; (~500 lines / ~20 KB).
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tSC = tStream.LinkToFile(..FilePath)
        If $$$ISERR(tSC) Quit
        Set tBuf = ""
        While 'tStream.AtEnd {
            Set tBuf = tBuf _ tStream.Read(32000)
        }
        Set ..FileContents = tBuf
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>AC-6 bullet 1 — exactly one
/// <code>addEventListener('keydown', ...)</code> on the input field.
/// Asserts the substring is present in the file contents (single
/// occurrence is sufficient — the JS attaches one listener total).</p>
Method TestKeydownListenerAttached()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "addEventListener('keydown'", "chat-panel.js attaches a keydown listener (AC-6 bullet 1)")
}

/// <p>AC-6 bullet 2 — Enter / Shift key checks distinguish submit vs
/// newline. Asserts both <code>event.key === 'Enter'</code> and
/// <code>event.shiftKey</code> appear (the JS uses them in the
/// onKeyDown split).</p>
Method TestEnterShiftSplit()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "event.key === 'Enter'", "Enter-key check present (AC-6 bullet 2)")
    Do $$$AssertTrue(..FileContents [ "event.shiftKey", "Shift-key check present (AC-6 bullet 2)")
}

/// <p>AC-6 bullet 3 — there is a
/// <code>zenPage.SendChatMessage(</code> call site. Story 3.3 wires
/// the actual ZenMethod; for this story we only assert the call site
/// exists.</p>
Method TestSendChatMessageCalled()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "zenPage.SendChatMessage(", "zenPage.SendChatMessage call site present (AC-6 bullet 3)")
}

/// <p>AC-6 bullet 4 — there is a <code>JSON.parse(</code> call site
/// for the returned envelope.</p>
Method TestJsonParseUsed()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "JSON.parse(", "JSON.parse call site present (AC-6 bullet 4)")
}

/// <p>AC-6 bullet 5 — tool-call card construction. We use
/// <code>document.createElement('details')</code> +
/// <code>setAttribute('class', 'sa-tool-call-card ...')</code> rather
/// than literal HTML, so the test asserts both load-bearing tokens
/// appear: the <code>'details'</code> createElement call AND the
/// <code>sa-tool-call-card</code> class string. Also asserts the
/// status-modifier names match the CSS token taxonomy shipped by
/// Story 3.1 (<code>--sa-tool-card-status-{running|complete|error}</code>)
/// — the JS must NOT emit a class like <code>sa-tool-card-status-ok</code>
/// because no CSS rule consumes it (the DTO's <code>status:"ok"</code>
/// must be mapped to the CSS modifier <code>complete</code>).</p>
Method TestToolCallCardConstruction()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "createElement('details')", "details element created via createElement (AC-6 bullet 5)")
    Do $$$AssertTrue(..FileContents [ "sa-tool-call-card", "sa-tool-call-card CSS class string present (AC-6 bullet 5)")
    ; Token-taxonomy guard: the JS must map DTO status="ok" -> CSS
    ; modifier "complete" to align with CSS tokens shipped by Story 3.1
    ; (--sa-tool-card-status-{running|complete|error}). The JS builds
    ; the class by concatenation, so we check the load-bearing fragment
    ; "'complete'" appears as a string literal in the source AND that
    ; the rejected literal "sa-tool-card-status-ok" does NOT appear
    ; anywhere (a regression where someone re-introduces the bare DTO
    ; status into the class name would re-introduce the mismatch).
    Do $$$AssertTrue(..FileContents [ "'complete'", "JS source contains the 'complete' modifier literal (AC-6 bullet 5 — CSS taxonomy guard)")
    Do $$$AssertTrue('(..FileContents [ "sa-tool-card-status-ok"), "JS does NOT emit sa-tool-card-status-ok (no CSS token of that name; ok must map to -complete)")
}

/// <p>AC-6 bullet 6 — citation-chip detection regex literal present.
/// The exact literal pattern from chat-panel.js:
/// <code>\[(rule_log|event_log|message|ack|iolog|tool):</code> (the
/// opening bracket-escape + the alternation + the colon).</p>
Method TestCitationRegexPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "\[(rule_log|event_log|message|ack|iolog|tool):", "Citation-chip regex literal present (AC-6 bullet 6)")
}

/// <p>AC-6 bullet 7 — ZERO occurrences of <code>.innerHTML =</code>
/// (XSS-safety invariant per AC-3 — all DOM construction must use
/// createElement + setAttribute + textContent).</p>
Method TestNoInnerHtml()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue('(..FileContents [ ".innerHTML ="), "ZERO .innerHTML= assignments (AC-6 bullet 7)")
    ; Also catch the no-space variant, e.g. .innerHTML=
    Do $$$AssertTrue('(..FileContents [ ".innerHTML="), "ZERO .innerHTML= (no-space) assignments (AC-6 bullet 7)")
}

/// <p>AC-6 bullet 8 — ZERO occurrences of <code>eval(</code> or
/// <code>Function(</code> (no dynamic code execution).</p>
Method TestNoEval()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue('(..FileContents [ "eval("), "ZERO eval( call sites (AC-6 bullet 8)")
    Do $$$AssertTrue('(..FileContents [ "new Function("), "ZERO new Function( call sites (AC-6 bullet 8)")
}

/// <p>AC-6 bullet 9 — ZERO occurrences of CDN URLs
/// (<code>cdnjs|jsdelivr|unpkg|googleapis</code>) — vendored only per
/// NFR-C5.</p>
Method TestNoCdnUrls()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue('(..FileContents [ "cdnjs"), "ZERO cdnjs CDN URLs (AC-6 bullet 9)")
    Do $$$AssertTrue('(..FileContents [ "jsdelivr"), "ZERO jsdelivr CDN URLs (AC-6 bullet 9)")
    Do $$$AssertTrue('(..FileContents [ "unpkg"), "ZERO unpkg CDN URLs (AC-6 bullet 9)")
    Do $$$AssertTrue('(..FileContents [ "googleapis"), "ZERO googleapis CDN URLs (AC-6 bullet 9)")
}

/// <p>Story 3.3 AC-6 — prior-transcript rendering loop present.
/// Asserts the JS source contains the <code>renderPriorTranscript</code>
/// helper (loop body) AND a reference to the bootstrap-context
/// <code>priorTranscript</code> field. Together these prove the JS can
/// pick up the returning-conversation surface from the bootstrap object
/// and render each turn into the transcript.</p>
Method TestPriorTranscriptRenderingPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "renderPriorTranscript", "renderPriorTranscript helper present (Story 3.3 AC-3)")
    Do $$$AssertTrue(..FileContents [ "priorTranscript", "JS reads the bootstrap priorTranscript field (Story 3.3 AC-6)")
}

/// <p>Story 3.3 AC-4 — first-time welcome message rendered. Asserts the
/// JS source contains the <code>renderWelcomeMessage</code> helper AND
/// a load-bearing fragment of the welcome-message text (the
/// "I can read this session's headers" capability-summary opener that
/// the AC-4 spec text mandates). The fragment is unique enough that a
/// regression which deletes the welcome message will trip the test.</p>
Method TestWelcomeMessagePresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "renderWelcomeMessage", "renderWelcomeMessage helper present (Story 3.3 AC-4)")
    Do $$$AssertTrue(..FileContents [ "I can read this session's headers", "welcome message capability-summary fragment present (Story 3.3 AC-4)")
}

/// <p>Story 3.4 AC-6 — citation-chip click delegation listener
/// present. Asserts the JS source attaches a delegated <code>click</code>
/// listener on <code>.sa-message-transcript</code> AND uses
/// <code>closest('.sa-citation-chip')</code> to detect chip clicks
/// regardless of which inner node the operator clicked. Together these
/// two fragments prove the AC-6 delegation mechanism is wired (no
/// per-chip onclick — chips are emitted with no inline handler per
/// UX-DR19, so the listener MUST be on the transcript ancestor).</p>
Method TestCitationDelegationListenerPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "transcriptEl.addEventListener('click'", "transcript-level click listener attached (Story 3.4 AC-6)")
    Do $$$AssertTrue(..FileContents [ "closest('.sa-citation-chip')", "delegated handler uses closest('.sa-citation-chip') (Story 3.4 AC-6)")
    Do $$$AssertTrue(..FileContents [ "zenPage.onCitationClick", "delegated handler dispatches to zenPage.onCitationClick (Story 3.4 AC-6)")
}

/// <p>Story 3.4 AC-4 / Carry-Forward closure (Path 2) — the
/// <code>renderToolCard</code> helper emits
/// <code>data-tool-name</code> on every card alongside the existing
/// <code>data-tool-call-id="tc-N"</code>. Asserts the
/// <code>setAttribute('data-tool-name'</code> fragment is present in
/// the JS source. This closes the Story 3.2 reviewer's binding
/// deferral about <code>tc-N</code> synthesis vs LLM-emitted
/// <code>data-cite-id</code> mismatch — the
/// <code>onCitationClick</code> handler now has a tool-name-keyed
/// lookup primary path with the dispatch-index fallback retained.</p>
Method TestRenderToolCardEmitsToolNameAttr()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "setAttribute('data-tool-name'", "renderToolCard tags every card with data-tool-name (Story 3.4 Carry-Forward Path 2 closure)")
}

/// <p>Story 3.5 AC-5 — <code>ERROR_KIND_TO_TEXT</code> map literal
/// present + load-bearing kinds. Asserts the JS source contains the
/// canonical map identifier AND the six wire-format error kinds the
/// AgentLoop / OpenAIProvider / SendChatMessage envelopes can produce
/// (provider_timeout, provider_error, provider_auth, provider_rate_limit,
/// no_config, internal). A regression that drops one of the kinds would
/// silently fall back to the generic "Something went wrong" path,
/// burying operator-actionable per-kind advice.</p>
Method TestErrorKindToTextMapPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "ERROR_KIND_TO_TEXT", "ERROR_KIND_TO_TEXT map identifier present (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'provider_timeout'", "ERROR_KIND_TO_TEXT keys provider_timeout (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'provider_error'", "ERROR_KIND_TO_TEXT keys provider_error (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'provider_auth'", "ERROR_KIND_TO_TEXT keys provider_auth (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'provider_rate_limit'", "ERROR_KIND_TO_TEXT keys provider_rate_limit (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'no_config'", "ERROR_KIND_TO_TEXT keys no_config (Story 3.5 AC-5)")
    Do $$$AssertTrue(..FileContents [ "'internal'", "ERROR_KIND_TO_TEXT keys internal (Story 3.5 AC-5)")
    ; UX-DR18-MVP-subset verbatim text fragments — locks the wording.
    Do $$$AssertTrue(..FileContents [ "exceeded 90 seconds", "provider_timeout includes the 90-second mention (UX-DR18-MVP-subset)")
    Do $$$AssertTrue(..FileContents [ "operator-admin needs to set up", "no_config text uses the operator-admin call-to-action (UX-DR18-MVP-subset)")
}

/// <p>Story 3.5 AC-5 — <code>renderErrorBlock</code> handles unknown
/// kinds via the generic fallback. Asserts the JS source contains the
/// fallback text fragment <code>"Something went wrong: "</code>; this
/// is the literal that fires when <code>error.kind</code> is undefined
/// or not present in the map. A regression that hard-codes the AC-5 map
/// without the unknown-kind fallback would break backward compatibility
/// with Story 3.2's existing error paths (which emit
/// <code>{kind:'provider_error', message:'...'}</code> but used to
/// render via the prior <code>error.message</code>-only path — the
/// generic fallback is the safety net).</p>
Method TestRenderErrorBlockHandlesUnknownKind()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "Something went wrong: ", "renderErrorBlock has unknown-kind fallback text (Story 3.5 AC-5)")
    ; Map lookup pattern — locks the renderer-via-map dispatch shape.
    Do $$$AssertTrue(..FileContents [ "ERROR_KIND_TO_TEXT[kind]", "renderErrorBlock looks up by kind (Story 3.5 AC-5)")
}

/// <p>Story 3.4 AC-7 — <code>parseInlineCitations</code> regex widened
/// to capture an OPTIONAL third group (the body class name needed by
/// parent <code>selectItem</code>'s <code>extraType</code> param).
/// Asserts the new regex literal contains the optional third group
/// pattern <code>(?::([^\]]+))?</code> AND that the chip emits
/// <code>data-cite-klass</code> when the third group matches.</p>
Method TestParseInlineCitationsKlassCapture()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "(?::([^\]]+))?", "Citation regex includes the optional klass capture group (Story 3.4 AC-7)")
    Do $$$AssertTrue(..FileContents [ "setAttribute('data-cite-klass'", "Chip writes data-cite-klass when klass capture matched (Story 3.4 AC-7)")
    Do $$$AssertTrue(..FileContents [ "setAttribute('aria-label'", "Chip writes aria-label per citation type (Story 3.4 AC-5)")
}

}
