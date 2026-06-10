# Querying InterSystems IRIS Interoperability Message Traces — Agent Guide

This guide teaches an AI agent how to write correct, performant SQL queries against
**InterSystems IRIS Interoperability** message-trace data (the `Ens.*` message model and
the message-body tables it routes), plus the IRIS SQL dialect quirks you must respect to
get correct results.

It is distilled from hands-on experience building and refining hundreds of trace queries
against live IRIS instances. Everything here is **generic** — it assumes nothing about any
particular deployment, tool, or proprietary schema. Schema reference is limited to:

- `%`-prefixed system tables (`INFORMATION_SCHEMA.*`, `%Dictionary.*`)
- `Ens.*` Interoperability framework tables (e.g. `Ens.MessageHeader`, `Ens.Util.Log`)
- `HS.*` HealthShare standard message classes (e.g. `HS.Message.*`, `HS.FHIRServer.*`)
- Other standard IRIS / `EnsLib.*` classes

> **Most of what you query in a real deployment is custom and undocumented here.** You will
> encounter **application-specific** message-body classes *and* non-message tables (lookup /
> reference / directory tables, config tables, `Ens.SearchTableBase` search tables, reporting
> tables) with names you've never seen. This guide's `Ens.*`/`HS.*`/`%` reference is the stable
> portable core; the rest is local to the deployment. Don't hardcode or assume — **discover,
> explore, and learn** custom tables at runtime (see `04-schema-discovery.md` →
> "Discovering custom application tables"). Wherever an example needs a concrete application
> name, it uses an obvious placeholder like `MyApp.Some.Process` or `INTEROPNS` — substitute
> what you discover live.

## How to execute queries

This guide is execution-agnostic. SQL reaches IRIS through one of:

- **Atelier REST API** (most portable for an agent): `POST {base}/api/atelier/v1/{namespace}/action/query`
  with body `{"query": "SELECT ..."}` and HTTP Basic auth. Results come back as
  `result.content` (array of row objects); errors in `status.errors`. The user account needs
  the `%Development` resource. See `08-execution-and-connection.md`.
- **JDBC/ODBC**, the `iris sql` shell, the Management Portal SQL page, `%SYSTEM.SQL`, or
  embedded SQL — all run the same dialect described here.

IRIS SQL is **namespace-scoped**: you connect to one namespace and cannot JOIN across
namespaces in a single statement. Pick the namespace that holds the production/trace data.

## Read these in order

| File | What it covers |
|------|----------------|
| `00-query-methodology.md` | The disciplined, iterative workflow for building a correct trace query — how I actually approach the problem. |
| `01-iris-sql-dialect.md` | IRIS SQL syntax that differs from standard SQL: `TOP`, `%ID`, ODBC `{fn}` escapes, dates, `%EXTERNAL`/`%ODBCOUT`, `$LIST`, streams, case sensitivity, reserved words. |
| `02-interop-message-model.md` | How `%Persistent` classes project to SQL tables (columns, embedded serial objects, collections, relationships, RowID/IDKEY), inheritance/extents/polymorphism and `%CLASSNAME`; then the `Ens.MessageHeader` routing model: header↔body, sessions, request/response correlation, AdditionalInfo collection tables. |
| `03-performance-and-plans.md` | Reading `EXPLAIN`, optimizer hints (`%PARALLEL`, `%IGNOREINDEX`), the cost-vs-runtime trap, cold/warm cache, indexing, and the read-only projection-index pattern. |
| `04-schema-discovery.md` | Discovering schemas, tables, columns, body types, and class→table mappings at runtime via `INFORMATION_SCHEMA` and `%Dictionary`. |
| `05-reference-ens-tables.md` | Detailed field-by-field reference for `Ens.MessageHeader` and `Ens.Util.Log`. |
| `06-reference-hs-message-tables.md` | Detailed reference for standard HealthShare body classes: `HS.Message.*`, `HS.FHIRServer.Interop.Request` — SAML data, content streams, AdditionalInfo. |
| `07-query-cookbook.md` | Copy-adaptable query patterns: daily counts, error rates, latency, session traces, document counting, orphan detection. |
| `08-execution-and-connection.md` | The Atelier REST API contract, connection setup, safety limits, and read-only discipline. |

## The two cardinal rules

1. **Read-only.** Trace querying is `SELECT` only. Never emit `INSERT/UPDATE/DELETE/DROP/CREATE/ALTER/TRUNCATE`.
2. **Show your work and validate every result.** After every execution, show the exact SQL
   *and* its output, and confirm with the user that the result is correct before building
   further. A query that "runs" is not the same as a query that is *right* — IRIS will
   silently return wrong rows for several traps documented here (integer-vs-string columns,
   case-folding, IsError on the wrong leg). Verification is not optional.
