# Story 7.1: Task-0 Probe + Audit FK Cascade Design

Status: done

## Story

As a **developer preparing the inspection chat-history sweep** (Stories 7.2 + 7.3),
I want a verified Task-0 probe of `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionId)` SQLCODE semantics on a live IRIS 2024.1+ instance, plus a documented design decision on whether `Audit.LlmCall` and `Audit.ToolCall` FK references to `Chat.History` cascade-delete or are scrubbed by the sweep task itself,
So that Story 7.2's sweep task can rely on a verified existence-check primitive and a clear cascade contract per architecture §"Carry-forward Task-0 probes" Epic 7 (line 1331) and NFR-SC4 (audit-volume bound by sweep cascade).

## Acceptance Criteria

**AC-1 — Task-0 probe SQLCODE semantics captured verbatim.** Execute `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionId)` against the live `HSCUSTOM` namespace via `iris_execute_classmethod` (or a temporary helper class method per project rule "execute_classmethod only works with CLASS METHODS") with two cases:
- (a) `pSessionId` set to a known-existing session id (use a fresh row from `SELECT TOP 1 SessionId FROM Ens.MessageHeader ORDER BY %ID DESC` — the sample production has been Bootstrap-installed per Epic 6 retro readiness assessment).
- (b) `pSessionId` set to a guaranteed-non-existing session id (e.g., `"DOES_NOT_EXIST_99999999"`).
Capture the resulting `SQLCODE` value verbatim from each case in this story's **Completion Notes** (per Rule 2 sharpened evidence shape).

**AC-2 — Probe outputs match expected; if not, escalate.** Expected: case (a) returns `SQLCODE=0` (row exists); case (b) returns `SQLCODE=100` (no row). If either differs from the expected, the dev MUST escalate to the lead via clarification message and Story 7.2's sweep-task existence-check is redesigned.

**AC-3 — Audit FK cascade design decision recorded — Option B selected.** Document in Completion Notes that **Option B** (sweep task explicitly deletes audit rows referencing the chat-history row before deleting the chat-history row itself) is the chosen approach. Reasoning chain MUST cite all three of the following:
1. **Storage shape match.** `Audit.LlmCall.ChatHistoryId` and `Audit.ToolCall.ChatHistoryId` are declared as `%String` (not typed `%Persistent` references — verified empirically: read [`src/SessionAgent/Audit/LlmCall.cls:55`](../../src/SessionAgent/Audit/LlmCall.cls#L55) and [`src/SessionAgent/Audit/ToolCall.cls:54`](../../src/SessionAgent/Audit/ToolCall.cls#L54)). True foreign-key cascade DELETE (Option A) would require either typed-reference conversion OR a `%Relationship` declaration — both are schema migrations; both break Story 2.5's chosen storage shape.
2. **NFR-SC4 audit-volume bound preserved.** Option B preserves the bound (audit rows go away with chat rows during the sweep); Option C breaks it.
3. **Consistency with Topic-10 Option B chat-history sweep pattern** — operationally consistent (the sweep task owns all cleanup; one task class, one schedule entry, one audit-event emission per run per architecture §"Audit event triples" line 387).

Option A and Option C are documented as rejected with one-line rationale each.

**AC-4 — Architecture sentence added.** Append a single sentence to architecture.md §"Audit-log volume" (the row at line 1039) OR the §"Persistence-Layer Volume Notes" entry at line 994 (whichever the dev judges semantically clearer — note both as candidate sites in the story; the line that already says *"Volume bounded by chat-history sweep cascade (NFR-SC4)"* is the natural anchor). Suggested wording: *"Cascade implementation per Story 7.1 Option B: the sweep task deletes audit rows referencing the chat-history row before deleting the chat-history row itself (storage-shape `%String` ChatHistoryId precludes true FK cascade DELETE without a Story 2.5 schema migration)."*

**AC-5 — Story 7.2 implementation hint pre-recorded.** Add a one-paragraph "Implementation hint for Story 7.2" stanza to this story's Dev Notes naming the specific work the sweep task will need to do per Option B:
- For each orphaned `Chat.History` row, first `DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?` and `DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?` (parameterized prepare per project rule "Search-Arg-Construction Safety").
- Then delete the `Chat.History` row.
- Note that neither `Audit.LlmCall` nor `Audit.ToolCall` currently declares an `Index` on `ChatHistoryId` (verified by grep at `src/SessionAgent/Audit/{LlmCall,ToolCall}.cls`). Story 7.2 must decide whether to add the indexes (preferred — sweep is O(orphans × log(audit_size)) instead of O(orphans × audit_size)) OR document the trade-off as accepted (`PurgeOrphanedChatHistory` runs daily off-peak so a full audit-table scan per orphan-row may still be acceptable for small audit volumes).

**AC-6 — Verification gate.** No `.cls` file is modified in this story (probe + design decision only). If the dev judges that adding the `ChatHistoryId` indexes to `Audit.LlmCall` and `Audit.ToolCall` belongs in this story (Rule 8 fix-now: predicted-bug shape — sweep performance degradation is genuinely predicted), the dev may include them with their own `iris_doc_compile` cycle. Per-class regression sweep + SQL ground-truth probe per Rule 6 step 3 / Story 5.0 AC-1 canonical SQL form. Expected count band: 288/288 (Story 7.0 baseline) ± any new test methods added.

## Tasks / Subtasks

- [x] **Task 1 — Task-0 probe execution (AC: #1, #2)**
  - [x] Verify sample-production state via `Ens.Director.IsProductionRunning` per Epic-cycle Step 1 verification probe (Rule 7 sub-clause). If 0, run `Bootstrap.Install` + `StartProductionIfStopped` + at least one `RunScenario` then re-verify.
  - [x] Pull a known-existing `SessionId` via `iris_sql_execute`: `SELECT TOP 1 %EXACT(SessionId) FROM Ens.MessageHeader ORDER BY %ID DESC`. Record verbatim.
  - [x] Execute the probe via `iris_execute_classmethod` (build a temporary helper that runs the embedded SQL) — case (a) with the captured SessionId, case (b) with `"DOES_NOT_EXIST_99999999"`. Capture both `SQLCODE` values verbatim into Completion Notes.
  - [x] Verify case (a) returns SQLCODE=0; case (b) returns SQLCODE=100. Per project rule "Storage Sections", drop the temporary helper class after probe completes.

- [x] **Task 2 — Audit FK cascade design decision documentation (AC: #3)**
  - [x] Verify storage shape empirically: read [`src/SessionAgent/Audit/LlmCall.cls:55`](../../src/SessionAgent/Audit/LlmCall.cls#L55) (`Property ChatHistoryId As %String;`) and [`src/SessionAgent/Audit/ToolCall.cls:54`](../../src/SessionAgent/Audit/ToolCall.cls#L54) (same shape).
  - [x] Document Option B selection in Completion Notes with the 3-point reasoning chain (storage shape, NFR-SC4, Topic-10 consistency).
  - [x] Document Option A rejection: would require schema migration of Story 2.5's chosen storage shape (typed reference or `%Relationship`); breaks the "FK shape" doc-comment in `LlmCall.cls:21` ("Story 2.6 may add a calculated property or relationship to navigate the link without changing this storage shape" — explicitly preserves `%String`).
  - [x] Document Option C rejection: would break NFR-SC4 audit-volume bound; would require a separate audit-volume management strategy (not in scope for v1).

- [x] **Task 3 — Architecture.md sentence (AC: #4)**
  - [x] Append the Option-B cascade sentence to [`_bmad-output/planning-artifacts/architecture.md`](../planning-artifacts/architecture.md) line 994 (Persistence-Layer Volume Notes — Audit row) — the natural anchor since that line already cites NFR-SC4. Verify the appended sentence reads as readable English in the rendered Markdown (Rule 12 content-correctness check).

- [x] **Task 4 — Implementation hint stanza (AC: #5)**
  - [x] Add the "Implementation hint for Story 7.2" stanza to this story's Dev Notes. Cover: (a) the per-orphan delete sequence (audit rows first, then Chat.History row); (b) the parameterized prepare requirement; (c) the missing `ChatHistoryId` index trade-off and Story 7.2's decision.

- [x] **Task 5 — Stale-reference scan (Rule 4 / AC: #6)**
  - [x] `grep -ni "PurgeOrphanedChatHistory\|ChatHistoryId\|FK cascade\|NFR-SC4" .claude/rules/ docs/ src/SessionAgent/ _bmad-output/planning-artifacts/` — confirm no contradictory wording across canonical docs. Resolve any contradiction in the same edit.

- [x] **Task 6 — Verification battery (AC: #6)**
  - [x] No `.cls` files in scope unless Task 5 surfaces a fix-now indexing recommendation; if not, skip compile step.
  - [x] Per-class regression sweep using the `object-script-testing.md` truncation workaround. Expected band: 288/288 ± any new tests.
  - [x] Capture verbatim SQL ground-truth probe per Rule 6 / Story 5.0 AC-1 canonical form into Completion Notes.

## Dev Notes

### Rule 1 spec-length watch

This spec targets ~165 lines. Lower than Story 4.0 (~225) and 6.0 (352), and cleanly under the 250-line cap. Triage-style structure (Task-0 probe → design decision → architecture sentence → implementation hint → verification) keeps each AC self-contained.

### Rule 3 higher-level MCP first

- For the SQLCODE probe, use `iris_execute_classmethod` against a temporary helper class (Story 4.0 pattern). `iris_sql_execute` does NOT return raw `SQLCODE` — it returns rows or an error envelope; the embedded SQL form via `&sql(...) ... SQLCODE` is the contract being verified, so the helper-class form is the right tool.
- For pulling the existing SessionId in Task 1: `iris_sql_execute` is preferred over `iris_execute_command`.
- For verifying sample-production state: `iris_execute_classmethod` against `Ens.Director.IsProductionRunning` is the canonical probe.

### Rule 7 sub-clause (sample-production state at Step 1)

The Epic 7 cycle's Step 1 sprint-planning DID verify sample-production state implicitly via the Epic 6 retro readiness assessment (line 138: "Sample production state ✅ INSTALLED + RUNNING. Sessions 3482, 5133 available."). Story 7.1's dev should re-verify in Task 1 anyway since several days of cycle resumes may have intervened.

### Rule 10 — no external defaults set

This story sets no library version, model name, or API endpoint. Rule 10 (Perplexity-mandatory verification line) does not apply.

### Audit FK current state — stored as %String

[`src/SessionAgent/Audit/LlmCall.cls:21-27`](../../src/SessionAgent/Audit/LlmCall.cls#L21-L27) explicitly documents the `%String`-not-typed-FK choice: *"Story 2.6 may add a calculated property or relationship to navigate the link without changing this storage shape."* This is a deliberate Story 2.5 design constraint that Story 7.1's Option B selection preserves — Option A would require breaking that constraint.

### Implementation hint for Story 7.2 (pre-recording per AC-5)

Story 7.2's `OnTask()` per-orphan loop pseudocode (Option B):

```objectscript
; For each orphaned chat-history row id (where Ens.MessageHeader.SessionId no longer exists):
;   1. DELETE FROM SessionAgent_Audit.LlmCall WHERE ChatHistoryId = ?  (parameterized prepare)
;   2. DELETE FROM SessionAgent_Audit.ToolCall WHERE ChatHistoryId = ?  (parameterized prepare)
;   3. DELETE FROM SessionAgent_Chat.History WHERE %ID = ?  (or .%DeleteId)
; Emit one audit event per OnTask run summarizing {orphans_deleted, llm_audit_deleted, tool_audit_deleted, scan_time_ms}.
```

Sub-decision Story 7.2 will need to settle: add `Index ChatHistoryIdIdx On ChatHistoryId` to `Audit.LlmCall` + `Audit.ToolCall` so the DELETEs are indexed (preferred — sweep performance scales with orphan count, not audit-table size). Without the index, each per-orphan DELETE pair triggers a full audit-table scan; for small audit volumes this is acceptable, but Story 7.3's 1,000-session integration test will surface the cost. Story 7.2 should include a decision note in its spec.

### Sources

- [`epics.md` Epic 7 Story 7.1 ACs](../planning-artifacts/epics.md) (lines extracted in retro pre-flight).
- [`architecture.md` line 1331](../planning-artifacts/architecture.md) — Carry-forward Task-0 probe entry for Epic 7.
- [`architecture.md` line 1039 / 994](../planning-artifacts/architecture.md) — NFR-SC4 mapping + Persistence-Layer Volume Notes; AC-4 target site.
- [`architecture.md` line 387](../planning-artifacts/architecture.md) — Audit event triples (`SessionAgent` / `TaskRun` / `<task_name>`).
- [`prd.md`](../planning-artifacts/prd.md) — FR44 (chat-history lifecycle), NFR-R2 (purge integrity), NFR-SC4 (audit-volume bound).
- [`src/SessionAgent/Audit/LlmCall.cls:21-27, 55`](../../src/SessionAgent/Audit/LlmCall.cls) — `%String` storage shape doc + property declaration.
- [`src/SessionAgent/Audit/ToolCall.cls:50-54`](../../src/SessionAgent/Audit/ToolCall.cls) — same shape.
- [`src/SessionAgent/Installer.cls:110, 316-388`](../../src/SessionAgent/Installer.cls) — `ScheduleTaskIfClassExists` defensive scheduler hook (Story 7.2 will trigger this once the task class exists).
- [`.claude/rules/iris-objectscript-basics.md`](../../.claude/rules/iris-objectscript-basics.md) §"IRIS SQL Case Sensitivity" (`%EXACT()` use), §"Pattern Replication Completeness".
- [`.claude/rules/object-script-testing.md`](../../.claude/rules/object-script-testing.md) §"SQL-probe-as-ground-truth for test-pass verification" (Rule 6 sub-clause).
- [`.claude/rules/epic-cycle-discipline.md`](../../.claude/rules/epic-cycle-discipline.md) Rule 2 sharpened (verbatim AC-contract evidence), Rule 7 sub-clause (sample-production state probe).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (1M context) — dev agent invoked via `/epic-cycle` Story 7.1 worktree.

### Debug Log References

- `iris_execute_classmethod` against `Ens.Director.IsProductionRunning` — initial probe returned 0 (production stopped); started via `SessionAgent.Sample.Bootstrap.StartProductionIfStopped`, re-probe returned 1.
- `iris_doc_put` deployed temporary `SessionAgent.TempProbe.SessionIdExistenceProbe.cls` (NOT in `src/`, lives only on IRIS side per "iris_doc_put = throwaway test classes only" project rule); `iris_doc_compile` clean (50ms); two probe invocations; `iris_doc_delete` removed it; `%Dictionary.ClassDefinition.%ExistsId` returned 0 confirming removal.
- Package-runner `iris_execute_tests target=SessionAgent.Test level=package` JSON envelope truncated to 22 methods (just `AgentConfigTest` + `AgentDtoTest`); SQL ground-truth probe against TestInstance ID 248 returned full 288/288 (the run executed all 35 classes; envelope truncation per `object-script-testing.md` workaround). `MAX(ID)` lexical-sort caveat noted: query `WHERE tc.ID %STARTSWITH '248||'` is the unambiguous form for "latest run" verification.

### Completion Notes List

**AC-1 / AC-2 — Task-0 SQLCODE probe outputs (verbatim).** Probe class: temporary `SessionAgent.TempProbe.SessionIdExistenceProbe` (deployed via `iris_doc_put`, compiled clean, deleted after both cases ran). Probe method body:
```objectscript
ClassMethod Probe(pSessionId As %String) As %String
{
    Set exists = ""
    &sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :pSessionId)
    Quit "SQLCODE=" _ SQLCODE _ ";exists=" _ exists
}
```

- **Case (a) — existing SessionId.** Pulled `SELECT TOP 1 %EXACT(SessionId) FROM Ens.MessageHeader ORDER BY %ID DESC` → `5294`. Probe call: `Probe("5294")` returned `"SQLCODE=0;exists=1"` — **SQLCODE=0 verbatim**, row found (host variable `exists` populated with the literal `1` from the SELECT).
- **Case (b) — non-existing SessionId.** Probe call: `Probe("DOES_NOT_EXIST_99999999")` returned `"SQLCODE=100;exists="` — **SQLCODE=100 verbatim**, no row found (host variable `exists` remained at its initialized `""`).

Both cases match the AC-2 expected values. AC-1 + AC-2 satisfied; the existence-check primitive is ready for Story 7.2's per-orphan loop.

**AC-3 — Audit FK cascade design decision: Option B selected.** Three-point reasoning chain:

1. **Storage shape match.** Verified empirically by reading [`src/SessionAgent/Audit/LlmCall.cls:55`](../../src/SessionAgent/Audit/LlmCall.cls#L55) (`Property ChatHistoryId As %String;`) and [`src/SessionAgent/Audit/ToolCall.cls:54`](../../src/SessionAgent/Audit/ToolCall.cls#L54) (same `Property ChatHistoryId As %String;`). The doc-comment in `LlmCall.cls:21-27` explicitly preserves the `%String` shape: *"Story 2.6 may add a calculated property or relationship to navigate the link without changing this storage shape."* True FK cascade DELETE (Option A) would require either typed-reference conversion OR a `%Relationship` declaration — both are schema migrations; both break Story 2.5's deliberate storage choice.
2. **NFR-SC4 audit-volume bound preserved.** Option B preserves the bound (audit rows go away with chat rows during the daily sweep, per architecture.md line 994 NFR-SC4 anchor); Option C breaks it (dangling-FK rows accumulate).
3. **Topic-10 Option B operational consistency.** The chat-history sweep already follows Topic-10 Option B (sweep task owns all cleanup; one task class, one schedule entry, one audit-event emission per run per architecture.md line 387 audit-event triple `(SessionAgent, TaskRun, PurgeOrphanedChatHistory)`). Option B for Audit cascade extends the same operational pattern — the sweep task that owns chat-row deletion also owns the dependent audit-row deletion.

**Option A rejected.** Would require breaking Story 2.5's `%String`-not-typed-FK design (`LlmCall.cls:21-27` doc-comment explicitly preserves this shape: *"Story 2.6 may add a calculated property or relationship to navigate the link without changing this storage shape"*); converting `ChatHistoryId` to a typed `Chat.History` reference or a `%Relationship` is a schema migration and breaks the Story 2.5 design intent.

**Option C rejected.** Would break NFR-SC4 audit-volume bound (audit rows would accumulate forever as chat rows are swept, defeating the "Volume bounded by chat-history sweep cascade" architecture invariant); would require a separate audit-volume management strategy (e.g., independent retention policy on Audit tables) — not in scope for v1.

**AC-4 — Architecture sentence appended.** [`_bmad-output/planning-artifacts/architecture.md`](../planning-artifacts/architecture.md) line 994 now reads (verbatim):
> *"- **`SessionAgent.Audit.{LlmCall, ToolCall}`** — append-only; FK to `Chat.History`. Volume bounded by chat-history sweep cascade (NFR-SC4). Cascade implementation per Story 7.1 Option B: the sweep task deletes audit rows referencing the chat-history row before deleting the chat-history row itself (storage-shape `%String` ChatHistoryId precludes true FK cascade DELETE without a Story 2.5 schema migration)."*

Rule 12 layout-vs-content human read complete: no mojibake, no spacing artifacts, semantically continuous with the existing "Volume bounded..." clause.

**AC-5 — Story 7.2 implementation hint stanza pre-recorded.** Verified the spec's Dev Notes already contains the "Implementation hint for Story 7.2 (pre-recording per AC-5)" section (story file lines 88-100), covering (a) per-orphan delete sequence (audit rows first via parameterized DELETE, then Chat.History row), (b) parameterized-prepare requirement, (c) the missing `ChatHistoryId` index trade-off + Story 7.2 sub-decision.

**AC-6 — Verification battery results (verbatim).**
- No `.cls` files in scope; compile step skipped (only the temporary probe class was created and deleted).
- Stale-reference scan (Rule 4): grep across `.claude/rules/`, `docs/`, `src/SessionAgent/`, `_bmad-output/planning-artifacts/` for `PurgeOrphanedChatHistory|ChatHistoryId|FK cascade|NFR-SC4` — all references consistent with Option B; one near-miss (`FindRelatedSessions.cls:47` mentions "FK cascade-on-delete") clarified to be about `Ens.SuperSessionIndex → Ens.MessageHeader` (Ensemble's built-in schema, unrelated to `SessionAgent.Audit.* → Chat.History`).
- Carry-forward grep (Rule 9): `deferred-work.md` searched for "Story 7.1" — zero matches; no carry-forwards bound.
- Regression sweep — package runner `iris_execute_tests target=SessionAgent.Test level=package` ran 35 test classes (envelope truncated to 22-method JSON, full data persisted in `^UnitTest.Result` run index 248).
- **SQL ground-truth probe (Rule 6 / Story 5.0 AC-1 canonical form):**

```sql
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END) AS Failed
FROM %UnitTest_Result.TestMethod tm
JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
WHERE %EXACT(tc.ID) %STARTSWITH '248||'
```

**Verbatim result:** `{"columns":["Total","Passed","Failed"],"rows":[[288,288,0]],"rowCount":1}` — **288/288 PASS, 0 failures.** Failure-only probe `WHERE tc.ID %STARTSWITH '248||' AND tm.Status = 0` returned `FailCount=0`. Matches Story 7.0 baseline exactly (288/288 — no new tests added in 7.1, none expected). Rule 6 sweep gate satisfied.

### File List

**Modified:**
- `_bmad-output/planning-artifacts/architecture.md` — appended Option-B cascade sentence to line 994 (Persistence-Layer Volume Notes — Audit row).
- `_bmad-output/implementation-artifacts/7-1-task-0-probe-audit-fk-cascade-design.md` — task checkboxes flipped to `[x]`, Dev Agent Record / Completion Notes / File List / Change Log filled in, Status flipped to `review`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story 7.1 status: `ready-for-dev` → `in-progress` (will flip to `review` at Step 9).

**No `.cls` files modified.** A temporary probe-helper class `SessionAgent.TempProbe.SessionIdExistenceProbe` was deployed via `iris_doc_put` (not in `src/`), compiled, used, and deleted — does not appear in this list (lives only on IRIS side, scrubbed at end of Task 1).

## Code Review

**Reviewer:** Claude Opus 4.7 (1M context) — code-review subagent invoked via `/epic-cycle` Story 7.1.
**Date:** 2026-05-06.
**Verdict:** **APPROVED for merge.** Zero HIGH / zero MEDIUM / zero LOW findings.

### Three-layer adversarial review summary

**Blind Hunter (diff-only).** Architecture sentence at line 994 reads as continuous prose (Rule 12 readability check passes — no mojibake, no broken markdown, no spacing artifacts). Completion Notes contain literal verbatim probe outputs (`"SQLCODE=0;exists=1"` and `"SQLCODE=100;exists="`) plus the canonical Probe method body (`Set exists = ""` initializer + `&sql(...)` + `Quit "SQLCODE=" _ SQLCODE _ ";exists=" _ exists` — Rule 2 sharpened evidence shape). Sprint status flip confirmed at sprint-status.yaml line 114 (`review`). File List complete.

**Edge Case Hunter (diff + project read).** Storage-shape claim verified empirically: `src/SessionAgent/Audit/LlmCall.cls:55` and `src/SessionAgent/Audit/ToolCall.cls:54` both declare `Property ChatHistoryId As %String;`. The doc-comment at `LlmCall.cls:21-27` explicitly preserves the `%String` shape (*"Story 2.6 may add a calculated property or relationship to navigate the link without changing this storage shape"*) — Option B preserves Story 2.5's intent; Option A would break it. Architecture line 1039 NFR-SC4 row (`sweep cascade via Task/Purge*.cls`) is consistent with line 994's appended sentence — no contradiction. Carry-forward entry at line 1331 (Epic 7 Story 7.1 Task-0 probe) is closed by this story. Stale-reference scan: dev's near-miss disambiguation of `FindRelatedSessions.cls:47` is correct — that cite is for `Ens.SuperSessionIndex → Ens.MessageHeader` (Ensemble built-in cascade), orthogonal to `SessionAgent.Audit.* → Chat.History`. The 288/288 SQL ground-truth probe uses the `WHERE tc.ID %STARTSWITH '248||'` TestInstance-prefix form (more robust than `MAX(ID)` lex-sort) — empirically supports the Story 7.0 retro AI-1 deferred-item-G rebinding to story 7.0.

**Acceptance Auditor (diff + spec + context docs).**
- AC-1: Verbatim SQLCODE captured for both cases (a: `"SQLCODE=0;exists=1"`, b: `"SQLCODE=100;exists="`). Probe method body included verbatim. ✅ PASS.
- AC-2: Both cases match expected (0/100). No escalation triggered. ✅ PASS.
- AC-3: Option B selected with 3-point reasoning chain (storage shape `%String`, NFR-SC4 bound preservation, Topic-10 Option B operational consistency). Option A rejected (would require `%Persistent` reference or `%Relationship` schema migration breaking Story 2.5). Option C rejected (would break NFR-SC4 audit-volume bound). ✅ PASS.
- AC-4: Architecture sentence appended at line 994 (Persistence-Layer Volume Notes — Audit row, the natural anchor since that line already cites NFR-SC4). Cites Story 7.1 Option B explicitly, cites the storage-shape `%String` precludes-true-FK-cascade rationale. Reads as readable English. ✅ PASS.
- AC-5: Implementation-hint stanza in Dev Notes lines 88–100. Covers (a) per-orphan delete sequence (audit rows first via parameterized DELETE, then Chat.History row), (b) parameterized-prepare requirement, (c) missing `ChatHistoryId` index trade-off + Story 7.2 sub-decision hand-off. ✅ PASS.
- AC-6: 288/288 PASS via SQL ground-truth probe verbatim in Completion Notes. TestInstance ID 248 with `%STARTSWITH '248||'` form. Failure-only probe also captured (`FailCount=0`). Matches Story 7.0 baseline (288/288 — no new tests added in 7.1, none expected). Rule 6 sweep gate satisfied. ✅ PASS.

### Findings

None. The story is a clean low-risk Task-0 probe + design-decision deliverable. No `.cls` files modified, the temporary probe class was correctly deployed-used-deleted server-side, the design decision is grounded in three empirically-verified citations (storage shape, NFR-SC4, Topic-10), and the Story 7.2 hand-off (per-orphan delete sequence + index sub-decision) is preserved cleanly in Dev Notes.

### Deferrals

None added to `deferred-work.md`. Rule 9 carry-forward grep returned zero matches for "Story 7.1" pre-review (consistent with the dev's pre-review grep). No findings warrant deferral.

### Approval

Story 7.1 is approved for the dev-status flip to `done` and commit. The Audit FK cascade contract is now ready for Story 7.2 to consume.

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-05-06 | Initial spec drafted by lead — Task-0 probe + Audit FK cascade Option B selection (storage-shape match preserved per Story 2.5 doc-comment, NFR-SC4 bound preserved, Topic-10 Option B sweep consistency) | Claude Opus 4.7 (lead) |
| 2026-05-06 | Dev complete — Task-0 probe SQLCODE outputs verbatim (case a: SQLCODE=0, case b: SQLCODE=100); Option B selection documented with 3-point reasoning chain (storage-shape `%String`, NFR-SC4 bound, Topic-10 sweep consistency); Options A/C rejected with one-line rationale; architecture.md line 994 cascade sentence appended; stale-reference scan clean (one near-miss in `FindRelatedSessions.cls:47` clarified as Ensemble-built-in `Ens.SuperSessionIndex` cascade, not Audit→Chat); regression sweep 288/288 PASS via SQL ground-truth probe on TestInstance ID 248 (envelope truncation per `object-script-testing.md` workaround). Story flipped to `review`. | Claude Opus 4.7 (dev) |
