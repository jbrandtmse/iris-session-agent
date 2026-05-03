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

---

## Deferred from: code review of story-1.3-audit-event-pre-registration (2026-05-02)

- **`ToolCall` audit event registration deferred to Epic 2 lazy-on-first-use — confirm Story 2.10 picks this up or extend Story 1.3 retroactively.**

  - **Source:** Story 1.3 code review.
  - **Severity:** LOW (acceptable design choice for Story 1.3 scope; no operator-observable impact until Story 2.10 ships the tool registry).
  - **The deferral:** `EnsureEvents()` registers 11 triples (4 LlmCall + 4 VocabWrite + 3 TaskRun) but registers ZERO `ToolCall` triples at install time. The architecture (architecture.md line 822 onward) already enumerates 13 inspection tool names (`session_summary`, `session_timeline`, `message_headers`, `event_log`, `rule_log`, `find_related_sessions`, `find_sessions_by_body`, `get_message_body`, `get_message_detail`, `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods`, `explain_error`) plus 8+ Search tools (line 836+) — so technically all known tool names COULD have been registered now.
  - **Why deferring is acceptable:** (a) Story 2.10 explicitly owns the tool-registry boundary; (b) the architecture text says ToolCall emissions originate at `SessionAgent.Tool.Registry.Dispatch` "(Story 2.10 onward)"; (c) Search tools (Epic 8) and any growth-tier additions (Epic 10) would also need registration entries — a centralized lazy-register-on-dispatch helper inside Story 2.10's tool registry is cleaner than splitting registration between EnsureEvents() (for the inspection 13) and the registry path (for everything else).
  - **What needs to happen in Story 2.10:** add a `RegisterIfMissing(source, type, name)` helper to `SessionAgent.Audit.Emit` (or to the tool registry itself), and call it from the registry's `Dispatch` boundary on first emit per tool. Alternative: extend `EnsureEvents()` with the then-known tool name universe at the time Story 2.10 ships, AND add the lazy helper for any tools added later.
  - **Owner:** Dev (when implementing Story 2.10 — `2-10-tool-base-abstract-tool-registry-task-0-probe`).
  - **Blocking?** Not blocking Stories 1.4–1.7 or any of Epic 2 prior to Story 2.10. Becomes blocking on Story 2.10 entering dev — that story MUST address ToolCall registration as part of its own scope.

- **Inline-comment clarity around the argumentless `Quit` inside the While loop in `Emit.cls` line 72.**

  - **Source:** Story 1.3 code review.
  - **Severity:** LOW (cosmetic — code is correct as written; reviewer preference only).
  - **The observation:** The argumentless `Quit` at line 72 breaks out of the While loop (per ObjectScript semantics: `Quit` inside a While exits the loop, not the enclosing block). Control then falls through to line 77 (`Set $NAMESPACE = tOrigNS`) and the try block closes naturally. Status is correctly carried in `tSC` and returned by the outer `Quit tSC` at line 83. The existing inline comment "argumentless quit out of While; try/catch closes below" is accurate but a future maintainer who hasn't internalized that "Quit-inside-While exits the loop only" might benefit from one extra word, e.g., "argumentless quit exits While loop only; namespace restore on line 77 still runs before try/catch closes."
  - **Recommendation:** No change required. If a future story touches `Emit.cls` for unrelated reasons, optionally tighten the inline comment then. Not worth a dedicated edit.
  - **Owner:** None (no action required).
  - **Blocking?** Not blocking anything.

---

## Deferred from: code review of story-1.4-read-only-rbac-role-install (2026-05-02)

- **Historical-doc references to `%SessionAgent_ReadOnly` (with leading `%`) preserved as authoring history.**

  - **Source:** Story 1.4 code review.
  - **Severity:** LOW (no operator-observable impact; the live IRIS role is `SessionAgent_ReadOnly` with no leading `%`, and all operator-facing + agent-authoring-facing artifacts have been updated to match).
  - **The cross-cutting finding:** Story 1.4 Task 0 probe revealed that IRIS rejects user-created RBAC role names beginning with `%` (error #887 "Invalid role name" — the `%` prefix is reserved exclusively for IRIS-shipped pre-defined system roles per the `Security.Roles.Create` validator). The locked role name was changed from `%SessionAgent_ReadOnly` (per the original project memory + research docs) to `SessionAgent_ReadOnly`. See `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt` §"Naming-decision note" for verbatim probe transcript.
  - **What was updated in this commit (HIGH/MEDIUM auto-resolved):**
    - `README.md` — operator-facing prereqs, design properties, Epic 1 description.
    - `_bmad-output/planning-artifacts/architecture.md` — multiple references (lines 28, 91, 112, 253, 862, 980, 1072) — agent-authoring-facing spec.
    - `_bmad-output/planning-artifacts/prd.md` — multiple references — agent-authoring-facing spec.
    - `_bmad-output/planning-artifacts/epics.md` — Story 1.4 spec text + FR/NFR/AR cross-references — agent-authoring-facing.
    - `_bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md` — LLM-distillate (agent-authoring-facing).
    - `_bmad-output/planning-artifacts/implementation-readiness-report-2026-05-02.md` — FR50 coverage row.
    - `C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/project_package_naming.md` — the locked-naming memory; updated with the probe rationale appended so future BMAD runs see both the corrected name AND the historical "why".
  - **What was deliberately preserved as historical (this deferral):**
    - `_bmad-output/implementation-artifacts/1-1-project-initialization.md` — Story 1.1 spec, historical authoring record predating the rename.
    - `_bmad-output/implementation-artifacts/1-2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites.md` — Story 1.2 spec, historical authoring record predating the rename.
    - `_bmad-output/implementation-artifacts/1-4-read-only-rbac-role-install.md` — Story 1.4's OWN AC/Task wording. The dev's adaptation is captured verbatim in §"Task 0 Output" (Naming-decision note), §"Completion Notes List" (NEW finding paragraph), and §"Change Log". The original AC/Task text is preserved as the authoring trace.
    - `_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md` and `…-message-search-agent-no-ai-hub-research-2026-05-02.md` — research input documents that informed the architecture; preserved as frozen historical inputs per the existing `project_package_naming.md` precedent for AI-Hub research docs ("historical and should NOT be retroactively renamed — they document a frozen previous design"). The same logic applies: the research docs reflect the architect's pre-probe assumption.
    - `src/SessionAgent/Security/ReadOnlyRole.cls` lines 31, 38 + the probe transcript file — explanatory doc-comments that quote the rejected name as the **rationale** for the rename. Removing them would erase the "why" future readers need to understand the name choice. **Intentionally retained.**
  - **Why deferring the historical refs is correct:** authoring history of dev/story decisions is the audit trail for *why* the project converged on the current spec. Retroactively rewriting Story 1.1 and Story 1.2's authoring text would erase the trace that the rename was discovered in Story 1.4 Task 0, not pre-known at planning. The pattern matches the existing precedent in `project_package_naming.md` for the AI-Hub-coupled research docs ("historical and should NOT be retroactively renamed — they document a frozen previous design").
  - **Live-IRIS confirmation (2026-05-02 code review):** `Security.Roles.Exists("SessionAgent_ReadOnly")` returns 1; `Security.Roles.Exists("%SessionAgent_ReadOnly")` returns 0. The live role is correct.
  - **Owner:** None — historical preservation is the resolution. Future stories that re-cite `%SessionAgent_ReadOnly` should be flagged in code review as a stale reference.
  - **Blocking?** Not blocking. Story 1.5 (the natural carrier for installer-orchestrator wiring) inherits the corrected name from the updated planning artifacts.

---

## Resolved during Story 1.5 verification (2026-05-02) — superseded by README §"Operator Prerequisites" §1

- **`zpm` was installed in `%SYS` but not mapped into HSCUSTOM. Required `zpm "enable -map -globally"`.**
  - **First-attempt symptom:** `zpm "load c:/git/iris-session-agent"` errored with `<CLASS DOES NOT EXIST>DisplayError *%IPM.Repo.UniversalSettings`. The class actually exists and is fully compiled in `%SYS` (verified empirically via `%Dictionary.ClassDefinition.%ExistsId` returning 1 and `##class(%IPM.Repo.UniversalSettings).%New()` succeeding). The error appeared because the IPM lifecycle's Configure phase context-switches into the install target namespace (HSCUSTOM), where `%IPM.*` classes had no mapping.
  - **Resolution (single command from `%SYS`):** `zpm "enable -map -globally"` — maps the `%IPM` package and `%IPM.*` routines from `%SYS` into HSCUSTOM, HSSYS, HSSYSLOCALTEMP, IRISCOUCH, USER. After the mapping, `zpm load` from HSCUSTOM succeeded end-to-end across all six IPM lifecycle phases on first install AND on idempotent reinstall.
  - **Architecture confirmation (Perplexity research, training-knowledge basis):** IPM follows install-once-in-`%SYS` plus map-across-namespaces. The bundled HealthShare 0.9.0+snapshot in HSLIB/HSSYS is read-only DeveloperMode and exists only for HealthShare's own internal package management; not relevant to user-namespace mapping.
  - **Operator-observable state propagated:** README §"Operator Prerequisites" §1 now documents the install-IPM-and-enable-globally sequence as a one-time setup step. Story 1.5's commit carries this README change (per `research-first.md` rule 5: operator-observable state must ride the commit). No follow-up work needed; Story 1.7 (CI scaffolding) inherits the documented prerequisite as a normal CI environment-setup step.
