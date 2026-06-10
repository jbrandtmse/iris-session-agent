# Execution & Connection (generic)

This guide is execution-agnostic, but an agent needs *some* way to run SQL. The most portable
option that needs no client libraries is the **Atelier REST API** built into IRIS. Any other
path (JDBC/ODBC, the `iris sql` shell, Management Portal, embedded SQL, `%SYSTEM.SQL`) runs the
identical dialect — pick whatever your environment offers.

## Atelier REST API

- **Endpoint:** `POST {base_url}/api/atelier/v1/{namespace}/action/query`
  - `{base_url}` e.g. `https://host:52773` or `http://localhost:52773`
  - `{namespace}` selects which namespace's data you query (IRIS SQL is namespace-scoped — you
    cannot JOIN across namespaces in one statement).
- **Request body:** `{"query": "SELECT ..."}`
- **Auth:** HTTP Basic (username/password). The account needs the **`%Development`** resource
  privilege.
- **Row cap:** append `?max=N` to the URL to limit rows returned — keep a hard cap (e.g. 200 for
  data, 1000 for metadata) on every call as a safety net, independent of any `TOP N` in the SQL.
- **Response JSON shape:**
  ```json
  {
    "status":  { "errors": [], "summary": "" },
    "console": [],
    "result":  { "content": [ { "Col1": "v1", "Col2": "v2" }, ... ] }
  }
  ```
  - Rows are in `result.content` (array of objects keyed by column name/alias).
  - **Always check `status.errors` first** — a non-empty array means the SQL failed; the entry
    carries the `SQLCODE` and message. An empty `content` with no error just means zero rows.

### Minimal call (illustrative — use whatever HTTP client you have)

```bash
curl -s -u "$USER:$PASS" \
  -H 'Content-Type: application/json' \
  -X POST "$BASE/api/atelier/v1/$NS/action/query?max=200" \
  -d '{"query": "SELECT TOP 5 ID, TimeCreated FROM Ens.MessageHeader ORDER BY ID DESC"}'
```

> If you wrap this in a script, **escape `$` in SQL** (e.g. `\$LISTGET`) so the shell doesn't
> expand it, and prefer reading credentials from a file/stdin over putting the password in the
> command line.

## Connection workflow

1. Collect: base URL, namespace, username, password.
2. Test with a trivial query: `SELECT 1 AS ConnectionTest`.
   - HTTP 401/403 → bad credentials or missing `%Development`.
   - Namespace error → wrong/nonexistent namespace.
   - SSL/TLS error → check the URL scheme; you may need to relax cert verification for an
     internal host.
   - Timeout → wrong host/port or network path.
3. Discover `Ens.MessageHeader` columns and the active body types (`04`) to orient.
4. Decide a default preview row count (e.g. 10) and use it as `TOP N` while iterating.

## Choosing the namespace

Trace data lives in the **Interoperability** namespace for the production you care about — the
one whose `Ens.MessageHeader` has the messages. If unsure, you can only see one namespace's
data per connection; reconnect (or re-point the URL's `{namespace}`) to switch. The same query
often works across namespaces but watch for: different component (config) names, body classes
that don't exist everywhere, and per-instance `ID` magnitudes (`05`).

## Safety / discipline

- **Read-only.** `SELECT` only — never `INSERT/UPDATE/DELETE/DROP/CREATE/ALTER/TRUNCATE`. If a
  request implies a write, decline and explain this is a read-only trace tool.
- **Never** weaken any connection/target restrictions your environment imposes (allowlists,
  blocked hosts). If a target is disallowed, stop and say so — don't route around it.
- **Bound time and rows** on every query; large `Ens.*` tables without a time filter will be
  slow or time out.
- **Don't persist credentials** in the repo or in long-lived files; pass them per call and
  clean up any temp credential file at session end.
- **Show every query and its result** to the user and confirm correctness before building on it
  (`00`).
