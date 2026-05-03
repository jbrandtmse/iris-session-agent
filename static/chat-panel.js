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
        inFlight: false       // true while a turn is mid-flight
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

        // AC-1 / UX-DR16: auto-focus on tab open. Per AC-3 ordering:
        // prior-transcript render must complete before focus so the input
        // is the operator's natural next action.
        state.inputEl.focus();
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
        block.textContent = "I can read this session's headers, bodies, event log, rule log, and BP state. " +
            "I can't change anything; I only read. " +
            "Try: what happened? · why did the rule fire? · show me the failing body.";
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

        if (typeof zenPage !== 'undefined' && zenPage && typeof zenPage.onCitationClick === 'function') {
            try {
                zenPage.onCitationClick(citeType, citeId, citeKlass);
            } catch (e) {
                if (typeof console !== 'undefined' && console.warn) {
                    console.warn('[chat-panel] zenPage.onCitationClick threw: ' + (e && e.message));
                }
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
        var contextHintsJson = '{}';

        // AC-1: invoke the ZenMethod hyperevent. Story 3.3 wires the
        // server-side SendChatMessage. The Zen synchronous-AJAX proxy
        // returns the ZenMethod's string return value directly.
        if (typeof zenPage !== 'undefined' && zenPage && typeof zenPage.SendChatMessage === 'function') {
            try {
                var envelopeJson = zenPage.SendChatMessage(agentName, sessionKey, userText, contextHintsJson);
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
                    handleEnvelope(hookEnvelope);
                } catch (e2) {
                    handleEnvelopeError(e2);
                }
            } else {
                handleEnvelopeError(new Error('zenPage.SendChatMessage unavailable'));
            }
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

        // AC-3: render the final assistant answer in fallback Markdown
        // mode. Use the helper that builds the DOM XSS-safely.
        var assistantMarkdown = (envelope && envelope.assistantMarkdown) || '';
        var assistantBlock = document.createElement('div');
        assistantBlock.setAttribute('class', 'sa-message-block sa-msg-agent');
        renderMarkdownFallback(assistantMarkdown, assistantBlock);
        state.transcriptEl.appendChild(assistantBlock);

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
     * AC-4: render an error block. error = {kind, message}. The message
     * is rendered as plain textContent so any provider-side strings
     * containing HTML are inert.
     */
    function renderErrorBlock(error) {
        var block = document.createElement('div');
        block.setAttribute('class', 'sa-message-block sa-msg-agent sa-msg-error');

        var text = document.createElement('span');
        text.setAttribute('class', 'sa-error-text');
        text.textContent = (error && error.message) || 'An error occurred.';
        block.appendChild(text);

        var hint = document.createElement('span');
        hint.setAttribute('class', 'sa-error-hint');
        hint.textContent = ' (Try resubmitting; if the error persists, check the agent configuration.)';
        block.appendChild(hint);

        state.transcriptEl.appendChild(block);
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
        summaryText.textContent = ' called ' + ((card && card.name) || '(unnamed)');
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
})();
