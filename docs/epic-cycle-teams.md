# Epic Development Cycle Slash Command

Develop a slash command that executes the BMAD Method development implementation cycle, using Agent Teams, sequentially for a story for all stories in an Epic, or a range of Epics. The task sequence is:

**Per Epic:**
0. **Lead** executes `/bmad-sprint-planning` directly (ensures sprint-status.yaml is current)

**Per Story:**
1. **Lead** executes `/bmad-create-story` directly (no agent — prevents race-ahead)
2. Agent: `/bmad-dev-story`
3. Agent: `/bmad-code-review`  (once the story is developed by previous agent)
4. **Lead**: Commit and Push to Git

**End of Epic:**
5. **Lead** pauses and asks user: "Would you like to run a retrospective?" If yes, execute `/bmad-retrospective`

Make sure to include a file for the slash command in the `/.claude/commands` folder so the workflow can be executed as a slash command.

## Execution Guidelines

**IMPORTANT:** Each task should be executed in Agent Teams using the **spawn-on-demand** pattern.

Automatically resolve all high and medium severity issues found during code review using your best judgment and BMAD guidance.

Stories are to be documented/updated consistently with the instructions in each Skill.

**IMPORTANT:** The BMAD method skills must be used /bmad-create-story, /bmad-dev-story, /bmad-code-review. Don't skip any steps other than the fact that we are doing this in YOLO mode.

## Permission Mode (Critical)

**All agents must be spawned with `mode: "bypassPermissions"`** — this is YOLO mode. Agents should not prompt for file edits, bash commands, or tool permissions. Without this, the pipeline stalls on every file write waiting for human approval.

## Skill Tool Invocation (Critical)

All BMAD skills (`/bmad-create-story`, `/bmad-dev-story`, `/bmad-code-review`) must be invoked via the **`Skill` tool**, not interpreted inline. Agent prompts must explicitly state: "use the `Skill` tool to invoke /bmad-dev-story". Without this directive, agents may attempt to execute the skill logic themselves rather than delegating to the skill definition.

## Spawn-on-Demand Coordination (Critical)

**Do NOT use the task list system** (`TaskCreate`, `TaskList`, `TaskUpdate`). Agents poll TaskList on every wake-up and will self-schedule regardless of prompt instructions, `blockedBy` constraints, or task ownership. This behavior cannot be overridden by prompt text alone.

Instead, the lead tracks pipeline state directly from the epic story list and coordinates agents via **spawn-on-demand**:

### Task-in-Prompt Pattern (Preferred)

Embed the task directly in the agent's spawn prompt rather than using SendMessage after spawning. This is more reliable — agents sometimes go idle without picking up messages sent via SendMessage.

For each pipeline step, the lead:

1. **Spawns** a fresh agent with `mode: "bypassPermissions"` and the full task embedded in the prompt
2. **Uses unique names** per story: `dev-{epic}-{story}` and `cr-{epic}-{story}` (e.g., `dev-2-3`, `cr-2-3`) — never reuse generic names like `developer` or `code-reviewer`
3. **Waits** for the completion message
4. **Shuts down** the agent via `SendMessage(type: "shutdown_request")`
5. **Waits for shutdown approval** — do NOT spawn the next agent until the shutdown confirmation is received (prevents name collisions)

This completely eliminates self-scheduling — terminated agents can't poll TaskList.

### Pipeline Flow

```
For each epic in range:
  Lead executes /bmad-sprint-planning via Skill tool (ensures sprint-status.yaml is current)
  Lead logs sprint planning completion
  Lead reviews previous epic's retrospective (MANDATORY)
  Lead triages all deferred items and action items
  Lead creates Story X.0 via /bmad-create-story (even if all items deferred — documents triage)
  Lead logs retrospective review completion

  For each story in order (including X.0):
    Lead executes /bmad-create-story skill directly via Skill tool (pipeline gate)
    Lead captures story file path from skill output
    Lead spawns developer → dispatches with story file path → waits for completion (captures file list) → shuts down → waits for shutdown approval
    Lead spawns code-reviewer → dispatches with file list from developer → waits for completion → shuts down → waits for shutdown approval
    Lead does feat commit + push (submodules first, then parent — see Submodule Commit Order)
    Lead logs completion → next story

  Lead pauses: "Would you like to run a retrospective?" → if yes, execute /bmad-retrospective via Skill tool
  Lead logs epic completion → next epic
```

### Retrospective Review & Story X.0 Creation (Mandatory Gate)

After sprint planning and before building the story list, the lead must review the previous epic's retrospective and create a cleanup story. **This step is mandatory** — it closes the feedback loop between retrospectives and sprint planning, ensuring deferred items are systematically triaged rather than silently dropped.

1. **Calculate previous epic number** — if processing Epic N, look for Epic N-1's retrospective.
2. **Search for the retrospective file**: `_bmad-output/implementation-artifacts/epic-{N-1}-retro-*.md`
3. **If a retrospective exists**, read it and extract:
   - All **action items** (with status: completed, in-progress, not addressed)
   - All **deferred review findings** from that epic's stories
   - Any **preparation tasks** recommended for the current epic
4. **Also read `_bmad-output/implementation-artifacts/deferred-work.md`** (if it exists) to collect any centralized deferred items not yet resolved.
5. **Triage every item** into one of three categories:
   - **Include in Story X.0** — items relevant to the current epic's codebase or blocking quality
   - **Explicitly defer with rationale** — items not relevant yet (e.g., belongs to a future epic)
   - **Drop** — items already resolved or no longer applicable
6. **Create Story X.0** by executing `/bmad-create-story` with args: `"Story {N}.0: Epic {N-1} Deferred Cleanup"`. The story file should include the full triage table showing each item, its source, and the triage decision. If ALL items are triaged as defer/drop, still create the X.0 story to document the decision.
7. **If no previous retrospective exists** (e.g., Epic 1, or retro was skipped), log that no retrospective was found and skip Story X.0 creation.
8. Log the retrospective review and Story X.0 creation in the cycle log.

This gate was elevated from optional to mandatory after the Epic 6 retrospective revealed that skipping Story X.0 caused deferred items to silently accumulate across multiple epics with no triage.

### Sprint Planning Per Epic (Critical Gate)

Before processing any stories for an epic, the lead must run sprint planning:

1. Execute `/bmad-sprint-planning` directly via the `Skill` tool (NOT via an agent).
2. This ensures `sprint-status.yaml` is current, all stories are tracked, and any status mismatches are caught.
3. If sprint planning surfaces issues, pause and inform the user before proceeding.
4. Log sprint planning completion in the cycle log.

This is a pipeline gate — stories should not be processed until sprint planning confirms the epic's story list is accurate.

### Retrospective Per Epic (User Decision Point)

After all stories in an epic are complete, the lead must pause for the user:

1. Announce epic completion and ask: "Epic X is complete. Would you like to run a retrospective before moving to the next epic? (yes/no)"
2. **Wait for the user's response.** Do NOT proceed automatically.
3. If **yes**: Execute `/bmad-retrospective` directly via the `Skill` tool. This is interactive and requires user participation. Wait for completion before continuing.
4. If **no**: Log that the retrospective was skipped. Continue to the next epic.

Retrospectives surface deferred work, process improvements, and preparation tasks for the next epic. They also update `deferred-work.md` and may create cleanup stories (Story X.0 pattern).

### Lead Creates Story Files (Critical Gate)

The lead executes `/bmad-create-story` directly via the `Skill` tool — NOT via an agent. This is a deliberate pipeline gate that prevents agents from racing ahead. **Capture the story file path** from the skill output to pass to the developer agent.

### Context Handoff Between Stages (Critical)

Each pipeline stage produces output that downstream stages need:

1. **Story creation → Developer**: The lead passes the **story file path** from `/bmad-create-story` output to the developer agent.
2. **Developer → Code reviewer**: The developer's completion message must include **all files created/modified with full paths**. The lead includes this file list in the code reviewer's dispatch message.
3. **Code reviewer → Commit**: The lead uses file lists from both agents to stage the correct files for commit.

Without explicit context handoff, downstream agents lack the information to do their job effectively.

### Shutdown-Before-Respawn Sequencing (Critical)

After sending `SendMessage(type: "shutdown_request")`, **wait for the shutdown approval message** before spawning the next agent. Agent shutdown is asynchronous — an idle notification may arrive before the shutdown approval. If you spawn a new agent with the same name (e.g., `developer`) before the old one terminates, you get a name collision.

Pattern:
```
Lead sends shutdown_request → may receive idle notification → receives shutdown_approved → safe to spawn next agent
```

### Agent Prompt Requirements

Each agent's spawn prompt must include:

```
**CRITICAL — Single-Task Agent:**
- You will receive exactly ONE task via SendMessage from the lead.
- Execute the workflow for that task using the `Skill` tool to invoke the specified BMAD skill.
- When done, send a completion message to the lead including:
  - All files created or modified (full paths)
  - Key decisions made
  - Any issues encountered and how they were resolved
- After sending the completion message, STOP completely.
- Do NOT call TaskList, do NOT look for more work.
- Approve any shutdown request immediately.
- Do NOT use TaskList, TaskCreate, or TaskUpdate.
- If you encounter ambiguous requirements or need user input, send a message to the lead describing the issue clearly. Do NOT proceed until the lead responds.

Wait for the lead to send you your task. Do NOT start any work until the lead messages you.
```

## When to Pause

Within each agent in the Agent Team, only pause to ask me a question if:

- The acceptance criteria or requirements are ambiguous
- There are multiple reasonable design options and my preference matters
- Proceeding would risk breaking important constraints (security, compliance, performance, interoperability)

## Handling Clarifications

When an agent needs clarification, it sends a message to the lead instead of a completion message. The lead must handle this correctly:

1. **Do NOT shut down the agent** — it is waiting for a response, not finished.
2. Surface the agent's question to the user in the main conversation, including the Story ID and relevant context.
3. Wait for the user's answer.
4. Relay the user's answer back to the agent via `SendMessage`, incorporating it as a hard constraint.
5. The agent resumes its workflow and eventually sends a completion message.
6. Proceed with normal shutdown only after receiving the completion message.

**Key distinction:** A clarification message is NOT a completion message. The lead must differentiate between "I'm done, here are the results" and "I have a question, please advise."

## Submodule Commit Order (Critical)

`src/MA` and `src/MALIB` are **git submodules** pointing to separate repositories. When stories modify files in these directories, the commit and push sequence matters:

1. **Commit and push inside each affected submodule first** (`git -C src/MA add ... && git -C src/MA commit && git -C src/MA push`)
2. **Then commit and push in the parent repo**, staging both parent-repo files and the updated submodule pointers (`git add src/MA src/MALIB`)

If the parent repo is pushed with a submodule pointer that doesn't exist on the submodule's remote, other developers will get checkout failures. Always submodules-first.

The lead should check `git -C src/MA status --short` and `git -C src/MALIB status --short` after each story to determine which submodules (if any) have changes.

## Completion Logging

At the completion of each story, write a brief log entry summarizing:

- Story ID/name
- Files touched
- Key design decisions
- Any issues auto-resolved vs. those that required my input

## Anti-Patterns (Do NOT Use)

These patterns were tested and failed due to agent self-scheduling behavior:

- **TaskCreate/TaskList/TaskUpdate** — Agents poll TaskList on every wake-up and grab tasks regardless of `blockedBy`, prompt instructions, or task ownership
- **Persistent agents between tasks** — Idle agents self-schedule. Always shut down after each task
- **`blockedBy` constraints** — The task system does NOT enforce `blockedBy`. Agents work out of order
- **Lead-owned task parking** — Assigning tasks to "team-lead" is unreliable; agents still find and grab tasks
- **Self-scheduling prompts** — "Do NOT call TaskList" is unreliable; agents have built-in polling behavior that overrides prompt instructions
- **Story-creator agent** — A story-creator agent races ahead to create story files for future stories, enabling other agents to self-schedule. The lead must create story files directly as a pipeline gate
- **Spawning without permission mode** — Without `mode: "bypassPermissions"`, agents prompt for every file edit and bash command, stalling the pipeline
- **Spawning before shutdown confirms** — Reusing an agent name before the previous agent's shutdown is confirmed causes name collisions
- **Inline skill execution** — Agents interpreting skill logic themselves instead of invoking via the `Skill` tool; always specify `Skill` tool usage explicitly in prompts
- **Missing context handoff** — Not passing file lists between stages; code reviewers can't review effectively without knowing which files changed
- **Parent-before-submodule push** — Pushing the parent repo before submodule commits are pushed leaves broken submodule pointers on the remote; always commit and push submodules first
- **Generic agent names** — Using `developer` and `code-reviewer` across stories causes stale shutdown requests to be picked up by new agents. Always use unique names like `dev-2-3`, `cr-2-3`
- **Spawn-then-message pattern** — Agents sometimes go idle without picking up SendMessage dispatches. Task-in-prompt pattern (embedding the task in the spawn prompt) is more reliable
- **Normalizing known test failures** — Carrying forward "4 pre-existing failures, unrelated" across an entire epic erodes baseline reliability. Fix or formally defer in deferred-work.md immediately
- **Deferred findings only in story files** — Without centralized tracking in deferred-work.md, deferred items are invisible. Code reviewer prompts must explicitly require logging to deferred-work.md
- **Reading only from epics.md** — Sprint-status.yaml may contain additional stories (cleanup stories from retrospectives, hotfixes). Build story list from both sources
- **Skipping retrospective review before epic start** — Without explicitly reading the previous retro and triaging deferred items, action items and deferred findings silently accumulate. The retrospective review + Story X.0 creation step is mandatory even if the previous epic had no HIGH-severity items

## Lead Discipline (load-bearing rules)

The lead's behavior across the cycle is governed by [`.claude/rules/epic-cycle-discipline.md`](../.claude/rules/epic-cycle-discipline.md). **Read that file in pre-flight before starting any cycle.** As of the Epic 3 retrospective (2026-05-03) the rule count is **12** — the file is the durable capture of the Epic 1, Epic 2, and Epic 3 retrospective lessons:

1. Spec length governance (≤ 250 lines)
2. No `[x]` without verification — ever
3. Higher-level MCP before generic `iris_execute_command`
4. Stale-reference scan at story start
5. One-liner check before deferring
6. Self-initiated empirical test pass at epic end (sharpened Epic 3 retro: rich-data battery)
7. Operator setup at sprint planning
8. Defer threshold raised — "fix now" is the default
9. Predicted-bug deferrals binding on the named successor
10. External-default research at spec time (Perplexity-mandatory)
11. Live integration smoke test mandatory when external API is in scope
12. Rendered-text readability — human-read step in every UI-story empirical battery (added Epic 3 retro)

Each rule is grounded in a specific incident requiring user intervention from one of the first three epics. The rule file documents the trigger, rule, rationale, and how-to-apply for each.

## Lessons Learned (Epic 1 Retrospective — 2026-05-02, real)

1. **Task-0 backend-surface probes earned their keep three times.** Web Gateway timeout label (1.2), `Security.Roles` `%`-prefix rejection (1.4), `%SYS.Task` Name non-uniqueness (1.5). All three would have shipped as bugs without the probe. **Implication:** keep Task-0 probes mandatory for every story that touches a new IRIS-side dependency.
2. **Discover-and-propagate beats fix-and-forget.** When a cross-cutting finding emerges (RBAC role rename, IPM mapping, HSCUSTOMCODE non-existence), the same commit must update every canonical artifact — README, architecture, prd, epics, distillate, project memory. Story 1.4's RBAC rename and Story 1.6's HSCUSTOMCODE correction set the precedent.
3. **Honest about partial state preserves operator trust.** `docs/operator-quickstart.md` explicitly says "the chat tab doesn't exist yet — Epic 3 ships it" instead of pretending. SQL verification step uses real Epic-1 state (`Security.Events` + `Security.Roles`), not the not-yet-shipped audit ledger tables.
4. **Mid-epic process shift: ~3× token efficiency for equal quality.** Stories 1.1–1.4 used the full dev-agent + reviewer-agent pipeline. Stories 1.5–1.7 used collaborative inline implementation by lead with empirical verification. Same outcome, ~1/3 the token spend. The user-prompted shift was load-bearing — without it the second half would have cost ~3× more for no measurable quality benefit.
5. **Auto-sync workflow change** (`.vscode/settings.json` with `objectscript.conn.active=true`) eliminates the `iris_doc_load` round-trip per file edit. Saves ~5–15 KB tokens per ObjectScript story edit cycle. Codified in `.claude/rules/iris-objectscript-basics.md` §"VSCode Auto-Sync Workflow".
6. **Story X.0 cleanup pattern (MANDATORY)** — Epic 1 had no previous retrospective so Story 1.0 was skipped per the documented "no retrospective found" path. Epic 2 onward will see Story X.0 fire on every cycle: read previous retro, triage action items + deferred findings, create the cleanup story (even if all items defer/drop, to document the triage decision).
