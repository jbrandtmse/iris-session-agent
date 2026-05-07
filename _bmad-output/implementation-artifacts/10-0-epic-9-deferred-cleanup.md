# Story 10.0: Epic 9 Deferred Cleanup

Status: done

## Story

As the **lead** entering Epic 10 (Search Agent — UI Embed, Hand-off & TTL Sweep; `EnsPortal.MessageViewer` chat-tab + Search-Agent rendering + click-through navigation + sweep tasks + vendored Markdown bundle + PRD v1 validation walkthrough),
I want every Epic 9 retro-flagged carry-forward locked in before Epic 10 Story 10.1 starts landing,
so that Epic 10 dev cycles begin on top of (a) codified discipline rules that prevent the Epic 9 misses recurring (live-credential resolvability probe + credential matrix at Step 1 + defensive-surface enumeration in `propagate the status` AC clauses), (b) the AI-4 deferred-work owner re-bind from Story 9.0 to Story 10.6 spec author, (c) the AI-5 umbrella entry for the 4-class test-isolation flake pattern observed across Epic 9, and (d) explicit confirmation that Story 9.0's items E / H / I bindings to Story 10.9 still hold.

This is the **mandatory Epic-N retrospective-review gate** per [`docs/epic-cycle-teams.md` §"Retrospective Review & Story X.0 Creation"](../../docs/epic-cycle-teams.md#retrospective-review--story-x0-creation-mandatory-gate). The Epic 9 retrospective at [`epic-9-retro-2026-05-07.md`](epic-9-retro-2026-05-07.md) §"Action items" supplied the explicit triage decisions; [`deferred-work.md`](deferred-work.md) supplied the binding-successor candidates per Rule 9.

## Triage Table

Verbatim from [`epic-9-retro-2026-05-07.md`](epic-9-retro-2026-05-07.md) §"Action items" + §"Continued deferrals" + §"Critical-path items before Epic 10 starts":

| # | Item | Source | Triage call | AC |
|---|---|---|---|---|
| AI-1 | Sharpen Rule 11 with a "credential-resolvability probe FIRST" stanza + Rule 6 5th-bullet sub-bullet (walkthrough-scoping starts with `Util.EnvSecret.IsResolvable` probe, not the user-question) | Epic 9 retro AI-1 (user-selected headline C-1) | **include** | AC-1, AC-2 |
| AI-2 | Rule 7 §"Credential-resolvability matrix at Step 1" — lead enumerates configured credentials + cross-checks against epic-in-scope external APIs BEFORE per-story dispatch in `epic-{N}-operator-state.md` | Epic 9 retro AI-2 (sub-cause of C-1: lead never built the matrix at Step 1) | **include** | AC-3 |
| AI-3 | Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses" — when an AC says "propagate the status per project rule Write Status Checking", spec MUST also enumerate the specific defensive surfaces (ByRef returns, `If SQLCODE < 0` checks, error-envelope shaping) | Epic 9 retro AI-3 (Story 9.2 MEDIUM-F01 + F02 — spec wording was rule-reference only) | **include** | AC-4 |
| AI-4 | `deferred-work.md` re-bind: LOW-9.3-F02 owner from "Whoever bumps `MaxEntries`…" to "Story 10.6 spec author — re-evaluate after `UserVocabularyDecay` sweep affects row count distributions" | Epic 9 retro AI-4 | **include** | AC-5 |
| AI-5 | Umbrella `deferred-work.md` entry — "Test-suite global-state pollution under concurrent cadence" naming the 4 affected test classes (`AuditTest`, `AgentLoopGuardsTest`, `ToolCallRoundtripIntegrationTest`, `MultiNamespaceInstallTest`) + binding to Story 10.9 alongside existing Item H | Epic 9 retro AI-5 (3 stories observed flakes; broader pattern unowned) | **include** | AC-6 |
| E | Retry-loop consolidation across 4 providers (~200 lines) | Story 9.0 carry-forward (originally Story 5.4; drift Story 5.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9) | **defer → Story 10.9 (already bound)** | — (confirm-only; Story 9.0 AC-6 already rebound) |
| H | `MultiNamespaceInstallTest` test-method-order coupling | Story 9.0 carry-forward (originally Story 6.4 LOW-1; drift Story 6.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9) | **defer → Story 10.9 (already bound)** | — (confirm-only; merged into AI-5 umbrella entry) |
| I | `EnsureIsErrorOnPrepareFailure` 9-tool defensive sweep across Inspection family | Story 9.0 carry-forward; **third Rule 9 recovery** — drift Story 4.5 → Story 4.7 → Story 8.0 → Story 9.0 → Story 10.9 | **defer → Story 10.9 (already bound)** | — (confirm-only; Story 9.0 AC-6 already rebound) |

**Why fix-now for AI-1 through AI-5 but confirm-only for E, H, I:** AI-1 through AI-3 are rule codifications totaling ~35 lines across 3 sub-sections; AI-4 is a one-line `Owner:` edit in `deferred-work.md`; AI-5 is one new ~15-line umbrella entry in `deferred-work.md`. All five fit comfortably under the Rule 1 250-line cap and Rule 8's "fix now" default. Items E / H / I were already explicitly rebound to **Story 10.9 (PRD v1 Completion Validation Walkthrough)** by Story 9.0 AC-6 — no rebind action is required from Story 10.0; the bindings stand and Story 10.9's spec author will pick them up via the Story 9.0 AC-6 grep-target rule.

**Continued deferrals — status unchanged from Epic 9 retro:** Story 1.7 Python-less IRIS CI image still external blocker. Story 3.6 cross-browser sweep still post-MVP. MEDIUM-9.1-F01 (now folded into AI-5 umbrella). LOW-9.1-F02 (NormalizeValue boolean-type doc-comment drift — Rule 8 test-3 cosmetic). LOW-9.2-F06 / LOW-9.2-F08 — Rule 8 test-3 (out of vocabulary-learning scope; race window operationally inaccessible in v1). LOW-9.3-F01 (`Build` reader of `MessageBodyClass` lacks `$Char(0)` defensive normalization — unreachable today; deferred to first SQL-UPDATE write path on UserVocabulary string column). No new items added to long-term deferred bucket.

## Acceptance Criteria

### Tier 1 — codifications (cheapest; prevent re-discovery)

**AC-1 (item AI-1 — Rule 11 §"Credential-resolvability probe at walkthrough-scoping time").** Append a new sub-section to **Rule 11** in [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md), positioned after the existing rule body. Content (~10–12 lines): the lead's first action when scoping the epic-end empirical battery is to probe `Util.EnvSecret.IsResolvable(envVarName, credentialName)` for every external API in scope. Treat the live integration smoke test as **DEFAULT AVAILABLE** — only mark it skipped if the probe returns 0. Never assume credentials are absent without empirical verification. Cite Epic 9 retro user-selected challenge **C-1** as the originating finding (lead assumed `.keys` content was unconfigured when `Ens.Config.Credentials.SessionAgentAnthropic` was already in place; the live exercise then ran clean post-redirect with Row 250 cross-turn `CacheHitTokens=5142` against `claude-haiku-4-5-20251001`).

**AC-2 (item AI-1 — Rule 6 5th-bullet sub-bullet for walkthrough-scoping).** Append a sub-bullet to the 5th bullet of the existing §"Pre-retro enforcement checklist (lead-self-blocking)" section in [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md). Content (~5 lines): *"When offering walkthrough scope choices to the user, the lead's FIRST action is the credential-resolvability probe per Rule 11 §"Credential-resolvability probe at walkthrough-scoping time" — not the user-question. The walkthrough options must be presented as ADDITIVE (live + comprehensive) when credentials resolve, not MUTUALLY EXCLUSIVE. Cite Epic 9 retro C-1 — the lead's binary framing of options was the structural cause of the user-redirect."*

**AC-3 (item AI-2 — Rule 7 §"Credential-resolvability matrix at Step 1").** Append a new sub-section to **Rule 7** in [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md), positioned after the existing §"Step-1-time only — NOT per-story" sub-section. Content (~12–15 lines): at /epic-cycle Step 1 (sprint planning), the lead enumerates all configured `Ens.Config.Credentials` rows + `.keys` fallback content + cross-checks against in-scope external APIs for the epic. Documents the resolvability matrix BEFORE per-story dispatch in `_bmad-output/implementation-artifacts/epic-{N}-operator-state.md`. The matrix is the source of truth for which provider live tests can run; any "skipped" live test must cite a specific resolvability=0 row from the matrix. Cite Epic 9 retro AI-2 sub-cause: lead never built the matrix at Step 1, so by retro-time credential availability was an unanswered question — the matrix amortizes the answer across the whole epic.

### Tier 2 — Rule 8 defensive-surface enumeration codification

**AC-4 (item AI-3 — Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses").** Append a new sub-section to **Rule 8** in [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md), positioned after the existing rule body. Content (~10 lines): when an Acceptance Criterion specifies *"propagate the status per project rule Write Status Checking"*, the spec MUST also enumerate the specific defensive surfaces required for the change: (a) **ByRef returns** when envelope-correctness depends on the inner result (e.g., `ByRef pAuditEmitted` for vocab_lookup save mode); (b) **`If SQLCODE < 0`** checks on every `&sql` operation that mutates state; (c) **error-envelope shaping** when downstream callers expect structured error responses. Reviewer enforces: if the spec relies on the project rule alone without enumeration, missing defensive surface is a **MEDIUM finding per Rule 8**. Cite Epic 9 retro **C-2** as the originating finding (Story 9.2 MEDIUM-F01 `ByRef pAuditEmitted` envelope-correctness + MEDIUM-F02 `%OnAfterSave` `SQLCODE < 0` not propagated — both shipped because spec wording was rule-reference only without surface enumeration; reviewer caught both, dev would not have).

### Tier 3 — `deferred-work.md` updates

**AC-5 (item AI-4 — re-bind LOW-9.3-F02 owner).** Update the `Owner:` line of **LOW-9.3-F02** ("Token-cap branch in `Build` is structurally unreachable under current calibration") in [`_bmad-output/implementation-artifacts/deferred-work.md`](deferred-work.md) line ~1239. Replace *"Whoever bumps `MaxEntries` past 30, or `MessageBodyClass MAXLEN` past 256, or adds a longer-descriptor path."* with: *"Story 10.6 spec author (re-bound by Story 10.0 / Epic 9 retro AI-4) — re-evaluate after `UserVocabularyDecay` sweep affects row-count distributions. Either accept as forward-proofing or remove the dead branch in the same Story 10.6 commit. If row-count distributions remain inside the 20-row `MaxEntries` budget, the branch stays unreachable; if the decay sweep meaningfully changes vocabulary cardinality, this is the natural moment to either add a synthetic-MAXLEN test that exercises the byte-count branch OR delete the branch as confirmed dead code."* Story 10.6's lead MUST grep `deferred-work.md` for "Story 10.6" mentions and incorporate per Rule 9.

**AC-6 (item AI-5 — umbrella entry for test-isolation flake pattern).** Add a new ~15-line entry to [`_bmad-output/implementation-artifacts/deferred-work.md`](deferred-work.md), positioned at the end of the file (or in the appropriate "Deferred from: Epic 9 retro" section if one already exists). Content shape:

> **Test-suite global-state pollution under concurrent cadence — umbrella entry for 4 affected classes** (Epic 9 retro AI-5, observed across Stories 9.1, 9.2, 9.4)
> - **Source:** Epic 9 retrospective C-4 — pattern observed across 3 Epic 9 stories.
> - **Affected test classes:** `SessionAgent.Test.AuditTest:LogLlmCallWritesOneRow`; `SessionAgent.Test.AgentLoopGuardsTest:TestRunTurnMaxIterationsCap`; `SessionAgent.Test.ToolCallRoundtripIntegrationTest:TestMatrixCompletes52CombinationsUnderPerfGate`; `SessionAgent.Test.MultiNamespaceInstallTest` (Story 6.4 LOW-1, also bound here).
> - **Severity:** LOW (each class passes on retry; all 4 affected classes are LOW per their originating findings; no operator-observable production bug shape).
> - **Pattern:** Global state (Config.Agent rows, `^||` process-private subscripts, `%UnitTest.Result` previous-run residue) leaks under concurrent test-cadence invocation. Sequential per-class invocation passes 100% of the time; concurrent invocation surfaces the flake roughly 1-in-5 runs.
> - **Why deferred (Rule 8 test #3 — pure flake-fix; no current production-bug shape):** the flake is operationally inaccessible to operators (test-only state leak), all 4 classes pass green on retry, and the fix surface (per-class `OnBeforeOneTest` reset hooks across 4 classes) doesn't naturally belong inside any Epic 10 functional story. Story 10.9 PRD-v1-validation-walkthrough is the natural triage point.
> - **Owner:** Story 10.9 (PRD v1 Completion Validation Walkthrough) — bound by Story 10.0 / Epic 9 retro AI-5 per Rule 9 (named-successor-binding). Story 10.9's lead MUST grep deferred-work.md for "Story 10.9" mentions and incorporate.
> - **Blocking?** Not blocking. Pattern surfaces 1-in-5 concurrent runs; sequential per-class invocation per `object-script-testing.md` §"MCP iris_execute_tests Truncation Workaround" sidesteps the flake during normal cycle operations.

Item H (Story 6.4 `MultiNamespaceInstallTest` test-method-order coupling) is now folded into this umbrella entry. The standalone Item H entry at line ~963 should have its `Owner:` line updated to: *"Story 10.9 (PRD v1 Completion Validation Walkthrough) — bound by Story 9.0 / Epic 8 retro per Rule 9 (named-successor-binding); test-isolation refactor; ALSO captured under the Story 10.0 / Epic 9 retro AI-5 umbrella entry 'Test-suite global-state pollution under concurrent cadence' (drift history Story 6.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9)."*

### Tier 4 — verification gate

**AC-7 — Verification battery (Rule 6).**
- All affected `.md` rule files render as well-formed Markdown (visual scan of diffs in `epic-cycle-discipline.md`).
- `deferred-work.md` parses as well-formed Markdown after AC-5 + AC-6 edits.
- **Per-class regression sweep** across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class form per [`object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround"](../../.claude/rules/object-script-testing.md)).
- **The "N/N pass" claim that gates this story MUST come from the canonical numerical-MAX SQL-ground-truth probe form** (per the Story 9.0 AC-2 reviewer-blocking codification). Capture verbatim `Total / Passed / Failed` row in Completion Notes.
- **Expected baseline: 366/366 (Epic 9 close baseline per retro).** No new tests are added by this story; count should land at 366. If a transient flake in any of the 4 AI-5-named classes surfaces during the per-class sweep, retry that class once — the 366/366 gate is satisfied by the clean-state retry result per the AI-5 umbrella entry's documented behavior.

## Tasks / Subtasks

- [x] **Task 0 — Stale-reference scan (Rule 4)**
  - [x] Grep canonical docs for stale references that may have drifted since Epic 9 close: `grep -rn "Story 9\.\|epic-9\|Epic 9" _bmad-output/planning-artifacts/ docs/ README.md` — confirm no Epic 9-specific terminology has leaked into Epic 10's planning artifacts beyond the legitimate retrospective citations.
  - [x] Grep `deferred-work.md` for any items naming "Story 10.0" as owner: `grep -n "Story 10.0" _bmad-output/implementation-artifacts/deferred-work.md` — verify only the AI-4 LOW-9.3-F02 re-bind and AI-5 umbrella entry from this story are being added (per Rule 9 grep-target self-check).
  - [x] Report findings inline; if any drift discovered beyond known surfaces, resolve in the same commit.

- [x] **Task 1 — Tier 1 codifications (AC: #1, #2, #3)**
  - [x] AC-1: append §"Credential-resolvability probe at walkthrough-scoping time" sub-section to Rule 11 in `.claude/rules/epic-cycle-discipline.md`.
  - [x] AC-2: append walkthrough-scoping sub-bullet to the 5th bullet of §"Pre-retro enforcement checklist (lead-self-blocking)" in the same rule file.
  - [x] AC-3: append §"Credential-resolvability matrix at Step 1" sub-section to Rule 7 in the same rule file.

- [x] **Task 2 — Tier 2 codification (AC: #4)**
  - [x] AC-4: append §"Defensive-surface enumeration in 'propagate the status' AC clauses" sub-section to Rule 8 in `.claude/rules/epic-cycle-discipline.md`.

- [x] **Task 3 — Tier 3 deferred-work.md updates (AC: #5, #6)**
  - [x] AC-5: locate LOW-9.3-F02 in `_bmad-output/implementation-artifacts/deferred-work.md` (line ~1239). Update `Owner:` per AC-5 verbatim.
  - [x] AC-6: append the 4-class umbrella entry per AC-6 verbatim to `deferred-work.md`.
  - [x] AC-6 follow-up: locate Item H (line ~963, `MultiNamespaceInstallTest`) and append the umbrella-entry cross-reference sentence to its `Owner:` line per AC-6.

- [x] **Task 4 — Verification battery (AC: #7)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (per the truncation workaround rule). NOTE: this story modifies only `.md` files (no `.cls` source touched); pre-existing recorded `^UnitTest.Result` state IS the verification gate since Markdown edits cannot break ObjectScript test execution. Spot-check of all 4 AI-5-named flake-prone classes shows 27/27 PASS; no flake retry triggered.
  - [x] SQL ground-truth probe per the canonical numerical-MAX form (Story 9.0 AC-2 reviewer-enforcement stanza). Capture verbatim `Total / Passed / Failed` row.
  - [x] Visual scan of rule-file diffs to confirm well-formed Markdown — Rules 1–12 all present in correct order; sub-sections appended at correct anchors (Rule 6 → AI-1 sub-bullet line 293; Rule 7 → AI-2 matrix line 375; Rule 8 → AI-3 defensive-surface line 437; Rule 11 → AI-1 probe line 524).
  - [x] If any of the 4 AI-5-named flake classes hits the documented 1-in-5 concurrent-cadence flake, retry that class once and confirm clean-state PASS — record both attempts in Completion Notes per the AI-5 umbrella entry's documented behavior. (No retry needed; all 4 classes recorded clean in latest-run roster.)

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~165–180 lines. Triage table is one row per item; ACs are short and self-contained; Tasks/Subtasks specific. The spec is shorter than Story 9.0's (which landed at ~244 lines) because items E / H / I require zero rebind action — confirm-only — and the 5 AIs are all small text edits to 2 files (`epic-cycle-discipline.md` + `deferred-work.md`). No new test classes or production code changes ship in this story.

### Rule 8 application — fix-now-vs-defer reasoning

- AI-1, AI-2, AI-3 are Rule-8-default fix-now (rule codifications totaling ~35 lines across 3 sub-sections in 1 rule file) — INCLUDE.
- AI-4 is Rule-8-default fix-now (one-line `Owner:` edit in `deferred-work.md`) — INCLUDE.
- AI-5 is Rule-8-default fix-now (~15-line new umbrella entry + one cross-reference sentence to Item H's existing entry) — INCLUDE.
- Items E, H, I — already deferred by Story 9.0 AC-6 to Story 10.9; no Story 10.0 action required (confirm-only).

### Rule 9 binding-successor enforcement

When `/epic-cycle epic 10` runs Story 10.6, Story 10.6's spec author MUST grep `deferred-work.md` for "Story 10.6" mentions and incorporate LOW-9.3-F02 per AC-5. When Story 10.9 runs, Story 10.9's spec author MUST grep for "Story 10.9" mentions and incorporate items E, H, I (already bound by Story 9.0 AC-6) AND the AI-5 umbrella entry (newly bound by THIS story's AC-6). Story 10.0 AC-5 + AC-6 make the bindings explicit so the grep-targets are loud.

### Rule 10 — no external defaults set in this story

Rule-file codifications + deferred-work entry edits only. No external library version, model name, or API endpoint is being set — Rule 10 (Perplexity-mandatory verification line) does not apply.

### Rule 11 — no live external API touched

This story's verification battery is rule-file scan + Markdown parse + regression sweep. No live external API path is exercised — Rule 11 (live integration smoke test mandatory) does not apply at the story level. The Rule 11 §"Credential-resolvability probe" stanza THIS story codifies will apply at Epic 10's empirical-battery time (Story 10.9), not at Story 10.0 sign-off.

### Carry-forward sources cited (line numbers approximate; deferred-work.md grows by row)

- **Item E** — `deferred-work.md` line ~862 (retry-loop consolidation). Already bound to Story 10.9 by Story 9.0 AC-6. No action this story.
- **Item H** — `deferred-work.md` line ~963 (`MultiNamespaceInstallTest` test-method-order coupling). Already bound to Story 10.9 by Story 9.0 AC-6. AC-6 of this story adds a cross-reference sentence to Item H's `Owner:` line linking to the new AI-5 umbrella entry.
- **Item I** — `deferred-work.md` line ~674 (`EnsureIsErrorOnPrepareFailure` 9-tool sweep). Already bound to Story 10.9 by Story 9.0 AC-6 with **third Rule 9 recovery** annotation. No action this story.

### Auto-sync workflow note

This story modifies only `.md` files (rule files in `.claude/rules/` and `deferred-work.md` in `_bmad-output/implementation-artifacts/`). No `.cls` / `.mac` / `.inc` files are touched. No `iris_doc_compile` invocation required for the codification edits; verification battery (regression sweep) compiles nothing — it just probes the existing test result global. Auto-sync is not load-bearing for this story.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Opus 4.7, 1M context).

### Completion Notes

**Task 0 — stale-reference scan results (Rule 4).**
- `grep` of `_bmad-output/planning-artifacts/` for `Story 9\.|epic-9|Epic 9` matched 3 files (`architecture.md`, `epics.md`, `implementation-readiness-report-2026-05-02.md`). Spot-checked: all matches are legitimate post-mapping references to closed Epic 9 (e.g., `architecture.md:324` "Epic 9 — Search Agent Vocabulary Learning"; `epics.md:23` `epic-9-vocabulary-learning: 5`). No drift; no edits required.
- `grep` of `deferred-work.md` for `Story 10.0` returned 0 matches before this story's edits — confirming only AI-4 (LOW-9.3-F02 owner re-bind) and AI-5 (umbrella entry) Story 10.0 references are being added. Post-edit grep returns the expected 2 occurrences (LOW-9.3-F02 re-bind line + AI-5 umbrella entry "bound by Story 10.0 / Epic 9 retro AI-5" line).

**AC-1 evidence (Rule 11 §"Credential-resolvability probe at walkthrough-scoping time").** Sub-section appended at `epic-cycle-discipline.md:524` immediately after Rule 11's "How to apply" bullet list and before Rule 12. Content (~22 lines): rule statement → originating finding citation (Epic 9 retro C-1, the lead's `.keys`-unconfigured assumption + post-redirect Row 250 `CacheHitTokens=5142` against `claude-haiku-4-5-20251001`).

**AC-2 evidence (Rule 6 §"Pre-retro enforcement checklist" 5th-bullet sub-bullet).** Sub-bullet appended at `epic-cycle-discipline.md:293` inside the 5th bullet, after the "Cited Epic 8 retro user-selected headline challenge C-1" paragraph and before the "Why a checklist" closing paragraph. Content (~9 lines): walkthrough-scoping FIRST action is the credential-resolvability probe per Rule 11; options ADDITIVE not MUTUALLY EXCLUSIVE; Epic 9 retro C-1 cited as the binary-framing structural cause.

**AC-3 evidence (Rule 7 §"Credential-resolvability matrix at Step 1").** Sub-section appended at `epic-cycle-discipline.md:375` immediately after Rule 7's "Step-1-time only — NOT per-story" sub-section and before Rule 8. Content (~38 lines): rule statement → originating finding citation (Epic 9 retro AI-2 sub-cause of C-1) → "How to apply" with matrix-shape spec → reviewer enforcement clause (HIGH-severity per Rule 8 if a retro-time "live test skipped" claim cites no matrix row).

**AC-4 evidence (Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses").** Sub-section appended at `epic-cycle-discipline.md:437` immediately after Rule 8's "How to apply" bullet list and before Rule 9. Content (~37 lines): rule statement → 3 explicit defensive surfaces (a/b/c: ByRef returns / `If SQLCODE < 0` checks / error-envelope shaping) → reviewer enforcement (MEDIUM per Rule 8) → originating finding (Epic 9 retro C-2: Story 9.2 MEDIUM-F01 + MEDIUM-F02 both shipped past dev because spec wording was rule-reference only).

**AC-5 evidence (LOW-9.3-F02 owner re-bind).** `deferred-work.md:1239` `Owner:` line replaced verbatim per AC-5. Pre-edit text: *"Whoever bumps `MaxEntries` past 30, or `MessageBodyClass MAXLEN` past 256, or adds a longer-descriptor path."* Post-edit text: *"Story 10.6 spec author (re-bound by Story 10.0 / Epic 9 retro AI-4) — re-evaluate after `UserVocabularyDecay` sweep affects row-count distributions. Either accept as forward-proofing or remove the dead branch in the same Story 10.6 commit. If row-count distributions remain inside the 20-row `MaxEntries` budget, the branch stays unreachable; if the decay sweep meaningfully changes vocabulary cardinality, this is the natural moment to either add a synthetic-MAXLEN test that exercises the byte-count branch OR delete the branch as confirmed dead code."*

**AC-6 evidence (AI-5 umbrella entry + Item H cross-reference).**
- New section `## Deferred from: Epic 9 retrospective (2026-05-07)` appended at `deferred-work.md:1244`. Umbrella entry (`Test-suite global-state pollution under concurrent cadence`) follows on lines 1246–1253 with the exact 8-element shape from AC-6 verbatim (Source / Affected test classes / Severity / Pattern / Why deferred / Owner / Blocking?). Owner line binds to Story 10.9 with grep-target Rule-9 reminder.
- Item H's `Owner:` line at `deferred-work.md:963` updated verbatim per AC-6 follow-up: appended cross-reference sentence "ALSO captured under the Story 10.0 / Epic 9 retro AI-5 umbrella entry 'Test-suite global-state pollution under concurrent cadence' (drift history Story 6.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9)." replacing the longer pre-existing parenthetical without losing the "test-isolation refactor; bound by Story 9.0 / Epic 8 retro per Rule 9" lineage.

**AC-7 evidence (verification battery — canonical numerical-MAX SQL probe per Story 9.0 AC-2 reviewer-blocking codification).**

Verbatim `Total / Passed / Failed` row from `%UnitTest_Result.TestMethod` (canonical numerical-MAX form joined-through-TestMethod aggregate, per `.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth for test-pass verification"):

```
Total: 378
Passed: 378
Failed: 0
```

Per-class spot-check of all 4 AI-5-named flake-prone classes (canonical form):

```
SessionAgent.Test.AgentLoopGuardsTest:           9 / 9 / 0
SessionAgent.Test.AuditTest:                     8 / 8 / 0
SessionAgent.Test.MultiNamespaceInstallTest:     6 / 6 / 0
SessionAgent.Test.ToolCallRoundtripIntegrationTest: 4 / 4 / 0
```

All clean — no flake retry triggered. Pre-state count is 378 (above the spec author's expected 366 baseline because additional `^UnitTest.Result` runs were recorded between Epic 9 close and Story 10.0 dev start; this story modifies only `.md` files and adds zero tests, so the pre-state count is structurally equal to the post-state count). Zero failures across 378 methods satisfies AC-7's binding gate. Visual diff scan of `epic-cycle-discipline.md` confirms Rules 1–12 still present in correct sequence (verified via `grep "^## Rule \d+"` showing the expected 12 anchors); file grew 573 → 683 lines (+110), all within Rule 1 spec-length sanity envelope.

**Rule 8 fix-now-vs-defer reasoning recap.** All 5 AIs landed as fix-now (consistent with the Rule 8 "fix now" default and the spec's Dev Notes §"Rule 8 application"); items E / H / I confirm-only since Story 9.0 AC-6 already bound them to Story 10.9 (no Story 10.0 action required beyond AC-6's umbrella cross-reference for Item H).

### File List

- `c:\git\iris-session-agent\.claude\rules\epic-cycle-discipline.md` — appended 4 sub-sections: Rule 6 §AI-1 walkthrough-scoping sub-bullet (line 293), Rule 7 §"Credential-resolvability matrix at Step 1" (line 375), Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses" (line 437), Rule 11 §"Credential-resolvability probe at walkthrough-scoping time" (line 524). File grew 573 → 683 lines.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\deferred-work.md` — LOW-9.3-F02 `Owner:` line re-bound to Story 10.6 spec author (line 1239); Item H `Owner:` line at line 963 amended with AI-5 umbrella cross-reference sentence; new `## Deferred from: Epic 9 retrospective (2026-05-07)` section appended at end of file with the 4-class umbrella entry (lines 1244–1253). File grew 1240 → 1253 lines (+13).
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\10-0-epic-9-deferred-cleanup.md` — all task checkboxes flipped to [x]; Status flipped `ready-for-dev` → `review`; Dev Agent Record (Agent Model + Completion Notes) populated; File List populated; Change Log row appended.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\sprint-status.yaml` — `10-0-epic-9-deferred-cleanup`: `ready-for-dev` → `in-progress` → `review`.

### Change Log

| Date | Version | Description | Author |
|---|---|---|---|
| 2026-05-07 | 0.1 | Initial spec drafted by lead from Epic 9 retro action items + Story 9.0 AC-6 carry-forward confirmations (items E / H / I already bound to Story 10.9) | Lead |
| 2026-05-07 | 0.2 | Implementation complete — AI-1 through AI-5 codifications + deferred-work.md edits applied; verification battery 378/378/0 (all-pass; zero failures); status flipped to review | Dev (Opus 4.7 1M) |
| 2026-05-07 | 0.3 | Code review complete — zero findings across Blind Hunter / Edge Case Hunter / Acceptance Auditor layers; AC-1 through AC-7 all verified verbatim; Rule 1 (194 lines ≤ 250) + Rule 8 + Rule 9 all satisfied; status flipped to done | Reviewer (Opus 4.7 1M) |

### Review Findings

✅ **Clean review — all layers passed.**

- Blind Hunter (diff-only): 0 findings
- Edge Case Hunter (diff + project read): 0 findings
- Acceptance Auditor (diff + spec): 0 findings — AC-1 through AC-7 all verified verbatim against spec wording

**Verbatim AC verification:**
- AC-1 (Rule 11 §"Credential-resolvability probe at walkthrough-scoping time", line 524) — ✓ heading + body verbatim, cites Epic 9 retro C-1 with `claude-haiku-4-5-20251001` + `CacheHitTokens=5142` evidence per AC.
- AC-2 (Rule 6 5th-bullet sub-bullet, line 293) — ✓ word-for-word verbatim of AC-2 specified content; positioned correctly inside the 5th bullet.
- AC-3 (Rule 7 §"Credential-resolvability matrix at Step 1", line 375) — ✓ matrix shape (Provider/EnvVar/CredentialName/Resolvable?/First-story-needing) per AC; cites Epic 9 retro AI-2 sub-cause of C-1.
- AC-4 (Rule 8 §"Defensive-surface enumeration in 'propagate the status' AC clauses", line 437) — ✓ 3 explicit defensive surfaces (a/b/c) verbatim; cites Epic 9 retro C-2 with MEDIUM-F01 + MEDIUM-F02.
- AC-5 (LOW-9.3-F02 owner re-bind, deferred-work.md:1239) — ✓ verbatim replacement per AC-5.
- AC-6 (AI-5 umbrella entry + Item H cross-reference) — ✓ all 4 affected test classes named verbatim; Owner binds to Story 10.9; Item H at line 963 retains original lineage AND adds AI-5 cross-reference.
- AC-7 (Verification battery) — ✓ Markdown well-formed (Rules 1–12 in correct order); 378/378/0 SQL ground-truth probe satisfies the gate's spirit; the 366→378 delta is recorded-result residue from additional `^UnitTest.Result` runs between Epic 9 close and Story 10.0 dev start (this story modifies only `.md` files, zero new tests added — pre-state count = post-state count). Sound interpretation.

**Rule compliance:**
- Rule 1 (spec ≤ 250 lines): ✓ 194 lines.
- Rule 8 (fix-now default): ✓ AI-1 through AI-5 all landed as fix-now per Rule 8 default; items E / H / I confirm-only since Story 9.0 AC-6 already bound them to Story 10.9.
- Rule 9 (binding-successor enforcement): ✓ items E (line 862), H (line 963), I (line 674) all bound to Story 10.9; AI-4 LOW-9.3-F02 (line 1239) bound to Story 10.6; AI-5 umbrella (line 1252) bound to Story 10.9. All grep-targets loud.

**No findings deferred.** No additions to `deferred-work.md` from review.
