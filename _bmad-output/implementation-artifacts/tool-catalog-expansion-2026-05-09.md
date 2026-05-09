# Tool Catalog Expansion — 2026-05-09

**Source:** Post-Epic-12 demo walkthrough on 2026-05-09 (`demo-2026-05-09-walkthrough.md`). The Inspection Agent investigated session 80562 across 4 tool calls and was correct that *"the full source code is needed to see the exact routing logic"* — flagging a real gap in the inspection-tool catalog. Conversation with project lead surfaced 4 more adjacent gaps in the same "what does this configured thing actually do" category, plus 1 cross-session search gap.

**Scope:** 5 new tools across Epic 13. **NO bugs**, **NO existing-behavior changes** — pure additive surface. Brings inspection tool count 13 → 17 and search tool count 10 → 11; total catalog 23 → 28.

**FR59 implication:** cross-matrix gate grows from 92 (23 × 4) to 112 (28 × 4) combinations. Each new tool adds 4 combinations to the live-test sweep.

---

## TOOL-1 — `get_class_source` (Inspection)

**Operator-facing question:** *"Show me the actual source code of this class / this method."*

**Pairs with:** `get_business_process_source` (existing — class structure summary, signatures only) and `list_business_process_methods` (existing — method roster). Today the LLM lists method signatures + sees `has_body: true` flags but cannot read the bodies. This tool closes that gap.

**Why it's tier-1:** appeared as the explicit blocker in the 2026-05-09 demo. Generalizes beyond BPs — works for any class (BO, BP, DTL, message body, search table, custom). DTLs in particular: their transform logic lives in the `DTL` XData section, which `get_class_source` exposes as raw XML for the LLM to parse.

**IRIS API:**
```objectscript
Set tSC = ##class(%Atelier.v1.Utils.TextServices).GetTextAsArray(
    pClassName _ ".cls",
    /*pFlags*/ 0,
    .tTextArray,
    /*pBinary*/ 0)
```
Underlying call: `$$GetTextAsArray^%apiSRC` — same surface Atelier / VSCode ObjectScript / Studio use. Reads `^oddDEF` global storage; works whether the class was IPM-loaded or `$System.OBJ.Load`'d.

**Arguments:**
- `class_name` (required, string) — e.g. `SessionAgent.Sample.BP.OrderRouter`. Apply Story 12.2's strip-last-segment fallback for the class+method-name slip pattern.
- `method_name` (optional, string) — when present, return only that method's body via simple regex extraction (`Method <name>(`...closing `}` matching brace depth 0).
- `include_doc_comments` (optional, boolean, default `true`) — when false, strip `///` lines to save tokens.

**Anti-method-suffix description warning** (Story 12.2 sibling sweep — required): the `class_name` description must include the warning *"Pass the class name only — do not include method names; use `method_name` for method-level filtering."*

**Response shape:**
```json
{
  "class_name": "SessionAgent.Sample.BP.OrderRouter",
  "method_name": "OnResponse",
  "source_lines": ["Method OnResponse(...)", "{", "...", "}"],
  "line_count": 47,
  "truncated": false,
  "render_strategy": "ok"
}
```

**Truncation guard:** if `method_name` omitted AND total lines > 2000, return first 1500 lines + `truncated: true` + a note suggesting `method_name` filter. Mirrors the project's `iris_execute_tests` truncation-aware pattern.

**LOC estimate:** ~80 lines + ~50 lines of test (3 methods: full-class, method-filter, class-not-found path). Per Rule 1 ≤ 250 line spec.

---

## TOOL-2 — `get_rule_source` (Inspection)

**Operator-facing question:** *"What does this rule actually say? I see it fired (per `rule_log`) but what's the constraint and the action?"*

**Pairs with:** `rule_log` (existing). Today the LLM reports *"rule X fired with action Y"* but has no source for the rule logic — operator-mysterious. This tool provides the rule body so the LLM can explain the routing decision.

**Why it's tier-1:** rule logic is the most operator-mysterious surface in Ensemble — the existing `rule_log` shows what fired but not why. Pairs naturally; almost feels like the existing tool's missing half.

**IRIS API:**
```objectscript
Set tRule = ##class(%Dictionary.XDataDefinition).IDKEYOpen(pRuleClass, "RuleDefinition")
If $IsObject(tRule) {
    Set tXData = ""
    Do tRule.Data.Rewind()
    While 'tRule.Data.AtEnd { Set tXData = tXData _ tRule.Data.Read(32000) }
}
```
Reads the `<XData name="RuleDefinition">...</XData>` block on any class extending `Ens.Rule.Definition` (or any rule class — the convention is universal across Ens rule storage).

**Arguments:**
- `rule_class` (required, string) — e.g. `SessionAgent.Sample.Rules.OrderRouting` (full class name from `rule_log` output). Apply strip-last-segment fallback.
- `parse_constraints` (optional, boolean, default `true`) — when true, parse the `<rule>...<when>...</when>...</rule>` XML and return a structured constraint+action list alongside the raw XML. When false, return raw XML only (cheaper for context budget).

**Anti-method-suffix description warning** (Story 12.2 sibling): same warning applies to `rule_class`.

**Response shape:**
```json
{
  "rule_class": "SessionAgent.Sample.Rules.OrderRouting",
  "rule_xml": "<ruleSet name=\"...\"><rule>...</rule></ruleSet>",
  "rule_count": 3,
  "constraints": [
    {"name": "rule-1", "when": "Document.OrderId > 100", "action": "send 'OrderRouter'"},
    {"name": "rule-2", "when": "Document.Type = \"Reject\"", "action": "return 'Rejected'"}
  ],
  "render_strategy": "ok"
}
```

**Truncation guard:** rule XData is typically 50-500 lines; bounded. No truncation expected.

**LOC estimate:** ~60 lines (the `parse_constraints` XML walker is the bulk of it). +~40 lines of test.

---

## TOOL-3 — `get_production_config_item` (Inspection)

**Operator-facing question:** *"What's the file path FilePublish is writing to? What pool size is OrderRouter configured with? What credentials does this BO use?"*

**Pairs with:** `session_timeline` / `message_headers` (existing). Today the LLM sees *that* a BO failed but cannot see *what it was configured to do*. Half of real production triage is config-related (pool=0, wrong file path, credential mismatch, schedule disabled, adapter setting wrong).

**Why it's tier-1:** the most common operator-blocked-by-config investigation pattern. Today there is zero path for the LLM to read configured adapter settings.

**IRIS API:**
```objectscript
Set tProd = ##class(Ens.Config.Production).%OpenId(pProductionName)
Set tItems = tProd.Items  ; relationship; iterate by Name = pConfigItem
; OR direct lookup:
Set tItem = ##class(Ens.Config.Item).NameKeyOpen(pProductionName, pConfigItem)
; Settings are tItem.Settings (relationship): Target, Name, Value
```

Returns: adapter type, business-class name, enabled flag, pool size, queue/auto-resend config, comment, and the full settings list (`Target` ∈ {`Adapter`, `Host`}, `Name`, `Value`).

**Arguments:**
- `production_name` (required, string) — e.g. `SessionAgent.Sample.Production`. Apply strip-last-segment fallback.
- `config_item_name` (required, string) — e.g. `FilePublish`, `SqlPersist`, `OrderRouter`.

**Response shape:**
```json
{
  "production_name": "SessionAgent.Sample.Production",
  "config_item_name": "FilePublish",
  "class_name": "SessionAgent.Sample.BO.FilePublish",
  "adapter_class": "EnsLib.File.OutboundAdapter",
  "enabled": true,
  "pool_size": 1,
  "comment": "...",
  "host_settings": [
    {"name": "FilePath", "value": "C:\\Data\\Outbound"},
    {"name": "Filename", "value": "order-%f%Q.txt"}
  ],
  "adapter_settings": [
    {"name": "FilePath", "value": "C:\\Data\\Outbound"}
  ],
  "render_strategy": "ok"
}
```

**Result-size expectation:** typically 5-30 settings per item. No truncation guard needed.

**LOC estimate:** ~80 lines. +~40 lines of test.

---

## TOOL-4 — `get_queue_state` (Inspection)

**Operator-facing question:** *"Why is this session suspended? Is the BO's queue stuck?"*

**Pairs with:** `session_summary` / `message_headers` (existing). Existing tools show session-level status (Suspended / Completed / etc.) but not queue-depth or whether messages are sitting in a config-item's input queue waiting for the BO to drain them.

**Why it's tier-2 (still worth shipping):** less load-bearing than 13.1-13.3 because not every investigation hits a queue-stuck pattern. But when it does, current tools have no answer.

**IRIS API:**
```objectscript
&sql(SELECT Count, AvgWaitSeconds, OldestId
     INTO :tCount, :tAvg, :tOldest
     FROM Ens.Queue
     WHERE Name = :pConfigItem)
```
Or use `Ens.Util.Statistics:GetQueueCounts()` for a full snapshot.

**Arguments:**
- `config_item_name` (required, string) — e.g. `FilePublish`.
- `include_oldest_messages` (optional, boolean, default `false`) — if true AND queue depth > 0, return the IDs of the oldest 5 queued messages so the LLM can cross-ref with `message_headers`.

**Response shape:**
```json
{
  "config_item_name": "FilePublish",
  "queue_depth": 3,
  "avg_wait_seconds": 12.5,
  "oldest_message_id": 80999,
  "oldest_message_age_seconds": 45,
  "oldest_message_ids": [80999, 81002, 81007],
  "render_strategy": "ok"
}
```

**Result-size expectation:** tiny (single config-item snapshot). No truncation needed.

**LOC estimate:** ~40 lines. +~30 lines of test.

---

## TOOL-5 — `find_sessions_using_class` (**Search**, not Inspection)

**Operator-facing question:** *"Where else has this BP/BO/message class been used recently? Show me the sessions that touched OrderRouter in the last 24 hours."*

**Pairs with:** existing search tools. This is a SEARCH tool (cross-session) not an Inspection tool (single session). Belongs under `src/SessionAgent/Tool/Search/`, registers with `message-search` agent.

**Why useful:** when investigation reveals a problem class, operator may want to know which other sessions touched it (for impact assessment). Today no path to do this from the agent surface.

**IRIS API:**
```sql
SELECT %EXACT(SessionId), MIN(TimeCreated) AS FirstSeen, MAX(TimeCreated) AS LastSeen, COUNT(*) AS MsgCount
FROM Ens.MessageHeader
WHERE (%EXACT(SourceConfigName) = ? OR %EXACT(TargetConfigName) = ? OR %EXACT(MessageBodyClassName) = ?)
  AND TimeCreated >= ?  -- time window
GROUP BY SessionId
ORDER BY MAX(TimeCreated) DESC
```
The class-name field in `Ens.MessageHeader` matches via three columns: `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName`. Tool searches all three by default; can be narrowed with optional `match_field`.

**Arguments:**
- `class_name` (required, string) — e.g. `SessionAgent.Sample.BO.FilePublish` or `SessionAgent.Sample.Msg.OrderRequest`. Apply strip-last-segment fallback.
- `match_field` (optional, enum: `source_config`, `target_config`, `message_body`, `any`; default `any`).
- `time_window_hours` (optional, integer, default 24, MINVAL 1, MAXVAL 168).
- `limit` (optional, integer, default 20, MAXVAL 100). Bounded-WHERE invariant per existing search-agent rule.

**Anti-method-suffix description warning** (Story 12.2 sibling): yes.

**Response shape:**
```json
{
  "class_name": "SessionAgent.Sample.BO.FilePublish",
  "match_field": "any",
  "time_window_hours": 24,
  "session_count": 3,
  "sessions": [
    {"session_id": 80569, "first_seen": "2026-05-09T17:26:23Z", "last_seen": "2026-05-09T17:26:23Z", "msg_count": 1, "matched_via": "target_config"},
    {"session_id": 80562, "first_seen": "2026-05-09T17:26:17Z", "last_seen": "2026-05-09T17:26:17Z", "msg_count": 1, "matched_via": "target_config"},
    {"session_id": 80559, "first_seen": "2026-05-09T17:26:11Z", "last_seen": "2026-05-09T17:26:11Z", "msg_count": 1, "matched_via": "target_config"}
  ],
  "truncated": false,
  "render_strategy": "ok"
}
```

**Truncation guard:** apply existing search-agent `limit` cap (default 20). If matches > limit, return `truncated: true` and suggest narrower `time_window_hours` or specific `match_field`.

**Bounded-WHERE invariant:** queries MUST include time window (default 24h enforced server-side) AND indexed column. `Ens.MessageHeader.SourceConfigName` / `TargetConfigName` / `MessageBodyClassName` are all indexed via `Ens` standard secondary indexes.

**LOC estimate:** ~80 lines + ~50 lines of test.

---

## Cross-cutting requirements (all 5 tools)

**1. Project rule compliance:**
- **Rule 8 §"$Char(0) sentinel"** — N/A; these tools take string inputs from the LLM, not `Config.Agent` rows.
- **Rule 8 §"Class injection guard"** — class names go into SQL WHERE / `%OpenId` / regex; validate against `^[A-Za-z%][A-Za-z0-9%._]*$` server-side before use. Reject and return structured error otherwise.
- **Story 12.2 anti-method-suffix description warning** — required on every `class_name` / `rule_class` / `production_name` argument description.
- **Story 12.2 strip-last-segment fallback** — required on tools 13.1 / 13.2 / 13.3 / 13.5 (all class-name acceptors). Auto-correct + `class_name_auto_corrected_from` field on success; `candidate_class_name` field on still-not-found.

**2. Test coverage:** each tool ≥ 3 test methods (positive, negative class-not-found, edge case like empty/method-suffix/over-large-result). Targets the FR59 cross-matrix gate at 28 × 4 = 112 combinations.

**3. Dispatch policy:** all 5 are read-only (`MutatesState=0`); RBAC role `SessionAgent_ReadOnly` already grants SELECT on the underlying Ens.* / %Dictionary.* / %Atelier.* tables.

**4. Tool-registration contract:** each tool implements:
- `Description` parameter — Anthropic-style, ≤ 1024 chars
- `Invoke(pArgs, ByRef pResult)` method
- `GetInputSchema()` returning JSON-schema for the tool's args
- Registered in `Tool.Registry` with the right agent-name (Inspection: 13.1-13.4; Search: 13.5)

**5. Token-budget discipline:** each tool returns `render_strategy` field (existing convention: `"ok"` / `"class_not_found"` / `"truncated"` / etc.) so the LLM can branch its narrative without re-parsing.

---

## Recommended Epic 13 story shape

| # | Story | Tool | Family | LOC est. (spec + impl + tests) | Bundles |
|---|---|---|---|---|---|
| 13.0 | Epic 12 deferred cleanup + Epic 13 setup | (audit trail) | — | docs only | Rule 7 sprint-planning gate |
| 13.1 | `get_class_source` | Inspection | ~80+50+spec | (none) |
| 13.2 | `get_rule_source` | Inspection | ~60+40+spec | (none) |
| 13.3 | `get_production_config_item` | Inspection | ~80+40+spec | (none) |
| 13.4 | `get_queue_state` | Inspection | ~40+30+spec | (none) |
| 13.5 | `find_sessions_using_class` | **Search** | ~80+50+spec | (none) |

**Story bundling rationale:** kept as 6 separate stories because each tool is independent (no shared code), each fits Rule 1 ≤ 250 lines, each has its own AC contract + test surface. Bundling 13.1+13.4 ("inspection-only quick wins") would reduce stories to 5 but lose per-tool reviewer focus — not recommended.

**Recommended ordering (smallest/least-risky first):**
13.0 → 13.4 (smallest tool, validates the "add a new Inspection tool" path without scope baggage) → 13.2 (small, pairs with rule_log) → 13.1 (the originally-motivating tool, biggest LOC of the inspection set) → 13.3 (config-item — different table set, exercises the SQL-probe-into-Ens.Config family) → 13.5 (Search tool, exercises the Search-tool-add path; saved for last so any patterns from 13.1-13.4 inform the Search variant).

**No epic-update / PRD / architecture changes needed.** Epic 13 is pure tool-catalog expansion within the existing tool-registry surface; no NFR shifts, no UX-DR shifts, no MVP exit-criteria language change.

**End-of-cycle empirical battery (Rule 6):**
- Tool count probe: `iris_execute_classmethod` against `Tool.Registry.ListTools` → expect 28 entries (13 inspection + 4 new = 17; 10 search + 1 new = 11).
- Live agent turn against the 2026-05-09 demo session 80562: ask *"What does the OrderRouter rule say, and where is FilePublish writing files to?"* — exercises 13.2 + 13.3 in one turn.
- FR59 cross-matrix gate: 112 combinations clean.
- Regression sweep clean (461 + ~30 new tests = ~491 expected).

---

## Open question for the project lead

**Tool 13.5 framing:** is `find_sessions_using_class` the right ASK shape? Alternative framings the user might prefer:

- **(a) [chosen]** `find_sessions_using_class(class_name, ...)` — pure cross-session search; lives in Search agent.
- **(b)** `list_session_class_usage(session_id)` — Inspection variant: "which classes did THIS session touch?" Returns a class roster.
- **(c)** Both — different tools for different question shapes.

The current draft assumes (a). If (b) or (c) is preferred, swap before drafting Story 13.5's spec.

---

## Change Log

- 2026-05-09 — Initial draft (lead, post-demo + tool-scoping conversation). Awaiting `/bmad-correct-course` to formalize as Epic 13.
