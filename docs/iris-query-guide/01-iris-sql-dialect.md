# IRIS SQL Dialect — The Things That Bite

IRIS SQL is mostly ANSI-ish but has a set of dialect rules and encoding behaviors that, if
ignored, produce **silently wrong results** (not errors). This file is the reference for all
of them. Internalize it before writing trace queries.

## Row limiting

- Use `SELECT TOP N ...` — **not** `LIMIT N` (IRIS does not support `LIMIT`).
- `TOP` goes right after `SELECT` (and after `DISTINCT` if present): `SELECT TOP 50 DISTINCT ...`.
- Most execution endpoints also accept an out-of-band max-rows cap (e.g. the Atelier API's
  `?max=N`). Keep a hard cap on every call as a safety net, independent of `TOP`.

## `%ID` — always use it in JOINs

`%ID` is a pseudo-column that always resolves to the row's RowID, even when:
- the default `ID` column was renamed (IRIS renames it to `ID1`, `ID2`, ... when the class
  defines its own `ID` property), or
- the class uses an IDKEY on a string property.

```sql
INNER JOIN MyApp_Some.Body body ON hdr.MessageBodyId = body.%ID
```

- Do **not** confuse `%ID` with `%ROWID` — `%ROWID` is cursor-based and serves a different
  purpose. Use `%ID` for joins and identity.
- When `ID` is a plain bigint that wasn't renamed, `ID` and `%ID` are interchangeable — but
  defaulting to `%ID` is always safe, so prefer it.

## ObjectScript class name → SQL schema.table

This conversion is constant and critical (body tables are identified by their *class* name in
`Ens.MessageHeader.MessageBodyClassName`):

- Take the full class name `Package.SubPackage.ClassName`.
- **Replace every dot except the last with an underscore.** Everything before the last dot is
  the SQL **schema**; the part after the last dot is the **table**.
- Examples:
  - `EnsLib.HL7.Message` → `EnsLib_HL7.Message`
  - `HS.Message.PatientSearchRequest` → `HS_Message.PatientSearchRequest`
  - `My.App.Messages.PatientRequest` → `My_App_Messages.PatientRequest`
  - `Ens.Util.Log` → `Ens_Util.Log`

Don't hand-derive when you can confirm it: `%Dictionary.CompiledClass` exposes the authoritative
`SqlSchemaName` / `SqlTableName` for any class (see `04`).

## Dates and elapsed time

- **Date math:** `DATEADD('day', -N, CURRENT_TIMESTAMP)` (also `'hour'`, `'minute'`, `'second'`,
  `'ms'`/`'millisecond'`). This is the workhorse for time-window filters.
- **Elapsed seconds:** `{fn TIMESTAMPDIFF(SQL_TSI_SECOND, ts1, ts2)}` (ODBC scalar escape).
  Other intervals: `SQL_TSI_MINUTE`, `SQL_TSI_HOUR`, etc.
- **Elapsed in ms:** `DATEDIFF('ms', ts1, ts2)`.
- **Extract the date portion of a timestamp for display / daily grouping:**
  - `TO_CHAR(ts, 'YYYY-MM-DD')` → a human-readable `'2026-06-09'` string. **Use this** for any
    column shown to the user and for `GROUP BY` daily buckets.
  - `{fn SUBSTRING(ts, 1, 10)}` also yields the leading `YYYY-MM-DD` substring.
  - `CAST(ts AS DATE)` returns the IRIS **internal day-count integer** (e.g. `67705`), *not* a
    readable date — useful for date arithmetic, useless for display. Don't show it to users.

## Encoded columns — decode functions

IRIS persists several types in internal formats that look like garbage in raw output. Decode
them:

| When the column is... | Use | Notes |
|-----------------------|-----|-------|
| An **integer-coded enum** (status, type, business-type) | `%EXTERNAL(col)` | Renders the logical/display value (e.g. `1`→`"BusinessService"`). `%ODBCOUT` does **not** decode enums — it returns the raw integer. |
| A **`%Status` value** (error status) | `%ODBCOUT(col)` | Renders the human-readable status/error string. Without it you get binary-encoded garble. |
| A **`$LIST`** | `$LISTGET(col, N)` | Extract Nth element (1-based). See below. |
| A **stream** (`longvarchar`/`longvarbinary`) | `SUBSTRING(col, 1, N)` | Read first N chars as a string. See below. |

> **Rule of thumb:** integer enums → `%EXTERNAL`; `%Status` → `%ODBCOUT`. They are *not*
> interchangeable, and using the wrong one returns either raw integers or garble.

## Integer columns vs string literals — the silent no-op trap

Several framework columns are **integers** even though they represent words ("Request",
"Completed"). Comparing them to a string literal does **not** error — IRIS coerces the
non-numeric string to `0`, which usually makes the predicate a silent no-op:

```sql
-- WRONG — Type is integer; 'Response' coerces to 0, so this matches NOTHING:
WHERE Type = 'Response'
-- WRONG — Status is integer; 'Delivered' coerces to 0 → becomes Status != 0 → keeps ALL rows:
WHERE Status != 'Delivered'

-- RIGHT — use the integer code, or decode then compare:
WHERE Type = 2                          -- 2 = Response
WHERE %EXTERNAL(Status) != 'Delivered'  -- compare against decoded text
```

This is the #1 cause of "my filter returns zero rows" or "my exclusion isn't excluding
anything." Whenever a filter behaves bizarrely, check whether the column is really an integer.

## Case sensitivity

- IRIS SQL string comparisons, `WHERE` matching, `GROUP BY`, and `LIKE` are **case-insensitive
  by default**. `WHERE Name = 'abc'` matches `'ABC'`.
- This matters when a value is stored in one case but you're matching against another — e.g.
  `MessageBodyClassName` is frequently stored **ALL CAPS** (`HS.MESSAGE.PATIENTSEARCHREQUEST`)
  even though the class is mixed-case. Case-insensitive matching means `= 'HS.Message.PatientSearchRequest'`
  still works — but be aware when you *display* or *group* the value.
- To force **case-sensitive** behavior — essential when grouping/aggregating URLs, OIDs,
  identifiers, or other case-significant strings, or when joining to a catalog that uses
  EXACT collation — wrap the column in `%EXACT(col)`:
  ```sql
  SELECT %EXACT(ai.AdditionalInfo) AS TargetURL, COUNT(*) AS Cnt
  FROM ..._AdditionalInfo ai
  GROUP BY %EXACT(ai.AdditionalInfo)
  ```
- Joining `%Dictionary.CompiledClass.Name` (EXACT, mixed-case) to an ALL-CAPS
  `MessageBodyClassName` requires `UPPER()` on **both** sides (see `04`).

## `$LIST` and serial property extraction

`$LIST` is IRIS's native binary list format. Columns holding `$LIST` data show
control-character headers in raw output. Extract elements with `$LIST` functions:

- `$LISTGET(col, N)` — Nth element (1-based).
- `$LISTLENGTH(col)` — element count.
- **Nested** `$LISTGET($LISTGET(col, N), M)` — for a `$LIST` of `$LIST(key,value)` pairs
  (common for serialized `%ArrayOfDataTypes`/key-value properties): position `N` selects the
  pair, `M=1` is the key, `M=2` is the value.
- `$LISTFROMSTRING(str, delim)` — converts a **delimited string** to a `$LIST`. Do **not** use
  it on data that is already native `$LIST` format.

How to tell which you have: native `$LIST` columns show binary control-character headers in
raw `SELECT`; delimited strings show visible separators (commas/pipes) and can be handled with
plain `SUBSTRING`/string functions or `$LISTFROMSTRING`.

```sql
SELECT $LISTGET(MyListCol, 1)                       AS FirstItem,
       $LISTLENGTH(MyListCol)                       AS ItemCount,
       $LISTGET($LISTGET(MyPairsCol, 1), 1)         AS Key1,
       $LISTGET($LISTGET(MyPairsCol, 1), 2)         AS Value1
FROM MyTable
```

> **Position is not stable across rows** when a serialized list contains a variable set of
> keys (e.g. HTTP headers). To pull a specific key, scan a *range* of positions with a `CASE`
> that checks the key at each position (see `06` for the worked pattern). Scanning many
> positions across many rows is CPU-heavy — bound the time window.

> **Shell escaping:** if you pass SQL containing `$LISTGET` through a shell (bash/zsh), escape
> the `$` as `\$LISTGET` so the shell doesn't try to expand it.

## Stream columns (`longvarchar` / `longvarbinary`)

To read a stream as a string for use with string functions:

- Use `SUBSTRING(stream_col, 1, N)` — works on both `longvarchar` and `longvarbinary`. This is
  more performant than `CONVERT(VARCHAR(N), stream_col)`, which can time out on unfiltered
  queries.
- `SUBSTR` does **not** work on streams → `SQLCODE -37`. Only `SUBSTRING` works.
- To find a substring within a stream: `CHARINDEX('needle', SUBSTRING(stream_col, 1, N))`, then
  `SUBSTRING(stream_col, pos - offset, length)` to pull context around the hit.
- `{fn LOCATE(...)}` does **not** work → `SQLCODE -40` (the `FN` ODBC escape isn't supported for
  `LOCATE`). Use `CHARINDEX`.
- **Counting occurrences** of a marker in a stream (e.g. XML elements) — length-difference trick:
  ```sql
  (CHAR_LENGTH(SUBSTRING(s, 1, 100000))
    - CHAR_LENGTH(REPLACE(SUBSTRING(s, 1, 100000), '</TheTag>', ''))) / 9   -- 9 = len('</TheTag>')
  ```

## `GROUP BY` / `ORDER BY` restrictions

- **You cannot reference a SELECT column alias in `GROUP BY`** (and generally not in `ORDER BY`
  for computed expressions) → `SQLCODE -29`. Repeat the full expression in `GROUP BY`, or
  (cleaner) compute the expression in an inner subquery and `GROUP BY`/`ORDER BY` the alias in
  the outer query.
  ```sql
  -- Works: compute in subquery, group/order by alias outside
  SELECT t.Bucket, COUNT(*) AS Cnt
  FROM ( SELECT TO_CHAR(TimeCreated,'YYYY-MM-DD') AS Bucket FROM Ens.MessageHeader WHERE ... ) t
  GROUP BY t.Bucket
  ORDER BY t.Bucket DESC
  ```
  Note: `GROUP BY <the TO_CHAR expression>` directly also works; `ORDER BY <alias>` works for
  non-computed aliases. The subquery form sidesteps all the edge cases at once.

## Reserved-word aliases

`COUNT` and `ROWS` (among others) are reserved and **cannot be used as column aliases** →
`SQLCODE -1`. Use `Total`, `Cnt`, `MsgCount`, etc.

```sql
SELECT COUNT(*) AS Total     -- good
SELECT COUNT(*) AS Count     -- SQLCODE -1
```

## `COUNT(*)` vs `COUNT(1)`

Identical plan and cost in IRIS — `COUNT(1)` is parameterized to `COUNT(?)` and evaluated the
same way. There is **no** performance advantage to either; "`COUNT(1)` is faster" is a myth
here. Use whichever reads clearly.

## `COUNT(DISTINCT col)` is expensive

`COUNT(DISTINCT)` builds a distinct-value temp file that grows with cardinality — the most
expensive aggregate on large tables. Where the data model lets you count a proxy instead (e.g.
counting session-start rows rather than `COUNT(DISTINCT SessionId)`), prefer it. See `03`/`07`.

## Prefix matching

`%STARTSWITH` is an efficient prefix predicate:
```sql
WHERE SCHEMA_NAME %STARTSWITH '%'        -- e.g. to find/exclude system schemas
WHERE TargetConfigName %STARTSWITH 'MyApp.'
```

## Hint placement (summary — full detail in `03`)

- Index/parallel hints — `%PARALLEL`, `%ALLINDEX`, `%IGNOREINDEX {idx}`, `%FIRSTTABLE`,
  `%INORDER`, `%STARTTABLE`, `%FULL` — go **before** the table name:
  `FROM %PARALLEL Ens.MessageHeader`, `FROM %IGNOREINDEX TimeCreated Ens.MessageHeader`.
  Placing them after the table → `SQLCODE -25`.
- `%NOLOCK` (read-uncommitted) goes **after** the table name: `FROM Ens.MessageHeader %NOLOCK`.
  Note: some execution paths reject `%NOLOCK` (observed `SQLCODE -25` via the Atelier query
  endpoint) — drop it there if it errors.
