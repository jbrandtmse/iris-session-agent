# Story 12.7: README Rewrite — Quick Start + Screenshots + Clean-Namespace Recipe + Launch URLs

**Status:** done

**Source:** `_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md` ENH-09 (Quick Start + agent-in-action screenshots) + ENH-10 (end-to-end clean-namespace recipe) + ENH-11 (explicit launch URLs for the new MessageViewer page). Bundled per Sprint Change Proposal §"8-story split" — all three touch the same file (README.md) and pair naturally with screenshots captured during the Epic 12 work. Documentation-only story; no source-code changes.

## User Story

As a **first-time visitor** evaluating whether to install iris-session-agent, I want the README to lead with what the agents actually do (not 100+ lines of operator prerequisites), with screenshots showing the agents in action against realistic test data, AND a clean-namespace recipe so I can try it without polluting my main HSCUSTOM. So that I can decide whether to install in 2 minutes instead of skipping the README out of frustration.

## Acceptance Criteria

**AC-1 — README has a top-of-document "Quick Start — using the agents" section.** [ENH-09]
- **Given** the current README starts with `# iris-session-agent` then jumps straight into `## v1.0.0 scope-complete summary` (line 14) and `## Operator Prerequisites` (line 26),
- **When** the rewrite lands,
- **Then** a new `## Quick start — using the agents` section appears between the title and the v1.0.0 scope summary, OR between the v1.0.0 scope summary and Operator Prerequisites. The section includes:
  - A 1–2 sentence pitch ("Two agents that read your Ensemble sessions and answer questions in plain English…").
  - 2–3 example operator prompts that work against the sample interop production (verbatim copy-paste-ready strings).
  - A pointer to the screenshot below (or inline image rendering).

> **Verbatim evidence:** Read the post-fix README. Confirm Quick Start section present with section heading, pitch sentence, and example prompts. Capture relevant headings via `grep -n "^##" README.md`.

**AC-2 — README contains 2 or 3 compelling screenshots.** [ENH-09]
- **Given** Stories 12.1, 12.4, 12.5, 12.6 produced multiple chrome-devtools-mcp screenshots demonstrating the agents at work,
- **When** the rewrite lands,
- **Then** at least 2 screenshots are committed under `documentation/images/readme/` (or similar canonical path) and embedded in README via relative-path Markdown image tags. Suggested: (a) Search Agent finding sessions across the namespace, (b) Inspection Agent investigating a specific session with tool calls visible.

> **Verbatim evidence:** Verify image files exist at the documented path. Verify README contains `![...](documentation/images/readme/...)` tags pointing to them. Run `ls documentation/images/readme/*.png` (or equivalent path) and capture verbatim.

**AC-3 — README has a "Try it in a clean namespace" section.** [ENH-10]
- **Given** the existing README has §"Multi-Namespace Install" (line 172) AND §"Sample interoperability production for testing" (line 242) as separate sections,
- **When** the rewrite lands,
- **Then** a new linear `## Try it in a clean namespace (recommended for evaluation)` section walks through end-to-end as ONE recipe: (1) create namespace, (2) map `SessionAgent.PKG`, (3) `InstallIntoNamespace`, (4) credentials, (5) AgentConfig form, (6) Bootstrap.InstallProduction, (7) RunScenario, (8) launch the agent UI in the new namespace, (9) tear-down recipe. Cross-references to existing detailed sections are acceptable for steps that don't need re-explanation.

> **Verbatim evidence:** Read the post-fix README §"Try it in a clean namespace" section verbatim. Confirm all 9 steps are present.

**AC-4 — README documents launch URLs for both agent screens.** [ENH-11]
- **Given** the custom `SessionAgent.EnsPortal.MessageViewer` page (Story 10.1) and `SessionAgent.EnsPortal.VisualTrace` page do not appear as new menu entries in the Mgmt Portal nav,
- **When** the rewrite lands,
- **Then** the README explicitly documents:
  - Direct URL: `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.MessageViewer.zen`.
  - Mgmt Portal breadcrumb path: `Interoperability → Message Viewer + Search Agent`.
  - Sister page (Inspection Agent on VisualTrace): `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>`.
  - A note that both URLs are bookmarkable.
  - Cross-reference to Story 12.3's BUG-04 fix (clicking session-ID badges in the table now opens the custom VisualTrace, not the standard one).

> **Verbatim evidence:** Read the post-fix README §"Launching the agents" (or equivalent subsection of §"Quick start"). Confirm all 4 URL/path entries present.

**AC-5 — Existing README sections still render correctly + no broken links.**
- **Given** the rewrite reorganizes sections,
- **When** the post-fix README is rendered (e.g., via GitHub or `pandoc`),
- **Then** all existing operator-prerequisite sections (IRIS versions, IPM, RBAC, package mapping, API keys, SSL/TLS, daily purge) are still present and reachable. Internal anchor links from one section to another still work.

> **Verbatim evidence:** Compare the section-heading list pre-fix vs post-fix via `grep -n "^##" README.md` — every pre-existing `## ` heading should still appear (modulo intentional reorganization). New headings added by Story 12.7 should be enumerated.

**AC-6 — Spec length verification** — `wc -l _bmad-output/implementation-artifacts/12-7-...` ≤ 250.

## Tasks / Subtasks

- [x] **Task 0 — Backend-surface probe**
  - [x] Read current `README.md` in full to map existing structure.
  - [x] Enumerate available screenshots from prior Epic 12 stories (`12-1-screenshot-no-horizontal-scrollbar.png`, `12-4-screenshot-agentconfig-maxiter-field.png`, `12-5-screenshot-load-button.png`, `12-5-screenshot-filter-badge.png`, `12-6-screenshot-tile-replay-{1,2,3}.png`). Pick 2–3 most compelling for the README.
  - [x] Confirm canonical image path. Suggest `documentation/images/readme/` to keep README assets distinct from the planning/implementation artifacts.
- [x] **Task 1 — Add `## Quick start — using the agents` section** [ENH-09]
  - [x] Position: between `# iris-session-agent` (line 1) and `## v1.0.0 scope-complete summary` (line 14). Justification: first-time readers should see what the agents do BEFORE the scope summary or operator prerequisites.
  - [x] Body: 1-2 sentence pitch, 2–3 example prompts, pointer to screenshots.
  - [x] Example prompts (operator-friendly):
    - `"Find sessions with errors in the last hour"` (Search Agent on the MessageViewer page).
    - `"Why did this session fail?"` (Inspection Agent on the VisualTrace page).
    - `"Show me the source of the OrderRouter business process"` (BP introspection — example of tool-call-driven Q&A).
- [x] **Task 2 — Add `### Launching the agents` subsection** [ENH-11]
  - [x] Position: inside §"Quick start — using the agents" as a sub-section.
  - [x] Document the 4 launch entry points per AC-4 (direct URL, breadcrumb, sister page, bookmarkable note).
  - [x] Cross-reference Story 12.3's session-ID-link fix.
- [x] **Task 3 — Capture/copy 2–3 screenshots into README path** [ENH-09]
  - [x] Create `documentation/images/readme/` directory (use `mkdir -p`).
  - [x] Copy chosen screenshots from `_bmad-output/implementation-artifacts/` into `documentation/images/readme/` with operator-friendly file names (e.g., `search-agent-finding-failed-sessions.png`, `inspection-agent-investigating-session.png`, `agent-config-form.png`).
  - [x] Embed via Markdown image tags in the Quick Start section: `![Search Agent finding failed sessions](documentation/images/readme/search-agent-finding-failed-sessions.png)`.
- [x] **Task 4 — Add `## Try it in a clean namespace (recommended for evaluation)` section** [ENH-10]
  - [x] Position: between the v1.0.0 scope summary and the existing §"Operator Prerequisites" header.
  - [x] Linear walkthrough per AC-3's 9 steps.
  - [x] Cross-references to detailed sections (RBAC, SSL, etc.) for the steps that already have detailed content elsewhere — keep this section concise (~40–60 lines).
- [x] **Task 5 — Verify no breakage on existing sections** [AC-5]
  - [x] `grep -n "^## " README.md` pre-fix — capture verbatim.
  - [x] Apply edits.
  - [x] `grep -n "^## " README.md` post-fix — capture verbatim.
  - [x] Diff: every pre-existing `## ` heading should appear in the post-fix list (modulo intentional renames).
  - [x] Manually scan internal anchor links (e.g., `[§ "6. LLM provider API keys"](#6-llm-provider-api-keys)`) — verify they still resolve.
- [x] **Task 6 — `node -c` parse check (Story 12.0 Carry-Forward)**
  - [x] This story does NOT modify `static/chat-panel.js`. Document "binding does not apply" in Completion Notes.
- [x] **Task 7 — Spec length verification** — `wc -l` ≤ 250.
- [x] **Task 8 — Sprint-status flip** — `12-7-...: ready-for-dev` → `in-progress` → `review` → `done`.
- [ ] **Task 9 — Commit + push** (lead) — `docs(epic-12): story 12.7 — README rewrite (Quick Start + screenshots + clean-namespace recipe + launch URLs)`.

## Dev Notes

### Why no code changes

This is a documentation-only story. No `.cls`, no `.js`, no `.css` modifications. The only "implementation" is README edits + image file additions.

### Why position Quick Start at the top

Per the bug report ENH-09 rationale: *"The agents are the value of the project. The current README's ratio of 'things to install' to 'things you can do' is heavily weighted toward installation. A reader who wants to evaluate whether to install will close the README before they hit the 'What it does' section on line 290."* Putting the Quick Start at the top (above the v1.0.0 summary or right after it) inverts that ratio.

### Screenshots — suggested choices from Epic 12 captures

- **`12-5-screenshot-load-button.png`** — shows Search Agent results with the new "Load 3 sessions into table" button. Demonstrates: chat panel + tile rendering + new button affordance.
- **`12-5-screenshot-filter-badge.png`** — shows the filter badge AND the table narrowed to agent's sessions. Demonstrates: agent-driven table filter integration.
- **`12-6-screenshot-tile-replay-3.png`** — shows tiles preserved across Back navigation. Demonstrates: persistence of agent results.
- **`12-4-screenshot-agentconfig-maxiter-field.png`** — shows the AgentConfig Zen form. Demonstrates: per-agent configurability.

The dev should pick 2–3 that best tell the "search → click-through → investigate" workflow story.

### File paths

- README.md edit (~150 lines added/reorganized).
- New `documentation/images/readme/` directory with 2–3 PNG files (each is a copy of an existing artifact image; not a re-shoot).

### Patterns to follow verbatim

- Existing README §"Sample interoperability production for testing" structure (terminal commands in code blocks, table for scenario modes) — re-use the pattern for the clean-namespace recipe.
- Existing README §"Multi-Namespace Install" for the namespace-creation steps — cross-reference rather than duplicate.

## Completion Notes

**Files modified / created:**

- `README.md` (modified) — added `## Quick start — using the agents` section at line 14 (29 lines: pitch + 3 example prompts + 3 image embeds + `### Launching the agents` subsection); added `## Try it in a clean namespace (recommended for evaluation)` section at line 55 (55 lines: 9-step linear recipe).
- `documentation/images/readme/` (new directory) — 3 PNG files copied from Epic 12 implementation artifacts:
  - `search-agent-finding-failed-sessions.png` (← `12-5-screenshot-load-button.png`, 152634 bytes)
  - `search-results-filter-table.png` (← `12-5-screenshot-filter-badge.png`, 95459 bytes)
  - `agent-config-form.png` (← `12-4-screenshot-agentconfig-maxiter-field.png`, 60687 bytes)

**Screenshot selection rationale.** Picked the three that tell a coherent "discover → click-through → configure" workflow narrative:
1. `search-agent-finding-failed-sessions.png` — Search Agent results with "Load N sessions into table" button (most compelling — shows the agent finding sessions + the operator's next-action affordance).
2. `search-results-filter-table.png` — filter badge applied + table narrowed (shows the agent → table integration that's distinctive to this project).
3. `agent-config-form.png` — AgentConfig Zen form (shows per-agent configurability, important for evaluation).
Skipped `12-1-screenshot-no-horizontal-scrollbar.png` (CSS-correctness fix, not a workflow demo) and `12-6-screenshot-tile-replay-*.png` (the filter-badge screenshot already covers the agent→table integration story; tile-replay is a more nuanced UX detail not central to a first-time-evaluator's interest).

**AC-1 verification (Quick Start at top).** `grep -n "^## " README.md` post-fix — `## Quick start — using the agents` appears at line 14, between `# iris-session-agent` (line 1) and `## v1.0.0 scope-complete summary` (line 43). Pitch sentence (line 16): *"Two agents that read your Ensemble sessions and answer questions in plain English."* Three example prompts at lines 20-22; three image embeds at lines 24-28.

**AC-2 verification (screenshots committed).** `ls documentation/images/readme/*.png` verbatim:

```
-rw-r--r-- 1 Josh 197121  60687 May  8 16:31 agent-config-form.png
-rw-r--r-- 1 Josh 197121 152634 May  8 16:31 search-agent-finding-failed-sessions.png
-rw-r--r-- 1 Josh 197121  95459 May  8 16:31 search-results-filter-table.png
```

All 3 embedded in README via `![Alt text](documentation/images/readme/<name>.png)` markdown tags at lines 24, 26, 28.

**AC-3 verification (clean-namespace recipe).** `## Try it in a clean namespace (recommended for evaluation)` at line 55. All 9 steps present and verified: (1) create namespace [line 59], (2) map `SessionAgent.PKG` [line 61-69], (3) `InstallIntoNamespace` [line 71-76], (4) credentials [line 78], (5) AgentConfig form [line 80], (6) `Bootstrap.InstallProduction` [line 82-87], (7) `RunScenario` [line 89-96], (8) launch UI [line 98], (9) tear down [line 100-107]. Cross-references to existing detailed sections at steps 2, 4 (avoids duplication per Rule 1).

**AC-4 verification (launch URLs).** `### Launching the agents` subsection at line 30. All 4 entry-point types documented:
- Direct URL (Search Agent): `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.MessageViewer.zen` — line 35.
- Mgmt Portal breadcrumb: `Interoperability → Message Viewer + Search Agent` — line 36.
- Sister page (Inspection Agent on VisualTrace): `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<id>` — line 38.
- Bookmarkable note + cross-reference to Story 12.3's BUG-04 fix: line 38 (*"bookmarkable; pin the URL with a specific session id"*) and line 39 (*"clicking a session-ID badge in any agent reply opens that session in the custom Visual Trace screen — Story 12.3 fix"*).

**AC-5 verification (no broken sections + anchors).**

Pre-fix `## ` headings (11):
```
14:## v1.0.0 scope-complete summary
26:## Operator Prerequisites
172:## Multi-Namespace Install
234:## Browser support (MVP)
242:## Sample interoperability production for testing
290:## What it does
307:## Status
321:## Development Plan
347:## Planning Artifacts (BMAD)
368:## Project posture
376:## Contributing
```

Post-fix `## ` headings (13):
```
14:## Quick start — using the agents
43:## v1.0.0 scope-complete summary
55:## Try it in a clean namespace (recommended for evaluation)
111:## Operator Prerequisites
257:## Multi-Namespace Install
319:## Browser support (MVP)
327:## Sample interoperability production for testing
375:## What it does
392:## Status
406:## Development Plan
432:## Planning Artifacts (BMAD)
453:## Project posture
461:## Contributing
```

Diff: every pre-existing `## ` heading appears in the post-fix list. Two new headings added (`## Quick start — using the agents`, `## Try it in a clean namespace (recommended for evaluation)`). Zero pre-existing headings dropped.

Internal anchor links scanned (8 total): `#sample-interoperability-production-for-testing` (×2), `#8-bookmark-urls`, `#multi-namespace-install`, `#6-llm-provider-api-keys` (×2), `#launching-the-agents`, `#operator-prerequisites`. All 8 verified to resolve to existing `## ` or `### ` heading anchors.

**AC-6 verification (spec length).** `wc -l _bmad-output/implementation-artifacts/12-7-...md` returns 130 lines (≤ 250 cap). After completion-notes additions the spec grows but remains under cap.

**Task 6 — `node -c` parse check (Story 12.0 Carry-Forward).** This story does NOT modify `static/chat-panel.js`. The carry-forward binding does not apply.

**Rule 12 (rendered-text readability) verification.** Read the rendered README post-edit. (a) No mojibake characters in any new section — em-dashes (—), arrows (→), and curly quotes ('') all render as correct UTF-8 glyphs. (b) Example prompts are operator-grade English: *"Find sessions with errors in the last hour"*, *"Why did this session fail?"*, *"Show me the source of the OrderRouter business process"* — all parsable, not vague. (c) Launch URLs match the existing §"8. Bookmark URLs" pattern: `http://<host>:<port>/csp/<lower-namespace>/SessionAgent.EnsPortal.MessageViewer.zen` is the same shape as the post-Bookmark URLs section already in the file. No README screenshot needed; the existing `documentation/images/readme/*.png` files are sufficient evidence per the story's "documentation-only" carve-out.

**Rule 5 (one-liner check before deferring).** No anchor links broken by the reorganization — `grep -n "\](#" README.md` enumeration showed all 8 internal links still resolve. No fix-now items found.

**Sprint status.** `_bmad-output/implementation-artifacts/sprint-status.yaml` flipped `12-7-readme-rewrite-quickstart-screenshots-cleanns: ready-for-dev → in-progress` at story start; Step 9 of the workflow flips it to `review` after this completion-notes commit.

## Review Findings

**Code review complete (2026-05-08).** 0 HIGH / 0 MEDIUM / 0 LOW findings. Clean review — all three review layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor) passed.

**Verbatim verification of all 6 ACs (review-side reproduction):**

- **AC-1 (Quick Start at top).** Reviewer ran `grep -n "^## " README.md` post-fix and confirmed `## Quick start — using the agents` at line 14, between `# iris-session-agent` (line 1) and `## v1.0.0 scope-complete summary` (line 43). Pitch sentence (line 16) reads as readable English: *"Two agents that read your Ensemble sessions and answer questions in plain English."* Three example prompts at lines 20–22 are operator-grade copy-paste-ready strings (*"Find sessions with errors in the last hour"*, *"Why did this session fail?"*, *"Show me the source of the OrderRouter business process"*).
- **AC-2 (screenshots committed).** Reviewer ran `ls -la documentation/images/readme/` — 3 PNG files present (`agent-config-form.png` 60687 bytes, `search-agent-finding-failed-sessions.png` 152634 bytes, `search-results-filter-table.png` 95459 bytes). Each PNG opened via Read tool — confirmed all three are real images (AgentConfig Zen form / Search Agent on Message Viewer with chat panel / Filtered table showing 3 narrow-down sessions). Markdown image tags at lines 24, 26, 28 use relative paths (`documentation/images/readme/...`) and meaningful alt text (not just "screenshot").
- **AC-3 (clean-namespace recipe).** Reviewer read `## Try it in a clean namespace (recommended for evaluation)` at line 55 in full; all 9 steps present and traced individually: (1) line 59, (2) lines 61–69, (3) lines 71–76, (4) line 78, (5) line 80, (6) lines 82–87, (7) lines 89–96, (8) line 98, (9) lines 100–107. Cross-references at steps 2 (`#multi-namespace-install`) and 4 (`#6-llm-provider-api-keys`) avoid duplication per Rule 1; section concise at 55 lines with ~10 minute time estimate at line 109.
- **AC-4 (launch URLs).** Reviewer read `### Launching the agents` subsection at line 30; all 4 entry-point types verified — direct MessageViewer URL (line 35), Mgmt Portal breadcrumb path (line 36), sister VisualTrace URL with `?SESSIONID=<id>` parameter (line 38), bookmarkable note + Story 12.3 BUG-04 cross-reference (lines 35, 38, 39).
- **AC-5 (no breakage + anchors).** Reviewer ran `grep -n "^## " README.md` and confirmed all 11 pre-existing `## ` headings preserved (v1.0.0 summary, Operator Prerequisites, Multi-Namespace Install, Browser support (MVP), Sample interoperability production for testing, What it does, Status, Development Plan, Planning Artifacts (BMAD), Project posture, Contributing). Two new `## ` headings added (Quick Start + Try it in a clean namespace). All 8 internal anchor links (`#sample-interoperability-production-for-testing` ×2, `#8-bookmark-urls`, `#multi-namespace-install`, `#6-llm-provider-api-keys` ×2, `#launching-the-agents`, `#operator-prerequisites`) verified to resolve to existing `## ` or `### ` heading anchors via grep cross-check.
- **AC-6 (spec length).** Reviewer ran `wc -l _bmad-output/implementation-artifacts/12-7-...md` — 211 lines (under the 250 cap per Rule 1).

**Rule 12 (rendered-text readability) review-side pass.** Reviewer ran `grep -nP "[^\x00-\x7F]" README.md | head -50` (UTF-8 locale) and inspected every non-ASCII byte in the new sections. All non-ASCII characters are correctly-encoded UTF-8 glyphs (em-dashes `—`, arrows `→`, curly quotes `' "`, section markers `§`). Zero `Â`-prefixed garbage indicating UTF-8-as-CP1252 mojibake. Reviewer additionally read the new prose top-to-bottom for parsability — all sentences are operator-grade English, no vague phrasing, example prompts realistic (an operator would actually type these strings).

**Rule 8 (defer threshold) review-side pass.** No findings raised. The reviewer noted one pre-existing convention drift in §"8. Bookmark URLs" (uses `<NS>` placeholder uppercase form while Quick Start uses `<lower-namespace>` — the new sections introduced the more correct convention) but this is out of story scope (story is documentation-additive only, no AC requires harmonizing the older sections). Dismissed as noise per Rule 8 test 3 (cosmetic, no predicted-bug shape).

**Scope check.** Reviewer ran `git status --short` — only README.md, sprint-status.yaml, story spec file, and new `documentation/` PNG folder modified. Zero `.cls` / `.js` / `.css` changes (story scope is documentation-only). Confirmed via `git diff --stat HEAD` — 86 net lines added across README.md + sprint-status.yaml only.

**Status flip.** Story 12.7 `review` → `done` in story file Status header AND `sprint-status.yaml` development_status entry.

## Change Log

- 2026-05-08 — Initial draft (lead, post-Story 12.5 commit `0e12d94`).
- 2026-05-08 — Dev implementation complete (3 README sections added: Quick Start + Launching the agents subsection + Try it in a clean namespace; 3 screenshots committed under `documentation/images/readme/`; all 6 ACs verified with verbatim grep + ls evidence).
- 2026-05-08 — Code review complete (clean: 0 HIGH / 0 MEDIUM / 0 LOW); status flipped review → done.
