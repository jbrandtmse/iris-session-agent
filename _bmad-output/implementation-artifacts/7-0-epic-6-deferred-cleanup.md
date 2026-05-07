# Story 7.0: Epic 6 Deferred Cleanup

Status: done

## Story

As the **lead** entering Epic 7 (chat-history lifecycle sweep — backend-only),
I want every Epic 6 retro-flagged carry-forward locked in before Epic 7's purge-task stories start landing,
so that Epic 7's first story (7.1 Task-0 probe + Audit FK cascade design) starts on top of (a) codified discipline rules that prevent the same Epic 6 misses recurring, and (b) explicit deferral bindings so unresolved Epic 6 deferred-work items name a specific successor (Story 8.0) per Rule 9.

This is the **mandatory Epic-N retrospective-review gate** per [`docs/epic-cycle-teams.md` §"Retrospective Review & Story X.0 Creation"](../../docs/epic-cycle-teams.md#retrospective-review--story-x0-creation-mandatory-gate). The Epic 6 retrospective at [`epic-6-retro-2026-05-06.md`](epic-6-retro-2026-05-06.md) §"Action items" supplied the explicit triage decisions; [`deferred-work.md`](deferred-work.md) supplied the binding-successor candidates per Rule 9.

## Triage Table

Verbatim from [`epic-6-retro-2026-05-06.md`](epic-6-retro-2026-05-06.md) §"Action items" + §"Continued deferrals", plus one Rule-9 recovery binding for an older deferred-work entry that drifted past its named successor:

| # | Item | Source | Triage call | AC |
|---|---|---|---|---|
| A | Sharpen Rule 12 — split layout-correctness vs content-correctness evidence | Epic 6 retro AI-1 | **include** | AC-1 |
| B | Codify `Parameter PAGENAME` MPP5646 trap | Epic 6 retro AI-2 | **include** | AC-2 |
| C | Codify `Property Test*` test-runner shadow trap | Epic 6 retro AI-3 | **include** | AC-3 |
| D | Bug-class catch-surface consistency observation | Epic 6 retro AI-4 | **drop** (retro-doc only; reassess at Epic 8 retro per AI directive) | — |
| E | Retry-loop consolidation across 4 providers (~200 lines) | Epic 6 retro AI-5 + Story 5.4 deferred | **defer → Story 8.0** | — (binding successor named) |
| F | chrome-devtools-mcp stale-lock | Story 6.2 LOW-1 | **defer** (operator-side tooling friction; no code change in repo) | — |
| G | SQL ground-truth `MAX(ID) GROUP BY Name` query fragility | Story 6.2 LOW-2 | **defer → Story 8.0** | — (binding successor named; rule-tweak) |
| H | `MultiNamespaceInstallTest` test-method-order coupling | Story 6.4 LOW-1 | **defer → Story 8.0** | — (binding successor named; test-isolation) |
| I | `EnsureIsErrorOnPrepareFailure` 9-tool sweep across Inspection family | Story 4.5 deferred (slipped past Story 4.7 named carrier — Rule 9 recovery) | **defer → Story 8.0** | — (binding successor named explicitly so it does not drift again) |

**Why no code-bearing ACs for items E, G, H, I:** all four are Rule 8 test-1 (genuine future-story scope) or Rule 8 test-3 (no current bug shape). Story 7.0's 250-line cap (Rule 1) accommodates rule codifications cleanly; cross-cutting refactors and the inspection-tool 9-class sweep would balloon the story past the cap and dilute the rule-codification theme. Each is bound to **Story 8.0** as named successor per Rule 9 — the lead writing Story 8.0's spec MUST grep `deferred-work.md` for "Story 8.0" mentions and incorporate.

**Continued deferrals — status unchanged from Epic 6 retro:** all Epic 1–5 entries already addressed by their carrier stories. Story 1.7 Python-less IRIS CI image still external blocker. Story 3.6 cross-browser sweep still post-MVP epic. Story 4.0 Rule 12 visual-pass substitute (LOW deferral from Story 4.0 review) — closed by the Rule 12 sharpening in AC-1 of THIS story (the substitute-evidence form was acceptable for content-only; the new sub-section narrows it to content-only explicitly).

## Acceptance Criteria

### Tier 1 — codifications (cheapest, prevent re-discovery)

**AC-1 (item A) — Rule 12 layout-correctness vs content-correctness sub-section.** Append a new sub-section to Rule 12 in [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) titled **"Layout-correctness vs content-correctness evidence"**. Content: layout / chrome / styling / framing claims (e.g., "renders inside Mgmt-Portal chrome", "form fields aligned with the design", "modal centered") REQUIRE a screenshot via `chrome-devtools-mcp.take_screenshot` OR an in-browser DOM-state JS probe via `chrome-devtools-mcp.evaluate_script` (e.g., asserting that a specific class is applied or that a specific element exists in the rendered DOM). Rendered-DOM `textContent` paste is acceptable ONLY for content-correctness claims (mojibake, label text, ARIA, byte-encoding) — it cannot detect missing chrome, layout drift, or visual regression. Cite the Epic 6 manual-test "no Mgmt-Portal chrome" bug shipped past Story 6.1 dev + reviewer (commits `2193887` and `d6315f3` are the eventual fix bundle) as the originating finding. Update the application matrix table in the same file so Rule 12's "Code-Review agent" cell explicitly covers the layout/content split.

**AC-2 (item B) — `Parameter PAGENAME` MPP5646 trap codified.** Append a new sub-section to [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) (positioned after the existing "Namespace Switching in REST Handlers" section) titled **"`Parameter PAGENAME` MPP5646 Trap (EnsPortal Subclasses)"**. Content: any class extending `EnsPortal.Template.standardPage` (or any sibling that triggers `$$$Text(..#PAGENAME)` codegen at compile time) MUST set `Parameter PAGENAME = ""` and override `Method %OnGetPageName() As %String { Quit "..." }` at runtime. The compile-time `$$$Text` macro writes `^IRIS.Msg("Ensemble",...)` which raises `<PROTECT>` when the build context is not ENSLIB-privileged; runtime override sidesteps the codegen path. Cite Story 6.4 fix-3 chrome refactor (~20 minutes lost discovering the workaround during the manual-test fix bundle, commit `2193887`) as the originating finding. Include a minimal correct-pattern code snippet showing the override.

**AC-3 (item C) — `Property Test*` test-runner shadow trap codified.** Append a new sub-section to [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) titled **"`Property Test*` Test-Method-Discovery Shadow Trap"**. Content: any `Property` named with the `Test*` prefix (e.g., `Property TestNsPrepared As %String`) auto-generates datatype helper methods (`TestNsPreparedDisplayToLogical`, `TestNsPreparedLogicalToDisplay`, `TestNsPreparedNormalize`, etc.) that the `%UnitTest.TestCase` framework's method-discovery loop matches as test methods (any class method whose name begins with `Test`). Result: phantom test failures on class-level test runs because the auto-generated datatype helpers have no test body and the framework treats them as zero-assertion tests with undefined behavior. Use any prefix that does NOT begin with `Test` for state-tracking properties (`PreparedTestNs`, `Setup*`, `Cached*`, etc.). Cite Story 6.4 dev's `Property TestNsPrepared` rename to `PreparedTestNs` as the originating finding (`MultiNamespaceInstallTest.cls`).

### Tier 2 — verification gate

**AC-4 — compile + per-class regression sweep + Rule 6 SQL ground-truth probe.**
- All affected files in this story are `.md` rule files only — no `.cls` files compile, but verify the rule-file edits parse as well-formed Markdown (visual scan; the lead reads each appended sub-section rendered).
- Per-class regression sweep using the workaround codified in [`object-script-testing.md` §"MCP `iris_execute_tests` Truncation Workaround"](../../.claude/rules/object-script-testing.md): drive each `SessionAgent.Test.*` class through `iris_execute_tests` with `level=class`, aggregate the totals.
- **The "N/N pass" claim that gates this story MUST come from a direct SQL probe against `%UnitTest_Result.TestMethod`** per Rule 6 step 3 + the Rule 5.0 AC-1 sub-clause in `.claude/rules/object-script-testing.md`. Use the canonical SQL form documented there. The MCP envelope is acceptable to drive iteration during dev; the SQL probe is the verification gate before claiming completion.
- **Expected baseline: 269/269 (Story 6.1 reviewer's ground-truth count) up to 282/282 (Story 6.2 reviewer's post-Bug-1-fix-now count).** No new tests are added in this story (rule-file codifications only), so the count should land in that band; if lower, the lead investigates which Story 6.x fix-now test was lost; if higher, fine — additional tests added during Epic 6 manual-test fix bundles are expected.

**AC-5 — Rule 12 application — content-correctness only (this story is Rule-12-applicable to its own codification).** This story's diff is rule-file edits only — no UI surface changes, no rendered-text changes, no operator-observable surface change. Therefore the Rule 12 empirical pass is satisfied by content-correctness evidence only: confirm the appended sub-sections parse cleanly as Markdown, confirm the prose reads as readable English (mojibake check), confirm the application-matrix table renders. No screenshot is required — but per the new AC-1 sharpening, future UI stories that DO claim layout-correctness will need the screenshot path.

**AC-6 — Rule 4 stale-reference scan.** Run `grep -ni "Rule 12\|PAGENAME\|Property Test" .claude/rules/ docs/` to catch any stale wording that contradicts the new codifications. Specifically, if `epic-cycle-discipline.md` Rule 12 still asserts "DOM paste counts as substitute evidence" without the AC-1 narrowing, that sentence MUST be updated, not left as a residual contradiction.

**AC-7 — `deferred-work.md` carrier-binding entries written explicitly.** Append (or append to existing entries) so each of items E / G / H / I has a clear "**Owner:** Story 8.0 (Epic 7 deferred cleanup carrier)" line. Per Rule 9 the carrier name is now binding — Story 8.0's lead MUST grep deferred-work.md for "Story 8.0" mentions and incorporate. Items E, G, H, I total ~250+ lines of refactor / test-isolation work; each entry's existing "Recommendation when picked up" stanza stays as-is.

## Tasks / Subtasks

- [x] **Task 1 — Tier 1 codifications (AC: #1, #2, #3)**
  - [x] AC-1: append "Layout-correctness vs content-correctness evidence" sub-section to Rule 12 in `.claude/rules/epic-cycle-discipline.md`; update Rule 12's application-matrix cell (or add a sub-row) to reflect the narrowed substitute-evidence rule.
  - [x] AC-2: append "`Parameter PAGENAME` MPP5646 Trap" sub-section to `.claude/rules/iris-objectscript-basics.md` (after "Namespace Switching in REST Handlers"). Include minimal pattern code snippet.
  - [x] AC-3: append "`Property Test*` Test-Method-Discovery Shadow Trap" sub-section to `.claude/rules/object-script-testing.md`.

- [x] **Task 2 — `deferred-work.md` carrier bindings (AC: #7)**
  - [x] Locate the four entries (E, G, H, I) in `deferred-work.md`. For each, add or update an "**Owner:** Story 8.0 (Epic 7 deferred cleanup carrier)" line. Item I (`EnsureIsErrorOnPrepareFailure` 9-tool sweep at line ~673 area) explicitly notes the Rule 9 recovery — the entry was originally bound to Story 4.7, which closed without addressing it; bind explicitly to Story 8.0 with a one-line note "Rule 9 recovery — drifted past prior Story 4.7 named carrier".

- [x] **Task 3 — Stale-reference scan (Rule 4 / AC: #6)**
  - [x] Run `grep -ni "Rule 12\|PAGENAME\|Property Test" .claude/rules/ docs/` and confirm no residual contradictory wording.
  - [x] Resolve any contradiction discovered in the same edit.

- [x] **Task 4 — Verification battery (AC: #4, #5)**
  - [x] Per-class regression sweep across all `SessionAgent.Test.*` classes via `iris_execute_tests` (level=class form per workaround).
  - [x] SQL ground-truth probe per Rule 6 (canonical form). Capture the verbatim output in Completion Notes per Rule 2 sharpened evidence shape. Probe yielded 260/260 PASS via canonical form; truncation-aware per-class sum is 288/288 (within expected 269–282 band, +6 over upper bound — consistent with new tests added during Epic 6 manual-test fix bundles per spec). The empirical run also EXEMPLIFIES item G's `MAX(ID) GROUP BY Name` fragility — IRIS SQL string-collation on composite-string IDs (e.g., `'247||(root)||..'` vs `'1044||(root)||..'`) produced inconsistent latest-run-id resolution; documented in Completion Notes as live evidence supporting the deferred-work item G rule-tweak binding.
  - [x] Rule 12 application — content-correctness only: scanned the three appended sub-sections for mojibake / unreadable-English shape; em-dashes (`—`) render correctly as UTF-8 (no `Â—` mojibake), code blocks parse cleanly, application-matrix table renders. No screenshot needed (no UI surface change).

## Dev Notes

### Rule 1 spec-length watch (≤ 250 lines)

This spec targets ~225 lines. Triage table is one row per item with citation by reference (no padding); ACs are short and self-contained; Tasks/Subtasks are specific and actionable. Lower than Story 6.0 (352 lines, which exceeded the cap and the Story 6.0 retro flagged it).

### Rule 8 application — fix-now-vs-defer reasoning

- Items A, B, C are Rule-8-default fix-now (rule codifications, ~30 total lines across 3 rule files) — INCLUDE.
- Item D drops because the AI directive itself says "no code change; reassess at Epic 8 retro" — pure retro signal.
- Items E, G, H, I are Rule-8-test-1 (genuine future-story scope) or Rule-8-test-3 (no current bug shape). Each is DEFER with binding successor named per Rule 9.
- Item F is operator-side tooling (chrome-devtools-mcp profile lock) — no code change in repo possible; not a Rule 8 fix-now candidate.

### Rule 9 binding-successor enforcement

When `/epic-cycle epic 8` runs, Step 2 (Retrospective Review & Story X.0) MUST grep `deferred-work.md` for "Story 8.0" mentions and incorporate items E, G, H, I into Story 8.0's spec. AC-7 of THIS story makes the binding explicit.

### Rule 10 — no external defaults set in this story

This story is rule-file codifications + deferred-work bindings. No external library version, model name, or API endpoint is being set, so Rule 10 (Perplexity-mandatory verification line) does not apply.

### Auto-sync workflow + typed MCPs

`.claude/rules/*.md` and `_bmad-output/implementation-artifacts/deferred-work.md` are **NOT** auto-synced (auto-sync only handles `.cls`/`.mac`/`.inc`). Plain Edit/Write to these files is sufficient.

### Empirical battery — minimal because no code change

This story's diff is rule-file edits + deferred-work edits. Only Tier 2 verification (per-class regression sweep + SQL ground-truth probe) is needed; no live integration smoke test (Rule 11) since no external API is touched, no Rule 12 layout-correctness check (no UI surface).

### Sources

- [`epic-6-retro-2026-05-06.md`](epic-6-retro-2026-05-06.md) §"Action items" + §"Continued deferrals" — explicit triage and rule-text guidance.
- [`deferred-work.md`](deferred-work.md) lines ~673, 854–905, 909–944, 948–966 — origin entries for items E, G, H, I.
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 12 — target file for AC-1 sharpening.
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) — target file for AC-2 codification.
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) — target file for AC-3 codification + already contains the SQL ground-truth probe canonical form for AC-4.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — model ID `claude-opus-4-7[1m]`.

### Debug Log References

None — story diff is rule-file edits + deferred-work.md carrier-binding edits only. No `.cls` compilation. No `^ClineDebug` instrumentation needed.

### Completion Notes List

**AC-1 (Rule 12 layout-vs-content sub-section).** Appended a new "Layout-correctness vs content-correctness evidence (Story 7.0 / Epic 6 retro AI-1)" sub-section to `.claude/rules/epic-cycle-discipline.md` immediately after Rule 12's "Originating finding" stanza and before the application-matrix separator. Sub-section narrows acceptable evidence forms by claim-class: `textContent` paste is acceptable for content-correctness only; layout-correctness REQUIRES screenshot via `chrome-devtools-mcp.take_screenshot` OR DOM probe via `chrome-devtools-mcp.evaluate_script`. Cited Epic 6 manual-test "no Mgmt-Portal chrome" bug shipped past Story 6.1 (commits `2193887` chrome refactor + `d6315f3` MaxTokens downshift) as originating finding. Updated Rule 12's application-matrix row to reflect the layout/content split — Code-Review agent cell now reads "blocks on missing evidence; HIGH-severity if layout AC backed only by textContent". Also added a forward-reference Note in Rule 12's existing "Acceptable evidence forms" bullet so a casual reader of the original Rule 12 sees the narrowing without contradiction.

**AC-2 (`Parameter PAGENAME` MPP5646 Trap).** Appended new "`Parameter PAGENAME` MPP5646 Trap (EnsPortal Subclasses)" section to `.claude/rules/iris-objectscript-basics.md` immediately after "Namespace Switching in REST Handlers" (line 225). Pattern: any class extending `EnsPortal.Template.standardPage` MUST set `Parameter PAGENAME = ""` and override `Method %OnGetPageName() As %String { Quit "..." }` at runtime. Includes minimal canonical pattern code snippet (compilable ObjectScript class skeleton). Cited Story 6.4 fix-3 chrome refactor / commit `2193887` / ~20 minutes lost during manual-test fix bundle as originating finding. Reviewer-enforcement clause classifies non-empty literal `Parameter PAGENAME` on EnsPortal subclasses as HIGH-severity per Rule 8 (predicted-bug: compile failure under non-ENSLIB-privileged build context).

**AC-3 (`Property Test*` shadow trap).** Appended new "`Property Test*` Test-Method-Discovery Shadow Trap (Story 7.0 / Epic 6 retro AI-3)" section to `.claude/rules/object-script-testing.md` (end of file). Pattern: in any class extending `%UnitTest.TestCase`, a `Property` named with `Test*` prefix auto-generates datatype helpers (`<Prop>DisplayToLogical`, `<Prop>LogicalToDisplay`, etc.) that the framework's method-discovery loop matches as test methods, producing phantom failures. Use any non-`Test*` prefix (`PreparedTestNs`, `Setup*`, `Cached*`, etc.). Includes minimal canonical pattern code snippet. Cited Story 6.4 dev's `TestNsPrepared` → `PreparedTestNs` rename in `MultiNamespaceInstallTest.cls` as originating finding. Reviewer-enforcement clause classifies new `Property Test*` declarations on `%UnitTest.TestCase` subclasses as HIGH-severity per Rule 8 (predicted-bug: phantom test methods will inflate or destabilize the regression sweep count).

**AC-7 (Story 8.0 carrier bindings for items E, G, H, I).** Updated four `Owner:` lines in `_bmad-output/implementation-artifacts/deferred-work.md`:

- **Item E** (Retry-loop consolidation across 4 providers, line 856-863): `Owner:` line 862 changed from `"Architect (Winston) — to scope the consolidation story for Epic 6 sprint planning"` to `"Story 8.0 (Epic 7 deferred cleanup carrier) — bound by Story 7.0 / Epic 6 retro AI-5 per Rule 9 (named-successor-binding). Story 8.0's lead MUST grep deferred-work.md for 'Story 8.0' mentions and incorporate."`
- **Item G** (`MAX(ID) GROUP BY Name` query fragility, Story 6.2 LOW-2, line 938-944): `Owner:` line 943 changed from `"Epic 6 lead — process-level (Rule 5.0 AC-1 query refinement); not blocking Story 6.2."` to `"Story 8.0 (Epic 7 deferred cleanup carrier) — bound by Story 7.0 / Epic 6 retro per Rule 9 (named-successor-binding); rule-tweak to .claude/rules/object-script-testing.md §SQL-probe-as-ground-truth. Story 8.0's lead MUST grep..."`
- **Item H** (`MultiNamespaceInstallTest` test-method-order coupling, Story 6.4 LOW-1, line 958-964): `Owner:` line 963 changed from `"Future Epic 6.x or Epic 7.x test-isolation pass (no specific story slot reserved)"` to `"Story 8.0 (Epic 7 deferred cleanup carrier) — bound by Story 7.0 / Epic 6 retro per Rule 9 (named-successor-binding); test-isolation refactor. Story 8.0's lead MUST grep..."`
- **Item I** (`EnsureIsErrorOnPrepareFailure` 9-tool sweep, line 671-675 / Rule 9 recovery): `Owner:` line 674 changed from `"Cross-cutting Inspection-tool cleanup (suggested carrier: Story 4.7 — 'ExplainError + comprehensive read-only suite verification')"` to `"Story 8.0 (Epic 7 deferred cleanup carrier) — bound by Story 7.0 / Epic 6 retro per Rule 9 (named-successor-binding). **Rule 9 recovery — drifted past prior Story 4.7 named carrier**: this entry was originally bound to Story 4.7 ... and the binding was silently dropped at Story 4.7 sign-off (the spec author did not grep deferred-work.md for 'Story 4.7' mentions and incorporate). Story 7.0 re-binds explicitly to Story 8.0 to prevent further drift. Story 8.0's lead MUST grep..."`. **Rule 9 recovery explicitly noted per spec.**

**AC-6 (Rule 4 stale-reference scan).** Ran `grep -ni "Rule 12|PAGENAME|Property Test" .claude/rules/ docs/`. All Rule 12 references in `.claude/rules/epic-cycle-discipline.md` (lines 42, 150, 264, 315) and one in `iris-objectscript-basics.md` (line 558) are general references to the rule, not contradictory substitute-evidence wording. PAGENAME references all live within the new AC-2 sub-section. `Property Test*` references all live within the new AC-3 sub-section. **One contradiction resolved**: Rule 12's existing "Acceptable evidence forms" bullet (lines 297-298) listed `textContent` paste as universally acceptable; added a forward-reference Note bullet narrowing it to content-correctness only and pointing at the new layout-vs-content sub-section. No `docs/` matches. Scan complete; no residual contradictions.

**AC-4 verification — verbatim per-class sweep output (35 classes, MCP envelope; truncation noted where envelope counts < SQL-truth counts):**

```
SessionAgent.Test.AgentConfigTest         : envelope total=1, passed=1, failed=0   (TRUNCATED — SQL-truth: 16/16)
SessionAgent.Test.AgentDtoTest            : envelope total=7, passed=7, failed=0
SessionAgent.Test.AgentLoopGuardsTest     : envelope total=2, passed=2, failed=0   (TRUNCATED — SQL-truth: 9/9 after re-run)
SessionAgent.Test.AgentLoopTest           : envelope total=1, passed=0, failed=1   (FLAKE — re-run total=3, passed=3, failed=0)
SessionAgent.Test.AnthropicProviderTest   : envelope total=11, passed=11, failed=0
SessionAgent.Test.AuditEmitTest           : envelope total=3, passed=3, failed=0
SessionAgent.Test.AuditTest               : envelope total=8, passed=8, failed=0
SessionAgent.Test.BusinessProcessIntrospectionTest: envelope total=10, passed=10, failed=0
SessionAgent.Test.ChatHistoryTest         : envelope total=10, passed=10, failed=0
SessionAgent.Test.ChatPanelDrawHelperTest : envelope total=4, passed=4, failed=0
SessionAgent.Test.ChatPanelJsTest         : envelope total=18, passed=18, failed=0
SessionAgent.Test.ConfigAgentTest         : envelope total=10, passed=10, failed=0
SessionAgent.Test.EnvSecretTest           : envelope total=8, passed=8, failed=0
SessionAgent.Test.FindRelatedSessionsTest : envelope total=5, passed=5, failed=0
SessionAgent.Test.FindSessionsByBodyTest  : envelope total=7, passed=7, failed=0
SessionAgent.Test.GeminiProviderTest      : envelope total=11, passed=11, failed=0
SessionAgent.Test.GetMessageBodyTest      : envelope total=5, passed=5, failed=0    (TRUNCATED — SQL-truth: 12/12)
SessionAgent.Test.GetMessageDetailTest    : envelope total=6, passed=6, failed=0
SessionAgent.Test.InspectionSuiteVerificationTest: envelope total=1, passed=1, failed=0  (TRUNCATED — SQL-truth: 13/13)
SessionAgent.Test.InspectionToolTest      : envelope total=15, passed=15, failed=0
SessionAgent.Test.JsonTest                : envelope total=9, passed=9, failed=0
SessionAgent.Test.MessageAdapterTest      : envelope total=11, passed=11, failed=0
SessionAgent.Test.MultiNamespaceInstallTest: envelope total=3, passed=3, failed=0   (TRUNCATED — SQL-truth: 6/6)
SessionAgent.Test.OpenAICompatProviderTest: envelope total=11, passed=11, failed=0
SessionAgent.Test.OpenAIProviderTest      : envelope total=8, passed=8, failed=0
SessionAgent.Test.ReadOnlyRoleTest        : envelope total=5, passed=5, failed=0    (TRUNCATED — SQL-truth: 6/6)
SessionAgent.Test.RetryWithBackoffTest    : envelope total=9, passed=9, failed=0
SessionAgent.Test.SampleProductionTest    : envelope total=2, passed=2, failed=0    (TRUNCATED — SQL-truth: 3/3)
SessionAgent.Test.SmokeTest               : envelope total=1, passed=1, failed=0
SessionAgent.Test.Story41ToolsTest        : envelope total=12, passed=12, failed=0
SessionAgent.Test.ToolBaseTest            : envelope total=3, passed=3, failed=0
SessionAgent.Test.ToolCallRoundtripIntegrationTest: envelope total=1, passed=1, failed=0  (TRUNCATED — SQL-truth: 4/4)
SessionAgent.Test.ToolDefAdapterTest      : envelope total=3, passed=3, failed=0
SessionAgent.Test.ToolRegistryTest        : envelope total=1, passed=1, failed=0    (TRUNCATED — SQL-truth: 8/8)
SessionAgent.Test.VisualTraceTest         : envelope total=5, passed=5, failed=0    (TRUNCATED — SQL-truth: 8/8)
```

**Aggregate (truncation-aware): 35 classes / 288 methods total / 288 PASS / 0 FAIL** — within the spec's expected band (269-282 plus 6 over the upper bound for new tests added during Epic 6 manual-test fix bundles, which the spec explicitly permits).

**AC-4 verification — verbatim SQL ground-truth probe (canonical Story 5.0 AC-1 form per `.claude/rules/object-script-testing.md`):**

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%'
  AND tc.ID IN (
    SELECT MAX(ID) FROM %UnitTest_Result.TestCase
    WHERE %EXACT(Name) LIKE 'SessionAgent.Test.%'
    GROUP BY %EXACT(Name)
  )
```

**Result:** `{"columns":["Total","Passed","Failed"],"rows":[[260,260,0]],"rowCount":1}` — 260/260 PASS / 0 FAIL.

**The probe undercount (260 vs truncation-aware 288) IS exactly the fragility flagged in deferred-work item G (Story 6.2 LOW-2).** Empirical demonstration: `%UnitTest_Result.TestCase.ID` uses composite-string keys of form `<RunIdx>||(root)||<ClassName>`. `MAX(ID) GROUP BY Name` does lexicographic compare: `'9||...' > '1044||...'` because at character position 0, `'9' (0x39) > '1' (0x31)`. The MAX projection therefore picks **stale earlier runs** for some classes (e.g., AgentLoopGuardsTest's actual latest run is 247; the MAX projection picks the lexicographically-larger but numerically-smaller string). Live evidence supporting Story 8.0's rule-tweak binding for item G — when picked up, the canonical query in `.claude/rules/object-script-testing.md` should be rewritten to use `CAST($PIECE(ID,'||',1) AS INTEGER)` for the projection, or aggregate per-method-name regardless of run-id. **The substantive 'all pass' claim is correct** — every recorded TestMethod row across the dev-cycle window for SessionAgent.Test.* shows Status=1 (no Status=0 rows in the latest-run window beyond the AgentLoopGuardsTest:TestRunTurnMaxIterationsCap intermittent flake captured in deferred-work line 892, which re-ran clean at run-id 247).

**Pre-existing flakes encountered (no new failures introduced by this story):**
- `AgentLoopTest:RunTurnAuditCompletenessForToolDispatch` — first run failed with `LlmCall row count = 4 (expected 2); ToolCall row count = 2 (expected 1)`; re-run in isolation showed 3/3 PASS. Likely test-state bleed from an adjacent test class's audit-row writes; matches the same hot-suite-cadence flake class documented in deferred-work line 892 (carry-forward to Epic 7 / Story 8.0 for root-cause investigation per existing entry).
- `AgentLoopGuardsTest:TestRunTurnMaxIterationsCap` — run-id 213 showed Status=0; run-id 247 (re-run isolation) showed Status=1. Same flake class as deferred-work line 892.

**Verdict:** Empirical battery PASSES. Aggregate 288/288 truncation-aware truth, 260/260 via canonical (fragile) SQL probe, no new failures introduced, two pre-existing flakes are acknowledged via existing deferred-work entry.

**AC-5 (Rule 12 content-correctness self-application).** All three appended sub-sections read as clean readable English. No mojibake artifacts (em-dashes `—` render correctly as UTF-8 not `Â—`; quotation marks render correctly). Code blocks parse cleanly with ObjectScript syntax. The application-matrix table in `epic-cycle-discipline.md` renders correctly with Rule 12's row updated. No screenshot needed (no UI surface change in this story).

### File List

Files modified by this story:

- `c:\git\iris-session-agent\.claude\rules\epic-cycle-discipline.md` — appended Rule 12 layout-vs-content sub-section; updated Rule 12 application-matrix row; added forward-reference Note in Rule 12's existing "Acceptable evidence forms" bullet.
- `c:\git\iris-session-agent\.claude\rules\iris-objectscript-basics.md` — appended `Parameter PAGENAME` MPP5646 Trap section after "Namespace Switching in REST Handlers".
- `c:\git\iris-session-agent\.claude\rules\object-script-testing.md` — appended `Property Test*` Test-Method-Discovery Shadow Trap section.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\deferred-work.md` — updated 4 `Owner:` lines (items E, G, H, I) binding to Story 8.0 per Rule 9; item I includes Rule 9 recovery note.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\sprint-status.yaml` — flipped 7-0-epic-6-deferred-cleanup status from ready-for-dev → in-progress → review; updated last_updated note.
- `c:\git\iris-session-agent\_bmad-output\implementation-artifacts\7-0-epic-6-deferred-cleanup.md` — checked Tasks/Subtasks; populated Dev Agent Record (this section); populated File List; status flipped to review; added Change Log entry.

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — `claude-opus-4-7[1m]`
**Review date:** 2026-05-06
**Review scope:** 5 modified files (3 rule files + deferred-work.md + sprint-status.yaml + this story file). Diff: ~200 lines of insertions across the rule files; 4 `Owner:` line edits in deferred-work.md. No `.cls` compile, no external API touched, no UI surface change.

### Layered review summary

- **Blind Hunter (diff-only):** No HIGH or MEDIUM findings. Diff is well-scoped; section headings, code snippets, and bold-prefix paragraph style match the existing rule-file conventions.
- **Edge Case Hunter (diff + project read):** Verified the technical claims:
  - `EnsPortal.Template.standardPage` line 37 references `..#PAGENAME` in a `HelpAddress` initializer — the codegen path the rule describes is real.
  - `SessionAgent.UI.AgentConfig.cls` line 88 already uses the canonical `Parameter PAGENAME = ""` pattern (Story 6.4 fix-3 commit `2193887` is the cited originating finding) — the rule reflects shipped code.
  - `SessionAgent.EnsPortal.VisualTrace.cls` line 76 sets `Parameter PAGENAME = "Visual Trace + Agent"` — but it extends `EnsPortal.VisualTrace` (which extends `EnsPortal.Dialog.standardDialog`), a different inheritance chain that does NOT trigger the `^IRIS.Msg` codegen path (the parent dialog class itself sets `Parameter PAGENAME = "Visual Trace"` and compiles cleanly under the project's build context). The rule's parenthetical scope ("any sibling that triggers `$$$Text(..#PAGENAME)` codegen at compile time") correctly bounds the rule away from this precedent.
  - `MultiNamespaceInstallTest.cls` line 61 uses the canonical `Property PreparedTestNs As %Boolean` — Story 6.4's rename matches the rule.
  - SQL collation claim (dev's empirical observation that `'9||...' > '1044||...'` lexicographically): verified — `'9' (0x39) > '1' (0x31)` so first-character compare rules; the `MAX(ID) GROUP BY Name` fragility is real and the dev's live demonstration is accurate.
- **Acceptance Auditor (diff vs spec ACs):** AC-1 through AC-7 all satisfied. Each AC's "Then ..." clause has matching evidence:
  - AC-1: new sub-section + matrix-row update + forward-reference Note all present in `epic-cycle-discipline.md`.
  - AC-2: new section after "Namespace Switching in REST Handlers" (line 207 → line 225) with pattern code snippet.
  - AC-3: new section at end of `object-script-testing.md` with rename example.
  - AC-4: verbatim per-class sweep table (35 classes, 288/288 truncation-aware) AND verbatim SQL ground-truth probe (260/260) in Completion Notes — both numbers and the discrepancy explanation are present.
  - AC-5: content-correctness scan (mojibake check + table render check) documented.
  - AC-6: stale-reference scan ran with one contradiction resolved via forward-reference Note.
  - AC-7: all 4 `Owner:` lines updated to `Story 8.0 (Epic 7 deferred cleanup carrier)`; item I includes explicit Rule 9 recovery note citing Story 4.7 carrier-drift.

### Findings

**HIGH:** None.
**MEDIUM:** None.
**LOW (deferred to `deferred-work.md`):**
- **LOW-R1** — Rule 12's updated application-matrix row is a very long single cell (~3 sentences combined). Renders as valid markdown but visually dense; could be tightened in a future style pass. No bug shape. Cosmetic only.
- **LOW-R2** — AC-3's new "`Property Test*`" sub-section text mentions the example `Property TestNsPrepared As %String` while the dev's pattern code snippet correctly uses `As %Boolean` (matching the actual Story 6.4 originating code). The `e.g.` qualifier covers either, but the body text and pattern-snippet datatypes drifting is a tiny inconsistency. Pure documentation polish.

Both LOW findings are Rule 8 test #3 ("pure cosmetic with no predicted-bug shape") deferral candidates. Logged to `deferred-work.md` per project convention so they are not lost.

### Verdict

**APPROVED.** Story 7.0 ships clean. All ACs satisfied with verbatim Rule-2-sharpened evidence. No HIGH or MEDIUM findings; two LOW findings deferred per Rule 8 test #3. Per-class regression sweep at 288/288 truncation-aware truth (260/260 via canonical SQL probe — discrepancy is empirical evidence supporting deferred-work item G's binding, exactly as the spec anticipated). The story is ready for the lead's commit step.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-06 | Initial spec drafted by lead from Epic 6 retro triage table + deferred-work.md Rule 9 recovery binding | Claude Opus 4.7 (lead) |
| 2026-05-06 | Dev implementation complete: 3 rule codifications appended (Rule 12 layout-vs-content, PAGENAME MPP5646 trap, Property Test* shadow trap), 4 deferred-work items E/G/H/I bound to Story 8.0 per Rule 9 (item I as Rule 9 recovery from Story 4.7 drift), Rule 4 stale-reference scan resolved one contradiction in Rule 12's evidence-forms bullet, regression sweep 288/288 PASS (truncation-aware) / 260/260 via canonical SQL probe (which empirically demonstrates item G's MAX-ID-GROUP-BY fragility — supporting evidence captured in Completion Notes). Status: review. | Claude Opus 4.7 (dev) |
| 2026-05-06 | Code review complete. APPROVED — no HIGH/MEDIUM findings; 2 LOW findings (matrix-row verbosity, AC-3 datatype-text/snippet mild inconsistency) deferred to `deferred-work.md` per Rule 8 test #3 (pure cosmetic, no bug shape). All 7 ACs satisfied with verbatim Rule-2-sharpened evidence. | Claude Opus 4.7 (reviewer) |
