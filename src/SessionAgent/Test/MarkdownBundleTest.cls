/// <p>Story 10.7 unit tests — verifies the vendored Markdown bundle
/// ships correctly:</p>
/// <ol>
/// <li>marked.min.js exists in src/static/ with version ≥ 18.0.2 (or
/// stable equivalent — Perplexity-verified at story-creation time per
/// AC-7).</li>
/// <li>dompurify.min.js exists in src/static/ with version 3.x.</li>
/// <li>module.xml contains the FileCopy directive shipping
/// src/static/ → /csp/&lt;NS&gt;/sa-static/ (per Story 10.7 Task 0
/// architectural pivot — see module.xml comment).</li>
/// <li>NFR-C5 invariant: zero literal "https://cdn." URLs in any
/// src/static/*.js / *.css file (no CDN dependencies — bundle is
/// self-hosted).</li>
/// </ol>
///
/// <p>The tests read files from the on-disk repo under
/// <code>$SYSTEM.Util.GetEnviron("ISA_REPO_ROOT")</code> if set,
/// otherwise default to <code>c:\git\iris-session-agent\</code> — the
/// dev-host check; CI would supply the repo root via env var.</p>
Class SessionAgent.Test.MarkdownBundleTest Extends %UnitTest.TestCase
{

/// %OnNew override required when extending %UnitTest.TestCase per
/// project rule §"Critical Constructor (%OnNew) Requirements".
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// Resolve the repo root — env var ISA_REPO_ROOT, else fallback to
/// the canonical Windows dev-host path (matches the local-server
/// auto-sync workflow per .vscode/settings.json).
ClassMethod GetRepoRoot() As %String [ Private ]
{
    Set tRoot = $SYSTEM.Util.GetEnviron("ISA_REPO_ROOT")
    If tRoot = "" Set tRoot = "c:\git\iris-session-agent\"
    Quit ##class(%Library.File).NormalizeDirectory(tRoot)
}

/// Read a file's contents into a single string. Returns "" if the file
/// doesn't exist OR if the read fails.
ClassMethod ReadFile(pPath As %String) As %String [ Private ]
{
    Set tContent = ""
    If '##class(%Library.File).Exists(pPath) Quit tContent
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tSC = tStream.LinkToFile(pPath)
    If $$$ISERR(tSC) Quit tContent
    While 'tStream.AtEnd {
        Set tContent = tContent _ tStream.Read(32000)
    }
    Quit tContent
}

/// AC-1 verification — marked.min.js exists in src/static/ AND has a
/// version banner in its header. The vendored marked@18.x bundle from
/// jsDelivr begins with a banner line referencing the source path
/// "/npm/marked@<VERSION>/lib/marked.umd.js" — we assert the version
/// substring matches the canonical-stable form (18.x for this story).
Method TestMarkedJsExistsAndVersionPinned()
{
    Set tPath = ..GetRepoRoot() _ "src\static\marked.min.js"
    Do $$$AssertTrue(##class(%Library.File).Exists(tPath), "src/static/marked.min.js must exist")
    Set tContent = ..ReadFile(tPath)
    Do $$$AssertTrue($Length(tContent) > 1000, "marked.min.js must have substantive content (>1KB) — was: " _ $Length(tContent))
    ; Per AC-1 + Rule 10: version pinned to ≥ 18.0.2 (or current stable
    ; per Perplexity verification). Spec verification line in Completion
    ; Notes states marked@18.0.3 is the dev-time stable; the vendored
    ; bundle's jsDelivr banner names the source path which embeds the
    ; version number. Match against the major version 18 (forward-
    ; compatible if a 18.x patch ships before this test runs).
    Do $$$AssertTrue(tContent [ "marked@18.", "marked.min.js header banner must reference marked@18.x — was: " _ $Extract(tContent, 1, 200))
}

/// AC-1 verification — dompurify.min.js exists in src/static/ AND its
/// license banner names version 3.x (the AC-1 floor). The vendored
/// DOMPurify bundle's first line is a license comment of the form
/// /*! @license DOMPurify 3.X.Y | (c) Cure53 ... */
Method TestDomPurifyJsExistsAndVersionPinned()
{
    Set tPath = ..GetRepoRoot() _ "src\static\dompurify.min.js"
    Do $$$AssertTrue(##class(%Library.File).Exists(tPath), "src/static/dompurify.min.js must exist")
    Set tContent = ..ReadFile(tPath)
    Do $$$AssertTrue($Length(tContent) > 1000, "dompurify.min.js must have substantive content (>1KB) — was: " _ $Length(tContent))
    Do $$$AssertTrue(tContent [ "DOMPurify 3.", "dompurify.min.js license banner must reference DOMPurify 3.x — was: " _ $Extract(tContent, 1, 200))
}

/// AC-2 verification — module.xml contains the FileCopy directive
/// shipping src/static/ to the per-namespace CSP directory. The Story
/// 10.7 Task 0 architectural pivot replaced the originally-spec'd
/// dedicated-CSPApplication path (which hit a Web Gateway routing gap
/// — ${cspdir} expanded but Apache had no Alias for the new top-level
/// /csp/static/ prefix) with a per-NS path served by the existing
/// /csp/<NS>/ Web Application.
Method TestModuleXmlContainsFileCopy()
{
    Set tPath = ..GetRepoRoot() _ "module.xml"
    Do $$$AssertTrue(##class(%Library.File).Exists(tPath), "module.xml must exist at repo root")
    Set tContent = ..ReadFile(tPath)
    ; FileCopy directive must reference the src/static/ source AND the
    ; per-NS sa-static/ target. The exact attribute order is not tested
    ; (XML attribute order is non-significant); we check the substring
    ; presence of both pieces.
    Do $$$AssertTrue(tContent [ "FileCopy", "module.xml must contain a <FileCopy> directive")
    Do $$$AssertTrue(tContent [ "src/static/", "module.xml FileCopy Name attribute must reference src/static/")
    Do $$$AssertTrue(tContent [ "sa-static/", "module.xml FileCopy Target attribute must reference sa-static/ subdirectory")
}

/// AC-1 / AC-5 NFR-C5 invariant — no literal "https://cdn." URLs in any
/// src/static/ file. The vendored library headers may reference jsdelivr
/// in their comment banners (the Original-File path is "https://www.jsdelivr.com/...",
/// NOT https://cdn.*); the strict NFR-C5 grep is for the "cdn." substring
/// after "https://" — vendored libraries should be self-contained.
Method TestNoCdnUrlsInStatic()
{
    Set tStaticDir = ..GetRepoRoot() _ "src\static\"
    Do $$$AssertTrue(##class(%Library.File).DirectoryExists(tStaticDir), "src/static/ directory must exist")
    Set tRS = ##class(%Library.File).FileSetFunc(tStaticDir, "*.js;*.css", , 0)
    Set tFound = 0
    Set tFoundFile = ""
    Set tFoundLine = ""
    While tRS.%Next() {
        Set tFile = tRS.%Get("Name")
        Set tContent = ..ReadFile(tFile)
        ; Check for "https://cdn." substring — any library that includes
        ; an absolute CDN URL fails the invariant.
        If tContent [ "https://cdn." {
            Set tFound = 1
            Set tFoundFile = tFile
            ; Extract the offending substring for the assertion message
            Set tIdx = $Find(tContent, "https://cdn.")
            Set tFoundLine = $Extract(tContent, tIdx - 12, tIdx + 60)
            Quit
        }
    }
    Do $$$AssertTrue('tFound, "NFR-C5 violation — found 'https://cdn.' literal in " _ tFoundFile _ ": " _ tFoundLine)
}

}
