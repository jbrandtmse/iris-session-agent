/// <p>Inspection tool — retrieves distilled IRIS-SQL / Interoperability
/// query expertise from the install-seeded knowledge corpus
/// (<CLASS>SessionAgent.Knowledge.Article</CLASS>, seeded by
/// <CLASS>SessionAgent.Knowledge.SeedContent</CLASS>). Shipped by Story
/// 14.1 (FR62) so agents consult dialect/trap knowledge on demand BEFORE
/// authoring SQL instead of carrying it in the cached system prompt.</p>
///
/// <p><b>Tool name:</b> <code>get_query_knowledge</code>. Read-only
/// (<parameter>MutatesState</parameter>=0). Exposed to BOTH agents
/// (registry auto-discovery; decision D1).</p>
///
/// <p><b>Input:</b> <code>{topic (optional enum of the 7 corpus topics),
/// keywords (optional free text), max_results (optional, default 3,
/// hard max 5)}</code>. At least one of <code>topic</code> /
/// <code>keywords</code> is required — both empty returns the canonical
/// validation-failure envelope.</p>
///
/// <p><b>Matching.</b> Keywords are lowercased and split on whitespace
/// (first 8 terms); each term contributes 1 to a relevance score when it
/// LIKE-matches the article's <code>Keywords</code> or <code>Title</code>
/// (UPPER on both sides; parameterized <code>?</code> placeholders only —
/// keyword terms are operator/LLM input). Results are ordered by score
/// descending, then slug. A topic filter (when supplied) restricts the
/// candidate set; topic-only calls return the topic's articles ordered by
/// slug.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{render_strategy:"ok", article_count, truncated, topic,
/// keywords, articles:[{slug, title, body}]}</code>. Total body budget is
/// ~16 KB: when accumulating the next article's body would exceed the
/// budget, the result is cut there and <code>truncated=true</code> (the
/// first article is body-truncated to fit rather than dropped).</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-1-knowledge-corpus-get-query-knowledge-tool.md">Story 14.1</a> — AC-4 source.</li>
/// <li><a href="../../Knowledge/SeedContent.cls">SessionAgent.Knowledge.SeedContent</a> — the corpus.</li>
/// <li><a href="GetClassSource.cls">GetClassSource.cls</a> — registration template (Story 13.1).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetQueryKnowledge Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_query_knowledge";

Parameter Description As %String = "Retrieve distilled InterSystems IRIS SQL and Interoperability trace-query expertise from the seeded knowledge corpus. Consult this BEFORE authoring any SQL against Ens.* / message tables - the IRIS dialect silently returns wrong results for several traps (integer-vs-string filters, case folding, encoded columns). Filter by topic (methodology, dialect, message-model, performance, discovery, reference, cookbook) and/or free-text keywords.";

Parameter MutatesState As %Boolean = 0;

/// <p>Hard cap on the total characters of article body returned in one
/// call (~16 KB budget per AC-4).</p>
Parameter BODYCHARBUDGET As %Integer = 16000;

/// <p>JSON Schema for <code>get_query_knowledge</code>. Both properties
/// optional at the schema level; the at-least-one-of contract is
/// enforced server-side (the locked schema subset cannot express it).
/// The topic enum is a genuinely-static taxonomy (7 fixed corpus
/// topics), so enumerating it here is allowed per the LLM Prompt
/// Construction rule.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "topic": {
                "type": "string",
                "enum": ["methodology", "dialect", "message-model", "performance", "discovery", "reference", "cookbook"],
                "description": "Optional topic filter. One of: methodology (the query-building loop + diagnostic checklist), dialect (IRIS SQL syntax traps: TOP not LIMIT, %ID joins, decode functions, integer-string trap, case/%EXACT, $LIST, streams), message-model (Ens.MessageHeader spine, header-body joins, sessions, request/response correlation), performance (plans, hints, indexing), discovery (finding unknown tables/columns at runtime), reference (Ens.MessageHeader / Ens.Util.Log / HS.* column cards), cookbook (copy-adaptable parameterized recipes)."
            },
            "keywords": {
                "type": "string",
                "description": "Optional free-text search terms (whitespace-separated), matched case-insensitively against each article's keyword list and title - e.g. 'latency self-join' or 'integer status filter zero rows'. Supply topic, keywords, or both; at least one is required."
            },
            "max_results": {
                "type": "integer",
                "description": "Optional maximum number of articles to return. Default 3, hard max 5.",
                "minimum": 1,
                "maximum": 5
            }
        },
        "required": [],
        "additionalProperties": false
    }
}

/// <p>Retrieve up to <code>max_results</code> corpus articles matching
/// the topic and/or keyword criteria. Parameterized SQL only; the
/// clamped integer row limit is the only inlined value. Validation
/// failures return the canonical <code>{isError:1, ...}</code> envelope;
/// SQL prepare/execute failures route through the
/// <CLASS>SessionAgent.Tool.Base</CLASS> centralized gates.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{"articles":[]}}
    Try {
        ; --- Input extraction ---
        Set tTopic = ""
        Set tKeywords = ""
        Set tMax = 3
        If $IsObject($Get(pJsonArgs)) {
            Set tTopic = pJsonArgs.%Get("topic")
            Set tKeywords = pJsonArgs.%Get("keywords")
            If pJsonArgs.%IsDefined("max_results") {
                Set tMax = +pJsonArgs.%Get("max_results")
            }
        }
        Set tTopic = $ZStrip(tTopic, "<>W")
        ; Normalize keyword whitespace: tabs / CR / LF / NUL become spaces
        ; so multiline or tab-separated LLM input still splits into terms
        ; (the tokenizer below splits on the space character only), and a
        ; control-char-only string correctly fails the at-least-one-of
        ; validation. Cap length at 512 so a pathological keywords arg
        ; cannot bloat the envelope / audit row past the body budget's
        ; intent (terms beyond the cap could never all bind anyway - only
        ; the first 8 terms are used).
        Set tKeywords = $Translate(tKeywords, $Char(9) _ $Char(10) _ $Char(13) _ $Char(0), "    ")
        Set tKeywords = $Extract($ZStrip(tKeywords, "<>W"), 1, 512)
        ; Clamp max_results: default 3 when missing or below 1 (the
        ; schema's minimum), hard max 5, fractional values floored.
        If tMax < 1 Set tMax = 3
        If tMax > 5 Set tMax = 5
        Set tMax = tMax \ 1

        ; --- Validation: at least one of topic / keywords ---
        If (tTopic = "") && (tKeywords = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"at least one of topic or keywords is required (topics: methodology, dialect, message-model, performance, discovery, reference, cookbook)"}]}
            Quit
        }

        ; --- Validation: topic must be one of the 7 corpus topics ---
        If tTopic '= "" {
            Set tValidTopics = $ListBuild("methodology", "dialect", "message-model", "performance", "discovery", "reference", "cookbook")
            If '$ListFind(tValidTopics, tTopic) {
                Set pResult = {"isError":(1), "content":[{"type":"text","text":("invalid topic '" _ tTopic _ "' - valid topics: methodology, dialect, message-model, performance, discovery, reference, cookbook")}]}
                Quit
            }
        }

        ; --- Split keywords into terms (lowercase, whitespace-split, max 8) ---
        Set tTermCount = 0
        If tKeywords '= "" {
            Set tNorm = $ZStrip($ZConvert(tKeywords, "L"), "<>=W")
            For i = 1:1:$Length(tNorm, " ") {
                Set tTerm = $Piece(tNorm, " ", i)
                If tTerm = "" Continue
                If tTermCount >= 8 Quit
                Set tTermCount = tTermCount + 1
                Set tTerms(tTermCount) = tTerm
            }
        }

        ; --- Build parameterized SQL ---
        ; Keyword mode scores each term: +1 when the term LIKE-matches
        ; UPPER(Keywords) or UPPER(Title). Score computed in an inner
        ; subquery (a SELECT alias cannot be referenced in WHERE/ORDER BY
        ; directly - the corpus's own groupby-restrictions trap), filtered
        ; and ordered outside. tMax is a clamped integer, safe to inline;
        ; all operator/LLM-supplied strings bind via ? placeholders.
        Set tParmCount = 0
        If tTermCount > 0 {
            Set tScore = ""
            For i = 1:1:tTermCount {
                If i > 1 Set tScore = tScore _ " + "
                Set tScore = tScore _ "(CASE WHEN UPPER(Keywords) LIKE ? OR UPPER(Title) LIKE ? THEN 1 ELSE 0 END)"
                Set tParmCount = tParmCount + 1
                Set tParms(tParmCount) = "%" _ $ZConvert(tTerms(i), "U") _ "%"
                Set tParmCount = tParmCount + 1
                Set tParms(tParmCount) = "%" _ $ZConvert(tTerms(i), "U") _ "%"
            }
            Set tInner = "SELECT Slug, Title, Body, " _ tScore _ " AS Score FROM SessionAgent_Knowledge.Article"
            If tTopic '= "" {
                Set tInner = tInner _ " WHERE %EXACT(Topic) = ?"
                Set tParmCount = tParmCount + 1
                Set tParms(tParmCount) = tTopic
            }
            Set tSql = "SELECT TOP " _ tMax _ " Slug, Title, Body FROM (" _ tInner _ ") t WHERE t.Score > 0 ORDER BY t.Score DESC, t.Slug"
        } Else {
            ; Topic-only mode.
            Set tSql = "SELECT TOP " _ tMax _ " Slug, Title, Body FROM SessionAgent_Knowledge.Article WHERE %EXACT(Topic) = ? ORDER BY Slug"
            Set tParmCount = 1
            Set tParms(1) = tTopic
        }

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCp = tStmt.%Prepare(tSql)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) Quit
        Set tParms = tParmCount
        Set tRS = tStmt.%Execute(tParms...)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit

        ; --- Accumulate articles under the ~16 KB body budget ---
        Set tArticles = []
        Set tUsed = 0
        Set tTruncated = 0
        While tRS.%Next() {
            Set tSlug = tRS.%Get("Slug")
            Set tTitle = tRS.%Get("Title")
            Set tBody = tRS.%Get("Body")
            Set tLen = $Length(tBody)
            If (tUsed + tLen) > ..#BODYCHARBUDGET {
                Set tTruncated = 1
                If tArticles.%Size() = 0 {
                    ; First article alone exceeds the budget - return it
                    ; body-truncated rather than returning nothing.
                    Set tBody = $Extract(tBody, 1, ..#BODYCHARBUDGET)
                    Do tArticles.%Push({"slug":(tSlug), "title":(tTitle), "body":(tBody)})
                }
                Quit
            }
            Set tUsed = tUsed + tLen
            Do tArticles.%Push({"slug":(tSlug), "title":(tTitle), "body":(tBody)})
        }

        ; --- Success envelope ---
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Do pResult.structuredContent.%Set("topic", tTopic)
        Do pResult.structuredContent.%Set("keywords", tKeywords)
        Do pResult.structuredContent.%Set("articles", tArticles)
        Do pResult.structuredContent.%Set("article_count", tArticles.%Size(), "number")
        Do pResult.structuredContent.%Set("truncated", tTruncated, "boolean")
        Set tCriteria = ""
        If tTopic '= "" Set tCriteria = "topic=" _ tTopic
        If tKeywords '= "" Set tCriteria = tCriteria _ $Select(tCriteria'="":" ", 1:"") _ "keywords='" _ tKeywords _ "'"
        Set pResult.content.%Get(0).text = "get_query_knowledge: " _ tArticles.%Size() _ " article(s) for " _ tCriteria _ $Select(tTruncated:" [truncated to fit body budget]", 1:"")
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
