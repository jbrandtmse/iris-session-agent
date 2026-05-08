# Story 12.0: Epic 11 Deferred Cleanup + Epic 12 Setup

**Status:** done

**Source:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-05-08.md` opens Epic 12 in response to the 2026-05-08 walkthrough's 11 findings (`_bmad-output/implementation-artifacts/walkthrough-bugs-2026-05-08.md`). This Story 12.0 is the Rule 7 sprint-planning gate — it triages every Epic 10 retrospective AI + Epic 11 deferred-work entry into Include / Defer / Drop buckets, confirms Epic 12 operator-state, and binds the Story 10.13 `node -c` requirement to Stories 12.1 / 12.6 (which will modify `chat-panel.js`).

## User Story

As the **lead** running `/epic-cycle 12`, I want every Epic 10 / Epic 11 deferred item explicitly triaged and Epic 12 operator-state explicitly captured, so that subsequent Story 12.x dev agents inherit a clean working state and no deferred item silently falls off the radar.

## Acceptance Criteria

**AC-1 — Triage table.** This story file contains a verbatim triage table mapping every recent (Epic 10 wrap-up + Epic 11) deferred-work entry AND every Epic 10 retrospective Action Item (AI-1 through AI-5) AND every Epic 10 retrospective continued-deferral item (lines 59–65 of the retro file) to one of three buckets: **Include in Story 12.x** (with named successor), **Defer to v2** (with rationale), or **Drop** (with rationale, including DROP–RESOLVED-by-Story-N.M for items already closed). The triage table is the audit trail.

> **Then** the table appears verbatim under "Triage Decisions" below; every recent deferred-work entry from `deferred-work.md` lines 1431–1455 is represented; every Epic 10 retro AI (AI-1 through AI-5) from `epic-10-retro-2026-05-08.md` is represented; every continued-deferral entry from retro lines 59–65 is represented; no deferred item is missing.

**AC-2 — Operator-state capture.** Story file Completion Notes captures verbatim probe output proving (a) `Ens.Director.IsProductionRunning` returns 1, (b) `Util.EnvSecret.IsResolvable("SESSIONAGENT_OPENAI_API_KEY", "SessionAgentOpenAI")` returns 1, (c) `SessionAgent.Sample.Production` is registered in `Ens_Config.Production`. Per Rule 7 §"Sample production state at Epic-cycle Step 1" + §"Credential-resolvability matrix at Step 1".

> **Then** Completion Notes shows three probe envelopes verbatim with their `returnValue` / row data; if any probe fails, the dev escalates to the lead before continuing per Rule 7.

**AC-3 — `chat-panel.js` `node -c` capture rule binding.** Story 10.13's deferred entry ("Reviewer notes the verbatim `node -c` output should be captured on the next chat-panel.js modification to satisfy the AC verbatim") is added as a binding requirement to Stories 12.1 and 12.6 spec-drafting notes via a Carry-Forward section in this Story 12.0 file. Per Rule 9 binding-deferrals.

> **Then** "Carry-Forward" section below explicitly names Story 12.1 + Story 12.6 as the binding successors for the `node -c` capture; a same-commit cross-reference exists.

**AC-4 — Sprint-status epic activation.** `sprint-status.yaml` epic-12 status flipped from `backlog` to `in-progress` (per the standard "first story in epic" auto-flip).

> **Then** `grep "epic-12:" sprint-status.yaml` returns `epic-12: in-progress`; Story 12.0 status is `ready-for-dev` after this story file is created (or `done` after the story commit lands).

**AC-5 — No `Story 12.x` binding-successor entries already in deferred-work.md.** Rule 9 grep confirms no pre-existing entry names a Story 12.x as carrier (clean ledger before Epic 12 dispatch).

> **Then** `grep -ni "Story 12\|story-12\|Story-12" deferred-work.md` returns ≤ 1 hit (and that hit is the existing line-128 passing reference, not a binding entry).

**AC-6 — Spec length governance.** This story file is ≤ 250 lines (Rule 1 cap).

> **Then** `wc -l 12-0-epic-11-deferred-cleanup.md` returns ≤ 250.

## Tasks / Subtasks

- [x] **Task 1 — Read source artifacts**
  - [x] Read `walkthrough-bugs-2026-05-08.md` (11 findings + their root causes)
  - [x] Read `sprint-change-proposal-2026-05-08.md` (8-story plan + bundling rationale)
  - [x] Read `epic-10-retro-2026-05-08.md` (5 AIs + v2-deferred items)
  - [x] Read recent `deferred-work.md` entries (lines 1431–1455 — Stories 10.10 / 10.11 / 10.13 / 11.2)
- [x] **Task 2 — Build triage table** (see Triage Decisions below; 14 items triaged after dev-12-0 clarification expansion: original 9 + 4 retro AIs (AI-1/AI-2/AI-3/AI-4) + 1 continued-deferral (Story 10.13 MaxTokens cascade overwrite, RESOLVED by Story 11.1); AI-5 row label corrected from "AI-1" to "AI-5")
- [x] **Task 3 — Operator-state probes** — see Completion Notes below for verbatim envelopes
- [x] **Task 4 — Carry-Forward section authored** — `node -c` capture rule binds Story 12.1 + Story 12.6
- [x] **Task 5 — Rule 9 binding-successor grep** — confirmed clean (1 passing reference; 0 binding entries)
- [x] **Task 6 — Sprint-status flip** — `epic-12: backlog` → `in-progress` confirmed; `12-0-epic-11-deferred-cleanup: backlog` → `ready-for-dev` → `review` (dev flipped to in-progress, lead now flips to review pre-commit)
- [x] **Task 7 — Spec length verification** — `wc -l` re-verified at 129 lines after expansion (≤ 250)
- [x] **Task 8 — Commit + push** (lead path — `feat(epic-12): story 12.0 — Epic 11 deferred cleanup + Epic 12 setup`)

## Triage Decisions

| Source | Item | Decision | Rationale | Successor |
|---|---|---|---|---|
| `deferred-work.md` line 1431 (Story 10.10) | 4 LOW JS code-smells (`arguments` on no-arg method, magic-number `currTab !== 5`, redundant `detailsHidden` guard, `_tabDisplay['Agent']` key naming) | DROP | Rule 8 test 3 — all explicitly noted as cosmetic, no predicted-bug shape | n/a |
| `deferred-work.md` line 1440 (Story 10.11) | LOW test coverage gaps (unknown-provider fallthrough, `endpointUrl=""` assert) + LOW cascade UX friction | DROP | Rule 8 test 3 — cosmetic test-coverage; UX friction closed by Story 10.13 F-3 | n/a |
| `deferred-work.md` line 1448 (Story 10.13) | LOW — "verbatim `node -c` output should be captured on next `chat-panel.js` modification" | INCLUDE — bind to Stories 12.1 + 12.6 | Both Stories 12.1 (CSS overflow) and 12.6 (tile replay) modify `static/chat-panel.js`. Each spec MUST include a `node -c static/chat-panel.js` probe in Tasks/Subtasks with verbatim exit-0 capture in Completion Notes. | Story 12.1, Story 12.6 |
| `deferred-work.md` line 1453 (Story 11.2) | LOW — Implementation Plan / File List narrative undercount (30/19 vs empirical 33/21) | DROP | Rule 8 test 3 — cosmetic doc-drift in Story 11.2's spec narrative; tests pass; no shipped code defect | n/a |
| Epic 10 retro AI-1 | Rule 12 sharpened wording on runtime-behavior layout-correctness ACs (chrome-devtools-mcp non-substitutable) | DEFER to v2 | Rule-codification work; was assigned to never-created Story 11.0 (Epic 11 went directly to hotfixes 11.1–11.4). Not Epic 12 scope (Epic 12 = bug fixes + UX polish, not rule codifications) | v2 / dedicated rule-codification story |
| Epic 10 retro AI-2 | Hotfix re-verification protocol — every hotfix must run the original walkthrough that surfaced the defect | DEFER to v2 | Same rationale as AI-1: rule codification, was Story 11.0 territory, not Epic 12 scope | v2 |
| Epic 10 retro AI-3 | Spec-length governance — UI-rendering specs justify a higher cap or different Rule 1 nuance | DEFER to v2 | Same rationale: rule codification, was Story 11.0 territory, not Epic 12 scope. Epic 12 specs adhere to existing Rule 1 ≤ 250 cap | v2 |
| Epic 10 retro AI-4 | UI-epic mandatory-walkthrough sub-section (Rule 6 addition for any UI epic) | DEFER to v2 | Same rationale: rule codification, was Story 11.0 territory. Epic 12's pre-retro empirical battery (Rule 6 step 4) already covers walkthrough verification for the UI fixes | v2 |
| Epic 10 retro AI-5 (chat-panel JS parse-and-static-check) | "Add ESLint or `node -c`-style JS parse-and-static-check to the regression sweep" | DEFER to v2 | Standalone test harness work, not Epic 12 scope; the per-story `node -c` capture (per AC-3 above) covers the immediate need without requiring a new test class | v2 |
| Epic 10 retro Story 7.0 carry-forward Items E / H / I | Test-isolation flake (drift history 4.5 → 4.7 → 8.0 → 9.0 → 10.9 → "v2 cleanup") | DEFER to v2 | 4 prior Rule 9 recovery thresholds reached per Story 9.0 AC-6 compounding-recovery clause. Dedicated v2 cleanup story per Epic 10 retro AI-5 umbrella | v2 |
| Epic 10 retro Story 10.7 multi-NS install gap | Programmatic bundle copy on `InstallIntoNamespace` | DROP — RESOLVED by Story 11.3 | Story 11.3 shipped the programmatic copy in v1.0.1 (`Installer.CopyStaticBundleToNamespace`). README workaround section now marked DEPRECATED | n/a (closed) |
| Epic 10 retro Story 10.7 custom Prism grammars | Full ObjectScript / HL7 grammars (currently STUBs with markup/csharp fallbacks) | DEFER to v2 | Epic 12 doesn't touch the Markdown bundle; STUB fallbacks ship and render readably; full grammar authoring is a v2 nice-to-have | v2 |
| Epic 10 retro Story 10.8 off-page citation full sync | `svgPage` lacks page-of-row API; pragmatic-acceptance fallback shipped | DEFER to v2 | Epic 12 doesn't touch off-page citation flow; pragmatic fallback works; full sync requires svgPage API change | v2 |
| Epic 10 retro line 65 — Story 10.13 LOW: MaxTokens cascade overwrite | Operator's persisted MaxTokens replaced by canonical default on Provider rotation | DROP — RESOLVED by Story 11.1 | Story 11.1 ("MaxTokens Cascade Preservation on Provider Rotation") shipped in v1.0.1 with the symmetric preserve-when-customized heuristic — captures `data.MaxTokens`, compares against canonical default, restores if customized. AgentConfigTest 22/22 pass. Different bug shape than Epic 12's BUG-06 (BUG-06 is `MaxIterationsPerTurn`, not `MaxTokens`) | n/a (closed) |

**Total:** 14 items triaged. **0 INCLUDE** (only AC-3 carry-forward into Stories 12.1 / 12.6, not new ACs). **9 DEFER**. **5 DROP** (3 cosmetic + 2 RESOLVED).

## Carry-Forward (Rule 9 binding-deferrals on named successors)

- **Story 12.1** (UX polish — CSS overflow + Inspection prompt) MUST add a `node -c static/chat-panel.js` probe to its Tasks/Subtasks and capture verbatim exit-0 output in Completion Notes. Source: Story 10.13 deferred-work entry (`deferred-work.md` line 1450).
- **Story 12.6** (Chat history tile replay) MUST add a `node -c static/chat-panel.js` probe to its Tasks/Subtasks and capture verbatim exit-0 output in Completion Notes. Source: Story 10.13 deferred-work entry (`deferred-work.md` line 1450). Story 12.6 modifies `chat-panel.js` more substantially than 12.1, so the probe is doubly load-bearing here.

When the lead drafts Stories 12.1 and 12.6 specs (per Step 4a of `/epic-cycle 12`), this Carry-Forward section MUST be cross-referenced by name. Reviewer enforces: a Story 12.1 or 12.6 diff missing the `node -c` capture is a HIGH-severity finding per Rule 8 (predicted-bug shape: parse-error in `chat-panel.js` ships silently to operators).

## Dev Notes

### Operator-state pre-conditions (verified at Story 12.0 dispatch time)

The lead probed three operator-state surfaces before dispatching this story. Verbatim envelopes go in Completion Notes per AC-2.

- `Ens.Director.IsProductionRunning` — initial probe returned 0 (production stopped); `Ens.Director.StartProduction("SessionAgent.Sample.Production")` returned 1; re-probe returned 1.
- `Util.EnvSecret.IsResolvable("SESSIONAGENT_OPENAI_API_KEY", "SessionAgentOpenAI")` — returned 1 (credential row present).
- `Ens_Config.Production` SQL probe — `SessionAgent.Sample.Production` row present (registered).

### Spec scope discipline

This is a documentation-only story. No `.cls` / `.js` / `.md` source-code edits. The "implementation" is:
1. Authoring this spec file (≤ 250 lines).
2. The sprint-status flip (`epic-12: backlog → in-progress`; `12-0-...: backlog → ready-for-dev` then `→ done` at commit time).
3. The git commit with this file + the sprint-status update.

### Patterns to follow verbatim

- This file's Triage Decisions table format mirrors `5-0-epic-4-deferred-cleanup.md` and `8-0-epic-7-deferred-cleanup.md`.
- The Carry-Forward section format mirrors Story 10.0 AC-5's "Re-bind LOW-9.3-F02 to Story 10.6" pattern.

### Why no Epic 11 retrospective file exists

Per `sprint-status.yaml` line 161, `epic-11-retrospective: optional`. The Epic 11 (v1.0.1 patch) shipped 4 stories cleanly with no project-lead-elected retrospective. The Sprint Change Proposal opening Epic 12 (`sprint-change-proposal-2026-05-08.md` §"Section 2 / Epic Impact") explicitly accepts this — Story 12.0 substitutes for the retrospective triage step by reading deferred-work entries directly.

## Completion Notes

**Operator-state probes (verbatim, AC-2):**

```
Ens.Director.IsProductionRunning() → returnValue=1
Util.EnvSecret.IsResolvable("SESSIONAGENT_OPENAI_API_KEY", "SessionAgentOpenAI") → returnValue=1
SQL: SELECT %EXACT(Name) FROM Ens_Config.Production WHERE %EXACT(Name) %STARTSWITH 'SessionAgent.Sample'
  → 1 row: ["SessionAgent.Sample.Production"]
```

**Rule 9 binding-successor grep (verbatim, AC-5):**

```
grep -ni "Story 12\|story-12\|Story-12" _bmad-output/implementation-artifacts/deferred-work.md
  → line 128 only: passing reference in unrelated rationale text ("none planned through Epic 12")
  → 0 binding-successor entries.
```

**Spec length (AC-6):** verified pre-commit via `wc -l _bmad-output/implementation-artifacts/12-0-epic-11-deferred-cleanup.md`.

## Change Log

- 2026-05-08 — Initial draft (lead). Triage table + Carry-Forward + Completion Notes.
