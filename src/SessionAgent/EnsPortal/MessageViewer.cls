/// <p>Search-agent host page — subclass of <CLASS>EnsPortal.MessageViewer</CLASS>
/// that adds an "Ask the agent" tab right-appended to the parent's tab
/// strip. Clicking the tab opens the chat panel scoped to the
/// <code>message-search</code> Search Agent, pre-populated with the
/// operator's prior conversation (if any) per UX-DR15 (cross-page
/// affordance parity with the Inspection Agent host page in
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>).</p>
///
/// <p><b>Tab strip strategy — copy-and-extend from grandparent.</b>
/// <code>EnsPortal.MessageViewer</code> does NOT define its own tab
/// strip XData; the tab strip lives in the grandparent
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>'s
/// <code>XData detailsPane</code> (a <code>&lt;tabGroup
/// id="detailsTabGroup"&gt;</code> with FOUR children: <code>headerDetails</code>,
/// <code>bodyDetails</code>, <code>bodyContents</code>, <code>traceContent</code>).
/// We re-state the grandparent's four tabs verbatim and append a new
/// <code>&lt;tab id="askAgentTab"&gt;</code> as the fifth child. The
/// trade-off: if InterSystems adds a new core tab in a future IRIS
/// release, we will not pick it up automatically — a version-pinning
/// concession we accept for MVP, mirroring the Story 3.3 precedent.</p>
///
/// <p><b>CSS / JS contribution mechanism.</b> Identical to Story 3.3.
/// We override <code>%OnDrawHTMLHead()</code> to call <code>##super()</code>
/// (preserves parent's contributions) then emit (a) the chat-panel CSS
/// via <CLASS>SessionAgent.UI.ChatPanel</CLASS>.<METHOD>EmitStyle</METHOD>
/// and (b) the <code>chat-panel.js</code> script tag served via the
/// per-namespace <code>/csp/&lt;ns&gt;/SessionAgent.UI.ChatPanelAsset.cls</code>
/// asset (Story 3.6).</p>
///
/// <p><b>ZenMethod hyperevent — <method>SendChatMessage</method>.</b> The
/// browser's chat-panel.js calls
/// <code>zenPage.SendChatMessage(agentName, sessionKey, userText, contextHintsJson)</code>.
/// Method signature is byte-for-byte identical to Story 3.3's so the
/// shared <code>chat-panel.js</code> works for both host pages without
/// per-page branching. The agent name is caller-supplied via
/// <code>pAgentName</code>; for this host, the browser passes
/// <code>"message-search"</code>.</p>
///
/// <p><b>Search session key (FR43).</b> Unlike the Inspection host page
/// (which uses <code>..sessionId</code> — the Ens session id from the
/// parent's URL parameter), the Search Agent's session key is a
/// registry-issued GUID generated in <method>DrawChatPanel</method> on
/// first tab open and persisted in
/// <code>%session.Data("SessionAgentMessageSearchKey")</code> for
/// stability across page interactions in the same browser session.
/// Subsequent tab opens re-use the GUID (returning-conversation
/// surfacing per AC-4).</p>
///
/// <p><b>MPP5646 trap workaround.</b> Per
/// <code>.claude/rules/iris-objectscript-basics.md</code> §"Parameter
/// PAGENAME MPP5646 Trap": setting <code>Parameter PAGENAME = "..."</code>
/// directly compile-fails with <code>&lt;PROTECT&gt; ^IRIS.Msg</code>
/// under non-ENSLIB-privileged build context (the parent's DOMAIN
/// triggers <code>$$$Text(..#PAGENAME)</code> codegen at compile time
/// which writes into <code>^IRIS.Msg("Ensemble",...)</code>). We leave
/// <code>PAGENAME = ""</code> and override <code>%OnGetPageName()</code>
/// at runtime to supply the page name without triggering the
/// compile-time codegen.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 10.1</a> — AC source.</li>
/// <li><CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> — Inspection-
/// agent parallel host page (Story 3.3); copy-source for the methods on
/// this class.</li>
/// <li><CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS> —
/// shared chat panel HTML emitter (Story 3.1).</li>
/// <li><CLASS>SessionAgent.UI.ChatPanel</CLASS> — chat-panel CSS
/// emitter (Story 3.1).</li>
/// <li><CLASS>SessionAgent.Chat.History</CLASS> — prior-conversation
/// row (Story 2.6).</li>
/// <li><CLASS>SessionAgent.Agent.AgentLoop</CLASS> — turn orchestrator
/// (Story 2.12, Story 9.4 vocabulary digest first-turn injection).</li>
/// <li><a href="../../../irislib/EnsPortal/Template/filteredViewer.cls">irislib/EnsPortal/Template/filteredViewer.cls</a>
/// lines 298-321 — grandparent <code>XData detailsPane</code>
/// structure verified via Task 0 probe.</li>
/// </ul>
Class SessionAgent.EnsPortal.MessageViewer Extends EnsPortal.MessageViewer [ System = 4 ]
{

/// <p>MPP5646 workaround: leave PAGENAME blank to suppress the
/// <code>$$$Text(..#PAGENAME)</code> compile-time codegen path which
/// raises <code>&lt;PROTECT&gt;</code> on <code>^IRIS.Msg("Ensemble",...)</code>
/// under non-ENSLIB-privileged build context. Resolve the page name at
/// runtime via <method>%OnGetPageName</method> instead.</p>
Parameter PAGENAME = "";

/// <p>Runtime page-name resolution — supplies the browser tab title
/// without triggering the parent's compile-time
/// <code>$$$Text(..#PAGENAME)</code> codegen path.</p>
Method %OnGetPageName() As %String
{
    Quit "Message Viewer + Search Agent"
}

/// <p>Override the grandparent's tab strip
/// (<code>EnsPortal.Template.filteredViewer:XData detailsPane</code>) —
/// re-state the four parent tabs verbatim and append our "Ask the
/// agent" tab as the fifth child. Strategy documented in the class
/// doc-comment (copy-and-extend; Zen has no XData merge semantic).</p>
///
/// <p>The new <code>&lt;tab id="askAgentTab"&gt;</code> hosts a single
/// <code>&lt;html&gt;</code> Zen component whose <code>OnDrawContent</code>
/// callback dispatches to <method>DrawChatPanel</method> on this class.
/// The seed is unused in MVP — first-time vs returning is decided
/// server-side by <method>DrawChatPanel</method> itself.</p>
XData detailsPane [ XMLNamespace = "http://www.intersystems.com/zen" ]
{
<pane>
<tabGroup id="detailsTabGroup" showTabBar="true" remember="true" onshowTab="zenPage.onTabChange();" >
<tab id="headerDetails" caption="Header" title="Message Header Properties">
<html id="detailsContent" OnDrawContent="DrawDetailsContent" />
</tab>
<tab id="bodyDetails" caption="Body" title="Message Body Properties">
<html id="bodyInfo" OnDrawContent="DrawBodyInfo" />
</tab>
<tab id="bodyContents" caption="Contents" title="Message Body Contents">
<html id="fullContent" containerStyle="padding-top: 5px; padding-bottom: 5px;" OnDrawContent="DrawFullContentLinks" />
<iframe id="contentFrame" frameBorder="false"/>
</tab>
<tab id="traceContent" caption="Trace" title="Message Trace">
<html id="traceLink" enclosingStyle="padding: 5px;" >
<a class="ribbonSortOption fullMessage" href="#" onclick="zenPage.showTrace(zenPage.selectedId); return false;" title="#(%page.msgViewTraceHover)#">#(%page.msgViewTrace)#</a>
<span id="traceTruncated" class="fullMessage" style="padding-left:10px; font-weight: bold;"></span>
</html>
<pane id="svgTracePane" paneName="svgTracePane" />
</tab>
<!-- Caption/title set at runtime in %OnAfterCreatePage to avoid
     compile-time MPP5646 lookup against the Ensemble message catalog
     (the parent's DOMAIN="Ensemble" causes Zen to %macroText custom
     captions, which raises <PROTECT> when inserting new strings into
     ^IRIS.Msg("Ensemble",...) from a non-ENSLIB build context). The
     runtime path uses the inherited %ZEN.Component.tab.caption setter
     which does NOT trigger the catalog write. -->
<tab id="askAgentTab">
<html id="chatPanelHost" OnDrawContent="DrawChatPanel" />
</tab>
</tabGroup>
</pane>
}

/// <p>Override the parent's <code>%OnAfterCreatePage</code> — calls
/// <code>##super()</code> first (preserves any parent setup), then sets
/// the caption + title on our new <code>askAgentTab</code> at runtime.
/// The XData declaration omits these attributes (see XData detailsPane
/// comment) to avoid the compile-time MPP5646 / <code>&lt;PROTECT&gt;</code>
/// error.</p>
Method %OnAfterCreatePage() As %Status
{
    Set tSC = ##super()
    If $$$ISERR(tSC) Quit tSC

    Set tTab = ..%GetComponentById("askAgentTab")
    If $IsObject(tTab) {
        Set tTab.caption = "Ask the agent"
        Set tTab.title = "Ask the SessionAgent for help finding sessions across this IRIS instance"
    }
    Quit $$$OK
}

/// <p>Zen <code>OnDrawContent</code> callback for the
/// <code>&lt;tab id="askAgentTab"&gt;</code>. Generates-or-reuses the
/// search-session GUID per AC-3, reads the operator's prior chat
/// history (Story 2.6), and dispatches to
/// <CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS>.<METHOD>DrawChatPanel</METHOD>
/// with the right parameters (first-time empty transcript +
/// "Ask anything..." placeholder OR returning-conversation transcript +
/// "Continue the search." placeholder).</p>
///
/// <p>The <code>%session.Data("SessionAgentMessageSearchKey")</code>
/// slot is the per-CSP-session GUID. On first chat-tab open within a
/// browser session we create the GUID; subsequent visits re-use it
/// (returning-conversation surfacing). The "New search" affordance
/// (clearing the slot) is deferred to Story 10.2.</p>
///
/// <p>The <code>%session.Username</code> read happens here, at the
/// page-render boundary. The chat-history lookup uses
/// <code>ConvKeyIdxOpen</code> (concurrency=0 — lock-free read) rather
/// than <method>SessionAgent.Chat.History.LoadOrCreate</method> because
/// we MUST NOT acquire the per-row lock during page render (the lock
/// is acquired later by <method>SendChatMessage</method> when the
/// operator sends their first turn).</p>
///
/// <p>Returns <code>$$$OK</code> always — render failures degrade
/// gracefully (the ChatPanelDrawHelper still emits the empty shell so
/// the operator can submit a turn even if the prior-history lookup
/// failed). The <code>pSeed</code> parameter is unused in MVP.</p>
Method DrawChatPanel(pSeed As %String) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tAgentName = "message-search"

        ; Generate-or-reuse the search-session GUID. Per AC-3, persist in
        ; %session.Data so it stays stable across tab opens in the same
        ; browser session.
        Set tSessionKey = ""
        If $IsObject($Get(%session)) {
            Set tSessionKey = %session.Data("SessionAgentMessageSearchKey")
            If tSessionKey = "" {
                Set tSessionKey = $System.Util.CreateGUID()
                Set %session.Data("SessionAgentMessageSearchKey") = tSessionKey
            }
        }
        If tSessionKey = "" {
            ; Defense-in-depth — test harness without %session attached.
            Set tSessionKey = "test-" _ $Job
        }

        Set tPortalUser = ""
        If $IsObject($Get(%session)) {
            Set tPortalUser = %session.Username
        }
        If tPortalUser = "" {
            ; Defense-in-depth: even with no portal session attached
            ; (e.g., test harness fixture), still render the panel shell
            ; so the operator sees a valid tab. The chat history lookup
            ; below will short-circuit to first-time-empty.
            Set tPortalUser = $Username
        }

        ; ─────────────────────────────────────────────────────────────
        ; Story 3.5 AC-1 / AC-4 — no-config detection. Pre-flight SQL
        ; against SessionAgent_Config.Agent. If no row OR Enabled=0,
        ; emit the config-empty prompt instead of the chat shell. The
        ; admin probe uses $System.Security.Check("%All", "U").
        ; ─────────────────────────────────────────────────────────────
        Set tConfigRow = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
        If '$IsObject(tConfigRow) || (tConfigRow.Enabled = 0) {
            Set tIsAdmin = $System.Security.Check("%All", "U")
            Set tEmptySC = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).EmitConfigEmpty(tAgentName, tIsAdmin)
            If $$$ISERR(tEmptySC) {
                Set tSC = tEmptySC
            }
            ; Release the OREF if we opened one (disabled-row path).
            If $IsObject(tConfigRow) Do tConfigRow.%Close()
            Quit
        }
        Do tConfigRow.%Close()

        ; Lookup prior history (lock-free). The ConvKeyIdxOpen helper
        ; is auto-generated by the dictionary from the unique
        ; ConvKeyIdx index on Chat.History.
        Set tPriorJson = "[]"
        Set tPlaceholder = "Ask anything across this IRIS instance."
        If (tSessionKey '= "") && (tPortalUser '= "") {
            Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(tAgentName, tSessionKey, tPortalUser, 0)
            If $IsObject(tHist) {
                ; Returning conversation — flatten the canonical-Anthropic
                ; turns into the simple chat-shape the JS init expects.
                Set tPriorJson = ..FlattenTurnsForBootstrap(tHist)
                ; Non-empty array means returning-variant placeholder.
                If tPriorJson '= "[]" {
                    Set tPlaceholder = "Continue the search."
                }
                Do tHist.%Close()
            }
        }

        ; Dispatch to the shared helper. It writes to the current device
        ; via &html<...> (the Zen OnDrawContent callback's output goes to
        ; the page response).
        Set tHelperSC = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel(tAgentName, tSessionKey, tPortalUser, "", tPriorJson, tPlaceholder)
        If $$$ISERR(tHelperSC) {
            ; Helper-level error is unexpected (only invariant: empty
            ; agent name, which we hard-code). Capture without raising
            ; so the page still loads — operator sees an empty shell.
            Set tSC = tHelperSC
        }
    }
    Catch ex {
        ; Never let a render error escape — page must load. The chat
        ; tab will be empty/broken but the parent Message Viewer
        ; functionality remains intact (AC-5).
        Set tSC = ex.AsStatus()
    }
    ; Always return OK — the parent Zen renderer doesn't surface
    ; OnDrawContent failures to the operator usefully.
    Quit $$$OK
}

/// <p>Internal helper — flatten the canonical-Anthropic
/// <CLASS>SessionAgent.Chat.History</CLASS>.<property>TurnsJson</property>
/// stream into the simplified chat-shape the JS init expects:
/// <code>[{role:"operator|agent", content:"plain-text-or-markdown"}]</code>.
/// Verbatim copy from <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>
/// per Story 10.1 spec §"Patterns to follow verbatim".</p>
///
/// <p>Mapping rules:</p>
/// <ul>
/// <li>Anthropic <code>"user"</code> turns with <code>type:"text"</code>
/// blocks → <code>{role:"operator", content:&lt;text&gt;}</code>.</li>
/// <li>Anthropic <code>"assistant"</code> turns with
/// <code>type:"text"</code> blocks → <code>{role:"agent",
/// content:&lt;text&gt;}</code>. Multiple text blocks are concatenated.</li>
/// <li>Anthropic <code>"user"</code> turns with only
/// <code>type:"tool_result"</code> blocks → SKIPPED (operator never
/// typed them).</li>
/// <li>Anthropic <code>"assistant"</code> turns with only
/// <code>type:"tool_use"</code> blocks (no text) → SKIPPED.</li>
/// </ul>
///
/// <p>Returns the JSON-serialized array. On any failure, returns
/// <code>"[]"</code> so the panel still renders the welcome message.</p>
ClassMethod FlattenTurnsForBootstrap(pHist As SessionAgent.Chat.History) As %String
{
    Set tFlat = ##class(%DynamicArray).%New()
    Try {
        If '$IsObject(pHist) Quit
        If '$IsObject(pHist.TurnsJson) Quit
        Do pHist.TurnsJson.Rewind()
        If pHist.TurnsJson.AtEnd Quit
        Set tBuf = ""
        While 'pHist.TurnsJson.AtEnd {
            Set tBuf = tBuf _ pHist.TurnsJson.Read(32000)
        }
        If tBuf = "" Quit

        Set tArr = ##class(%DynamicArray).%FromJSON(tBuf)
        If '$IsObject(tArr) Quit

        ; Iterate canonical turns and produce flat ones.
        Set tIter = tArr.%GetIterator()
        While tIter.%GetNext(.tIdx, .tTurn) {
            If '$IsObject(tTurn) Continue
            Set tRole = tTurn.%Get("role")
            Set tContent = tTurn.%Get("content")
            If '$IsObject(tContent) Continue

            ; Concatenate every type:"text" block's text. Skip
            ; tool_use / tool_result blocks (no surfacing in MVP).
            Set tText = ""
            Set tBlockIter = tContent.%GetIterator()
            While tBlockIter.%GetNext(.tBidx, .tBlock) {
                If '$IsObject(tBlock) Continue
                If tBlock.%Get("type") '= "text" Continue
                Set tText = tText _ tBlock.%Get("text")
            }

            ; If no text content (pure tool_use/result turn), skip.
            If tText = "" Continue

            Set tFlatTurn = ##class(%DynamicObject).%New()
            ; Map canonical roles to chat-form roles.
            If tRole = "user" {
                Do tFlatTurn.%Set("role", "operator")
            } ElseIf tRole = "assistant" {
                Do tFlatTurn.%Set("role", "agent")
            } Else {
                ; Unknown role — pass through verbatim.
                Do tFlatTurn.%Set("role", tRole)
            }
            Do tFlatTurn.%Set("content", tText)
            Do tFlat.%Push(tFlatTurn)
        }
    }
    Catch ex {
        ; Swallow — fall through to the empty-array degradation.
        Set tFlat = ##class(%DynamicArray).%New()
    }
    Quit tFlat.%ToJSON()
}

/// <p>Override the parent's <code>%OnDrawHTMLHead</code> head-contribution
/// callback. Calls <code>##super()</code> first (preserves parent's
/// styling), then emits (a) the chat-panel CSS via
/// <CLASS>SessionAgent.UI.ChatPanel</CLASS>.<METHOD>EmitStyle</METHOD>
/// and (b) the <code>chat-panel.js</code> include served via the
/// per-namespace <code>/csp/&lt;ns&gt;/SessionAgent.UI.ChatPanelAsset.cls</code>
/// asset (Story 3.6). The URL is built dynamically from
/// <code>$NAMESPACE</code> so the same page works on any namespace
/// where the <code>SessionAgent.PKG</code> resource is mapped.</p>
///
/// <p>Verbatim copy from <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>
/// per Story 10.1 spec §"Patterns to follow verbatim".</p>
Method %OnDrawHTMLHead() As %Status
{
    Set tSC = ##super()
    If $$$ISERR(tSC) Quit tSC

    ; Emit chat-panel CSS via the shared style emitter (Story 3.1).
    Set tStyleSC = ##class(SessionAgent.UI.ChatPanel).EmitStyle()
    If $$$ISERR(tStyleSC) Quit tStyleSC

    ; Emit the chat-panel.js include. URL derives from $NAMESPACE so the
    ; same script tag works on every namespace mapped to SessionAgent.PKG.
    Set tNSLower = $ZCONVERT($NAMESPACE, "L")
    Write "<script type=""text/javascript"" src=""/csp/" _ tNSLower _ "/SessionAgent.UI.ChatPanelAsset.cls""></script>", !

    Quit $$$OK
}

/// <p>ZenMethod hyperevent — invoked by chat-panel.js's
/// <code>zenPage.SendChatMessage(...)</code> call. Resolves the caller
/// context at the trust boundary (<code>%session.Username</code>),
/// invokes <method>SessionAgent.Agent.AgentLoop.RunTurn</method>, and
/// returns the <CLASS>SessionAgent.Agent.TurnResult</CLASS>'s
/// <method>ToJson</method> envelope for client-side parsing.</p>
///
/// <p><b>Never-throw contract (FR37 / UX-DR18).</b> Any exception
/// converts to a structured error envelope:
/// <code>{"error":{"kind":"internal","message":"..."}}</code>.</p>
///
/// <p><b>Verbatim copy</b> from
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> per Story 10.1
/// spec §"Patterns to follow verbatim". The agent name is caller-
/// supplied via <code>pAgentName</code>, so the body is agent-name-
/// agnostic and identical between Inspection and Search hosts.</p>
ClassMethod SendChatMessage(pAgentName As %String, pSessionKey As %String, pUserText As %String, pContextHintsJson As %String) As %String [ ZenMethod ]
{
    Set tEnvelope = ""
    Try {
        ; Boundary resolution per architecture §"Caller context propagation".
        ; %session.Username is the only Zen-side context fetch — never inside
        ; a tool, never inside AgentLoop.
        Set tPortalUser = ""
        If $IsObject($Get(%session)) {
            Set tPortalUser = %session.Username
        }
        If tPortalUser = "" {
            Set tPortalUser = $Username
        }

        ; Parse pContextHintsJson string into a %DynamicObject for
        ; RunTurn. On parse failure, populate tEnvelope with the
        ; structured error envelope and skip RunTurn.
        Set tHints = ##class(%DynamicObject).%New()
        Set tParseFailed = 0
        If pContextHintsJson '= "" {
            Try {
                Set tParsed = ##class(%DynamicObject).%FromJSON(pContextHintsJson)
                If $IsObject(tParsed) {
                    Set tHints = tParsed
                }
            }
            Catch parseEx {
                Set tParseFailed = 1
                Set tErr = ##class(%DynamicObject).%New()
                Set tErrInner = ##class(%DynamicObject).%New()
                Do tErrInner.%Set("kind", "internal")
                Do tErrInner.%Set("message", "Internal error — see audit log")
                Do tErr.%Set("error", tErrInner)
                Set tEnvelope = tErr.%ToJSON()

                ; Best-effort audit row. ChatHistoryId is empty (no row
                ; was created); the row still lands so operators can
                ; correlate with the chat-panel error block.
                Try {
                    Do ##class(SessionAgent.Audit.Emit).LogLlmCall("", "session-agent", "n/a", 0, 0, 0, 0, "error", 0, 1, "SendChatMessage: malformed pContextHintsJson — " _ parseEx.DisplayString())
                }
                Catch auditEx {
                    ; Swallow — never-throw is the higher invariant.
                }
            }
        }

        ; If hints parsing failed, tEnvelope is already populated with
        ; the error JSON — skip RunTurn (the malformed-input path is
        ; terminal).
        If tParseFailed Quit

        ; Invoke RunTurn — the orchestrator constructs the CallerContext
        ; from these args internally. Never throws (FR37).
        Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn(pAgentName, pSessionKey, tPortalUser, pUserText, tHints)
        If '$IsObject(tResult) {
            ; Defense in depth — RunTurn's contract returns a TurnResult
            ; on every code path, but if a regression broke that we
            ; surface a structured envelope rather than a Zen TypeError.
            Set tErr = ##class(%DynamicObject).%New()
            Set tErrInner = ##class(%DynamicObject).%New()
            Do tErrInner.%Set("kind", "internal")
            Do tErrInner.%Set("message", "Internal error — see audit log")
            Do tErr.%Set("error", tErrInner)
            Set tEnvelope = tErr.%ToJSON()
            Quit
        }

        ; Happy path — serialize the TurnResult envelope verbatim.
        Set tEnvelope = tResult.ToJson()
    }
    Catch ex {
        ; Never-throw contract — convert to structured error envelope.
        ; Story 10.5 AC-2: detect IRIS lock-fail (error code 5803,
        ; $$$LockFailedToAcquireExclusive — verified Task 0; the spec-named
        ; $$$ERRORLOCKFAILED macro itself does not exist in this IRIS
        ; distro) and surface a distinct error.kind = "lock_held" so
        ; chat-panel.js renders the concurrent-tab banner via the AC-5
        ; path. Verbatim copy from VisualTrace per the AC-2 same-body
        ; contract.
        Set tKind = "internal"
        Set tMessage = "Internal error — see audit log"
        ; Story 10.5 review fix-now (F-1): comma-boundary-anchored 5803
        ; match — see VisualTrace.IsChatHistoryLocked for rationale.
        If ("," _ $SYSTEM.Status.GetErrorCodes(ex.AsStatus()) _ ",") [ ",5803," {
            Set tKind = "lock_held"
            Set tMessage = "Another browser tab is mid-conversation with this agent."
        }
        Set tErr = ##class(%DynamicObject).%New()
        Set tErrInner = ##class(%DynamicObject).%New()
        Do tErrInner.%Set("kind", tKind)
        Do tErrInner.%Set("message", tMessage)
        Do tErr.%Set("error", tErrInner)
        Set tEnvelope = tErr.%ToJSON()

        ; Best-effort audit row capturing the full exception for ops.
        Try {
            Do ##class(SessionAgent.Audit.Emit).LogLlmCall("", "session-agent", "n/a", 0, 0, 0, 0, "error", 0, 1, "SendChatMessage exception: " _ ex.DisplayString())
        }
        Catch auditEx {
            ; Swallow — never-throw is the higher invariant.
        }
    }
    Quit tEnvelope
}

/// <p>Story 10.5 AC-1 — server-side lock probe. Invoked by
/// <code>chat-panel.js</code>'s <code>checkLockState()</code> at chat-
/// panel-open AND every ~2 seconds while the banner is visible. Returns
/// a JSON envelope <code>{"locked": true|false}</code> describing whether
/// another process currently holds the
/// <CLASS>SessionAgent.Chat.History</CLASS> exclusive lock for the
/// <code>(pAgentName, pSessionKey, %session.Username)</code> tuple.</p>
///
/// <p>Verbatim copy from
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> — same body, same
/// signature, so the shared <code>chat-panel.js</code> works for both
/// host pages. See VisualTrace's IsChatHistoryLocked doc-comment for the
/// full semantics + Task 0 finding (lock-fail error code is 5803,
/// not the spec-named <code>$$$ERRORLOCKFAILED</code> macro which does
/// not exist in this IRIS distro).</p>
ClassMethod IsChatHistoryLocked(pAgentName As %String, pSessionKey As %String) As %String [ ZenMethod ]
{
    Set tEnvelope = ""
    Try {
        Set tPortalUser = ""
        If $IsObject($Get(%session)) {
            Set tPortalUser = %session.Username
        }
        If tPortalUser = "" {
            Set tPortalUser = $Username
        }

        ; Probe lock state without holding. See VisualTrace for semantics.
        Set tSC = $$$OK
        Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(pAgentName, pSessionKey, tPortalUser, 4, .tSC)
        ; Story 10.5 review fix-now (F-1): comma-boundary-anchored 5803
        ; match — see VisualTrace.IsChatHistoryLocked for rationale.
        If '$IsObject(tHist) && ($$$ISERR(tSC)) && (("," _ $SYSTEM.Status.GetErrorCodes(tSC) _ ",") [ ",5803,") {
            Set tEnvelope = "{""locked"": true}"
            Quit
        }
        If $IsObject(tHist) {
            Do tHist.%Close()
        }
        Set tEnvelope = "{""locked"": false}"
    }
    Catch ex {
        Set tEnvelope = "{""locked"": false, ""probe_error"": " _ ##class(%DynamicObject).%New().%Set("text", ex.DisplayString()).%ToJSON() _ "}"
    }
    Quit tEnvelope
}

/// <p>Story 10.3 AC-1 — ZenMethod hyperevent wrapper for click-through
/// vocabulary capture. The browser-side <code>onSearchResultClick</code>
/// handler in <code>chat-panel.js</code> calls
/// <code>zenPage.RecordClickThrough(searchSessionKey, sessionId,
/// contributingToolCallsJson)</code> (3 args — Zen hyperevent boundary).
/// This wrapper resolves <code>%session.Username</code> at the trust
/// boundary and delegates to Story 9.5's 4-arg ClassMethod
/// <CLASS>SessionAgent.Search.VocabCapture</CLASS>.<METHOD>RecordClickThrough</METHOD>.</p>
///
/// <p><b>Boundary resolution.</b> Per architecture §"Caller context
/// propagation" — <code>%session.Username</code> is read here at the
/// public-surface boundary, never inside business logic. The substrate
/// ClassMethod accepts <var>pPortalUser</var> as a parameter and never
/// reads <code>%session</code> itself.</p>
///
/// <p><b>Never-throw contract.</b> The substrate ClassMethod has its own
/// <code>Try / Catch</code> and never throws (Story 9.5 AC); this wrapper
/// just delegates without adding its own guard. The return-shape passes
/// through verbatim from the inner ClassMethod (per Story 9.5's contract):
/// <code>{success: true, aliases_recorded: [...]}</code> happy-path OR
/// <code>{success: false, error: "..."}</code> error-path; either way,
/// fire-and-forget from the JS side per UX-DR25.</p>
ClassMethod RecordClickThrough(pSearchSessionKey As %String, pSessionId As %String, pContributingToolCallsJson As %String) As %String [ ZenMethod ]
{
    Set tPortalUser = ""
    If $IsObject($Get(%session)) {
        Set tPortalUser = %session.Username
    }
    If tPortalUser = "" {
        Set tPortalUser = $Username
    }
    Quit ##class(SessionAgent.Search.VocabCapture).RecordClickThrough(pSearchSessionKey, pSessionId, pContributingToolCallsJson, tPortalUser)
}

}
