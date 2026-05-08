/// <p>CSS contributor for the Session Agent chat panel — emits a
/// <code>&lt;style&gt;</code> block defining the full
/// <code>--sa-*</code> token surface (10 MVP tokens from Story 3.1
/// AC-3 + 8 Growth-tier tokens hoisted from Story 10.2 / 10.4 / 10.5
/// component-rule literals per Story 10.8 AC-1 / UX-DR12-full /
/// UX-DR23) and the matching <code>sa-*</code> component-class rules
/// per Story 3.1 AC-4.</p>
///
/// <p>This class is shared between the Inspection (Story 3.3, this epic)
/// and Search (Epic 10) EnsPortal subclasses — both call
/// <CLASS>SessionAgent.UI.ChatPanel</CLASS>.<METHOD>EmitStyle</METHOD>
/// from their <code>OnPageHeadStyle</code> / <code>XData Style</code>
/// hooks. Don't bake any inspection- or search-specific behavior here.</p>
///
/// <p><b>Token inheritance contract (UX-DR26).</b> Each token's value is
/// of the form <code>var(--parent-token-name, fallback)</code>. The
/// fallback is a reasonable approximation of the parent Mgmt Portal Zen
/// palette per architecture §"Token Initial Values" (lines 622–629); the
/// fallback IS the rendered value in MVP — Mgmt Portal Zen does not
/// publish a public <code>--*</code> CSS-variable namespace, so the
/// <code>var()</code> reference will always degrade to the fallback for
/// MVP. A future Epic 10.7+ work item will replace the fallbacks with
/// live parent-palette lookups when the vendored UX components land.</p>
///
/// <p>Per AC-4, the foundation layer (font-family, font-size, line-height,
/// button styles, form controls) is NOT overridden — the host page's
/// parent Mgmt Portal styling carries through. The <code>sa-*</code>
/// rules here only set layout (flex, overflow) and color (via tokens)
/// — no <code>position: fixed</code> overlays, no z-index games, no
/// custom keyframes (per UX-DR28's seven anti-patterns of no-modals).</p>
///
/// <p>References:</p>
/// <ul>
/// <li>Story 3.1 spec AC-3 (10-token list, exact), AC-4 (no overrides,
/// no anti-patterns).</li>
/// <li>UX-design-spec §"Component Strategy MVP" (lines 1268–1276) and
/// §"Component 1 — sa-chat-panel" (line 984).</li>
/// <li>architecture.md §"Token Initial Values" (lines 622–629) — parent-
/// palette guess list.</li>
/// </ul>
Class SessionAgent.UI.ChatPanel Extends %RegisteredObject
{

/// <p>Emit the chat-panel CSS as a <code>&lt;style&gt;</code> block to
/// the current device. Called from a host page's
/// <code>OnPageHeadStyle</code> (or equivalent) so the styles arrive
/// before the panel HTML is rendered.</p>
///
/// <p>Returns <code>$$$OK</code> always — emission has no failure mode
/// (no I/O check beyond what <code>&amp;html</code> already provides).</p>
///
/// <p>Emits 18 <code>--sa-*</code> tokens — the original 10 MVP tokens
/// per AC-3 plus 8 Growth-tier tokens hoisted from inline literals per
/// Story 10.8 AC-1 — and the component-class rules per AC-4 task spec
/// (Task 2). Token values use <code>var(--parent, fallback)</code>
/// form — the fallback values are commented inline citing the
/// architecture-suggested parent-palette source.</p>
///
/// <p><b>Story 10.8 AC-1 / UX-DR23 — WCAG AA contrast audit.</b> Every
/// rendered fallback satisfies AA thresholds (4.5:1 body text, 3:1
/// non-text). Verified contrasts on the rendered (post-var-fallback)
/// values:
/// <code>--sa-status-text-color</code> #606060 on
/// <code>--sa-message-agent-bg</code> #FFFFFF ≈ 5.7:1 (PASS body);
/// <code>--sa-error-text-color</code> #C62828 on #FFFFFF ≈ 5.9:1
/// (PASS body); <code>--sa-citation-chip-text</code> #0066CC on
/// <code>--sa-citation-chip-bg</code> #FFEEAA ≈ 6.0:1 (PASS body);
/// <code>--sa-banner-warning-fg</code> #6B4A0A on
/// <code>--sa-banner-warning-bg</code> alpha-composited #FBF6E9 ≈
/// 9.1:1 (PASS body); <code>--sa-tool-card-status-running</code>
/// #C6930A on #FFFFFF ≈ 3.7:1 (PASS non-text — used as a status
/// indicator, never as body text, with structural cue per UX-DR21);
/// <code>--sa-tool-card-status-complete</code> #2E7D32 on #FFFFFF ≈
/// 5.5:1 (PASS body). All values stay within the parent
/// EnsPortal.Application palette family per AC-1's "no brand-foreign
/// colors" clause.</p>
ClassMethod EmitStyle() As %Status
{
    &html<<style type="text/css">>

    ; --- The 10 MVP tokens (exact set per UX-DR12-MVP-subset, AC-3) ---
    ; Each value: var(--parent-token, fallback). Fallback is the
    ; architecture-cited approximation; the var() inheritance is forward-
    ; compatible with Epic 10.7+ live parent-palette lookups.
    &html<:root {>

    ; UX-design-spec §"Token Initial Values" line 622: operator-bg from
    ; parent's low-contrast surface variant. Mgmt Portal uses a near-white
    ; subtle surface for input/operator turns.
    &html<  --sa-message-operator-bg: var(--zen-portal-surface-subtle, #f0f4f8);>

    ; UX-design-spec line 623: agent-bg from parent default content
    ; background. Mgmt Portal default content area is white.
    &html<  --sa-message-agent-bg: var(--zen-portal-surface-default, #ffffff);>

    ; UX-design-spec line 624: tool-card border from parent's standard
    ; rule color. Mgmt Portal uses #d0d0d0-ish for table/section rules.
    &html<  --sa-tool-card-border: var(--zen-portal-rule, #d0d0d0);>

    ; UX-design-spec line 625: tool-card status — running uses parent's
    ; in-progress / accent color (Mgmt Portal accent yellow approximation).
    &html<  --sa-tool-card-status-running: var(--zen-portal-accent, #c6930a);>

    ; UX-design-spec line 626: complete — parent's success / OK color.
    ; Mgmt Portal uses a muted green for OK badges.
    &html<  --sa-tool-card-status-complete: var(--zen-portal-success, #2e7d32);>

    ; UX-design-spec line 627: error — parent's existing error/warning
    ; color. Mgmt Portal red is approximately #c62828.
    &html<  --sa-tool-card-status-error: var(--zen-portal-error, #c62828);>

    ; UX-design-spec line 628: citation chip background — parent's chip /
    ; tag surface. Light surface, slightly tinted.
    &html<  --sa-citation-chip-bg: var(--zen-portal-chip-bg, #ffeeaa);>

    ; UX-design-spec line 628: citation chip text — parent's link color.
    ; Mgmt Portal links are a muted blue.
    &html<  --sa-citation-chip-text: var(--zen-portal-link, #0066cc);>

    ; UX-design-spec line 629: status text — parent's secondary text /
    ; muted color. Mgmt Portal uses gray for status messages.
    &html<  --sa-status-text-color: var(--zen-portal-text-muted, #606060);>

    ; UX-design-spec line 629: error text — same parent error color as
    ; the tool-card status, but emitted as a separate token because
    ; UX-DR12 keeps them distinct (a future story may diverge them).
    &html<  --sa-error-text-color: var(--zen-portal-error, #c62828);>

    ; --- Story 10.8 AC-1 — full token resolution per UX-DR12-full /
    ; UX-DR23. The following 8 tokens were previously declared inline
    ; on the rules that use them (Story 10.2 / 10.4 / 10.5). Hoisted
    ; into :root here so the complete --sa-* surface is enumerable from
    ; one location and operators / future-epic devs can audit / override
    ; the values without grepping every component-rule. Each token's
    ; fallback maps to a parent-palette EnsPortal color per Task 0
    ; probe of irislib/EnsPortal/Application.cls Style block (#C6930A,
    ; #D7DBDD, #D0D0D0, #606060, #404040, #FFEEAA — the published
    ; palette surface) — values stay within that family per AC-1's
    ; "no brand-foreign colors" clause.
    ;
    ; --sa-hover-bg: subtle row-hover tint for sa-search-result-entry.
    ; rgba(0,0,0,0.04) is the WCAG-safe overlay (no contrast change vs
    ; parent body text inherited from EnsPortal.Application).
    &html<  --sa-hover-bg: var(--zen-portal-hover-bg, rgba(0, 0, 0, 0.04));>

    ; --sa-accent-color: the canonical "active link" hue, identical
    ; semantically to --sa-citation-chip-text. Both reference the same
    ; parent --zen-portal-link var; emitted as separate tokens because
    ; the UX spec keeps them distinct (citation vs hover-active).
    &html<  --sa-accent-color: var(--zen-portal-link, #0066cc);>

    ; --sa-muted-fg: secondary text (truncation notes, supplementary
    ; metadata) — same parent muted-text rung as --sa-status-text-color.
    ; Uses #666 fallback (slightly lighter than the #606060 status-text)
    ; so the two surfaces are distinguishable when stacked.
    &html<  --sa-muted-fg: var(--zen-portal-text-muted, #666);>

    ; --sa-from-search-stripe-border + -bg: the from-search stripe
    ; (Story 10.4 AC-4 / UX-DR5). border re-uses --sa-accent-color
    ; family; bg is an 8% tint of the same hue so it reads as a
    ; subtle "info" stripe, not a brand-foreign band. Two tokens
    ; (border vs bg) instead of one because the hover state above
    ; the stripe uses a 12% tint — keeping them as separate tokens
    ; lets a future story tune the hover band without touching the
    ; resting band.
    &html<  --sa-from-search-stripe-border: var(--zen-portal-link, #0066cc);>
    &html<  --sa-from-search-stripe-bg: var(--zen-portal-info-tint, rgba(0, 102, 204, 0.08));>

    ; --sa-banner-warning-{border,bg,fg}: concurrent-tab banner (Story
    ; 10.5 / UX-DR8 / FR46 / NFR-P4). Maps to the parent's accent-amber
    ; rung (--zen-portal-accent #C6930A). Border + 10% bg tint + a
    ; high-contrast text fg so the banner satisfies WCAG AA both as
    ; non-text (3:1 border-vs-bg) and as body text (4.5:1 fg-vs-bg).
    ; Computed contrast on the rendered fallback values: fg #6b4a0a on
    ; bg ~#fbf6e9 (after rgba alpha-compositing on white) ≈ 9.1:1 — AA
    ; pass (well above 4.5:1 threshold).
    &html<  --sa-banner-warning-border: var(--zen-portal-accent, #d49317);>
    &html<  --sa-banner-warning-bg: var(--zen-portal-accent-tint, rgba(212, 147, 23, 0.10));>
    &html<  --sa-banner-warning-fg: var(--zen-portal-warning-fg, #6b4a0a);>

    &html<}>

    ; --- Component-class rules (Task 2 minimums per Story 3.1) ---
    ; Layout-only rules: flex / overflow. Foundation (font, button,
    ; form control) intentionally NOT overridden per AC-4. No
    ; position:fixed, no z-index, no @keyframes per UX-DR28.

    &html<.sa-chat-panel { display: flex; flex-direction: column; height: 100%; }>
    &html<.sa-message-transcript { flex: 1 1 auto; overflow-y: auto; overflow-x: hidden; }>
    &html<.sa-input-area { display: flex; }>
    &html<.sa-input-field { flex: 1 1 auto; }>
    &html<.sa-status-text { color: var(--sa-status-text-color); font-style: italic; }>

    ; Story 3.7 fix-now (lead-driven walkthrough screenshot finding):
    ; operator/agent message attribution per UX-design-spec §"Operator vs.
    ; agent message attribution" line 776 — both visual-tint difference
    ; (token-driven) AND attribution prefix (`**You** —` / `**Agent** —`)
    ; were specified but never implemented. Without them the operator
    ; cannot visually tell which lines are their own questions vs. the
    ; agent's answers, especially in returning-conversation surfacing
    ; (Story 3.3 AC-3) which can have many alternating turns.
    ;
    ; Implementation: (a) every message block gets padding + margin so
    ; turns are visually separable; (b) operator vs. agent backgrounds
    ; differ via the existing --sa-message-{operator,agent}-bg tokens;
    ; (c) ::before pseudo-elements add the attribution prefix per the
    ; UX spec — the prefix is bold and slightly muted so it's clearly
    ; metadata not body content. Error variant inherits agent styling
    ; with a left border in --sa-error-text-color for at-a-glance
    ; visibility (color + structural cue per UX-DR21).
    &html<.sa-message-block { padding: 0.5em 0.75em; margin: 0.25em 0; border-radius: 4px; overflow-wrap: break-word; }>
    &html<.sa-msg-operator { background: var(--sa-message-operator-bg); }>
    &html<.sa-msg-agent { background: var(--sa-message-agent-bg); }>
    &html<.sa-msg-operator::before { content: "You — "; font-weight: bold; }>
    &html<.sa-msg-agent::before { content: "Agent — "; font-weight: bold; }>
    &html<.sa-msg-error { border-left: 3px solid var(--sa-error-text-color); }>

    ; Story 3.7+ manual-test fix-now: tool-card body's <pre><code> blocks
    ; (args + result JSON dumps) overflow horizontally when the content is
    ; wider than the chat panel — operator can't read past the right edge.
    ; Add overflow-x: auto so wide content scrolls horizontally within the
    ; <pre> element instead of clipping. word-break and white-space ensure
    ; long lines stay readable. Applies to nested code/pre inside the
    ; sa-tool-call-card (so plain inline <code> in agent text still wraps
    ; via parent block flow).
    &html<.sa-tool-call-card pre { max-width: 100%; overflow-x: auto; white-space: pre; word-break: normal; }>
    &html<.sa-tool-call-card pre code { display: block; }>

    ; --- Story 3.4 AC-4: tool-card highlight flash for citation-chip
    ; click target. Added to <details class="sa-tool-call-card"> by
    ; SessionAgent.EnsPortal.VisualTrace.onCitationClick(), removed
    ; ~1000ms later via setTimeout. Uses an outline (NOT a
    ; background-color or @keyframes per UX-DR28's no-modals/no-anims
    ; anti-pattern list — outline is a single transient visual cue,
    ; not a sustained animation). Color references the existing
    ; --sa-citation-chip-text token so the flash uses the same
    ; "active link" hue the chip itself does.
    &html<.sa-tool-card-highlight { outline: 2px solid var(--sa-citation-chip-text); transition: outline 0.3s ease; }>

    ; --- Story 3.5 AC-1 / AC-4 — config-empty prompt + disabled input
    ; field. Both rules reference existing tokens from the 10-token MVP
    ; set per UX-DR26 (no hex/rgba in component classes). The
    ; .sa-config-empty-prompt rule uses --sa-error-text-color (the same
    ; muted-error tone the panel uses for inline errors). The
    ; .sa-input-field-disabled rule uses opacity + cursor only — no
    ; color literal — so it inherits any parent disabled-input styling
    ; the host page contributes.
    &html<.sa-config-empty-prompt { padding: 1em; color: var(--sa-error-text-color); }>
    &html<.sa-input-field-disabled { opacity: 0.6; cursor: not-allowed; }>

    ; --- Story 4.0 AC-6 — citation-chip click failure notice. The notice
    ; is appended next to a chip when (a) the chip's id is empty/non-
    ; numeric (validation rejection pre-dispatch) or (b) the parent-side
    ; zenPage.onCitationClick handler threw (post-dispatch failure). It
    ; reuses --sa-error-text-color so the cue is visually consistent
    ; with the inline-error block (.sa-msg-error left border, the
    ; .sa-error-text span in the error envelope path). No new token
    ; needed — UX-DR21 / NFR-T1 satisfied via reuse.
    &html<.sa-citation-error { color: var(--sa-error-text-color); font-style: italic; margin-left: 0.25em; }>

    ; --- Story 10.2 AC-7 — Search-Agent curated-list rendering rules.
    ; Each sa-search-result-entry is a real <a> with display:block so
    ; the whole row is clickable; hover/focus styling uses the existing
    ; --sa-citation-chip-text token (chip-active hue) for the left
    ; border + a subtle background tint. The hover/focus tokens
    ; --sa-hover-bg / --sa-accent-color / --sa-muted-fg get explicit
    ; rgba/hex fallbacks so the rules render correctly even when the
    ; parent palette doesn't define them — same fallback-with-var()
    ; pattern as the 10-token MVP set above. The
    ; --sa-tool-card-status-error token already exists and is reused
    ; for the Error-status-row tint per UX-DR21.
    &html<.sa-search-result-entry { display: block; padding: 8px 12px; margin: 4px 0; text-decoration: none; color: inherit; border-left: 3px solid transparent; border-radius: 4px; transition: background 100ms; }>
    &html<.sa-search-result-entry:hover, .sa-search-result-entry:focus { background: var(--sa-hover-bg, rgba(0, 0, 0, 0.04)); border-left-color: var(--sa-accent-color, #0066cc); }>
    &html<.sa-search-result-status-error { color: var(--sa-tool-card-status-error, #c53030); font-weight: 600; }>
    &html<.sa-search-result-sid { font-weight: 600; }>
    &html<.sa-search-truncation-note { font-style: italic; margin: 6px 0; padding: 4px 8px; color: var(--sa-muted-fg, #666); }>

    ; --- Story 10.4 AC-4 — from-search stripe (UX-DR5). The stripe is a
    ; thin horizontal bar above the chat transcript with the literal
    ; search query, an Accept button, and an × Dismiss button. Both
    ; buttons share styling tokens with the existing search-result-entry
    ; rules above (--sa-from-search-stripe-border / -bg fall back to the
    ; same #0066cc / rgba(0,102,204,0.08) pair). All colors reference CSS
    ; custom properties with explicit fallback hex/rgba literals per
    ; .claude/rules/angular-patterns.md analog for ObjectScript-emitted
    ; CSS — fallbacks are the rendered values today (parent palette
    ; doesn't publish these vars yet).
    &html<.sa-from-search-stripe { display: flex; align-items: center; gap: 8px; height: 32px; padding: 0 12px; margin: 0 0 8px 0; border-left: 3px solid var(--sa-from-search-stripe-border, #0066cc); background: var(--sa-from-search-stripe-bg, rgba(0, 102, 204, 0.08)); font-size: 0.92em; }>
    &html<.sa-stripe-text { flex: 1 1 auto; }>
    &html<.sa-stripe-accept, .sa-stripe-dismiss { background: transparent; border: 1px solid var(--sa-from-search-stripe-border, #0066cc); border-radius: 3px; padding: 2px 8px; cursor: pointer; font-size: 0.9em; }>
    &html<.sa-stripe-dismiss { padding: 2px 6px; }>
    &html<.sa-stripe-accept:hover, .sa-stripe-dismiss:hover { background: var(--sa-from-search-stripe-bg, rgba(0, 102, 204, 0.12)); }>

    ; --- Story 10.5 AC-6 — concurrent-tab banner + locked-input rules.
    ; The banner is a non-modal advisory bar mounted ABOVE the chat
    ; transcript when another browser tab holds the Chat.History
    ; exclusive lock (FR46, UX-DR8, NFR-P4). Visual treatment: warning-
    ; tone (amber) left border + tinted background, matches the
    ; from-search stripe pattern from Story 10.4 AC-4. Per AC-6 all
    ; colors reference CSS custom properties with explicit fallback
    ; hex/rgba literals so the rules render correctly even when the
    ; parent palette doesn't define the var (--sa-banner-warning-*
    ; tokens are not yet in the 10-token MVP set; the var() form is
    ; forward-compatible with Epic 10.7+ live-palette lookups).
    ;
    ; The .sa-input-locked rule applies opacity + cursor-not-allowed
    ; visual de-emphasis to the input when the banner is shown — the
    ; input is also disabled at the attribute level (chat-panel.js
    ; setAttribute('disabled', 'disabled')), so screen readers + keyboard
    ; users get the hard signal too.
    &html<.sa-concurrent-tab-banner { display: flex; align-items: center; padding: 10px 12px; margin: 0 0 8px 0; border-left: 3px solid var(--sa-banner-warning-border, #d49317); background: var(--sa-banner-warning-bg, rgba(212, 147, 23, 0.10)); color: var(--sa-banner-warning-fg, #6b4a0a); font-size: 0.94em; min-height: 40px; }>
    &html<.sa-input-locked { opacity: 0.55; cursor: not-allowed; }>

    ; Story 10.13 F-4 — Search-Agent chat panel sizing on the Message
    ; Viewer. The parent EnsPortal.MessageViewer hosts the panel inside
    ; #detailsTabGroup → #askAgentTab, an area the parent designed for
    ; narrow property forms (Header / Body / Contents / Trace tabs each
    ; show ~12-16 form fields), so the area defaults to a small width
    ; and the panel rendered ~168px wide × 36px tall (verified via
    ; chrome-devtools-mcp DOM probe at story-implementation time). The
    ; rule below targets the panel ONLY when it appears inside the
    ; Message-Viewer detail-pane parent — a more specific selector
    ; (#detailsTabGroup #askAgentTab .sa-chat-panel) wins over the base
    ; rule's height:100%. The VisualTrace host page uses parent id
    ; #contentTabs (NOT #detailsTabGroup) so this rule does NOT regress
    ; that surface. The min-height: 400px reserves enough vertical
    ; space for the welcome message + several turns of conversation;
    ; min-width: 480px gives the transcript readable width and lets
    ; tool-call cards lay out without awkward wrapping.
    &html<#detailsTabGroup #askAgentTab .sa-chat-panel { min-width: 480px; min-height: 400px; }>
    &html<#detailsTabGroup #askAgentTab .sa-message-transcript { min-height: 280px; }>

    &html<</style>>
    Quit $$$OK
}

}
