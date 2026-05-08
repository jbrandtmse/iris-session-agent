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

/// <p>Story 12.5 (BUG-05) — comma-separated session IDs the operator
/// pulled from a Search-Agent tile list via the "Load N sessions into
/// table" button. When non-empty, <method>CreateResultSet</method>
/// wraps the parent's generated SQL with a
/// <code>WHERE Session IN (CSV)</code> sub-query restriction so the
/// central results table shows ONLY those sessions (with all the table's
/// existing sort / paginate / export affordances intact).</p>
///
/// <p><b>Storage shape — CSV not JSON.</b> Per Story 12.5 spec Dev Notes
/// §"Why semicolon-separated CSV (not JSON)": Zen
/// <code>%ZEN.Datatype.string</code> is a single line, no encoding
/// overhead. The button click hands JSON to
/// <method>ApplyAgentSessionFilter</method>, which converts to CSV at
/// the JS boundary; the server-side <method>CreateResultSet</method>
/// reads the CSV directly and emits <code>Session IN (CSV)</code>.</p>
///
/// <p><b>SQL injection guard.</b> The session IDs are integers from the
/// agent's tool result. <method>ApplyAgentSessionFilter</method>
/// validates at the JS boundary (<code>/^\d+(,\d+)*$/</code>) before
/// assigning to this property. <method>CreateResultSet</method>
/// re-validates server-side before SQL concatenation — never trust
/// input crossing a Zen boundary.</p>
Property agentSessionFilterIds As %ZEN.Datatype.string;

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
        ; browser session. NOTE: read via $Get(%session.Data(...)) — a
        ; bare `%session.Data("missing-key")` raises <UNDEFINED> rather
        ; than returning empty string. Story 10.10 surfaced this on the
        ; first-time render path; the prior form bypassed the
        ; "If tSessionKey = """ guard and propagated the exception to the
        ; outer Catch.
        Set tSessionKey = ""
        If $IsObject($Get(%session)) {
            Set tSessionKey = $Get(%session.Data("SessionAgentMessageSearchKey"))
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
/// <code>[{role:"operator|agent", content:"plain-text-or-markdown",
/// toolCalls?:[{id,name,args,result,status}]}]</code>.
/// Verbatim copy from <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS>
/// per Story 10.1 spec §"Patterns to follow verbatim".</p>
///
/// <p>Mapping rules (Story 12.6 — BUG-07 chat-history tile replay):</p>
/// <ul>
/// <li>Anthropic <code>"user"</code> turns with <code>type:"text"</code>
/// blocks → <code>{role:"operator", content:&lt;text&gt;}</code>.</li>
/// <li>Anthropic <code>"assistant"</code> turns → <code>{role:"agent",
/// content:&lt;text&gt;, toolCalls?:[...]}</code>. Multiple text blocks
/// are concatenated. <code>type:"tool_use"</code> blocks are collected
/// into the <code>toolCalls</code> array as
/// <code>{id, name, args:&lt;input&gt;}</code> entries. A pure-tool_use
/// assistant turn (no text) still emits an entry with empty
/// <code>content</code> so the JS replay path can re-render the
/// tool-call tiles.</li>
/// <li>Anthropic <code>"user"</code> turns containing
/// <code>type:"tool_result"</code> blocks → each tool_result is paired
/// with its matching tool_use via <code>tool_use_id</code> and merged
/// into the prior assistant entry's <code>toolCalls[i].result</code>
/// (parsed JSON object) + <code>toolCalls[i].status</code>
/// (<code>"error"</code> if <code>is_error=true</code> else
/// <code>"ok"</code>). If the user turn ALSO has text blocks, an
/// <code>operator</code> entry is emitted in addition. A pure-
/// tool_result user turn does NOT emit a new entry.</li>
/// </ul>
///
/// <p>Backward compatible — pre-Story-12.6 consumers receive
/// <code>{role, content}</code> verbatim; the optional
/// <code>toolCalls</code> field is ignored when absent.</p>
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

        ; Story 12.6 — pairing-state for tool_use ↔ tool_result merge.
        ; tToolCallIndex maps canonical tool_use_id → "<flatEntryIdx>|<toolCallIdx>"
        ; for every tool_use emitted by the most-recent assistant turn.
        ; Walking the next user turn's tool_result blocks merges back
        ; into the prior assistant entry via this map.
        Set tToolCallIndex = ##class(%DynamicObject).%New()

        ; Iterate canonical turns and produce flat ones.
        Set tIter = tArr.%GetIterator()
        While tIter.%GetNext(.tIdx, .tTurn) {
            If '$IsObject(tTurn) Continue
            Set tRole = tTurn.%Get("role")
            Set tContent = tTurn.%Get("content")
            If '$IsObject(tContent) Continue

            ; Walk this turn's content blocks once, partitioning into
            ; (a) concatenated text and (b) collected tool_use /
            ; tool_result blocks for separate handling below.
            Set tText = ""
            Set tToolUses = ##class(%DynamicArray).%New()
            Set tToolResults = ##class(%DynamicArray).%New()
            Set tBlockIter = tContent.%GetIterator()
            While tBlockIter.%GetNext(.tBidx, .tBlock) {
                If '$IsObject(tBlock) Continue
                Set tBlockType = tBlock.%Get("type")
                If tBlockType = "text" {
                    Set tText = tText _ tBlock.%Get("text")
                } ElseIf tBlockType = "tool_use" {
                    Do tToolUses.%Push(tBlock)
                } ElseIf tBlockType = "tool_result" {
                    Do tToolResults.%Push(tBlock)
                }
            }

            ; ── Assistant turn — emit ONE entry combining text + toolCalls.
            If tRole = "assistant" {
                ; Reset tool-call pairing map for THIS turn's tool_use ids.
                Set tToolCallIndex = ##class(%DynamicObject).%New()

                Set tHasToolUses = (tToolUses.%Size() > 0)
                If (tText = "") && ('tHasToolUses) Continue

                Set tFlatTurn = ##class(%DynamicObject).%New()
                Do tFlatTurn.%Set("role", "agent")
                Do tFlatTurn.%Set("content", tText)

                If tHasToolUses {
                    Set tToolCallsArr = ##class(%DynamicArray).%New()
                    Set tTuIter = tToolUses.%GetIterator()
                    While tTuIter.%GetNext(.tTuIdx, .tTu) {
                        Set tCall = ##class(%DynamicObject).%New()
                        Set tTuId = tTu.%Get("id")
                        Do tCall.%Set("id", tTuId)
                        Do tCall.%Set("name", tTu.%Get("name"))
                        ; Pass tool_use.input through as `args` to match the
                        ; live envelope's toolCallsRendered[].args field.
                        Do tCall.%Set("args", tTu.%Get("input"))
                        Do tToolCallsArr.%Push(tCall)
                        ; Record (flatIdx, toolCallIdx) for tool_result merge.
                        If tTuId '= "" {
                            Do tToolCallIndex.%Set(tTuId, tFlat.%Size() _ "|" _ (tToolCallsArr.%Size() - 1))
                        }
                    }
                    Do tFlatTurn.%Set("toolCalls", tToolCallsArr)
                }
                Do tFlat.%Push(tFlatTurn)
                Continue
            }

            ; ── User turn — merge any tool_result blocks into the prior
            ; assistant entry via the pairing map; emit an operator entry
            ; for any text content.
            If tRole = "user" {
                ; Merge tool_result blocks into prior assistant entry's
                ; toolCalls[].result / .status fields.
                Set tTrIter = tToolResults.%GetIterator()
                While tTrIter.%GetNext(.tTrIdx, .tTr) {
                    Set tUseId = tTr.%Get("tool_use_id")
                    If tUseId = "" Continue
                    Set tCoord = tToolCallIndex.%Get(tUseId)
                    If tCoord = "" Continue
                    Set tFlatIdx = +$Piece(tCoord, "|", 1)
                    Set tCallIdx = +$Piece(tCoord, "|", 2)
                    If (tFlatIdx >= tFlat.%Size()) Continue
                    Set tPriorEntry = tFlat.%Get(tFlatIdx)
                    If '$IsObject(tPriorEntry) Continue
                    Set tPriorCalls = tPriorEntry.%Get("toolCalls")
                    If '$IsObject(tPriorCalls) Continue
                    If (tCallIdx >= tPriorCalls.%Size()) Continue
                    Set tPriorCall = tPriorCalls.%Get(tCallIdx)
                    If '$IsObject(tPriorCall) Continue

                    ; tool_result.content is typically a JSON-serialized
                    ; string (canonical-MCP tool envelope shape:
                    ; {content:[...], structuredContent:{...}}). Parse to
                    ; an object so the JS path can read .structuredContent
                    ; without a re-parse. Defensive on parse failure —
                    ; keep raw string.
                    Set tRawResult = tTr.%Get("content")
                    Set tParsedResult = ""
                    If $IsObject(tRawResult) {
                        Set tParsedResult = tRawResult
                    } ElseIf tRawResult '= "" {
                        Try {
                            Set tParsedResult = ##class(%DynamicAbstractObject).%FromJSON(tRawResult)
                        } Catch tParseEx {
                            Set tParsedResult = tRawResult
                        }
                    }
                    Do tPriorCall.%Set("result", tParsedResult)
                    Set tIsError = tTr.%Get("is_error")
                    If tIsError {
                        Do tPriorCall.%Set("status", "error")
                    } Else {
                        Do tPriorCall.%Set("status", "ok")
                    }
                }

                ; Emit the operator entry only if the user turn has text.
                If tText '= "" {
                    Set tFlatTurn = ##class(%DynamicObject).%New()
                    Do tFlatTurn.%Set("role", "operator")
                    Do tFlatTurn.%Set("content", tText)
                    Do tFlat.%Push(tFlatTurn)
                    ; Operator turn ends a tool-pairing window.
                    Set tToolCallIndex = ##class(%DynamicObject).%New()
                }
                Continue
            }

            ; Unknown role — preserve text-only fallback as before.
            If tText = "" Continue
            Set tFlatTurn = ##class(%DynamicObject).%New()
            Do tFlatTurn.%Set("role", tRole)
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

    ; URL prefix derives from $NAMESPACE so the same page works on every
    ; namespace mapped to SessionAgent.PKG.
    Set tNSLower = $ZCONVERT($NAMESPACE, "L")
    Set tStaticBase = "/csp/" _ tNSLower _ "/sa-static/"

    ; Story 10.7 — vendored Markdown bundle (verbatim mirror of
    ; SessionAgent.EnsPortal.VisualTrace per Story 10.1's "Patterns to
    ; follow verbatim"). Emit in dependency order so the JS pipeline
    ; (marked → DOMPurify → Prism) is available at chat-panel.js
    ; execution time.
    Write "<link rel=""stylesheet"" type=""text/css"" href=""", tStaticBase, "prism.min.css"" />", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "marked.min.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism.min.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-clike.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-csharp.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-markup.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-sql.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-javascript.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-json.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-objectscript.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "prism-hl7.js""></script>", !
    Write "<script type=""text/javascript"" src=""", tStaticBase, "dompurify.min.js""></script>", !

    ; Emit the chat-panel.js include. URL derives from $NAMESPACE so the
    ; same script tag works on every namespace mapped to SessionAgent.PKG.
    Write "<script type=""text/javascript"" src=""/csp/", tNSLower, "/SessionAgent.UI.ChatPanelAsset.cls""></script>", !

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

/// <p>Story 10.10 hotfix — override the grandparent's
/// <code>onTabChange()</code> to skip the destructive
/// <code>refreshContents()</code> path for our 5th tab
/// (<code>askAgentTab</code>). The grandparent's
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>.<METHOD>onTabChange</METHOD>
/// has a hard <code>switch (currTab) { case 1..4: ...; default: break }</code>
/// that ignores tab indices &gt; 4 — our 5th tab never has its server-side
/// <code>OnDrawContent</code> callback fired on tab-click. The previous
/// (Story 10.10) implementation called
/// <code>chatHost.refreshContents()</code> in the override to "wake up"
/// the panel — but per the Story 10.13 walkthrough investigation, Zen
/// renders <code>OnDrawContent</code> at page-parse time anyway (the
/// panel HTML is already in the DOM when the page loads, just hidden
/// via the parent's tabGroup CSS). Calling
/// <code>refreshContents()</code> destructively REPLACES the panel HTML
/// — wiping the welcome message, the input field's bound event
/// listeners, and the IIFE-scoped chat-panel.js state. The fix:
/// short-circuit BEFORE the destructive refresh, leaving the
/// page-load-time-rendered panel intact.</p>
///
/// <p><b>Story 10.13 F-2 (release-blocker).</b> The pre-Story-10.13
/// override called <code>refreshContents()</code> on every tab-click
/// (gated only by a <code>_tabDisplay['Agent']==='__rendered__'</code>
/// sentinel). The sentinel guard worked correctly for repeated clicks
/// AFTER the first refresh, but the first-ever click ALWAYS hit the
/// destructive path — wiping the working DOM. Empirically verified via
/// chrome-devtools-mcp DOM probe: pre-first-click the transcript
/// contained the welcome message + had bound event listeners; post-
/// first-click the transcript was empty (refreshContents replaced the
/// HTML; chat-panel.js init() doesn't re-run, so the new transcript
/// has no welcome and the new input has no event listeners). The fix:
/// onTabChange is now a no-op for the Agent tab — Zen's lazy-render
/// already drew the panel HTML at page load, and the IIFE's init()
/// already bound all events. There is no "refresh" we need; we just
/// need to NOT destroy what's working.</p>
ClientMethod onTabChange() [ Language = javascript ]
{
    // Always invoke the parent's onTabChange first so tabs 1-4 (Header /
    // Body / Contents / Trace) keep their existing refresh semantics.
    this.invokeSuper('onTabChange', arguments);

    // Tab 5 (askAgentTab) is the gap the parent's switch leaves uncovered —
    // BUT we no longer need to fill it. Per Story 10.13 F-2 investigation:
    // Zen renders the askAgentTab's <html OnDrawContent="DrawChatPanel"/>
    // at page-parse time (eager render); the chat-panel.js IIFE binds
    // events at DOMContentLoaded. The previous Story 10.10 fix triggered
    // a destructive re-render on first tab-click which wiped the IIFE-
    // bound DOM. The correct behavior is no-op: the panel is already
    // ready; clicking the tab just makes it visible (Zen handles the
    // visibility toggle separately). See class doc-comment + the
    // §"Story 10.13 F-2" doc-block above for the full rationale.
    //
    // We still set the sentinel for ergonomic reasons (so any future code
    // that introspects _tabDisplay['Agent'] to detect "is the panel
    // rendered?" gets a truthy answer).
    if (this.detailsHidden) { return; }
    var tabGroup = zen('detailsTabGroup');
    if (!tabGroup) { return; }
    var currTab = tabGroup.getCurrTabNo();
    if (currTab !== 5) { return; }

    if (!this._tabDisplay) { this._tabDisplay = new Object(); }
    this._tabDisplay['Agent'] = '__rendered__';
    // No re-render call — see Story 10.13 F-2 doc-comment above.
}

/// <p>Story 12.5 (BUG-05) — override the grandparent's
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>:<code>XData
/// searchPane</code> to inject a "Filtered by agent search" badge host
/// element ABOVE the existing filter form. The override re-states the
/// parent's searchPane verbatim and prepends a single
/// <code>&lt;html id="agentFilterBadgeHost"&gt;</code> element whose
/// <code>OnDrawContent="DrawAgentFilterBadge"</code> callback emits the
/// badge HTML when <property>agentSessionFilterIds</property> is non-
/// empty. When the property is empty the callback writes nothing, so
/// the host element renders as a zero-height stub and the form layout
/// is unchanged.</p>
///
/// <p>Verbatim XData duplication is the same trade-off documented in
/// the class doc-comment for <code>XData detailsPane</code> — Zen has
/// no XData merge semantic, so we re-state the parent's body and accept
/// the version-pinning concession (if InterSystems adds new search
/// criteria in a future IRIS release we will not pick them up
/// automatically; this is a known cost).</p>
XData searchPane [ XMLNamespace = "http://www.intersystems.com/zen" ]
{
<pane xmlns="http://www.intersystems.com/zen">

<pane id="jsonPane" paneName="jsonPane" hidden="true" />
<jsonProvider id="queryHistory" OnGetArray="GetQueryHistory" />

<!-- Story 12.5 (BUG-05) — agent-search filter badge host. Renders
     a "Filtered by agent search: N sessions" pill above the filter
     form when ..agentSessionFilterIds is non-empty. The callback
     writes nothing when empty so the host degrades to zero height. -->
<html id="agentFilterBadgeHost" OnDrawContent="DrawAgentFilterBadge" />

<form id="searchForm" labelPosition="top" cellStyle="padding:3px;">

<hgroup>
<vgroup cellStyle="padding:3px;">
<select label="Sort Order" id="SortOrder" name="SortOrder" displayList="Newest First,Oldest First" valueList="2,1" value="2" showEmpty="false" onchange="zenPage.updateSearchState(); return true;"/>
<select id="TimeFormat" label="Time Format" name="TimeFormat" showEmpty="false" value="999" valueList="999,12" displayList="Complete,Time Only" onchange="zenPage.updateSearchState(); return true;"/>
</vgroup>
<vgroup cellStyle="padding:3px;">
<combobox label="Page Size" id="pageSize" name="pageSize" onchange="zenPage.searchIfValidPageSize(zenThis.value);" editable="true"
	unrestricted="true" size="4" title="Select Page Size in rows or enter a number" valueList="1,5,10,20,30,50,100,200,500,1000" value="100"/>
<text label="Page" id="pageNumber" name="pageNumber" readOnly="true" size="4" />
</vgroup>
</hgroup>


<expando id="simpleCriteria" caption="Basic Criteria" animate="true">

<hgroup cellStyle="padding:3px;">
<select label="Status" name="Status" displayList="All,Completed,Error,Created,Queued,Delivered,Discarded,Suspended,Deferred,Aborted"
	valueList=",9,8,1,2,3,4,5,6,7" value="" showEmpty="false" onchange="zenPage.updateSearchState(); return true;"/>
<select label="Type" id="Type" name="Type" displayList="Session Start,Request,Response,All" valueList="0,1,2,3" value="0" showEmpty="false" onchange="zenPage.updateSearchState(); return true;"/>
</hgroup>

<hgroup cellStyle="padding:3px;">
<dateText label="Start Time" name="StartTime" size="18" showTime="true" defaultTime="00:00:00" onchange="zenPage.updateSearchState(); return true;"/>
<text label="Start ID" name="StartId" size="9" onchange="zenPage.updateSearchState(); return true;"/>
</hgroup>

<hgroup cellStyle="padding:3px;">
<dateText label="End Time" name="EndTime" size="18" showTime="true" defaultTime="23:59:59" onchange="zenPage.updateSearchState(); return true;"/>
<text label="End ID" name="EndId" size="9" onchange="zenPage.updateSearchState(); return true;"/>
</hgroup>

<selector id="Source" label="Source" name="Source" size="33" context="Ens/MsgSource" onchange="zenPage.updateSearchState(); return true;"/>

<selector id="Target" label="Target" name="Target" size="33" context="Ens/MsgTarget" onchange="zenPage.updateSearchState(); return true;"/>
<text id="SequenceManagerSearch" name="SequenceManagerSearch" hidden="true" />
</expando>

<expando id="extendedCriteria" caption="Extended Criteria" expanded="false" animate="true">
<hgroup>
<spacer width="5" />
<html>
<div id="addCriterion" class="critLink wrapper" title="#(%page.tipAddCriterionTitle)#" onclick="zenPage.addCriterion(); return false;">
<img id="addCriterionBtn"  src="portal/add_24.gif" style="vertical-align: middle;" ></img>
<span id="addCriterionTxt" class="linkText">#(%page.tipAddCriterion)#</span>
</div>
</html>
<spacer width="15" />
<html>
<div id="addOR" class="critLink wrapper" title="#(%page.tipAddORTitle)#" onclick="zenPage.addOR(); return false;">
<img id="addORBtn" src="portal/views_add_48.gif" width="24px" height="24px" style="vertical-align: middle;" ></img>
<span id="addORTxt" class="linkText">#(%page.tipAddOR)#</span>
</div>
</html>
</hgroup>
<spacer height="5"/>
<html id="criteria">
</html>
</expando>

<expando id="savedSearches" caption="Saved Searches" expanded="false" animate="true">
<hgroup>
<html>
<div id="saveSearch" class="critLink wrapper" title="#(%page.tipSave)#" onclick="zenPage.saveSearch();">
<img id="saveSearchBtn" src="deepsee/insert_table_48.png" width="24px" height="24px" style="vertical-align: middle;" ></img>
<span id="saveSearchTxt" class="linkText">#(%page.tipSave)#</span>
</div>
</html>
<spacer width="10" />
<html>
<div id="saveSearchAs" class="critLink wrapper" title="#(%page.tipSaveAs)#" onclick="zenPage.toggleSaveAs(true);">
<img id="saveSearchAsBtn" src="deepsee/insert_table_fav_48.png" width="24px" height="24px" style="vertical-align: middle;" ></img>
<span id="saveSearchAsTxt" class="linkText">#(%page.tipSaveAs)#</span>
</div>
</html>
<spacer width="10" />
<html>
<div id="searchDelete" class="critLink wrapper" title="#(%page.tipDelete)#" onclick="zenPage.deleteSearch(zen('savedList').getValue());">
<img id="searchDeleteBtn" src="deepsee/close_a_24.png" width="24px" height="24px" style="vertical-align: middle;" ></img>
<span id="searchDeleteTxt" class="linkText">#(%page.tipDelete)#</span>
</div>
</html>
</hgroup>
<spacer height="10" />
<hgroup id="searchSaveGroup">
<select id="savedList" showEmpty="true" title="Choose a saved search" queryClass="EnsPortal.MsgFilter.SavedSearch" queryName="ListPermanent" controlStyle="width: 200px;" onchange="zenPage.loadSearch(zenThis.getValue(), false);" />
</hgroup>
<hgroup id="searchSaveAsGroup" hidden="true" cellVAlign="top">
<text id="saveAsName" hint="Enter a name for the search" />
<spacer width="5" />
<image id="saveAsGo" title="Save this search" onclick="zenPage.saveSearch(zen('saveAsName').getValue(),true);" controlClass="critLink" src="deepsee/ok_24.png" />
<spacer width="5" />
<image id="saveAsExit" title="Don't save search" onclick="zenPage.toggleSaveAs(false);" controlClass="critLink" src="deepsee/close_a_24.png" />
</hgroup>
</expando>
</form>
</pane>
}

/// <p>Story 12.5 (BUG-05) — Zen <code>OnDrawContent</code> callback for
/// the <code>&lt;html id="agentFilterBadgeHost"&gt;</code> element above
/// the filter form. Emits the "Filtered by agent search: N sessions"
/// badge HTML with a small ✕ button when
/// <property>agentSessionFilterIds</property> is non-empty; emits
/// nothing (zero-height host) otherwise.</p>
///
/// <p>The badge clear-button calls
/// <method>ClearAgentSessionFilter</method> which resets the property,
/// refreshes this host, and triggers <code>doSearch()</code> to
/// re-render the table without the filter (AC-5).</p>
Method DrawAgentFilterBadge(pSeed As %String) As %Status
{
    Set tIds = ..agentSessionFilterIds
    ; $Char(0) sentinel guard — Zen string properties may be re-read after
    ; an UPDATE through the SQL projection of the form session; normalize
    ; per project rule §"$Char(0) sentinel".
    If tIds = $Char(0) Set tIds = ""
    If tIds = "" Quit $$$OK

    ; Count the IDs server-side so the badge text is independent of any
    ; client-side state. The validation guard in CreateResultSet covers
    ; the SQL-injection surface; here we only count items separated by ','.
    Set tCount = $Length(tIds, ",")

    &html<<div class="sa-agent-filter-badge" role="status" aria-live="polite">>
    &html<<span class="sa-agent-filter-badge-text">Filtered by agent search: #(tCount)# sessions</span>>
    &html<<button type="button" class="sa-agent-filter-badge-clear" title="Clear agent-search filter" aria-label="Clear agent-search filter" onclick="zenPage.ClearAgentSessionFilter(); return false;">×</button>>
    &html<</div>>
    Quit $$$OK
}

/// <p>Story 12.5 (BUG-05) — apply the agent-search filter to the
/// central results table. Called by the
/// <code>chat-panel.js</code>'s "Load N sessions into table" button.</p>
///
/// <p><b>Input.</b> <var>pSessionIdsJson</var> is a JSON-stringified
/// array of integer session IDs (e.g., <code>"[100,101,102]"</code>).
/// The button's click handler passes
/// <code>JSON.stringify(sessionIds)</code> directly so this method
/// owns the JSON-to-CSV conversion at the JS boundary, and then the
/// page property holds CSV (cheaper for the SQL-emit path).</p>
///
/// <p><b>Validation contract.</b> Each parsed array element is
/// validated against <code>/^\d+$/</code>; any non-numeric element
/// rejects the whole filter (no-op, alert the operator). The
/// SQL-injection guard is double-coverage: this client-side
/// validation + server-side re-validation in
/// <method>CreateResultSet</method>.</p>
///
/// <p><b>Re-search trigger.</b> After setting the property, refresh
/// the badge host (<code>zen('agentFilterBadgeHost').refreshContents()</code>)
/// so the badge appears, then call <code>zenPage.doSearch()</code>
/// to re-execute the parent's search path with our new filter
/// active. The parent's <code>doSearch()</code> calls
/// <method>CreateResultSet</method> internally via the tablePane's
/// query lifecycle.</p>
ClientMethod ApplyAgentSessionFilter(pSessionIdsJson) [ Language = javascript ]
{
    if (!pSessionIdsJson) {
        return;
    }
    var ids;
    try {
        ids = JSON.parse(pSessionIdsJson);
    } catch (e) {
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[sa-search] ApplyAgentSessionFilter: malformed JSON', e);
        }
        return;
    }
    if (!Array.isArray(ids) || ids.length === 0) {
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[sa-search] ApplyAgentSessionFilter: empty or non-array input');
        }
        return;
    }
    // Validate each element is a positive integer (or the string form
    // thereof). Reject the whole filter on any non-numeric element —
    // SQL-injection-guard double-coverage (server-side re-validates).
    var csv = '';
    for (var i = 0; i < ids.length; i++) {
        var raw = ids[i];
        var n = Number(raw);
        if (!isFinite(n) || n <= 0 || Math.floor(n) !== n || String(raw).match(/^\d+$/) === null) {
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[sa-search] ApplyAgentSessionFilter: non-numeric session id rejected', raw);
            }
            return;
        }
        csv += (i > 0 ? ',' : '') + String(n);
    }
    // Persist on the Zen page property (server-readable in
    // CreateResultSet via ..agentSessionFilterIds).
    zenPage.agentSessionFilterIds = csv;

    // Refresh the badge host so the operator sees confirmation.
    try {
        var host = zen('agentFilterBadgeHost');
        if (host) {
            host.refreshContents();
        }
    } catch (e2) {
        // Non-fatal — the filter still works without the badge.
    }

    // Trigger the parent's search path so the tablePane re-queries
    // with our filter active.
    try {
        zenPage.doSearch();
    } catch (e3) {
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[sa-search] doSearch() threw after ApplyAgentSessionFilter', e3);
        }
    }
}

/// <p>Story 12.5 (BUG-05) — override the parent's
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>:<method>loadSearch</method>
/// so that the existing Reset button on the page Ribbon (which fires
/// <code>zenPage.loadSearch('',true)</code> per
/// <CLASS>EnsPortal.MessageViewer</CLASS>:<method>OnGetRibbonInfo</method>
/// line 138) ALSO clears <property>agentSessionFilterIds</property> +
/// refreshes the badge host. Without this override Reset would clear
/// the form fields but leave the agent filter active — the badge would
/// still show "Filtered by agent search: N sessions" and the table
/// would still narrow to those IDs, contradicting operator intent
/// (Story 12.5 AC-5: "Clear-filter button (✕ on the badge OR existing
/// Reset button) clears agent-session-filter mode"). Code-review
/// finding fix.</p>
///
/// <p><b>Reset semantics.</b> The parent dispatches Reset by calling
/// <code>loadSearch('',true)</code> — empty <var>searchName</var> +
/// <var>run=true</var>. We detect that signature and clear the agent
/// filter BEFORE delegating to the parent so the parent's
/// <code>doSearch()</code> at the tail re-runs against the cleared
/// state.</p>
ClientMethod loadSearch(searchName, run) [ Language = javascript ]
{
    // Story 12.5 — Reset button path also clears the agent filter.
    if (searchName === '' || searchName == null) {
        zenPage.agentSessionFilterIds = '';
        try {
            var host = zen('agentFilterBadgeHost');
            if (host) {
                host.refreshContents();
            }
        } catch (e) {
            // Non-fatal — badge refresh is cosmetic; the filter state
            // is already cleared.
        }
    }
    // Delegate to the parent's loadSearch which handles the saved-search
    // load path AND triggers doSearch() when run=true.
    return this.invokeSuper('loadSearch', arguments);
}

/// <p>Story 12.5 (BUG-05) — clear the agent-search filter and
/// re-render the table without the SessionId restriction. Called by
/// the ✕ button on the badge AND can be called externally (e.g., by
/// the existing Reset button via a future wiring).</p>
ClientMethod ClearAgentSessionFilter() [ Language = javascript ]
{
    zenPage.agentSessionFilterIds = '';

    // Refresh the badge host so the badge disappears.
    try {
        var host = zen('agentFilterBadgeHost');
        if (host) {
            host.refreshContents();
        }
    } catch (e2) {
        // Non-fatal.
    }

    // Trigger re-search without the filter.
    try {
        zenPage.doSearch();
    } catch (e3) {
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[sa-search] doSearch() threw after ClearAgentSessionFilter', e3);
        }
    }
}

/// <p>Story 12.5 (BUG-05) — override the grandparent's
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>:<method>CreateResultSet</method>
/// so that when <property>agentSessionFilterIds</property> is non-empty
/// the central results table shows ONLY the agent-supplied sessions.
/// When the property is empty the override is a transparent
/// pass-through to <code>##super()</code>.</p>
///
/// <p><b>Minimum-blast-radius design.</b> Per Story 12.5 spec Dev Notes
/// §"Why minimum-blast-radius on CreateResultSet": call
/// <code>##super()</code> first to build the base ResultSet (preserving
/// every parent-side filter, sort, pagination, and warning behavior),
/// then if the agent-filter is active, build a wrapper
/// <code>%SQL.Statement</code> whose query is
/// <code>SELECT * FROM (&lt;original SQL&gt;) ms_sub WHERE ms_sub.Session
/// IN (CSV)</code> and return the wrapper's
/// <code>%SQL.StatementResult</code>. The original SQL is read from
/// <property>searchQuery</property> which the parent populates as a
/// side-effect of <code>##super()</code>.</p>
///
/// <p><b>SQL injection guard (server-side, second line of defense).</b>
/// The CSV is re-validated against
/// <code>$Match(tIds, "^[0-9]+(,[0-9]+)*$")</code> before
/// concatenation. If validation fails, fall back to the unfiltered
/// parent ResultSet (the JS boundary's validation should have caught
/// it; failing safe is still the right behavior).</p>
///
/// <p><b>Column name "Session".</b> The parent's underlying query
/// (<CLASS>EnsPortal.MsgFilter.Assistant</CLASS>:<method>GenerateSQL</method>)
/// emits <code>head.SessionId As Session</code> — confirmed via Task 0
/// probe of <code>irislib/EnsPortal/MsgFilter/Assistant.cls</code> line
/// 247 / 493. So the wrapper's WHERE clause references
/// <code>ms_sub.Session</code>.</p>
Method CreateResultSet(Output pSC As %Status, pInfo As %ZEN.Auxiliary.QueryInfo) As %ResultSet
{
    Set tBaseRS = ##super(.pSC, pInfo)
    If $$$ISERR(pSC) Quit tBaseRS

    ; Property read with $Char(0) normalization (project rule).
    Set tIds = ..agentSessionFilterIds
    If tIds = $Char(0) Set tIds = ""
    If tIds = "" Quit tBaseRS

    ; SQL injection guard — server-side re-validation of the CSV. If the
    ; pattern doesn't match, fall back to unfiltered (the JS boundary
    ; should have caught this; defense-in-depth).
    If '$Match(tIds, "^[0-9]+(,[0-9]+)*$") Quit tBaseRS

    ; The parent populates ..searchQuery from tFilter.GeneratedSQL as a
    ; side-effect of ##super(). If empty (e.g., search-warning early
    ; exit), there's nothing to wrap — return base unchanged.
    Set tBaseSql = ..searchQuery
    If tBaseSql = "" Quit tBaseRS

    ; Build the wrapper SQL. Column name "Session" is the parent's
    ; SELECT alias for head.SessionId. The CSV has been pattern-validated
    ; so direct concatenation is safe.
    Set tWrappedSql = "SELECT * FROM (" _ tBaseSql _ ") ms_sub WHERE ms_sub.Session IN (" _ tIds _ ")"

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare(tWrappedSql)
    If $$$ISERR(tPrepSC) {
        ; Wrapper %Prepare failed — return base RS so the operator still
        ; sees results, but emit a parent-rendered search warning so the
        ; operator is NOT misled by the badge claiming a filter is active
        ; while the table shows the unfiltered base. Story 12.5 review-
        ; finding fix: silent leak when wrapper prepare fails.
        Do ..searchWarnings.Insert("Agent-search filter (" _ $Length(tIds, ",") _ " sessions) could not be applied — wrapper SQL failed to prepare. Showing unfiltered results. Use the badge × button to clear the filter.")
        Quit tBaseRS
    }
    Set tWrappedRS = tStmt.%Execute()
    If '$IsObject(tWrappedRS) {
        Do ..searchWarnings.Insert("Agent-search filter (" _ $Length(tIds, ",") _ " sessions) could not be applied — wrapper SQL did not return a result set. Showing unfiltered results.")
        Quit tBaseRS
    }
    If tWrappedRS.%SQLCODE < 0 {
        Do ..searchWarnings.Insert("Agent-search filter (" _ $Length(tIds, ",") _ " sessions) could not be applied — wrapper SQL execution failed (SQLCODE " _ tWrappedRS.%SQLCODE _ "). Showing unfiltered results.")
        Quit tBaseRS
    }

    ; Update the parent's searchQuery so the "Show Query" diagnostic
    ; reflects the actually-executed query (operator-observability).
    Set ..searchQuery = tWrappedSql
    Set pInfo.queryText = tWrappedSql

    Quit tWrappedRS
}

/// <p>Story 12.3 (BUG-04, HIGH severity) — override the parent's
/// <code>showTrace</code> ClientMethod so the green session-ID link in
/// the search-results table opens the CUSTOM
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> page (with the
/// "Ask the agent" 4th tab) instead of the standard
/// <code>EnsPortal.VisualTrace.zen</code> page (3 tabs only —
/// Header / Body / Contents). Without this override the operator
/// loses the cross-page hand-off from Search-Agent results into the
/// per-session Inspection-Agent surface.</p>
///
/// <p><b>Body — verbatim copy of the parent
/// (<code>irislib/EnsPortal/MessageViewer.cls</code> lines 178-188)
/// with the URL substring</b> <code>'EnsPortal.VisualTrace.zen'</code>
/// <b>changed to</b>
/// <code>'SessionAgent.EnsPortal.VisualTrace.zen'</code> — every other
/// behavior (bubble-cancel, sessionId guard, <code>window.open</code>
/// dispatch) preserved verbatim.</p>
///
/// <p><b>Coverage of both invocation paths.</b> The parent's
/// <method>%OnGetTableLinkMenu</method> (line 160) and
/// <method>%OnGetDetailsLinkMenu</method> (line 173) both bind their
/// menu entries to <code>"zenPage.showTrace"</code> — so this single
/// override covers (a) the green column-link click AND (b) the
/// right-click "Visual Trace" context-menu entry. Confirmed via Task 0
/// probe of <code>irislib/EnsPortal/MessageViewer.cls</code>.</p>
ClientMethod showTrace(sessionId, evt) [ Language = javascript ]
{
	if (evt) {
		evt.cancelBubble = true;
		if (evt.stopPropagation) evt.stopPropagation();
	}
	if (sessionId != -1) {
		var URI = zenLink('SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID='+sessionId);
		window.open(URI);
	}
}

}
