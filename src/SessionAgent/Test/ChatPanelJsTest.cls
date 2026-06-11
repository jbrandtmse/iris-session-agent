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

        ; Candidate 1: IPM module root. Same lookup pattern as
        ; SessionAgent.UI.ChatPanelAsset (Story 3.6 fix-now). Works on any
        ; install topology where the IPM source tree is intact post-install.
        Try {
            Set tMod = ##class(%IPM.Storage.Module).NameOpen("iris-session-agent")
            If $IsObject(tMod) {
                Set tCandidate = tMod.Root _ "static/chat-panel.js"
                If ##class(%File).Exists(tCandidate) {
                    Set ..FilePath = tCandidate
                }
            }
        } Catch tIpmEx {
            ; IPM lookup fail is non-fatal — fall through to repo-path candidates.
        }

        ; Candidate 2 + 3: hardcoded repo-source paths (dev-cycle fallback
        ; for environments where IPM module isn't registered yet).
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

/// <p>Story 3.2 AC-6 bullet 7 — bound .innerHTML occurrences (XSS-safety
/// invariant per AC-3 — all DOM construction must use createElement +
/// setAttribute + textContent).</p>
///
/// <p><b>Story 10.7 relaxation:</b> Growth-tier
/// <method>renderMarkdownGrowth</method> pipes Markdown through
/// <code>marked.parse → DOMPurify.sanitize</code> BEFORE assigning to
/// <code>parentNode.innerHTML</code>. The XSS-safety invariant is preserved
/// because DOMPurify strips dangerous markup (<code>&lt;script&gt;</code>,
/// <code>onerror=</code>, etc.) — verified empirically in the AC-5 XSS
/// smoke (Completion Notes) and in
/// <CLASS>SessionAgent.Test.MarkdownBundleTest</CLASS>. The single
/// permitted innerHTML site is in <code>renderMarkdownGrowth</code>,
/// immediately after the <code>DOMPurify.sanitize</code> call. Other
/// innerHTML uses remain banned.</p>
Method TestNoInnerHtml()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    ; Story 10.7: AT MOST ONE innerHTML occurrence (Growth-tier
    ; renderMarkdownGrowth, gated by DOMPurify.sanitize).
    ; $Length(s, sub) returns occurrences+1 of `sub` in `s`, so subtract 1.
    Set tCountSpaced = $Length(..FileContents, ".innerHTML =") - 1
    Set tCountTight = $Length(..FileContents, ".innerHTML=") - 1
    ; The two substrings are mutually exclusive at any given position
    ; (chars differ at offset 11 — space vs '='), so a single innerHTML
    ; site appears in EXACTLY ONE form. Take the max so the assertion
    ; sees a count of 1 regardless of which form the dev wrote.
    Set tCount = $Select(tCountSpaced > tCountTight: tCountSpaced, 1: tCountTight)
    Do $$$AssertTrue(tCount '> 1, "AT MOST ONE .innerHTML assignment (Story 10.7 Growth-tier exception); found " _ tCount)
    ; If a permitted innerHTML site is present, assert DOMPurify.sanitize
    ; appears in the file too (gating invariant).
    If tCount = 1 {
        Do $$$AssertTrue(..FileContents [ "DOMPurify.sanitize", "Growth-tier innerHTML must be paired with DOMPurify.sanitize call site")
    }
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
/// a load-bearing fragment of the welcome-message text. Wording last
/// refreshed in the Story 9.0 / Epic 8 retro AI-3 closure (2026-05-07)
/// to directive form — the welcome string no longer enumerates a
/// hardcoded capability list (3-tool, 6-category, or any-N drift
/// vector), and instead points the operator at "ask anything" + an
/// "I'm read-only" assertion + 3 example questions. Same fix-class as
/// Story 4.0 system-prompt enumeration anti-pattern, applied to the
/// operator-facing welcome string for the second time
/// (Epic 3 / Epic 4 / Epic 8 — three rounds of welcome-message drift
/// before the directive-form rewrite ended the recurrence).</p>
Method TestWelcomeMessagePresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "renderWelcomeMessage", "renderWelcomeMessage helper present (Story 3.3 AC-4)")
    Do $$$AssertTrue(..FileContents [ "Ask anything about this session", "welcome message directive-form opener present (Story 9.0 / Epic 8 retro AI-3 — directive form replaces stale capability enumeration)")
    Do $$$AssertTrue(..FileContents [ "I'm read-only", "welcome message read-only assertion present (Story 9.0 / Epic 8 retro AI-3)")
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

/// <p>Story 4.0 AC-5 — <code>extractToolErrorPreview</code> helper
/// present + tool-card summary path consumes it. The helper extracts a
/// human-readable error preview from a tool-call card with status=error
/// for display in the COLLAPSED card summary line. The renderer concat
/// pattern <code>errorPreview + ' &mdash; called ' +</code> proves the
/// summary path actually consumes the preview rather than ignoring it.
/// A regression that silently drops the helper would re-hide validator
/// rejections behind the expand affordance — the predicted-bug shape
/// from the Epic 3 manual-testing surface (item F in Story 4.0
/// triage).</p>
Method TestExtractToolErrorPreviewPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "function extractToolErrorPreview", "extractToolErrorPreview helper present (Story 4.0 AC-5)")
    Do $$$AssertTrue(..FileContents [ "extractToolErrorPreview(card)", "renderToolCard call site invokes extractToolErrorPreview (Story 4.0 AC-5)")
    ; The summary-line concat uses an em-dash (U+2014) which the IRIS XML
    ; round-trip converts to the &mdash; entity in this .cls source. Match
    ; on the load-bearing identifiers around it instead, which are stable
    ; under the round-trip and still prove the renderer-consumes-preview
    ; path is wired (a regression that drops the consumption would have
    ; to also rename one of these tokens).
    Do $$$AssertTrue(..FileContents [ "if (errorPreview)", "renderToolCard branches on errorPreview presence (Story 4.0 AC-5)")
    Do $$$AssertTrue(..FileContents [ "summaryText.textContent = errorPreview", "summary line consumes the preview when present (Story 4.0 AC-5)")
}

/// <p>Story 4.0 AC-6 — citation-chip click defensive guards present.
/// Asserts the JS source contains the <code>isCitationDispatchable</code>
/// validator AND the <code>surfaceCitationErrorNotice</code> renderer AND
/// the strict numeric-id regex <code>/^\d+$/</code> the validator uses
/// for typed id-bearing citation types. A regression that drops any of
/// these helpers re-opens the silent-no-op behavior the Epic 3 manual
/// testing surface (item H in Story 4.0 triage) flagged as predicted-bug
/// shape. The dedup attribute <code>data-cite-error-shown</code> assertion
/// locks the (3) dedup behavior so subsequent clicks don't pile up
/// duplicate notices.</p>
Method TestCitationDefensiveGuardsPresent()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "function isCitationDispatchable", "isCitationDispatchable helper present (Story 4.0 AC-6.1)")
    Do $$$AssertTrue(..FileContents [ "function surfaceCitationErrorNotice", "surfaceCitationErrorNotice helper present (Story 4.0 AC-6.1+2)")
    Do $$$AssertTrue(..FileContents [ "/^\d+$/", "strict numeric-id regex present in validator (Story 4.0 AC-6.1)")
    Do $$$AssertTrue(..FileContents [ "data-cite-error-shown", "dedup attribute present in surfaceCitationErrorNotice (Story 4.0 AC-6.3)")
    Do $$$AssertTrue(..FileContents [ "sa-citation-error", "notice CSS class present (Story 4.0 AC-6.1+2)")
    Do $$$AssertTrue(..FileContents [ "isCitationDispatchable(citeType, citeId)", "onTranscriptClick gates dispatch through validator (Story 4.0 AC-6.1)")
}

/// <p>Story 10.13 F-2 — sentinel-set-on-initial-render contract. The
/// chat-panel.js init() function MUST set
/// <code>zenPage._tabDisplay['Agent']='__rendered__'</code> at the end
/// of init so the host page's onTabChange override (e.g. the
/// <CLASS>SessionAgent.EnsPortal.MessageViewer</CLASS> override added
/// in Story 10.10) short-circuits on the FIRST operator click. Without
/// this sentinel, the first tab-click calls
/// <code>chatHost.refreshContents()</code> which re-runs OnDrawContent
/// server-side and replaces the working DOM that init() bound events
/// to — leaving the panel inert (transcript empty, Enter no longer
/// submits). The Story 10.10 override-side guard works correctly; this
/// test enforces the init-side companion that the original Story 10.10
/// implementation missed (surfaced empirically by the Story 10.9
/// walkthrough V2).</p>
Method TestSentinelSetOnInitialRender()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    ; Sentinel-set fragment present in init().
    Do $$$AssertTrue(..FileContents [ "zenPage._tabDisplay['Agent'] = '__rendered__'", "init() sets _tabDisplay['Agent']='__rendered__' to short-circuit the first-click refresh (Story 10.13 F-2)")
    ; Defensive guard around zenPage access — the Story 3.6 manual-smoke
    ; fixture loads the JS without a Zen page; the typeof guard keeps
    ; this safe outside a Zen page context.
    Do $$$AssertTrue(..FileContents [ "typeof zenPage !== 'undefined'", "init() guards the sentinel-set behind a typeof zenPage check (Story 10.13 F-2 defense)")
}

/// <p>Story 10.13 F-5 — agent-aware welcome message. The
/// <code>renderWelcomeMessage</code> helper MUST branch on
/// <code>state.context.agentName</code> so the Search Agent
/// (<code>message-search</code>) gets a Search-flavored greeting +
/// Search-flavored example questions, while the Inspection Agent
/// (<code>session-inspection</code> via VisualTrace) keeps its
/// existing per-session greeting. Pre-Story 10.13 the welcome was
/// hardcoded for the Inspection host and shipped verbatim on the
/// Search host, surfacing a UX gap (operator saw "Ask anything about
/// this session..." despite no "this session" context on Message
/// Viewer).</p>
Method TestWelcomeMessageAgentAware()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    ; Branch keys off the bound agentName (state.context.agentName).
    Do $$$AssertTrue(..FileContents [ "agentName === 'message-search'", "renderWelcomeMessage branches on state.context.agentName === 'message-search' (Story 10.13 F-5)")
    ; Search-Agent welcome opener (verbatim per the AC suggestion).
    Do $$$AssertTrue(..FileContents [ "Ask me to find sessions across this IRIS instance", "Search-flavored welcome opener present for message-search (Story 10.13 F-5)")
    ; Search-Agent example-question fragment (substantive content check).
    Do $$$AssertTrue(..FileContents [ "find failed admits in the last hour", "Search-flavored example question present (Story 10.13 F-5)")
    ; Inspection-Agent welcome STILL present (regression guard — we
    ; branched, didn't replace).
    Do $$$AssertTrue(..FileContents [ "Ask anything about this session", "Inspection-flavored welcome still present in else branch (Story 10.13 F-5 regression guard)")
}

/// <p><b>Story 14.5 AC-2 / AC-6 — Epic 14 welcome-text capability
/// update (Rule 4 watch-item closure).</b> Substring-grep binding
/// (Epic 12 AI-5): enumerate ALL expected new capability phrases,
/// assert each present; then assert the stale before-state phrasing
/// (the two replaced example questions) is ABSENT; then assert no
/// tool-name enumeration leaked into the file (the Epic 4→8
/// stale-enumeration class — capability AREAS only, never tool
/// names/counts). The shared capability sentence appears in BOTH
/// welcome branches (asserted twice via occurrence count).</p>
Method TestWelcomeMessageEpic14Capabilities()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    ; New capability-area phrases — present (both branches share the sentence).
    Do $$$AssertTrue(..FileContents [ "analytics and statistics questions with read-only SQL", "Story 14.5 AC-2: analytics/statistics capability area present")
    Do $$$AssertTrue(..FileContents [ "I always show the SQL I ran", "Story 14.5 AC-2: SQL-disclosure reassurance present")
    Do $$$AssertTrue(..FileContents [ "describe unfamiliar message types", "Story 14.5 AC-2: schema-discovery capability area present")
    Do $$$AssertTrue(..FileContents [ "remember schema notes for this namespace", "Story 14.5 AC-2: per-namespace schema-notes capability area present")
    ; The capability sentence appears in BOTH branches ($Length(s,sub)
    ; returns occurrences+1).
    Do $$$AssertEquals($Length(..FileContents, "I always show the SQL I ran") - 1, 2, "Story 14.5 AC-2: capability sentence present in BOTH welcome branches")
    ; New example questions — present (one per branch).
    Do $$$AssertTrue(..FileContents [ "what's the error rate by target in the last 24 hours?", "Story 14.5 AC-2: inspection-branch analytic example present")
    Do $$$AssertTrue(..FileContents [ "how many messages per day went through the order router this month?", "Story 14.5 AC-2: search-branch analytic example present")
    ; Stale before-state phrasing — the two replaced examples must be gone.
    Do $$$AssertTrue('(..FileContents [ "find sessions matching X"), "Story 14.5 AC-2: stale inspection example 'find sessions matching X' removed")
    Do $$$AssertTrue('(..FileContents [ "which messages had OrderRequest bodies"), "Story 14.5 AC-2: stale search example 'which messages had OrderRequest bodies' removed")
    ; No tool-name enumeration anywhere in the JS (capability AREAS only).
    Do $$$AssertTrue('(..FileContents [ "execute_readonly_sql"), "Story 14.5 AC-2: no execute_readonly_sql tool-name enumeration in chat-panel.js")
    Do $$$AssertTrue('(..FileContents [ "get_query_knowledge"), "Story 14.5 AC-2: no get_query_knowledge tool-name enumeration in chat-panel.js")
    Do $$$AssertTrue('(..FileContents [ "save_schema_note"), "Story 14.5 AC-2: no save_schema_note tool-name enumeration in chat-panel.js")
    ; Middle-dot example separators retained in the welcome strings
    ; (real U+00B7 per fix ebde251 — served with TranslateTable=UTF8).
    ; Encoding-robust count: whether the stream decoded UTF-8 (U+00B7 =
    ; $Char(183)) or read raw bytes (0xC2 0xB7 — the 0xB7 byte still
    ; surfaces as $Char(183)), the separator contributes one $Char(183)
    ; per occurrence. Two welcome branches x two separators each = >= 4.
    Set tDotCount = $Length(..FileContents, $Char(183)) - 1
    Do $$$AssertTrue(tDotCount >= 4, "Story 14.5 AC-2: U+00B7 example separators retained (found " _ tDotCount _ ", expected >= 4)")
}

/// <p>Story 12.6 (BUG-07) — renderPriorTranscript must replay
/// preserved tool_use ↔ tool_result pairs by invoking the same
/// renderSearchResultList helper the live path uses. Asserts the
/// JS source contains:</p>
/// <ul>
/// <li><code>turn.toolCalls</code> — the replay path reads the new
/// optional field on each entry.</li>
/// <li><code>renderSearchResultList</code> — the live-path renderer
/// is reused (no duplicate code; same DOM as fresh tiles).</li>
/// <li><code>structuredContent</code> + <code>sessions</code> —
/// the structural-signal contract from Story 10.2 AC-1 (tool name
/// is NOT inspected; the sessions[] array shape drives the render).</li>
/// </ul>
/// <p>Together these prove the BUG-07 fix is wired: tile-shape tool
/// results are re-rendered after page reload, preserving the search
/// → click-through → Back UX.</p>
Method TestPriorTranscriptReplaysToolCalls()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "turn.toolCalls", "Story 12.6: renderPriorTranscript reads turn.toolCalls (BUG-07 fix)")
    Do $$$AssertTrue(..FileContents [ "renderSearchResultList(t,", "Story 12.6: replay path invokes renderSearchResultList with toolCall index t (BUG-07 fix)")
    ; Structural-signal contract — same shape detector as the live path.
    Do $$$AssertTrue(..FileContents [ "structuredContent", "Story 12.6: replay path reads structuredContent (live-path structural-signal contract)")
    Do $$$AssertTrue(..FileContents [ "sc.sessions", "Story 12.6: replay path reads sessions[] array (live-path structural-signal contract)")
    ; Comment trace — anchor the BUG-07 reference so future grep
    ; finds the rule citation alongside the code.
    Do $$$AssertTrue(..FileContents [ "BUG-07", "Story 12.6: renderPriorTranscript carries a BUG-07 comment anchor")
}

/// <p>Test (Story 12.5 BUG-05 AC-1, AC-6) — assert
/// <code>renderSearchResultList</code> in <code>static/chat-panel.js</code>
/// emits the "Load N sessions into table" button:</p>
/// <ul>
/// <li>The CSS class <code>sa-load-into-table-btn</code> is referenced.</li>
/// <li>The label <code>Load</code> + <code>sessions into table</code>
/// substrings are present (the count <code>N</code> is interpolated at
/// render time so we can't assert the literal full string).</li>
/// <li>The click handler invokes
/// <code>zenPage.ApplyAgentSessionFilter(JSON.stringify(...))</code>.</li>
/// <li>Per-element validation regex <code>/^\d+$/</code> is present
/// (SQL-injection JS-side guard, AC-3 prerequisite).</li>
/// </ul>
/// <p>AC-6 (replayed tile lists also emit the button) is satisfied
/// automatically because the new emission lives inside the SAME
/// <code>renderSearchResultList</code> function that
/// <code>renderPriorTranscript</code> already calls in the replay path
/// (per Story 12.6's wiring) — this test confirms the live-path emission
/// surface, the replay path inherits it for free.</p>
Method TestRenderSearchResultListEmitsLoadButton()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)

    ; Load-bearing CSS class on the button surface.
    Do $$$AssertTrue(..FileContents [ "sa-load-into-table-btn", "Story 12.5 AC-1: renderSearchResultList emits the .sa-load-into-table-btn class")
    ; Operator-readable label fragments (count N is interpolated at render time).
    Do $$$AssertTrue(..FileContents [ "sessions into table", "Story 12.5 AC-1: button label contains 'sessions into table'")
    Do $$$AssertTrue(..FileContents [ "'Load '", "Story 12.5 AC-1: button label literal 'Load ' present")
    ; Click handler invokes the ZenMethod with JSON-serialized array.
    Do $$$AssertTrue(..FileContents [ "zenPage.ApplyAgentSessionFilter(", "Story 12.5 AC-1: click handler calls zenPage.ApplyAgentSessionFilter")
    Do $$$AssertTrue(..FileContents [ "JSON.stringify(filtered)", "Story 12.5 AC-1: click handler passes JSON.stringify(filtered) (validated array)")
    ; Per-element numeric validation — SQL-injection JS-side guard.
    Do $$$AssertTrue(..FileContents [ "/^\d+$/", "Story 12.5 AC-3 SQL-injection guard: per-element regex /^\d+$/ present in renderSearchResultList")
    ; BUG-05 comment anchor.
    Do $$$AssertTrue(..FileContents [ "BUG-05", "Story 12.5: chat-panel.js carries a BUG-05 comment anchor")
}

}
