/// <p>Inspection tool — pivot through an <CLASS>Ens.SearchTableBase</CLASS>
/// subclass extent (e.g., <CLASS>EnsLib.HL7.SearchTable</CLASS>) to find
/// Ens sessions whose body matched a <code>(prop_name, prop_value)</code>
/// pair. Read-only (<parameter>MutatesState</parameter>=0). Story 4.6 —
/// the <b>first cross-codebase consumer of the SearchTableBase row shape</b>;
/// Epic 8 Story 8.5 (<code>SearchByBodyField</code>) cites this tool's
/// Task-0 probe captures.</p>
///
/// <p><b>Tool name:</b> <code>find_sessions_by_body</code>.</p>
///
/// <p><b>Input:</b>
/// <code>{search_table_class (required), prop_name (required),
/// prop_value (required), time_window_hours?, limit?}</code>.
/// <code>time_window_hours</code> default 168 (1 week), range
/// [1, 8760]; <code>limit</code> default 50, range [1, 1000].</p>
///
/// <p><b>Output (structuredContent):</b></p>
/// <ul>
/// <li>Happy path: <code>{search_table_class, prop_name, prop_value,
/// time_window_hours, sessions:[{session_id, time_created,
/// source_config_name, target_config_name, message_id}, ...],
/// session_count, render_strategy:"matched_sessions"}</code>.</li>
/// <li>No matches: <code>{... sessions:[], session_count:0,
/// render_strategy:"no_matches"}</code> — NOT
/// <code>isError</code>; an empty result is normal.</li>
/// <li>Class not installed: <code>{render_strategy:"search_table_not_installed",
/// error_text:"<class> is not installed in this namespace; body-field
/// search is unavailable for this body class"}</code> with
/// <code>isError:1</code>.</li>
/// <li>Wrong superclass: <code>{render_strategy:"not_search_table_subclass",
/// error_text:"<class> exists but is not a subclass of
/// Ens.SearchTableBase"}</code> with <code>isError:1</code>.</li>
/// <li>Unexpected exception: <code>{render_strategy:"query_error",
/// error_text:"..."}</code> with <code>isError:1</code>.</li>
/// </ul>
///
/// <p><b>Class validation idiom (binding for Epic 8 Story 8.5).</b> The
/// canonical hierarchy probe is
/// <code>$ClassMethod(class, "%Extends", "Ens.SearchTableBase")</code>
/// guarded by
/// <code>##class(%Dictionary.CompiledClass).%ExistsId(class)</code>. Two
/// alternatives were considered and rejected during Task 0 probing:</p>
/// <ol>
/// <li><b>SQL <code>PrimarySuper LIKE '%~Ens.SearchTableBase~%'</code></b>
/// — REJECTED. <code>%Dictionary.CompiledClass.PrimarySuper</code> only
/// walks the <em>primary</em> (first-listed) inheritance chain. Real
/// SearchTable subclasses declare
/// <code>Super = "%Persistent,Ens.VDoc.SearchTable"</code>, with
/// <code>%Persistent</code> as the primary super, so
/// <code>Ens.SearchTableBase</code> never appears in
/// <code>PrimarySuper</code> for them. The original spec's
/// <code>PrimarySuperList</code> string also doesn't exist as a
/// projection (SQLCODE -29).</li>
/// <li><b><code>$ClassMethod(class, "%IsA", "Ens.SearchTableBase")</code></b>
/// — REJECTED. <code>%IsA</code> returns 0 for
/// <code>EnsLib.HL7.SearchTable</code> (and similar VDoc tables) on a
/// well-formed system because the class is <code>Abstract</code>; that
/// method is the instance-side check. <code>%Extends</code> is the
/// class-lineage check that returns 1 for both abstract and concrete
/// hierarchy members.</li>
/// </ol>
///
/// <p><b>VDoc row-shape pivot (Rule 8 fix-now).</b> The original spec
/// assumed the SearchTable extent is shaped <code>(DocId, PropName,
/// PropValue)</code>. Task 0 empirically verified the shape is
/// <code>(PropId %Integer, PropValue %String, DocId %String)</code> with
/// the prop-name → PropID mapping in
/// <code>Ens.Config.SearchTableProp</code>
/// (<code>WHERE ClassExtent = ? AND Name = ?</code>). The tool emits a
/// 2-step lookup: first map <code>prop_name</code> → <code>PropId</code>
/// against <code>Ens.Config.SearchTableProp</code>, then JOIN
/// <code>&lt;search_table_class&gt;</code> on
/// <code>(PropId, PropValue)</code> to
/// <code>Ens.MessageHeader.MessageBodyId = SearchTable.DocId</code>. If
/// the prop-name lookup yields no row, the tool returns
/// <code>render_strategy="no_matches"</code> (graceful — most likely the
/// operator typed a property name that this SearchTable doesn't index).</p>
///
/// <p><b>v1 scope: VDoc-style SearchTables only.</b>
/// <CLASS>Ens.CustomSearchTable</CLASS>-derived classes do NOT use the
/// <code>(PropId, PropValue)</code> shape — they declare their own
/// per-subclass properties and have no
/// <code>Ens.Config.SearchTableProp</code> mapping. For a custom
/// SearchTable, the prop-name lookup returns no row, so the tool
/// returns <code>render_strategy="no_matches"</code> rather than
/// erroring. Custom SearchTable support is a future story.</p>
///
/// <p><b>SQL discipline.</b> <code>%EXACT()</code> on every
/// <code>%String</code> projection and predicate
/// (<code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>DocId</code>, <code>PropValue</code>, <code>Name</code>,
/// <code>ClassExtent</code>); plain comparison on
/// <code>SessionId</code> (%Integer), <code>PropId</code> (%Integer),
/// and <code>TimeCreated</code> (%TimeStamp via ODBC string).
/// Parameterized via <code>%SQL.Statement.%Prepare</code> +
/// <code>%Execute(?, ...)</code>. The <code>search_table_class</code>
/// IS interpolated into the prepared SQL string (SearchTable subclass
/// names cannot be SQL-bound — they choose the FROM table) but ONLY
/// after class validation succeeds, which restricts the value to a real
/// installed subclass of <code>Ens.SearchTableBase</code> — the input
/// is therefore not operator-controllable to inject arbitrary SQL.</p>
///
/// <p><b>Wildcard handling.</b> <code>prop_value</code> is bound as a
/// SQL parameter against <code>=</code>; <code>%</code> and
/// <code>_</code> are NOT interpreted as wildcards. v1 is exact-match
/// only. Future LIKE support would need an <code>exact_match: false</code>
/// schema flag.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.6</a> (line 1588) — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/4-6-findsessionsbybody-ens-searchtablebase-pivot.md">Story 4.6 spec</a>
/// — Task 0 probe captures (binding for Epic 8 Story 8.5).</li>
/// <li><a href="../../../../irislib/Ens/SearchTableBase.cls">irislib/Ens/SearchTableBase.cls</a>,
/// <a href="../../../../irislib/Ens/VDoc/SearchTable.cls">VDoc/SearchTable.cls</a>,
/// <a href="../../../../irislib/Ens/Config/SearchTableProp.cls">Config/SearchTableProp.cls</a>,
/// <a href="../../../../irislib/%25Dictionary/CompiledClass.cls">%Dictionary/CompiledClass.cls</a>.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.FindSessionsByBody Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "find_sessions_by_body";

Parameter Description As %String = "Find Ens sessions whose body matched an indexed (PropName, PropValue) pair via Ens.SearchTableBase subclass extents.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Required:
/// <code>search_table_class</code>, <code>prop_name</code>,
/// <code>prop_value</code>. Optional:
/// <code>time_window_hours</code> (default 168, range [1, 8760]),
/// <code>limit</code> (default 50, range [1, 1000]).
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "search_table_class": {"type": "string", "description": "Fully qualified name of an Ens.SearchTableBase subclass (e.g., EnsLib.HL7.SearchTable)."},
            "prop_name": {"type": "string", "description": "Indexed property name registered for this SearchTable (e.g., MRN, AccountNumber)."},
            "prop_value": {"type": "string", "description": "Exact value to match against PropValue. Wildcards are not interpreted in v1."},
            "time_window_hours": {"type": "integer", "description": "Limit results to messages whose TimeCreated falls within this many hours of now. Default 168 (1 week).", "minimum": 1, "maximum": 8760},
            "limit": {"type": "integer", "description": "Max sessions returned. Default 50.", "minimum": 1, "maximum": 1000}
        },
        "required": ["search_table_class", "prop_name", "prop_value"],
        "additionalProperties": false
    }
}

/// <p>Implementation per AC-4. Steps:</p>
/// <ol>
/// <li>Pre-validate inputs.</li>
/// <li>Class validation — exists + extends Ens.SearchTableBase.</li>
/// <li>Sanitize time_window_hours (clamp default 168, range [1, 8760]).</li>
/// <li>Sanitize limit (clamp default 50, range [1, 1000]).</li>
/// <li>Map prop_name → PropId via Ens.Config.SearchTableProp.</li>
/// <li>Build parameterized SQL with the validated SearchTable class
/// interpolated into the FROM clause (only path — table names cannot be
/// SQL-bound). Execute and collect rows.</li>
/// <li>Emit happy-path / no_matches / error envelope.</li>
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
        Set tTimeWindow = 168
        Set tLimit = 50
        If $IsObject($Get(pJsonArgs)) {
            Set tSearchClass = pJsonArgs.%Get("search_table_class")
            Set tPropName = pJsonArgs.%Get("prop_name")
            Set tPropValue = pJsonArgs.%Get("prop_value")
            Set tTwArg = pJsonArgs.%Get("time_window_hours")
            Set:tTwArg'=$$$NULLOREF tTimeWindow = +tTwArg
            Set tLimitArg = pJsonArgs.%Get("limit")
            Set:tLimitArg'=$$$NULLOREF tLimit = +tLimitArg
        }

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

        ; --- Step 3: class existence + Ens.SearchTableBase membership.
        ; Probe via %Dictionary.CompiledClass first; %Extends throws
        ; <CLASS DOES NOT EXIST> for missing classes, so the existence
        ; guard is required.
        If '##class(%Dictionary.CompiledClass).%ExistsId(tSearchClass) {
            Set tErrText = tSearchClass _ " is not installed in this namespace; body-field search is unavailable for this body class"
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("render_strategy", "search_table_not_installed")
            Do pResult.structuredContent.%Set("error_text", tErrText)
            Set pResult.content.%Get(0).text = tErrText
            Set pResult."isError" = 1
            Quit
        }
        ; Class exists; check superclass via %Extends (the canonical idiom
        ; for class-lineage; %IsA fails for abstract intermediates).
        Set tIsSubclass = $ClassMethod(tSearchClass, "%Extends", "Ens.SearchTableBase")
        If 'tIsSubclass {
            Set tErrText = tSearchClass _ " exists but is not a subclass of Ens.SearchTableBase"
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("render_strategy", "not_search_table_subclass")
            Do pResult.structuredContent.%Set("error_text", tErrText)
            Set pResult.content.%Get(0).text = tErrText
            Set pResult."isError" = 1
            Quit
        }

        ; --- Step 4: clamp/normalize numeric inputs.
        If (tTimeWindow < 1) Set tTimeWindow = 168
        If (tTimeWindow > 8760) Set tTimeWindow = 8760
        If (tLimit < 1) Set tLimit = 50
        If (tLimit > 1000) Set tLimit = 1000

        ; --- Step 5: prop_name → PropId lookup against Ens.Config.SearchTableProp.
        ; Per Task 0, ClassExtent + Name uniquely identify the row; PropID
        ; is the integer the SearchTable extent stores.
        Set tStmtProp = ##class(%SQL.Statement).%New()
        Set tSCp = tStmtProp.%Prepare("SELECT PropID FROM Ens_Config.SearchTableProp WHERE %EXACT(ClassExtent) = ? AND %EXACT(Name) = ?")
        If $$$ISERR(tSCp) {
            ; Treat prepare failure as query_error — defensive.
            Set tErrText = "PropId-lookup prepare failed: " _ $System.Status.GetErrorText(tSCp)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
            Quit
        }
        Set tRsProp = tStmtProp.%Execute(tSearchClass, tPropName)
        Set tPropId = ""
        If tRsProp.%Next() {
            Set tPropId = tRsProp.%Get("PropID")
        }

        ; If the prop_name isn't registered for this SearchTable, the
        ; SearchTable can't possibly contain matching rows — return
        ; no_matches gracefully (NOT an error). This also covers
        ; Ens.CustomSearchTable subclasses that don't use the
        ; PropId/PropValue shape.
        If (tPropId = "") {
            Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
            Do pResult.structuredContent.%Set("prop_name", tPropName)
            Do pResult.structuredContent.%Set("prop_value", tPropValue)
            Do pResult.structuredContent.%Set("time_window_hours", tTimeWindow, "number")
            Do pResult.structuredContent.%Set("sessions", [])
            Do pResult.structuredContent.%Set("session_count", 0, "number")
            Do pResult.structuredContent.%Set("render_strategy", "no_matches")
            Set pResult.content.%Get(0).text = "no sessions matched (" _ tPropName _ "=" _ tPropValue _ ") via " _ tSearchClass
            Quit
        }

        ; --- Step 6: build the search SQL.
        ; The SearchTable subclass's SQL table name is derived via the
        ; %compiledclass.SqlSchemaName + SqlTableName projection (e.g.,
        ; EnsLib.HL7.SearchTable → EnsLib_HL7.SearchTable). Look these
        ; up dynamically so this tool works for any registered subclass.
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

        ; Build the time lower-bound as ODBC TIMESTAMP. $Horolog is
        ; (date,seconds-since-midnight). Subtract whole seconds to compute
        ; a lower bound. tTimeWindow is hours.
        Set tNowDate = +$Horolog
        Set tNowSecs = +$Piece($Horolog, ",", 2)
        Set tTotalSecs = (tNowDate * 86400) + tNowSecs
        Set tLowerSecs = tTotalSecs - (tTimeWindow * 3600)
        Set tLowerDate = tLowerSecs \ 86400
        Set tLowerSod = tLowerSecs # 86400
        Set tLowerHorolog = tLowerDate _ "," _ tLowerSod
        Set tLowerOdbc = $ZDateTime(tLowerHorolog, 3, 1, 0)

        ; Construct the SQL — the FROM table comes from validated metadata
        ; (it cannot be operator-controlled to inject arbitrary SQL because
        ; tSearchClass passed the existence + %Extends gate, and the
        ; SqlSchemaName/SqlTableName come from the compiled-class projection,
        ; not the user input string).
        Set tSql = "SELECT TOP ? mh.SessionId AS session_id, mh.TimeCreated AS time_created, "
        Set tSql = tSql _ "%EXACT(mh.SourceConfigName) AS source_config_name, "
        Set tSql = tSql _ "%EXACT(mh.TargetConfigName) AS target_config_name, "
        Set tSql = tSql _ "%EXACT(st.DocId) AS message_id "
        Set tSql = tSql _ "FROM " _ tFromTable _ " st "
        Set tSql = tSql _ "JOIN Ens.MessageHeader mh ON %EXACT(mh.MessageBodyId) = %EXACT(st.DocId) "
        Set tSql = tSql _ "WHERE st.PropId = ? AND %EXACT(st.PropValue) = ? AND mh.TimeCreated >= ? "
        Set tSql = tSql _ "ORDER BY mh.TimeCreated DESC, mh.ID DESC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCs = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCs) {
            Set tErrText = "search SQL prepare failed: " _ $System.Status.GetErrorText(tSCs)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
            Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
            Quit
        }
        Set tRs = tStmt.%Execute(tLimit, tPropId, tPropValue, tLowerOdbc)

        ; --- Step 7: collect rows.
        Set tSessions = []
        Set tCount = 0
        While tRs.%Next() {
            Set tEntry = {}
            Do tEntry.%Set("session_id", +tRs.%Get("session_id"), "number")
            Do tEntry.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("time_created")))
            Do tEntry.%Set("source_config_name", tRs.%Get("source_config_name"))
            Do tEntry.%Set("target_config_name", tRs.%Get("target_config_name"))
            Do tEntry.%Set("message_id", tRs.%Get("message_id"))
            Do tSessions.%Push(tEntry)
            Set tCount = tCount + 1
        }

        ; --- Step 8: build envelope.
        Do pResult.structuredContent.%Set("search_table_class", tSearchClass)
        Do pResult.structuredContent.%Set("prop_name", tPropName)
        Do pResult.structuredContent.%Set("prop_value", tPropValue)
        Do pResult.structuredContent.%Set("time_window_hours", tTimeWindow, "number")
        Do pResult.structuredContent.%Set("sessions", tSessions)
        Do pResult.structuredContent.%Set("session_count", tCount, "number")
        If (tCount = 0) {
            Do pResult.structuredContent.%Set("render_strategy", "no_matches")
            Set pResult.content.%Get(0).text = "no sessions matched (" _ tPropName _ "=" _ tPropValue _ ") in last " _ tTimeWindow _ "h via " _ tSearchClass
        } Else {
            Do pResult.structuredContent.%Set("render_strategy", "matched_sessions")
            Set pResult.content.%Get(0).text = tCount _ " session(s) matched (" _ tPropName _ "=" _ tPropValue _ ") in last " _ tTimeWindow _ "h via " _ tSearchClass
        }
        Quit
    }
    Catch ex {
        ; Story 4.7 AC-7 — operator-friendly catch text (Story 4.5 R-4).
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Set pResult.structuredContent = {"render_strategy":"query_error", "error_text":(tErrText)}
        Quit
    }
    Quit tSC
}

}
