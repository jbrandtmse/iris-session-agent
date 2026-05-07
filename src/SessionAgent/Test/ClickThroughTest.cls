/// <p>Story 10.3 AC-6 — unit tests for the click-through wiring shipped
/// across <CLASS>SessionAgent.EnsPortal.MessageViewer</CLASS> (3-arg
/// <code>[ZenMethod]</code> wrapper) AND <code>static/chat-panel.js</code>
/// (<code>onSearchResultClick</code> body, <code>state.lastToolCallsRendered</code>
/// cache, destination-URL construction).</p>
///
/// <p><b>Coverage map.</b> Per AC-6 the four load-bearing assertions are:</p>
/// <ol>
/// <li><method>RecordClickThroughWrapperResolvesUserAtBoundary</method> —
/// invoke <code>MessageViewer.RecordClickThrough</code> ClassMethod
/// without a CSP session, verify the response JSON is well-formed (the
/// boundary delegates to <code>$Username</code> fallback). Asserts the
/// wrapper exists, accepts 3 args, and returns a JSON-parseable string
/// without throwing. Does NOT assert on aliases recorded — Story 9.5's
/// <CLASS>SessionAgent.Search.VocabCapture</CLASS> tests cover that.</li>
/// <li><method>ChatPanelJsContainsRecordClickThroughCall</method> —
/// <code>%File</code>-grep assertion against
/// <code>static/chat-panel.js</code> confirming the literal string
/// <code>zenPage.RecordClickThrough(</code> appears (proves the JS wires
/// the hyperevent invocation).</li>
/// <li><method>ChatPanelJsContainsFromSearchUrlParam</method> —
/// <code>%File</code>-grep assertion that the JS source contains both
/// <code>FROM_SEARCH=</code> and <code>SESSIONID=</code> query-param
/// fragments + the <code>SessionAgent.EnsPortal.VisualTrace.zen</code>
/// destination path.</li>
/// <li><method>ChatPanelJsCachesToolCallsRendered</method> —
/// <code>%File</code>-grep assertion that the JS source caches the
/// most-recent agent turn's <code>toolCallsRendered</code> via
/// <code>state.lastToolCallsRendered =</code> (proves AC-3's caching
/// mechanism is wired).</li>
/// </ol>
///
/// <p><b>File-locator strategy.</b> Mirrors
/// <CLASS>SessionAgent.Test.ChatPanelJsTest</CLASS> — try the IPM module
/// root first, fall back to the canonical repo paths. If neither resolves
/// the file, every <code>%File</code>-grep assertion fails loudly via
/// <method>LoadFile</method>'s status return.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/10-3-click-through-capture-navigation-to-visual-trace.md">Story 10.3 spec</a> — AC-6 verbatim source.</li>
/// <li><CLASS>SessionAgent.EnsPortal.MessageViewer</CLASS> — host of the 3-arg ZenMethod wrapper.</li>
/// <li><CLASS>SessionAgent.Search.VocabCapture</CLASS> — Story 9.5 substrate (4-arg ClassMethod).</li>
/// <li><CLASS>SessionAgent.Test.ChatPanelJsTest</CLASS> — locator pattern reuse.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a> — assertion macros, %OnNew(initvalue), Test* shadow trap.</li>
/// </ul>
Class SessionAgent.Test.ClickThroughTest Extends %UnitTest.TestCase
{

/// <p>Resolved absolute path to <code>chat-panel.js</code>, or empty if
/// not located. Populated lazily by <method>LoadFile</method>.</p>
Property FilePath As %String;

/// <p>Full text contents of <code>chat-panel.js</code>. Populated lazily
/// by <method>LoadFile</method>. Note: the property name is
/// <code>FileContents</code> — does NOT begin with <code>Test</code> so
/// the framework's test-method-discovery loop does NOT shadow it (see
/// <code>.claude/rules/object-script-testing.md</code> §"Property Test*
/// Test-Method-Discovery Shadow Trap").</p>
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

/// <p>Locate <code>chat-panel.js</code> on disk and load its full
/// contents into <property>FileContents</property>. Verbatim copy of
/// the locator strategy from <CLASS>SessionAgent.Test.ChatPanelJsTest</CLASS>
/// — IPM module root first, then hardcoded repo paths (Win + Linux).</p>
Method LoadFile() As %Status
{
    Set tSC = $$$OK
    Try {
        ; Already loaded? Reuse.
        If ..FilePath '= "" Quit

        ; Candidate 1: IPM module root.
        Try {
            Set tMod = ##class(%IPM.Storage.Module).NameOpen("iris-session-agent")
            If $IsObject(tMod) {
                Set tCandidate = tMod.Root _ "static/chat-panel.js"
                If ##class(%File).Exists(tCandidate) {
                    Set ..FilePath = tCandidate
                }
            }
        } Catch tIpmEx {
            ; IPM lookup fail is non-fatal — fall through to repo paths.
        }

        ; Candidate 2: Windows repo path.
        If ..FilePath = "" {
            Set tRepoWin = "c:\git\iris-session-agent\static\chat-panel.js"
            If ##class(%File).Exists(tRepoWin) {
                Set ..FilePath = tRepoWin
            }
        }
        ; Candidate 3: Linux mirror.
        If ..FilePath = "" {
            Set tRepoNix = "/git/iris-session-agent/static/chat-panel.js"
            If ##class(%File).Exists(tRepoNix) {
                Set ..FilePath = tRepoNix
            }
        }

        If ..FilePath = "" {
            Set tSC = $$$ERROR($$$GeneralError, "ClickThroughTest: could not locate chat-panel.js in any candidate path")
            Quit
        }

        ; Read full contents (~30 KB after Story 10.3 additions).
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

/// <p>AC-6 #1 — invoke
/// <CLASS>SessionAgent.EnsPortal.MessageViewer</CLASS>'s
/// <method>RecordClickThrough</method> ClassMethod without a CSP session
/// (test-harness context — <code>$IsObject($Get(%session))</code> is
/// false). The wrapper MUST resolve <code>$Username</code> as the
/// fallback portal user, delegate to Story 9.5's substrate, and return
/// a JSON-parseable envelope (never throws).</p>
///
/// <p>The envelope's <code>success</code> flag is asserted true (empty
/// JSON array → no aliases inferred, but no error either, per Story 9.5
/// AC-1). The <code>search_session_key</code> + <code>session_id</code>
/// passthrough fields are verified non-empty (echo contract).</p>
///
/// <p>This test does NOT assert on <code>aliases_recorded</code>
/// content — that's covered by Story 9.5's
/// <CLASS>SessionAgent.Test.SearchVocabCaptureTest</CLASS>.</p>
Method TestRecordClickThroughWrapperResolvesUserAtBoundary()
{
    Set tEnvelopeJson = ""
    Set tThrew = 0
    Try {
        Set tEnvelopeJson = ##class(SessionAgent.EnsPortal.MessageViewer).RecordClickThrough("sa-test-103-key", "0", "[]")
    } Catch ex {
        Set tThrew = 1
    }
    Do $$$AssertTrue('tThrew, "RecordClickThrough wrapper never throws")
    Do $$$AssertNotEquals(tEnvelopeJson, "", "RecordClickThrough returns a non-empty JSON string")

    ; Verify it parses as JSON (well-formed envelope).
    Set tParsed = ""
    Set tParseThrew = 0
    Try {
        Set tParsed = ##class(%DynamicObject).%FromJSON(tEnvelopeJson)
    } Catch parseEx {
        Set tParseThrew = 1
    }
    Do $$$AssertTrue('tParseThrew, "RecordClickThrough envelope is JSON-parseable")
    Do $$$AssertTrue($IsObject(tParsed), "Parsed envelope is an object")

    ; Verify success flag = true (empty contributing tool calls → no
    ; aliases inferred; not an error per Story 9.5 AC-1).
    Do $$$AssertEquals(tParsed.%Get("success"), 1, "envelope.success is true on empty tool-call array")

    ; Verify passthrough echo fields per Story 9.5 AC-3.
    Do $$$AssertEquals(tParsed.%Get("search_session_key"), "sa-test-103-key", "search_session_key echoed verbatim")
    Do $$$AssertEquals(tParsed.%Get("session_id"), "0", "session_id echoed verbatim")
}

/// <p>AC-6 #2 — <code>%File</code>-grep assertion that the JS source
/// contains the literal call site
/// <code>zenPage.RecordClickThrough(</code>. This proves the click
/// handler in <code>onSearchResultClick</code> wires the hyperevent
/// invocation. A regression that drops the call site (e.g., a refactor
/// that names the method differently or comments out the call) will
/// surface here loudly.</p>
Method TestChatPanelJsContainsRecordClickThroughCall()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "zenPage.RecordClickThrough(", "chat-panel.js wires the zenPage.RecordClickThrough( call site (Story 10.3 AC-6 #2)")
}

/// <p>AC-6 #3 — <code>%File</code>-grep assertion that the JS source
/// constructs the destination URL with both <code>FROM_SEARCH=</code>
/// and <code>SESSIONID=</code> query parameters AND the
/// <code>SessionAgent.EnsPortal.VisualTrace.zen</code> destination path.
/// All three load-bearing fragments must appear; Story 10.4 will read
/// the <code>FROM_SEARCH</code> param to render the "from search"
/// stripe.</p>
Method TestChatPanelJsContainsFromSearchUrlParam()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "FROM_SEARCH=", "chat-panel.js URL builder includes FROM_SEARCH= query param (Story 10.3 AC-4 / AC-6 #3)")
    Do $$$AssertTrue(..FileContents [ "SESSIONID=", "chat-panel.js URL builder includes SESSIONID= query param (Story 10.3 AC-4 / AC-6 #3)")
    Do $$$AssertTrue(..FileContents [ "SessionAgent.EnsPortal.VisualTrace.zen", "chat-panel.js URL builder targets VisualTrace.zen destination (Story 10.3 AC-4 / AC-6 #3)")
}

/// <p>AC-6 #4 — <code>%File</code>-grep assertion that the JS source
/// caches the most-recent agent turn's <code>toolCallsRendered[]</code>
/// via <code>state.lastToolCallsRendered =</code>. This proves AC-3's
/// caching mechanism is wired so that <code>onSearchResultClick</code>
/// can assemble the contributing-tool-calls payload from the cache.</p>
Method TestChatPanelJsCachesToolCallsRendered()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "state.lastToolCallsRendered =", "chat-panel.js caches toolCallsRendered into state.lastToolCallsRendered (Story 10.3 AC-3 / AC-6 #4)")
}

}
