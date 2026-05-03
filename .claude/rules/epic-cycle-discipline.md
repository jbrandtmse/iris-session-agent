# Epic-Cycle Discipline Rules

**Source: Epic 1 retrospective (2026-05-02).** Each rule is grounded in a real Epic 1 incident requiring user intervention. Rules apply to the **lead** running `/epic-cycle`, and where applicable to dev/reviewer agents.

These rules exist because Epic 1 required user intervention 6+ times for things the autonomous pipeline should have caught. The headline retrospective feedback was: *"I had to intervene."* The capture surface is durable rules so the same mistakes are not made.

## Rule 1: Spec length governance

**Rule.** Story spec files SHOULD be ≤ 250 lines. If a draft exceeds 250 lines, the lead must trim before handing to the dev agent or before committing.

**Trigger.** Self-check at end of spec drafting: `wc -l <story-file>`. If > 250, trim before submitting.

**Rationale.** Stories 1.1–1.4 spec files ran ~600 lines each. Most padding was re-citation of architecture/PRD content the dev agent could read directly. Stories 1.5–1.7 ran ~210 lines and produced equal quality at ~1/3 the token spend. User intervention was required mid-cycle to surface this.

**How to apply.**

- The story file is the *delta* over what's already in the planning artifacts — not a re-summary.
- Cite by reference (`[Source: architecture.md §X]`), don't quote in extenso.
- ACs from epics.md should be present (mapped 1:1 with citations to the originating epic clause), but other epic content should be referenced not duplicated.
- Tasks/Subtasks should be specific and actionable, not narrative paragraphs.
- Dev Notes should contain only the *non-obvious* context the dev agent needs — anything findable by reading architecture.md is over-padding.

## Rule 2: No `[x]` without verification — ever

**Rule.** The lead must NEVER mark a verification task `[x]` in a spec without running the verification and capturing evidence.

**Trigger.** Any time the lead is about to flip `[ ]` → `[x]` on a Tasks/Subtasks line that involves running a command, executing a test, or empirically confirming behavior.

**Rationale.** During Story 1.5 spec rewrite, the lead marked Task 4 (`zpm load` end-to-end) `[x]` without running it. User caught the trust violation by asking "did you actually run zpm load?" Marking ACs satisfied without proof is the worst-case failure mode in autonomous pipelines — it converts a missing verification into a future bug that ships unflagged.

**How to apply.**

- Default for verification-task checkboxes is `[ ]` until empirical evidence is captured in the story file's Completion Notes.
- If the verification can't be run (blocked, unavailable, environment-dependent), keep `[ ]` and document the blocker explicitly with the marker `[~]` (partial / blocked) and a one-line "blocked by ..." note.
- Never speculatively complete. "Looks like it should work" is not verification.
- This rule applies to Lead, Dev agents, and Code-Review agents equally.

## Rule 3: Higher-level MCP before generic `iris_execute_command`

**Rule.** Before constructing an `iris_execute_command` invocation, check whether a typed MCP exists for the operation. If yes, use the typed MCP.

**Trigger.** Spec-writing time AND dev-execution time. Both ends of the pipeline.

**Common typed MCPs to check first:**

| Domain | Typed MCP family |
|---|---|
| RBAC roles, users, resources | `mcp__iris-admin-mcp__iris_role_*`, `iris_user_*`, `iris_resource_*` |
| Task Manager entries | `mcp__iris-ops-mcp__iris_task_list/manage/run/history` |
| Audit log queries | `mcp__iris-ops-mcp__iris_audit_events` |
| System / namespace metadata | `mcp__iris-admin-mcp__iris_namespace_list`, `iris_database_list` |
| SQL queries | `mcp__iris-dev-mcp__iris_sql_execute` (preferred over execute_command for SELECT) |
| Macro lookups | `mcp__iris-dev-mcp__iris_macro_info` |
| Class introspection | `mcp__iris-dev-mcp__iris_doc_search`, `iris_doc_get` |
| Single-method calls | `mcp__iris-dev-mcp__iris_execute_classmethod` (preferred over execute_command for typed args) |

**Rationale.** Story 1.4 dev burned material token budget probing `Security.Roles` and `Security.Users` via `iris_execute_command` `Help()` calls when `iris-admin-mcp.iris_role_*` provides typed JSON. The auto-sync workflow commit (`fe6277c`) codified the rule, but Story 1.5's spec STILL prescribed `iris_execute_command` probes — proving the rule needs a self-check trigger at spec-writing time, not just dev-execution time.

**How to apply.**

- When drafting a story spec's Task 0 probe instructions, list the typed MCPs first and reserve `iris_execute_command` for genuine one-off ObjectScript snippets that no typed MCP covers.
- When executing as a dev agent, scan available MCPs before reaching for `iris_execute_command`.
- `iris_execute_command` is acceptable when: (a) you need to capture multi-line `Write` output that no typed MCP returns, (b) you're testing ObjectScript syntax/semantics that has no API equivalent, (c) you're running a custom multi-statement script with `Try/Catch` that needs in-line state.

## Rule 4: Stale-reference scan at story start

**Rule.** Before writing a story spec or executing it, grep canonical docs for terms relevant to the story. If a term doesn't match live IRIS state (verified via empirical MCP probe), flag for correction in the same commit as the story.

**Trigger.** Story spec drafting; specifically when the story touches an external dependency name (database, namespace, role, class, table, environment variable, file path).

**Canonical docs to scan:**

- `README.md`
- `_bmad-output/planning-artifacts/architecture.md`
- `_bmad-output/planning-artifacts/prd.md`
- `_bmad-output/planning-artifacts/epics.md`
- `_bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md`
- `_bmad-output/planning-artifacts/implementation-readiness-report-*.md`

**Rationale.** Story 1.6 work surfaced HSCUSTOMCODE references in 5 active files. The HSCUSTOMCODE database does not exist on this IRIS install (HSCUSTOM is a 1:1 namespace-to-database mapping per `iris_namespace_list`). User caught this; lead would have shipped Stories 1.1–1.5 with the stale name and only noticed when an operator failed to find the database in the Mgmt Portal.

**How to apply.**

- Add to story-spec drafting workflow: identify external dependency terms (databases, namespaces, role names, table names, paths, env vars).
- Run typed MCP probe to confirm the names match live IRIS state: `iris_namespace_list`, `iris_database_list`, `iris_role_list`, `iris_doc_search`, etc.
- Discrepancies trigger a same-commit correction pass through all canonical docs (per the cross-cutting rename precedent set by Story 1.4 SessionAgent_ReadOnly fix).
- Also update auto-memory entries that may carry the stale term (e.g., `project_package_naming.md`).

## Rule 5: One-liner check before deferring

**Rule.** When something fails (zpm error, compile error, test failure, MCP error), spend 5–15 minutes on empirical investigation via probes + research BEFORE deferring to a future story.

**Trigger.** Lead is about to write "deferred to Story X.Y" or "blocked by external Z" in a story file or `deferred-work.md`.

**Rationale.** Story 1.5 lead initially flagged the `zpm load` failure as a Story 1.7 deferral (CI environment IPM toolchain). User redirected to Perplexity research. The actual fix was a single command (`zpm "enable -map -globally"`). Deferring to Story 1.7 would have left every operator hitting the same wall and propagated stale assumptions through 2+ epics until Story 1.7 finally shipped.

**How to apply.** Before writing the deferral, run this investigation sequence:

1. **Empirical MCP probe** of the actual error: typed MCP for the failing surface (e.g., `iris_role_list` if the error is RBAC-related).
2. **`irislib/` source read** for the API behavior, if applicable.
3. **Perplexity search** for the exact symptom + relevant InterSystems / IRIS / IPM keywords.
4. **Cross-check** the failure against deferred-work.md — has this been seen before?

If the fix is found in <15 min total: apply it, update affected docs in the same commit, do NOT defer. If the investigation surfaces a genuine future-work blocker (e.g., "needs a Python-less IRIS image that doesn't exist publicly yet"), THEN defer with the investigation's findings cited in the deferral entry.

## Rule 6: Self-initiated empirical test pass at epic end (sharpened by Epic 2 retro)

**Rule.** **The lead does NOT propose the retrospective until the epic-end empirical battery transcript exists in the conversation.** Producing the transcript is the precondition; without it, the lead has not actually finished the epic — only finished writing the code.

**Trigger.** Immediately after the last story's commit lands. Before any "Epic N is complete" language. Before asking the user about retrospective. Before any other action.

**Rationale.** Epic 1 retro added this rule with the wording *"before announcing complete"*. Epic 2 lead violated it by jumping from Story 2.12 commit → "Epic 2 complete, ready for retro?" with zero empirical battery. User had to redirect: *"Fix the 5 bugs first. Manually test Epic 2 functionality."* Same failure mode as Epic 1, same redirect, five real shipped bugs caught only by the user-led test pass. The original wording let the lead weasel — "I announced complete AND asked about retro in the same sentence, no rule violated." Sharpened wording removes the weasel.

**Standard battery (adapt per epic; ALL must run BEFORE the retro question):**

1. **End-to-end install:** `zpm load` (or epic-specific install path), capture full lifecycle output.
2. **Expected state via typed MCPs:** `iris_role_list`, `iris_audit_events`, `iris_namespace_list`, `iris_task_list`, etc. — whichever surfaces are owned by the epic's deliverables.
3. **Full regression suite:** `iris_execute_tests` per-class sweep (the package-level runner truncates; per-class is the workaround codified across Stories 2.4 through 2.12).
4. **Live integration test** (per Rule 11 below — added Epic 2 retro): if the epic ships any code path that calls an external API, run the live test. Mock-only smoke tests are insufficient.
5. **CI gates:** run each gate locally as the workflow would.
6. **Cross-cutting invariant checks:** file-presence, `Language = python` grep, CDN grep, any other invariant the epic's stories depend on.
7. **Document results in the retrospective opening as the empirical foundation.**

The battery is the *epic's exit gate* — without passing it, no retrospective conversation begins. If the lead skips the battery, the user redirect is the rule's enforcement mechanism (and that redirect itself is a rule-violation signal worth surfacing in the retro).

## Rule 7: Operator setup at sprint planning, not at retro

**Rule.** During Step 1 of `/epic-cycle` (sprint planning), the lead identifies every operator-side prerequisite the epic's stories will require — API keys, SSL configurations, env-vars, credential rows, `Enabled=1` toggles, RBAC grants — and asks the user for them upfront. Captured in `_bmad-output/implementation-artifacts/epic-{N}-operator-state.md` so credentials survive cycle resumes.

**Trigger.** Pre-flight checklist construction. Any story spec that names `Util.EnvSecret`, `%Net.HttpRequest`, `Ens.Config.Credentials`, `Security.SSLConfigs`, or any external-API URL is a flag.

**Rationale.** Epic 2 ran 13 stories of dev/reviewer cycles + a "complete" SmokeTest, and the live OpenAI integration was never exercised because the API key wasn't available until the user supplied it during the retro empirical battery. The cost: an entire cycle of fix-rebuild-retest after switching `gpt-4o → gpt-4.1-mini` (which itself was discovered AFTER the credentials were finally wired). If the credential had been requested at Epic 2 sprint planning, Story 2.12 SmokeTest could have been a real live test instead of a mock pretending to be a smoke test, and Stories 2.9/2.12 reviewers would have caught the OpenAI tool_result bug + the stale gpt-4o default + the missing `DefaultSSL` prereq before they shipped.

**How to apply.**

- At sprint planning, lead reads the epic's story list and constructs an "operator-state checklist" of all prerequisites.
- Lead asks the user for them in a single batched message at Step 1, BEFORE Story X.0 creation.
- User-supplied credentials persist in `Ens.Config.Credentials` (project rule: never in `.env` files committed to the repo; `.keys` is gitignored as a local-only fallback).
- The checklist file documents which agent/credential maps to which story. Story specs MAY reference it.
- If the user can't supply a credential at planning time (e.g., they're not at their workstation), the lead notes the gap and explicitly defers the live-test gate to the retro empirical battery — but as a documented deferral, not an oversight.

## Rule 8: Defer threshold raised — "fix now" is the default

**Rule.** Code reviewers may defer a finding ONLY if it passes one of three explicit tests:

1. **Genuine future-epic scope:** the work belongs to a story in a later epic that isn't yet drafted (e.g., a Story 7.x sweep task referenced from a Story 2.x audit-row writer).
2. **External-dependency blocker:** the fix requires an artifact that doesn't exist yet (e.g., a Python-less IRIS 2024.1 community Docker image).
3. **Pure cosmetic with no predicted-bug shape:** doc-comment polish, dead-code remnant, name-style preference. The reviewer must explicitly state "no bug shape" in the deferral entry.

**Anything the reviewer can articulate as "this might break X" or "this gap will cause Y" or "the next story should also handle Z" → AUTO-FIX in the current story, not defer.**

**Trigger.** Code reviewer about to write a `deferred-work.md` entry.

**Rationale.** Epic 2 accumulated ~30 deferred-work entries; the user-led empirical battery proved 5 of them (17%) were real shipped bugs. The most painful was Story 2.8 reviewer's deferral that named the exact file/line/test gap and reassigned ownership to Story 2.9 — Story 2.9's reviewer didn't read Story 2.8's deferred-work, didn't add the test, the bug shipped, OpenAI HTTP 400'd on turn 2. The deferred-work pattern as previously practiced was a write-only release valve. Raising the threshold + making "fix now" the default flips the burden: the reviewer must justify the defer, not justify the fix.

**How to apply.**

- Reviewer drafts the finding.
- Before writing `deferred-work.md`, ask: "Can I articulate this as a predicted bug?" If yes → fix now. If no → check the three explicit tests above. If none pass → fix now.
- A deferral entry MUST include a one-line justification picking which of the three tests applies. No justification → not a valid deferral.
- This rule supersedes the prior implicit pattern of "LOW severity = defer". Severity is orthogonal: a LOW-severity predicted-bug still gets fixed now.

## Rule 9: Predicted-bug deferrals must be binding on the named successor

**Rule.** When a code reviewer's deferred-work entry names a specific future story as the carrier (e.g., *"owner reassigned to Story 2.10"*), the lead's `bmad-create-story` step for that future story MUST grep `deferred-work.md` for entries naming it and incorporate the carry-forward into the story's Acceptance Criteria. The reassignment is binding, not advisory.

**Trigger.** Lead writing a story spec via `/bmad-create-story` (Step 4a of `/epic-cycle`).

**Rationale.** Story 2.0 successfully closed Story 1.3's `RegisterIfMissing` reassignment because Story 2.0 explicitly reads `deferred-work.md` as part of the triage gate. Story 2.10 successfully closed Story 2.0's `RegisterIfMissing` carry-forward because the spec author (lead) read the triage table. But Story 2.9 SILENTLY DROPPED Story 2.8's reassigned-to-2.9 deferred entry (the OpenAI tool_result test gap) because the lead writing Story 2.9's spec didn't grep deferred-work.md for "Story 2.9" mentions. The predicted bug shipped. This rule closes the gap.

**How to apply.**

- During spec drafting for Story N: `grep -ni "Story N\|story-N\|Story-N" _bmad-output/implementation-artifacts/deferred-work.md`.
- For each match where the entry names Story N as the owner / next carrier: incorporate the work into the spec's ACs (or explicitly document why it can't be done in this story and re-defer with a new named successor).
- Spec must include a "Carry-forward from prior deferred-work entries" section that lists each match and how it's addressed.
- Lead-self-block: spec is not "ready-for-dev" until the grep was run + every match acknowledged.

## Rule 10: External-default research at spec time (Perplexity-mandatory)

**Rule.** Any story spec that sets a canonical default value for an external system — model name, API version string, package version, endpoint URL, library tag, third-party tool version — MUST include in Dev Notes a verification line of the form:

> *"Verified current as of {YYYY-MM-DD} via {Perplexity query summary OR official source URL}: {recommended choice + cost/quality/recency rationale}."*

Without this line, the lead self-blocks the spec.

**Trigger.** Story spec authoring. Examples: any story setting a default LLM model name (Story 2.4), default IRIS version compatibility (Story 1.1), default vendored library version (Story 10.7), default API endpoint (Story 2.9).

**Rationale.** Story 2.4's spec set `OpenAI: gpt-4o` as the canonical default. The architecture.md OD4 row even said *"verify current model name before each release tag — release-gate item, model names drift"*. Nobody verified. Dev/reviewer agents have training cutoffs that predate gpt-4.1-mini (2025-04) and gpt-5 family (2025-08); without an explicit Perplexity research step, they keep picking the model name they were trained on. User caught this in Epic 2 retro — gpt-4o is 6.25× more expensive than gpt-4.1-mini for the same tool-calling reliability. We rebuilt 12 files of canonical references after the fact. Should have been picked at Story 2.4 spec time.

**How to apply.**

- Spec author identifies any external-default values being set.
- Runs `mcp__perplexity-mcp__search` with a query naming the specific external system + "current versions / pricing / recommended for {use case} as of {YYYY-MM}".
- Pastes the verification line into Dev Notes verbatim with the date and a 1-sentence rationale.
- If multiple options surface, document why this one was picked (cost, quality, recency, license, etc.).
- Reviewer enforces: an external-default story without a verification line is a HIGH-severity finding that auto-blocks ship (per Rule 8: predicted-bug — drift between training-data default and current-best).

## Rule 11: Live integration smoke test mandatory when external API is in scope

**Rule.** Any epic that adds or modifies a code path calling an external API MUST ship one live smoke test (gated behind a credential-presence check that skips gracefully if the credential is absent). Mock smoke tests can stay; they don't substitute. The live test is the wire-format-correct proof.

**Trigger.** Epic-end empirical battery (Rule 6). If the epic touches an external API and there's no live smoke test that exercised the real wire format, the empirical battery is incomplete.

**Rationale.** Story 2.12's `SmokeTest.cls` used `MockOpenAIProvider` returning canned responses in the canonical wire shape we already knew worked. It passed. Real OpenAI then rejected the second turn with HTTP 400 because the canonical-Anthropic `tool_result` block wasn't being translated into OpenAI's `{role:"tool", tool_call_id, content}` shape — a wire-format gap mock tests can't detect by definition (mocks ARE the canonical shape). The bug had been predicted by Story 2.8's reviewer (see Rule 9), reassigned to Story 2.9, dropped, shipped. A live smoke test running once per epic-end battery would have caught it before the retro.

**How to apply.**

- Live test class names: `<EpicSurface>SmokeLive.cls` (e.g., `OpenAIProviderSmokeLive.cls`) OR a `[ NotForCi ]` marker on the existing smoke test.
- First line of the test: probe credential availability via `Util.EnvSecret.IsResolvable(envVarName, credentialName)`. If false, mark the test skipped (not failed) so CI without credentials still passes.
- Test must invoke the actual external API path (real HTTPS, real auth, real wire format) and assert at least one round-trip succeeds.
- Live tests participate in the epic-end battery (Rule 6 step 4). Lead runs them. Failure = epic not done.

---

## Application matrix (updated Epic 2 retro)

| Rule | Applies to Lead | Applies to Dev agent | Applies to Code-Review agent |
|---|---|---|---|
| 1. Spec length governance ≤ 250 lines | ✓ (drafting) | ✓ (when proposing edits) | — |
| 2. No `[x]` without verification | ✓ | ✓ | ✓ |
| 3. Higher-level MCP first | ✓ (spec) | ✓ (execution) | ✓ (verification) |
| 4. Stale-reference scan at story start | ✓ (story start) | ✓ (canonical doc edits) | ✓ (cross-cutting) |
| 5. One-liner check before deferring | ✓ | ✓ (escalate with investigation) | ✓ |
| 6. **Sharpened**: empirical battery transcript precondition for retro | ✓ | — | — |
| 7. Operator setup at sprint planning | ✓ | — | — |
| 8. Defer threshold raised — "fix now" is default | ✓ (story sign-off) | — | ✓ (primary) |
| 9. Predicted-bug deferrals binding on named successor | ✓ (spec drafting) | — | ✓ (records the reassignment) |
| 10. External-default research at spec time | ✓ | ✓ (escalate if discovered mid-execution) | ✓ (block on missing verification line) |
| 11. Live integration smoke test mandatory | ✓ (epic-end) | ✓ (story authoring if API touched) | ✓ (verifies test exists) |

## How to load these rules in a future cycle

The `/epic-cycle` slash command's pre-flight reads this file alongside `docs/epic-cycle-teams.md`. Both are required reading before any story work begins. See [`.claude/commands/epic-cycle.md`](../commands/epic-cycle.md) for the pre-flight sequence.

For non-cycle work on this project, the lead inherits these rules via the auto-memory feedback entry `feedback_epic_cycle_discipline.md` — see [`MEMORY.md`](../../C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/MEMORY.md).
