/// <p>Schema-discovery tool — authoritative description of a compiled
/// persistent class's SQL projection: <code>schema.table</code> mapping,
/// columns + datatypes, indexes, extent classes (self + primary-chain
/// descendants), collection child tables vs embedded collections, and an
/// optional <code>AdditionalInfo</code> key census (FR61, Story 14.2
/// AC-2). The agent runs this BEFORE authoring SQL against a body table
/// so table/column names are discovered, never hallucinated.</p>
///
/// <p><b>Tool name:</b> <code>describe_message_class</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>SQL injection defense — all 4 layers</b> (project rule §"SQL
/// Injection Defense in ObjectScript"): (1) schema description names the
/// expected format; (2) server-side <code>$Match</code> regex
/// <code>^[A-Za-z%][A-Za-z0-9%._]*$</code>; (3) <code>class_name</code>
/// is always bound as a <code>?</code> placeholder — the only spliced
/// identifiers are catalog-derived (<code>SqlSchemaName</code>/child
/// table from <CLASS>%Dictionary.CompiledClass</CLASS>, NOT operator
/// input) and are still regex-gated before splicing (defense in depth);
/// (4) reviewer confirms 1–3.</p>
///
/// <p><b>Subclass strategy (Task 0 probe, 2026-06-11).</b> Naive
/// <code>UPPER(Super) [ UPPER('Ens.MessageHeader')</code> false-positives
/// on the <code>Ens.MessageHeaderBase</code> substring. This tool matches
/// the tilde-delimited <code>PrimarySuper</code> chain instead:
/// <code>UPPER(PrimarySuper) [ '~CLASSNAME~'</code> — delimiter-safe and
/// multi-level. It enumerates the <b>extent classes</b> (self + all
/// primary-chain descendants — the classes whose rows can appear in this
/// table's polymorphic extent). Limitation: descendants reaching the
/// class only through a secondary (multiple-inheritance) superclass are
/// not enumerated; message-body hierarchies use single primary
/// inheritance.</p>
///
/// <p><b>Embedded vs projected collections (Epic 13 Pattern B).</b> A
/// list/array property only sometimes projects a child SQL table
/// (<code>&lt;Table&gt;_&lt;PropName&gt;</code>); list-of-serial and
/// $LIST-storage collections stay embedded with NO SQL table. Ground
/// truth is <CLASS>INFORMATION_SCHEMA.TABLES</CLASS> existence, so each
/// collection property carries <code>projects_child_table</code> +
/// <code>child_table</code> (empty = embedded; not queryable as a
/// table).</p>
///
/// <p><b>Output budget.</b> structuredContent is trimmed toward ≈16 KB —
/// oversize arrays are cut and <code>truncated:true</code> is set.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-2-schema-discovery-tools.md">Story 14.2</a> AC-2 — AC source.</li>
/// <li><a href="../../../../docs/iris-query-guide/04-schema-discovery.md">docs/iris-query-guide/04-schema-discovery.md</a> §"Class → SQL table mapping (authoritative)".</li>
/// <li><a href="../../../../irislib/%25Dictionary/CompiledClass.cls">irislib/%Dictionary/CompiledClass.cls</a> — Super (comma-list, direct) vs PrimarySuper (tilde chain) semantics.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.DescribeMessageClass Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "describe_message_class";

Parameter Description As %String = "Describe a compiled persistent class's SQL projection: authoritative schema.table mapping, columns with datatypes, indexes, extent classes (subclasses sharing the table), collection child tables vs embedded collections, and an AdditionalInfo key census when present. Run this before writing SQL against any class's table.";

Parameter MutatesState As %Boolean = 0;

/// <p>Cap on extent-class enumeration rows.</p>
Parameter MAXEXTENTCLASSES As %Integer = 100;

/// <p>Cap on AdditionalInfo key-census rows.</p>
Parameter MAXADDITIONALINFOKEYS As %Integer = 25;

/// <p>Approximate structuredContent character budget.</p>
Parameter RESULTCHARBUDGET As %Integer = 16384;

/// <p>JSON Schema — single required <code>class_name</code>. Layer (1)
/// of the SQL-injection defense lives in the description.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "class_name": {
                "type": "string",
                "description": "Full package-qualified class name to describe (e.g. 'SessionAgent.Sample.Msg.OrderRequest' or 'Ens.MessageHeader'). Pass the class name only — do not include method names. Case-insensitive lookup against the compiled-class catalog."
            }
        },
        "required": ["class_name"],
        "additionalProperties": false
    }
}

/// <p>Validate, resolve the class via
/// <CLASS>%Dictionary.CompiledClass</CLASS>, then assemble the
/// description envelope. Non-existent or non-persistent classes return
/// the success-shape <code>render_strategy:"class_not_found"</code>
/// envelope — class absence is operator-observable state, not a fault.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Extract + validate class_name ---
        Set tClassName = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tClassName = pJsonArgs.%Get("class_name")
            Set:tClassName=$$$NULLOREF tClassName = ""
        }
        If tClassName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing class_name"}]}
            Quit
        }
        ; Layer (2) — server-side $Match regex validation.
        If '$Match(tClassName, "^[A-Za-z%][A-Za-z0-9%._]*$") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid class_name format — must be a valid ObjectScript class name (e.g. 'SessionAgent.Sample.Msg.OrderRequest')"}]}
            Quit
        }

        ; --- Authoritative class → table lookup (UPPER both sides; Layer 3: ? binding) ---
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare("SELECT %EXACT(Name), %EXACT(SqlSchemaName), %EXACT(SqlTableName), %EXACT(ClassType) FROM %Dictionary.CompiledClass WHERE UPPER(Name) = UPPER(?)")
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit
        Set tRS = tStmt.%Execute(tClassName)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit
        Set tFound = 0
        Set (tCanonicalName, tSchema, tTable, tClassType) = ""
        If tRS.%Next() {
            Set tFound = 1
            ; Positional reads — %EXACT() in SELECT renames columns.
            Set tCanonicalName = tRS.%GetData(1)
            Set tSchema = tRS.%GetData(2)
            Set tTable = tRS.%GetData(3)
            Set tClassType = tRS.%GetData(4)
        }
        ; Fetch-time fault gate — a %Next() error must not masquerade as
        ; class_not_found (review fix 14.2).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- class_not_found envelope (non-existent OR non-persistent) ---
        If ('tFound) || (tClassType '= "persistent") {
            Do pResult.structuredContent.%Set("class_name", $Select(tFound:tCanonicalName, 1:tClassName))
            Do pResult.structuredContent.%Set("class_exists", tFound, "boolean")
            If tFound Do pResult.structuredContent.%Set("class_type", tClassType)
            Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
            If 'tFound {
                Set pResult.content.%Get(0).text = "class not found: " _ tClassName _ " (not compiled in this namespace)"
            } Else {
                Set pResult.content.%Get(0).text = "class " _ tCanonicalName _ " exists but is not persistent (ClassType='" _ tClassType _ "') — it has no SQL table projection"
            }
            Quit
        }

        ; --- (a) schema.table mapping ---
        Do pResult.structuredContent.%Set("class_name", tCanonicalName)
        Do pResult.structuredContent.%Set("class_exists", 1, "boolean")
        Do pResult.structuredContent.%Set("class_type", tClassType)
        Do pResult.structuredContent.%Set("schema_name", tSchema)
        Do pResult.structuredContent.%Set("table_name", tTable)
        Do pResult.structuredContent.%Set("qualified_table", tSchema _ "." _ tTable)

        ; --- (b) columns; (c) indexes; (d) extent classes; (e) collections; (f) AdditionalInfo census ---
        If ..AppendColumns(pResult, tSchema, tTable) Quit
        If ..AppendIndexes(pResult, tSchema, tTable) Quit
        If ..AppendExtentClasses(pResult, tCanonicalName) Quit
        Set tAddlChildTable = ""
        If ..AppendCollections(pResult, tCanonicalName, tSchema, tTable, .tAddlChildTable) Quit
        If tAddlChildTable '= "" {
            If ..AppendAdditionalInfoCensus(pResult, tSchema, tAddlChildTable) Quit
        }

        ; --- ≈16 KB budget with truncated marker ---
        Do ..ApplyCharBudget(pResult)
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Set tColCount = pResult.structuredContent.%Get("columns").%Size()
        Set tIdxCount = pResult.structuredContent.%Get("indexes").%Size()
        ; Subclass count from the pre-trim field, NOT from the post-trim
        ; extent_classes array size — ApplyCharBudget may have cut the
        ; array, and an empty extent would render "-1" (review fix 14.2).
        Set pResult.content.%Get(0).text = tCanonicalName _ " -> " _ tSchema _ "." _ tTable _ " — " _ tColCount _ " column(s), " _ tIdxCount _ " index(es), " _ +pResult.structuredContent.%Get("subclass_count") _ " subclass(es) in extent."
        If tColCount = 0 {
            ; A projected table always has at least the ID column — zero
            ; INFORMATION_SCHEMA columns means the catalog row exists but
            ; the table is not live/queryable (NoExtent, suppressed
            ; projection). Flag it so the agent does not author SQL
            ; against a non-queryable name (review fix 14.2).
            Do pResult.structuredContent.%Set("sql_projection_found", 0, "boolean")
            Set pResult.content.%Get(0).text = pResult.content.%Get(0).text _ " WARNING: no INFORMATION_SCHEMA columns found — the projected table may not exist or be queryable in this namespace."
        }
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

/// <p>(b) — columns + datatypes via INFORMATION_SCHEMA.COLUMNS. Returns
/// 1 when pResult was mutated to an error envelope (caller Quits).</p>
ClassMethod AppendColumns(pResult As %DynamicObject, pSchema As %String, pTable As %String) As %Boolean
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare("SELECT %EXACT(COLUMN_NAME), %EXACT(DATA_TYPE), %EXACT(IS_NULLABLE) FROM INFORMATION_SCHEMA.COLUMNS WHERE UPPER(TABLE_SCHEMA) = UPPER(?) AND UPPER(TABLE_NAME) = UPPER(?) ORDER BY ORDINAL_POSITION")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit 1
    Set tRS = tStmt.%Execute(pSchema, pTable)
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Set tCols = []
    While tRS.%Next() {
        Set tCol = {}
        Do tCol.%Set("name", tRS.%GetData(1))
        Do tCol.%Set("type", tRS.%GetData(2))
        Do tCol.%Set("nullable", $Select(tRS.%GetData(3)="YES":1, 1:0), "boolean")
        Do tCols.%Push(tCol)
    }
    ; Fetch-time fault gate (review fix 14.2) — partial rows must not
    ; ship inside an ok envelope.
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Do pResult.structuredContent.%Set("columns", tCols)
    Quit 0
}

/// <p>(c) — indexes via INFORMATION_SCHEMA.INDEXES, aggregated to one
/// entry per index name with an ordered column list.</p>
ClassMethod AppendIndexes(pResult As %DynamicObject, pSchema As %String, pTable As %String) As %Boolean
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare("SELECT %EXACT(INDEX_NAME), %EXACT(COLUMN_NAME), PRIMARY_KEY, NON_UNIQUE FROM INFORMATION_SCHEMA.INDEXES WHERE UPPER(TABLE_SCHEMA) = UPPER(?) AND UPPER(TABLE_NAME) = UPPER(?) ORDER BY INDEX_NAME, ORDINAL_POSITION")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit 1
    Set tRS = tStmt.%Execute(pSchema, pTable)
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Set tIndexes = []
    Set tCurrent = ""
    While tRS.%Next() {
        Set tIdxName = tRS.%GetData(1)
        If ('$IsObject(tCurrent)) || (tCurrent.%Get("name") '= tIdxName) {
            Set tCurrent = {}
            Do tCurrent.%Set("name", tIdxName)
            Do tCurrent.%Set("columns", [])
            Do tCurrent.%Set("primary_key", +tRS.%GetData(3), "boolean")
            Do tCurrent.%Set("unique", '(+tRS.%GetData(4)), "boolean")
            Do tIndexes.%Push(tCurrent)
        }
        Do tCurrent.%Get("columns").%Push(tRS.%GetData(2))
    }
    ; Fetch-time fault gate (review fix 14.2).
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Do pResult.structuredContent.%Set("indexes", tIndexes)
    Quit 0
}

/// <p>(d) — extent classes via the tilde-delimited PrimarySuper chain
/// (self + primary-chain descendants; see class banner for the
/// substring-trap rationale). UPPER() both sides — the bound token is
/// pre-uppercased in ObjectScript.</p>
ClassMethod AppendExtentClasses(pResult As %DynamicObject, pClassName As %String) As %Boolean
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare("SELECT TOP ? %EXACT(Name) FROM %Dictionary.CompiledClass WHERE UPPER(PrimarySuper) [ ? ORDER BY %EXACT(Name)")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit 1
    Set tChainToken = "~" _ $ZConvert(pClassName, "U") _ "~"
    Set tRS = tStmt.%Execute(..#MAXEXTENTCLASSES + 1, tChainToken)
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Set tExtent = []
    Set tOverflow = 0
    While tRS.%Next() {
        If tExtent.%Size() >= ..#MAXEXTENTCLASSES { Set tOverflow = 1 Quit }
        Do tExtent.%Push(tRS.%GetData(1))
    }
    ; Fetch-time fault gate (review fix 14.2).
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Do pResult.structuredContent.%Set("extent_classes", tExtent)
    Do pResult.structuredContent.%Set("subclass_count", $Select(tExtent.%Size()>0:tExtent.%Size()-1, 1:0), "number")
    If tOverflow Do pResult.structuredContent.%Set("extent_classes_truncated", 1, "boolean")
    Quit 0
}

/// <p>(e) — collection properties + projected child tables. Ground truth
/// for projection is INFORMATION_SCHEMA.TABLES existence of
/// <code>&lt;Table&gt;_&lt;PropNameSans%&gt;</code> (Epic 13 Pattern B:
/// embedded serial/$LIST collections have NO SQL table). Also returns
/// the AdditionalInfo child-table name via <var>pAddlChildTable</var>
/// when the class has an array property named AdditionalInfo whose
/// child table is projected.</p>
ClassMethod AppendCollections(pResult As %DynamicObject, pClassName As %String, pSchema As %String, pTable As %String, Output pAddlChildTable As %String) As %Boolean
{
    Set pAddlChildTable = ""
    ; Candidate child tables prefixed <Table>_ in the class's schema —
    ; used as an existence LOOKUP only. The published child_tables roster
    ; is built from the per-property matches below, so an unrelated table
    ; that merely shares the <Table>_ prefix (e.g. a sibling class with an
    ; explicit SqlTableName) is never presented as this class's child
    ; table (review fix 14.2 — ownership verification).
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare("SELECT %EXACT(TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES WHERE UPPER(TABLE_SCHEMA) = UPPER(?) AND UPPER(TABLE_NAME) %STARTSWITH UPPER(?) ORDER BY TABLE_NAME")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit 1
    Set tRS = tStmt.%Execute(pSchema, pTable _ "_")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Set tChildLookup = {}
    While tRS.%Next() {
        Set tChild = tRS.%GetData(1)
        Do tChildLookup.%Set($ZConvert(tChild, "U"), tChild)
    }
    ; Fetch-time fault gate (review fix 14.2).
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1

    ; Collection properties (list/array) from the compiled-property catalog.
    ; NOTE — deliberate exception to the "UPPER() both sides on %Dictionary
    ; name comparisons" rule: pClassName here is the CANONICAL name already
    ; resolved (case-exact) from %Dictionary.CompiledClass in Invoke(), not
    ; operator/LLM input, so the casing-varies rationale does not apply.
    ; UPPER(parent) defeats the parent index and forces a full scan of the
    ; property catalog — measured 8.9s vs <0.1s on the 2026-06-11 HS dev
    ; install (the scan dominated a 10.9s tool dispatch and tripped the
    ; roundtrip matrix perf gate in full-package sweep run 176). Exact
    ; `parent = ?` is index-backed and correctness-equivalent for a
    ; catalog-derived canonical name.
    Set tStmt2 = ##class(%SQL.Statement).%New()
    Set tSCp2 = tStmt2.%Prepare("SELECT %EXACT(Name), %EXACT(Collection), %EXACT(Type) FROM %Dictionary.CompiledProperty WHERE parent = ? AND Collection IS NOT NULL AND Collection <> '' ORDER BY %EXACT(Name)")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp2, ..#ToolName) Quit 1
    Set tRS2 = tStmt2.%Execute(pClassName)
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS2, ..#ToolName) Quit 1
    Set tCollections = []
    Set tChildTables = []
    Set tHasAddl = 0
    While tRS2.%Next() {
        Set tPropName = tRS2.%GetData(1)
        Set tCollection = tRS2.%GetData(2)
        Set tType = tRS2.%GetData(3)
        ; Default child-table projection name: <Table>_<PropName> with
        ; the % prefix stripped (verified live: %MessagesReceived ->
        ; OrderRouter_MessagesReceived).
        Set tExpected = pTable _ "_" _ $Translate(tPropName, "%", "")
        Set tActual = tChildLookup.%Get($ZConvert(tExpected, "U"))
        Set:tActual=$$$NULLOREF tActual = ""
        Set tEntry = {}
        Do tEntry.%Set("name", tPropName)
        Do tEntry.%Set("collection", tCollection)
        Do tEntry.%Set("element_type", tType)
        Do tEntry.%Set("projects_child_table", (tActual '= ""), "boolean")
        Do tEntry.%Set("child_table", tActual)
        Do tCollections.%Push(tEntry)
        If tActual '= "" Do tChildTables.%Push(tActual)
        If (tPropName = "AdditionalInfo") && (tCollection = "array") && (tActual '= "") {
            Set tHasAddl = 1
            Set pAddlChildTable = tActual
        }
    }
    ; Fetch-time fault gate (review fix 14.2).
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS2, ..#ToolName) Quit 1
    Do pResult.structuredContent.%Set("child_tables", tChildTables)
    Do pResult.structuredContent.%Set("collection_properties", tCollections)
    Do pResult.structuredContent.%Set("has_additional_info", tHasAddl, "boolean")
    Quit 0
}

/// <p>(f) — TOP-bounded key census from the projected AdditionalInfo
/// child table. The schema/table identifiers are catalog-derived (never
/// operator input) and are still regex-gated before splicing into the
/// SQL text — identifiers cannot be bound as <code>?</code> parameters.</p>
ClassMethod AppendAdditionalInfoCensus(pResult As %DynamicObject, pSchema As %String, pChildTable As %String) As %Boolean
{
    ; Defense in depth: refuse identifier shapes outside the catalog norm.
    ; The skip flag distinguishes "census refused" from "table has zero
    ; keys" so the agent never concludes AdditionalInfo is unused when
    ; the tool actually declined to look (review fix 14.2).
    If ('$Match(pSchema, "^[A-Za-z%][A-Za-z0-9_]*$")) || ('$Match(pChildTable, "^[A-Za-z%][A-Za-z0-9_]*$")) {
        Do pResult.structuredContent.%Set("additional_info_keys", [])
        Do pResult.structuredContent.%Set("additional_info_census_skipped", 1, "boolean")
        Quit 0
    }
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSCp = tStmt.%Prepare("SELECT TOP ? %EXACT(element_key), COUNT(*) FROM " _ pSchema _ "." _ pChildTable _ " GROUP BY %EXACT(element_key) ORDER BY COUNT(*) DESC")
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit 1
    Set tRS = tStmt.%Execute(..#MAXADDITIONALINFOKEYS)
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Set tKeys = []
    While tRS.%Next() {
        Set tEntry = {}
        Do tEntry.%Set("key", tRS.%GetData(1))
        Do tEntry.%Set("count", +tRS.%GetData(2), "number")
        Do tKeys.%Push(tEntry)
    }
    ; Fetch-time fault gate (review fix 14.2).
    If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit 1
    Do pResult.structuredContent.%Set("additional_info_keys", tKeys)
    Quit 0
}

/// <p>Trim oversize arrays toward the ≈16 KB structuredContent budget
/// and set <code>truncated</code>. Trim order: extent_classes →
/// columns → indexes → child_tables → collection_properties →
/// additional_info_keys. If the JSON still exceeds the budget after the
/// plan is exhausted (e.g. one very large non-array value),
/// <code>truncated</code> is still set so the budget contract is never
/// silently violated (review fix 14.2).</p>
ClassMethod ApplyCharBudget(pResult As %DynamicObject)
{
    Set tTruncated = 0
    If $Length(pResult.structuredContent.%ToJSON()) > ..#RESULTCHARBUDGET {
        Set tPlan = $ListBuild($ListBuild("extent_classes", 20), $ListBuild("columns", 60), $ListBuild("indexes", 20), $ListBuild("child_tables", 20), $ListBuild("collection_properties", 20), $ListBuild("additional_info_keys", 10))
        Set tPtr = 0
        While $ListNext(tPlan, tPtr, tStep) {
            If $Length(pResult.structuredContent.%ToJSON()) <= ..#RESULTCHARBUDGET Quit
            Set tField = $List(tStep, 1)
            Set tCap = $List(tStep, 2)
            Set tArr = pResult.structuredContent.%Get(tField)
            If '$IsObject(tArr) Continue
            If tArr.%Size() <= tCap Continue
            Set tNew = []
            Set tIter = tArr.%GetIterator()
            While tIter.%GetNext(.tKey, .tVal) {
                If tNew.%Size() >= tCap Quit
                Do tNew.%Push(tVal)
            }
            Do pResult.structuredContent.%Set(tField, tNew)
            Set tTruncated = 1
        }
        ; Plan exhausted but still over budget — the contract must not be
        ; silently violated (review fix 14.2).
        If $Length(pResult.structuredContent.%ToJSON()) > ..#RESULTCHARBUDGET Set tTruncated = 1
    }
    Do pResult.structuredContent.%Set("truncated", tTruncated, "boolean")
    Quit
}

}
