/// <p>Static HTML draw helper for the Session Agent chat panel — the
/// single entry point both the Inspection (Story 3.3) and Search (Epic 10)
/// EnsPortal subclasses call to emit the panel's semantic shell into a
/// host page. Per architecture §"Project Directory Structure" both classes
/// (this helper plus <CLASS>SessionAgent.UI.ChatPanel</CLASS>) live under
/// <code>SessionAgent.*</code> and are shared between the two future portal
/// subclasses — keep them inspection-agnostic.</p>
///
/// <p>The emitted structure (per Story 3.1 AC-1):</p>
/// <pre>
/// &lt;section role="region" aria-label="Agent chat panel" class="sa-chat-panel"&gt;
///   &lt;div class="sa-message-transcript"&gt;&lt;/div&gt;
///   &lt;div class="sa-status-text" aria-live="polite"&gt;&lt;/div&gt;
///   &lt;form class="sa-input-area"&gt;
///     &lt;textarea class="sa-input-field" aria-label="Ask anything about this session"
///               placeholder="Ask anything about this session."&gt;&lt;/textarea&gt;
///   &lt;/form&gt;
///   &lt;script&gt;window.SessionAgentChat = {agentName:"...",sessionKey:"...",portalUser:"...",priorTranscript:[],placeholder:"..."};&lt;/script&gt;
/// &lt;/section&gt;
/// </pre>
///
/// <p>The bootstrap-context <code>&lt;script&gt;</code> block is the only
/// inline JS the helper emits — script-source inclusion (the
/// <code>&lt;script src="chat-panel.js"&gt;</code> for Story 3.2) is the
/// host page's responsibility (Story 3.3 wires it via
/// <code>%OnDrawHTMLHead</code>). Per AC-2
/// the bootstrap values are JSON-encoded via <code>%DynamicObject.%ToJSON()</code>
/// to defeat XSS at the script-data boundary; we additionally post-process
/// any literal <code>&lt;/script&gt;</code> substring into the JSON-valid
/// escape <code>&lt;\/script&gt;</code> to defeat script-tag-break-out
/// (the case AC-5's XSS probe asserts).</p>
///
/// <p><b>Bootstrap-context extension (Story 3.3 AC-6).</b> The bootstrap
/// object now includes two additional fields: <code>priorTranscript</code>
/// (an array of <code>{role, content}</code> turns from the operator's
/// prior conversation, or empty array for first-time) and
/// <code>placeholder</code> (the input-field placeholder text — first-time
/// vs returning variant). Story 3.2's chat-panel.js init reads these and
/// renders either the welcome message (empty transcript) or the prior
/// turns (non-empty), then sets the input placeholder. The two new
/// parameters default to first-time-empty / first-time-placeholder so
/// Story 3.1's existing 4 tests (which call the 4-arg form) still pass
/// untouched.</p>
///
/// <p><b>Output channel.</b> By default the helper writes to the current
/// device using the Zen <code>&amp;html&lt;...&gt;</code> macro — this is
/// the canonical live-portal usage from inside an
/// <code>&lt;html OnDrawContent="..."/&gt;</code> Zen callback. For
/// testability the helper accepts an optional
/// <code>pStream As %Stream.Object</code>; when supplied the helper writes
/// to the stream instead of the current device. Tests pass a
/// <code>%Stream.GlobalCharacter</code>, inspect its buffered contents
/// after the call, and assert the rendered output. (Choice documented in
/// Completion Notes — pStream-based capture chosen over $IO mnemonic-space
/// redirection because the latter is fragile under the test harness's own
/// output capture.)</p>
///
/// <p>References:</p>
/// <ul>
/// <li>Story 3.1 spec AC-1, AC-2, AC-5.</li>
/// <li>Story 3.3 spec AC-6 (bootstrap extension for prior transcript).</li>
/// <li><code>irislib/EnsPortal/VisualTrace.cls</code> §<code>DrawTraceTop</code>
/// (line 693) — canonical <code>&amp;html&lt;...&gt;</code> output pattern
/// for an EnsPortal helper.</li>
/// <li><code>irislib/EnsPortal/Application.cls</code> — parent Zen
/// application (verified existing via Task 0 probe).</li>
/// <li>Project rule §"<code>%DynamicObject</code> Iterator Safety" — we
/// build the bootstrap object once and never iterate-and-mutate.</li>
/// </ul>
Class SessionAgent.EnsPortal.Util.ChatPanelDrawHelper Extends %RegisteredObject
{

/// <p>Emit the chat panel's static HTML shell. Writes to the current
/// device via <code>&amp;html&lt;...&gt;</code> by default, OR to
/// <code>pStream</code> if supplied (for testability).</p>
///
/// <p><b>Parameters:</b></p>
/// <ul>
/// <li><code>pAgentName</code> — short name of the bound agent
/// (e.g. <code>"session-inspection"</code>). Required; empty raises an
/// error status.</li>
/// <li><code>pSessionKey</code> — Ens session-key the chat is anchored to.
/// May be empty (e.g. when the host page hasn't selected a session yet).</li>
/// <li><code>pPortalUser</code> — IRIS portal username the chat history
/// should attribute turns to. May be empty (e.g. first-install / not-yet-
/// logged-in states).</li>
/// <li><code>pStream</code> — optional <code>%Stream.Object</code>. When
/// supplied, the helper writes the rendered HTML to it. When omitted the
/// helper writes to the current device via the <code>&amp;html</code>
/// macro.</li>
/// <li><code>pPriorTranscriptJson</code> — Story 3.3 AC-6. Optional JSON
/// string of an array of <code>{role, content}</code> turns from the
/// operator's prior conversation. Defaults to <code>"[]"</code>
/// (first-time, no prior conversation). Parsed once via
/// <code>%FromJSON</code> and embedded into the bootstrap object as the
/// <code>priorTranscript</code> field. Malformed JSON falls back to
/// empty-array semantics rather than raising — the panel is still usable
/// even if the prior-conversation surfacing fails (FR37 graceful
/// degradation).</li>
/// <li><code>pPlaceholder</code> — Story 3.3 AC-6. Optional input-field
/// placeholder text. Defaults to
/// <code>"Ask anything about this session."</code> (first-time variant).
/// Story 3.3 supplies <code>"Continue the conversation."</code> for
/// returning conversations per UX-DR17-MVP-subset.</li>
/// <li><code>pFromSearchQuery</code> — Story 10.4 AC-2. Optional literal
/// search query text (the verbatim first-user-message from the search
/// session's <CLASS>SessionAgent.Chat.History</CLASS>). When non-empty,
/// the bootstrap context emits <code>fromSearchQuery: "&lt;text&gt;"</code>
/// and <code>chat-panel.js</code> renders the "from search" stripe per
/// UX-DR5. Defaults to <code>""</code> for back-compat with the
/// Inspection-non-hand-off path AND the Search-Agent's MessageViewer host
/// page (which never passes this).</li>
/// <li><code>pFromSearchKey</code> — Story 10.4 AC-2. Optional search-
/// session key (the value the FROM_SEARCH URL param carried). Embedded
/// in the bootstrap context so the JS click handlers and the stripe DOM's
/// <code>data-search-key</code> attribute carry the search context into
/// the next <code>contextHints</code> turn. Defaults to <code>""</code>.</li>
/// </ul>
///
/// <p><b>Returns:</b> <code>$$$OK</code> on success; <code>$$$ERROR</code>
/// for parameter validation failures (only invariant: empty
/// <code>pAgentName</code>).</p>
ClassMethod DrawChatPanel(pAgentName As %String, pSessionKey As %String = "", pPortalUser As %String = "", pStream As %Stream.Object = "", pPriorTranscriptJson As %String = "[]", pPlaceholder As %String = "Ask anything about this session.", pFromSearchQuery As %String = "", pFromSearchKey As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        ; Parameter validation — only empty agent name is an invariant
        ; violation per Story 3.1 AC-1 / Task 1.
        If $Get(pAgentName) = "" {
            Set tSC = $$$ERROR($$$GeneralError, "DrawChatPanel: pAgentName is required")
            Quit
        }

        ; Build the JSON-encoded bootstrap context per AC-2. Use
        ; %DynamicObject.%ToJSON() — produces JSON-object-literal-safe
        ; output. Post-process the </script> escape per AC-5: %ToJSON
        ; does NOT escape the literal "</script>" substring, which would
        ; allow script-tag break-out if a value contains it. The escape
        ; "<\/script>" is JSON-string-valid (the JSON spec permits "\/"
        ; as an escape for "/") and breaks the HTML parser's lookahead
        ; for </script>.
        Set tCtx = ##class(%DynamicObject).%New()
        Do tCtx.%Set("agentName", pAgentName)
        Do tCtx.%Set("sessionKey", pSessionKey)
        Do tCtx.%Set("portalUser", pPortalUser)

        ; Story 3.3 AC-6 — embed prior transcript as a parsed array. If
        ; the input is not parseable JSON (corruption / caller bug) we
        ; degrade to an empty array rather than raising — the panel must
        ; still render even if the prior-conversation surfacing fails
        ; (FR37 graceful degradation). The %ToJSON re-serialization
        ; preserves the array shape.
        Set tPrior = ##class(%DynamicArray).%New()
        If pPriorTranscriptJson '= "" {
            Try {
                Set tParsed = ##class(%DynamicArray).%FromJSON(pPriorTranscriptJson)
                If $IsObject(tParsed) {
                    Set tPrior = tParsed
                }
            }
            Catch parseEx {
                ; Swallow — fall through to empty-array default. The
                ; panel still renders the welcome message; the operator
                ; sees a fresh-conversation experience instead of a
                ; broken page.
            }
        }
        Do tCtx.%Set("priorTranscript", tPrior)

        ; Story 3.3 AC-6 — embed placeholder. Story 3.3's caller decides
        ; first-time vs returning variant; we pass through verbatim.
        Do tCtx.%Set("placeholder", pPlaceholder)

        ; Story 10.4 AC-2 — embed the from-search literal query + the
        ; search-session key. chat-panel.js init reads both: when
        ; fromSearchQuery is non-empty it renders the stripe DOM (UX-DR5)
        ; and seeds state.fromSearchContext so the next submitTurn() pass
        ; carries the search context into the AgentLoop's contextHints
        ; (AC-8). Both default to "" — the inspection-non-hand-off path
        ; AND the Search-Agent's MessageViewer host page leave them empty
        ; and the panel renders without the stripe.
        Do tCtx.%Set("fromSearchQuery", pFromSearchQuery)
        Do tCtx.%Set("fromSearchKey", pFromSearchKey)

        Set tBootstrapJson = tCtx.%ToJSON()
        Set tBootstrapJson = $Replace(tBootstrapJson, "</script>", "<\/script>")

        ; Emit either to the supplied stream OR to the current device.
        ; The shape is identical; only the write channel differs. Keeping
        ; both paths in this method (rather than a helper) keeps the HTML
        ; shape singular — there is exactly one source of truth for the
        ; rendered structure.
        If $IsObject(pStream) {
            Do pStream.Write("<section role=""region"" aria-label=""Agent chat panel"" class=""sa-chat-panel"">")
            Do pStream.Write("<div class=""sa-message-transcript""></div>")
            Do pStream.Write("<div class=""sa-status-text"" aria-live=""polite""></div>")
            Do pStream.Write("<form class=""sa-input-area"">")
            Do pStream.Write("<textarea class=""sa-input-field"" aria-label=""Ask anything about this session"" placeholder=""Ask anything about this session.""></textarea>")
            Do pStream.Write("</form>")
            Do pStream.Write("<script>window.SessionAgentChat = " _ tBootstrapJson _ ";</script>")
            Do pStream.Write("</section>")
        } Else {
            &html<<section role="region" aria-label="Agent chat panel" class="sa-chat-panel">>
            &html<<div class="sa-message-transcript"></div>>
            &html<<div class="sa-status-text" aria-live="polite"></div>>
            &html<<form class="sa-input-area">>
            &html<<textarea class="sa-input-field" aria-label="Ask anything about this session" placeholder="Ask anything about this session."></textarea>>
            &html<</form>>
            &html<<script>window.SessionAgentChat = #(tBootstrapJson)#;</script>>
            &html<</section>>
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Story 3.5 AC-1 / AC-4 — emit the config-empty prompt instead of
/// the chat shell when no <CLASS>SessionAgent.Config.Agent</CLASS> row
/// exists for the bound agent OR the row is disabled. Replaces the
/// transcript area + disables the input field per UX-DR7-admin.</p>
///
/// <p><b>Two variants:</b></p>
/// <ul>
/// <li><b>Admin variant</b> (<var>pIsAdmin</var>=1): the prompt names
/// the future Epic 6 config page (<code>SessionAgent.UI.AgentConfig.zen</code>)
/// as a placeholder URL with a "coming in Epic 6" caveat. Operators
/// with <code>%All</code> see actionable language.</li>
/// <li><b>Non-admin variant</b> (<var>pIsAdmin</var>=0): the prompt
/// reads *"This agent isn't configured yet. Ask your operator-admin."*
/// — no link, no actionable language. Aligns with UX-DR7-admin (only
/// admins see the configuration link).</li>
/// </ul>
///
/// <p><b>Accessibility (UX-DR20-MVP):</b> the prompt has
/// <code>role="alert"</code> so screen readers announce the empty state
/// on tab open. The input field has <code>aria-disabled="true"</code>
/// plus the visual de-emphasis CSS class
/// <code>sa-input-field-disabled</code> (Story 3.5 AC-1 +
/// <CLASS>SessionAgent.UI.ChatPanel</CLASS> CSS additions).</p>
///
/// <p><b>NO bootstrap script.</b> chat-panel.js does NOT initialize in
/// this state — the input field is disabled, the transcript is replaced
/// by the prompt, and there's no submit affordance. Skipping the
/// bootstrap also avoids the <code>SessionAgentChat</code> global being
/// emitted with empty values that could confuse a future smoke test.</p>
ClassMethod EmitConfigEmpty(pAgentName As %String, pIsAdmin As %Boolean = 0) As %Status
{
    Set tSC = $$$OK
    Try {
        If $Get(pAgentName) = "" {
            Set tSC = $$$ERROR($$$GeneralError, "EmitConfigEmpty: pAgentName is required")
            Quit
        }

        ; Emit the panel shell with the prompt replacing the transcript +
        ; disabled input. The shape matches DrawChatPanel's wrapper so
        ; CSS selectors like .sa-chat-panel still apply (UX-DR7-admin
        ; says "replace transcript area"; we keep the panel chrome and
        ; replace the inner content).
        ;
        ; Admin variant (Story 6.3 AC-1): a real <a> anchor pointing to
        ; the namespace-scoped AgentConfig zen page replaces the Story 3.5
        ; placeholder bare-text reference. The href interpolates
        ; $ZConvert($NAMESPACE, "L") so multi-namespace installs (Story 6.4)
        ; route correctly. The U+2192 RIGHTWARDS ARROW glyph is the literal
        ; Unicode character (UTF-8 byte sequence E2 86 92) per Rule 12 —
        ; NOT an ASCII '->' substitute. UX-DR19 requires a real <a>;
        ; UX-DR20 requires aria-label="Configure agent".
        ;
        ; Non-admin variant (UX-DR7-admin): unchanged from Story 3.5 — no
        ; link, just the "Ask your operator-admin." guidance.
        &html<<section role="region" aria-label="Agent chat panel" class="sa-chat-panel">>
        If pIsAdmin {
            Set tNsLower = $ZConvert($NAMESPACE, "L")
            &html<<div class="sa-config-empty-prompt" role="alert">This agent isn't configured yet. <a href="/csp/#(tNsLower)#/SessionAgent.UI.AgentConfig.zen" aria-label="Configure agent">Configure agent →</a></div>>
        } Else {
            Set tPromptText = "This agent isn't configured yet. Ask your operator-admin."
            &html<<div class="sa-config-empty-prompt" role="alert">#($ZConvert(tPromptText, "O", "HTML"))#</div>>
        }
        &html<<form class="sa-input-area">>
        &html<<textarea class="sa-input-field sa-input-field-disabled" aria-label="Agent not configured" aria-disabled="true" disabled></textarea>>
        &html<</form>>
        &html<</section>>
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
