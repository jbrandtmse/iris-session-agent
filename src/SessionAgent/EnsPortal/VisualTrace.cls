/// <p>Inspection-agent host page — subclass of <CLASS>EnsPortal.VisualTrace</CLASS>
/// that adds an "Ask the agent" tab right-appended to the parent's tab
/// strip. Clicking the tab opens the chat panel scoped to the current
/// Visual-Trace session, pre-populated with the operator's prior
/// conversation (if any) per UX-DR15-Inspection / UX-DR17-MVP-subset.</p>
///
/// <p><b>Tab strip strategy — copy-and-extend.</b> Zen has no built-in
/// "merge with parent XData" semantic; overriding an XData block fully
/// replaces the parent's. The Story 3.3 Task 0 probe established that the
/// parent's tab strip lives in <code>XData allTabs</code> (a
/// <code>&lt;tabGroup id="contentTabs"&gt;</code> with three child
/// <code>&lt;tab&gt;</code> elements: <code>headerDetails</code>,
/// <code>bodyDetails</code>, <code>bodyContents</code>). We re-state the
/// parent's three tabs verbatim and append a new
/// <code>&lt;tab id="askAgentTab" caption="Ask the agent"&gt;</code> as
/// the fourth child. The trade-off: if InterSystems adds a new core tab
/// in a future IRIS release, we will not pick it up automatically — a
/// version-pinning concession we accept for MVP. A future story (3.6+)
/// can add a regression check against the parent class signature.</p>
///
/// <p><b>CSS / JS contribution mechanism.</b> The parent uses
/// <code>%OnDrawHTMLHead()</code> as its runtime head-contribution
/// callback (it calls <code>##super()</code> + emits Event-Log style).
/// We override <code>%OnDrawHTMLHead()</code> to call <code>##super()</code>
/// (preserves parent's contributions) then emit (a) the chat-panel CSS
/// via <CLASS>SessionAgent.UI.ChatPanel</CLASS>.<METHOD>EmitStyle</METHOD>
/// and (b) the <code>&lt;script src="/csp/static/iris-session-agent/chat-panel.js"&gt;</code>
/// vendored static include. The static asset CSP application is
/// declared in <code>module.xml</code>'s <code>&lt;CSPApplication&gt;</code>
/// block per Story 3.0 wiring.</p>
///
/// <p><b>ZenMethod hyperevent — <method>SendChatMessage</method>.</b> The
/// browser's chat-panel.js calls
/// <code>zenPage.SendChatMessage(agentName, sessionKey, userText, contextHintsJson)</code>.
/// The ClassMethod invokes
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> with
/// <code>%session.Username</code> as the portal user (caller-context
/// resolution at the trust boundary per architecture §"Caller context
/// propagation"), receives a <CLASS>SessionAgent.Agent.TurnResult</CLASS>,
/// and returns its <method>ToJson</method> string for client-side parsing.
/// The method NEVER throws (FR37) — any escape converts to a structured
/// error JSON so the browser always receives a parseable envelope.</p>
///
/// <p><b>Caller-context boundary.</b> Per architecture §"Caller context
/// propagation" / NFR-S6: <code>%session.Username</code> resolution
/// happens AT this boundary; tools NEVER read <code>$NAMESPACE</code> or
/// session state directly. <method>RunTurn</method> constructs the
/// <CLASS>SessionAgent.Agent.CallerContext</CLASS> from the parameters
/// we pass through.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 3.3</a> — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Operator-facing dispatch" line 266; §"UI hosting" line 282;
/// §"ZenMethod hyperevents" line 572; §"Project Directory Structure"
/// line 876.</li>
/// <li><CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS> —
/// emits the panel HTML shell (Story 3.1, extended Story 3.3 Task 1).</li>
/// <li><CLASS>SessionAgent.UI.ChatPanel</CLASS> — emits the panel CSS
/// (Story 3.1).</li>
/// <li><CLASS>SessionAgent.Chat.History</CLASS> — prior-conversation
/// row (Story 2.6).</li>
/// <li><CLASS>SessionAgent.Agent.AgentLoop</CLASS> — turn orchestrator
/// (Story 2.12); <method>RunTurn</method> takes the parameters we plumb.</li>
/// <li><a href="../../../irislib/EnsPortal/VisualTrace.cls">irislib/EnsPortal/VisualTrace.cls</a>
/// — parent class verified via Task 0 probe (XData allTabs structure +
/// %OnDrawHTMLHead callback).</li>
/// </ul>
Class SessionAgent.EnsPortal.VisualTrace Extends EnsPortal.VisualTrace [ System = 4 ]
{

/// <p>Localized page name. Inherits parent's "Visual Trace" base; Zen
/// uses this for the browser tab title.</p>
Parameter PAGENAME = "Visual Trace + Agent";

/// <p>Story 10.4 AC-1 — search-session key inherited from a click-through
/// hand-off. When the operator clicks a session entry on the Search Agent
/// page (Story 10.3), the navigation URL appends
/// <code>&FROM_SEARCH=&lt;search-session-key&gt;</code>. Zen's
/// <code>ZENURL</code> binding auto-captures this query-string param into
/// the property. Read by <method>DrawChatPanel</method> to look up the
/// search-session's <CLASS>SessionAgent.Chat.History</CLASS> row and
/// extract the literal operator query for the "from search" stripe
/// (UX-DR5). Empty in the typical Inspection-flow case (no hand-off).</p>
Property fromSearchKey As %ZEN.Datatype.string(ZENURL = "FROM_SEARCH");


/// <p>Override the parent's tab strip (<code>XData allTabs</code>) — copy
/// the parent's three tabs verbatim and append our "Ask the agent" tab as
/// the fourth child. Strategy documented in the class doc-comment
/// (copy-and-extend; Zen has no XData merge semantic).</p>
///
/// <p>The new <code>&lt;tab id="askAgentTab"&gt;</code> hosts a single
/// <code>&lt;html&gt;</code> Zen component whose <code>OnDrawContent</code>
/// callback dispatches to <method>DrawChatPanel</method> on this class
/// (Zen lookup is method-name-based against the page instance). The seed
/// is unused in MVP — first-time vs returning is decided server-side by
/// <method>DrawChatPanel</method> itself.</p>
XData allTabs [ XMLNamespace = "http://www.intersystems.com/zen" ]
{
<pane>
<tabGroup id="contentTabs" showTabBar="true" remember="true" onshowTab="zenPage.updateTabs(true);">
<tab id="headerDetails" caption="Header" title="Message Header Properties">
<html id="detailsContent" OnDrawContent="DrawDetailsContent" />
</tab>
<tab id="bodyDetails" caption="Body" title="Message Body Properties">
<html id="bodyInfo" OnDrawContent="DrawBodyInfo" />
</tab>
<tab id="bodyContents" caption="Contents" title="Message Body Contents">
<html id="fullContent" containerStyle="padding-top: 5px; padding-bottom: 5px;" OnDrawContent="DrawFullContentLinks" />
<iframe id="contentFrame" frameBorder="false" width="100%"/>
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
/// <code>##super()</code> first (preserves parent's SVG-canvas
/// dimensions wiring), then sets the caption + title on our new
/// <code>askAgentTab</code> at runtime. The XData declaration omits
/// these attributes (see XData allTabs comment) to avoid the
/// compile-time MPP5646 / <code>&lt;PROTECT&gt;</code> error.</p>
Method %OnAfterCreatePage() As %Status
{
    Set tSC = ##super()
    If $$$ISERR(tSC) Quit tSC

    Set tTab = ..%GetComponentById("askAgentTab")
    If $IsObject(tTab) {
        Set tTab.caption = "Ask the agent"
        Set tTab.title = "Ask the SessionAgent about this Ens session"
    }
    Quit $$$OK
}

/// <p>Zen <code>OnDrawContent</code> callback for the
/// <code>&lt;tab id="askAgentTab"&gt;</code>. Reads the operator's prior
/// chat history (Story 2.6) and dispatches to
/// <CLASS>SessionAgent.EnsPortal.Util.ChatPanelDrawHelper</CLASS>.<METHOD>DrawChatPanel</METHOD>
/// with the right parameters (first-time empty transcript +
/// "Ask anything..." placeholder OR returning-conversation transcript +
/// "Continue the conversation." placeholder).</p>
///
/// <p>The <code>%session.Username</code> read happens here, at the
/// page-render boundary. The chat-history lookup uses
/// <code>%OpenId</code> (concurrency=0 — lock-free read) rather than
/// <method>SessionAgent.Chat.History.LoadOrCreate</method> because we
/// MUST NOT acquire the per-row lock during page render (the lock is
/// acquired later by <method>SendChatMessage</method> when the operator
/// sends their first turn). A read-only render that briefly held the
/// lock would block any concurrent turn from another tab.</p>
///
/// <p>If no prior history row exists for this
/// <code>(agent, session, user)</code> tuple, we render the
/// first-time variant (empty transcript + first-time placeholder).</p>
///
/// <p>Returns <code>$$$OK</code> always — render failures degrade
/// gracefully (the ChatPanelDrawHelper still emits the empty shell so
/// the operator can submit a turn even if the prior-history lookup
/// failed). The <code>pSeed</code> parameter is unused in MVP.</p>
Method DrawChatPanel(pSeed As %String) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tAgentName = "session-inspection"
        Set tSessionKey = ..sessionId
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
        ; admin probe uses $System.Security.Check("%All", "U") —
        ; verified Task 0 (returns 1 if user has %All, 0 otherwise;
        ; 2-arg form). Per project rule §"Namespace Switching in REST
        ; Handlers" (analogous applies to Zen callbacks), we do NOT
        ; switch namespace — SessionAgent_Config.Agent lives in the
        ; HSCUSTOM namespace the Zen page already runs in. The query
        ; uses the ConvKeyIdxOpen-style auto-generated AgentNameIdx
        ; helper (preferred over raw &sql to avoid SQL-vs-property-name
        ; drift; the spec's WHERE Name=:pAgentName was a reference to
        ; the property at spec-time, but the storage column is actually
        ; AgentName per Task 0 SQL probe).
        ; ─────────────────────────────────────────────────────────────
        Set tConfigRow = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
        If '$IsObject(tConfigRow) || (tConfigRow.Enabled = 0) {
            ; Admin probe for variant selection. Returns 1 when the
            ; logged-in user has %All; 0 otherwise. Spec's TBD-resolve:
            ; MVP uses %All; Epic 6 will introduce %SessionAgent_Admin
            ; and adjust this check.
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
        Set tPlaceholder = "Ask anything about this session."
        If (tSessionKey '= "") && (tPortalUser '= "") {
            Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(tAgentName, tSessionKey, tPortalUser, 0)
            If $IsObject(tHist) {
                ; Returning conversation — flatten the canonical-Anthropic
                ; turns into the simple chat-shape the JS init expects:
                ; [{role:"operator|agent", content:"plain-text-or-markdown"}]
                Set tPriorJson = ..FlattenTurnsForBootstrap(tHist)
                ; Non-empty array means returning-variant placeholder.
                If tPriorJson '= "[]" {
                    Set tPlaceholder = "Continue the conversation."
                }
                Do tHist.%Close()
            }
        }

        ; ─────────────────────────────────────────────────────────────
        ; Story 10.4 AC-1 — read the FROM_SEARCH URL param (auto-bound
        ; to ..fromSearchKey via ZENURL). When non-empty, look up the
        ; search-session's Chat.History row using the same
        ; (AgentName, SessionKey, PortalUser) tuple the search agent
        ; persists under (Story 10.1 / 10.2 store under
        ; AgentName="message-search"). Extract the literal first-user-
        ; message via ExtractLiteralFirstUserMessage. The two-array
        ; invariant (Story 9.4) means the digest prefix is NOT in the
        ; persisted TurnsJson — the canonical first user-text block IS
        ; the literal operator query verbatim.
        ;
        ; Empty key OR no history row → tFromSearchQuery="" → the helper
        ; emits fromSearchQuery:"" and chat-panel.js renders no stripe
        ; per AC-2 / AC-3.
        ; ─────────────────────────────────────────────────────────────
        Set tFromSearchQuery = ""
        If ..fromSearchKey '= "" {
            Set tSearchHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("message-search", ..fromSearchKey, tPortalUser, 0)
            If $IsObject(tSearchHist) {
                Set tFromSearchQuery = ..ExtractLiteralFirstUserMessage(tSearchHist)
                Do tSearchHist.%Close()
            }
        }

        ; Dispatch to the shared helper. It writes to the current device
        ; via &html<...> (the Zen OnDrawContent callback's output goes to
        ; the page response).
        Set tHelperSC = ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel(tAgentName, tSessionKey, tPortalUser, "", tPriorJson, tPlaceholder, tFromSearchQuery, ..fromSearchKey)
        If $$$ISERR(tHelperSC) {
            ; Helper-level error is unexpected (only invariant: empty
            ; agent name, which we hard-code). Capture without raising
            ; so the page still loads — operator sees an empty shell.
            Set tSC = tHelperSC
        }
    }
    Catch ex {
        ; Never let a render error escape — page must load. The chat
        ; tab will be empty/broken but the parent Visual Trace
        ; functionality remains intact (AC-5).
        Set tSC = ex.AsStatus()
    }
    ; Always return OK — the parent Zen renderer doesn't surface
    ; OnDrawContent failures to the operator usefully.
    Quit $$$OK
}

/// <p>Story 10.4 AC-1 — extract the literal first-user-message from a
/// <CLASS>SessionAgent.Chat.History</CLASS> row's
/// <property>TurnsJson</property> canonical-Anthropic stream. Returns the
/// verbatim <code>text</code> field of the FIRST <code>role:"user"</code>
/// turn's first <code>type:"text"</code> block.</p>
///
/// <p><b>Two-array invariant (Story 9.4).</b> The persisted
/// <code>TurnsJson</code> is the canonical array — the digest prefix is
/// NEVER persisted (the digest only rides the provider-bound
/// <code>tTurnsForLlm</code> parallel array, never the canonical
/// <code>tTurns</code> stored to <code>Chat.History</code>). So
/// <code>TurnsJson[0].content[0].text</code> for the first user turn IS
/// the literal operator query verbatim — NO digest stripping required.</p>
///
/// <p>Returns <code>""</code> on any failure (no row, malformed JSON, no
/// user turns, no text block on the first user turn) — the caller renders
/// no stripe in that case per AC-2.</p>
ClassMethod ExtractLiteralFirstUserMessage(pHist As SessionAgent.Chat.History) As %String
{
    Set tLiteral = ""
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

        ; Walk turns; stop at the first role="user" turn with a text block.
        Set tIter = tArr.%GetIterator()
        While tIter.%GetNext(.tIdx, .tTurn) {
            If '$IsObject(tTurn) Continue
            If tTurn.%Get("role") '= "user" Continue
            Set tContent = tTurn.%Get("content")
            If '$IsObject(tContent) Continue
            Set tBlockIter = tContent.%GetIterator()
            While tBlockIter.%GetNext(.tBidx, .tBlock) {
                If '$IsObject(tBlock) Continue
                If tBlock.%Get("type") '= "text" Continue
                ; First text block of the first user turn — verbatim text.
                Set tLiteral = tBlock.%Get("text")
                Quit
            }
            ; Whether or not we found a text block, this was the first
            ; user turn — do NOT continue scanning (the first user turn
            ; defines the literal operator query per Story 9.4).
            Quit
        }
    }
    Catch ex {
        ; Swallow — empty-string degradation is the safe UX.
        Set tLiteral = ""
    }
    Quit tLiteral
}

/// <p>Internal helper — flatten the canonical-Anthropic
/// <CLASS>SessionAgent.Chat.History</CLASS>.<property>TurnsJson</property>
/// stream into the simplified chat-shape the JS init expects:
/// <code>[{role:"operator|agent", content:"plain-text-or-markdown"}]</code>.</p>
///
/// <p>Mapping rules:</p>
/// <ul>
/// <li>Anthropic <code>"user"</code> turns with <code>type:"text"</code>
/// blocks → <code>{role:"operator", content:&lt;text&gt;}</code>.</li>
/// <li>Anthropic <code>"assistant"</code> turns with
/// <code>type:"text"</code> blocks → <code>{role:"agent",
/// content:&lt;text&gt;}</code>. Multiple text blocks are concatenated.</li>
/// <li>Anthropic <code>"user"</code> turns with only
/// <code>type:"tool_result"</code> blocks (the orchestrator's
/// tool-result-relay turn) → SKIPPED (operator never typed them).</li>
/// <li>Anthropic <code>"assistant"</code> turns with only
/// <code>type:"tool_use"</code> blocks (no text) → SKIPPED (operator
/// sees the tool-call cards inline with the next turn's render in MVP;
/// this is acceptable for first-pass surfacing per UX-DR17-MVP-subset).</li>
/// </ul>
///
/// <p>Returns the JSON-serialized array. On any failure (corrupt
/// stream, parse error), returns <code>"[]"</code> so the panel still
/// renders the welcome message.</p>
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
        ; Swallow — fall through to the empty-array degradation. The
        ; panel will render the welcome message on a corrupt history,
        ; which is the safest UX (operator can still chat).
        Set tFlat = ##class(%DynamicArray).%New()
    }
    Quit tFlat.%ToJSON()
}

/// <p>Override the parent's <code>%OnDrawHTMLHead</code> head-contribution
/// callback. Calls <code>##super()</code> first (preserves parent's
/// EventInfo style), then emits (a) the chat-panel CSS via
/// <CLASS>SessionAgent.UI.ChatPanel</CLASS>.<METHOD>EmitStyle</METHOD>
/// and (b) the chat-panel.js include — served via the
/// <CLASS>SessionAgent.UI.ChatPanelAsset</CLASS> CSP page (Story 3.6 fix:
/// replaces the broken <code>/csp/static/iris-session-agent/chat-panel.js</code>
/// dedicated-static-CSPApplication approach that hit a ZPM
/// <code>${cspdir}</code>-not-expanded bug; pivots to a class-served
/// asset routed via the per-namespace <code>/csp/&lt;ns&gt;</code>
/// auto-CSP-application that IRIS creates for every namespace).</p>
///
/// <p>The URL is built dynamically from <code>$NAMESPACE</code> so the same
/// page works on any namespace where the <code>SessionAgent.PKG</code>
/// resource is mapped — zero install-time configuration needed for
/// multi-namespace deployments.</p>
Method %OnDrawHTMLHead() As %Status
{
    Set tSC = ##super()
    If $$$ISERR(tSC) Quit tSC

    ; Emit chat-panel CSS via the shared style emitter (Story 3.1).
    Set tStyleSC = ##class(SessionAgent.UI.ChatPanel).EmitStyle()
    If $$$ISERR(tStyleSC) Quit tStyleSC

    ; Emit the chat-panel.js include. URL derives from $NAMESPACE so the
    ; same script tag works on every namespace mapped to SessionAgent.PKG.
    ; Story 3.6 fix-now: replaces the broken
    ; /csp/static/iris-session-agent/chat-panel.js dedicated-static path
    ; with the class-served /csp/<ns>/SessionAgent.UI.ChatPanelAsset.cls.
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
/// <code>{"error":{"kind":"internal","message":"..."}}</code>. The
/// browser's chat-panel.js sees the <code>error</code> key and renders
/// the structured error block; the operator can retry without seeing
/// a raw stack trace.</p>
///
/// <p><b>pContextHintsJson handling.</b> The browser sends a JSON
/// string; <method>RunTurn</method> takes a <code>%DynamicObject</code>.
/// We parse the string here (with a graceful fallback to empty-object
/// on parse error) so the boundary contract matches the orchestrator
/// expectation.</p>
///
/// <p><b>Audit trail on internal error.</b> When the never-throw envelope
/// fires, we emit a best-effort
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> row via
/// <CLASS>SessionAgent.Audit.Emit</CLASS>.<METHOD>LogLlmCall</METHOD>
/// with <code>IsError=1</code> and the exception text in
/// <code>ErrorText</code>, so operators have a paper trail. The
/// <code>ChatHistoryId</code> is empty (no row was created) — analytics
/// queries that filter by FK will not double-count this row.</p>
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
        ; structured error envelope and skip RunTurn (the parse-fail
        ; path is itself the terminal state for the call). Use a
        ; sentinel flag because argumentless Quit inside an inner
        ; Catch only exits the inner Try block, not the outer method.
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
                ; Surface as a structured error — malformed hints is the
                ; only client-side input validation we enforce; if the
                ; browser sent garbage, the operator deserves to see why.
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
        ; path. The per-kind text is the same banner-equivalent message
        ; UX-DR8 / FR46 specify.
        Set tKind = "internal"
        Set tMessage = "Internal error — see audit log"
        ; Story 10.5 review fix-now (F-1): comma-boundary-anchored 5803
        ; match — see IsChatHistoryLocked above for rationale.
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
/// <p><b>Pattern (verified Story 10.5 Task 0).</b> The actual error code
/// IRIS emits on <code>%OpenId(id, 4)</code> lock-fail is
/// <code>5803</code> (<code>$$$LockFailedToAcquireExclusive</code> per
/// <code>irislib/%occErrors.inc</code> line 2017). The Story 10.5 spec's
/// reference to <code>$$$ERRORLOCKFAILED</code> is a generic stand-in
/// for the IRIS lock-fail error code — the actual macro of that name
/// does NOT exist in this IRIS distro. We detect via
/// <code>$SYSTEM.Status.GetErrorCodes(tSC) [ "5803"</code> per
/// <code>.claude/rules/iris-objectscript-basics.md</code> §"$$$ERROR* macro
/// detection".</p>
///
/// <p><b>Probe semantics.</b> Try <code>ConvKeyIdxOpen(...,4,.tSC)</code>
/// (concurrency=4 + the dictionary's auto-generated default timeout —
/// <code>$ZU(115,4)</code>). If the OREF returns NULL with status
/// containing 5803, another process holds the lock — emit
/// <code>{"locked":true}</code>. Otherwise we briefly held the lock; release
/// immediately via <code>%Close()</code> so the actual turn-holder can
/// re-acquire when their LoadOrCreate fires next. Emit <code>{"locked":false}</code>.</p>
///
/// <p><b>Defensive Catch.</b> Probe failure is treated as
/// <code>locked: false</code> so the banner doesn't false-positive into a
/// stuck state. Operator can still attempt a turn; if a real lock IS held,
/// <method>SendChatMessage</method> will surface it via the structured-
/// error path (AC-2 — <code>error.kind = "lock_held"</code>).</p>
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

        ; Probe lock state without holding. ConvKeyIdxOpen wraps %OpenId
        ; with concurrency=4 (exclusive) and the dictionary's default
        ; timeout. If the row is locked by another process, the call
        ; returns $$$NULLOREF and tSC carries error code 5803
        ; ($$$LockFailedToAcquireExclusive — verified Task 0). Otherwise
        ; we briefly held the lock; release immediately so the turn-
        ; holder can re-acquire on the next LoadOrCreate.
        Set tSC = $$$OK
        Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(pAgentName, pSessionKey, tPortalUser, 4, .tSC)
        ; Story 10.5 review fix-now (F-1): comma-boundary-anchored match
        ; against the canonical $$$LockFailedToAcquireExclusive code (5803,
        ; per irislib/%occErrors.inc:2017). Wrapping the codes-list with
        ; "," _ ... _ "," and matching ",5803," ensures word-boundary
        ; semantics — the bare-substring form ([ "5803") would false-
        ; positive on any future IRIS code containing "5803" as a digit-
        ; substring (e.g., 58031, 15803). The canonical %SYSTEM.Status.Equals
        ; alternative requires Include %occErrors which neither parent
        ; class declares; the comma-anchor form preserves the spec's
        ; substring-detection contract while eliminating the false-positive
        ; risk class. See .claude/rules/iris-objectscript-basics.md
        ; §"IRIS error code 5803 / $$$LockFailedToAcquireExclusive".
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
        ; Defensive: probe failure treated as "not locked" so the banner
        ; doesn't false-positive into a stuck state. Operator can still
        ; attempt a turn; if real lock held, SendChatMessage surfaces it
        ; via the structured-error path (AC-2).
        Set tEnvelope = "{""locked"": false, ""probe_error"": " _ ##class(%DynamicObject).%New().%Set("text", ex.DisplayString()).%ToJSON() _ "}"
    }
    Quit tEnvelope
}

/// <p>Story 3.4 — citation-chip click handler. Invoked by
/// <code>chat-panel.js</code>'s delegated click listener on
/// <code>.sa-message-transcript</code> when the operator clicks any
/// <code>.sa-citation-chip</code>. Dispatches by <code>type</code>:</p>
///
/// <ul>
/// <li><code>rule_log | event_log | message | ack | iolog</code> →
/// parent-panel navigation. Calls
/// <code>zenPage.svgPage.selectItem(null, parentType, null, id, klass, null)</code>
/// after mapping the chip-type to the parent's vocabulary
/// (<code>rule_log</code>→<code>rule</code>, <code>event_log</code>→
/// <code>event</code>, <code>iolog</code>→<code>ioLog</code>;
/// <code>message</code> and <code>ack</code> pass through). Per Task 0
/// probe of <code>irislib/EnsPortal/SVG/VisualTrace.cls</code> line
/// 2374, <code>selectItem(evt, type, svgId, itemId, extraType, lineId)</code>
/// sets <code>zenPage.currentId/currentType/currentClass</code> and
/// invokes <code>zenPage.updateTabs()</code> unconditionally — the SVG
/// highlight is best-effort (silently skipped when <code>svgId</code>
/// is null OR the row is not on the current SVG page). This handles
/// AC-2 (on-page) and AC-3 (off-page partial sync) in one call — no
/// try/catch needed; the parent does NOT throw on off-page items.</li>
/// <li><code>tool</code> → in-chat scroll-and-expand per AC-4. Lookup
/// strategy per the Carry-Forward decision (Path 2 — closes Story 3.2
/// reviewer's binding deferral about <code>data-tool-call-id="tc-N"</code>
/// vs LLM-emitted <code>data-cite-id</code>):
///   <ol>
///   <li>First, <code>document.querySelector('.sa-tool-call-card[data-tool-name="<id>"]')</code> — primary path (tool name match).</li>
///   <li>Else, <code>document.querySelector('.sa-tool-call-card[data-tool-call-id="<id>"]')</code> — fallback for the <code>[tool:tc-N]</code> LLM convention.</li>
///   <li>If neither match, console.warn (silent for the operator).</li>
///   </ol>
///   Limitation: when the same tool name appears multiple times in one
///   turn, the handler picks the FIRST matching card (querySelector
///   semantics). Re-defer to Epic 10 only if a real-world duplicate-
///   tool case surfaces. The lookup uses <code>CSS.escape()</code>
///   (Chrome 46+, Firefox 31+, Safari 10.1+, Edge 79+ — NFR-C6
///   evergreen-browser scope; no polyfill needed).</li>
/// </ul>
///
/// <p>The <code>klass</code> argument is the optional body-class name
/// from the citation chip's <code>data-cite-klass</code> attribute
/// (Story 3.4 AC-7 widened the regex to capture it). May be
/// <code>null</code> or empty when the LLM emits the short
/// <code>[message:42]</code> form; the parent's selectItem treats
/// missing extraType the same way ack-rendering will fall back to
/// the row's stored class.</p>
ClientMethod onCitationClick(type, id, klass) [ Language = javascript ]
{
    if (!type || !id) {
        return;
    }

    // Tool-type: in-chat scroll-and-expand. Lookup strategy per
    // Story 3.2 reviewer's deferred-work entry (Path 2 closure).
    if (type === 'tool') {
        var card = document.querySelector('.sa-tool-call-card[data-tool-name="' + CSS.escape(id) + '"]');
        if (!card) {
            // Fallback: the [tool:tc-N] LLM convention (dispatch-index match).
            card = document.querySelector('.sa-tool-call-card[data-tool-call-id="' + CSS.escape(id) + '"]');
        }
        if (!card) {
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[VisualTrace] onCitationClick(tool): no card matched id="' + id + '"');
            }
            return;
        }
        // Force-expand the <details> + scroll into view + 1-second
        // highlight flash via the sa-tool-card-highlight CSS rule
        // (UI/ChatPanel.cls EmitStyle()).
        card.open = true;
        card.scrollIntoView({behavior: 'smooth', block: 'nearest'});
        card.classList.add('sa-tool-card-highlight');
        setTimeout(function () {
            card.classList.remove('sa-tool-card-highlight');
        }, 1000);
        return;
    }

    // Parent-panel navigation types. Map chip-type vocabulary to the
    // parent's selectItem vocabulary (per Task 0 probe of
    // irislib/EnsPortal/VisualTrace.cls _contentIndex / _tabMap +
    // SVG/VisualTrace.cls selectItem signature).
    var parentTypeMap = {
        'rule_log': 'rule',
        'event_log': 'event',
        'message': 'message',
        'ack': 'ack',
        'iolog': 'ioLog'
    };
    var parentType = parentTypeMap[type];
    if (!parentType) {
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[VisualTrace] onCitationClick: unknown citation type "' + type + '"');
        }
        return;
    }

    // selectItem signature (verified Task 0):
    //   selectItem(evt, type, svgId, itemId, extraType, lineId)
    // We pass null for evt, svgId, lineId — we don't have an SVG event
    // and we don't know the SVG element ids from a citation chip.
    // The parent silently skips the SVG highlight when svgId is null
    // OR getElementById returns null (off-page case), AND ALWAYS sets
    // currentId/currentType/currentClass + calls updateTabs(). So the
    // single call covers AC-2 (on-page) AND AC-3 (off-page partial
    // sync) without needing try/catch detection.
    var trace = zen('SVGTrace');
    var svgPage = (trace && trace.svgWindow) ? trace.svgWindow.svgPage : null;
    var klassArg = klass || '';
    if (svgPage && typeof svgPage.selectItem === 'function') {
        svgPage.selectItem(null, parentType, null, id, klassArg, null);
        // selectItem internally invokes zenPage.updateTabs() — no
        // additional updateTabs call needed.
    } else {
        // Defense-in-depth: SVG frame not loaded yet (rare — chip
        // can't render before the agent answer, which can't render
        // before the page loaded the SVG frame). Set state directly
        // and call updateTabs(true) per AC-3 fallback.
        zenPage.currentId = id;
        zenPage.currentType = parentType;
        zenPage.currentClass = klassArg;
        if (typeof zenPage.updateTabs === 'function') {
            zenPage.updateTabs(true);
        }
    }
}

}
