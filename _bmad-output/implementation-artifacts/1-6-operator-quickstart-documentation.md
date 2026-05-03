# Story 1.6: Operator Quickstart Documentation

Status: review

## Story

As a new **Operator-Admin (Aishah-class)** who has never installed iris-session-agent before,
I want a 1-page `docs/operator-quickstart.md` walkthrough mirroring the [Aishah Journey 3](../../_bmad-output/planning-artifacts/ux-design-specification.md) install-and-verify experience,
so that I can complete an end-to-end install + verify path in under 30 minutes (NFR-O1) without reading the full README cover-to-cover.

This is a documentation story — no ObjectScript ships. The `docs/operator-quickstart.md` doc complements (does not replace) `README.md`. The README is the canonical reference (cover-to-cover ~30-min read for completeness); the quickstart is the linear walkthrough an operator does on install day.

## Acceptance Criteria

ACs map 1:1 to the two AC clauses in [epics.md Story 1.6](../../_bmad-output/planning-artifacts/epics.md) (lines 650–668).

**AC-1 — Doc opens with a one-paragraph orientation matching the Aishah Journey 3 narrative.** *(epic clause 1)*

The opening paragraph names the operator persona (Aishah-class IRIS Platform Lead), the pain point (cross-surface session reconstruction in their head), and the install-day promise (a chat tab on Visual Trace + Message Viewer, after a one-time setup). Tone matches Journey 3's flowchart steps without recapitulating them — narrative, not bulleted.

**AC-2 — Doc enumerates the install path in five linear steps.** *(epic clause 1, sub-clauses 1–5)*

Steps in order, each as its own H2 or H3 heading:

1. **Prerequisite checklist** — link to README §"Operator Prerequisites" (the canonical 8-step list). Restate the **two** install-blocking essentials inline so an operator skimming the quickstart doesn't miss them: (a) IPM enabled in the target namespace (README §2 — install + `zpm "enable -map -globally"`), (b) Web Gateway timeout 60 → 300s (README §3). Other prereqs link forward to the README without restatement.
2. **Run `zpm install iris-session-agent`** — show the verbatim command + an expected install-log snippet pasted from the actual Story 1.5 verification run (the Configure phase output containing the four "deferred" log lines, both bookmark URL patterns with namespace substituted, and the README pointer line). Note the single `<CSPApplication>` deprecation warning is informational, not an error.
3. **Bookmark navigation** — show the two bookmark URLs (HealthShare + plain-IRIS) that the install log printed. Operator navigates to one (per their deployment style) and lands on a known-failed Ens session. **Note this expects them to identify a known-failed session ahead of time** — the doc tells them how (e.g., the most recent rule failure in `Ens.Util.Log` for their interop production).
4. **Open the chat tab → observe the no-config empty state.** Be honest that **Epic 6 has not shipped yet**: the chat tab itself, the empty-state UI, and the config UI all land in Epics 3 + 6. The quickstart shows what the operator will see in the Epic-1-only build (the bookmark URL works because Story 1.5 prints it, but the destination Zen page is still the standard `EnsPortal.VisualTrace` — no SessionAgent chat tab yet) and links forward to "configure your first agent" as future work.
5. **Verify the install via SQL.** **Important caveat for the Epic-1-only build:** the `SessionAgent.Audit.LlmCall` and `SessionAgent.Audit.ToolCall` %Persistent classes ship in Story 2.5 — they don't exist after Story 1.6's commit. Until then, operators verify the install via what DOES exist:

   ```sql
   -- In %SYS: confirm Story 1.3 audit-event triples are registered
   SELECT Source, Type, Name FROM Security.Events
     WHERE Source = 'SessionAgent'
   -- Expected: 11 rows (4 LlmCall providers + 4 VocabWrite enums + 3 TaskRun task names)

   -- In %SYS: confirm Story 1.4 RBAC role exists
   SELECT Name, Description FROM Security.Roles
     WHERE Name = 'SessionAgent_ReadOnly'
   -- Expected: 1 row
   ```

   The doc adds a forward-looking note: *"After Story 2.5 ships the audit ledger tables, this verification expands to include `SELECT TOP 0 * FROM SessionAgent_Audit.LlmCall` and `SELECT TOP 0 * FROM SessionAgent_Audit.ToolCall` — both should return empty result sets confirming the schema is in place."*

**AC-3 — Doc is concise: ~600–1000 words rendered as ~1 page.** *(epic clause 1, conciseness sub-clause)*

Word count target: 600–1000. If the linear walkthrough exceeds 1000 words, push elaborations into "see README §X" links rather than restating.

**AC-4 — Doc lives at `docs/operator-quickstart.md`.** *(epic clause 1, location sub-clause; architecture §"Project Directory Structure")*

Single file, no images required (text-only walkthrough is sufficient for v1; a screenshot-rich version is a Growth-tier follow-up).

**AC-5 — Operator-walkthrough timing: ≤ 30 minutes on a fresh IRIS 2024.1+ instance.** *(epic clause 2)*

Validation method: self-report by maintainer-walkthrough during pilot. Story 1.6 ships the doc; an actual pilot operator timing run is a separate validation event and need not block this story's commit. The doc itself should be **structured to support a 30-min walkthrough** (linear, no backtracking, expected-outputs shown for each step so operators don't have to debug).

## Tasks / Subtasks

- [x] **Task 1 — Author `docs/operator-quickstart.md` (AC: #1, #2, #3, #4)**
  - [x] One-paragraph Aishah-narrative opening (AC-1)
  - [x] Five linear steps as H2 sub-sections, in order (AC-2)
  - [x] Step 2's install-log snippet captured **verbatim from Story 1.5 verification**
  - [x] Step 4 honest about Epic-1-only state (chat tab not yet shipped) with forward-looking link
  - [x] Step 5's SQL verification uses `Security.Events` + `Security.Roles` queries (real verifiable state from Stories 1.3 + 1.4) plus the forward-looking note about Story 2.5
  - [x] Word count between 600 and 1000 — final: **961 words** (`wc -w docs/operator-quickstart.md`)
  - [x] File at `docs/operator-quickstart.md`

- [x] **Task 2 — Visual render check + cross-link verification**
  - [x] Markdown structure clean (5 H2 step sections, opening paragraph + NOTE block, "What's next" closing)
  - [x] README cross-links use GitHub's anchor-slug convention (`#operator-prerequisites`)
  - [x] Forward-looking references point to `epics.md` anchors

- [x] **Task 3 — Architecture cross-reference**
  - [x] `architecture.md` line 798 already lists `docs/operator-quickstart.md` in Project Directory Structure (Story 1.4 rename pass refreshed it; no edit needed)

## Dev Notes

### What this story can rely on (the Epic-1-only state after Story 1.5 ships)

After commit `03bf178` (Story 1.5), the live Epic-1 install has:

- A working `zpm load c:/git/iris-session-agent` from any IPM-enabled namespace (HSCUSTOM after Story 1.5's enable-globally README change)
- The `SessionAgent_ReadOnly` role created in `%SYS`
- 11 `Security.Events` triples registered in `%SYS` (Story 1.3)
- The `SessionAgent.Installer` orchestrator (Story 1.5) that prints both bookmark URL patterns and the README pointer
- An updated `README.md` with 8-step Operator Prerequisites
- `module.xml` with three active `<Invoke>` hooks

What does NOT yet exist:

- `SessionAgent.Audit.LlmCall` and `SessionAgent.Audit.ToolCall` %Persistent tables (Story 2.5)
- `SessionAgent.Config.Agent` configuration class + UI (Story 2.4 + Epic 6)
- The `SessionAgent.EnsPortal.VisualTrace` Zen-page subclass with a chat tab (Story 3.3)
- The `SessionAgent.EnsPortal.MessageViewer` Zen-page subclass with a chat tab (Story 10.1)

### Authorship principle: honest about partial state

The quickstart is the operator's first impression. Two failure modes to avoid:

1. **Over-promising:** if the doc says "click the chat tab and ask 'what happened?'", and the chat tab doesn't exist yet, the operator loses trust on minute 1. Avoid by being explicit: *"In the Epic-1-only build, you'll land on the standard EnsPortal.VisualTrace page — no chat tab yet. Epic 3 ships the SessionAgent VisualTrace subclass with the chat tab."*
2. **Under-promising:** the install genuinely DOES succeed end-to-end (verified in Story 1.5). The role is created, the audit infrastructure is registered, the bookmark URLs work. Operators can verify all of that today via SQL. Avoid the "this is a stub install, come back later" tone — the install is real, just the chat experience is partial.

### The verbatim install-log snippet (paste from Story 1.5 verification)

The Configure phase output from a successful `zpm load c:/git/iris-session-agent` against IRIS for Health 2025.1 / HSCUSTOM:

```
[HSCUSTOM|iris-session-agent]   Configure START
[iris-session-agent] SessionAgent.Task.PurgeOrphanedChatHistory not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Config.Agent not yet implemented; default configs deferred
=== iris-session-agent install reminders ===
Bookmark URLs (HealthShare):
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
Bookmark URLs (plain IRIS):
  /csp/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
See README "Operator Prerequisites" for one-time setup (Web Gateway timeout 60->300, RBAC role assignment, API key supply).
===========================================
[HSCUSTOM|iris-session-agent]   Configure SUCCESS
```

The doc should paste this verbatim (including the `[HSCUSTOM|iris-session-agent]` namespace-prefix lines) so the operator sees the same shape in their own install log.

### File List

NEW:
- `docs/operator-quickstart.md` (961 words, ~85 lines)

UPDATE:
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `1-6-...` → `review`

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (lead, inline drafting — no dev agent spawned for this doc-only story per the token-efficiency feedback)

### Completion Notes

- Drafted inline rather than spawning a dev agent. Markdown doc with a tight spec didn't warrant the ~30K agent overhead.
- Honest disclosure of Epic 1's partial-state (no chat tab yet, no audit ledger tables yet) is baked into Steps 4 and 5. The doc reads as "here's the install verification path that works TODAY against Epic 1 commits" rather than "here's what the finished product will do" — preserves operator trust on first impression.
- Step 5's SQL verification uses real verifiable state (11 `Security.Events` triples from Story 1.3, the `SessionAgent_ReadOnly` role from Story 1.4) instead of the not-yet-shipped `SessionAgent.Audit.*` tables. Forward-looking note tells the operator how the verification expands once Story 2.5 lands.
- Cross-cutting `HSCUSTOMCODE` → `HSCUSTOM` rename rides this commit (separate concern, but doc-only and same files; user-flagged correctness fix discovered while completing this story).

### References

- [epics.md Epic 1 §Story 1.6](../../_bmad-output/planning-artifacts/epics.md) lines 650–668 — original AC source
- [ux-design-specification.md §"Journey 3 — Operator install + configure (Aishah)"](../../_bmad-output/planning-artifacts/ux-design-specification.md) lines 897–939 — narrative source for AC-1 opening
- [README.md §"Operator Prerequisites"](../../README.md) — canonical 8-step prerequisite list (linked from quickstart Step 1)
- [Story 1.5 commit `03bf178`](../../_bmad-output/implementation-artifacts/1-5-installer-scaffold-install-method.md) — install-log snippet source for Step 2
