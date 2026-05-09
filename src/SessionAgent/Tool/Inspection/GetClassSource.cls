/// <p>Inspection tool — returns the full ObjectScript source of any
/// compiled class via the Atelier text-services API
/// (<CLASS>%Atelier.v1.Utils.TextServices</CLASS>). Optionally filters
/// to a single method body using a brace-depth tracker, and optionally
/// strips <code>///</code> doc-comment lines. Shipped by Story 13.1.</p>
///
/// <p><b>Tool name:</b> <code>get_class_source</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{class_name (required), method_name (optional), include_doc_comments (optional bool, default true)}</code>.</p>
///
/// <p><b>Output (structuredContent, no method_name):</b>
/// <code>{class_name, method_name, source_lines, line_count, truncated, render_strategy}</code>.
/// <code>source_lines</code> is a JSON array of strings.</p>
///
/// <p><b>Output (method_name supplied):</b> same shape; <code>source_lines</code>
/// contains only the method signature through its closing <code>}</code>
/// (brace-depth tracker). If the named method is not found,
/// <code>render_strategy="method_not_found"</code> with empty
/// <code>source_lines</code>.</p>
///
/// <p><b>Truncation guard.</b> When <code>method_name</code> is omitted
/// AND the class exceeds 2000 lines, only the first 1500 lines are
/// returned with <code>truncated=true</code> and a suggestion to use
/// <code>method_name</code> for method-level filtering.</p>
///
/// <p><b>Class-not-found envelope.</b> If the class is not compiled in
/// the current namespace, returns
/// <code>render_strategy="class_not_found"</code> — NOT an error
/// envelope. Class absence is operator-observable state.</p>
///
/// <p><b>Strip-last-segment fallback (AC-8).</b> When the initial lookup
/// misses AND the class name contains a dot, the last dot-segment is
/// stripped and the lookup is retried once. On success: normal envelope
/// plus <code>class_name_auto_corrected_from</code> field. On
/// still-not-found: class_not_found envelope plus
/// <code>candidate_class_name</code> field. Pattern copied from
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS>
/// lines 105-156.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/13-1-get-class-source-tool.md">
/// Story 13.1</a> — AC source.</li>
/// <li><a href="../../../../irislib/%25Atelier/v1/Utils/TextServices.cls">
/// irislib/%Atelier/v1/Utils/TextServices.cls</a> —
/// <code>GetTextAsArray</code> API signature.</li>
/// <li><a href="GetBusinessProcessSource.cls">GetBusinessProcessSource.cls</a>
/// — strip-last-segment fallback pattern (lines 105-156).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetClassSource Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_class_source";

Parameter Description As %String = "Read the full ObjectScript source of any compiled class — including DTL XData, method bodies, and BP logic — so the agent can explain exactly what a configured item does.";

Parameter MutatesState As %Boolean = 0;

/// <p>JSON Schema for <code>get_class_source</code>. Required:
/// <code>class_name</code>. Optional: <code>method_name</code>,
/// <code>include_doc_comments</code>. <code>additionalProperties</code>
/// false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "class_name": {
                "type": "string",
                "description": "Full class name of the compiled class to read (e.g., SessionAgent.Sample.BP.OrderRouter). Pass the class name only — do not include method names; use `method_name` for method-level filtering."
            },
            "method_name": {
                "type": "string",
                "description": "Optional. When supplied, only the lines from the named method's signature through its closing } are returned. Omit to return the full class source."
            },
            "include_doc_comments": {
                "type": "boolean",
                "description": "When false, strip /// doc-comment lines from source_lines before returning. Default true."
            }
        },
        "required": ["class_name"],
        "additionalProperties": false
    }
}

/// <p>Read the class source via
/// <class>%Atelier.v1.Utils.TextServices</class>.GetTextAsArray,
/// apply optional method-level filter and doc-comment strip, and
/// return the structured envelope. Class-absence and method-not-found
/// surface as non-error envelopes.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Input validation ---
        Set tClassName = ""
        Set tMethodName = ""
        Set tIncludeDocs = 1
        If $IsObject($Get(pJsonArgs)) {
            Set tClassName = pJsonArgs.%Get("class_name")
            Set:tClassName=$$$NULLOREF tClassName = ""
            Set tMethodName = pJsonArgs.%Get("method_name")
            Set:tMethodName=$$$NULLOREF tMethodName = ""
            If pJsonArgs.%IsDefined("include_doc_comments") {
                Set tIncludeDocs = +pJsonArgs.%Get("include_doc_comments")
            }
        }
        If (tClassName = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing class_name"}]}
            Quit
        }

        ; --- Initial GetTextAsArray probe ---
        Kill tTextArray
        Set tDocName = tClassName _ ".cls"
        Set tLookupSC = ##class(%Atelier.v1.Utils.TextServices).GetTextAsArray(tDocName, 0, .tTextArray, 0)
        Set tFound = $$$ISOK(tLookupSC) && ($Data(tTextArray) > 0)

        ; --- Strip-last-segment fallback (AC-8) ---
        ; Pattern copied from GetBusinessProcessSource.cls lines 105-156.
        Set tOriginalClassName = tClassName
        Set tAutoCorrected = 0
        Set tStrippedName = ""
        If 'tFound, tClassName [ "." {
            Set tSegmentCount = $Length(tClassName, ".")
            If tSegmentCount > 1 {
                Set tStrippedName = $Piece(tClassName, ".", 1, tSegmentCount - 1)
                Kill tTextArray
                Set tRetryDocName = tStrippedName _ ".cls"
                Set tRetrySC = ##class(%Atelier.v1.Utils.TextServices).GetTextAsArray(tRetryDocName, 0, .tTextArray, 0)
                If $$$ISOK(tRetrySC) && ($Data(tTextArray) > 0) {
                    ; Retry succeeded — proceed with the stripped name.
                    Set tClassName = tStrippedName
                    Set tAutoCorrected = 1
                    Set tFound = 1
                }
            }
        }

        ; --- Class-not-found envelope (AC-7) ---
        If 'tFound {
            Do pResult.structuredContent.%Set("class_name", tOriginalClassName)
            Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
            Do pResult.structuredContent.%Set("source_lines", [])
            Do pResult.structuredContent.%Set("line_count", 0, "number")
            Do pResult.structuredContent.%Set("truncated", 0, "boolean")
            ; AC-8 — surface candidate stripped name for self-correction.
            If tStrippedName '= "" {
                Do pResult.structuredContent.%Set("candidate_class_name", tStrippedName)
            }
            Set pResult.content.%Get(0).text = "class not found: " _ tOriginalClassName
            Quit
        }

        ; --- Extract lines from tTextArray ---
        ; tTextArray(0) = line count; tTextArray(1..N) = lines.
        Set tTotalLines = +$Get(tTextArray(0))

        ; --- Truncation guard (AC-6) — no method_name, class > 2000 lines ---
        Set tTruncated = 0
        Set tTruncationNote = ""
        If (tMethodName = "") && (tTotalLines > 2000) {
            Set tTotalLines = 1500
            Set tTruncated = 1
            Set tTruncationNote = "Class exceeds 2000 lines. Use method_name to filter."
        }

        ; --- Build working line array (full class or method-filtered) ---
        Set tLines = []

        If tMethodName = "" {
            ; Full class — collect up to tTotalLines lines.
            For i = 1:1:tTotalLines {
                Do tLines.%Push($Get(tTextArray(i)))
            }
        } Else {
            ; Method-level brace-depth filter (AC-4).
            Set tInMethod = 0
            Set tDepth = 0
            For i = 1:1:+$Get(tTextArray(0)) {
                Set tLine = $Get(tTextArray(i))
                If 'tInMethod {
                    ; Match "Method Name(" or "ClassMethod Name(" lines.
                    Set tNorm = $ZStrip(tLine, "<W")
                    Set tIsMethod = ($Extract(tNorm, 1, 7) = "Method ") || ($Extract(tNorm, 1, 12) = "ClassMethod ")
                    If tIsMethod {
                        ; Extract the bare method name (segment before first "(").
                        Set tNamePart = $Piece(tNorm, "(", 1)
                        Set tLastWord = $Piece(tNamePart, " ", *)
                        If tLastWord = tMethodName {
                            Set tInMethod = 1
                            Set tDepth = 0
                            Do tLines.%Push(tLine)
                        }
                    }
                } Else {
                    Do tLines.%Push(tLine)
                    ; Count braces in this line to track depth.
                    For j = 1:1:$Length(tLine) {
                        Set tCh = $Extract(tLine, j)
                        If tCh = "{" {
                            Set tDepth = tDepth + 1
                        } ElseIf tCh = "}" {
                            Set tDepth = tDepth - 1
                            If tDepth = 0 {
                                ; Closing brace at depth 0 — method complete.
                                Quit
                            }
                        }
                    }
                    If tDepth = 0 Quit  ; method complete after processing this line
                }
            }
            ; Method not found?
            If tLines.%Size() = 0 {
                Do pResult.structuredContent.%Set("class_name", tClassName)
                Do pResult.structuredContent.%Set("method_name", tMethodName)
                Do pResult.structuredContent.%Set("render_strategy", "method_not_found")
                Do pResult.structuredContent.%Set("source_lines", [])
                Do pResult.structuredContent.%Set("line_count", 0, "number")
                Do pResult.structuredContent.%Set("truncated", 0, "boolean")
                If tAutoCorrected {
                    Do pResult.structuredContent.%Set("class_name_auto_corrected_from", tOriginalClassName)
                }
                Set pResult.content.%Get(0).text = "method not found: " _ tMethodName _ " in " _ tClassName
                Quit
            }
        }

        ; --- include_doc_comments=false strip (AC-5) ---
        If 'tIncludeDocs {
            Set tFiltered = []
            Set tIter = tLines.%GetIterator()
            While tIter.%GetNext(.tKey, .tLineVal) {
                ; Strip lines whose left-trimmed content starts with "///".
                If $Extract($ZStrip(tLineVal, "<W"), 1, 3) '= "///" {
                    Do tFiltered.%Push(tLineVal)
                }
            }
            Set tLines = tFiltered
        }

        ; --- Build success envelope ---
        Do pResult.structuredContent.%Set("class_name", tClassName)
        Do pResult.structuredContent.%Set("method_name", tMethodName)
        Do pResult.structuredContent.%Set("source_lines", tLines)
        Do pResult.structuredContent.%Set("line_count", tLines.%Size(), "number")
        Do pResult.structuredContent.%Set("truncated", tTruncated, "boolean")
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        If tTruncated {
            Do pResult.structuredContent.%Set("truncation_note", tTruncationNote)
        }
        ; AC-8 — surface auto-correction marker when strip-last-segment succeeded.
        If tAutoCorrected {
            Do pResult.structuredContent.%Set("class_name_auto_corrected_from", tOriginalClassName)
        }

        ; Operator-facing summary text.
        Set tMethodLabel = $Select(tMethodName '= "":" method '" _ tMethodName _ "'", 1:" (full class)")
        Set tTruncLabel = $Select(tTruncated:" [truncated to 1500/" _ (+$Get(tTextArray(0))) _ " lines]", 1:"")
        Set pResult.content.%Get(0).text = tClassName _ tMethodLabel _ " — " _ tLines.%Size() _ " lines" _ tTruncLabel
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
