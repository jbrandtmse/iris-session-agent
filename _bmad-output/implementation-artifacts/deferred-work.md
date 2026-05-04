# Deferred Work

This file accumulates findings, follow-ups, and architect-decision items that are flagged during code review but are not in-scope for the current story to fix. Each entry records the source story, the date deferred, and the rationale.

---

## Deferred from: code review of story-1.1-project-initialization (2026-05-02)

- **`static/` directory placement: architecture diagram vs. IPM `<FileCopy>` resolution semantics — architect decision required before Story 10.7.**

  - **Source:** Story 1.1 code review (this file's first deferred item).
  - **Severity:** LOW (no impact on Story 1.1 — both directories exist; both ACs pass).
  - **The discrepancy:** AC-1 mandates the verbatim `<FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>` from research §"IPM module.xml — Concrete v1 Shape" line 974. Per IPM source (`%IPM.ResourceProcessor.FileCopy.GetSource()` resolves `Module.Root + Name`), the `Name="static/"` attribute resolves to `c:/git/iris-session-agent/static/` — at the module root, NOT under `<SourcesRoot>src/</SourcesRoot>`. However, the canonical project tree in [architecture.md §"Project Directory Structure" line 901](../planning-artifacts/architecture.md) shows `static/` nested under `src/` (i.e., `src/static/marked.min.js`, `src/static/chat-panel.js`, etc.). The two are structurally inconsistent — IPM will look for vendored static assets at module-root `static/`, not at `src/static/` where the architecture diagram places them.
  - **Story 1.1 mitigation:** Both `static/` (module root) and `src/static/` directories created with `.gitkeep` placeholders so AC-1's verbatim shape AND AC-7's architecture-diagram-tree-match both pass.
  - **Why this must be resolved before Story 10.7:** Story 10.7 ships the vendored Markdown bundle (marked.min.js, prism.min.js, prism-objectscript.js, prism-sql.js, prism-javascript.js, prism-json.js, prism-hl7.js, prism-xml.js, prism.min.css, dompurify.min.js, chat-panel.js, sessionagent-chat.css). These files MUST land in the directory IPM's `<FileCopy>` actually copies from. If Story 10.7 follows the architecture diagram and places them under `src/static/`, IPM will not find them and the CSP-served bundle will be empty — breaking the Growth-tier UI render path silently.
  - **Two clean resolutions for the architect to choose between:**
    1. **Update the architecture diagram** (architecture.md line 901 area) to move `static/` from under `src/` to repo root, matching where IPM's `<FileCopy Name="static/">` actually resolves. Delete `src/static/.gitkeep` from the repo as a follow-up cleanup. This is the lower-friction option — IPM source is authoritative, the diagram is a doc bug.
    2. **Update `module.xml`** to add `<SourceDirectory>src/static/</SourceDirectory>` (or use `Name="src/static/"`) so the FileCopy actually resolves to `src/static/` matching the diagram. Delete the module-root `static/.gitkeep` from the repo as a follow-up. This deviates from AC-1's verbatim research-line-974 shape.
  - **Recommendation:** Option 1 — the IPM source is the authoritative truth about where `<FileCopy Name="static/">` resolves; the diagram is the doc bug; AC-1's verbatim shape stays intact. Option 2 deviates from the canonical IPM-on-2024.1 module.xml shape that the research source spent effort to verify.
  - **Owner:** Architect (Winston) — to resolve in a one-line architecture.md edit + a follow-up story (or as a tag-along scope item in Story 10.7's spec).
  - **Blocking?** Not blocking Story 1.2 through 10.6. Blocks Story 10.7 if not resolved before that story enters dev.
  - **Triage 2026-05-03 (Story 2.0): deferred — natural carrier is Story 10.7 (vendored Markdown bundle); LOW severity; both `static/` and `src/static/` exist with `.gitkeep`, no operator-observable break until Story 10.7 enters dev.**

---

## Deferred from: code review of story-1.2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites (2026-05-02)

- **Story-spec internal contradiction: AC-2 ("exactly three concrete steps") vs. Task 1 ("seven sub-steps per the research doc shape") — story-template guidance for future Task-0 stories.**

  - **Source:** Story 1.2 code review (this file's second deferred item).
  - **Severity:** LOW (no impact on Story 1.2 itself — the contradiction was caught and resolved in code review by swapping README §3 ↔ §5 to satisfy AC-2's blocking-step relative ordering while keeping Task 1's 7-step canonical structure).
  - **The contradiction:** AC-2 reads *"the section enumerates exactly three concrete steps in this order: 1. Web Gateway timeout, 2. RBAC, 3. API key."* Task 1 reads *"use the full content per [research §"Operator README Content"] … keep `## Operator Prerequisites` as the H2; use `### 1.` through `### 7.` H3s for the seven sub-steps per the research doc shape."* The research doc's canonical 7-step shape places API key at §3 and RBAC at §5 (timeout → API key → … → RBAC), which conflicts with AC-2's mandated ordering (timeout → RBAC → API key). A literal reading of both at the same time is impossible.
  - **How it played out:** Dev followed Task 1 literally → README came out with blocking trio in canonical-research-doc order (timeout § 2 → API key § 3 → RBAC § 5) → code reviewer caught the AC-2 violation and swapped § 3 ↔ § 5 to land timeout → RBAC → API key. Both AC-2 and Task 1 are now satisfied (Task 1's "seven sub-steps" structure is preserved; only blocking-step relative ordering was adjusted).
  - **Why this is worth recording:** Story 1.2 is the **first Task-0 probe story in the project**, and the story template here is the prototype every future Task-0 story will copy. If the AC vs. Task drift is left uncorrected in the template, future stories will inherit the same trap — dev will follow Task 1 literally, code review will catch the AC violation, and review-time rework becomes the norm. Cheap fix at the planning layer; expensive if it recurs across Epics 2, 7, 9, 10 (each has at least one Task-0 probe per architect's roadmap).
  - **Recommendation for the next story-template revision (PM/SM, applies to Stories 2.10, 7.1, 9.1 and any other future Task-0 stories):** When AC enumerates "the install-blocking" steps and Task 1 expands them within a wider canonical structure, AC should say *"the **blocking** steps appear in this **relative** order — non-blocking sections may be interspersed per the canonical structure cited in Task 1"*, OR Task 1 should say *"adapt the canonical structure to put blocking steps in the AC-mandated order; deviate from the research doc's section numbering as needed."* Either phrasing eliminates the trap.
  - **Owner:** PM (John) or SM, on the next story-template revision pass — single one-paragraph clarification in the BMAD `bmad-create-story` workflow's AC-vs-Task guidance.
  - **Blocking?** Not blocking. Cosmetic/process improvement item.
  - **Triage 2026-05-03 (Story 2.0): deferred — natural carrier is the next BMAD `bmad-create-story` template revision (PM-owned process item); resolved cosmetically inside Story 1.2 itself; no follow-up code change required.**

---

## Deferred from: code review of story-1.3-audit-event-pre-registration (2026-05-02)

- **`ToolCall` audit event registration deferred to Epic 2 lazy-on-first-use — confirm Story 2.10 picks this up or extend Story 1.3 retroactively.**

  - **Source:** Story 1.3 code review.
  - **Severity:** LOW (acceptable design choice for Story 1.3 scope; no operator-observable impact until Story 2.10 ships the tool registry).
  - **The deferral:** `EnsureEvents()` registers 11 triples (4 LlmCall + 4 VocabWrite + 3 TaskRun) but registers ZERO `ToolCall` triples at install time. The architecture (architecture.md line 822 onward) already enumerates 13 inspection tool names (`session_summary`, `session_timeline`, `message_headers`, `event_log`, `rule_log`, `find_related_sessions`, `find_sessions_by_body`, `get_message_body`, `get_message_detail`, `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods`, `explain_error`) plus 8+ Search tools (line 836+) — so technically all known tool names COULD have been registered now.
  - **Why deferring is acceptable:** (a) Story 2.10 explicitly owns the tool-registry boundary; (b) the architecture text says ToolCall emissions originate at `SessionAgent.Tool.Registry.Dispatch` "(Story 2.10 onward)"; (c) Search tools (Epic 8) and any growth-tier additions (Epic 10) would also need registration entries — a centralized lazy-register-on-dispatch helper inside Story 2.10's tool registry is cleaner than splitting registration between EnsureEvents() (for the inspection 13) and the registry path (for everything else).
  - **What needs to happen in Story 2.10:** add a `RegisterIfMissing(source, type, name)` helper to `SessionAgent.Audit.Emit` (or to the tool registry itself), and call it from the registry's `Dispatch` boundary on first emit per tool. Alternative: extend `EnsureEvents()` with the then-known tool name universe at the time Story 2.10 ships, AND add the lazy helper for any tools added later.
  - **Owner:** Dev (when implementing Story 2.10 — `2-10-tool-base-abstract-tool-registry-task-0-probe`).
  - **Blocking?** Not blocking Stories 1.4–1.7 or any of Epic 2 prior to Story 2.10. Becomes blocking on Story 2.10 entering dev — that story MUST address ToolCall registration as part of its own scope.
  - **Triage 2026-05-03 (Story 2.0): owner reassigned to Story 2.10 — must be addressed in that story's scope. Forward-looking note added to `epics.md` Story 2.10 section so the create-story workflow picks it up when 2.10's spec is drafted. See [`2-0-epic-1-deferred-cleanup.md`](2-0-epic-1-deferred-cleanup.md) and [`epic-1-retro-2026-05-02.md`](epic-1-retro-2026-05-02.md) (2026-05-02).**

- **Inline-comment clarity around the argumentless `Quit` inside the While loop in `Emit.cls` line 72.**

  - **Source:** Story 1.3 code review.
  - **Severity:** LOW (cosmetic — code is correct as written; reviewer preference only).
  - **The observation:** The argumentless `Quit` at line 72 breaks out of the While loop (per ObjectScript semantics: `Quit` inside a While exits the loop, not the enclosing block). Control then falls through to line 77 (`Set $NAMESPACE = tOrigNS`) and the try block closes naturally. Status is correctly carried in `tSC` and returned by the outer `Quit tSC` at line 83. The existing inline comment "argumentless quit out of While; try/catch closes below" is accurate but a future maintainer who hasn't internalized that "Quit-inside-While exits the loop only" might benefit from one extra word, e.g., "argumentless quit exits While loop only; namespace restore on line 77 still runs before try/catch closes."
  - **Recommendation:** No change required. If a future story touches `Emit.cls` for unrelated reasons, optionally tighten the inline comment then. Not worth a dedicated edit.
  - **Owner:** None (no action required).
  - **Blocking?** Not blocking anything.
  - **Triage 2026-05-03 (Story 2.0): dropped — cosmetic only; existing inline comment "argumentless quit out of While; try/catch closes below" is accurate. Future stories that touch `Emit.cls` for unrelated reasons may optionally tighten the wording.**

---

## Deferred from: code review of story-1.4-read-only-rbac-role-install (2026-05-02)

- **Historical-doc references to `%SessionAgent_ReadOnly` (with leading `%`) preserved as authoring history.**

  - **Source:** Story 1.4 code review.
  - **Severity:** LOW (no operator-observable impact; the live IRIS role is `SessionAgent_ReadOnly` with no leading `%`, and all operator-facing + agent-authoring-facing artifacts have been updated to match).
  - **The cross-cutting finding:** Story 1.4 Task 0 probe revealed that IRIS rejects user-created RBAC role names beginning with `%` (error #887 "Invalid role name" — the `%` prefix is reserved exclusively for IRIS-shipped pre-defined system roles per the `Security.Roles.Create` validator). The locked role name was changed from `%SessionAgent_ReadOnly` (per the original project memory + research docs) to `SessionAgent_ReadOnly`. See `_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt` §"Naming-decision note" for verbatim probe transcript.
  - **What was updated in this commit (HIGH/MEDIUM auto-resolved):**
    - `README.md` — operator-facing prereqs, design properties, Epic 1 description.
    - `_bmad-output/planning-artifacts/architecture.md` — multiple references (lines 28, 91, 112, 253, 862, 980, 1072) — agent-authoring-facing spec.
    - `_bmad-output/planning-artifacts/prd.md` — multiple references — agent-authoring-facing spec.
    - `_bmad-output/planning-artifacts/epics.md` — Story 1.4 spec text + FR/NFR/AR cross-references — agent-authoring-facing.
    - `_bmad-output/planning-artifacts/product-brief-iris-session-agent-distillate.md` — LLM-distillate (agent-authoring-facing).
    - `_bmad-output/planning-artifacts/implementation-readiness-report-2026-05-02.md` — FR50 coverage row.
    - `C:/Users/Josh/.claude/projects/c--git-iris-session-agent/memory/project_package_naming.md` — the locked-naming memory; updated with the probe rationale appended so future BMAD runs see both the corrected name AND the historical "why".
  - **What was deliberately preserved as historical (this deferral):**
    - `_bmad-output/implementation-artifacts/1-1-project-initialization.md` — Story 1.1 spec, historical authoring record predating the rename.
    - `_bmad-output/implementation-artifacts/1-2-web-gateway-timeout-task-0-probe-readme-operator-prerequisites.md` — Story 1.2 spec, historical authoring record predating the rename.
    - `_bmad-output/implementation-artifacts/1-4-read-only-rbac-role-install.md` — Story 1.4's OWN AC/Task wording. The dev's adaptation is captured verbatim in §"Task 0 Output" (Naming-decision note), §"Completion Notes List" (NEW finding paragraph), and §"Change Log". The original AC/Task text is preserved as the authoring trace.
    - `_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md` and `…-message-search-agent-no-ai-hub-research-2026-05-02.md` — research input documents that informed the architecture; preserved as frozen historical inputs per the existing `project_package_naming.md` precedent for AI-Hub research docs ("historical and should NOT be retroactively renamed — they document a frozen previous design"). The same logic applies: the research docs reflect the architect's pre-probe assumption.
    - `src/SessionAgent/Security/ReadOnlyRole.cls` lines 31, 38 + the probe transcript file — explanatory doc-comments that quote the rejected name as the **rationale** for the rename. Removing them would erase the "why" future readers need to understand the name choice. **Intentionally retained.**
  - **Why deferring the historical refs is correct:** authoring history of dev/story decisions is the audit trail for *why* the project converged on the current spec. Retroactively rewriting Story 1.1 and Story 1.2's authoring text would erase the trace that the rename was discovered in Story 1.4 Task 0, not pre-known at planning. The pattern matches the existing precedent in `project_package_naming.md` for the AI-Hub-coupled research docs ("historical and should NOT be retroactively renamed — they document a frozen previous design").
  - **Live-IRIS confirmation (2026-05-02 code review):** `Security.Roles.Exists("SessionAgent_ReadOnly")` returns 1; `Security.Roles.Exists("%SessionAgent_ReadOnly")` returns 0. The live role is correct.
  - **Owner:** None — historical preservation is the resolution. Future stories that re-cite `%SessionAgent_ReadOnly` should be flagged in code review as a stale reference.
  - **Blocking?** Not blocking. Story 1.5 (the natural carrier for installer-orchestrator wiring) inherits the corrected name from the updated planning artifacts.
  - **Triage 2026-05-03 (Story 2.0): dropped — historical preservation IS the resolution. Authoring history is the audit trail for *why* the rename happened in Story 1.4 Task 0; retroactive rewrites would erase the trace. Pattern matches existing `project_package_naming.md` precedent for AI-Hub research docs.**

---

## Deferred from: Story 1.7 lightweight CI scaffolding (2026-05-02)

- **`%UnitTest` execution step in `.github/workflows/ci.yml` awaits a Python-less IRIS 2024.1 community Docker image.**

  - **Source:** Story 1.7 implementation; TODO comment at `.github/workflows/ci.yml` lines 9–12.
  - **Severity:** LOW (no operator-observable break; dev-host `iris_execute_tests` remains the integration-test surface meanwhile).
  - **The deferral:** Story 1.7 shipped 4 PR-time gates (structural checks + NFR-C2 + NFR-C5) but did NOT add a `%UnitTest` execution step. The blocker is environmental: IRIS Community 2024.1 images currently bundle embedded Python by default, which violates the project's NFR-M9 Python-Optional Compilation invariant for end-to-end CI verification of the pure-OS-runtime promise. Until a publicly available Python-less IRIS 2024.1 community Docker image exists, CI cannot run the unit-test battery without contaminating the runtime environment.
  - **Workaround in place:** dev-host `mcp__iris-dev-mcp__iris_execute_tests` against the `SessionAgent.Test` package is the authoritative integration-test surface. Every story's Definition of Done requires the test pass empirically before commit.
  - **What needs to happen for resolution:** (a) InterSystems publishes a Python-less Community 2024.1+ image, OR (b) a community-built image emerges that satisfies NFR-M9, OR (c) CI matrix uses a paid/licensed IRIS image variant where Python can be excluded at install time. Once available, add a `%UnitTest` job to `ci.yml` that runs `Do ##class(%UnitTest.Manager).RunTest("SessionAgent.Test")` and asserts 9/9 (or current count) passing.
  - **Owner:** None — environmental blocker; revisit when image landscape changes.
  - **Blocking?** Not blocking any story. CI gates remain useful for structural + NFR invariants; unit-test regressions are caught at dev-host commit time.
  - **Triage 2026-05-03 (Story 2.0): deferred indefinitely until image exists — genuine future-work blocker; Story 1.7's TODO comment in `.github/workflows/ci.yml` names the gating condition. Dev-host `iris_execute_tests` remains the integration-test surface meanwhile.**

---

## Deferred from: code review of story-2.1-util-json-helpers (2026-05-03)

- **No defensive nil/empty-input guard on `Redact`, `DeepMerge`, `EmitNull`.**

  - **Source:** Story 2.1 code review (Blind Hunter B-2, Edge Case Hunter E-4).
  - **Severity:** LOW (Try/Catch already converts the resulting `<INVALID OREF>` or `<METHOD DOES NOT EXIST>` into a `%Status` error; AC-1 does not specify nil-input handling; foundational utility callers are internal `SessionAgent.*` code only — no untrusted input surface).
  - **The observation:** If a caller passes `pObj = $$$NULLOREF` or `pObj = ""` (empty string, common with uninitialized `%DynamicObject` variables) to `Redact`, `DeepMerge`, or `EmitNull`, the inner `pObj.%ToJSON()` / `pObj.%Set(...)` call throws an IRIS error. The Try/Catch block correctly converts the throw into a `%Status` error, so the caller's `$$$ISERR(tSC)` check still works — but the error message ("`<METHOD DOES NOT EXIST>` ... `%ToJSON`") is cryptic compared to a deliberate `If pObj = "" Quit $System.Status.Error($$$GeneralError, "Json.Redact: pObj is empty/null")`.
  - **Why deferring is acceptable:** (a) AC-1 does not require explicit nil guards; (b) the foundational utility is called only from internal `SessionAgent.*` code paths (audit emit, LLM provider request prep), all of which construct their `%DynamicObject` arguments before passing — nil-input is a programming bug at the call site, not user-data invalid input; (c) the Try/Catch already prevents process abort and surfaces the error via `%Status`; (d) the "real" hardening comes when the call sites land (Story 2.5 audit emit, Stories 2.8/2.9 LLM providers) — the call site can choose between defensive guards (skip redaction when `pObj` is null) or strict assertion (treat null as caller bug). Adding guards now would prematurely commit to one of those policies.
  - **What to do if it bites:** When Story 2.5 / 2.8 / 2.9 lands, add nil-input handling either at the call site (preferred — gives the caller policy control) or in `SessionAgent.Util.Json` (if every caller wants the same policy). At that point, also add a `TestRedactNilInputReturnsError` and equivalent for `DeepMerge` / `EmitNull`.
  - **Owner:** Whoever first hits a `<METHOD DOES NOT EXIST>` from a `SessionAgent.Util.Json` call (most likely Story 2.5 audit emit dev when an audit event fires before its payload object is initialized).
  - **Blocking?** Not blocking. Story 2.1 ships as-is; downstream stories inherit the Try/Catch-converts-to-`%Status` behavior and can layer their own nil policy.

- **No depth-limit on recursion in `Redact` / `DeepMerge`.**

  - **Source:** Story 2.1 code review (Blind Hunter B-4).
  - **Severity:** LOW (no untrusted-input surface; redaction operates on internally-constructed audit-log payloads, not parsed external JSON).
  - **The observation:** `RedactWalkObject` / `RedactWalkArray` / `MergeWalkObject` recurse without a depth bound. A deeply-nested JSON (e.g., 10K levels) would stack-overflow the IRIS process. Real-world risk is near-zero for the audit-log redaction call site (LLM request bodies are flat or 2-3 levels deep) and for `DeepMerge` (per-agent config files are typically 1-2 levels).
  - **Why deferring is acceptable:** (a) every current and planned caller constructs the input internally — no untrusted external JSON ever reaches `Util.Json`; (b) IRIS's default process stack can handle several thousand recursion levels before hitting `<MAXSTRING>` or `<FRAMESTACK>`, far above any realistic payload depth; (c) adding a depth-counter parameter to the helper signatures would clutter the foundational API for a hypothetical attack surface that doesn't exist; (d) if a future story does process untrusted JSON via `Util.Json` (none planned through Epic 12), that story should add the depth check at its boundary, not in the foundational utility.
  - **What to do if it bites:** add an optional `pMaxDepth As %Integer = 64` parameter to `Redact` and `DeepMerge`, default 64 (same as JSON-spec recommended max nesting), thread through to recursive helpers, throw `%Status` error on overflow. Add corresponding tests.
  - **Owner:** None — environmental; revisit if a future story routes user-supplied JSON through `Util.Json`.
  - **Blocking?** Not blocking anything.

---

## Deferred from: code review of story-2.3-util-envsecret-credential-resolution (2026-05-03)

- **No public IRIS API mutates a process's environment variables from inside the same process — affects every future story whose tests need to plant a sentinel env-var.**

  - **Source:** Story 2.3 Task 0 (irislib API verification) + code review.
  - **Severity:** LOW (Story 2.3 itself is unaffected — the test strategy adapted to read the OS-set `PATH` env-var as the env-var-rung input, which exercises the same code path empirically).
  - **The cross-cutting finding:** The Story 2.3 spec proposed using `$SYSTEM.Util.SetEnviron(name, value)` to plant a sentinel env-var per test. Empirical Task 0 probing on the dev host showed: (a) `$SYSTEM.Util.SetEnviron` does NOT exist on this IRIS install (`<METHOD DOES NOT EXIST>` error from `iris_execute_command`); (b) `$ZF(-2, name, value)` returns 0 but the value is silently discarded — a subsequent `$SYSTEM.Util.GetEnviron(name)` returns empty; (c) per Perplexity research, env vars are inherited at IRIS process startup and cannot be retroactively set from inside the same IRIS process. `%SYSTEM.Util` (irislib snapshot, line 86) exposes only `GetEnviron`.
  - **Story 2.3 mitigation (the PATH-pattern):** tests capture `$SYSTEM.Util.GetEnviron("PATH")` once at `OnBeforeAllTests` into a property `OsPathValue`, assert it is non-empty (test-host invariant), and use the captured value as the expected return from the env-var rung. `Resolve("PATH", "")` empirically traverses the same code path (`$SYSTEM.Util.GetEnviron(<non-empty name>)` returning a non-empty value) without needing a SetEnviron API. No env-var mutation occurs, so no env-var cleanup is needed. Documented in detail in the test class doc-comment at `src/SessionAgent/Test/EnvSecretTest.cls` lines 1-40.
  - **Why this is worth recording at the project level:** any future story whose tests need to plant a sentinel env-var inside IRIS will hit the same wall. Two viable workarounds emerged:
    1. **PATH-pattern (used by Story 2.3):** read an OS-set env-var that is reliably non-empty on every test host (PATH on Windows / Unix). Works when the test only needs to assert "the env-var rung returns the OS value"; doesn't work when the test needs to inject a specific sentinel value (e.g., to assert precedence over a competing source with a known string).
    2. **Subprocess-with-injected-env pattern (not yet used):** invoke a child IRIS process via `$ZF(-100)` with the `IRIS_*=val` injected into the child's environment; the child can `GetEnviron` it. Heavyweight; only justified when sentinel-value injection is mandatory.
    3. **Mock the resolver in tests (rejected for Story 2.3):** restructure the production class to take the env-var lookup as a callable / strategy and inject a stub in tests. Rejected because it changes the production class shape just to satisfy a test, and the PATH-pattern empirically tests the same code path without that change.
  - **Future-story considerations:** the most likely candidates are Story 2.9 (`OpenAIProvider` end-to-end test that wants `OPENAI_API_KEY` set to a known value) and any growth-tier provider story (Anthropic/Gemini/Ollama). When those stories enter dev, the story-creation skill should consider: (a) does the test only need "env-var resolves SOME non-empty value" (PATH-pattern works); (b) does the test need a specific sentinel value AND can it use `Ens.Config.Credentials` (rung 2) instead, where `SetCredential(...)` is a clean fixture API; (c) only if neither (a) nor (b) works, escalate to subprocess-with-injected-env or production-class mocking.
  - **Owner:** None at story creation — applies to whoever drafts a story whose tests need sentinel-env-var injection. Reference this entry from the story spec's Dev Notes if the story explicitly chooses one of the workarounds.
  - **Blocking?** Not blocking. Story 2.3 ships with the PATH-pattern; downstream stories inherit the documented options.

- **No test for "credential row exists with empty `Password`" — rung 2 falls through correctly but edge case not asserted.**

  - **Source:** Story 2.3 code review (Edge Case Hunter EC-1).
  - **Severity:** LOW (production behavior is correct: `tCredValue '= ""` check at line 101 means an empty Password causes fall-through to rung 3; an empty Password is not a valid API key and falling through is the right behavior).
  - **The observation:** `TestCredentialPathResolves` covers Password = `"cred-value-xyz789"` (non-empty). No test covers Password = `""` (operator created a credential row with Username only and forgot to set the password, or set it to empty deliberately). The fall-through to rung 3 (AES stub → empty) is the right behavior, but not asserted.
  - **What to do if it bites:** add `TestCredentialEmptyPasswordFallsThrough` that creates a credential row with `SetCredential("X", "user", "", 1)` and asserts `Resolve("", "X")` returns `""`. Two-line test plus one-line cleanup.
  - **Owner:** None — defer until Story 2.9 (`OpenAIProvider`) actually surfaces an empty-Password operator misconfig in a real test scenario; if it never does, the fall-through behavior is implicit and safe.
  - **Blocking?** Not blocking.

- **No test exercises the `Resolve` Try/Catch swallow path on a real exception — covered by inspection + contract only.**

  - **Source:** Story 2.3 code review (Edge Case Hunter EC-2).
  - **Severity:** LOW (the catch block is defensive against `tCred.Password` getter failures from `%CSP.Util.Passwd` → `%SYS.Ensemble.SecondaryGet`; forcing such a failure in a unit test would require corrupting secondary storage, which is impractical and risky).
  - **The observation:** The Try/Catch around lines 88-100 protects against any exception from `%OpenId` or the `.Password` getter. The `%ExistsId = 1` precondition (line 89) means `%OpenId` should always succeed; the real risk surface is the `%CSP.Util.Passwd.PasswordGet` delegation. No test forces this catch-path to execute. The comment at lines 97-98 documents the intent explicitly (swallow + no-log), and code-review inspection verifies the catch never embeds credential content into any log surface — but the empirical guarantee is missing.
  - **What to do if it bites:** if a future operator reports a credentials-row-corrupted scenario in production, add a regression test that uses a mocked credentials class (subclass of `Ens.Config.Credentials` with a `PasswordGet` that throws) injected via a story-specific test helper. Until then, the catch is correct by inspection.
  - **Owner:** None — defer until a real corruption scenario emerges.
  - **Blocking?** Not blocking.

- **`^ClineDebug` cleanup in `TestResolveDoesNotMutateClineDebug` is in-method rather than in `OnAfterOneTest` — if the prior assert fails, the `Kill` is skipped.**

  - **Source:** Story 2.3 code review (Blind Hunter B-4).
  - **Severity:** LOW (cosmetic — `^ClineDebug` is a transient debug global; leaking the sentinel string `"sentinel-before-resolve-call"` between tests has no functional impact, and any subsequent test that reads `^ClineDebug` would either ignore the existing value or set its own sentinel first).
  - **The observation:** `src/SessionAgent/Test/EnvSecretTest.cls` line 200 calls `Kill ^ClineDebug` at the end of the test method body, after the assertion at line 197. If the assert fails, the `Kill` is skipped and the sentinel persists in `^ClineDebug` until the next test runs (or until manual cleanup). The `OnAfterOneTest` cleanup at lines 80-88 only deletes the test credential row, not `^ClineDebug`.
  - **What to do if it bites:** move `Kill ^ClineDebug` into `OnAfterOneTest` (wrap in try-around-each-cleanup per the existing pattern). One-line change in `OnAfterOneTest`. Not worth a dedicated edit unless `OnAfterOneTest` is touched for unrelated reasons.
  - **Owner:** None (cosmetic).
  - **Blocking?** Not blocking.

- **Package-level `iris_execute_tests SessionAgent.Test` undercounts (returned 25 vs aggregate 35) — class-level runs confirm 35/35 pass.**

  - **Source:** Story 2.3 code review (verification step). Recurrence confirmed in Story 2.4 code review (2026-05-03): now reports 35/35 vs aggregate 45/45 (RetryWithBackoff still missing + ReadOnlyRole::RoleInstallIdempotent still missing; ConfigAgentTest's 10/10 IS picked up at package level).
  - **Severity:** INFO (no functional impact — every test passes when invoked at class level; the dev's claim of 45/45 is correct and verifiable).
  - **The observation:** Running `mcp__iris-dev-mcp__iris_execute_tests SessionAgent.Test` at `package` level returned `total:25, passed:25` in Story 2.3 era, missing all 9 RetryWithBackoff tests and 1 each of Json and ReadOnlyRole. In Story 2.4 era, it reports `total:35, passed:35` after ConfigAgentTest's 10 tests joined the package — but RetryWithBackoff (9) and ReadOnlyRole::RoleInstallIdempotent (1) are STILL absent. Running each class individually at `class` level returned the expected counts: AuditEmit=3, EnvSecret=8, Json=9, ReadOnlyRole=6, RetryWithBackoff=9, ConfigAgentTest=10, total 45. All 45 pass.
  - **Probable cause:** test-runner discovery quirk in the package-level path. The miss-list is consistent across both stories (RetryWithBackoff entire class + ReadOnlyRole::RoleInstallIdempotent), suggesting a deterministic discovery filter rather than a stale-metadata or queue-ordering issue. The Story 2.4 evidence (10 new tests successfully discovered at package level) rules out "all-new-tests miss"; the bug appears tied to specific class/method patterns.
  - **What to do if it bites:** if a future story claims an `N/N` count that doesn't match the package-level run, fall back to class-level invocations to confirm. Re-evaluate the deferral if a third story is bitten — the consistent miss-list may eventually justify investigation into the iris-dev-mcp test-runner code path.
  - **Owner:** None — environmental; class-level runs are the authoritative source until package-level discovery stabilizes.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-2.5-audit-ledger-schema-emit-helpers-recipe-doc (2026-05-03)

- **`OnAfterOneTest` and similar helpers in `AuditTest.cls` set `tOrigNS = $NAMESPACE` inside the Try block.** If the read of `$NAMESPACE` ever threw (it cannot — it's a literal special-variable read), the Catch block's `Set $NAMESPACE = tOrigNS` would `<UNDEFINED>` error. Defensive practice (already used in `Audit.Emit.RegisterIfMissing` and `EnsureEvents`) is to set `tOrigNS` BEFORE the Try block. Cosmetic; functionally fine because `Set tOrigNS = $NAMESPACE` cannot throw.
  - **Severity:** LOW.
  - **Locations:** `src/SessionAgent/Test/AuditTest.cls:69-78` (`OnAfterOneTest`), 243-251 (`TestRegisterIfMissingIsIdempotent`), 265-287 (`TestEpic1AuditEmitTripleRegistrationIntact`).
  - **What to do if it bites:** never — but if a future story adds a similar pattern, hoist the `Set tOrigNS` out of the Try block to match the production-code pattern in `Audit.Emit`.

- **No indices on `Timestamp` for either audit table (`SessionAgent.Audit.LlmCall` / `Audit.ToolCall`).** Recipes 1, 3, and 4 all filter `WHERE Timestamp >= ?`. Without an index on `Timestamp`, every recipe full-scans the extent. For the hobby-scale audit volume Story 2.5 ships against, this is fine. Once production volume grows (or once the recipes start running on every operator dashboard refresh), an index will become necessary.
  - **Severity:** LOW (out of Story 2.5 spec scope).
  - **Locations:** `src/SessionAgent/Audit/LlmCall.cls`, `src/SessionAgent/Audit/ToolCall.cls`.
  - **What to do if it bites:** add `Index TimestampIdx On Timestamp;` to both classes; recompile; the Storage section regenerates with the index map. Verify recipe 1's full-scan latency before/after on a populated table to confirm impact.

- **Recipe doc lacks an explicit operator note that `Timestamp` comparisons are lexical (string), not temporal.** Because `Timestamp` is `%String` (not `%TimeStamp` or `%Library.PosixTime`), `WHERE Timestamp >= ?` is a string comparison. The query works correctly only when the parameter is in the same fixed-width ISO-8601 form the rows use (`YYYY-MM-DDTHH:MM:SSZ`, 20 chars). A non-padded format like `2026-5-3T00:00:00Z` (no leading zeros) sorts incorrectly relative to `2026-05-03T00:00:00Z`. The corrected ObjectScript snippets in Recipes 1 and 2 produce the right shape, so an operator who copies the snippets is safe; the gap is for operators who hand-construct timestamps.
  - **Severity:** LOW (operator polish).
  - **Locations:** `docs/audit-sql-recipes.md`.
  - **What to do if it bites:** add a short note under the §"Note on case-sensitivity" section explaining the string-comparison contract and the exact ISO format the rows use.

- **Source:** Story 2.5 code review (2026-05-03). Two MED findings were auto-fixed in the same review pass: (1) `LogToolCall` now calls `RegisterIfMissing` BEFORE the row save so a registration failure does not leave a persisted row behind that a retry would duplicate; (2) `docs/audit-sql-recipes.md` Recipe 1 and Recipe 2 ObjectScript snippets corrected to produce well-formed ISO-8601 UTC parameters (the originals constructed malformed strings).

---

## Deferred from: code review of story-2.6-chat-history-chat-turn-persistence-concurrency-lock (2026-05-03)

- **`TestUpdatedAtAdvancesOnSave` test name no longer matches its body.** After the dev's wall-clock `Hang 1.1` workaround (the test runner silently dropped the method when wall-clock sleep was used; replaced with synthetic future timestamp `"2099-12-31T23:59:59Z"`), the test now validates timestamp **construction format** (length=20, T at char 11, Z at char 20) and byte-identical persistence round-trip — NOT the "advances on save" semantic the method name promises. AC-4's spec note explicitly says "this story doesn't require LoadOrCreate to advance UpdatedAt; AgentLoop Story 2.12 will set it on each turn save. This test verifies the timestamp construction works — set it manually in the test." So the body matches the spec's scoped intent; only the method name overshoots.
  - **Severity:** LOW (cosmetic; test passes; AC-4 contract satisfied).
  - **Location:** `src/SessionAgent/Test/ChatHistoryTest.cls:226–255`.
  - **What to do if it bites:** rename to `TestUpdatedAtRoundTripsByteIdentical` (or similar) when Story 2.12 (AgentLoop) adds the real "advances on save" behavior — at that point a sibling test `TestUpdatedAtAdvancesOnAgentLoopTurnSave` should be added under the AgentLoop test class, leaving this one to assert the lower-level construction/round-trip invariant.
  - **Owner:** Story 2.12 dev (natural carrier — they will implement the "advances on save" behavior in `AgentLoop.RunTurn` and own the test that verifies it).

- **`LoadOrCreate` empty-string parameter validation.** No guard against `pAgentName=""`, `pSessionKey=""`, or `pPortalUser=""`. The unique `ConvKeyIdx` would still be enforced on `("", "", "")` so a single empty-tuple row could be created and reopened on subsequent calls. Caller is currently trusted (`AgentLoop` will pass real values); v1 acceptable.
  - **Severity:** LOW (defensive validation gap; no operator-observable break for trusted callers).
  - **Location:** `src/SessionAgent/Chat/History.cls:157`.
  - **What to do if it bites:** add a 3-line guard at top of `LoadOrCreate`: `If (pAgentName="")||(pSessionKey="")||(pPortalUser="") { Set pStatus = $$$ERROR($$$GeneralError,"LoadOrCreate requires non-empty AgentName, SessionKey, PortalUser") Quit $$$NULLOREF }`. Natural carrier: Story 2.12 (AgentLoop) when wiring the real call sites — defensive validation belongs at the trust boundary, not here.

- **`Turn.FromCanonical` accepts non-string `role` without validation.** A malformed canonical input like `{role: {nested: "x"}, content: [...]}` would assign an OREF to `Turn.Role` (`%String`). Since `Turn` is `%RegisteredObject` (no `%Save`), no validation surfaces — the malformed value silently lands in memory and propagates to whatever serializes the turn back out.
  - **Severity:** LOW (defensive validation gap; trusted internal callers only — `Turn` is constructed from JSON the AgentLoop owns or from LLM provider responses validated upstream).
  - **Location:** `src/SessionAgent/Chat/Turn.cls:102`.
  - **What to do if it bites:** add a guard `If '$IsObject(pCanonicalTurnObj.role) { Set tTurn.Role = pCanonicalTurnObj.role } Else { Set tTurn.Role = "" }` or use `$Get` semantics on the dynamic-object property. Natural carrier: Story 2.9 (LLM OpenAI provider) or 2.12 (AgentLoop) when actual untrusted inputs flow into `FromCanonical`.

- **Source:** Story 2.6 code review (2026-05-03). One MED finding was auto-fixed in the same review pass: `LoadOrCreate` now accepts `ByRef pStatus As %Status` so callers can distinguish lock-conflict from save-failure from not-found, fixing the doc-comment claim that `tSC` was caller-visible (it was local-scope only). Compile clean; 9/9 ChatHistoryTest still passing; 62/62 full regression intact.

---

## Deferred from: code review of story-2.7-agent-dtos (2026-05-03)

- **`TurnResult.ToJson()` shares OREF aliases with caller's `UsageRollup` / `ToolCallsRendered` rather than deep-copying.** When `ToJson()` is called and a caller subsequently mutates `..UsageRollup` or `..ToolCallsRendered`, the previously-returned JSON string is immutable so the wire payload is fine — but the `%DynamicObject` returned from `ToJson()` is no longer in scope so the alias cannot leak there. The risk is purely if a future caller stores the temporary `tObj` reference (currently not exposed; method returns the JSON string only). Documenting for future-proofing if the method shape ever evolves to return the `%DynamicObject` directly.
  - **Severity:** LOW (no current operator-observable break; defensive design note for future evolution).
  - **Location:** `src/SessionAgent/Agent/TurnResult.cls:69, :77`.
  - **What to do if it bites:** if `ToJson()` is ever refactored to return the `%DynamicObject` (or to expose `tObj` to a caller), substitute deep-copy via `##class(%DynamicObject).%FromJSON(..UsageRollup.%ToJSON())` for the alias assignments. Natural carrier: any future story that extends `TurnResult` with a `ToDynamicObject()` method (none currently planned).

- **`%ResultSet` cleanup hygiene — `tRS.%Close()` not called in test helpers across the project.** `AgentDtoTest.cls`'s `ListUserMethods` was patched in this review to call `%Close()` (defensive). However, this is a project-wide hygiene gap — many other test classes use `%ResultSet` without explicit close. Cursor handles release on OREF GC, so impact is bounded.
  - **Severity:** LOW (resource hygiene; no operator-observable break).
  - **Location:** project-wide pattern; spot-check `src/SessionAgent/Test/*.cls` for `%ResultSet.%New` calls without paired `%Close()`.
  - **What to do if it bites:** add a project-wide grep + lint pass that flags `##class(%ResultSet).%New(...)` without a matching `%Close()` in the same method scope. Natural carrier: a future Epic-N retrospective action item if test-suite resource pressure becomes observable in CI.

- **Source:** Story 2.7 code review (2026-05-03). Two MED findings were auto-fixed in the same review pass: (a) `ListUserMethods` now validates `pClassName` exists before iterating (silent fake-green prevention for `TestNoBusinessLogic`) AND closes the `%ResultSet`; (b) `TestTurnResultToJsonHandlesEmptyArrays` was strengthened to assert the `usageRollup:{}` invariant, and a new `TestTurnResultToJsonHandlesUnsetDynamicProps` test was added to exercise the `ToJson()` Else branches with truly-unset properties (previously dead-tested code). Compile clean; 7/7 AgentDtoTest now passing (was 6/6); 69/69 full per-class regression intact (correcting both the original spec estimate of 68 and the dev's empirical 67 — actual baseline was 62, not 61, due to ConfigAgentTest having 10 test methods not 9).

---

## Deferred from: code review of story-2.9-llm-openaiprovider-concrete (2026-05-03)

- **`^||` (process-private global) does NOT preserve OREFs — record at project level so future stories don't repeat the trap.**
  - **Severity:** LOW (informational; Story 2.9 dev empirically discovered and worked around it within the story by refactoring from option-i to option-ii inline retry loop. No outstanding code change.)
  - **The empirical finding (Story 2.9 dev, verified via `Set ^||X=$This Write $IsObject(^||X)` returning 0):** `^||` process-private globals serialize their stored values to strings the same way persistent globals do. An object reference assigned to a `^||` slot loses its OREF identity on the next read; what comes back is the OID string, not a usable object. This blocks any pattern that tries to back-channel an instance reference across a static dispatch boundary (e.g., `RetryWithBackoff.Execute` → `$ClassMethod(<class>, "WrappedCallMessages")` — the static fixture has no `..` self to dispatch on, so callers that need instance state must find another channel).
  - **Two clean alternatives that DO preserve OREFs in-process:**
    1. **Inline orchestration on the instance** (Story 2.9's choice): replicate the orchestrator's logic inline inside the instance method, using only the orchestrator's STATELESS helpers (`IsRetryable`, `ParseRetryAfter`, `ExpBackoffSec`). Virtual dispatch on `..InstanceMethodHook()` works as expected. Cost: ~30 lines of duplicated retry-loop code per concrete; benefit: no cross-cutting infrastructure changes.
    2. **Refactor the orchestrator to take an instance + method-name pair** (deferred, larger refactor): `RetryWithBackoff.ExecuteOnInstance(pInstance, pMethodName, pArgsList)` that dispatches via `$Method(pInstance, pMethodName, pArgsList...)` — that builtin DOES preserve virtual dispatch. Story 5.x (Anthropic/Gemini/OpenAICompat) MAY adopt this if duplicating the inline retry loop becomes maintenance friction.
  - **Why deferring (not fixing now) is correct:** Story 2.9 ships clean with option (i)'s inline duplication (30 lines). Stories 5.1–5.3 will each add another ~30 lines of similar inline retry; if the cumulative duplication crosses ~120 lines, the architect should evaluate option (2) as a follow-up cleanup at Epic 5 retro time. Premature refactor before the second concrete ships would commit to a shape that may not fit Anthropic's `Retry-After: HTTP-date` parsing or Gemini's structured `retryDelay` envelope.
  - **What to do if it bites:** at Epic 5 retro time, audit the four concrete provider classes (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`, `OpenAICompatProvider`) for retry-loop duplication. If duplication exceeds the threshold the architect sets, refactor the orchestrator to `ExecuteOnInstance(pInstance, pMethodName, ...)` and migrate all four concretes to it.
  - **Owner:** Architect at Epic 5 retro (natural carrier — first opportunity to evaluate the duplication-vs-abstraction trade-off across all four concretes).
  - **Blocking?** Not blocking. Story 2.9 ships; Stories 5.1–5.3 will follow the same inline-retry pattern.

- **Source:** Story 2.9 code review (2026-05-03). Two LOW cosmetic findings were auto-fixed in the same review pass: (a) two stale doc-comment references to `WrappedCallMessages` (the option-i fixture method that was removed when the dev refactored to option-ii inline retry) corrected to `CallMessages` / "inline retry loop in `CallMessages`" at `OpenAIProvider.cls` lines 146 and 502. (b) Story-file regression-count reporting corrected from 82/82 to 87/87 (dev had undercounted AuditTest as 3 — actual is 8; confirmed empirically by `iris_execute_tests SessionAgent.Test.AuditTest` returning `total:8, passed:8`).

---

## Deferred from: code review of story-2.8-llm-provider-abstract-adapter-utilities (2026-05-03)

- **No test exercises the OpenAI tool_result fan-out path in `MessageAdapter.CanonicalToOpenAi`.**
  - **Severity:** LOW (silent-regression risk only; the path compiles and is exercised whenever a real OpenAI provider receives a `tool` role canonical message at runtime — but no unit test locks the behavior).
  - **Location:** `src/SessionAgent/LLM/Util/MessageAdapter.cls:195-224` (the `If tRole = "tool"` branch that emits one OpenAI message per `tool_result` block) plus `src/SessionAgent/Test/MessageAdapterTest.cls` (no covering `Test*` method).
  - **The gap:** `TestCanonicalToGeminiRoleMapping` exercises a single `tool_result` block but tests Gemini's `functionResponse` part, not OpenAI's per-block fan-out. `TestRoundTripOpenAi` exercises assistant-side `tool_use`, not the tool-side `tool_result`. The OpenAI tool-message emission has its own non-trivial logic (per-block iteration, `tool_use_id` → `tool_call_id` rename, content stringification of array form via `%ToJSON`) that is currently uncovered.
  - **What to add:** one new `Test*` method that feeds a canonical `tool` role message with TWO `tool_result` blocks (one with string content, one with array-of-text-blocks content) and asserts the OpenAI output is TWO `{role:"tool", tool_call_id, content:...}` messages with the expected stringified content shapes.
  - **Why deferred (not fixed in review):** AC-4 enumerates seven specific `Test*` methods for `MessageAdapterTest`; the fan-out test is not among them. Adding it now would expand AC-4 scope mid-review. Natural carrier: Story 2.9 (`OpenAIProvider`) which will be the first real consumer of this path — its dev cycle should add the missing coverage as part of integration testing the OpenAI wire shape end-to-end.
  - **Owner:** Story 2.9 dev (when implementing `OpenAIProvider`'s `CallMessages`).
  - **Blocking?** Not blocking. The path is logically correct on inspection; this is a defense-in-depth coverage gap, not a bug.

- **Source:** Story 2.8 code review (2026-05-03). Two findings were auto-fixed in the same review pass: (a) `MessageAdapter.CanonicalToOpenAi` line 239 used the literal two-character string `"\n"` (backslash + n) when concatenating multiple text blocks for OpenAI's single `content` field — ObjectScript double-quoted strings do not interpret backslash escapes, so the user-visible content was getting `foo\nbar` instead of `foo` + newline + `bar`; replaced with `$Char(10)` plus a clarifying inline comment. (b) `Provider.ComputeLatencyMs` doc-comment said "integer-truncated" but `$Normalize(tDelta * 1000, 0)` rounds half-up; corrected the doc-comment to "integer-rounded (via `$Normalize`)". Both fixes verified: 5 classes recompile clean; 7/7 MessageAdapterTest + 3/3 ToolDefAdapterTest pass; 79/79 full per-class regression sweep intact (zero regressions across the 9 prior test classes — AgentDtoTest 7 + AuditEmit 3 + Audit 8 + ChatHistory 9 + ConfigAgent 10 + EnvSecret 8 + Json 9 + ReadOnlyRole 6 + RetryWithBackoff 9 + MessageAdapter 7 + ToolDefAdapter 3 = 79).

---

## Deferred from: code review of story-2.10-tool-base-abstract-tool-registry-task-0-probe (2026-05-03)

- **`Tool.Registry` discovery query is direct-subclass-only — transitive subclasses invisible to `ListTools`/`ResolveToolName`.**

  - **Source:** Story 2.10 code review (2026-05-03).
  - **Severity:** LOW (no impact on Story 2.10 — v1 inspection + search tools all extend `SessionAgent.Tool.Base` directly per architecture pattern).
  - **The gap:** `Tool/Registry.cls:54` and `:234` use `WHERE %EXACT(Super) = 'SessionAgent.Tool.Base' AND Abstract = 0` — this finds ONLY direct subclasses. If a future epic introduces an intermediate base class (e.g., `SessionAgent.Tool.Inspection.Common Extends SessionAgent.Tool.Base` and then `SessionAgent.Tool.Inspection.SessionSummary Extends SessionAgent.Tool.Inspection.Common`), the leaf class will not appear in `ListTools()` output and `Dispatch("session_summary",...)` will return the unknown-tool envelope. Spec line 41 says "all subclasses of SessionAgent.Tool.Base in the current namespace" — direct-vs-transitive ambiguous.
  - **Why deferring is acceptable:** v1 architecture (architecture.md §"Pattern Examples — canonical tool implementation skeleton") shows every concrete tool extending `SessionAgent.Tool.Base` directly with no intermediate. Stories 2.11 (three example Inspection tools) and 4.x (full Inspection suite) follow that pattern. No operator-observable break in v1.
  - **What to add when surfaced:** swap the SQL filter for a recursive ClassDefinition walk (e.g., `%Dictionary.CompiledClass.PrimarySuperList` traversal) OR maintain an explicit `ToolHierarchy` list in the registry. Add a regression test (`TestListToolsIncludesIndirectSubclass`) with a chained stub fixture (`StubReadOnlyChild Extends StubReadOnlyTool`) when the change lands.
  - **Owner:** Whoever introduces the first intermediate base class (likely an Epic 4 or Epic 8 dev). The story that introduces it MUST extend `Tool.Registry` discovery in the same commit.
  - **Blocking?** Not blocking. v1 stays direct-subclass for the foreseeable future.

- **`Tool.Registry.Dispatch` does not defensively guard against null `pCallerCtx` in the audit-emit branch.**

  - **Source:** Story 2.10 code review (2026-05-03).
  - **Severity:** LOW (no impact — every internal caller — `AgentLoop`, the future MCP handler — constructs a `CallerContext` before dispatch; defense-in-depth gap, not a bug).
  - **The gap:** `Tool/Registry.cls:175–178` reads `pCallerCtx.AgentName` inside the `If tDispatchAttempted = 1` block — which executes AFTER the outer Try/Catch closes. If `pCallerCtx` were `$$$NULLOREF` or `""`, this would throw `<INVALID OREF>` outside any catch and the caller would see an uncaught exception instead of the standard envelope. The defensive `$IsObject($Get(pJsonArgs))` checks at lines 180 and 184 suggest the dev was thinking defensively about `pJsonArgs` but skipped the same posture for `pCallerCtx`.
  - **Why deferring is acceptable:** Every constructed call site uses `##class(SessionAgent.Agent.CallerContext).%New()` per Story 2.7 contract; tests in `ToolRegistryTest.cls:74–82` (`NewInspectionCtx` helper) confirm the construction shape. There's no path in shipped code that hands `Dispatch` a null context.
  - **What to add when surfaced:** at the top of `Dispatch`, add `If '$IsObject($Get(pCallerCtx)) { Set pResult = {"isError":(1), "content":[{"type":"text", "text":"missing caller context"}]} Quit $$$OK }` plus a `TestDispatchRejectsNullCallerContext` regression test.
  - **Owner:** Whichever story first introduces a non-internal caller (e.g., the MCP server export deferred from v1 scope per `project_v1_scope_boundaries.md`).
  - **Blocking?** Not blocking. Internal callers always construct a valid context.

- **MCP `iris_execute_tests` truncation on `ToolRegistryTest` — addendum to existing Story 2.4 entry.**

  - **Source:** Story 2.10 code review (2026-05-03).
  - **Severity:** LOW (tooling quirk, not a code defect).
  - **The observation:** `mcp__iris-dev-mcp__iris_execute_tests` against `SessionAgent.Test.ToolRegistryTest` consistently reports `total: 5–6` while the underlying `^UnitTest.Result` global captures all 7 method results with `status=1`. This is a read-timing window in the MCP server — the response is read before the runner finishes writing the trailing entries. The faster `ToolBaseTest` (sub-2ms per method) does not hit the window.
  - **Verification path:** dev verified 7/7 by walking `^UnitTest.Result(<lastIdx>, <suite>, "SessionAgent.Test.ToolRegistryTest", *)` directly, confirming all 7 entries with `status=1` and non-zero durations.
  - **Owner:** MCP server maintainer (out of project scope). This is the second instance of this quirk seen on Story 2.x suites — append to the existing Story 2.4 deferred-work entry as a recurrence note rather than a new entry.
  - **Blocking?** Not blocking. Operator workaround is the `^UnitTest.Result` direct read documented above.

---

## Deferred from: code review of story-2.11-three-example-inspection-tools (2026-05-03)

- **`Ens.MessageHeader.TimeCreated` surfaced as server-local ODBC timestamp string (not ISO-8601 UTC with Z) in tool output.**

  - **Source:** Story 2.11 code review (2026-05-03) — Blind Hunter + Edge Case Hunter overlap.
  - **Severity:** LOW (no operator-observable break in Story 2.11 itself; the tool output is structurally well-formed and the dev's tests assert chronological ordering via lexical compare which works on ODBC strings; deferring because the fix needs to span all three tools and a future test asserting the format).
  - **The observation:** Three tools project `TimeCreated` (`Ens.DataType.UTC` — ODBC TIMESTAMP) directly into `pResult.structuredContent.events[].time` (SessionTimeline) and `headers[].time_created` (MessageHeaders), and DATEDIFF computes durations from the same column (SessionSummary). IRIS surfaces TIMESTAMP values as `yyyy-mm-dd hh:mm:ss[.fff]` strings WITHOUT a `Z` suffix, in the IRIS process locale (server-local time) — NOT the ISO-8601 UTC `2026-05-03T10:30:45Z` shape mandated by the project rule §"Timestamp and Encoding Standards". When SessionTimeline's optional `from_time` / `to_time` ISO-8601 UTC bounds are exercised against this server-local stored data, the `WHERE TimeCreated >= ?` comparison silently mixes timezones — operator filters by UTC bounds but the rows are stored in local time, producing an off-by-N hours skew when the server is not on UTC.
  - **Why deferring is acceptable:** (a) Story 2.11's AC-2/AC-3 specify the tool output shape but do NOT mandate ISO-8601 UTC normalization on the projection — the spec was written assuming the column projects as-is; (b) every other Ens tool in the namespace (Mgmt Portal, business-process viewer, message browser) shows the same server-local rendering, so the inspection tool is consistent with operator expectations on this IRIS install; (c) a fix would need to (i) normalize the projection in all three tools, (ii) pre-convert the SessionTimeline `from_time`/`to_time` bounds back to server-local for the SQL predicate (or change the query to `CAST` the column to UTC inside SQL), and (iii) add covering tests — this is a focused tightening pass, not a one-line edit; (d) the most likely natural carrier is the AgentLoop smoke-test story (2.12) which is the first story to exercise these tools end-to-end against the LLM and observe what the operator-readable text actually looks like.
  - **What to do if it bites:** in SessionSummary/SessionTimeline/MessageHeaders, replace `TimeCreated AS event_time` / `... AS time_created` projections with `$Translate($ZDateTime($ZDateTimeH(TimeCreated, 3) - $ZTimeZoneH/86400, 3, 1), ' ', 'T') || 'Z'` (or the SQL equivalent) to normalize to ISO-8601 UTC at the projection. Add `TestTimeProjectionIsIsoUtcWithZ` per tool that asserts the format `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`. For SessionTimeline, also pre-convert `from_time` / `to_time` UTC ISO inputs to server-local before binding into the predicate (or wrap the column in a UTC-conversion SQL function on both sides of the comparison).
  - **Owner:** Story 2.12 dev (AgentLoop smoke test) — first story that will see the operator-facing output of these tools and judge whether the server-local timestamp format is acceptable for operator/LLM consumption. If 2.12 dev confirms acceptable, defer further until an operator complains; if not, fix in 2.12's scope.
  - **Blocking?** Not blocking Story 2.11 or Story 2.12. Becomes a real bug only when (a) an operator queries SessionTimeline with explicit UTC ISO bounds AND (b) the IRIS server runs in a non-UTC locale. Both currently true for very few hobby installs.

- **`min_severity` filter in MessageHeaders is case-sensitive — `"ERROR"` / `"Error"` silently no-ops.**

  - **Source:** Story 2.11 code review (2026-05-03) — Edge Case Hunter.
  - **Severity:** LOW (JSON Schema enum constrains valid values to lowercase `info|warning|error`; only relevant if the LLM ignores the schema and sends mixed-case input).
  - **The observation:** `MessageHeaders.cls:77` uses `If tMinSev = "error"` — ObjectScript string comparison is case-sensitive, so `"Error"` / `"ERROR"` / `"eRRor"` skip the IsError=1 filter and return all 5 rows instead of the 2 error rows. The JSON Schema declares `enum: ["info","warning","error"]` so a strictly compliant LLM will only send the canonical lowercase form, but the schema is informational at the tool level (the architecture's "Tool input JSON Schema subset" doesn't mandate runtime schema validation inside `Invoke`).
  - **Why deferring is acceptable:** the JSON Schema enum is the contract; non-conformant input is the LLM's bug, not the tool's. Adding case-folding (`If $$$LOWER(tMinSev) = "error"`) would silently mask a contract violation that should surface as a no-op result (5 rows instead of the expected 2). When the LLM's prompt is wrong, returning more data than expected is the safer failure mode than silently coercing — the operator will notice "wait, all 5 rows are showing".
  - **What to do if it bites:** if Story 2.12's AgentLoop smoke-test or a real operator session shows the LLM consistently sending mis-cased severity values, add `Set tMinSev = $ZConvert(tMinSev, "L")` immediately after the `pJsonArgs.%Get("min_severity")` read to normalize. Add `TestMessageHeadersAcceptsMixedCaseMinSeverity` to lock the new behavior.
  - **Owner:** Story 2.12 dev or a future per-tool-hardening story.
  - **Blocking?** Not blocking.

- **Process-private global subscript naming convention — hyphens (`-`) are invalid; use camelcase or remove punctuation.**

  - **Source:** Story 2.11 code review (2026-05-03) — Edge Case Hunter; recurrence-tracking from dev's empirical discovery in Story 2.11 implementation.
  - **Severity:** LOW (project-wide convention finding; Story 2.11 already self-corrected from `^||SessionAgentTest2-11Ids` to `^||SessionAgentTest211Ids`).
  - **The observation:** ObjectScript treats `-` as the subtraction/negation operator inside subscript expressions, so `^||SessionAgentTest2-11Ids` parses as `^||(SessionAgentTest2 - 11) _ "Ids"` — almost always a `<SYNTAX>` error. The same trap applies to `^||X.y.z` (`.` is OREF dispatch), `^||X+1` (`+` is unary plus), and any other operator character. Safe characters: alphanumeric + `_` (when not at the start). The Story 2.11 spec proposed a hyphenated subscript and the dev had to discover and fix it during implementation.
  - **Why this is worth recording at the project level:** the `bmad-create-story` workflow has shipped at least one story spec with an invalid subscript (Story 2.11). If the spec had been written by a less-experienced dev or a future agent without the empirical context, the trap could ship as a runtime `<SYNTAX>` error in the test fixture. Codifying the convention here lets future story specs (and code reviewers) flag invalid subscripts at spec-writing time.
  - **What to do:** when a story spec proposes a `^||` (or any global) subscript with non-alphanumeric characters, the lead/code-reviewer should flag it during spec review. Recommended convention: alphanumeric + camelcase (e.g., `^||SessionAgentTest211Ids`, `^||MyToolFixtureRowIds`) — no hyphens, dots, or operator characters.
  - **Owner:** None (process item). Lead at story-creation time. Code reviewer if the spec slips through.
  - **Blocking?** Not blocking.

- **`OnBeforeAllTests` observed running TWICE within a single `iris_execute_tests` invocation per dev's notes — root cause not investigated.**

  - **Source:** Story 2.11 dev notes (Other observations) + code review (2026-05-03).
  - **Severity:** LOW (idempotent in practice — the defensive `DELETE FROM Ens.MessageHeader WHERE SessionId = ?` sweep at the top of `OnBeforeAllTests` makes the duplicate invocation harmless; the second seed write happens with a fresh slate after the first's rows are wiped).
  - **The observation:** Dev added a `^ClineDebug` instrument during fixture diagnosis and observed `OnBeforeAllTests` firing twice in a single `iris_execute_tests SessionAgent.Test.InspectionToolTest` invocation. The fixture is idempotent (defensive sweep + capture-IDs-by-tIdx so the second call overwrites the first's IDs in the same global), so all 9/9 tests still pass. Cause not investigated.
  - **Why deferring is acceptable:** behavior is idempotent and the test counts come out correct. Investigation cost (instrument the test runner, walk `^UnitTest.Result` writes, possibly file an iris-dev-mcp issue) far exceeds the impact (zero — fixture is built to tolerate the duplication).
  - **What to do if it bites:** if a future test class's `OnBeforeAllTests` does NON-idempotent work (e.g., increments a counter, reserves a unique ID, sends an email) and surfaces a duplicate side effect, instrument with `^ClineDebug = ^ClineDebug _ "OnBeforeAllTests called at " _ $ZH _ ";"` and run the suite to confirm the doubling, then file an iris-dev-mcp issue. Until then the convention should be: `OnBeforeAllTests` MUST be idempotent (defensive sweep + overwrite-safe fixture writes).
  - **Owner:** None — environmental quirk; recurrence-tracking only.
  - **Blocking?** Not blocking.

- **SessionSummary returns success envelope (zeros + empty root_class) for unknown session_id — operator cannot distinguish "session does not exist" from "session exists with 0 messages."**

  - **Source:** Story 2.11 code review (2026-05-03) — Edge Case Hunter.
  - **Severity:** LOW (semantic ambiguity; Story 2.11 spec does not require differentiation; the LLM/operator can infer "unknown session" from the message_count=0 + empty root_class combination).
  - **The observation:** `SessionSummary.cls:102-118` — when `tRs.%Next()` returns nothing (unknown session_id), the aggregate query returns one row with COUNT=0 / SUM=NULL / MIN=NULL / MAX=NULL, so `tMsgCount=0`, `tErrCount=0`, `tDurationMs=0`. The root-class query returns no rows so `tRootClass=""`. The output text reads `"Session 99999: 0 messages, 0 errors, root class ."` — slightly malformed (period directly after "class " with no class name) and semantically indistinguishable from a real session that happens to be empty (which would never happen in real Ens runtime — every session has at least one message).
  - **Why deferring is acceptable:** Ens sessions in practice always have ≥1 message (the session is created BY the first message), so an empty real session does not exist. The "unknown session" case surfaces as the all-zeros envelope which the LLM/operator can reasonably interpret. The fix would add a 4th SQL probe (`SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ?` short-circuit) or a structuredContent boolean field `session_exists` — both add complexity for a marginal UX improvement.
  - **What to do if it bites:** add `If tMsgCount = 0 { Set pResult.content.%Get(0).text = "Session " _ tSessionId _ " not found or empty." Do pResult.structuredContent.%Set("session_exists", 0, "boolean") }` plus a corresponding non-zero branch. Add `TestSessionSummaryUnknownSessionReturnsExistsFalse`.
  - **Owner:** Story 2.12 dev or a future per-tool-hardening story; if AgentLoop smoke-test sees the LLM mis-interpret the all-zeros envelope, fix at that point.
  - **Blocking?** Not blocking.

---

## Resolved during Story 1.5 verification (2026-05-02) — superseded by README §"Operator Prerequisites" §1

- **`zpm` was installed in `%SYS` but not mapped into HSCUSTOM. Required `zpm "enable -map -globally"`.**
  - **First-attempt symptom:** `zpm "load c:/git/iris-session-agent"` errored with `<CLASS DOES NOT EXIST>DisplayError *%IPM.Repo.UniversalSettings`. The class actually exists and is fully compiled in `%SYS` (verified empirically via `%Dictionary.ClassDefinition.%ExistsId` returning 1 and `##class(%IPM.Repo.UniversalSettings).%New()` succeeding). The error appeared because the IPM lifecycle's Configure phase context-switches into the install target namespace (HSCUSTOM), where `%IPM.*` classes had no mapping.
  - **Resolution (single command from `%SYS`):** `zpm "enable -map -globally"` — maps the `%IPM` package and `%IPM.*` routines from `%SYS` into HSCUSTOM, HSSYS, HSSYSLOCALTEMP, IRISCOUCH, USER. After the mapping, `zpm load` from HSCUSTOM succeeded end-to-end across all six IPM lifecycle phases on first install AND on idempotent reinstall.
  - **Architecture confirmation (Perplexity research, training-knowledge basis):** IPM follows install-once-in-`%SYS` plus map-across-namespaces. The bundled HealthShare 0.9.0+snapshot in HSLIB/HSSYS is read-only DeveloperMode and exists only for HealthShare's own internal package management; not relevant to user-namespace mapping.
  - **Operator-observable state propagated:** README §"Operator Prerequisites" §1 now documents the install-IPM-and-enable-globally sequence as a one-time setup step. Story 1.5's commit carries this README change (per `research-first.md` rule 5: operator-observable state must ride the commit). No follow-up work needed; Story 1.7 (CI scaffolding) inherits the documented prerequisite as a normal CI environment-setup step.

---

## Deferred from: code review of story-2.12-agent-agentloop-orchestration-end-to-end-smoke-test (2026-05-03)

- **AgentLoop tool dispatch defends thin against malformed `tool_use` blocks (empty `id`, non-object `input`).**

  - **Source:** Story 2.12 code review (Blind Hunter B7 + Edge Case Hunter E5).
  - **Severity:** LOW — current production providers (OpenAI, future Anthropic/Gemini) populate `id` and `input` per their respective specs; the model would have to emit a malformed block.
  - **The two thin-defense points in `AgentLoop.RunTurn`:**
    1. `c:/git/iris-session-agent/src/SessionAgent/Agent/AgentLoop.cls:251-254` — `tBlockToolUseId` defaults to empty string when `id` is absent. The `tool_result` block then carries `tool_use_id = ""`. The next round-trip sends this empty id back to the model, which both OpenAI and Anthropic specs require to be non-empty — provider responds with HTTP 400, which the AgentLoop surfaces as a structured error envelope. Defensible (no crash) but the operator gets a generic 400 instead of a clearer "model emitted tool_use without id" message.
    2. `c:/git/iris-session-agent/src/SessionAgent/Agent/AgentLoop.cls:255-258` — `tBlockInput = tBlock.%Get("input")` is then passed to `Tool.Registry.Dispatch(...)` and `tCard.%Set("args", tBlockInput)`. If `input` is a JSON string instead of an object (some weakly-typed model outputs), `Dispatch` receives a string. Tool implementations defend with `$IsObject` checks, so this degrades to the tool's "missing required arg" path — not a crash, but the diagnostic is sub-optimal.
  - **Recommended fix (when picked up):** add `If '$IsObject(tBlockInput) Set tBlockInput = ##class(%DynamicObject).%New()` after line 258, and synthesize `tBlockToolUseId = "call_" _ tIter _ "_" _ tBidx` when the model omits `id`. Both defenses are 1-2 lines each.
  - **Owner:** Whoever next touches `AgentLoop.RunTurn` (Epic 3 hyperevent dispatch, or Story 5.x when adding the second provider concrete that may surface this in production telemetry).
  - **Blocking?** Not blocking. Mock + production coverage is intact; OpenAI's well-formed tool_use blocks satisfy the contract today.

- **`SmokeTest.OnBeforeAllTests` swallows `tHdr.%Save()` failures during the 5-row Ens.MessageHeader fixture seed.**

  - **Source:** Story 2.12 code review (Blind Hunter B17).
  - **Severity:** LOW — the smoke test runs on the maintainer's local IRIS; a save failure during fixture seed is rare and surfaces downstream as a count assertion failure (`tLlmCount = 0` instead of 2).
  - **Location:** `c:/git/iris-session-agent/src/SessionAgent/Test/SmokeTest.cls:89-91` — the inner `For` loop checks `If $$$ISERR(tSaveSC) Quit` which exits the loop body but the outer `OnBeforeAllTests` returns `$$$OK` regardless of how many rows actually persisted. The maintainer running the smoke test sees the assertion fail at `5 messages` substring without context.
  - **Recommended fix:** propagate the save failure to `OnBeforeAllTests`'s return status: `If $$$ISERR(tSaveSC) Quit tSaveSC`. The IRIS unit-test framework will skip the test method with the failure surfaced.
  - **Owner:** Whoever next touches `SmokeTest.cls` (Story 2.12a real-API smoke test, or any future maintenance pass).
  - **Blocking?** Not blocking. Defensive sweep on line 73 + idempotent re-run mitigate.

- **`Chat.History.LoadOrCreate` NULLOREF return surfaces a single generic "Concurrent turn in progress" envelope regardless of underlying cause.**

  - **Source:** Story 2.12 code review (Edge Case Hunter E11).
  - **Severity:** LOW — observed by the operator only when the lock contention path fires. The current envelope is operator-readable; differentiating "lock conflict" from "persistence error" from "validation error" adds diagnostic value when triaging production issues but does not block any AC.
  - **Location:** `c:/git/iris-session-agent/src/SessionAgent/Agent/AgentLoop.cls:131-136` — `If '$IsObject(tHist)` returns "Concurrent turn in progress; please wait." even when `tLoadStatus` carries a different error (e.g., a persistence-layer issue that would warrant a different operator response).
  - **Recommended fix:** inspect `tLoadStatus` and surface a richer message when the cause is non-lock: `If $$$ISERR(tLoadStatus) Set tResult.AssistantMarkdown = "Chat history error: " _ $System.Status.GetErrorText(tLoadStatus)` else fall through to the lock-contention message.
  - **Owner:** Whoever next touches `AgentLoop.RunTurn` (Epic 3 hyperevent dispatch, or Story 5.x).
  - **Blocking?** Not blocking. Acceptable degradation for v1.

---

## Deferred from: code review of story-3-2-client-side-chat-panel-js-mvp-render-submit (2026-05-03)

- **`data-tool-call-id="tc-N"` synthesis vs. citation-chip `data-cite-id` lookup contract — Story 3.4 must bridge the gap.** **[CLOSED 2026-05-03 by Story 3.4 — Rule 9 binding deferral honored]**

  - **Source:** Story 3.2 code review (lead's prompt item 2 — contract-handoff to Story 3.4).
  - **Severity:** MEDIUM (predicted bug — Story 3.4's `sa-cite-tool` chip click handler will not be able to look up the matching tool-call card by id without a bridging strategy).
  - **The gap:** Story 3.2's `renderToolCard` synthesizes `data-tool-call-id="tc-{dispatchIndex}"` (e.g., `tc-0`, `tc-1`) because the `Agent.TurnResult` DTO does NOT ship a real per-tool-call id (verified against `src/SessionAgent/Agent/AgentLoop.cls:302-316` — DTO shape is `{name, args, result, status}` only). Story 3.4 will wire the `sa-citation-chip.sa-cite-tool` `onclick` handler to "open the matching tool-call card" — but the `data-cite-id` on the chip comes from the LLM's Markdown emission (e.g., `[tool:list_sessions]` -> `data-cite-id="list_sessions"`). The chip's id ("list_sessions") does NOT match the card's synthetic id ("tc-3"), so a naive `document.querySelector('[data-tool-call-id="' + chipCiteId + '"]')` lookup will return null.
  - **Three resolution paths Story 3.4 can pick:**
    1. **System-prompt convention.** Update the agent system prompt to instruct the LLM to emit citations of the form `[tool:tc-N]` where N is the dispatch index. The LLM has visibility into dispatch order via tool_use blocks, but this is brittle (LLM may invent ids that don't match).
    2. **Tool-name lookup.** Story 3.4's onclick handler does `document.querySelectorAll('.sa-tool-call-card')` and walks them, matching by the tool name shown in `<code class="sa-tool-name">`. Robust against any LLM citation form, but O(n) per click and breaks if the same tool is called multiple times in one turn.
    3. **Index-of-call lookup.** Update `renderToolCard` to also tag each card with `data-tool-name="{card.name}"` AND `data-tool-call-occurrence="{nth-time-this-tool-appears}"`. Story 3.4's chip handler asks the LLM to emit `[tool:list_sessions#1]` for the first call, `#2` for the second, etc. Most expressive but needs LLM cooperation.
  - **Recommendation:** Path 2 is the cleanest for v1 (no LLM-prompt changes; works regardless of citation form; Story 3.4 owns the handler entirely so the change is local). Story 3.4's spec author should pick a path explicitly and document it in the spec — this entry is the binding handoff.
  - **Owner reassigned to Story 3.4** (`sa-cite-tool` chip handler authoring).
  - **Why this is a Rule 9 binding deferral, not a fix-now in Story 3.2:** Story 3.2's contract surface (`data-tool-call-id` on cards) is correct given the DTO reality. The bug shape is on the consumer side (the not-yet-written click handler in Story 3.4), not on the producer side (the cards themselves). The synthesis the dev chose is reasonable; the contract just needs the consumer to know about it. Per Rule 9, Story 3.4's spec MUST grep `deferred-work.md` for "Story 3.4" mentions and incorporate this carry-forward into its ACs.
  - **Blocking?** Blocks Story 3.4 entering dev — must be addressed in Story 3.4's scope.
  - **CLOSURE (Story 3.4, 2026-05-03):** Path 2 (tool-name lookup) implemented exactly as recommended, with Path 1 (dispatch-index `tc-N`) retained as fallback. Closure mechanism:
    - **Producer side** (`static/chat-panel.js` `renderToolCard`): added `details.setAttribute('data-tool-name', (card && card.name) || '')` alongside the existing `data-tool-call-id="tc-N"`. Both attributes coexist on every card.
    - **Consumer side** (`src/SessionAgent/EnsPortal/VisualTrace.cls` `onCitationClick` ClientMethod): tool-type branch does `document.querySelector('.sa-tool-call-card[data-tool-name="' + CSS.escape(id) + '"]')` first, falls back to `data-tool-call-id` if no name match. Either citation form (`[tool:list_sessions]` OR `[tool:tc-3]`) lands the right card. CSS.escape() availability per NFR-C6 evergreen-browser scope (no polyfill needed).
    - **Limitation documented inline** (per spec Carry-Forward decision): "when the same tool name appears multiple times in one turn, the handler picks the FIRST matching card." Re-deferred to Epic 10 ONLY if a real-world duplicate-tool case surfaces — this story does not pre-defer.
    - **Test coverage:** `ChatPanelJsTest.TestRenderToolCardEmitsToolNameAttr` (producer) + `VisualTraceTest.TestOnCitationClickPresent` (consumer — asserts both `data-tool-name` and `data-tool-call-id` lookups present in the ClientMethod body). Both passing.



---

## Deferred from: code review of story-3-3-ensportal-visualtrace-subclass-tab-placement-zenmethod-returning-conversation-surfacing (2026-05-03)

- **System prompt does NOT inject the bound IRIS session_id; LLM hallucinates session_ids when the operator's text doesn't mention them.** **[CLOSED 2026-05-03 by Story 3.5 — Rule 9 binding deferral honored]**

  - **Closure mechanism:** Story 3.5 AC-6 implemented Path 1 (prompt augmentation in `Agent.AgentLoop.RunTurn`) verbatim. After `tSysPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt(pAgentName)` (line 184), inserted `If pSessionKey '= "" { Set tSysPrompt = tSysPrompt _ " The currently-bound IRIS Production Ens session ID for this conversation is " _ pSessionKey _ ". Use this id verbatim when calling inspection tools unless the operator explicitly asks about a different session." }`. Two new tests in `SessionAgent.Test.AgentLoopGuardsTest`: `TestRunTurnInjectsBoundSessionIdIntoSystemPrompt` (capture-mock asserts the binding sentence with bound key) and `TestRunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty` (structural test reading the compiled `RunTurn` body via `%Dictionary.CompiledMethod` — empty-pSessionKey path is unreachable via `RunTurn` because `Chat.History.LoadOrCreate` rejects empty session keys, so the omission case is verified structurally).
  - **Empirical Rule 11 verification (Story 3.5 Task 6):** Re-ran the F5 demanding prompt (*"Walk me through what happened in this session, then check if any messages had errors..."*) against bound session "1" via `SessionAgent.EnsPortal.VisualTrace.SendChatMessage("session-inspection", "1", ...)`. Tools dispatched with `args: {"session_id":"1"}` (the bound id) — NOT a hallucinated UUID. Compare to F5 capture which showed `args: {"session_id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890"}`. Fix verified empirically.
  - **Source:** Story 3.3 code review (cr-3-3 finding F5; lead's prompt critical item #6 — re-run live OpenAI smoke with a more demanding prompt).
  - **Severity:** MEDIUM (predicted bug — affects every operator question that doesn't explicitly mention the session id; the agent confidently calls inspection tools with wrong ids and returns hallucinated grounding).
  - **Evidence (verbatim transcript from cr-3-3 demanding-prompt smoke):**
    - Bound `pSessionKey = "1"`; bound `tCtx.IrisSessionId = "1"` (constructed in `Agent.AgentLoop.RunTurn` line 119).
    - Operator prompt: *"Walk me through what happened in this session, then check if any messages had errors, and if there were errors show me details. Be thorough."* (no explicit ID mention)
    - Tools dispatched (envelope `toolCallsRendered`):
      - `session_timeline` with `args: {"session_id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890"}`
      - `message_headers` with `args: {"session_id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","min_severity":"error"}`
    - Final assistant text references the hallucinated UUID, not session "1".
  - **Root cause:** `SessionAgent.Config.AgentDefaults.GetSystemPrompt("session-inspection")` (Story 2.4) returns a static system prompt that lists tool names + the read-only invariant but does NOT mention the bound session id. The `Agent.AgentLoop.RunTurn` (Story 2.12) constructs a `CallerContext` with `IrisSessionId = pSessionKey` but never injects it into the prompt the LLM sees. The LLM is forced to invent or guess the id.
  - **Why this is NOT a Story 3.3 bug:** Story 3.3's job is plumbing the ZenMethod boundary + bootstrap-context for prior conversation. The bound session id IS correctly passed to `RunTurn` (verified in `SendChatMessage` line 424). The grounding gap is owned by `AgentDefaults.GetSystemPrompt` (Story 2.4) and `AgentLoop.RunTurn` (Story 2.12), both pre-existing.
  - **Recommended fix paths:**
    1. **Prompt augmentation in `AgentLoop.RunTurn`** — after `tSysPrompt = ...` (line 184), append `tSysPrompt = tSysPrompt _ " The currently-bound IRIS Production Ens session ID for this conversation is " _ pSessionKey _ ". Use this id verbatim when calling inspection tools unless the operator explicitly asks about a different session."` Smallest change; preserves agent-level prompt customization.
    2. **First-turn user-message context injection** — prepend a system-style first user message that introduces the binding. More flexible (different formats per agent) but couples to the chat history shape.
    3. **Tool-call default-arg injection** — modify the inspection tools to default `session_id` to `CallerContext.IrisSessionId` when the LLM omits it. Belt-and-suspenders but doesn't help when the LLM emits a wrong id.
  - **Recommendation:** Path 1 is smallest and matches the read-only-invariant-injection pattern already in the prompt. The fix is a single-line addition in `Agent.AgentLoop.RunTurn`.
  - **Owner reassigned to Story 3.5** (empty-states + provider-error envelopes — natural home for prompt-engineering pass that touches the inspection-agent system prompt). Per Rule 9, Story 3.5's spec author MUST grep `deferred-work.md` for "Story 3.5" mentions and incorporate this carry-forward into the ACs.
  - **Why this is a Rule 8 valid defer (Test 1: genuine future-epic scope):** The fix touches Story 2.4's `AgentDefaults` or Story 2.12's `AgentLoop.RunTurn` (or both — depending on whether the binding is added to the static prompt or injected per-turn). Both are out-of-scope for Story 3.3's "wire the ZenMethod boundary + bootstrap context" charter. Story 3.5 is the next logical home; if Story 3.5 ships before this is fixed, the lead must re-defer with a new named successor (Rule 9 binding chain).
  - **Blocking?** Not blocking Story 3.3 ship — the wire-format integration (AC-7) is verified end-to-end and tools DO dispatch + return real data. The bug surfaces only when the operator omits the session id from the prompt; in MVP usage where the operator IS the session-context originator (they navigated to Visual Trace on session N), they will frequently omit the id assuming the agent knows it. Worth fixing in Story 3.5.

---

## Deferred from: Story 3.6 (cross-browser scope reduction) (2026-05-03)

- **Firefox / Safari / Edge cross-browser smoke deferred. Per project-lead direction 2026-05-03 — MVP scope reduced to Chrome via `chrome-devtools-mcp`.**

  - **Source:** Story 3.6 spec (Status section + AC-3); project-lead direction recorded 2026-05-03 alongside the spec re-shaping.
  - **Severity:** LOW (MVP-acceptable; Mgmt Portal Zen inheritance + standards-compliant DOM + ARIA — verified via Chrome smoke at every Story 3.6+ commit — provide best-effort cross-browser confidence in the absence of dedicated sweeps).
  - **The deferral:** The original Epic 3 spec (`epics.md` §"Story 3.6", lines 1282–1319) called for a full cross-browser sweep across "the latest two versions of Chrome, Firefox, Safari, and Edge" plus screen-reader and WCAG contrast checks. Story 3.6 ships the **Chrome-only** smoke runbook ([`docs/testing/chrome-devtools-smoke.md`](../../docs/testing/chrome-devtools-smoke.md)) executed via the [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp) server. Firefox / Safari / Edge sweeps are out of MVP scope.
  - **Deferral test (per [discipline rule 8](../../.claude/rules/epic-cycle-discipline.md)):** **Test 1 — genuine future-epic scope.** Full cross-browser parity needs CI infrastructure (Playwright or Selenium grid), per-OS browser pools (macOS for Safari, Windows for Edge, Linux for Firefox CI runners), and manual operator time at every release cut. None of those are in scope for the MVP demo-able milestone (Epics 1–4); all of them belong to a discrete future-epic concern.
  - **What still ships in MVP:** The chat panel is built on standards-compliant DOM (`<section>` / `<form>` / `<textarea>` / `<details>` / `<a>`), standards ARIA attributes (`role="region"`, `aria-label`, `aria-live="polite"`, `aria-disabled`), and inherits the Mgmt Portal Zen wrapper's tab chrome / focus management / color contrast. The Story 3.6 Chrome runbook's Lighthouse step (`mcp__chrome-devtools-mcp__lighthouse_audit` with category `accessibility`) asserts a ≥ 0.9 score against the parent shell — the same standards-compliant primitives that score in Chrome score equivalently in Firefox / Safari / Edge in the absence of browser-specific bugs.
  - **Owner:** Post-MVP cross-browser hardening epic (epic number TBD — likely a new Epic between current Epic 10 and the v1.x growth tier, OR a tag-along scope addition to a future UI-focused epic). The owning epic's spec author MUST:
    - Translate the 10-step Chrome runbook in [`docs/testing/chrome-devtools-smoke.md`](../../docs/testing/chrome-devtools-smoke.md) into a Playwright (or Selenium) cross-browser equivalent.
    - Add a per-OS browser-matrix CI job (parallel to `.github/workflows/ci.yml`) that runs the matrix.
    - Capture screen-reader transcripts (NVDA on Firefox/Windows, VoiceOver on Safari/macOS) for the agent-turn flow.
    - Decide whether to keep the Chrome `chrome-devtools-mcp` runbook as the dev-host smoke surface OR retire it in favor of the unified cross-browser runner.
  - **Blocking?** No. The Chrome smoke is the MVP integration-test surface; the deferred cross-browser sweep does not gate any current epic. If a Firefox / Safari / Edge regression is reported by an early adopter before the post-MVP epic ships, the lead handles it as a one-off fix-now per Rule 8 rather than waiting for the dedicated epic.
  - **Triage note:** When the post-MVP cross-browser epic is created, this entry is its binding-deferral handoff per [discipline rule 9](../../.claude/rules/epic-cycle-discipline.md). The spec author for that epic MUST grep `deferred-work.md` for "post-MVP cross-browser" and incorporate the work into the epic's ACs.

---

## **[CLOSED 2026-05-03 by Story 3.6 — module.xml fix-now via class-served-asset pivot]** Deferred from: Story 3.6 lead-driven smoke (2026-05-03) — module.xml `${cspdir}` template not expanded by ZPM

**CLOSURE:** Replaced the dedicated static-asset `<CSPApplication>` + `<FileCopy>` machinery with a `%CSP.Page` subclass `SessionAgent.UI.ChatPanelAsset` that streams `static/chat-panel.js` from the IPM module's `Root` directory at runtime. Class is shipped via the existing `SessionAgent.PKG` resource — no separate CSPApplication, no FileCopy, no `${cspdir}` template variable, no install-time deployment step. URL changed from `/csp/static/iris-session-agent/chat-panel.js` to `/csp/<ns>/SessionAgent.UI.ChatPanelAsset.cls`. Per-namespace deployment is automatic for any namespace mapped to `SessionAgent.PKG`. Empirically verified end-to-end via the AC-5 lead-driven smoke (the same one that originally surfaced the bug): chat panel JS now loads, init fires, prior 9-turn transcript renders, ZenMethod hyperevent succeeds, real OpenAI gpt-4.1-mini response appears in the transcript.

**ORIGINAL ENTRY (kept for audit trail):**

- **`module.xml` `<FileCopy Target="${cspdir}static/iris-session-agent/"/>` and `<CSPApplication Path="${cspdir}static/iris-session-agent">` produce literal-string Path resolution, breaking static-asset serving on a fresh `zpm install iris-session-agent`.**

  - **Source:** Story 3.6 lead-driven AC-5 smoke execution 2026-05-03. Discovered when chat-panel.js returned 404 from `http://localhost:52773/csp/static/iris-session-agent/chat-panel.js` after a clean dev install.
  - **Severity:** MEDIUM (predicted operator-visible bug — every `zpm install iris-session-agent` on a fresh IRIS install produces a non-functional chat panel because chat-panel.js is unreachable; the chat tab renders the HTML shell but the JS init never fires, so the input field is wired to nothing).
  - **Evidence (verbatim):**
    - Resolved CSP application Path on this dev install: `C:\git\iris-session-agent\.${CSPDIR}STATIC\IRIS-SESSION-AGENT\` — literal `${CSPDIR}` substring, not expanded.
    - Workaround applied during smoke: manually set `Path = "C:\InterSystems\IRISHealth\CSP\static\iris-session-agent\"` via `Security.Applications.%OpenId(...).Path = ...; %Save()`. After this and a manual file copy `C:/git/iris-session-agent/static/chat-panel.js → C:/InterSystems/IRISHealth/CSP/static/iris-session-agent/chat-panel.js`, IRIS-side `$System.CSP.GetFileName(...)` resolves correctly — but the Apache Web Gateway has its own in-process config cache that does NOT pick up the new Path without a gateway-side reload (see next entry).
  - **Root cause:** ZPM template variable `${cspdir}` is not the correct IPM/ZPM variable syntax for the CSP install directory. Common alternatives that may work: `{cspdir}` (no `$`), `${csp.dir}`, an `<InvokeScript>` that resolves `$System.CSP.GetFileName("/")` at install time, or an `<Invoke Method="..."/>` hook that runs after FileCopy to fix the Path.
  - **Recommended fix paths:**
    1. **Verify correct ZPM variable syntax** via the IPM source (https://github.com/intersystems/ipm) and update `module.xml` accordingly. Test by reinstalling on a clean namespace.
    2. **Add an `<Invoke>` hook to `Installer.Install`** that runs after FileCopy + CSPApplication creation, opens the application, and rewrites the Path using `$System.CSP.GetFileName("/")` resolution.
    3. **Stop using the `${cspdir}` template entirely** — declare the FileCopy + CSPApplication with explicit relative paths under the module's source root (ZPM supports this) and let ZPM compute the install location.
  - **Owner reassigned to Story 3.7** (PRD MVP exit-criteria validation — pilot operator walkthrough). The pilot operator's clean `zpm install` is the empirical-test gate that this fix unblocks. Per Rule 9, Story 3.7's spec author MUST grep `deferred-work.md` for "Story 3.7" mentions and incorporate this carry-forward.
  - **Blocking?** **YES for the pilot walkthrough (Story 3.7).** The Story 3.6 commit ships the runbook + README + this deferral entry; the chat panel works on the current dev install via the manual workaround. But Story 3.7's "pilot operator on a clean install" is unreachable until this fix lands — therefore Story 3.7 cannot be empirically validated until module.xml is fixed.

---

## **[CLOSED 2026-05-03 by Story 3.6 — class-served-asset pivot eliminates the CSP-application-Path concern entirely]** Deferred from: Story 3.6 lead-driven smoke (2026-05-03) — Web Gateway in-process config cache requires reload after CSP application Path change

**CLOSURE:** The asset-class pivot (see entry above) routes the JS through the namespace's auto-CSP-application (`/csp/<ns>/`), which has no operator-mutable Path. The Web Gateway's in-process cache concern was specific to the dedicated `/csp/static/iris-session-agent` application's Path field — eliminated by removing that application altogether. Class-based dispatch goes directly to IRIS's `%CSP.Page.OnPage` handler with no Path lookup at all.

**ORIGINAL ENTRY (kept for audit trail):**

- **The IRIS Web Gateway (Apache module) caches CSP application Path mappings in-process and does NOT pick up changes from `Security.Applications.%Save()` calls without a gateway-side reload.**

  - **Source:** Story 3.6 lead-driven AC-5 smoke execution 2026-05-03. After the workaround for the `${cspdir}` bug (above) was applied, IRIS-side `$System.CSP.GetFileName(...)` returned the correct file path — but the Apache Web Gateway continued serving 404 for the chat-panel.js URL. Even cache-busting query strings did not help.
  - **Severity:** LOW for MVP (operator-visible only on first install AND after any Path-change to the static-asset CSP application; once the gateway reloads — typically on next IRIS service restart or via the Web Gateway management portal "Apply Settings" action — the path resolves correctly).
  - **The deferral:** Document this in operator-quickstart README. After `zpm install iris-session-agent`, the operator may need to perform one of: (a) restart IRIS, (b) restart the Web Gateway via the Web Gateway management UI (`http://<host>:<port>/csp/bin/Systems/Module.cxw` → "Apply Settings"), (c) add an `<Invoke>` hook to `Installer.Install` that programmatically nudges the gateway via a recognized API. Investigate (c) before falling back to (a) or (b) in operator docs.
  - **Owner reassigned to Story 3.7** (PRD MVP exit-criteria validation — pilot operator walkthrough). Pair with the `${cspdir}` fix above; both block the same pilot-operator-on-clean-install scenario.
  - **Blocking?** Same as above — blocks Story 3.7's clean-install validation. Not blocking Story 3.6's commit (the runbook + README + smoke evidence are the deliverables; the integration bug is documented for the next story to close).
