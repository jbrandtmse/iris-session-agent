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
/// </ul>
///
/// <p><b>Returns:</b> <code>$$$OK</code> on success; <code>$$$ERROR</code>
/// for parameter validation failures (only invariant: empty
/// <code>pAgentName</code>).</p>
ClassMethod DrawChatPanel(pAgentName As %String, pSessionKey As %String = "", pPortalUser As %String = "", pStream As %Stream.Object = "", pPriorTranscriptJson As %String = "[]", pPlaceholder As %String = "Ask anything about this session.") As %Status
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

}
