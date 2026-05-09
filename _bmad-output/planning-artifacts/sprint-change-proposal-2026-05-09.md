# Sprint Change Proposal — 2026-05-09

**Triggered by:** Post-Epic-12 demo walkthrough on 2026-05-09 (`_bmad-output/implementation-artifacts/demo-2026-05-09-walkthrough.md`). The Inspection Agent investigated session 80562 across 4 tool calls and was correct that *"the full source code is needed to see the exact routing logic"* — surfacing a real gap in the inspection tool catalog. Project lead's follow-up scoping conversation surfaced 4 more adjacent gaps in the same "what does this configured thing actually do" category, plus 1 cross-session search gap.

**Mode:** Batch (full proposal + Epic 13 spec + 6-story breakdown in one document).

**Scope classification:** **Moderate** — opens new Epic 13, adds 6 new stories, expands `epics.md` with the full Epic 13 section, expands `sprint-status.yaml`. **No PRD / architecture / UX-spec edits required.** Pure additive surface — tool-registry expansion within the existing FR59 contract. No backwards-incompat changes, no NFR shifts, no architectural decisions overturned.

**Source-of-truth artifact:** `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` (already drafted; 303 lines; per-tool design including IRIS API + arguments + response shape + LOC estimate + project-rule compliance). Each Story 13.x spec will cite this artifact as its source of truth — same pattern Epic 12 used with `walkthrough-bugs-2026-05-08.md`.

---

## Section 1 — Issue Summary

The 2026-05-09 live demo against the sample interop production exercised both agents end-to-end: Search Agent found the failed sessions, click-through navigated cleanly, Inspection Agent diagnosed the root cause via 4 tool calls (`event_log` + `get_business_process_instance` + `get_business_process_source` + a follow-up `event_log`). The investigation produced a structurally correct answer ("two BOs raised injected `<Ens>ErrGeneral` exceptions on OrderId ORD-000239") and the LLM correctly self-reported its remaining limitation: *"the full source code is needed to see the exact routing logic. Would you like me to retrieve the full source code?"*

That self-report wasn't a hedge — it was an accurate statement of what the existing tool catalog can NOT return. `get_business_process_source` returns class-level structure (signatures, properties, parameters, `has_body` flags) but not method bodies. The agent was correct to stop and ask rather than hallucinate.

The follow-up conversation with the project lead surfaced four more adjacent gaps in the "what does this configured thing actually do" pattern:
- Rule logic (`Ens.Rule.Log` shows what fired, but not the rule's constraint/action source)
- Production config-item settings (operator wants to know "what file path is FilePublish writing to?" — currently no path)
- Queue state (operator wants to know "is this session stuck waiting on a queue?")

Plus one cross-session question that's separate but adjacent: *"where else has this class been used recently?"* — useful for impact assessment when a problem class is identified.

These are all real read-only ObjectScript surfaces that have stable IRIS APIs (`%Atelier.v1.Utils.TextServices`, `%Dictionary.XDataDefinition`, `Ens.Config.Item`, `Ens.Queue`, indexed `Ens.MessageHeader` columns). The five tools that close these gaps are scoped per-tool in the source-of-truth artifact with full IRIS API + argument + response-shape detail.

---

## Section 2 — Impact Analysis

### Epic Impact

| Epic | Current state | After this proposal |
|---|---|---|
| Epic 12 (Walkthrough Hardening) | 8 stories, all `done`. Retrospective `done`. | No change. |
| Epic 13 (NEW — Tool Catalog Expansion) | Does not exist. | 6 new stories, expanding the inspection catalog by 4 tools (13 → 17) and the search catalog by 1 tool (10 → 11). Total catalog: 23 → 28. |

### Story Impact

6 new stories under Epic 13. Each tool ships as its own story (no bundling) because each is independent — different IRIS API, different test surface, different agent registration; reviewer benefits from per-tool partition.

| Story | Tool | Family | LOC est. (impl + tests) | Dependencies |
|---|---|---|---|---|
| **13.0** | Epic 12 deferred cleanup + Epic 13 setup | (audit trail) | docs only | Rule 7 sprint-planning gate |
| **13.1** | `get_class_source` | Inspection | ~80 + 50 | Builds Test.Util.RegressionSweepCount helper (per Carry-Forward; reused by 13.2–13.5) |
| **13.2** | `get_rule_source` | Inspection | ~60 + 40 | (none) |
| **13.3** | `get_production_config_item` | Inspection | ~80 + 40 | (none) |
| **13.4** | `get_queue_state` | Inspection | ~40 + 30 | (none) |
| **13.5** | `find_sessions_using_class` | **Search** (not Inspection) | ~80 + 50 | (none) |

**Why 13.5 is a Search tool.** Tools 13.1–13.4 operate on a single surface (a class, a rule, a config item, a queue) — Inspection Agent territory. Tool 13.5 walks across `Ens.MessageHeader` to find sessions that touched a given class — that's the Search Agent's job (cross-session indexed scan with bounded WHERE invariant per Rule 6 step 4 / FR59). Lives in `src/SessionAgent/Tool/Search/`, registers with the `message-search` agent.

**Recommended ordering:**
13.0 → 13.4 (smallest tool, validates the "add a new Inspection tool" path without LOC baggage) → 13.2 (small, pairs naturally with `rule_log`) → 13.1 (originally-motivating tool; biggest LOC of the inspection set; builds the regression-sweep helper) → 13.3 (config-item — different table set, exercises `Ens.Config.*` SQL family) → 13.5 (Search tool, exercises the Search-tool-add path; saved for last so any patterns from 13.1–13.4 inform the Search variant).

### Artifact Conflicts

| Artifact | Edit |
|---|---|
| `epics.md` | Append a new `## Epic 13` section. Add Epic 13 to the "Post-v1.0.0 maintenance epics" subsection alongside Epic 11 and Epic 12. Add the 6 story sub-headers (Story 13.0 — Story 13.5). Estimated ~80 new lines (smaller than Epic 12's section because per-tool detail lives in the source-of-truth artifact, not in epics.md). |
| `sprint-status.yaml` | Insert 8 new lines after Epic 12's block: `epic-13: backlog` + 6 story entries + `epic-13-retrospective: optional`. |
| `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md` | No edit. Pre-existing source-of-truth artifact for Story 13.x specs to cite. |
| `_bmad-output/implementation-artifacts/deferred-work.md` | Story 13.0 will scan during its triage phase per Rule 7 / Rule 9. |
| `prd.md` | **No edit.** None of the 5 tools touch FR/NFR statements. The tool catalog is operational scope inside the existing FR59 cross-matrix gate; expansion within that contract doesn't change the contract. |
| `architecture.md` | **No edit.** All 5 tools follow the existing `Tool.Base` extension pattern. No new architectural decisions; no shared-infrastructure edits. |
| `ux-design-specification.md` | **No edit.** Tool results render through the existing `sa-tool-call-card` component shape (UX-DR2). No new UX-DRs needed. |
| `README.md` | **No edit at proposal time.** At Epic 13 retro time the maintainer may bump the "23 tools" callout in the v1.0.0 scope-complete summary table to "28 tools"; that's a one-line edit and doesn't need to land in this proposal commit. |

### Technical Impact

- **No breaking changes.** All 5 tools are additive — new files only (1 tool class + 1 test class per tool), no edits to existing tool classes. v1.0.2 install paths continue to work unchanged.
- **No new external dependencies.** All 5 tools call existing IRIS APIs (`%Atelier.v1.Utils.TextServices`, `%Dictionary.XDataDefinition`, `Ens.Config.Production` / `Ens.Config.Item` / `Ens.Config.Setting`, `Ens.Queue`, `Ens.MessageHeader`). RBAC role `SessionAgent_ReadOnly` already grants SELECT on all these tables.
- **FR59 cross-matrix gate growth:** 23 × 4 = 92 → 28 × 4 = **112 combinations**. Each new tool adds 4 cross-provider combinations to the live-test sweep. Test class additions are mechanical: each new tool ships its own `*Test.cls` with ≥3 methods (positive / negative class-not-found / edge case).
- **Test surface growth:** ≈ 30 new test methods across Epic 13 (5 tools × 3 methods each + helper-class tests + integration coverage). Final regression sweep target: ≈491 (461 baseline + ~30 new).
- **Token-budget discipline:** every tool returns a `render_strategy` field (existing convention) so the LLM can branch its narrative without re-parsing. Tools 13.1 and 13.5 ship truncation guards (large class source / large session-list result).
- **SQL injection guards:** tools 13.1, 13.2, 13.3, 13.5 accept class-name strings that go into `%OpenId` / regex / SQL WHERE. Each tool validates against `^[A-Za-z%][A-Za-z0-9%._]*$` server-side before use, mirrors Story 12.5's 4-layer defense pattern.
- **Story 12.2 anti-method-suffix description warning** required on every `class_name` / `rule_class` / `production_name` argument description (4 of the 5 tools).
- **Story 12.2 strip-last-segment fallback** required on tools 13.1, 13.2, 13.3, 13.5 (all class-name acceptors).

---

## Section 3 — Recommended Approach

**Direct adjustment** — open Epic 13, run `/epic-cycle 13`. Pure additive surface; no rollback or replan needed.

**Rationale:**
1. **No bug surface.** Epic 13 is feature expansion, not bug fixing. The 5 tools close gaps surfaced by the demo + scoping conversation, not by reported defects.
2. **All scoping done up-front.** The `tool-catalog-expansion-2026-05-09.md` source-of-truth artifact has per-tool IRIS API, arguments, response shape, truncation guards, and project-rule compliance. Dev agents inherit the analysis directly — no spec-time investigation drift, no rediscovery cost across 6 stories.
3. **Pattern proven on Epic 12.** Walkthrough → scoping doc → Sprint Change Proposal → `/epic-cycle` worked end-to-end with no scope creep. Same shape here.
4. **Minimal blast radius per story.** Each tool is one new file + one new test file, registered in `Tool.Registry`. No cross-tool dependencies (the only inter-story dependency is the Test.Util helper that 13.1 builds and 13.2-13.5 reuse — cleanly bound per Carry-Forward).

**Risk assessment:**
- **LOW risk on all 5 tools.** Each follows an established pattern (`Tool.Base` subclass, `Invoke` + `GetInputSchema`, `Tool.Registry` registration). No novel ObjectScript techniques required.
- **MEDIUM risk on 13.1 (`get_class_source`)** — only because of the regex-based method-body extraction when the LLM passes a `method_name` filter. Brace-matching needs to handle nested `{ }` correctly. Fallback: when regex extraction fails, return full class source + warn that filter was unable to isolate the method. Reviewer should specifically pressure-test the regex against generated/abstract methods.
- **LOW risk on 13.5 (`find_sessions_using_class`)** — bounded-WHERE invariant + indexed columns make the SQL fast and predictable. Reuses Story 12.5's SQL-injection-guard pattern.

**Recommended ordering** (per scoping doc — bottom-up by risk):
- 13.0 → 13.4 → 13.2 → 13.1 → 13.3 → 13.5

---

## Section 4 — Detailed Change Proposals

### Change 1: Add Epic 13 to `epics.md`

**Location:** Append after Epic 12 section (currently end of file). Add Epic 13 to the "Post-v1.0.0 maintenance epics" subsection.

**New section content:**

```markdown
### Epic 13: Tool Catalog Expansion

**Operator outcome:** Five new agent-introspection tools that close gaps surfaced by the 2026-05-09 demo and the lead's scoping conversation. The Inspection Agent gains source-introspection (full UDL class source + rule source + production config-item settings + queue state); the Search Agent gains cross-session class-usage discovery. Tool catalog grows from 23 to 28 (FR59 cross-matrix gate from 92 to 112 combinations).

Source-of-truth artifact: `_bmad-output/implementation-artifacts/tool-catalog-expansion-2026-05-09.md`.

**Stories:** 6 (13.0 setup + 5 tool-add stories).

**No PRD / architecture / UX-spec edits.** Pure additive surface within the existing tool-registry pattern.
```

Per-story sub-sections drafted at `/bmad-create-story` time (Step 4a of `/epic-cycle 13`), per Rule 1 ≤ 250 lines per spec.

### Change 2: Add Epic 13 entries to `sprint-status.yaml`

**Location:** After the existing Epic 12 block (line 173 `epic-12-retrospective: done`).

**New entries:**

```yaml
  epic-13: backlog
  13-0-epic-12-deferred-cleanup: backlog
  13-1-get-class-source-tool: backlog
  13-2-get-rule-source-tool: backlog
  13-3-get-production-config-item-tool: backlog
  13-4-get-queue-state-tool: backlog
  13-5-find-sessions-using-class-tool: backlog
  epic-13-retrospective: optional
```

### Change 3: Story specs (drafted at `/epic-cycle 13` time, not at proposal time)

Per project workflow, individual story specs are drafted by the lead during `/epic-cycle` Step 4a (`/bmad-create-story` Skill invocation), NOT at sprint-change-proposal time. The proposal commits to the 6-story shape; story-spec drafting follows.

For each story, the spec template will include:
- AC enumeration with citation back to `tool-catalog-expansion-2026-05-09.md` per-tool detail
- Task 0 backend-surface probe (verify the IRIS API works on the live IRIS dev install)
- Tasks/Subtasks with explicit verbatim-AC-contract evidence shapes (per Rule 2 sharpened)
- Dev Notes: Story 12.2 anti-method-suffix description warning + strip-last-segment fallback + `$Char(0)` sentinel + 4-layer SQL injection defense (per Rule 8 / 9 / 12)
- Patterns to follow verbatim section pointing at existing tool classes
- Spec length target ≤ 250 lines per Rule 1

### Change 4: No edits to `prd.md`, `architecture.md`, `ux-design-specification.md`, or `README.md`

Confirmed: zero conflicts. README's "23 tools" callout edit deferred to Epic 13 retro time as a one-line bump (not blocking).

---

## Section 5 — Implementation Handoff

**Scope classification:** **Moderate** — backlog reorganization (new epic, 8 new tracking entries) but no fundamental replan. No PM/Architect involvement required. Ready for direct dev execution via the existing `/epic-cycle 13` pipeline.

**Recipients:**
- **Project Lead** — confirms approval, then invokes `/epic-cycle 13` (or defers per personal cadence) to drive the 6 stories through the standard pipeline.
- **Developer agents** (spawned per `/epic-cycle 13` Step 4 — one per story) — implement against the drafted specs.
- **Code-Review agents** (spawned per `/epic-cycle 13` Step 4c — one per story) — review against `.claude/rules/*.md`.

**Deliverables produced by this proposal:**
- This document (`sprint-change-proposal-2026-05-09.md`).
- Approval signal from project lead (next message).
- On approval: `epics.md` + `sprint-status.yaml` edits land in a single commit (the proposal commit). Epic 13 is then `backlog` and ready for `/epic-cycle 13`.

**Success criteria for Epic 13:**
- All 6 stories ship `done`.
- Tool catalog grows to 28 entries verifiable via `iris_execute_classmethod Tool.Registry:ListTools`.
- FR59 cross-matrix gate runs clean against 112 combinations (or skips per credential resolvability per Rule 11).
- Each new tool has its own test class; regression sweep clean (≈491 expected — 461 baseline + ~30 new).
- Live-agent demo turn (Rule 6 step 4): ask the Inspection Agent the 2026-05-09 demo's follow-up question — *"What does the OrderRouter rule say, and where is FilePublish writing files to?"* — exercises 13.2 + 13.3 in one turn against real sample-prod data.
- No regression on v1.0.2 functionality (Stories 12.0-12.7 still work; sample-prod walkthrough still produces clean turns).

**Pre-flight before invoking `/epic-cycle 13`:**
- Confirm sample interop production is running (per Rule 7 §"Sample production state at Epic-cycle Step 1") — already running from the 2026-05-09 demo.
- Confirm credential resolvability matrix (per Rule 7 §"Credential-resolvability matrix at Step 1") — `SessionAgentOpenAI` already configured for both agents post-demo remediation.
- Confirm no in-flight uncommitted work in the repo.

**Story 13.0 triage notes (Rule 7 sprint-planning gate carry-forward):**

Per Epic 12 retrospective (`epic-12-retro-2026-05-08.md`), 5 action items captured:

| AI | Action | Triage for Epic 13 | Successor |
|---|---|---|---|
| **AI-1** | Codify "SQL injection 4-layer defense" pattern as project rule | **INCLUDE** as Carry-Forward to Story 13.5 (only Epic 13 tool with SQL string-concat surface) | Story 13.5 |
| **AI-2** | Bake canonical numerical-MAX SQL probe into reusable Test.Util helper | **INCLUDE** as Carry-Forward to Story 13.1 (first dev story; helper pays off across 13.2-13.5) | Story 13.1 |
| **AI-3** | File AgentConfig credCombo Zen widget propagation bug | **DEFER to v3** — not Epic 13 scope. Recurrence-evidence-confirmed during 2026-05-09 demo (operator-side credential-fix worked but the underlying Zen widget gap is real). | v3 / future bug-investigation walkthrough |
| **AI-4** | Sharpen Rule 6 §"Pre-retro enforcement checklist" wording | **DEFER to v3** — meta-rule update, lands at next-retro time | v3 |
| **AI-5** | Tighten substring-grep test pattern for multi-reference shapes | **INCLUDE** as Carry-Forward to Stories 13.1-13.5 (any story using substring-based source-introspection assertions should follow the strip-and-grep precise-check pattern) | Stories 13.1-13.5 |

LOW deferrals from Epic 12 (11 entries): all DEFER — story-specific cosmetic items, not Epic 13 surface.

---

## Approval

**Project Lead:** please review and respond with one of:
- `yes` — I commit `epics.md` + `sprint-status.yaml` edits in a single commit, and Epic 13 is then ready for `/epic-cycle 13`.
- `revise` (with specifics) — I'll iterate this proposal.
- `no` — I'll close the proposal and re-open the conversation.
