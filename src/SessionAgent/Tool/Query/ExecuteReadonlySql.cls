/// <p>Query tool — runs a single LLM-authored SQL SELECT statement under
/// the <CLASS>SessionAgent.Tool.Query.Base</CLASS> compiler-level
/// read-only guard pipeline (Story 14.3 / FR60). Opens the long tail of
/// open-ended analytical trace questions without sacrificing the v1
/// read-only guarantee: every non-SELECT statement (INSERT / UPDATE /
/// DELETE / CALL / DDL) is rejected pre-execution by the
/// <code>statementType</code> gate, multi-statement input is rejected by
/// validation, and results are row-capped, char-budgeted, and
/// elapsed-guarded.</p>
///
/// <p><b>Tool name:</b> <code>execute_readonly_sql</code>. Read-only
/// (<parameter>MutatesState</parameter>=0). Exposed to BOTH agents
/// (registry auto-discovery; decision D1).</p>
///
/// <p><b>Input:</b> <code>{sql (required), max_rows (optional, default
/// 50, clamp 1..200)}</code>. Results render in <code>%SelectMode</code>
/// ODBC for stable timestamp/decode rendering (set by the base
/// pipeline pre-<code>%Prepare</code>).</p>
///
/// <p><b>Output (structuredContent):</b> <code>{render_strategy:"ok",
/// columns:[...], rows:[[...]], row_count, truncated, truncate_reason?,
/// elapsed_ms}</code>; error envelopes carry
/// <code>render_strategy</code> ∈ {<code>validation_error</code>,
/// <code>multi_statement</code>, <code>not_select</code>,
/// <code>prepare_error</code>, <code>execute_error</code>} plus a
/// SQLCODE-keyed <code>hint</code> from the knowledge corpus's
/// <code>diagnostic-checklist</code> article on prepare/execute
/// failures.</p>
///
/// <p><b>Residual risk + elapsed-guard semantics</b> are documented on
/// <CLASS>SessionAgent.Tool.Query.Base</CLASS> (the doc-comment of
/// record per proposal §4.2 item 1): a SELECT can invoke SQL-projected
/// class methods with side effects — mitigated by L3 RBAC
/// (<code>SessionAgent_ReadOnly</code>), 100% ToolCall audit, and the
/// read-only prompt covenant; the elapsed guard fires between fetch
/// iterations and does not preempt a long <code>%Execute</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md">Story 14.3</a> — AC-3/AC-4 source.</li>
/// <li><a href="Base.cls">SessionAgent.Tool.Query.Base</a> — the guard pipeline.</li>
/// </ul>
Class SessionAgent.Tool.Query.ExecuteReadonlySql Extends SessionAgent.Tool.Query.Base
{

Parameter ToolName As %String = "execute_readonly_sql";

Parameter Description As %String = "Run a single read-only SQL SELECT statement against this namespace and return capped tabular results. Use for open-ended analytical questions the purpose-built tools do not cover (aggregates, custom joins, AdditionalInfo pivots). Consult get_query_knowledge BEFORE authoring SQL - the IRIS dialect has silent traps. EXPLAIN SELECT is also accepted for query-plan reasoning on slow queries (plan-only; EXPLAIN of a write statement is rejected). Non-SELECT statements (INSERT/UPDATE/DELETE/CALL/DDL) are rejected by a compiler-level gate; results are row-capped and time-guarded.";

Parameter MutatesState As %Boolean = 0;

/// <p>JSON Schema for <code>execute_readonly_sql</code> (locked subset).
/// The <code>sql</code> description is SQL-injection layer L1 — it
/// primes the LLM toward correctly-shaped single-SELECT input before
/// the server-side gates fire.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "sql": {
                "type": "string",
                "description": "A single SQL SELECT statement, or EXPLAIN SELECT for a query plan. Always include a time-window predicate and TOP N on exploratory queries. INSERT/UPDATE/DELETE/CALL are rejected, including under EXPLAIN."
            },
            "max_rows": {
                "type": "integer",
                "description": "Optional maximum number of result rows. Default 50, hard max 200.",
                "minimum": 1,
                "maximum": 200
            }
        },
        "required": ["sql"],
        "additionalProperties": false
    }
}

/// <p>Validate args, clamp <code>max_rows</code>, and route execution
/// through the base pipeline's single entry point
/// <method>RunGuardedSelect</method> — this method performs NO direct
/// <code>%Prepare</code>/<code>%Execute</code> (the
/// <CLASS>SessionAgent.Test.ReadOnlySqlInvariantTest</CLASS> contract).</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Input extraction + required-arg validation (FR37) ---
        Set tSql = ""
        Set tMaxRows = ..#DEFAULTMAXROWS
        If $IsObject($Get(pJsonArgs)) {
            Set tSql = pJsonArgs.%Get("sql")
            If pJsonArgs.%IsDefined("max_rows") {
                Set tMaxRows = +pJsonArgs.%Get("max_rows")
            }
        }
        If $ZStrip(tSql, "<>WC") = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"sql is required: a single SQL SELECT statement"}]}
            Quit
        }
        ; Clamp max_rows: default when non-positive, hard ceiling, floor
        ; fractional values.
        Set tMaxRows = tMaxRows \ 1
        If tMaxRows < 1 Set tMaxRows = ..#DEFAULTMAXROWS
        If tMaxRows > ..#HARDMAXROWS Set tMaxRows = ..#HARDMAXROWS

        ; --- Route through the guarded pipeline (the ONLY execution path) ---
        Set tSC = ..RunGuardedSelect(tSql, tMaxRows, .pResult)
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
    }
    Quit tSC
}

}
