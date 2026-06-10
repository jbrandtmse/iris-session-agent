# Performance, Query Plans, and the Optimizer

Trace tables are large (often millions of rows) and full of encoded/stream columns. This file
covers reading plans, the optimizer hints that actually help, and — importantly — the traps
where the optimizer's *estimated cost* lies to you and you must measure the *clock* instead.

## Reading query plans

- **`EXPLAIN SELECT ...`** returns the showplan as an XML `<plans>` document (a single `Plan`
  column over the Atelier query endpoint). `<cost value="N"/>` is the optimizer's **estimated
  relative cost**, derived from table statistics — **not** a runtime measurement.
  - Use it only for **relative, apples-to-apples** comparison of two plans **on the same
    instance against the same data**. The magnitude does **not** transfer between instances
    (a dev box and a prod box with different row counts and statistics produce different costs).
- **`EXPLAIN STAT`** is unreliable via the Atelier endpoint — it returns near-zero runtime
  stats (`GlobalRefs=1`, `RowCount=0`) because it doesn't fully execute the worker modules
  through that path. For *measured* runtime (global references, time), use the Management Portal
  → System Explorer → SQL page instead, or time the actual execution.

## The cost-vs-runtime trap (read this twice)

**Estimated cost frequently disagrees with measured runtime. Trust the clock.** Concrete,
verified failure modes:

1. **Parameterized literals fool selectivity estimates.** For a `SELECT TOP N ... WHERE
   <bitmap-indexed col>='X' AND ID > {watermark} ... ORDER BY ID`, forcing the optimizer off
   the time index onto the ID-ordered bitmap (`%IGNOREINDEX TimeCreated`) was measured **~25×
   faster (25 s → 1 s)** *despite a 33× **higher** estimated cost*. The watermark/cutoff
   literals defeated the optimizer's selectivity math.

2. **Always-true range predicates collapse estimated cost without changing the plan.** Adding
   `AND ID > 1` (or `SessionId >= {watermark}`) to a query whose driving index is keyed
   `(TimeCreated, ID)` introduces a range condition on a later subscript. The optimizer applies
   a selectivity factor and the **estimated** cost can drop dramatically (observed
   1,377,904 → 2,137; 1,377,904 → 2,022 — a ~500–600× "improvement") **with no change to the
   access path**. Since the predicate filters nothing at runtime, the speedup is an estimation
   *artifact*. It produces a *real* gain only if the changed estimate happens to flip the
   optimizer to a genuinely better plan (e.g. a different join order on a multi-table query) —
   and it's fragile (can backfire after statistics are re-gathered). **Don't ship `ID > 1`
   expecting speed.**

3. **Cold vs warm cache swamps plan differences.** The same query measured **~142 s cold vs
   ~7–8 s warm** on a month of data — a 20× swing from caching alone, while `EXPLAIN` rated the
   cold-slower plan as cheaper. When comparing two plans, run each **warm and cold** and trust
   the measured time, not `<cost value>`.

**Takeaway:** use `EXPLAIN` cost to *generate hypotheses* about plan shape, then **measure** to
decide. Never optimize purely on estimated cost.

## Optimizer hints

All of these go **before** the table name (`SQLCODE -25` if placed after):

| Hint | Effect |
|------|--------|
| `%PARALLEL` | Split the scan into ID subranges processed in parallel, merged by a coordinator. |
| `%IGNOREINDEX {idx}` | Forbid the optimizer from using index `{idx}` (force a different access path). |
| `%ALLINDEX` / `%FULL` | Consider all indexes / force a full scan. |
| `%FIRSTTABLE`, `%STARTTABLE`, `%INORDER` | Pin join order / starting table. |

(`%NOLOCK`, the read-uncommitted hint, is the exception — it goes *after* the table name.)

### `%PARALLEL` — when it helps and when it hurts

**Helps:**
- Large `GROUP BY` / `COUNT` / `SUM` scans, especially when the dominant cost is a per-row
  master-map read. The showplan shows "Call module ... in parallel on each subrange."
- Large **anti-joins** (`NOT EXISTS` over big body tables) that otherwise time out serially —
  e.g. orphan detection, where there's no index on `Ens.MessageHeader.MessageBodyId`.

**Hurts / no-ops:**
- **Small tables** — the optimizer may decline it (verified: on a ~15k-row table, parallel cost
  ≈ serial cost). It's a *request*, not a guarantee.
- **Inside a scalar `COUNT(*)` subquery** — counter-productive (observed slower than plain).
  Don't parallelize the subqueries of a count-comparison.
- **Many `%PARALLEL` queries at once** — they oversubscribe cores and *all* time out. Run one
  at a time, and prefer off-peak on busy production systems (parallel workers compete with live
  traffic for CPU).

### `%IGNOREINDEX` — forcing a better access path

Placement: `FROM %IGNOREINDEX TimeCreated Ens.MessageHeader` (index name before the table).
Use case (verified): a `TOP N ... WHERE MessageBodyClassName='X' AND ID > {watermark} ...
ORDER BY ID` defaults to driving off the `TimeCreated` index, master-map-reading every
candidate to apply the class filter, then **materializing the whole qualifying set into a
temp-file sorted by ID and only then taking `TOP N`** (no short-circuit) — roughly O(N²) across
a watermark loop. Forcing `%IGNOREINDEX TimeCreated` makes it drive the **ID-ordered
`MessageBodyClassName` bitmap**, which satisfies `ORDER BY ID` with no sort, touches only the
target class, and **short-circuits at `TOP N`**. Measured ~25× faster despite a higher estimated
cost. (Caveat: it still master-reads each target-class row in ID order to test a `TimeCreated`
cutoff, so an aggressive cutoff means reading more than N to fill a batch.)

## Indexing realities on `Ens.MessageHeader`

Verified on a real instance (yours may differ — check `INFORMATION_SCHEMA.INDEXES`):

- Indexes are typically **single-column** — commonly there are **no compound indexes**:
  `Extent`/`IDKEY` (ID), `TimeCreated`, `SessionId`, `MessageBodyId`, `SourceConfigName`,
  `TargetConfigName`, `MessageBodyClassName`, `Status`.
- **Bitmap indexes** on `TargetConfigName`, `MessageBodyClassName`, `TimeCreated`,
  `SourceConfigName`, `Status`. A three-way bitmap intersection of e.g.
  (`TargetConfigName` × `MessageBodyClassName` × `TimeCreated`) is fast.
- **No bitmap index on `Type`** — a `Type=1/2` filter is applied as a post-bitmap row-by-row
  test, *not* an index lookup. It reduces *results*, not *rows read*. Don't expect `Type`
  filtering to cut I/O.
- Standard (non-bitmap) indexes are physically keyed `(value, ID)`.
- Storage globals: data `^Ens.MessageHeaderD`, index `^Ens.MessageHeaderI`.

**Consequence — the master-map read floor:** any predicate needing a column **not** carried in
the driving index forces a per-row master-map read. Example: a by-day **session** count drives
the `TimeCreated` index but must master-read each row for `SessionId` (not co-indexed) — that
per-row read is the cost floor. By contrast, a pure `COUNT(*)` grouped by
`TO_CHAR(TimeCreated,'YYYY-MM-DD')` over a time range is **index-only** (plan shows
`Read index map ...TimeCreated` with no master read) and returns in seconds even over
multi-million-row tables; `%PARALLEL` splits the index range across cores.

## I/O-bound vs plan-bound

If a query is slow because it reads many **fat body rows** (large streams/SAML payloads), no
amount of join rewriting helps — it's **I/O-bound**, not plan-bound. Signs: rewriting the join
(pinning configs to literals, adding rsh time windows, derived tables) yields the **same plan**
and ~unchanged estimated cost; the cost is cold reads of big bodies. Levers that actually help:
chunk by time, refresh statistics (`TUNE TABLE`), increase buffer-pool/global cache, run warm,
or **materialize a slim reporting table** (see below). Don't keep rewriting the query.

## The read-only projection-index pattern (covering index on an unmodifiable class)

When a compound/covering index would make a query index-only, but the table is a **system class
you must not modify** (`Ens.*`, `EnsLib.*`, `HS.*` — overwritten on upgrade), create a
**projection class**: a separate persistent class whose storage points at the *same data
global* but its *own index global*.

```objectscript
Class Custom.EventLogIndex Extends %Persistent
{
  // Only the properties needed for the index + query, mapped to the original storage positions.
  Property ConfigName  As %String;
  Property Type        As %Integer;
  Property TimeLogged  As %TimeStamp;
  Property MessageId   As %Integer;

  Index CompoundIdx On (ConfigName, Type, TimeLogged);

  Storage Default {
    <DataLocation>^Ens.Util.LogD</DataLocation>          // SAME data global as the original
    <IndexLocation>^Custom.EventLogIndexI</IndexLocation> // your OWN index global
    // <Value> positions must match the original class's storage layout exactly
  }
}
```

- Inserts go through the original class, so the projection index does **not** auto-update — run
  `%BuildIndices()` on a scheduled task. Acceptable for recent-/time-bounded data.
- Query change: `FROM Original_Schema.Table` → `FROM Custom_Schema.ProjectionTable`; the
  optimizer uses your compound index instead of a bitmap intersection or master-map read.
- When to reach for it: showplan shows bitmap intersection or per-row master reads as the
  dominant cost and a covering index would eliminate it, but the table is a system class.

## Orphaned message-body detection — a cautionary perf+correctness tale

An "orphan" is a persistent body row with **no `Ens.MessageHeader` referencing it** (body
`%Save()`'d but never headed/routed, or its header was purged while the body lingered). It's a
common cleanup question, and it's a minefield:

- **Pure-SQL orphan counts OVER-COUNT for any base class that has subclasses** (shared extent —
  see `02`). A base-class-only `NOT EXISTS` flags live, *headed* subclass messages as false
  orphans. (Verified: a base-only filter reported 51 "orphans" where the true count was 0.)
- **Always match id AND class** (`MessageBodyId` is class-scoped).
- Best-effort SQL matches the base class **and all its subclasses** with `IN (...)`, queried
  **once** per hierarchy, and needs `%PARALLEL` (no index on `MessageBodyId`, so serial
  anti-joins time out):
  ```sql
  SELECT COUNT(*) FROM %PARALLEL HS_Message.SomeResponse b
  WHERE NOT EXISTS (
    SELECT 1 FROM Ens.MessageHeader h
    WHERE h.MessageBodyId = b.%ID
      AND h.MessageBodyClassName IN ('HS.Message.SomeResponse', '<subclass1>', '<subclass2>')
  )
  ```
- Even this isn't fully reliable — the `IN (...)` list is only as complete as the subclasses you
  enumerate (`%Dictionary.CompiledClass`, `04`); a missed/uncompiled live subclass re-introduces
  over-counting. The only fully reliable check confirms each candidate by its **row's actual
  class** (open the object, check `%ClassName`), which **cannot be done in pure SQL**.
- **Never drive a `DELETE` from a SQL orphan count.** (And this guide is read-only regardless.)
  Leaf classes (no subclasses) are counted correctly on their own name; the `BodyRows −
  HeaderRows` triage is a valid lower bound for leaf classes only.
