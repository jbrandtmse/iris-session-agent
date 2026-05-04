# Sprint Change Proposal — 2026-05-03

**Triggered by:** Epic 3 Story 3.7 lead-driven walkthrough (chrome-devtools-mcp). The walkthrough surfaced four scope-relevant findings that the project lead reviewed and approved for in-cycle scope expansion before closing Epic 3 + running the retrospective.

**Mode:** Batch (full proposal, all change items together). Pre-aligned with project lead in the planning conversation that preceded `/bmad-correct-course`.

**Scope classification:** **Moderate** — three new stories spanning two epics (Epic 3 + Epic 6); both epic story lists expand; sprint-status.yaml grows; no architectural decisions overturned; no MVP exit-criteria language change.

---

## Section 1 — Issue Summary

The Story 3.7 walkthrough exercised the chat panel against the dev install over six turns. Four findings emerged that warrant scope expansion before Epic 3 closes:

1. **Cross-session warning is currently advisory-only.** Story 3.5 AC-6's binding-sentence injection in `AgentLoop.RunTurn` includes the language *"unless the operator explicitly asks about a different session."* The Story 3.7 fix-now extended this to a `MUST mention in your response that you are reaching outside the bound session` instruction. Empirical Turn 5 (operator typed *"Show me what's in session 2"*) showed the LLM **ignored the instruction** — likely because 9 prior "session 1" turns of context dominated the system-prompt. The cross-session dispatch worked (per the soft-scope policy chosen), but the operator-facing disclosure failed. System-prompt-only enforcement is unreliable; programmatic enforcement is needed.

2. **Visual differentiation between operator + agent turns** (Story 3.7 lead's screenshot finding). UX-design-spec line 776 specified `**You** —` / `**Agent** —` attribution prefixes + subtle background-tint difference. Tokens existed in `UI/ChatPanel.cls` (Story 3.1) but the corresponding `.sa-msg-operator` / `.sa-msg-agent` rules were never written. **Resolved in-flight in Story 3.7 commit `e3741aa`** — confirmed visually after browser refresh. **No new story needed.**

3. **No comprehensive sample interoperability solution exists for testing.** The dev install has 4 sessions / 0 errors — insufficient richness to exercise the agent's full capability surface. PRD MVP Exit Criterion #2's "real diagnosis" portion is structurally blocked. A purpose-built sample production (Business Service + Business Processes + Business Operations, adapterless, scenario-driven, error-injection-capable) would supply the empirical substrate Stories 3.7 (and Epic 4's Story 4.7 comprehensive read-only suite) need. Justification: the agent demo is only as compelling as the sessions it inspects.

4. **Multi-namespace install is undocumented.** Today's `Installer.Install()` runs against the caller's `$NAMESPACE` (defaulting to HSCUSTOM when invoked from `%SYS`). Operators with multiple interop namespaces have no documented per-namespace install path. `Config.Agent` rows are namespace-local (per-NS data), but the package-mapping + ChatPanelAsset cls availability is per-NS too. Worth scoping now even if execution waits.

---

## Section 2 — Impact Analysis

### Epic Impact

| Epic | Current state | After this proposal |
|---|---|---|
| Epic 3 | 8 stories (3.0–3.7), all `done`. Awaiting retro. | 10 stories. Adds Story 3.8 (cross-session warning) + Story 3.9 (sample production + walkthrough re-run). Both insert between Story 3.7 and `epic-3-retrospective`. |
| Epic 6 | 3 stories (6.1–6.3), all `backlog`. | 4 stories. Adds Story 6.4 (multi-namespace install support). Inserts between Story 6.3 and `epic-6-retrospective`. |

### Story Impact

- **Story 3.7** (already `done`): no edits to the story file. The deferred-work entry it logged (cross-session disclosure) gets its named successor (Story 3.8) under Rule 9 binding.
- **Story 3.8** (NEW): Server-side AgentLoop notice; +1 unit test. Spec ~100 lines (small).
- **Story 3.9** (NEW): Sample interop production — adapterless BS + ≥2 BPs + ≥2 BOs + scenario method + walkthrough re-run as AC. Spec ~200–250 lines.
- **Story 6.4** (NEW): `Installer.InstallIntoNamespace(pNamespace)` + per-NS package-mapping verification + README operator-walkthrough. Spec ~120 lines.

### Artifact Conflicts

- **`epics.md`** — append Story 3.8 + 3.9 sections under Epic 3; append Story 6.4 under Epic 6. Update each epic's "Stories (in order)" enumeration.
- **`sprint-status.yaml`** — insert 3 new entries.
- **`deferred-work.md`** — tag the Story 3.7 cross-session-disclosure entry as `[CARRIED-FORWARD-TO Story 3.8]` (Rule 9 binding).
- **`prd.md`** — no edit needed. MVP exit-criteria language unchanged. Story 3.9 strengthens the empirical substrate for Exit Criterion #2 but doesn't change the gate.
- **`architecture.md`** — no edit needed. Sample production is a test fixture, not architectural runtime. Multi-namespace install is an installer extension, not an architectural change.
- **UX-design-spec** — no edit needed.

### Technical Impact

- **Story 3.8**: ~10 lines of ObjectScript in `AgentLoop.RunTurn` after the tool-dispatch loop. ~50 lines of test code. No new classes.
- **Story 3.9**: New `SessionAgent.Sample.*` package — likely 5–8 new `.cls` files (BS, BPs, BOs, request/response message classes, bootstrap helper). Excluded from `module.xml` `<Resource>` (operator-invoked install). Test coverage = the walkthrough re-run + a per-class compile sweep.
- **Story 6.4**: ~30 lines of ObjectScript in `Installer.cls` (new ClassMethod). README operator-walkthrough section.
- **No backwards-incompat changes**. No prior story's commits need amending. No production-class signatures change.

---

## Section 3 — Recommended Approach

**Direct Adjustment** — add 3 new stories within the existing plan. No rollback. No MVP scope reduction.

**Rationale:**
- Item 1 (cross-session warning) closes a Rule 9 binding deferral logged 30 minutes ago by Story 3.7. Naturally belongs in Epic 3's close-out, not Epic 4+. Small (~100-line spec, ~30-line implementation). Avoids letting the deferred-work entry decay across multiple epics.
- Item 2 (visual differentiation) shipped in Story 3.7 commit `e3741aa`. Already done; no new story needed.
- Item 3 (sample production) is a meaningful one-time investment that pays dividends for Epic 4's Story 4.7 ("comprehensive read-only suite verification" — currently has no rich data substrate to verify against). Doing it now in Epic 3 — adjacent to the chat-panel work + the project lead's freshest pilot-walkthrough memory — is more efficient than deferring to Epic 4 or later.
- Item 4 (multi-namespace install) is genuinely later-epic scope. Per-agent config UI (Epic 6) is the natural home: an operator who spans namespaces will likely also be the operator-admin configuring per-namespace agent settings. The two stories share an audience.

**Effort estimate:**
- Story 3.8: 1 dev/cr/commit cycle, ~30 min.
- Story 3.9: 1–2 dev/cr/commit cycles, ~60–90 min (sample production scaffolding is meaty).
- Story 6.4: deferred to Epic 6 execution. Scoped now; not implemented now.

**Risk:**
- Story 3.9 is the largest scope add. Risk is spec-length overrun (Rule 1 ≤250 line cap). Mitigation: Dev Notes brevity; separate scaffolding-only spec from walkthrough-re-run AC if it overflows.
- Multi-namespace (Story 6.4) deferral risk: per-NS `Config.Agent` semantics may surface unexpected coupling in Epic 4–5 work. Mitigation: explicit architectural decision documented in Story 6.4 spec (per-NS rows vs global table with namespace column).

**Timeline impact:** Minimal. Epic 3 retrospective deferred by ~2 hours (Stories 3.8 + 3.9 commit → battery re-run → retro). Epic 6 expands by ~30–60 min when it executes (months from now in this hobby-project cadence).

---

## Section 4 — Detailed Change Proposals

### Change 4.1 — `epics.md` Epic 3 story list update

**Section:** Epic 3 "Stories (in order)" enumeration (lines 1104–1112).

**OLD:**
```
**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 3.1**: Chat Panel HTML Draw Helper + Minimum CSS Tokens (...)
2. **Story 3.2**: Client-Side `chat-panel.js` MVP (...)
3. **Story 3.3**: `SessionAgent.EnsPortal.VisualTrace` subclass (...)
4. **Story 3.4**: Citation chips with parent `selectItem`/`updateTabs` integration (...)
5. **Story 3.5**: Empty states + config-empty prompt (...) + provider-error envelopes
6. **Story 3.6**: Cross-Browser Smoke Test + Accessibility Inheritance Verification
7. **Story 3.7**: PRD MVP Exit Criteria Validation — Pilot Operator Walkthrough on a Real Failed Session
```

**NEW:** Same list with two additions:
```
7. **Story 3.7**: PRD MVP Exit Criteria Validation — Pilot Operator Walkthrough on a Real Failed Session
8. **Story 3.8**: Programmatic Cross-Session Disclosure — server-side `AgentLoop` notice when tool args contain `session_id` ≠ `pSessionKey` (closes Story 3.7 deferred-work binding entry per Rule 9)
9. **Story 3.9**: Sample Interoperability Production + Walkthrough Re-Run on Rich Data (`SessionAgent.Sample.*` package — adapterless BS + ≥2 BPs + ≥2 BOs + scenario method with success/error injection; rich message bodies; not installed via IPM `<Resource>`; closes the partial portion of PRD MVP Exit Criterion #2)
```

**Rationale:** Adds the two new in-epic stories. Preserves existing numbering. Documents Story 3.8's binding closure of Story 3.7's deferred-work entry per Rule 9.

### Change 4.2 — `epics.md` Story 3.8 NEW section

**Section:** Insert after the existing Story 3.7 section.

**NEW (full new section):**

```markdown
### Story 3.8: Programmatic Cross-Session Disclosure

As an Operator who may legitimately ask the agent to compare details between sessions,
I want any cross-session tool dispatch (where `tool_args.session_id ≠ chat_tab.bound_session_id`) to produce a deterministic operator-facing notice in the agent's final response — even when the LLM forgets to disclose the cross-session reach itself,
So that I always see when the agent has reached outside the bound session, and the audit ledger + the in-turn UI agree on the scope of the dispatch.

This closes the Story 3.7 lead-driven walkthrough's deferred-work entry binding cross-session-disclosure programmatic enforcement to a future story (Rule 9 — see `deferred-work.md` §"Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03) — system-prompt-only cross-session disclosure unreliable").

**Acceptance Criteria:**

**Given** the developer is implementing the cross-session detection in `Agent.AgentLoop.RunTurn`
**When** the iteration loop processes a tool's `args` after dispatch
**Then** the loop inspects `args` for a `session_id` value (when present)
**And** if the value differs from `pSessionKey`, the loop appends to a per-turn `tCrossSessionList` ($listbuild of distinct session-ids reached outside scope)
**And** the inspection handles missing-`session_id` gracefully (most tool calls carry a `session_id` arg; tools that don't are unaffected)

**Given** the iteration loop completes
**When** `tCrossSessionList` is non-empty
**Then** the final assistant text emitted by `RunTurn` is server-side-prepended with: *"Note: this turn dispatched tools against session(s) X (and Y, etc.) outside this chat's bound session N. Audit ledger captured all dispatches."* — followed by a paragraph break + the original assistant text
**And** the notice substring is locked by a unit test in `Test/AgentLoopGuardsTest.cls` named `TestRunTurnAppendsCrossSessionNotice`

**Given** the audit ledger semantics from Story 2.5
**When** the cross-session notice is appended
**Then** `Audit.LlmCall` and `Audit.ToolCall` rows still contain the bound `pSessionKey` as `ChatHistoryId` linkage (no audit-row schema change)
**And** the cross-session reach is detectable post-hoc via `SELECT %EXACT(Args) FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = N AND %EXACT(Args) [ '"session_id":"M"'` for any `M ≠ N`

**Given** the Story 3.5 system-prompt language already encourages the LLM to disclose cross-session reaches
**When** the LLM does disclose AND the server-side notice is also appended
**Then** the operator sees both — duplicate disclosure is acceptable (defense-in-depth). The LLM's prose disclosure is conversational; the server-side notice is deterministic. They reinforce each other; they don't conflict.

**Given** the existing 5+ Epic 3 walkthrough turns
**When** an integration test re-runs Story 3.7 Turn 5 (*"Show me what's in session 2"*) against the updated AgentLoop
**Then** the final assistant text begins with the *"Note: this turn dispatched..."* sentence
**And** the cross-session reach is operator-visible regardless of LLM compliance with the system-prompt instruction
```

**Rationale:** Concise spec (~100 lines target). Closes Story 3.7's binding deferred-work entry.

### Change 4.3 — `epics.md` Story 3.9 NEW section

**Section:** Insert after the new Story 3.8 section (above).

**NEW (sketch — full text drafted in the create-story phase):**

```markdown
### Story 3.9: Sample Interoperability Production + Walkthrough Re-Run on Rich Data

As the maintainer + pilot operator validating the agent against richer data than the dev install's 4-message-zero-error baseline,
I want a purpose-built `SessionAgent.Sample.*` interoperability solution — adapterless Business Service callable via a public ClassMethod, ≥2 Business Processes, ≥2 Business Operations, configurable error injection, rich enough message bodies for the agent to answer multi-step diagnostic questions — installed separately from the IPM `<Resource>` so it's clearly a test fixture, not runtime,
So that PRD MVP Exit Criterion #2's "real diagnosis through the agent" portion is empirically reproducible AND Epic 4's Story 4.7 ("comprehensive read-only suite verification") has rich data to inspect against.

**Acceptance Criteria:**

**(detailed ACs to be drafted by `/bmad-create-story` per Rule 1 spec-length governance)**

Outline:
- AC-1: `SessionAgent.Sample.*` package — adapterless `Sample.BS.OrderIngest` (or similar) with `ClassMethod RunScenario(pErrorMode As %String = "none") As %Status` where pErrorMode ∈ {none, businessProcessFailure, businessOperationFailure, providerError, partialSuccess}.
- AC-2: ≥2 Business Processes (e.g., `Sample.BP.OrderRouter`, `Sample.BP.OrderValidator`) with realistic step sequences (3–5 steps each).
- AC-3: ≥2 Business Operations (e.g., `Sample.BO.SqlPersist`, `Sample.BO.FilePublish`) with adapter-less or stub-adapter implementations.
- AC-4: Rich message bodies — at minimum `Sample.Msg.Order` with patient-id-style identifier, line items, totals, status, audit notes (5–10 fields), enough field richness that `session_summary` + `session_timeline` + `message_headers` produce interesting + distinctive output across scenarios.
- AC-5: Bootstrap helper — `Do ##class(SessionAgent.Sample.Bootstrap).InstallProduction()` creates the production + enables it; idempotent; logs operator instructions.
- AC-6: README operator section documenting the sample-production install + scenario invocation.
- AC-7: Walkthrough re-run via chrome-devtools-mcp against the sample production — at least one scenario WITH errors. Captured as Story 3.9 evidence.
- AC-8: NOT installed via IPM `<Resource>` — package excluded from `SessionAgent.PKG`. Operator runs bootstrap explicitly. README covers.
- AC-9: Compile + tests — per-class compile sweep clean; ≥3 unit tests (production starts, scenarios produce expected message counts, error-injection produces expected IsError counts).

**Sample-production scope CAP:** Story 3.9 ships ENOUGH richness for the agent demo — not a full healthcare-interop reference implementation. Realistic but minimal: 3–4 message types, 4–6 distinct scenarios. Future Growth-tier work may expand.
```

**Rationale:** Outline-only — full ACs drafted by `/bmad-create-story` to ensure Rule 1 (≤250 lines) is met. Ample room to expand sample-production scope if needed; explicit cap to prevent scope creep.

### Change 4.4 — `epics.md` Epic 6 story list update

**Section:** Epic 6 "Stories (in order)" enumeration (lines 1729–1733).

**OLD:**
```
**Stories (in order — each completable based only on previous stories within this epic):**

1. **Story 6.1**: `SessionAgent.UI.AgentConfig.zen` (...)
2. **Story 6.2**: Save handler + validation + hot config change verification (...)
3. **Story 6.3**: Replace placeholder admin-link in `sa-config-empty-prompt` (...)
```

**NEW:** Same list with one addition:
```
3. **Story 6.3**: Replace placeholder admin-link in `sa-config-empty-prompt` (...)
4. **Story 6.4**: Multi-namespace install support — `Installer.InstallIntoNamespace(pNamespace)` for operators with multiple interop namespaces; per-namespace `Config.Agent` semantics; README operator-walkthrough
```

### Change 4.5 — `epics.md` Story 6.4 NEW section

**Section:** Insert after the existing Story 6.3 section.

**NEW (sketch — full text drafted in the create-story phase when Epic 6 executes):**

```markdown
### Story 6.4: Multi-Namespace Install Support

As an Operator-Admin running iris-session-agent in an environment with multiple interop namespaces (e.g., HSCUSTOM + a dedicated test namespace + a per-tenant namespace),
I want a documented + tested install path that scopes the agent install to one namespace at a time — `Do ##class(SessionAgent.Installer).InstallIntoNamespace("OTHERNS")` — and a clear architectural decision about whether `Config.Agent` rows are per-namespace or shared,
So that I can deploy the agent across multiple operational contexts without overwriting per-namespace configuration or violating the read-only invariant on cross-namespace `Ens.*` data.

**Acceptance Criteria (outline — drafted in detail by `/bmad-create-story` when Epic 6 executes):**

- AC-1: `Installer.InstallIntoNamespace(pNamespace As %String) As %Status` ClassMethod — switches namespace, calls existing `Install()` work scoped to the named namespace, restores original namespace.
- AC-2: Architectural decision: `Config.Agent` rows are PER-NAMESPACE (default) — each namespace's `SessionAgent_Config.Agent` table is independent. Operators with cross-namespace identical config use a documented copy script.
- AC-3: `SessionAgent.PKG` package mapping — operator must map the package to the target namespace before running `InstallIntoNamespace` (architecture.md §"Project Directory Structure" already calls out per-namespace package routing).
- AC-4: README operator section — multi-namespace install walkthrough with copy-paste-able commands.
- AC-5: `Test/MultiNamespaceInstallTest.cls` — installs into a temporary test namespace + validates Config.Agent + RBAC role + audit-event registration are all per-namespace.
- AC-6: Compatible with existing single-namespace install path — `Install()` is unchanged; `InstallIntoNamespace` is additive.
```

**Rationale:** Outline. Belongs in Epic 6 because the operator-admin audience overlaps with per-agent config UI users.

### Change 4.6 — `sprint-status.yaml` updates

**Section:** Epic 3 + Epic 6 development_status entries.

**OLD (Epic 3 block):**
```yaml
  epic-3: in-progress
  3-0-epic-2-deferred-cleanup: done
  3-1-chat-panel-html-draw-helper-minimum-css-tokens: done
  3-2-client-side-chat-panel-js-mvp-render-submit: done
  3-3-ensportal-visualtrace-subclass-tab-placement-zenmethod-returning-conversation-surfacing: done
  3-4-citation-chips-with-parent-selectitem-updatetabs-integration: done
  3-5-empty-states-config-empty-prompt-provider-error-envelopes: done
  3-6-cross-browser-smoke-test-accessibility-inheritance-verification: done
  3-7-prd-mvp-exit-criteria-validation-pilot-operator-walkthrough: done
  epic-3-retrospective: optional
```

**NEW (Epic 3 block):**
```yaml
  epic-3: in-progress
  3-0-epic-2-deferred-cleanup: done
  3-1-chat-panel-html-draw-helper-minimum-css-tokens: done
  3-2-client-side-chat-panel-js-mvp-render-submit: done
  3-3-ensportal-visualtrace-subclass-tab-placement-zenmethod-returning-conversation-surfacing: done
  3-4-citation-chips-with-parent-selectitem-updatetabs-integration: done
  3-5-empty-states-config-empty-prompt-provider-error-envelopes: done
  3-6-cross-browser-smoke-test-accessibility-inheritance-verification: done
  3-7-prd-mvp-exit-criteria-validation-pilot-operator-walkthrough: done
  3-8-programmatic-cross-session-disclosure: backlog
  3-9-sample-interoperability-production-and-walkthrough-rerun: backlog
  epic-3-retrospective: optional
```

**OLD (Epic 6 block):**
```yaml
  epic-6: backlog
  6-1-agentconfig-zen-form-layout: backlog
  6-2-save-handler-hot-config-change-verification: backlog
  6-3-replace-placeholder-admin-link-end-to-end-configure-and-ask-validation: backlog
  epic-6-retrospective: optional
```

**NEW (Epic 6 block):**
```yaml
  epic-6: backlog
  6-1-agentconfig-zen-form-layout: backlog
  6-2-save-handler-hot-config-change-verification: backlog
  6-3-replace-placeholder-admin-link-end-to-end-configure-and-ask-validation: backlog
  6-4-multi-namespace-install-support: backlog
  epic-6-retrospective: optional
```

**Rationale:** Three new entries reflecting the three new stories. Ordering preserves existing convention (sequential within each epic).

### Change 4.7 — `deferred-work.md` Story 3.7 cross-session entry tagged with named successor

**Section:** Existing entry titled "Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03) — system-prompt-only cross-session disclosure unreliable".

**Edit:** Update the `**Owner:**` line to name Story 3.8 explicitly (per Rule 9 binding — predicted-bug deferral binding on the named successor).

**OLD:**
```
**Owner:** Future story TBD — likely an Epic 4 story (...) OR a dedicated security/UX hardening story (...). Per Rule 9, the spec author for the carrier story MUST grep `deferred-work.md` for "Story 3.7 lead-driven walkthrough" and incorporate this entry into the ACs.
```

**NEW:**
```
**Owner reassigned to Story 3.8** (`Programmatic Cross-Session Disclosure`) — added to Epic 3 via Sprint Change Proposal 2026-05-03. Per Rule 9, Story 3.8's spec author MUST grep `deferred-work.md` for "Story 3.7 lead-driven walkthrough" and incorporate this entry into the ACs.
```

**Rationale:** Rule 9 binding closure pattern — named-successor reassignment from "TBD" to "Story 3.8" so the binding is auditable.

---

## Section 5 — Implementation Handoff

**Scope classification:** **Moderate** — multi-story expansion across two epics + sprint-status reorganization + epics.md edits + deferred-work.md binding update.

**Recipients:**
- **Lead (handles PO + Dev roles in this single-stakeholder hobby project):** approves this proposal; applies the artifact edits (epics.md, sprint-status.yaml, deferred-work.md); resumes `/epic-cycle` to dev/cr/commit Stories 3.8 + 3.9 (per the same pipeline that ran Stories 3.0–3.7). Story 6.4 stays `backlog` — executes when Epic 6 runs.

**Success criteria:**
- Stories 3.8 + 3.9 land via the standard dev → code-review → commit pipeline + pass per-class regression.
- Story 6.4 is in sprint-status with full epics.md spec — picked up cleanly when `/epic-cycle epic 6` runs.
- The Rule 9 binding from Story 3.7's deferred-work entry to Story 3.8 is empirically closed (Story 3.8's spec author runs the grep + Story 3.8's commit message tags the deferred-work entry CLOSED).
- Epic 3 retrospective runs AFTER Stories 3.8 + 3.9 land, with all the expansion findings folded into the empirical battery transcript.

**Deliverables produced by this proposal:**
- This document (`sprint-change-proposal-2026-05-03.md`).
- 7 artifact-edit specifications (Changes 4.1–4.7) ready to apply on user approval.

---

## Approval

**Status:** Awaiting user approval to apply Changes 4.1–4.7 to live artifacts.

Once approved, the lead applies the edits + resumes `/epic-cycle` for Stories 3.8 + 3.9. Story 6.4 stays in sprint-status backlog until Epic 6 executes.
