# Reference: `Ens.*` Framework Tables

Detailed field-level reference for the two `Ens.*` tables you query most. Column lists are
**representative** — they can vary slightly by IRIS version, so confirm against
`INFORMATION_SCHEMA.COLUMNS` (`04`). The *behaviors and encodings* below are stable.

---

# `Ens.MessageHeader`

The central routing-metadata table. One row per message in an Interoperability production.

## Columns (typical, ~24)

| Column | Type | Notes |
|--------|------|-------|
| `ID` | bigint | RowID. Usually not renamed, so `ID` and `%ID` both work — prefer `%ID` in joins. |
| `SessionId` | integer | Groups a logical exchange. **First message has `ID = SessionId`.** Single-column index. |
| `Type` | integer | **1 = Request, 2 = Response.** Integer-coded — never compare to `'Request'`/`'Response'` strings. **No bitmap index** (post-filter, doesn't cut I/O). |
| `SourceConfigName` | varchar | Sending production component. Bitmap-indexed. |
| `TargetConfigName` | varchar | Receiving production component. Bitmap-indexed. Primary routing filter. |
| `TimeCreated` | timestamp | When the header was created. Bitmap + range index; the usual time filter. |
| `TimeProcessed` | timestamp | When processing finished. On a request leg, ≈ the response's `TimeCreated` (basis for single-header latency, see `02`). |
| `Status` | integer | Routing state, integer-coded — decode with `%EXTERNAL(Status)`. Observed: `8`→"Error", `9`→"Completed". Independent of `IsError`. Single-column (bitmap) index. |
| `IsError` | bit | Set on the **response** (`Type=2`), not the request. |
| `ErrorStatus` | varchar | `%Status` format — render with `%ODBCOUT(ErrorStatus)`; raw is binary garble. |
| `MessageBodyClassName` | varchar | Full class name of the body; often stored **ALL CAPS**. Bitmap-indexed. |
| `MessageBodyId` | varchar | FK to body `%ID`. **Class-scoped, not globally unique** — match with class. Single-column index. |
| `CorrespondingMessageId` | integer | Correlated partner header; **bidirectional but often `0`/unpopulated** on internal legs. |
| `SourceBusinessType` / `TargetBusinessType` | integer | Integer-coded — `%EXTERNAL()`: `1`→"BusinessService", `2`→"BusinessProcess", `3`→"BusinessOperation". (`%ODBCOUT` does **not** decode these.) |
| `BusinessProcessId` | integer | |
| `Priority`, `Invocation`, `Banked`, `Resent`, `SuperSession`, `Description`, `ReturnQueueName`, `TargetQueueName` | various | Mostly routing internals; `Description` is often empty. |

## Decode cheat-sheet

| Column | Decode with | Result |
|--------|-------------|--------|
| `Type` | (use integer) | `1`=Request, `2`=Response |
| `Status` | `%EXTERNAL(Status)` | "Completed", "Error", ... |
| `SourceBusinessType`/`TargetBusinessType` | `%EXTERNAL(...)` | "BusinessService"/"BusinessProcess"/"BusinessOperation" |
| `ErrorStatus` | `%ODBCOUT(ErrorStatus)` | readable error text |

## Gotchas (verified the hard way)

- **`IsError`/`ErrorStatus` are on the response, not the request** — correlate to the response
  header to judge request failure (see `02`, request/response correlation).
- **`Type` is integer** — `Type = 'Response'` matches nothing (string coerces to 0).
- **`Status` is integer** — `Status != 'Delivered'` becomes `Status != 0`, a no-op that keeps
  every row. Use `%EXTERNAL(Status) != 'Delivered'`.
- **`MessageBodyClassName` case** varies (commonly ALL CAPS). Comparisons are case-insensitive
  by default so `=` still matches, but verify the *stored* case before relying on display/group
  output, and use `%EXACT()` when case matters.
- **`ID` magnitude is per-instance.** Observed ranges differ by orders of magnitude across
  instances (tens of thousands on one, millions on another). A hardcoded `ID > N` floor copied
  from another environment can silently exclude **every** row. Never port ID floors.
- **`MessageBodyId` is class-scoped** — never join headers to bodies on `MessageBodyId` alone;
  always pair with `MessageBodyClassName`.
- **`%NOLOCK`** may be rejected by some endpoints (`SQLCODE -25` via the Atelier query endpoint).

## Session timing patterns

```sql
-- Session START: the initiating header (ID = SessionId)
INNER JOIN Ens.MessageHeader fsh
  ON fsh.ID = hdr.SessionId AND fsh.SessionId = hdr.SessionId
-- fsh.TimeCreated = session start

-- Session FINISH: final response back to the initiator
LEFT JOIN Ens.MessageHeader lsh
  ON lsh.SessionId = fsh.SessionId
 AND lsh.TargetConfigName = fsh.SourceConfigName
 AND lsh.Type = 2
-- lsh.TimeProcessed = session finish

-- Message-level finish: the correlated response to THIS message
LEFT JOIN Ens.MessageHeader drh
  ON drh.CorrespondingMessageId = hdr.%ID
-- drh.TimeCreated = when this message's response was created
```

## Counting sessions without `COUNT(DISTINCT)`

Count session **starts** (each session has exactly one `ID = SessionId` row) instead of
`COUNT(DISTINCT SessionId)`:

```sql
SUM(CASE WHEN SessionId = ID THEN 1 ELSE 0 END) AS SessionCount
-- or, equivalently, in a filtered query:
COUNT(*) ... WHERE ID = SessionId
```

- Equal to `COUNT(DISTINCT SessionId)` whenever sessions don't span the bucket boundary
  (e.g. midnight for daily buckets) — verified equal on every day of a 47-day sample.
- Far more scalable: `COUNT(DISTINCT)` maintains a distinct temp-file that grows with session
  cardinality; the `CASE/SUM` keeps one accumulator per group. (The optimizer's *static* cost
  rates them near-equal, but the SUM avoids the distinct temp-I/O that dominates at scale.)
- Semantics: this counts sessions that *started* in the bucket (vs `COUNT(DISTINCT)` = sessions
  *active* in the bucket).

## Plan notes (recap from `03`)

- Pure `COUNT(*)` by `TO_CHAR(TimeCreated,'YYYY-MM-DD')` over a time range is **index-only** —
  fast even on millions of rows; `%PARALLEL` splits the range across cores.
- A by-day **session** count must master-read each row for `SessionId` (not co-indexed with
  `TimeCreated`) — that per-row read is the floor; only a covering `(TimeCreated, SessionId)`
  projection index makes it index-only (see `03`).
- Adding `ID > 1` / `SessionId >= {watermark}` collapses *estimated* cost without changing the
  plan — not a real speedup. Measure.

---

# `Ens.Util.Log` (SQL: `Ens_Util.Log`)

The Interoperability **event log** — errors, warnings, info, traces, alerts emitted by
production components. Great for "what went wrong and where," and joins cleanly to
`Ens.MessageHeader`.

## Columns

| Column | Type | Notes |
|--------|------|-------|
| `%ID` / `ID` | bigint | RowID. |
| `ConfigName` | varchar(128) | Production component that logged the event. **Bitmap index.** |
| `Job` | varchar | `$Job` of the logging process. |
| `MessageId` | integer | FK to `Ens.MessageHeader.%ID` — the message current when the event was logged (not necessarily the cause). |
| `SessionId` | integer | FK to `Ens.MessageHeader.SessionId`. |
| `SourceClass` | varchar(255) | Class that logged the event. |
| `SourceMethod` | varchar(40) | Method that logged the event. |
| `Stack` | varchar | A **`$LIST`** of stack frames (error stack). Extract with `$LISTGET(Stack, N)`. Only populated for errors. |
| `StatusValue` | varchar | `%Status` — render with `%ODBCOUT(StatusValue)`. Defaults to OK (`1`); meaningful only for status-logged errors. |
| `Text` | varchar(32000) | The event message (truncated at 32000). |
| `TimeLogged` | timestamp | UTC. **Standard index** — efficient for time-range filters. |
| `TraceCat` | varchar(10) | Trace category; only for trace events (`Type=5`). |
| `Type` | integer | Event type — **bitmap index**. Decode with `%EXTERNAL(Type)`. See table below. |

## `Type` values (`Ens.DataType.LogType`)

| Value | Meaning |
|-------|---------|
| 1 | Assert |
| 2 | Error |
| 3 | Warning |
| 4 | Info |
| 5 | Trace |
| 6 | Alert (also triggers SNMP/WMI notification) |

Use `%EXTERNAL(Type)` for display.

## Relationships / join patterns

```sql
-- Log entry → the message header active when it was logged
LEFT JOIN Ens.MessageHeader hdr ON log.MessageId = hdr.%ID

-- Log entry → the session-initiating header
LEFT JOIN Ens.MessageHeader sess ON log.SessionId = sess.%ID

-- From a message header → its log entries
LEFT JOIN Ens_Util.Log log ON hdr.%ID = log.MessageId
```

To attribute a logged error to a specific body type in the same session, join through
`Ens.MessageHeader` on `SessionId` **and filter `SourceConfigName`** to the component that
logged the error — otherwise multiple messages per session inflate counts:

```sql
INNER JOIN Ens.MessageHeader mh
  ON mh.SessionId = log.SessionId
 AND mh.SourceConfigName = 'MyApp.Some.Component'   -- the component that logged the error
 AND mh.MessageBodyClassName = 'MyApp.Message.SomeRequest'
-- log filter: log.Type = 2 (Error) AND log.ConfigName = 'MyApp.Some.Component'
```

## Gotchas & performance

- `Type` is integer — use `%EXTERNAL(Type)` for display; filter on the integer.
- `Stack` is a `$LIST`, not a plain string — `$LISTGET(Stack, N)` per frame.
- `StatusValue` is `%Status` — `%ODBCOUT()` it; raw is garble; defaults to `1` (OK).
- `MessageId` is the header id *at the time of logging*, not necessarily the message that
  caused the event.
- **Grouping errors:** the same error often appears as many near-identical strings (differing
  trailing IDs/timestamps). Group by a truncated prefix and show `MIN()` of the full text:
  `GROUP BY SUBSTRING(Text, 1, 20)`, `SELECT MIN(SUBSTRING(Text,1,255))`.
- **Wide time windows with a `ConfigName` filter can time out** — start with a 1-day window and
  widen, or raise the execution timeout. The `Text` filter/grouping is the expensive part.
- For recurring/large analyses where a compound index `(ConfigName, Type, TimeLogged)` would
  help but you can't modify the system class, use the read-only projection-index pattern (`03`).
