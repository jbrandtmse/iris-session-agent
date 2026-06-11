/// <p>Inspection tool — list a class's methods (own + inherited) via
/// <CLASS>%Dictionary.CompiledMethod</CLASS> reflection. Third of three
/// BP-introspection tools shipped by Story 4.4 (alongside
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS>
/// and <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessInstance</CLASS>).</p>
///
/// <p><b>Tool name:</b> <code>list_business_process_methods</code>.
/// Read-only (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{bp_class_name (required)}</code>.</p>
///
/// <p><b>Why <CLASS>%Dictionary.CompiledMethod</CLASS> over
/// <CLASS>%Dictionary.MethodDefinition</CLASS>.</b> Operators asking
/// *"what methods does <code>BP.OrderRouter</code> have"* expect to see
/// inherited <code>Ens.BusinessProcess</code> + <code>Ens.Host</code>
/// methods too. <code>%Dictionary.CompiledMethod</code> includes
/// inherited methods (each method has an <code>Origin</code> column
/// naming the declaring class); <code>%Dictionary.MethodDefinition</code>
/// shows only locally-declared methods. The companion
/// <CLASS>SessionAgent.Tool.Inspection.GetBusinessProcessSource</CLASS>
/// tool already surfaces the locally-declared view via
/// <code>%Dictionary.ClassDefinition.Methods</code>, so this tool's job
/// is the post-inheritance / compiled view.</p>
///
/// <p><b>Filtering rules (Task-0 probe finding, 2026-05-04 — Rule 8 fix-now).</b>
/// Story spec line 117 prescribed
/// <code>%Dictionary.CompiledMethod_PropertyDefinition('%Dictionary.CompiledMethod')</code>
/// — that table-valued function does NOT exist on this IRIS install
/// (SQLCODE -30 "function not found"). Switched to plain
/// <code>SELECT FROM %Dictionary.CompiledMethod WHERE Parent = ?</code>.
/// However the unfiltered query returns 759 rows for
/// <code>SessionAgent.Sample.BP.OrderRouter</code> — most are
/// auto-generated property accessors with empty <code>Origin</code> /
/// no formal spec. Apply these filters:</p>
/// <ul>
/// <li><code>CompilerGenerated = 0</code> — excludes IRIS-generated
/// accessors / serializers / etc.</li>
/// <li><code>Internal = 0</code> — excludes methods flagged
/// <code>[Internal]</code> by their author.</li>
/// <li><code>Origin &lt;&gt; ''</code> — excludes auto-generated property
/// accessor wrappers that have no explicit declaring class.</li>
/// <li><code>NOT Name LIKE '%%%'</code> — excludes
/// <code>%%</code>-prefixed compiler scaffolding methods.</li>
/// </ul>
///
/// <p>The filtered result for <code>SessionAgent.Sample.BP.OrderRouter</code>
/// is the operator-meaningful set: own methods (<code>OnRequest</code>,
/// <code>OnResponse</code>, <code>OnError</code>, <code>OnComplete</code>,
/// <code>buildResponse</code>) plus inherited methods from
/// <code>Ens.BusinessProcess</code>, <code>Ens.Host</code>,
/// <code>Ens.Settings</code>, and the <code>%Library.Persistent</code>
/// /<code>%Library.SwizzleObject</code> / <code>%Library.RegisteredObject</code>
/// chain (~141 rows on the live install — empirically confirmed at code
/// review time, 2026-05-04). The original spec hand-estimate of "44 rows"
/// excluded the inherited persistence/serializer methods that operators
/// legitimately want to see when introspecting a BP class.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{class_name, exists, methods:[{name, signature, return_type,
/// formal_args, comment, is_classmethod, origin}], method_count}</code>.
/// Signature shape: <code>name(formal_args) As return_type</code> for
/// instance methods; prepended with <code>"ClassMethod "</code> for
/// class methods.</p>
///
/// <p><b>Class-not-found.</b> If no rows match
/// <code>Parent = bp_class_name</code>, the result is
/// <code>{class_name, exists:false, methods:[], method_count:0,
/// render_strategy:"class_not_found"}</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.4</a> AC-7..9 — AC source.</li>
/// <li><a href="../../../../irislib/%25Dictionary/CompiledMethod.cls">irislib/%Dictionary/CompiledMethod.cls</a> —
/// columns: <code>Name</code>, <code>FormalSpec</code>, <code>ReturnType</code>,
/// <code>Description</code>, <code>ClassMethod</code>, <code>Origin</code>,
/// <code>CompilerGenerated</code>, <code>Internal</code>, <code>Parent</code>.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.ListBusinessProcessMethods Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "list_business_process_methods";

Parameter Description As %String = "List a class's compiled methods (own + inherited) with signatures via %Dictionary.CompiledMethod reflection, filtered to the operator-meaningful set (excludes compiler-generated, internal, and origin-less scaffolding).";

Parameter MutatesState As %Boolean = 0;

/// <p>Locked-subset JSON Schema. Required: <code>bp_class_name</code>.
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "bp_class_name": {"type": "string", "description": "Full class name (e.g., SessionAgent.Sample.BP.OrderRouter). Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.BP.OrderRouter', not 'SessionAgent.Sample.BP.OrderRouter.OnRequest')."}
        },
        "required": ["bp_class_name"],
        "additionalProperties": false
    }
}

/// <p>Run the filtered <CLASS>%Dictionary.CompiledMethod</CLASS> query
/// and project each row into a method entry. Class-absence surfaces as
/// <code>exists:false, render_strategy:"class_not_found"</code>.</p>
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

        ; Filtered SELECT against %Dictionary.CompiledMethod. Filters per
        ; Task-0 probe finding to reduce 759 raw rows to the ~44 operator-
        ; meaningful methods.
        Set tSql = "SELECT %EXACT(Name) AS name, FormalSpec AS formal_spec, %EXACT(ReturnType) AS return_type, %EXACT(Description) AS description, ClassMethod AS is_classmethod, %EXACT(Origin) AS origin FROM %Dictionary.CompiledMethod WHERE Parent = ? AND CompilerGenerated = 0 AND Internal = 0 AND %EXACT(Origin) <> '' AND NOT Name %STARTSWITH '%%' ORDER BY Name"
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCprep = tStmt.%Prepare(tSql)
        ; Story 11.2 — centralized prepare-failure gate.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCprep, ..#ToolName) Quit
        Set tRs = tStmt.%Execute(tClassName)
        ; Story 14.0 — centralized execute-failure gate (cr-13-3).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRs, ..#ToolName) Quit

        Set tMethods = []
        Set tMethodCount = 0
        While tRs.%Next() {
            Set tName = tRs.%Get("name")
            Set tFormal = tRs.%Get("formal_spec")
            Set tReturn = tRs.%Get("return_type")
            Set tDesc = tRs.%Get("description")
            Set tIsClassMethod = +tRs.%Get("is_classmethod")
            Set tOrigin = tRs.%Get("origin")
            ; signature shape
            Set tSig = tName _ "(" _ tFormal _ ")"
            If tReturn '= "" {
                Set tSig = tSig _ " As " _ tReturn
            }
            If tIsClassMethod {
                Set tSig = "ClassMethod " _ tSig
            }
            Set tEntry = {}
            Do tEntry.%Set("name", tName)
            Do tEntry.%Set("signature", tSig)
            Do tEntry.%Set("return_type", tReturn)
            Do tEntry.%Set("formal_args", tFormal)
            Do tEntry.%Set("comment", tDesc)
            Do tEntry.%Set("is_classmethod", tIsClassMethod, "boolean")
            Do tEntry.%Set("origin", tOrigin)
            Do tMethods.%Push(tEntry)
            Set tMethodCount = tMethodCount + 1
        }

        If tMethodCount = 0 {
            ; Distinguish "no methods after filtering" from "class doesn't
            ; exist". Probe %Dictionary.ClassDefinition for class existence.
            Set tClsExists = ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName)
            If 'tClsExists {
                Do pResult.structuredContent.%Set("class_name", tClassName)
                Do pResult.structuredContent.%Set("exists", 0, "boolean")
                Do pResult.structuredContent.%Set("methods", [])
                Do pResult.structuredContent.%Set("method_count", 0, "number")
                Do pResult.structuredContent.%Set("render_strategy", "class_not_found")
                Set pResult.content.%Get(0).text = "class not found: " _ tClassName
                Quit
            }
        }

        Do pResult.structuredContent.%Set("class_name", tClassName)
        Do pResult.structuredContent.%Set("exists", 1, "boolean")
        Do pResult.structuredContent.%Set("methods", tMethods)
        Do pResult.structuredContent.%Set("method_count", tMethodCount, "number")
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Set pResult.content.%Get(0).text = tClassName _ ": " _ tMethodCount _ " methods (filtered to operator-meaningful set)"
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
