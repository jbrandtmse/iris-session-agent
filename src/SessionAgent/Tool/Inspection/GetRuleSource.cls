/// <p>Inspection tool — reads the raw <code>RuleDefinition</code> XData
/// from a compiled Ensemble rule class and optionally parses the
/// <code>&lt;rule&gt;</code> / <code>&lt;when&gt;</code> /
/// <code>&lt;send&gt;</code> / <code>&lt;return&gt;</code> elements into
/// a structured <code>constraints</code> array. Shipped by Story 13.2.</p>
///
/// <p><b>Tool name:</b> <code>get_rule_source</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{rule_class (required), parse_constraints (optional bool, default true)}</code>.
/// <code>rule_class</code> is the full class name of a compiled Ensemble
/// rule class that owns a <code>RuleDefinition</code> XData block (e.g.,
/// <code>SessionAgent.Sample.Rules.OrderRouting</code>). Do NOT append a
/// method name — see AC-7.</p>
///
/// <p><b>Output (structuredContent, parse_constraints=true):</b>
/// <code>{rule_class, rule_xml, rule_count, constraints:[{name, when, action}...],
/// render_strategy}</code>.</p>
///
/// <p><b>Output (parse_constraints=false):</b> same shape but
/// <code>rule_count=0</code> and <code>constraints=[]</code> — raw XML
/// only, cheaper for context budget.</p>
///
/// <p><b>Class-not-found envelope.</b> If the class does not exist OR
/// has no <code>RuleDefinition</code> XData, returns
/// <code>render_strategy="class_not_found"</code> with empty rule_xml and
/// empty constraints — NOT an error envelope (<code>isError</code> is
/// absent). Class absence is operator-observable state analogous to
/// <code>get_business_process_source</code>'s class_not_found path.</p>
///
/// <p><b>Strip-last-segment fallback (AC-6).</b> When the XData lookup
/// misses AND the class name contains a dot, the last dot-segment is
/// stripped and the lookup retried once. On success: normal envelope +
/// <code>rule_class_auto_corrected_from</code> top-level field showing the
/// original input. On still-not-found: class_not_found envelope +
/// <code>candidate_rule_class</code> field showing the stripped name so
/// the LLM can self-correct on the next turn. Pattern copied exactly from
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS>
/// lines 105-156.</p>
///
/// <p><b>XML walking (<code>%XML.TextReader</code>).</b> When
/// <code>parse_constraints=true</code>, the XData stream is re-wound and
/// passed to <code>%XML.TextReader.ParseStream()</code>. Element nodes
/// <code>rule</code>, <code>when</code>, <code>send</code>, and
/// <code>return</code> are matched by <code>LocalName</code>; attribute
/// values are extracted via <method>MoveToAttributeName</method> + the
/// <code>Value</code> property (there is no <code>GetAttribute</code> method
/// on <class>%XML.TextReader</class>; verified in irislib/%XML/TextReader.cls).
/// Each <code>&lt;send&gt;</code> or <code>&lt;return&gt;</code> produces
/// one constraints array entry under the most-recent enclosing
/// <code>&lt;rule&gt;</code> / <code>&lt;when&gt;</code> context.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/13-2-get-rule-source-tool.md">
/// Story 13.2</a> — AC source.</li>
/// <li><a href="GetBusinessProcessSource.cls">GetBusinessProcessSource.cls</a>
/// — strip-last-segment fallback pattern (lines 105-156).</li>
/// <li><a href="../../../../irislib/%25Dictionary/XDataDefinition.cls">
/// irislib/%Dictionary/XDataDefinition.cls</a> — Data stream property.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetRuleSource Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_rule_source";

Parameter Description As %String = "Read the raw RuleDefinition XML from a compiled Ensemble rule class and parse routing constraints — helps explain which rule fired and why, as reported by rule_log.";

Parameter MutatesState As %Boolean = 0;

/// <p>JSON Schema for <code>get_rule_source</code>. Required:
/// <code>rule_class</code>. Optional: <code>parse_constraints</code>
/// (boolean, default true). <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "rule_class": {
                "type": "string",
                "description": "Full class name of the Ensemble rule class whose RuleDefinition XData to read (e.g., SessionAgent.Sample.Rules.OrderRouting). Pass the class name only — do not include method names."
            },
            "parse_constraints": {
                "type": "boolean",
                "description": "When true (default), parse the RuleDefinition XML and return a structured constraints array. When false, return only the raw rule_xml (cheaper for context budget)."
            }
        },
        "required": ["rule_class"],
        "additionalProperties": false
    }
}

/// <p>Open the RuleDefinition XData block, read the raw XML, and
/// optionally parse routing constraints. Pre-validates
/// <code>rule_class</code>. Class-absence (or absent XData block)
/// surfaces as a <code>class_not_found</code> envelope, not an error.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; --- Input validation ---
        Set tRuleClass = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tRuleClass = pJsonArgs.%Get("rule_class")
            Set:tRuleClass=$$$NULLOREF tRuleClass = ""
        }
        If (tRuleClass = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing rule_class"}]}
            Quit
        }

        ; parse_constraints defaults to true when omitted
        Set tParseConstraints = 1
        If $IsObject($Get(pJsonArgs)) && pJsonArgs.%IsDefined("parse_constraints") {
            Set tParseConstraints = +pJsonArgs.%Get("parse_constraints")
        }

        ; --- XData lookup ---
        Set tXData = $$$NULLOREF
        Try {
            Set tXData = ##class(%Dictionary.XDataDefinition).IDKEYOpen(tRuleClass, "RuleDefinition")
        }
        Catch openEx {
            Set tXData = $$$NULLOREF
        }

        ; --- Strip-last-segment fallback (AC-6) ---
        ; Copied exactly from GetBusinessProcessSource.cls lines 105-156 pattern.
        Set tOriginalRuleClass = tRuleClass
        Set tAutoCorrected = 0
        Set tStrippedName = ""
        If '$IsObject(tXData), tRuleClass [ "." {
            Set tSegCount = $Length(tRuleClass, ".")
            If tSegCount > 1 {
                Set tStrippedName = $Piece(tRuleClass, ".", 1, tSegCount - 1)
                Try {
                    Set tXData = ##class(%Dictionary.XDataDefinition).IDKEYOpen(tStrippedName, "RuleDefinition")
                }
                Catch retryEx {
                    Set tXData = $$$NULLOREF
                }
                If $IsObject(tXData) {
                    Set tRuleClass = tStrippedName
                    Set tAutoCorrected = 1
                }
            }
        }

        ; --- Class-not-found envelope (AC-5) ---
        If '$IsObject(tXData) {
            Do pResult.structuredContent.%Set("rule_class", tOriginalRuleClass)
            Do pResult.structuredContent.%Set("rule_xml", "")
            Do pResult.structuredContent.%Set("rule_count", 0, "number")
            Do pResult.structuredContent.%Set("constraints", [])
            Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
            If tStrippedName '= "" {
                Do pResult.structuredContent.%Set("candidate_rule_class", tStrippedName)
            }
            Set pResult.content.%Get(0).text = "rule class not found or no RuleDefinition XData: " _ tOriginalRuleClass
            Quit
        }

        ; --- Read raw XML from stream (AC-2) ---
        Set tXml = ""
        Do tXData.Data.Rewind()
        While 'tXData.Data.AtEnd {
            Set tXml = tXml _ tXData.Data.Read(32000)
        }

        ; --- Optionally parse constraints (AC-3, AC-4) ---
        ; %XML.TextReader.ParseStream is a ClassMethod; Output param receives the reader.
        ; Use MoveToAttributeName(name) + ..Value to read attribute values.
        Set tConstraints = []
        Set tRuleCount = 0
        If tParseConstraints {
            Do tXData.Data.Rewind()
            Set tParseSC = ##class(%XML.TextReader).ParseStream(tXData.Data, .tReader)
            If $$$ISOK(tParseSC) && $IsObject(tReader) {
                Set tCurRule = ""
                Set tCurWhen = ""
                While tReader.Read() {
                    If tReader.NodeType = "element" {
                        If tReader.LocalName = "rule" {
                            Set tCurRule = ""
                            If tReader.MoveToAttributeName("name") {
                                Set tCurRule = tReader.Value
                                Do tReader.MoveToElement()
                            }
                            Set tRuleCount = tRuleCount + 1
                        } ElseIf tReader.LocalName = "when" {
                            Set tCurWhen = ""
                            If tReader.MoveToAttributeName("condition") {
                                Set tCurWhen = tReader.Value
                                Do tReader.MoveToElement()
                            }
                        } ElseIf tReader.LocalName = "send" {
                            Set tTarget = ""
                            If tReader.MoveToAttributeName("target") {
                                Set tTarget = tReader.Value
                                Do tReader.MoveToElement()
                            }
                            Set tEntry = {}
                            Do tEntry.%Set("name", tCurRule)
                            Do tEntry.%Set("when", tCurWhen)
                            Do tEntry.%Set("action", "send '" _ tTarget _ "'")
                            Do tConstraints.%Push(tEntry)
                        } ElseIf tReader.LocalName = "return" {
                            Set tEntry = {}
                            Do tEntry.%Set("name", tCurRule)
                            Do tEntry.%Set("when", tCurWhen)
                            Do tEntry.%Set("action", "return")
                            Do tConstraints.%Push(tEntry)
                        }
                    }
                }
            }
        }

        ; --- Build success envelope ---
        Do pResult.structuredContent.%Set("rule_class", tRuleClass)
        Do pResult.structuredContent.%Set("rule_xml", tXml)
        Do pResult.structuredContent.%Set("rule_count", tRuleCount, "number")
        Do pResult.structuredContent.%Set("constraints", tConstraints)
        Do pResult.structuredContent.%Set("render_strategy", "ok")

        ; Strip-last-segment auto-correction marker (AC-6)
        If tAutoCorrected {
            Do pResult.structuredContent.%Set("rule_class_auto_corrected_from", tOriginalRuleClass)
        }

        Set tConstraintLabel = $Select(tParseConstraints:"parsed " _ tRuleCount _ " rule(s)", 1:"raw XML only (parse_constraints=false)")
        Set pResult.content.%Get(0).text = tRuleClass _ " — " _ $Length(tXml) _ " bytes XML, " _ tConstraintLabel
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
