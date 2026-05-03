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

## Rule 6: Self-initiated empirical test pass at epic end

**Rule.** Before announcing "Epic N complete" and asking about retrospective, run the full deliverable battery: end-to-end install, expected-state queries, full regression suite, CI gates.

**Trigger.** End of last story's commit in an epic, before transitioning to the retrospective decision.

**Rationale.** Epic 1 lead announced complete and proposed retrospective without running the empirical battery. User had to request "manually test Epic 1 functionality." The lead-initiated battery is the difference between "claims of completeness" and "demonstrable completeness." It also surfaces any cross-story regressions before the retrospective so the retro analysis has empirical foundation, not speculation.

**Standard battery (adapt per epic):**

1. **End-to-end install:** `zpm load` (or epic-specific install path), capture full lifecycle output.
2. **Expected state via typed MCPs:** `iris_role_list`, `iris_audit_events`, `iris_namespace_list`, `iris_task_list`, etc. — whichever surfaces are owned by the epic's deliverables.
3. **Full regression suite:** `iris_execute_tests` at package level (not just the new tests — the *full* `SessionAgent.Test` package, to catch regressions in earlier-epic tests).
4. **CI gates:** run each gate locally as the workflow would (structural checks, NFR-C2 grep, NFR-C5 grep, etc.).
5. **Cross-cutting invariant checks:** file-presence, `Language = python` grep, CDN grep, any other invariant the epic's stories depend on.
6. **Document results** in the retrospective opening as the empirical foundation.

The battery is the *epic's exit gate* — without passing it, the retrospective is operating on assumptions.

---

## Application matrix

| Rule | Applies to Lead | Applies to Dev agent | Applies to Code-Review agent |
|---|---|---|---|
| 1. Spec length governance | ✓ (drafting) | ✓ (when proposing edits to a spec) | — |
| 2. No `[x]` without verification | ✓ | ✓ | ✓ |
| 3. Higher-level MCP first | ✓ (spec) | ✓ (execution) | ✓ (verification) |
| 4. Stale-reference scan | ✓ (story start) | ✓ (when modifying canonical docs) | ✓ (cross-cutting check) |
| 5. One-liner check before deferring | ✓ | ✓ (escalate to lead with investigation, not raw error) | ✓ |
| 6. Empirical test pass at epic end | ✓ | — | — |

## How to load these rules in a future cycle

The `/epic-cycle` slash command's pre-flight reads this file alongside `docs/epic-cycle-teams.md`. Both are required reading before any story work begins. See [`.claude/commands/epic-cycle.md`](../commands/epic-cycle.md) for the pre-flight sequence.

For non-cycle work on this project, the lead inherits these rules via the auto-memory feedback entry `feedback_epic_cycle_discipline.md` — see [`MEMORY.md`](../../C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/MEMORY.md).
