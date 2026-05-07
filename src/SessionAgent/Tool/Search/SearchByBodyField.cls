/// <p>Search tool — pivot through an <CLASS>Ens.SearchTableBase</CLASS>
/// subclass extent (e.g., <CLASS>EnsLib.HL7.SearchTable</CLASS>) to find
/// Ens sessions whose body matched a <code>(prop_name, prop_value)</code>
/// pair. Search-agent companion to Inspection's
/// <CLASS>SessionAgent.Tool.Inspection.FindSessionsByBody</CLASS>
/// (Story 4.6 — first cross-codebase consumer of the SearchTableBase
/// row shape). Story 8.5 reuses Story 4.6's three validated patterns
/// verbatim:</p>
/// <ol>
/// <li><b>Class validation</b> — <code>%Dictionary.CompiledClass.%ExistsId</code>
/// existence guard plus <code>$ClassMethod(class, "%Extends",
/// "Ens.SearchTableBase")</code> hierarchy check (per Story 4.6 Task 0
/// finding: <code>%IsA</code> returns 0 for abstract intermediates like
/// <CLASS>EnsLib.HL7.SearchTable</CLASS>; <code>%Extends</code> is the
/// class-lineage check that returns 1 for both abstract and concrete
/// hierarchy members).</li>
/// <li><b>Two-step prop-name → PropId resolution</b> via
/// <CLASS>Ens.Config.SearchTableProp</CLASS>
/// (<code>WHERE ClassExtent = ? AND Name = ?</code>); the integer PropId
/// is the discriminator the SearchTable extent stores, not the operator's
/// logical property name.</li>
/// <li><b>v1 VDoc-only scope.</b>
/// <CLASS>Ens.CustomSearchTable</CLASS>-derived classes have no
/// <CLASS>Ens.Config.SearchTableProp</CLASS> mapping for their indexed
/// columns — when the prop-name lookup yields no row, the tool returns a
/// <code>no_matches</code> envelope (graceful — most likely the operator
/// typed a property the SearchTable doesn't index).</li>
/// </ol>
///
/// <p><b>Tool name:</b> <code>search_by_body_field</code>.</p>
///
/// <p><b>Read-only.</b> <parameter>MutatesState</parameter>=0.</p>
///
/// <p><b>Input (AC-2).</b>
/// <code>{search_table_class (required), prop_name (required),
/// prop_value (required), time_window_hours? (default 168, max 720),
/// limit? (default 50, max 500)}</code>. <code>time_window_hours</code>
/// default of <b>168 hours = 7 days</b> overrides the
/// <CLASS>SessionAgent.Tool.Search.Base</CLASS> default of 24 hours per
/// architecture OD8 <code>BodyFieldDefaultHours</code> — body-field
/// queries are typically less time-bounded than status / source queries
/// (operator looking up "MRN 12345" usually means the past week, not the
/// past day).</p>
///
/// <p><b>Indexed lead column (AC-1).</b>
/// <method>GetIndexedLeadColumns</method> returns
/// <code>["PropValue"]</code> — the canonical indexed column on every
/// <CLASS>Ens.SearchTableBase</CLASS> subclass extent (the
/// <code>(PropId, PropValue, DocId)</code> row shape's middle column,
/// which the bounded-WHERE invariant test discovers via static
/// inspection). The OPERATOR-supplied <code>prop_name</code> is the
/// LOGICAL name; <code>PropValue</code> is the PHYSICAL indexed column —
/// the <code>structuredContent.indexed_lead_column</code> field reports
/// <code>"PropValue"</code> for invariant-test consistency, while the
/// per-tool summary text mentions the operator-supplied
/// <code>prop_name</code> for operator-readability. See
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest.BuildIndexedColumnSet</CLASS>
/// — the indexed-set extension that accepts <code>"PropValue"</code> as
/// a documented indexed column for this tool.</p>
///
/// <p><b>Output (structuredContent).</b>
/// <code>{search_table_class, prop_name, prop_value,
/// time_window_used, sessions:[{session_id, time_created,
/// source_config_name, target_config_name, message_body_class_name,
/// status}, ...], session_count, indexed_lead_column:"PropValue",
/// render_strategy}</code>. <code>render_strategy</code> values:
/// <code>matched_sessions</code> (sessions returned),
/// <code>no_matches</code> (prop-name unknown for this SearchTable OR
/// no SearchTable rows match the value),
/// <code>search_table_not_installed</code> +
/// <code>not_search_table_subclass</code> (validation failures with
/// <code>isError:1</code>).</p>
///
/// <p><b>SQL safety + %EXACT() discipline (AC-5).</b>
/// <code>%EXACT()</code> on every <code>%String</code> projection +
/// predicate (<code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>, <code>DocId</code>,
/// <code>PropValue</code>, <code>Name</code>, <code>ClassExtent</code>);
/// plain comparison on <code>SessionId</code> (%Integer),
/// <code>PropId</code> (%Integer), <code>Status</code> (%Integer),
/// <code>TimeCreated</code> (Ens.DataType.UTC). Caller-supplied
/// <code>prop_value</code> is bound via <code>?</code> placeholder — never
/// concatenated into SQL. <code>search_table_class</code> IS interpolated
/// into the SQL FROM clause (table names cannot be SQL-bound) but ONLY
/// after the existence + <code>%Extends</code> validation gate, restricting
/// the value to a real installed subclass of
/// <CLASS>Ens.SearchTableBase</CLASS> — not operator-controllable to inject
/// arbitrary SQL.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.5</a> — AC source.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS> §"BuildBoundedWhereClause".</li>
/// <li><CLASS>SessionAgent.Tool.Inspection.FindSessionsByBody</CLASS>
/// (Story 4.6) — same JOIN/lookup pattern; shared SearchTable shape.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"OD8 BodyFieldDefaultHours" (168h default), §"Risk Mitigation:
/// SearchTable not installed".</li>
/// <li><a href="../../../../irislib/Ens/SearchTableBase.cls">irislib/Ens/SearchTableBase.cls</a>,
/// <a href="../../../../irislib/Ens/Config/SearchTableProp.cls">irislib/Ens/Config/SearchTableProp.cls</a>.</li>
/// </ul>
Class SessionAgent.Tool.Search.SearchByBodyField Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "search_by_body_field";

Parameter Description As %String = "Find Ens sessions via an Ens.SearchTableBase pivot — search_table_class + (prop_name, prop_value) predicate joins the indexed extent to Ens.MessageHeader. Default time window 168h (7d).";

Parameter MutatesState As %Boolean = 0;

/// <p>Default time window for this tool — <b>168 hours = 7 days</b>.
/// Overrides <CLASS>SessionAgent.Tool.Search.Base</CLASS>'s 24h default
/// per architecture OD8 <code>BodyFieldDefaultHours</code>. Body-field
/// queries (e.g., "find MRN 12345") are typically less time-bounded
/// than status/source queries.</p>
Parameter DefaultTimeWindowHours As %Integer = 168;

/// <p>Indexed lead column for AR11 invariant: <code>PropValue</code>.
/// This is the canonical indexed column on every
/// <CLASS>Ens.SearchTableBase</CLASS> subclass extent — the
/// <code>(PropId, PropValue, DocId)</code> row shape's middle column.
/// The bounded-WHERE invariant test
/// (<CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS>)
/// inspects this static return; AC-8 sub-task extended
/// <method>BuildIndexedColumnSet</method> to accept
/// <code>"PropValue"</code> as a documented indexed column for this
/// tool.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["PropValue"]
}

/// <p>Locked-subset JSON Schema (AC-2). Required:
/// <code>search_table_class</code>, <code>prop_name</code>,
/// <code>prop_value</code>. Optional: <code>time_window_hours</code>
/// (default 168, max 720), <code>limit</code> (default 50, max 500).
/// Locked subset (no <code>oneOf</code>/<code>anyOf</code>/etc.);
/// <code>additionalProperties: false</code>.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "search_table_class": {"type": "string", "description": "Fully-qualified Ens.SearchTableBase subclass name (e.g., 'EnsLib.HL7.SearchTable')."},
            "prop_name": {"type": "string", "description": "Indexed property name registered for this SearchTable (e.g., 'PID:3' for HL7 MRN, 'MRN', 'AccountNumber')."},
            "prop_value": {"type": "string", "description": "Exact value to match against PropValue. Wildcards are not interpreted in v1."},
            "time_window_hours": {"type": "integer", "description": "TimeCreated window in hours. Default 168 (7d), max 720 (30d).", "minimum": 1, "maximum": 720},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50, max 500.", "minimum": 1, "maximum": 500}
        },
        "required": ["search_table_class", "prop_name", "prop_value"],
        "additionalProperties": false
    }
}

/// <p>Implementation per AC-3, AC-4, AC-5, AC-6. Steps:</p>
/// <ol>
/// <li>Argument extraction + required-input validation (FR37 envelope).</li>
/// <li>AC-3: Class existence + <code>Ens.SearchTableBase</code> membership
/// validation. <b>This MUST run BEFORE any SQL construction</b> — the
/// validated <code>search_table_class</code> string is interpolated into
/// the FROM clause.</li>
/// <li>Limit + time-window clamp.</li>
/// <li>AC-4 Step A — prop-name → PropId resolution against
/// <CLASS>Ens.Config.SearchTableProp</CLASS>. If unknown, return
/// <code>no_matches</code> (graceful — handles both unregistered
/// prop-names and Custom SearchTables which don't use the
/// <code>(PropId, PropValue)</code> shape).</li>
/// <li>Resolve the SearchTable's SQL schema/table via
/// <CLASS>%Dictionary.CompiledClass</CLASS> projection.</li>
/// <li>AC-4 Step B — JOIN + bounded-WHERE SELECT. Time window
/// applied via <method>BuildBoundedWhereClause</method> (this tool's
/// <parameter>DefaultTimeWindowHours</parameter>=168 picks up
/// automatically when the caller passes 0).</li>
/// <li>Build envelope.</li>
/// </ol>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"sessions":[]}}
    Try {
        ; --- Step 1: argument extraction.
        Set tSearchClass = ""
        Set tPropName = ""
        Set tPropValue = ""
        Set tWindowHours = 0
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tSearchClassArg = pJsonArgs.%Get("search_table_class")
            Set:tSearchClassArg'=$$$NULLOREF tSearchClass = tSearchClassArg
            Set tPropNameArg = pJsonArgs.%Get("prop_name")
            Set:tPropNameArg'=$$$NULLOREF tPropName = tPropNameArg
            Set tPropValueArg = pJsonArgs.%Get("prop_value")
            Set:tPropValueArg'=$$$NULLOREF tPropValue = tPropValueArg
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }
        Set:tSearchClass=$$$NULLOREF tSearchClass = ""
        Set:tPropName=$$$NULLOREF tPropName = ""
        Set:tPropValue=$$$NULLOREF tPropValue = ""

        ; --- Step 2: required-input validation (FR37 envelope).
        If (tSearchClass = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing search_table_class"}]}
            Quit
        }
        If (tPropName = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing prop_name"}]}
            Quit
        }
        If (tPropValue = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing prop_value"}]}
            Quit
        }

        ; --- Step 3: AC-3 class existence + Ens.SearchTableBase membership.
        ; Pattern reused verbatim from Story 4.6 FindSessionsByBody Task 0:
        ; %Dictionary.CompiledClass.%ExistsId existence guard (otherwise
        ; %Extends throws <CLASS DOES NOT EXIST>); then $ClassMethod(...,
        ; "%Extends", ...) for the class-lineage check (%IsA returns 0 for
        ; abstract intermediates like EnsLib.HL7.SearchTable).
        ; This MUST run BEFORE SQL construction — tSearchClass is interpolated
        ; into the FROM clause and the validation gate is what restricts it
        ; to a real SearchTable subclass.
        If '##class(%Dictionary.CompiledClass).%ExistsId(tSearchClass) {
            Set tErrText = tSearchClass _ " is not an installed Ens.SearchTableBase subclass — install HealthShare SearchTables or use search_by_message_class instead"
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("indexed_lead_column", "PropValue")
            Do pResult.structuredContent.%Set("render_strategy", "search_table_not_installed")
            Do pResult.structuredContent.%Set("error_text", tErrText)
            Set pResult.content.%Get(0).text = tErrText
            Set pResult."isError" = 1
            Quit
        }
        Set tIsSubclass = $ClassMethod(tSearchClass, "%Extends", "Ens.SearchTableBase")
        If 'tIsSubclass {
            Set tErrText = tSearchClass _ " exists but is not a subclass of Ens.SearchTableBase"
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("indexed_lead_column", "PropValue")
            Do pResult.structuredContent.%Set("render_strategy", "not_search_table_subclass")
            Do pResult.structuredContent.%Set("error_text", tErrText)
            Set pResult.content.%Get(0).text = tErrText
            Set pResult."isError" = 1
            Quit
        }

        ; --- Step 4: clamp limit.
        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 500) Set tLimit = 500

        ; --- Step 5: prop_name → PropId lookup against Ens.Config.SearchTableProp.
        ; Pattern reused verbatim from Story 4.6 FindSessionsByBody. If
        ; the prop_name isn't registered for this SearchTable (or the
        ; SearchTable is an Ens.CustomSearchTable subclass with no
        ; mapping), the tool returns no_matches gracefully — NOT an error.
        Set tStmtProp = ##class(%SQL.Statement).%New()
        Set tSCp = tStmtProp.%Prepare("SELECT PropID FROM Ens_Config.SearchTableProp WHERE %EXACT(ClassExtent) = ? AND %EXACT(Name) = ?")
        If $$$ISERR(tSCp) {
            Set tErrText = "PropId-lookup prepare failed: " _ $System.Status.GetErrorText(tSCp)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"prepare_error", "error_text":(tErrText)}
            Quit
        }
        Set tRsProp = tStmtProp.%Execute(tSearchClass, tPropName)
        Set tPropId = ""
        If tRsProp.%Next() {
            Set tPropId = tRsProp.%Get("PropID")
        }

        Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)

        If (tPropId = "") {
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("time_window_used", tWindowUsed, "number")
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("indexed_lead_column", "PropValue")
            Do pResult.structuredContent.%Set("render_strategy", "no_matches")
            Set tErrText = "Property '" _ tPropName _ "' is not indexed by SearchTable '" _ tSearchClass _ "'"
            Do pResult.structuredContent.%Set("error_text", tErrText)
            Set pResult.content.%Get(0).text = tErrText
            Set pResult."isError" = 1
            Quit
        }

        ; --- Step 6: resolve SearchTable's SQL schema/table via compiled-class projection.
        Set tCompiled = ##class(%Dictionary.CompiledClass).%OpenId(tSearchClass)
        If '$IsObject(tCompiled) {
            Set tErrText = "could not open compiled class metadata for " _ tSearchClass
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
            Quit
        }
        Set tSqlSchema = tCompiled.SqlSchemaName
        Set tSqlTable = tCompiled.SqlTableName
        If (tSqlSchema = "") || (tSqlTable = "") {
            Set tErrText = tSearchClass _ " has no SQL schema/table projection — cannot search"
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
            Quit
        }
        Set tFromTable = tSqlSchema _ "." _ tSqlTable

        ; --- Step 7: build the bounded WHERE clause + JOIN SQL.
        ; BuildBoundedWhereClause picks up this class's DefaultTimeWindowHours
        ; (168) automatically when tWindowHours = 0. Additional predicates
        ; are the (PropId, PropValue) match on the SearchTable side.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(
            tWindowHours, .tParams, .tErr,
            "st.PropId = ?", "%EXACT(st.PropValue) = ?")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }
        ; tParams now contains: [tCutoffOdbc] (from BuildBoundedWhereClause's
        ; default-window mode against mh.TimeCreated). The "TimeCreated > ?"
        ; predicate refers to mh, but BuildBoundedWhereClause emits an
        ; unqualified "TimeCreated > ?". Replace with mh.TimeCreated.
        ; Note: BuildBoundedWhereClause emits "TimeCreated > ?" and stub-
        ; positive tests (Story 8.2) verify that exact form. Concrete tools
        ; using JOINs need to qualify it; we do that here.
        Set tFragment = $Replace(tFragment, "TimeCreated > ?", "mh.TimeCreated > ?")
        ; Now push the (PropId, PropValue) bind values onto tParams in
        ; predicate order.
        Do tParams.%Push(tPropId)
        Do tParams.%Push(tPropValue)

        Set tSql = "SELECT TOP ? mh.SessionId AS sid, mh.TimeCreated AS tc, "
        Set tSql = tSql _ "%EXACT(mh.SourceConfigName) AS src, "
        Set tSql = tSql _ "%EXACT(mh.TargetConfigName) AS tgt, "
        Set tSql = tSql _ "%EXACT(mh.MessageBodyClassName) AS bc, "
        Set tSql = tSql _ "mh.Status AS st "
        Set tSql = tSql _ "FROM " _ tFromTable _ " st "
        Set tSql = tSql _ "JOIN Ens.MessageHeader mh ON %EXACT(mh.MessageBodyId) = %EXACT(st.DocId) "
        Set tSql = tSql _ "WHERE " _ tFragment _ " "
        Set tSql = tSql _ "ORDER BY mh.TimeCreated DESC, mh.ID DESC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCs = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCs) {
            Set tErrText = "search SQL prepare failed: " _ $System.Status.GetErrorText(tSCs)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"prepare_error", "error_text":(tErrText)}
            Quit
        }

        ; Variadic %Execute via canonical multi-dim local-array apply.
        Kill tArgs
        Set tArgs(1) = tLimit
        Set tArgIdx = 1
        Set tBindIter = tParams.%GetIterator()
        While tBindIter.%GetNext(.tBindKey, .tBindVal) {
            Set tArgIdx = tArgIdx + 1
            Set tArgs(tArgIdx) = tBindVal
        }
        Set tArgs = tArgIdx
        Set tRs = tStmt.%Execute(tArgs...)

        Set tSessions = []
        Set tCount = 0
        While tRs.%Next() {
            Set tEntry = {}
            Do tEntry.%Set("session_id", +tRs.%Get("sid"), "number")
            Do tEntry.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("tc")))
            Do tEntry.%Set("source_config_name", tRs.%Get("src"))
            Do tEntry.%Set("target_config_name", tRs.%Get("tgt"))
            Do tEntry.%Set("message_body_class_name", tRs.%Get("bc"))
            Do tEntry.%Set("status", +tRs.%Get("st"), "number")
            Do tSessions.%Push(tEntry)
            Set tCount = tCount + 1
        }

        ; --- Step 8: build envelope.
        Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
        Do pResult.structuredContent.%Set("prop_name", tPropName)
        Do pResult.structuredContent.%Set("prop_value", tPropValue)
        Do pResult.structuredContent.%Set("time_window_used", tWindowUsed, "number")
        Do pResult.structuredContent.%Set("sessions", tSessions)
        Do pResult.structuredContent.%Set("session_count", tCount, "number")
        Do pResult.structuredContent.%Set("indexed_lead_column", "PropValue")
        If (tCount = 0) {
            Do pResult.structuredContent.%Set("render_strategy", "no_matches")
            Set pResult.content.%Get(0).text = "No sessions matched (" _ tPropName _ "='" _ tPropValue _ "') in " _ tSearchClass _ " in the last " _ tWindowUsed _ " hour(s)."
        } Else {
            Do pResult.structuredContent.%Set("render_strategy", "matched_sessions")
            Set pResult.content.%Get(0).text = "Found " _ tCount _ " session(s) where " _ tPropName _ " = '" _ tPropValue _ "' in " _ tSearchClass _ " in the last " _ tWindowUsed _ " hour(s)."
        }
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
        Quit
    }
    Quit tSC
}

}
