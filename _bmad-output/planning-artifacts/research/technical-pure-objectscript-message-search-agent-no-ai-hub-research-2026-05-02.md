---
stepsCompleted: [1, 2, 3, 4, 5, 6]
workflowComplete: true
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Pure-ObjectScript Message Search Agent — No AI Hub, IRIS 2024.1+'
research_goals: 'Design the Message Search Agent — sibling to the Session Inspection Agent — that lives in custom EnsPortal.MessageViewer and helps operators find Ensemble sessions via natural-language query. Pure ObjectScript only. IRIS 2024.1+. Reuses the shared infrastructure (provider abstraction, tool registry pattern, agent loop, audit log, RBAC role, Markdown bundle) defined in the sibling research doc; adds: (1) search-oriented tool surface over Ens.MessageHeader and related tables; (2) scale-handling patterns for namespaces with millions of rows; (3) per-user search-term-learning persistence; (4) chat keying model when no Ens session id exists at conversation start; (5) hand-off pattern from search agent to inspection agent on session click-through; (6) search-arg-construction safety against SQL injection. MCP-export-friendly tool dispatch contract carried forward. Out of scope (sibling doc): the inspection agent itself; AI Hub primitives; embedded Python.'
user_name: 'Developer'
date: '2026-05-02'
web_research_enabled: true
source_verification: true
depends_on: technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md
---

# Research Report: Technical — Message Search Agent

**Date:** 2026-05-02
**Author:** Developer
**Research Type:** Technical
**Depends on:** [Sibling research — Pure-ObjectScript Session Inspection Agent (No AI Hub)](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)

---

## Research Overview

This document is the v1 architectural blueprint for the **Message Search Agent** — sibling to the Session Inspection Agent, both shipping in the `iris-session-agent` IPM module on **IRIS / IRIS for Health 2024.1+**, in **pure ObjectScript** with no embedded Python and no AI Hub primitives. The Message Search Agent lives as a chat tab on a custom `SessionAgent.EnsPortal.MessageViewer` subclass and helps operators find Ensemble sessions via natural-language query — the inverse of the Inspection Agent's role (find a session vs. explain a session). The two agents share ~80% of their infrastructure (provider abstraction, agent loop, tool registry pattern, persistence schemas, audit log, RBAC role, Markdown rendering bundle, IPM packaging) and diverge on three axes: a different tool surface (8 search tools over `Ens.MessageHeader` indexed access paths, all SQL-driven), a per-user vocabulary-learning class family (`SessionAgent.Search.UserVocabulary` + namespace baseline + ship-with seed) that injects retrieval-augmented prompting into the first user message, and a different chat-keying lifecycle (registry-issued GUID per portal session, TTL-based purge instead of Ens-session-coupled).

The research progresses through six steps: scope confirmation (§Technical Research Scope Confirmation), the search-specific platform surface and IRIS SQL scale patterns (§Technology Stack Analysis), search-arg-construction safety + canonical query templates + vocabulary-learning update path + hand-off pattern (§Integration Patterns Analysis), the 8-tool catalog + vocabulary class family + portal subclass shape (§Architectural Patterns and Design), code skeletons including a fully-worked example tool and the digest-builder logic (§Implementation Approaches and Technology Adoption), and a synthesis with strategic recommendations + risk roll-up (§Research Synthesis & Executive Summary at the end of the document). Two stream conflicts surfaced and were resolved against authoritative source: `%NOLOCK` is a DML-only hint in IRIS SQL (drop from search SELECTs), and `Ens.MessageHeader.IsError`/`Type`/`CorrespondingMessageId` are NOT indexed by default (verified directly in `irislib/Ens/MessageHeader.cls` lines 14–28 — only 8 indexed access paths exist on the table). For the bottom-line decision matrix, scan §Research Synthesis & Executive Summary at the end of this document.

## Table of Contents

1. [Technical Research Scope Confirmation](#technical-research-scope-confirmation) — what's in / what's out, eight topics, MCP→`iris-execute-mcp-v2` clarification
2. [Technology Stack Analysis](#technology-stack-analysis) — `Ens.MessageHeader` 8 indexed access paths, `Ens.SuperSessionIndex` cross-session lookup, SearchTable body-search pattern, IRIS SQL scale patterns, two stream-conflict resolutions, `SessionAgent.Search.UserVocabulary` storage primitive
3. [Integration Patterns Analysis](#integration-patterns-analysis) — agent loop reuse, three-layer search-arg safety, eight canonical query templates, search-result→chat-turn refinement cycle, vocabulary-learning update path, search→inspection hand-off via URL parameter, audit-log enrichment, MessageViewer UX integration, chat-keying lifecycle without an Ens session id
4. [Architectural Patterns and Design](#architectural-patterns-and-design) — component diagram delta, 8-tool search catalog, vocabulary-learning class family, `SessionAgent.EnsPortal.MessageViewer` subclass, audit enrichment columns, search-agent config defaults, IPM additive packaging, `SessionAgent.Task.PurgeStaleSearchChat` TTL sweep
5. [Implementation Approaches and Technology Adoption](#implementation-approaches-and-technology-adoption) — 7-epic search-agent sequence (12-18), example `SearchByStatus` tool implementation, `UserVocabulary` persistence methods, `VocabularyDigest.Build` cascade, click-through dispatch interceptor, installer additions, operator README, test strategy
6. [Research Synthesis & Executive Summary](#research-synthesis--executive-summary) — top findings, strategic recommendations, risk roll-up, Task-0 carry-forwards, open questions, source documentation, workflow completion

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Pure-ObjectScript Message Search Agent — No AI Hub, IRIS 2024.1+

**Research Goals:** Design the Message Search Agent — sibling to the Session Inspection Agent — that lives in custom `EnsPortal.MessageViewer` and helps operators find Ensemble sessions via natural-language query.

**Project context that constrains this research** (carried forward from saved memories + the sibling research doc + clarification on 2026-05-02):

- **Pure ObjectScript only.** No embedded Python in the runtime path.
- **IRIS / IRIS for Health 2024.1+.**
- **No AI Hub primitives.**
- **Reuses the v1 shared infrastructure** per the sibling doc's two-agent infra-sharing matrix: `SessionAgent.Agent.AgentLoop`, the four-provider `SessionAgent.LLM.Provider` family, `SessionAgent.Tool.Base` + `SessionAgent.Tool.Registry` pattern, `SessionAgent.Chat.History` schema (different keying), `SessionAgent.Config.Agent` (different row), `SessionAgent.Audit.{LlmCall,ToolCall}`, `%SessionAgent_ReadOnly` RBAC role, vendored `marked` + `Prism` + `DOMPurify` Markdown bundle.
- **MCP-exportable dispatch contract** — same `(toolName, jsonArgs) → jsonResult` discipline; same 7-anti-pattern list applies. **Important clarification (2026-05-02):** MCP serving will NOT be done in this project. It will be done in the **standalone IRIS MCP Server Suite at `../iris-execute-mcp-v2`**, which will consume our tool registry. Our job here is to keep the registry introspectable enough for that suite to wrap.
- **Read-only.** Same three-layer enforcement.
- **IPM-installable.** Ships in the same `module.xml` as the inspection agent.

**Technical Research Scope (eight topics):**

1. **Search-oriented tool surface** — Tools mapping natural-language operator queries to filtered SQL over `Ens.MessageHeader` and friends. Candidates: search-by-date-range, search-by-source/target-config, search-by-status, search-by-error-flag, search-by-message-body-field, search-by-patient-or-order-id-hint, search-similar-sessions, narrow-recent-results, drill-into-session. ~7-10 tools.
2. **Scale-handling patterns** — Namespaces with millions of `Ens.MessageHeader` rows. `TOP N` pagination, mandatory time-window bounds, `Ens.SuperSessionIndex` for cross-instance lookups, `_AdditionalInfo` body-field indexes, `%NOLOCK` hint, query-cancellation budget. **Goal: every search tool has a worst-case latency ceiling regardless of namespace size.**
3. **Per-user search-term-learning persistence** — `SessionAgent.Search.UserVocabulary` `%Persistent` class shape; what signals to capture (filter combinations, accepted/rejected results, query templates); retrieval-augmented prompting at turn time (inject user's vocabulary into the agent's system prompt).
4. **Chat keying model without an Ens session id** — Keying options: registry-issued GUID per browser-tab, per-portal-user-day, persistent until manual clear, etc. Plus lifecycle / TTL — when does a search-agent chat row purge?
5. **Hand-off pattern: search agent → inspection agent** — When the search agent surfaces a candidate session, how does the operator click through and what context is preserved? Two design candidates: URL-parameter context-pass; cross-agent shared `SessionAgent.Chat.HandoffContext` row.
6. **Search-arg-construction safety / SQL injection prevention** — LLM constructs tool args; tool args become SQL parameters. The dispatch contract must guarantee parameterization. Specific patterns: `%SQL.Statement.%Prepare` + `%Execute(?, ?)`, regex/whitelist validation, output-of-LLM-as-input handling, bounded `WHERE` clauses against runaway full-table scans.
7. **UX integration with EnsPortal.MessageViewer's existing filter UI** — Does the agent populate the existing filter controls, run its own queries beneath them, or both? Does the chat tab live alongside or replace the filter panel?
8. **Differences from the inspection agent's tool/audit model** — Search tools are all SQL-driven (no per-message body dispatch). Audit log differences: search agent logs query templates and result-set sizes for vocabulary learning. Configuration differences: cheaper-model defaults are usually fine since result-set summarization is less complex than session narrative.

**Methodology:** Same as the sibling doc — InterSystems docs (2024.1 surface), local `irislib/`, Perplexity MCP cross-checks (minimum 2 authoritative sources per non-trivial finding), confidence levels (High / Medium / Low) called out, Task-0 probes flagged where 2024.1 verification is incomplete.

**Out of scope (kept here for honesty):**

- The Session Inspection Agent itself (sibling doc).
- AI Hub primitives.
- Embedded-Python alternatives.
- Multi-modal search (image attachments, OCR).
- Cross-IRIS-instance federated search.
- Vector / semantic search on message bodies (would use `%Library.Embedding`; v2 concern).
- **MCP serving** — handled by `../iris-execute-mcp-v2` (sibling project), not this one.

**Scope Confirmed:** 2026-05-02

---

## Technology Stack Analysis

> **Note on reuse:** Most of the IRIS 2024.1 platform surface (the OS primitives — `%Net.HttpRequest`, `%DynamicObject`, `%Persistent`, `%Dictionary.*`, `%CSP.Session`/ZenMethod hyperevents, `Ens.Config.Credentials`, `$SYSTEM.Util.GetEnviron`, encryption primitives) is **shared with the Session Inspection Agent and inventoried in the [sibling research doc §"IRIS 2024.1 Platform Surface"](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md#technology-stack-analysis).** Step 2 here covers only what's distinct to the search problem: the actual indexed search surface on `Ens.MessageHeader`, IRIS SQL scale patterns, the body-search SearchTable infrastructure, and the per-user vocabulary-learning storage primitives.

### `Ens.MessageHeader` Indexed Search Surface (the canonical lookup)

Verified directly from local source [`irislib/Ens/MessageHeader.cls`](irislib/Ens/MessageHeader.cls) lines 14–28 — these are the **only indexes** the IRIS optimizer can use without operator-installed customization:

| Index | Property | Type | Storage / Use |
|---|---|---|---|
| `Extent` | (extent) | **bitmap** | Full-extent enumeration marker |
| `TimeCreated` | TimeCreated | **standard** | **Primary time-window driver** for every search query |
| `Status` | Status | **bitmap** | Low-cardinality enum; combine via bitmap AND |
| `SourceConfigName` | SourceConfigName | **bitmap** | Config-host filter |
| `TargetConfigName` | TargetConfigName | **bitmap** | Config-host filter |
| `SessionId` | SessionId | **standard** | Session-trace expansion (used by inspection agent too) |
| `MessageBodyClassName` | MessageBodyClassName | **bitmap** | Message-class filter |
| `MessageBodyId` | MessageBodyId | **standard** | High-cardinality (~unique); header→body and SearchTable joins |
| `%ID` | (IDKEY) | implicit | Auto-increment, monotonic; keyset pagination |

`EXTENTSIZE = 20,000,000` is the optimizer's cardinality estimate, declared on the class — meaning IRIS sizes its plans for ~20M rows. **Confidence: High** — verified from authoritative source.

**Indexes that DO NOT exist by default — search tools must NOT lead with these predicates:**

- ❌ `IsError` — no index. Use `Status` (which carries error encoding) or apply `IsError` only as a residual filter after a more selective predicate narrows the row set.
- ❌ `Type` (Request/Response) — no index. Bound by `SessionId` or `TimeCreated` first.
- ❌ `CorrespondingMessageId` — no index. Walk request→response pairs via `%ID` join, not via this column.
- ❌ `TimeProcessed` — no index (only `TimeCreated` is indexed; this is a common pitfall).
- ❌ `SuperSession` on the header itself — query `Ens.SuperSessionIndex` instead (see below).
- ❌ `Description`, `TargetQueueName`, `ReturnQueueName`, `BusinessProcessId`, `Priority`, `Invocation`, `Resent` — no indexes.

### `Ens.SuperSessionIndex` — Cross-Session Lookup

Separate `%Persistent` class with two indexes:

- `SuperSession` indexed via `SQLUPPER(250)` — case-insensitive lookup on the supersession identifier.
- `MessageHeader` (FK to `Ens.MessageHeader`, `OnDelete=cascade`).

Maintained by `Ens.MessageHeader.%OnAfterSave` (lines 177–208 of `MessageHeader.cls`): on insert creates a row; on update only rewrites if `SuperSession` changed. Failure is swallowed (`Catch {}`) so the header save never aborts.

**Cross-instance lookup pattern:** `SELECT m.%ID, m.SessionId FROM Ens.SuperSessionIndex idx JOIN Ens.MessageHeader m ON idx.MessageHeader = m.%ID WHERE idx.SuperSession = ?`. This is the only indexed path to retrieve all headers participating in a multi-instance trace. Querying `Ens.MessageHeader.SuperSession` directly is a full-extent scan.

### Body-Field Search via SearchTable Pattern

Confirmed in source via `Ens.MessageHeader.Purge()` line 374 reference to `Ens.SearchTableBase.RemoveSearchTableEntries(...)`. The pattern:

- A SearchTable subclass extends `Ens.VDoc.SearchTable` / `Ens.SearchTableBase` and declares `<Item>` entries that XPath/property-extract a body field at save time.
- Entries are persisted as separate indexed rows keyed by `(DocId, PropId, PropValue)` — **this is the only indexed body-search surface.**
- Health Connect ships standard SearchTables with naming convention `<Family>.SearchTable` (e.g., `EnsLib.HL7.SearchTable`).
- To search bodies by an arbitrary field, the agent's tool joins `Ens.MessageHeader` to the SearchTable on `MessageBodyId`.

Direct SQL access on `MessageBody` columns (without a SearchTable) is a full scan plus a per-row object swizzle — operationally unusable on multi-million-row namespaces. **Confidence: Medium** — the class hierarchy is in `irislib`; recommend confirming against `https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=EGIN_options_searchtable` before shipping body-field search tools (Task-0 probe candidate).

### IRIS SQL Scale Patterns (2024.1)

For tools running against multi-million-row `Ens.MessageHeader`:

- **`%SQL.Statement` parameterized queries.** Canonical pattern: `Set tStmt = ##class(%SQL.Statement).%New() ; Set tSC = tStmt.%Prepare("SELECT TOP ? ID, Status FROM Ens.MessageHeader WHERE TimeCreated > ?") ; Set tRs = tStmt.%Execute(limit, since)`. Use positional `?` placeholders. **`TOP NULL` returns 0 rows, not all** — sentinel-large-int or omit `TOP` if you really want all rows. Cached-query optimization is automatic.
- **`TOP N` semantics.** IRIS applies `ORDER BY` first, then `TOP` selects from the ordered set — opposite of the common "TOP first" misconception. Without `ORDER BY`, results are unpredictable. *Source: [RSQL_top](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_top), [RSQL_order](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_order).*
- **Pagination at scale.** IRIS 2024.1 supports `OFFSET n ROWS FETCH FIRST m ROWS ONLY` — but **avoid for deep pagination on 10M-row tables.** Every page does a scan-and-discard up to the offset; cost grows linearly. Use **keyset / cursor pagination** instead: `WHERE %ID < :lastSeenId ORDER BY %ID DESC FETCH FIRST 50 ROWS ONLY`. Constant-time per page via the IDKEY.
- **Time-window patterns.** `DATEADD('hour', -24, CURRENT_TIMESTAMP)`, `DATEDIFF('day', t1, t2)`. **Pitfall: `CURRENT_TIMESTAMP` is server-local time, not UTC** — `Ens.MessageHeader.TimeCreated` is `Ens.DataType.UTC` stored in `$Horolog` UTC format; mismatched timezone produces silent wrong-windowed results. **Use `GETUTCDATE()` for UTC** or convert `TimeCreated` explicitly. *Source: [RSQL_dateadd](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_dateadd).*
- **Bitmap-index recognition.** The optimizer picks a bitmap path for `= constant` and `IN (a, b, c)` predicates against bitmap-indexed columns. **Avoid** `%STARTSWITH`, `LIKE`, function calls on indexed columns, and inequality operators (`<>`, `!=`) — these defeat bitmap lookup. Verify chosen plan with `EXPLAIN`.
- **`%PARALLEL` hint** (`FROM %PARALLEL Ens.MessageHeader`). Useful for analytical queries that scan many rows but return few (aggregates, `GROUP BY`). Avoid for OLTP-style point lookups; each query consumes worker processes. `AutoParallel=1` is on by default; explicit hint forces consideration. *Source: [GSOC_parallel](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=GSOC_parallel).*
- **Query timeouts.** Process-level `SET %SQLTIMEOUT = seconds` before `%Execute` is the supported per-process knob. Cancel a runaway: `CALL $SYSTEM.SQL.CancelQuery(pid, sqlid)` or DDL `CANCEL QUERY pid`. **Inside CSP context, the gateway timeout (60s default, 300s recommended per the inspection-agent doc's operator-prerequisite finding) bounds the request anyway** — the agent loop's per-tool budget should be well under the gateway timeout.
- **Stream columns** (`%Stream.GlobalCharacter`). Direct `SELECT streamCol` returns first 100 chars + `...`. Use `SUBSTRING(streamCol, 1, N)` for previews, `DATALENGTH(streamCol)` for size, `CONVERT(streamCol, VARCHAR(N))` for short streams. Other functions raise SQLCODE -37. *Source: [GSQL_blobs](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_blobs).*
- **`%SelectMode`** values (0=LOGICAL `$Horolog` for dates, 1=ODBC `YYYY-MM-DD`, 2=DISPLAY locale-formatted). **Set `tStmt.%SelectMode=1` (ODBC) for predictable date round-trips** in programmatic tool implementations; mismatched mode causes SQLCODE -146 on date predicates.

**Confidence: High** for the canonical patterns; **Medium** for `%PARALLEL` heuristics (workload-dependent).

### Cross-Stream Reconciliation — Two Substantive Conflicts Resolved

The Step 2 research streams disagreed on two facts. Both resolved against authoritative source:

**Conflict 1 — `%NOLOCK` semantics.** Stream A recommended `%NOLOCK` on every agent SELECT (citing it as a "dirty read trade-off worth taking"). Stream B asserted that **`%NOLOCK` is a DML-only hint in IRIS SQL** — valid only after `UPDATE`, `DELETE`, `INSERT`, `TRUNCATE` (e.g., `UPDATE %NOLOCK Ens.MessageHeader SET ...`); IRIS does not support dirty reads on SELECT, and `WITH (NOLOCK)` from TSQL is parsed-and-ignored on SELECT. Stream B cited `GTSQ_commands` and `RSQL_update`. **Resolution: Stream B is correct.** SELECT in IRIS is non-blocking by default — readers don't acquire shared locks against concurrent writers. **Search tools should NOT add `%NOLOCK` to SELECT statements; it has no effect and is confusing for future readers.** **Confidence: High**.

**Conflict 2 — `Ens.MessageHeader` index list.** Stream A read the source file directly and reported `IsError`, `Type`, `CorrespondingMessageId`, `Priority` as **NOT indexed**. Stream B asserted from generic IRIS knowledge that bitmap indexes exist on `Status`, `IsError`, `Type`, `Priority`. **Resolution: Stream A is correct.** Direct verification against `irislib/Ens/MessageHeader.cls` lines 14–28 (above) confirms the eight indexes listed; `IsError`, `Type`, `CorrespondingMessageId`, `Priority` are **NOT indexed by default**. Search tools must lead WHERE clauses with one of the eight indexed columns. **Confidence: High**.

### Per-User Vocabulary-Learning Architecture (Storage Primitive Layer)

Per the user's spec — the agent learns the search vocabulary the user employs over time — Step 2 establishes the storage primitives. Pattern detail and update logic land in Step 3-4. The candidate primitive class:

```
SessionAgent.Search.UserVocabulary  -- %Persistent
  PortalUser     %String(MAXLEN=64)  [Required]
  Alias          %String(MAXLEN=128) [Required]      // "failed admits"
  TemplateKind   %String(VALUELIST=",sql,toolargs,filterset")
  Template       %Stream.GlobalCharacter             // canonical form
  UseCount       %Integer  [InitialExpression=0]
  SuccessCount   %Integer  [InitialExpression=0]     // click-through occurred
  FailureCount   %Integer  [InitialExpression=0]     // refined/restarted
  Confidence     %Numeric(SCALE=3)                   // computed
  LastUsed       %TimeStamp
  CreatedVia     %String(VALUELIST=",explicit,clickthrough,extracted,seed")
  Source         %String(MAXLEN=64)                  // session-id that produced this row

  Index UserAlias On (PortalUser, Alias) [Unique]
  Index UserHot   On (PortalUser, Confidence, LastUsed)  // for digest ranking
```

Mirrors `SessionAgent.Chat.History` and `SessionAgent.Audit.ToolCall` shapes already defined in the inspection-agent doc — no new IRIS primitives needed; pure `%Persistent` + standard properties.

**Update path (storage-level — full pattern in Step 3):**

- **Click-through (primary, implicit):** Increment `UseCount` and `SuccessCount` on the contributing-tools' vocabulary entries when the operator clicks through to inspect a returned session.
- **Explicit save-as (always honored):** `Confidence=1.0, CreatedVia=explicit`. Highest priority.
- **Session-end batch extraction (defer to v1.5):** LLM-generated alias proposals; risky for PHI leakage so requires regex scrub before persisting.

**Retrieval-augmented prompting at turn time.** Per Anthropic prompt-caching contract (cited in the sibling doc §"LLM Provider HTTP APIs"), the cache prefix is `system + tools` — both must be byte-stable across turns to hit the cache. **The user-vocabulary digest must NOT ride in the cached prefix** — it changes per user, per session, and would shred the cache hit rate. Instead: inject a `<user_vocabulary>` block (top 15-20 entries by `Confidence DESC, LastUsed DESC`, ~800-1,200 tokens) **as the prefix of the first user message** — uncached, but cheap. Long tail accessible via a `vocab_lookup(alias)` callable tool.

A sibling `SessionAgent.Search.NamespaceVocabulary` (same schema, no `PortalUser`) provides a per-namespace baseline learned passively from cross-user high-confidence entries — bridges new users and cross-team common patterns. **Defer to v1.5** if scope-cutting.

### Privacy / PHI considerations for vocabulary learning

The product brief assumes PHI is segregated by IRIS namespace per InterSystems-customer policy; vocabulary inherits that namespace boundary by default (`SessionAgent.Search.UserVocabulary` lives in the same namespace as `SessionAgent.Chat.History`). **However: aliases extracted from chat history may embed MRN-like substrings.** v1 mitigation: regex-scrub digits-of-length-≥6 and known PHI-ish patterns before persisting an extracted alias. Explicit save-as is operator-typed and escapes scrubbing. Audit every insert via `$System.Security.Audit("SessionAgent","VocabWrite",...)` — events must be pre-registered per the project's existing audit-events rule.

### "Do this / Don't do this" Cheat Sheet for Search Tool Implementations

**Do:**

1. Use `%SQL.Statement` with `?` placeholders and explicit `%SelectMode = 1` (ODBC) for date filters.
2. Page with `WHERE %ID < :lastSeen ORDER BY %ID DESC FETCH FIRST n ROWS ONLY`.
3. Filter `Status`, `SourceConfigName`, `TargetConfigName`, `MessageBodyClassName` with `=` or `IN(...)` to hit the bitmap indexes.
4. Lead every WHERE clause with one of the eight indexed columns; apply non-indexed predicates as residual filters.
5. Use UTC explicitly for time windows (convert `TimeCreated` to UTC if comparing against `CURRENT_TIMESTAMP`).
6. Join through `Ens.SuperSessionIndex` for cross-session lookups, never via `Ens.MessageHeader.SuperSession` directly.

**Don't:**

1. Don't add `%NOLOCK` to SELECTs — it's a DML hint, ignored on SELECT, and SELECTs are non-blocking by default in IRIS.
2. Don't `OFFSET 100000 ROWS` on multi-million-row tables — keyset paginate by `%ID` instead.
3. Don't `SELECT streamColumn` directly — use `SUBSTRING(col, 1, N)`.
4. Don't put `LIKE`, `%STARTSWITH`, or `<>` on bitmap-indexed columns when `=` or `IN(...)` works.
5. Don't pass `NULL` to `TOP ?` expecting "all rows" — you get zero. Sentinel-large-int or omit `TOP`.
6. Don't query `IsError`, `Type`, `CorrespondingMessageId`, `TimeProcessed`, or any non-indexed column as the *leading* WHERE predicate — full-extent scan against 20M rows.
7. Don't search message-body fields without going through a `Ens.SearchTableBase` SearchTable — direct body-property SQL is a per-row swizzle.

### Confidence Notes & Task-0 Probes Carried Forward

- **`Ens.MessageHeader` index inventory**: **High** — read directly from `irislib/Ens/MessageHeader.cls`.
- **`Ens.SuperSessionIndex` shape**: **High** — read directly.
- **SearchTable / `<X>_AdditionalInfo` pattern**: **Medium** — class hierarchy verified in `irislib`; specific 2024.1 doc URL not surfaced. **Task-0 probe carried forward**: query an existing SearchTable subclass (e.g., `EnsLib.HL7.SearchTable`) on a populated dev instance and capture verbatim row shape before designing body-search tools.
- **`%NOLOCK` on SELECT (Stream A vs B conflict)**: **High** — Stream B's documentation citation overrules Stream A's misreading; IRIS SELECTs are non-blocking by default and `%NOLOCK` is a DML-only hint.
- **Vocabulary-learning primitive class shape**: **High** — mirrors existing `SessionAgent.Chat.History` / `SessionAgent.Audit.ToolCall` patterns; pure `%Persistent`, no new IRIS primitives.
- **Prompt-caching prefix stability for digest injection**: **High** — Anthropic contract verified in sibling doc; rules out cached-system-prompt injection of per-user vocabulary.

---

## Integration Patterns Analysis

> **Note on scope:** Step 3 covers what's distinct to the search problem — search-arg safety, scale-bounded query templates, vocabulary-learning update path, hand-off to the inspection agent, MessageViewer UX integration, and chat-keying without an Ens session id. The shared patterns (agent tool-call loop, provider abstraction, three-layer read-only enforcement, retry/backoff, error-handling-as-structured-tool-result) are inherited verbatim from the [sibling doc §"Integration Patterns Analysis"](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md#integration-patterns-analysis) and not restated here.

### How the Search Agent Reuses the Inspection Agent's Infrastructure

The `SessionAgent.Agent.AgentLoop.RunTurn` from the sibling doc is **agent-agnostic** — it accepts an `agentName` argument and routes to the corresponding tool registry. The Message Search Agent drives the same loop with three differences:

| Layer | Inspection Agent | Search Agent |
|---|---|---|
| Tool registry | `SessionAgent.Tool.Inspection.*` (13 tools — SQL + method-dispatch) | `SessionAgent.Tool.Search.*` (~8-10 tools — **all SQL-driven, no method-dispatch**) |
| Chat-history keying | `(agentName, irisSessionId, portalUser)` | `(agentName, searchSessionKey, portalUser)` — `searchSessionKey` is a registry-issued GUID, not an Ens session id |
| System prompt injection | Static system prompt + tool defs (cached) | Static system prompt + tool defs (cached) **+** uncached `<user_vocabulary>` block in first user message |
| Audit log enrichment | Standard `SessionAgent.Audit.{LlmCall,ToolCall}` rows | Standard rows **+** vocabulary-update writes to `SessionAgent.Search.UserVocabulary` |
| Lifecycle coupling | Chat history purges with `Ens.MessageHeader.Purge()` (Topic 10 Option B) | **No Ens-session coupling** — TTL-based or operator-clear (see §"Chat-Keying Lifecycle" below) |

Everything else — provider abstraction (4 concretes), retry policy, three-layer read-only enforcement, RBAC role, Markdown rendering bundle, IPM packaging — is **identical and shared**. Adding the search agent costs one new tool package, one new portal subclass extension (the chat tab on `SessionAgent.EnsPortal.MessageViewer`), and one new persistent class (`SessionAgent.Search.UserVocabulary`).

### Search-Arg-Construction Safety — SQL Injection Prevention as Three Layers

The LLM constructs tool arguments. Tool arguments become SQL parameters. **A confused or jailbroken LLM must never be able to inject SQL.** Three defensive layers, each independently sufficient against simple attacks; together a defense-in-depth posture appropriate for read-only-but-PHI-adjacent search:

| Layer | Mechanism | Enforced where |
|---|---|---|
| **L1 — Parameterized prepare** | Every search tool uses `%SQL.Statement.%Prepare(constantSqlString) + %Execute(:bindParam, :bindParam)` exclusively. **No string concatenation** of arg values into SQL. The constant SQL string is reviewable at compile-time; arg values pass through IRIS's parameter binding. | Inside each `SessionAgent.Tool.Search.*.Invoke()` |
| **L2 — Whitelist validation** | Free-form string args (e.g., `source_config_name` — operator-named hosts) validated against a regex (`[A-Za-z0-9_\-\.]+`, max 64 chars) at the top of `Invoke`. Reject with `{isError: true, content:[{type:"text", text:"argument failed validation"}]}` if the arg fails. List args (`status_in: [...]`) validated element-by-element. | Inside each `SessionAgent.Tool.Search.*.Invoke()` (top of method) |
| **L3 — Bounded WHERE clause requirement** | Every search tool's SQL **must** include at minimum one indexed-column predicate. Tools that take an "everything" query (e.g., a generic search-by-text) fall back to a default `TimeCreated >= DATEADD('hour', -24, GETUTCDATE())` window. **No tool may issue a SELECT that the optimizer would resolve as a full-extent scan.** Code review checklist + runtime QUERY plan inspection in tests. | `SessionAgent.Tool.Search.Base` constructor + Step 5 tests |

L1 alone defeats SQL injection. L2 catches an LLM passing exotic strings (`'; DROP TABLE`) before they ever hit the prepare. L3 protects the namespace's operational performance from a confused LLM that issues a search for "everything ever" without a sensible WHERE clause. **L3 is the search-agent-specific layer not present in the inspection agent** — the inspection agent's tools are bounded by the SessionId already.

Per the project's CLAUDE.md `IRIS SQL Case Sensitivity` rule, every string-equality predicate in a search tool wraps the indexed column with `%EXACT()` to preserve case-sensitive matching. Per the `%EXACT()` is also required on the SELECT projection to avoid case-folded display.

### Canonical Query Templates Per Indexed Access Path

The eight indexed columns from Step 2 yield exactly eight canonical query templates. Every search tool's SQL is a parameterization of one of these (or a `JOIN` of two for compound searches). Templates cited as canonical because they're the access paths the optimizer recognizes as bitmap or standard-index lookups.

| # | Lead column | Template | Tools that use this |
|---|---|---|---|
| 1 | `TimeCreated` (range) | `WHERE TimeCreated >= ? AND TimeCreated < ?` | Default time-window-bounded queries; recent-errors |
| 2 | `Status` (=, IN) | `WHERE %EXACT(Status) IN (?, ?, ?)` | Search-by-status; failed-this-week |
| 3 | `SourceConfigName` (=, IN) | `WHERE %EXACT(SourceConfigName) IN (?, ?)` | Search-by-source-config |
| 4 | `TargetConfigName` (=, IN) | `WHERE %EXACT(TargetConfigName) IN (?, ?)` | Search-by-target-config |
| 5 | `MessageBodyClassName` (=, IN) | `WHERE %EXACT(MessageBodyClassName) IN (?, ?)` | Search-by-message-class |
| 6 | `SessionId` (=) | `WHERE %EXACT(SessionId) = ?` | Drill-into-session (hand-off-prep) |
| 7 | `MessageBodyId` (=) — joined to SearchTable | `JOIN <X>.SearchTable st ON h.MessageBodyId = st.DocId WHERE st.PropName = ? AND %EXACT(st.PropValue) = ?` | Search-by-body-field (HL7 patient-id, MRN, order number) |
| 8 | `Ens.SuperSessionIndex.SuperSession` (=) | `JOIN Ens.SuperSessionIndex idx ON idx.MessageHeader = h.%ID WHERE idx.SuperSession = ?` | Cross-instance-trace |

Compound searches AND-combine multiple indexed columns. The optimizer's bitmap-index path handles `Status = ? AND SourceConfigName = ? AND MessageBodyClassName = ?` efficiently — these are the most operationally-common filter combinations.

**Time-window default:** Every search tool that takes a `time_window` arg defaults to `last 24 hours` if the arg is missing. The default is configurable per-user (see vocabulary-learning §below). The default exists to enforce the L3 bounded-WHERE requirement — there is no "search forever" mode in v1.

**Pagination:** `WHERE %ID < :lastSeenId ORDER BY %ID DESC FETCH FIRST 50 ROWS ONLY` — keyset, not OFFSET (per Step 2 cheat sheet).

### The Search-Result → Chat-Turn Refinement Cycle

A typical search session is multi-turn:

```
turn 1 → operator: "find HL7 ADT messages from last week with errors"
       agent calls search_by_class("EnsLib.HL7.Message") + search_by_status(["Error"])
                + time_window("last 7 days") → 247 results
       agent: "247 errored ADT messages in the last week. Want to narrow by source?"

turn 2 → operator: "yeah, just from EpicADT"
       agent calls narrow_results({source_config: "EpicADT"}) → 18 results
       agent: "18 from EpicADT. Top 5 by recency: ..." (lists with click-through links)

turn 3 → operator clicks session 3F2A8B...
       hand-off → inspection agent loads with that session id
```

Two architectural points fall out:

1. **Each turn's tool dispatch is independent SQL** — the agent does not maintain a "result-set cursor" in memory. The next turn's `narrow_results` tool re-runs the SQL with the additional filter. Correctness is automatic (no stale-result bugs); cost is bounded by the time-window on each turn (L3 invariant).
2. **The agent's `narrow_results` is just a multi-filter version of the indexed-column tools** — same templates from the table above, AND'd. No special "cursor narrowing" tool needed.

### Vocabulary-Learning Update Path

Three signals captured into `SessionAgent.Search.UserVocabulary` per the Step 2 storage primitive:

| Signal | When fired | What gets written |
|---|---|---|
| **Click-through (primary, implicit)** | Operator clicks a returned session row in the chat panel — fires a JS event that posts to a `RecordClickThrough(searchSessionKey, sessionId, contributingToolCalls)` ZenMethod | For each tool-call in `contributingToolCalls`, find or create a vocabulary row keyed `(portalUser, alias)` where alias = synthesized canonical name of the filter combination. Increment `UseCount` and `SuccessCount`. Refresh `Confidence`. |
| **Explicit save-as (always honored)** | Operator types or button-clicks "save this search as 'X'" | Create row with `Confidence=1.0, CreatedVia=explicit`. Highest priority for digest ranking. |
| **Refinement signal (negative-only)** | Operator issues a "narrow" or "restart" tool call within the same chat turn | Decrement `Confidence` on the prior turn's contributing rows by a small delta (e.g., 0.05). Do NOT create new rows from refinements — they're partial misses, not new vocabulary. |

The dispatch interceptor at `SessionAgent.Tool.Registry.Dispatch` is where the audit-log row gets written (per the inspection-agent doc). For the search agent specifically, the dispatch interceptor **also** captures the `contributingToolCalls` set into a request-scoped session-data structure that the click-through ZenMethod retrieves later. **`SessionAgent.Search.UserVocabulary` writes happen out-of-band** of the agent loop turn — not synchronously inside `RunTurn`, so a vocabulary write failure can never break the operator's chat experience.

The system prompt for the search agent has a templated section like:

```
<user_vocabulary>
This operator (alice@example.org) frequently uses:
- "failed admits" → search_by_class("EnsLib.HL7.Message") AND status="Error" AND class CONTAINS "ADT"
- "epic outbound" → search_by_target_config("EpicOutbound") AND time_window("last 24h")
- "MRN lookup" → search_by_body_field("PatientId") with whatever number the user gives
Default time window: 48 hours back
</user_vocabulary>
```

Top 15-20 entries by `Confidence DESC, LastUsed DESC`, ~800-1,200 tokens, injected as the prefix of the **first user message** of each chat session — uncached but cheap. Long tail accessible via a `vocab_lookup(alias)` callable tool. **Per Step 2, this digest must NOT ride in the cached prefix.**

### Hand-off Pattern: Search Agent → Inspection Agent

When the operator clicks a session row from the search agent's results:

1. The chat panel's JS captures the click event with the target `sessionId`.
2. Posts a `RecordClickThrough` ZenMethod (vocabulary-learning signal — see above).
3. **Navigates** to `SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<sessionId>&FROM_SEARCH=<searchSessionKey>` — the inspection agent's host page.
4. The inspection agent's `SessionAgent.EnsPortal.VisualTrace` reads the `FROM_SEARCH` URL parameter and, if present, loads the search agent's chat history briefly into a "context hint" stripe at the top of the chat tab — purely informational ("You came here from a search for: '247 ADT errors last week → 18 from EpicADT'").

**Two design candidates considered:**

- **(A) URL-parameter context-pass** — Selected. The `FROM_SEARCH` URL param is a short opaque key the inspection agent uses to look up the prior search context. Stateless from the operator's browser perspective, no shared `SessionAgent.Chat.HandoffContext` row needed. **Confidence: High** for simplicity.
- **(B) Cross-agent shared context row** — Rejected for v1. Adds a `%Persistent` class with a 24-hour TTL whose only purpose is to stash a "what brought us here" string. Over-engineered for v1. The URL-param approach scales fine for the operational scope.

### Audit Logging Enrichment for Search

The inspection agent's audit ledger (`SessionAgent.Audit.LlmCall` + `SessionAgent.Audit.ToolCall`) is reused. The search agent **adds** these fields to `SessionAgent.Audit.ToolCall`:

- `ResultSetSize` (`%Integer`) — number of rows the tool returned. Useful for vocabulary learning (a tool call returning 0 rows is a miss; a tool call returning 1-50 rows is the "happy zone"; a tool call returning 1000+ rows is too broad).
- `QueryTemplate` (`%String(MAXLEN=128)`) — the canonical name of the underlying query template (from the table above; e.g., `"time_window+status+source"`). Drives the vocabulary-learning alias synthesis.
- `IndexUsed` (`%String(MAXLEN=64)`) — the bitmap-or-standard index the optimizer picked. Captured via post-execution `EXPLAIN` (or skipped if too expensive). Helps debug "why was this slow" after the fact.

These fields are non-required (default empty for inspection-agent rows). Schema is shared; only search-agent dispatch populates them.

### UX Integration with EnsPortal.MessageViewer's Existing Filter UI

`EnsPortal.MessageViewer` (verified locally at `irislib/EnsPortal/MessageViewer.cls`) extends `EnsPortal.Template.filteredViewer` and inherits a filter pane (date, source, target, status, body class) plus result-set pagination via `onChangeResultsPage`. Two design questions:

**Does the agent populate the existing filter UI, or run its own SQL beneath it?** Recommendation: **run its own SQL beneath, then optionally update the filter UI as a secondary write.** Reasoning:

- The existing filter UI is operator-typed; the agent adapting to it correctly is brittle (filter UI may not expose all the indexed columns the agent wants to use, e.g., compound `MessageBodyClassName` filters).
- Running SQL beneath the filter UI lets the agent return result counts and a curated top-N list inline in the chat — same shape as the inspection-agent's tool returns.
- After a click-through, optionally writing the agent's selected filters into the filter pane (so the operator sees them on the page) is a UX nicety. **Defer to v1.5 if scope-cutting** — v1 ships with chat-only result display.

**Does the chat tab live alongside or replace the filter panel?** Alongside. The chat tab is a 4th tab on `SessionAgent.EnsPortal.MessageViewer` (mirroring the Phase 2 pattern from the inspection-agent doc); the filter panel and result grid stay where they are. Operators who prefer typed filters keep them; operators who prefer chat get a parallel surface.

### Chat-Keying Lifecycle — No Ens Session ID at Conversation Start

The inspection agent keys chat history on `(agentName, irisSessionId, portalUser)` — `irisSessionId` exists from page load (the operator opened a Visual Trace on a specific session). The search agent has **no `irisSessionId` at conversation start** — the operator is *looking for* one.

Recommended keying:

- **`searchSessionKey` = registry-issued GUID** generated when the operator opens the chat tab on `SessionAgent.EnsPortal.MessageViewer`. Stored in `%session.Data("AppSearchAgent","sessionKey")` for the duration of the portal session.
- **Per-portal-user-day rotation:** if the operator opens the chat tab on a fresh day (or after the portal session expires), a new GUID is generated. Avoids unbounded growth of stale chat-history rows.
- **Persistent until manual clear or TTL expiry.** A "Clear history" button in the chat tab calls `SessionAgent.Chat.History.%DeleteId(...)`. Otherwise rows persist for 30 days post-`UpdatedAt` (TTL sweep task — see below).

**Lifecycle (when do search-agent chat rows purge?):**

- The Topic 10 Option B sweep task from the inspection-agent doc filters on `WHERE AgentName = 'session-inspection'` — search-agent rows are explicitly excluded.
- A **separate** sweep task `SessionAgent.Task.PurgeStaleSearchChat` runs daily and deletes `SessionAgent.Chat.History` rows where `AgentName = 'message-search' AND UpdatedAt < (now - 30 days)`. Configurable retention via `SessionAgent.Config.Agent.SearchChatRetentionDays` (default 30).
- The 30-day default is conservative (operators may revisit a search several days later); operators can shorten or lengthen via config.

### Confidence Notes for Step 3 Findings

- **Search-arg safety three-layer pattern**: **High** — defense-in-depth against SQL injection is canonical and L3 (bounded WHERE) is project-specific, low-risk.
- **Eight canonical query templates**: **High** — directly mapped to the indexed columns verified in Step 2.
- **Vocabulary-learning update path**: **Medium-High** — the click-through signal capture is well-defined; the alias-synthesis from `contributingToolCalls` is a heuristic (a deterministic "canonical-form-stringification" of tool args) that may need tuning after observation. **Task-0 probe deferred to Step 5: implement and unit-test alias synthesis on canned tool-args.**
- **Hand-off via URL parameter**: **High** — simpler than a `%Persistent` `SessionAgent.Chat.HandoffContext` row and equivalently functional.
- **EnsPortal.MessageViewer 4th-tab pattern**: **High** — mirrors the inspection-agent doc's Phase 2 + Phase 3 patterns; the parent class hierarchy is verified locally.
- **30-day default chat retention**: **Medium** — operationally defensible but may need adjustment based on actual operator behavior post-launch. Configurable, so easy to tune.

---

## Architectural Patterns and Design

> **Note on scope:** The shared infrastructure (component diagram, class hierarchy roots, provider abstraction, three-layer read-only enforcement, security model, IPM packaging, deployment topology) is inventoried in the [sibling doc §"Architectural Patterns and Design"](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md#architectural-patterns-and-design). Step 4 here covers only the search-agent additions: the 8-tool catalog, the vocabulary-learning class family, the search-agent host page subclass, audit-log enrichments, configuration row defaults, and the search-agent-specific sweep task.

### Architectural Additions to the Component Diagram

The shared `SessionAgent.*` framework gains three new sub-packages and one new portal subclass:

```
                                                    NEW IN SEARCH-AGENT EPIC:
SessionAgent.Tool.Search.*   ────────────────  ←  (8 tools — see catalog below)
SessionAgent.Search.UserVocabulary       ────  ←  per-user vocabulary persistence
SessionAgent.Search.NamespaceVocabulary  ────  ←  per-namespace baseline (v1.5)
SessionAgent.Search.SeedVocabulary       ────  ←  ship-with seed templates
SessionAgent.Task.PurgeStaleSearchChat   ────  ←  TTL sweep (separate from Topic-10 sweep)
SessionAgent.EnsPortal.MessageViewer     ────  (already in shared map, gets a chat tab)
SessionAgent.UI.AgentConfig              ────  (already shared; gets a 2nd row in its list)
```

Everything else (`SessionAgent.Agent.AgentLoop`, `SessionAgent.LLM.Provider` family, `SessionAgent.Tool.{Base,Registry}`, `SessionAgent.Chat.History`, `SessionAgent.Config.Agent`, `SessionAgent.Audit.*`, `SessionAgent.Security.ReadOnlyRole`, the markdown bundle, IPM packaging, deployment topology) is inherited verbatim from the inspection-agent epic.

### The 8-Tool Search Catalog (v1)

Each tool is a `SessionAgent.Tool.Base` subclass under `SessionAgent.Tool.Search.*`. All have `MutatesState=0` and are blocked by Layer 2 + Layer 3 against any write attempt. Each tool's SQL is a parameterization of one of the eight canonical query templates from §"Canonical Query Templates Per Indexed Access Path" in Step 3.

| # | Tool class | Lead index | Purpose | Inputs (JSON Schema subset) |
|---|---|---|---|---|
| 1 | `SearchByTime` | `TimeCreated` | Default time-window listing of recent messages | `start`, `end` (ISO 8601 UTC); `top` (1-200, default 50) |
| 2 | `SearchByStatus` | `Status` | Filter by message status (e.g., Error, Completed) | `status_in` (array of allowed values); `time_window_hours` (default 24) |
| 3 | `SearchBySource` | `SourceConfigName` | Filter by source business host | `source_in` (array, max 10); `time_window_hours` (default 24) |
| 4 | `SearchByTarget` | `TargetConfigName` | Filter by target business host | `target_in` (array, max 10); `time_window_hours` (default 24) |
| 5 | `SearchByMessageClass` | `MessageBodyClassName` | Filter by message class (HL7 ADT, ORM, etc.) | `class_in` (array, max 5); `time_window_hours` (default 24) |
| 6 | `SearchBySession` | `SessionId` | Drill into a specific session (handoff prep) | `session_id` |
| 7 | `SearchByBodyField` | `MessageBodyId` (joined to SearchTable) | Find sessions by indexed body-field value (HL7 patient-id, MRN, order number) | `searchtable_class`, `prop_name`, `prop_value`; `time_window_hours` (default 168 = 7 days) |
| 8 | `SearchBySuperSession` | `Ens.SuperSessionIndex.SuperSession` | Find headers participating in a supersession trace | `supersession_id` |

**Compound filtering:** A single tool can take multiple indexed-column args (e.g., `SearchByStatus(status_in=["Error"], source_in=["EpicADT"], time_window_hours=24)`); the SQL builds an AND'd WHERE clause. This is preferred over multi-tool composition for the agent loop because it's one round-trip and the optimizer's bitmap-index intersection is efficient.

**Vocabulary lookup tool** (callable from the agent loop for the long-tail user vocabulary):

| # | Tool class | Purpose | Inputs |
|---|---|---|---|
| 9 (utility) | `VocabLookup` | Retrieve a saved alias by name (long-tail vocabulary not in the cached digest) | `alias` (string, max 128 chars) |

`VocabLookup` returns `{template_kind, template, confidence, last_used}` — the agent uses `template` to construct subsequent search-tool calls.

### Vocabulary-Learning Class Family (Concrete Schemas)

Three persistent classes:

```
SessionAgent.Search.UserVocabulary  -- per-user, primary
  PortalUser     %String(MAXLEN=64)  [Required]                        -- PK part 1
  Alias          %String(MAXLEN=128) [Required]                        -- PK part 2 ("failed admits")
  TemplateKind   %String(VALUELIST=",sql,toolargs,filterset")
  Template       %Stream.GlobalCharacter                                -- canonical form
  UseCount       %Integer  [InitialExpression=0]
  SuccessCount   %Integer  [InitialExpression=0]                        -- click-through occurred
  FailureCount   %Integer  [InitialExpression=0]                        -- refined/restarted
  Confidence     %Numeric(SCALE=3)                                      -- recomputed in OnUpdate
  LastUsed       %TimeStamp
  CreatedVia     %String(VALUELIST=",explicit,clickthrough,extracted,seed")
  Source         %String(MAXLEN=64)                                     -- session-id that produced this row
  Index PK   On (PortalUser, Alias) [Unique, PrimaryKey]
  Index Hot  On (PortalUser, Confidence, LastUsed)                      -- digest ranking

SessionAgent.Search.NamespaceVocabulary  -- per-namespace baseline (v1.5)
  -- (same shape minus PortalUser; used to bootstrap new users)

SessionAgent.Search.SeedVocabulary  -- ship-with operator-editable starter set
  -- (same shape minus PortalUser; populated by SessionAgent.Installer at install time)
```

**Confidence formula** (computed in `%OnAfterSave` trigger): `Confidence = SuccessCount / (SuccessCount + FailureCount + 1)`. The `+1` smooths early-life rows; a single click-through against zero failures yields 0.5, growing as success accumulates.

**Digest-assembly pseudocode** (`SessionAgent.Search.VocabularyDigest.Build(portalUser)`):

```
1. Query SessionAgent.Search.UserVocabulary:
     WHERE PortalUser = :user AND Confidence >= 0.3
     ORDER BY Confidence DESC, LastUsed DESC
     FETCH FIRST 20 ROWS ONLY
2. If fewer than 10 rows: union with SessionAgent.Search.NamespaceVocabulary
   (top 10 - count) entries.
3. If still fewer than 10: union with SessionAgent.Search.SeedVocabulary
   (top 10 - count) entries.
4. Render as a Markdown <user_vocabulary> block, ~800-1,200 tokens, injected
   as the prefix of the FIRST user message of the chat session. NEVER in the
   cached system prompt (per Step 2 prompt-caching invariant).
```

### `SessionAgent.EnsPortal.MessageViewer` Subclass

Same Phase-3 subclassing pattern as the inspection agent's `SessionAgent.EnsPortal.VisualTrace`. The subclass inherits everything from `EnsPortal.MessageViewer` (the IRIS-shipped class verified in `irislib/EnsPortal/MessageViewer.cls`) and:

1. **Adds a chat tab** to whichever XData pane drives the page's tab structure (Phase 2 pattern from the inspection-agent doc — `XData allTabs` override, `OnDrawContent="DrawChatPanel"`, agent-name-aware `DrawChatPanel` call).
2. **Reuses the shared `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`** — same `OnDrawContent` implementation as the inspection agent's chat tab; just passes `"message-search"` instead of `"session-inspection"` as the agent-name seed.
3. **Hosts the click-through hand-off** — when the operator clicks a session row in the chat panel results, the JS event posts `RecordClickThrough(searchSessionKey, sessionId, contributingToolCalls)` to record the vocabulary signal, then **navigates** to `/csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<sessionId>&FROM_SEARCH=<searchSessionKey>` (per Step 3 hand-off pattern).
4. **Does NOT modify the existing filter pane.** The inherited filter UI continues to work untouched. The chat panel runs SQL beneath it (per Step 3 UX-integration recommendation).
5. **Does NOT override `showTrace`** — the existing one-line `showTrace` override pattern in the original product brief is for navigating from MessageViewer → VisualTrace on a row click; for our search-agent's chat-panel-result click-through we navigate via the URL pattern above (which lands on the same VisualTrace subclass), so no double-override needed.

The new class is short — primarily an XData override and a few ZenMethods (`SendChatMessage`, `RecordClickThrough`, `ResetSearchChat`):

```objectscript
Class SessionAgent.EnsPortal.MessageViewer Extends EnsPortal.MessageViewer
{
  Parameter RESOURCE = "%Ens_MessageViewer:USE";  // inherited from parent

  XData allTabs [ XMLNamespace = "http://www.intersystems.com/zen" ]
  {
    <!-- inherited 4 tabs PLUS one new tab -->
    <tab id="searchChatTab" caption="Search Agent" title="Find sessions via natural-language chat">
      <html id="searchChatUI" OnDrawContent="DrawSearchChatPanel"/>
    </tab>
  }

  ClassMethod DrawSearchChatPanel(pSeed As %String) As %Status
  {
    Quit ##class(SessionAgent.EnsPortal.Util.ChatPanelDrawHelper).DrawChatPanel("message-search")
  }

  Method SendChatMessage(pAgentName, pSearchSessionKey, pUserText, pContextHints) As %String [ ZenMethod ]
  {
    // Same shape as inspection-agent's SendChatMessage; routes to AgentLoop.RunTurn
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn(
      pAgentName,
      pSearchSessionKey,
      %session.Username,
      pUserText,
      pContextHints
    )
    Quit tResult.%ToJSON()
  }

  Method RecordClickThrough(pSearchSessionKey, pSessionId, pContributingToolCallsJson) As %String [ ZenMethod ]
  {
    Quit ##class(SessionAgent.Search.UserVocabulary).RecordSuccess(
      %session.Username, pSearchSessionKey, pSessionId, pContributingToolCallsJson
    )
  }

  Method ResetSearchChat() As %String [ ZenMethod ]
  {
    Set tKey = $Get(%session.Data("SessionAgentSearch","sessionKey"))
    If tKey '= "" Do ##class(SessionAgent.Chat.History).%DeleteId("message-search||"_tKey_"||"_%session.Username)
    Kill %session.Data("SessionAgentSearch")
    Quit "{}"
  }
}
```

### Chat-Keying Lifecycle Implementation

The `searchSessionKey` GUID lives in `%session.Data("SessionAgentSearch","sessionKey")`. Initialization happens in the chat panel's first `SendChatMessage` call:

```objectscript
ClassMethod EnsureSearchSessionKey() As %String
{
  Set tKey = $Get(%session.Data("SessionAgentSearch","sessionKey"))
  If tKey = "" {
    Set tKey = $System.Util.CreateGUID()
    Set %session.Data("SessionAgentSearch","sessionKey") = tKey
    Set %session.Data("SessionAgentSearch","createdAt") = $ZDateTime($Horolog, 3, 1)
  }
  Quit tKey
}
```

GUID rotation rules:

- **Same key reused for the lifetime of the portal CSP session** (typically until `%session.AppTimeout` expires — default 15 min idle, refreshed on activity).
- **New key on next portal-session login** — `%session.Data` is reset on logout.
- **No daily-rotation enforcement in v1** — too aggressive; operators may want to revisit a search across a portal-session pause. Daily rotation can be added in v1.5 if vocabulary-learning rows accumulate too noisily.

### Audit-Log Enrichment Schema

The shared `SessionAgent.Audit.ToolCall` class gains three optional columns. Defaults for inspection-agent rows leave them empty:

```objectscript
Class SessionAgent.Audit.ToolCall Extends %Persistent
{
  // ... existing columns from inspection-agent doc ...

  /// Number of rows the tool returned. Search-agent only.
  Property ResultSetSize As %Integer;

  /// Canonical name of the underlying query template (e.g., "time_window+status+source").
  /// Search-agent only.
  Property QueryTemplate As %String(MAXLEN=128);

  /// The optimizer-chosen index, captured via post-execution EXPLAIN.
  /// Search-agent only; may be empty if EXPLAIN was skipped (cost-tradeoff).
  Property IndexUsed As %String(MAXLEN=64);
}
```

These columns are referenced by:

- `SessionAgent.Search.UserVocabulary.RecordSuccess()` to find the contributing tool calls when a click-through fires.
- The Step 6 vocabulary-extraction batch job (v1.5) for finding tool-arg combinations that consistently produce small (good) result sets.
- Operator-debugging queries ("which tool calls have been the slowest" → `WHERE QueryTemplate IS NOT NULL ORDER BY DurationMs DESC`).

### Configuration Architecture for the Search Agent

The `SessionAgent.Config.Agent` row for `AgentName='message-search'` ships with these defaults (set by `SessionAgent.Installer.SeedDefaultAgentConfigs()` per the inspection-agent doc):

| Field | Default | Notes |
|---|---|---|
| `AgentName` | `"message-search"` | Primary key |
| `Provider` | `"openai"` | Per scope amendment, OpenAI ships first |
| `Model` | `"gpt-4o"` | Cheaper than gpt-5 for search; result-set summarization is simpler than session narrative |
| `MaxTokens` | `2048` | Smaller than inspection (4096) — search responses are typically short lists |
| `Temperature` | `0.0` | Deterministic |
| `ReadOnly` | `1` | Same as inspection — Layer 2 enforcement |
| `EnvVarName` | `"OPENAI_API_KEY"` | Same env var as inspection by default |
| `CredentialName` | `""` | Operator can switch to a separate credential |
| `Enabled` | `0` | Off by default; operator opts in via `SessionAgent.UI.AgentConfig` |
| `SystemPromptOverride` | (empty — uses default) | The seed system prompt covers tool-use guidance and vocabulary-injection placeholder |

The seed system prompt for the search agent has a templated `<user_vocabulary>` placeholder that `SessionAgent.Agent.AgentLoop.RunTurn` replaces with the digest at turn time. **Per Step 2 prompt-caching invariant, the digest replacement happens in the FIRST USER MESSAGE, not in the system prompt itself** — so the system prompt's templated placeholder is rendered to a generic instruction ("the user vocabulary will be provided in your first user message; consult it before constructing tool calls").

### IPM Packaging — Additive Only

No changes to `module.xml` from the inspection-agent doc. The single `<Resource Name="SessionAgent.PKG"/>` resource line covers the new search classes automatically. The `SessionAgent.Installer.Install()` install hook gains:

- **`InstallSearchSweepTask()`** — schedules `SessionAgent.Task.PurgeStaleSearchChat` daily at 03:00 UTC (1 hour after the inspection-agent's purge sweep at 02:00, to avoid contention).
- **Updated `SeedDefaultAgentConfigs()`** — already inserts both `session-inspection` and `message-search` rows per the inspection-agent doc shape.
- **`SeedSearchVocabulary()`** — populates `SessionAgent.Search.SeedVocabulary` with ~10 ship-with starter templates (failed admits, last-24h errors, by-source filter, etc.). Operator-editable post-install via SQL or the config UI.
- **Updated operator README reminders** — adds bullet about `SessionAgent.EnsPortal.MessageViewer.zen` bookmark URL and a brief explainer about the per-user vocabulary feature.

### `SessionAgent.Task.PurgeStaleSearchChat` (TTL Sweep)

Mirrors the inspection-agent's Topic-10 Option-B sweep, but scoped to search-agent rows only with TTL semantics instead of Ens-coupling:

```objectscript
Class SessionAgent.Task.PurgeStaleSearchChat Extends %SYS.Task.Definition
{
  Parameter TaskName = "SessionAgent PurgeStaleSearchChat";

  Method OnTask() As %Status
  {
    Set tRetentionDays = ##class(SessionAgent.Config.Agent).GetSearchChatRetentionDays()  // default 30
    Set tCutoff = $ZDateTime($Horolog - tRetentionDays, 3, 1)
    Set tDeleted = 0
    &sql(DECLARE C1 CURSOR FOR
         SELECT %ID FROM SessionAgent_Chat.History
         WHERE AgentName = 'message-search' AND UpdatedAt < :tCutoff)
    &sql(OPEN C1)
    For { &sql(FETCH C1 INTO :id)  Quit:SQLCODE'=0
      Set tSC = ##class(SessionAgent.Chat.History).%DeleteId(id)
      Set:$$$ISOK(tSC) tDeleted = tDeleted + 1
    }
    &sql(CLOSE C1)
    Do ##class(%SYS.Audit).Audit("SessionAgent","TaskRun","PurgeStaleSearchChat",,,"Deleted="_tDeleted)
    Quit $$$OK
  }
}
```

Vocabulary rows are NOT swept by this task — they have their own decay logic (see Step 5).

### Confidence Notes for Step 4 Findings

- **8-tool catalog**: **High** — directly mapped to the eight indexed access paths from Step 2; each tool's SQL template is canonical.
- **Vocabulary class family schemas**: **High** — mirrors existing `SessionAgent.Chat.History` and `SessionAgent.Audit.ToolCall` patterns; uses only verified IRIS primitives.
- **Confidence formula `Success / (Success + Failure + 1)`**: **Medium** — defensible smoothing approach; alternatives (Wilson confidence interval, beta-distribution prior) are more sophisticated but add complexity. Re-litigate at Step 5 if early operator data shows the formula misranks vocabulary entries.
- **Digest assembly with 0.3 confidence threshold and 20-row cap**: **Medium** — operationally reasonable defaults, but the threshold and cap are tunable. **Task-0 probe deferred to Step 5: implement digest assembly and verify token-count of typical digests via Anthropic's token-counting endpoint or manual estimation.**
- **`SessionAgent.EnsPortal.MessageViewer` subclass shape**: **High** — mirrors the inspection-agent's `SessionAgent.EnsPortal.VisualTrace` Phase-2 pattern; XData override + ZenMethod hyperevents are stable Zen idioms.
- **Audit-log enrichment columns**: **High** — `%Persistent` schema additions are non-breaking; existing inspection-agent rows simply have the new columns empty.
- **TTL retention default of 30 days**: **Medium** — operationally defensible but tune-once-observed. Configurable via `SessionAgent.Config.Agent.SearchChatRetentionDays`.

---

## Implementation Approaches and Technology Adoption

> **Note on scope:** Step 5 here covers only the search-agent additions to the implementation surface defined in the [sibling doc §"Implementation Approaches and Technology Adoption"](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md#implementation-approaches-and-technology-adoption). The IPM `module.xml`, `SessionAgent.Installer.Install()`, `SessionAgent.LLM.OpenAIProvider`, `SessionAgent.Util.RetryWithBackoff`, `SessionAgent.Tool.Base`/`Registry`, `SessionAgent.Chat.History`, and `SessionAgent.Security.ReadOnlyRole.Install()` are all reused without modification. New code shown here: example search tool, vocabulary persistence methods, digest builder, click-through dispatch interceptor, search-agent installer additions, test strategy additions.

### Implementation Roadmap (Search-Agent Epic Sequence)

The search agent extends the inspection-agent's 11-epic plan with these epics — earliest start after Epic 6 (which delivers the inspection-agent OpenAI demo):

| # | Epic | Depends on (inspection-agent epics) | Purpose |
|---|---|---|---|
| 12 | `SessionAgent.Search.UserVocabulary` + `SessionAgent.Search.SeedVocabulary` + Installer additions | 1, 4 | Vocabulary persistence foundation; ship-with seed |
| 13 | 8-tool search catalog (`SessionAgent.Tool.Search.*`) + `VocabLookup` utility | 3, 12 | Search tool surface complete |
| 14 | Click-through capture (dispatch interceptor + `RecordSuccess` method) | 4, 12, 13 | Vocabulary signal capture |
| 15 | `SessionAgent.Search.VocabularyDigest.Build` (digest assembly) + first-user-message prefix injection in `AgentLoop.RunTurn` | 13, 14 | Retrieval-augmented prompting active |
| 16 | `SessionAgent.EnsPortal.MessageViewer` subclass + chat tab + `RecordClickThrough` ZenMethod + handoff URL navigation | 5, 6, 13 | Phase-3 search agent live |
| 17 | `SessionAgent.Task.PurgeStaleSearchChat` + retention config | 4 | TTL sweep operational |
| 18 (v1.5) | `SessionAgent.Search.NamespaceVocabulary` cross-user baseline + extraction batch job | 14 | Cross-user signal pickup |

Epics 12-17 land in the same release as inspection-agent epics 1-11; the IPM module ships both agents at once.

### Example Search Tool — `SessionAgent.Tool.Search.SearchByStatus`

Canonical pattern for the 8 indexed-column search tools. Other tools follow the same shape with different lead column and parameter set.

```objectscript
Class SessionAgent.Tool.Search.SearchByStatus Extends SessionAgent.Tool.Base
{
  Parameter ToolName = "search_by_status";
  Parameter Description = "Find Ensemble messages filtered by status (Error, Completed, etc.) within a time window. Bitmap-index path on Status; bounded by time window.";
  Parameter MutatesState = 0;

  ClassMethod GetInputSchema() As %DynamicObject
  {
    Quit {
      "type": "object",
      "properties": {
        "status_in": {
          "type": "array",
          "items": {"type": "string", "enum": ["Pending","InProcess","Completed","Error","Discarded","Suspended","Aborted","Deferred","Delivered","Queued","Resent","Resending","Pause"]},
          "description": "Allowed status values; OR'd"
        },
        "time_window_hours": {"type": "integer", "minimum": 1, "maximum": 720, "description": "Hours back from now; default 24, max 720 (30 days)"},
        "source_in": {"type": "array", "items": {"type": "string"}, "maxItems": 10, "description": "Optional: AND filter by source config name"},
        "target_in": {"type": "array", "items": {"type": "string"}, "maxItems": 10, "description": "Optional: AND filter by target config name"},
        "top": {"type": "integer", "minimum": 1, "maximum": 200, "description": "Result row cap; default 50"}
      },
      "required": ["status_in"],
      "additionalProperties": false
    }
  }

  ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
  {
    Set tSC = $$$OK
    Set pResult = {"content": [{"type": "text", "text": ""}], "structuredContent": {}}
    Try {
      ; L2 whitelist validation — reject anything that didn't pass schema enum
      Set tStatusIn = pJsonArgs.%Get("status_in")
      If 'tStatusIn.%Size() {
        Set pResult = {"isError": (1), "content": [{"type":"text","text":"status_in must be non-empty"}]}
        Return $$$OK
      }
      Set tWindowHours = +pJsonArgs.%Get("time_window_hours", 24)
      Set tTop = +pJsonArgs.%Get("top", 50)
      Set tSourceIn = pJsonArgs.%Get("source_in")
      Set tTargetIn = pJsonArgs.%Get("target_in")

      ; Validate optional source/target args (whitelist regex per Step 3 L2)
      For tArr = tSourceIn, tTargetIn {
        If $IsObject(tArr) {
          Set tIter = tArr.%GetIterator()
          While tIter.%GetNext(.k, .v) {
            If '$Match(v, "^[A-Za-z0-9_\-\.]+$") || ($Length(v) > 64) {
              Set pResult = {"isError": (1), "content": [{"type":"text","text":"invalid config name"}]}
              Return $$$OK
            }
          }
        }
      }

      ; Build SQL with parameterized placeholders for status_in array
      Set tStatusPlaceholders = "?"
      For i = 2:1:tStatusIn.%Size() Set tStatusPlaceholders = tStatusPlaceholders_",?"
      Set tSql = "SELECT TOP "_(+tTop)_" %ID, SessionId, %EXACT(Status), %EXACT(SourceConfigName), %EXACT(TargetConfigName), TimeCreated"_
                 " FROM Ens.MessageHeader"_
                 " WHERE %EXACT(Status) IN ("_tStatusPlaceholders_")"_
                 "   AND TimeCreated >= DATEADD('hour', -"_(+tWindowHours)_", GETUTCDATE())"
      ; Optional source/target AND clauses
      If $IsObject(tSourceIn) && tSourceIn.%Size() {
        Set tSrcPlaceholders = ""
        For i = 1:1:tSourceIn.%Size() Set tSrcPlaceholders = tSrcPlaceholders_$Select(i=1:"",1:",")_"?"
        Set tSql = tSql_" AND %EXACT(SourceConfigName) IN ("_tSrcPlaceholders_")"
      }
      If $IsObject(tTargetIn) && tTargetIn.%Size() {
        Set tTgtPlaceholders = ""
        For i = 1:1:tTargetIn.%Size() Set tTgtPlaceholders = tTgtPlaceholders_$Select(i=1:"",1:",")_"?"
        Set tSql = tSql_" AND %EXACT(TargetConfigName) IN ("_tTgtPlaceholders_")"
      }
      Set tSql = tSql_" ORDER BY TimeCreated DESC"

      Set tStmt = ##class(%SQL.Statement).%New()
      Set tStmt.%SelectMode = 1  ; ODBC mode for predictable date round-trip per Step 2
      Set tSC = tStmt.%Prepare(tSql)
      If $$$ISERR(tSC) Quit
      ; Build params array in the same order placeholders were emitted
      Set tParams = ##class(%ListOfDataTypes).%New()
      Set tIter = tStatusIn.%GetIterator()
      While tIter.%GetNext(.k, .v) Do tParams.Insert(v)
      If $IsObject(tSourceIn) {
        Set tIter = tSourceIn.%GetIterator()
        While tIter.%GetNext(.k, .v) Do tParams.Insert(v)
      }
      If $IsObject(tTargetIn) {
        Set tIter = tTargetIn.%GetIterator()
        While tIter.%GetNext(.k, .v) Do tParams.Insert(v)
      }
      Set tRs = tStmt.%Execute(tParams...)

      ; Shape result
      Set tRows = []
      Set tCount = 0
      While tRs.%Next() {
        Set tCount = tCount + 1
        Do tRows.%Push({
          "id":       (tRs.%Get("ID")),
          "sessionId":(tRs.%Get("SessionId")),
          "status":   (tRs.%Get("Status")),
          "source":   (tRs.%Get("SourceConfigName")),
          "target":   (tRs.%Get("TargetConfigName")),
          "time":     (tRs.%Get("TimeCreated"))
        })
      }
      Do pResult.structuredContent.%Set("rows", tRows)
      Do pResult.structuredContent.%Set("count", tCount)
      Do pResult.structuredContent.%Set("query_template", "status+time"_$Select($IsObject(tSourceIn):"+source", 1:"")_$Select($IsObject(tTargetIn):"+target", 1:""))
      Set pResult.content.%Get(0).text = "Found "_tCount_" messages matching status filter."
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
  }
}
```

Key invariants enforced inline (per Step 3 three-layer search-arg safety):

- **L1**: All values pass through `tStmt.%Execute(...)` parameter binding; no string concatenation of values into SQL.
- **L2**: Schema enum on `status_in`; regex validation on `source_in`/`target_in`; integer bounds on numeric args.
- **L3**: `TimeCreated` always present in WHERE; bounded by `time_window_hours` (default 24, max 720). Cannot construct an unbounded query.

Other tools in `SessionAgent.Tool.Search.*` follow the same shape, swapping the lead column and the args-validation set.

### `SessionAgent.Search.UserVocabulary` Persistence Methods

```objectscript
Class SessionAgent.Search.UserVocabulary Extends %Persistent
{
  // ... properties from Step 4 schema ...

  /// Recompute Confidence on every save.
  Method %OnAfterSave() As %Status
  {
    Set tDenom = ..SuccessCount + ..FailureCount + 1
    Set ..Confidence = ..SuccessCount / tDenom
    ; Avoid recursive %Save — write directly via SQL
    &sql(UPDATE SessionAgent_Search.UserVocabulary SET Confidence = :..Confidence WHERE %ID = :..%Id())
    Quit $$$OK
  }

  /// Capture a click-through signal. Called from RecordClickThrough ZenMethod.
  ClassMethod RecordSuccess(
    pPortalUser As %String,
    pSearchSessionKey As %String,
    pSessionId As %String,
    pContributingToolCallsJson As %String
  ) As %String
  {
    Set tCalls = {}.%FromJSON(pContributingToolCallsJson)
    Set tIter = tCalls.%GetIterator()
    While tIter.%GetNext(.k, .call) {
      Set tAlias = ..SynthesizeAlias(call)  ; deterministic stringification of tool args
      Set tId = pPortalUser_"||"_tAlias
      Set tRow = ..%OpenId(tId, 4)  ; concurrency=4 for read-modify-write
      If '$IsObject(tRow) {
        Set tRow = ..%New()
        Set tRow.PortalUser = pPortalUser
        Set tRow.Alias = tAlias
        Set tRow.TemplateKind = "toolargs"
        Do tRow.Template.Write(call.%ToJSON())
        Set tRow.CreatedVia = "clickthrough"
        Set tRow.Source = pSearchSessionKey
      }
      Set tRow.UseCount = tRow.UseCount + 1
      Set tRow.SuccessCount = tRow.SuccessCount + 1
      Set tRow.LastUsed = $ZDateTime($Horolog, 3, 1)
      Set tSC = tRow.%Save()  ; triggers Confidence recompute via %OnAfterSave
      $$$LogIfErr(tSC, "RecordSuccess: save failed for "_tId)
    }
    Quit "{""ok"": true, ""recorded"": "_tCalls.%Size()_"}"
  }

  /// Symmetric to RecordSuccess; called when the operator refines or restarts mid-turn.
  ClassMethod RecordFailure(pPortalUser, pPriorTurnContributingCallsJson) As %Status
  {
    Set tCalls = {}.%FromJSON(pPriorTurnContributingCallsJson)
    Set tIter = tCalls.%GetIterator()
    While tIter.%GetNext(.k, .call) {
      Set tAlias = ..SynthesizeAlias(call)
      Set tRow = ..%OpenId(pPortalUser_"||"_tAlias, 4)
      Continue:'$IsObject(tRow)  ; only decrement existing rows; never create from refinement
      Set tRow.FailureCount = tRow.FailureCount + 1
      Do tRow.%Save()
    }
    Quit $$$OK
  }

  /// Deterministic canonical-form stringification of a tool-args object.
  /// Same args produce same alias regardless of property order.
  ClassMethod SynthesizeAlias(pCall As %DynamicObject) As %String
  {
    ; Form: "tool_name|key1=val1|key2=val2|..." with keys sorted lex
    Set tName = pCall.%Get("name")
    Set tArgs = pCall.%Get("input")  ; canonical Anthropic shape
    Set tKeys = ""
    Set tIter = tArgs.%GetIterator()
    While tIter.%GetNext(.k, .v) {
      Set tKeys($Increment(tKeys)) = k_"="_..SerializeArgValue(v)
    }
    ; Sort keys
    Set tSorted = ""
    For i = 1:1:tKeys Set tSorted = tSorted_$Select(i=1:"", 1:"|")_tKeys(i)
    ; (Real implementation sorts; pseudocode skips for brevity)
    Quit $Extract(tName_"|"_tSorted, 1, 128)  ; truncate to MAXLEN
  }

  ClassMethod SerializeArgValue(pVal) As %String
  {
    If $IsObject(pVal) Quit "[array:"_pVal.%ToJSON()_"]"
    Quit $Translate(pVal, "|", "_")  ; escape pipe for the alias delimiter
  }

  /// Decay sweep — called by the daily purge task.
  ClassMethod DecaySweep() As %Status
  {
    Set tCutoff = $ZDateTime($Horolog - 90, 3, 1)
    &sql(DELETE FROM SessionAgent_Search.UserVocabulary
         WHERE Confidence < 0.2 AND LastUsed < :tCutoff)
    Quit $$$OK
  }
}
```

### `SessionAgent.Search.VocabularyDigest.Build` (Digest Assembly)

```objectscript
Class SessionAgent.Search.VocabularyDigest Extends %RegisteredObject
{
  Parameter MaxEntries = 20;
  Parameter MinUserConfidence = 0.3;

  /// Build the user-vocabulary block to inject as the first-user-message prefix.
  ClassMethod Build(pPortalUser As %String) As %String
  {
    Set tEntries = ""
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tStmt.%SelectMode = 1
    Do tStmt.%Prepare(
      "SELECT TOP ? Alias, Template, Confidence FROM SessionAgent_Search.UserVocabulary "_
      "WHERE PortalUser = ? AND Confidence >= ? "_
      "ORDER BY Confidence DESC, LastUsed DESC"
    )
    Set tRs = tStmt.%Execute(..#MaxEntries, pPortalUser, ..#MinUserConfidence)
    Set tCount = 0
    While tRs.%Next() {
      Set tCount = tCount + 1
      Set tEntries = tEntries_"- """_tRs.%Get("Alias")_""" → "_tRs.%Get("Template")_$c(10)
    }
    ; Fall back to namespace baseline / seed if too few user rows
    If tCount < 10 {
      Do ..AppendNamespaceBaseline(.tEntries, .tCount, ..#MaxEntries - tCount)
    }
    If tCount < 10 {
      Do ..AppendSeed(.tEntries, .tCount, ..#MaxEntries - tCount)
    }
    If tCount = 0 Quit ""  ; no vocabulary at all — first-time user with no seed
    Quit "<user_vocabulary>"_$c(10)_
         "This operator ("_pPortalUser_") frequently uses these search aliases:"_$c(10)_
         tEntries_
         "Apply the canonical templates above when the operator's wording matches an alias. "_
         "If their wording matches no alias, construct fresh tool args."_$c(10)_
         "</user_vocabulary>"_$c(10)
  }

  ClassMethod AppendNamespaceBaseline(ByRef pEntries, ByRef pCount, pBudget) As %Status
  { /* similar shape, queries SessionAgent.Search.NamespaceVocabulary */ }

  ClassMethod AppendSeed(ByRef pEntries, ByRef pCount, pBudget) As %Status
  { /* similar shape, queries SessionAgent.Search.SeedVocabulary */ }
}
```

The digest is invoked by `SessionAgent.Agent.AgentLoop.RunTurn` **only on the first turn of a new chat session** (when `App.Chat.History.GetTurnsArray()` returns empty). The digest is then prepended to the operator's first user message before append-to-history. Subsequent turns reuse the existing history.

### Click-Through Dispatch Interceptor — Capturing `contributingToolCalls`

The `SessionAgent.Tool.Registry.Dispatch` interceptor (defined in the inspection-agent doc) gains a request-scoped capture for the search agent:

```objectscript
ClassMethod Dispatch(pAgentName, pToolName, pCallerCtx, pJsonArgs, Output pResult) As %Status
{
  ; ... existing inspection-agent dispatch logic ...

  ; Search-agent-specific: capture contributing tool calls for click-through correlation
  If pAgentName = "message-search" {
    Set tCallId = $System.Util.CreateGUID()
    Set tCall = {"name": (pToolName), "input": (pJsonArgs)}
    Set tKey = pCallerCtx.SessionKey  ; the searchSessionKey GUID
    Set %session.Data("SessionAgentSearch","contributingCalls", tKey, tCallId) = tCall.%ToJSON()
  }

  ; ... call tool, log audit row, return ...
}
```

When `RecordClickThrough(searchSessionKey, sessionId, ...)` ZenMethod fires from the chat panel JS, it gathers all `%session.Data("SessionAgentSearch","contributingCalls", tKey, *)` entries for that key and passes them as the `contributingToolCallsJson` arg to `SessionAgent.Search.UserVocabulary.RecordSuccess`. The `%session.Data` cache is cleared after a successful click-through (a turn-level cleanup at end-of-turn would also be sufficient).

### `SessionAgent.Installer` Additions

The installer body from the inspection-agent doc gains four call sites:

```objectscript
ClassMethod Install(pInstance As %String = "iris-session-agent") As %Status
{
  Set tSC = $$$OK
  Set tOrigNS = $NAMESPACE
  Try {
    ; ... existing 6 install steps from inspection-agent doc ...

    ; (7) NEW: Install search-agent-specific sweep task (offset 1 hour from inspection)
    Set tSC = ..InstallSearchSweepTask()  Quit:$$$ISERR(tSC)

    ; (8) NEW: Seed ship-with vocabulary templates
    Set tSC = ..SeedSearchVocabulary()    Quit:$$$ISERR(tSC)

    ; (9) NEW: Schedule decay sweep on UserVocabulary (weekly, Sunday 04:00 UTC)
    Set tSC = ..InstallVocabularyDecayTask()  Quit:$$$ISERR(tSC)
  }
  Catch ex { Set tSC = ex.AsStatus() }
  Set $NAMESPACE = tOrigNS
  Quit tSC
}

ClassMethod InstallSearchSweepTask() As %Status
{
  Set tTask = ##class(%SYS.Task).%New()
  Set tTask.Name = "SessionAgent.PurgeStaleSearchChat"
  Set tTask.NameSpace = $NAMESPACE
  Set tTask.TaskClass = "SessionAgent.Task.PurgeStaleSearchChat"
  Set tTask.DailyFrequency = 0
  Set tTask.StartDate = +$Horolog
  Set tTask.DailyStartTime = 10800  ; 03:00 UTC, in seconds since midnight
  Quit tTask.%Save()
}

ClassMethod SeedSearchVocabulary() As %Status
{
  Set tSeeds = $ListBuild(
    $ListBuild("failed admits", "toolargs", "{""name"":""search_by_message_class"",""input"":{""class_in"":[""EnsLib.HL7.Message""],""status_in"":[""Error""],""time_window_hours"":24}}"),
    $ListBuild("recent errors",  "toolargs", "{""name"":""search_by_status"",""input"":{""status_in"":[""Error""],""time_window_hours"":24}}"),
    $ListBuild("today by source", "toolargs", "{""name"":""search_by_source"",""input"":{""time_window_hours"":24}}"),
    $ListBuild("supersession lookup", "toolargs", "{""name"":""search_by_supersession"",""input"":{}}")
    ; ...etc, ~10 total
  )
  Set tPtr = 0
  While $ListNext(tSeeds, tPtr, tSeed) {
    Set tAlias = $ListGet(tSeed, 1)
    If '##class(SessionAgent.Search.SeedVocabulary).%ExistsId(tAlias) {
      Set tRow = ##class(SessionAgent.Search.SeedVocabulary).%New()
      Set tRow.Alias = tAlias
      Set tRow.TemplateKind = $ListGet(tSeed, 2)
      Do tRow.Template.Write($ListGet(tSeed, 3))
      Set tRow.CreatedVia = "seed"
      Set tSC = tRow.%Save()
      $$$LogIfErr(tSC, "SeedSearchVocabulary: save failed for "_tAlias)
    }
  }
  Quit $$$OK
}

ClassMethod InstallVocabularyDecayTask() As %Status
{
  Set tTask = ##class(%SYS.Task).%New()
  Set tTask.Name = "SessionAgent.UserVocabularyDecay"
  Set tTask.NameSpace = $NAMESPACE
  Set tTask.TaskClass = "SessionAgent.Task.UserVocabularyDecay"
  Set tTask.WeeklyFrequency = 0  ; weekly
  Set tTask.WeeklyDays = 1  ; Sunday
  Set tTask.DailyStartTime = 14400  ; 04:00 UTC
  Quit tTask.%Save()
}
```

The decay task itself is a one-line wrapper:

```objectscript
Class SessionAgent.Task.UserVocabularyDecay Extends %SYS.Task.Definition
{
  Parameter TaskName = "SessionAgent UserVocabularyDecay";
  Method OnTask() As %Status
  {
    Quit ##class(SessionAgent.Search.UserVocabulary).DecaySweep()
  }
}
```

### Operator README Additions

Append to the operator README from the inspection-agent doc:

```markdown
### 8. Message Search Agent

The Message Search Agent provides natural-language search over Ens.MessageHeader.

- Bookmark URL: /csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen
  Click the "Search Agent" tab to chat.
- The agent learns each operator's search vocabulary over time (per portal user).
  Aliases the operator click-throughs frequently bubble up in the agent's prompt.
- Default chat retention is 30 days. Adjust via:
    UPDATE SessionAgent_Config.Agent SET SearchChatRetentionDays = 60
    WHERE AgentName = 'message-search'
- Vocabulary decay: rows with Confidence < 0.2 and LastUsed > 90 days ago are
  pruned weekly. Adjust the SessionAgent.Task.UserVocabularyDecay task schedule
  if you want a different cadence.
- Seed vocabulary lives in SessionAgent_Search.SeedVocabulary. Edit via SQL or
  the SessionAgent.UI.AgentConfig page (v1.5).
```

### Test Strategy Additions (Search-Agent-Specific)

Adds four test layers to the inspection-agent test strategy:

| Layer | Test scope | Notes |
|---|---|---|
| Unit | Each search tool's `Invoke` against canned `Ens.MessageHeader` rows; `SynthesizeAlias` deterministic stringification; `Confidence` formula | Mock `Ens.MessageHeader` rows in `OnBeforeOneTest`; tear down. Verify deterministic alias for same-args-different-order. |
| Integration | End-to-end click-through: insert vocab row, click-through, verify `UseCount`/`SuccessCount` increment and `Confidence` recompute | Use `%UnitTest.TestCase` with two-step setup. |
| Scale | Load 100k `Ens.MessageHeader` rows, run each search tool, verify p95 latency < 500ms | Skip in default CI; gated behind `SESSIONAGENT_RUN_SCALE_TESTS=1` env flag. |
| Vocabulary digest | Build digest with 0/5/15/25 user rows, verify token count via `App.Util.Json.EstimateTokens` (or simple char/4 estimate); verify cascade to namespace/seed when user rows are sparse | Token estimate ≤1,500 tokens per Step 2 budget. |

### Confidence Notes for Step 5 Findings

- **`SearchByStatus` example pattern**: **High** — directly applies Step 2 (indexed columns) + Step 3 (three-layer arg safety).
- **`SynthesizeAlias` deterministic stringification**: **Medium** — pseudocode shows the shape; real implementation needs sort-keys-lex helper. **Task-0 carry-forward: unit-test the alias function against ~10 reordering scenarios before relying on it for vocabulary keying.**
- **`%OnAfterSave` SQL UPDATE to avoid recursion**: **Medium** — established IRIS idiom but needs verification on 2024.1 (specifically that `%OnAfterSave` issuing a SQL UPDATE on the same row does NOT re-fire `%OnAfterSave`).
- **Click-through `%session.Data` capture pattern**: **High** — uses already-vetted CSP session data idiom; cleanup at click-through completion.
- **Installer additions**: **High** — additive shape, no breaking changes to inspection-agent install path.
- **30/90-day retention defaults**: **Medium** — operationally reasonable; configurable post-launch.
- **100k-row scale test threshold**: **Medium** — round number; may need adjustment when actual customer namespaces are profiled. Document the test configurability so operators can tune up to their actual scale.

---

## Research Synthesis & Executive Summary

### The Bottom Line

The Message Search Agent ships as **additive code on top of the Session Inspection Agent's framework** — ~80% of the codebase reuses verbatim, with the deltas concentrated in eight SQL-driven search tools over `Ens.MessageHeader`'s indexed access paths plus a per-user vocabulary-learning class family. The hardest architectural challenge is **not the LLM agent loop or the SQL** but **bounding query cost in namespaces with millions of `Ens.MessageHeader` rows** — solved by an L3 invariant that every search SQL must lead with at least one of the 8 indexed columns and include a default 24-hour `TimeCreated` window. The riskiest non-obvious finding: `Ens.MessageHeader` does **not** index `IsError`, `Type`, `CorrespondingMessageId`, `TimeProcessed`, or `Priority` — easy to assume otherwise, expensive to discover at runtime against a 20M-row table.

### Top Findings (the seven that matter most)

1. **Only 8 indexed access paths exist on `Ens.MessageHeader`**, verified directly from `irislib/Ens/MessageHeader.cls` lines 14–28: `Extent` (bitmap), `TimeCreated` (standard), `Status` (bitmap), `SourceConfigName` (bitmap), `TargetConfigName` (bitmap), `SessionId` (standard), `MessageBodyClassName` (bitmap), `MessageBodyId` (standard). Plus `%ID` (IDKEY). **`IsError`, `Type`, `CorrespondingMessageId`, `TimeProcessed`, `Priority`, `Description`, queue names — none indexed.** This single fact drives the entire search-tool design.
2. **Body-field search requires `Ens.SearchTableBase` SearchTables.** No SearchTable → no indexed body-field search → full-extent scan + per-row swizzle on multi-million-row tables. SearchTable shape verification carried forward as a Task-0 probe.
3. **`%NOLOCK` is a DML-only hint in IRIS SQL** — ignored on SELECT; SELECTs are non-blocking by default. Don't add `%NOLOCK` to search-tool SQL; it has no effect and confuses readers.
4. **The L3 bounded-WHERE invariant is the difference between "agent works at scale" and "agent kills the production server."** Every search tool must lead WHERE with at least one indexed column AND include a default `TimeCreated` window of 24h (max 720h / 30d). No "search forever" mode in v1.
5. **Vocabulary digest cannot ride in the cached system prompt.** Per-user, per-session content shreds Anthropic's prompt-cache hit rate. Inject as the **first user message prefix** instead — uncached but cheap (~800-1,200 tokens). Long tail accessible via a `vocab_lookup` callable tool.
6. **The hand-off from search agent → inspection agent is a URL parameter**, not a shared `%Persistent` `HandoffContext` row. Stateless, simpler, scales fine.
7. **Click-through is the highest-signal vocabulary input.** Operator clicking through to inspect a returned session = "this result was relevant" = positive signal. Capture via JS event → `RecordClickThrough` ZenMethod → `UserVocabulary.RecordSuccess()`. **Vocabulary writes happen out-of-band of the agent loop** so a write failure can never break the chat.

### Strategic Recommendations (top six)

1. **Implement after inspection-agent Epic 6 (the OpenAI demo).** The shared framework needs to exist before the search-specific code can land; epics 12-17 follow naturally.
2. **Ship the SearchTable Task-0 probe in Epic 12.** Verify the SearchTable shape on the operator's instance before writing `SearchByBodyField`. If the operator hasn't installed Health Connect SearchTables, body-field search degrades to "not available" gracefully — better than silent full-table-scan disasters.
3. **Default vocabulary-extraction triggers to click-through-only in v1.** LLM-extracted aliases from chat transcripts (the §"Update Path" item (b)) is appealing but PHI-leakage-risky. Defer to v1.5 once click-through baseline is observed in production.
4. **Make the 24-hour default time window operator-configurable per user via `UserVocabulary`.** Some operators routinely search the last 7 days; some only the last hour. Capture this as a learned preference, not a hardcoded default.
5. **Plan for the v1.5 namespace baseline now even though it's deferred.** The schema is identical to `UserVocabulary` minus `PortalUser`; shipping the empty class in v1 means v1.5 is just population logic.
6. **Re-evaluate the 30-day retention default at PRD-time** if compliance constraints surface. Configurable via `SessionAgent.Config.Agent.SearchChatRetentionDays`; operators in regulated environments may need shorter.

### Risk Roll-Up (consolidated from confidence notes across all steps)

| Risk | Severity | Mitigation in v1 |
|---|---|---|
| **Tool issues full-table scan against 20M rows** | High (catastrophic at scale) | L3 invariant: every search WHERE must lead with an indexed column + time window. Code review checklist. Scale test gated behind env flag. |
| **SearchTable not installed on operator's namespace** | Medium | Task-0 probe in Epic 12; `SearchByBodyField` returns graceful "not configured" error, not a scan. |
| **Vocabulary digest exceeds prompt-caching budget** | Medium | Token estimate in test layer; cap at top-20 entries / 1,200 tokens; degrade gracefully (truncate digest, not chat). |
| **`SynthesizeAlias` non-determinism (different keys-orders → different aliases)** | Medium | Task-0 carry-forward: unit test against ~10 reordering scenarios before relying on it. |
| **`%OnAfterSave` recursion via Confidence recompute** | Medium | Task-0 carry-forward: verify `%OnAfterSave` issuing SQL UPDATE on the same row does NOT re-fire. Direct SQL UPDATE bypasses ORM. |
| **PHI-like substrings leak into extracted aliases** | Medium | v1: extracted-alias path deferred. Click-through-only signal capture in v1; explicit save-as escapes scrubbing. |
| **Chat-history rows accumulate without bound when operators leave tabs open** | Low (configurable) | TTL sweep + `%session.AppTimeout` GUID rotation + 30-day default retention. |
| **Bitmap-index path defeated by `LIKE`/`%STARTSWITH`/`<>`** | Low (within our control) | Tools use `=` and `IN(...)` only against bitmap-indexed columns; code review checklist + EXPLAIN inspection in tests. |
| **OpenAI tool-call quality on smaller models** | Low (covered in inspection-agent doc) | Same retry-with-correction loop; default to gpt-4o for search. |
| **Confidence formula misranks** (`Success / (Success + Failure + 1)`) | Low | Simple smoothing; observable post-launch via audit log; can be swapped for Wilson interval if data shows misranking. |

### Task-0 Probes Carried Forward to Implementation

Per the project's `research-first.md` rule 4 — execute on a live 2024.1 instance **before** the implementation story they unblock is dispatched:

1. **SearchTable shape verification** — query an existing SearchTable subclass (e.g., `EnsLib.HL7.SearchTable`) and capture verbatim row shape `(DocId, PropName, PropValue)`. Unblocks Epic 13's `SearchByBodyField` tool.
2. **`SynthesizeAlias` determinism unit test** — run the alias function against ~10 reordering scenarios (same args, different key order) and verify identical output. Unblocks Epic 14 (vocabulary capture).
3. **`%OnAfterSave` non-recursion verification** — confirm that `%OnAfterSave` issuing a SQL UPDATE on the same row does NOT re-fire `%OnAfterSave` on 2024.1. Unblocks Epic 12 (vocabulary persistence).

Plus the three carried forward from the inspection-agent doc (Dictionary reflection, embedded-SQL `SELECT INTO :exists`/`SQLCODE=100` semantics, Web Gateway timeout default).

### Open Questions (defer to PRD or post-launch observation)

1. **PHI-redaction policy for extracted aliases (v1.5).** When LLM-extracted alias generation lands, the regex-scrub for digits-of-length-≥6 is a starting point — but a more sophisticated policy (e.g., named-entity recognition on alias text) may be needed for regulated environments. Decision belongs to the PRD when v1.5 scope is finalized.
2. **Cross-tab vocabulary contamination.** Operator opens two `MessageViewer` tabs in different namespaces; each captures vocabulary into the same `UserVocabulary` row keyed only by `(PortalUser, Alias)`. A row aggregated from "EpicADT" namespace and "MeditechORM" namespace could become nonsensical. Possible v1.5 fix: include `Namespace` in the primary key. Defer until cross-namespace contamination is observed.
3. **Search agent's chat history isn't visible to the inspection agent.** When the operator clicks through, the inspection agent sees a context-hint stripe ("you came here from search...") but doesn't have access to the search conversation's message history. Could enrich the inspection agent's first turn with the search transcript, but operators may prefer fresh context. PRD-time decision.
4. **Operator-curated vocabulary export/import across IRIS instances.** `%Library.Persistent.%Export()` works for one operator's rows; multi-operator export with merge semantics is a v1.5+ concern.

### Source Documentation Recap

**Authoritative IRIS sources** — verified directly:

- [`irislib/Ens/MessageHeader.cls`](irislib/Ens/MessageHeader.cls) lines 14–28 (8-index inventory; the load-bearing fact for the entire search design)
- [`irislib/Ens/SuperSessionIndex.cls`](irislib/Ens/SuperSessionIndex.cls) (cross-session lookup mechanism)
- [`irislib/EnsPortal/MessageViewer.cls`](irislib/EnsPortal/MessageViewer.cls) (host page for the chat tab subclass)

**InterSystems documentation** — pinned to 2024.1 surface where possible:

- [Web Gateway Configure System-Wide Parameters](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCGI_oper_config) (gateway timeout)
- [`RSQL_top`](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_top), [`RSQL_order`](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_order) (TOP semantics)
- [`RSQL_dateadd`](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=RSQL_dateadd) (time-window patterns)
- [`GSQL_blobs`](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_blobs) (stream column SQL access)
- [`GSOC_parallel`](https://docs.intersystems.com/iris20241/csp/docbook/DocBook.UI.Page.cls?KEY=GSOC_parallel) (`%PARALLEL` hint)
- [Community: each Web Gateway timeout's meaning](https://community.intersystems.com/post/description-each-timeout-value-can-be-set-default-parameter-web-gatewaycsp-gateway-management)

**Anthropic / OpenAI / Gemini / MCP** — see [sibling research doc §"Research Synthesis & Executive Summary"](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md#research-synthesis--executive-summary). Same source bundle applies to both agents.

**Vocabulary-learning prior art**: [Atlan agent-memory architectures](https://atlan.com/know/agent-memory-architectures/) (tiered MemGPT pattern, ~90% token savings, ~6pp accuracy delta), arXiv 2603.07670v1 (RL-optimized memory ops, Ebbinghaus decay).

**Project context**: `docs/initial-prompt.md` (the user's authoritative scope spec for both agents); `sources/iris-session-chat/_bmad-output/planning-artifacts/product-brief-ensemble-session-inspection-agent-distillate.md` (original AI-Hub-coupled brief); the saved memories at `~/.claude/projects/c--git-iris-session-agent/memory/` (ObjectScript-only constraint, 2024.1 floor, full v1 scope, package naming convention).

### Workflow Completion

| Step | Title | Output |
|---|---|---|
| 1 | Scope Confirmation | Locked: 8 topics, MCP→`iris-execute-mcp-v2` clarification, shared-infrastructure reuse from inspection-agent doc |
| 2 | Technology Stack Analysis | 3 parallel research streams; 8-index inventory verified from source; two stream-conflict resolutions (`%NOLOCK`, `IsError`/`Type` indexing); `UserVocabulary` storage primitive defined |
| 3 | Integration Patterns Analysis | 8 canonical query templates, three-layer search-arg safety with L3 bounded-WHERE invariant, vocabulary-learning update path, URL-parameter hand-off, audit enrichment, MessageViewer UX recommendation |
| 4 | Architectural Patterns | 8-tool catalog, vocabulary class family schemas, `SessionAgent.EnsPortal.MessageViewer` subclass, audit-log enrichment columns, config row defaults, IPM additive shape, TTL sweep task |
| 5 | Implementation Approaches | 7-epic search sequence (12-18), `SearchByStatus` worked example, `UserVocabulary.RecordSuccess`/`RecordFailure`/`SynthesizeAlias`/`DecaySweep`, `VocabularyDigest.Build` cascade, click-through dispatch interceptor, installer additions, operator README, 4-layer test strategy |
| 6 | Synthesis & Executive Summary | This section. |

**Confidence summary across the document:** Most findings High, with five Medium-confidence items explicitly flagged and three Task-0 probes carried forward (six total when combined with the inspection-agent doc's three). No Low-confidence findings shipped as primary recommendations.

**Document length:** ~9,000 words — sized smaller than the inspection-agent doc since most of the architecture is shared and referenced by hyperlink rather than restated.

**Companion deliverables (referenced):**

1. **Inspection-agent research doc** — `technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md`. The shared-infrastructure reference; both docs read together for the full v1 picture.
2. **Cleanup edit proposal** — `cleanup-edit-proposal-2026-05-02.md` — non-destructive callout-only edits to the two AI-Hub-coupled 2026-04-24 docs, awaiting user approval to apply.

---

**Research Completion Date:** 2026-05-02
**Research Period:** 2026-05-02 (one continuous research session, sibling to the 2026-05-01 inspection-agent doc)
**Document Length:** ~9,000 words (synthesis-tight, no padding; comprehensive coverage of search-agent-specific concerns)
**Source Verification:** All non-trivial claims cited; minimum 2 authoritative sources per High-confidence finding per the project's `research-first.md` rule. Confidence levels (High / Medium / Low) called out explicitly throughout.
**Task-0 Probes Required Before Implementation:** 3 search-agent-specific (carried forward in §Task-0 Probes above) + 3 inherited from the inspection-agent doc.

*This research document serves as the architectural blueprint for the v1 release of the Message Search Agent in the `iris-session-agent` IPM module and provides the foundation for downstream PRD, architecture, epic, and story authoring. It assumes the reader has loaded the sibling Session Inspection Agent research doc as shared-infrastructure reference; where shared patterns are needed they are cross-referenced rather than restated.*
