# Story 1.2: Web Gateway Timeout Task-0 Probe + README Operator Prerequisites

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an **Operator-Admin (Aishah-class)**,
I want the README's `## Operator Prerequisites` section to document the three install-blocking prerequisites — Web Gateway timeout raise, RBAC role grant, and LLM provider API key supply — with concrete, **verbatim default values captured from a live 2024.1+ instance**,
so that I can complete the prerequisites in under 30 minutes (NFR-O1) before installing the product, without trial-and-error against the Web Gateway management page.

This story executes the **first Task-0 probe in the project** (per [research-first.md §"Task 0 backend-surface probe"](../../.claude/rules/research-first.md)) — capturing the Web Gateway's "Server Response Timeout" default value from the actual installed IRIS gateway, then embedding that verbatim into the README so future operators see a real number ("raise from 30s → 300s"), not a hand-waved "raise the default."

## Acceptance Criteria

**AC-1 — Task-0 probe captures the Web Gateway "Server Response Timeout" verbatim default.**

**Given** the developer is preparing the Operator Prerequisites README content
**When** they run the Task-0 probe to capture the Web Gateway "Server Response Timeout" verbatim default value (per [architecture.md §"Carry-forward Task-0 probes" Epic 1](../../_bmad-output/planning-artifacts/architecture.md), G3 in Gap Analysis: *"Web Gateway 60s default Task-0 probe (capture verbatim from operator's gateway)"*)
**Then** the captured value is recorded verbatim in this story's **Task 0 Output** section below
**And** the IRIS version that was probed is recorded (e.g., "IRIS for Health 2025.1.x" — captured during Story 1.1's `zpm load` verification)
**And** the probe method (which page / which command produced the value) is documented so future operators can re-run it on their own gateways

**AC-2 — README §"Operator Prerequisites" enumerates the three steps in order with the captured value embedded.**

**Given** the operator opens the README
**When** they navigate to `## Operator Prerequisites`
**Then** the section enumerates exactly three concrete steps in this order:

1. **Raise Web Gateway "Server Response Timeout"** from `<verbatim-probed-default>s` → **300s**, with the documented reason: *"LLM-call latencies often sit in the 30–90s band; the default kills them mid-stream. The 300s value gives a 90s per-call cap × 3-tool-call agent turn comfortable headroom — see [PRD NFR-P1](../../_bmad-output/planning-artifacts/prd.md) and [architecture line 1131](../../_bmad-output/planning-artifacts/architecture.md) for the timeout-cascade rationale."*
2. **Grant `%SessionAgent_ReadOnly` role** to the operator user/role (deferred until Story 1.4 ships the role; the README can call out "the install creates this role automatically — assign it after install")
3. **Supply LLM provider API key** — env-var (preferred for containers, e.g., `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GOOGLE_API_KEY`) OR `Ens.Config.Credentials` row (traditional installs, with `SystemName='openai-prod'` style and the `SessionAgent.Config.Agent.CredentialName` pointer)

**AC-3 — README shows BOTH Mgmt Portal bookmark URL patterns.**

**Given** the operator reads the Operator Prerequisites section
**When** they reach the bookmark / post-install navigation guidance
**Then** the section shows BOTH URL patterns:

- **HealthShare:** `/csp/healthshare/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`
- **Plain IRIS:** `/csp/<NS>/SessionAgent.EnsPortal.{VisualTrace,MessageViewer}.zen`

**And** each pattern has a one-line note explaining when each applies (HealthShare deployments use the `/healthshare/` prefix; plain IRIS deployments do not).

**AC-4 — Section is positioned as the first H2 after the project introduction.**

**Given** the operator is reading the README top-to-bottom
**When** they scroll past the project header, the under-construction banner, and the one-paragraph orientation
**Then** `## Operator Prerequisites` is the **first H2 heading** they encounter (per [Aishah Journey 3 expectation](../../_bmad-output/planning-artifacts/ux-design-specification.md): *"prerequisites precede the install command"*).
**Note:** Story 1.1 already established this positioning. Story 1.2 must **preserve** it while expanding the section's body content — do not move the H2 heading.

**AC-5 — README path to the Web Gateway timeout setting matches a verifiable IRIS 2024.1+ administrative path.**

**Given** the operator follows the README's navigation breadcrumb to the Web Gateway timeout setting
**When** they navigate per the README's instructions (e.g., `Web Gateway management page (typically http://<host>/csp/bin/Systems/Module.cxw) → System Default Parameters → Server Response Timeout`)
**Then** the change is verifiable: the operator can locate the exact setting at the documented path on the live IRIS 2024.1+ Web Gateway management page
**And** the probe output (Task 0 Output section) confirms the path was traversed during the probe — i.e., the probe is the proof that the documented path is correct

## Task 0 — Backend-surface probe (capture before authoring README content)

Per [research-first.md §"Task 0 backend-surface probe"](../../.claude/rules/research-first.md), this story **cannot author the README content** until the probe captures the actual Web Gateway "Server Response Timeout" default value. Authoring without the probe risks shipping a hand-waved value ("raise the default to 300") that doesn't match what operators see on their own gateways.

### Probe approach (pick one; doc the choice)

**Option A — Chrome DevTools MCP (preferred when the gateway is HTTP-reachable):**

1. Use `mcp__chrome-devtools-mcp__new_page` to open `http://<iris-host>:<port>/csp/bin/Systems/Module.cxw` (the Web Gateway management page; auth credentials default `CSPSystem` / the OS-installed gateway password — operator is local to this dev box).
2. Navigate to **System Default Parameters** (left-nav).
3. Use `mcp__chrome-devtools-mcp__take_snapshot` to capture the page state including the **"Server Response Timeout"** field's current value.
4. Record the value verbatim (e.g., `30 seconds`, `60 seconds`, `300 seconds` — whatever the live default reports).
5. Capture a screenshot for the story file as evidence (`mcp__chrome-devtools-mcp__take_screenshot`).

**Option B — Filesystem inspection (fallback if the gateway management page isn't HTTP-reachable from this dev environment):**

1. Locate the Web Gateway config file. On Windows IRIS installs it's typically under `<install-dir>\csp\CSP.ini` or `<install-dir>\csp\CSP.conf`. On Linux: `/usr/irissys/csp/CSP.ini` (or per the IRIS install layout).
2. Grep for `Server_Response_Timeout` (or equivalent — the exact key name varies by gateway version; check both `Server_Response_Timeout` and `ServerResponseTimeout`).
3. Capture the verbatim value as the probe output.

**Option C — IRIS class lookup (last resort):**

1. Use `mcp__iris-dev-mcp__iris_execute_command` with: `Write ##class(%CSP.Mgr.GatewayMgr).%New().GetServerResponseTimeout()` (or equivalent — the dev should look up the actual API in `irislib/%CSP.Mgr/*.cls` first per project rule "IRIS Library Source").

### Required Task 0 output (paste into this story's "Task 0 Output" section before continuing to Tasks 1–4)

```
Probe method:        <A | B | C>
IRIS version probed: <IRIS for Health 2025.1.x — copy-paste from `iris session IRIS -U %SYS "Write $zv"` output>
Verbatim default:    <e.g., "30 seconds" — exact wording as it appeared on the gateway page or config>
Path traversed:      <e.g., "Web Gateway → System Default Parameters → Server Response Timeout">
Screenshot/log:      <relative path to a captured screenshot under _bmad-output/implementation-artifacts/probes/, OR a verbatim CSP.ini snippet, OR the raw command output>
```

If the dev cannot reach the gateway management page AND cannot find the config file AND cannot find an IRIS class for the gateway timeout, **escalate to the lead via clarification** — do not author the README with a guessed value.

## Tasks / Subtasks

- [x] **Task 0 — Run the Web Gateway timeout probe (AC: #1, #5)**
  - [x] Identify the IRIS Web Gateway management URL on the local dev IRIS instance (try `http://localhost:52773/csp/bin/Systems/Module.cxw` first; the port may differ on this install — check the `iris list` output if uncertain)
  - [x] Pick a probe option (A / B / C) per the approach above; document the choice
  - [x] Capture the verbatim default value, IRIS version, and probe method in this story's **Task 0 Output** section below
  - [x] If Option A succeeded, save a screenshot under `_bmad-output/implementation-artifacts/probes/story-1-2-webgateway-timeout-probe-<date>.png`

- [x] **Task 1 — Author full Operator Prerequisites README content (AC: #2, #3, #4)**
  - [x] Read the existing `README.md` first (Story 1.1 added a placeholder `## Operator Prerequisites` section at line 12; the placeholder body is currently 1 sentence + 3 bullet stubs — the canonical README structure to expand into is laid out in [research §"Operator README Content" lines 1587–1638](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md))
  - [x] **Replace the placeholder body** (NOT the heading; preserve the H2 heading position) with the full content per [research §"Operator README Content"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md), with these adaptations:
    - The `### 2. Web Gateway timeout` paragraph must use the **probed verbatim default** (Task 0 output) — replace the research doc's `60s` with the actual probed value if different
    - The `### 6. Bookmark URL` block must show **BOTH** patterns (HealthShare AND plain IRIS), one per line, with a one-line note explaining when each applies
    - The `### 5. RBAC` paragraph must call out that *"the installer creates `%SessionAgent_ReadOnly` automatically — assign it to operator users after install completes"* (deferred behavior; Story 1.4 ships the role install)
    - The `### 7. Daily purge task` paragraph stays as-is (Story 7.2 ships the task; the README can describe the planned behavior)
  - [x] Section header structure: keep `## Operator Prerequisites` as the H2; use `### 1.` through `### 7.` H3s for the seven sub-steps per the research doc shape
  - [x] Preserve all existing README content that is NOT the placeholder body (under-construction banner, project intro, "What it does", "Status", "Development Plan", "Planning Artifacts (BMAD)", "Project posture", "Contributing")

- [x] **Task 2 — Verify the README's documented Web Gateway path matches the live administrative path (AC: #5)**
  - [x] If Task 0 used Option A (Chrome DevTools navigation), the path was already traversed during the probe — confirm it matches what's written in the README's `### 2.` paragraph
  - [x] If Task 0 used Option B or C, manually verify the path by navigating the live gateway management page to the documented setting (or by re-running the probe with Option A as a cross-check)
  - [x] Update the README path text if the probe revealed a different navigation breadcrumb

- [x] **Task 3 — Render the README locally and visually verify positioning (AC: #4)**
  - [x] Open the updated `README.md` in a markdown previewer (VSCode's built-in preview, or `gh markdown-preview`, or any equivalent) *(verified by reading the rendered grep output of `^## ` headings; `## Operator Prerequisites` is at line 12, immediately after the project header at line 1, the under-construction warning at lines 3–6, the project intro at line 8, and the tagline at line 10 — i.e., it is the first H2 the operator encounters when reading top-to-bottom)*
  - [x] Confirm `## Operator Prerequisites` is the first H2 after the project introduction (under-construction banner + intro paragraphs are above it; "What it does" comes after it) *(grep confirmed H2 ordering: 1. Operator Prerequisites @12, 2. What it does @78, 3. Status @95, 4. Development Plan @109, 5. Planning Artifacts (BMAD) @135, 6. Project posture @156, 7. Contributing @164)*
  - [x] Confirm both bookmark URL patterns render as inline code blocks (not as clickable links) *(both patterns are wrapped in backticks in the source markdown lines 66–70 — they will render as inline `<code>` elements in any standard markdown renderer, not as `<a href="...">` clickable links because they are not formal `[text](url)` links and they don't start with `http://` or `https://` schemes that would trigger autolinking)*

- [x] **Task 4 — Verify story dev notes accurately log the captured probe output**
  - [x] Move the captured Task 0 Output values from the **Task 0 Output** section to the **Completion Notes** section of the **Dev Agent Record** (so they're retrievable from the standard story-file completion log)
  - [x] Reference the screenshot path (if any) in the Completion Notes
  - [x] Confirm `Status: review` flip after all tasks are complete

## Task 0 Output

```
Probe method:        A (Chrome DevTools MCP — live Web Gateway management page) + B (CSP.ini cross-check) + C (irislib source-doc cross-check)
IRIS version probed: IRIS for Windows (x86-64) 2025.1 (Build 230.2U) Wed Jun 4 2025 18:53:21 EDT — HealthShare feature enabled
Verbatim default:    60 (seconds) — field labeled "Server Response Timeout:" in the live management page; field tooltip: "Max number of seconds allowed for InterSystems IRIS to respond before returning the 'Server Busy' error, between 1 and 2147483647"
Path traversed:      http://localhost:52773/csp/bin/Systems/Module.cxw → Login (CSPSystem) → Configuration → Default Parameters → "Connections to InterSystems IRIS" group → "Server Response Timeout" field
Screenshot/log:      _bmad-output/implementation-artifacts/probes/story-1-2-webgateway-timeout-probe-2026-05-02.png (full-page screenshot of the live Default Parameters page showing Server Response Timeout = 60)
```

### Probe cross-checks (three independent sources converge on `60`)

1. **Option A — Chrome DevTools MCP (live management page):** The actual rendered "Server Response Timeout" textbox on `http://localhost:52773/csp/bin/Systems/Module.cxw → Default Parameters` shows `value="60"`. This is the value the operator sees today.
2. **Option B — Filesystem inspection (`C:\InterSystems\IRISHealth\CSP\bin\CSP.ini`):** Section `[SYSTEM]` line `Server_Response_Timeout=60`. This is the on-disk persisted form.
3. **Option C — IRIS source documentation (`irislib\%CSP\Mgr\GatewayMgr.cls` line 157):** The class-level doc-comment example for the `sys_get_CSP_ini` callback shows `ini("[SYSTEM]","Server_Response_Timeout")=60`, confirming `60` is InterSystems' documented default.

### Path-label corrections vs. story stub

The story stub's tentative path was `Web Gateway management page → System Default Parameters → Server Response Timeout`. The live UI uses these **exact** labels:

- Left-nav section header: **Configuration**
- Menu item: **Default Parameters** (not "System Default Parameters")
- Group heading on the form: **Connections to InterSystems IRIS**
- Field label: **Server Response Timeout** (with a colon in the rendered UI: `Server Response Timeout:`)

The README will use the live-verified labels.

## Dev Notes

### Why the Task-0 probe is mandatory for this story

This is the **first Task-0 probe in the project**, executed under the [research-first.md §"Task 0 backend-surface probe"](../../.claude/rules/research-first.md) rule. The cited failure mode (from the rule itself):

> *"Story 12.4 (Python JSRuntime backend) was specced, context-filled, and the dev agent was dispatched before anyone verified that `%SYS.Python.Import("sys")` succeeded on the dev host — it did not, and the entire story was deferred."*

For Story 1.2, the analogous failure is shipping the README with a hand-waved Web Gateway default. Operators on different IRIS versions / different platforms see different defaults. If we ship `60s` and the operator's gateway shows `30s`, they'll wonder if the doc is wrong or if their install is misconfigured. **The verbatim probe is the single most operator-trust-building action this story takes.**

### What's in the existing README that must be preserved (UPDATE-not-REPLACE inventory)

Per [Story 1.1](1-1-project-initialization.md), `README.md` already contains:

- **Project header** (`# iris-session-agent`) — line 1
- **Under-construction warning blockquote** — lines 3–6 (referencing Epic 1 Story 1.1; this paragraph is now stale because Story 1.1 has shipped — leave it; Story 1.6 quickstart doc / Story 1.7 CI scaffolding may revise it)
- **One-paragraph project orientation** — lines 8–10
- **`## Operator Prerequisites` H2** — line 12 (PLACEHOLDER body; this story REPLACES the body, KEEPS the heading)
- **`## What it does`** through **`## Contributing`** — lines 22–end (PRESERVE entirely; do not edit)

The story's mandate is to **expand the Operator Prerequisites body**. All other README sections stay byte-identical.

### Why both bookmark URL patterns are required, not just one

[Architecture line 1071](../../_bmad-output/planning-artifacts/architecture.md) and [research §"Operator README Content"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) both call out that the project must support **both** HealthShare and plain-IRIS deployments. The URL prefix differs by deployment:

- HealthShare adds an extra `/healthshare/` segment between `/csp/` and the namespace
- Plain IRIS does not

If we document only one pattern, half the operator audience will copy-paste a 404. Per [PRD FR52](../../_bmad-output/planning-artifacts/prd.md): the README must show both patterns.

### Why the RBAC step references a role that doesn't exist yet

Story 1.4 ships `SessionAgent.Security.ReadOnlyRole.Install`, which creates `%SessionAgent_ReadOnly` at install time. Story 1.2's README content is written **forward-looking** — it tells the operator what will exist after install, not what exists today. By the time this README ships in any non-pre-alpha distribution (Epic 3 first-delight demo per the Status section), Stories 1.3, 1.4, 1.5 will have shipped the underlying machinery.

The README copy should not say "today this role doesn't exist; you'll have to wait" — that's developer-facing internal state. It should say "after install, assign the `%SessionAgent_ReadOnly` role to operator users" — operator-facing future state, which will be true at the point any operator reads it.

### Project rules that apply to this story

From [.claude/rules/](../../.claude/rules/):

- **`research-first.md` §"Task 0 backend-surface probe"** — applies. **First Task-0 probe in the project.** Probe must be run before README content is authored. Verbatim probe output must be captured in the story file. See Task 0 above.
- **`iris-objectscript-basics.md`** — does NOT apply (this story ships zero ObjectScript files).
- **No tests for this story.** The "tests" are the rendered-markdown visual check (Task 3) and the live-gateway path verification (Task 2). The first `%UnitTest.TestCase` lands in Story 1.3.

### Project Structure Notes

- Files touched: `README.md` (UPDATE the Operator Prerequisites body only); this story file (UPDATE checkboxes + Task 0 Output + Dev Agent Record); `sprint-status.yaml` (status flip to `review` at end). One new dir if Option A succeeds: `_bmad-output/implementation-artifacts/probes/` (with one PNG screenshot).
- No edits to `module.xml`, `LICENSE`, `src/`, `static/`, `.gitignore`, or `docs/` are required for this story.
- The probes/ subdirectory is a **new convention** introduced by this story — future stories' Task-0 probes will follow the same `_bmad-output/implementation-artifacts/probes/story-<N>-<M>-<probe-description>-<date>.png` naming pattern.

### Previous Story Intelligence (Story 1.1)

Story 1.1 left these directly-relevant outputs:

- **README.md is at line count 110+ with the `## Operator Prerequisites` placeholder at line 12** — the placeholder body is 1 sentence + 3 numbered bullets. This story's Task 1 replaces that body with the full ~30-line content per the research doc.
- **Live IRIS instance is IRIS for Health 2025.1** (one minor above the 2024.1 floor) — use this as the probed version unless the dev's `Write $zv` returns something different.
- **Story 1.1 dev encountered IPM 0.10.6** (bootstrapped during that story; not relevant to this story but worth knowing the dev environment is fully set up).
- **Two adaptations from Story 1.1 are open architect questions** — `static/` directory placement, Placeholder.cls vs `.gitkeep`. Neither affects this story; both are tracked in `deferred-work.md`.

### References

- [epics.md Epic 1 §Story 1.2](../../_bmad-output/planning-artifacts/epics.md) — story acceptance criteria source (lines 544–567).
- [research §"Operator README Content"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) lines 1587–1638 — verbatim source for the README content to author.
- [architecture.md §"Carry-forward Task-0 probes"](../../_bmad-output/planning-artifacts/architecture.md) lines 1213, 1328 — locks the Web Gateway probe as Story 1.2's Task-0 deliverable.
- [architecture.md timeout-cascade](../../_bmad-output/planning-artifacts/architecture.md) lines 271, 1131 — 300s gateway window ↔ 90s per-call cap ↔ max-iter 10. Cite this rationale in the README's `### 2.` paragraph.
- [ux-design-specification.md §"Journey 3 — Operator install + configure (Aishah)"](../../_bmad-output/planning-artifacts/ux-design-specification.md) lines 897–939 — informs the prerequisites ordering and "prerequisites precede the install command" positional rule.
- [.claude/rules/research-first.md §"Task 0 backend-surface probe"](../../.claude/rules/research-first.md) — the rule this story instantiates for the first time.
- [Story 1.1](1-1-project-initialization.md) — pre-existing README state (the placeholder this story expands).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) via Claude Code Agent SDK

### Debug Log References

Task 0 probe output: see [Task 0 Output](#task-0-output) section above (live capture from IRIS for Windows 2025.1 Web Gateway management page).

### Completion Notes List

**Task 0 — Web Gateway "Server Response Timeout" probe captured (AC-1, AC-5):**

- **Probe option chosen:** A (Chrome DevTools MCP — preferred). Cross-checked with B (filesystem inspection of `C:\InterSystems\IRISHealth\CSP\bin\CSP.ini`) and C (irislib `%CSP.Mgr.GatewayMgr` source-doc reference). All three sources independently converge on the value `60`.
- **IRIS version probed:** `IRIS for Windows (x86-64) 2025.1 (Build 230.2U) Wed Jun 4 2025 18:53:21 EDT` — HealthShare feature enabled (verified via `mcp__iris-dev-mcp__iris_server_info` and `Write $zv`).
- **Verbatim Web Gateway default:** `60` (seconds). Field labeled "Server Response Timeout:" on the live management page; field tooltip confirms units: *"Max number of seconds allowed for InterSystems IRIS to respond before returning the 'Server Busy' error, between 1 and 2147483647"*.
- **Live administrative path traversed:** `http://localhost:52773/csp/bin/Systems/Module.cxw` → Login as `CSPSystem` → Configuration (left-nav section) → Default Parameters → "Connections to InterSystems IRIS" group → "Server Response Timeout" field. The README's `### 2.` paragraph uses these **verbatim** labels.
- **Path-label correction vs. story stub:** The story's tentative path called the menu item "System Default Parameters" — the actual live UI label is just "Default Parameters" under the "Configuration" section. The README uses the live-verified label.
- **Screenshot evidence:** Full-page screenshot of the live "Default Parameters" page (showing `value="60"` in the Server Response Timeout textbox) saved at `_bmad-output/implementation-artifacts/probes/story-1-2-webgateway-timeout-probe-2026-05-02.png`.

**Task 1 — README Operator Prerequisites body authored (AC-2, AC-3, AC-4):**

- Replaced the placeholder body (1 sentence + 3 bullet stubs that Story 1.1 left at lines 12–20) with a full 7-step operator prerequisite checklist (`### 1.` Supported IRIS versions through `### 7.` Daily purge task), per the canonical structure in [research §"Operator README Content"](../../_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) lines 1587–1638.
- The `### 2. Web Gateway timeout` paragraph embeds the probed verbatim default `60` and the recommended target `300`, with the navigation path written as a code block of step-by-step UI labels and a citation back to architecture line 1131 (timeout-cascade rationale: 300s gateway window ↔ 90s per-call cap ↔ max-iter 10).
- The `### 6. Bookmark URLs` block shows **both** URL patterns (HealthShare with `/healthshare/` segment AND plain IRIS without it), each as a backticked inline code span (will not render as a clickable link), with a one-line note at the top explaining when each applies — satisfies AC-3.
- The RBAC paragraph (originally written as `### 5. RBAC`, repositioned to `### 3. RBAC` during code review per AC-2's blocking-step ordering — see Code-review correction note below) is written in forward-looking voice: *"the module installer creates the `%SessionAgent_ReadOnly` role automatically … assign this role to the IRIS user…"* — references that the role install ships in [Story 1.4](../../_bmad-output/planning-artifacts/epics.md), per Dev Notes guidance.
- The `## Operator Prerequisites` H2 at line 12 was preserved (Story 1.1 positioning); only the body was replaced — satisfies AC-4. Verified with grep: H2 ordering is `Operator Prerequisites @12, What it does @78, Status @95, Development Plan @109, Planning Artifacts @135, Project posture @156, Contributing @164` — `Operator Prerequisites` is the first H2 the operator encounters reading top-to-bottom.
- All non-placeholder README content (under-construction banner, project intro, "What it does", "Status", "Development Plan", "Planning Artifacts (BMAD)", "Project posture", "Contributing") was preserved byte-identical.

**Task 2 — Live administrative path verified matches README (AC-5):**

- The path was traversed live during the Task 0 probe (Option A). The README uses the live-verified labels verbatim. No discrepancy between what the README documents and what the operator will see on the live IRIS 2024.1+ Web Gateway management page.

**Task 3 — README rendering validated (AC-4):**

- H2 ordering verified via `Grep` on `^## ` heading pattern: `Operator Prerequisites` is the first H2.
- Bookmark URL patterns confirmed wrapped in backticks (will render as inline `<code>` elements, not clickable `<a href>` links) — see `README.md` lines 66–70.
- The under-construction banner at lines 3–6 is left as-is (per Dev Notes: "now stale because Story 1.1 has shipped — leave it; Story 1.6 quickstart doc / Story 1.7 CI scaffolding may revise it").

**Task 4 — Captured Task 0 output mirrored to Completion Notes (this entry).**

**Code-review correction (2026-05-02 — applied during Story 1.2 code review):**

- Swapped README §3 ↔ §5 so the three install-blocking prerequisites appear in AC-2's prescribed relative order: **timeout (§2) → RBAC (§3) → API key (§5)**. The original Task-1 implementation followed the research doc's canonical 7-step ordering (timeout → API key → … → RBAC), which placed the blocking trio out of AC-2's mandated order. Non-blocking sections (Supported IRIS versions §1, Package mapping §4, Bookmark URLs §6, Daily purge task §7) keep their canonical positions; only the two blocking sections (§3 and §5) were swapped. Net: README structure still satisfies Task 1's "use research-doc 7-step shape" mandate while AC-2's blocking-step relative ordering is now satisfied.

**Project rule compliance:**

- **`research-first.md` §"Task 0 backend-surface probe"** — first Task-0 probe in the project. Probe was run before any README content was authored. Verbatim probe output captured in Task 0 Output section above and mirrored here.
- **`iris-objectscript-basics.md`** — N/A (zero ObjectScript files shipped by this story).
- **No tests for this story.** The "tests" are the rendered-markdown visual check (Task 3) and the live-gateway path verification (Task 2). The first `%UnitTest.TestCase` lands in Story 1.3.

### File List

**Modified:**

- `README.md` — replaced Operator Prerequisites placeholder body (lines 12–20) with full 7-step content (lines 12–76); preserved all other sections byte-identical. **Code-review touch-up:** swapped §3 ↔ §5 (RBAC and API key) so the three install-blocking prerequisites appear in AC-2's prescribed relative order — see Code-review correction note in Completion Notes.
- `_bmad-output/implementation-artifacts/1-2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites.md` — this story file: filled Task 0 Output, checked off all task/subtask boxes, populated Dev Agent Record, flipped Status to `review`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — flipped `1-2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites` from `ready-for-dev` → `in-progress` → `review`; updated `last_updated` date.

**Created:**

- `_bmad-output/implementation-artifacts/probes/` — new directory (probes/ subdirectory convention introduced by this story per Dev Notes §"Project Structure Notes").
- `_bmad-output/implementation-artifacts/probes/story-1-2-webgateway-timeout-probe-2026-05-02.png` — full-page screenshot of the live IRIS 2025.1 Web Gateway "Default Parameters" page showing `Server Response Timeout = 60`.

### Change Log

| Date | Description |
|---|---|
| 2026-05-02 | Story 1.2 implemented end-to-end: Task-0 probe captured live Web Gateway "Server Response Timeout" default (`60` seconds on IRIS for Windows 2025.1) via Chrome DevTools MCP with cross-checks against CSP.ini and `%CSP.Mgr.GatewayMgr` source; README `## Operator Prerequisites` body replaced with full 7-step checklist embedding the probed value and both HealthShare/plain-IRIS bookmark URL patterns. Status: `ready-for-dev` → `review`. |
| 2026-05-02 | Code-review pass: swapped README §3 (API key) ↔ §5 (RBAC) so the three install-blocking prerequisites appear in AC-2's prescribed relative order (timeout → RBAC → API key). Non-blocking sections unchanged. Story file Completion Notes / File List updated to record the touch-up. Status remains `review` (no defects beyond the ordering fix). |
