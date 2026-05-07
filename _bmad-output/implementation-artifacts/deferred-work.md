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
  - **Status:** **CLOSED 2026-05-06 by Story 5.0 AC-6** — `TestCanonicalUserTwoToolResultBlocksFanOutToTwoOpenAiToolMessages` added to `src/SessionAgent/Test/MessageAdapterTest.cls`. Test feeds a canonical user-role message with TWO `tool_result` blocks (one string content, one array-of-text-blocks content) and asserts the OpenAI output is TWO `{role:"tool", tool_call_id, content:...}` messages with the array form stringified via `%ToJSON`. Verified pass: 11/11 MessageAdapterTest pass post-Story-5.0 (was 10/10).
  - **Severity:** LOW (silent-regression risk only; the path compiles and is exercised whenever a real OpenAI provider receives a `tool` role canonical message at runtime — but no unit test locks the behavior).
  - **Location:** `src/SessionAgent/LLM/Util/MessageAdapter.cls:195-224` (the `If tRole = "tool"` branch that emits one OpenAI message per `tool_result` block) plus `src/SessionAgent/Test/MessageAdapterTest.cls` (no covering `Test*` method).
  - **The gap:** `TestCanonicalToGeminiRoleMapping` exercises a single `tool_result` block but tests Gemini's `functionResponse` part, not OpenAI's per-block fan-out. `TestRoundTripOpenAi` exercises assistant-side `tool_use`, not the tool-side `tool_result`. The OpenAI tool-message emission has its own non-trivial logic (per-block iteration, `tool_use_id` → `tool_call_id` rename, content stringification of array form via `%ToJSON`) that is currently uncovered.
  - **What to add:** one new `Test*` method that feeds a canonical `tool` role message with TWO `tool_result` blocks (one with string content, one with array-of-text-blocks content) and asserts the OpenAI output is TWO `{role:"tool", tool_call_id, content:...}` messages with the expected stringified content shapes.
  - **Why deferred (not fixed in review):** AC-4 enumerates seven specific `Test*` methods for `MessageAdapterTest`; the fan-out test is not among them. Adding it now would expand AC-4 scope mid-review. Natural carrier: Story 2.9 (`OpenAIProvider`) which will be the first real consumer of this path — its dev cycle should add the missing coverage as part of integration testing the OpenAI wire shape end-to-end.
  - **Owner:** Story 2.9 dev (when implementing `OpenAIProvider`'s `CallMessages`). **Reassignment dropped silently in Story 2.9; Epic 4 retro continued-deferrals flagged it; Story 5.0 AC-6 closed it.**
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

---

## Deferred from: Story 3.7 lead-driven walkthrough (2026-05-03) — system-prompt-only cross-session disclosure unreliable

**STATUS: CLOSED 2026-05-03 by Story 3.8 (Programmatic Cross-Session Disclosure).** The recommended fix shipped verbatim — `Agent.AgentLoop.RunTurn` now (a) inspects every dispatched tool's `args.session_id` (Story 3.8 AC-1, lines ~325–346 of `src/SessionAgent/Agent/AgentLoop.cls`), (b) collects distinct cross-session ids into a per-turn dedup list, and (c) prepends a deterministic operator-facing notice (`"Note: this turn dispatched tools against session(s) X outside this chat's bound session N. Audit ledger captured all dispatches."`) to the final assistant text after the iteration loop completes (Story 3.8 AC-2, lines ~408–428). Defense-in-depth with the Story 3.7 system-prompt language (which is unchanged — both fire; the operator sees both). Locked by `Test/AgentLoopGuardsTest.TestRunTurnAppendsCrossSessionNotice` + `TestRunTurnSkipsNoticeWhenNoCrossSession`. Total test count 156 → 158 (+2). Closure mechanism: server-side prepend in `RunTurn` (Path 1 from this entry). Optional Path 2 (chat-panel.js UI modifier on tool-cards) remains available for a future story if real-world feedback says the inline notice isn't visible enough; the server-side notice is sufficient for MVP per Story 3.8 Dev Notes §"Why server-side notice (not client-side detection)".

**ORIGINAL ENTRY (kept for audit trail):**

- **The Story 3.5 AC-6 system-prompt language requiring the LLM to disclose cross-session reaches in its response is unreliable when conversation context has many same-session prior turns. Programmatic enforcement is needed.**

  - **Source:** Story 3.7 lead-driven walkthrough Turn 5 (2026-05-03). The lead asked *"Show me what's in session 2"* (a different session than the bound session 1). The agent dispatched `session_summary` with `session_id: "2"` (correct soft-scope behavior — cross-session dispatch allowed) BUT the agent's response did NOT include the required *"Note: you asked about session 2 which is outside this chat's bound session 1"* disclosure that the Story 3.7 fix-now system-prompt language requires. The LLM ignored the "MUST" instruction — likely swayed by 9 prior "session 1, session 1, session 1" turns of context.
  - **Severity:** MEDIUM (operator-visible — operators may assume answers are scoped to the bound session when they're not; audit-trail attribution is correct so the divergence is recoverable post-hoc, but in-the-moment operator confusion is a real UX gap).
  - **Recommended fix:** Programmatic enforcement in `Agent.AgentLoop.RunTurn`. After each tool dispatch, inspect the args for a `session_id` value. If present AND ≠ `pSessionKey`, set a `tCrossSessionDetected = 1` flag. After the LLM's final response, if the flag is set, prepend an automatic notice to the final assistant text: *"Note: this turn dispatched tools against session(s) X (and Y, etc.) outside this chat's bound session N. Audit ledger captured all dispatches."* The notice is server-side-rendered so the LLM cannot omit it.
  - **Optional UI extension:** Story 3.2's `chat-panel.js` `renderToolCard` could detect args.session_id ≠ bootstrap-context.sessionKey at render time and add a subtle inline notice to the tool-call card (e.g., a `.sa-tool-card-cross-session` modifier with a different border or icon). Belt-and-suspenders alongside the AgentLoop server-side notice.
  - **Owner reassigned to Story 3.8** (`Programmatic Cross-Session Disclosure`) — added to Epic 3 via Sprint Change Proposal 2026-05-03. Per Rule 9, Story 3.8's spec author MUST grep `deferred-work.md` for "Story 3.7 lead-driven walkthrough" and incorporate this entry into the ACs.
  - **Blocking?** Not blocking. Story 3.5 AC-6's bound-session injection still works (no UUID hallucinations — verified by the demanding-prompt smoke). Story 3.7's commit ships the system-prompt-only enforcement + this deferral; operators on the dev install can still safely use the chat panel (audit ledger captures everything; cross-session reaches are visible after the fact).
  - **Audit-trail proof of detectability today:** the cross-session reach IS captured in `SessionAgent_Audit.ToolCall.Args` as JSON containing `"session_id":"2"` even when the in-turn LLM disclosure fails. SQL probe: `SELECT %EXACT(Args), ChatHistoryId FROM SessionAgent_Audit.ToolCall WHERE %EXACT(Args) [ '"session_id":"2"' AND ChatHistoryId IN (SELECT ID FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) = '1')` returns the rows.

---

## **[CLOSED 2026-05-03 by Story 4.1 review — three chrome-devtools-mcp captures filed + reviewer-inspected]** Deferred from: Story 4.0 code review (2026-05-03) — Rule 12 visual-check substitution + Node-harness brittleness

**CLOSURE:** Story 4.1's lead-driven empirical battery completed the binding visual-gate after the chrome-devtools-mcp browser lock was cleared (lead closed the conflicting browser session). Three captures filed: `4-1-rule-12-visual-pass-1.png` (event_log success render with severity counts + no mojibake), `4-1-rule-12-visual-pass-2.png` (AC-5 collapsed-card error preview via `min_severity:'critical'` enum-rejection — substituted from spec's `DOES_NOT_EXIST_!@#` example because that produces a clean empty result rather than an isError envelope; same render path), `4-1-rule-12-visual-pass-3.png` (AC-6 inline notice next to `[message:abc]` malformed citation chip). Story 4.1 reviewer opened all three PNGs and visually verified AC-5 collapsed disclosure triangle, error badge, validation-message preview, and AC-6 verbatim notice wording. The Node DOM-mock harness (`rule-12-empirical-pass-4-0.js`) and the byte-level UTF-8 scan from Story 4.0 remain in place as residual evidence; the chrome-devtools-mcp captures supersede the substitution requirement.

**ORIGINAL ENTRY (kept for audit trail):**

- **The Story 4.0 Rule 12 empirical pass was satisfied via a Node DOM-mock harness rather than a chrome-devtools-mcp visual screenshot.**

  - **Source:** Story 4.0 dev cycle 2026-05-03. The chrome-devtools-mcp browser was locked from a prior process (`The browser is already running for C:\Users\Josh\.cache\chrome-devtools-mcp\chrome-profile`); the dev substituted `_bmad-output/implementation-artifacts/rule-12-empirical-pass-4-0.js` (a 35-assertion Node harness loading `static/chat-panel.js` source into a minimal DOM mock and exercising AC-5 + AC-6 helper paths). The reviewer additionally performed a byte-level UTF-8 mojibake scan of the served file (`0xC3 0x82 0xC2 0xB7` shape absent; 63 valid em-dash sequences `0xE2 0x80 0x94`; middle-dot at expected positions = `0xC2 0xB7`).
  - **Severity:** LOW. Rule 12's underlying concern (mojibake / encoding drift will ship silently) is directly addressed by the byte-scan, which is rigorous evidence. The Node harness is closer to a DOM dump than a human visual read, but the helper-path assertions DO prove the rendered surface behaves as specced. The remaining gap is tactile — what does the validator-rejection summary line ACTUALLY look like in the chat panel for an operator looking at it? That's a tactile-UX question the byte-scan cannot answer.
  - **The deferral:** before the Epic 4 retrospective, the lead must perform one chrome-devtools-mcp visual pass against a real chat panel exercising (a) a tool-error envelope so AC-5's collapsed-summary preview is visible, and (b) a malformed citation chip so AC-6's notice is visible. Capture screenshots into the Epic 4 retro file. This carries forward into Story 4.1's Rule 12 application matrix as the binding visual gate (per Rule 9 the named-successor is Story 4.1, where the lead's empirical battery already opens the chat panel against sample-production data).
  - **Owner reassigned to Story 4.1** (Epic 4 first-rendering — EventLog/RuleLog) — Story 4.1's spec author must grep `deferred-work.md` for "Story 4.0 code review" and incorporate this visual-check requirement into Story 4.1's empirical battery section. Per Rule 9 this reassignment is BINDING.
  - **Blocking?** Not blocking Story 4.0's commit. The byte-scan is rigorous evidence the originating mojibake bug class is absent; the Node harness exercises the new helper code paths. The visual pass is residual confidence that the rendered text is tactile-readable to a human eye.
  - **Rule 8 self-check:** is this a fix-now or a defer? Defer is justified under Rule 8 test 2 (external-dependency blocker — the chrome-devtools-mcp browser is locked; reviewer cannot start a second profile without disrupting the user's other browser session). The visual evidence is residual confidence, not a predicted bug.

- **Node harness `rule-12-empirical-pass-4-0.js` regex-slices `chat-panel.js` source to find helper bodies — silent failure mode if helpers are renamed.**

  - **Source:** Story 4.0 code review of `_bmad-output/implementation-artifacts/rule-12-empirical-pass-4-0.js`. The harness uses `sliceFunction(src, 'function extractToolErrorPreview')` etc. to extract helper bodies. If a future story renames the helper, the harness throws `'marker not found'`; the regex slicing is stable enough for one-shot evidence (the file's purpose) but is not standing test infrastructure.
  - **Severity:** LOW. The harness is committed as evidence (the `_bmad-output/implementation-artifacts/` location signals one-off proof, not standing CI), and the actual standing static-grep tests are in `SessionAgent.Test.ChatPanelJsTest` (`TestExtractToolErrorPreviewPresent` + `TestCitationDefensiveGuardsPresent` — added by code review 2026-05-03). The harness fragility is acceptable because its purpose is single-snapshot Rule-12 evidence, not regression prevention.
  - **The deferral:** none — the harness is intentionally one-shot. If a future story re-uses the harness pattern (Rule 12 + browser unavailable again), the next dev should either (a) re-run the harness and accept the rename-fragility, or (b) port the helper-extraction to a more durable mechanism (e.g., extract via a stable export marker comment like `/* @export */`). NOT carrying this forward as a binding successor entry — this is documented for future harness reuse only.
  - **Blocking?** Not blocking.

---

## Deferred from: Story 4.1 code review (2026-05-03) — AC-5 visual-gate spec example mismatch

- **Story 4.1 spec AC-8 sub-item (2) cited `event_log` with bogus `session_id: "DOES_NOT_EXIST_!@#"` as the trigger for the AC-5 collapsed-card error preview — but EventLog correctly returns a clean empty result (`event_count=0`) for non-matching session_ids, NOT an isError envelope. Future Story X.0-style cleanup specs should use a different example.**

  - **Source:** Story 4.1 review F-5 (2026-05-03). The dev caught this empirically during the visual-gate execution and substituted `min_severity:'critical'` enum-rejection (which DOES produce isError) to exercise the same render path. The substitution is honest evidence (the chat-panel render path verified is identical for any isError envelope; AC-5's contract is the rendered output shape, not the specific trigger). But the spec's example, if quoted into a future cleanup story without re-thinking, would block dev with the same "this doesn't trip isError" finding.
  - **Severity:** LOW (no operator-observable impact — the code is correct; the spec example is the bug. No predicted-bug shape against shipped code.)
  - **Why this is a Rule 8 valid defer (Test 3: pure cosmetic with no predicted-bug shape):** The spec author's intent was clearly *"any deliberately-failing call that exercises the AC-5 render path"* — the specific `DOES_NOT_EXIST_!@#` example was a guess at what would fail. EventLog's design (tolerates non-matching session_ids; session-existence is `SessionSummary`'s domain) is correct. The fix is a one-line spec-hygiene update, not a code change.
  - **The deferral:** any future Story X.0-style cleanup spec that touches the inspection-tool visual-gate language should substitute a deliberately-failing call that DOES trip isError, e.g.: *"`event_log` with `min_severity: 'critical'` (an enum-rejection — EventLog's input validation produces the canonical structured error envelope `{isError:1, content:[{type:"text", text:"min_severity must be one of: info, warning, error, assert (got: critical)"}]}`)"*. This is precise, deterministic, and matches the same render path AC-5 was meant to verify.
  - **Owner:** No bound successor. Pick up at the next epic-end retrospective or any future story that touches `_bmad-output/planning-artifacts/epics.md` Story 4.1 / Story 4.0 visual-gate language.
  - **Blocking?** Not blocking. Story 4.1 ships clean; the visual gate was satisfied via the substitution; the F-1 fix locks the more important contract (`severity_counts` semantics).

---

## Deferred from: Story 4.2 code review (2026-05-04) — GetMessageBody dispatch ladder

- **HL7 summary mode does not extract per-segment `:0` field walk; `body_repr` is just the raw ER7 truncated to 256 chars.**

  - **Source:** Story 4.2 review (auditor finding A2, 2026-05-04). Spec AC-3 Step 3 wording: *"render via `body.OutputToString()` for raw; `body.GetMessageType()` + `body.GetSegmentCount()` + per-segment `:0` field for summary."* The implementation uses `Name` (message type) + `SegCount` (segment count) calculated properties — both correct per Task 0 probe — but does NOT extract per-segment `:0` (the segment-name field) for the summary output. Summary mode for HL7 falls through the same code path as raw, producing the full ER7 string and relying on the outer Invoke truncation to 256 chars.
  - **Severity:** LOW. Sample data has zero HL7 rows in production; only the test fixture exercises Step 3. Operator-readable summary is still produced via `message_type` + `segment_count` extras + truncated `body_repr`. The per-segment `:0` field walk is a nice-to-have absent from impl, not a correctness bug.
  - **Why this is a Rule 8 valid defer (Test 3: pure cosmetic with no predicted-bug shape):** The structuredContent already carries `message_type` and `segment_count` as first-class extras; per-segment field enumeration would duplicate information for operators inspecting the `body_repr`. If a future operator needs structured HL7 segment introspection, a dedicated `get_hl7_segment` tool (or an `extract` mode for `get_message_body`) is a cleaner addition than retrofitting summary-mode field walking into the dispatch helper.
  - **Owner:** No bound successor. Could be picked up by Epic 8 Story 8.6 `InspectBodyCandidates` if it wants per-segment introspection, OR by a future Epic 4.x dedicated HL7 helper.
  - **Blocking?** Not blocking. Story 4.2 ships with summary-mode parity for HL7 == raw-mode + truncation, which matches the Step 6 stream-summary behavior pattern.

- **Step 9 fallback path (`render_strategy="unknown"`, `dispatch_failed:1`) lacks empirical test coverage.**

  - **Source:** Story 4.2 review (auditor + edge-case finding A6 + E1, 2026-05-04). `TestStep9UnknownDispatchFailed` uses a header pointing at a non-existent class, which fails Step 2 body open with `body_not_found` — NOT Step 9's `unknown`. The test's assertion accepts both outcomes (`tStrategy = "body_not_found" || "unknown"`), so the live path it exercises is Step 2's failure, not Step 9's fallback. The originally-seeded `GmbFixtureRegistered.cls` (a pure %RegisteredObject) was deleted in code review since it was unreferenced dead code.
  - **Severity:** LOW (Step 9 is by design a defensive fallback that's structurally unreachable for any object successfully passing Step 2 `%OpenId` — every Ens-persistable body extends `%Persistent` or `%RegisteredObject` and therefore matches Step 8's predicate, leaving Step 9 as defense-in-depth only).
  - **Why this is a Rule 8 valid defer (Test 1: external-dependency / structural unreachability):** Constructing a body that opens via `%OpenId` but extends NEITHER `%Persistent` NOR `%RegisteredObject` requires bypassing IRIS's OREF-construction layer, which is not possible from ObjectScript. The Step 9 path is reachable ONLY via a future architectural change (e.g., `%Library.Base` directly opening as a body) that is out of scope for any current epic.
  - **The deferral:** if Epic 8 Story 8.6 `InspectBodyCandidates` ends up reusing the dispatch ladder (deferred per architecture.md G2), it should add a synthetic test that monkey-patches `ClassExtends` to return false for all 5 ladder predicates — this is the only practical way to drive Step 9 to fire. Until then, the path is exercised by the type-system invariant (every OREF extends one of the two), not by a runtime test.
  - **Owner:** No bound successor. Could be picked up by Epic 8 Story 8.6 if/when the dispatch ladder is extracted to `SessionAgent.Body.DispatchLadder`.
  - **Blocking?** Not blocking. Story 4.2's 11 other test methods (1-8, empty-body, missing-id, header-not-found, registry-listing) cover every reachable dispatch outcome.



---

## Deferred from: code review of 4-3-getmessagedetail (2026-05-03)

- **`get_message_detail` description sharpening to dampen redundant `rule_log` follow-up.**

  - **Source:** Story 4.3 code review (lead-flagged item #5).
  - **Severity:** LOW (Rule 8 valid defer Test 1 — natural carrier is Story 4.7 `ExplainError` + comprehensive read-only suite verification, where prompt-engineering / tool-description tightening across the full inspection suite is in scope).
  - **The observation:** Live OpenAI smoke turn (Rule 6 sharpened, session 850 / message 854) showed agent dispatching `get_message_detail` (correct primary) PLUS `rule_log` (1 follow-up call to confirm session-wide rules) — 2 tool calls instead of the spec's implicit 1-call expectation. The redundancy is technical: `get_message_detail.rule_decisions` already covers the per-message scope (which is what the user asked about); the agent's decision to additionally check `rule_log` for session-wide visibility is reasonable but produces an extra tool round-trip.
  - **Why this is not a Story 4.3 ship blocker:** the `rule_log` call is genuinely broader scope (session-wide vs per-message), and the LLM's decision to check it is defensible. The first call (`get_message_detail`) was correctly grounded and complete. Wall-clock impact: 5.1s end-to-end including both tool calls — not problematic.
  - **Two clean resolutions for Story 4.7:**
    1. **Sharpen `get_message_detail`'s tool description** to make explicit that `rule_decisions` already covers per-message rule-firing — e.g., "Return full message header + body summary + linked rule-log decisions for a single message — rule_decisions covers all rules that fired for THIS message; use rule_log only for session-wide rule history beyond the current message."
    2. **Leave as-is** if the cross-tool prompt-engineering pass in Story 4.7 finds the session-wide check is operator-valuable in practice.
  - **Recommendation:** Resolution #1 (description sharpening) is the lower-risk fix; the description currently makes both tools look "redundantly" applicable for "tell me about message N + rules that fired".
  - **Owner:** Dev agent for Story 4.7 (comprehensive read-only suite verification).
  - **Blocking?** Not blocking Stories 4.4–4.6. Becomes scope-relevant when Story 4.7 enters dev (cross-tool prompt-engineering pass).

- **`SessionAgent.Sample.Bootstrap` `Write` statements block `iris_execute_classmethod` smoke calls.**

  - **Source:** Story 4.3 code review (lead-flagged item #4).
  - **Severity:** LOW (Rule 8 valid defer Test 3 — pure cosmetic with no predicted-bug shape: `Write` statements are intentional operator-facing console output for `iris session` interactive shell use).
  - **The observation:** `src/SessionAgent/Sample/Bootstrap.cls` `InstallProduction` (lines 49-54), `UninstallProduction` (lines 93, 97), and `StartProductionIfStopped` (no Write) emit `Write !, "[SessionAgent.Sample.Bootstrap] ..."` lines as operator-readable console feedback. When invoked via `iris_execute_classmethod` MCP, the Write output is intermixed with the JSON return envelope, breaking JSON-shape parsers (the dev's empirical observation during Story 4.3's Rule 6 battery).
  - **Story 4.3 dev workaround:** re-bootstrapped the sample production via `iris_production_control start` instead of `Bootstrap.InstallProduction` — operator-friendly alternate path that skips the Write-output friction.
  - **Why this is not a Story 4.3 regression:** the Write statements are a Story 3.9 carry-over (sample interop production scaffolding); they have NEVER been MCP-friendly. The friction was discovered during Story 4.3's Rule 6 empirical battery, not introduced by Story 4.3 code.
  - **Two clean resolutions:**
    1. **Wrap operator console output in a guard:** check `$IO` / device context and skip Write when called from a non-interactive shell (e.g., MCP / programmatic invocation). Return the same operator-readable text via the `%Status` payload instead.
    2. **Add a sibling `InstallProductionSilent` ClassMethod** that returns `%Status` only with no Write side-effects, and document it as the MCP-callable variant.
  - **Recommendation:** Resolution #1 — fewer methods to maintain, single source of truth for the install instructions text. Either resolution is fine.
  - **Owner:** No bound successor. Could be picked up opportunistically when a future story touches `Bootstrap.cls` (Story 4.x deferred clean-up, Story 6.x multi-namespace install support).
  - **Blocking?** Not blocking. The `iris_production_control start` operator workaround is canonical and documented (Story 4.3 Tasks/Subtasks Task 4).

---

## Deferred from: code review of story-4-4-bp-introspection-trio (2026-05-04)

- **Live-test only dispatched 2 of 3 new tools — `list_business_process_methods` was not invoked by the live OpenAI smoke turn.**

  - **Source:** Story 4.4 code review.
  - **Severity:** LOW (Rule 8 valid defer Test 3 — pure cosmetic with no predicted-bug shape: the tool unit tests prove dispatch + envelope shape work; the live turn just didn't exercise this particular tool because the agent answered the user's three-part question by combining `get_business_process_source` (which already returns method declarations) with `get_business_process_instance`. The agent made a reasonable cost/quality trade-off rather than dispatching all three.).
  - **Empirical SQL probe:** `SELECT %EXACT(ToolName), IsError, ChatHistoryId FROM SessionAgent_Audit.ToolCall WHERE ToolName IN ('get_business_process_source','get_business_process_instance','list_business_process_methods') ORDER BY ID DESC` returns only `get_business_process_instance` + `get_business_process_source` (ChatHistoryId=7) — `list_business_process_methods` not present.
  - **Story file overstatement:** Story 4.4 Task 6 (line 137) and Completion Notes (line 210) both claim *"All 3 new tools dispatched"*. Empirically only 2 dispatched. The visual-gate screenshot also shows only 2 tool cards rendered in the chat trace.
  - **Why this is not a regression / not a fix-now:** (a) `BusinessProcessIntrospectionTest:TestRegistryListToolsIncludesAllThreeBpTools` proves the registry surfaces all 3 tools, and `TestMethodsReturnsBpMethodList` proves `list_business_process_methods.Invoke` produces a valid envelope. The wire-format-correct proof exists. (b) The agent's tool-selection behavior is non-deterministic by design — Rule 6 sharpened just requires *that the tool path runs end-to-end*, not that all N tools dispatch on a single turn. (c) Trying to force the third dispatch via prompt engineering would be a make-work item with no operator value.
  - **Resolution:** No code change. Note for the Epic 4 retrospective: Rule 6 sharpened battery should distinguish "live test exercises each new tool *at least once across the battery*" from "single turn exercises every new tool" — the former is the operator-grounded standard, the latter is brittle prompt-engineering. Currently Rule 6 sharpened text is silent on the distinction.
  - **Owner:** Lead — note in Epic 4 retrospective; consider Rule 6 sharpening clarification.
  - **Blocking?** Not blocking. Story 4.4 ships with all three tools registered, unit-tested, and dispatch-ready.

- **Filter docstring claim "44 rows for BP.OrderRouter" was stale (live: 141 rows) — corrected at code review time.**

  - **Source:** Story 4.4 code review.
  - **Severity:** LOW (cosmetic only — was a stale Task-0 estimate; live count is 141, not 44; class-header docstring updated in same commit as the review).
  - **The discrepancy:** `ListBusinessProcessMethods.cls` line 46–50 (pre-edit) claimed *"The 44-row result for BP.OrderRouter after filtering is the operator-meaningful set."* Empirical probe at code-review time shows 141 rows post-filter. The 44 was a Task-0 hand-estimate that excluded inherited persistence/serializer/swizzle methods — those are legitimately operator-meaningful when introspecting a BP class.
  - **Resolution applied at code review:** docstring updated to the live 141-row figure with "empirically confirmed at code review time, 2026-05-04" citation, and a sentence explaining why the original 44-row estimate was low. No filter-logic change — the live behavior is correct; only the doc was stale.
  - **Owner:** Resolved (this commit).
  - **Blocking?** Not blocking.

- **AC-9 spec carries the wrong reflection-class name in the AC text — `%Dictionary.MethodDefinition` referenced in tool descriptions where `%Dictionary.CompiledMethod` is what the implementation actually uses.**

  - **Source:** Story 4.4 code review.
  - **Severity:** MEDIUM (resolved at code-review time as a fix-now: the tool's `Description` parameter — surfaced to the LLM via tool-list — claimed `%Dictionary.MethodDefinition` reflection, contradicting the actual `%Dictionary.CompiledMethod` implementation. An LLM reading the description could mis-route or skip the tool.).
  - **The discrepancy chain:** epics.md AC-9 wording (line 70 of story spec) prescribed `%Dictionary.MethodDefinition`. Task-0 probe found the prescribed projection (`%Dictionary.CompiledMethod_PropertyDefinition`) didn't exist; dev redesigned to `SELECT FROM %Dictionary.CompiledMethod`. The class-level Description parameter was not updated to match the new reality, so it still claimed `%Dictionary.MethodDefinition`.
  - **Resolution applied at code review:** rewrote the `Description` parameter on `ListBusinessProcessMethods.cls` and `GetBusinessProcessInstance.cls` to match the actual implementation. Both LLM-surfaced descriptions are now wire-truthful.
  - **Owner:** Resolved (this commit).
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-4.5-findrelatedsessions-ens-supersessionindex (2026-05-04)

- **Prepare-failure path returns bare success-shaped envelope without `isError:1`.**

  - **Source:** Story 4.5 code review (Blind Hunter B-3).
  - **Severity:** LOW (predicted-bug shape, but matches existing codebase pattern across Story 4.1+ tools; no genuine field-observable failure path on the dev install — `%Prepare` only fails on syntax errors in the literal SQL, which are caught by compile + per-class tests).
  - **The observation:** `FindRelatedSessions.Invoke()` initializes `pResult` to `{"content":[{"type":"text","text":""}], "structuredContent":{"related_sessions":[]}}` at the top of Try. The `Quit:$$$ISERR(tSCp)` / `Quit:$$$ISERR(tSCs)` / `Quit:$$$ISERR(tSCer)` / `Quit:$$$ISERR(tSCec)` patterns exit the Try on prepare failure but do NOT set `isError:1` — the caller would receive a success-shaped envelope with empty content text and an empty `related_sessions` array. Same shape exists in `EventLog.cls` line 156 + `RuleLog.cls` and was inherited by the dev as the codebase pattern.
  - **Predicted-bug shape:** if a future schema change breaks one of the `%Prepare` SQL strings (e.g., `Ens.SuperSessionIndex` schema migration removes the `MessageHeader` FK), operators see "no related sessions" instead of a meaningful error. The audit row would still emit with `IsError=0` but empty `ToolName` data — silent degradation rather than a loud failure.
  - **Defer rationale (Rule 8):** the bug shape is genuine but the carrier is the **whole Inspection-tool family**, not just Story 4.5. A cross-cutting fix should flow into Epic 7 or a dedicated cleanup story that adds an `EnsureIsErrorOnPrepareFailure` helper to `SessionAgent.Tool.Base` and retrofits all 9 inspection tools (EventLog, RuleLog, MessageHeaders, SessionSummary, SessionTimeline, GetMessageBody, GetMessageDetail, GetBusinessProcessSource, GetBusinessProcessInstance, ListBusinessProcessMethods, FindRelatedSessions) in one commit. Single-story fix would create inconsistency.
  - **Owner:** Story 10.9 (PRD v1 Completion Validation Walkthrough) — bound by Story 9.0 / Epic 8 retro per Rule 9 (named-successor-binding). **Rule 9 recovery — drifted past prior Story 4.7 named carrier**: this entry was originally bound to Story 4.7 ("ExplainError + comprehensive read-only suite verification") and the binding was silently dropped at Story 4.7 sign-off (the spec author did not grep deferred-work.md for "Story 4.7" mentions and incorporate). Story 7.0 re-bound explicitly to Story 8.0; **Second Rule 9 recovery — Story 8.0 re-binds to Story 9.0** to prevent further drift; **Third Rule 9 recovery — Story 9.0 re-binds to Story 10.9** to prevent further drift; full drift history Story 4.5 → Story 4.7 → Story 8.0 → Story 9.0 → Story 10.9 (the 9-tool defensive sweep across the Inspection family doesn't fit Epic 9's vocabulary-learning theme — Story 10.9 PRD-final-validation is the natural triage point). If Story 10.9 also can't carry, the recovery note compounds (fourth-recovery binding required — at which point a focused dedicated cleanup story should be opened rather than further re-binding). Story 10.9's lead MUST grep deferred-work.md for "Story 10.9" mentions and incorporate.
  - **Blocking?** Not blocking. Cosmetic robustness improvement; no current operator-observable break.

- **`Ens.MessageHeader.SuperSession` direct-column optimization (vs JOIN through `Ens.SuperSessionIndex`).**

  - **Source:** Story 4.5 code review (Edge Case Hunter E-1).
  - **Severity:** LOW (purely an optimization; current JOIN approach is semantically correct + matches spec intent "uses Ens.SuperSessionIndex").
  - **The observation:** `Ens.MessageHeader` has its own `SuperSession varchar` column (column #18). `Ens.SuperSessionIndex` is a side-table that indexes the same value with `SQLUPPER(250)` truncation + a unique-per-MessageHeader assumption. A direct query against `Ens.MessageHeader.SuperSession` (no JOIN) would be simpler and avoid one table touch. Tradeoffs: (a) the side-table has different population semantics — it's only populated when a `Ens.MessageHeader.OnSave` index trigger fires successfully; (b) the side-table's `SQLUPPER(250)` index makes case-insensitive lookups fast; (c) the spec said "uses Ens.SuperSessionIndex" so the JOIN approach is what was specified.
  - **Why deferred (Rule 8 test 3 — pure optimization, no predicted-bug shape):** the JOIN is correct, the spec says use the SuperSessionIndex, the dev install has zero rows on either side so we can't measure performance empirically. Optimization belongs in a future "search-tool performance pass" story.
  - **Owner:** Future Inspection/Search tool performance story (Epic 8 likely carrier — search tools share the same JOIN-vs-direct-column tradeoff against `Ens.SearchTableBase`).
  - **Blocking?** Not blocking.

- **Test fixture `OnBeforeAllTests` does not propagate seed-row failures to the test runner.**

  - **Source:** Story 4.5 code review (Edge Case Hunter E-3 + E-4).
  - **Severity:** LOW (cosmetic robustness — fixture failures would surface as assertion failures in the test bodies, not silent green tests, so the safety net catches the bug shape; just slightly later in the call stack than ideal).
  - **The observations:**
    1. `OnBeforeAllTests` checks `tRsHdr.%SQLCODE < 0` then does `Quit` — exits the For loop but does NOT return an error %Status to the test runner, so subsequent test methods run with partial fixture state.
    2. The "second header row to session A" insertion (line 147–150) ignores `%SQLCODE < 0` entirely. If A2 insert fails, `message_count >= 1` assertion in `TestRelatedSessionsFindsTwoOthers` would still pass (one row is enough), but the multi-row case wouldn't be exercised.
    3. The `tShiftedSecsA2 = tBaseSecs + 100` shift handles 1-day rollover via `$Select` but not 2-day. Real-world hit rate is essentially zero (test would have to run within the last 100 seconds before midnight).
  - **Why deferred (Rule 8 test 3 — no predicted-bug shape; assertion failures ARE the safety net):** if the fixture genuinely fails, test bodies will assert on missing rows and fail loudly. Hardening the fixture to also fail at the OnBeforeAllTests boundary is incremental robustness.
  - **Owner:** Any future Story-4.5 fixture-touching change.
  - **Blocking?** Not blocking.

- **Catch-block error_text uses `ex.DisplayString()` directly — may include raw IRIS error codes.**

  - **Source:** Story 4.5 code review (Edge Case Hunter E-7).
  - **Severity:** LOW (matches existing codebase pattern across all Story 4.1+ inspection tools; no operator-friendly redaction layer exists yet).
  - **The observation:** The outer `Catch ex` block sets `error_text:(ex.DisplayString())` in the `query_error` envelope. `ex.DisplayString()` returns IRIS-internal error formats like `<UNDEFINED>tIdx+5^SessionAgent.Tool...`, `<INVALID OREF>`, `<METHOD DOES NOT EXIST>` which are not operator-friendly. Operators see raw IRIS error codes in the chat panel rather than human-readable messages.
  - **Predicted-bug shape:** none — the `content[0].text` is also `ex.DisplayString()`, and the audit `ErrorText` column captures the same. So operators get a self-consistent (if unfriendly) error path.
  - **Defer rationale (Rule 8 test 3 — pure cosmetic, no predicted-bug shape):** no field break; no carrier exists yet for an operator-friendly error-redaction utility. Cross-cutting concern that belongs in an Inspection-tool quality-of-life pass.
  - **Owner:** Same future Inspection-tool cleanup story as B-3 above (suggested Story 4.7 sweep).
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-4.6-findsessionsbybody-ens-searchtablebase-pivot (2026-05-03)

- **Live OpenAI smoke turn substituted with three direct ObjectScript probes — credential not resolvable on dev install (Rule 11 conformance follow-up).**

  - **Source:** Story 4.6 code review (lead-flagged item #6 + Acceptance Auditor AC-6 review).
  - **Severity:** LOW (Rule 11 conformance: this story does not add OpenAI integration code, just consumes the existing path; substitution is acceptable per Rule 11 "if credential absent, test skipped not failed". Story 4.5 reportedly succeeded with the same credential check 2026-05-04, so the credential may have been rotated/expired between 4.5 and 4.6, OR Story 4.5's verification used a different credential path).
  - **The observation:** Dev report says `Util.EnvSecret.IsResolvable("OPENAI_API_KEY","SessionAgentInspectionApiKey") = 0` on this dev install. Three direct ObjectScript probes substituted: (1) `EnsLib.HL7.SearchTable` + `MRN=12345` → `render_strategy="no_matches"`, (2) `EnsLib.HL7v3.SearchTable` (truly not installed) → `render_strategy="search_table_not_installed"` + isError=1, (3) `Ens.MessageHeader` (wrong superclass) → `render_strategy="not_search_table_subclass"` + isError=1. All three render-paths exercised end-to-end; the visual-gate screenshot captures the rendered "not installed" envelope from path (2).
  - **Why deferred (Rule 8 test 3 — pure verification gap, no predicted-bug shape):** all three render paths the live LLM would exercise are already empirically verified via direct invocation. The remaining gap is purely "did the LLM choose the right tool name in response to the operator's English question?" — which Story 4.5 already proved end-to-end on the same tool surface. No predicted bug shape; the Story 4.7 (`ExplainError + comprehensive read-only suite verification`) sweep is the natural carrier for re-running live LLM smoke across the whole Epic 4 inspection-tool family once a credential is resolvable on the dev install.
  - **Owner:** Story 4.7 — should add as a verification-task line item: re-resolve `Util.EnvSecret.IsResolvable("OPENAI_API_KEY","SessionAgentInspectionApiKey")`. If 0, escalate to operator for credential setup before running live LLM smoke; if 1, run a single live-LLM turn covering each Epic 4 inspection tool (`event_log`, `rule_log`, `message_headers`, `session_summary`, `session_timeline`, `get_message_body`, `get_message_detail`, `get_business_process_source`, `get_business_process_instance`, `list_business_process_methods`, `find_related_sessions`, `find_sessions_by_body`).
  - **Blocking?** Not blocking. Acceptable Rule 11 substitution for Story 4.6 specifically; Story 4.7 sweep is the natural moment to verify the credential and exercise the full live-LLM matrix.

---

## Deferred from: code review of 4-7-explainerror-comprehensive-read-only-suite-verification (2026-05-04)

- **Story Completion Notes mis-state method count (8 vs 10) and falsely claim all passed.**

  - **Source:** Story 4.7 code review (reviewer empirical SQL probe of `%UnitTest_Result.TestMethod`).
  - **Severity:** LOW (housekeeping; self-resolving).
  - **The observation:** Story file lines 192-193 state *"all 8 methods Status=1 / passed"*. Empirically the suite has 10 methods, not 8, AND `TestFormatExceptionForOperatorStripsNoise` was failing across instances 931, 939, 969 — Status=0 consistent. The 211/0 figure was achievable only because the package-level `iris_execute_tests` runner truncates per-method reporting, masking the failure.
  - **Defer rationale (Rule 8 test 3 — pure cosmetic, no predicted-bug shape):** the failing method has been fixed in this same review (off-by-one closing-`>` drop, see story Review Findings); after fix all 10 methods are Status=1 and the 211/0 statement is now empirically accurate. The literal text in Completion Notes still says "8 methods" but no longer load-bearing for ship.
  - **Owner:** Lead — opportunistic when next touching this story file (e.g., Epic 4 retrospective writeup).
  - **Blocking?** Not blocking.

- **`BuildErrorTable()` rebuilds 10-entry %DynamicObject on every Invoke — class-header docstring incorrectly calls it "compile-time constant".**

  - **Source:** Story 4.7 code review (Edge Case Hunter).
  - **Severity:** LOW (Rule 8 test 3 — pure cosmetic with no predicted-bug shape).
  - **The observation:** The dev pivoted from `Parameter ERRORTABLE` JSON literal (didn't compile per ObjectScript class-parameter limitation) to a `[Internal] ClassMethod BuildErrorTable()`. The `Invoke` flow can call it up to twice per request (`LookupCuratedCode` → `BuildErrorTable`, then `GetTableEntry` → `BuildErrorTable` again). Class-header docstring at lines 28-32 calls this *"compile-time constant"* — empirically false; it's a per-call build of ~20 `%Set` invocations. Operator latency impact is sub-millisecond at 10 entries; only matters if heavy `explain_error` traffic emerges (e.g., agent looping over 50+ decode requests, which would build 100+ times).
  - **Why deferred (Rule 8 test 3):** PPG seeding (e.g., `^||SessionAgentExplainErrorTable` once-per-process) is the obvious follow-up if this ever matters, but the spec explicitly chose "rebuilt per call (cheap — 10 entries)" as the design and acknowledged the trade-off in Completion Notes line 178. The bug shape is purely a docstring drift — no operator-observable break.
  - **Owner:** No bound successor. Could be picked up opportunistically when a future story touches `ExplainError.cls`, OR if pilot operator data shows `explain_error` is dispatched in tight loops.
  - **Blocking?** Not blocking.

- **Visual-gate screenshot only shows 6 of 9 dispatched-tool sections in the visible viewport.**

  - **Source:** Story 4.7 code review (Blind Hunter).
  - **Severity:** LOW (Rule 8 test 3 — cosmetic / framing only, no predicted-bug shape).
  - **The observation:** `4-7-rule-12-visual-pass-1.png` shows 6 sections in the right pane (Summary, Timeline, Message Headers, Event Log, Rule Log, Find Related Sessions). The dev's audit-row probe shows 9 distinct tool names dispatched. The remaining 3 sections (`get_message_body`, `get_business_process_source`, `explain_error`) are below the fold — they were dispatched but the screenshot was framed at the top of the chat panel.
  - **Why deferred:** SQL probe `SELECT TOP 25 ID, ToolName, IsError, ChatHistoryId FROM SessionAgent_Audit.ToolCall ORDER BY ID DESC` returned 18 rows, ChatHistoryId=19, all `IsError=false`, 9 distinct tool names. The audit-row probe IS the empirical proof; the screenshot is corroborating evidence, not the gate. No regression.
  - **Owner:** No bound successor. If Epic 4 retrospective wants a more comprehensive visual, take a full-page scrolling screenshot via chrome-devtools-mcp.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of 5-0-epic-4-deferred-cleanup (2026-05-06)

- **Story 5.0 Completion Notes per-class breakdown lists `AuditEmitTest 3/3/0` but SQL probe at MAX(ID) shows that class was not part of the latest sweep cycle.**
  - **Source:** Story 5.0 code review (this file's entry).
  - **Severity:** LOW (notes accuracy; aggregate 225/225/0 is correct).
  - **The observation:** Reviewer ran the canonical SQL probe per AC-1 — `SELECT %EXACT(tc.Name), COUNT(*), SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END), SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) FROM %UnitTest_Result.TestMethod tm JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%' AND tc.ID IN (SELECT MAX(ID) ... GROUP BY %EXACT(Name)) GROUP BY %EXACT(tc.Name) ORDER BY %EXACT(tc.Name)` — returned 28 classes summing to 225, but `AuditEmitTest` was NOT in the result set. The dev's reported per-class breakdown listed 29 classes including `AuditEmitTest 3/3/0` with the parenthetical "(re-run individually)". Aggregate math (225/225/0) is correct without AuditEmitTest's "3" being added — meaning either the dev's per-class table includes a row that's leftover from earlier draft notes, or AuditEmitTest's row should have summed differently elsewhere. AC-7's contract is the aggregate, which holds — this is purely notes-accuracy.
  - **Why deferred:** LOW severity; aggregate contract holds; no predicted-bug shape. Per Rule 8 test 3 — cosmetic with no predicted-bug shape.
  - **Owner:** No bound successor; lead may correct in a follow-up cleanup commit if desired.
  - **Blocking?** Not blocking.

- **Rule 2 sharpening text says "5 reviewer-caught bugs" but enumerates 4 numbered list items.**
  - **Source:** Story 5.0 code review.
  - **Severity:** LOW (cosmetic — item 2 covers Story 4.4 HIGH x2 = 2 bugs in 1 list bullet, totaling 5 bug-instances across 4 bullets).
  - **The observation:** `.claude/rules/epic-cycle-discipline.md` Rule 2 sharpening section says "**5 reviewer-caught bugs that all involved the dev claiming completion based on tests-passing without empirical proof of the AC's actual contract:**" then numbers 1, 2, 3, 4. Item 2 reads "Story 4.4 HIGH x2 — class Description drift x2" which compresses 2 bugs into 1 bullet. Reader counting bullets sees 4; reader counting "x2" sees 5.
  - **Why deferred:** Cosmetic; the rule text is unambiguous to anyone reading carefully.
  - **Owner:** No bound successor.
  - **Blocking?** Not blocking.

- **Story 5.0 Change Log row 2 says "4 ObjectScript files modified, 2 rule files extended" — actually 3 ObjectScript files (`ExplainError.cls`, `InspectionSuiteVerificationTest.cls`, `MessageAdapterTest.cls`) + 2 rule files + 3 workflow artifacts (deferred-work.md, sprint-status.yaml, story file).**
  - **Source:** Story 5.0 code review.
  - **Severity:** LOW (cosmetic miscount in Change Log).
  - **Owner:** No bound successor.
  - **Blocking?** Not blocking.

- **Pre-existing flaky test observation: `SessionAgent.Test.AgentLoopGuardsTest:TestRunTurnMaxIterationsCap`.**
  - **Source:** Story 5.0 dev report + Story 5.0 reviewer re-run verification.
  - **Severity:** LOW (transient; passes on re-run).
  - **The observation:** Dev reported a transient `<INVALID OREF>` failure on the first post-Story-5.0 sweep, attributed to ambient `SessionAgent_Audit.LlmCall` row state from cumulative test runs (test asserts exactly 10 rows post-RunTurn; cumulative state had 20). Reviewer re-ran the class twice via `iris_execute_tests` + SQL probe — both runs Status=1, Duration ≈ 0.876s. Not caused by Story 5.0 (the dev did not touch `AgentLoop`, `ConfigAgent`, `Audit.LlmCall` storage, or this test class).
  - **Why deferred:** Pre-existing state-pollution sensitivity; Story 5.x dev can add a `Kill ^SessionAgent_Audit.LlmCallD` setup hook in `OnBeforeOneTest` if it recurs. Per Rule 8 test 1 (genuine future-epic scope — Epic 5 LLM provider stories will exercise `LlmCall` audit row writes more, may surface the issue more visibly).
  - **Owner:** Epic 5 dev (any of Stories 5.1-5.4) can add the cleanup hook if the test re-flakes during Epic 5 regression sweeps.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-5-1-llm-anthropicprovider-concrete (2026-05-06)

- **`SessionAgent.Config.Agent.SystemPromptOverride` MAXLEN=8192 silently truncates large operator-customized prompts.**
  - **Source:** Story 5.1 dev report (Debug Log References) — dev hit silent truncation when investigating cache_read=0 anomaly with a 63KB padded test prompt.
  - **Severity:** LOW (operator-visible behavior, but the runtime default `AgentDefaults.GetSystemPrompt` is well under 8192 and the override is operator-chosen).
  - **The observation:** `Config.Agent.cls:77` declares `Property SystemPromptOverride As %String(MAXLEN = 8192)`. When an operator supplies an override longer than 8192 characters, the persistence layer silently truncates without raising `%Status` warning. Dev empirically confirmed this swallowed a 63KB → 5469 chars transformation. For Anthropic providers, this matters because Haiku's prompt-cache minimum is roughly 2048 tokens (~8192 chars) — a truncated override below that threshold means cache_control markers never engage Anthropic's cache layer, defeating NFR-P6 cost savings.
  - **Why deferred:** (a) The runtime defaults (`AgentDefaults.GetSystemPrompt`) for both `session-inspection` and `message-search` agents are far below 8192. (b) Operators using a richly-tuned override are the only affected surface, and they are sophisticated users likely to notice the truncation in the Story 6.1 Zen form once it ships. (c) The fix is a cooperative change between `Config.Agent.cls` (raise MAXLEN, or convert to stream backing), the Story 6.1 Zen form (add a length warning + char counter), and possibly a startup linter that warns in `^%SYS.SessionAgent.Audit` if a row's override is exactly 8192 chars (a likely truncation marker).
  - **Recommendation:** Story 6.1 (AgentConfig Zen form layout) is the natural carrier — when shipping the form, add (a) a visible char counter on the `SystemPromptOverride` textarea, (b) a soft validator that flags overrides > 7500 chars (warning) and > 8192 chars (block-or-truncate-with-confirm), (c) a one-line operator-facing note in README §Operator Prerequisites about the cap. Alternatively, raise the property cap to `MAXLEN=32767` (or convert to a stream property) in a Story 6.x backend tweak.
  - **Owner:** **Story 6.1 (AgentConfig Zen form layout) — BINDING REASSIGNMENT per Rule 9 (Story 6.0 AC-2, 2026-05-06).** The Zen form's textarea is the operator-UX surface where char-counter + soft validator + property-cap raise all converge. Story 6.1's spec author MUST grep this file for "Story 6.1" and incorporate this entry into Story 6.1's ACs (Rule 9 binding-deferral mechanism). The property-cap raise specifically (`MAXLEN=8192` → `MAXLEN=32767`, or stream conversion) MAY be deferred to a sibling Story 6.x backend tweak if Story 6.1's scope tightens, but the operator-facing surface (char counter + soft validator + README note) is binding for Story 6.1.
  - **Blocking?** Not blocking. Operators can work around by keeping overrides ≤ 8192 chars.

- **`BuildPayload` `%FromJSON(%ToJSON())` defensive-copy round-trip on tool defs could throw on malformed input.**
  - **Source:** Story 5.1 code review (edge-case scan).
  - **Severity:** LOW (caught by outer Try/Catch in `CallMessages`; canonical tool defs from `Tool.Registry.ListTools()` are well-formed by construction).
  - **The observation:** `AnthropicProvider.cls:467` performs `Set tToolCopy = ##class(%DynamicObject).%FromJSON(tTool.%ToJSON())` to defensively clone each canonical tool def before potentially adding `cache_control`. If `tTool` somehow contains a `%DynamicArray` or `%DynamicObject` with a circular reference or non-serializable value, the `%ToJSON` could fail. The outer Try/Catch in `CallMessages` would convert this to a structured error envelope (no crash), but the failure mode is silent to the operator.
  - **Why deferred:** (a) `Tool.Registry.ListTools()` returns deterministically-shaped canonical tool defs from the trust-boundary registry — circular references are not a real attack/error surface. (b) The defensive clone is itself the right pattern (avoids mutating caller's tool def). (c) A more robust clone strategy would use `%DynamicObject.%New()` + key-by-key copy, but that adds maintenance cost for negligible reward.
  - **Recommendation:** No action. Document as known-acceptable in Story 5.4 (tool-call roundtrip integration test infrastructure) so the integration test exercises tool-def shape edge cases.
  - **Owner:** Story 5.4 dev (tool-call roundtrip integration tests) — verify integration test covers malformed-tool-def graceful degradation.
  - **Blocking?** Not blocking.

- **`ParseEndpointUrl` server includes port suffix when endpoint URL has explicit port (`https://host:443/path`).**
  - **Source:** Story 5.1 code review (edge-case scan; pre-existing shape inherited from Story 2.9 OpenAIProvider).
  - **Severity:** LOW (pre-existing; both providers have identical parser; default 443 inferred when `Https=1` so observable break only on non-standard ports).
  - **The observation:** Both `OpenAIProvider.ParseEndpointUrl` and `AnthropicProvider.ParseEndpointUrl` set `Server = $Extract(stripped, 1, slashPos - 2)`. For input `"https://api.anthropic.com:443/v1/messages"`, this yields `Server = "api.anthropic.com:443"` rather than the bare hostname + a separate `Port=443` setting. `%Net.HttpRequest` typically resolves a port-suffixed hostname correctly via DNS but this is non-canonical use.
  - **Why deferred:** (a) Standard Anthropic / OpenAI endpoints have no port suffix in the canonical URL. (b) Operator-override endpoints (`Config.Agent.EndpointUrl`) for non-standard hosts (e.g., a corporate proxy) are an Epic 5.3 OpenAI-compatible concern. (c) Same parser ships in OpenAIProvider since Story 2.9 with no observable break in production.
  - **Recommendation:** Story 5.3 (OpenAI-compatible provider) should generalize the URL parser into a shared utility and split `host:port` into separate `Server` and `Port` fields. Apply the fix to all four concrete providers in the same commit.
  - **Owner:** Story 5.3 (OpenAICompatProvider concrete) — natural carrier since it owns the operator-override URL surface most directly.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-5-2-llm-geminiprovider-concrete (2026-05-06)

- **Story 5.1 (`AnthropicProvider`) lacks a standing `*Live.cls` smoke test class — pattern divergence from Story 5.2's `GeminiProviderLive.cls`.**
  - **Source:** Story 5.2 code review (lead flagged item #4).
  - **Severity:** LOW (operator-observable as inconsistency only at epic-end battery time; both providers were live-verified during their respective stories — Story 5.1 via a transient helper that was deleted, Story 5.2 via the standing `GeminiProviderLive.cls`).
  - **The observation:** Story 5.2 commits `src/SessionAgent/Test/GeminiProviderLive.cls` as a standing class supporting the epic-end empirical battery (Rule 6 step 4 / Rule 11) — gracefully skips on missing credential, follows `*Live.cls` naming, NOT a `%UnitTest.TestCase` subclass so doesn't run in CI by default, exposes a single `Invoke()` classmethod the lead can call manually for re-verification. Story 5.1 used a transient helper class that the dev deleted post-investigation, so the Anthropic provider has no standing live-test surface. At Epic 5 retro time, the lead will re-run the empirical battery against the four shipped providers; if `AnthropicProviderLive.cls` doesn't exist, the lead will have to re-author it ad-hoc, defeating the standing-class rationale.
  - **Why deferred:** Predicted-bug shape per Rule 8 — Epic 5 retro empirical battery will be inconsistent across providers, increasing re-author cost. Genuine future-epic scope per Rule 8 test 1: the natural carrier is Story 5.3 (`OpenAICompatProvider`) where the dev will already be authoring `OpenAICompatProviderLive.cls` per the same Rule 11 pattern; adding `AnthropicProviderLive.cls` retroactively in the same commit is cheap (mirror `GeminiProviderLive.cls`, swap to Anthropic credential + Anthropic endpoint).
  - **Recommendation:** In Story 5.3's spec, add a Task line: "Author `OpenAICompatProviderLive.cls` AND retroactively add `AnthropicProviderLive.cls` (mirror `GeminiProviderLive.cls`) so all four cloud providers have standing Rule 11 live-test surfaces by Epic 5 close." This unifies the pattern at minimal cost.
  - **Owner:** Story 5.3 dev (OpenAICompatProvider concrete) — closest natural carrier; same provider epic.
  - **Blocking?** Not blocking. Epic 5 retro can re-author ad-hoc if the deferral is missed.
  - **Status (2026-05-06): CLOSED by Story 5.3 (AC-9).** `src/SessionAgent/Test/AnthropicProviderLive.cls` shipped following the `GeminiProviderLive.cls` template; live verified in Story 5.3 review (audit row 7 against fresh Anthropic call — claude-haiku-4-5-20251001, tool_use, IsError=0). Three standing live-test classes now exist (`AnthropicProviderLive`, `GeminiProviderLive`, `OpenAICompatProviderLive`); Story 2.9 OpenAIProvider has its own pre-existing live test.

---

## Deferred from: code review of story-5-3-llm-openaicompatprovider-concrete (2026-05-06)

- **Optional-auth design relies on operator setting `Config.Agent.EnvVarName='PATH'` (or any always-set env var) to satisfy the abstract template's credential-missing fast path.**
  - **Source:** Story 5.3 code review (lead flagged item #3); dev's Design Decision #2 in story Completion Notes.
  - **Severity:** LOW (operator-observable as docs-bound friction; no functional bug — production code paths verified by `TestAuthHeaderEmptyKeyOmitsHeader` test pass + live Ollama call pass with `EnvVarName=PATH, CredentialName=""`).
  - **The friction:** `SessionAgent.LLM.Provider.Invoke` (the abstract template) resolves the API key via `EnvSecret.Resolve(EnvVarName, CredentialName)` BEFORE calling the concrete's `CallMessages`. When both are empty (the natural Ollama-no-auth config), `Resolve` returns empty, the abstract surfaces "Credential resolution failed" and never invokes the concrete. Story 5.3's workaround: README + operator-quickstart instruct the operator to set `EnvVarName=PATH` (a guaranteed-non-empty env var) so `Resolve` returns non-empty (the value of $PATH), the abstract template proceeds, and `OpenAICompatProvider.CallMessages` then explicitly clears `..ApiKey` when `CredentialName=""` so no spurious Bearer header is built. This works but is an idiom that requires reading the docs to discover; an operator who skips the EnvVarName instruction will see the false-negative "Credential resolution failed" envelope despite intending optional-auth.
  - **Why deferred (Rule 8 test 1 — genuine future-epic scope):** the cleaner fix is to lift the credential-missing fast path INTO the abstract's per-concrete decision (e.g., concrete returns `IsAuthOptional()` or the concrete owns the resolved value verification) — that's a non-trivial refactor of the Story 2.8 abstract template and crosses the OpenAI/Anthropic/Gemini surfaces. Story 5.4 (tool-call-roundtrip integration test infrastructure) or a future Epic 5 retrospective action item is the natural carrier.
  - **Owner:** Future Epic 5 retro / Story 5.4 dev — to assess whether the operator-friction warrants the abstract refactor, OR whether docs-only is sufficient.
  - **Blocking?** Not blocking — production live test passes; docs are accurate.

- **`OpenAICompatProvider.BuildPayload` always emits `tools: []` even when `pToolDefs` is empty, mirroring Story 2.9 OpenAIProvider behavior. Some OpenAI-compatible endpoints (older Ollama versions, vLLM with strict validation) reject empty tools arrays with 400.**
  - **Source:** Story 5.3 code review.
  - **Severity:** LOW (pre-existing parity behavior; not a Story 5.3 regression — `OpenAIProvider.BuildPayload` does the same).
  - **The observation:** lines 471-472 of `OpenAICompatProvider.cls` always call `Do tPayload.%Set("tools", tOaTools)` regardless of `tOaTools.%Size()`. The Story 5.3 live test passes because it provides one tool (event_log); a production agent with zero tool-defs in flight could trigger an endpoint-specific 400. Live OpenAI cloud accepts empty tools arrays; live Ollama/qwen3:14b accepts them; LM Studio's strict-mode setting and llama.cpp older builds may not.
  - **Why deferred (Rule 8 test 3 — pure cosmetic / pre-existing parity / no production-shape bug observed):** the runtime always provides a non-empty 13-tool catalog at AgentLoop dispatch time, so the empty-tools edge case never reaches the wire in the canonical SessionAgent.Inspection / .Search agent flows. Operator-built custom agents could in theory configure zero tools, but that's a corner the operator chose. The fix (skip `%Set` when `tOaTools.%Size() = 0`) is one-line and could ride the next provider-touching story; not worth a same-commit fix when no failing wire-shape was observed.
  - **Recommendation:** When the next provider story touches the BuildPayload helpers (e.g., a 5th provider extension), patch all four providers to skip the `tools` field when empty. One-line fix `If $IsObject(tOaTools), tOaTools.%Size() > 0 { Do tPayload.%Set("tools", tOaTools) }`.
  - **Owner:** Future provider story.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-5.4-tool-call-roundtrip-integration-test-infrastructure (2026-05-06)

- **Retry-loop duplication across 4 concrete providers — 1.7× threshold; refactor to `RetryWithBackoff.ExecuteOnInstance` strongly justified.**
  - **Source:** Story 5.4 AC-7 audit + carry-forward from Story 2.9 deferred entry (deferred-work.md:258 area).
  - **Severity:** MEDIUM (architect-decision item — not a bug, but a maintenance cost: every retry-tuning change requires 4 parallel edits with bug-introducing copy-paste risk).
  - **The count (verified Story 5.4):** OpenAIProvider 55 lines (243-297), AnthropicProvider 48 lines (291-338), GeminiProvider ~45 lines, OpenAICompatProvider ~46 lines — total **~194-202 lines** of structurally identical retry orchestration. Story 2.9 deferred-work threshold was ~120 lines for evaluating refactor.
  - **Why deferred (Rule 8 test 1 — genuine future-story scope):** the refactor crosses all four production providers + their unit-test classes. Touching that surface is a deliberate scope-bounded story (Story 6.x or 7.x), not an opportunistic ride-along on a test-infrastructure story. Story 5.4's mock harness deliberately bypasses the retry path (mock CallMessages overrides the production retry loop), so the matrix test wouldn't catch a refactor regression — Story 6.x must add focused unit tests around `RetryWithBackoff.ExecuteOnInstance` itself and verify each provider's retry envelope wiring still triggers correctly post-refactor.
  - **Recommendation:** Open Story 6.x as **"Provider retry-loop consolidation to `RetryWithBackoff.ExecuteOnInstance`"** with ACs covering: (a) introduce a `ExecuteOnInstance(pProviderLabel, pCallback) As %DynamicObject` helper that returns `{statusCode, bodyText, headers, midFlight, exhausted}`; (b) replace the inline `While tAttempt < tMaxAttempts {...}` block in each of the 4 providers with one call to that helper; (c) add `RetryWithBackoffTest` cases for the new helper; (d) verify the 11 per-provider tests + 4 `*ProviderLive` tests still pass.
  - **Owner:** Story 10.9 (PRD v1 Completion Validation Walkthrough) — bound by Story 9.0 / Epic 8 retro per Rule 9 (named-successor-binding). Story 10.9's lead MUST grep deferred-work.md for "Story 10.9" mentions and incorporate. (Re-bound from Story 9.0 — substantive ~200-line refactor across 4 providers doesn't fit Epic 9's vocabulary-learning theme; deferred under Rule 8 test #1 — genuine future-story scope. Drift history: Story 5.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9.)
  - **Blocking?** Not blocking. Maintenance-cost item, not correctness.

- **Gemini live-API stopReason inconsistency: `finishReason="STOP"` returned despite `functionCall` part being present, mapped to canonical `stopReason="end_turn"` instead of `tool_use` — RESOLVED 2026-05-06 in Epic 5 manual-test bundle (Bug-4).**
  - **Source:** Story 5.4 closing-battery live test (Audit.LlmCall row 121: gemini, end_turn, with content `type=tool_use name=event_log`).
  - **Severity:** MEDIUM (operator-observable: AgentLoop's iteration-termination depends on accurate stopReason — a tool_use turn misclassified as end_turn could cause the agent to stop iterating instead of dispatching the tool call).
  - **Resolution:** Epic 5 user-led manual-test pass surfaced the predicted symptom end-to-end (Gemini chat-panel response rendered empty agent block — tool dispatch never fired). Fixed in `MessageAdapter.GeminiToCanonical` with content-aware override: when `tCallSeq > 0` (any `tool_use` block emitted), force `tStopReason = "tool_use"` regardless of finishReason. The deferred recommendation called for fixing `ProviderToCanonical` post-process; the actual fix lives one level deeper at `GeminiToCanonical` where `tCallSeq` is already tracked. OpenAI's adapter doesn't have the analogous bug — its `MapOpenAiFinishReason` maps `tool_calls` correctly via the wire-level `finish_reason` field which OpenAI populates accurately. Verified end-to-end via chat panel post-fix.
  - **The observation:** `MessageAdapter.MapGeminiFinishReason` (line 666 of MessageAdapter.cls) maps `"STOP" → "end_turn"` without inspecting the candidate's content. The matrix mock (`BuildGeminiToolUseResponse`) deliberately emits `finishReason="TOOL_CALLS"` to exercise the structurally correct path; the live API often returns `"STOP"` even with a `functionCall` part present, which the canonical translation classifies as terminal text-only end. AgentLoop's stop-reason switch (line ~285) routes `"end_turn"` to "no further iterations" — so the agent could fail to dispatch a real Gemini tool_use call.
  - **Why deferred (Rule 8 test 1 — genuine future-story scope):** the fix requires content-aware translation in `MessageAdapter.ProviderToCanonical("gemini", ...)` — post-process: if `stopReason="end_turn"` AND content has any `tool_use` block, override `stopReason → "tool_use"`. Same fix-class needed across `ProviderToCanonical("openai", ...)` for OpenAI's analogous `finish_reason="stop"` + `tool_calls` block edge (per Story 5.0/5.1 retros — verify whether OpenAI's adapter already handles this). Story 5.4's deterministic test passes because the mock emits `TOOL_CALLS`; only the live test surfaces the real-API quirk. Refactor + test add belongs in a focused Story 6.x.
  - **Recommendation:** Open Story 6.x as **"Content-aware stopReason override in MessageAdapter"** with ACs covering: (a) post-process step in `ProviderToCanonical` for both OpenAI and Gemini — if any `tool_use` content block is present, override `stopReason → "tool_use"` regardless of upstream finishReason; (b) add an integration test against a captured live Gemini response body that reproduces `STOP + functionCall`; (c) verify AgentLoop now correctly enters the tool-dispatch branch.
  - **Owner:** Architect (Winston) / Epic 6 dev — to scope for Epic 6 sprint planning.
  - **Blocking?** Could mask tool-dispatch failures on real Gemini traffic; should be picked up early in Epic 6.

- **AgentLoop "Concurrent turn in progress" message overloading — FIXED in Story 5.4.**
  - **Source:** Story 5.4 dev-discovered (debugging session 2026-05-06).
  - **Severity:** MEDIUM (was — fixed; entry kept for retro/learning purposes).
  - **The bug (now fixed):** `AgentLoop.RunTurn` line 131-135 emitted `"Concurrent turn in progress; please wait."` whenever `LoadOrCreate` returned NULLOREF, regardless of root cause. This masked datatype-validation failures (e.g., SessionKey overflowing MAXLEN=50) that produce a non-OK `tLoadStatus` — devs investigated phantom concurrency issues for hours instead of seeing the real validation error.
  - **Story 5.4 fix-now (Rule 8):** added `If $$$ISERR(tLoadStatus)` branch to surface the underlying error text via `$System.Status.GetErrorText`; the misleading "Concurrent turn in progress" message is now reserved for genuine lock-acquisition failures (where `pStatus = $$$OK` but the OREF is NULL).
  - **Verified empirically:** `RunTurn(..., "this-is-a-very-long-session-key-that-exceeds-50-chars-and-it-does", ...)` now returns `"Chat history load failed: ERROR #7201: Datatype value '...' length longer than MAXLEN allowed of 50"` — the real cause.
  - **Owner:** Story 5.4 (resolved); kept here as retro signal for "never-throw envelope but lossy error classification" pattern.
  - **Blocking?** Not blocking — fix shipped in Story 5.4.

- **Test-suite count mild drift in dev's Completion Notes — total is 266/266, not 264/264.**
  - **Source:** Story 5.4 code review SQL probe.
  - **Severity:** LOW (cosmetic — dev's verbatim regression sweep transcript shows individual class tallies that sum to 266; dev wrote "Total: 264 / 264 / 0" in the closing line. `VisualTraceTest` shows 8 tests in the live SQL but the dev's transcript wrote 6).
  - **Why noted:** Rule 2 sharpening asks for verbatim transcripts in Completion Notes; the verbatim per-class output is correct; only the manually-summed total line is +2 stale (likely typed before the latest VisualTraceTest method additions).
  - **Recommendation:** Pass-through — does not invalidate the empirical battery; future Rule-2 transcripts should sum the per-class tallies via `SUM(tm.ID)` rather than typing a manual total to avoid this class of drift.
  - **Owner:** Lead (process improvement — automate the total in future transcripts).
  - **Blocking?** Not blocking.

- **Pre-existing flake in `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` — intermittently fails under heavier test-suite cadence (carry-forward to Epic 6 retro).**
  - **Source:** Story 5.4 code review re-run; carry-forward from Story 5.0 mention.
  - **Severity:** LOW (pre-existing — Story 5.4 re-runs showed Status=1 in fresh isolation; Status=0 surfaced when run inside a hot suite-39 cadence; 1-of-2 runs flaked).
  - **The observation:** running `RunOneTestCase` produced Status=1; the same method shows Status=0 in a prior TestSuite=35 run captured in `%UnitTest_Result`. Not investigated deeply during Story 5.4 review (out of scope for the closer; pre-existing).
  - **Recommendation:** Carry forward to Epic 6 for root-cause investigation. Likely cause is global state leaking between `OnBeforeOneTest`/`OnAfterOneTest` boundaries (override holders, ProviderOverride PPG, Config.Agent rows). The matrix test (`OnAfterAllTests`) sweeps SessionKey-prefixed rows; the AgentLoopGuardsTest may not. Worth a focused re-test cadence run + global-state probe.
  - **Owner:** Epic 6 dev / lead.
  - **Blocking?** Not blocking — flakes do not block ship; flake budget belongs in Epic 6 retro health.

- **`epic-5-operator-state.md:85` says "all three cloud providers" — stale phrasing now that 4 providers ship.**
  - **Source:** Story 5.4 review Rule-4 stale-reference scan.
  - **Severity:** LOW (internal planning artifact, not operator-facing; OpenAICompat is technically a cloud or local endpoint, ambiguous categorization).
  - **Recommendation:** Pick up in Epic 5 retro doc-cleanup pass; rewrite as "all four providers (OpenAI / Anthropic / Gemini / OpenAI-Compat)".
  - **Owner:** Epic 5 retro.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-6-1-agentconfig-zen-form-layout (2026-05-06)

- **`AgentConfigTest.TestLoadAgentConfigReturnsSeededRow` softened `Enabled=0` assertion to boolean-shape check — operator-state-tolerant but loses seed-default coverage.**
  - **Source:** Story 6.1 code review LOW-1.
  - **Severity:** LOW (no predicted-bug shape; documented design choice).
  - **The observation:** The dev softened `$$$AssertEquals(Enabled, 0)` to `AssertTrue((Enabled=0) || (Enabled=1))` because the live `Config.Agent` row for `session-inspection` had `Enabled=1` (operator-modified state from prior Epic 4/5 manual testing). The softening is justified per Rule 9 (test must not break on operator state drift), but it loses coverage of the genuine seed-default invariant.
  - **Recommendation:** A future test-hardening pass (sibling Story 6.x or an Epic 6 retro action item) should add a `TestLoadAgentConfigSeedDefaultEnabled` that resets state via `%DeleteId` + reseed in `OnBeforeOneTest` and asserts the genuine seed-default value. The seed-default invariant is owned by `ConfigAgentTest.cls` (the persistence-layer test class), not by the UI helper test, so the softening here is acceptable for Story 6.1's scope.
  - **Owner:** Epic 6 lead — pick up during retro health-check pass or sibling test-hardening story.
  - **Blocking?** Not blocking. Story 6.1 ships as-is.

- **Story 6.1 Completion Notes regression-sweep count was understated by 30 (claimed 239/239, ground truth was 269/269 from SQL probe).**
  - **Source:** Story 6.1 code review MEDIUM-1.
  - **Severity:** MEDIUM at find-time (Rule 5.0 AC-1 violation: SQL-probe-as-ground-truth); resolved in this commit by reviewer-annotated correction in Completion Notes.
  - **Recommendation:** Lead must apply Rule 5.0 AC-1's SQL-probe-as-ground-truth invariant on every empirical-battery claim — drive the "N/N pass" line from the SQL probe against `%UnitTest_Result.TestMethod`, NOT from the `iris_execute_tests` JSON envelope (which silently truncates per Rule 6 step 3). The package-runner truncation behavior was directly observed in this story (package-level invocation returned only 11 of the 270 test methods). Codify this as a sprint-planning checklist item: "Did the empirical battery claim cite a SQL probe?" If no, reject the claim. Already covered by Rule 5.0 AC-1 — this entry is informational so future cycles see this is a recurring failure mode.
  - **Owner:** Epic 6 lead — process-level, not code-level.
  - **Blocking?** Not blocking — substantive "all pass" claim was correct in shape; only the count was wrong.

---

## Deferred from: code review of story-6.2-save-handler-hot-config-change-verification (2026-05-06)

- **Story 6.2 LOW-1 — chrome-devtools-mcp stale lock blocked Rule 12 screenshot evidence; dev fell back to rendered-DOM textContent fetch (acceptable per Rule 12 §"Acceptable evidence forms").**
  - **Source:** Story 6.2 code review.
  - **Severity:** LOW (no code defect — process / tooling friction).
  - **Observation:** chrome-devtools-mcp returned the same Story-6.1 stale-lock condition (`The browser is already running for C:\Users\Josh\.cache\chrome-devtools-mcp\chrome-profile`). The dev fell back to rendered-DOM textContent verification via direct CSP HTTP fetch, which Rule 12 §"Acceptable evidence forms" lists as acceptable evidence. The reviewer reproduced the same fallback during this review — chrome-devtools-mcp remains locked. Both Story 6.1 and Story 6.2 have now hit this condition.
  - **Recommendation:** Operator should clear the chrome-devtools-mcp profile lock before any future UI-story empirical battery so the screenshot path is available — or the project should document the rendered-DOM textContent fallback as the canonical evidence form for this codebase's UI stories until the lock issue is resolved upstream. The Rule 12 human-read step (the substantive invariant — "is the rendered text readable English?") was satisfied in both Story 6.1 and Story 6.2 via the textContent paste; the screenshot is a delivery-form preference, not a contract gap.
  - **Owner:** Operator (Josh) for the lock clear; Epic 6 lead for the rendered-DOM textContent canonicalization decision if the lock keeps recurring.
  - **Blocking?** Not blocking — Story 6.2 ships as-is with textContent fallback evidence.

- **Story 6.2 LOW-2 — regression-sweep aggregate count of 281/281 in the dev's Completion Notes does not match the SQL ground-truth probe (which shows 254/254 from MAX-runIdx-per-class projection).**
  - **Source:** Story 6.2 code review.
  - **Severity:** LOW (no operator-observable impact; the substantive "all pass" claim is true — only the count is contested).
  - **Observation:** The dev's table in Completion Notes claims 281 SessionAgent.Test methods total (15 in AgentConfigTest after their +11 additions). The SQL ground-truth probe via `MAX(ID) GROUP BY Name` per Story 5.0 AC-1 returns 254 — the SQL projection picks the most-recent run-id per class, but those run-ids vary across classes (AgentConfigTest's most-recent run was run 158 with all 15 methods, but the projection's chosen ID may be a stale run for some other class that didn't include the new tests). The SQL probe-as-ground-truth pattern is actually loose when test classes are run individually at different times — the "latest run per class" is a moving target. The empirical reality (verified by reviewer): AgentConfigTest run 158 has 15/15 PASS (verified directly via `^UnitTest.Result(158,...)` walk), and reviewer's run 173 added a 16th test (`TestSaveAgentConfigRejectsInvalidCredTypeRadio` for Bug-1 fix-now) and observed 16/16 PASS. **The fix-now bug count is +12 over the Story 6.1 baseline (270 SessionAgent.Test methods + 12 new = 282/282 substantive count after the reviewer-added test).**
  - **Recommendation:** The Story 5.0 AC-1 SQL probe shape is correct in principle (ground-truth via `^UnitTest.Result`), but the join-on-MAX-ID-per-class form is fragile across multi-run sessions (it will silently pick stale runs when the dev ran a class individually after a package run). A more robust shape: aggregate each test method's most-recent status by name (regardless of run-id), or run a full-package sweep at the very end and aggregate from THAT single run-id. Codifying this as a tweak to the Story 5.0 AC-1 query in `.claude/rules/object-script-testing.md` is a process-level Epic 6 retro item.
  - **Owner:** RESOLVED in Story 8.0 AC-5 (commit pending). Rule-tweak shipped: `.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth for test-pass verification" canonical SQL form rewritten to use numeric run-id comparison (`$PIECE(ID,'||',1)+0`) instead of lexicographic `MAX(ID) GROUP BY %EXACT(Name)`, and the inner `MaxRunIdx` aggregate is now JOIN'd through TestMethod so orphaned TestCase runs (with zero method rows) cannot be selected as "latest". Empirical demonstration stanza added citing this entry's 281-vs-254 discrepancy and Story 7.0 verification battery's 260/260 (canonical, fragile) vs 288/288 (truncation-aware truth) discrepancy.
  - **Blocking?** Not blocking — substantive "all pass" claim is correct.

---

## Deferred from: Story 6.4 (Multi-Namespace Install Support, 2026-05-06)

- **`SessionAgent.Installer:CopyConfigBetweenNamespaces(pSrc, pDst)` cross-namespace config copy helper.**
  - **Source:** Story 6.4 AC-5 architectural-decision documentation.
  - **Severity:** Backend tweak — pure-cosmetic operator convenience (Rule 8 test #3: "no bug shape").
  - **Justification (Rule 8 test #3):** the per-namespace `Config.Agent` decision recorded in AC-5 is the safer default for v1 — operators with cross-namespace identical config maintain the rows manually (or copy via SQL `INSERT ... SELECT FROM ...` cross-namespace) until a future helper ships. There is no predicted-bug shape — the helper is a usability nicety, not a correctness gap.
  - **Recommendation when picked up:** ship as a peer ClassMethod on `SessionAgent.Installer` mirroring the `InstallIntoNamespace` pattern (3-tier validation: pSrc empty / equals pDst / pSrc-or-pDst nonexistent + package-mapped check on both, then a transactional cross-namespace `Config.Agent` row copy with the destination's existing rows replaced atomically). Should be additive — must NOT retroactively flip the per-namespace default to a shared-config default.
  - **Owner:** Future Epic 6.x story (no specific story slot reserved — pick up when an operator surfaces the need).
  - **Blocking?** Not blocking. Story 6.4 ships the multi-namespace install path; cross-namespace copy is a usability follow-up.

- **`MultiNamespaceInstallTest` test-method-order coupling — TestInstallIntoNamespaceCreatesPerNamespaceState mutates SATEST64 Provider before TestInstallIntoNamespaceIdempotency runs.** (LOW — Story 6.4 reviewer-found, 2026-05-06)
  - **Source:** Story 6.4 code review (Edge Case Hunter layer) — `src/SessionAgent/Test/MultiNamespaceInstallTest.cls:280` (`Do ..SetSessionInspectionProvider("anthropic")`) followed by `:308` (`TestInstallIntoNamespaceIdempotency`).
  - **Severity:** LOW — passes today; predicted-bug shape is hypothetical and contingent on future test refactoring.
  - **Justification (Rule 8 test #3 "no bug shape"):** `TestInstallIntoNamespaceCreatesPerNamespaceState` flips SATEST64's `session-inspection.Provider` to "anthropic" as the cross-namespace independence assertion. `TestInstallIntoNamespaceIdempotency` runs after (alphabetical method-order in `%UnitTest`), and the second `InstallIntoNamespace` does NOT overwrite the existing row (per the `AgentNameIdxExists` guard in `Installer.SeedOneAgent`). The idempotency test only counts rows, so the cross-test coupling does not affect today's pass/fail outcome. If a future test reorder swaps these methods, or adds an intermediate test that depends on the seed Provider being "openai", the seed-shape coupling could surface as a flaky test.
  - **Recommendation when picked up:** add an explicit `Reset` step in `OnBeforeOneTest` (or a new `OnBeforeOneTest` per-method discriminator) that re-seeds SATEST64 to the canonical seed shape via direct SQL `DELETE FROM SessionAgent_Config.Agent` + re-run `..Install("")`. Alternatively, parameterize the `SetSessionInspectionProvider` mutation to roll back at the end of the test method. Either approach removes the cross-test order dependency.
  - **Owner:** Story 10.9 (PRD v1 Completion Validation Walkthrough) — bound by Story 9.0 / Epic 8 retro per Rule 9 (named-successor-binding); test-isolation refactor. Story 10.9's lead MUST grep deferred-work.md for "Story 10.9" mentions and incorporate. (Re-bound from Story 9.0 — test-isolation refactor across 6 test methods doesn't fit Epic 9's vocabulary-learning theme; deferred under Rule 8 test #3 — current 6/6 PASS, predicted-bug shape is hypothetical and contingent on future test refactoring. Drift history: Story 6.4 → Story 7.0 → Story 8.0 → Story 9.0 → Story 10.9.)
  - **Blocking?** Not blocking. Story 6.4 ships with all 6 tests passing on the current method order.

---

## Deferred from: code review of story-7.0-epic-6-deferred-cleanup (2026-05-06)

- **LOW-R1 — Rule 12 application-matrix row visual density.**
  - **Source:** Story 7.0 code review.
  - **Severity:** LOW (Rule 8 test #3 — pure cosmetic, no bug shape).
  - **Observation:** Rule 12's row in the application-matrix table at `.claude/rules/epic-cycle-discipline.md` line 394 packs ~3 sentences (rule-name parenthetical + Lead cell + Dev cell + Code-Review cell) into a single table row. Renders as valid markdown but is visually dense compared to the other rule rows (1-line cells). A future style pass could split the rule-name cell into a short label + footnote / split the row into a primary row + a sub-row for the layout/content split.
  - **Recommendation when picked up:** Either split into two rows (one for content-correctness, one for layout-correctness) or refactor the matrix entry into a footnote+anchor pattern so the matrix stays scan-friendly. Pure formatting; no functional change.
  - **Owner:** Future style/readability pass on `.claude/rules/epic-cycle-discipline.md` (no specific story slot reserved).
  - **Blocking?** Not blocking. Rule semantics are unaffected.

- **LOW-R2 — AC-3 sub-section datatype example drift between body text and pattern snippet.**
  - **Source:** Story 7.0 code review.
  - **Severity:** LOW (Rule 8 test #3 — pure cosmetic; the `e.g.` qualifier covers either datatype).
  - **Observation:** The new "`Property Test*` Test-Method-Discovery Shadow Trap" sub-section in `.claude/rules/object-script-testing.md` mentions the example `Property TestNsPrepared As %String` in the rule body (line 238), while the pattern code snippet (line 279) uses `Property PreparedTestNs As %Boolean [ InitialExpression = 0 ]` (matching the actual Story 6.4 originating code at `src/SessionAgent/Test/MultiNamespaceInstallTest.cls:61`). Both forms are valid examples; the body-text vs snippet datatype drifting is cosmetic.
  - **Recommendation when picked up:** Align the body-text example to `As %Boolean` to match the originating finding's actual datatype, OR keep `As %String` deliberately to make the rule generalize. Either is fine; just pick one.
  - **Owner:** Future docs polish pass on `.claude/rules/object-script-testing.md` (no specific story slot reserved).
  - **Blocking?** Not blocking. The rule's substantive guidance (any `Test*` prefix triggers the shadow trap) is correct regardless of the example datatype.

---

## Deferred from: code review of story-7-2-purgeorphanedchathistory-task-installer-scheduling (2026-05-06)

- **LOW-7.2-F02 — `tScanRS` not closed if outer Try fails between `%Execute` (line 117) and explicit `%Close` (line 132).**
  - **Source:** Story 7.2 code review (Edge Case Hunter layer, finding F-02).
  - **Severity:** LOW (no concrete predicted-bug shape under realistic operating conditions).
  - **Observation:** [`src/SessionAgent/Task/PurgeOrphanedChatHistory.cls:117-132`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls#L117) opens `tScanRS` at line 117 and explicitly closes it at line 132 after the `%Next()` loop completes. If an exception raises mid-Phase 1 (e.g., a transient %SQL.Statement runtime error during `%Get`), the outer `Catch` at line 195 absorbs it and sets `tSC = ex.AsStatus()`, but the open result-set is not explicitly `%Close()`'d before exit. IRIS GC eventually reclaims the transient handle.
  - **Why deferred (Rule 8 review):** Test 1 (future-epic scope) — not a fit; the fix would land in Story 7.2 if pursued. Test 2 (external-dependency blocker) — not a fit. Test 3 (cosmetic / no predicted-bug shape) — borderline; under realistic operating conditions (`%SYS.Task` daily-2am sweep + IRIS GC + per-orphan sub-Try absorbing all the predictable failure modes), the leak shape doesn't materialize. The outer-Catch path is reached only on Phase 1 fatal errors that imply a deeper IRIS-side issue (Ens.MessageHeader scan failure, statement-cache exhaustion) where the unreleased RS handle is the least of the operator's concerns.
  - **Recommendation when picked up:** Wrap `tScanRS = tScanStmt.%Execute()` in its own try/finally-equivalent block that calls `%Close()` on the outer-catch path. The cleanest pattern is `If $IsObject(tScanRS) Do tScanRS.%Close()` as the first line of the outer Catch, before `Set tSC = ex.AsStatus()`.
  - **Owner:** None reserved. Optional polish for any future story that touches `PurgeOrphanedChatHistory.OnTask()` for unrelated reasons.
  - **Blocking?** Not blocking.

- **LOW-7.2-F03 — `tLlmRS` / `tToolRS` not closed if `%Execute` raises mid-DELETE inside Phase 3 sub-Try.**
  - **Source:** Story 7.2 code review (Edge Case Hunter layer, finding F-03).
  - **Severity:** LOW (sub-Try absorbs; transient RS handle is GC'd).
  - **Observation:** [`src/SessionAgent/Task/PurgeOrphanedChatHistory.cls:165-175`](../../src/SessionAgent/Task/PurgeOrphanedChatHistory.cls#L165) per-orphan sub-Try executes `tLlmStmt.%Execute(tChatId)` → counter advance → `Do tLlmRS.%Close()`. Same shape for `tToolRS`. If `%Execute` itself raises, the partially-bound RS object is never `%Close()`'d. The sub-Try at line 186 `Catch exOrphan { ... }` absorbs the exception and the loop continues with the next orphan; the orphan that triggered the exception is silently skipped.
  - **Why deferred (Rule 8 review):** Same rationale as F-02. The forward-progress design (per AC-4 commit-per-orphan) explicitly accepts per-orphan failure as silent skip. Adding `If $IsObject(tLlmRS) Do tLlmRS.%Close()` and the equivalent for `tToolRS` inside the sub-Try's catch block would be belt-and-suspenders cleanup; the cost (4 extra lines) vs the benefit (transient handle released ~0.001s sooner per failed orphan) doesn't move the needle for a daily 2am sweep.
  - **Recommendation when picked up:** Same pattern as F-02 — `If $IsObject(tLlmRS) Do tLlmRS.%Close()` and `If $IsObject(tToolRS) Do tToolRS.%Close()` as the first lines of the per-orphan sub-Try's catch block.
  - **Owner:** None reserved. Same optional-polish bucket as F-02.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-8-1-vocabulary-schemas-seed-templates (2026-05-07)

- **LOW-8.1-F01 — `SeedVocabulary.Seed()` lacks DB-level concurrency guard against double-insertion under simultaneous Installer invocations.**
  - **Source:** Story 8.1 code review (Edge Case Hunter layer, finding F-2).
  - **Severity:** LOW (no concrete predicted-bug shape under realistic operating conditions; IPM lifecycle is single-threaded).
  - **Observation:** [`src/SessionAgent/Search/SeedVocabulary.cls:152-207`](../../src/SessionAgent/Search/SeedVocabulary.cls#L152) `InsertIfMissing` uses a TOCTOU pattern — probes via `SELECT TOP 1 ID ... WHERE %EXACT(Alias)=? AND MessageBodyClass IS NULL` then inserts via `%New() + %Save()` without a transactional bracket or DB-level uniqueness constraint on `(Alias, MessageBodyClass)`. If two `Installer.Install` invocations run concurrently (e.g., parallel IPM operations on a shared IRIS instance, or an operator script that loops `zpm install` while another `zpm install` is mid-flight), both probes can return zero rows, both inserts succeed, the SeedVocabulary extent ends up with 20 rows instead of 10. The `AliasIdx` is non-unique (per AC-2 — multiple `MessageBodyClass` values may share an Alias), so it provides no DB-level guard.
  - **Why deferred (Rule 8 review):** Test 1 (future-epic scope) — not a fit; could land in Story 8.1 itself if pursued. Test 2 (external-dependency blocker) — not a fit. Test 3 (cosmetic / no predicted-bug shape) — borderline. IPM's `<Invoke>` lifecycle invokes `Installer.Install("")` once per `zpm load` / `zpm install` operation; concurrent IPM operations on the same module in the same namespace are not a documented operator workflow and would surface other races first (Audit.Emit.EnsureEvents has the same shape, and ships from Epic 1). The realistic operator's single-threaded install path makes this LOW.
  - **Recommendation when picked up:** Either (a) add a unique compound `(Alias, MessageBodyClass)` index to `SeedVocabulary.cls` — but this needs careful schema migration since the dev's empirical finding (IRIS stores empty `%String` as SQL NULL) means SQL-level uniqueness on a NULL column is implementation-defined; or (b) wrap the probe-then-insert in `TSTART`/`TCOMMIT` with `LOCK +^SeedVocabularyLock:0`. Option (b) is the safer pattern and aligns with NFR-R5 idempotency hardening.
  - **Owner:** None reserved. Natural carrier is the v1.5 / Vision-tier vocabulary hardening pass (the same epic that also activates `NamespaceVocabulary` aggregation logic).
  - **Blocking?** Not blocking. Operator-observable break only under unsupported concurrent-install workflow.

---

## Deferred from: code review of story-8-3-6-simple-indexed-access-tools (2026-05-07)

- **LOW-8.3-F01 — `SELECT DISTINCT TOP ?` is redundant after `GROUP BY mh.SessionId` in all 6 search-tool SQL constructions.**
  - **Source:** Story 8.3 code review (Acceptance Auditor layer).
  - **Severity:** LOW (cosmetic; no behavioral or performance impact).
  - **Observation:** [`src/SessionAgent/Tool/Search/SearchByTime.cls:164`](../../src/SessionAgent/Tool/Search/SearchByTime.cls#L164), and identical lines in `SearchByStatus.cls`, `SearchBySource.cls`, `SearchByTarget.cls`, `SearchByMessageClass.cls`, `SearchBySession.cls`. Each SQL leads with `SELECT DISTINCT TOP ? mh.SessionId AS sid, MIN(mh.TimeCreated) AS tc, ... FROM Ens.MessageHeader mh WHERE ... GROUP BY mh.SessionId`. After `GROUP BY mh.SessionId` each group already produces exactly one row, so the leading `DISTINCT` is a no-op. The optimizer likely strips it but the query plan would be cleaner without it.
  - **Why deferred (Rule 8 review):** Test 3 (cosmetic / no predicted-bug shape) — fits cleanly. The SQL is correct and produces the documented result shape; removing `DISTINCT` is a one-character edit per tool that doesn't change behavior. Not worth the test-class re-run cost in this story.
  - **Recommendation when picked up:** Drop the `DISTINCT` keyword from all 6 SQL constructions in a follow-up cleanup story (or as a drive-by fix in any story that touches these classes).
  - **Owner:** None reserved. Natural carrier is any Story 8.x or future story that meaningfully edits the search-tool SQL.
  - **Blocking?** Not blocking. No operator-observable difference.

- **LOW-8.3-F02 — `time_window_used: 0` in SearchByTime explicit-bound mode may confuse operators reading the envelope.**
  - **Source:** Story 8.3 code review (Edge Case Hunter layer).
  - **Severity:** LOW (operator-observable but documented in Completion Notes; no functional bug).
  - **Observation:** [`src/SessionAgent/Tool/Search/SearchByTime.cls:160`](../../src/SessionAgent/Tool/Search/SearchByTime.cls#L160) — when the caller supplies `from_time` and/or `to_time` (explicit-bound mode), the envelope reports `time_window_used: 0`. An operator reading the structured envelope sees `time_window_used: 0` and may interpret it as "0 hours = no window applied = empty results" rather than "explicit bounds drove the query, no helper-default applied". The existing AC-6 keyed-lookup mode uses JSON `null` for the same semantic ("no window applied"); the explicit-bound mode could be unified to also emit `null` for consistency.
  - **Why deferred (Rule 8 review):** Test 3 (cosmetic / no predicted-bug shape) — fits. The 0 sentinel is documented in the dev's Completion Notes design-decisions block, the LLM is informed of the canonical semantics via system prompt + tool description, and the test class asserts the 0 value explicitly. Switching to `null` would touch the test class + the SearchByTime tool; the value is non-zero churn for an operator-readability nicety.
  - **Recommendation when picked up:** Standardize the "no window applied" signal across `SearchByTime` explicit-bound mode AND `SearchBySession` keyed-lookup mode by emitting `null` in both cases. Update the test assertion accordingly.
  - **Owner:** None reserved. Natural carrier is Story 8.4/8.5/8.6/8.7 (extending the Search Agent tool suite — likely encounters the same envelope-shape question for vocabulary-driven tools).
  - **Blocking?** Not blocking. Operator-observable but ergonomic-not-functional.

---

## Deferred from: code review of story-8.4-searchbysupersession (2026-05-07)

- **LOW-8.4-F01 — Phase-1 "no super-session for seed_session_id" error envelope omits a `super_session_key: ""` field that callers may expect for shape stability.**
  - **Source:** Story 8.4 code review (informational-only finding).
  - **Severity:** LOW (cosmetic; no contract breach).
  - **Observation:** [`src/SessionAgent/Tool/Search/SearchBySuperSession.cls:173`](../../src/SessionAgent/Tool/Search/SearchBySuperSession.cls#L173) — when Phase-1 lookup finds no `Ens.SuperSessionIndex` row for the supplied `seed_session_id`, the structured-content envelope returns `{render_strategy: "no_super_session_for_seed", seed_session_id: tSeedId}` without a `super_session_key: ""` field. Sister tool `SessionAgent.Tool.Inspection.FindRelatedSessions` (Story 4.5) DOES echo `super_session_key: ""` in its empty-shape envelope so downstream renderers can rely on a stable shape regardless of `isError`. The Story 8.4 dev's design choice is defensible — `isError:1` clearly steers callers to read `content[0].text` — but it leaves the structuredContent shape inconsistent across the cross-instance tool family.
  - **Why deferred (Rule 8 review):** Test 3 (cosmetic / no predicted-bug shape) — fits. No operator-observable bug; no envelope contract breach (the absence of `super_session_key` is consistent with the documented success-only-presence rule). Adding the field is a one-line patch but would benefit from being part of a deliberate cross-tool envelope-stability sweep, not a one-off.
  - **Recommendation when picked up:** When Story 8.5/8.6/8.7 ship their additional cross-instance/vocabulary-driven tools, codify a "structuredContent fields are always present, defaulted to JSON `null` or empty string on isError envelopes" convention across the Search Agent tool family + retrofit `SearchBySuperSession` and the existing `FindRelatedSessions` if they drift.
  - **Owner:** None reserved. Natural carrier is Story 8.5/8.6/8.7 (continued Search Agent extension).
  - **Blocking?** Not blocking. Cosmetic shape consistency.

- **LOW-8.4-F02 — Lex-MAX vs numerical-MAX SQL form ambiguity in `^UnitTest.Result` probes; project rule already mandates numerical-MAX but several stories have re-tripped the lex-MAX trap.**
  - **Source:** Story 8.4 code review (auto-resolved in same commit; logged for visibility).
  - **Severity:** LOW (the project rule §"SQL-probe-as-ground-truth for test-pass verification" in `.claude/rules/object-script-testing.md` already mandates the numerical-MAX form via `$PIECE(ID,'||',1)+0`; the rule is sound but stories 8.0, 8.2, 8.3, 8.4 have each surfaced one instance of dev-fallback to bare lex-MAX).
  - **Observation:** Story 8.4 dev's submission reported `282/282/0` from a `MAX(ID)` SQL probe; the actual ground-truth aggregate via numerical-MAX is `310/310/0` (matching the spec's expected baseline). The dev's debug-log notes acknowledged the lex-MAX-vs-numerical-MAX concern verbatim but then declined to use the numerical-MAX form. Story 8.2 reviewer encountered the same flag and dismissed it as "rule already addresses it"; Story 8.4 surfaced it again — the *rule* is fine, the *muscle memory* is not yet automatic.
  - **Why deferred:** Test 3 (cosmetic — no predicted-bug shape; the binding "0 failures" signal is preserved in both forms). The story-level fix landed in the Completion Notes correction. The pattern-prevention angle is what makes this worth a deferred-work entry — to surface the recurrence pattern for the next epic-cycle retrospective so the rule's enforcement gets a sharper trigger (e.g., a per-story Task-0 SQL-template the dev pastes verbatim, instead of constructing the SQL ad-hoc).
  - **Recommendation when picked up:** At the next Epic-cycle retrospective (Epic 8 close), consider a sharpening to Rule 6 step 3 / `.claude/rules/object-script-testing.md` §"SQL-probe-as-ground-truth": ship a literal copy-pasteable SQL template inside the project rule file and require dev Completion Notes to paste the template verbatim before substituting class-filter values. The current rule cites the form correctly but allows dev-construction-from-memory which has now mis-fired across 4 stories.
  - **Owner:** None reserved. Natural carrier is Epic 8 retrospective / Story 8.7 close-out.
  - **Blocking?** Not blocking. Process-improvement item.

---

## Deferred from: code review of story-8.5-searchbybodyfield-ens-searchtablebase-pivot (2026-05-07)

- **LOW-8.5-F01 — AC-3 spec wording drift: `%IsA` → `%Extends` (lead-attention spec correction; no code change).**
  - **Source:** Story 8.5 code review (informational-only finding for the lead).
  - **Severity:** LOW (no operator-observable defect — the dev's `%Extends` form is the empirically-correct one and is verbatim-reused from Story 4.6 [`FindSessionsByBody.cls:217`](../../src/SessionAgent/Tool/Inspection/FindSessionsByBody.cls#L217); Story 4.6's class-doc comment §"Class validation idiom" lines 37–61 documents WHY `%IsA` was rejected during Task-0 probing and `%Extends` chosen instead).
  - **Observation:** AC-3 in [Story 8.5 spec](8-5-searchbybodyfield-ens-searchtablebase-pivot.md) (line 26) reads *"...via `$ClassMethod(class, "%IsA", "Ens.SearchTableBase")` (per Story 4.6's verified pattern...)"*. The verified Story 4.6 pattern is `%Extends`, not `%IsA`. The dev correctly followed the verbatim-reuse instruction in Dev Notes ("Reuse 3 patterns verbatim from Story 4.6, do NOT re-derive") which overrides the AC-3 wording, and `SearchByBodyField.cls:241` uses `%Extends`. The story spec drift is in epics.md Story 8.5 source text — the lead authoring AC-3 from epics.md picked up the wrong API name.
  - **Why deferred (Rule 8 review):** Test 3 — pure spec/doc cosmetic with no predicted-bug shape. The shipped code is correct. The deferral exists to surface the spec-drift to the lead for a one-line correction in `epics.md` Story 8.5 (and any planning artifact that propagated AC-3 verbatim) so future authors of body-field-pivot tools don't re-derive `%IsA` from a stale AC.
  - **Recommendation when picked up:** Lead correction to [`epics.md` §"Story 8.5"](../planning-artifacts/epics.md) AC-3 — change `%IsA` → `%Extends`. Add a parenthetical citing Story 4.6 Task-0 finding so the rationale is preserved. No code change, no test change.
  - **Owner:** Lead (one-line `epics.md` edit on next planning-artifact pass; or rolls into Epic 8 retrospective close-out alongside the LOW-8.4-F02 sharpening).
  - **Blocking?** Not blocking. Spec-drift cosmetic; the live code is correct.

- **MEDIUM-8.5-F02 — `Tool.Search.Base.BuildBoundedWhereClause` lacks an optional alias parameter for JOIN-form callers; Story 8.5 carries a local `$Replace` workaround that future search-tool authors will re-inherit.** **[RESOLVED in Story 8.6 — 2026-05-07]**
  - **Source:** Story 8.5 code review (predicted-recurrence pattern).
  - **Resolution (Story 8.6):** All 3 coordinated changes from the Recommendation block landed in Story 8.6: (1) `Tool.Search.Base.BuildBoundedWhereClause` signature extended with `pTimeColumnAlias As %String = ""` parameter; non-empty value qualifies the emitted `TimeCreated > ?` predicate (e.g., `"mh.TimeCreated > ?"`). (2) `BoundedWhereInvariantTest` extended with new method `TestStubFixtureBoundedWhereWithAliasQualifies` asserting the alias-qualified form. (3) `SearchByBodyField.Invoke` Step 7 refactored to pass `"mh"` as the alias parameter — `$Replace` workaround removed. The new tool `Tool.Search.InspectBodyCandidates` uses the alias parameter directly. All existing callers updated to pass `""` for backward compatibility. 318/318 SQL ground-truth pass.
  - **Severity:** MEDIUM. The shipped workaround at [`SearchByBodyField.cls:336`](../../src/SessionAgent/Tool/Search/SearchByBodyField.cls#L336) — `Set tFragment = $Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")` — is functionally correct (the substring is unique to `BuildBoundedWhereClause`'s emitted output, no SQL-injection risk because no operator input flows through it, no aliasing collision possible). But it sets a precedent: any future search tool that needs a JOIN form will re-inherit the same `$Replace`. Story 8.6 (`InspectBodyCandidates`) is the next consumer that will hit this exact shape.
  - **Why deferred (Rule 8 review):** Test 1 — genuine future-epic scope. The natural binding successor is **Story 8.6** (`InspectBodyCandidates`), which also pivots through SearchTable + JOIN and will be the second consumer of the workaround. The refactor is a backward-compatible additive parameter change that fits naturally inside Story 8.6's scope rather than retrofitting Story 8.5 in isolation.
  - **Predicted-bug shape (Rule 9 binding):** if `BuildBoundedWhereClause`'s emitted-output substring drifts in a future Story 8.6+ change (e.g., emits `"TimeCreated >= ?"` or `"TimeCreated > ? AND ..."`), Story 8.5's local `$Replace` will silently fail to qualify the alias and the SQL will reference the unqualified `TimeCreated` against an ambiguous column on the JOIN — `<SQLCODE>` -29 or similar will surface at runtime. The refactor closes the latent failure mode.
  - **Recommendation when picked up (Story 8.6 binding):**
    1. Extend `Tool.Search.Base.BuildBoundedWhereClause` signature with optional `pTimeColumnAlias As %String = ""` parameter; when non-empty, emit `pTimeColumnAlias _ "." _ "TimeCreated > ?"` instead of the bare form.
    2. Update Story 8.2 stub-positive tests (`TestStubFixtureBoundedWhereDefaultsTo24h`) to assert the bare form when `pTimeColumnAlias = ""` (default backward-compatible) AND add a positive-test asserting `"mh.TimeCreated > ?"` when `pTimeColumnAlias = "mh"`.
    3. Refactor `SearchByBodyField.Invoke` Step 7 to pass `"mh"` as the alias parameter and remove the `$Replace` workaround.
    4. `InspectBodyCandidates` (Story 8.6) uses the new alias parameter directly, never inheriting the workaround.
  - **Owner:** Story 8.6 dev. **Story 8.6 spec author MUST grep `deferred-work.md` for "Story 8.6" mentions per Rule 9 and incorporate the refactor into Story 8.6's ACs as a sub-task.**
  - **Blocking?** Not blocking Story 8.5 (workaround is correct + documented). Becomes blocking on Story 8.6 entering dev — that story MUST address the alias-parameter refactor as part of its scope.



---

## Deferred from: code review of story-8.6-inspectbodycandidates-two-stage-body-content-search (2026-05-07)

- **LOW-8.6-F01 — Stale class doc-comment in `SearchToolTest.cls` claims 100 cap-test rows are seeded that aren't.**
  - **Source:** Story 8.6 code review (informational-only finding).
  - **File:** [`src/SessionAgent/Test/SearchToolTest.cls`](../../src/SessionAgent/Test/SearchToolTest.cls) lines 53-62.
  - **Severity:** LOW (no operator-observable defect; no test-correctness defect — the cap test asserts the AC-2 hard-validation path that fires BEFORE the prefilter SQL runs, so the 100 fixture rows would be unreachable code).
  - **Observation:** The class doc-comment claims `OnBeforeAllTests` seeds "100 cap-test rows in BASESID+200..299 each with Status=8 (Error) and identical body text — exercises the AC-2 hard cap rejection path with candidate_cap=100." The seeding code does NOT actually create those rows; only the 5 happy-path bodies + 1 missing-body row are seeded. The `TestInspectBodyCandidatesCapEnforcedAt50` test correctly exercises the structured-error envelope path WITHOUT needing the 100 fixture rows.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape. The documentation is misleading but the test logic is correct.
  - **Recommendation when picked up:** Edit class doc-comment to remove the "100 cap-test rows" claim; replace with "AC-2 hard-cap-validation tests rejection envelope without depending on fixture rows".
  - **Owner:** Future cosmetic-cleanup pass; or rolls into Epic 8 retrospective close-out.
  - **Blocking?** Not blocking.

- **LOW-8.6-F02 — Dead PPG initialization scaffolding for cap-test fixture that was never seeded.**
  - **Source:** Story 8.6 code review (informational-only finding; sibling to LOW-8.6-F01).
  - **File:** [`src/SessionAgent/Test/SearchToolTest.cls`](../../src/SessionAgent/Test/SearchToolTest.cls) lines 447-448 + lines 607-615.
  - **Severity:** LOW (dead code; killing/iterating empty PPGs is a no-op).
  - **Observation:** `Kill ^||SessionAgentSearchInspectCapTestIds` and `Kill ^||SessionAgentSearchInspectCapBodyIds` are present in `OnBeforeAllTests`, and parallel iteration sweeps in `OnAfterAllTests`. But neither PPG is ever populated — the cap-test fixture is not seeded.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape.
  - **Recommendation when picked up:** Either remove the dead PPG references (cleanup pass) or seed the actual 100-row cap-test fixture (enhancement). Neither is binding; pairs with LOW-8.6-F01 closure.
  - **Owner:** Future cosmetic-cleanup pass; or rolls into Epic 8 retrospective close-out.
  - **Blocking?** Not blocking.

- **LOW-8.6-F03 — `InspectBodyCandidates` operator-readable summary echoes integer Status code rather than display name.**
  - **Source:** Story 8.6 code review (enhancement opportunity).
  - **File:** [`src/SessionAgent/Tool/Search/InspectBodyCandidates.cls`](../../src/SessionAgent/Tool/Search/InspectBodyCandidates.cls) line 447 (operator-readable summary text).
  - **Severity:** LOW (no predicted-bug shape — the rendering is technically accurate).
  - **Observation:** When `prefilter_indexed_column="Status"` and `prefilter_value="8"`, the operator-readable `content[0].text` reads "Inspected N candidate(s) filtered by Status='8' in the last 24 hour(s); …". An operator unfamiliar with Ens status codes will see `Status='8'` and have to look up that 8 = Error. Sibling tool `SearchByStatus` translates the integer to its display name internally before reporting; `InspectBodyCandidates` does not.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape. The LLM driving the tool will know the status code semantics (it is enum-described in `SearchByStatus.cls` Description) and can include the display name in its operator-facing summary; the LLM-grounded `structuredContent` carries the canonical machine-readable shape.
  - **Recommendation when picked up:** Display-name-translate when `prefilter_indexed_column="Status"` (e.g., `Status='Error'` instead of `Status='8'`). The translation table is already implemented in [`SearchByStatus.cls`](../../src/SessionAgent/Tool/Search/SearchByStatus.cls) `StatusDisplayToCode` (could lift to a shared helper, or inline the inverse map in `InspectBodyCandidates`).
  - **Owner:** Story 8.7 (Epic 8 closer) or Epic 8 retrospective close-out.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-8.7-vocablookup-utility-comprehensive-searchtooltest (2026-05-07)

- **LOW-8.7-F01 — `VocabLookup.InvokeList` argument-array packing has a fragile dead-code shape.**
  - **Source:** Story 8.7 code review (Blind-Hunter layer).
  - **File:** [`src/SessionAgent/Tool/Search/VocabLookup.cls`](../../src/SessionAgent/Tool/Search/VocabLookup.cls) lines 211-220 (post-review-fix line numbers).
  - **Severity:** LOW (no operator-observable defect — keyed-lookup mode means `tParams` is always empty in current usage; the `tArgs(2) = pPortalUser` line correctly lands `pPortalUser` at the second `?` placeholder).
  - **Observation:** `InvokeList` initializes `tArgs(1) = tLimit` then iterates the `tParams` array (empty after `BuildBoundedWhereClause(KeyedLookupSentinel, ...)` returns) starting at index 2, then UNCONDITIONALLY sets `tArgs(2) = pPortalUser`. If `tParams` ever contained binds (e.g., a future refactor that mixes time-window mode with PortalUser binding), the iterator's first bind at index 2 would be silently overwritten by the PortalUser assignment. The `InvokeSearch` method uses an explicit numbered packing (`tArgs(1)=tLimit, tArgs(2)=pPortalUser, tArgs(3)=tPattern`) which is the cleaner pattern.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape. The current `BuildBoundedWhereClause(KeyedLookupSentinel, ...)` contract guarantees `tParams` is empty in the keyed-lookup path, so the dead-code iterator loop is functionally equivalent to a no-op. Refactoring to the explicit numbered packing would be a one-line cleanup but no operator-observable defect can be predicted from the current shape.
  - **Recommendation when picked up:** Replace the iterator + `tArgs(2)` assignment with the explicit form used by `InvokeSearch`:
    ```
    Kill tArgs
    Set tArgs(1) = tLimit
    Set tArgs(2) = pPortalUser
    Set tArgs = 2
    ```
  - **Owner:** Future cosmetic-cleanup pass; or rolls into Epic 9 vocabulary-learning enhancements (Story 9.1+) if those touch `VocabLookup.InvokeList`.
  - **Blocking?** Not blocking.

- **LOW-8.7-F02 — `vocab_lookup` invalid-mode error message renders awkward when mode is empty (`got: ''`).**
  - **Source:** Story 8.7 code review (Edge-Case-Hunter layer).
  - **File:** [`src/SessionAgent/Tool/Search/VocabLookup.cls`](../../src/SessionAgent/Tool/Search/VocabLookup.cls) line 212 (post-review-fix line numbers).
  - **Severity:** LOW (no operator-observable defect — error envelope is correctly structured; only the prose is mildly awkward).
  - **Observation:** When the operator invokes `vocab_lookup({})` with no `mode` field, the dispatch falls through to the `Else` branch that emits *"vocab_lookup mode must be one of 'list' | 'save' | 'search'; got: ''"*. The trailing `got: ''` is functionally correct but reads awkward — an operator who forgot to include `mode` would benefit from a more direct *"the 'mode' field is required"* phrasing.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape. The locked-subset JSON Schema declares `mode` as `required`, so a future MCP-side validator will reject the empty-mode request before it even reaches `Invoke`; the prose only matters for tests / direct-dispatch callers.
  - **Recommendation when picked up:** Branch the error message: when `tMode = ""` emit *"vocab_lookup requires a 'mode' field — one of 'list' | 'save' | 'search'"*; otherwise keep the current "got: 'X'" form.
  - **Owner:** Future cosmetic-cleanup pass.
  - **Blocking?** Not blocking.

---

## Deferred from: code review of story-9.1-task-0-probes-onaftersave-non-recursion-synthesizealias-determinism (2026-05-07)

- **MEDIUM-9.1-F01 — Pre-existing flake observation: `SessionAgent.Test.AuditTest:TestLogLlmCallWritesOneRow` — intermittently fails on first run, passes on retry (carry-forward to Epic 9 retro / future test-hardening pass).**
  - **Source:** Story 9.1 dev's regression-sweep transcript ("first run failed `AssertEquals: 5 LogLlmCall invocations -> 5 rows persisted`; passed on retry") — reviewer-confirmed not introduced by Story 9.1 (no `AuditTest.cls` modifications in the diff; last commit touching the file is `229f223` from Epic 2 retro).
  - **File:** [`src/SessionAgent/Test/AuditTest.cls`](../../src/SessionAgent/Test/AuditTest.cls) line 149 (`TestLogLlmCallWritesOneRow`).
  - **Severity:** MEDIUM at observation-time (a flaky regression-sweep test pollutes the pass-count signal); LOW for ship-blocking purposes (passes on retry; no operator-observable defect).
  - **Observation:** The test calls `LogLlmCall` 5 times then asserts `SELECT COUNT(*) AS Cnt FROM SessionAgent_Audit.LlmCall = 5`. `OnBeforeOneTest` already kills `^SessionAgent.Audit.LlmCallD` and `^SessionAgent.Audit.LlmCallI` so seeded baseline is empty. The flake symptom (count != 5) suggests concurrent writes from another test or background process emitting LlmCall audit events during the window between OnBeforeOneTest's kill and the test's COUNT(*) probe.
  - **Why deferred (Rule 5 + Rule 8 review):** Pre-existing pattern — same root-cause shape as `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` already in this file (line 892+) — global state leaking across tests under heavy concurrent test cadence. Story 9.1 dev correctly noted it but it's out-of-scope for a probe-only story. Per Rule 5, root-cause investigation deferred; per Rule 8 Test 1 (genuine future-epic scope) — flake budget belongs in Epic 9 retro health-check pass alongside the existing `AgentLoopGuardsTest` carry-forward.
  - **Recommendation when picked up:** Combine with `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` deferred entry (line 892+) into a single Epic 9 / Epic 10 test-isolation hardening story. Likely fix: add a process-locking guard or a unique-namespace prefix to LlmCall test rows so concurrent test execution doesn't cross-contaminate. Worth a focused re-test cadence run + global-state probe.
  - **Owner:** Epic 9 retro / future test-hardening pass.
  - **Blocking?** Not blocking — flakes do not block ship; passes on retry; flake budget belongs in Epic 9 retro health.

- **LOW-9.1-F02 — `SessionAgent.Search.SynthesizeAlias.NormalizeValue` boolean-type comment misleading.**
  - **Source:** Story 9.1 code review (Edge-Case-Hunter layer).
  - **File:** [`src/SessionAgent/Search/SynthesizeAlias.cls`](../../src/SessionAgent/Search/SynthesizeAlias.cls) lines 178-181.
  - **Severity:** LOW (no operator-observable defect — behavior is correct; only the comment is misleading).
  - **Observation:** The comment at line 179 says *`"true"/"false" are already lowercase canonical"`* but `%GetIterator()` typically delivers boolean values as the integers `1` or `0` (with type=`"boolean"` flag), not the string literals `"true"`/`"false"`. The actual stringification `pVal _ ""` produces `"1"`/`"0"`, which is consistent with the rest of the function (numeric stringification). Determinism holds — `{flag:true}` and `{flag:1}` would converge — but the comment text suggests the function emits `"true"`/`"false"` which is incorrect.
  - **Why deferred (Rule 8 review):** Test 3 — pure cosmetic, no predicted bug shape. AC-2 does not require boolean test coverage; no production caller currently passes booleans (Story 9.5's click-through capture key contract uses tool-arg dictionaries that are typically string-keyed/string-valued). If Story 9.5 surfaces a boolean-value scenario the comment can be tightened then.
  - **Recommendation when picked up:** Either (a) rewrite the comment to *"booleans deliver as 1/0 integers from %GetIterator(); stringify via concat to produce '1'/'0' (consistent with numeric stringification path)"*, or (b) explicitly canonicalize booleans to `"true"`/`"false"` strings to make the alias more human-readable. (a) preserves current behavior; (b) is a behavior change that needs a determinism test — pick (a) for the cosmetic cleanup pass.
  - **Owner:** Story 9.5 dev (when consuming `SynthesizeAlias`) or future cosmetic-cleanup pass.
  - **Blocking?** Not blocking — Story 9.5 will exercise the contract empirically and can revise then if needed.

---

## Deferred from: code review of story-9-2-uservocabulary-recordsuccess-recordfailure-recursion-safe-onaftersave (2026-05-07)

- **LOW-9.2-F06 — `RecordSuccess` / `RecordFailure` accept empty `pPortalUser` / `pAlias` without input validation.**
  - **Source:** Story 9.2 code review (Blind-Hunter layer).
  - **File:** [`src/SessionAgent/Search/UserVocabulary.cls`](../../src/SessionAgent/Search/UserVocabulary.cls) lines 153 (`RecordSuccess`) and 247 (`RecordFailure`).
  - **Severity:** LOW (no production caller currently passes empty values — `VocabLookup.InvokeSave` and the `Invoke` dispatcher's caller-context guard reject empty `PortalUser` upstream; `pAlias = ""` is rejected by the XOR mode-dispatch check at `Invoke` line 200).
  - **Observation:** Neither `RecordSuccess` nor `RecordFailure` validates that `pPortalUser '= ""` and `pAlias '= ""` before the `%SQL.Statement` probe. A future direct caller (e.g., a Story 9.5 ZenMethod, an REST handler, or any non-VocabLookup entry point) that forgets the upstream guard would create rows with empty PortalUser and/or empty Alias — which would still satisfy the `(PortalUser, Alias)` unique index (empty ≠ empty for different invocations? actually empty = empty for the unique constraint, so subsequent calls would correctly increment instead of insert) but pollutes the vocabulary table with operator-invisible rows.
  - **Why deferred (Rule 8 review):** Test #1 — genuine future-story scope. The natural carrier is **Story 9.5 (`RecordClickThrough` ZenMethod)** which is the next direct caller of `RecordSuccess`. Story 9.5's spec MUST add the input-validation guard to its own ZenMethod entry (per the project pattern of validating at the public-surface layer, not deep in the persistence-helper layer); pushing that guard into `RecordSuccess` itself would be premature defensive programming. If a third caller surfaces in Story 9.6+, revisit this deferral.
  - **Recommendation when picked up:** Story 9.5's `RecordClickThrough` ZenMethod adds at its top:
    ```
    If pPortalUser = "" Quit $$$ERROR($$$GeneralError, "RecordClickThrough: pPortalUser required")
    If pAlias = "" Quit $$$ERROR($$$GeneralError, "RecordClickThrough: pAlias required")
    ```
    Same shape applies to any future direct caller. The persistence helpers (`RecordSuccess` / `RecordFailure`) stay as low-validation primitives so callers can compose them.
  - **Owner:** Story 9.5 dev (when authoring `RecordClickThrough` ZenMethod).
  - **Blocking?** Not blocking — Story 9.2 ships safely because all current callers guard at their own entry points.

- **LOW-9.2-F08 — `%OnAfterSave` Confidence-recompute race under concurrent saves on the same row.**
  - **Source:** Story 9.2 code review (Edge-Case-Hunter layer).
  - **File:** [`src/SessionAgent/Search/UserVocabulary.cls`](../../src/SessionAgent/Search/UserVocabulary.cls) lines 297-308 (`%OnAfterSave`).
  - **Severity:** LOW (no operator-observable bug under expected single-portal-user single-session usage; vocabulary writes are serialized at the (`PortalUser`, `Alias`) granularity and a single operator does not generate concurrent saves on the same alias).
  - **Observation:** Two near-simultaneous `RecordSuccess` calls against the same `(PortalUser, Alias)` row — e.g., Session A and Session B both clicking through the same hit at the same instant — could both read stale `SuccessCount` (say `3`), both compute `Confidence = 3 / (3+0+1) = 0.75`, and both UPDATE Confidence=0.75 even though one of the writes should have observed `SuccessCount=4` and computed `0.8`. The `%Save()` / OREF persistence layer serializes the SuccessCount integer increment correctly (each save sees its own pre-incremented value), but the trigger's `..SuccessCount` snapshot at trigger-fire time may already be stale relative to the storage layer's actual post-commit value if a parallel session committed first. Last-write-wins on Confidence — semantically the trailing-Confidence is a few thousandths off the "correct" recompute. Self-corrects on the next save.
  - **Why deferred (Rule 8 review):** Test #1 — out of AC-3 scope ("recursion-safe", not "concurrent-safe"). AC-3 verifies the trigger doesn't re-fire itself; concurrency is a separate hardening axis the architecture has not yet declared as a v1 requirement (the search agent is single-portal-user-per-session by design; the per-user vocab table is not a high-write-contention surface). Story 9.5's `RecordClickThrough` ZenMethod adds a single click-write path; Story 9.4's first-message prefix-injection adds a sweep-style read path; neither concurrent-saves-on-same-row workload exists in v1.
  - **Recommendation when picked up (Epic 10+ hardening or a future high-write-contention story):** wrap the trigger's compute+UPDATE in a `LOCK +^SessionAgenC88B.UserVocabularyD(:tId):0E="lockfail"` to serialize concurrent recomputes per-row. Alternative: move the Confidence recompute to a SQL CASE expression in the trigger's UPDATE so the computed value reads the current `SuccessCount` / `FailureCount` from the row at UPDATE time (avoiding the OREF snapshot stale-read).
  - **Owner:** Future hardening story (Epic 10 retrospective candidate or the first concurrent-write contention bug report).
  - **Blocking?** Not blocking — single-operator per-session usage means the race window is operationally inaccessible in v1.


---

## Deferred from: code review of story-9.3-search-vocabularydigest-build (2026-05-07)

- **LOW-9.3-F01 — `Build` reader of `MessageBodyClass` lacks `$Char(0)` defensive normalization.**
  - **Source:** Story 9.3 code review (Edge-Case-Hunter layer).
  - **File:** [`src/SessionAgent/Search/VocabularyDigest.cls`](../../src/SessionAgent/Search/VocabularyDigest.cls) line 118 (`If tBodyClass '= ""`).
  - **Severity:** LOW (not a current bug — `MessageBodyClass` is written via property assignment in `RecordSuccess` lines 178/186, NOT via SQL UPDATE, so the `$Char(0)` legacy-null sentinel is structurally unreachable).
  - **Observation:** Per project rule §"`$Char(0)` sentinel — grep target for `%String` reads with SQL UPDATE write paths", any `%String` column whose write path includes SQL UPDATE returns `$Char(0)` from the OREF/SQL read site for rows that were updated to empty-string via SQL. `Build` reads `MessageBodyClass` and checks `If tBodyClass '= ""` to decide between the column value and the `CreatedVia` fallback. Today this is safe because `UserVocabulary.RecordSuccess` writes `MessageBodyClass` via `Set tRow.MessageBodyClass = pBodyClass` (property assignment, not SQL UPDATE). If a future story adds a SQL UPDATE write path against `MessageBodyClass` (e.g., a bulk-clear ZenMethod, a "reclassify alias" admin tool, an `_users`-style replication hook), this read site would silently treat `$Char(0)` as non-empty and push the literal one-char NUL into the rendered descriptor — producing baffling LLM output (`- "alias" — \x00 (confidence 0.50)`).
  - **Why deferred (Rule 8 review):** Test #3 — pure cosmetic at the moment with no current predicted-bug shape. The grep-target invariant is satisfied today (no SQL UPDATE write path against `MessageBodyClass`), so adding the `If tBodyClass = $Char(0) Set tBodyClass = ""` line now is pre-emptive defensive code. Per the rule's enforcement language, the line gets added the moment a SQL-UPDATE write path is introduced. Story 9.5 (`RecordClickThrough` ZenMethod) and Story 9.4 (first-turn prefix injection) do NOT introduce SQL UPDATE write paths against `MessageBodyClass`.
  - **Recommendation when picked up:** When a future story adds any SQL-UPDATE write path against `MessageBodyClass`, add the canonical normalization line below the `tBodyClass` read in `Build`:
    ```objectscript
    Set tBodyClass = tRs.%Get("mbc")
    If tBodyClass = $Char(0) Set tBodyClass = ""
    ```
    Same pattern applies to any other %String read in this class if the substrate's write path expands. Reviewer should grep `..ConfigAgent.* | tRs.%Get("...")` style reads across `SessionAgent.Search.*` at the time of expansion.
  - **Owner:** Whoever adds the first SQL-UPDATE write path against any `UserVocabulary` %String column.
  - **Blocking?** Not blocking — current write path is property-assignment only.

- **LOW-9.3-F02 — Token-cap branch in `Build` is structurally unreachable under current calibration.**
  - **Source:** Story 9.3 code review (Edge-Case-Hunter layer).
  - **File:** [`src/SessionAgent/Search/VocabularyDigest.cls`](../../src/SessionAgent/Search/VocabularyDigest.cls) lines 156-160 (`If tEstTokens > 1200 { Set tBudgetExceeded = 1 Quit }`).
  - **Severity:** LOW (code path is structurally unreachable given current calibration; no operator-observable defect; the AC-4 truncation marker still fires correctly via the row-count `MaxEntries` cap).
  - **Observation:** Each rendered row is `- "<Alias>" — <descriptor> (confidence X.XX)` ≈ 165 chars at maximum (`Alias` MAXLEN=512 — but operator-typed aliases are typically <50 chars; `MessageBodyClass` MAXLEN=128). Even at the worst-case 165 chars/row × 20 rows (`MaxEntries=20`) + ~35-char header = ~3,335 chars ÷ 4 ≈ 833 tokens. The `1,200` token cap is unreachable while `MaxEntries=20` and `MessageBodyClass MAXLEN=128`. The dev's `TestVocabularyDigestTokenCapEnforced` test acknowledges this in its docstring ("the marker fires from the row-count cap rather than the token cap, but either flavor satisfies AC-4's 'truncation marker present' contract"). The branch is therefore exercised at compile-time only; runtime coverage is 0% under current calibration constants.
  - **Why deferred (Rule 8 review):** Test #1 — genuine future-epic scope. The branch becomes runtime-reachable IF either calibration constant is bumped: `MaxEntries` from 20 to ≥30, OR `MessageBodyClass MAXLEN` from 128 to ≥256, OR a longer-descriptor variant (e.g., row-pinned schema description) is added. Until then the path is dead-code-by-reachability rather than dead-code-by-design — keeping it preserves the AC-4 contract for the moment of expansion. Adding a synthetic-MAXLEN test today would couple the test to current calibration without earning meaningful coverage.
  - **Recommendation when picked up:** When `MaxEntries`, `MessageBodyClass MAXLEN`, or descriptor-length grows enough to push the worst-case rendered digest past 1,200 tokens, add a test that injects a synthetic descriptor-string of exactly the boundary length and asserts both (a) the digest stops including rows when adding the next would exceed the cap, AND (b) the truncation marker fires with the correct "(N more aliases hidden)" count. Until then the row-count cap is the binding constraint and the existing `TestVocabularyDigestTokenCapEnforced` test gives sufficient AC-4 coverage.
  - **Owner:** Whoever bumps `MaxEntries` past 30, or `MessageBodyClass MAXLEN` past 256, or adds a longer-descriptor path.
  - **Blocking?** Not blocking — branch is unreachable under current calibration; AC-4 truncation marker is still empirically verified via the row-count cap path.
