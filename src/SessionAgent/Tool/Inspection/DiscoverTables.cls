/// <p>Schema-discovery tool — enumerate SQL tables/views visible in the
/// namespace via <CLASS>INFORMATION_SCHEMA.TABLES</CLASS>, optionally
/// filtered by a case-insensitive name fragment (FR61, Story 14.2 AC-3).
/// This is the entry point for finding custom application tables the
/// fixed tool catalog does not anticipate — lookup/reference tables,
/// search tables, config tables, reporting tables.</p>
///
/// <p><b>Tool name:</b> <code>discover_tables</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{name_fragment (optional), include_system
/// (optional bool, default false), max_results (optional int, default 50,
/// clamped 1..200)}</code>. The fragment is bound as a parameterized
/// both-sides-UPPER <code>LIKE</code> — never concatenated into the SQL
/// text (SQL-injection layers 1–3 per project rule; layer 2 regex gates
/// the fragment shape server-side).</p>
///
/// <p><b>System-schema exclusion.</b> With
/// <code>include_system=false</code> (default), schemas starting with
/// <code>%</code> and the <code>INFORMATION_SCHEMA</code> schema itself
/// are excluded. <code>Ens*</code> schemas are operator-relevant and stay
/// INCLUDED (per Story 14.2 AC-3).</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{name_fragment, include_system, max_results,
/// tables:[{schema, name, type}], table_count, truncated,
/// render_strategy:"ok"}</code>. An empty result is NOT an error.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-2-schema-discovery-tools.md">Story 14.2</a> AC-3 — AC source.</li>
/// <li><a href="../../../../docs/iris-query-guide/04-schema-discovery.md">docs/iris-query-guide/04-schema-discovery.md</a> §"Discovering custom application tables (end-to-end)".</li>
/// </ul>
Class SessionAgent.Tool.Inspection.DiscoverTables Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "discover_tables";

Parameter Description As %String = "List SQL tables and views in the namespace from INFORMATION_SCHEMA.TABLES, optionally filtered by a case-insensitive table-name fragment. Default excludes %-system and INFORMATION_SCHEMA schemas (Ens* schemas stay included). Use this to find custom application tables before describing or querying them.";

Parameter MutatesState As %Boolean = 0;

/// <p>Default result cap.</p>
Parameter DEFAULTMAXRESULTS As %Integer = 50;

/// <p>Hard result cap.</p>
Parameter MAXMAXRESULTS As %Integer = 200;

/// <p>JSON Schema — all properties optional. Layer (1) of the
/// SQL-injection defense lives in the <code>name_fragment</code>
/// description.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "name_fragment": {
                "type": "string",
                "description": "Optional case-insensitive fragment matched anywhere in the table name (e.g. 'MessageHeader', 'Order', 'SearchTable'). Pass a bare name fragment only — letters, digits, '%', '.', '_' (no spaces, no SQL syntax). LIKE wildcard semantics apply to '_' and '%' characters. Dotted fragments (e.g. 'Ens.MessageHeader') are also matched against the qualified schema.name."
            },
            "include_system": {
                "type": "boolean",
                "description": "When true, include %-system schemas and INFORMATION_SCHEMA in the listing. Default false. Ens* schemas are always included."
            },
            "max_results": {
                "type": "integer",
                "description": "Maximum tables returned. Default 50, clamped 1..200.",
                "minimum": 1,
                "maximum": 200
            }
        },
        "required": [],
        "additionalProperties": false
    }
}

/// <p>Run the parameterized INFORMATION_SCHEMA.TABLES listing and return
/// the envelope. Empty listing returns <code>tables:[]</code> with
/// <code>render_strategy:"ok"</code>.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"tables":[]}}
    Try {
        ; --- Extract arguments ---
        Set tFragment = ""
        Set tIncludeSystem = 0
        Set tMax = ..#DEFAULTMAXRESULTS
        If $IsObject($Get(pJsonArgs)) {
            Set tFragment = pJsonArgs.%Get("name_fragment")
            Set:tFragment=$$$NULLOREF tFragment = ""
            ; Type-gated reads (review fix 14.2): an object/array-valued
            ; arg must not reach boolean/integer coercion — an OREF
            ; stringifies as "n@%Library.DynamicObject" and `\ 1` would
            ; coerce it to an arbitrary small integer.
            If pJsonArgs.%IsDefined("include_system") {
                Set tISType = pJsonArgs.%GetTypeOf("include_system")
                If (tISType = "boolean") || (tISType = "number") {
                    Set tIncludeSystem = ''+pJsonArgs.%Get("include_system")
                } ElseIf tISType = "string" {
                    ; Providers drift on declared schemas (Epic 5 history) —
                    ; accept the string forms "true"/"1" as true.
                    Set tISVal = $ZConvert(pJsonArgs.%Get("include_system"), "L")
                    Set tIncludeSystem = ((tISVal = "true") || (tISVal = "1"))
                }
            }
            Set tMaxType = pJsonArgs.%GetTypeOf("max_results")
            If (tMaxType = "number") || (tMaxType = "string") {
                Set tMaxArg = pJsonArgs.%Get("max_results")
                If tMaxArg '= "" Set tMax = tMaxArg \ 1
            }
        }
        ; Clamp 1..200 per AC-3 — consistent with list_active_body_types
        ; hours<1 clamping to 1 (review fix 14.2; previously sub-1 fell
        ; back to the default 50, contradicting the published schema).
        If tMax < 1 Set tMax = 1
        If tMax > ..#MAXMAXRESULTS Set tMax = ..#MAXMAXRESULTS

        ; Layer (2) — server-side $Match regex validation on the fragment.
        If (tFragment '= "") && ('$Match(tFragment, "^[A-Za-z0-9%._]+$")) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid name_fragment format — use a bare table-name fragment (letters, digits, '%', '.', '_')"}]}
            Quit
        }

        ; --- Build the parameterized listing (Layer 3: fragment bound as ?) ---
        Set tSql = "SELECT TOP ? %EXACT(TABLE_SCHEMA), %EXACT(TABLE_NAME), %EXACT(TABLE_TYPE) FROM INFORMATION_SCHEMA.TABLES"
        Set tWhere = ""
        If 'tIncludeSystem {
            Set tWhere = "NOT (TABLE_SCHEMA %STARTSWITH '%') AND UPPER(TABLE_SCHEMA) <> 'INFORMATION_SCHEMA'"
        }
        Set tDotted = (tFragment [ ".")
        If tFragment '= "" {
            Set:tWhere'="" tWhere = tWhere _ " AND "
            If tDotted {
                ; Dotted fragments (e.g. 'Ens.MessageHeader') can never match
                ; a bare TABLE_NAME — also match the qualified schema.name.
                ; Package '.' maps to '_' in the schema name, so the second
                ; bind translates '.' -> '_' (the LIKE single-char wildcard
                ; matches both) (review fix 14.2).
                Set tWhere = tWhere _ "(UPPER(TABLE_NAME) LIKE '%' || UPPER(?) || '%' OR UPPER(TABLE_SCHEMA) || '.' || UPPER(TABLE_NAME) LIKE '%' || UPPER(?) || '%')"
            } Else {
                Set tWhere = tWhere _ "UPPER(TABLE_NAME) LIKE '%' || UPPER(?) || '%'"
            }
        }
        Set:tWhere'="" tSql = tSql _ " WHERE " _ tWhere
        Set tSql = tSql _ " ORDER BY TABLE_SCHEMA, TABLE_NAME"

        ; Fetch cap+1 so `truncated` reflects genuine overflow, not an
        ; exact-count boundary (review fix 14.2 — same pattern as
        ; DescribeMessageClass.AppendExtentClasses).
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare(tSql)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit
        If tFragment '= "" {
            If tDotted {
                Set tRS = tStmt.%Execute(tMax + 1, tFragment, $Translate(tFragment, ".", "_"))
            } Else {
                Set tRS = tStmt.%Execute(tMax + 1, tFragment)
            }
        } Else {
            Set tRS = tStmt.%Execute(tMax + 1)
        }
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        Set tTables = []
        Set tOverflow = 0
        While tRS.%Next() {
            If tTables.%Size() >= tMax { Set tOverflow = 1 Quit }
            ; Positional %GetData reads — %EXACT() in SELECT renames columns.
            Set tEntry = {}
            Do tEntry.%Set("schema", tRS.%GetData(1))
            Do tEntry.%Set("name", tRS.%GetData(2))
            Do tEntry.%Set("type", tRS.%GetData(3))
            Do tTables.%Push(tEntry)
        }
        ; Fetch-time fault gate — a mid-cursor error must not ship partial
        ; rows inside an ok envelope (review fix 14.2).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- Success envelope (empty listing is NOT an error) ---
        Do pResult.structuredContent.%Set("name_fragment", tFragment)
        Do pResult.structuredContent.%Set("include_system", tIncludeSystem, "boolean")
        Do pResult.structuredContent.%Set("max_results", tMax, "number")
        Do pResult.structuredContent.%Set("tables", tTables)
        Do pResult.structuredContent.%Set("table_count", tTables.%Size(), "number")
        Do pResult.structuredContent.%Set("truncated", tOverflow, "boolean")
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Set tFragLabel = $Select(tFragment'="":" matching '" _ tFragment _ "'", 1:"")
        Set pResult.content.%Get(0).text = "Found " _ tTables.%Size() _ " table(s)/view(s)" _ tFragLabel _ $Select(tOverflow:" (truncated at " _ tMax _ ")", 1:"") _ "."
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

}
