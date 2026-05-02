**Technology Scope: All technologies.** This research-first principle applies to both ObjectScript backend and Angular/TypeScript frontend work.

## Brief overview
- Adopt a "Research First" workflow: when not 100% certain about a technical point, research with Perplexity MCP before deciding or coding.
- For ObjectScript: emphasis on InterSystems IRIS topics (syntax, best practices, IRIS features, Ensemble/Interoperability, SQL, globals, vector search, embedded Python).
- For Angular/TypeScript: emphasis on Angular 19 patterns, CDK, RxJS, modern CSS, accessibility (WCAG).
- Keep research focused, cite authoritative sources, and convert findings into precise implementation steps.

## When to research
- Any uncertainty about IRIS/Ensemble method signatures, adapters, or configuration.
- ObjectScript syntax and semantics (e.g., $$$ macro usage, QUIT behavior in try/catch, abstract method requirements).
- IRIS SQL, globals, or vector embedding datatypes/operations behavior.
- Conflicting memories, ambiguous forum answers, or gaps in best practices.

## How to use Perplexity MCP effectively
- Use the integrated Perplexity MCP tools with specific, context-rich prompts:
  - Prefer: `search` for broad discovery, `get_documentation` for targeted docs, `check_deprecated_code` to validate deprecations or outdated patterns.
- Include context in queries (e.g., "ObjectScript", "InterSystems IRIS", feature name, known error code).
- Example queries:
  - "ObjectScript abstract method compile requirements curly braces return value"
  - "IRIS vector search error -259 datatype mismatch %Library.Embedding vs %Vector"
  - "Ens.BusinessOperation OnMessage method signature and request/response types"
  - "Embedded Python in IRIS: correct way to import and check Python availability"
- Iterate with follow-up questions if initial results conflict or lack clarity.

## Sources and citation
- Prioritize: InterSystems official docs (docs.intersystems.com), InterSystems Community posts, official GitHub/org publications, and highly reputable sources.
- Provide 2–4 authoritative links with a one-line rationale per link.
- Quote short key lines only when they directly impact implementation decisions.

## From research to action
- Summarize decisions as bullets before coding (what to change and why).
- Map each decision to a concrete step (e.g., "Use $$$ macros, not $$" -> "Update all macros in ClassX.cls").
- For IRIS/ObjectScript changes, validate by compiling with the IRIS MCP compile tools after applying updates.

## IRIS/ObjectScript emphasis
- Confirm Ensemble/Interoperability signatures, adapters, and sync/async patterns via research prior to implementing.
- After research, verify uncertain SQL/globals/vector behavior with small, isolated tests using IRIS MCP tools.
- Prefer native ObjectScript patterns for IRIS operations; reserve embedded Python for external library integrations (after researching correct bridge usage).

### Task 0 backend-surface probe (Epic 12+ story creation)

Added by Story 12.0 (2026-04-17) to codify the Epic 11 retrospective Action
Item #1. Applies to every **Epic 12 and later** story whose acceptance
criteria reference a new or modified backend endpoint (or a new subprocess /
bridge surface). Non-binding for Angular-UI-only stories that only consume
already-shipped endpoints.

Every such story **must** include a **Task 0** item in Tasks/Subtasks that
captures:

1. **A live `curl` probe against the proposed endpoint**, e.g.
   `curl -u _system:SYS -i http://localhost:52773/iris-couch/_session`.
   Run it before writing any code. If the endpoint does not exist yet, probe
   the *closest existing* endpoint (same handler family) so the story has a
   concrete before-state to diff against.
2. **Verbatim expected output pasted into the story Tasks** — status code
   plus body (truncated to ~20 lines if large). This locks the wire shape
   before the dev starts writing code and makes the AC auditable at review
   time.
3. **A concrete reference read cited in the story Dev Notes.** For Epic 12
   specifically:
   - Stories consuming `%SYS.Python` must cite a page from
     `documentation/IRIS_Embedded_Python_Complete_Manual.md` (bridge usage,
     object lifetime, GIL considerations).
   - Stories using `$ZF(-1)` subprocess APIs must cite the couchjs line
     protocol in `sources/couchdb/share/server/` (stdin/stdout framing,
     error handling, shutdown signaling) or the InterSystems `$ZF(-1)` doc.
   - Stories touching any other backend surface must cite either the
     CouchDB 3.x source under `sources/couchdb/` or an InterSystems doc
     page, not just a Perplexity search summary.
4. **Pre-flight dev-environment capability check (added 2026-04-18, Story
   13.0 from Epic 12 retro AI #1).** When a story's core capability depends
   on a runtime primitive that the current dev host may or may not provide
   (embedded Python via `%SYS.Python.Import`, an `irispip`-installed Python
   package, a subprocess toolchain like Node/Deno via `$ZF(-100)`, a
   specific filesystem path, or an external CLI), the Task 0 output **must**
   include the verbatim terminal output of a probe that exercises that
   primitive on the current dev host **before** the AC block is authored.
   If the probe fails or the primitive is unavailable, the story creator
   **must** escalate to the user for a defer/drop decision **before**
   writing 300+ lines of spec. The cited failure mode: Story 12.4 (Python
   JSRuntime backend) was specced, context-filled, and the dev agent was
   dispatched before anyone verified that `%SYS.Python.Import("sys")`
   succeeded on the dev host — it did not, and the entire story was
   deferred. The probe forms:
   - **Embedded Python:** `iris session IRIS -U <ns> "##class(%SYS.Python).Import(\"sys\")"` — or the MCP equivalent `iris_execute_command`. A failure looks like `ERROR: <OBJECT DISPATCH> ... Failed to Load Python ... Check CPF parameters:[PythonRuntimeLibrary,PythonRuntimeLibraryVersion]`.
   - **`$ZF(-100)` subprocess:** `Set tSC = $ZF(-100, "/SHELL", "cmd", "/c", "echo hello")` then `zw tSC` — success is `tSC=0`.
   - **External CLI / `irispip`:** probe the exact invocation the story would use (`irispip install --target <dir> <pkg>` dry-run, `node --version`, etc.) and capture the exit status.
   - **HTTP endpoint:** the `curl` probe from item 1 already covers this
     case; the new item 4 only adds probes for non-HTTP primitives.

   The probe output belongs in the story's **Task 0** section alongside the
   `curl` output from item 1, not as a separate phase — a single Task 0 that
   captures every pre-flight check the story depends on.

5. **Operator-facing state must ride the commit (added 2026-04-18, Story
   13.0 from Epic 12 retro AI #2).** When a story is deferred, scope-cut,
   or ships a known operator-observable limitation, `README.md` **must** be
   updated **in the same commit** as the sprint-status flip or scope-cut
   commit, naming the deferred backend, the cut feature, or the new
   operator prerequisite. Internal refactors, test renames, and
   implementation-detail changes do **not** require README updates — this
   rule applies to operator-observable state only. The cited failure mode:
   Story 12.2's view-query-parameter scope cut (`group`, `group_level`,
   `startkey`, `endkey`, `limit`, `skip` all deferred to a future 12.2a)
   was documented in the story file, in `deferred-work.md`, and in the
   commit message — but **not** in the README. Operators reading the README
   had no way to see that those parameters were not yet supported; the gap
   was only caught when Josh surfaced it during the Epic 12 retrospective
   discussion. If in doubt about whether a change is operator-observable,
   update the README — false positives (an extra README paragraph) cost
   nothing; false negatives (silent scope cuts) erode operator trust.

This rule supersedes the ad-hoc "read the manual" prep tasks the Epic 11
retro dropped — the citation lives inside each story's Dev Notes where the
implementing developer will actually see it.

## Escalation if ambiguity remains
- If sources disagree, briefly summarize the conflict and propose the safest standards-compliant approach.
- If uncertainty persists after an initial research pass, ask one targeted clarifying question to unblock.

## Deliverable format for researched answers
- Provide:
  - A brief summary of findings (1–3 bullets)
  - A decision list (actionable bullets)
  - Source links (2–4) and any decisive short quotes
  - Any adjusted code snippet(s) reflecting the researched guidance
