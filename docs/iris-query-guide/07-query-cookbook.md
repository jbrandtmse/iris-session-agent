# Query Cookbook

Copy-adaptable patterns. Replace placeholder component/class names with values you discover
live (`04`). Every query bounds time and previews with `TOP N` — keep both habits.

## Messages per day through a component

```sql
SELECT TOP 100
       TO_CHAR(TimeProcessed, 'YYYY-MM-DD') AS Day,
       COUNT(*)                             AS MsgCount
FROM Ens.MessageHeader
WHERE TargetConfigName = 'MyApp.Some.Operations'
  AND TimeProcessed > DATEADD('day', -30, CURRENT_TIMESTAMP)
GROUP BY TO_CHAR(TimeProcessed, 'YYYY-MM-DD')
ORDER BY Day DESC
```

## Daily message + session counts (scalable, no `COUNT(DISTINCT)`)

```sql
SELECT TOP 100
       TO_CHAR(TimeCreated, 'YYYY-MM-DD')              AS Day,
       COUNT(*)                                        AS MessageCount,
       SUM(CASE WHEN SessionId = ID THEN 1 ELSE 0 END) AS SessionCount
FROM %PARALLEL Ens.MessageHeader
WHERE TimeCreated >= DATEADD('day', -60, CURRENT_TIMESTAMP)
GROUP BY TO_CHAR(TimeCreated, 'YYYY-MM-DD')
ORDER BY Day DESC
```
`SUM(CASE WHEN SessionId = ID ...)` counts session starts ≈ distinct sessions (when sessions
don't cross midnight) and avoids the distinct temp-file. See `05`.

## Errors in the last 24 hours

```sql
SELECT TOP 50 ID, SessionId, TimeCreated, SourceConfigName, TargetConfigName,
       %ODBCOUT(ErrorStatus) AS ErrorText
FROM Ens.MessageHeader
WHERE IsError = 1
  AND TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
ORDER BY TimeCreated DESC
```
Remember `IsError` is set on the **response** leg (`Type=2`).

## Long-running messages (> 20 s)

```sql
SELECT TOP 50 ID, SessionId, TargetConfigName, MessageBodyClassName,
       TimeCreated, TimeProcessed,
       {fn TIMESTAMPDIFF(SQL_TSI_SECOND, TimeCreated, TimeProcessed)} AS ProcessingSec
FROM Ens.MessageHeader
WHERE {fn TIMESTAMPDIFF(SQL_TSI_SECOND, TimeCreated, TimeProcessed)} > 20
  AND TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
ORDER BY ProcessingSec DESC
```

## Full trace of one session (chronological)

```sql
SELECT ID, Type, SourceConfigName, TargetConfigName, MessageBodyClassName,
       TimeCreated, %EXTERNAL(Status) AS Status, IsError
FROM Ens.MessageHeader
WHERE SessionId = :session_id
ORDER BY TimeCreated ASC, ID ASC
```

## Business Operation response latency (single-header, no self-join)

```sql
SELECT TOP 100 ID, SessionId, TimeCreated,
       DATEDIFF('ms', TimeCreated, TimeProcessed) AS ResponseMs
FROM %PARALLEL Ens.MessageHeader
WHERE Type = 1
  AND TargetConfigName = 'MyApp.Some.Operations'
  AND TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
ORDER BY ResponseMs DESC
```
Use when `CorrespondingMessageId` is `0` on these legs and the op fires many times per session
(pairing would be ambiguous). The request leg's own `TimeProcessed − TimeCreated` is the
response latency. See `02`.

## Request → response latency via `CorrespondingMessageId` (when populated)

```sql
SELECT TOP 100 rq.ID AS RequestId, rs.ID AS ResponseId,
       rq.TimeCreated AS RequestTime, rs.TimeCreated AS ResponseTime,
       DATEDIFF('ms', rq.TimeCreated, rs.TimeCreated) AS LatencyMs,
       rs.IsError
FROM Ens.MessageHeader rq
LEFT JOIN Ens.MessageHeader rs
  ON rs.CorrespondingMessageId = rq.%ID
 AND rs.TimeCreated > DATEADD('hour', -1, CURRENT_TIMESTAMP)   -- keep JOIN + WHERE windows in sync
WHERE rq.Type = 1
  AND rq.TimeCreated > DATEADD('hour', -1, CURRENT_TIMESTAMP)
ORDER BY LatencyMs DESC
```

## Request → response when `CorrespondingMessageId` is unpopulated (self-join)

```sql
SELECT TOP 100 rqh.SessionId,
       rqh.TimeCreated AS ReqTime, rsh.TimeCreated AS RespTime,
       DATEDIFF('ms', rqh.TimeCreated, rsh.TimeCreated) AS LatencyMs,
       rsh.IsError
FROM Ens.MessageHeader rqh
LEFT JOIN Ens.MessageHeader rsh
  ON rsh.SessionId = rqh.SessionId
 AND rsh.TargetConfigName = rqh.SourceConfigName
 AND rsh.SourceConfigName = rqh.TargetConfigName
 AND rsh.Type = 2
WHERE rqh.Type = 1
  AND rqh.SourceConfigName = 'MyApp.Inbound.Service'
  AND rqh.TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
ORDER BY LatencyMs DESC
```

## Failure rate by a dimension, with time bucket

```sql
SELECT %EXACT(ai.AdditionalInfo)                      AS TargetURL,
       COUNT(*)                                       AS Total,
       SUM(CASE WHEN resp.IsError = 1 THEN 1 ELSE 0 END) AS Failures,
       CAST(SUM(CASE WHEN resp.IsError = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))
                                                      AS FailurePct
FROM Ens.MessageHeader rqh
INNER JOIN HS_Message.PatientSearchRequest psr
        ON rqh.MessageBodyId = psr.%ID
LEFT  JOIN HS_Message.PatientSearchRequest_AdditionalInfo ai
        ON psr.%ID = ai.PatientSearchRequest AND ai.element_key = 'WSA:To'
LEFT  JOIN Ens.MessageHeader resp
        ON resp.CorrespondingMessageId = rqh.%ID
       AND resp.TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
WHERE rqh.MessageBodyClassName = 'HS.Message.PatientSearchRequest'
  AND rqh.TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
GROUP BY %EXACT(ai.AdditionalInfo)
ORDER BY Failures DESC
```

## Grouping noisy error text

When `%ODBCOUT(ErrorStatus)` yields many strings differing only in trailing IDs/UUIDs/timestamps,
group by a truncated prefix and display a representative full error with `MIN()`:

```sql
SELECT MIN(SUBSTRING(%ODBCOUT(rsh.ErrorStatus), 1, 255)) AS ErrorText,
       COUNT(*)                                          AS Total
FROM Ens.MessageHeader rsh
WHERE rsh.IsError = 1
  AND rsh.TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
GROUP BY SUBSTRING(%ODBCOUT(rsh.ErrorStatus), 1, 20)   -- widen/narrow the prefix to tune grouping
ORDER BY Total DESC
```

## Aggregate-first, then join lookups (avoid per-row lookup joins)

When aggregating header/body data and joining to a small lookup/reference/directory table,
aggregate **first** in a subquery, then join the lookup to the ~K distinct grouped keys — not
to every one of millions of message rows:

```sql
-- GOOD
SELECT dir.Name, agg.MsgCount
FROM ( SELECT hdr.SomeKey, COUNT(*) AS MsgCount
       FROM Ens.MessageHeader hdr
       WHERE hdr.TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
       GROUP BY hdr.SomeKey ) agg
LEFT JOIN SomeSchema.LookupTable dir ON agg.SomeKey = dir.SomeKey
ORDER BY agg.MsgCount DESC
```
Also reduces bitmap-intersection cost — push non-essential filters out of the inner scan and
let the join/subquery do the filtering.

## Document count per session from a response stream

```sql
SELECT TOP 100 hdr.SessionId, hdr.TimeCreated,
       (CHAR_LENGTH(SUBSTRING(qr.ContentStream, 1, 100000))
         - CHAR_LENGTH(REPLACE(SUBSTRING(qr.ContentStream, 1, 100000),
             '</rim:ExtrinsicObject>', ''))) / 22 AS Doc_Count
FROM Ens.MessageHeader hdr
INNER JOIN HS_Message_IHE_XDSb.QueryResponse qr ON hdr.MessageBodyId = qr.%ID
WHERE hdr.MessageBodyClassName = 'HS.Message.IHE.XDSb.QueryResponse'
  AND hdr.TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
ORDER BY Doc_Count DESC
```
(For a session total across multiple response rows, use the correlated `SUM(...)` subquery in `06`.)

## Watermark / batch scan by body class (forced bitmap, short-circuits at TOP N)

```sql
SELECT TOP 1000 ID, MessageBodyId
FROM %IGNOREINDEX TimeCreated Ens.MessageHeader
WHERE MessageBodyClassName = 'HS.Message.XMLMessage'
  AND ID > :watermark
  AND TimeCreated < :cutoff
ORDER BY ID
```
Forcing the ID-ordered `MessageBodyClassName` bitmap (off the time index) makes `ORDER BY ID`
sort-free and short-circuit at `TOP N` — ~constant work per batch. See `03`.

## Orphaned-body screen (rough — never drives a delete; read-only)

```sql
SELECT COUNT(*) FROM %PARALLEL HS_Message.SomeResponse b
WHERE NOT EXISTS (
  SELECT 1 FROM Ens.MessageHeader h
  WHERE h.MessageBodyId = b.%ID
    AND h.MessageBodyClassName IN
      ('HS.Message.SomeResponse', '<subclass1>', '<subclass2>')   -- enumerate via %Dictionary (04)
)
```
Match base **and all subclasses** (shared extent over-counts otherwise); `%PARALLEL` because
there's no index on `MessageBodyId`. Treat the number as a rough screen only — authoritative
orphan detection needs object-level class confirmation, which pure SQL can't do (`03`).

## Discovery one-liners (see `04` for the full set)

```sql
-- active body types, last 7 days
SELECT DISTINCT MessageBodyClassName, COUNT(*) AS MsgCount FROM Ens.MessageHeader
WHERE TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
GROUP BY MessageBodyClassName ORDER BY MsgCount DESC

-- columns of a table
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'HS_Message' AND TABLE_NAME = 'XMLMessage' ORDER BY ORDINAL_POSITION

-- class -> SQL table mapping
SELECT Name, SqlSchemaName, SqlTableName FROM %Dictionary.CompiledClass
WHERE ClassType = 'persistent' AND UPPER(Name) = UPPER('HS.Message.XMLMessage')
```
