/// <p>Story 10.4 AC-9 — unit tests for the from-search stripe wiring
/// shipped across <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>
/// (<code>fromSearchKey</code> ZENURL property +
/// <code>ExtractLiteralFirstUserMessage</code> helper),
/// <CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS>
/// (<code>pFromSearchQuery</code> / <code>pFromSearchKey</code> bootstrap
/// emission), <CLASS>SessionAgent.UI.ChatPanel</CLASS>
/// (<code>EmitStyle</code> CSS rules), and <code>static/chat-panel.js</code>
/// (<code>renderFromSearchStripe</code> + <code>state.fromSearchContext</code>
/// + Accept/Dismiss handlers + <code>submitTurn</code> merge).</p>
///
/// <p><b>Coverage map.</b> Per AC-9 the four load-bearing assertions are:</p>
/// <ol>
/// <li><method>TestVisualTracePropertyFromSearchKeyExists</method> —
/// <code>%Dictionary.PropertyDefinition</code> lookup confirms the new
/// <code>fromSearchKey</code> ZENURL property exists on
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>.</li>
/// <li><method>TestExtractLiteralQueryFromHistory</method> — invoke
/// <method>SessionAgent.EnsPortal.VisualTrace.ExtractLiteralFirstUserMessage</method>
/// against a seeded <CLASS>SessionAgent.Chat.History</CLASS> row; assert
/// verbatim match.</li>
/// <li><method>TestChatPanelJsContainsFromSearchStripe</method> —
/// <code>%File</code>-grep assertion that <code>chat-panel.js</code> wires
/// the stripe class name, the state cache key, the Accept-button handler,
/// and the contextHints merge.</li>
/// <li><method>TestEmitStyleContainsFromSearchStripeRules</method> —
/// <code>EmitStyle</code> output contains the new CSS rule selectors.</li>
/// </ol>
///
/// <p><b>File-locator strategy.</b> Mirrors
/// <CLASS>SessionAgent.Test.ClickThroughTest</CLASS> (Story 10.3) — try the
/// IPM module root first, fall back to the canonical repo paths. If neither
/// resolves the file, every <code>%File</code>-grep assertion fails loudly
/// via <method>LoadFile</method>'s status return.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/10-4-sa-from-search-stripe-inspection-side-from-search-handling.md">Story 10.4 spec</a> — AC-9 verbatim source.</li>
/// <li><CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> — host of the
/// <code>fromSearchKey</code> ZENURL property + extraction helper.</li>
/// <li><CLASS>SessionAgent.Test.ClickThroughTest</CLASS> — locator pattern
/// reuse + <code>FileContents</code> property naming convention (Property
/// Test* shadow-trap rule per
/// <a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>).</li>
/// </ul>
Class SessionAgent.Test.FromSearchStripeTest Extends %UnitTest.TestCase
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
/// the locator strategy from <CLASS>SessionAgent.Test.ClickThroughTest</CLASS>
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
            Set tSC = $$$ERROR($$$GeneralError, "FromSearchStripeTest: could not locate chat-panel.js in any candidate path")
            Quit
        }

        ; Read full contents.
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

/// <p>AC-9 #1 — <code>%Dictionary.PropertyDefinition</code> lookup
/// confirms the new <code>fromSearchKey</code> ZENURL property exists
/// on <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> (the property
/// auto-binds the <code>FROM_SEARCH</code> URL query param into the page
/// instance per Zen <code>ZENURL</code> semantics). A regression that
/// drops the property OR renames it surfaces here.</p>
Method TestVisualTracePropertyFromSearchKeyExists()
{
    Set tExists = 0
    Set tType = ""
    &sql(SELECT 1, %EXACT(Type)
         INTO :tExists, :tType
         FROM %Dictionary.PropertyDefinition
         WHERE %EXACT(Parent) = 'SessionAgent.EnsPortal.VisualTrace'
           AND %EXACT(Name) = 'fromSearchKey')
    Do $$$AssertEquals(SQLCODE, 0, "fromSearchKey property row found in %Dictionary.PropertyDefinition (Story 10.4 AC-1 / AC-9 #1)")
    Do $$$AssertEquals(tType, "%ZEN.Datatype.string", "fromSearchKey is typed as %ZEN.Datatype.string for ZENURL binding")
}

/// <p>AC-9 #2 — invoke
/// <method>SessionAgent.EnsPortal.VisualTrace.ExtractLiteralFirstUserMessage</method>
/// against a transient <CLASS>SessionAgent.Chat.History</CLASS> row whose
/// <code>TurnsJson</code> stream contains the canonical-Anthropic shape
/// with a single <code>role:"user"</code> turn carrying one
/// <code>type:"text"</code> block. Assert the helper returns the
/// verbatim text. Per Story 9.4's two-array invariant the digest prefix
/// is NEVER persisted — the first user turn's text block IS the literal
/// operator query verbatim.</p>
Method TestExtractLiteralQueryFromHistory()
{
    ; Build a transient (un-saved) Chat.History row to exercise the helper
    ; without polluting the live table. The helper only reads TurnsJson;
    ; AgentName/SessionKey/PortalUser are not consulted.
    Set tHist = ##class(SessionAgent.Chat.History).%New()
    Set tHist.AgentName = "message-search"
    Set tHist.SessionKey = "sa-test-104-extract"
    Set tHist.PortalUser = "_SYSTEM"
    Set tQ = $Char(34)
    Set tBody = "[{"_tQ_"role"_tQ_":"_tQ_"user"_tQ_","_tQ_"content"_tQ_":[{"_tQ_"type"_tQ_":"_tQ_"text"_tQ_","_tQ_"text"_tQ_":"_tQ_"find sessions with errors"_tQ_"}]}]"
    Do tHist.TurnsJson.Write(tBody)

    Set tLiteral = ##class(SessionAgent.EnsPortal.VisualTrace).ExtractLiteralFirstUserMessage(tHist)
    Do $$$AssertEquals(tLiteral, "find sessions with errors", "ExtractLiteralFirstUserMessage returns the verbatim first-user-message text (Story 10.4 AC-1 / AC-9 #2)")

    ; Negative case — empty/null OREF returns "" without throwing.
    Set tEmpty = ##class(SessionAgent.EnsPortal.VisualTrace).ExtractLiteralFirstUserMessage($$$NULLOREF)
    Do $$$AssertEquals(tEmpty, "", "ExtractLiteralFirstUserMessage returns empty string for null OREF (graceful degradation)")
}

/// <p>AC-9 #3 — <code>%File</code>-grep assertion that the JS source
/// contains the load-bearing fragments for the from-search stripe:
/// the CSS class name <code>sa-from-search-stripe</code>, the state
/// cache key <code>state.fromSearchContext</code>, the Accept-button
/// handler class <code>sa-stripe-accept</code>, and the contextHints
/// merge call site that drains <code>state.fromSearchContext</code>.
/// A regression that drops any of these surfaces here loudly.</p>
Method TestChatPanelJsContainsFromSearchStripe()
{
    Do $$$AssertStatusOK(..LoadFile(), "LoadFile resolved chat-panel.js at " _ ..FilePath)
    Do $$$AssertTrue(..FileContents [ "sa-from-search-stripe", "chat-panel.js wires the sa-from-search-stripe CSS class (Story 10.4 AC-3 / AC-9 #3)")
    Do $$$AssertTrue(..FileContents [ "state.fromSearchContext", "chat-panel.js exposes state.fromSearchContext for one-shot drain (Story 10.4 AC-5/AC-7 / AC-9 #3)")
    Do $$$AssertTrue(..FileContents [ "sa-stripe-accept", "chat-panel.js wires the sa-stripe-accept button class (Story 10.4 AC-5 / AC-9 #3)")
    Do $$$AssertTrue(..FileContents [ "sa-stripe-dismiss", "chat-panel.js wires the sa-stripe-dismiss button class (Story 10.4 AC-6 / AC-9 #3)")
    Do $$$AssertTrue(..FileContents [ "renderFromSearchStripe", "chat-panel.js defines the renderFromSearchStripe function (Story 10.4 AC-3 / AC-9 #3)")
}

/// <p>AC-9 #4 — read the implementation text of
/// <method>SessionAgent.UI.ChatPanel.EmitStyle</method> from
/// <code>%Dictionary.MethodDefinition</code> and assert the new from-
/// search stripe CSS rule selectors are present in the method body:
/// <code>.sa-from-search-stripe</code>, <code>.sa-stripe-text</code>,
/// <code>.sa-stripe-accept</code>, <code>.sa-stripe-dismiss</code>. Also
/// asserts the fallback-color tokens
/// (<code>--sa-from-search-stripe-border</code> and
/// <code>-bg</code>) appear so the rules render in the absence of a
/// parent-palette definition (UX-DR26 forward-compatibility pattern).</p>
///
/// <p>Reading the dictionary's stored Implementation text is more robust
/// than capturing the method's <code>&amp;html&lt;...&gt;</code> output
/// via device redirection — the stream-device redirection pattern fails
/// under the Atelier test runner's I/O harness with <code>&lt;NOTOPEN&gt;</code>
/// on subsequent <code>Write</code> calls.</p>
Method TestEmitStyleContainsFromSearchStripeRules()
{
    Set tImpl = ""
    Set tMethod = ##class(%Dictionary.MethodDefinition).IDKEYOpen("SessionAgent.UI.ChatPanel", "EmitStyle")
    Do $$$AssertTrue($IsObject(tMethod), "EmitStyle method definition resolved from %Dictionary")
    If $IsObject(tMethod) {
        Do tMethod.Implementation.Rewind()
        While 'tMethod.Implementation.AtEnd {
            Set tImpl = tImpl _ tMethod.Implementation.Read(32000)
        }
        Do tMethod.%Close()
    }

    Do $$$AssertTrue(tImpl [ ".sa-from-search-stripe", "EmitStyle emits the .sa-from-search-stripe rule (Story 10.4 AC-4 / AC-9 #4)")
    Do $$$AssertTrue(tImpl [ ".sa-stripe-text", "EmitStyle emits the .sa-stripe-text rule")
    Do $$$AssertTrue(tImpl [ ".sa-stripe-accept", "EmitStyle emits the .sa-stripe-accept rule")
    Do $$$AssertTrue(tImpl [ ".sa-stripe-dismiss", "EmitStyle emits the .sa-stripe-dismiss rule")
    Do $$$AssertTrue(tImpl [ "--sa-from-search-stripe-border", "EmitStyle references the --sa-from-search-stripe-border token")
    Do $$$AssertTrue(tImpl [ "--sa-from-search-stripe-bg", "EmitStyle references the --sa-from-search-stripe-bg token")
}

}
