# Schema Discovery at Runtime

Never hardcode a body table's columns or assume a class→table mapping. Discover them live —
schemas vary by IRIS version, by HealthShare/EnsLib version, and by application. These queries
work in any namespace.

> **Assume you are walking into an environment full of tables this guide does not document.**
> Every real deployment has **custom, application-specific schemas and tables** — proprietary
> message-body classes, plus non-message tables (lookup/reference/directory tables, config
> tables, `Ens.SearchTableBase` search tables, reporting tables, embedded-business-logic
> classes). The `Ens.*`/`HS.*`/`%` reference in this guide is the *stable, portable* core; the
> bulk of what you'll actually join to is local to the deployment and has names you've never
> seen. Your job is to **discover, explore, and learn** those at runtime — the rest of this file
> is the toolkit for doing exactly that. See "Discovering custom application tables" below for
> the end-to-end workflow.

## List schemas (excluding system schemas)

```sql
SELECT SCHEMA_NAME
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE NOT SCHEMA_NAME %STARTSWITH '%'
ORDER BY SCHEMA_NAME
```

## List tables in a schema

```sql
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'Ens'
ORDER BY TABLE_NAME
```

## List columns of a table

```sql
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Ens' AND TABLE_NAME = 'MessageHeader'
ORDER BY ORDINAL_POSITION
```

Reading the column list, flag for yourself:
- Likely **foreign keys** (names ending in `Id`, or types referencing another persistent class).
- The **payload-bearing** columns vs metadata.
- **Stream** columns (`longvarchar`/`longvarbinary`) — need `SUBSTRING` (see `01`).
- Anything that looks **encoded** (integer where you expected text → probably an enum; a column
  documented as `%Status` → `%ODBCOUT`).

## List indexes (to reason about access paths)

```sql
SELECT *
FROM INFORMATION_SCHEMA.INDEXES
WHERE TABLE_SCHEMA = 'Ens' AND TABLE_NAME = 'MessageHeader'
```

Tells you which columns are indexed and whether indexes are bitmap, single-column, or compound
— directly informs the performance reasoning in `03`.

## Which message body types are actually in use

The most useful first query in any new namespace — shows which body tables have data worth
joining to, and at what volume:

```sql
SELECT DISTINCT MessageBodyClassName, COUNT(*) AS MsgCount
FROM Ens.MessageHeader
WHERE TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
GROUP BY MessageBodyClassName
ORDER BY MsgCount DESC
```

## Which production components (config names) are active

Tells you what `SourceConfigName`/`TargetConfigName` values you can filter on:

```sql
SELECT DISTINCT SourceConfigName, TargetConfigName, MessageBodyClassName
FROM Ens.MessageHeader
WHERE TimeCreated > DATEADD('day', -1, CURRENT_TIMESTAMP)
ORDER BY SourceConfigName, TargetConfigName
```

## Class → SQL table mapping (authoritative)

Rather than hand-deriving `schema.table` from a class name, ask the catalog. This also lets you
sweep an unknown set of body types and map each to its table:

```sql
SELECT DISTINCT h.MessageBodyClassName, c.SqlSchemaName, c.SqlTableName
FROM ( SELECT DISTINCT MessageBodyClassName AS mbc
       FROM Ens.MessageHeader
       WHERE MessageBodyClassName IS NOT NULL AND MessageBodyClassName <> '' ) h
JOIN %Dictionary.CompiledClass c
  ON UPPER(c.Name) = UPPER(h.mbc)
WHERE c.ClassType = 'persistent'
```

Two non-obvious requirements:
- **`UPPER()` on both sides of the join is mandatory.** `%Dictionary.CompiledClass.Name` uses
  case-sensitive (EXACT) collation and is mixed-case (`HS.Message.XMLMessage`), while
  `MessageBodyClassName` is frequently stored ALL CAPS (`HS.MESSAGE.XMLMESSAGE`). A plain `=`
  join returns nothing.
- **Filter `ClassType = 'persistent'`** to skip body classes that have no SQL table.

## Enumerate subclasses of a base class

Needed for correct orphan detection and for any query against a base body class that has
subclasses (shared-extent issue, see `02`/`03`):

```sql
SELECT Name
FROM %Dictionary.CompiledClass
WHERE UPPER(Super) [ UPPER('HS.Message.SomeResponse')   -- [ is the "contains" operator
```

Recurse for deeper hierarchies, and verify per namespace — a subclass that isn't compiled in
this namespace won't appear (and that's exactly the gap that re-introduces orphan over-counting).

## Identify a row's *real* class with `%CLASSNAME`

Because a base table also returns subclass rows (polymorphic extent — see `02`), the table you
queried does **not** tell you a row's actual class. The `%CLASSNAME` pseudo-column does — it's the
authoritative per-row class identifier IRIS stores with every object:

```sql
-- what subclasses actually live in this base extent, and how many of each?
SELECT %CLASSNAME AS RealClass, COUNT(*) AS Cnt
FROM HS_Message.SomeResponse
GROUP BY %CLASSNAME
ORDER BY Cnt DESC

-- restrict a base-table query to genuine base-class rows (exclude subclasses)
SELECT %ID, ... FROM HS_Message.SomeResponse WHERE %CLASSNAME = 'HS.Message.SomeResponse'
```

Use this to (a) discover which subclasses are present in real data before building an `IN (...)`
list, and (b) get correct counts when a base class has subclasses.

## Find a collection (`_AdditionalInfo`) table and its keys

Check existence:
```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'MyApp_Message' AND TABLE_NAME = 'SomeBody_AdditionalInfo'
```
Enumerate keys (do this the first time you encounter a body table — it tells you what you can
pivot later):
```sql
SELECT DISTINCT element_key, COUNT(*) AS Cnt
FROM MyApp_Message.SomeBody_AdditionalInfo
GROUP BY element_key
ORDER BY Cnt DESC
```
Verify the FK column name and that the collection table actually links to the body class you
think it does — a same-named collection table can belong to a *different* persistent class with
a different RowID column and not FK to your table (see `06` for a real example of this trap).

## Sample rows

A concrete feel for the data beats guessing:
```sql
SELECT TOP 5 * FROM MyApp_Message.SomeBody
```
Use this to confirm encodings (is that column a `$LIST`? a `%Status`? an enum?) before writing
the real query — and always show the user what came back.

## Discovering custom application tables (end-to-end)

You will routinely need a table that is **not** documented in this guide and **not** reachable
from `Ens.MessageHeader` (a reference/lookup/directory table, a config table, an
`Ens.SearchTableBase` search index, a reporting table, or just an app's own persistent class).
Treat any unknown table as a discovery task, not a guess. The workflow:

**1. Find candidate schemas.** List non-system schemas (above). Application schemas are the
ObjectScript packages with dots→underscores (e.g. class package `My.App.Directory` → schema
`My_App_Directory`). Browse them to see what the deployment defines.

**2. Find candidate tables.** List tables per schema (above). To search broadly by name across
all schemas when you only know a fragment (e.g. "directory", "patient", "config"):
```sql
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE UPPER(TABLE_NAME) [ UPPER('directory')        -- [ = "contains"
ORDER BY TABLE_SCHEMA, TABLE_NAME
```
Filter to base tables (exclude views) with `TABLE_TYPE = 'BASE TABLE'` if needed.

**3. Get the authoritative class behind a table** (and vice-versa) — useful because gotchas
live at the class level (data types, serial/`$LIST` properties, relationships):
```sql
SELECT Name, SqlSchemaName, SqlTableName, Super, ClassType
FROM %Dictionary.CompiledClass
WHERE SqlSchemaName = 'My_App_Directory' AND SqlTableName = 'Organization'
```

**4. Read its columns and indexes** (the `INFORMATION_SCHEMA.COLUMNS` / `.INDEXES` queries
above). Note FK-looking columns, stream/`$LIST`/`%Status`/enum columns, and what's indexed.

**5. Sample rows** (above) to confirm real encodings and population before trusting any column.

**6. Find how it links to the trace data.** A custom lookup/reference table usually joins to a
body column (an OID, code, config name, or id). Confirm the join key by sampling both sides and
matching a few values by hand — don't assume a column named `OrgID` on one table equals
`OrgID` on another (case, prefixes like `urn:oid:`, alias-vs-OID — see `06`). Watch the
case-collation trap: if either side uses EXACT collation, `UPPER()` both sides of the join.

**7. Persist what you learned.** Record the table's columns, encodings, decode functions, the
confirmed join key(s) to the trace tables, any gotchas, and *which namespace/instance you
verified it in*. Re-reading your own notes before the next query is the highest-leverage habit
(see `00`). A short per-table note file (class name, SQL `schema.table`, columns, join keys,
gotchas) pays for itself immediately.

> **Search tables (`Ens.SearchTableBase`):** many productions index message content into
> auto-populated search tables (one row per indexed property, keyed back to the message). If you
> find a `*SearchTable*`-named class in the schema list, it can be a far cheaper join target than
> parsing the body stream — discover its columns and the id it carries back to `Ens.MessageHeader`.
