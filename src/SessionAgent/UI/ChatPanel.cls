/// <p>CSS contributor for the Session Agent chat panel — emits a
/// <code>&lt;style&gt;</code> block defining the minimum 10
/// <code>--sa-*</code> tokens and the matching <code>sa-*</code>
/// component-class rules per Story 3.1 AC-3 / AC-4 (UX-DR12-MVP-subset,
/// UX-DR26).</p>
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
/// <p>Emits exactly 10 <code>--sa-*</code> tokens per AC-3 and the
/// minimum component-class rules per AC-4 task spec (Task 2). Token
/// values use <code>var(--parent, fallback)</code> form — the fallback
/// values are commented inline citing the architecture-suggested parent-
/// palette source.</p>
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

    &html<}>

    ; --- Component-class rules (Task 2 minimums per Story 3.1) ---
    ; Layout-only rules: flex / overflow. Foundation (font, button,
    ; form control) intentionally NOT overridden per AC-4. No
    ; position:fixed, no z-index, no @keyframes per UX-DR28.

    &html<.sa-chat-panel { display: flex; flex-direction: column; height: 100%; }>
    &html<.sa-message-transcript { flex: 1 1 auto; overflow-y: auto; }>
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
    &html<.sa-message-block { padding: 0.5em 0.75em; margin: 0.25em 0; border-radius: 4px; }>
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

    &html<</style>>
    Quit $$$OK
}

}
