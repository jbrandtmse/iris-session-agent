# Query-Building Methodology

This is the internal approach — how to go from a vague request ("show me the failing XCPD
queries in the last day") to a correct, validated SQL statement. Trace data is deceptively
hard: the schema is dynamic, columns are encoded, and the JOINs have non-obvious correctness
traps. A disciplined loop beats one-shot guessing every time.

## The loop: Discover → Build → Execute → Validate → Refine

```
        ┌─────────────────────────────────────────────┐
        ▼                                             │
  Discover schema   →   Build/modify SQL   →   Execute (small TOP N)
  (only what you             │                        │
   don't already know)       │                        ▼
                             │                  Show SQL + results
                             │                        │
                             └──── Refine ◀──── Validate with user
                                  (diagnose,          │
                                   fix, re-run)   confirm correct?
                                                       │ yes
                                                       ▼
                                                  Finalize / next field
```

### 1. Understand the question before touching SQL
Translate the request into concrete terms:
- **Which table is the spine?** Almost always `Ens.MessageHeader`. Most trace questions are
  "messages where X" or "sessions where X".
- **Header-only, or do I need a body table?** If the question only references routing metadata
  (timestamps, components, error status, session) it's header-only. If it references payload
  content (patient name, OID, document count, FHIR path) you must JOIN to a body table.
- **Is it per-message, per-session, or an aggregate/rate?** This decides whether you GROUP BY,
  count session-starts, or correlate request↔response.
- **What time window?** Trace tables are huge. *Always* bound by time unless the user truly
  wants everything. Default to a narrow window (1 day) and widen on request.

### 2. Discover only what you don't already know
Don't query `INFORMATION_SCHEMA` for things you've already learned. But never *assume* a
body table's columns — schemas vary by IRIS version and by application. Before joining to a
body table you haven't seen:
- Map its `MessageBodyClassName` → SQL `schema.table` (see `02`).
- Pull its columns from `INFORMATION_SCHEMA.COLUMNS`.
- If it has an `_AdditionalInfo` collection table, enumerate the keys (see `02`).
See `04-schema-discovery.md` for the exact queries.

**Persist what you learn.** Keep per-table notes (column types, decode functions, gotchas,
working JOIN patterns, which namespace/instance you verified them in). Re-reading your own
notes before building a new query is the single highest-leverage habit — it prevents
re-discovering the same encoding traps and lets you transfer a proven pattern (e.g. a failure-
rate query) from one body type to a similar one.

### 3. Build incrementally
Start from the header spine and add one thing at a time:
1. `FROM Ens.MessageHeader hdr` + a time filter + a handful of header columns.
2. Run it. Confirm the shape.
3. Add the body JOIN (with its `MessageBodyClassName` filter). Run. Confirm.
4. Add related-table JOINs, AdditionalInfo pivots, aggregates — each followed by a run.

Adding everything at once and debugging a 6-JOIN query that returns nothing is the slow path.
One change per iteration localizes every bug.

### 4. Always run with a small `TOP N` first
Preview with `SELECT TOP 10` (or whatever the user wants to eyeball). Only remove/raise the
limit once the query is confirmed correct. This keeps iterations fast and protects huge tables.

### 5. Show the SQL *and* the output — every single time
Every turn that executes SQL must display both the exact statement and what came back —
including diagnostic probes, schema lookups, and data samples, not just the "final" query.
Never run a query silently and never summarize results without showing them. The user catches
correctness problems you can't see (a column that *looks* populated but is the wrong org, a
count that's an order of magnitude off).

### 6. Validate, then refine — never auto-confirm
After showing results, explicitly ask whether the output is correct. If the user reports a
problem, diagnose against the checklist below, explain the fix and *why*, re-run, and ask
again. Loop until confirmed. Do not move on to the next field/aggregate until the current
result is accepted.

## Diagnostic checklist (when results are wrong)

| Symptom | Likely cause → fix |
|---------|--------------------|
| **Missing rows / fewer than expected** | `INNER JOIN` excluding non-matching rows → switch to `LEFT JOIN`. Or WHERE too tight (date range, exact class name) → relax. Or `MessageBodyClassName` case/spelling wrong → verify the *actual stored* value. |
| **Zero rows from a filter that "should" match** | Integer column compared to a string literal (`Type='Response'`, `Status!='Delivered'`) silently coerces to `0` and matches nothing / everything. Use the integer code or `%EXTERNAL()`. Also: a hardcoded `ID > N` floor copied from another instance — ID magnitudes are per-instance. |
| **Duplicate rows** | Cartesian product from a missing JOIN predicate, or genuinely multiple headers/bodies per session. Fix the ON clause or add the discriminating predicate (e.g. `TargetConfigName`) — don't slap on `DISTINCT` to paper over a real join bug. |
| **A column is all NULL** | A `LEFT JOIN` with no match (often *correct* — explain it), or you're reading the field on the wrong leg (e.g. SAML data empty on the responding side / on fan-out legs), or the column genuinely isn't populated in this flow. |
| **Garbled / binary-looking data** | The column is an encoded `%Status` (`%ODBCOUT()`), an integer-coded enum (`%EXTERNAL()`), a `$LIST` (`$LISTGET()`), or a stream (`SUBSTRING()`). See `01`. |
| **Error text is many near-identical strings** | Group by a truncated prefix and show `MIN(...)` of the full text (see `07`). |
| **`SQLCODE -29`** | You referenced a column alias in `GROUP BY`/`ORDER BY`. Wrap the computed expression in a subquery. |
| **`SQLCODE -1` on an alias** | The alias is a reserved word (`COUNT`, `ROWS`). Rename it. |
| **`SQLCODE -25` ("encountered after end of query")** | A `%PARALLEL`/`%IGNOREINDEX` hint placed *after* the table name (must be *before*), or `%NOLOCK` used where the endpoint rejects it. See `01`/`03`. |
| **`SQLCODE -37` / `-40`** | `SUBSTR`/`LOCATE` used on a stream or as an `{fn}` escape that isn't supported — use `SUBSTRING`/`CHARINDEX`. |
| **Timeout / very slow** | Narrow the time window; lower `TOP N`; add `%PARALLEL` for large aggregates/anti-joins; add a matching time predicate *on a correlation JOIN* (not just WHERE); avoid `COUNT(DISTINCT)` on huge tables. See `03`. |

## When you hit a knowledge gap
If you're unsure about a function's syntax, a type's encoding, or a class's behavior:
1. Check your own persisted notes and this guide first.
2. Probe the data directly — `SELECT TOP 3` the raw column, or count non-null values — and
   show the user what you found.
3. Consult InterSystems IRIS SQL documentation (web search "InterSystems IRIS SQL <topic>")
   if available. Verify anything you're not certain of rather than guessing silently.
