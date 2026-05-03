---
description: Run the BMAD development cycle (sprint planning → stories → dev → code review → commit → retro) across one or more epics using spawn-on-demand agent teams
argument-hint: <epic-number> | <start>-<end>   (e.g., "5" or "5-7")
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent, SendMessage, TaskOutput, AskUserQuestion]
---

# /epic-cycle — Multi-Agent BMAD Development Pipeline

You are the **Lead** for a BMAD-Method development pipeline. The user invoked this command with: `$ARGUMENTS`

Your job is to drive every story in the requested epic(s) through:

```
sprint-planning → retro-review → Story X.0 → (per story: create → dev → code-review → commit) → end-of-epic retro
```

…using the **spawn-on-demand agent team** pattern documented in `docs/epic-cycle-teams.md`. **Read that file before you start** — it is the source of truth and contains failure modes you must avoid.

---

## Argument Parsing

Parse `$ARGUMENTS` into a list of epic numbers:

- `5` → `[5]`
- `5-7` → `[5, 6, 7]`
- Empty / missing → ask the user which epic(s) to run; do not guess.
- Invalid (non-numeric, reverse range, etc.) → stop and report the parse error.

State the resolved epic list back to the user in one sentence before starting.

---

## Pre-Flight (run once, before the first epic)

1. **Read `docs/epic-cycle-teams.md`** in full. Internalize the Anti-Patterns section.
2. **Verify BMAD artifacts exist**: `_bmad-output/planning-artifacts/epics.md` (and `prd.md`, `architecture.md`). If missing, stop and tell the user — there is nothing to develop.
3. **Locate sprint-status**: `_bmad-output/implementation-artifacts/sprint-status.yaml` may not exist yet on a fresh project. The first `/bmad-sprint-planning` call will create it.
4. **Check submodule presence**: run `git config --file .gitmodules --get-regexp path` to discover any submodules. Record the list — you'll need it for the per-story commit step. (On this project, none currently exist; that may change.)
5. **Initialize a cycle log** in memory (you will print a final summary at the end). For each epic/story you process, record: epic, story, agents spawned, files touched, issues, auto-resolved-vs-asked.

---

## Per-Epic Loop

For each epic `N` in the resolved list, in ascending order:

### Step 1 — Sprint Planning Gate

- Invoke `/bmad-sprint-planning` **directly via the `Skill` tool** (NOT via an agent).
- If the skill surfaces inconsistencies (story missing from sprint-status, status mismatch, etc.), pause and tell the user before continuing.
- Log: `epic-{N}: sprint-planning complete`.

### Step 2 — Retrospective Review & Story X.0 (Mandatory Gate)

- Compute previous epic number `P = N - 1`.
- If `P >= 1`, search `_bmad-output/implementation-artifacts/` for `epic-{P}-retro-*.md`:
  - **If found**: read it. Extract every action item (with status), every deferred review finding, and any preparation tasks recommended for epic `N`.
  - **Also read** `_bmad-output/implementation-artifacts/deferred-work.md` if it exists. Collect any unresolved items not yet triaged.
  - **Triage every item** into one of three buckets and record the rationale:
    1. **Include in Story `{N}.0`** — relevant to this epic's codebase or blocks quality.
    2. **Explicitly defer with rationale** — belongs to a future epic.
    3. **Drop** — already resolved or no longer applicable.
  - Create Story `{N}.0` by invoking `/bmad-create-story` via the `Skill` tool with args: `"Story {N}.0: Epic {P} Deferred Cleanup"`. The triage table (item, source, decision, rationale) must appear in the story body. **Create Story X.0 even if every item triages to defer/drop** — the story is the audit trail.
  - **If not found** (e.g., `N == 1`, or retro skipped): log "no retrospective found for epic {P}; skipping Story {N}.0 creation" and continue.
- Log: `epic-{N}: retro-review complete`.

### Step 3 — Build Story List

- Read both `_bmad-output/planning-artifacts/epics.md` AND `sprint-status.yaml` for epic `N`. Merge: sprint-status may contain hotfixes / cleanup stories that aren't in epics.md (this is one of the Anti-Patterns — don't build the list from epics.md alone).
- Order: Story `{N}.0` first (if created), then `{N}.1`, `{N}.2`, … in ascending order.
- Skip stories whose sprint-status is already **`done`** (resume support — see Lessons Learned #6).

### Step 4 — Per-Story Pipeline

For each story `{N}.{S}` in the ordered list:

#### 4a. Lead creates the story file (pipeline gate)

- Invoke `/bmad-create-story` **via the `Skill` tool** with args naming the specific story (e.g., `"Story {N}.{S}"`). The lead does this directly — never delegate to an agent (Anti-Pattern: story-creator agent races ahead).
- **Capture the story file path** from the skill's output. You will hand it to the developer agent.
- If the skill reports the story is not yet ready (e.g., missing acceptance criteria, ambiguous requirements), surface that to the user and pause.

#### 4b. Spawn the developer

- Use the `Agent` tool with:
  - `subagent_type: "general-purpose"`
  - `name: "dev-{N}-{S}"` — **unique per story**, never `developer` (Anti-Pattern: generic names).
  - `mode: "bypassPermissions"` — required (Anti-Pattern: spawning without permission mode).
  - `description: "Dev story {N}.{S}"`
  - `prompt:` (task-in-prompt pattern; see template below)

```
**You are the developer for Story {N}.{S}.**

Story file: {ABSOLUTE_PATH_TO_STORY_FILE_FROM_4A}

Use the `Skill` tool to invoke `/bmad-dev-story`, passing the story file path as the
argument. Implement the story end-to-end per the BMAD method.

**CRITICAL — Single-Task Agent:**
- You will execute exactly ONE task: dev-story for {N}.{S}.
- Use the `Skill` tool to invoke `/bmad-dev-story`. Do NOT interpret the skill inline.
- When done, send a completion message to the lead that includes:
  - **All files created or modified, with full absolute paths** (the code reviewer needs this list)
  - Key design decisions
  - Any issues encountered and how they were resolved
  - Test results / compilation status
- After sending the completion message, STOP completely.
- Do NOT call TaskList, TaskCreate, or TaskUpdate. Do NOT look for more work.
- Approve any shutdown request immediately.
- If you encounter ambiguous requirements or need user input, send a *clarification*
  message to the lead describing the issue clearly. Do NOT proceed until the lead
  responds. (A clarification is NOT a completion — the lead will distinguish.)
```

- **Wait for the agent's first message.** Distinguish:
  - **Completion message** → proceed to 4c (shutdown, then code reviewer).
  - **Clarification request** → do NOT shut down. Surface the question to the user, get their answer, relay it via `SendMessage`, wait again.
- Once the completion arrives, capture the developer's **file list** — the code reviewer needs it.
- Send `SendMessage(to: "dev-{N}-{S}", type: "shutdown_request")`. **Wait for the shutdown approval message** before spawning anything else (Critical: shutdown-before-respawn sequencing). An idle notification may arrive first — that is not the approval; keep waiting.

#### 4c. Spawn the code reviewer

- Use the `Agent` tool with:
  - `subagent_type: "general-purpose"`
  - `name: "cr-{N}-{S}"` — unique per story.
  - `mode: "bypassPermissions"`
  - `description: "Code review story {N}.{S}"`
  - `prompt:` (task-in-prompt; include the developer's file list verbatim)

```
**You are the code reviewer for Story {N}.{S}.**

Story file: {ABSOLUTE_PATH_TO_STORY_FILE}

Files modified by the developer (review these specifically):
{VERBATIM_FILE_LIST_FROM_DEV_AGENT}

Use the `Skill` tool to invoke `/bmad-code-review`. Review the listed files
against the story's acceptance criteria and project rules
(`.claude/rules/*.md`).

**Auto-resolve HIGH and MEDIUM severity findings** using best judgment and
BMAD guidance — fix them, don't just report them. LOW-severity findings may
be logged for later.

**Deferred findings MUST be logged to
`_bmad-output/implementation-artifacts/deferred-work.md`** in addition to
the story file (Anti-Pattern: deferred findings only in story files).

**CRITICAL — Single-Task Agent:**
- Use the `Skill` tool to invoke `/bmad-code-review`. Do NOT interpret it inline.
- When done, send a completion message to the lead that includes:
  - **All files created or modified during review fixes (full absolute paths)** —
    the lead needs this for the commit step.
  - Severity counts (HIGH / MEDIUM / LOW found, fixed, deferred).
  - Any items added to `deferred-work.md` with their rationale.
- After sending, STOP. Approve shutdown immediately.
- Do NOT call TaskList. If unsure, send a clarification message instead of guessing.
```

- Same wait-then-distinguish protocol as 4b. Capture the reviewer's file list (it may have added fixes on top of the developer's set).
- Send `shutdown_request`, wait for shutdown approval.

#### 4d. Lead commits and pushes

- Compute the **combined file list** = dev files ∪ reviewer files.
- **Submodule-first commit order** (Critical):
  1. For each submodule path (from pre-flight): run `git -C {submodule} status --short`. If non-empty, `git -C {submodule} add {its files}`, `git -C {submodule} commit -m "feat(epic-{N}): story {N}.{S} — {short title}"`, `git -C {submodule} push`.
  2. **Then** in the parent repo: stage parent-repo files AND any updated submodule pointers (`git add {parent files} {submodule paths}`), commit with the same `feat(epic-{N})` style message, push.
- Use a HEREDOC for the commit message; end with the Co-Authored-By line per `~/.claude/CLAUDE.md` commit conventions. Do NOT skip hooks.
- If `git push` fails (auth, network, hook), **stop the pipeline** and surface the failure to the user — do not silently continue with an unpushed commit.
- Log: `epic-{N}: story {N}.{S} complete` with the bullet summary defined in "Completion Logging" below.

### Step 5 — End-of-Epic Retrospective Decision

After the last story in epic `N`:

- Use `AskUserQuestion` to ask: *"Epic {N} is complete. Would you like to run a retrospective before moving to the next epic? (yes / no)"*
- **Wait for the user's answer.** Do NOT auto-run.
- **yes** → invoke `/bmad-retrospective` via the `Skill` tool. This is interactive; let the user drive it. Wait for completion.
- **no** → log "epic-{N}: retrospective skipped per user".
- Log: `epic-{N}: complete`.

Continue to the next epic in the list.

---

## Completion Logging (per story)

For each story, append to the cycle log a short bullet block:

```
- Story {N}.{S} — {title}
  - Files: {short list — paths only, comma-separated, truncate to ~10 with "+N more"}
  - Key decisions: {1-line each, max 3}
  - Auto-resolved: {count} | Required user input: {count}
  - Commit: {short SHA from parent-repo commit}
```

At the very end of `/epic-cycle`, print the full cycle log to the user as the final message.

---

## Pause / Escalation Triggers

Pause the pipeline and ask the user when:

- A skill (sprint-planning, create-story, retrospective) reports an error you can't auto-resolve.
- An agent sends a **clarification message** (not a completion). Surface it verbatim with story context.
- `git push` fails for any reason (don't try to bypass with `--force`, `--no-verify`, etc.).
- A story's acceptance criteria are genuinely ambiguous after the dev agent reports back.
- Any pre-flight check fails (missing artifacts, malformed argument, etc.).

Do NOT pause for routine MEDIUM/HIGH code-review findings — those auto-resolve per the prompt template above.

---

## Anti-Patterns — Do NOT Use

(Reminder; full list in `docs/epic-cycle-teams.md`.)

- ❌ `TaskCreate` / `TaskList` / `TaskUpdate` — agents poll and self-schedule.
- ❌ Persistent agents between stories — always shut down after each task.
- ❌ Generic agent names (`developer`, `code-reviewer`) — always `dev-{N}-{S}` / `cr-{N}-{S}`.
- ❌ Spawning without `mode: "bypassPermissions"`.
- ❌ Inline skill execution by agents — always direct them to use the `Skill` tool.
- ❌ Spawning the next agent before shutdown is **approved** (idle notification ≠ approval).
- ❌ Pushing the parent repo before submodule pushes complete.
- ❌ Building the story list from `epics.md` alone — also read `sprint-status.yaml`.
- ❌ Skipping retrospective review / Story X.0 when a previous retro exists.
- ❌ A "story-creator" agent — the lead creates story files directly.

---

## Start

Once you've parsed `$ARGUMENTS` and finished pre-flight, state the plan to the user in 2–3 sentences (epic list, story count if known, expected commits) and then begin Epic 1 of the resolved list. Drive the pipeline to completion, pausing only on the triggers above.
