# Audit SQL Recipes

This document is for **operators** of the SessionAgent agents. Every LLM
round-trip and every tool dispatch made by an agent is recorded as a row in
one of two SQL tables:

- `SessionAgent_Audit.LlmCall` — one row per LLM provider call
  (request issued, response received or error raised).
- `SessionAgent_Audit.ToolCall` — one row per tool dispatch
  (agent invoked a registered tool, received a result or error).

There is **no separate audit UI** — the design choice (per the PRD's NFR-O3
"operator-observable via standard tooling") is to keep audit data inspectable
through the SQL surface every IRIS operator already knows. This document
provides the five recipes operators most often need.

The queries can be run from any IRIS SQL surface: the Management Portal's
SQL page, an `iris session` SQL shell, the `iris_sql_execute` MCP tool, or
any `%SQL.Statement` invocation in your own code.

---

### Note on case-sensitivity

IRIS SQL is case-insensitive by default for string comparisons. Every
recipe below wraps string columns with `%EXACT()` to preserve the original
case of values (so `OpenAI` and `openai` are treated as different) and to
ensure case-sensitive WHERE-clause matching. If you remove `%EXACT()`, you
may see incorrect grouping or matching due to case folding.

---

## Recipe 1 — How many tokens did we spend yesterday?

This recipe sums input tokens (the prompt) and output tokens (the
completion) across every LLM call made the previous calendar day (in UTC,
the timezone the agent records timestamps in). The two parameters are
**yesterday at midnight UTC** and **today at midnight UTC**, formatted as
ISO-8601 strings such as `2026-05-02T00:00:00Z` and `2026-05-03T00:00:00Z`.

To compute these in ObjectScript:

```objectscript
; $H is local Horolog; the date integer of $ZTimeStamp gives today in UTC.
Set tTodayDate = +$Piece($ZTimeStamp, ",", 1)
Set tToday = $ZDate(tTodayDate, 3) _ "T00:00:00Z"
Set tYesterday = $ZDate(tTodayDate - 1, 3) _ "T00:00:00Z"
```

`$ZDate(d, 3)` returns `YYYY-MM-DD` for the day integer `d`. Concatenating
`T00:00:00Z` produces the ISO-8601 UTC midnight string the queries expect.

Then:

```sql
SELECT SUM(RequestTokens + ResponseTokens) AS TotalTokens
FROM SessionAgent_Audit.LlmCall
WHERE Timestamp >= ?
  AND Timestamp < ?
```

Pass `tYesterday` and `tToday` as the two `?` parameters. The result is a
single row with one column (`TotalTokens`); divide by the per-million-token
provider rate to get a rough cost estimate. If your agent uses Anthropic
prompt caching, you can additionally subtract `CacheHitTokens` from
`RequestTokens` to compute the *uncached* token spend.

---

## Recipe 2 — What tools did the agent dispatch in the last hour?

This recipe is the operator's primary "what is the agent doing?" probe.
It groups `SessionAgent_Audit.ToolCall` by tool name and sorts the most
frequent dispatches first. The `?` parameter is **the timestamp one hour
ago**, formatted as ISO-8601 UTC.

To compute the parameter in ObjectScript:

```objectscript
; Subtract 3600 seconds from the seconds-of-day part of $ZTimeStamp.
; If we cross midnight backwards, decrement the day and wrap the seconds.
Set tNow = $ZTimeStamp
Set tDay = +$Piece(tNow, ",", 1)
Set tSec = +$Piece(tNow, ",", 2) - 3600
If tSec < 0 { Set tSec = tSec + 86400, tDay = tDay - 1 }
Set tOneHourAgo = $Translate($ZDateTime(tDay _ "," _ tSec, 3, 1), " ", "T") _ "Z"
```

Then:

```sql
SELECT %EXACT(ToolName) AS Tool,
       COUNT(*) AS DispatchCount
FROM SessionAgent_Audit.ToolCall
WHERE Timestamp >= ?
GROUP BY %EXACT(ToolName)
ORDER BY DispatchCount DESC
```

Two columns come back: tool name and dispatch count. A spike in any single
tool is a useful signal — for example, a runaway agent stuck in a loop
calling `find_related_sessions` over and over will show up immediately at
the top.

---

## Recipe 3 — Any timeouts or errors today?

This recipe combines errors from both audit tables (LLM-call failures and
tool-dispatch failures) into a single result set sorted by time. Every
error row carries human-readable context in `ErrorText`. The `?` parameter
is **today at midnight UTC**, formatted as ISO-8601 (computed identically
to Recipe 1's `tToday`).

```sql
SELECT Timestamp,
       %EXACT(Provider) AS Source,
       %EXACT(ErrorText) AS Detail
FROM SessionAgent_Audit.LlmCall
WHERE IsError = 1
  AND Timestamp >= ?
UNION ALL
SELECT Timestamp,
       %EXACT(ToolName) AS Source,
       %EXACT(ErrorText) AS Detail
FROM SessionAgent_Audit.ToolCall
WHERE IsError = 1
  AND Timestamp >= ?
ORDER BY Timestamp DESC
```

Pass the same `?` value for both placeholders. The `Source` column tells
you whether the failure came from an LLM provider (you'll see `openai`,
`anthropic`, etc.) or from a tool dispatch (you'll see the tool name like
`session_summary`). The `Detail` column carries the operator-readable
error text — never API-key material (NFR-S3 forbids it).

---

## Recipe 4 — Which sessions had the highest tool-call count?

This recipe groups tool dispatches by `ChatHistoryId` (the parent
conversation) and surfaces the chats with the most tool activity. Useful
for finding "expensive" conversations — the ones where the agent had to
do the most work. The `?` parameter is the lower time bound (e.g., the
start of the current week) as ISO-8601 UTC.

```sql
SELECT %EXACT(ChatHistoryId) AS ChatId,
       COUNT(*) AS Calls
FROM SessionAgent_Audit.ToolCall
WHERE Timestamp >= ?
GROUP BY %EXACT(ChatHistoryId)
ORDER BY Calls DESC
```

Two columns: chat-history ID and total tool-call count. To see the LLM
side of the same conversation, swap the table for `SessionAgent_Audit.LlmCall`
and `COUNT(*)` becomes the LLM-round-trip count.

---

## Recipe 5 — Are any audit rows orphaned (missing FK)?

This recipe finds audit rows whose `ChatHistoryId` does not point to an
existing chat-history record — orphans, in other words. Useful for
verifying the `PurgeOrphanedChatHistory` task (Story 7.2) is doing its
job, and for spotting bugs where audit was emitted but the parent chat
record was never persisted.

> **Note: this query becomes runnable once Story 2.6 ships
> `SessionAgent.Chat.History`.** Until then, the `LEFT JOIN` form below
> will fail at parse time because the table does not exist. As an interim
> sanity check, the query in the second code block lists every distinct
> `ChatHistoryId` referenced from the audit tables; an operator can spot-
> check whether each ID looks like a real session ID their agent emitted.

Once Story 2.6 ships, the orphan check is:

```sql
SELECT %EXACT(L.ChatHistoryId) AS OrphanedChatId,
       COUNT(*) AS OrphanedRows
FROM SessionAgent_Audit.LlmCall L
LEFT JOIN SessionAgent_Chat.History H
       ON %EXACT(H.ID) = %EXACT(L.ChatHistoryId)
WHERE H.ID IS NULL
GROUP BY %EXACT(L.ChatHistoryId)
ORDER BY OrphanedRows DESC
```

The interim spot-check (works today):

```sql
SELECT DISTINCT %EXACT(ChatHistoryId) AS ChatId
FROM SessionAgent_Audit.LlmCall
ORDER BY %EXACT(ChatHistoryId)
```

Run the equivalent against `SessionAgent_Audit.ToolCall` to cover both
audit tables.
