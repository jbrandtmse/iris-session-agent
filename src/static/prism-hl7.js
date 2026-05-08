/* Story 10.7 STUB grammar — Prism does NOT ship HL7. We register the
 * language token and inherit from Prism.languages.markup. Segment-pipe-
 * delimited text falls back to plain rendering — acceptable for v1.
 * Full HL7 segment-aware grammar deferred to a future story (Epic 11).
 * See deferred-work.md "Custom Prism grammars". */
(function () {
    if (typeof Prism === 'undefined' || !Prism.languages) {
        return;
    }
    Prism.languages.hl7 = Prism.languages.markup || {};
}());
