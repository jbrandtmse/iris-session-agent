/// <p>Inspection tool — reads back the agent-authored learned schema
/// notes (<CLASS>SessionAgent.Knowledge.SchemaNote</CLASS>) for the
/// ACTIVE namespace, most-recently-verified first (Epic 14 FR63 /
/// Story 14.4). Each returned note carries <code>age_days</code> so the
/// LLM sees staleness and re-verifies old facts instead of trusting them
/// blindly — the FR63 retrieval contract.</p>
///
/// <p><b>Tool name:</b> <code>get_schema_notes</code>. Read-only
/// (<parameter>MutatesState</parameter>=0). Exposed to BOTH agents
/// (registry auto-discovery).</p>
///
/// <p><b>Namespace from CallerContext (NFR-S6).</b> The notes are scoped
/// to <property>pCallerCtx.Namespace</property> — never an LLM argument —
/// so retrieval cannot reach across namespaces. The optional
/// <code>subject_fragment</code> IS LLM input and binds via a
/// parameterized <code>LIKE</code> placeholder only.</p>
///
/// <p><b>age_days semantics.</b> Computed server-side as the UTC
/// calendar-day delta between <code>$ZTimeStamp</code> and the row's
/// <property>VerifiedAt</property> (both UTC — no timezone skew). A note
/// saved today reads <code>age_days=0</code>; clamped at 0 for
/// clock-skew defensiveness.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-4-learned-schema-notes-digest-injection.md">Story 14.4</a> — AC-4 source.</li>
/// <li><a href="GetQueryKnowledge.cls">GetQueryKnowledge.cls</a> — agent-owned-table retrieval template (Story 14.1).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetSchemaNotes Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_schema_notes";

Parameter Description As %String = "Read the schema notes previously saved for the active namespace (facts recorded by save_schema_note in earlier conversations), most recently verified first. Each note carries age_days - treat notes with large age_days as potentially stale and re-verify before relying on them. Optional subject_fragment substring-filters by subject.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. All properties optional — empty args
/// returns the namespace's notes with the default page size.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "subject_fragment": {"type": "string", "description": "Optional case-insensitive substring filter on the note subject (e.g. 'order-id')."},
            "max_results": {"type": "integer", "description": "Optional maximum number of notes to return. Default 10, max 50.", "minimum": 1, "maximum": 50}
        },
        "required": [],
        "additionalProperties": false
    }
}

/// <p>Return up to <code>max_results</code> notes for the active
/// namespace ordered <code>VerifiedAt DESC</code>. Empty result is the
/// ok-envelope (no notes saved yet is not an error). Parameterized SQL
/// only; the clamped integer row limit is the only inlined value. SQL
/// prepare/execute failures route through the
/// <CLASS>SessionAgent.Tool.Base</CLASS> centralized gates.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"notes":[]}}
    Try {
        ; --- Input extraction ---
        Set tFragment = ""
        Set tMax = 10
        If $IsObject($Get(pJsonArgs)) {
            Set tFragment = pJsonArgs.%Get("subject_fragment")
            If pJsonArgs.%IsDefined("max_results") {
                Set tMaxRaw = pJsonArgs.%Get("max_results")
                ; Type guard (Story 14.4 review fix): a nested
                ; object/array %Get returns an OREF — treat as missing
                ; (default applies via the clamp below).
                Set tMax = $Select($IsObject(tMaxRaw): 0, 1: +tMaxRaw)
            }
        }
        ; Type guard (Story 14.4 review fix): OREF fragment → missing.
        If $IsObject(tFragment) Set tFragment = ""
        Set:tFragment=$$$NULLOREF tFragment = ""
        ; Control-char normalization (Story 14.1 keyword precedent) +
        ; defensive length cap matching the Subject column.
        Set tFragment = $Translate(tFragment, $Char(9) _ $Char(10) _ $Char(13) _ $Char(0), "    ")
        Set tFragment = $Extract($ZStrip(tFragment, "<>W"), 1, 256)
        ; Clamp max_results: default 10 when missing or below 1, hard
        ; max 50, fractional values floored.
        If tMax < 1 Set tMax = 10
        If tMax > 50 Set tMax = 50
        Set tMax = tMax \ 1

        ; --- Namespace from CallerContext (NFR-S6) ---
        Set tNamespace = ""
        If $IsObject($Get(pCallerCtx)) Set tNamespace = pCallerCtx.Namespace
        If tNamespace = $Char(0) Set tNamespace = ""
        If tNamespace = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"get_schema_notes requires a populated CallerContext.Namespace (trust-boundary contract)"}]}
            Quit
        }

        ; --- Parameterized SQL — tMax is a clamped integer (safe to
        ; inline); namespace + fragment bind via ? placeholders. Explicit
        ; AS aliases avoid the %EXACT()-renames-the-column trap (project
        ; rule §"%EXACT() in SELECT Changes Column Aliases").
        Set tSql = "SELECT TOP " _ tMax _ " %EXACT(Subject) AS sub, %EXACT(Body) AS bod, VerifiedAt AS va, %EXACT(SourceAgent) AS sa" _
            " FROM SessionAgent_Knowledge.SchemaNote WHERE %EXACT(Namespace) = ?"
        If tFragment '= "" {
            Set tSql = tSql _ " AND UPPER(Subject) LIKE ? ESCAPE '\'"
        }
        Set tSql = tSql _ " ORDER BY VerifiedAt DESC, %EXACT(Subject) ASC"

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare(tSql)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit
        If tFragment '= "" {
            ; LIKE-metacharacter escaping (Story 14.4 review fix): the
            ; documented contract is a SUBSTRING filter, so '%' / '_' in
            ; the fragment must match literally, not as wildcards.
            Set tEscaped = $Replace(tFragment, "\", "\\")
            Set tEscaped = $Replace(tEscaped, "%", "\%")
            Set tEscaped = $Replace(tEscaped, "_", "\_")
            Set tRS = tStmt.%Execute(tNamespace, "%" _ $ZConvert(tEscaped, "U") _ "%")
        } Else {
            Set tRS = tStmt.%Execute(tNamespace)
        }
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- Accumulate notes with age_days staleness (FR63) ---
        Set tNotes = []
        Set tNowDay = $Piece($ZTimeStamp, ",", 1)
        While tRS.%Next() {
            Set tVa = tRS.%Get("va")
            Set tAgeDays = ""
            If tVa '= "" {
                Set tAgeDays = tNowDay - $Piece($ZDateTimeH(tVa, 3), ",", 1)
                If tAgeDays < 0 Set tAgeDays = 0
            }
            Set tEntry = {}
            Do tEntry.%Set("subject", tRS.%Get("sub"))
            Do tEntry.%Set("note", tRS.%Get("bod"))
            Do tEntry.%Set("verified_at", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tVa))
            Do tEntry.%Set("age_days", +tAgeDays, "number")
            Do tEntry.%Set("source_agent", tRS.%Get("sa"))
            Do tNotes.%Push(tEntry)
        }
        ; Story 14.2 post-loop fetch-fault gate (cr-13-3 sibling) — a
        ; mid-fetch fault flips %SQLCODE negative after %Next() returns 0.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- Success envelope (empty result is ok-shape per AC-4) ---
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Do pResult.structuredContent.%Set("namespace", tNamespace)
        Do pResult.structuredContent.%Set("subject_fragment", tFragment)
        Do pResult.structuredContent.%Set("notes", tNotes)
        Do pResult.structuredContent.%Set("count", tNotes.%Size(), "number")
        If tNotes.%Size() = 0 {
            Set pResult.content.%Get(0).text = "No schema notes saved for namespace '" _ tNamespace _ "'" _ $Select(tFragment '= "": " matching '" _ tFragment _ "'", 1: "") _ " yet. Use save_schema_note to record discovered facts."
        } Else {
            Set pResult.content.%Get(0).text = "get_schema_notes: " _ tNotes.%Size() _ " note(s) for namespace '" _ tNamespace _ "'" _ $Select(tFragment '= "": " matching '" _ tFragment _ "'", 1: "") _ " (most recently verified first; check age_days for staleness)."
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

}
