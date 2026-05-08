/* Story 10.7 STUB grammar — Prism does NOT ship a canonical ObjectScript
 * grammar. We register the language token and inherit from
 * Prism.languages.csharp (closest-approximate fit — bracket-block syntax,
 * similar identifier rules). Operators see basic syntax coloring instead
 * of the vanilla `markup` fallback. Full grammar deferred to a future
 * story (Epic 11). See deferred-work.md "Custom Prism grammars". */
(function () {
    if (typeof Prism === 'undefined' || !Prism.languages) {
        return;
    }
    if (!Prism.languages.csharp) {
        // Defense-in-depth: if csharp didn't load (curated build skipped
        // it), fall through to markup so the language token still
        // registers without throwing.
        Prism.languages.objectscript = Prism.languages.markup || {};
        return;
    }
    Prism.languages.objectscript = Prism.languages.csharp;
}());
