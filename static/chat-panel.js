/*
 * Session Agent — chat panel client (MVP, Story 3.2).
 *
 * Wired by:
 *   - Story 3.1's SessionAgent.EnsPortal.Util.ChatPanelDrawHelper, which
 *     emits the host HTML shell + the bootstrap-context inline script
 *     `window.SessionAgentChat = {agentName, sessionKey, portalUser}`.
 *   - Story 3.3's EnsPortal.VisualTrace subclass, which serves this file
 *     via `<script src="/csp/static/iris-session-agent/chat-panel.js">`
 *     and ships the `SendChatMessage` ZenMethod hyperevent.
 *   - Story 3.4 will wire the citation-chip onclick handler (parent-frame
 *     selectItem / updateTabs).
 *
 * XSS-safety invariants (AC-3 + AC-6):
 *   - ZERO inner-HTML assignment patterns. All DOM is built via
 *     createElement + setAttribute + textContent + appendChild.
 *   - ZERO dynamic-code-execution patterns.
 *   - ZERO CDN URLs (vendored only per NFR-C5).
 */
(function () {
    'use strict';

    /* ------------------------------------------------------------------ */
    /* Module-private state.                                               */
    /* ------------------------------------------------------------------ */
    var state = {
        context: null,        // window.SessionAgentChat snapshot
        inputEl: null,        // .sa-input-field textarea
        transcriptEl: null,   // .sa-message-transcript div
        statusEl: null,       // .sa-status-text div
        inFlight: false,      // true while a turn is mid-flight
        // Story 10.3 AC-3 — cache the most-recent agent turn's
        // toolCallsRendered[] for the click-through capture entry. The
        // cache is set at the END of handleEnvelope (after all rendering
        // completes) so a render-error path does NOT populate the cache
        // with a partially-processed envelope. Returning-conversation
        // transcripts loaded from Chat.History do NOT populate the cache
        // (they have no envelope) — clicks on those entries fire
        // RecordClickThrough with '[]' (empty contributing tool calls),
        // which Story 9.5's substrate handles per its AC-1 (no aliases
        // inferred → returns aliases_recorded: []; not an error).
        lastToolCallsRendered: [],
        // Story 10.4 AC-5 / AC-6 / AC-7 — from-search context cache.
        // Populated when init() detects fromSearchQuery in the bootstrap
        // context (UX-DR5 stripe rendered). Drained on the next
        // submitTurn() into the contextHintsJson payload (one-shot —
        // set to null after the turn fires so subsequent turns don't
        // re-send the search context). Cleared by the × Dismiss handler
        // so a dismissed stripe never carries through to the chat.
        fromSearchContext: null
    };

    /* Citation-chip regex per AC-3 (Story 3.2) extended in Story 3.4
     * AC-7 with an OPTIONAL third capture group for the body class
     * name (klass — the type the parent selectItem call needs to render
     * the Header tab for ack/iolog message-style rows). Pattern matches:
     *   [rule_log:42]                          (no klass)
     *   [message:42:Ens.MessageHeader]         (explicit klass)
     *   [event_log:7], [ack:5], [iolog:3], [tool:list_sessions]
     * The third group is optional — `[message:42]` still matches with
     * klass = undefined. Used by parseInlineCitations(). The regex
     * literal is also inspected by the AC-6 static-file validator
     * (Story 3.2) + the AC-8 klass-capture assertion (Story 3.4). */
    var CITE_RE = /\[(rule_log|event_log|message|ack|iolog|tool):([^\]:]+)(?::([^\]]+))?\]/g;

    /* Map of citation type -> short CSS modifier per AC-3:
     *   rule_log  -> sa-cite-rule
     *   event_log -> sa-cite-event
     *   message   -> sa-cite-message
     *   ack       -> sa-cite-ack
     *   iolog     -> sa-cite-iolog
     *   tool      -> sa-cite-tool */
    var CITE_TYPE_TO_MODIFIER = {
        'rule_log': 'sa-cite-rule',
        'event_log': 'sa-cite-event',
        'message': 'sa-cite-message',
        'ack': 'sa-cite-ack',
        'iolog': 'sa-cite-iolog',
        'tool': 'sa-cite-tool'
    };

    /* Code-fence regex: ```lang\n...\n``` — captures lang (optional) + body. */
    var CODE_FENCE_RE = /```([a-zA-Z0-9_+-]*)\n([\s\S]*?)\n```/g;

    /* Story 3.5 AC-5 — operator-readable error text per kind, keyed by
     * the canonical envelope `error.kind` values produced by the
     * AgentLoop / OpenAIProvider error envelopes:
     *   provider_timeout  — 90s cap exceeded (Story 2.9 OpenAIProvider).
     *   provider_error    — generic provider HTTP error.
     *   provider_auth     — 401/403 from provider (bad/missing API key).
     *   provider_rate_limit — 429 from provider.
     *   no_config         — agent not configured (caught fallback when
     *                       the EnsPortal.VisualTrace AC-4 server-side
     *                       no-config detection didn't fire — defense-
     *                       in-depth at the JS layer).
     *   internal          — defense-in-depth catch-all from the
     *                       SendChatMessage never-throw envelope.
     * Each entry is a function(error) -> string so per-kind retry hints
     * + provider/reason interpolation can vary. The UX-DR18-MVP-subset
     * spec text is preserved verbatim where possible. Unknown kinds
     * fall back to the generic message via renderErrorBlock. */
    var ERROR_KIND_TO_TEXT = {
        'provider_timeout': function (err) {
            return 'The LLM call exceeded 90 seconds. The provider may be overloaded or the question too complex. Try again or simplify.';
        },
        'provider_error': function (err) {
            var provider = (err && err.provider) || 'the provider';
            var reason = (err && err.message) || 'unknown error';
            return "Couldn't reach " + provider + ': ' + reason + ". Check the provider's status or your API key.";
        },
        'provider_auth': function (err) {
            var provider = (err && err.provider) || 'the provider';
            return "Couldn't authenticate to " + provider + '. Check your API key in the agent configuration.';
        },
        'provider_rate_limit': function (err) {
            var provider = (err && err.provider) || 'the provider';
            return provider + ' is rate-limiting requests. Wait a moment and try again.';
        },
        'no_config': function (err) {
            return "This agent isn't configured. An operator-admin needs to set up an LLM provider.";
        },
        'internal': function (err) {
            var msg = (err && err.message) || 'an unexpected error';
            return 'Something went wrong: ' + msg + '. See the audit log for details.';
        }
    };

    /* Story 10.2 AC-1 / AC-3 — IRIS Ens message-status enum mapped to
     * display labels for the search-result list rendering. The values are
     * the integers emitted by Epic 8 search tools' `structuredContent.sessions[].status`
     * field (verified Task 0 against SearchByStatus.cls:194). The Status:
     * column on each sa-search-result-entry shows the label, and entries
     * with status === 5 (Error) get the .sa-search-result-status-error
     * CSS class for the existing --sa-tool-card-status-error tint. Other
     * status values render with the default text color. The map is
     * declared at IIFE scope so it is shared by the renderer and the
     * aria-label builder. */
    var ENS_STATUS_LABEL = {
        1: 'Created',
        2: 'Queued',
        3: 'Delivered',
        4: 'Completed',
        5: 'Error',
        6: 'Aborted',
        7: 'Discarded',
        8: 'Suspended',
        9: 'Deferred'
    };

    /* ------------------------------------------------------------------ */
    /* Init: wait for DOMContentLoaded if needed, then wire handlers.      */
    /* ------------------------------------------------------------------ */
    function init() {
        if (typeof window === 'undefined') {
            return;
        }
        state.context = window.SessionAgentChat || null;
        if (!state.context) {
            // Bootstrap context absent — host page failed to emit it.
            // Surface a console warning, do NOT throw, so manual smoke
            // (Story 3.6) can still load the file and inspect handlers.
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[chat-panel] window.SessionAgentChat missing — bootstrap context not emitted');
            }
        }

        state.inputEl = document.querySelector('.sa-input-field');
        state.transcriptEl = document.querySelector('.sa-message-transcript');
        state.statusEl = document.querySelector('.sa-status-text');

        if (!state.inputEl || !state.transcriptEl || !state.statusEl) {
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[chat-panel] required DOM elements not found — sa-input-field / sa-message-transcript / sa-status-text');
            }
            return;
        }

        // AC-1: keydown handler — Enter -> submit, Shift+Enter -> default
        // newline, Esc -> no-op MVP (TODO Story 3.5+: cancel in-flight).
        state.inputEl.addEventListener('keydown', onKeyDown);

        // Story 3.4 AC-6: single delegated click listener on the
        // transcript that fires when the operator clicks any
        // .sa-citation-chip. The listener is attached to the parent
        // transcript element (not each chip) so it survives every
        // dynamically appended message block (operator turns, agent
        // turns, prior-transcript replays). Reads data-cite-type /
        // data-cite-id / data-cite-klass and dispatches to
        // zenPage.onCitationClick(type, id, klass) — the ClientMethod
        // shipped in Story 3.4 on SessionAgent.EnsPortal.VisualTrace.
        // Falls back to console.warn + window.SessionAgentChatTestHook
        // if zenPage is absent (Story 3.6 manual-smoke fixture pattern).
        state.transcriptEl.addEventListener('click', onTranscriptClick);

        // Story 3.3 AC-6 — apply the placeholder from the bootstrap context
        // (overrides Story 3.1's static HTML default). First-time vs
        // returning is decided server-side in EnsPortal.VisualTrace; we
        // just plumb the value into the input.
        var placeholder = state.context && state.context.placeholder;
        if (placeholder) {
            state.inputEl.setAttribute('placeholder', placeholder);
        }

        // Story 3.3 AC-3 / AC-4 — render the prior transcript (returning
        // conversation) OR the welcome message (first-time). The
        // priorTranscript is an array of {role, content} objects from
        // Chat.History.TurnsJson, flattened to chat-shape by the server.
        var priorTranscript = (state.context && state.context.priorTranscript) || [];
        if (priorTranscript.length > 0) {
            renderPriorTranscript(priorTranscript);
        } else {
            renderWelcomeMessage();
        }

        // Story 10.4 AC-3 — from-search stripe (UX-DR5). When the host
        // page came from a Search-Agent click-through, the bootstrap
        // context carries fromSearchQuery (literal operator query text)
        // and fromSearchKey (search-session key). Non-empty query → render
        // the stripe DOM ABOVE the transcript with three exits (Accept,
        // × Dismiss, implicit-accept on typing). Empty query → no stripe
        // (the typical Inspection-flow case).
        var fromSearchQuery = (state.context && state.context.fromSearchQuery) || '';
        var fromSearchKey = (state.context && state.context.fromSearchKey) || '';
        if (fromSearchQuery) {
            renderFromSearchStripe(fromSearchQuery, fromSearchKey);
        }

        // AC-1 / UX-DR16: auto-focus on tab open. Per AC-3 ordering:
        // prior-transcript render must complete before focus so the input
        // is the operator's natural next action.
        state.inputEl.focus();
    }

    /**
     * Story 10.4 AC-3 / AC-5 / AC-6 — render the "from search" stripe
     * above the chat transcript when the operator arrived via a Search-
     * Agent click-through. The stripe carries the literal search query
     * verbatim plus three exits:
     *
     *   - Accept button → fire an automatic agent turn with
     *     state.fromSearchContext attached as contextHints (AC-5).
     *   - × Dismiss button → silent dismiss; clear fromSearchContext so
     *     subsequent turns operate as a fresh chat (AC-6).
     *   - Implicit-accept on typing → submitTurn() drains
     *     fromSearchContext into the next turn's contextHints (AC-7).
     *
     * XSS-safety: createElement + textContent + setAttribute only — never
     * innerHTML. The literal query is HTML-escaped via textContent (the
     * browser does the encoding).
     */
    function renderFromSearchStripe(query, searchKey) {
        if (!state.transcriptEl || !state.transcriptEl.parentNode) {
            return;
        }
        // Seed state.fromSearchContext per AC-5 #2 / AC-7. The shape per
        // AC-8 is {from_search, search_query, search_session_key} — the
        // AgentLoop's contextHints already accepts arbitrary dict shapes
        // per Story 2.7's DTO contract; no orchestrator change needed.
        state.fromSearchContext = {
            from_search: true,
            search_query: query,
            search_session_key: searchKey || ''
        };

        var stripe = document.createElement('div');
        stripe.setAttribute('class', 'sa-from-search-stripe');
        stripe.setAttribute('role', 'status');
        stripe.setAttribute('aria-live', 'polite');
        stripe.setAttribute('data-search-key', searchKey || '');

        // Stripe text — literal query inserted via textContent so XSS-safe
        // even if the operator's search query contained HTML. The U+2014
        // EM DASH is the literal Unicode character (UTF-8 byte sequence
        // E2 80 94) per Rule 12 — not a hyphen-minus substitute.
        var textSpan = document.createElement('span');
        textSpan.setAttribute('class', 'sa-stripe-text');
        textSpan.textContent = "You came from a search for '" + query + "' — want me to look at this session?";
        stripe.appendChild(textSpan);

        // Accept button — AC-5.
        var acceptBtn = document.createElement('button');
        acceptBtn.setAttribute('class', 'sa-stripe-accept');
        acceptBtn.setAttribute('type', 'button');
        acceptBtn.textContent = 'Accept';
        acceptBtn.addEventListener('click', function () {
            // AC-5 #1 — hide the stripe.
            if (stripe.parentNode) {
                stripe.parentNode.removeChild(stripe);
            }
            // AC-5 #3 — pre-fill the input + AC-5 #4 — submitTurn() drains
            // state.fromSearchContext into contextHintsJson on the next
            // call. The synthesized prompt is the simplest path per AC-5.
            if (state.inputEl) {
                state.inputEl.value = "Look at this session in the context of my earlier search.";
            }
            submitTurn();
        });
        stripe.appendChild(acceptBtn);

        // × Dismiss button — AC-6.
        var dismissBtn = document.createElement('button');
        dismissBtn.setAttribute('class', 'sa-stripe-dismiss');
        dismissBtn.setAttribute('type', 'button');
        dismissBtn.setAttribute('aria-label', 'Dismiss from-search context');
        dismissBtn.textContent = '×'; // U+00D7 MULTIPLICATION SIGN — the canonical close glyph.
        dismissBtn.addEventListener('click', function () {
            // AC-6 #1 — hide the stripe.
            if (stripe.parentNode) {
                stripe.parentNode.removeChild(stripe);
            }
            // AC-6 #2 — clear fromSearchContext so subsequent turns run
            // with empty contextHints. Per AC-6 #3 the stripe stays
            // hidden for the rest of the chat session — the parentNode
            // removal above is the implementation.
            state.fromSearchContext = null;
        });
        stripe.appendChild(dismissBtn);

        // Insert ABOVE the transcript so the stripe occupies the top of
        // the panel chrome. The transcript element is a direct child of
        // .sa-chat-panel; insert the stripe as the previous sibling.
        state.transcriptEl.parentNode.insertBefore(stripe, state.transcriptEl);
    }

    /**
     * Story 3.3 AC-3 — render the prior conversation as a sequence of
     * sa-message-block elements. Operator turns render plain; agent turns
     * use the Markdown fallback path (citation chips, code fences). After
     * the loop, scroll the transcript to the bottom so the most recent
     * message is visible.
     *
     * The priorTranscript shape is the simplified chat-form
     * [{role: "operator|agent", content: "..."}], NOT the canonical
     * Anthropic shape persisted in Chat.History.TurnsJson — the server
     * (EnsPortal.VisualTrace.DrawChatPanel) flattens it before embedding
     * in the bootstrap context.
     */
    function renderPriorTranscript(turns) {
        for (var i = 0; i < turns.length; i++) {
            var turn = turns[i];
            if (!turn || !turn.role) {
                continue;
            }
            var role = turn.role;
            var content = turn.content || '';
            var block = document.createElement('div');
            block.setAttribute('class', 'sa-message-block sa-msg-' + role);
            if (role === 'agent') {
                // Use the Markdown fallback path so citation chips +
                // code fences render correctly in the prior transcript.
                renderMarkdownFallback(content, block);
            } else {
                // Operator turns are plain text per Story 3.1's
                // submitTurn() echo path.
                block.textContent = content;
            }
            state.transcriptEl.appendChild(block);
        }
        // Scroll to most-recent message (AC-3).
        state.transcriptEl.scrollTop = state.transcriptEl.scrollHeight;
    }

    /**
     * Story 3.3 AC-4 — first-time welcome message rendered as a regular
     * sa-message-block sa-msg-agent (NOT a separate splash component per
     * UX-DR17). Approximately 3 lines covering capability summary +
     * read-only assertion + 3 example questions. Pure textContent — no
     * inner-HTML, citation chips, or markdown rendering needed for the
     * static welcome.
     */
    function renderWelcomeMessage() {
        var block = document.createElement('div');
        block.setAttribute('class', 'sa-message-block sa-msg-agent');
        block.textContent = "Ask anything about this session OR about other sessions across this IRIS instance. I'm read-only — I can't change anything. " +
            "Try: what happened in this session? · which messages had errors? · find sessions matching X.";
        state.transcriptEl.appendChild(block);
    }

    function onKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            submitTurn();
            return;
        }
        if (event.key === 'Escape') {
            // TODO Story 3.5+: cancel in-flight turn. MVP no-ops Esc:
            // when no turn is in flight Esc does nothing; when one IS in
            // flight, the operator must wait for it to complete. The
            // cancel ZenMethod is not yet shipped.
            return;
        }
        // Shift+Enter and all other keys: default textarea behavior.
    }

    /**
     * Story 3.4 AC-6 — delegated click listener on the transcript.
     * Detects clicks on any .sa-citation-chip (using closest() so a
     * click inside the chip's textContent still resolves to the chip
     * element), preventDefault()'s the anchor's native href="#"
     * navigation, then dispatches to zenPage.onCitationClick(type, id,
     * klass). Falls back to console.warn + window.SessionAgentChatTestHook
     * when zenPage.onCitationClick is unavailable (Story 3.6 manual-smoke
     * fixture pattern, mirroring the submitTurn() fallback).
     */
    function onTranscriptClick(event) {
        // Story 10.2 AC-4 — search-result-entry click delegation. Parallel
        // to the existing .sa-citation-chip branch below: detect clicks
        // on any .sa-search-result-entry anchor and dispatch to the stub
        // handler. Story 10.3 will replace the stub body with the actual
        // RecordClickThrough hyperevent + navigation. The function-name
        // boundary `onSearchResultClick` is the load-bearing contract.
        var entry = event.target && event.target.closest && event.target.closest('.sa-search-result-entry');
        if (entry) {
            onSearchResultClick(entry, event);
            return;
        }

        var chip = event.target && event.target.closest && event.target.closest('.sa-citation-chip');
        if (!chip) {
            return;
        }
        // Prevent the browser from following href="#" (which would scroll
        // the page to the top + push a history entry).
        event.preventDefault();

        var citeType = chip.getAttribute('data-cite-type');
        var citeId = chip.getAttribute('data-cite-id');
        var citeKlass = chip.getAttribute('data-cite-klass'); // null when absent — handler treats as ""

        // Story 4.0 AC-6 (1) — validate before dispatching. For id-bearing
        // citation types (message / session / process — and the existing
        // typed citations rule_log / event_log / message / ack / iolog),
        // the id MUST be a non-empty numeric string. Invent / drift bugs
        // in the LLM output produce empty or non-numeric ids; without
        // this guard we'd dispatch the bad value into zenPage.onCitationClick
        // which then throws or silently no-ops, leaving the operator
        // staring at an unresponsive chip with no feedback.
        // The 'tool' citation type is exempt because tool ids may be
        // string names (e.g., "list_sessions") not numeric tc-N indices.
        if (!isCitationDispatchable(citeType, citeId)) {
            surfaceCitationErrorNotice(chip);
            return;
        }

        if (typeof zenPage !== 'undefined' && zenPage && typeof zenPage.onCitationClick === 'function') {
            try {
                zenPage.onCitationClick(citeType, citeId, citeKlass);
            } catch (e) {
                if (typeof console !== 'undefined' && console.warn) {
                    console.warn('[chat-panel] zenPage.onCitationClick threw: ' + (e && e.message));
                }
                // Story 4.0 AC-6 (2) — surface a user-visible notice when
                // zenPage.onCitationClick throws. The previous behavior
                // only logged to console; the operator saw nothing change
                // when they clicked the chip. Now they get a visible cue
                // that something went wrong and they can move on or retry.
                surfaceCitationErrorNotice(chip);
            }
            return;
        }

        // Story 3.6 manual smoke / non-Zen-page load fallback.
        if (typeof console !== 'undefined' && console.warn) {
            console.warn('[chat-panel] zenPage.onCitationClick unavailable — citation chip click ignored');
        }
        if (typeof window.SessionAgentChatTestHook === 'function') {
            try {
                // Re-use Story 3.2's hook pattern for testability; the
                // hook receives the same 3 args the ClientMethod would.
                window.SessionAgentChatTestHook(citeType, citeId, citeKlass);
            } catch (e2) {
                // Swallow — the hook is test-only.
            }
        }
    }

    /**
     * Story 4.0 AC-6 (1) — determine whether a (type, id) pair is safe to
     * dispatch into zenPage.onCitationClick. Returns false for empty/null
     * ids on every type, and false for non-numeric ids on the typed
     * id-bearing citation types. Returns true for the 'tool' citation
     * type when the id is non-empty, regardless of numeric-ness, because
     * tool ids may be either tc-N synthetic indices OR plain tool names.
     */
    function isCitationDispatchable(citeType, citeId) {
        if (citeId == null || citeId === '') {
            return false;
        }
        if (citeType === 'tool') {
            // Tool citations may be 'tc-3' or 'list_sessions' — any
            // non-empty string passes validation. The downstream
            // onCitationClick handles the lookup-or-fallback.
            return true;
        }
        // For numeric id-bearing types, require pure digits. Reject
        // negative numbers, decimals, scientific notation, leading/
        // trailing whitespace — the underlying ObjectId is a positive
        // integer. /^\d+$/ is intentionally strict.
        return /^\d+$/.test(citeId);
    }

    /**
     * Story 4.0 AC-6 (1) + (2) + (3) — surface a user-visible notice that
     * a citation chip click failed (validation rejection OR parent-side
     * dispatch throw). The notice is an inline span appended to the
     * chip's parent paragraph (NOT in place of the chip itself), so the
     * original citation chip stays clickable for retry. Dedup: if the
     * same chip already has a notice attached, do not duplicate it on
     * subsequent clicks.
     *
     * The notice text is fixed and pre-translated (no template
     * substitution of untrusted LLM strings). Construction is
     * createElement + textContent — XSS-safe.
     */
    function surfaceCitationErrorNotice(chip) {
        if (!chip) {
            return;
        }
        // Dedup: a single chip emits at most one notice. Use a chip-level
        // flag so subsequent clicks no-op without piling up notices in
        // the transcript.
        if (chip.getAttribute('data-cite-error-shown') === '1') {
            return;
        }
        chip.setAttribute('data-cite-error-shown', '1');

        var notice = document.createElement('span');
        notice.setAttribute('class', 'sa-citation-error');
        notice.setAttribute('role', 'alert');
        notice.textContent = " Couldn't resolve this citation — the agent may have referenced a missing or malformed id.";

        // Append to the chip's parent (typically a <p> from the markdown
        // fallback render). Falls back to the chip's parentNode if the
        // closest('p') walk returns null (defensive).
        var host = (chip.closest && chip.closest('p')) || chip.parentNode;
        if (host && host.appendChild) {
            host.appendChild(notice);
        }
    }

    /* ------------------------------------------------------------------ */
    /* Submit path.                                                        */
    /* ------------------------------------------------------------------ */
    function submitTurn() {
        if (state.inFlight) {
            return;
        }
        var userText = state.inputEl.value;
        if (!userText || !userText.replace(/\s+/g, '').length) {
            return;
        }

        // Append the operator's question to the transcript first so they
        // see immediate confirmation that it landed.
        var operatorBlock = document.createElement('div');
        operatorBlock.setAttribute('class', 'sa-message-block sa-msg-operator');
        operatorBlock.textContent = userText;
        state.transcriptEl.appendChild(operatorBlock);

        // Clear input + show "Thinking..." + disable input per AC-5.
        state.inputEl.value = '';
        state.statusEl.textContent = 'Thinking...';
        state.inputEl.disabled = true;
        state.inFlight = true;

        var agentName = (state.context && state.context.agentName) || '';
        var sessionKey = (state.context && state.context.sessionKey) || '';

        // Story 10.4 AC-7 / AC-8 — merge state.fromSearchContext (set by
        // init() when the bootstrap context's fromSearchQuery is non-
        // empty) into the contextHintsJson payload. Implicit-accept (the
        // operator types before clicking either stripe button) and
        // explicit-accept (Accept button) both drain the context here;
        // dismiss-then-type runs with the empty default. After the turn
        // fires we hide the stripe (treated as implicit accept per AC-7)
        // and null fromSearchContext for one-shot consumption.
        var contextHintsJson = '{}';
        var fromSearchAttached = false;
        if (state.fromSearchContext) {
            try {
                contextHintsJson = JSON.stringify(state.fromSearchContext);
                fromSearchAttached = true;
            } catch (e) {
                // Defense-in-depth — fromSearchContext is a plain object
                // we constructed ourselves so JSON.stringify can't throw
                // in practice. The fallback empty-object payload still
                // sends the turn with no hints rather than blocking it.
                contextHintsJson = '{}';
            }
        }

        // AC-1: invoke the ZenMethod hyperevent. Story 3.3 wires the
        // server-side SendChatMessage. The Zen synchronous-AJAX proxy
        // returns the ZenMethod's string return value directly.
        //
        // Story 10.4 review F-1 — track whether the dispatch into the
        // orchestrator actually fired. A JS-side throw (network blip,
        // zenPage stub missing) means the turn never reached
        // SendChatMessage and the contextHints were not consumed. In
        // that case we MUST keep state.fromSearchContext populated so
        // the operator's retry attempt re-sends the context. A returned
        // envelope (success OR server-rendered error envelope) means
        // the orchestrator ran — drain the one-shot per AC-7.
        var turnDispatched = false;
        if (typeof zenPage !== 'undefined' && zenPage && typeof zenPage.SendChatMessage === 'function') {
            try {
                var envelopeJson = zenPage.SendChatMessage(agentName, sessionKey, userText, contextHintsJson);
                turnDispatched = true;
                handleEnvelope(envelopeJson);
            } catch (e) {
                handleEnvelopeError(e);
            }
        } else {
            // Story 3.6 manual smoke / non-Zen-page load: zenPage absent.
            // Surface a console warning + render an info block so the
            // operator sees that the call site is wired but the host
            // didn't supply the ZenMethod proxy. The handlers are still
            // attached so input still echoes; only the dispatch is shorted.
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[chat-panel] zenPage.SendChatMessage unavailable — running outside a Zen page');
            }
            // Manual-smoke test hook: a smoke test driver may install
            // window.SessionAgentChatTestHook(agentName, sessionKey,
            // userText, contextHintsJson) to synthesize an envelope.
            // Documented in Completion Notes — not load-bearing in
            // production.
            if (typeof window.SessionAgentChatTestHook === 'function') {
                try {
                    var hookEnvelope = window.SessionAgentChatTestHook(agentName, sessionKey, userText, contextHintsJson);
                    turnDispatched = true;
                    handleEnvelope(hookEnvelope);
                } catch (e2) {
                    handleEnvelopeError(e2);
                }
            } else {
                handleEnvelopeError(new Error('zenPage.SendChatMessage unavailable'));
            }
        }

        // Story 10.4 AC-7 — implicit-accept cleanup. If fromSearchContext
        // was attached to this turn AND the dispatch reached the
        // orchestrator, hide the stripe (if still present — explicit
        // Accept already removed it) and null the context so subsequent
        // turns don't re-send it. AC-7 spec: "the stripe is hidden
        // (treated as implicit Accept). And state.fromSearchContext =
        // null after the turn fires (one-shot consumption)." Review F-1:
        // gate on turnDispatched so a JS-side throw (no envelope ever
        // returned, contextHints never reached the orchestrator) does
        // NOT drop the search context — the operator's retry must
        // re-send it.
        if (fromSearchAttached && turnDispatched) {
            var stripeEl = document.querySelector('.sa-from-search-stripe');
            if (stripeEl && stripeEl.parentNode) {
                stripeEl.parentNode.removeChild(stripeEl);
            }
            state.fromSearchContext = null;
        }
    }

    function handleEnvelope(envelopeJson) {
        var envelope;
        try {
            envelope = JSON.parse(envelopeJson);
        } catch (parseErr) {
            handleEnvelopeError(parseErr);
            return;
        }

        if (envelope && envelope.error) {
            renderErrorBlock(envelope.error);
            finishTurn();
            return;
        }

        // AC-2: render tool-call cards in dispatch order.
        var cards = (envelope && envelope.toolCallsRendered) || [];
        for (var i = 0; i < cards.length; i++) {
            var cardNode = renderToolCard(cards[i], i);
            state.transcriptEl.appendChild(cardNode);
        }

        // Story 10.2 AC-1 — Search-Agent rendering: scan toolCallsRendered[]
        // for any tool whose result.structuredContent.sessions is an array.
        // Per AC-1's structural-signal contract, the tool name is NOT part
        // of the detection — Epic 8 search tools are the canonical
        // producers of sessions[] arrays and Inspection tools never emit
        // this shape, so the structural signal is sufficient and forward-
        // compatible (any future search tool that emits sessions[] gets
        // the curated-list rendering automatically). Render the curated
        // list BEFORE the assistantMarkdown block so the visual order is
        // [tool-cards] -> [curated session list] -> [agent narrative].
        for (var k = 0; k < cards.length; k++) {
            var card = cards[k];
            var sc = card && card.result && card.result.structuredContent;
            if (sc && Array.isArray(sc.sessions)) {
                // Skip the empty-sessions[] case per AC-5 — the agent's
                // assistantMarkdown carries the no-match narrative + any
                // refinement suggestions; rendering an empty <a> list
                // would just be visual noise.
                if (sc.sessions.length === 0) {
                    continue;
                }
                var totalCount = (typeof sc.result_count === 'number') ? sc.result_count : sc.sessions.length;
                var limitArg = (card.args && typeof card.args.limit === 'number') ? card.args.limit : 0;
                renderSearchResultList(k, sc.sessions, totalCount, limitArg);
            }
        }

        // AC-3: render the final assistant answer in fallback Markdown
        // mode. Use the helper that builds the DOM XSS-safely.
        var assistantMarkdown = (envelope && envelope.assistantMarkdown) || '';
        var assistantBlock = document.createElement('div');
        assistantBlock.setAttribute('class', 'sa-message-block sa-msg-agent');
        renderMarkdownFallback(assistantMarkdown, assistantBlock);
        state.transcriptEl.appendChild(assistantBlock);

        // Story 10.3 AC-3 — cache the most-recent agent turn's
        // toolCallsRendered[] for the click-through capture path. Set
        // AFTER all rendering completes so a render-error path doesn't
        // populate the cache with a partially-processed envelope. Each
        // operator turn overwrites the previous cache; the click handler
        // (onSearchResultClick) reads it to assemble contributingToolCalls.
        state.lastToolCallsRendered = (envelope && envelope.toolCallsRendered) || [];

        finishTurn();
    }

    function handleEnvelopeError(err) {
        var msg = (err && err.message) || 'Unknown error';
        renderErrorBlock({ kind: 'provider_error', message: msg });
        finishTurn();
    }

    function finishTurn() {
        // AC-5: clear status text, re-enable + refocus input.
        state.statusEl.textContent = '';
        state.inputEl.disabled = false;
        state.inFlight = false;
        // UX-DR16: refocus after every Enter submission.
        state.inputEl.focus();
    }

    /* ------------------------------------------------------------------ */
    /* Render helpers — all XSS-safe (createElement + textContent only).   */
    /* ------------------------------------------------------------------ */

    /**
     * Story 3.5 AC-5 (extends Story 3.2 AC-4) — render an error block.
     * error = {kind, message, provider?}. The kind is looked up in
     * ERROR_KIND_TO_TEXT for an operator-readable message + per-kind
     * retry hint. Unknown kinds fall back to the generic
     * "Something went wrong: <message>" pattern.
     *
     * The message is rendered as plain textContent so any provider-side
     * strings containing HTML are inert (XSS-safety per Story 3.2 AC-3).
     */
    function renderErrorBlock(error) {
        var block = document.createElement('div');
        block.setAttribute('class', 'sa-message-block sa-msg-agent sa-msg-error');

        var text = document.createElement('span');
        text.setAttribute('class', 'sa-error-text');

        // Story 3.5 AC-5: look up by kind. Unknown kinds fall through to
        // the generic message which preserves the prior Story 3.2 shape
        // (so existing behavior is backward-compatible when kind is
        // missing or unrecognized).
        var kind = error && error.kind;
        var renderer = kind && ERROR_KIND_TO_TEXT[kind];
        if (renderer) {
            text.textContent = renderer(error);
        } else {
            text.textContent = 'Something went wrong: ' + ((error && error.message) || 'unknown error');
        }
        block.appendChild(text);

        // Per-kind retry hints already live inside the ERROR_KIND_TO_TEXT
        // renderers; the generic .sa-error-hint span stays only for the
        // unknown-kind path so the operator still sees a recovery cue.
        if (!renderer) {
            var hint = document.createElement('span');
            hint.setAttribute('class', 'sa-error-hint');
            hint.textContent = ' (Try resubmitting; if the error persists, check the agent configuration.)';
            block.appendChild(hint);
        }

        state.transcriptEl.appendChild(block);
    }

    /**
     * Story 4.0 AC-5 — extract a human-readable error preview from a
     * tool-call card for display in the COLLAPSED card summary.
     *
     * Returns a non-empty string (truncated to 80 chars + ellipsis when
     * longer) when ALL of the following are true:
     *   1. card.status === 'error'
     *   2. card.result is a non-null object
     *   3. card.result.content is a non-empty array
     *   4. card.result.content[0].type === 'text'
     *   5. card.result.content[0].text is a non-empty string
     *
     * Returns the empty string for any shape mismatch — the caller falls
     * back to the prior "called <name>" wording. Never throws; never
     * inspects untrusted strings beyond .substring (which can't crash on
     * any String value). The result is consumed via textContent — no
     * markup interpretation, XSS-safe by construction.
     */
    function extractToolErrorPreview(card) {
        if (!card || card.status !== 'error') {
            return '';
        }
        var result = card.result;
        if (!result || typeof result !== 'object') {
            return '';
        }
        var content = result.content;
        if (!content || !content.length) {
            return '';
        }
        var first = content[0];
        if (!first || first.type !== 'text') {
            return '';
        }
        var text = first.text;
        if (typeof text !== 'string' || !text.length) {
            return '';
        }
        if (text.length > 80) {
            return text.substring(0, 80) + '…';
        }
        return text;
    }

    /**
     * AC-2: render one tool-call card. card shape per Agent.TurnResult
     * DTO (Story 2.7, verified Task 0): {name, args, result, status}.
     * status is "ok" or "error" in the actual DTO. The CSS tokens shipped
     * by Story 3.1's SessionAgent.UI.ChatPanel are
     * --sa-tool-card-status-{running|complete|error} (UX-design-spec lines
     * 625-627). Map DTO status into the CSS modifier name to preserve the
     * spec'd CSS taxonomy:
     *   ok    -> complete
     *   error -> error
     *   (no DTO value maps to "running" today — the AgentLoop blocks
     *    until each tool returns; "running" is reserved for a future
     *    streaming/async dispatch surface.)
     *
     * The dispatchIndex is used as the data-tool-call-id (the actual DTO
     * does not ship an id field; Story 3.4's chip handler can lookup by
     * index). The synthetic "tc-{index}" id is stable within a single
     * turn render.
     */
    function renderToolCard(card, dispatchIndex) {
        var statusVal = (card && card.status) || 'ok';
        var statusModifier = statusVal === 'error' ? 'error' : 'complete';
        var details = document.createElement('details');
        details.setAttribute('class', 'sa-tool-call-card sa-tool-card-status-' + statusModifier);
        details.setAttribute('data-tool-call-id', 'tc-' + dispatchIndex);
        // Story 3.4 AC-4 / Carry-Forward (Path 2 — tool-name lookup): tag
        // each card with data-tool-name="<card.name>" so the citation-chip
        // click handler in onCitationClick can find the matching card by
        // name (primary lookup). The dispatch-index data-tool-call-id stays
        // as the fallback (Path 1) for the [tool:tc-N] LLM convention.
        // Limitation (documented per spec): when the same tool name is
        // called multiple times in one turn, the handler picks the FIRST
        // matching card. Re-deferred to Epic 10 if real-world duplicate-
        // tool-name turns surface — this story doesn't pre-defer. Use
        // setAttribute (auto-encodes) — never string-concat into HTML
        // (XSS-safety per Story 3.2 AC-3 / Story 3.4 Dev Notes).
        details.setAttribute('data-tool-name', (card && card.name) || '');

        var summary = document.createElement('summary');

        var statusIndicator = document.createElement('span');
        statusIndicator.setAttribute('class', 'sa-tool-card-status-indicator');
        statusIndicator.textContent = statusVal === 'error' ? '!' : 'OK';
        summary.appendChild(statusIndicator);

        var nameEl = document.createElement('code');
        nameEl.setAttribute('class', 'sa-tool-name');
        nameEl.textContent = (card && card.name) || '(unnamed)';
        summary.appendChild(nameEl);

        var summaryText = document.createElement('span');
        summaryText.setAttribute('class', 'sa-tool-summary');
        // Story 4.0 AC-5 — validator-rejection visibility in COLLAPSED state.
        // When the tool returned an error envelope and the first content block
        // is a text block (the canonical Anthropic / OpenAI tool_result shape
        // emitted by Tool.Base.WrapError), prepend the first 80 chars of
        // that text to the summary so the operator sees the validation
        // message without having to expand the card. Keep the trailing
        // " called <name>" so the tool identity stays visible. XSS-safety
        // preserved (textContent only). Defensive: any shape mismatch falls
        // back to the prior "called <name>" wording.
        var errorPreview = extractToolErrorPreview(card);
        if (errorPreview) {
            summaryText.textContent = errorPreview + ' — called ' + ((card && card.name) || '(unnamed)');
        } else {
            summaryText.textContent = ' called ' + ((card && card.name) || '(unnamed)');
        }
        summary.appendChild(summaryText);

        details.appendChild(summary);

        // Body: args (input) + result, both as <pre><code>JSON</code></pre>.
        var argsLabel = document.createElement('div');
        argsLabel.setAttribute('class', 'sa-tool-section-label');
        argsLabel.textContent = 'args:';
        details.appendChild(argsLabel);

        var argsBlock = document.createElement('pre');
        var argsCode = document.createElement('code');
        argsCode.textContent = stringifySafe(card && card.args);
        argsBlock.appendChild(argsCode);
        details.appendChild(argsBlock);

        var resultLabel = document.createElement('div');
        resultLabel.setAttribute('class', 'sa-tool-section-label');
        resultLabel.textContent = 'result:';
        details.appendChild(resultLabel);

        var resultBlock = document.createElement('pre');
        var resultCode = document.createElement('code');
        resultCode.textContent = stringifySafe(card && card.result);
        resultBlock.appendChild(resultCode);
        details.appendChild(resultBlock);

        return details;
    }

    /**
     * AC-3 fallback render: split markdown on \n\n into paragraphs,
     * extract code fences first (so their contents don't get re-parsed
     * for citations), then within each paragraph tokenize citation chips.
     * All construction via createElement / textContent — no innerHTML.
     */
    function renderMarkdownFallback(markdown, parentNode) {
        if (!markdown) {
            return;
        }

        // First pass: extract code fences. Replace each fence with a
        // placeholder token "CB{idx}"; we'll re-insert the
        // <pre><code> nodes during the paragraph walk.
        var codeBlocks = [];
        var withPlaceholders = markdown.replace(CODE_FENCE_RE, function (_match, lang, body) {
            var idx = codeBlocks.length;
            codeBlocks.push({ lang: lang || '', body: body });
            return 'CB' + idx + '';
        });

        var paragraphs = withPlaceholders.split(/\n\n+/);
        for (var p = 0; p < paragraphs.length; p++) {
            var para = paragraphs[p];
            if (!para.length) {
                continue;
            }
            // If the paragraph IS a placeholder, render the matching
            // code block as a top-level <pre><code>.
            var cbMatch = para.match(/^CB(\d+)$/);
            if (cbMatch) {
                var cb = codeBlocks[parseInt(cbMatch[1], 10)];
                var pre = document.createElement('pre');
                var code = document.createElement('code');
                if (cb.lang) {
                    code.setAttribute('class', 'language-' + cb.lang);
                }
                code.textContent = cb.body;
                pre.appendChild(code);
                parentNode.appendChild(pre);
                continue;
            }
            // Otherwise render as <p> with inline citation tokenization.
            var pNode = document.createElement('p');
            parseInlineCitations(para, pNode, codeBlocks);
            parentNode.appendChild(pNode);
        }
    }

    /* Citation type -> aria-label template per Story 3.4 AC-5 + UX-DR20-MVP.
     * Each entry is a function (id) -> "...". Templates intentionally end
     * with the verb the click action triggers ("view in Header tab" /
     * "scroll to card") so screen-reader users hear the navigation
     * promise before the chip fires. Per AC-5 the chip is a real <a>;
     * the aria-label REPLACES the chip's textContent for screen-reader
     * announcement (the visual textContent stays the canonical bracket
     * form so sighted users see the citation as it appears in the
     * Markdown). */
    var CITE_TYPE_TO_ARIA = {
        'rule_log': function (id) { return 'Rule log entry ' + id + ' — view in Header tab'; },
        'event_log': function (id) { return 'Event log entry ' + id + ' — view in Header tab'; },
        'message': function (id) { return 'Message ' + id + ' — view in Header tab'; },
        'ack': function (id) { return 'ACK message ' + id + ' — view in Header tab'; },
        'iolog': function (id) { return 'IO log entry ' + id + ' — view in Header tab'; },
        'tool': function (id) { return 'Tool call ' + id + ' — scroll to card'; }
    };

    /**
     * Tokenize a string into text segments + citation chip <a> elements,
     * appending each to parentNode. Inline code-fence placeholders inside
     * paragraphs are rendered as inline <code> elements.
     *
     * Story 3.4 AC-7 extension: the regex captures an OPTIONAL third
     * group `klass` (the parent body-class name needed by selectItem's
     * `extraType` parameter — see Story 3.4 Task 0 probe of
     * irislib/EnsPortal/SVG/VisualTrace.cls). When the third group
     * matches, the chip gets `data-cite-klass="<klass>"`; otherwise the
     * attribute is omitted. Story 3.4 AC-5 / UX-DR20-MVP: every chip
     * also gets a descriptive `aria-label` per citation type.
     *
     * XSS-safety preserved (Story 3.2 AC-3): all attribute writes use
     * setAttribute (auto-encodes); textContent is the only text-node
     * sink. The new data-cite-klass + aria-label values come from
     * LLM-emitted strings (untrusted) but never string-concat into HTML.
     */
    function parseInlineCitations(text, parentNode, codeBlocks) {
        // Walk: alternate plain text + citation matches.
        var lastIdx = 0;
        // Reset regex lastIndex (it's a /g regex shared across calls).
        CITE_RE.lastIndex = 0;
        var match;
        while ((match = CITE_RE.exec(text)) !== null) {
            if (match.index > lastIdx) {
                appendTextWithInlineCode(text.substring(lastIdx, match.index), parentNode, codeBlocks);
            }
            var citeType = match[1];
            var citeId = match[2];
            var citeKlass = match[3]; // undefined when 3rd group absent
            var chip = document.createElement('a');
            var modifier = CITE_TYPE_TO_MODIFIER[citeType] || 'sa-cite-other';
            chip.setAttribute('class', 'sa-citation-chip ' + modifier);
            chip.setAttribute('href', '#');
            chip.setAttribute('data-cite-type', citeType);
            chip.setAttribute('data-cite-id', citeId);
            // Story 3.4 AC-7: only set data-cite-klass when the optional
            // 3rd capture group matched. setAttribute auto-encodes the
            // (untrusted) LLM value — XSS-safe.
            if (citeKlass) {
                chip.setAttribute('data-cite-klass', citeKlass);
            }
            // Story 3.4 AC-5: descriptive aria-label per citation type
            // (UX-DR20-MVP). The id is interpolated by the template
            // function — setAttribute auto-encodes.
            var ariaFn = CITE_TYPE_TO_ARIA[citeType];
            if (ariaFn) {
                chip.setAttribute('aria-label', ariaFn(citeId));
            }
            // Visual textContent: preserve the canonical bracket form
            // (with klass when present, matching the Markdown source).
            var visualText = '[' + citeType + ':' + citeId + (citeKlass ? ':' + citeKlass : '') + ']';
            chip.textContent = visualText;
            parentNode.appendChild(chip);
            lastIdx = match.index + match[0].length;
        }
        if (lastIdx < text.length) {
            appendTextWithInlineCode(text.substring(lastIdx), parentNode, codeBlocks);
        }
    }

    /**
     * Append a text segment to parentNode. Inline code-fence placeholders
     * within the segment become inline <code> elements (rare — most code
     * fences span their own paragraph, but this handles the edge case).
     */
    function appendTextWithInlineCode(text, parentNode, codeBlocks) {
        var inlineRe = /CB(\d+)/g;
        var lastIdx = 0;
        var match;
        while ((match = inlineRe.exec(text)) !== null) {
            if (match.index > lastIdx) {
                parentNode.appendChild(document.createTextNode(text.substring(lastIdx, match.index)));
            }
            var cb = codeBlocks[parseInt(match[1], 10)];
            var code = document.createElement('code');
            if (cb.lang) {
                code.setAttribute('class', 'language-' + cb.lang);
            }
            code.textContent = cb.body;
            parentNode.appendChild(code);
            lastIdx = match.index + match[0].length;
        }
        if (lastIdx < text.length) {
            parentNode.appendChild(document.createTextNode(text.substring(lastIdx)));
        }
    }

    /* ------------------------------------------------------------------ */
    /* Story 10.2 — Search-Agent curated-list rendering.                   */
    /* ------------------------------------------------------------------ */

    /**
     * Story 10.2 AC-2 / AC-3 — render a curated list of session entries
     * as <a class="sa-search-result-entry"> anchors appended to the
     * transcript, between the tool-call cards and the agent's narrative.
     *
     * Each entry is a real anchor (display: block via the CSS rule from
     * Story 10.2 AC-7) so the entire row is clickable and keyboard-default
     * focusable per UX-DR20. Visible columns per AC-3 in order:
     *   1. SessionId (bold)
     *   2. TimeCreated relative form (`3 minutes ago`); absolute ISO Z on title attribute
     *   3. Source -> Target arrow with <no-source> fallback
     *   4. MessageBodyClassName (full FQN, truncated to 40 chars + ellipsis)
     *   5. Status display label from ENS_STATUS_LABEL; status === 5 (Error)
     *      gets sa-search-result-status-error class
     *   6. (MVP-deferred) brief context — slot-only; no per-session
     *      annotation comes from AgentLoop today (per AC-3 #6)
     *
     * Columns separated by U+00B7 middle dot ` · ` matching the welcome
     * message convention; UTF-8 encoding via the asset's TranslateTable=UTF8.
     *
     * AC-6 — when totalCount > limitArg, append a single
     * <div class="sa-search-truncation-note"> after the list with the
     * "Showing first N of M" message. The agent's assistantMarkdown will
     * also mention truncation per the AgentLoop prompt template; this
     * extra DOM block makes the visual marker explicit per UX-DR29.
     *
     * XSS-safety: entirely createElement + textContent + setAttribute. No
     * innerHTML, no string-concat into HTML attributes (setAttribute
     * auto-encodes).
     */
    function renderSearchResultList(tcIndex, sessions, totalCount, limitArg) {
        if (!sessions || !sessions.length) {
            return;
        }
        var searchSessionKey = (state.context && state.context.sessionKey) || '';
        for (var i = 0; i < sessions.length; i++) {
            var s = sessions[i];
            if (!s) {
                continue;
            }
            var anchor = document.createElement('a');
            anchor.setAttribute('class', 'sa-search-result-entry');
            anchor.setAttribute('href', '#');
            anchor.setAttribute('data-session-id', String(s.session_id != null ? s.session_id : ''));
            anchor.setAttribute('data-search-session-key', searchSessionKey);
            anchor.setAttribute('data-tool-call-index', String(tcIndex));

            var sourceName = s.source_config_name || '<no-source>';
            var targetName = s.target_config_name || '<no-target>';
            var bodyClass = s.message_body_class_name || '';
            var statusLabel = ENS_STATUS_LABEL[s.status] || ('Unknown(' + s.status + ')');
            var relTime = formatRelativeTime(s.time_created);
            var absTime = s.time_created || '';

            // aria-label per AC-2 — descriptive, no separators in the
            // screen-reader announcement so the synthesizer can parse
            // each clause naturally.
            var aria = 'Session ' + (s.session_id != null ? s.session_id : 'unknown')
                + ' from ' + sourceName + ' to ' + targetName
                + ', ' + bodyClass
                + ', Status: ' + statusLabel
                + ', ' + relTime;
            anchor.setAttribute('aria-label', aria);

            // Title attribute carries the absolute ISO Z timestamp for
            // hover-reveal (sighted users see the relative form by
            // default; hovering the anchor reveals the precise time).
            if (absTime) {
                anchor.setAttribute('title', absTime);
            }

            // Column 1: SessionId (bold via .sa-search-result-sid).
            var sidSpan = document.createElement('span');
            sidSpan.setAttribute('class', 'sa-search-result-sid');
            sidSpan.textContent = 'Session ' + (s.session_id != null ? s.session_id : 'unknown');
            anchor.appendChild(sidSpan);

            anchor.appendChild(document.createTextNode(' · '));

            // Column 2: relative time (absolute on the anchor's title).
            anchor.appendChild(document.createTextNode(relTime));

            anchor.appendChild(document.createTextNode(' · '));

            // Column 3: Source -> Target with arrow.
            anchor.appendChild(document.createTextNode(sourceName + ' → ' + targetName));

            anchor.appendChild(document.createTextNode(' · '));

            // Column 4: MessageBodyClassName, truncated to 40 chars.
            anchor.appendChild(document.createTextNode(truncateClassName(bodyClass, 40)));

            anchor.appendChild(document.createTextNode(' · '));

            // Column 5: Status label, with .sa-search-result-status-error
            // when status === 5 (Error).
            var statusSpan = document.createElement('span');
            if (s.status === 5) {
                statusSpan.setAttribute('class', 'sa-search-result-status-error');
            }
            statusSpan.textContent = 'Status: ' + statusLabel;
            anchor.appendChild(statusSpan);

            // Column 6 (MVP-deferred): brief context — no AgentLoop
            // emission today; slot intentionally empty per AC-3 #6.

            state.transcriptEl.appendChild(anchor);
        }

        // AC-6 — truncation marker DOM block. Emitted when totalCount
        // exceeds limitArg AND limitArg is positive (limitArg=0 means the
        // tool call did not pass an explicit limit, so we cannot prove
        // truncation occurred — defer to the assistantMarkdown narrative).
        if (limitArg > 0 && totalCount > limitArg) {
            var note = document.createElement('div');
            note.setAttribute('class', 'sa-search-truncation-note');
            note.textContent = 'Showing first ' + sessions.length + ' of ' + totalCount + ' matches — refine your query to narrow results.';
            state.transcriptEl.appendChild(note);
        }
    }

    /**
     * Story 10.2 AC-3 — convert an ISO Z timestamp string to a relative
     * form like "3 minutes ago", "2 hours ago", "5 days ago". For
     * deltas beyond 30 days the absolute ISO date (YYYY-MM-DD) is
     * returned so the operator still gets a recognizable temporal cue
     * without unwieldy "1247 days ago" strings.
     *
     * Returns "(unknown time)" for null/empty/unparseable input — the
     * UI fallback so a missing timestamp doesn't break the entry render.
     */
    function formatRelativeTime(isoZ) {
        if (!isoZ) {
            return '(unknown time)';
        }
        var t = Date.parse(isoZ);
        if (isNaN(t)) {
            return '(unknown time)';
        }
        var deltaMs = Date.now() - t;
        // Guard against future timestamps (clock skew, fixture drift).
        if (deltaMs < 0) {
            deltaMs = 0;
        }
        var seconds = Math.floor(deltaMs / 1000);
        if (seconds < 60) {
            return seconds === 1 ? '1 second ago' : seconds + ' seconds ago';
        }
        var minutes = Math.floor(seconds / 60);
        if (minutes < 60) {
            return minutes === 1 ? '1 minute ago' : minutes + ' minutes ago';
        }
        var hours = Math.floor(minutes / 60);
        if (hours < 24) {
            return hours === 1 ? '1 hour ago' : hours + ' hours ago';
        }
        var days = Math.floor(hours / 24);
        if (days <= 30) {
            return days === 1 ? '1 day ago' : days + ' days ago';
        }
        // Beyond 30 days — show absolute date (first 10 chars of ISO Z = YYYY-MM-DD).
        return isoZ.substring(0, 10);
    }

    /**
     * Story 10.2 AC-3 column 4 — truncate a class FQN to maxChars
     * characters, appending a U+2026 ellipsis when truncation occurred.
     * Empty / null input returns the empty string (the column renders
     * blank rather than emitting "..." with no content).
     */
    function truncateClassName(fqn, maxChars) {
        if (!fqn) {
            return '';
        }
        if (fqn.length <= maxChars) {
            return fqn;
        }
        return fqn.substring(0, maxChars) + '…';
    }

    /**
     * Story 10.3 AC-2 / AC-3 / AC-4 / AC-5 — search-result-entry click
     * handler. Replaces Story 10.2's stub body.
     *
     * Called by onTranscriptClick when the operator clicks any
     * .sa-search-result-entry anchor. Execution sequence:
     *   1. event.preventDefault() — suppress the default href="#" jump.
     *   2. Read data-session-id / data-search-session-key /
     *      data-tool-call-index attributes from the anchor.
     *   3. Assemble contributingToolCalls[] by mapping
     *      state.lastToolCallsRendered into the {tool_name, args, result}
     *      shape Story 9.5's substrate expects (AC-3).
     *   4. Fire-and-forget zenPage.RecordClickThrough(searchSessionKey,
     *      sessionId, JSON.stringify(contributingToolCalls)) wrapped in
     *      try/catch — any throw is logged via console.warn but the
     *      operator MUST navigate even if vocabulary capture fails (AC-5).
     *   5. Construct the destination URL (HealthShare-aware via path
     *      detection, AC-4) and set window.location.href.
     *
     * UX-DR25 fire-and-forget: NO confirmation message; navigate
     * immediately after the hyperevent call returns to the JS event loop.
     *
     * The function-name boundary is the load-bearing surface contract:
     * onTranscriptClick dispatches by name.
     */
    function onSearchResultClick(anchor, event) {
        if (event && typeof event.preventDefault === 'function') {
            event.preventDefault();
        }
        if (!anchor || typeof anchor.getAttribute !== 'function') {
            return;
        }
        var sessionId = anchor.getAttribute('data-session-id') || '';
        var searchSessionKey = anchor.getAttribute('data-search-session-key') || '';
        var tcIndex = anchor.getAttribute('data-tool-call-index') || '';

        // Story 10.3 AC-3 — assemble contributingToolCalls[] from the
        // cached most-recent agent turn's toolCallsRendered[]. Map each
        // tool-call card to the {tool_name, args, result} triple Story 9.5
        // expects. Empty cache (e.g., click on a returning-conversation
        // entry that loaded from Chat.History without re-issuing a search)
        // produces an empty array; Story 9.5's substrate handles that
        // correctly per its AC-1.
        var cached = state.lastToolCallsRendered || [];
        var contributingToolCalls = [];
        for (var i = 0; i < cached.length; i++) {
            var tc = cached[i];
            if (!tc) {
                continue;
            }
            contributingToolCalls.push({
                tool_name: tc.name,
                args: tc.args,
                result: tc.result
            });
        }

        // Story 10.3 AC-5 — fire-and-forget the hyperevent. Wrap in
        // try/catch so a throw (network error, missing zenPage, 500
        // response) is logged but does NOT block the navigation that
        // follows. The operator MUST reach Visual Trace even if
        // vocabulary capture fails.
        try {
            if (typeof zenPage !== 'undefined' && zenPage && typeof zenPage.RecordClickThrough === 'function') {
                zenPage.RecordClickThrough(searchSessionKey, sessionId, JSON.stringify(contributingToolCalls));
            } else if (typeof console !== 'undefined' && console.warn) {
                console.warn('[sa-search] zenPage.RecordClickThrough unavailable — capture skipped, proceeding with navigation');
            }
        } catch (captureErr) {
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[sa-search] RecordClickThrough threw — proceeding with navigation:', captureErr);
            }
        }

        // Manual-smoke / test fixture hook: a smoke driver may install
        // window.SessionAgentSearchClickTestHook(sessionId, tcIndex,
        // contributingToolCalls, destinationUrl) to assert click handling.
        // Production never installs it. We delay the test-hook call until
        // after the destinationUrl is computed below so smokes can assert
        // on the URL too.

        // Story 10.3 AC-4 — construct the destination URL with the
        // HealthShare-vs-plain-IRIS prefix detection. The pattern matches
        // Story 1.5's installer-printed bookmark patterns (verbatim) with
        // the added FROM_SEARCH query param so Story 10.4 can render the
        // "from search" stripe on the Visual Trace destination page.
        var currentPath = (typeof window !== 'undefined' && window.location && window.location.pathname) || '';
        var isHealthShare = currentPath.indexOf('/csp/healthshare/') === 0;
        var nsMatch = currentPath.match(/\/csp\/(?:healthshare\/)?([^/]+)\//);
        var ns = nsMatch ? nsMatch[1] : 'hscustom';
        var prefix = isHealthShare ? '/csp/healthshare/' + ns : '/csp/' + ns;
        var destinationUrl = prefix + '/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=' + encodeURIComponent(sessionId) + '&FROM_SEARCH=' + encodeURIComponent(searchSessionKey);

        // Test-hook firing AFTER destinationUrl is built — gives smokes
        // visibility into all 4 load-bearing values without re-deriving
        // them.
        if (typeof window !== 'undefined' && typeof window.SessionAgentSearchClickTestHook === 'function') {
            try {
                window.SessionAgentSearchClickTestHook(sessionId, tcIndex, contributingToolCalls, destinationUrl);
            } catch (e) {
                // Swallow — test-only hook.
            }
        }

        // Navigate. Per UX-DR25, no confirmation surface; the operator
        // arrives on the Visual Trace tab silently.
        if (typeof window !== 'undefined' && window.location) {
            window.location.href = destinationUrl;
        }
    }

    /**
     * Append a generic message block (helper documented in spec). Not
     * called by the current submit path — kept available for Story 3.4+
     * extensions (e.g., system-message blocks).
     */
    function appendMessageBlock(role, contentNode) {
        var block = document.createElement('div');
        block.setAttribute('class', 'sa-message-block sa-msg-' + role);
        block.appendChild(contentNode);
        state.transcriptEl.appendChild(block);
        return block;
    }

    /**
     * Explicit text-escaping helper per spec. Sets textContent — the
     * browser does the encoding. The function exists for clarity at
     * call sites (e.g., escapeText(node, untrustedString) reads more
     * intentionally than node.textContent = untrustedString).
     */
    function escapeText(node, text) {
        node.textContent = text == null ? '' : String(text);
    }

    /**
     * JSON-stringify a value safely for display. Returns "(none)" for
     * null/undefined; falls back to String() if JSON.stringify throws
     * (cyclic refs, etc.).
     */
    function stringifySafe(value) {
        if (value === null || value === undefined) {
            return '(none)';
        }
        try {
            return JSON.stringify(value, null, 2);
        } catch (e) {
            return String(value);
        }
    }

    /* ------------------------------------------------------------------ */
    /* Boot.                                                               */
    /* ------------------------------------------------------------------ */
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // No exported API — module is self-contained. The optional manual-
    // smoke hook (window.SessionAgentChatTestHook) is consulted but
    // never installed by us.
    // Suppress unused-helper warnings by referencing them in a no-op
    // closure (helps static analyzers; runtime cost is zero).
    void appendMessageBlock;
    void escapeText;
    // Story 10.2 — `renderSearchResultList` is invoked by handleEnvelope
    // and `onSearchResultClick` is invoked by onTranscriptClick, so they
    // are NOT unused. The void-references below are defensive against
    // tree-shaking analyzers that may not trace dynamic dispatch through
    // the closure-scoped delegation. Helper functions formatRelativeTime
    // and truncateClassName are reachable through renderSearchResultList,
    // so no separate void references are needed for them.
    void renderSearchResultList;
    void onSearchResultClick;
    // Story 10.4 — renderFromSearchStripe is invoked by init() when the
    // bootstrap context carries fromSearchQuery; the void reference is
    // defensive against tree-shaking analyzers that may not trace dynamic
    // dispatch through the closure-scoped delegation.
    void renderFromSearchStripe;
})();
