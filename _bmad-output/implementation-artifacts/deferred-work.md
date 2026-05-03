# Deferred Work

This file accumulates findings, follow-ups, and architect-decision items that are flagged during code review but are not in-scope for the current story to fix. Each entry records the source story, the date deferred, and the rationale.

---

## Deferred from: code review of story-1.1-project-initialization (2026-05-02)

- **`static/` directory placement: architecture diagram vs. IPM `<FileCopy>` resolution semantics — architect decision required before Story 10.7.**

  - **Source:** Story 1.1 code review (this file's first deferred item).
  - **Severity:** LOW (no impact on Story 1.1 — both directories exist; both ACs pass).
  - **The discrepancy:** AC-1 mandates the verbatim `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>` from research §"IPM module.xml — Concrete v1 Shape" line 974. Per IPM source (`%IPM.ResourceProcessor.FileCopy.GetSource()` resolves `Module.Root + Name`), the `Name="static/"` attribute resolves to `c:/git/iris-session-agent/static/` — at the module root, NOT under `<SourcesRoot>src/</SourcesRoot>`. However, the canonical project tree in [architecture.md §"Project Directory Structure" line 901](../planning-artifacts/architecture.md) shows `static/` nested under `src/` (i.e., `src/static/marked.min.js`, `src/static/chat-panel.js`, etc.). The two are structurally inconsistent — IPM will look for vendored static assets at module-root `static/`, not at `src/static/` where the architecture diagram places them.
  - **Story 1.1 mitigation:** Both `static/` (module root) and `src/static/` directories created with `.gitkeep` placeholders so AC-1's verbatim shape AND AC-7's architecture-diagram-tree-match both pass.
  - **Why this must be resolved before Story 10.7:** Story 10.7 ships the vendored Markdown bundle (marked.min.js, prism.min.js, prism-objectscript.js, prism-sql.js, prism-javascript.js, prism-json.js, prism-hl7.js, prism-xml.js, prism.min.css, dompurify.min.js, chat-panel.js, sessionagent-chat.css). These files MUST land in the directory IPM's `<FileCopy>` actually copies from. If Story 10.7 follows the architecture diagram and places them under `src/static/`, IPM will not find them and the CSP-served bundle will be empty — breaking the Growth-tier UI render path silently.
  - **Two clean resolutions for the architect to choose between:**
    1. **Update the architecture diagram** (architecture.md line 901 area) to move `static/` from under `src/` to repo root, matching where IPM's `<FileCopy Name="static/">` actually resolves. Delete `src/static/.gitkeep` from the repo as a follow-up cleanup. This is the lower-friction option — IPM source is authoritative, the diagram is a doc bug.
    2. **Update `module.xml`** to add `<SourceDirectory>src/static/</SourceDirectory>` (or use `Name="src/static/"`) so the FileCopy actually resolves to `src/static/` matching the diagram. Delete the module-root `static/.gitkeep` from the repo as a follow-up. This deviates from AC-1's verbatim research-line-974 shape.
  - **Recommendation:** Option 1 — the IPM source is the authoritative truth about where `<FileCopy Name="static/">` resolves; the diagram is the doc bug; AC-1's verbatim shape stays intact. Option 2 deviates from the canonical IPM-on-2024.1 module.xml shape that the research source spent effort to verify.
  - **Owner:** Architect (Winston) — to resolve in a one-line architecture.md edit + a follow-up story (or as a tag-along scope item in Story 10.7's spec).
  - **Blocking?** Not blocking Story 1.2 through 10.6. Blocks Story 10.7 if not resolved before that story enters dev.

---

## Deferred from: code review of story-1.2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites (2026-05-02)

- **Story-spec internal contradiction: AC-2 ("exactly three concrete steps") vs. Task 1 ("seven sub-steps per the research doc shape") — story-template guidance for future Task-0 stories.**

  - **Source:** Story 1.2 code review (this file's second deferred item).
  - **Severity:** LOW (no impact on Story 1.2 itself — the contradiction was caught and resolved in code review by swapping README §3 ↔ §5 to satisfy AC-2's blocking-step relative ordering while keeping Task 1's 7-step canonical structure).
  - **The contradiction:** AC-2 reads *"the section enumerates exactly three concrete steps in this order: 1. Web Gateway timeout, 2. RBAC, 3. API key."* Task 1 reads *"use the full content per [research §"Operator README Content"] … keep `## Operator Prerequisites` as the H2; use `### 1.` through `### 7.` H3s for the seven sub-steps per the research doc shape."* The research doc's canonical 7-step shape places API key at §3 and RBAC at §5 (timeout → API key → … → RBAC), which conflicts with AC-2's mandated ordering (timeout → RBAC → API key). A literal reading of both at the same time is impossible.
  - **How it played out:** Dev followed Task 1 literally → README came out with blocking trio in canonical-research-doc order (timeout § 2 → API key § 3 → RBAC § 5) → code reviewer caught the AC-2 violation and swapped § 3 ↔ § 5 to land timeout → RBAC → API key. Both AC-2 and Task 1 are now satisfied (Task 1's "seven sub-steps" structure is preserved; only blocking-step relative ordering was adjusted).
  - **Why this is worth recording:** Story 1.2 is the **first Task-0 probe story in the project**, and the story template here is the prototype every future Task-0 story will copy. If the AC vs. Task drift is left uncorrected in the template, future stories will inherit the same trap — dev will follow Task 1 literally, code review will catch the AC violation, and review-time rework becomes the norm. Cheap fix at the planning layer; expensive if it recurs across Epics 2, 7, 9, 10 (each has at least one Task-0 probe per architect's roadmap).
  - **Recommendation for the next story-template revision (PM/SM, applies to Stories 2.10, 7.1, 9.1 and any other future Task-0 stories):** When AC enumerates "the install-blocking" steps and Task 1 expands them within a wider canonical structure, AC should say *"the **blocking** steps appear in this **relative** order — non-blocking sections may be interspersed per the canonical structure cited in Task 1"*, OR Task 1 should say *"adapt the canonical structure to put blocking steps in the AC-mandated order; deviate from the research doc's section numbering as needed."* Either phrasing eliminates the trap.
  - **Owner:** PM (John) or SM, on the next story-template revision pass — single one-paragraph clarification in the BMAD `bmad-create-story` workflow's AC-vs-Task guidance.
  - **Blocking?** Not blocking. Cosmetic/process improvement item.
