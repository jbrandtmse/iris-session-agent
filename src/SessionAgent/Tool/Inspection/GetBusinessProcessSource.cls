/// <p>Inspection tool — return the structured source representation of a
/// Business Process class via <CLASS>%Dictionary.ClassDefinition</CLASS>
/// reflection. First of three BP-introspection tools shipped by Story
/// 4.4 (alongside <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessInstance</CLASS>
/// and <CLASS>SessionAgent.Tool.Inspection.ListBusinessProcessMethods</CLASS>).</p>
///
/// <p><b>Tool name:</b> <code>get_business_process_source</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{bp_class_name (required)}</code> — full class
/// name like <code>SessionAgent.Sample.BP.OrderRouter</code> or
/// <code>Ens.BusinessProcess</code>.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{class_name, super_class, abstract, parameters:[...], properties:[...],
/// methods:[...], method_count, property_count, parameter_count}</code>.
/// Each method entry: <code>{name, signature, comment, has_body}</code>.
/// Each property entry: <code>{name, type, comment}</code>. Each parameter
/// entry: <code>{name, default_value, comment}</code>.</p>
///
/// <p><b>Class-not-found envelope.</b> If
/// <code>%Dictionary.ClassDefinition.%OpenId(class)</code> returns
/// <code>$$$NULLOREF</code> (typo, deleted, never existed) the result is
/// <code>{render_strategy:"class_not_found", class_name, ...}</code> with
/// empty arrays — NOT an error envelope. Class absence is operator-
/// observable state, same shape as <code>get_message_body</code>'s
/// <code>render_strategy="header_not_found"</code> for a missing message.</p>
///
/// <p><b>Implementation iterates only declared (locally-authored) members</b>
/// — <CLASS>%Dictionary.ClassDefinition</CLASS> exposes only the children
/// directly defined on the class. To see inherited methods, operators use
/// the companion <CLASS>SessionAgent.Tool.Inspection.ListBusinessProcessMethods</CLASS>
/// tool which queries the compiled (post-inheritance) view via
/// <CLASS>%Dictionary.CompiledMethod</CLASS>.</p>
///
/// <p><b>Method <code>has_body</code> determination.</b>
/// <code>%Dictionary.MethodDefinition.Implementation</code> is a
/// <CLASS>%Stream.TmpCharacter</CLASS> stream, NOT a string. Check
/// <code>Implementation.Size > 0</code> rather than string equality (Task-0
/// probe finding, 2026-05-04).</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.4</a> AC-1..3 — AC source.</li>
/// <li><a href="../../../../irislib/%25Dictionary/ClassDefinition.cls">irislib/%Dictionary/ClassDefinition.cls</a> —
/// <code>Methods</code> / <code>Properties</code> / <code>Parameters</code>
/// children relationships, <code>Super</code> / <code>Abstract</code>
/// scalar properties.</li>
/// <li><a href="../../../../irislib/%25Dictionary/MethodDefinition.cls">irislib/%Dictionary/MethodDefinition.cls</a> —
/// <code>FormalSpec</code>, <code>ReturnType</code>, <code>Description</code>,
/// <code>Implementation</code> (Stream).</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetBusinessProcessSource Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_business_process_source";

Parameter Description As %String = "Read the structured source representation of a Business Process class — superclass, parameters, properties, methods.";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Required: <code>bp_class_name</code>.
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "bp_class_name": {"type": "string", "description": "Full class name of the Business Process class (e.g., SessionAgent.Sample.BP.OrderRouter or Ens.BusinessProcess). Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."}
        },
        "required": ["bp_class_name"],
        "additionalProperties": false
    }
}

/// <p>Open the class definition and project its declared methods,
/// properties, and parameters. Pre-validates <code>bp_class_name</code>.
/// Class-absence surfaces as a <code>class_not_found</code> envelope, not
/// an error.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tClassName = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tClassName = pJsonArgs.%Get("bp_class_name")
            Set:tClassName=$$$NULLOREF tClassName = ""
        }
        If (tClassName = "") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing bp_class_name"}]}
            Quit
        }

        ; Open the class definition. NULLOREF on missing class.
        Set tCls = $$$NULLOREF
        Try {
            Set tCls = ##class(%Dictionary.ClassDefinition).%OpenId(tClassName)
        }
        Catch openEx {
            Set tCls = $$$NULLOREF
        }

        ; Story 12.2 BUG-03 — class-name fallback. If the initial lookup
        ; missed AND the class name contains a "." (multi-segment), strip
        ; the last dot-segment and retry once. Common LLM slip: "appended
        ; a method name to the class name". Retry succeeds → render normal
        ; "ok" envelope using the stripped name + a top-level
        ; "class_name_auto_corrected_from" field showing the original
        ; input. Retry still misses → fall through to the existing
        ; class_not_found envelope, augmented with a
        ; "candidate_class_name" field so the LLM can self-correct on the
        ; next turn.
        Set tOriginalClassName = tClassName
        Set tAutoCorrected = 0
        Set tStrippedName = ""
        If '$IsObject(tCls), tClassName [ "." {
            Set tSegmentCount = $Length(tClassName, ".")
            If tSegmentCount > 1 {
                Set tStrippedName = $Piece(tClassName, ".", 1, tSegmentCount - 1)
                Try {
                    Set tCls = ##class(%Dictionary.ClassDefinition).%OpenId(tStrippedName)
                }
                Catch retryEx {
                    Set tCls = $$$NULLOREF
                }
                If $IsObject(tCls) {
                    ; Retry succeeded — proceed with the stripped name as
                    ; the canonical class name; remember to surface the
                    ; auto-correction marker.
                    Set tClassName = tStrippedName
                    Set tAutoCorrected = 1
                }
            }
        }

        If '$IsObject(tCls) {
            Do pResult.structuredContent.%Set("class_name", tOriginalClassName)
            Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
            Do pResult.structuredContent.%Set("super_class", "")
            Do pResult.structuredContent.%Set("abstract", 0, "boolean")
            Do pResult.structuredContent.%Set("parameters", [])
            Do pResult.structuredContent.%Set("properties", [])
            Do pResult.structuredContent.%Set("methods", [])
            Do pResult.structuredContent.%Set("method_count", 0, "number")
            Do pResult.structuredContent.%Set("property_count", 0, "number")
            Do pResult.structuredContent.%Set("parameter_count", 0, "number")
            ; Story 12.2 BUG-03 — surface the candidate stripped name so
            ; the LLM can self-correct on the next turn.
            If tStrippedName '= "" {
                Do pResult.structuredContent.%Set("candidate_class_name", tStrippedName)
            }
            Set pResult.content.%Get(0).text = "class not found: " _ tOriginalClassName
            Quit
        }

        Set tSuper = tCls.Super
        Set tAbstract = +tCls.Abstract

        ; Methods — iterate Methods relationship (children of the class).
        Set tMethods = []
        Set tMethodCount = 0
        For tIdx = 1:1:tCls.Methods.Count() {
            Set tMethDef = tCls.Methods.GetAt(tIdx)
            If '$IsObject(tMethDef) Continue
            Set tName = tMethDef.Name
            Set tFormal = tMethDef.FormalSpec
            Set tReturn = tMethDef.ReturnType
            Set tDesc = tMethDef.Description
            ; signature = name(formalSpec) As returnType
            Set tSignature = tName _ "(" _ tFormal _ ")"
            If tReturn '= "" {
                Set tSignature = tSignature _ " As " _ tReturn
            }
            ; has_body — Implementation is a %Stream.TmpCharacter; check Size.
            Set tHasBody = 0
            Try {
                If $IsObject(tMethDef.Implementation) && (tMethDef.Implementation.Size > 0) {
                    Set tHasBody = 1
                }
            }
            Catch implEx {
                Set tHasBody = 0
            }
            Set tEntry = {}
            Do tEntry.%Set("name", tName)
            Do tEntry.%Set("signature", tSignature)
            Do tEntry.%Set("comment", tDesc)
            Do tEntry.%Set("has_body", tHasBody, "boolean")
            Do tMethods.%Push(tEntry)
            Set tMethodCount = tMethodCount + 1
        }

        ; Properties — iterate Properties relationship.
        Set tProps = []
        Set tPropCount = 0
        For tIdx = 1:1:tCls.Properties.Count() {
            Set tPropDef = tCls.Properties.GetAt(tIdx)
            If '$IsObject(tPropDef) Continue
            Set tEntry = {}
            Do tEntry.%Set("name", tPropDef.Name)
            Do tEntry.%Set("type", tPropDef.Type)
            Do tEntry.%Set("comment", tPropDef.Description)
            Do tProps.%Push(tEntry)
            Set tPropCount = tPropCount + 1
        }

        ; Parameters — iterate Parameters relationship.
        Set tParams = []
        Set tParamCount = 0
        For tIdx = 1:1:tCls.Parameters.Count() {
            Set tParamDef = tCls.Parameters.GetAt(tIdx)
            If '$IsObject(tParamDef) Continue
            Set tEntry = {}
            Do tEntry.%Set("name", tParamDef.Name)
            Do tEntry.%Set("default_value", tParamDef.Default)
            Do tEntry.%Set("comment", tParamDef.Description)
            Do tParams.%Push(tEntry)
            Set tParamCount = tParamCount + 1
        }

        Do pResult.structuredContent.%Set("class_name", tClassName)
        Do pResult.structuredContent.%Set("super_class", tSuper)
        Do pResult.structuredContent.%Set("abstract", tAbstract, "boolean")
        Do pResult.structuredContent.%Set("parameters", tParams)
        Do pResult.structuredContent.%Set("properties", tProps)
        Do pResult.structuredContent.%Set("methods", tMethods)
        Do pResult.structuredContent.%Set("method_count", tMethodCount, "number")
        Do pResult.structuredContent.%Set("property_count", tPropCount, "number")
        Do pResult.structuredContent.%Set("parameter_count", tParamCount, "number")
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        ; Story 12.2 BUG-03 — surface auto-correction marker when the
        ; initial lookup missed and the strip-last-segment retry succeeded.
        If tAutoCorrected {
            Do pResult.structuredContent.%Set("class_name_auto_corrected_from", tOriginalClassName)
        }

        Set tSuperLabel = $Select(tSuper="":"<no superclass>", 1:"extends " _ tSuper)
        Set pResult.content.%Get(0).text = tClassName _ " (" _ tSuperLabel _ ") — " _ tMethodCount _ " methods, " _ tPropCount _ " properties, " _ tParamCount _ " parameters"
        Quit
    }
    Catch ex {
        ; Story 4.7 AC-7 — operator-friendly catch text (Story 4.5 R-4).
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
        Quit
    }
    Quit tSC
}

}
