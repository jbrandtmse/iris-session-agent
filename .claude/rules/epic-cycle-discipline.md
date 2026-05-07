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

**Sharpened (Story 5.0 / Epic 4 retro AI-2) — verbatim AC-contract evidence in Completion Notes.** For each verification task `[x]`, the dev's Completion Notes MUST capture **verbatim output that proves the AC's "Then ..." clause holds** — a SQL probe result, a method invocation return, a tool dispatch envelope, a class Description grep, a chrome-devtools-mcp screenshot reference, or whatever evidence form matches the contract. **"Tests passed" is necessary but not sufficient.** Examples of the evidence-shape match:

- AC's "Then ..." is *"the class declares Description = X"* → evidence is the **verbatim Description string** from the compiled class (e.g., `iris_doc_get` UDL output or `iris_sql_execute` against `%Dictionary.ParameterDefinition`).
- AC's "Then ..." is *"the SQL projection returns N rows of shape Y"* → evidence is the **verbatim SQL probe output** with column headers and row data.
- AC's "Then ..." is *"the rendered welcome message reads 'Hello, $User'"* → evidence is the **verbatim chrome-devtools-mcp `take_snapshot` / `take_screenshot` output** showing that exact string in the rendered DOM (per Rule 12 — UI stories).
- AC's "Then ..." is *"the tool dispatch returns `render_strategy=matched`"* → evidence is the **verbatim envelope JSON** from `iris_execute_classmethod` against `Tool.Registry.Dispatch`.
- AC's "Then ..." is *"the regression sweep is N/N pass"* → evidence is the **verbatim SQL probe output against `%UnitTest_Result.TestMethod`** per Rule 6 step 3 (the MCP envelope is best-effort, not ground truth).

The originating Epic 4 incidents — **5 reviewer-caught bugs that all involved the dev claiming completion based on tests-passing without empirical proof of the AC's actual contract:**
1. **Story 4.3 HIGH** — silent `%Prepare` failure path: tests passed but no test exercised the SQL Statement.%Prepare-returns-error code path.
2. **Story 4.4 HIGH x2** — class Description drift x2: tests passed but the registered tool descriptions in `%Dictionary.ParameterDefinition` had drifted from the spec wording, surfacing as wrong tool descriptions in `Tool.Registry.ListTools` output.
3. **Story 4.7 HIGH** — `FormatException` off-by-one: dev claimed "8/8 methods pass" from `iris_execute_tests`; real recorded state was 9/10 (one tail row truncated from the envelope; SQL probe would have caught it).
4. **Story 4.5 wider sweep needed** — `find_related_sessions` empty-array case wasn't asserted on the actual SQL probe shape; the test passed against the dev's mental model but the production output differed.

**Apply at story sign-off.** When flipping the last task `[x]`, the dev re-reads each AC and confirms the Completion Notes contain the verbatim evidence shape matching that AC's "Then ..." clause. If any AC lacks the evidence, the dev keeps the task `[ ]` until the evidence is captured.

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

### Watch-item: operator-facing static text vs shipped-capability divergence (Story 5.0 / Epic 4 retro AI-3)

When an epic adds tools, providers, agents, or other shipped capabilities, the stale-reference scan MUST also include **operator-facing static text** that may have been written in a prior epic enumerating only the THEN-shipped capabilities. The scan target list extends beyond external dependency names (HSCUSTOMCODE | gpt-4o | etc.) to include:

- **Welcome messages** in chat panels, portals, REPLs (e.g., `chat-panel.js renderWelcomeMessage`).
- **Error envelopes** that enumerate what the system can/can't do (e.g., "I can answer questions about: A, B, C" — must update when D ships).
- **Status messages** rendered in the UI (e.g., "X tools available" must match the actual registered count).
- **Button labels / attribution prefixes / capability statements** in any operator-rendered surface.
- **Doc comments + class Descriptions** that enumerate capability lists (these surface in `Tool.Registry.ListTools` output and operator-facing portals).

**Originating finding.** Story 4.7 manual-test session (Epic 4 close-out) caught the chat-panel `renderWelcomeMessage` claiming only the **3 Epic 3 inspection tools** (`session_summary`, `session_timeline`, `message_headers`) despite Epic 4 having shipped **13 total tools** (10 new — `event_log`, `rule_log`, `get_message_body`, `get_message_detail`, three BP-introspection, `find_related_sessions`, `find_sessions_by_body`, `explain_error`). The welcome message had not been updated as Epic 4 stories shipped the new tools — a stale-reference invariant that no automated test caught because the welcome string is operator-facing prose, not a structural assertion. Fix landed in commit `d7ebf80`.

**Apply at story start.** When a story adds a capability, the lead's Task 0 stale-reference scan MUST `grep` for capability enumerations across `*.js` (UI assets), `*.cls` (doc comments + Description parameters), `*.md` (README, deferred-work, planning artifacts) and update each reference in the same commit. The scan keywords are the capability-list terms, not just the dependency names: e.g., for a new tool `find_x`, grep for the existing tool names that appear together in lists (`session_summary`, `session_timeline`, etc.) — wherever an enumeration appears, that's a candidate for stale-reference correction.

### Operator-observable surface enumeration at story-spec time (Story 8.0 / Epic 7 retro AI-1)

**Rule.** Any story shipping a Mgmt-Portal-visible artifact — a `%SYS.Task`
entry, an audit-event triple (`Source`/`Type`/`Name`), an RBAC role, a Web
Application, a Zen page page-name, a system-shipped resource, a Production
item, or any other operator-observable surface — MUST enumerate **at story-
spec time** the descriptive text fields the artifact exposes (the Mgmt-
Portal `Description` column, the audit-event description, the role
doc-comment, the Web App description, the Zen page `%OnGetPageName`
return, etc.) and confirm each is populated with operator-readable text.
An empty `Description` field on a shipped artifact is a HIGH-severity
finding per Rule 8 (predicted-bug shape: operator opens Mgmt Portal,
sees a blank entry, cannot self-orient — the same operator-UX gap that
Epic 7 user-led empirical battery surfaced).

**Originating finding.** Story 7.2 shipped the
`SessionAgent.PurgeOrphanedChatHistory` `%SYS.Task` row (ID 1007) with
an **empty Description** column — the dev correctly populated `Name`,
`TaskClass`, and frequency fields, but never copied the implementing
class's class-level `Description` doc-comment into the task entry's
`Description` field. An operator opening Task Manager saw a blank
description column for the new sweep task and could not self-orient
without grepping the codebase. The fix-now landed in Story 8.0 AC-2
(`Installer.ScheduleTaskIfClassExists` reads
`%Dictionary.ClassDefinition.%OpenId(pTaskClass).Description` and assigns
to `tTask.Description` before `%Save`); this codification prevents the
recurrence on every future Mgmt-Portal-visible-artifact-shipping story.

**How to apply.**

- At spec-writing time: identify each Mgmt-Portal-visible artifact the
  story will ship. Enumerate the descriptive text fields (Description
  column, doc-comment, page-name, etc.) the artifact exposes.
- For each field, confirm the spec sets the field to operator-readable
  text. "Operator-readable" means a sentence an operator can read in
  Mgmt Portal that explains what the artifact is and what touching it
  does — not a class name, not a placeholder, not blank.
- The spec MUST cite the specific source the descriptive text comes
  from (class-level doc-comment, AC text, README pointer, etc.) so the
  dev does not re-author drift-prone copy.
- Reviewer enforces: a shipped artifact whose Mgmt-Portal-visible
  Description / doc-comment / page-name surface is empty is a
  HIGH-severity finding per Rule 8. Block until populated.

**Surfaces commonly missed (extend this list when a new shape recurs):**

- `%SYS.Task.Description` — shipped via `Installer.ScheduleTaskIfClassExists`
  (Story 8.0 AC-2 reads from `%Dictionary.ClassDefinition.Description` of
  the implementing class).
- `Security.Events.Description` — audit-event triples shipped via
  `SessionAgent.Audit.Emit.EnsureEvents` must populate the Description
  column for the Mgmt Portal audit-event browser.
- `Security.Roles.Description` — RBAC role shipped via
  `SessionAgent.Security.ReadOnlyRole.Install` populates the Description
  column.
- `Security.Applications.Description` — Web App description for Mgmt
  Portal Web Application listing.
- `EnsPortal.Template.standardPage` `%OnGetPageName` — Zen page
  display-name surfaced in the portal banner / breadcrumb.
- `%Dictionary.ParameterDefinition` `Description` parameter on
  `Tool.Inspection.*` and `Tool.Search.*` classes — surfaces in
  `Tool.Registry.ListTools` operator-facing output AND the LLM tool
  manifest.

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
3. **Full regression suite:** `iris_execute_tests` per-class sweep (the package-level runner truncates; per-class is the workaround codified across Stories 2.4 through 2.12; see [`.claude/rules/object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround"](object-script-testing.md)). **The "N/N test pass" claim that gates the retro MUST come from a direct SQL probe against `%UnitTest_Result.TestMethod` (joined to `TestCase`), not from the MCP envelope** — the envelope can silently truncate failing-tail rows and mask off-by-one bugs (Story 4.7 HIGH severity). See [`.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth for test-pass verification"](object-script-testing.md) for the canonical query.
4. **Live integration test** (per Rule 11 below — added Epic 2 retro; **sharpened Epic 3 retro AI-13**): if the epic ships any code path that calls an external API, run the live test against **rich, production-shaped data** — sample production, fixture data, or real captured traffic. A bare namespace with synthetic test sessions does NOT count. For projects without a sample production, the lead must build minimal fixture data before claiming the battery is complete. Cited reason: Epic 3 Story 3.7 lead-walkthrough-on-bare-HSCUSTOM → user-redirected-to-sample-production incident — the redirect surfaced 5 manual-test bugs in 30 minutes that the bare-namespace smoke missed. Mock-only smoke tests are insufficient.
5. **User-led chat-panel manual-test pass — REQUIRED for any epic that touches LLM provider code (added Epic 5 retro AI-1 / Story 6.0 AC-1).** "Touches LLM provider code" means: a new concrete `SessionAgent.LLM.<X>Provider` ships, the abstract `SessionAgent.LLM.Provider` template changes, `MessageAdapter` / `ToolDefAdapter` translation logic changes, or `AgentLoop` provider-integration changes. **The lead does NOT propose the retrospective until the user has driven the chat panel through each configured provider with at least one tool-dispatch turn.** Mock-matrix is API-level (canonical inputs); live tests bypass the operator-storage path; the chat panel exercises BOTH the canonical wire-shape AND the operator-storage read path (Config.Agent rows mutated via the Zen form / SQL UPDATE). The Epic 5 manual-test session is the originating incident — Bugs 1 (`$Char(0)` sentinel from SQL UPDATE write path), 2 (`MAXLEN=50` overflow on SessionKey), 3 (`additionalProperties` rejected by Gemini's Schema proto), 4 (Gemini stopReason=STOP with functionCall present) all surfaced ONLY via user-led chat-panel manual-test, NOT in mock-matrix or live-test classes. Cited Project Lead acceptance of the human-in-the-loop step (2026-05-06): *"User-led manual testing is fine, it's good for me to be in the loop at that point."* Capture the manual-test session as a screenshot (per Rule 12) plus a one-line per-provider notation in the retro opening (e.g., *"Anthropic chat-panel turn against sample-prod session 1844 — tool dispatched, citations rendered, no mojibake"*).
6. **CI gates:** run each gate locally as the workflow would.
7. **Cross-cutting invariant checks:** file-presence, `Language = python` grep, CDN grep, any other invariant the epic's stories depend on.
8. **Document results in the retrospective opening as the empirical foundation.**

The battery is the *epic's exit gate* — without passing it, no retrospective conversation begins. If the lead skips the battery, the user redirect is the rule's enforcement mechanism (and that redirect itself is a rule-violation signal worth surfacing in the retro).

### Pre-retro enforcement checklist (lead-self-blocking) (Story 8.0 / Epic 7 retro AI-3)

**Rule.** Before the lead proposes the retrospective, FOUR specific
bullets MUST appear **verbatim in the conversation transcript**. A bare
claim "regression sweep passed" is insufficient — the lead self-blocks
the retro proposal until each bullet's evidence is captured inline:

1. **Task Manager / typed-MCP observability probe output for any new
   operator-observable artifact shipped this epic.** For every shipped
   `%SYS.Task` row, audit-event triple, Web App, RBAC role, etc.,
   capture the typed-MCP envelope showing the artifact in operator-
   visible state with non-empty Description (`iris_task_list`,
   `iris_audit_events`, `iris_role_list`, `iris_webapp_list`, etc., per
   Rule 3). If the epic shipped no operator-observable artifacts, the
   lead must explicitly note "no operator-observable artifacts shipped
   this epic" — silence is not acceptable.

2. **Audit-event triple verification.** Run
   `SELECT %EXACT(EventSource), %EXACT(EventType), %EXACT(EventName)
   FROM %SYS.Audit_Events WHERE %EXACT(EventSource) = 'SessionAgent'`
   (or the epic's specific filter) and capture the verbatim row roster
   showing every triple the epic registered or modified. If the epic
   added no audit triples, "no audit triples shipped this epic" is the
   acceptable note.

3. **Rich-data live exercise of the epic's primary code path.** Per
   Rule 11 if external API is in scope; per Rule 6 step 4 otherwise.
   Bare-namespace synthetic data does NOT count — the live exercise
   runs against sample-production fixture data, real captured traffic,
   or operator-supplied production-shaped state. Capture the verbatim
   primary output (HTTP envelope, audit row, render envelope, etc.)
   that proves the path ran end-to-end.

4. **Full regression sweep via SQL ground-truth probe.** Verbatim
   `Total / Passed / Failed` row from `%UnitTest_Result.TestMethod`
   (per AC-5 tweaked form below — numeric run-id comparison, not
   lexicographic `MAX(ID) GROUP BY %EXACT(Name)`). The
   `iris_execute_tests` envelope is best-effort; the SQL probe is the
   verification gate. If the epic added new tests, the count must
   reconcile to the pre-state baseline + new test count.

**Why a checklist (not just sharpened wording).** Epic 7 retro finding
C-5 surfaced the lead jumping straight to the retro question without
emitting the empirical battery transcript inline — third recurrence of
the same failure mode (Epic 1 added Rule 6, Epic 2 sharpened the
"transcript precondition" wording, Epic 7 still violated). The pattern
is that "transcript precondition" is too abstract: the lead can
mentally rationalize "I ran the battery in earlier turns, the user can
scroll back" and skip the inline emission. Making the four bullets
**verbatim** + **inline** + **named-checklist** removes the rationalization
surface — either the four bullets are visible in the latest turns, or
they are not.

**Apply at retro proposal time.** The lead's retro-proposal message
MUST contain or directly precede the four bullets. The user redirect is
the enforcement mechanism: if the lead proposes the retro and the four
bullets are missing, the user redirects with "where is the battery?"
and the cycle restarts at this rule. Each redirect is a rule-violation
signal worth surfacing in the retro itself (meta-self-correction).

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

### Watch-item: Sample production state at Epic-cycle Step 1 (Story 5.0 / Epic 4 retro AI-4)

During Step 1 sprint planning, the lead MUST verify **sample-production state** (running / stopped / uninstalled) and re-Bootstrap to a known-good state if needed, **BEFORE** any per-story dev cycles run. This avoids the per-story re-Bootstrap friction observed in **Stories 4.3, 4.6, and 4.7**, all of which required mid-story re-Bootstrap when the dev agent discovered the production was stopped or uninstalled at story-start time.

**One-line addition to the operator-setup checklist:**

> *Sample production: confirm `Ens.Director.IsProductionRunning` returns 1 OR run `Bootstrap.Install` + `StartProductionIfStopped` + at least one `RunScenario` to populate fresh sessions.*

**Rationale.** Sample-production state is operator-managed but ambient — it can drift between cycle resumes (server restart, namespace switch, manual cleanup), and a dev agent that finds a stopped or uninstalled production has to break flow to re-Bootstrap, which costs ~10 minutes per occurrence and creates a Rule 6 false-negative risk if the dev forgets to re-run scenario data after Bootstrap. Verifying once at Step 1 amortizes the check across the whole epic.

**Apply at sprint planning.** When the lead constructs the operator-state checklist, sample-production state is a checklist item alongside API keys / SSL configurations / credentials. The lead's Step 1 verification probe set:

```
mcp__iris-dev-mcp__iris_execute_classmethod  classMethod: Ens.Director.IsProductionRunning
```

Returns `1` → state confirmed, no action.
Returns `0` → run `Bootstrap.Install` + `StartProductionIfStopped` + at least one `RunScenario`, then re-probe.
Returns error → the production may be uninstalled in this namespace; run full `Bootstrap.Install` from scratch.

**Step-1-time only — NOT per-story (Story 8.0 / Epic 7 retro AI-4).** The
lead emits ONE `Ens.Director.IsProductionRunning` check + auto-Bootstrap
(per the probe set above) at /epic-cycle Step 1, **BEFORE any story is
dispatched**, so the entire epic runs against verified-running
production. Per-story-time probes are too late: production drifts
between stories during cycle resumes (server restart, namespace switch,
user-initiated cleanup, manual scenario reset), and a dev agent that
finds a stopped or uninstalled production has to break flow to
re-Bootstrap. The cost is ~10 minutes per occurrence and a Rule 6
false-negative risk if the dev forgets to re-run scenario data after
Bootstrap. Verifying once at Step 1 amortizes the check across the
whole epic. Cited Epic 7 Story 7.2 incident: dev discovered
`IsProductionRunning=0` mid-story and had to break flow to re-Bootstrap
before completing AC verification — fourth recurrence across Epic 4
(Stories 4.3, 4.6, 4.7) → Epic 5 → Epic 6 → Epic 7. The Step-1-time
amortization is the structural fix; per-story discovery is the
recurring failure mode.

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

## Rule 12: Rendered-text readability — read it as a human (added Epic 3 retro AI-12)

**Rule.** Every UI story's empirical battery MUST include a step where the lead
reads the **rendered text content** AS A HUMAN and confirms it is readable
English (or the project's UI language). Welcome messages, error envelopes,
status messages, button labels, attribution prefixes — every visible string
the operator can see. **Screenshot-and-look-at-it counts.** Automated DOM
dumps + a11y-tree scrapes alone do **NOT** count — both pass cleanly when
the underlying characters are mojibake.

**Trigger.** Any story whose acceptance criteria include UI rendering
(component HTML, CSS classes, asset files served to the browser, generated
strings displayed in chat panels / portals / banners). Applies to the lead
running the empirical battery, the dev agent producing the smoke output,
and the code reviewer verifying the rendered surface.

**Rationale.** Epic 3 Story 3.7 shipped a UTF-8 mojibake welcome message to
production — `Â·` replaced the `·` separator because the
`SessionAgent.UI.ChatPanelAsset` stream was not configured with
`TranslateTable=UTF8`. Every automated check (DOM-snapshot diff, a11y-tree
walk, header inspection) passed because the bytes were valid in some
encoding — the bug only surfaced when a human read the rendered chat panel.
The fix landed in commit `ebde251`. The retrospective AI-12 codified the
rule because the next UI story (Story 3.8 cross-session disclosure) was
about to repeat the same failure mode in a different asset path, and the
lead would have shipped it again without a human-read step in the battery.

**How to apply.**

- For each UI story, the empirical battery includes a screenshot or
  rendered-content paste of every new or modified visible string. The lead
  reads each one and asks: *"Is this readable English? Are there mojibake
  artifacts (`Â`, `â€™`, `Ã©`, etc.)? Does the spacing make sense?"*
- Acceptable evidence forms: a screenshot via `chrome-devtools-mcp`'s
  `take_screenshot`, a rendered-DOM `textContent` paste, or an in-browser
  console transcript showing the visible strings. **Note:** `textContent`
  paste is acceptable for **content-correctness** claims only (mojibake,
  label text, ARIA, byte-encoding). For **layout-correctness** claims
  (chrome, framing, placement), see the "Layout-correctness vs
  content-correctness evidence" sub-section below — `textContent` is
  insufficient and a screenshot or DOM probe is required.
- **Not acceptable** as the sole evidence: HTML-source diff (the bytes
  may be valid HTML but encode mojibake when interpreted), a11y-tree
  output (screen readers announce mojibake as garbage but the tree walker
  still passes), or a passing DOM-snapshot test (snapshots compare bytes
  — they cannot tell `·` from `Â·`).
- The reviewer enforces: a UI story whose empirical battery is missing a
  human-readability evidence step is a HIGH-severity finding per Rule 8 —
  predicted-bug shape (mojibake / encoding drift will ship silently).

**Originating finding.** UTF-8 mojibake `Â·` welcome-message incident
(Story 3.7 → fix in commit `ebde251`). First applied: this story (4.0,
the same commit that codifies the rule).

### Layout-correctness vs content-correctness evidence (Story 7.0 / Epic 6 retro AI-1)

**Rule.** Rule 12's empirical evidence forms split into two distinct
categories — they are NOT interchangeable:

- **Content-correctness** claims — mojibake checks, label text, ARIA
  labels, byte-level encoding, readable-English prose. Acceptable
  evidence: a screenshot, a rendered-DOM `textContent` paste, an
  in-browser console transcript showing the visible strings.
- **Layout-correctness** claims — chrome / styling / framing / placement
  assertions like *"renders inside Mgmt-Portal chrome"*, *"form fields
  aligned with the design"*, *"modal centered"*, *"breadcrumb appears
  above the content area"*, *"Zen form inherits the portal's standardPage
  banner"*. Acceptable evidence: **REQUIRES** either a screenshot via
  `chrome-devtools-mcp.take_screenshot` OR an in-browser DOM-state JS
  probe via `chrome-devtools-mcp.evaluate_script` (e.g., asserting that
  a specific class is applied, that a specific element exists in the
  rendered DOM, that a parent wrapper is present, that a CSS computed
  property has the expected value).

**Why the split.** A rendered-DOM `textContent` paste reads the visible
strings but cannot detect missing chrome, layout drift, or visual
regression — `textContent` ignores element identity, parent hierarchy,
applied classes, and computed styles. The bytes pass the readability
check while the surface ships without its expected wrapper, banner, or
framing. Conversely, a screenshot detects layout drift but is
expensive evidence to capture for every byte-level mojibake check —
content-correctness claims do not need the screenshot path.

**Originating finding.** Epic 6 manual-test session caught the
`SessionAgent.UI.Portal.AgentConfigForm` Zen page rendering **without
the Mgmt-Portal `EnsPortal.Template.standardPage` chrome** — no banner,
no left navigation, no breadcrumb. The dev's empirical battery had
included a `textContent` paste of the form fields (which read cleanly
as readable English — content-correctness passed) but no screenshot
and no DOM probe asserting the parent chrome wrapper was present.
Story 6.1 dev + reviewer both passed the surface based on the
content-correctness evidence; the gap surfaced only when the user
opened the page in a browser. Fix bundle landed in commits `2193887`
(chrome refactor + 3 sibling fix-nows) and `d6315f3` (MaxTokens
default downshift). The retrospective AI-1 codified the rule because
the next UI story would have repeated the same failure mode.

**How to apply.**

- At spec-writing time: when an AC asserts a layout/chrome/framing
  property of the rendered surface, the empirical-battery evidence
  block in the spec MUST require a screenshot or a DOM probe — not
  just a `textContent` paste.
- At dev-execution time: when implementing a UI story, capture the
  layout-correctness evidence form that matches each AC's "Then ..."
  clause. If an AC says *"renders inside Mgmt-Portal chrome"*, the
  evidence is a `take_screenshot` of the page showing the chrome OR
  an `evaluate_script` probe asserting `document.querySelector('.PortalBanner') !== null`.
- At review time: a UI story whose layout-correctness AC is backed
  only by `textContent` evidence is a HIGH-severity finding per Rule 8
  (predicted-bug shape: layout drift will ship silently). Block until
  the screenshot or DOM probe is captured.

---

## Application matrix (updated Epic 3 retro)

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
| 12. Rendered-text readability — human-read step in UI-story battery (content-correctness: textContent OK; **layout-correctness: requires screenshot or DOM probe** per Story 7.0 / Epic 6 retro AI-1) | ✓ (UI-story epic-end) | ✓ (smoke-output evidence — match form to AC: textContent for content claims, screenshot/DOM probe for layout claims) | ✓ (blocks on missing evidence; HIGH-severity if layout AC backed only by textContent) |

## How to load these rules in a future cycle

The `/epic-cycle` slash command's pre-flight reads this file alongside `docs/epic-cycle-teams.md`. Both are required reading before any story work begins. See [`.claude/commands/epic-cycle.md`](../commands/epic-cycle.md) for the pre-flight sequence.

For non-cycle work on this project, the lead inherits these rules via the auto-memory feedback entry `feedback_epic_cycle_discipline.md` — see [`MEMORY.md`](../../C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/MEMORY.md).
