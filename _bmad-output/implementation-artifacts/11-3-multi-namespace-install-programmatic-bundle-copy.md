# Story 11.3: Multi-Namespace Install — Programmatic Bundle Copy

Status: done

## Story

As an **Operator-Admin running `Installer.InstallIntoNamespace("OTHERNS")` to extend SessionAgent into a non-HSCUSTOM namespace**,
I want the vendored static bundle (`marked.min.js`, `prism*.js`, `dompurify.min.js`, etc.) to be automatically copied to `${cspdir}/<OTHERNS>/sa-static/` — so that the chat panels in OTHERNS work end-to-end with the Growth-tier Markdown rendering,
So that I don't have to manually `robocopy` / `cp -r` the files post-install per the Story 10.7 README workaround.

## Background — Story 10.7 F1 mitigation, programmatic fix deferred to v2

Story 10.7's `<FileCopy>` directive only fires at the original ZPM install (typically into HSCUSTOM). When operators run `Installer.InstallIntoNamespace("OTHERNS")`, the static bundle is NOT copied to `${cspdir}/OTHERNS/sa-static/`. Per the Story 10.7 review F1 finding:

> Per-NS host pages emit a URL that returns HTTP 404. Defense-in-depth fallback (`typeof marked === 'undefined'`) keeps multi-NS operators on Story 3.2 MVP rendering. README documents the manual `robocopy`/`cp -r` workaround; deferred-work entry captures the full programmatic-fix recommendation.

v1.0.1 fix-now per user post-tag triage.

## Acceptance Criteria

### AC-1 — `Installer.InstallIntoNamespace` copies the bundle

**Given** the operator invokes `##class(SessionAgent.Installer).InstallIntoNamespace("OTHERNS")` from `%SYS` namespace
**When** the install proceeds
**Then** the installer locates the source bundle directory (the original IPM-installed location — see AC-3 for resolution strategy) AND copies the contents to `${cspdir}/OTHERNS/sa-static/`.
**And** the copy is idempotent — re-running `InstallIntoNamespace("OTHERNS")` succeeds whether or not the target directory already exists or is partially populated.
**And** the operator does NOT need to manually `robocopy` / `cp -r` post-install.

### AC-2 — Source bundle path resolution

**Given** the installer needs to locate the original bundle source
**When** the developer implements the path resolution
**Then** the resolution strategy is one of:
1. **IPM Module Root API** — query the IPM-installed module's root directory via `%ZPM.PackageManager.Developer.Module:GetRootDirectory()` (or equivalent IPM API) for the `iris-session-agent` module → bundle is at `<root>/static/`.
2. **Walk back from `${cspdir}/<original-install-ns>/sa-static/`** — assume HSCUSTOM was the original install namespace; `${cspdir}/hscustom/sa-static/` exists post-install per Story 10.7's `<FileCopy>` directive; copy from there.
3. **Embedded resource** — read the bundle files via `%Library.File` from the source path discovered via `$ZUtil(12)` + relative path traversal.

The dev should pick the most robust strategy. **Preference: option 2 (walk back from canonical install location)** — simplest, no IPM API dependency, works regardless of how the module was installed.

### AC-3 — Implementation in `Installer.cls`

**Given** the dev is extending `SessionAgent.Installer:InstallIntoNamespace`
**When** the dev adds the bundle-copy step
**Then** a new private ClassMethod `CopyStaticBundleToNamespace(pNamespace As %String) As %Status`:

```objectscript
ClassMethod CopyStaticBundleToNamespace(pNamespace As %String) As %Status [ Private ]
{
    Set tSC = $$$OK
    Try {
        // Resolve canonical source: ${cspdir}/hscustom/sa-static/ (Story 10.7 install location)
        Set tCspDir = $System.CSP.GetDefaultApp("%SYS").Path  // OR use %SYS-specific cspdir lookup
        Set tSource = tCspDir _ "hscustom/sa-static/"
        Set tTarget = tCspDir _ $ZCONVERT(pNamespace, "L") _ "/sa-static/"

        // Bail-out: source doesn't exist (means the original install didn't run)
        If '##class(%File).DirectoryExists(tSource) {
            // Log + return OK — operator can manually copy or re-run zpm install
            Quit
        }

        // Idempotent: ensure target directory exists
        Set tCreateSC = ##class(%File).CreateDirectoryChain(tTarget)
        If $$$ISERR(tCreateSC) Set tSC = tCreateSC Quit

        // Copy each file in the source directory (non-recursive — bundle is flat)
        Set tRs = ##class(%ResultSet).%New("%File:FileSet")
        Do tRs.Execute(tSource, "*", "Name", 1)
        While tRs.Next() {
            Set tFileName = ##class(%File).GetFilename(tRs.Get("Name"))
            Set tCopySC = ##class(%File).CopyFile(tRs.Get("Name"), tTarget _ tFileName, 1)  // overwrite=1 for idempotence
            If $$$ISERR(tCopySC) Set tSC = tCopySC Quit
        }
        Do tRs.Close()
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}
```

**And** `InstallIntoNamespace` invokes the helper before/after the existing seed-config + audit-event-registration steps (order doesn't matter; install-time only).

**And** if the helper returns an error, log it but don't fail the entire install — the operator can recover via manual copy. Pattern: `Set tCopySC = ..CopyStaticBundleToNamespace(pNamespace) If $$$ISERR(tCopySC) { Write !, "[iris-session-agent] WARN: bundle copy failed for "_pNamespace_" — see manual robocopy fallback in README", $System.Status.GetErrorText(tCopySC) }`.

### AC-4 — README workaround marked DEPRECATED

**Given** the programmatic fix is in place
**When** the dev updates `README.md` §"Multi-Namespace Install"
**Then** the manual `robocopy` / `cp -r` instructions are marked DEPRECATED (kept for operators on older versions but noted as no-longer-required for v1.0.1+).

### AC-5 — Test class additions

**Given** `SessionAgent.Test.MultiNamespaceInstallTest` already exists
**When** the dev extends it
**Then** at least 1 new test:
- `TestInstallIntoNamespaceCopiesStaticBundle` — invoke `InstallIntoNamespace("SATEST64")` (or the test namespace), verify post-install that `${cspdir}/satest64/sa-static/marked.min.js` exists.

### AC-6 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.Installer`.
- `SessionAgent.Test.MultiNamespaceInstallTest` extended (1 new test).
- **Per-class regression sweep + canonical numerical-MAX SQL probe**. **Expected baseline 423 + 1 = 424+**.

## Tasks / Subtasks

- [x] **Task 0 — Probe `${cspdir}` resolution + IPM Module Root API**
  - [x] Read `irislib/%System/CSP.cls` for the canonical way to resolve `${cspdir}`.
  - [x] If IPM Module Root API is preferred, probe `%ZPM.PackageManager.Developer.Module` for the right method.
  - [x] Document the chosen strategy.

  **Strategy chosen: Option 2 (walk back from canonical install location).**
  CSP-dir resolution: `##class(%File).SubDirectoryName($System.Util.InstallDirectory(), "csp", 1)` produces `C:\InterSystems\IRISHealth\CSP\` (Windows) or `/usr/irissys/csp/` (Linux). Source bundle: `<csp>/hscustom/sa-static/` (13 files confirmed: `marked.min.js`, `prism-*.js`, `dompurify.min.js`, etc.). Target: `<csp>/<lower(pNamespace)>/sa-static/`. No IPM API dependency — works regardless of how the module was installed. Empirical probe (HSCUSTOM, 2026-05-08): `sa-static` exists at canonical hscustom path; `satest64/` csp dir does not exist (`CreateDirectoryChain` handles).

- [x] **Task 1 — Implement `CopyStaticBundleToNamespace` helper (AC: #3)**
  - [x] Add the private ClassMethod per AC-3 verbatim (or adapted to the chosen path-resolution strategy).
  - [x] Add invocation from `InstallIntoNamespace` with non-fatal error handling.
  - [x] Compile.

- [x] **Task 2 — README update (AC: #4)**
  - [x] Mark manual `robocopy` / `cp -r` instructions as DEPRECATED (no-longer-required for v1.0.1+).

- [x] **Task 3 — Test class extension (AC: #5)**
  - [x] Add `TestInstallIntoNamespaceCopiesStaticBundle` to `MultiNamespaceInstallTest`. Compile + per-class run.

- [x] **Task 4 — Live verification**
  - [x] Run `Installer.InstallIntoNamespace("SATEST64")` against a test namespace; verify `${cspdir}/satest64/sa-static/` is populated; HTTP-fetch one of the assets to confirm 200 response.

  **Live evidence (2026-05-08, HSCUSTOM, dev host):**
  - BEFORE: `${cspdir}/satest64/sa-static/` did NOT exist (`exists: 0`).
  - `Installer.InstallIntoNamespace("SATEST64")` log line: `[iris-session-agent] Copied 13 static bundle file(s) to C:\InterSystems\IRISHealth\CSP\satest64\sa-static\`.
  - AFTER: target directory exists (`exists: 1`); `marked.min.js exists: 1` at `C:\InterSystems\IRISHealth\CSP\satest64\sa-static\marked.min.js`.
  - Idempotent re-run: second `InstallIntoNamespace("SATEST64")` succeeds with same "Copied 13 file(s)" log line; status OK.
  - **HTTP-fetch caveat (out of AC-1 scope):** `/csp/satest64/sa-static/marked.min.js` returns HTTP 404 because SATEST64 has no `/csp/satest64` CSP Web Application registered (the namespace was created via `Config.Namespaces.Create` only, without the per-NS CSP web-app registration that HealthShare environments perform via `EnableNamespace`). This is a pre-existing namespace-bootstrap concern orthogonal to Story 11.3 — AC-1 specifies "copies the contents to `${cspdir}/OTHERNS/sa-static/`" (disk delivery, satisfied) and does NOT require a CSP web-app to exist. Reference: hscustom path `/csp/hscustom/sa-static/marked.min.js` returns HTTP 200 / 42803 bytes — the bundle itself is HTTP-servable when a `/csp/<NS>` web app is registered. Operators on plain-IRIS deployments who create namespaces without the implicit `/csp/<NS>` web-app will still need to create the web-app separately (this is unchanged from pre-11.3 behavior).

- [x] **Task 5 — Verification battery**
  - [x] Per-class regression sweep + canonical numerical-MAX SQL probe.

  **SQL ground-truth (canonical numerical-MAX form, per `.claude/rules/object-script-testing.md`):**
  ```
  Total | Passed | Failed
  ------|--------|-------
   426  |  426   |   0
  ```
  Exceeds 424+ baseline expected per AC-6 (423 prior + 1 new = 424+). Per-class probe of `SessionAgent.Test.MultiNamespaceInstallTest`: 7/7 pass; new `TestInstallIntoNamespaceCopiesStaticBundle` Status=1.

## Dev Notes

### Rule 1 / Rule 8 / Rule 11

- **Rule 1:** Spec ~140 lines.
- **Rule 8:** Real operator-observable defect for multi-NS deployments; fix-now.
- **Rule 11:** Live exercise via Task 4 against SATEST64.

### Cross-platform path concerns

`${cspdir}` resolution differs on Windows vs Linux. Use `##class(%File).NormalizeFilename` and `##class(%File).CreateDirectoryChain` (which handles cross-platform path semantics) rather than string concatenation with hardcoded separators. The bundle filenames are always lowercase `marked.min.js` etc.; case-sensitive match on Linux but case-insensitive on Windows — `##class(%File).FileSet` handles both.

## Dev Agent Record

### Implementation Plan (executed)

1. **Task 0** — Probed `${cspdir}` resolution. Chose Option 2 (walk back from canonical install location): `##class(%File).SubDirectoryName($System.Util.InstallDirectory(), "csp", 1)` resolves cross-platform.
2. **Task 1** — Added private `CopyStaticBundleToNamespace(pNamespace)` ClassMethod to `SessionAgent.Installer.cls`. Uses `%File:CreateDirectoryChain` for idempotent target creation, `%ResultSet "%File:FileSet"` for source enumeration (skipping directory entries defensively), `%File:CopyFile` with overwrite=1. Invoked from `InstallIntoNamespace` as final step (5) with non-fatal error handling — failure logs WARN line pointing at README's deprecated manual fallback but does NOT propagate as install failure.
3. **Task 2** — Updated README §"Multi-Namespace Install" to mark v1.0.1+ as automatic; preserved manual `robocopy`/`cp -r` instructions inside a `<details>` collapsible block labeled DEPRECATED.
4. **Task 3** — Added `TestInstallIntoNamespaceCopiesStaticBundle` to `MultiNamespaceInstallTest`. Uses same path-resolution strategy as the helper to compute expected target. Skips gracefully when runner lacks create-namespace permission, when SATEST64 not prepared, OR when source bundle is missing. Asserts: target dir exists, `marked.min.js` present at target, ≥2 files copied.
5. **Task 4** — Live verification on dev host: `[iris-session-agent] Copied 13 static bundle file(s) to C:\InterSystems\IRISHealth\CSP\satest64\sa-static\` log line confirms; `marked.min.js exists: 1`; idempotent re-run successful. HTTP-fetch returns 404 because SATEST64 has no `/csp/satest64` Web Application registered — out-of-AC-1-scope namespace-bootstrap concern, documented in Task 4 Completion Notes.
6. **Task 5** — Regression sweep via canonical numerical-MAX SQL probe: 426/426/0 (exceeds 424+ baseline expected by AC-6); new test `TestInstallIntoNamespaceCopiesStaticBundle` Status=1.

### Completion Notes

- **AC-1 satisfied** — `Installer.InstallIntoNamespace("OTHERNS")` now copies bundle to `${cspdir}/<lower-OTHERNS>/sa-static/` automatically. Idempotent (verified via second invocation against same NS).
- **AC-2 satisfied** — Strategy chosen: Option 2 (walk back from canonical install location), per spec preference. No IPM API dependency.
- **AC-3 satisfied** — Private `CopyStaticBundleToNamespace(pNamespace As %String) As %Status [ Private ]` method added to `SessionAgent.Installer.cls`. Invoked from `InstallIntoNamespace` with non-fatal error handling per spec wording.
- **AC-4 satisfied** — README §"Multi-Namespace Install" v1.0.1+ updated; manual `robocopy`/`cp -r` workaround marked DEPRECATED inside a collapsible details block.
- **AC-5 satisfied** — `TestInstallIntoNamespaceCopiesStaticBundle` added to `SessionAgent.Test.MultiNamespaceInstallTest`; SQL probe confirms Status=1.
- **AC-6 satisfied** — `iris_doc_compile` clean for both `SessionAgent.Installer` and `SessionAgent.Test.MultiNamespaceInstallTest`. Per-class regression sweep + canonical numerical-MAX SQL probe: **426/426/0** (exceeds 424+ baseline). MultiNamespaceInstallTest: 7/7 pass.

### Verbatim AC-contract evidence (per .claude/rules/epic-cycle-discipline.md Rule 2 sharpened form)

**AC-1 evidence — disk delivery:**
```
BEFORE InstallIntoNamespace:
  target: C:\InterSystems\IRISHealth\CSP\satest64\sa-static\
  exists: 0
[iris-session-agent] Copied 13 static bundle file(s) to C:\InterSystems\IRISHealth\CSP\satest64\sa-static\
AFTER:
  target dir exists: 1
  marked.min.js exists: 1
```

**AC-1 idempotency evidence — second invocation:**
```
[iris-session-agent] Copied 13 static bundle file(s) to C:\InterSystems\IRISHealth\CSP\satest64\sa-static\
Re-run status:    (empty = $$$OK)
```

**AC-5 evidence — verbatim per-method roster (canonical numerical-MAX SQL probe of `SessionAgent.Test.MultiNamespaceInstallTest`):**
| Method | Status |
|---|---|
| TestInstallIntoNamespaceCopiesStaticBundle | 1 |
| TestInstallIntoNamespaceCreatesPerNamespaceState | 1 |
| TestInstallIntoNamespaceIdempotency | 1 |
| TestInstallIntoNamespaceRejectsEmptyString | 1 |
| TestInstallIntoNamespaceRejectsMissingNamespace | 1 |
| TestInstallIntoNamespaceRejectsSysNs | 1 |
| TestInstallIntoNamespaceRejectsUnmappedPackage | 1 |

**AC-6 evidence — verbatim regression sweep totals (canonical numerical-MAX form):**
```
Total | Passed | Failed
------|--------|-------
 426  |  426   |   0
```

### File List

- `src/SessionAgent/Installer.cls` (modified — added `CopyStaticBundleToNamespace` private ClassMethod + non-fatal invocation from `InstallIntoNamespace` as step 5)
- `README.md` (modified — §"Multi-Namespace Install" updated for v1.0.1 auto-copy; manual `robocopy`/`cp -r` workaround marked DEPRECATED inside collapsible `<details>` block)
- `src/SessionAgent/Test/MultiNamespaceInstallTest.cls` (extended — 1 new test method `TestInstallIntoNamespaceCopiesStaticBundle`)
- `_bmad-output/implementation-artifacts/11-3-multi-namespace-install-programmatic-bundle-copy.md` (story file — task checkboxes flipped, Dev Agent Record populated, status → review)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status flipped ready-for-dev → in-progress → review)

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-08 | 0.1 | Initial spec drafted post-v1.0.0-tag from Story 10.7 F1 deferred-work. | Lead |
| 2026-05-08 | 1.0 | Implementation complete. `CopyStaticBundleToNamespace` helper added; `InstallIntoNamespace` invokes with non-fatal error handling; README workaround marked DEPRECATED; new test `TestInstallIntoNamespaceCopiesStaticBundle` passes; regression sweep 426/426/0 via canonical numerical-MAX SQL probe. | Dev |
