# Story 1.1: Project Initialization

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an **Operator-Admin**,
I want to clone the iris-session-agent repository and find a complete IPM-installable package skeleton at the repo root,
so that I can run `zpm load /path/to/repo` against a fresh **IRIS / IRIS for Health 2024.1+** instance and observe the package compiles cleanly with exit status 0 — before any feature work lands.

This is the foundation story for Epic 1: it creates the hand-authored `module.xml` + `LICENSE` + `README.md` + `.gitignore` + empty `src/` skeleton. There is intentionally no `iris init` CLI ([Source: architecture.md §"Initialization (Story 1.1 work)"](../../_bmad-output/planning-artifacts/architecture.md)). Subsequent Epic-1 stories layer audit-event registration (1.3), RBAC role install (1.4), the `Installer.Install` orchestrator (1.5), operator quickstart docs (1.6), and CI scaffolding (1.7) on top of this skeleton.

## Acceptance Criteria

**AC-1 — `module.xml` exists at repo root, matching the verbatim 33-line shape from the architecture's research source.**

**Given** the user has cloned the repository
**When** they inspect the repo root
**Then** `module.xml` exists with the exact shape documented in [research §"IPM `module.xml` — Concrete v1 Shape"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) (lines 957–993). Specifically:

- Single `<Resource Name="SessionAgent.PKG"/>` entry
- `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>`
- Dedicated unauthenticated `<CSPApplication Url="/csp/static/iris-session-agent" Path="${cspdir}static/iris-session-agent" Resource="" Recurse="1" UseCookies="0" AuthenticationMethods="64"/>`
- Three `<Invoke>` install hooks targeting `SessionAgent.Installer.Install`, `SessionAgent.Audit.Emit.EnsureEvents`, `SessionAgent.Security.ReadOnlyRole.Install`
  - **CRITICAL:** these target classes do not yet exist (they ship in stories 1.3, 1.4, 1.5). The hooks must be **commented out** with a brief inline note (`<!-- Uncommented in Story 1.5 once installer ships -->`) so `zpm load` succeeds against the empty skeleton. Story 1.5 uncomments them.
- `<Name>iris-session-agent</Name>`, `<Version>1.0.0</Version>`, `<Description>Pure-ObjectScript Ensemble session inspection and message search agents</Description>`, `<Packaging>module</Packaging>`, `<SourcesRoot>src</SourcesRoot>`

**AC-2 — `LICENSE` exists at repo root with verbatim MIT text and the project's copyright line.**

**Given** the user inspects the repo root
**When** they open `LICENSE`
**Then** the file contains the standard MIT License text with the copyright line `Copyright (c) 2026 Joshua Brandt` ([Source: architecture.md §"Project Directory Structure"](../../_bmad-output/planning-artifacts/architecture.md), [project memory: product posture — open-source from day one, likely MIT]).

**AC-3 — `README.md` exists with a project header, one-line description, and a placeholder `## Operator Prerequisites` heading (full content lands in Story 1.2).**

**Given** the user opens `README.md`
**When** they read it
**Then** the file contains (at minimum) a project header, a one-line description, and an `## Operator Prerequisites` H2 heading positioned as the first H2 after the project introduction with placeholder body text (e.g., `_Full content lands in Story 1.2 — see [epics.md](_bmad-output/planning-artifacts/epics.md#story-12)._`).
**And** the existing README content (already substantive per pre-existing repo state — under-construction banner, "What it does" sections, Status section) is **preserved**, not replaced. The acceptance criterion is structural anchor presence, not content rewrite.

**AC-4 — `.gitignore` exists with standard IRIS, VSCode, and IDE patterns.**

**Given** the user inspects `.gitignore`
**When** they read it
**Then** the file lists, at minimum:

- IRIS artifacts: `*.cls.gz`, `*.int.gz`, `*.xml.gz`, `*.gbl.xml`, IRIS export staging dirs, journal/buffer pool noise
- VSCode patterns: `.vscode/*` except `.vscode/settings.json`, `.vscode/tasks.json`, `.vscode/launch.json`, `.vscode/extensions.json` (standard "ignore everything except shared config" pattern)
- IDE patterns: `.idea/`, `*.iml`, `*.swp`, `.vs/`
- OS noise: `Thumbs.db`, `.DS_Store`
- The existing `irislib/` and `sources/` entries (preserved — these are local read-only reference dirs the user keeps out of source control)

**AC-5 — `src/SessionAgent/` and `src/static/` directories exist (empty or with `.gitkeep`).**

**Given** the user inspects the source tree
**When** they `ls src/`
**Then** both `src/SessionAgent/` and `src/static/` directories exist. Each contains either content (when later stories add it) or a `.gitkeep` file so the empty directory is tracked by git ([Source: architecture.md §"Project Directory Structure" lines 800–913](../../_bmad-output/planning-artifacts/architecture.md)).

**AC-6 — `zpm load` succeeds against this skeleton on a fresh IRIS 2024.1+ instance.**

**Given** a fresh IRIS / IRIS for Health 2024.1+ instance with no existing iris-session-agent install
**When** the user runs `zpm load /path/to/repo`
**Then** the install completes with exit status 0
**And** `module.xml` is parsed without warnings
**And** no `[Language = python]` references appear in any shipped file under `src/SessionAgent/` (CI grep enforces in Story 1.7; manual grep verifies for this story).

**AC-7 — Repository tree matches the architecture's Project Directory Structure file tree.**

**Given** the developer wants to verify the project root layout
**When** they view the repository tree
**Then** the layout matches [architecture.md §"Project Directory Structure"](../../_bmad-output/planning-artifacts/architecture.md) (lines 770–916). For Story 1.1's scope, that means: `module.xml`, `LICENSE`, `README.md`, `.gitignore` at root; empty `src/SessionAgent/` and `src/static/` directories. Higher-level dirs that already exist (`docs/`, `_bmad-output/`, `.github/`) remain undisturbed; class-level files are out of scope for this story.

## Tasks / Subtasks

- [x] **Task 1 — Author `module.xml` at repo root (AC: #1, #6)**
  - [x] Copy the 33-line shape verbatim from [research lines 957–993](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)
  - [x] **Comment out** the three `<Invoke>` lines (target classes not yet shipped); add inline note `<!-- Uncommented in Story 1.5 once installer ships -->` above the commented block
  - [x] Verify `<CSPApplication>` `AuthenticationMethods="64"` (= unauthenticated; required for browser to fetch vendored static assets without a portal session)
  - [x] Save with UTF-8, LF line endings (no BOM)

- [x] **Task 2 — Author `LICENSE` at repo root (AC: #2)**
  - [x] Use the standard MIT License text (copy from https://opensource.org/license/mit or any canonical source)
  - [x] Set the copyright line to: `Copyright (c) 2026 Joshua Brandt`
  - [x] Save with UTF-8, LF line endings

- [x] **Task 3 — Update `README.md` to add `## Operator Prerequisites` placeholder (AC: #3)**
  - [x] Read the existing `README.md` first (it already has a project header, under-construction banner, "What it does" section, "Status" section — these must be preserved)
  - [x] Insert an `## Operator Prerequisites` H2 heading **immediately after the one-line description / project introduction**, before "## What it does" (per [epics.md Story 1.2 AC](../../_bmad-output/planning-artifacts/epics.md#story-12) which says the section is "the first H2 heading after the project introduction"). Body text: `_Full content lands in Story 1.2 — see [Operator README Content in research](_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)._` (1–2 sentence placeholder is sufficient)
  - [x] Do **not** delete or rewrite existing README content — Story 1.1's job is to add the structural anchor only

- [x] **Task 4 — Update `.gitignore` with standard IRIS / VSCode / IDE patterns (AC: #4)**
  - [x] Read the existing `.gitignore` first (currently has `irislib/` and `sources/` — preserve these)
  - [x] Add a section header comment for each grouping (`# IRIS`, `# VSCode`, `# IDE`, `# OS`)
  - [x] Add patterns listed in AC-4
  - [x] For VSCode: use the standard "ignore-all-except-shared-config" pattern (`.vscode/*` then `!.vscode/settings.json` etc.)
  - [x] Save with UTF-8, LF line endings

- [x] **Task 5 — Create empty `src/SessionAgent/` and `src/static/` directories with `.gitkeep` (AC: #5)** — *adapted, see Completion Notes*
  - [x] `mkdir -p src/SessionAgent` and `mkdir -p src/static`
  - [x] `touch src/SessionAgent/.gitkeep` and `touch src/static/.gitkeep` — *`.gitkeep` in `src/SessionAgent/` was replaced with `src/SessionAgent/Placeholder.cls` (a hidden no-op class) because IPM's `Default.Package` resource processor walks the package directory with a `*` wildcard and rejects `.gitkeep` as "Unknown file type". The Placeholder class satisfies AC-5's "or content" provision and tracks the directory in git. `src/static/.gitkeep` is unchanged.*
  - [x] Confirm `git status` shows both placeholder files as new untracked files

- [x] **Task 6 — Verify `zpm load` succeeds (AC: #6)**
  - [x] **Use the iris-dev MCP** (`iris_doc_load` or equivalent) to load this skeleton on the locally-running IRIS 2024.1+ instance — *used `mcp__iris-dev-mcp__iris_execute_command` with `zpm "load c:/git/iris-session-agent"` in `%SYS` namespace*
  - [x] If `iris_doc_load` isn't suited to whole-module loads, run the equivalent IRIS shell command via `iris_execute_command`: `do $system.OBJ.LoadDir("/path/to/repo/src","ck",,1)` is a class-only fallback; for full module load use `zpm "load /path/to/repo"` via `iris_execute_command`
  - [x] Capture the install log; confirm exit status 0 and no warnings about `module.xml` parsing — *all 6 lifecycle phases SUCCESS; the only WARNING is a deprecation notice for the `<CSPApplication>` tag (not a parsing warning)*
  - [x] Document captured log snippet in **Completion Notes** below
  - [x] Run `grep -r "Language = python" src/SessionAgent/` — must return zero matches (NFR-C2 per architecture's pure-OS-runtime invariant) — *zero matches confirmed*

- [x] **Task 7 — Verify repository tree matches architecture (AC: #7)**
  - [x] Run `git status` and `ls -la` at repo root
  - [x] Confirm: `module.xml`, `LICENSE`, `README.md`, `.gitignore` exist at root; `src/SessionAgent/Placeholder.cls` and `src/static/.gitkeep` are tracked; `static/.gitkeep` at module root tracked (required by `<FileCopy Name="static/">` semantics — see Completion Notes for the architecture-diagram vs verbatim-module.xml reconciliation)

## Dev Notes

### Why this story is a "hand-author scaffold" rather than `iris init` or a generator

There is no `iris init` CLI. Per [architecture.md §"Initialization (Story 1.1 work)"](../../_bmad-output/planning-artifacts/architecture.md): *"The first implementation story creates by hand at the repo root."* The architectural decisions provided by this approach are already locked:

- **Language & runtime:** ObjectScript only — no Python, no JavaScript at the IRIS runtime layer (vendored JS is browser-side only). Per **PRD NFR-C2 (pure-OS-runtime invariant)**.
- **Module shape:** Single ZPM module, single `<Resource>`, no transitive deps. Per **PRD NFR-C4**.
- **Static-asset distribution:** Self-hosted under `/csp/static/iris-session-agent/`, no CDN. Per **PRD NFR-C5**.
- **Build tooling:** None custom — IRIS's compiler does the work; tests use `%UnitTest.TestCase`; no transpile, bundle, or post-process step at install.
- **Code organization:** All classes under `SessionAgent.*` (single root package, per saved memory `project_package_naming.md`).

### Pre-existing repo state (already on disk — do NOT recreate, only update)

```
iris-session-agent/
├── README.md                  # 110 lines; substantial under-construction banner + "What it does" content already exists
├── .gitignore                 # 2 lines: `irislib/` + `sources/`
├── .git/, .claude/, _bmad/, _bmad-output/, docs/, irislib/, sources/, src/   # all directories already present
└── iris-session-agent.code-workspace   # VSCode workspace file (leave alone)
```

**Files to CREATE:** `module.xml`, `LICENSE`, `src/SessionAgent/.gitkeep`, `src/static/.gitkeep`.
**Files to UPDATE (not replace):** `README.md` (add `## Operator Prerequisites` placeholder), `.gitignore` (add IRIS/VSCode/IDE patterns).

### Verbatim `module.xml` shape (from research lines 957–993, with Invoke comments noted)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Export generator="Cache" version="25">
  <Document name="iris-session-agent.ZPM">
    <Module>
      <Name>iris-session-agent</Name>
      <Version>1.0.0</Version>
      <Description>Pure-ObjectScript Ensemble session inspection and message search agents</Description>
      <Packaging>module</Packaging>
      <SourcesRoot>src</SourcesRoot>

      <!-- Class packages compiled into HSCUSTOMCODE -->
      <Resource Name="SessionAgent.PKG"/>

      <!-- Static UI assets vendored locally (no CDN dependency per PRD NFR-C5) -->
      <FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>

      <!-- Dedicated CSP application for static assets (unauthenticated read) -->
      <CSPApplication Url="/csp/static/iris-session-agent"
                      Path="${cspdir}static/iris-session-agent"
                      Resource=""
                      Recurse="1"
                      UseCookies="0"
                      AuthenticationMethods="64"/>

      <!-- Install-time hooks — uncommented in Story 1.5 once installer ships
      <Invoke Method="Install" Class="SessionAgent.Installer"/>
      <Invoke Method="EnsureEvents" Class="SessionAgent.Audit.Emit"/>
      <Invoke Method="Install" Class="SessionAgent.Security.ReadOnlyRole"/>
      -->

      <!-- No external ZPM dependencies (per PRD NFR-M9 / NFR-C4 lineage) -->
    </Module>
  </Document>
</Export>
```

### Project rules that apply to this story

From [.claude/rules/](../../.claude/rules/):

- **`research-first.md` §"Task 0 backend-surface probe"** — applies to Epic 12+ stories whose ACs reference new/modified backend endpoints. Story 1.1 is **not** Epic 12+ and does not introduce a backend endpoint. **No Task 0 probe required for this story.** (Story 1.2's Web Gateway timeout probe is the first Task 0 probe in this project.)
- **`iris-objectscript-basics.md` §Naming Conventions** — applies once class files start landing (Stories 1.3+). Story 1.1 ships no class files, so no naming-convention checks apply yet.
- **No tests for this story.** Story 1.1's "tests" are the `zpm load` exit-status-0 check (AC-6) and the structural file-presence checks (AC-1 through AC-7). The first `%UnitTest.TestCase` lands in Story 1.3 (`Test/AuditEmitTest.cls`).

### Handling the in-place README.md

The pre-existing `README.md` is already 110 lines of substantive content with an under-construction banner, project description, "What it does", design properties, and Status sections. **Do not rewrite it.** The story's intent is to ensure the `## Operator Prerequisites` structural anchor exists for Story 1.2 to fill — that's all this story should change in the README.

Insertion point: locate the first `## ` H2 heading in the existing README (currently `## What it does`) and insert `## Operator Prerequisites` + 1–2 sentence placeholder immediately **before** it. The pre-existing markdown blockquote (`> [!WARNING] Under construction...`) is part of the project introduction and stays above the new H2 — per [epics.md Story 1.2 AC](../../_bmad-output/planning-artifacts/epics.md): *"the section is positioned as the first H2 heading after the project introduction"*.

### Why three `<Invoke>` hooks must be commented out for this story

Story 1.1 ships **no ObjectScript classes**. The three install hooks reference classes that don't exist yet:

- `SessionAgent.Installer.Install` — ships in Story 1.5
- `SessionAgent.Audit.Emit.EnsureEvents` — ships in Story 1.3
- `SessionAgent.Security.ReadOnlyRole.Install` — ships in Story 1.4

If these hooks are uncommented at this story's stage, `zpm load` will fail at install time with `<CLASS DOES NOT EXIST>` — violating AC-6. The architecturally clean solution is to keep them as **commented-out lines** so the file shape matches the v1 spec verbatim (a future reviewer doesn't have to wonder why they're missing) but install succeeds. **Story 1.5 uncomments these lines as part of its own AC.**

### Project Structure Notes

- All paths in this story are at the **repo root** or under `src/`. No edits under `_bmad/`, `_bmad-output/`, `docs/`, or `.claude/` are required (those are planning/configuration artifacts, not shippable source).
- The `iris-session-agent.code-workspace` file at repo root is a VSCode workspace file — **leave it alone**, do not touch.
- The pre-existing `irislib/` and `sources/` directories are local read-only reference checkouts (per the existing `.gitignore`). They stay ignored. This story does not interact with them.

### References

- [architecture.md §"Initialization (Story 1.1 work)"](../../_bmad-output/planning-artifacts/architecture.md) — locks the hand-author approach and the architectural decisions baked into this skeleton (no Python at runtime, single root package, no CDN).
- [architecture.md §"Project Directory Structure"](../../_bmad-output/planning-artifacts/architecture.md) lines 770–916 — the canonical file tree to align against.
- [architecture.md §"Naming Patterns"](../../_bmad-output/planning-artifacts/architecture.md) lines 354–411 — naming conventions (apply when class files land in 1.3+).
- [research §"IPM `module.xml` — Concrete v1 Shape"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) lines 957–993 — verbatim source for `module.xml`.
- [epics.md Epic 1 §Story 1.1](../../_bmad-output/planning-artifacts/epics.md) — story acceptance criteria source (lines 517–542).
- [epics.md Epic 1 §Story 1.2](../../_bmad-output/planning-artifacts/epics.md) — informs README placeholder positioning (lines 544–567).
- Project memory `project_package_naming.md` — all classes under `SessionAgent.*`; RBAC role is `%SessionAgent_ReadOnly`.
- Project memory `project_iris_version_floor.md` — IRIS 2024.1 floor; verify any used IPM features against 2024.1.
- Project memory `project_implementation_language.md` — pure ObjectScript; no Python in runtime path.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) via Claude Code SDK; iris-dev MCP server for IRIS execution against IRIS for Health 2025.1 (Build 230.2U) on Windows 11.

### Debug Log References

- IRIS server probe (Build 2025.1.0.230.2U; namespaces: %SYS, HSCUSTOM, HSLIB, HSSYS, HSSYSLOCALTEMP, IRISCOUCH, USER; HEALTHSHARE + ENSEMBLE features enabled)
- IPM was not pre-installed; bootstrapped via `$System.OBJ.Load("C:\Users\Josh\AppData\Local\Temp\zpm-installer.xml","ck")` — installer downloaded from `https://pm.community.intersystems.com/packages/zpm/latest/installer` (yields IPM 0.10.6 in %SYS, sufficient for `zpm load` lifecycle).
- `zpm load c:/git/iris-session-agent` final run: all 6 phases (Initialize / Reload / Validate / Compile / Activate / Configure) report SUCCESS.
- IRIS source-of-truth references read for IPM behavior decisions: `%IPM.Storage.ResourceReference.GetChildren` (PKG resource only walks `*.cls,*.mac,*.int,*.inc`), `%IPM.ResourceProcessor.Default.Document.OnPhase` (Reload phase calls `$system.OBJ.ImportDir(path, "*"_..FilenameExtension, ...)` — with empty FilenameExtension this becomes `*` which catches `.gitkeep`), `%IPM.ResourceProcessor.FileCopy.GetSource` (`Module.Root + Name` — i.e., FileCopy `Name` attribute is relative to repo root, NOT to `<SourcesRoot>`).

### Completion Notes List

**Final state: all 7 ACs satisfied; all 7 Tasks complete.**

#### `zpm load` capture (AC-6 evidence — fresh load, no prior install present):

```
WARNING: The <CSPApplication></CSPApplication> resource tag is deprecated and may be removed in a future release of IPM.
         Please contact the package developer of iris-session-agent to use <WebApplication></WebApplication> instead
Building dependency graph...Done.
[%SYS|iris-session-agent]	Initialize START
[%SYS|iris-session-agent]	Initialize SUCCESS
[%SYS|iris-session-agent]	Reload START (C:\git\iris-session-agent\)
[%SYS|iris-session-agent]	Reload SUCCESS
[iris-session-agent]	Module object refreshed.
[%SYS|iris-session-agent]	Validate START
[%SYS|iris-session-agent]	Validate SUCCESS
[%SYS|iris-session-agent]	Compile START
[%SYS|iris-session-agent]	Compile SUCCESS
[%SYS|iris-session-agent]	Activate START
[%SYS|iris-session-agent]	Configure START
[%SYS|iris-session-agent]	Configure SUCCESS
[%SYS|iris-session-agent]	Activate SUCCESS
```

The verbose-mode run additionally shows: `Loading file C:\git\iris-session-agent\src\SessionAgent\Placeholder.cls as udl` ... `Compiling class SessionAgent.Placeholder` ... `Compilation finished successfully in 0.004s.`

The single WARNING is a tag-deprecation notice (the `<CSPApplication>` resource tag has been superseded by `<WebApplication>` in newer IPM versions); it is NOT a `module.xml` parsing warning. The verbatim shape from research lines 957–993 uses `<CSPApplication>`, so this warning was unavoidable without deviating from AC-1.

#### Two adaptations from the story's Tasks (both motivated by IPM's directory-walk behavior; AC spirit preserved):

1. **`src/SessionAgent/Placeholder.cls` instead of `src/SessionAgent/.gitkeep`.** IPM's `Default.Package` resource processor inherits its Reload phase from `Default.Document.OnPhase`, which calls `$system.OBJ.ImportDir(packageDir, "*"_..FilenameExtension, ...)`. With the verbatim `<Resource Name="SessionAgent.PKG"/>` (no FilenameExtension override), the wildcard becomes `*` and ImportDir errors on `.gitkeep` as "Unknown file type" — failing AC-6. Solutions considered: (a) add `FilenameExtension="cls"` to the Resource (deviates from AC-1's verbatim shape — rejected per the user lead's "use module.xml exactly" directive); (b) place a stub class in the package — chosen. `SessionAgent.Placeholder` is `[Hidden]`, contains no methods or properties, and a class-level doc comment naming Story 1.3 as the stub-removal trigger when `SessionAgent.Audit.Emit` ships as the first real class. AC-5's wording ("Each contains either content (when later stories add it) or a `.gitkeep` file") explicitly accepts "content" as an alternative. Net: AC-1 verbatim preserved, AC-5 satisfied via the "content" branch, AC-6 passes.

2. **`static/` at the repo root (not `src/static/`) is what `<FileCopy>` actually copies from.** The verbatim `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>` (research line 974) resolves the source via `%IPM.ResourceProcessor.FileCopy.GetSource()` as `Module.Root _ Name` — i.e., `c:/git/iris-session-agent/static/`, NOT `c:/git/iris-session-agent/src/static/`. The architecture diagram (architecture.md line 901) places `static/` under `src/`, but that placement is inconsistent with how IPM's `<FileCopy Name>` actually resolves. To satisfy AC-6 without modifying the verbatim module.xml, I created `static/` at the module root with a `.gitkeep` placeholder; `src/static/.gitkeep` was kept per the architecture-diagram-AC-7 requirement. **For Story 10.7** (vendored Markdown bundle — `marked.min.js`, Prism, DOMPurify), the vendored files should land in `static/` at module root (where `<FileCopy>` looks), not in `src/static/`. Recommend the architect update the diagram to match IPM's actual resolution, or add an explicit `<SourceDirectory>src/static/</SourceDirectory>` attribute to the `<FileCopy>` if the `src/static/` placement is preferred — both options to be settled before Story 10.7 begins. Documented this discrepancy in the FileList notes for the lead's awareness.

#### Other observations (informational, no AC impact):

- The `<CSPApplication>` element creates a Web Application but its `Path="${cspdir}static/iris-session-agent"` attribute is not expanded by robocopy when IPM evaluates the `Path` for the CSPApplication's filesystem-attribute (Activate phase verbose log shows `Path: C:\git\iris-session-agent\.${CSPDIR}STATIC\IRIS-SESSION-AGENT\` — the `${CSPDIR}` token is taken literally). This creates a stray directory `.${CSPDIR}STATIC/` at the repo root on every install. The actual file copy (separate from the CSPApp Path setting) goes to the correct `c:\InterSystems\IRISHealth\CSP\static\iris-session-agent\` location. Added `.${CSPDIR}STATIC/` to `.gitignore` so it can never accidentally be committed. The CSPApplication itself is created and its `AuthenticationMethods=64` (unauthenticated) flag is set correctly. This is an IPM 0.10.6 (the bootstrapped version) limitation, not a Story 1.1 defect.
- The IRIS instance available locally is **2025.1**, which is one minor revision above the **2024.1 floor** (per `project_iris_version_floor.md`). The IPM features used here (`<Resource>`, `<FileCopy>`, `<CSPApplication>`, `<Invoke>` (commented), `${cspdir}` expansion) all exist in IPM-on-2024.1 per IPM's compatibility matrix; explicit verification on a 2024.1 build is deferred to Epic 1 Story 1.7's CI scaffolding.

#### Sprint-status update:

- `1-1-project-initialization` flipped from `ready-for-dev` → `in-progress` at the start of the run; will flip to `review` at completion.

### File List

#### Created
- `c:\git\iris-session-agent\module.xml` — verbatim 33-line shape from research §"IPM module.xml — Concrete v1 Shape" (lines 957–993), with the three `<Invoke>` lines commented out (Story 1.5 will uncomment them).
- `c:\git\iris-session-agent\LICENSE` — standard MIT License text with `Copyright (c) 2026 Joshua Brandt`.
- `c:\git\iris-session-agent\src\SessionAgent\Placeholder.cls` — `[Hidden]` no-op class so the empty package directory tracks in git AND IPM's Default.Package directory walker succeeds. Removed in Story 1.3 when `SessionAgent.Audit.Emit` ships.
- `c:\git\iris-session-agent\src\static\.gitkeep` — tracks the architecture-diagram `src/static/` directory in git. Note: not used by IPM (see Completion Note #2).
- `c:\git\iris-session-agent\static\.gitkeep` — tracks the module-root `static/` directory in git; this is the directory `<FileCopy Name="static/">` actually copies from. Story 10.7 vendored assets (`marked.min.js`, Prism, DOMPurify, `chat-panel.js`, `sessionagent-chat.css`) land here.

#### Modified
- `c:\git\iris-session-agent\.gitignore` — preserves the existing two lines (`irislib/`, `sources/`) and adds standard IRIS / VSCode (with shared-config exclusions) / IDE / OS patterns per AC-4. Also includes `.${CSPDIR}STATIC/` to swallow the IPM 0.10.6 robocopy quirk noted above.
- `c:\git\iris-session-agent\README.md` — relocated the existing `## Operator Prerequisites` section so it is the **first H2 heading after the project introduction** (per AC-3 / Story 1.2 wording). The pre-existing section content (placeholder copy + 3-step list) was preserved verbatim during the move; no new prose was added beyond positioning. All other README content (under-construction banner, "What it does", "Status", "Development Plan", "Planning Artifacts", "Project posture", "Contributing") is unchanged.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\sprint-status.yaml` — `1-1-project-initialization` flipped `ready-for-dev` → `in-progress` (Step 4) → will flip to `review` (Step 9). `last_updated` comment updated.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\1-1-project-initialization.md` — story file `Status` field, all Tasks/Subtasks checkboxes, Dev Agent Record sub-sections (Agent Model Used, Debug Log References, Completion Notes List, File List, Change Log).

#### Deleted
- *(none)*

### Change Log

- 2026-05-02 — Story 1.1 implementation complete. Created `module.xml` (verbatim 33-line shape with `<Invoke>` block commented for Story 1.5 to uncomment), `LICENSE` (MIT, `Joshua Brandt`), `src/SessionAgent/Placeholder.cls` (stub for IPM directory-walk compatibility), `src/static/.gitkeep`, `static/.gitkeep` (module-root, for `<FileCopy>` source). Modified `README.md` (moved `## Operator Prerequisites` to first-H2-after-intro position, content preserved) and `.gitignore` (added IRIS / VSCode / IDE / OS sections + `.${CSPDIR}STATIC/` swallow pattern). Verified `zpm "load c:/git/iris-session-agent"` against locally-running IRIS for Health 2025.1 (IPM 0.10.6 bootstrapped from `pm.community.intersystems.com`); all 6 lifecycle phases SUCCESS. NFR-C2 grep for `Language = python` under `src/SessionAgent/` returned 0 matches. Story status `in-progress` → `review`.
- 2026-05-02 — Code review complete (reviewer: Claude Opus 4.7 1M, separate context). All 7 ACs pass. Both adaptations triaged as IN-SPEC: (1) `Placeholder.cls` is the architecturally clean choice — AC-5 explicitly accepts "either content or .gitkeep", and AC-1's verbatim shape forbids adding `FilenameExtension="cls"` to the `<Resource>` (the alternative IPM-conventional fix); (2) creating both `static/` (module-root, for verbatim `<FileCopy>` source) AND `src/static/` (for architecture-diagram tree match) is the only way to satisfy AC-1 and AC-7 simultaneously without modifying spec docs. The doc-vs-IPM-resolution inconsistency between architecture diagram line 901 and research line 974 is logged to `deferred-work.md` for architect resolution before Story 10.7 (which ships actual content into `static/`). 0 HIGH, 0 MEDIUM findings; 1 LOW deferred. Story status remains `review` → ready for sprint lead's commit step.

### Review Findings

- [x] [Review][Defer] `static/` directory location — architecture diagram (line 901) shows `src/static/` but verbatim `<FileCopy Name="static/">` from research line 974 resolves to module-root `static/` per IPM source — architect must reconcile before Story 10.7 ships content into `static/`. [architecture.md:901, module.xml:15] — deferred, doc inconsistency not introduced by this story; Story 1.1 mitigated by creating BOTH directories so AC-1 + AC-7 both pass. Logged to `deferred-work.md`.
