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

    /* Citation-chip regex per AC-3. Pattern matches:
     *   [rule_log:...], [event_log:...], [message:...], [ack:...],
     *   [iolog:...], [tool:...]
     * Used by parseInlineCitations(). The regex literal is also inspected
     * by the AC-6 static-file validator. */
    var CITE_RE = /\[(rule_log|event_log|message|ack|iolog|tool):([^\]]+)\]/g;

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

        // AC-1 / UX-DR16: auto-focus on tab open.
        state.inputEl.focus();
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

    /**
     * Tokenize a string into text segments + citation chip <a> elements,
     * appending each to parentNode. Inline code-fence placeholders inside
     * paragraphs are rendered as inline <code> elements.
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
            var chip = document.createElement('a');
            var modifier = CITE_TYPE_TO_MODIFIER[citeType] || 'sa-cite-other';
            chip.setAttribute('class', 'sa-citation-chip ' + modifier);
            chip.setAttribute('href', '#');
            chip.setAttribute('data-cite-type', citeType);
            chip.setAttribute('data-cite-id', citeId);
            chip.textContent = '[' + citeType + ':' + citeId + ']';
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
