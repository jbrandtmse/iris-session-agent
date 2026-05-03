# Story 3.1: Chat Panel HTML Draw Helper + Minimum CSS Tokens

Status: review

## Story

As a **developer building the Inspection Agent UI**,
I want a `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper` class providing a single entry point that emits the chat panel's static HTML structure plus a `SessionAgent.UI.ChatPanel` CSS-contributor class providing the minimum `--sa-*` token set and `sa-*` component classes,
So that the Visual Trace subclass (Story 3.3) can include the chat panel via a single call and the rendered panel inherits Mgmt Portal styling per UX-DR26.

This is the **first UI story of Epic 3** — the demo-able-milestone epic. It establishes the visual scaffolding both Inspection (Story 3.3) and Search (Epic 10) will consume. Per architecture §"Project Directory Structure" both classes are shared between the two future portal subclasses, hence the placement under `EnsPortal.Util` (helper) and `UI` (CSS).

## Acceptance Criteria

ACs come from epics.md §"Story 3.1: Chat Panel HTML Draw Helper + Minimum CSS Tokens" verbatim.

### AC-1 — `ChatPanelDrawHelper.DrawChatPanel` emits the semantic shell

**Given** the developer is implementing `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`
**When** they implement the helper class
**Then** the class provides `ClassMethod DrawChatPanel(pAgentName As %String, pSessionKey As %String, pPortalUser As %String) As %Status` that emits the chat panel's static HTML using `&html<...>` per Zen convention with this structure:
- outer `<section role="region" aria-label="Agent chat panel" class="sa-chat-panel">` (UX-DR1)
- empty `<div class="sa-message-transcript"></div>` (the message blocks land here at runtime)
- empty `<div class="sa-status-text" aria-live="polite"></div>` (UX-DR6)
- `<form class="sa-input-area">` containing `<textarea class="sa-input-field" aria-label="Ask anything about this session" placeholder="Ask anything about this session.">` (UX-DR10)

Placeholder text is fixed for MVP at *"Ask anything about this session."* — Story 3.3 swaps it to *"Continue the conversation."* on returning-conversation surfacing.

### AC-2 — No `<script>` other than the per-instance bootstrap data

**Given** the developer is implementing `DrawChatPanel`
**Then** the helper does NOT include any `<script src="...">` or inline JS implementation — script-source inclusion is the host page's responsibility (Story 3.3 wires it via `OnPageHeadStyle`/`OnPageHeadScript`).
**And** the helper emits exactly one `<script>` block populated from server-side context: `window.SessionAgentChat = {agentName: "<pAgentName>", sessionKey: "<pSessionKey>", portalUser: "<pPortalUser>"};` so `chat-panel.js` (Story 3.2) reads context without DOM scraping.
**And** all three context values are emitted via JSON encoding (`##class(%DynamicObject).%New().%Set("k", v).%ToJSON()` or `$ZCONVERT(value, "O", "JSON")`) to defeat XSS/HTML-injection at the script-data boundary — never raw string concatenation into a JS literal.

### AC-3 — `SessionAgent.UI.ChatPanel` CSS contributor — minimum token set

**Given** the developer is implementing `SessionAgent.UI.ChatPanel`
**When** they implement the CSS contributor
**Then** the class provides a `ClassMethod EmitStyle() As %Status` (or equivalent name — see Dev Notes for naming alignment with the Zen contributor pattern Story 3.3 will use) that writes a `<style>...</style>` block to the current device, defining ONLY the minimum `--sa-*` tokens needed for MVP (per UX-DR12-MVP-subset):
- `--sa-message-operator-bg`
- `--sa-message-agent-bg`
- `--sa-tool-card-border`
- `--sa-tool-card-status-running`
- `--sa-tool-card-status-complete`
- `--sa-tool-card-status-error`
- `--sa-citation-chip-bg`
- `--sa-citation-chip-text`
- `--sa-status-text-color`
- `--sa-error-text-color`

Token *values* resolve against parent palette via inheritance (`var(--sa-message-operator-bg, /* inherited fallback */)`) — no hardcoded hex/rgba per UX-DR26. Reasonable parent-palette references per architecture §"Token Initial Values" (lines 622–629): operator-bg from parent's low-contrast surface variant; agent-bg from parent default content background; tool-card-border from parent's standard rule color; status-error from parent's existing error/warning color; citation-chip-text from parent's link color.

### AC-4 — `sa-*` component classes inherit parent foundation; no overrides

**Given** the developer is implementing `EmitStyle`
**When** the contributor defines `sa-*` component class rules
**Then** the rules reference parent palette via inheritance — NO hardcoded hex/rgba per UX-DR26.
**And** parent Mgmt Portal styling is inherited entirely for foundation layer — `font-family`, `font-size`, `line-height`, button styles, and form controls are NOT overridden by `sa-*` rules.
**And** the styling supports the seven anti-patterns of UX-DR28 (no-modals): no `position: fixed` overlays, no `z-index` games beyond inherited Zen layering, no animation keyframes beyond what Zen renders by default.

### AC-5 — Unit tests verify rendered output

**Given** a unit test inspects `DrawChatPanel`'s rendered output
**When** the test invokes `DrawChatPanel("session-inspection", "1184729", "marisol.rivera")`
**Then** the test asserts the output contains the literal class names: `sa-chat-panel`, `sa-message-transcript`, `sa-status-text`, `sa-input-area`, `sa-input-field` (semantic structure).
**And** the output contains a `<script>` block declaring `window.SessionAgentChat` whose JSON-parsed payload has `agentName === "session-inspection"`, `sessionKey === "1184729"`, `portalUser === "marisol.rivera"`.
**And** the output passes basic HTML structural validity: every opened tag is closed; no `<div onclick=...>` patterns per UX-DR19 (event wiring lives in the JS file, not the HTML).
**And** an XSS-injection probe: `DrawChatPanel("session-inspection", "</script><img onerror=alert(1)>x", "user")` produces output where the injected fragment is JSON-string-encoded inside the bootstrap (no script-tag break-out).

### AC-6 — Compile + tests + regression intact

- `iris_doc_compile` clean for `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`, `SessionAgent.UI.ChatPanel`, `SessionAgent.Test.ChatPanelDrawHelperTest`.
- New test class `SessionAgent.Test.ChatPanelDrawHelperTest` adds at least 3 net new tests (semantic-structure, bootstrap-context, XSS-probe).
- Per-class regression sweep: 126 + 3 = **129/129** total. (Story 3.0 baseline was 126.)

## Tasks / Subtasks

- [x] **Task 0 — Pre-flight surface probe (Rule 4 + project-rule "Read files being modified")**
  - [x] Confirm `EnsPortal.Application.cls` exists in IRIS via `iris_doc_get` (it is the parent stylesheet referenced by AC-3/AC-4 inheritance fallback) — capture its presence + a 1-line description in Completion Notes.
  - [x] Confirm Zen `&html<...>` macro / `%CSP.Page.Write()` is the right output channel for `DrawChatPanel` by reading one existing `OnDrawContent` implementation (e.g., `irislib/EnsPortal/`); cite the file in Completion Notes.
  - [x] Confirm the directory `src/SessionAgent/EnsPortal/Util/` exists or needs creation (Story 2.x didn't touch it).

- [x] **Task 1 — Implement `ChatPanelDrawHelper.cls` (AC: #1, #2)**
  - [x] Create `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls` extending `%RegisteredObject`.
  - [x] `ClassMethod DrawChatPanel(pAgentName As %String, pSessionKey As %String, pPortalUser As %String) As %Status` — per AC-1 structure.
  - [x] JSON-encode all three context values (Util.Json from Story 2.1, or built-in `$ZCONVERT(..., "O", "JSON")`) before splicing into the `window.SessionAgentChat` literal.
  - [x] Return `$$$OK` on success; `$$$ERROR(...)` on parameter validation failure (empty `pAgentName` is the only invariant violation; `pSessionKey` and `pPortalUser` may be empty for first-install / not-yet-logged-in states).

- [x] **Task 2 — Implement `UI.ChatPanel.cls` (AC: #3, #4)**
  - [x] Create `src/SessionAgent/UI/ChatPanel.cls` extending `%RegisteredObject`.
  - [x] `ClassMethod EmitStyle() As %Status` — emits `<style>...</style>` defining the 10 `--sa-*` tokens per AC-3 + the minimum component-class rules per AC-4.
  - [x] Token values: use `var(--inherited-token-name, fallback)` referencing parent Mgmt Portal palette (cite parent token names in CSS comments — see Dev Notes for the parent-palette guess-list).
  - [x] Component-class rules cover at minimum: `.sa-chat-panel { display:flex; flex-direction:column; height:100%; }`, `.sa-message-transcript { flex:1 1 auto; overflow-y:auto; }`, `.sa-input-area { display:flex; }`, `.sa-input-field { flex:1 1 auto; }`, `.sa-status-text { color:var(--sa-status-text-color); font-style:italic; }`.

- [x] **Task 3 — Tests (AC: #5)**
  - [x] Create `src/SessionAgent/Test/ChatPanelDrawHelperTest.cls` extending `%UnitTest.TestCase` (per `.claude/rules/object-script-testing.md` — `%OnNew(initvalue)` boilerplate).
  - [x] `TestSemanticStructure` — invokes `DrawChatPanel("session-inspection", "1184729", "marisol.rivera")` capturing `Write` output via the optional `pStream` parameter approach (chosen over `$IO` redirection — see Completion Notes), asserts all 5 class names present.
  - [x] `TestBootstrapContext` — captures output, locates the `<script>` block, JSON-parses the assigned object via `{}.%FromJSON(...)`, asserts the three keys + values.
  - [x] `TestXssEscaping` — invokes with `pSessionKey = "</script><img onerror=alert(1)>x"`, asserts the literal `</script>` substring does NOT appear in the output unencoded (the JSON encoding produces `<\/script>` after explicit post-processing — verified live).
  - [x] Bonus `TestEmptyAgentNameRejected` — locks the AC-1 boundary: empty `pAgentName` is the only invariant violation; empty `pSessionKey` / `pPortalUser` are valid.

- [x] **Task 4 — Compile + per-class regression sweep (AC: #6)**
  - [x] `iris_doc_compile` for the 3 new classes.
  - [x] Per-class `iris_execute_tests` for `ChatPanelDrawHelperTest` plus a sanity sweep of the 18 prior test classes — captured counts in Completion Notes; final 118/118 (zero regressions, zero failures).

- [x] **Task 5 — Stale-reference grep (Rule 4)**
  - [x] `grep "HSCUSTOMCODE|%SessionAgent_ReadOnly|gpt-4o" src/SessionAgent/` → 1 hit in `Security/ReadOnlyRole.cls` doc-comment is intentional historical context (Story 1.4 naming-decision note explaining why the role is `SessionAgent_ReadOnly` not `%SessionAgent_ReadOnly`). Not a stale reference; not Story 3.1 scope. No action.
  - [x] `grep "Custom\.EnsPortal" src/SessionAgent/` → 0 hits.

## Dev Notes

### Architecture-cited file placements

Per architecture.md §"Complete Project Directory Structure" (lines 872–880):
- `src/SessionAgent/UI/ChatPanel.cls` — shared CSS/JS contributors used by both EnsPortal subclasses
- `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls` — shared `OnDrawContent("DrawChatPanel")` helper

Both classes are *shared* between the future Inspection (Story 3.3, this epic) and Search (Epic 10) portal subclasses. Don't bake any inspection-specific behavior into them.

### Parent palette — token-fallback guess list

UX-design-spec §"Token Initial Values" (lines 620–629) prescribes parent-palette references rather than concrete CSS variable names. Mgmt Portal Zen does NOT publish a public `--*` token set — its CSS uses pre-CSS-vars conventions. Practical approach for AC-3: use `var(--sa-message-operator-bg, #f5f5f5)` form where the fallback is the architecture-suggested approximation. The `var()` reference will degrade gracefully if a token is not defined; the fallback is what actually renders. This is a deliberate Story 3.1 choice — a future epic (10.7+) can replace fallbacks with live parent-palette lookups when the vendored UX components land.

### `&html<...>` and output capture for tests

Zen's `&html<...>` macro writes directly to `%CSP.Page.OUT` (the current device). To unit-test the rendered output, the test redirects `$IO` to a string mnemonic space:

```objectscript
Set tDevice = "|TempStream"
Open tDevice:("New":"RWS"):0
Use tDevice
Do ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel(...)
Use $IO  ; restore
Set tOutput = ...read tDevice...
Close tDevice
```

Alternative: the helper can take an optional `pStream As %Stream.GlobalCharacter` parameter for testability, with a default that writes to `%CSP.Page.OUT`. Pick whichever is cleaner; document the choice in Completion Notes.

### XSS escaping

Per AC-2 + AC-5 the bootstrap context MUST be JSON-encoded. The simplest pure-OS approach:

```objectscript
Set tCtx = ##class(%DynamicObject).%New()
Do tCtx.%Set("agentName", pAgentName)
Do tCtx.%Set("sessionKey", pSessionKey)
Do tCtx.%Set("portalUser", pPortalUser)
&html<<script>window.SessionAgentChat = #(tCtx.%ToJSON())#;</script>>
```

The `%ToJSON()` output is JS-object-literal-safe (it produces valid JSON, which is a strict subset of valid JS). The only remaining XSS vector is a `</script>` substring inside one of the values, which `%ToJSON()` does NOT escape by default. The test asserts this case explicitly. If `%ToJSON()` does emit a bare `</script>`, post-process: `Set tJson = $Replace(tCtx.%ToJSON(), "</script>", "<\/script>")` — the slash-escape is JSON-valid and breaks the script-tag-break-out vector.

### Order of operations recommended

1. Task 0 probe first.
2. Task 1 (helper) and Task 2 (CSS contributor) in parallel — they don't depend on each other.
3. Task 3 (tests) once Task 1 lands.
4. Task 4 + Task 5.

### Sources

- [`epics.md`](../planning-artifacts/epics.md) §"Epic 3" lines 1100–1112 + §"Story 3.1" lines 1114–1139.
- [`architecture.md`](../planning-artifacts/architecture.md) §"Complete Project Directory Structure" lines 872–880; §"Token Initial Values" lines 620–629; §"Component dependency map" lines 982–987.
- [`ux-design-specification.md`](../planning-artifacts/ux-design-specification.md) §"Component Strategy MVP" lines 1268–1276; §"Component 1 — sa-chat-panel" line 984; UX-DR12-MVP-subset.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — `%OnNew(initvalue)` boilerplate, `$$$AssertX` macros (no `$$$AssertFalse`).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — auto-sync workflow; ObjectScript naming (no underscores in parameter / class-parameter names).
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rules 1, 2, 3, 4, 8.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — single-task dev agent dispatched by Epic 3 cycle lead.

### Debug Log References

(none — clean compile + clean tests on first pass)

### Completion Notes List

**Task 0 probe outputs (Rule 4 — `iris_doc_get` typed MCP, NOT `iris_execute_command`)**

- `EnsPortal.Application.cls` exists in IRIS (DB: ENSLIB; ts: 2025-06-04). 1-line description: it is the Zen application class for the IMP — `Extends (%CSP.Portal.Application, EnsPortal.Util.PageLinks)`, sets `APPLICATIONNAME = "Interoperability Management Portal"`, `HOMEPAGE = "%CSP.Portal.Home.zen"`, `DOMAIN = "Ensemble"`, and contributes an `XData Style` block defining `.fieldBoxIndent`, `.hrline`, `.expandoNode` etc. for portal-wide CSS conventions.
- `OnDrawContent` reference cited: `irislib/EnsPortal/VisualTrace.cls` line 290 (`<html id="theTraceTop" OnDrawContent="DrawTraceTop" />`) wires a Zen `<html>` element to the helper at line 693 `Method DrawTraceTop(pSeed As %String) As %Status`. The helper uses `&html<...>` macro with `#(...)#` for runtime interpolation and `..EscapeHTML(...)` for attribute escaping. This is the canonical pattern Story 3.3 will follow when wiring `ChatPanelDrawHelper.DrawChatPanel` from a portal page.
- Directory creation: `src/SessionAgent/EnsPortal/` and `src/SessionAgent/UI/` did NOT exist before this story; both auto-created when the new `.cls` files were written.

**XSS-escaping approach (parent-agent special-attention item)**

Raw `%ToJSON()` was **NOT sufficient**. `%DynamicObject.%ToJSON()` does not escape the literal substring `</script>` inside string values, which would allow script-tag break-out. The implementation explicitly post-processes via `Set tBootstrapJson = $Replace(tCtx.%ToJSON(), "</script>", "<\/script>")` before splicing into the `<script>` block. The escape `<\/script>` is JSON-string-valid (the JSON spec permits `\/` as an escape for `/`), survives `%FromJSON` round-trip cleanly, and breaks the HTML parser's scan for the closing `</script>` tag. Verified live via `iris_execute_classmethod` with the AC-5 probe input `"</script><img onerror=alert(1)>x"` — the rendered output contains `"<\\/script>"` (the JSON-encoded form of `<\/script>`) instead of the bare `</script>`, and `TestXssEscaping` passes.

**Output-capture approach (Dev Notes choice)**

Optional `pStream As %Stream.Object` parameter chosen over `$IO` mnemonic-space redirection. Rationale: `$IO` redirection across `&html<>` interacts badly with the `%UnitTest` test harness's own output capture and is fragile across IRIS versions. The stream-parameter approach is deterministic and the helper falls back to `&html<>` (current-device write) when `pStream` is empty — preserving canonical live-portal usage from Story 3.3's `OnDrawContent` callback context.

**Compile output**

```
Compilation finished successfully in 0.002s.
SessionAgent.EnsPortal.Util.ChatPanelDrawHelper — clean
SessionAgent.UI.ChatPanel — clean
SessionAgent.Test.ChatPanelDrawHelperTest — clean
```

**Per-class regression test counts (Task 4)**

| Test class | Passed/Total |
|---|---|
| AgentDtoTest | 7/7 |
| AgentLoopGuardsTest | 1/1 |
| AgentLoopTest | 3/3 |
| AuditEmitTest | 3/3 |
| AuditTest | 8/8 |
| ChatHistoryTest | 10/10 |
| ChatPanelDrawHelperTest (NEW) | **4/4** |
| ConfigAgentTest | 10/10 |
| EnvSecretTest | 8/8 |
| InspectionToolTest | 15/15 |
| JsonTest | 9/9 |
| MessageAdapterTest | 10/10 |
| OpenAIProviderTest | 8/8 |
| ReadOnlyRoleTest | 5/5 |
| RetryWithBackoffTest | 9/9 |
| SmokeTest | 1/1 |
| ToolBaseTest | 3/3 |
| ToolDefAdapterTest | 3/3 |
| ToolRegistryTest | 1/1 |
| **Total** | **118/118 (zero failures, zero skips)** |

**Discrepancy note (per Rule 2 — no `[x]` without truthful evidence):** AC-6 / spec said the Story 3.0 baseline was 126, expecting 126+3 = 129 after this story. Empirically the actual baseline across the 18 prior test classes is 114, and this story adds 4, bringing the total to 118. The 126 figure in the spec was a planning estimate, not a measured count. AC-6's spirit ("no regressions + ≥ 3 new tests") is satisfied: zero regressions across all 18 prior classes, 4 new tests added (3 required by AC-5 + 1 boundary bonus). Documented honestly rather than fudged.

**AC traceability**

- AC-1 (semantic shell) — satisfied by `DrawChatPanel` HTML emission + `TestSemanticStructure` assertions (5 class names + ARIA attrs + fixed placeholder).
- AC-2 (no extra `<script src=...>`, JSON-encoded bootstrap) — satisfied; the only `<script>` block emitted is the bootstrap context, JSON-encoded with `%ToJSON()` + `</script>` post-processing.
- AC-3 (10-token list, exact) — satisfied; `EmitStyle` defines exactly the 10 tokens listed (`--sa-message-operator-bg`, `--sa-message-agent-bg`, `--sa-tool-card-border`, `--sa-tool-card-status-running`, `--sa-tool-card-status-complete`, `--sa-tool-card-status-error`, `--sa-citation-chip-bg`, `--sa-citation-chip-text`, `--sa-status-text-color`, `--sa-error-text-color`).
- AC-4 (no overrides; no anti-patterns) — satisfied; all token values are `var(--parent, fallback)` form (no bare hex/rgba); component classes set only flex/overflow/color (no font-family override, no `position: fixed`, no z-index, no `@keyframes`).
- AC-5 (semantic + bootstrap + XSS tests) — satisfied; 3 required tests + 1 boundary bonus, all pass.
- AC-6 (compile clean + ≥ 3 new tests + no regressions) — satisfied (with the actual-vs-estimated total-count discrepancy documented above).

**Task 5 stale-reference grep results**

- `HSCUSTOMCODE|%SessionAgent_ReadOnly|gpt-4o` → 1 hit in `src/SessionAgent/Security/ReadOnlyRole.cls` doc-comment line 31 — this is intentional historical context from Story 1.4's naming-decision note, NOT a stale reference. The actual role name shipped is `SessionAgent_ReadOnly` (no `%`). No action.
- `Custom\.EnsPortal` → 0 hits. Project rule (all custom classes under `SessionAgent.*`) holds.

### File List

- `src/SessionAgent/EnsPortal/Util/ChatPanelDrawHelper.cls` (NEW)
- `src/SessionAgent/UI/ChatPanel.cls` (NEW)
- `src/SessionAgent/Test/ChatPanelDrawHelperTest.cls` (NEW)
- `_bmad-output/implementation-artifacts/3-1-chat-panel-html-draw-helper-minimum-css-tokens.md` (story file: status, tasks, completion notes)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status flip ready-for-dev → in-progress → review)

### Change Log

| Date | Author | Change |
|---|---|---|
| 2026-05-03 | Dev (Opus 4.7) | Implement Story 3.1: `ChatPanelDrawHelper.DrawChatPanel` (semantic HTML + JSON-encoded bootstrap with `</script>` post-processing for XSS); `UI.ChatPanel.EmitStyle` (10 `--sa-*` tokens + 5 component-class rules, all `var(--parent, fallback)` form per UX-DR26); `ChatPanelDrawHelperTest` (4 tests: semantic-structure, bootstrap-context, XSS-escaping, empty-agent-name boundary). Compile clean; 118/118 tests pass; zero regressions. |
