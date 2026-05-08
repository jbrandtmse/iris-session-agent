# Story 10.7: Vendored Markdown Bundle + `chat-panel.js` Growth-Tier Render Upgrade

Status: done

## Story

As an **Operator reading a long-form agent answer with code blocks** (e.g., the agent shows a fragment of an HL7 message, an SQL query, or an ObjectScript snippet),
I want the answer rendered with proper Markdown structure + syntax-highlighted code blocks via the vendored `marked` + `Prism.js` + `DOMPurify` bundle hosted at `/csp/static/iris-session-agent/`,
So that long-form answers are scannable, code is highlighted (ObjectScript / JS / JSON / SQL / HL7 / XML), and all rendering is XSS-safe per FR54 + UX-DR13 + NFR-C5 (no CDN — self-hosted).

This story upgrades the chat-panel rendering from Story 3.2's MVP fallback (textContent + manual code-fence detection) to the Growth-tier pipeline (marked → Prism → DOMPurify → innerHTML). The bundle is vendored — no CDN, no external load — per NFR-C5.

## Scope clarifications (Rule 8 explicit deferrals)

**Custom Prism language grammars deferred (per Rule 8 test 1 — genuine future-epic scope):**
- **`prism-objectscript.js`** — Prism does NOT ship a canonical ObjectScript grammar. Writing a faithful ObjectScript grammar from scratch (covering `Set`, `Quit`, `$$$macros`, `&sql(...)`, `##class()`, embedded Python switches, etc.) is a multi-hundred-line effort that doesn't fit Story 10.7's 250-line spec budget. **Story 10.7 ships a STUB `prism-objectscript.js` that registers the language token but inherits from `Prism.languages.csharp`** (closest-approximate fit — bracket-block syntax, similar identifier rules); operators see basic syntax coloring instead of vanilla `markup` fallback. Future story (deferred to Story 10.X / Epic 11) writes the full grammar.
- **`prism-hl7.js`** — Same shape: Prism does NOT ship HL7. **Story 10.7 ships a STUB that registers the language token but inherits from `Prism.languages.markup`** (segment-pipe-delimited text falls back to plain rendering — acceptable for v1; HL7 syntax-highlighting is a Growth-tier nice-to-have).

Both stubs are file-presence-correct (the vendored bundle ships all the JS files AC-1 names) AND the runtime fallback works correctly. The deferred work is upgrading the stubs to faithful grammars — logged in `deferred-work.md` per AC-8.

## Acceptance Criteria

ACs come from epics.md §"Story 10.7" verbatim, augmented by the scope clarification above.

### AC-1 — Vendored bundle assets

**Given** the developer is preparing the vendored bundle
**When** they download + commit the asset files to [`src/static/`](../../src/static/)
**Then** the directory contains:
| File | Source | Version | Notes |
|---|---|---|---|
| `marked.min.js` | https://cdn.jsdelivr.net/npm/marked/marked.min.js (then committed) | ≥ **18.0.2** (CVE-2026-41680 fixed) | Core Markdown parser. Verify version per Rule 10 below. |
| `prism.min.js` (core) | https://prismjs.com/download.html (curated build) | latest stable as of 2026-05 | Core highlighter. |
| `prism-objectscript.js` | **STUB written this story** | — | Inherits from `Prism.languages.csharp`. |
| `prism-sql.js` | Prism canonical | latest | Stock language pack. |
| `prism-javascript.js` | Prism canonical | latest | Stock language pack. |
| `prism-json.js` | Prism canonical | latest | Stock language pack. |
| `prism-hl7.js` | **STUB written this story** | — | Inherits from `Prism.languages.markup`. |
| `prism-xml.js` (or `prism-markup.js` which IS XML) | Prism canonical | latest | Stock language pack. |
| `prism.min.css` (low-contrast theme) | Prism canonical | latest | Theme matching parent palette. |
| `dompurify.min.js` | https://cdn.jsdelivr.net/npm/dompurify@3 | ≥ **3.x** | XSS gate. Verify version per Rule 10 below. |

**And** all assets are committed to `src/static/` (NOT `static/` — the existing chat-panel.js lives at `static/chat-panel.js` per Story 3.6's pattern; vendored deps use the `src/static/` path so they ship via `module.xml` `<FileCopy>` per AC-2).

**And** **NFR-C5 invariant**: `grep -rn "https://cdn\." src/static/` returns ZERO matches — no CDN URLs in any vendored file (these MAY appear as comments in the original library headers; if they do, replace with the local relative path OR strip).

### AC-2 — Static-asset CSP application + FileCopy

**Given** the bundle is deployed via `module.xml`
**When** the operator installs / re-installs the package
**Then** [`module.xml`](../../module.xml) is extended with:

```xml
<CSPApplication
    Url="/csp/static/iris-session-agent"
    Directory="${cspdir}/static/iris-session-agent"
    AuthenticationMethods="64"
    DispatchClass=""
    Recurse="1"
/>
<FileCopy Src="static/" Target="${cspdir}/static/iris-session-agent/" />
```

**And** the existing `<Resource Name="SessionAgent.PKG"/>` line stays verbatim.
**And** browser requests to `/csp/static/iris-session-agent/marked.min.js` etc. return the assets with correct MIME types (`application/javascript`, `text/css`).

**Story 3.6 deprecation note:** Story 3.6 dropped the `<CSPApplication>` block due to a `${cspdir}` template-expansion bug observed at install time on a particular IRIS release. Task 0 MUST verify whether that bug is still reproducible on the current dev install — if so, AC-2's CSPApplication addition needs a workaround (hardcoded path OR alternate ZPM directive). If the bug is no longer reproducible, the new CSPApplication block ships as-is.

### AC-3 — Host-page `<script>` includes

**Given** the host pages contribute the vendored bundle to the rendered page
**When** the developer extends `%OnDrawHTMLHead` on BOTH `SessionAgent.EnsPortal.VisualTrace` and `SessionAgent.EnsPortal.MessageViewer`
**Then** AFTER the existing `chat-panel.js` include line, the methods emit additional `<script>` tags for the vendored bundle in dependency order:
1. `<link rel="stylesheet" href="/csp/static/iris-session-agent/prism.min.css">`
2. `<script src="/csp/static/iris-session-agent/marked.min.js"></script>`
3. `<script src="/csp/static/iris-session-agent/prism.min.js"></script>`
4. `<script src="/csp/static/iris-session-agent/prism-{objectscript,sql,javascript,json,hl7,xml}.js"></script>` (in any order — Prism plugins register at script-load time)
5. `<script src="/csp/static/iris-session-agent/dompurify.min.js"></script>`
6. (Existing: `<script src="/csp/<NS>/SessionAgent.UI.ChatPanelAsset.cls"></script>` — unchanged)

**And** the includes are unconditional — the bundle loads on every chat-panel render. (Performance is acceptable: total bundle ~120 KB gzipped, served once via browser cache.)

### AC-4 — `chat-panel.js` Growth-tier pipeline

**Given** `chat-panel.js` already has `renderMarkdownFallback` (Story 3.2 MVP)
**When** the developer adds the Growth-tier pipeline
**Then** a new function `renderMarkdownGrowth(markdown, parentNode)` is added:
```js
function renderMarkdownGrowth(markdown, parentNode) {
    if (typeof marked === 'undefined' || typeof DOMPurify === 'undefined') {
        // Bundle not loaded — fall back to MVP path (Story 3.2)
        renderMarkdownFallback(markdown, parentNode);
        return;
    }
    var html = marked.parse(markdown || '');
    var clean = DOMPurify.sanitize(html, { USE_PROFILES: { html: true } });
    parentNode.innerHTML = clean;
    if (typeof Prism !== 'undefined' && Prism.highlightAllUnder) {
        Prism.highlightAllUnder(parentNode);
    }
    // Re-run citation-chip parsing on the rendered DOM (Story 3.2's
    // pattern detection still works post-Markdown render — chips are
    // visible as inline-text patterns in the rendered HTML).
    parseInlineCitations(parentNode.innerText, parentNode, []);
}
```

**And** `handleEnvelope` is extended to call `renderMarkdownGrowth` instead of `renderMarkdownFallback` when the bundle is loaded.
**And** the fallback path is preserved — `renderMarkdownFallback` stays in the file as a defense-in-depth backup.
**And** code blocks with language hints (e.g., ` ```objectscript ... ``` `) get the appropriate Prism grammar applied; unknown languages fall back to `markup` (Prism's default) gracefully.

### AC-5 — XSS-safety verification

**Given** an integration test exercises the rendering pipeline
**When** the test feeds an agent response containing a paragraph + an HL7 code block + an ObjectScript code block + an inline citation chip
**Then** the rendered DOM contains the paragraph as `<p>`, the code blocks as `<pre><code class="language-hl7">` and `<pre><code class="language-objectscript">` with Prism-applied syntax classes, and the citation chip as a clickable anchor.
**And** an XSS-attempt test (Markdown containing `<script>alert(1)</script>` and `<img src=x onerror="alert(1)">`) is sanitized by DOMPurify — neither the script nor the img-onerror executes; the `<script>` block is stripped entirely; the `<img>` is preserved without the `onerror` attribute.
**And** **NFR-C5 enforcement** (no CDN) is verified by Story 1.7's CI grep — `grep -rn "https://cdn\." src/static/` returns ZERO matches.

### AC-6 — Compile + tests + regression intact

- `iris_doc_compile` clean for any modified `.cls` files (`VisualTrace`, `MessageViewer`).
- `node -c static/chat-panel.js` parses cleanly.
- New test class [`src/SessionAgent/Test/MarkdownBundleTest.cls`](../../src/SessionAgent/Test/MarkdownBundleTest.cls) (NEW) — at least 4 tests: (a) `marked.min.js` file exists in `src/static/` AND has version ≥ 18.0.2 in its header banner; (b) `dompurify.min.js` file exists with version 3.x; (c) `module.xml` contains the `<CSPApplication>` block for `/csp/static/iris-session-agent`; (d) NFR-C5 grep — no `https://cdn.` strings in any `src/static/` file.
- **Per-class regression sweep + canonical numerical-MAX SQL probe**. **Expected baseline 404 + 4 = 408+**.

### AC-7 — Rule 10 external-default verification

**Given** this story sets vendored versions for `marked` (≥ 18.0.2) and `dompurify` (≥ 3.x)
**When** the dev applies the version pins
**Then** Dev Notes MUST include a Perplexity research line of the form: *"Verified current as of 2026-05-07 via mcp__perplexity-mcp__search query 'marked.js latest stable version + CVE-2026-41680 + dompurify 3.x stable as of 2026-05': {recommended choice + rationale}."*

This satisfies Rule 10 §"External-default research at spec time" — the spec's pinned versions must be empirically verified against current registry state at story-creation time.

### AC-8 — `deferred-work.md` entry for custom-grammar upgrade

**Given** this spec defers the full ObjectScript + HL7 Prism grammars
**When** the dev creates the deferred-work entry
**Then** a new entry is added to `deferred-work.md`:

> **Custom Prism grammars — `prism-objectscript.js` + `prism-hl7.js` STUBs ship with fallbacks (Story 10.7 deferral)**
> - **Source:** Story 10.7 spec §"Scope clarifications".
> - **Severity:** LOW (operator-observable: code blocks tagged ` ```objectscript ` get C# coloring instead of true ObjectScript syntax; ` ```hl7 ` gets plain text).
> - **Why deferred (Rule 8 test #1 — genuine future-epic scope):** Faithful ObjectScript grammar covering `$$$macros`, `&sql(...)`, `##class()`, embedded-Python switches, etc. is a multi-hundred-line effort that doesn't fit Story 10.7's spec budget. HL7 grammar (segment-pipe delimited) is similarly substantive.
> - **Recommendation when picked up:** Write `prism-objectscript.js` from scratch with token rules for ObjectScript-specific syntax. For HL7, either write a segment-aware grammar OR ship a simpler "color the segment headers" grammar.
> - **Owner:** Future Epic 11 / Vision-tier story.
> - **Blocking?** Not blocking. STUBs ship fallback rendering that is operator-acceptable for v1.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probes + Rule 10 verification**
  - [x] Verify `module.xml` `${cspdir}` template-expansion behavior on the current dev install — try a CSPApplication with that template variable, install, check if the path resolves correctly. Story 3.6 dropped this approach due to a bug; verify reproducibility. Document inline.
  - [x] Per Rule 10: run `mcp__perplexity-mcp__search` with the query specified in AC-7. Capture the verbatim response in working notes. Pin `marked` to the verified ≥ 18.0.2 stable + `dompurify` to the verified 3.x stable.
  - [x] Verify the existing `src/static/` directory has only `.gitkeep` (i.e., no pre-existing vendored files that would conflict).

- [x] **Task 1 — Vendor the standard library files (AC: #1)**
  - [x] Download `marked.min.js` (verified version) from npm registry. Commit to `src/static/`.
  - [x] Download `dompurify.min.js` (verified version). Commit.
  - [x] Download Prism core + the 4 stock language packs (sql, javascript, json, xml-or-markup) + the `prism.min.css` low-contrast theme from `prismjs.com/download.html` — use the curated-build URL. Commit each file.
  - [x] Strip any `https://cdn.*` URLs from comments in the vendored files (NFR-C5 invariant per AC-5).

- [x] **Task 2 — Write the 2 STUB Prism grammars (AC: #1)**
  - [x] Create `src/static/prism-objectscript.js` — single-line stub: `Prism.languages.objectscript = Prism.languages.csharp;` (or copy the C# grammar by reference).
  - [x] Create `src/static/prism-hl7.js` — single-line stub: `Prism.languages.hl7 = Prism.languages.markup;`.
  - [x] Both files are < 5 lines; ship as ASCII text.

- [x] **Task 3 — Extend `module.xml` (AC: #2)**
  - [x] Add the `<CSPApplication>` + `<FileCopy>` blocks per AC-2 verbatim.
  - [x] Re-install via `zpm load` to verify the asset path resolves; HTTP-fetch `/csp/static/iris-session-agent/marked.min.js` and confirm 200 status + correct MIME type.
  - [x] If the `${cspdir}` template-expansion bug from Story 3.6 reproduces, apply the workaround (hardcoded absolute path OR alternate directive). Document in Completion Notes.

- [x] **Task 4 — Extend `%OnDrawHTMLHead` on both host pages (AC: #3)**
  - [x] Append the 6+ `<script>` and `<link>` tags to `VisualTrace.cls:%OnDrawHTMLHead` AND `MessageViewer.cls:%OnDrawHTMLHead` (or the equivalent inherited path).
  - [x] Compile both classes via `iris_doc_compile`.

- [x] **Task 5 — Add `renderMarkdownGrowth` to `chat-panel.js` (AC: #4)**
  - [x] Add the function per AC-4's verbatim snippet.
  - [x] Extend `handleEnvelope` to call `renderMarkdownGrowth` when `marked` is loaded; fall back to `renderMarkdownFallback` when not.
  - [x] `node -c static/chat-panel.js` parse check.

- [x] **Task 6 — Add `MarkdownBundleTest` (AC: #5, #6)**
  - [x] Create the test class with 4 tests per AC-6.
  - [x] Compile + run via `iris_execute_tests` per-class. Confirm 4/4 PASS.

- [x] **Task 7 — XSS-safety smoke (AC: #5)**
  - [x] Use `chrome-devtools-mcp` (if available) to load Visual Trace, send an XSS-attempt agent response (constructed via test fixture or by direct DOM injection), and verify the script does NOT execute.
  - [x] If chrome-devtools-mcp is unavailable, the alternate-form fallback is a unit test that calls `DOMPurify.sanitize(...)` directly with the XSS payload and asserts the script tag is stripped.

- [x] **Task 8 — `deferred-work.md` entry (AC: #8)**
  - [x] Append the custom-grammar deferral entry per AC-8 verbatim.

- [x] **Task 9 — Verification battery (AC: #6)**
  - [x] Per-class regression sweep + canonical numerical-MAX SQL probe.
  - [x] If any AI-5 flake class hits, retry per Story 10.0 umbrella entry.

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

Spec targets ~245 lines. The scope clarifications (custom-grammar deferrals) are explicit per Rule 8 test 1 to keep the in-cycle work bounded.

### Rule 8 / Rule 9 / Rule 10 / Rule 11

- **Rule 8:** Net-new code; fix-now default. AC-8 explicit deferral for custom Prism grammars per Rule 8 test 1.
- **Rule 9:** No `Story 10.7` mentions in `deferred-work.md` at story-creation time.
- **Rule 10:** AC-7 mandates Perplexity verification of `marked` + `dompurify` versions. The dev must populate the verification line in their Completion Notes.
- **Rule 11:** No external-API live integration in this story (the bundle is a static-asset deploy + JS pipeline change). XSS test is the closest live exercise.

### Auto-sync workflow

`module.xml` is NOT auto-synced (it's the install manifest). All `.cls` files auto-sync. `static/*.js` files are NOT auto-synced (per Story 3.6 — served by `ChatPanelAsset.cls` for `chat-panel.js`; the new vendored files ship via FileCopy at install time, not via auto-sync).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context).

### Completion Notes

**Rule 10 verification line (AC-7).** *"Verified current as of 2026-05-07 via `mcp__perplexity-mcp__search` query 'marked.js latest stable version + CVE-2026-41680 fix + dompurify 3.x stable as of May 2026': **`marked@18.0.3`** (npm registry latest as of 2026-05-07; addresses CVE-2026-41680; satisfies AC-1 ≥18.0.2 floor); **`dompurify@3.1.7`** (latest 3.x stable; satisfies AC-1 ≥3.x floor)."* Both pulled from the jsDelivr-mirrored npm registry tarball — Marked from `https://cdn.jsdelivr.net/npm/marked@18.0.3/lib/marked.umd.min.js` (Marked v18 dropped the top-level `marked.min.js` build in favor of the UMD path); DOMPurify from `https://cdn.jsdelivr.net/npm/dompurify@3.1.7/dist/purify.min.js`. Pinning rationale: the spec floor is ≥18.0.2; Perplexity reports the current stable as 18.0.3 — choosing the npm-registry latest (18.0.3) over the floor satisfies both the spec contract and the Rule 10 "current-stable" guidance.

**AC-1 NFR-C5 grep result.** `grep -rn "https://cdn\." src/static/` returns ZERO matches. The vendored library headers from jsDelivr reference `https://www.jsdelivr.com/...` (NOT `https://cdn.*`) and the DOMPurify license banner references `github.com/cure53/...`. The strict NFR-C5 invariant pattern `https://cdn\.` is satisfied. Verified by `SessionAgent.Test.MarkdownBundleTest.TestNoCdnUrlsInStatic` (4/4 pass).

**AC-2 architectural pivot — Story 3.6 bug recurred AND a Web Gateway routing gap surfaced.** The original spec called for a dedicated `<CSPApplication>` registering `/csp/static/iris-session-agent` with `Directory="${cspdir}/static/iris-session-agent"`. Two empirical findings during Task 3 forced an architectural pivot:

1. **`<CSPApplication>` is deprecated in IPM 0.10.x** — the install log prints *"WARNING: The `<CSPApplication></CSPApplication>` resource tag is deprecated and may be removed in a future release of IPM. Please contact the package developer of iris-session-agent to use `<WebApplication></WebApplication>` instead"*. Switched to the `<WebApplication>` directive form.

2. **`${cspdir}` template did NOT expand into `Security.Applications.Path`** even with `<WebApplication>` — the activate-phase install log showed `Directory: C:\InterSystems\IRISHealth\CSP\/static/iris-session-agent` (correctly resolved) but post-install `SELECT Path FROM Security.Applications WHERE Name='/csp/static/iris-session-agent'` returned `Path = ""` (empty). This is the **same bug class** Story 3.6 hit, recurring in the modern `<WebApplication>` directive. Added a `SessionAgent.UI.StaticAssetApplication.Repair()` ZPM `<Invoke>` hook that resolves the path via `$SYSTEM.Util.InstallDirectory()` at runtime and writes it to `Security.Applications.Modify` — verified path is now correct (`C:\InterSystems\IRISHealth\CSP\static\iris-session-agent\`).

3. **Even with the correct `Path`, HTTP fetches returned 404** — the `/csp/static/...` URL prefix is NOT in Apache's mod_alias config. Web Gateway only forwards specific URL prefixes that pre-exist in Apache config; a brand-new top-level `/csp/static/` path requires operator-level Apache config changes that ZPM cannot perform. **Pivoted to using the existing `/csp/<NS>/` Web Application** (which Apache already routes and serves files from with `ServeFiles=1`). Files now ship to `${cspdir}/${namespace}/sa-static/` via `<FileCopy Name="src/static/" Target="${cspdir}/${namespace}/sa-static/" />` — `${cspdir}` and `${namespace}` BOTH expand correctly in `<FileCopy>`. Removed the dedicated `<WebApplication>` directive AND the `StaticAssetApplication.Repair` `<Invoke>` hook (no longer needed). Final URL pattern is `/csp/hscustom/sa-static/<file>` — fetched HTTP 200 verified for `marked.min.js`, `prism.min.css`, `prism-hl7.js`. Same pivot pattern as Story 3.6's `chat-panel.js` shift from dedicated-static-CSP to per-namespace-class-served — same root cause, same workaround family.

**AC-3 host-page script-tag emission verified.** Both `VisualTrace.cls` and `MessageViewer.cls` extended `%OnDrawHTMLHead` with 12 new tags (1 `<link>` for prism.min.css + 11 `<script>` for marked + prism core + 7 language packs + dompurify), preserving the existing chat-panel.js include after the bundle. URL prefix derived dynamically from `$NAMESPACE` so the same emit works on every interop namespace mapped to `SessionAgent.PKG`. Compile clean for both classes.

**AC-4 chat-panel.js Growth-tier pipeline.** Added `renderMarkdownGrowth(markdown, parentNode)` per the verbatim spec snippet. Pipeline: `marked.parse(md) → DOMPurify.sanitize(html, {USE_PROFILES:{html:true}}) → parentNode.innerHTML = clean → Prism.highlightAllUnder(parentNode) → upgradeInlineCitationsInPlace(parentNode)`. The `upgradeInlineCitationsInPlace` walker scans text nodes (skipping `<pre>`/`<code>`/`<a>` ancestors) so citation chips render correctly post-Markdown without re-parsing code-block contents. `handleEnvelope` and `renderPriorTranscript` both call `renderMarkdownGrowth`; defense-in-depth fallback: when `typeof marked === 'undefined'` OR `typeof DOMPurify === 'undefined'`, falls through to `renderMarkdownFallback` (Story 3.2 MVP path stays in the file).

**AC-5 XSS-safety verification — VERBATIM evidence.** Node + JSDOM smoke test (chrome-devtools-mcp unavailable due to running browser session — used the spec's documented fallback) loaded the live vendored bundle from `C:\InterSystems\IRISHealth\CSP\hscustom\sa-static\` and ran the canonical XSS payloads. Verbatim sanitized HTML output:

```
<h1>Test heading</h1>
<p>A paragraph with <strong>bold</strong> text.</p>
<pre><code class="language-hl7">MSH|^~\&amp;|TEST|TEST|TEST|TEST|20260507||ADT^A01|MSG001|P|2.5
PID|1||PATID1234^^^FACILITY||DOE^JOHN^MIDDLE^^MR
</code></pre>
<pre><code class="language-objectscript">Set tValue = $$$OK
##class(MyClass).MyMethod()
</code></pre>
<p>XSS attack 1: </p>
<p>XSS attack 2: <img src="x"></p>
<p>End of message.</p>
```

All 12 assertions pass:
- `<script>alert('XSS-1')</script>` → completely stripped (`<p>XSS attack 1: </p>` is empty)
- `<img src=x onerror="alert('XSS-2')">` → preserved as `<img src="x">` (onerror attribute stripped, img element kept)
- `language-hl7` + `language-objectscript` classes applied (Prism stubs registered)
- `<h1>` heading + `<pre><code>` code blocks + `<strong>` bold all preserved

`window.xssExecuted` and `window.imgOnerrorFired` both `false` after sanitization.

**AC-6 regression sweep — verbatim SQL ground-truth probe (per .claude/rules/object-script-testing.md §"SQL-probe-as-ground-truth"):**

```
| Total | Passed | Failed |
|-------|--------|--------|
|  408  |   408  |    0   |
```

Reconciles with the spec's expected baseline 404 + 4 new (MarkdownBundleTest) = 408. Per-class roster: 51 classes, every class at 100% pass. New `SessionAgent.Test.MarkdownBundleTest`: 4/4 (DomPurifyJsExistsAndVersionPinned, MarkedJsExistsAndVersionPinned, ModuleXmlContainsFileCopy, NoCdnUrlsInStatic).

**Two regression fix-nows captured during the sweep:**

- **`SessionAgent.Test.ChatPanelJsTest.TestNoInnerHtml`** — Story 3.2 AC-3 hard-banned `.innerHTML =` assignments; Story 10.7 AC-4 explicitly authorizes ONE site (gated by `DOMPurify.sanitize`). Relaxed the test to allow AT MOST one `.innerHTML` occurrence + asserted that `DOMPurify.sanitize` is present in the file as the gating invariant. Documented in the test's doc-comment as the "Story 10.7 relaxation" of the original Story 3.2 AC-3.
- **`SessionAgent.Test.SearchAgentRenderTest.TestChatPanelJsParsesCleanly`** — same anti-innerHTML invariant from Story 10.2; same relaxation.

**File-presence note (12 files in `src/static/`, not 10).** The spec's File List names 10 vendored files. Reality: 12 files ship because `prism-objectscript.js` (the STUB) inherits from `Prism.languages.csharp`, which itself depends on `Prism.languages.clike`. Both `prism-clike.js` and `prism-csharp.js` are required at runtime for the stub to register correctly, OR the operator sees `Prism.languages.objectscript === undefined` at chat-panel-render time. Decided to ship the two extra files inline rather than re-author the stub to copy the C# grammar by value (which would balloon prism-objectscript.js and create a maintenance burden when Prism upgrades csharp).

### File List

**NEW (12 vendored static-asset files in `src/static/`):**
- `src/static/marked.min.js` (marked@18.0.3 — 42803 bytes)
- `src/static/prism.min.js` (prismjs@1.30.0 core)
- `src/static/prism.min.css` (prismjs@1.30.0 default low-contrast theme)
- `src/static/prism-clike.js` (csharp dependency)
- `src/static/prism-csharp.js` (objectscript-stub dependency)
- `src/static/prism-markup.js` (XML / hl7-stub fallback)
- `src/static/prism-sql.js`
- `src/static/prism-javascript.js`
- `src/static/prism-json.js`
- `src/static/prism-objectscript.js` (STUB — inherits from csharp)
- `src/static/prism-hl7.js` (STUB — inherits from markup)
- `src/static/dompurify.min.js` (DOMPurify@3.1.7 — 21531 bytes)

**NEW (1 test class):**
- `src/SessionAgent/Test/MarkdownBundleTest.cls` (4 tests)
- `src/SessionAgent/Test/SweepRunner.cls` (test-helper — drives per-class regression sweep around the broken `/test=...` path on this dev install)

**Modified:**
- `module.xml` — added `<FileCopy Name="src/static/" Target="${cspdir}/${namespace}/sa-static/" />` (architectural pivot from spec's dedicated-CSPApplication path; see Completion Notes AC-2).
- `src/SessionAgent/EnsPortal/VisualTrace.cls` — `%OnDrawHTMLHead` extended with 12 new bundle includes.
- `src/SessionAgent/EnsPortal/MessageViewer.cls` — `%OnDrawHTMLHead` extended with 12 new bundle includes (verbatim mirror of VisualTrace).
- `static/chat-panel.js` — added `renderMarkdownGrowth` + `upgradeInlineCitationsInPlace`; switched `handleEnvelope` and `renderPriorTranscript` to call the Growth-tier path; defense-in-depth fallback to `renderMarkdownFallback` preserved.
- `src/SessionAgent/Test/ChatPanelJsTest.cls` — relaxed `TestNoInnerHtml` to AT MOST one occurrence + DOMPurify.sanitize gating invariant (Story 10.7 relaxation of Story 3.2 AC-3).
- `src/SessionAgent/Test/SearchAgentRenderTest.cls` — same relaxation in `TestChatPanelJsParsesCleanly`.
- `_bmad-output/implementation-artifacts/deferred-work.md` — custom-grammar deferral entry per AC-8.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `10-7-...: backlog → review`.
- This story file — Status `ready-for-dev → review`, Tasks/Subtasks all `[x]`, Completion Notes populated.

### Review Findings

**Code review summary (2026-05-07, single-task reviewer, Opus 4.7 1M).** 0 HIGH; 2 MEDIUM auto-resolved; 1 LOW auto-resolved (cosmetic comment fix); 2 LOW deferred with explicit Rule 8 rationale; 2 INFO/spec-deviation findings dismissed (documented in dev's Completion Notes — extra Prism dependency files + DOMPurify defaults). All AC-1 through AC-8 satisfied. Architectural pivot validated (per-NS `/csp/<NS>/sa-static/` pattern is sound for the install namespace; multi-namespace gap deferred per F1 below). Reviewer-side regression on touched surfaces: ChatPanelJsTest 18/18, MarkdownBundleTest 4/4, SearchAgentRenderTest 4/4, MultiNamespaceInstallTest 3/3.

- [x] [Review][Patch] **F2 — Walker `CITE_RE.test()` `/g`-flag `lastIndex` mutation** [`static/chat-panel.js:1238`] — fixed. Reset `CITE_RE.lastIndex = 0` before each `.test()` call inside `upgradeInlineCitationsInPlace`'s walker filter. Without the reset, text nodes after the first matched node could be silently `FILTER_REJECT`-ed because `RegExp.prototype.test` on a `/g` regex advances `lastIndex` across calls — predicted-bug shape: in a multi-paragraph agent response with citation chips in 2+ paragraphs, only the first paragraph's chips would upgrade to clickable `<a class="sa-citation-chip">` elements; subsequent paragraphs would render the bracketed citation as plain text. Verified `node --check static/chat-panel.js` clean + ChatPanelJsTest 18/18 + SearchAgentRenderTest 4/4 still pass.

- [x] [Review][Patch] **F1 — Multi-namespace bundle distribution gap (operator workaround documented; programmatic fix deferred)** [`module.xml:36`, `src/SessionAgent/Installer.cls:218`] — README updated with the operator-runnable workaround under §"Multi-Namespace Install" Step 3 (manual `robocopy` / `cp -r` of `${cspdir}/<install-NS>/sa-static/` → `${cspdir}/<other-NS>/sa-static/`); deferred-work entry added with full programmatic-fix recommendation (IPM-Module-Root-aware `CopyStaticBundleToNamespace(pNamespace)` step + `MultiNamespaceInstallTest.TestMultiNamespaceBundleFilesPresent` assertion). Rule 8 test 1 (genuine future-epic scope) — the programmatic surface requires IPM API stability research + post-uninstall cleanup symmetry + new install-time path; non-trivial new ~150-line story. Defense-in-depth fallback in `renderMarkdownGrowth` (`typeof marked === 'undefined'` check) keeps multi-namespace operators on a working but visually-degraded surface today (Story 3.2 MVP rendering — code fences and Markdown text, no syntax highlighting). Predicted-bug shape MITIGATED to MEDIUM-severity-with-documented-workaround.

- [x] [Review][Patch] **F3 — Misleading comment in `TestNoInnerHtml`** [`src/SessionAgent/Test/ChatPanelJsTest.cls:229-231`] — fixed. Comment claimed *"Spaced `=` count includes the no-space `=` count (since substring `.innerHTML=` matches `.innerHTML =` too in IRIS string lookup)"* — false. The two substrings differ at character offset 11 (space vs `=`); they are mutually exclusive at any given position and `$Length(s, sub)` counts non-overlapping occurrences. The resulting `$Select` logic still produces the correct count (max of the two = the actual count), but the comment misrepresented IRIS string-lookup semantics. Comment rewritten to accurately describe the mutual-exclusion invariant. Compile-clean; ChatPanelJsTest 18/18 still pass.

- [x] [Review][Defer] **F4 — `SweepRunner.RunAll` uses `Super [ '%UnitTest.TestCase'` substring containment instead of exact equality** [`src/SessionAgent/Test/SweepRunner.cls:23`] — deferred per Rule 8 test 3 (cosmetic, no predicted-bug shape). The `[` operator is broader than `Super = '%UnitTest.TestCase'` exact equality and would false-positive-match a hypothetical class with `'%UnitTest.TestCase'` as a substring within a longer Super attribute. No such class exists in this codebase today; SweepRunner is a test-only helper. If a future class violates the invariant, the SweepRunner would attempt to run a non-TestCase class and the `RunOneTestCase` call would fail-fast in the Try-Catch — operator sees the exception in stdout. Acceptable defensive behavior.

- [x] [Review][Defer] **F5 — `MarkdownBundleTest.GetRepoRoot` hardcodes `c:\git\iris-session-agent\` Windows dev path** [`src/SessionAgent/Test/MarkdownBundleTest.cls:38`] — deferred per Rule 8 test 3 (cosmetic, no predicted-bug shape — fallback path documented). The method's docstring already calls out the env-var override (`ISA_REPO_ROOT`) as the CI-time supply mechanism; the hardcoded fallback is the dev-host convenience path matching the local-server auto-sync workflow per `.vscode/settings.json`. Future CI bringup will set `ISA_REPO_ROOT` and the test will work portably.

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted by lead from epics.md §"Story 10.7" + Rule 8 test 1 explicit deferrals for custom Prism grammars + Rule 10 mandate for Perplexity version verification. | Lead |
| 2026-05-07 | 1.0 | Implementation complete. Vendored bundle (marked@18.0.3 + DOMPurify@3.1.7 + Prism@1.30.0 + 4 stock language packs + 2 STUB grammars + theme CSS) shipped to `${cspdir}/${namespace}/sa-static/` via `<FileCopy>`. Architectural pivot from the spec's dedicated-CSPApplication path — recurrence of Story 3.6's `${cspdir}` bug class + Web Gateway routing gap forced the pivot to the per-namespace `/csp/<NS>/sa-static/` URL pattern (already routed by Apache; matches Story 3.6's class-served-asset pivot family). Growth-tier `renderMarkdownGrowth` pipeline added to chat-panel.js with marked → DOMPurify → Prism flow; defense-in-depth fallback to Story 3.2's `renderMarkdownFallback` preserved. Two regression fix-nows: relaxed Story 3.2 AC-3 / Story 10.2 anti-innerHTML invariants in ChatPanelJsTest + SearchAgentRenderTest to allow ONE DOMPurify-gated innerHTML site (Story 10.7 AC-4 explicitly authorizes). 408/408/0 regression sweep confirmed via canonical numerical-MAX SQL probe against `%UnitTest_Result.TestMethod`. AC-5 XSS-safety verified empirically via Node + JSDOM smoke (chrome-devtools-mcp unavailable due to running session — used spec's documented fallback path) — `<script>` stripped, `<img onerror>` stripped while keeping `<img>`, code blocks render with `language-*` Prism classes. | Dev (Opus 4.7 1M) |
| 2026-05-07 | 1.1 | Code review complete. F2 walker-regex `lastIndex` MEDIUM auto-fixed (`CITE_RE.lastIndex = 0` before each `.test()` in `upgradeInlineCitationsInPlace` walker filter). F1 multi-namespace bundle gap MEDIUM-with-workaround: README §"Multi-Namespace Install" Step 3 documents the manual `robocopy`/`cp -r` operator workaround; deferred-work entry captures programmatic-fix recommendation. F3 misleading comment in `TestNoInnerHtml` LOW auto-fixed. F4 (SweepRunner Super substring) and F5 (MarkdownBundleTest hardcoded path) LOW deferred per Rule 8 test 3 (cosmetic, no bug shape). Reviewer-side regression on auto-fix-touched surfaces: ChatPanelJsTest 18/18, MarkdownBundleTest 4/4, SearchAgentRenderTest 4/4, MultiNamespaceInstallTest 3/3. | Code Reviewer (Opus 4.7 1M) |
