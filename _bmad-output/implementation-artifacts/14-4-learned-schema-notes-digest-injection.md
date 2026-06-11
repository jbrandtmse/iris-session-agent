# Story 14.4: Learned Schema Notes + First-Turn Digest Injection (FR63, D4)

Status: done

**Source:** `sprint-change-proposal-2026-06-10.md` Â§4.1 FR63 + Â§4.2 D4 (BUILD NOW â€” product-owner override). Precedents: `src/SessionAgent/Search/VocabularyDigest.cls` (`Build` shape + class params), `src/SessionAgent/Agent/AgentLoop.cls` ~lines 34â€“60 + 240â€“260 + 390â€“430 + 535â€“545 (Story 9.4 two-array first-user-message channel), `src/SessionAgent/Tool/Search/VocabLookup.cls` save mode (agent-owned-table write + audit + `pAuditEmitted` ByRef precedent), `src/SessionAgent/Audit/Emit.cls` (EnsureEvents pre-registration).

## Story

As an **operator whose namespace has custom schema quirks the agents discover at runtime**, I want the agents to persist timestamped schema notes (`save_schema_note`) and re-read them (`get_schema_notes` + first-turn digest), so that discovered facts survive across conversations instead of being re-derived every session â€” with staleness visible so old facts get re-verified.

## Acceptance Criteria

**AC-1 â€” `SessionAgent.Knowledge.SchemaNote` persistent class.** Properties: `Namespace` (%String 64), `Subject` (%String 256), `Body` (%String 4000, ASCII-safe), `VerifiedAt` (%TimeStamp, UTC â€” `$ZDateTime($ZTimeStamp,3,1)`-derived per project timestamp rule), `SourceAgent` (%String 64 â€” which agent wrote it). Unique composite index on (Namespace, Subject) â€” upsert key. Operator-readable class/property doc-comments (SQL Catalog surface).

> **Then** class compiles; columns + unique index verified via INFORMATION_SCHEMA; an upsert on an existing (Namespace,Subject) overwrites Body + refreshes VerifiedAt (no duplicate row).

**AC-2 â€” `save_schema_note` tool** (`SessionAgent.Tool.Inspection.SaveSchemaNote`, extends `Tool.Base`, **`MutatesState=1`** *(REVIEW ANNOTATION 2026-06-11: shipped `MutatesState=0` â€” documented deviation, accepted at code review; see Completion Notes "DEVIATION" entry + Review Findings R-1. The Registry hard-blocks `MutatesState=1` dispatch, making this literal unsatisfiable; the flag is the FR31/NFR-S1 `Ens.*`-mutation gate and SchemaNote is agent-owned, per the vocab_lookup save-mode precedent)*). Args: `subject` (required, â‰¤256), `note` (required, â‰¤4000). Namespace is taken from the CallerContext (never from the LLM). Writes ONLY to the agent-owned `SessionAgent_Knowledge.SchemaNote` table (vocab_lookup save-mode precedent). **Defensive surfaces (Rule 8 enumeration â€” epics.md 14.4 bullet):** (a) **ByRef audit-emitted envelope-correctness** â€” the write helper returns the audit-emission outcome ByRef (e.g. `pAuditEmitted`) and the tool envelope reports `audit_emitted` truthfully (vocab_lookup precedent); (b) **`If SQLCODE < 0` checks on every `&sql` mutation** (or `%Save` status checks if object access â€” check the status, do not discard); (c) **error-envelope shaping** â€” failures return the canonical structured error envelope (helpers per the 14.0 callout), never a bare %Status.

> **Then** live dispatch persists a row (SQL probe shows it, VerifiedAt fresh, SourceAgent populated); the audit row for the write exists (verbatim audit query output); a forced write failure path is unit-tested with the error envelope asserted.

**AC-3 â€” Audit pre-registration.** Task 0 probes the existing `%SYS.Audit_Events` triples for `SessionAgent`. If schema-note writes reuse an existing registered triple (e.g., the VocabWrite family) document that; if a NEW triple is required, register it in `Audit.Emit.EnsureEvents` **with a populated Description column** (Rule 4 operator-observable surface; Security.Events silent-drop rule) and note it for the epic-end battery's audit-triple bullet.

> **Then** Completion Notes records the triple used + verbatim `%SYS.Audit_Events` row(s); a live write emits a retrievable audit event (bounded-poll read per the Story 14.0 audit-flush pattern if needed).

**AC-4 â€” `get_schema_notes` tool** (`SessionAgent.Tool.Inspection.GetSchemaNotes`, extends `Tool.Base`, MutatesState=0). Args: `subject_fragment` (optional, parameterized LIKE), `max_results` (default 10, clamp 1..50). Returns notes for the ACTIVE namespace ordered most-recently-verified first; each entry carries `subject`, `note`, `verified_at`, **`age_days`** (staleness surfaced per FR63 â€” retrieval must make age visible).

> **Then** live dispatch returns the AC-2 row with `age_days=0`; fragment filter works; empty result is ok-envelope.

**AC-5 â€” `SchemaNoteDigest.Build(pNamespace)`** (`SessionAgent.Knowledge.SchemaNoteDigest`). Mirrors `VocabularyDigest.Build`: class params `MAXENTRIES=10`, `MAXCHARS=2000`; most-recently-verified-first; each line carries subject + age marker; returns `""` when no notes exist for the namespace (unlike VocabularyDigest there is no seed fallback â€” empty is correct and the injection collapses gracefully per the AgentLoop ~line 247 empty-digest precedent).

> **Then** unit tests: ordering, entry cap, char cap, empty-namespace returns "".

**AC-6 â€” AgentLoop first-turn injection for BOTH agents (D4).** Extend the Story 9.4 two-array channel (AgentLoop ~lines 240â€“260): **search agent** first-user-message prefix becomes vocabulary digest + schema-notes digest concatenated (vocab first; single `---` delimiter block structure preserved); **inspection agent** gains its first first-turn injection (schema-notes digest only), reusing the SAME two-array machinery (`tInjectDigest` path) â€” not a new mechanism. Cached `system + tools` prefix stays bit-identical (NFR-P6): the digest rides ONLY the uncached first-user-message segment.

> **Then** unit/integration tests assert: search agent first turn contains both digests in order; inspection agent first turn contains the schema digest; subsequent turns unprefixed; empty-digest collapse works for both agents; the NFR-P6 cache-stability test (existing) is EXTENDED to cover the inspection-agent injection and still passes.

**AC-7 â€” Suite updates.** ISV: **EXPECTEDTOOLCOUNT 33â†’35 + both tool names in `tExpected` + `GetRepresentativeArgs`** (representative save uses a `ztest-`-prefixed subject so sweeps stay clean â€” and the representative-args dispatch in ISV must not pollute: clean up or use the test-fixture subject convention). Roundtrip cardinality 132â†’140.

**AC-8 â€” Tests.** Coverage: AC-1 upsert; AC-2 write + audit + failure envelope + SQLCODE/status checks (source-introspection per substring-grep binding); AC-4 retrieval/staleness/fragment/clamp; AC-5 digest unit tests; AC-6 injection matrix (both agents Ã— first/subsequent Ã— empty/non-empty); ListTools manifest locks for both tools (TestRegistryListToolsIncludes* precedent). Full sweep = baseline 582 + new, 0 failures (verbatim ground-truth probe).

**AC-9 â€” README same-commit update** (catalog 35; schema-notes subsystem + staleness semantics; digest injection note).

**AC-10 â€” Spec â‰¤ 250 lines.**

## Integration ACs

In-story: real `Tool.Registry.Dispatch` e2e (AC-2/4); AgentLoop injection exercised by integration tests against the mock-provider matrix (real AgentLoop runtime). Cross-story: digest consumed by both agents' first turns (the D4 deliverable itself). Future: Story 14.5 prompt card names both tools; golden questions exercise saveâ†’re-read across conversations in the epic-end walkthrough.

## Consumed-by

- Story 14.5 â€” methodology card directs note-saving habit; GQ set asserts cross-conversation re-read.

## Tasks / Subtasks

- [x] **Task 0 â€” Pre-flight:** read `VocabularyDigest.cls` (full), `AgentLoop.cls` injection region (lines ~230â€“300, 380â€“430, 530â€“550), `VocabLookup.cls` save mode (audit + ByRef pattern), `Audit/Emit.cls` (EnsureEvents + existing triples); probe `%SYS.Audit_Events` for the SessionAgent triples (typed MCP `iris_audit_events` or SQL); decide reuse-vs-new triple (AC-3); capture verbatim probe outputs.
- [x] **Task 1 â€” `SchemaNote`** (AC-1) + compile + upsert probe.
- [x] **Task 2 â€” `SaveSchemaNote`** (AC-2) + audit (AC-3); live dispatch + SQL + audit probes.
- [x] **Task 3 â€” `GetSchemaNotes`** (AC-4); live dispatch probe.
- [x] **Task 4 â€” `SchemaNoteDigest`** (AC-5).
- [x] **Task 5 â€” AgentLoop injection both agents** (AC-6); run the cache-stability + injection tests.
- [x] **Task 6 â€” Suite updates** (AC-7).
- [x] **Task 7 â€” Tests** (AC-8); ground-truth sweep verbatim.
- [x] **Task 8 â€” README** (AC-9); Completion Notes + File List; `wc -l` â‰¤ 250.

### Review Findings

Code review 2026-06-11 (3 adversarial layers: Blind Hunter 16, Edge Case Hunter 11, Acceptance Auditor 7 â†’ deduped 24: 13 patch, 4 defer, 7 dismissed; 0 decision-needed). All patches applied in-review; all affected classes recompiled + re-run; final ground truth 616/616/0 (verbatim probe in "Ground-truth regression sweep (post-review)" below).

- [x] [Review][Decision R-1] **`MutatesState=0` deviation ACCEPTED-WITH-DOCUMENTATION.** Every factual claim in the dev's deviation rationale verified in source: `Registry.cls:167-173` hard-blocks `MutatesState=1` dispatch ("Tool blocked by read-only policy"); `VocabLookup.cls:119` declares `MutatesState=0` for its save mode with the identical agent-owned-table rationale; the "do NOT flip the flag" doc-comment is present on `SaveSchemaNote.cls`; `architecture.md` Â§"New package: SessionAgent.Knowledge.*" already states "Writes target agent-owned tables only (vocab_lookup save-mode precedent)". FR31/NFR-S1 (epics.md:85/148) define the flag as the `Ens.*`-mutation gate, so the L2 gate's semantics are NOT eroded by an agent-owned-table writer â€” **no architecture/PRD amendment required (no Rule 5 tripwire)**. Residual inconsistency was the spec's own AC-2 literal â€” annotated in place. README ToolCatalog wording softened ("the table row itself is the durable record of each write; the audit event + `audit_emitted` envelope field surface emission outcome") to remove the "authoritative record" overstatement that a silently-failed audit emit would falsify.
- [x] [Review][Patch cr-14-4-A] Upsert create-create race converges to update instead of surfacing a spurious write-failure envelope (one bounded retry-as-update on unique-index `%Save` failure) [src/SessionAgent/Knowledge/SchemaNote.cls:Upsert]
- [x] [Review][Patch cr-14-4-B] Audit-emit exception after a committed `%Save` no longer flips the envelope to "write failed" â€” inner Try around `$System.Security.Audit`, `audit_emitted=0` on throw [src/SessionAgent/Knowledge/SchemaNote.cls:Upsert]
- [x] [Review][Patch cr-14-4-C] Audit Details field-spoof hardening: LLM-controlled Subject now rendered LAST in the semicolon-delimited Details string [src/SessionAgent/Knowledge/SchemaNote.cls:Upsert]
- [x] [Review][Patch cr-14-4-D] Case-variant re-save: update branch reassigns `tRow.Subject = pSubject` so the stored casing matches the envelope echo (SQLUPPER index collation) [src/SessionAgent/Knowledge/SchemaNote.cls:Upsert]
- [x] [Review][Patch cr-14-4-E] Digest char-cap recency inversion: `Continue` â†’ stop-on-cap (`Quit`), mirroring the VocabularyDigest stop-on-cap precedent â€” a long newest note can no longer be skipped while older notes still render [src/SessionAgent/Knowledge/SchemaNoteDigest.cls:Build]
- [x] [Review][Patch cr-14-4-F] Bounded first-turn work: `COUNT(*)` + `SELECT TOP MAXENTRIES` replace the unbounded full-namespace scan-and-count; hidden-rows marker arithmetic unchanged [src/SessionAgent/Knowledge/SchemaNoteDigest.cls:Build]
- [x] [Review][Patch cr-14-4-G] Renderer-side subject sanitization (defense-in-depth): `$Translate` of TAB/CR/LF on the rendered Subject so a newline-bearing subject written via public `Upsert`/SQL UPDATE cannot forge the `\n\n---\n\n` delimiter (tool boundary already normalized; QA hostile-content lock covered body only) [src/SessionAgent/Knowledge/SchemaNoteDigest.cls:Build]
- [x] [Review][Patch cr-14-4-H] `$IsObject` type guards on `%Get` reads (`subject`, `note`, `subject_fragment`, `max_results`) â€” nested-object args can no longer persist/match as OREF-coerced garbage strings [src/SessionAgent/Tool/Inspection/SaveSchemaNote.cls, GetSchemaNotes.cls]
- [x] [Review][Patch cr-14-4-I] LIKE metacharacter escaping: `subject_fragment` now binds with `\`-escaped `%`/`_` + `ESCAPE '\'` so the documented substring contract holds (e.g. fragment `order_id` no longer wildcard-matches `orderXid`) [src/SessionAgent/Tool/Inspection/GetSchemaNotes.cls:Invoke]
- [x] [Review][Patch cr-14-4-J] Test determinism + hygiene: SchemaNoteDigestTest fixtures moved to synthetic namespace `ZTESTNS144DIG` (absolute-count asserts now immune to operator notes); `SeedNote` gained optional `pNamespace`; clamp test adds empirical `max_results=1` boundary + the `Set tMax = tMax \ 1` floor literal to the source lock; AgentLoop structural lock adds the collapse-construction literal [src/SessionAgent/Test/SchemaNoteDigestTest.cls, GetSchemaNotesTest.cls, AgentLoopSchemaDigestTest.cls]
- [x] [Review][Patch cr-14-4-K] Fixture-sweep DELETEs status-checked: `DeleteFixtureRows` returns `%Status` (prepare + `%SQLCODE<0` checked), propagated by all OnBefore/OnAfter call sites + both `SweepFixtures` helpers + the ISV `OnAfterOneTest` (now delegates) â€” a silently failed sweep can no longer poison the digest-dependent suites [src/SessionAgent/Test/SchemaNoteToolTest.cls + 4 call-site classes]
- [x] [Review][Patch cr-14-4-L] QA integration test: `<INVALID OREF>` guards before `notes.%Get(0).%Get(...)` chains so an empty retrieval fails with readable asserts instead of crashing [src/SessionAgent/Test/SchemaNoteIntegrationTest.cls]
- [x] [Review][Patch cr-14-4-M] Story record corrected: File List + AC-8 note now include the QA-stage `SchemaNoteIntegrationTest.cls` (5 new classes / 34 new methods, not 4/28); sweep evidence superseded by the post-review 616/616/0 probe; AC-2 literal annotated; AC-4 clamp deviation documented (below)
- [x] [Review][Defer] Namespace-shared digest prompt-context channel â€” design-accepted FR63/D4 residual risk; hardening (per-user scoping / content screening) is future product scope; README residual-risk note added [deferred-work.md 2026-06-11]
- [x] [Review][Defer] SchemaNote retention/decay sweep task (unbounded row growth; story-sized operator artifact per Rule 4) [deferred-work.md 2026-06-11]
- [x] [Review][Defer] AgentLoop empty-collapse assertions remain environment-conditional (deterministic coverage lives at digest-unit level + source lock; no production seam justified) [deferred-work.md 2026-06-11]
- [x] [Review][Defer] JSON-arg type-guard sweep for pre-14.4 tools (pre-existing surface, out of this diff) [deferred-work.md 2026-06-11]

**Documented AC deviations (review-accepted):** (1) AC-2 `MutatesState` â€” see R-1. (2) AC-4 "clamp 1..50": implemented as *invalid-or-below-1 â†’ default 10* (`If tMax < 1 Set tMax = 10`), i.e. `max_results=0` returns 10 rows, not 1 â€” treat-invalid-as-missing semantics, locked by `TestMaxResultsClamp` source introspection + the new empirical `max_results=1` boundary case; accepted as the safer LLM-facing behavior.

**Dismissed (with rationale):** empty-digest "User: " prefix for both agents (deliberate Story 9.4 AC-3 row-5 contract extension, documented + test-locked); `CountSchemaNoteAuditRows` best-effort shape (mirrors the SweepTaskTest Story 14.0 precedent; bounded poll is the flake control); `age_days` divergence on empty `VerifiedAt` (unreachable â€” column Required, %TimeStamp, no SQL-UPDATE-to-empty path); whitespace-only fragment degrading to unfiltered (envelope echoes the normalized fragment â€” observable); `save_schema_note` happy path absent from the 140-pair matrix (documented pollution-avoidance; happy path e2e-covered by SchemaNoteToolTest dispatch + ISV representative dispatch with cleanup); `tCtx` undefined in AgentLoop (defined at line 158, `Namespace = $NAMESPACE`, never LLM-controllable); README catalog/matrix counts (verified accurate: 35 tools, 23+11+1, 140 pairs).

**Lead verification highlights (review focus points):** AgentLoop two-array invariant intact â€” dual-push sites (lines 461/578) untouched, digest prefix only in `tTurnsForLlm`, persisted first turn = `pUserText` verbatim (`TestInspectionPersistedTurnsJsonCanonical`), NFR-P6 extension genuinely asserts byte-identical system+tools across turns with the digest injected on turn 1; SmokeTest exercises the injected first-turn path implicitly (RunTurn turn 1 through real AgentLoop; green in latest sweep). Audit triple re-probed live: `SessionAgent | SchemaNoteWrite | explicit | "SessionAgent schema-note write: agent-saved namespace fact (save_schema_note)" | Enabled=true`; 111 SchemaNoteWrite rows in `%SYS.Audit` at review time; `TestSaveAuditRowLands` (bounded 240Ã—0.5s poll) green post-fix. No TSTART/TCOMMIT anywhere in the new code â€” Transaction Side Effects rule N/A. Namespace isolation: `CallerContext.Namespace` is the only namespace source in both tools + digest call (`tCtx.Namespace`), no LLM-namespace arg in either schema (manifest locks assert absence). `$Char(0)`: normalized at both tools' namespace reads; `VerifiedAt` is %TimeStamp (sentinel rule N/A for the QA SQL-UPDATE backdate path). ISV representative-args hygiene verified (ztest- subject + status-checked OnAfterOneTest sweep; post-review probe shows 0 residual ztest- rows).

**Run-219 transient (Rule 5 investigation, review-stage).** The post-fix `SchemaNoteToolTest` class run (TestInstance 219, 13:41 UTC, ~90s after the 11-class recompile at 13:39:34) recorded `TestUpsertCreatesThenOverwrites` assert #6 failed ("second Upsert action = 'updated'") while every data-level assert in the same method passed (Cnt=1, body overwritten, VerifiedAt refreshed, SourceAgent updated) â€” a combination not coherently producible by either the pre- or post-review code, consistent with a pooled work-queue worker executing a stale routine image inside the recompile window (same transient class as the dev's run-203 note). Re-run on identical final code: TestInstance 229 = 9/9 green. Similarly, the first post-recompile `SchemaNoteIntegrationTest` run (221) crashed `TestAgeDaysAfterSqlUpdateBackdate` with `<INVALID OREF>`; non-reproducible on runs 223/224/225 (all green); cr-14-4-L makes that failure mode readable if it ever recurs. No code fix required; no failure reproduces on the final state.

### Ground-truth regression sweep (post-review)

Canonical numerical-MAX SQL probe (latest run per class), run 2026-06-11 after all review patches + per-class re-runs (SchemaNoteDigestTest 6/6, GetSchemaNotesTest 6/6, SchemaNoteToolTest 9/9 [run 229], AgentLoopSchemaDigestTest 7/7, SchemaNoteIntegrationTest 6/6, InspectionSuiteVerificationTest 13/13, ToolCallRoundtripIntegrationTest 4/4, AgentLoopVocabDigestTest 6/6):

```
Total | Passed | Failed
616   | 616    | 0
```

## Dev Notes

- **Helper callout (Story 14.0 Carry-Forward, verbatim):** *"For SQL prepare failures call `##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSC, ..#ToolName)`; for runtime execute failures call `EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName)` immediately after `%Execute` â€” do NOT construct raw `{"isError":1}` objects."* Post-loop fetch-fault gate on every cursor loop (14.2-review pattern).
- **AgentLoop is the riskiest diff of the epic** â€” the two-array invariant (shared assistant-turn OREF dual-push, digest-prefixed user block only in `tTurnsForLlm`) must NOT be restructured; extend the existing `tInjectDigest` path minimally. Read the Story 9.4 doc comments in full before touching. Existing AgentLoop tests must stay green untouched (any test edit there needs explicit justification in Completion Notes).
- **Namespace from CallerContext** (`tCtx.Namespace`), never an LLM arg â€” prevents cross-namespace writes. Subject/note are LLM input: validate lengths server-side; parameterized SQL everywhere; `$Match` not needed (free text) but control-char normalization per the 14.1-review keyword precedent is.
- **MutatesState=1 dispatch gate:** verify how Registry/Dispatch treats MutatesState=1 under the read-only RBAC posture (L2 gate per architecture) â€” probe an existing MutatesState=1 tool if one exists (vocab_lookup save mode?) and mirror its contract; document in Task 0.
- **`$Char(0)` sentinel rule:** SchemaNote columns are written via object access/INSERT (no Zen SQL-UPDATE path today) â€” note the rule's read-site grep is satisfied; if any read site checks `'= ""` on a column that could later be SQL-UPDATEd, normalize defensively.
- **Timestamps:** `VerifiedAt` UTC per the ISO-8601 project rule; `age_days` computed server-side from `$ZTimeStamp` delta (UTC-to-UTC).
- **Substring-grep binding (Epic 12 AI-5)** for source-introspection assertions.
- **Test hygiene:** `ztest-` subject prefix + OnAfterOneTest cleanup; audit assertions use the bounded exit-early poll pattern (Story 14.0); no `Property Test*`; classes â‰¤ ~500 lines.
- **Rule 10:** no external defaults â€” N/A.
- **Subagent refs:** `irislib/` for `%SYS.Audit` / `Security.Events` semantics; precedent files named above.

### References

- [Source: sprint-change-proposal-2026-06-10.md Â§4.1 FR63, Â§4.2 D4]
- [Source: epics.md Â§Epic 14 â€” 14.4 bullet (ByRef audit-emitted envelope-correctness per Rule 8 defensive-surface enumeration)]
- [Source: src/SessionAgent/Search/VocabularyDigest.cls; src/SessionAgent/Agent/AgentLoop.cls (Story 9.4 channel); src/SessionAgent/Tool/Search/VocabLookup.cls save mode; src/SessionAgent/Audit/Emit.cls]
- [Source: .claude/rules/epic-cycle-discipline.md Â§Rule 8 "Defensive-surface enumeration" (Epic 9 retro AI-3 â€” MEDIUM-F01/F02 incident)]

## Dev Agent Record

### Agent Model Used

Claude Fable 5 (claude-fable-5[1m]) via /epic-cycle dev-story stage.

### Debug Log References

- Temp probe class `SessionAgent.Test.ZTempSchemaNoteProbe144` used for live Registry.Dispatch evidence capture (deleted from disk + server doc `SessionAgent.Test.ZTempSchemaNoteProbe144.cls` at completion verification, 2026-06-11; `iris_doc_list` confirms no remaining match).
- `^||SessionAgent.SchemaDigest.LastError` PPG added as the digest's defensive error-capture channel (VocabularyDigest precedent).

### Completion Notes List

- **DEVIATION from AC-2 literal `MutatesState=1` â†’ shipped `MutatesState=0` (Task 0 gate decision, per the spec's own Dev Notes directive to "probe ... and mirror its contract").** Task 0 evidence: (1) `SessionAgent.Tool.Registry.Dispatch` Step 2 hard-blocks any `MutatesState=1` dispatch â€” `Set tMutates = ..GetParameterValue(tClassName, "MutatesState") If tMutates = 1 { Set pResult = {"isError":(1), "content":[{"type":"text", "text":"Tool blocked by read-only policy"}]} ... }` (Registry.cls ~line 168) â€” making AC-2's "live dispatch persists a row" THEN-clause unsatisfiable with the flag set; (2) the gate is structurally locked by `ToolRegistryTest` + `StubWriteTool` ("the registry MUST block this") and by `InspectionSuiteVerificationTest.TestAllToolsDeclareReadOnlyMutatesState` + `ToolCallRoundtripIntegrationTest.TestAllToolsAreReadOnly`, which assert MutatesState=0 on EVERY concrete tool; (3) the `vocab_lookup` save-mode precedent (writes to the agent-owned UserVocabulary table with `MutatesState=0`) documents that the flag is the FR31/NFR-S1 L2 flag for `Ens.*` mutation specifically â€” SchemaNote is agent-owned data, not `Ens.*`; (4) epics.md's 14.4 bullet does not mention MutatesState=1. The class doc-comment carries the full vocab_lookup-style "do NOT flip the flag" rationale; the `(SessionAgent, SchemaNoteWrite, explicit)` audit emit is the authoritative record of each write.
- **AC-1 verbatim evidence.** INFORMATION_SCHEMA.COLUMNS: `ID bigint NO | Body varchar 4000 NO | Namespace varchar 64 NO | SourceAgent varchar 64 YES | Subject varchar 256 NO | VerifiedAt timestamp NO`. INFORMATION_SCHEMA.INDEXES: `NsSubjectIdx (Namespace 1, Subject 2) NON_UNIQUE=0`. Upsert probe: first `Upsert("HSCUSTOM","ztest-upsert-probe-144","first body version","session-inspection")` â†’ row `VerifiedAt=2026-06-11 12:22:34` (UTC; local was 05:22 â€” UTC-7 confirms $ZTimeStamp); second Upsert with new body â†’ SQL probe `RowCnt=1, Bod="second body version OVERWRITES", Va=2026-06-11 12:22:53, SrcAgent=message-search` â€” single row, body overwritten, VerifiedAt refreshed.
- **AC-2 verbatim evidence (live Registry.Dispatch).** `status=OK | envelope={"content":[{"type":"text","text":"Saved schema note 'ztest-live-dispatch-144' (created) for namespace 'HSCUSTOM'."}],"structuredContent":{"render_strategy":"ok","namespace":"HSCUSTOM","subject":"ztest-live-dispatch-144","action":"created","verified_at":"2026-06-11T12:27:38Z","audit_emitted":1,"source_agent":"session-inspection"}}`. SQL probe of the persisted row: `HSCUSTOM | ztest-live-dispatch-144 | Live dispatch probe: ... | 2026-06-11 12:27:38 | session-inspection`. Forced write-failure path unit-tested (`TestSaveToolWriteFailureReturnsErrorEnvelope` â€” 70-char ctx Namespace > MAXLEN 64 â†’ `%Save` fails â†’ `{isError:1, render_strategy:"write_error", error_text:...}` asserted). Defensive surfaces a/b/c locked by `TestDefensiveSurfacesSourceIntrospection` (substring-grep binding on `SchemaNote.Upsert` + `SaveSchemaNote.Invoke` compiled sources).
- **AC-3 verbatim evidence.** Task 0 `Security.Events` probe returned the 45 pre-existing SessionAgent triples (LlmCallÃ—4, TaskRunÃ—3, VocabWriteÃ—4, ToolCallÃ—34 lazy) â€” NO reusable schema-note triple; the VocabWrite family is semantically vocabulary-specific, so a NEW triple was registered in `Audit.Emit.EnsureEvents`: post-registration probe â†’ `SessionAgent | SchemaNoteWrite | explicit | "SessionAgent schema-note write: agent-saved namespace fact (save_schema_note)" | Enabled=true` (Description populated per Rule 4). Live write audit row (daemon flush ~70s, retrieved via re-probe): `2026-06-11 12:27:38.859 | SessionAgent | SchemaNoteWrite | explicit | SchemaNote.Upsert: created schema note (save_schema_note) | Namespace=HSCUSTOM; Subject=ztest-live-dispatch-144; Action=created; SourceAgent=session-inspection; BodyLength=100`. Test-time retrieval uses the bounded exit-early poll (`WaitForSchemaNoteAuditIncrease`, 240Ã—0.5s per the Story 14.0 pattern) â€” `TestSaveAuditRowLands` green.
- **AC-4 verbatim evidence (live Registry.Dispatch).** `status=OK | envelope={"content":[{"type":"text","text":"get_schema_notes: 1 note(s) for namespace 'HSCUSTOM' matching 'ztest-live-dispatch' (most recently verified first; check age_days for staleness)."}],"structuredContent":{"notes":[{"subject":"ztest-live-dispatch-144","note":"...","verified_at":"2026-06-11T12:27:38Z","age_days":0,"source_agent":"session-inspection"}],"render_strategy":"ok","namespace":"HSCUSTOM","subject_fragment":"ztest-live-dispatch","count":1}}` â€” the AC-2 row returned with `age_days=0`; fragment filter + clamp + empty-ok-envelope covered by `GetSchemaNotesTest` (6/6 green via SQL ground-truth probe; MCP envelope truncated to 2 rows â€” known truncation, SQL probe authoritative).
- **AC-5.** `SchemaNoteDigest` mirrors `VocabularyDigest.Build` (params `MAXENTRIES=10` / `MAXCHARS=2000`, row-granular caps, hidden-rows marker pointing at `get_schema_notes`, PPG error capture) with NO seed fallback â€” empty namespace returns `""` (smoke: `Build("NOSUCHNAMESPACE144")` â†’ `""`; `Build("HSCUSTOM")` with one note â†’ header + `- "ztest-upsert-probe-144" (verified today): ...`). `SchemaNoteDigestTest` 6/6 green (ordering, entry cap, char cap, empty â†’ "", age markers, snippet collapse).
- **AC-6.** AgentLoop Step-4 injection EXTENDED, not restructured: the outer guard became first-turn-only (`If tTurns.%Size() = 0`), vocab digest still builds only for `message-search`, schema digest builds for ALL agents from `tCtx.Namespace`, concatenation = vocab first + blank line + schema, single `---` delimiter block preserved, empty-digest collapse (`"User: " _ pUserText`) now applies to both agents, `tInjectDigest=1` set unconditionally inside the guard (source-introspection literals `If tDigest '= ""` / `"User: "` / `Set tInjectDigest = 1` preserved â€” Story 9.4's `TestEmptyDigestStillWiresThrough` passes untouched). Two-array dual-push machinery untouched. `AgentLoopSchemaDigestTest` 7/7 green incl. `TestInspectionPersistedTurnsJsonCanonical` (persisted first user turn = pUserText verbatim) and `TestAnthropicCachedPrefixUnchangedInspectionAgent` (NFR-P6 extension: system + tools byte-identical across turns with the digest injected on turn 1).
- **JUSTIFIED AgentLoop-test edit (the only one).** `AgentLoopVocabDigestTest.TestInspectionAgentDoesNotReceiveDigest`: the Story 9.4 assertion "captured text does NOT contain '---'" encoded the pre-14.4 behavior (inspection agent receives NO injection); Story 14.4 deliberately gives the inspection agent a schema-notes digest, so that assertion fails whenever any schema note exists in the namespace (environment-dependent false failure). Amended to lock the durable invariant instead: inspection agent NEVER sees the vocabulary digest (both "## Common idioms" and "## Saved aliases" headers asserted absent) + raw pUserText still present. All 6 methods of the 9.4 class green post-amendment. No other AgentLoop test was modified.
- **AC-7.** ISV `EXPECTEDTOOLCOUNT` 33â†’35 + both tool names in `tExpected` + representative args (`save_schema_note` uses the `ztest-` subject convention; new `OnAfterOneTest` sweeps `ztest-%` SchemaNote rows so the representative dispatch never pollutes) + `get_schema_notes` added to `tNoRequiredArgs` (all-optional schema). ISV 13/13 green. Roundtrip cardinality lock 132â†’140 (4Ã—35) + `BuildMinimalToolArgs`: `get_schema_notes` gets a no-match fragment (success envelope, no pollution); `save_schema_note` deliberately falls through to `{}` (validation isError envelope satisfies the matrix's canonical-envelope contract without persisting rows 4Ã— per run â€” happy path covered e2e elsewhere). Roundtrip 4/4 green incl. the 140-pair matrix under the perf gate.
- **AC-8.** 28 new test methods across 4 new classes (SchemaNoteToolTest 9, GetSchemaNotesTest 6, SchemaNoteDigestTest 6, AgentLoopSchemaDigestTest 7). *(REVIEW CORRECTION 2026-06-11: the QA stage added a 5th class, `SchemaNoteIntegrationTest` (6 methods â€” cross-conversation e2e, namespace isolation, unique-index TOCTOU net, exact-MAXLEN boundaries, hostile-content delimiter integrity, SQL-UPDATE backdate age_days), bringing the story total to 5 new classes / 34 new methods; its 6/6 pass is included in the 616-method post-review ground truth below.)* Full-sweep ground-truth probe: see the verbatim Total/Passed/Failed line below (SQL probe per object-script-testing.md Â§"SQL-probe-as-ground-truth"; the `iris_execute_tests` envelope truncated repeatedly during this story â€” every per-class claim above was verified by the SQL probe, not the envelope).
- **AC-9.** README same-commit update: catalog 33â†’35 (inspection 21â†’23 + 2 new tool rows), FR59 matrix row 132â†’140, new "Learned schema notes" subsection (storage/upsert semantics, age_days staleness contract, both-agent first-turn digest injection + NFR-P6 note, audit triple), feature-table row for FR63.
- **Sweep evidence (filled at completion):** see "Ground-truth regression sweep" below.

### Ground-truth regression sweep (dev-stage â€” superseded by the post-review sweep under Review Findings)

Canonical numerical-MAX SQL probe (latest run per class, `%UnitTest_Result.TestMethod` JOIN `TestCase`, per object-script-testing.md Â§"SQL-probe-as-ground-truth"), run 2026-06-11 at completion verification. *(Note: this 610 count predates the QA-stage `SchemaNoteIntegrationTest` (+6 methods) â€” the authoritative post-review figure is 616/616/0.)*

```
Total | Passed | Failed
610   | 610    | 0
```

Full-package sweep TestInstance 211 (started 2026-06-11 05:50:56 local, 534s, ALL classes on final code) independently confirms: `Total=610 / Passed=610 / Failed=0` with zero `Status=0` rows.

**Completion-continuation investigation (Rule 5 evidence) â€” the 6 transient failures in sweep run 203.** An interim ground-truth probe taken before completion verification read 610/604/6 with 6 failing methods, all from TestInstance **203** (SearchVocabularyTestÃ—2 digest asserts, SmokeTest `<INVALID OREF>` at TestSmokeEndToEnd+18, Story41ToolsTest `<INVALID OREF>` at TestRuleLogTimestampIsoFormat+9, SweepTaskTestÃ—2 purge asserts). Root cause: **run 203 was a mid-dev-state sweep, not a regression.** Timestamp evidence: TestInstance 203 ran 05:08:49 â†’ ~05:14:34 (345s), while the FINAL server compiles of the Story 14.4 diff landed AFTER it â€” `Audit.Emit.cls` etag 05:23:43, `Agent.AgentLoop.cls` etag 05:29:05, `Test.AgentLoopVocabDigestTest.cls` etag 05:32:06. Verification on final code: each affected class re-run per-class and confirmed green via per-class SQL roster (SmokeTest 1/1, Story41ToolsTest 12/12 incl. TestRuleLogTimestampIsoFormat, SweepTaskTest 6/6 incl. both purge methods, SearchVocabularyTest 14/14 incl. both digest methods), and all four are also green inside full sweep 211. No code fix was required; no failure reproduced on the final code state.

### File List

- src/SessionAgent/Knowledge/SchemaNote.cls (new)
- src/SessionAgent/Knowledge/SchemaNoteDigest.cls (new)
- src/SessionAgent/Tool/Inspection/SaveSchemaNote.cls (new)
- src/SessionAgent/Tool/Inspection/GetSchemaNotes.cls (new)
- src/SessionAgent/Audit/Emit.cls (modified â€” SchemaNoteWrite triple in EnsureEvents + doc comment)
- src/SessionAgent/Agent/AgentLoop.cls (modified â€” Step-4 first-turn digest extension + doc comments)
- src/SessionAgent/Test/SchemaNoteToolTest.cls (new)
- src/SessionAgent/Test/GetSchemaNotesTest.cls (new)
- src/SessionAgent/Test/SchemaNoteDigestTest.cls (new)
- src/SessionAgent/Test/AgentLoopSchemaDigestTest.cls (new)
- src/SessionAgent/Test/SchemaNoteIntegrationTest.cls (new â€” QA stage; added to File List at review, cr-14-4-M)
- src/SessionAgent/Test/InspectionSuiteVerificationTest.cls (modified â€” AC-7)
- src/SessionAgent/Test/ToolCallRoundtripIntegrationTest.cls (modified â€” AC-7)
- src/SessionAgent/Test/AgentLoopVocabDigestTest.cls (modified â€” justified single-test amendment, see Completion Notes)
- README.md (modified â€” AC-9)
- _bmad-output/implementation-artifacts/14-4-learned-schema-notes-digest-injection.md (this file)
- _bmad-output/implementation-artifacts/sprint-status.yaml (status flip)

### Change Log

- 2026-06-11 (code review): 13 patches applied (cr-14-4-A..M â€” upsert race convergence, audit-exception envelope truth, details field-spoof reorder, case-variant subject, digest stop-on-cap + bounded TOP/COUNT fetch + renderer subject sanitization, arg type guards, LIKE escaping, test determinism/hygiene, OREF guards, story-record corrections), 4 deferred to deferred-work.md, 7 dismissed; MutatesState=0 deviation accepted with documentation (R-1); post-review ground truth 616/616/0; status stays `review` per /epic-cycle stage contract.
- 2026-06-11: Story 14.4 implemented â€” SchemaNote persistent class + save_schema_note/get_schema_notes tools (catalog 33â†’35), SchemaNoteWrite audit triple, SchemaNoteDigest, AgentLoop first-turn digest injection extended to both agents (two-array channel preserved), suite locks updated (ISV 35, matrix 140), README schema-notes section. 28 new tests.
