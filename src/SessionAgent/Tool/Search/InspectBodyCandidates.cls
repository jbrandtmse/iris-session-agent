/// <p>Search tool — two-stage indexed-prefilter + body-content inspection
/// for sessions whose body text matches a pattern that ISN'T indexed
/// (e.g., a diagnosis code substring, a free-text fragment in an HL7
/// segment). <b>Most-complex Story 8.x tool</b> — implements the FR18 +
/// architecture §"Innovation: Two-stage indexed-prefilter" pattern that
/// keeps body-content search safe at production scale despite the
/// ten-million-row Ens.MessageHeader extent (NFR-P3).</p>
///
/// <p><b>Tool name:</b> <code>inspect_body_candidates</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>The two-stage pattern:</b></p>
/// <ol>
/// <li><b>Stage 1 — indexed prefilter (≤50 candidates).</b> Narrow the
/// Ens.MessageHeader extent via an indexed-column predicate
/// (<code>prefilter_indexed_column</code> from
/// <code>{Status, SourceConfigName, TargetConfigName,
/// MessageBodyClassName}</code>) AND a bounded
/// <code>TimeCreated &gt; ?</code> window (default 24h). Returns at
/// most <code>candidate_cap</code> rows (≤50 per NFR-P3).</li>
/// <li><b>Stage 2 — body inspection.</b> For each candidate, invoke
/// the Epic 4 <CLASS>SessionAgent.Tool.Inspection.GetMessageBody</CLASS>
/// 9-step body-class dispatch ladder via direct
/// <method>Invoke</method> call (architecture §"G2 dispatch-ladder
/// extraction" — direct call until/unless the ladder is extracted to
/// <code>SessionAgent.Body.DispatchLadder</code>). Apply the
/// <code>pattern</code> against the rendered <code>body_repr</code>
/// text. Drop candidates whose body cannot be rendered (graceful per
/// AC-6).</li>
/// </ol>
///
/// <p><b>Pattern matching modes (AC-5).</b></p>
/// <ul>
/// <li><b>Substring mode (default,
/// <code>pattern_is_regex=false</code>).</b> Case-insensitive substring
/// search via <code>$Find</code> after <code>$ZConvert(..., "U")</code>
/// upper-folding both sides — match if <code>$Find &gt; 0</code>.</li>
/// <li><b>Regex mode (<code>pattern_is_regex=true</code>).</b>
/// <b>PCRE-flavor regex via <CLASS>%Regex.Matcher</CLASS></b> (ICU
/// engine; documented at
/// <a href="https://unicode-org.github.io/icu/userguide/strings/regexp.html">ICU
/// regex docs</a>). Operator-friendly choice — operators are far more
/// likely to know PCRE than InterSystems pattern syntax. The regex is
/// compiled once per Invoke and reused across all candidates.</li>
/// </ul>
///
/// <p><b>NFR-P3 hard cap.</b> <code>candidate_cap</code> defaults to
/// <b>50</b> and is HARD-capped at 50. A caller-supplied value &gt; 50
/// is rejected at validation time with a structured error envelope
/// (<code>errorCode="CandidateCapTooLarge"</code>) — the cap is a
/// safety bound, not a soft hint, because every candidate inspected
/// triggers a body-class dispatch which can cost hundreds of
/// milliseconds for HL7/XML/JSON renders.</p>
///
/// <p><b>Graceful per-candidate degradation (AC-6).</b> If the inner
/// <method>GetMessageBody.Invoke</method> returns
/// <code>render_strategy</code> in
/// <code>{header_not_found, no_body, body_not_found, dispatch_error,
/// json_adaptor_error, xml_adaptor_error}</code>, the candidate is
/// silently DROPPED from the matches list (NOT propagated as an error
/// to the overall envelope). The candidate IS still counted in
/// <code>candidates_inspected</code> so the operator sees how many
/// rows the tool attempted vs. how many actually matched.</p>
///
/// <p><b>GetIndexedLeadColumns() static fallback.</b> The actual
/// prefilter column is per-call dynamic (operator chooses one of 4
/// enum-constrained values). The Story 8.2 invariant test inspects
/// the classmethod return statically — so this method returns the
/// static fallback <code>["Status"]</code> (the most-common-case
/// value), which is in the documented indexed set. Mirrors Story 8.5's
/// <code>"PropValue"</code> canonical-placeholder pattern; the
/// per-call dynamic value is reflected in the envelope's
/// <code>indexed_lead_column</code> field, not in the classmethod
/// return.</p>
///
/// <p><b>Indexed lead column (AC-1).</b>
/// <method>GetIndexedLeadColumns</method> returns
/// <code>["Status"]</code> as the static placeholder. The actual
/// per-call indexed column is reflected in
/// <code>structuredContent.indexed_lead_column</code> (echoes the
/// caller-supplied <code>prefilter_indexed_column</code>).</p>
///
/// <p><b>SQL safety + %EXACT() discipline.</b>
/// <code>%EXACT()</code> on every <code>%String</code> projection +
/// predicate (<code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>); plain comparison on
/// <code>Status</code> (%Integer), <code>TimeCreated</code>
/// (Ens.DataType.UTC). The <code>prefilter_indexed_column</code> name
/// is interpolated into the SQL after enum validation gate (only one
/// of 4 hardcoded values is allowed); <code>prefilter_value</code> is
/// bound via <code>?</code> placeholder.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.6</a> — AC source.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS> §"BuildBoundedWhereClause".</li>
/// <li><CLASS>SessionAgent.Tool.Inspection.GetMessageBody</CLASS>
/// (Story 4.2) — the body-class dispatch ladder this tool composes.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"Innovation: Two-stage indexed-prefilter", §"NFR-P3 candidate cap",
/// §"Concurrent tool errors don't halt the agent".</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR18, NFR-P3.</li>
/// <li><a href="../../../../irislib/%25Regex/Matcher.cls">irislib/%Regex/Matcher.cls</a>
/// — ICU PCRE-flavor regex engine.</li>
/// </ul>
Class SessionAgent.Tool.Search.InspectBodyCandidates Extends SessionAgent.Tool.Search.Base
{

Parameter ToolName As %String = "inspect_body_candidates";

Parameter Description As %String = "Two-stage body-content search: narrow Ens.MessageHeader by an indexed prefilter (<=50 candidates), then open each body via the GetMessageBody dispatch ladder and filter by a pattern. pattern_is_regex=true uses PCRE/ICU regex; default is case-insensitive substring.";

Parameter MutatesState As %Boolean = 0;

/// <p>Hard cap on candidates inspected per AC-2 + NFR-P3. The cap is a
/// safety bound (not a soft hint) — every candidate inspected triggers
/// a body-class dispatch which can be expensive for HL7/XML/JSON
/// renders. A caller-supplied <code>candidate_cap</code> &gt; this is
/// REJECTED at validation, not silently clamped.</p>
Parameter MaxCandidateCap As %Integer = 50;

/// <p>AC-1 static fallback. The actual per-call indexed column is
/// dynamic (one of 4 enum values); the static return picks the
/// most-common case (<code>Status</code>) so the Story 8.2 invariant
/// test passes. The runtime envelope's <code>indexed_lead_column</code>
/// field reports the per-call value.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray
{
    Quit ["Status"]
}

/// <p>Locked-subset JSON Schema (AC-2). Required: <code>pattern</code>,
/// <code>prefilter_indexed_column</code>, <code>prefilter_value</code>.
/// <code>prefilter_indexed_column</code> is enum-constrained to the 4
/// indexed columns the bounded-WHERE invariant accepts as lead
/// columns. Optional: <code>time_window_hours</code> (default 24, max
/// 720), <code>pattern_is_regex</code> (default false),
/// <code>candidate_cap</code> (default 50, max 50 per NFR-P3).
/// <code>additionalProperties:false</code>.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "pattern": {"type": "string", "description": "Regex literal (PCRE/ICU flavor) when pattern_is_regex=true; substring otherwise."},
            "prefilter_indexed_column": {"type": "string", "description": "Indexed Ens.MessageHeader column to use for the prefilter narrow.", "enum": ["Status", "SourceConfigName", "TargetConfigName", "MessageBodyClassName"]},
            "prefilter_value": {"type": "string", "description": "Exact value to match for the indexed prefilter."},
            "time_window_hours": {"type": "integer", "description": "TimeCreated window in hours. Default 24, max 720.", "minimum": 1, "maximum": 720},
            "pattern_is_regex": {"type": "boolean", "description": "When true, pattern is a PCRE/ICU regex; when false (default), pattern is a case-insensitive substring."},
            "candidate_cap": {"type": "integer", "description": "Max candidates inspected. Default 50, max 50 (NFR-P3 hard bound).", "minimum": 1, "maximum": 50}
        },
        "required": ["pattern", "prefilter_indexed_column", "prefilter_value"],
        "additionalProperties": false
    }
}

/// <p>Implementation per AC-3, AC-4, AC-5, AC-6, AC-7, AC-10. Steps:</p>
/// <ol>
/// <li>Argument extraction + required-input validation.</li>
/// <li>AC-2 hard validation: <code>candidate_cap</code> &gt; 50 →
/// structured error (rejected, not silently clamped). Enum
/// validation on <code>prefilter_indexed_column</code>.</li>
/// <li>AC-5 regex compile (when <code>pattern_is_regex=true</code>) —
/// fail-fast on bad regex with a structured error envelope.</li>
/// <li>AC-3 Stage 1: prefilter SQL via
/// <method>Tool.Search.Base.BuildBoundedWhereClause</method> with
/// <code>"mh"</code> alias (AC-10) — uses the new alias parameter
/// directly, no $Replace workaround.</li>
/// <li>AC-4 Stage 2: per-candidate
/// <method>GetMessageBody.Invoke</method> with
/// <code>format="summary"</code>; extract <code>body_repr</code>;
/// AC-5 pattern match; AC-6 graceful drop on body-render error.</li>
/// <li>AC-7 envelope assembly + summary text.</li>
/// </ol>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Step 1: argument extraction.
        Set tPattern = ""
        Set tPrefilterCol = ""
        Set tPrefilterVal = ""
        Set tWindowHours = 0
        Set tPatternIsRegex = 0
        Set tCandidateCap = ..#MaxCandidateCap
        If $IsObject($Get(pJsonArgs)) {
            Set tPatternArg = pJsonArgs.%Get("pattern")
            Set:tPatternArg'=$$$NULLOREF tPattern = tPatternArg
            Set tPrefilterColArg = pJsonArgs.%Get("prefilter_indexed_column")
            Set:tPrefilterColArg'=$$$NULLOREF tPrefilterCol = tPrefilterColArg
            Set tPrefilterValArg = pJsonArgs.%Get("prefilter_value")
            Set:tPrefilterValArg'=$$$NULLOREF tPrefilterVal = tPrefilterValArg
            Set tWindowArg = pJsonArgs.%Get("time_window_hours")
            Set:tWindowArg'=$$$NULLOREF tWindowHours = +tWindowArg
            Set tRegexArg = pJsonArgs.%Get("pattern_is_regex")
            Set:tRegexArg'=$$$NULLOREF tPatternIsRegex = ''tRegexArg
            Set tCapArg = pJsonArgs.%Get("candidate_cap")
            Set:tCapArg'=$$$NULLOREF tCandidateCap = +tCapArg
        }
        Set:tPattern=$$$NULLOREF tPattern = ""
        Set:tPrefilterCol=$$$NULLOREF tPrefilterCol = ""
        Set:tPrefilterVal=$$$NULLOREF tPrefilterVal = ""

        ; --- Step 2: required-input validation (FR37 envelope).
        If (tPattern = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing pattern"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing pattern"}}
            Quit
        }
        If (tPrefilterCol = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing prefilter_indexed_column"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing prefilter_indexed_column"}}
            Quit
        }
        If (tPrefilterVal = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing prefilter_value"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing prefilter_value"}}
            Quit
        }

        ; --- Step 3: AC-2 enum validation on prefilter_indexed_column.
        ; Only the 4 documented indexed columns are accepted; this gate
        ; restricts the value before SQL interpolation (the column name
        ; cannot be SQL-bound; it MUST be a hardcoded literal).
        If (tPrefilterCol '= "Status")
            && (tPrefilterCol '= "SourceConfigName")
            && (tPrefilterCol '= "TargetConfigName")
            && (tPrefilterCol '= "MessageBodyClassName") {
            Set tErrText = "prefilter_indexed_column must be one of: Status, SourceConfigName, TargetConfigName, MessageBodyClassName (got: " _ tPrefilterCol _ ")"
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"validation_error", "error_text":(tErrText)}}
            Quit
        }

        ; --- Step 4: AC-2 hard cap validation. > 50 → reject with structured error.
        ; This MUST run BEFORE the prefilter SQL — silently clamping would
        ; produce misleading "NOTE: prefilter returned more than 50
        ; candidates" output (AC-7 NOTE bullet), and silently exceeding
        ; the cap would violate NFR-P3.
        If (tCandidateCap < 1) Set tCandidateCap = ..#MaxCandidateCap
        If (tCandidateCap > ..#MaxCandidateCap) {
            Set tErrText = "candidate_cap " _ tCandidateCap _ " exceeds NFR-P3 hard maximum of " _ ..#MaxCandidateCap
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"validation_error", "error_text":(tErrText), "errorCode":"CandidateCapTooLarge", "maxAllowed":(..#MaxCandidateCap)}}
            Quit
        }

        ; --- Step 5: AC-5 regex compile (fail-fast on bad regex).
        Set tMatcher = $$$NULLOREF
        If tPatternIsRegex {
            Try {
                Set tMatcher = ##class(%Regex.Matcher).%New(tPattern)
            }
            Catch regexEx {
                Set tErrText = "invalid regex pattern (PCRE/ICU): " _ regexEx.DisplayString()
                Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"validation_error", "error_text":(tErrText)}}
                Quit
            }
            If '$IsObject(tMatcher) {
                Set tErrText = "regex compile returned NULLOREF for pattern: " _ tPattern
                Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"validation_error", "error_text":(tErrText)}}
                Quit
            }
        }

        ; --- Step 6: Stage 1 prefilter SQL via BuildBoundedWhereClause.
        ; AC-10: pass "mh" as the alias parameter directly — uses the
        ; new alias-parameter signature from AC-9 sub-1 with no $Replace
        ; workaround.
        Set tParams = []
        Set tErr = ""
        Set tFragment = ##class(SessionAgent.Tool.Search.Base).BuildBoundedWhereClause(
            tWindowHours, .tParams, .tErr,
            "mh",
            "%EXACT(mh." _ tPrefilterCol _ ") = ?")
        If $IsObject(tErr) && (tErr.%Size() > 0) {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErr.%Get("message"))}], "structuredContent":(tErr)}
            Quit
        }
        ; tParams contains [tCutoffOdbc]. Push the prefilter_value bind.
        Do tParams.%Push(tPrefilterVal)

        Set tWindowUsed = $Select(tWindowHours = 0: ..#DefaultTimeWindowHours, 1: tWindowHours)

        ; Build the prefilter SQL. AC-3 SELECT: TOP ?, mh.ID, mh.SessionId,
        ; mh.MessageBodyId, %EXACT(mh.MessageBodyClassName), mh.TimeCreated.
        ; Note Status is %Integer for prefilter on Status; %EXACT() is
        ; harmless on numeric columns but spec says wrap string columns.
        Set tSql = "SELECT TOP ? mh.ID AS message_id, mh.SessionId AS sid, "
        Set tSql = tSql _ "%EXACT(mh.MessageBodyId) AS body_id, "
        Set tSql = tSql _ "%EXACT(mh.MessageBodyClassName) AS body_class, "
        Set tSql = tSql _ "mh.TimeCreated AS tc "
        Set tSql = tSql _ "FROM Ens.MessageHeader mh "
        Set tSql = tSql _ "WHERE " _ tFragment _ " "
        Set tSql = tSql _ "ORDER BY mh.TimeCreated DESC"

        Set tStmt = ##class(%SQL.Statement).%New()
        ; Request one extra row (cap+1) so we can detect the
        ; "prefilter returned more than 50 candidates" condition for
        ; the AC-7 NOTE bullet without paying for >cap actual rows.
        Set tProbeCap = tCandidateCap + 1
        Set tSCs = tStmt.%Prepare(tSql)
        If $$$ISERR(tSCs) {
            Set tErrText = "prefilter SQL prepare failed: " _ $System.Status.GetErrorText(tSCs)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"prepare_error", "error_text":(tErrText)}}
            Quit
        }

        ; Variadic %Execute via canonical multi-dim local-array apply.
        Kill tArgs
        Set tArgs(1) = tProbeCap
        Set tArgIdx = 1
        Set tBindIter = tParams.%GetIterator()
        While tBindIter.%GetNext(.tBindKey, .tBindVal) {
            Set tArgIdx = tArgIdx + 1
            Set tArgs(tArgIdx) = tBindVal
        }
        Set tArgs = tArgIdx
        Set tRs = tStmt.%Execute(tArgs...)

        ; Collect candidate rows.
        Set tCandidates = []
        Set tRowCount = 0
        Set tHitCap = 0
        While tRs.%Next() {
            Set tRowCount = tRowCount + 1
            If (tRowCount > tCandidateCap) {
                ; The (cap+1)th row is the indicator; do NOT append it
                ; to the candidate list.
                Set tHitCap = 1
                Quit
            }
            Set tCand = {}
            Do tCand.%Set("message_id", tRs.%Get("message_id"))
            Do tCand.%Set("session_id", +tRs.%Get("sid"), "number")
            Do tCand.%Set("body_id", tRs.%Get("body_id"))
            Do tCand.%Set("body_class", tRs.%Get("body_class"))
            Do tCand.%Set("time_created", ##class(SessionAgent.Tool.Base).NormalizeIsoZ(tRs.%Get("tc")))
            Do tCandidates.%Push(tCand)
        }

        ; --- Step 7: Stage 2 — body inspection per candidate.
        Set tMatches = []
        Set tCandidatesInspected = 0
        Set tMatchCount = 0
        Set tCandIter = tCandidates.%GetIterator()
        While tCandIter.%GetNext(.tCidx, .tCand) {
            Set tCandidatesInspected = tCandidatesInspected + 1
            Set tMessageId = tCand.%Get("message_id")
            Set tBodyClass = tCand.%Get("body_class")
            Set tSessionId = +tCand.%Get("session_id")

            ; AC-6: per-candidate Try/Catch. Body-render error → drop.
            Set tBodyText = ""
            Set tBodyResult = ""
            Set tBodyOk = 0
            Try {
                Set tBodyArgs = {"message_id":(tMessageId), "format":"summary"}
                Set tBodySC = ##class(SessionAgent.Tool.Inspection.GetMessageBody).Invoke(pCallerCtx, tBodyArgs, .tBodyResult)
                If $$$ISOK(tBodySC), $IsObject(tBodyResult) {
                    ; Drop candidates whose render strategy indicates the
                    ; body cannot be inspected. The "good" strategies are
                    ; the ones that produce body_repr text:
                    ; hl7, json_adaptor, xml_adaptor, stream,
                    ; ens_message_body, persistent. The "bad" strategies
                    ; (header_not_found, no_body, body_not_found,
                    ; *_error, dispatch_error, unknown) → silent drop.
                    Set tStrategy = ""
                    If $IsObject(tBodyResult.structuredContent) {
                        Set tStrategy = tBodyResult.structuredContent.%Get("render_strategy")
                    }
                    If (tStrategy = "hl7")
                        || (tStrategy = "json_adaptor")
                        || (tStrategy = "xml_adaptor")
                        || (tStrategy = "stream")
                        || (tStrategy = "ens_message_body")
                        || (tStrategy = "persistent") {
                        Set tBodyText = tBodyResult.structuredContent.%Get("body_repr")
                        If tBodyText = $$$NULLOREF Set tBodyText = ""
                        Set tBodyOk = 1
                    }
                }
            }
            Catch bodyEx {
                ; AC-6: graceful drop on inner-Invoke exception. NEVER
                ; propagate a per-candidate exception to the outer envelope.
                Set tBodyOk = 0
            }

            If 'tBodyOk Continue

            ; --- AC-5: pattern match against tBodyText.
            Set tMatched = 0
            If tPatternIsRegex {
                ; PCRE/ICU regex via %Regex.Matcher. Reset Text per
                ; candidate; Matcher is reused (compiled once at Step 5).
                Try {
                    Set tMatcher.Text = tBodyText
                    Set tMatched = ''tMatcher.Locate()
                }
                Catch regexEx2 {
                    ; Per-candidate regex eval failure → drop candidate
                    ; (defensive — should never happen if compile succeeded).
                    Set tMatched = 0
                }
            } Else {
                ; Case-insensitive substring search.
                Set tBodyU = $ZConvert(tBodyText, "U")
                Set tPatU = $ZConvert(tPattern, "U")
                Set tMatched = ($Find(tBodyU, tPatU) > 0)
            }

            If tMatched {
                Set tMatchCount = tMatchCount + 1
                Set tMatch = {}
                Do tMatch.%Set("message_id", tMessageId)
                Do tMatch.%Set("session_id", tSessionId, "number")
                Do tMatch.%Set("body_class", tBodyClass)
                ; body_excerpt — truncate to 256 chars max for envelope
                ; bound; the GetMessageBody summary mode already caps at
                ; 256 but defensive-truncate here too.
                Set tExcerpt = $Extract(tBodyText, 1, 256)
                Do tMatch.%Set("body_excerpt", tExcerpt)
                Do tMatches.%Push(tMatch)
            }
        }

        ; --- Step 8: build envelope (AC-7).
        Do pResult.structuredContent.%Set("pattern", tPattern)
        Do pResult.structuredContent.%Set("prefilter_indexed_column", tPrefilterCol)
        Do pResult.structuredContent.%Set("prefilter_value", tPrefilterVal)
        Do pResult.structuredContent.%Set("time_window_used", tWindowUsed, "number")
        Do pResult.structuredContent.%Set("pattern_is_regex", ''tPatternIsRegex, "boolean")
        Do pResult.structuredContent.%Set("candidates_inspected", tCandidatesInspected, "number")
        Do pResult.structuredContent.%Set("matches", tMatches)
        Do pResult.structuredContent.%Set("match_count", tMatchCount, "number")
        Do pResult.structuredContent.%Set("indexed_lead_column", tPrefilterCol)
        If tHitCap {
            Do pResult.structuredContent.%Set("render_strategy", "candidates_inspected_capped")
            Do pResult.structuredContent.%Set("cap_hit", 1, "boolean")
        } Else {
            Do pResult.structuredContent.%Set("render_strategy", "candidates_inspected")
            Do pResult.structuredContent.%Set("cap_hit", 0, "boolean")
        }

        ; AC-7 operator-readable summary text.
        Set tWindowText = "the last " _ tWindowUsed _ " hour(s)"
        Set tModeText = $Select(tPatternIsRegex: "regex", 1: "substring")
        Set tSummary = "Inspected " _ tCandidatesInspected _ " candidate(s) filtered by " _ tPrefilterCol _ "='" _ tPrefilterVal _ "' in " _ tWindowText _ "; " _ tMatchCount _ " matched " _ tModeText _ " pattern '" _ tPattern _ "' in their body content."
        If tHitCap {
            Set tSummary = tSummary _ " NOTE: prefilter returned more than " _ tCandidateCap _ " candidates — consider tightening the prefilter to broaden coverage."
        }
        Set pResult.content.%Get(0).text = tSummary
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"dispatch_error", "error_text":(tErrText)}}
        Quit
    }
    Quit tSC
}

}
