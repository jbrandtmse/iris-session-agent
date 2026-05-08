# Sprint Change Proposal — 2026-05-08

**Triggered by:** Project-lead-driven walkthrough on 2026-05-08 (post-v1.0.1 tag). Eight bugs and three documentation enhancements were observed during real operator workflow on session-inspection + search-agent surfaces. All findings are captured with verified root causes in [`_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md`](../implementation-artifacts/walkthrough-bugs-2026-05-08.md).

**Mode:** Batch (full proposal + Epic 12 spec + 8-story breakdown in one document).

**Scope classification:** **Moderate** — opens a new epic (Epic 12), adds 8 new stories, expands `epics.md` with the full Epic 12 section, expands `sprint-status.yaml` with the new tracking entries. No PRD MVP exit-criteria language change; no architectural decisions overturned; no backwards-incompat surface changes.

---

## Section 1 — Issue Summary

The 2026-05-08 walkthrough exercised the v1.0.1 install across both agent surfaces (Search Agent on the new Message Viewer page; Inspection Agent on the customized VisualTrace page) using the sample interop production's failed-session data. Eight discrete defects emerged, plus three documentation gaps that materially affect first-run experience. Severity distribution:

| Count | Severity | Items |
|---|---|---|
| 3 | HIGH | BUG-04 (session-link nav goes to standard VisualTrace, not custom — operators lose access to the agent tab); BUG-05 (Search Agent results don't drive the MessageViewer table — operators can't paginate/sort the 20+ session results); BUG-07 (chat history tile replay strips tool-result blocks — Back-button navigation forces re-search) |
| 4 | MEDIUM | BUG-01 (chat panel CSS horizontal overflow); BUG-02 (provider HTTP exception text swallowed in mid-flight error); BUG-03 (`get_business_process_source` tool returns `class_not_found` when LLM appends method name); BUG-06 (`MaxIterationsPerTurn=10` is hardcoded and not operator-configurable; fallback message is unhelpful) |
| 1 | LOW | BUG-08 (Inspection Agent surfaces "no message body on errored response" as a finding; this is normal Ensemble behavior and should be in the prompt) |
| 3 | DOC | ENH-09 (README needs Quick Start + screenshots); ENH-10 (README needs end-to-end clean-namespace recipe); ENH-11 (README needs explicit launch URLs for Message Viewer + Search Agent) |

Each item in the bug report includes:
- The reproduction path observed during the walkthrough
- Expected vs actual behavior
- Root-cause investigation with verified file paths and line numbers
- Recommended fix shape

The walkthrough also confirms that the v1.0.1 patch release functionally works (regression sweep clean, both agents respond against rich production data, citation chips work, click-through navigation works in the FROM_SEARCH path). The findings are quality-of-life and edge-case gaps surfaced only by hands-on operator exercise — not regression evidence.

---

## Section 2 — Impact Analysis

### Epic Impact

| Epic | Current state | After this proposal |
|---|---|---|
| Epic 11 (v1.0.1 patch) | 4 stories, all `done`. Retrospective `optional` (not yet run). | No change to Epic 11 scope. The optional retrospective remains optional. The proposal does NOT block on running Epic 11's retro — the deferred-cleanup work is rolled into Story 12.0 instead, per Rule 7's "Step 2 — Retrospective Review & Story X.0" gate (which accepts "no retrospective found / skipped" as a valid input). |
| Epic 12 (NEW) | Does not exist. | 8 new stories, fixing 8 bugs + 3 documentation enhancements. Targets a v1.0.2 release (or unversioned dev iteration if no formal tag is desired). |

### Story Impact

8 new stories under Epic 12. Bundling logic explained per story:

| Story | Title | Bundles | Size |
|---|---|---|---|
| **12.0** | Epic 11 deferred cleanup + Epic 12 setup | Rule 7 gate; cleans up any Epic 11 deferred-work entries; wires Epic 12 sprint-status | Small (~120 lines spec) |
| **12.1** | UX polish — chat panel overflow + Inspection prompt Ensemble domain knowledge | BUG-01 + BUG-08 (both small, both UX polish, both touch agent surfaces in different files) | Small (~150 lines spec) |
| **12.2** | Agent reliability — provider error diagnostics + tool class-name fallback | BUG-02 + BUG-03 (both about graceful degradation when something goes wrong; BUG-02 spans 4 provider files, BUG-03 is a single tool helper) | Medium (~200 lines spec) |
| **12.3** | MessageViewer session-link override to custom VisualTrace | BUG-04 (small surgical override of inherited `showTrace` ClientMethod) | Small (~120 lines spec) |
| **12.4** | AgentLoop `MaxIterationsPerTurn` configurability + richer fallback message | BUG-06 (Config.Agent property + Zen form field + AgentLoop wiring + fallback prose change) | Medium (~200 lines spec) |
| **12.5** | Search Agent results drive MessageViewer table (filter integration) | BUG-05 (new ZenMethod `ApplyAgentSessionFilter`, new "Load into table" affordance in chat-panel.js, filter-mode override in CreateResultSet) | **Large** (~250 lines spec) |
| **12.6** | Chat history tile replay — preserve tool_use / tool_result blocks across page reload | BUG-07 (extend FlattenTurnsForBootstrap server-side + extend renderPriorTranscript client-side; mirror in both MessageViewer.cls and VisualTrace.cls) | **Large** (~250 lines spec) |
| **12.7** | README rewrite — Quick Start, screenshots, clean-namespace recipe, launch URLs | ENH-09 + ENH-10 + ENH-11 (all touch the same file; pair naturally; one bundled commit; screenshots captured from clean-namespace setup) | Medium (~180 lines spec) |

**Why this 8-story split (rather than 11 one-per-finding):**
- BUG-01 + BUG-08 bundle: both are small (CSS rules + 1-paragraph prompt addition). Forcing them into separate stories would add overhead without isolation benefit. They land in different files, so reviewers can still partition the diff.
- BUG-02 + BUG-03 bundle: both are about the agent failing more gracefully. BUG-02 retrofits all 4 providers with `postEx.DisplayString()` capture; BUG-03 adds a strip-last-segment retry to `get_business_process_source`. Architecturally adjacent — "graceful degradation hardening" is the unifying theme.
- ENH-09/10/11 bundle: all README; one commit makes sense; screenshots from ENH-09 can be captured during ENH-10's clean-namespace setup.
- Three HIGH-severity items (BUG-04, BUG-05, BUG-07) ship as standalone stories because each touches sufficiently different surface area to warrant isolation.

### Artifact Conflicts

| Artifact | Edit |
|---|---|
| `epics.md` | Append a new `## Epic 12` section. Add Epic 12 to the "Epic List" enumeration on line 340. Add 8 story sub-headers (Story 12.0 — Story 12.7). Estimated ~250 new lines. |
| `sprint-status.yaml` | Insert 10 new lines: `epic-12: backlog` + 8 story entries + `epic-12-retrospective: optional`. Inserted in numeric order after the existing Epic 11 block. |
| `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` | No edit. The bug report is the source-of-truth artifact for Story 12.0 → Story 12.7 specs to cite during drafting. |
| `_bmad-output/implementation-artifacts/deferred-work.md` | No edit at proposal time. Story 12.0 will scan during its triage phase per Rule 7 / Rule 9. |
| `prd.md` | No edit. None of the findings touch MVP exit criteria, FR/NFR statements, or scope language. BUG-05 (Search drives table) is a UX enhancement on top of an existing capability, not a new requirement. BUG-06 (max-iterations configurable) adds an operator dial without changing the contract. |
| `architecture.md` | No edit. Provider-error capture (BUG-02) follows the existing PopulateErrorEnvelope pattern. Tile replay (BUG-07) extends the existing canonical-Anthropic persistence shape. Search-drives-table integration (BUG-05) extends the existing CreateResultSet path. None require architectural decisions. |
| `ux-design-specification.md` | No edit. BUG-01 is a missed CSS rule (no UX-spec deviation); BUG-05 is a new operator interaction but the underlying tile rendering is already specced; BUG-08 is prompt copy. Story 12.5's UX choices (where the "Load into table" button appears in the result set) are local-detail choices that fit within the existing spec's chat-panel attribution shape. |
| `README.md` | One large edit at Story 12.7 time (~150 lines added/reorganized + 2–3 image files committed under `documentation/images/readme/`). |

### Technical Impact

- **No breaking changes.** All fixes are additive or override-shaped. v1.0.0 / v1.0.1 install paths continue to work unchanged.
- **No new external dependencies.** All work uses existing patterns (Zen Method overrides, %DynamicArray serialization, %Net.HttpRequest exception capture).
- **No CPU / memory regression risk.** The largest behavioral change (BUG-07 tile replay) increases the bootstrap JSON payload by the size of preserved tool blocks per turn — bounded by `Chat.History.TurnsJson` storage which is already capped per FR16 retention sweep.
- **Test surface growth:** Each story adds 3–8 unit tests + a per-class regression-sweep contribution. Total estimated ≈ 35–50 new test methods across Epic 12. SQL ground-truth probe (per `.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth") remains the verification gate at retro time.
- **Compile-time risk:** Three stories (12.3 session-link override, 12.5 ApplyAgentSessionFilter ZenMethod, 12.6 FlattenTurnsForBootstrap extension) modify Zen page classes — `MPP5646 / <PROTECT>` watchpoint applies per `.claude/rules/iris-objectscript-basics.md` §"Parameter PAGENAME MPP5646 Trap". Spec-time compliance check required.
- **JS surface growth:** `chat-panel.js` gains ~120 LOC (Story 12.5 "Load into table" button + Story 12.6 `renderToolBlocksFromHistory`). Already covered by the Story 10.7+ vendored-bundle pipeline; no new JS deps.

---

## Section 3 — Recommended Approach

**Direct adjustment** is the right path: open Epic 12, draft 8 stories, run them through the standard `/epic-cycle 12` pipeline. No rollback is needed (Epic 11 functionally works); no MVP-scope retreat is needed (every finding is a defect or polish item against an already-shipped surface).

**Rationale:**
1. **Walkthrough drove the scope** — the user's hands-on session is exactly the empirical battery Rule 6 expected; the findings are the "what walkthrough surfaces that automated tests don't" payoff.
2. **All findings have verified root causes** — no spec-time investigation drift; the dev agents inherit the bug report's analysis directly.
3. **No urgency mismatch** — three HIGH-severity items but none are correctness-of-shipped-data issues (no audit-log corruption, no data loss, no privilege escalation). All are operator-experience / workflow gaps. Standard `/epic-cycle` cadence is appropriate.
4. **Bundling logic preserves story isolation** — bundled pairs (BUG-01+BUG-08, BUG-02+BUG-03, ENH-09+10+11) all land in different files within each story, so reviewers can still partition.

**Effort estimate (relative):**
- 3 small stories (12.0, 12.1, 12.3): each lighter than typical Epic 10 stories.
- 2 medium stories (12.2, 12.4, 12.7): typical complexity, retrofit shapes, document-edit shapes.
- 2 large stories (12.5, 12.6): each comparable to Story 10.5 (concurrent-tab banner) or Story 10.7 (Markdown bundle) — multi-file, server+client co-design.

**Risk assessment:**
- LOW risk on small/medium stories. Established patterns; well-bounded blast radius.
- MEDIUM risk on Story 12.5 (Search drives table): introduces new operator interaction; needs UX choice on filter-mode badge wording, "Load into table" button placement, Reset semantics. Will benefit from a quick UX-DR addendum at spec time.
- MEDIUM risk on Story 12.6 (tile replay): touches both server-side flattener (verbatim copies in MessageViewer.cls AND VisualTrace.cls) and client-side renderer; partition risk if only one side ships. Spec must explicitly bind the dual-flattener fix as a single-PR atomic change.

**Recommended ordering** (bottom-up by risk, so retrospective-worthy lessons surface early):
- 12.0 (setup) → 12.1 (polish) → 12.3 (small navigation fix) → 12.2 (provider hardening) → 12.4 (agent loop config) → 12.6 (tile replay) → 12.5 (search drives table) → 12.7 (README + screenshots, last so screenshots show all fixes in place).

---

## Section 4 — Detailed Change Proposals

### Change 1: Add Epic 12 to `epics.md`

**File:** `_bmad-output/planning-artifacts/epics.md`

**Location:** Append after the existing Epic 10 section (line ~2700, end of file). Add Epic 12 to the "Epic List" enumeration (currently ends at Epic 10 on line 419 — add line for Epic 11 if the lead wants it backfilled, then Epic 12).

**New section:**

```markdown
### Epic 12: Walkthrough Hardening — Bug Fixes & UX Polish

**Goal:** Address the 8 bugs and 3 documentation enhancements surfaced by the
2026-05-08 project-lead walkthrough on the v1.0.1 install. Improves operator
experience on both agent surfaces (Search Agent on Message Viewer + Inspection
Agent on Visual Trace) without introducing new architectural decisions or
changing MVP exit criteria.

**Stories (in order):**
- 12.0 — Epic 11 deferred cleanup + Epic 12 setup
- 12.1 — UX polish: chat panel CSS overflow + Inspection prompt Ensemble
  domain knowledge (BUG-01 + BUG-08)
- 12.2 — Agent reliability: provider HTTP error diagnostics + tool
  class-name fallback (BUG-02 + BUG-03)
- 12.3 — MessageViewer session-link override to custom VisualTrace (BUG-04)
- 12.4 — AgentLoop MaxIterationsPerTurn configurability + richer fallback
  message (BUG-06)
- 12.5 — Search Agent results drive MessageViewer table (BUG-05)
- 12.6 — Chat history tile replay — preserve tool_use / tool_result blocks
  across page reload (BUG-07)
- 12.7 — README rewrite: Quick Start + screenshots + clean-namespace recipe
  + launch URLs (ENH-09 + ENH-10 + ENH-11)

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md`
captures all 11 findings with reproduction steps, verified root causes
(file paths + line numbers), and recommended fix shapes. Each Story 12.x
spec cites this artifact as the source-of-truth for ACs.

**Severity distribution:** 3 HIGH, 4 MEDIUM, 1 LOW, 3 doc-enhancement.

**Out of scope for Epic 12:**
- Cross-browser sweep (Firefox/Safari/Edge) — already deferred to a
  post-MVP cross-browser hardening epic.
- New tool additions or new agents — Epic 12 is hardening only.
- Vocabulary tier or learning-loop changes — Epic 9 territory.
```

Plus per-story sub-sections — full text drafted at story-creation time per Rule 1 (≤ 250 lines / spec).

---

### Change 2: Add Epic 12 entries to `sprint-status.yaml`

**File:** `_bmad-output/implementation-artifacts/sprint-status.yaml`

**Location:** After the existing Epic 11 block (line 161 `epic-11-retrospective: optional`).

**New entries:**

```yaml
  epic-12: backlog
  12-0-epic-11-deferred-cleanup: backlog
  12-1-ux-polish-chat-overflow-and-inspection-prompt: backlog
  12-2-agent-reliability-provider-error-and-tool-fallback: backlog
  12-3-messageviewer-session-link-override: backlog
  12-4-agentloop-max-iterations-configurable: backlog
  12-5-search-results-drive-messageviewer-table: backlog
  12-6-chat-history-tile-replay: backlog
  12-7-readme-rewrite-quickstart-screenshots-cleanns: backlog
  epic-12-retrospective: optional
```

---

### Change 3: Story specs (drafted at `/epic-cycle 12` time, not at proposal time)

Per the project's workflow, individual story specs are drafted by the lead during the `/epic-cycle` Step 4a (`/bmad-create-story` Skill invocation), NOT at sprint-change-proposal time. The proposal commits to the 8-story shape; story-spec drafting follows.

For each story, the spec template will include:
- AC enumeration with citation back to `walkthrough-bugs-2026-05-08.md` BUG-XX or ENH-XX entries
- Task 0 backend-surface probe per `.claude/rules/research-first.md`
- Tasks/Subtasks with explicit verification-evidence shapes (per Rule 2 sharpened — verbatim AC-contract evidence)
- Dev Notes: Ensemble domain knowledge cross-references where applicable; project-rule cross-references; minimal duplication of architecture content
- Patterns to follow verbatim section pointing at specific existing classes
- Spec length target ≤ 250 lines per Rule 1

---

### Change 4: No edits to `prd.md`, `architecture.md`, `ux-design-specification.md`

Confirmed: zero conflicts. Listed here for absence of doubt.

---

## Section 5 — Implementation Handoff

**Scope classification:** **Moderate** — backlog reorganization (new epic, 8 new tracking entries) but no fundamental replan. No PM/Architect involvement required. Ready for direct dev execution via the existing `/epic-cycle` pipeline.

**Recipients:**
- **Project Lead** — confirms approval, then invokes `/epic-cycle 12` (or defers per personal cadence) to drive the 8 stories through the standard pipeline.
- **Developer agents** (spawned per `/epic-cycle 12` Step 4 — one per story) — implement against the drafted specs.
- **Code-Review agents** (spawned per `/epic-cycle 12` Step 4c — one per story) — review against `.claude/rules/*.md`.

**Deliverables produced by this proposal:**
- This document (`sprint-change-proposal-2026-05-08.md`).
- Approval signal from project lead (next message).
- On approval: `epics.md` + `sprint-status.yaml` edits land in a single commit (the proposal commit). Epic 12 is then `backlog` and ready for `/epic-cycle 12`.

**Success criteria for Epic 12:**
- All 8 stories ship `done`.
- Empirical battery (Rule 6) at retro time exercises each fix end-to-end against real walkthrough scenarios from 2026-05-08.
- The 11 findings in `walkthrough-bugs-2026-05-08.md` are each addressed (with citation in the Story X.x Completion Notes that fixed them).
- README at v1.0.2-tag time has Quick Start, screenshots, clean-namespace recipe, and launch URLs (ENH-09/10/11 all surface in the rendered README).
- No regression on the v1.0.1 functionality (Story 11.1 / 11.2 / 11.3 / 11.4 still work; sample-prod walkthrough still produces clean turns).

**Pre-flight before invoking `/epic-cycle 12`:**
- Confirm sample interop production is running (per Rule 7 §"Sample production state at Epic-cycle Step 1").
- Confirm credential resolvability matrix (per Rule 7 §"Credential-resolvability matrix at Step 1") — at minimum `SessionAgentOpenAI` since both agents are now wired to that.
- Confirm no in-flight uncommitted work in the repo.

---

## Approval

**Project Lead:** please review and respond with one of:
- `yes` — I commit `epics.md` + `sprint-status.yaml` edits in a single commit, and Epic 12 is then ready for `/epic-cycle 12`.
- `revise` (with specifics) — I'll iterate this proposal.
- `no` — I'll close the proposal and re-open the conversation.
