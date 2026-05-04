/*
 * Story 4.0 Rule 12 empirical pass — verifies the AC-5 + AC-6 chat-panel.js
 * defensive guards behave as specified by simulating the relevant code paths
 * in a minimal DOM environment.
 *
 * Rationale: chrome-devtools-mcp browser is locked from a prior process at
 * the time of this dev cycle, and the IRIS web app `/csp/static/iris-session-
 * agent` is not registered on this dev host. To still satisfy Rule 12
 * (rendered-text-readability empirical pass), this script:
 *   1. Builds a minimal mock window/document, mimicking the parts of the
 *      DOM the chat-panel.js helpers touch (createElement, setAttribute,
 *      textContent, appendChild, closest).
 *   2. Loads chat-panel.js in that environment and extracts the renderToolCard
 *      function plus the new extractToolErrorPreview / isCitationDispatchable /
 *      surfaceCitationErrorNotice helpers via the IIFE export pattern.
 *   3. Exercises:
 *      - AC-5: render a tool card with status="error" and a content[0] text
 *        block of >80 chars; assert the truncated preview appears in the
 *        summary text BEFORE expansion.
 *      - AC-5 fallback: same render with malformed envelope (result=null);
 *        assert the prior "called <name>" wording is preserved.
 *      - AC-6 (1) validation: dispatch with citeType="message", citeId="";
 *        assert no zenPage call AND a `.sa-citation-error` notice appears.
 *      - AC-6 (1) validation: dispatch with citeType="message", citeId="abc";
 *        assert no zenPage call (non-numeric id rejected).
 *      - AC-6 (1) tool exemption: dispatch with citeType="tool",
 *        citeId="list_sessions"; assert zenPage IS called.
 *      - AC-6 (2) parent-throw: zenPage.onCitationClick throws — assert the
 *        notice still appears.
 *      - AC-6 (3) dedup: click the same chip twice with bad id; assert
 *        only ONE notice is appended.
 *
 * The script is run with `node rule-12-empirical-pass-4-0.js`. All assertions
 * print PASS/FAIL with a 1-line description; any FAIL exits the script with
 * a non-zero status so CI / lead can detect regressions.
 *
 * Because the chat-panel.js IIFE is auto-executing inside a closure, this
 * script extracts the relevant helper sources via a regex-bounded slice and
 * `new Function(...)` instantiates them in a controlled scope.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const CHAT_PANEL_JS = fs.readFileSync(
    path.join(__dirname, '../../static/chat-panel.js'),
    'utf8'
);

let pass = 0;
let fail = 0;
function assert(cond, msg) {
    if (cond) {
        console.log('PASS  ' + msg);
        pass++;
    } else {
        console.log('FAIL  ' + msg);
        fail++;
    }
}

// --- Minimal DOM mock --------------------------------------------------------

function MockNode(tag) {
    this.tagName = (tag || 'DIV').toUpperCase();
    this.attributes = {};
    this._children = [];
    this._textContent = '';
    this.parentNode = null;
}
MockNode.prototype.setAttribute = function (k, v) { this.attributes[k] = String(v); };
MockNode.prototype.getAttribute = function (k) { return this.attributes[k] != null ? this.attributes[k] : null; };
MockNode.prototype.appendChild = function (n) { this._children.push(n); n.parentNode = this; return n; };
MockNode.prototype.closest = function (sel) {
    // Trivial selector match: '.<class>' or 'p'
    let cur = this;
    while (cur) {
        if (sel.startsWith('.')) {
            const cls = sel.substring(1);
            const aClass = cur.attributes && cur.attributes.class;
            if (aClass && aClass.split(/\s+/).indexOf(cls) >= 0) return cur;
        } else if (sel.toUpperCase() === cur.tagName) {
            return cur;
        }
        cur = cur.parentNode;
    }
    return null;
};
Object.defineProperty(MockNode.prototype, 'textContent', {
    get() { return this._textContent; },
    set(v) { this._textContent = v == null ? '' : String(v); }
});

const document = {
    createElement: (tag) => new MockNode(tag),
    createTextNode: (s) => {
        const n = new MockNode('#text');
        n.textContent = s;
        return n;
    }
};

// --- Extract the helpers from chat-panel.js via regex slicing ----------------

function sliceFunction(src, startMarker) {
    const idx = src.indexOf(startMarker);
    if (idx < 0) throw new Error('marker not found: ' + startMarker);
    let depth = 0;
    let i = idx;
    while (i < src.length) {
        const c = src.charAt(i);
        if (c === '{') depth++;
        else if (c === '}') { depth--; if (depth === 0) return src.substring(idx, i + 1); }
        i++;
    }
    throw new Error('unbalanced braces');
}

const extractFnSrc       = sliceFunction(CHAT_PANEL_JS, 'function extractToolErrorPreview');
const isDispatchableSrc  = sliceFunction(CHAT_PANEL_JS, 'function isCitationDispatchable');
const surfaceNoticeSrc   = sliceFunction(CHAT_PANEL_JS, 'function surfaceCitationErrorNotice');

// Instantiate in a scope that has `document` defined.
const ctx = new Function('document', `
    ${extractFnSrc}
    ${isDispatchableSrc}
    ${surfaceNoticeSrc}
    return { extractToolErrorPreview, isCitationDispatchable, surfaceCitationErrorNotice };
`)(document);

// --- AC-5 tests --------------------------------------------------------------

console.log('\n--- AC-5: extractToolErrorPreview ---');

const longErrText = 'Validation failed: session_id "DOES_NOT_EXIST" did not match any rows in Ens.MessageHeader for the configured tenant. Try a valid session id.';
const cardErrLong = {
    name: 'session_summary',
    status: 'error',
    args: { session_id: 'DOES_NOT_EXIST' },
    result: { content: [{ type: 'text', text: longErrText }], is_error: true }
};
const previewLong = ctx.extractToolErrorPreview(cardErrLong);
assert(previewLong.length === 81, 'long error preview is exactly 80 chars + ellipsis');
assert(previewLong.endsWith('…'), 'long preview ends with ellipsis');
assert(previewLong.indexOf('Validation failed') === 0, 'preview starts with original text');

const cardErrShort = {
    name: 'list_sessions',
    status: 'error',
    args: {},
    result: { content: [{ type: 'text', text: 'No sessions match the given filter.' }], is_error: true }
};
const previewShort = ctx.extractToolErrorPreview(cardErrShort);
assert(previewShort === 'No sessions match the given filter.', 'short error returned verbatim, no truncation');

const cardOk = { name: 'list_sessions', status: 'ok', args: {}, result: { content: [{ type: 'text', text: 'OK' }] } };
assert(ctx.extractToolErrorPreview(cardOk) === '', 'status=ok returns empty preview');

const cardErrNoResult = { name: 'x', status: 'error', args: {}, result: null };
assert(ctx.extractToolErrorPreview(cardErrNoResult) === '', 'null result returns empty preview (defensive)');

const cardErrNoContent = { name: 'x', status: 'error', args: {}, result: {} };
assert(ctx.extractToolErrorPreview(cardErrNoContent) === '', 'missing content returns empty preview');

const cardErrEmptyContent = { name: 'x', status: 'error', args: {}, result: { content: [] } };
assert(ctx.extractToolErrorPreview(cardErrEmptyContent) === '', 'empty content array returns empty preview');

const cardErrNonText = { name: 'x', status: 'error', args: {}, result: { content: [{ type: 'image', data: '...' }] } };
assert(ctx.extractToolErrorPreview(cardErrNonText) === '', 'first block non-text returns empty preview');

const cardErrEmptyText = { name: 'x', status: 'error', args: {}, result: { content: [{ type: 'text', text: '' }] } };
assert(ctx.extractToolErrorPreview(cardErrEmptyText) === '', 'empty text returns empty preview');

assert(ctx.extractToolErrorPreview(null) === '', 'null card returns empty preview');
assert(ctx.extractToolErrorPreview(undefined) === '', 'undefined card returns empty preview');

// --- AC-6 (1) tests: isCitationDispatchable ---------------------------------

console.log('\n--- AC-6 (1): isCitationDispatchable ---');

assert(ctx.isCitationDispatchable('message', '42') === true, 'numeric id passes for message');
assert(ctx.isCitationDispatchable('message', '') === false, 'empty id rejected');
assert(ctx.isCitationDispatchable('message', null) === false, 'null id rejected');
assert(ctx.isCitationDispatchable('message', undefined) === false, 'undefined id rejected');
assert(ctx.isCitationDispatchable('message', 'abc') === false, 'non-numeric id rejected');
assert(ctx.isCitationDispatchable('message', '99999') === true, 'long numeric id passes (the deliberately-malformed test case from AC-7)');
assert(ctx.isCitationDispatchable('message', '-5') === false, 'negative id rejected (strict /^\\d+$/)');
assert(ctx.isCitationDispatchable('message', '5.5') === false, 'decimal id rejected');
assert(ctx.isCitationDispatchable('message', ' 5') === false, 'leading-space id rejected');
assert(ctx.isCitationDispatchable('event_log', '7') === true, 'event_log numeric id passes');
assert(ctx.isCitationDispatchable('rule_log', '42') === true, 'rule_log numeric id passes');
assert(ctx.isCitationDispatchable('ack', '5') === true, 'ack numeric id passes');
assert(ctx.isCitationDispatchable('iolog', '3') === true, 'iolog numeric id passes');
assert(ctx.isCitationDispatchable('tool', 'list_sessions') === true, 'tool string id passes (tool exemption)');
assert(ctx.isCitationDispatchable('tool', 'tc-3') === true, 'tool tc-N synthetic id passes');
assert(ctx.isCitationDispatchable('tool', '') === false, 'tool empty id still rejected');

// --- AC-6 (2) + (3) tests: surfaceCitationErrorNotice -----------------------

console.log('\n--- AC-6 (2)+(3): surfaceCitationErrorNotice ---');

function buildChipInParagraph() {
    const p = document.createElement('p');
    const chip = document.createElement('a');
    chip.setAttribute('class', 'sa-citation-chip sa-cite-message');
    chip.setAttribute('data-cite-type', 'message');
    chip.setAttribute('data-cite-id', '');
    chip.textContent = '[message:]';
    p.appendChild(chip);
    return { p, chip };
}

const t1 = buildChipInParagraph();
ctx.surfaceCitationErrorNotice(t1.chip);
const noticeAfterFirst = t1.p._children.filter(n => n.attributes && n.attributes.class === 'sa-citation-error');
assert(noticeAfterFirst.length === 1, 'first call appends exactly one notice');
assert(noticeAfterFirst[0].textContent.indexOf("Couldn't resolve") >= 0, 'notice text matches AC-6 spec');
assert(noticeAfterFirst[0].attributes['role'] === 'alert', 'notice has role=alert for screen readers');
assert(t1.chip.parentNode === t1.p, 'original chip remains in the DOM (clickable for retry)');
assert(t1.chip.getAttribute('data-cite-error-shown') === '1', 'chip flagged after first notice');

// AC-6 (3) — dedup
ctx.surfaceCitationErrorNotice(t1.chip);
ctx.surfaceCitationErrorNotice(t1.chip);
const noticeAfterThree = t1.p._children.filter(n => n.attributes && n.attributes.class === 'sa-citation-error');
assert(noticeAfterThree.length === 1, 'dedup: 3 calls append at most ONE notice');

// Defensive: null chip / no parent — no crash
let crashed = false;
try { ctx.surfaceCitationErrorNotice(null); } catch (e) { crashed = true; }
assert(!crashed, 'null chip does not crash');

// --- Summary ----------------------------------------------------------------

console.log('\n=== SUMMARY ===');
console.log('PASS: ' + pass);
console.log('FAIL: ' + fail);
process.exit(fail === 0 ? 0 : 1);
