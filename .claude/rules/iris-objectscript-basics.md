# ObjectScript Basics
**Technology Scope: ObjectScript / InterSystems IRIS only.** These rules apply when working on `src/SessionAgent/` ObjectScript classes. They do NOT apply to Angular/TypeScript frontend work.

## VSCode Auto-Sync Workflow (this project)

`.vscode/settings.json` sets `objectscript.conn.active: true` and `objectscript.syncLocalChanges: "all"` against the `local` server (`localhost:52773`, namespace `HSCUSTOM`). The InterSystems ObjectScript extension auto-syncs every saved `.cls` / `.mac` / `.inc` file from this workspace to the IRIS server on save.

**Implication for dev agents and tool use:**

- **DO NOT call `mcp__iris-dev-mcp__iris_doc_load`** for files inside `src/SessionAgent/`. Edit/Write to the local file is enough — auto-sync pushes it.
- **DO call `mcp__iris-dev-mcp__iris_doc_compile`** after a meaningful edit to verify clean compile and surface error text. Auto-sync pushes the source but does not return compile errors to the agent.
- **DO call `mcp__iris-dev-mcp__iris_execute_classmethod`** for one-shot sanity calls (preferred over `iris_execute_command` for typed input/output and shorter responses).
- **Prefer high-level dedicated MCPs** over `iris_execute_command` / generic command execution where one exists:
  - `mcp__iris-admin-mcp__iris_role_*`, `iris_user_*`, `iris_resource_*` for RBAC operations
  - `mcp__iris-ops-mcp__iris_task_*` for Task Manager entries
  - `mcp__iris-ops-mcp__iris_audit_events` for audit log queries
  - `mcp__iris-dev-mcp__iris_sql_execute` for SQL probes
  - `mcp__iris-dev-mcp__iris_macro_info` for macro lookups
  - `mcp__iris-dev-mcp__iris_doc_search` / `iris_doc_get` for class introspection
  - Use `iris_execute_command` only for genuine one-off ObjectScript snippets that no dedicated MCP covers.
- **Bulk export rule (from user's global CLAUDE.md) still applies** — when running a bulk `iris_doc_export`, toggle `objectscript.conn.active: false` first to prevent the extension from fighting the export, then restore.

## Basics  
   - "namespace" = IRIS namespace  
   - "package" prefix = class prefix  
   - Do not create classes or properties with '%' or '_'  
   - Class parameter names must not contain underscore ('_') characters - use camel case (e.g., "MyParameter") or all caps without underscores (e.g., "MYPARAM" or "MYPARAMETER") instead
   - Method names must not contain underscore ('_') characters; use camel case (e.g., `TestCoreScenario45UNIT001`) and keep any formal test IDs in comments or assertion messages instead of the method name
   - Compile classes using the compile_objectscript_class or compile_objectscript_package MCP tool.

## Abstract Methods in ObjectScript
   - **CRITICAL**: Despite documentation suggesting otherwise, abstract methods MUST have code blocks with curly braces {} - they cannot be truly empty or the class will not compile
   - **CRITICAL**: Abstract methods must return an appropriate value based on their signature:
     - Methods returning objects: Use `Quit $$$NULLOREF` or `Quit ""`
     - Methods returning %Status: Use `Quit $$$OK`
     - Methods returning %String: Use `Quit ""`
     - Methods returning %Boolean: Use `Quit 0`
     - Methods returning %Numeric: Use `Quit 0`
   - Abstract methods are marked with `[ Abstract ]` keyword after the method signature
   - While documentation states abstract methods have no executable code, the compiler requires implementation bodies that return values
   - Subclasses override abstract methods with actual implementations
   - Example pattern:
     ```objectscript
     Method MyAbstractMethod() As %String [ Abstract ]
     {
         Quit ""
     }
     
     Method ProcessData() As %Status [ Abstract ]
     {
         Quit $$$OK
     }
     
     Method CreateObject() As MyClass [ Abstract ]
     {
         Quit $$$NULLOREF
     }
     ```
   - Both instance methods and class methods can be abstract
   - Classes containing abstract methods cannot be instantiated directly
   - Concrete subclasses must implement all inherited abstract methods

## While writting ObjectScript  
   - Return a %Status from methods that produce no return value.  
   - First line: Set tSC = $$$OK  
   - Last line: Quit tSC  
   - Use try/catch for error trapping  
   - Use doc comment banners with HTML/DocBook markup
   - CRITICAL: ObjectScript macro syntax must use triple dollar signs ($$$) not double ($$)
   - If encountering multiple $$ syntax errors in a file, use write_to_file for full replacement rather than multiple replace_in_file operations
   - %DynamicObject properties witih an underscore in the name must have qoutation marks around them because underscore is the concatination operator: Set request."max_results" = 5
   - CRITICAL: To produce JSON null in %DynamicObject, use `%Set("key", "", "null")` — the third parameter is the type hint. Using `%Set("key", "null", "null")` produces the string `"null"` instead.

## IRIS SQL Case Sensitivity
   - IRIS SQL is case-insensitive by default for string comparisons
   - All SELECT and WHERE clauses on string columns must wrap with `%EXACT()` to preserve case in returned values and ensure case-sensitive matching
   - Example: `SELECT %EXACT(DocId) FROM ... WHERE %EXACT(FieldValue) = 'order-001'`
   - Without `%EXACT()`, queries may return incorrect results due to case folding (e.g., "Order-001" matching "order-001")
   - This applies to all IRIS SQL queries, including embedded SQL (`&sql()`) and dynamic SQL via `%SQL.Statement`

## %EXACT() in SELECT Changes Column Aliases (Story 13.3 / Epic 13 retro AI-1)

**Rule.** When `%EXACT(col)` appears in the **SELECT column list** (not just in WHERE), IRIS renames the output column — `tRS.%Get("ID")` returns `""` because the column is now aliased as `%EXACT(ID)`, not `ID`. Use **positional `tRS.%GetData(n)`** access for any result set built with `%EXACT()` in the SELECT list.

**Originating incident.** Story 13.3 dev used `SELECT %EXACT(ID), %EXACT(ClassName), Enabled, PoolSize, %EXACT(Comment) FROM Ens_Config.Item WHERE ...`. `tRS.%Get("ID")` returned `""` in every row. Fix: switched to `tRS.%GetData(1)`, `tRS.%GetData(2)`, etc. — positional access is alias-independent.

**How to apply.**
- In WHERE: `%EXACT(col) = ?` is fine and required for case-sensitive comparison. No column alias created here.
- In SELECT list: avoid `%EXACT(col)` when you need to read the result by name. Two safe patterns:
  1. **Positional read:** `SET tVal = tRS.%GetData(n)` — works regardless of aliases.
  2. **Explicit alias:** `SELECT %EXACT(col) AS col_name FROM ...` then `tRS.%Get("col_name")` — the explicit alias overrides the function-generated alias.
- Reviewer enforcement: any code that calls `%Get("col")` after a SELECT that wraps `col` in `%EXACT()` without an explicit alias is a HIGH-severity finding (predicted-bug shape: silent empty-string return masks data).

## QUIT Statement Restrictions in Try/Catch Blocks
   - **CRITICAL**: QUIT with arguments is NOT allowed within Try/Catch blocks (ERROR #1043)
   - The $QUIT special variable determines if argumented QUIT is required (1) or not (0)
   - **Solutions for methods that must return values:**
     1. Initialize return variable before Try block: `Set result = ""`
     2. Set return value within Try block: `Set result = object`
     3. Use argumentless QUIT in Try/Catch: `Quit` (no arguments)
     4. Return the variable after Try/Catch: `Quit result`
   - **Alternative**: Use RETURN statement instead of QUIT (different semantics)
   - **Pattern Example:**
     ```objectscript
     Method CreateProduct() As Product
     {
         Set result = ""  // Initialize return variable
         Try {
             Set result = ##class(Product).%New()
             // More logic...
             Quit  // Argumentless QUIT
         }
         Catch ex {
             // Error handling...
             Quit  // Argumentless QUIT
         }
         Quit result  // Return the result after Try/Catch
     }
     ```
   - Multiple QUIT statements in a method are allowed, but consistency in argument usage is important
   - This restriction ensures proper exception handling and control flow in error scenarios

## When editing files 
   - When replace_in_file fails to resolve typos or syntax errors, use write_to_file for full file replacement
   - Use full file replacement (write_to_file) when multiple syntax corrections are needed to avoid cascading errors
   - CRITICAL: Always use write_to_file for $ vs $$ macro syntax fixes - never use replace_in_file for these issues

## InterSystems Libraries  
   - Use built-in IRIS classes/packages for performance and maintainability.
   - InterSystems Librarys have packages that begin with %, and also include: HS, Ens, and EnsLib amoung others.

## Naming Conventions  
   - Parameters have "p" prefix (e.g., pItem).  
   - Local variables have "t" prefix (e.g., tIndex).  
   - Class properties are capitalized with no prefix.
   - Class Parameters must be accessed using the # character (e.g., ..#PARAMETERNAME).

## Comments  
   - Semicolon for single-line comments  
   - Class/Method banners must have HTML & DocBook markup
   - Use `///` for method-level doc comments in class definitions; avoid `//`, which is not treated as a comment in ObjectScript classes and can break parsing
   - Reserve `/* ... */` block comments for safe top-of-file banners; avoid placing them immediately around method signatures, as mismatched or misplaced blocks can trigger ERROR #5559 parse failures

## Indentation and Formatting
   - Always indent ObjectScript commands within methods by at least 1 space or tab to avoid compile errors.
   - Ensure each code block is consistently spaced to maintain readability and proper compilation in IRIS.
   - When editing ObjectScript class files, prefer reading the entire file then writing the full content back, rather than partial search-replace, to maintain indentation integrity.

## Python Integration
   - Read documention/IRIS_Embedded_Python_Complete_Manual.md at the start of any session that intends to use Python, if it doesn't exist use Perplexity to search for the latest embedded python documentation.
   - Prefer native ObjectScript for IRIS operations (globals, persistence, SQL, transactions)
   - Use embedded Python only for external library integration (OpenAI, NumPy, ML libraries, document processing)
   - Follow embedded Python patterns: %SYS.Python.Import() for libraries, [Language = python] for methods
   - Use 'import iris' bridge when calling IRIS from Python code
   - Maintain backward compatibility with mock implementations as fallbacks
   - CRITICAL: ##class(%SYS.Python).IsAvailable() does NOT exist. To check for Python, you must first attempt to load it by importing a library (e.g., `do ##class(%SYS.Python).Import("sys")`), and *then* check the status with `##class(%SYS.Python).GetPythonVersion()`. The `GetPythonVersion()` method only detects if Python has *already been loaded*; it does not load Python itself.

## Python Integration Distribution Rules (added 2026-04-18, Story 13.0 from Epic 12 retro AI #6)

**Release gate.** These rules govern what ships to adopters. They are
enforced at code review time: any PR that violates them is blocked until
the violation is corrected. See **PRD NFR-M9 — Python-Optional Compilation**
for the PRD-level invariant these rules implement.

Cited reason: Epic 12 retrospective Action Items #6–#9 + NFR-M9
(2026-04-17). Story 12.4 (Python JSRuntime backend) deferral exposed that
a `[Language = python]` method in any shipped `.cls` file is a latent
install-break on every IRIS instance without embedded Python — an entire
class of customers (those whose IRIS build excludes Python, or whose
deploy pipeline has not configured `PythonRuntimeLibrary`) would see
`zpm install iris-couch` fail at compile time. This rule prevents that
ship-breaking pattern from re-entering the codebase when Story 12.4
resumes or when any future story is tempted to reach for
`[Language = python]`.

The four invariants:

1. **Zero `[Language = python]` methods in any shipped `.cls` file under
   `src/IRISCouch/`.** A reviewer sees this line and the PR is blocked.
   If a story genuinely needs Python, the story itself must be restructured
   to host the Python code as a ZPM-distributed resource (invariant 2), not
   embedded in a class. This applies to shipped classes only; debug /
   probe / scratch classes in an ignored path may temporarily use
   `[Language = python]` during local exploration, but must never be
   committed.

2. **Python bridges ship as ZPM `<FileCopy>` resources, never embedded in
   a class.** If Epic 12+ introduces a Python bridge (for example,
   `jsruntime.py` for a Python-backed JSRuntime implementation), the
   bridge is a standalone `.py` file under the ZPM module tree, declared
   in `module.xml` as a `<FileCopy>` resource copied to a known install
   location at package install time. The ObjectScript side calls into the
   bridge via `$ZF(-100)` or `%SYS.Python.Import` against the installed
   file path; the bridge's source does not live inside a `.cls`.

3. **`irispip install <package>` is documented as an operator-executed
   prerequisite, never invoked from a ZPM install hook.** If a Python
   bridge depends on third-party packages (e.g. `requests`, `pyjwt`),
   those packages are documented in the README / install guide as
   operator-run `irispip install` commands the operator performs once
   per IRIS instance. A ZPM install hook that attempts
   `do ##class(%SYS.Python).Run("irispip install ...")` is forbidden —
   it breaks on Python-less IRIS, it requires network access at install
   time on air-gapped hosts, and it silently upgrades packages the
   operator did not consent to install.

4. **`zpm install iris-couch` must succeed on an IRIS instance regardless
   of embedded Python availability.** Enforced by a release-gate CI job
   that runs `zpm install iris-couch` on a Python-less IRIS Community
   image (when that CI image becomes available — tracked in
   `deferred-work.md` under the Story 12.4-resumption prerequisites).
   Until the CI image lands, manual verification on a Python-less IRIS
   instance is the release gate.

If a future story violates any of these invariants, the reviewer's
checklist item is: "Does this PR introduce `[Language = python]` to a
shipped class? Does it embed a `.py` bridge? Does it invoke `irispip` from
a ZPM hook?" Any yes blocks the PR.

## Namespace Switching in REST Handlers
   - **CRITICAL**: Never use `New $NAMESPACE` in REST dispatch handler classes (classes extending `%Atelier.REST` or called from Dispatch UrlMap routes)
   - `New $NAMESPACE` + `Set $NAMESPACE = "%SYS"` makes classes from the original namespace (e.g., `ExecuteMCPv2.Utils`) invisible in catch blocks, causing `<CLASS DOES NOT EXIST>` crashes on any error path
   - **Safe pattern**: Use explicit save/restore with a local variable:
     ```objectscript
     Set tOrigNS = $NAMESPACE
     Set $NAMESPACE = "%SYS"
     ; ... do work in %SYS ...
     Set $NAMESPACE = tOrigNS
     ; ... now safe to call ExecuteMCPv2.Utils, RenderResponseBody, etc.
     ```
   - In catch blocks, ALWAYS restore namespace as the first line: `Set $NAMESPACE = tOrigNS`
   - Do all input validation (Utils.ValidateRequired, Utils.ReadRequestBody) BEFORE switching to %SYS
   - After each system class call (Config.*, Security.*), restore namespace before error handling
   - `Config.Namespaces`, `Config.Databases`, `Config.Map*` classes only exist in %SYS — they require the namespace switch
   - `Security.Users`, `Security.Roles`, `Security.Resources`, `Security.Applications`, `Security.SSLConfigs` also require %SYS
   - For listing operations, prefer `##class(%ResultSet).%New("Config.Namespaces:List")` named queries over non-existent class methods like `Config.Namespaces.NamespaceList()`

## `Parameter PAGENAME` MPP5646 Trap (EnsPortal Subclasses)

**Rule.** Any class extending `EnsPortal.Template.standardPage` (or any
sibling that triggers `$$$Text(..#PAGENAME)` codegen at compile time)
MUST set `Parameter PAGENAME = ""` and override
`Method %OnGetPageName() As %String { Quit "..." }` at runtime, rather
than setting `Parameter PAGENAME = "Some Page Name"` directly.

**Why.** When `Parameter PAGENAME` carries a non-empty value, the
`EnsPortal.Template.standardPage` superclass codegen path emits
`$$$Text(..#PAGENAME)` at compile time — the `$$$Text` macro writes
into `^IRIS.Msg("Ensemble", ...)` to register the page name as a
localizable string. That global node is **ENSLIB-privileged** at the
storage layer; when the build context (the user / process invoking
`compile_objectscript_class`, or the IPM `zpm load` lifecycle) does
NOT hold the ENSLIB write privilege, the codegen path raises
`<PROTECT> ^IRIS.Msg` and the compile fails with the cryptic
`MPP5646: ` prefix in the error envelope. The runtime
`%OnGetPageName()` override sidesteps the codegen path entirely —
the page name is resolved at request-handling time via the
already-privileged Ensemble portal context, not at compile time via
the build context's privilege set.

**Originating finding.** Story 6.4 fix-3 chrome refactor — the
`SessionAgent.UI.Portal.AgentConfigForm` Zen page initially set
`Parameter PAGENAME = "Configure Session Inspection Agent"` and
compile-failed with `MPP5646 <PROTECT> ^IRIS.Msg` under the dev
context. ~20 minutes were lost discovering the workaround during the
manual-test fix bundle (commit `2193887`). Codified here so the next
EnsPortal subclass author sees the rule before re-discovering it.

**The pattern.** Use this canonical form on every EnsPortal subclass:

```objectscript
Class SessionAgent.UI.Portal.MyForm Extends EnsPortal.Template.standardPage
{

/// MPP5646 workaround: leave PAGENAME blank to suppress the
/// $$$Text(..#PAGENAME) codegen path; resolve the page name at
/// runtime via %OnGetPageName() instead.
Parameter PAGENAME = "";

Method %OnGetPageName() As %String
{
    Quit "My Form Display Name"
}

}
```

**Reviewer enforcement.** Any new class extending
`EnsPortal.Template.standardPage` (or any sibling triggering the same
codegen) whose source sets `Parameter PAGENAME` to a non-empty literal
is a HIGH-severity finding per Rule 8 (predicted-bug shape: compile
failure under non-ENSLIB-privileged build context). Fix-now in the
same story.

## CouchDB Mango Selector Semantics
   - When a field referenced by a selector is **missing** from a document, CouchDB applies these rules:
     - `$ne` and `$nin` return **true** for missing fields — a missing field is "not equal" to any value
     - All other comparison operators (`$eq`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`) return **false** for missing fields
     - `$exists: false` returns **true** for missing fields; `$exists: true` returns **false**
   - This means queries like `{"status": {"$ne": "deleted"}}` will match documents that have no "status" field at all
   - The IRISCouch MangoSelector implementation must preserve these semantics in `EvalOperator` for correct CouchDB compatibility

## Storage Sections
   - IMPORTANT: Storage sections of ObjectScript classes should NEVER be edited or added.  The compiler will add/maintain these sections of the class based on properties declared in the class and superclasses.

## ObjectScript Compiler
   - Classes should be compiled using the compile_objectscript_class or compile_objectscript_package mcp tool.

## Ensemble Architecture Guidance
- When creating Business Services or Business Operations in Ensemble, ensure method signatures exactly match the InterSystems-defined definitions, for example:
  • OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject, ByRef pHint As %String).
  • OnMessage(pRequest As MyRequestClass, Output pResponse As MyResponseClass).
- Use custom classes extending Ens.Request/Ens.Response to handle data exchange between services and operations.
- Verify the proper IRIS adapter is specified on each Business Service/Operation (e.g., EnsLib.File.InboundAdapter, EnsLib.File.OutboundAdapter).
- Carefully implement synchronous vs. asynchronous flows depending on production requirements.
- Always confirm that the method arguments match the correct data types expected by Ensemble, to avoid signature errors.
- Thoroughly review the relevant built-in Ensemble classes (Ens.BusinessService, Ens.BusinessProcess, Ens.BusinessOperation) for method signatures and best practices before extending them.

## IRIS MCP Debugging Capabilities
- I have DIRECT access to IRIS through MCP server tools for debugging and execution
- Available tools: execute_command, execute_classmethod, get_global, set_global, execute_sql
- Can start/stop IRIS Interoperability Productions using interoperability_production_* tools
- **CRITICAL**: Always specify namespace parameter when using IRIS MCP tools
- **CRITICAL**: execute_classmethod only works with CLASS METHODS (marked ClassMethod), NOT instance methods
- For instance methods, build a classmethod that instances the class and then calls the instance method.
- **CRITICAL**: Do NOT use execute_command for debugging/testing - create unit tests or temporary debug class methods instead
- Self-debugging pattern: Initialize ^ClineDebug = "", capture steps with SET ^ClineDebug = ^ClineDebug _ "step info; ", inspect with get_global
- Can execute ObjectScript commands directly without user intervention
- Can call class methods with parameters and inspect results immediately
- Can run SQL queries directly on IRIS tables for validation
- Use globals for debugging state capture and inspection between method calls
- Always clean up debug globals after debugging sessions
- Namespace specification essential for accessing classes and data

## IRIS Environment Details
- **IRIS is NOT running in Docker** - do not use docker commands
- **Testing**: Use MCP tools (iris-execute-mcp) for execution
- **Direct IRIS access**: Available through MCP servers for real-time testing and debugging

## IRIS Library Source
- Always read `irislib/` source code for any IRIS system class before using it. Three bugs in Epic 7 (`$System.Security.Login()`, `$System.Encryption.PBKDF2()`, `$System.Encryption.HMACSHA()`) were caused by not reading the actual source. Use `irislib/%SYSTEM/Security.cls`, `irislib/%SYSTEM/Encryption.cls`, etc.
- `$System.Security.Login()` switches process context -- never use for credential validation; use `Security.Users.CheckPassword()` instead
- `$System.Encryption.PBKDF2()` exists natively -- do not reimplement crypto primitives
- IRIS `$System.Encryption.HMACSHA()` uses bit sizes (160, 256, 384, 512), not algorithm version numbers

## Pattern Replication Completeness
   - When replicating a multi-step pattern from an existing method (e.g., adding _users or _replicator hooks to a new method), enumerate ALL steps from the reference method and verify each one is present in the new code
   - Do not copy-paste and assume correctness — treat it as a checklist: list every step (MangoIndex update, Winners projection, _users sync, _replicator sync, changes feed, etc.) and confirm each is either included or explicitly not applicable
   - Common miss: forgetting MangoIndex re-indexing after body modification, or omitting NFR-R1 corruption detection in new write paths

## Transaction Side Effects
   - **CRITICAL**: Never spawn background jobs (JOB command), signal events ($System.Event.Signal), or perform I/O with external systems inside a TSTART/TCOMMIT block
   - Side effects must happen AFTER TCOMMIT — the background job could start reading data before it is committed
   - Pattern: save data needed for the side effect in a local variable during the transaction, then execute the side effect after TCOMMIT

## %DynamicObject Iterator Safety
   - **CRITICAL**: Never call %Set() or %Remove() on a %DynamicObject while iterating it with %GetIterator()
   - Collect keys into a $ListBuild list first, then iterate the list separately to modify the object
   - This applies to attachment processing, Mango selector evaluation, and any code that transforms JSON objects in-place

## $Char(0) sentinel — grep target for `%String` reads with SQL UPDATE write paths

**Rule.** Any code reading a `%String` column whose write path includes SQL
UPDATE (e.g., a Zen form save handler that emits `UPDATE … SET col = ''`,
or any direct `%SQL.Statement` call against the table) **must** inline-
normalize `$Char(0) → ""` at the read site, OR delegate the read to a
centralized helper that performs the normalization. This is a *grep-target*
invariant — every `..Config*.*` / `..<TableProperty>` read is a candidate
site, and reviewers grep for the pattern at story sign-off.

**Why.** IRIS's legacy `%String` representation uses `$Char(0)` (one byte,
ASCII NUL) as the in-table null sentinel for columns whose value was set
to `""` via a SQL UPDATE statement. The OREF-graph getter (`obj.Property`)
returns `$Char(0)` verbatim for such rows, but downstream code typically
checks `If tValue '= ""` — which is **TRUE for `$Char(0)`** because
`$Char(0)` is a non-empty 1-character string. The result: a
defaulting-on-empty fallback (e.g., "use the canonical default endpoint
URL when EndpointUrl is blank") is silently bypassed, and the empty-string
sentinel is forwarded to downstream APIs that interpret it as "look up
this credential" or "GET this URL" — producing baffling failures whose
root cause is invisible at the call site.

**Originating incidents.**
- **Story 4.0 codification (Epic 3 manual-test Bug-1, 2026-05-03)** —
  `Tool.Inspection.SessionSummary` and one sibling read `..ConfigAgent.X`
  for tool-config and shipped without the normalization; user-led
  chat-panel manual-test surfaced the failure mode.
- **Epic 5 manual-test Bug-1 (2026-05-06)** — `..ConfigAgent.EndpointUrl`
  read in `GetEndpointUrl()` of all 4 LLM providers needed the same
  normalization. Applied in Stories 5.1 / 5.2 / 5.3.
- **Story 6.0 sweep (2026-05-06)** — extended the codification beyond
  endpoint URL to credential-resolve sites:
  `..ConfigAgent.EnvVarName` + `..ConfigAgent.CredentialName` reads in
  `CallMessages` of all 4 providers (`SessionAgent.LLM.OpenAIProvider`,
  `AnthropicProvider`, `GeminiProvider`, `OpenAICompatProvider`) were
  unnormalized. Symptom: an operator who clears `EnvVarName` via the
  Zen form (or via `UPDATE Config_Agent SET EnvVarName = ''`) gets
  `$SYSTEM.Util.GetEnviron($Char(0))` invoked at runtime — undefined
  behavior; the credential ladder's rung-1 path fires against a
  bogus env-var name instead of being skipped. Same for `CredentialName`
  → `Ens.Config.Credentials.%ExistsId($Char(0))` → spurious credential
  lookup. Fixed in Story 6.0 Task 2.

**The pattern.** Use this canonical inline form at every read site (or
delegate to a helper that wraps it):

```objectscript
Set tStored = ""
If $IsObject(..ConfigAgent) Set tStored = ..ConfigAgent.<Property>
If tStored = $Char(0) Set tStored = ""
; ... downstream check `If tStored '= ""` now behaves correctly ...
```

**Grep-target invariant.** When a story modifies any code that reads a
`%String` property of a configuration object whose persistence layer is
mutated by SQL UPDATE (Config.Agent, Config.Search, future Config.X),
the dev MUST grep:

```
grep -rn "\.\.\.Config[A-Za-z]*\." src/SessionAgent/
```

…and confirm every match falls into one of:
1. **Already normalized** — the read site has the `If tStored = $Char(0) Set tStored = ""` line below it.
2. **Read into a comparison that doesn't care about empty-vs-NUL** — e.g., `If ..ConfigAgent.Provider = "openai"` — `$Char(0)` is not `"openai"`, so the comparison fires the same way for empty-string rows. (Documented exception; still safer to normalize so the variable can be reused.)
3. **Read into a method call that itself performs the normalization** — e.g., `Util.EnvSecret.Resolve(envVar, credName)` after Story 6.0 hardens the guard.

**Reviewer enforcement.** Any unnormalized `..Config*.*` read in a story diff
that doesn't fall into one of those three categories is a HIGH-severity
finding per Rule 8 (predicted-bug shape: drift between operator's empty-
string intent and the runtime's `$Char(0)`-backed read). Fix-now in the
same story.

## Response Utility Consistency
   - Always use `Response.JSON()` or `Response.JSONStatus(statusCode, obj)` for success responses — never write to %response.Write() directly or set ContentType/Status manually
   - This ensures consistent Content-Type headers, character encoding, and status codes across all endpoints

## Write Status Checking
   - Every `Storage.*` write method returns %Status — always check the return with `$$$ISERR(tSC)` and handle the error
   - Do not silently discard write failures, especially for checkpoint writes, document writes, and attachment stores
   - Pattern: `Set tSC = ##class(Storage.X).Write(...) If $$$ISERR(tSC) { ... handle ... }`

## Timestamp and Encoding Standards
   - ISO-8601 UTC timestamps: Use `$Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"` to produce `2026-04-13T10:30:45Z` format
   - **CRITICAL**: Use `$ZTimeStamp` (UTC) not `$Horolog` (local server time) when appending the "Z" suffix -- "Z" means UTC, and `$Horolog` returns local time which makes the timestamp semantically incorrect on non-UTC servers
   - Never use raw `$ZDateTime` which produces space-separated format
   - Base64 encoding: Use a single `$System.Encryption.Base64Encode(stream.Read(3600000))` call — never concatenate multiple Base64-encoded chunks, as interior padding characters produce invalid output
   - When round-trip correctness matters (attachments, checksums), add a unit test that encodes and decodes to verify

## Security.Events Pre-Registration for Audit
   - **CRITICAL**: `$System.Security.Audit("Source", "Type", "Name", ...)` silently returns 0 (failure) if the Source/Type/Name triple has not been pre-registered via `Security.Events.Create()` in the `%SYS` namespace
   - There is no error, no exception, and no log entry -- the audit event is simply lost
   - Always call an `EnsureEvents()` setup method during installation or upgrade to register all audit event types before any code attempts to emit them
   - Pattern reference: `IRISCouch.Audit.Emit.EnsureEvents()` -- switches to `%SYS`, iterates all event types, calls `Security.Events.Create()` for any that do not yet exist, then restores the original namespace
   - `Security.Events.Exists("Source", "Type", "Name")` can be used to check registration before creating
   - The `Installer.Install()` method must call `EnsureEvents()` so that audit events work immediately after deployment

## SaveDeleted Hook Ordering
   - In `DocumentEngine.SaveDeleted()`, system database hooks (_users, _replicator) that need document body must execute BEFORE projection updates (Winners.Upsert, MangoIndex.Delete) that clear or overwrite body data
   - The Winners projection sets body to "" for deleted docs — any hook running after that cannot read the original document content

## Process-Private Globals (`^||`) and OREF Storage
   - **CRITICAL**: Process-private globals (`^||...`) do **NOT** preserve `%RegisteredObject` / `%Persistent` OREFs across access. `Set ^||X = oref` then `Write $IsObject(^||X)` returns `0` — the OREF round-trips as the literal string `"oref@<class>"` because globals are scalar storage and OREF assignment to a global node implicitly stringifies the reference.
   - For test or back-channel state that needs to survive a `^||` round-trip, store the **class name** plus a `%DynamicObject.%ToJSON()` config blob and **re-instantiate** the object on read. Pattern:
     ```objectscript
     ; write
     Set ^||MyState("class") = "MyApp.SomeProvider"
     Set ^||MyState("config") = tConfigObj.%ToJSON()

     ; read
     Set tClass = $Get(^||MyState("class"))
     Set tCfg = ##class(%DynamicObject).%FromJSON($Get(^||MyState("config")))
     Set tInst = $ClassMethod(tClass, "%New")
     Do tInst.%InstallOverrideConfig(tCfg.%ToJSON())   ; or whatever rehydration the class exposes
     ```
   - For in-process singleton-style override holders (e.g., a test mock that an instantiating site reads back), use a `%RegisteredObject` singleton class with a class-level OREF property — OREF identity is preserved within the process via the dictionary, not via globals. See `SessionAgent.Agent.ProviderOverride` for the canonical pattern.
   - **Process-private global subscript naming**: subscripts (the parenthesized keys after `^||GlobalName`) must follow ObjectScript identifier rules — letters, digits, `%`, NO hyphens. The `-` character is the concatenation operator in ObjectScript and a subscript like `^||SessionAgentTest2-11Ids` parses as `^||SessionAgentTest2 - 11Ids` (subtraction expression), causing `<SYNTAX>` errors at compile/parse time. Use camelCase (`SessionAgentTest211Ids`) or snake_case (`session_agent_test_211_ids`) for multi-word subscripts; never embed hyphens.
   - **Originating findings**: Story 2.9 first surfaced the OREF non-preservation behavior empirically (commit `f84fd07` — `^||TestProviderHolder` round-tripped as a string instead of an OREF). Story 2.11 first surfaced the subscript naming requirement (`^||SessionAgentTest2-11Ids` failed at compile and was renamed to `^||SessionAgentTest211Ids` per `src/SessionAgent/Test/InspectionToolTest.cls`). Both rules codified here in Story 3.0 to prevent re-discovery.

## HTTP Integration Test Requirements
   - Every new handler method needs an HTTP integration test that verifies: (1) correct HTTP status code, (2) Content-Type header is application/json, (3) response body structure matches CouchDB spec
   - Format/encoding tests should include round-trip verification (encode then decode and compare)

## Subagent Briefing Requirements (ObjectScript stories only)
- All **ObjectScript** subagent prompts MUST include references to: (1) CouchDB source at `sources/couchdb/` for protocol/algorithm details, (2) IRIS library source at `irislib/` for API behavior verification
- For **Angular/TypeScript** stories (Epic 10+), include references to: (1) Chrome DevTools MCP for browser-based UI verification, (2) the IRISCouch REST API endpoints the UI consumes

## Research and Knowledge Resources
- Use Perplexity MCP as a reference source when uncertain about ObjectScript syntax, problem-solving approaches, or specification details
- Always research with Perplexity MCP before attempting solutions when knowledge is incomplete
- Consult Perplexity MCP for best practices, error resolution, and technical implementation guidance in ObjectScript and IRIS

## ObjectScript Collection and Object Handling
- CRITICAL: ObjectScript's $listbuild() and $list() functions serialize objects to strings, losing object identity
- When storing objects temporarily, use individual variables (Set obj1 = ..., Set obj2 = ...) rather than lists
- For unit tests, avoid $listbuild() when testing object properties - use direct object assignment instead
- Collection errors like "<INVALID OREF>" often indicate attempts to access serialized objects as if they were still objects
- When debugging collection issues, check for batch processing logic that may be accessing invalid object references

## Debugging and Error Resolution Patterns
- For "<INVALID OREF>" errors in collections: Look for object serialization issues or invalid object references in batch processing code
- For unit test failures with $ISOBJECT(): Check if objects are being stored in lists and losing object identity
- When multiple $ vs $$ syntax errors occur: Always use write_to_file for full replacement rather than multiple replace_in_file operations
- For complex ObjectScript debugging: Simplify architecture by eliminating unnecessary complexity (batch processing, complex collections) in favor of simple, reliable patterns
- Architecture principle: Choose reliability and maintainability over performance optimization when debugging complex issues

## IRIS Vector Search and Embedding Operations
- CRITICAL: Vector operations require exact datatype compatibility between query and stored embeddings
- Common SQL Error -259: "Cannot perform vector operation on vectors of different datatypes" indicates datatype mismatch
- SOLUTION: Use IRIS native embedding generation for query embeddings to match stored embedding types
- Pattern: Create temporary DocumentChunk with same MODEL parameter, use IRIS auto-embedding generation, extract result
- Vector search diagnostic approach: Create comprehensive diagnostic methods to isolate SQL query vs embedding generation issues
- Always use %Library.Embedding datatype for IRIS vector operations, not %Vector datatype
- Test vector operations with simple queries first, then complex semantic searches
- Realistic similarity scores for vector search: High relevance (0.6-0.8), Medium (0.3-0.6), Low (0.2-0.4)

##ObjectScript Debugging Instructions

ObjectScript can be debugged using globals by adding statements to the class:

Add the the following statement to your class file to clear the debug global: SET ^ClineDebug = ""
Each line in your class file where you want to add a debug statement use: SET ^ClineDebug = ^ClineDebug_"The information you want included; "
Execute the portion of the system you are testing, which will collect the debug information in ^ClineDebug
To read the debug information that has been captured while running the code, use the get_global tool to retrieve ^ClineDebug
Other things to keep in mind:

The excute_command tool can only be used with very simple commands. Instead of creating a complex commands, create a helper class method and use the execute_classmethod tool
To debug instance methods, create a temporary class method that calls the instance method. You can use ^ClineDebug within the class method if desired.
Make sure you clean up any temporary classes after you are finished with them.

## LLM Prompt Construction (Story 4.0 / Epic 3 retro AI-15)

**Anti-pattern: hardcoded enumeration of runtime-provided state in system prompts.**
When an ObjectScript-emitted system prompt could enumerate runtime state — tool
names, available providers, configured agents, registered transformations,
loaded productions, anything else assembled at process startup — **do NOT**
hardcode that enumeration in the prompt template. Instead, write a *directive*
that points the LLM at the runtime-provided typed list it already receives in
the same turn (the OpenAI/Anthropic `tools` array, the function-calling
manifest, etc.):

> *"Use only the tools in the list provided in this turn. Do not invent tool
> names. Do not describe capabilities you do not actually have."*

Reserve enumeration for **genuinely-static taxonomies** — protocol-level
keywords (`HL7`, `CSV`, `JSON`), enum members defined by the IRIS API, fixed
escalation tiers — values that the runtime cannot drift from in the field.

**Originating incident.** [`SessionAgent.Config.AgentDefaults:GetSystemPrompt`](../../src/SessionAgent/Config/AgentDefaults.cls)
shipped a hardcoded 13-tool enumeration in its system-prompt template through
Stories 2.4 → 3.8. Only 3 tools were actually loaded into the live tool
registry. Operators (and the agent itself) had no way to detect the drift —
the LLM happily described the 10 phantom capabilities and refused to fall
back to "I can only…" wording. Nine stories of capability hallucination shipped
before manual testing surfaced it; commit `768be17` deleted the enumeration
and replaced it with the directive form above. The subsequent retrospective
codified this anti-pattern as Epic 3 AI-15 because the same shape will
re-appear the moment Epic 4 / Epic 5 / Epic 6 add new tools, providers, or
agent presets.

**How to apply.**

- At spec-writing time: any story authoring or modifying a system-prompt
  template MUST audit it for enumeration-of-runtime-state. If found, rewrite
  to directive form before the dev agent gets the spec.
- At review time: a system-prompt diff that contains a hardcoded list of
  things the runtime separately ships in the request payload (tools,
  providers, namespaces, etc.) is a HIGH-severity finding per Rule 8 —
  predicted-bug shape (drift will silently ship). Block the PR.
- At runtime / smoke-test time: when exercising the chat path against a
  real provider, the empirical battery (Rule 12) must include a turn that
  asks the agent to enumerate its capabilities. If the agent claims a
  capability the runtime tool registry does not actually load, the prompt
  has drifted — file as a hot fix.

## SQL Injection Defense in ObjectScript (Story 13.0 / Epic 12 retro AI-1)

**Rule.** Any tool or method that accepts a class name, item name, or other
operator-supplied string and inserts it into an IRIS SQL query MUST apply
all four defense layers below. All four must be present before the story ships.

**The 4 layers:**

1. **LLM-prompt-level type hint.** The `GetInputSchema()` `description` field
   for the parameter must name the expected format explicitly:
   > *"Pass a full package-qualified class name (e.g. 'SessionAgent.Sample.BP.OrderRouter').
   > Pass the class name only — do not include method names."*
   This primes the LLM to supply correctly-shaped input before it reaches the server.

2. **Server-side `$Match` regex validation.** Before any SQL is prepared or
   executed, validate the input with:
   ```objectscript
   If '$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$") {
       Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid class_name format"}]}
       Quit
   }
   ```
   This blocks malformed input (SQL fragment injection attempts, empty strings,
   shell metacharacters) with a structured error before SQL is ever touched.

3. **Parameterized SQL (`?` placeholder).** The validated value MUST be bound
   as a `%SQL.Statement.%Execute(arg)` parameter — NEVER concatenated into the
   SQL text string. Even after regex validation, concatenation is forbidden:
   ```objectscript
   ; WRONG — never do this even after regex validation:
   Set tSql = "SELECT ... WHERE %EXACT(Name) = '" _ tClassName _ "'"

   ; CORRECT — parameterized:
   Set tSC = tStmt.%Prepare("SELECT ... WHERE %EXACT(Name) = ?")
   Set tRS = tStmt.%Execute(tClassName)
   ```

4. **Reviewer confirmation.** The code reviewer MUST explicitly confirm in the
   Review Findings section that all three implementation layers (1, 2, 3) are
   present. A story whose reviewer section does not call out all three layers
   is not considered reviewed for SQL injection safety.

**Originating context.** Epic 12 retrospective AI-1 (2026-05-09) — codified
because Story 13.5 (`find_sessions_using_class`) is the first Epic 13 tool
whose `class_name` parameter flows directly into a SQL `WHERE` clause across
three `Ens.MessageHeader` columns (`SourceConfigName`, `TargetConfigName`,
`MessageBodyClassName`). The inspection tools (13.1-13.4) use class names for
`%OpenId` and `%Dictionary` lookups, not SQL WHERE — the injection surface
is different but the pattern applies there too.

**Reviewer enforcement.** Missing any of layers 1-3 is a HIGH-severity finding
per Rule 8 (predicted-bug shape: malformed or adversarial class-name input
reaches the SQL engine). Fix-now in the same story. Layer 4 (reviewer callout)
is a MEDIUM finding if absent — the code may be correct but the review is
incomplete.