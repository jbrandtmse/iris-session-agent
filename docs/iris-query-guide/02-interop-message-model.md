# IRIS Persistence Model & the Interoperability Message Model

Trace querying revolves around `Ens.MessageHeader` and the body tables it points to — but those
tables are just **SQL projections of ObjectScript `%Persistent` classes**. Understanding how a
class becomes a table, and how inheritance projects, explains nearly every JOIN trap in this
guide: why you must match `(id, class)`, why a base-class query returns subclass rows, why some
columns are underscore-flattened, and why collections live in child tables. Read this first; the
message model below is a special case of it.

## How a `%Persistent` class becomes a SQL table

In IRIS the **class is the source of truth**; the SQL table is a *generated projection* of it.
You query the projection, but the gotchas come from the class definition.

- **Package → schema, class short name → table.** Class `My.App.PatientRequest` projects to SQL
  `My_App.PatientRequest` — every dot *except the last* becomes `_`; the part after the last dot
  is the table name (see `01`). The default package `User` maps to SQL schema `SQLUser`. A class
  can override either part with the `SqlSchemaName` / `SqlTableName` class keywords, so don't
  *assume* the name — confirm it from `%Dictionary.CompiledClass` (`SqlSchemaName` /
  `SqlTableName` columns, see `04`).
- **Stored literal properties → columns.** Each persistent property becomes a column of the same
  name (overridable per-property with `SqlFieldName`); **inherited properties are included** in
  the subclass's table.
- **RowID / `%ID`.** Every persistent class has an auto-assigned object identity — the ID —
  projected as the RowID column. IRIS names it `ID` when it can; if the class defines its own
  `ID` property, the system RowID is renamed `ID1`/`ID2`/…. The RowID is unique-constrained and
  non-updatable. **Always use the `%ID` pseudo-column in joins** — it resolves to the RowID
  whatever the real column name is (see `01`). An `IDKEY` index makes the RowID a *composite* of
  chosen properties instead of a plain integer counter (common for child/relationship classes).
- **Embedded serial objects (`%SerialObject`) → underscore-flattened columns.** A property whose
  type is a serial class is stored *inline in the same row*, and its sub-properties project as
  columns named `Property_SubField`. This is exactly why you see `SAMLData_OrganizationID`,
  `Errors_HighestError`, `BirthPlace_City`, etc. — `SAMLData`, `Errors`, `BirthPlace` are
  embedded serial objects, **not** separate tables. Deeper nesting just adds more underscores.
  You cannot join to these — they're plain columns on the parent row.
- **Collection properties (`list of` / `array of`) → child tables.** A collection projects as a
  *separate child table* (commonly `ParentTable_PropertyName`) with a foreign-key column back to
  the parent's RowID, plus the element value and an element index/key. This is the mechanism
  behind the `_AdditionalInfo` key-value tables described later in this file.
- **Relationships → child tables + foreign keys.** A one-to-many relationship projects the
  "many" side as its own table with an FK to the parent RowID. A *parent/child* (dependent)
  relationship goes further: the child's RowID **incorporates the parent's ID**, and the child
  can't exist without its parent. Both surface in SQL as foreign keys with referential integrity.
- **Caution:** not everything is a relational column. Calculated/transient properties aren't
  stored, and a serialized `$LIST` held in a *single* column is **not** a relational collection —
  it can't be joined and must be unpacked with `$LISTGET` (see `01` and the FHIR `Request_AdditionalInfo`
  example in `06`, which is a serialized `$LIST`, unlike the relational `_AdditionalInfo` tables).

## Inheritance, extents, and polymorphism

An **extent** is "all the stored rows for a persistent class." How inheritance maps to extents
drives several correctness traps:

- **Default multi-class extent (polymorphic).** With the default `%Storage.Persistent`
  projection, a subclass `B Extends A` is part of `A`'s extent: `A`'s extent contains every `A`
  **and** every `B`. Therefore **`SELECT ... FROM A` returns rows for `A` and all its
  subclasses.** A subclass table exposes the inherited columns plus its own.
- **`%CLASSNAME` reveals a row's *real* class.** IRIS stores an internal class identifier with
  each row (so `%OpenId` knows which class to instantiate); SQL exposes it as the pseudo-column
  `%CLASSNAME`. Use it to see or filter the actual class of polymorphic rows:
  `SELECT %ID, %CLASSNAME FROM A` or `WHERE %CLASSNAME = 'My.App.B'`. This is the authoritative
  per-row class — more reliable than inferring class from which table you queried.
- **RowIDs are unique *per extent*, not globally.** Within one shared extent (a base class and
  its subclasses) every RowID is unique. But two **unrelated** persistent classes have
  **separate extents with independent ID counters**, so the *same integer ID exists in both*.
  What is globally unique is the OID (`class || ID`), not the integer alone.

**Why this matters for message bodies — two distinct traps, kept separate:**

1. **Across different body classes → IDs collide.** Distinct body classes live in separate
   extents, so `MessageBodyId` (the integer) is **class-scoped, not globally unique** — the same
   id exists in many body tables. **Always join headers to bodies on id _and_ class together**,
   never on `MessageBodyId` alone.
2. **Within one base class's subclass hierarchy → over-counting.** Because a base table also
   returns its subclasses' rows, filtering only on the base class name (e.g. in an orphan
   `NOT EXISTS`) sweeps in live subclass messages that are actually headed under their *own*
   class names. Match the base class **and all subclasses** with `IN (...)` (enumerate them from
   `%Dictionary.CompiledClass`, `04`), or confirm each row with `%CLASSNAME`. See `03`/`07`.

(A superclass can be configured for an *alternative* projection where each subclass gets its own
extent and ID space — less common, but if you observe per-subclass ID sequences, that's why.)

## `Ens.MessageHeader` — the routing spine

Every message that flows through an Interoperability *production* gets exactly one row in
`Ens.MessageHeader`. The header holds **routing metadata** — who sent it, who received it,
when, status, error — but **not the payload**. Key columns (full reference in `05`):

- `ID` / `%ID` — the header's RowID.
- `SessionId` — groups all headers belonging to one logical exchange/trace. **The first
  message in a session has `ID = SessionId`** (the session-initiating header) — a fact you'll
  use constantly.
- `Type` — **integer**: `1` = Request, `2` = Response.
- `SourceConfigName` / `TargetConfigName` — the production components (business services /
  processes / operations) the message went from/to. These are your primary routing filters.
- `TimeCreated` / `TimeProcessed` — when the header was created / finished being processed.
- `Status` (integer enum, decode with `%EXTERNAL`), `IsError` (bit), `ErrorStatus` (`%Status`,
  render with `%ODBCOUT`).
- `CorrespondingMessageId` — points to the correlated request/response partner (bidirectional,
  but **not always populated** — see below).
- `MessageBodyClassName` + `MessageBodyId` — the pointer to the payload (see next section).

## Header → body: the payload lives in a separate table

The actual message content is in a **different table per message type**, identified by two
header columns:

- `MessageBodyClassName` — the full ObjectScript class name of the body (e.g.
  `HS.Message.PatientSearchRequest`, `EnsLib.HL7.Message`, or any app class).
- `MessageBodyId` — the foreign key into that body table's `%ID`.

To join header to body:

```sql
INNER JOIN HS_Message.PatientSearchRequest body
  ON hdr.MessageBodyId = body.%ID
WHERE hdr.MessageBodyClassName = 'HS.Message.PatientSearchRequest'
```

Critical rules:

1. **Convert the class name to `schema.table`** by replacing all dots-except-the-last with
   underscores (see `01`). Confirm via `%Dictionary.CompiledClass` when unsure.
2. **Always include the `MessageBodyClassName` filter** (or put it in the JOIN ON when mixing
   types). Without it, the join is ambiguous and wrong — because:
3. **`MessageBodyId` is class-scoped, not globally unique.** Different body classes are separate
   extents with independent ID counters, so the same integer id exists in many body tables (see
   "Inheritance, extents, and polymorphism" above). You must always match **id AND class
   together** — never join on `MessageBodyId` alone.
4. **Use `LEFT JOIN` when not every header has a matching body** of the class you're filtering
   on (mixed-type result sets, or headers with null bodies). Add `MessageBodyId IS NOT NULL`
   before a body join to skip no-body header rows defensively.

### Base/subclass over-counting (important)

Because a base body table also returns its **subclasses'** rows (the polymorphic extent
described above), filtering only on the base class name while the data contains subclass messages
— each headed under its *own* class name — misattributes those rows. This matters most for orphan
detection — see `03` and `07`. The fix: match the base class **and all its subclasses** with
`IN (...)` (enumerate via `%Dictionary.CompiledClass`, `04`), or confirm each row's real class
with the `%CLASSNAME` pseudo-column.

## Sessions

A `SessionId` ties together every header in one logical exchange (an inbound request, all the
internal routing legs it spawns, downstream calls, and the final response). Patterns:

- **Session-initiating header:** `ID = SessionId`. There is exactly one per session.
  ```sql
  -- the row that started the session:
  INNER JOIN Ens.MessageHeader fsh
    ON fsh.ID = hdr.SessionId AND fsh.SessionId = hdr.SessionId
  -- fsh.TimeCreated = session start time
  ```
- **Full session trace (all legs, chronological):**
  ```sql
  SELECT ID, Type, SourceConfigName, TargetConfigName, MessageBodyClassName,
         TimeCreated, %EXTERNAL(Status) AS Status
  FROM Ens.MessageHeader
  WHERE SessionId = :session
  ORDER BY TimeCreated ASC
  ```
- **Session finish (final response back to the initiator):** correlate to the *session
  initiator*, matching the final response leg whose target is the initiator's source:
  ```sql
  LEFT JOIN Ens.MessageHeader lsh
    ON lsh.SessionId = fsh.SessionId
    AND lsh.TargetConfigName = fsh.SourceConfigName
    AND lsh.Type = 2
  -- lsh.TimeProcessed = session finish time
  ```
- **One session usually contains many headers for the same body type** (an inbound leg, a
  routed leg, fan-out legs). When you need exactly one, **discriminate by `TargetConfigName`
  (or `SourceConfigName`)** — pick the routing leg you mean — rather than `MIN/MAX(ID)` games.
  E.g. filter to the routed leg (`SourceConfigName = '<the router>'`) to dedupe.

## Request / response correlation

There are two ways to pair a request with its response. Choose based on whether
`CorrespondingMessageId` is populated for the flow:

### A. `CorrespondingMessageId` (when populated)
```sql
LEFT JOIN Ens.MessageHeader resp
  ON resp.CorrespondingMessageId = hdr.%ID
```
- It's **bidirectional** (request and response each point at the other) but **not always
  populated** — many internal/synchronous legs leave it `0`/empty. Verify on a sample before
  relying on it.
- **Performance:** on high-volume flows this join times out even with a WHERE time filter. Add
  a **matching time predicate on the JOIN itself** so both sides are bounded:
  ```sql
  LEFT JOIN Ens.MessageHeader resp
    ON resp.CorrespondingMessageId = hdr.%ID
   AND resp.TimeCreated > DATEADD('hour', -1, CURRENT_TIMESTAMP)
  -- keep the WHERE window and the JOIN window in sync
  ```

### B. Self-join on `SessionId` + swapped configs (when CorrespondingMessageId is 0)
```sql
LEFT JOIN Ens.MessageHeader rsh
  ON rsh.SessionId = rqh.SessionId
 AND rsh.TargetConfigName = rqh.SourceConfigName
 AND rsh.SourceConfigName = rqh.TargetConfigName
 AND rsh.Type = 2
-- latency = DATEDIFF('ms', rqh.TimeCreated, rsh.TimeCreated)
```
Use this on internal legs where `CorrespondingMessageId` is unpopulated and the session fires
the same request/response pair many times (which makes id-pairing ambiguous).

### C. Single-header latency (no join at all)
For "how long did a Business Operation take to respond," the request leg's own
`TimeProcessed − TimeCreated` *is* the response latency — `TimeProcessed` on the request
header ≈ the response header's `TimeCreated`. This avoids a self-join entirely:
```sql
SELECT DATEDIFF('ms', rqh.TimeCreated, rqh.TimeProcessed) AS ResponseMs
FROM Ens.MessageHeader rqh
WHERE rqh.Type = 1 AND rqh.TargetConfigName = 'MyApp.Some.Operations'
  AND rqh.TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
```
Prefer this when the operation is called many times per session (pairing would be ambiguous)
and `CorrespondingMessageId` is 0 on those legs.

> **Where errors live:** `IsError`/`ErrorStatus` are set on the **response** header (`Type=2`),
> not the request. To judge whether a *request* failed, correlate to its response (A or B) and
> check `resp.IsError` / `resp.ErrorStatus` there. Filtering `IsError=1` on requests finds
> nothing.

## AdditionalInfo collection tables (key-value pivot)

Many body classes have array/list properties that IRIS projects as a child **collection
table** named `{Table}_AdditionalInfo`. These are the structured way to read per-message
key-value metadata (endpoints, purposes, identifiers, headers...). Typical columns:

- `{ParentTable}` — FK back to the parent body row's id (the column is named after the parent
  table, e.g. `PatientSearchRequest`).
- `element_key` — the key name (**case-sensitive** string).
- `AdditionalInfo` — the value. (Note the value column is `AdditionalInfo`, *not* `element_value`.)

**Discover the available keys** the first time you meet a body table:
```sql
SELECT DISTINCT element_key, COUNT(*) AS Cnt
FROM MyApp_Message.SomeBody_AdditionalInfo
GROUP BY element_key
ORDER BY Cnt DESC
```

**Pivot keys into columns** with one `LEFT JOIN` per key (always LEFT — not every row has every
key):
```sql
LEFT JOIN MyApp_Message.SomeBody_AdditionalInfo a1
  ON b.ID = a1.SomeBody AND a1.element_key = 'TargetEndpoint'
LEFT JOIN MyApp_Message.SomeBody_AdditionalInfo a2
  ON b.ID = a2.SomeBody AND a2.element_key = 'PurposeOfUse'
-- SELECT a1.AdditionalInfo AS TargetEndpoint, a2.AdditionalInfo AS Purpose
```

Notes:
- Keys are **case-sensitive**; use `%EXACT()` on the *value* when grouping case-significant
  data (URLs, OIDs).
- **Duplicate keys per parent row are possible** (multiple routing steps each add the same
  key). If a single value is expected, use a `TOP 1` correlated subquery instead of a join to
  avoid row multiplication in aggregates:
  ```sql
  (SELECT TOP 1 x.AdditionalInfo FROM MyApp_Message.SomeBody_AdditionalInfo x
     WHERE x.SomeBody = b.ID AND x.element_key = 'TargetEndpoint') AS TargetEndpoint
  ```
- This pattern applies to **any** IRIS body class with array/list properties — not just a
  specific table. Verify the actual collection-table name and FK column via `INFORMATION_SCHEMA`,
  because a similarly-named collection table can belong to a *different* persistent class
  (different RowID column) and not FK to the table you expect.
