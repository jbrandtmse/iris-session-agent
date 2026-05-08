/// <p>Inspection tool — open and render the body referenced by an
/// <CLASS>Ens.MessageHeader</CLASS> row via a runtime 9-step dispatch
/// ladder over body-class shape. Most-complex tool in Epic 4 — the
/// ladder is the only path bodies of unknown class can be safely
/// rendered because <CLASS>Ens.MessageHeader</CLASS> bodies are
/// dynamically typed (architecture §"Body-class dispatch chain",
/// research §"Body-Class Resolution: The Full Pattern").</p>
///
/// <p><b>Tool name:</b> <code>get_message_body</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{message_id (required), format?}</code>.
/// <code>format</code> enum <code>raw | summary</code> (default
/// <code>summary</code>). <code>raw</code> returns full body content
/// where the dispatch path supports it (full HL7 ER7 string, full
/// <code>%JSONExportToString</code> output, full
/// <code>XMLExportToString</code> output, first
/// <parameter>StreamReadLimit</parameter> bytes of stream).
/// <code>summary</code> truncates <code>body_repr</code> to ≤256
/// chars after rendering.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{message_id, body_class, body_id, render_strategy, body_repr,
/// truncated, ...}</code> where the <code>...</code> permits per-
/// strategy extras (HL7 step 3 adds <code>segment_count</code>,
/// <code>message_type</code>; Step 7 adds a property map).</p>
///
/// <p><b>9-step ladder (per epics.md line 1478, summarized):</b></p>
/// <ol>
/// <li>Header lookup — <code>SELECT MessageBodyClassName, MessageBodyId
/// FROM Ens.MessageHeader WHERE ID = ?</code> with <code>%EXACT()</code>.
/// Missing row → <code>render_strategy="header_not_found"</code>.</li>
/// <li>Empty-body short-circuit — if <code>MessageBodyId=""</code> after
/// step 1 → <code>render_strategy="no_body"</code> (DOES NOT enter step 2).</li>
/// <li>Body open — <code>$ClassMethod(class, "%OpenId", id, .tSC)</code>
/// inside Try/Catch. Failure or NULLOREF →
/// <code>render_strategy="body_not_found"</code>.</li>
/// <li>HL7 — <code>%Extends("EnsLib.HL7.Message")</code> →
/// <method>RenderHL7</method> (uses <code>OutputToString</code>,
/// <code>Name</code>, <code>SegCount</code> calculated properties).</li>
/// <li><code>%JSON.Adaptor</code> (and NOT <code>Ens.MessageBody</code>) →
/// <method>RenderJsonAdaptor</method>.</li>
/// <li><code>%XML.Adaptor</code> (and NOT <code>Ens.MessageBody</code>) →
/// <method>RenderXmlAdaptor</method>.</li>
/// <li><code>%Stream.Object</code> → <method>RenderStream</method>.</li>
/// <li><code>Ens.MessageBody</code> → <method>RenderEnsMessageBody</method>
/// (property reflection via <code>%Dictionary.CompiledClass</code>).</li>
/// <li>generic <code>%Persistent</code> → <method>RenderPersistent</method>
/// (property reflection same shape, but tagged differently).</li>
/// </ol>
///
/// <p>Step 9 (fallback) — unknown shape →
/// <code>render_strategy="unknown"</code>, <code>dispatch_failed:1</code>,
/// <code>fallback_repr=body_class_"_"_body_id</code>.</p>
///
/// <p><b>Class-level dispatch discriminator.</b> The ladder uses
/// <code>$ClassMethod(<class>, "%Extends", "<root>")</code> for steps
/// 4–8, NOT <code>%IsA</code>. Reason: <code>%XML.Adaptor</code> /
/// <code>%JSON.Adaptor</code> are Abstract mixin classes — instance-
/// level <code>tBody.%IsA("%XML.Adaptor")</code> returns 0 even when the
/// class chain extends them (Task-0 probe finding, 2026-05-04).
/// <code>%Extends</code> is the class-lineage check that returns the
/// correct answer for both Abstract mixins and concrete subclasses.</p>
///
/// <p><b>Step 5 / Step 7 exclusion guard (Rule 8 fix-now).</b>
/// <code>Ens.MessageBody</code> extends <code>%XML.Adaptor</code> for
/// storage projection — every <code>Ens.MessageBody</code> subclass
/// would otherwise dispatch to Step 5 XML export instead of Step 7's
/// more readable property reflection. Step 5 predicate therefore
/// includes <code>AND NOT %Extends("Ens.MessageBody")</code>; same
/// exclusion symmetric on Step 4.</p>
///
/// <p><b>StreamReadLimit truncation.</b> Step 6 caps stream reads at
/// <parameter>StreamReadLimit</parameter> bytes (~3 KB). Sets
/// <code>truncated=1</code> if <code>..AtEnd=0</code> after the read,
/// else <code>0</code>. Other branches set <code>truncated=0</code>
/// in raw mode and <code>truncated=1</code> in summary mode if the
/// rendered text exceeded 256 chars.</p>
///
/// <p><b>No throws.</b> Every branch returns a structured envelope.
/// Any unexpected exception in the outer Try/Catch →
/// <code>render_strategy="dispatch_error"</code>, <code>isError=1</code>.
/// Exceptions never escape <method>Invoke</method>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.2</a> (lines 1478–1512) — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/research/technical-ensemble-session-inspection-agent-research-2026-04-24.md">research</a>
/// §"Body-Class Resolution: The Full Pattern" (lines 379–435).</li>
/// <li><a href="../../../../irislib/Ens/MessageHeader.cls">irislib/Ens/MessageHeader.cls</a>,
/// <a href="../../../../irislib/EnsLib/HL7/Message.cls">EnsLib/HL7/Message.cls</a>,
/// <a href="../../../../irislib/%25JSON/Adaptor.cls">%JSON/Adaptor.cls</a>,
/// <a href="../../../../irislib/%25XML/Adaptor.cls">%XML/Adaptor.cls</a>,
/// <a href="../../../../irislib/%25Stream/Object.cls">%Stream/Object.cls</a>,
/// <a href="../../../../irislib/Ens/MessageBody.cls">Ens/MessageBody.cls</a>,
/// <a href="../../../../irislib/%25Dictionary/CompiledClass.cls">%Dictionary/CompiledClass.cls</a>.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetMessageBody Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_message_body";

Parameter Description As %String = "Open and render a message body via the runtime body-class dispatch ladder.";

Parameter MutatesState As %Boolean = 0;

/// <p>Hard cap (in bytes/chars) on the amount read from a
/// <CLASS>%Stream.Object</CLASS> body in step 6. ~3 KB; documented in
/// epics.md spec line 1496 as the truncation threshold.</p>
Parameter StreamReadLimit As %Integer = 3072;

/// <p>Hard cap on rendered <code>body_repr</code> length in
/// <code>summary</code> format. Beyond this, <code>body_repr</code> is
/// truncated and <code>truncated=1</code>.</p>
Parameter SummaryReprLimit As %Integer = 256;

/// <p>Locked-subset JSON Schema. Required: <code>message_id</code>.
/// Optional <code>format</code> with enum <code>raw | summary</code>.
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "message_id": {"type": "string", "description": "Ens.MessageHeader id"},
            "format": {"type": "string", "description": "Render format. raw returns full body where supported; summary truncates body_repr to <=256 chars.", "enum": ["raw", "summary"]}
        },
        "required": ["message_id"],
        "additionalProperties": false
    }
}

/// <p>Run the 9-step ladder. Outer Try/Catch catches any unexpected
/// exception and returns the standard error envelope —
/// <code>Invoke</code> NEVER lets an exception escape.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; ---- Pre-validation ----
        Set tMessageId = ""
        Set tFormat = "summary"
        If $IsObject($Get(pJsonArgs)) {
            Set tMessageId = pJsonArgs.%Get("message_id")
            Set tFormatArg = pJsonArgs.%Get("format")
            Set:tMessageId=$$$NULLOREF tMessageId = ""
            If (tFormatArg '= $$$NULLOREF) && (tFormatArg '= "") {
                Set tFormat = tFormatArg
            }
        }
        If tMessageId = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing message_id"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing message_id"}}
            Quit
        }
        ; Story 3.0 AC-3 case-insensitive enum normalization.
        Set tFormatNormalized = $ZConvert($ZStrip(tFormat, "<>W"), "L")
        If (tFormatNormalized '= "raw") && (tFormatNormalized '= "summary") {
            Set tFmtErr = "format must be one of: raw, summary (got: " _ tFormat _ ")"
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tFmtErr)}], "structuredContent":{"render_strategy":"validation_error", "error_text":(tFmtErr)}}
            Quit
        }
        Set tFormat = tFormatNormalized

        ; ---- Step 1 — header lookup ----
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSCprep = tStmt.%Prepare("SELECT %EXACT(MessageBodyClassName) AS body_class, %EXACT(MessageBodyId) AS body_id FROM Ens.MessageHeader WHERE ID = ?")
        ; Story 11.2 — centralized prepare-failure gate.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCprep, ..#ToolName) Quit
        Set tRs = tStmt.%Execute(tMessageId)
        Set tBodyClass = ""
        Set tBodyId = ""
        Set tFound = 0
        If tRs.%Next() {
            Set tBodyClass = tRs.%Get("body_class")
            Set tBodyId = tRs.%Get("body_id")
            ; Normalize the IRIS legacy %String null sentinel ($Char(0))
            ; that surfaces from rows whose column was assigned an
            ; empty string at INSERT time. Treat $Char(0) as "" for
            ; the dispatch ladder — operators don't care about the
            ; storage-encoding artifact.
            If tBodyClass = $Char(0) Set tBodyClass = ""
            If tBodyId = $Char(0) Set tBodyId = ""
            Set tFound = 1
        }
        If 'tFound {
            Do pResult.structuredContent.%Set("message_id", tMessageId)
            Do pResult.structuredContent.%Set("body_class", "")
            Do pResult.structuredContent.%Set("body_id", "")
            Do pResult.structuredContent.%Set("render_strategy", "header_not_found")
            Do pResult.structuredContent.%Set("body_repr", "")
            Do pResult.structuredContent.%Set("truncated", 0, "boolean")
            Set pResult.content.%Get(0).text = "no Ens.MessageHeader row for id " _ tMessageId
            Quit
        }

        ; ---- Step 1.5 — empty-body short-circuit (per epics.md AC line 1510-1512) ----
        If tBodyId = "" {
            Do pResult.structuredContent.%Set("message_id", tMessageId)
            Do pResult.structuredContent.%Set("body_class", tBodyClass)
            Do pResult.structuredContent.%Set("body_id", "")
            Do pResult.structuredContent.%Set("render_strategy", "no_body")
            Do pResult.structuredContent.%Set("body_repr", "")
            Do pResult.structuredContent.%Set("truncated", 0, "boolean")
            Set pResult.content.%Get(0).text = "message " _ tMessageId _ " has no body (MessageBodyId is empty)"
            Quit
        }

        ; ---- Step 2 — body open ----
        Set tBody = $$$NULLOREF
        Set tOpenSC = $$$OK
        Try {
            Set tBody = $ClassMethod(tBodyClass, "%OpenId", tBodyId, .tOpenSC)
        } Catch openEx {
            Set tOpenSC = openEx.AsStatus()
            Set tBody = $$$NULLOREF
        }
        If $$$ISERR(tOpenSC) || (tBody = $$$NULLOREF) {
            Do pResult.structuredContent.%Set("message_id", tMessageId)
            Do pResult.structuredContent.%Set("body_class", tBodyClass)
            Do pResult.structuredContent.%Set("body_id", tBodyId)
            Do pResult.structuredContent.%Set("render_strategy", "body_not_found")
            Do pResult.structuredContent.%Set("body_repr", "")
            Do pResult.structuredContent.%Set("truncated", 0, "boolean")
            Set pResult.content.%Get(0).text = "could not open body " _ tBodyClass _ ":" _ tBodyId
            Quit
        }

        ; ---- Steps 3-9 — typed dispatch via class-level %Extends ----
        Set tStrategy = ""
        Set tInner = {}
        Do tInner.%Set("message_id", tMessageId)
        Do tInner.%Set("body_class", tBodyClass)
        Do tInner.%Set("body_id", tBodyId)

        ; Step 3 — HL7 (%Extends("EnsLib.HL7.Message")). Tested first as
        ; the most-specific concrete virtual-doc class.
        If ..ClassExtends(tBodyClass, "EnsLib.HL7.Message") {
            Set tStrategy = "hl7"
            Do ..RenderHL7(tBody, tFormat, tInner)
        }
        ; Step 4 — %JSON.Adaptor (excluding Ens.MessageBody — those go
        ; to Step 7 reflection).
        ElseIf ..ClassExtends(tBodyClass, "%JSON.Adaptor") && '..ClassExtends(tBodyClass, "Ens.MessageBody") {
            Set tStrategy = "json_adaptor"
            Set tStrategy = ..RenderJsonAdaptor(tBody, tFormat, tInner, tStrategy)
        }
        ; Step 5 — %XML.Adaptor (excluding Ens.MessageBody — those go to
        ; Step 7 reflection; Ens.MessageBody auto-extends %XML.Adaptor for
        ; storage projection).
        ElseIf ..ClassExtends(tBodyClass, "%XML.Adaptor") && '..ClassExtends(tBodyClass, "Ens.MessageBody") {
            Set tStrategy = "xml_adaptor"
            Set tStrategy = ..RenderXmlAdaptor(tBody, tFormat, tInner, tStrategy)
        }
        ; Step 6 — %Stream.Object.
        ElseIf ..ClassExtends(tBodyClass, "%Stream.Object") {
            Set tStrategy = "stream"
            Do ..RenderStream(tBody, tFormat, tInner)
        }
        ; Step 7 — Ens.MessageBody (reflection over CompiledClass.Properties).
        ElseIf ..ClassExtends(tBodyClass, "Ens.MessageBody") {
            Set tStrategy = "ens_message_body"
            Do ..RenderEnsMessageBody(tBody, tBodyClass, tFormat, tInner)
        }
        ; Step 8 — generic %Persistent (or registered object) — same
        ; reflection but tagged differently.
        ElseIf ..ClassExtends(tBodyClass, "%Persistent") || ..ClassExtends(tBodyClass, "%RegisteredObject") {
            Set tStrategy = "persistent"
            Do ..RenderPersistent(tBody, tBodyClass, tFormat, tInner)
        }
        ; Step 9 — fallback.
        Else {
            Set tStrategy = "unknown"
            Do tInner.%Set("dispatch_failed", 1, "boolean")
            Do tInner.%Set("fallback_repr", tBodyClass _ "_" _ tBodyId)
            Do tInner.%Set("body_repr", "")
            Do tInner.%Set("truncated", 0, "boolean")
        }
        Do tInner.%Set("render_strategy", tStrategy)

        ; Apply summary truncation post-render. Raw mode never truncates
        ; here (HL7/JSON/XML branches return full repr); summary mode caps
        ; body_repr to SummaryReprLimit chars.
        If tFormat = "summary" {
            Set tRepr = tInner.%Get("body_repr")
            If $Length(tRepr) > ..#SummaryReprLimit {
                Do tInner.%Set("body_repr", $Extract(tRepr, 1, ..#SummaryReprLimit))
                Do tInner.%Set("truncated", 1, "boolean")
            }
        }

        Set pResult.structuredContent = tInner

        ; Operator-readable summary text.
        Set pResult.content.%Get(0).text = ..BuildSummaryText(tStrategy, tInner)
        Quit
    }
    Catch ex {
        ; No-throw guarantee — convert any escaping exception to the
        ; standard envelope. Step name "dispatch_error" makes the failure
        ; mode explicit in structuredContent for callers that key off
        ; render_strategy. Story 4.7 AC-7 — operator-friendly catch text
        ; via the FormatExceptionForOperator helper (Story 4.5 R-4 fix).
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"dispatch_error", "error_text":(tErrText)}}
    }
    Quit tSC
}

/// <p>Class-level mixin/lineage check. Wraps
/// <code>$ClassMethod(pClass, "%Extends", pRoot)</code> in a Try/Catch
/// because a malformed body class name (typo, deleted class) would
/// otherwise crash the ladder. Returns 0 on any failure path.</p>
ClassMethod ClassExtends(pClass As %String, pRoot As %String) As %Boolean
{
    Set tResult = 0
    Try {
        Set tResult = $ClassMethod(pClass, "%Extends", pRoot)
    }
    Catch ex {
        Set tResult = 0
    }
    Quit ''tResult
}

/// <p>Step 3 — render an <CLASS>EnsLib.HL7.Message</CLASS> body. Uses
/// <code>OutputToString(.pSeparators, .pSequenceNumber, .pStatus,
/// .pIOFormatClassname)</code> for the ER7 string;
/// <code>Name</code> calculated property for the message type
/// (e.g. "ORM_O01"); <code>SegCount</code> calculated property for
/// segment count. Sets <code>body_repr</code> to the ER7 in raw mode;
/// to a single-line summary in summary mode.</p>
ClassMethod RenderHL7(pBody As %RegisteredObject, pFormat As %String, pInner As %DynamicObject)
{
    Set tMessageType = ""
    Set tSegCount = 0
    Set tEr7 = ""
    Try { Set tMessageType = pBody.Name }
    Catch ex { Set tMessageType = "" }
    Try { Set tSegCount = +pBody.SegCount }
    Catch ex { Set tSegCount = 0 }
    Try {
        Set tStatus = $$$OK
        Set tEr7 = pBody.OutputToString(, , .tStatus)
        If $$$ISERR(tStatus) Set tEr7 = ""
    } Catch ex {
        Set tEr7 = ""
    }
    Do pInner.%Set("message_type", tMessageType)
    Do pInner.%Set("segment_count", tSegCount, "number")
    If pFormat = "raw" {
        Do pInner.%Set("body_repr", tEr7)
        Do pInner.%Set("truncated", 0, "boolean")
    } Else {
        ; Summary — single-line, truncation handled by outer Invoke.
        Do pInner.%Set("body_repr", tEr7)
        Do pInner.%Set("truncated", 0, "boolean")
    }
    Quit
}

/// <p>Step 4 — render a body that extends <code>%JSON.Adaptor</code>.
/// Calls <code>%JSONExportToString(.tJsonStr)</code>; on success writes
/// <code>body_repr</code> = JSON string; on failure returns the special
/// strategy <code>"json_adaptor_error"</code> so callers see the
/// dispatch path attempted.</p>
ClassMethod RenderJsonAdaptor(pBody As %RegisteredObject, pFormat As %String, pInner As %DynamicObject, pStrategy As %String) As %String
{
    Set tStrategy = pStrategy
    Set tJsonStr = ""
    Set tStatus = $$$OK
    Try {
        Set tStatus = pBody.%JSONExportToString(.tJsonStr)
    }
    Catch ex {
        Set tStatus = ex.AsStatus()
    }
    If $$$ISERR(tStatus) || (tJsonStr = "") {
        Set tStrategy = "json_adaptor_error"
        Do pInner.%Set("body_repr", "")
        Do pInner.%Set("truncated", 0, "boolean")
        Do pInner.%Set("error_text", $System.Status.GetErrorText(tStatus))
    } Else {
        Do pInner.%Set("body_repr", tJsonStr)
        Do pInner.%Set("truncated", 0, "boolean")
    }
    Quit tStrategy
}

/// <p>Step 5 — render a body that extends <code>%XML.Adaptor</code> but
/// not <code>Ens.MessageBody</code>. Calls
/// <code>XMLExportToString(.tXmlStr)</code>; on failure returns
/// <code>"xml_adaptor_error"</code> strategy.</p>
ClassMethod RenderXmlAdaptor(pBody As %RegisteredObject, pFormat As %String, pInner As %DynamicObject, pStrategy As %String) As %String
{
    Set tStrategy = pStrategy
    Set tXmlStr = ""
    Set tStatus = $$$OK
    Try {
        Set tStatus = pBody.XMLExportToString(.tXmlStr)
    }
    Catch ex {
        Set tStatus = ex.AsStatus()
    }
    If $$$ISERR(tStatus) || (tXmlStr = "") {
        Set tStrategy = "xml_adaptor_error"
        Do pInner.%Set("body_repr", "")
        Do pInner.%Set("truncated", 0, "boolean")
        Do pInner.%Set("error_text", $System.Status.GetErrorText(tStatus))
    } Else {
        Do pInner.%Set("body_repr", tXmlStr)
        Do pInner.%Set("truncated", 0, "boolean")
    }
    Quit tStrategy
}

/// <p>Step 6 — render a <CLASS>%Stream.Object</CLASS> body. Reads up to
/// <parameter>StreamReadLimit</parameter> bytes from the stream;
/// <code>truncated</code> = 1 if <code>..AtEnd=0</code> after the read
/// (i.e. more content remains). Strips CR/LF for one-line summary
/// readability while keeping the raw mode faithful (raw still includes
/// CR/LF inside the read string up to the limit).</p>
ClassMethod RenderStream(pBody As %RegisteredObject, pFormat As %String, pInner As %DynamicObject)
{
    Set tBytes = ""
    Set tTruncated = 0
    Try {
        Set tLen = ..#StreamReadLimit
        ; Rewind first — defensive against streams already partially read
        ; by a prior consumer in the same process.
        Try { Do pBody.Rewind() } Catch rwEx { }
        Set tBytes = pBody.Read(.tLen)
        Set tTruncated = ('pBody.AtEnd)
    }
    Catch ex {
        Set tBytes = ""
        Set tTruncated = 0
    }
    Do pInner.%Set("body_repr", tBytes)
    Do pInner.%Set("truncated", ''tTruncated, "boolean")
    Do pInner.%Set("read_byte_count", $Length(tBytes), "number")
    Quit
}

/// <p>Step 7 — render an <CLASS>Ens.MessageBody</CLASS> subclass via
/// <code>%Dictionary.CompiledClass</code> property reflection. Iterates
/// <code>tDef.Properties</code> and skips the auto-generated /
/// non-renderable properties (Private, Calculated, MultiDimensional,
/// Internal, or Collection). Builds <code>{prop_name: value}</code> map
/// from the live <code>pBody</code> instance. <code>body_repr</code> is
/// the JSON serialization of the property map.</p>
ClassMethod RenderEnsMessageBody(pBody As %RegisteredObject, pBodyClass As %String, pFormat As %String, pInner As %DynamicObject)
{
    Do ..RenderViaPropertyReflection(pBody, pBodyClass, pInner)
    Quit
}

/// <p>Step 8 — render a generic <code>%Persistent</code> /
/// <code>%RegisteredObject</code> body. Same reflection mechanics as
/// step 7 — Step 7 vs Step 8 distinction is in the outer ladder
/// (<code>render_strategy</code>), not the rendering itself.</p>
ClassMethod RenderPersistent(pBody As %RegisteredObject, pBodyClass As %String, pFormat As %String, pInner As %DynamicObject)
{
    Do ..RenderViaPropertyReflection(pBody, pBodyClass, pInner)
    Quit
}

/// <p>Shared property-reflection renderer used by Steps 7 and 8.
/// Reads the compiled class definition, iterates non-collection
/// non-internal properties, fetches values via
/// <code>$Property(instance, name)</code>, and packs them into a
/// <code>%DynamicObject</code> property map.</p>
///
/// <p><b>Skip rules</b> (each is a sufficient skip cause):</p>
/// <ul>
/// <li><code>Private = 1</code> — internal storage (<code>%Concurrency</code>,
/// <code>%%OID</code>, etc.)</li>
/// <li><code>Internal = 1</code> — flagged "do not display in automatic
/// documentation" — same intent for our property-map rendering.</li>
/// <li><code>Calculated = 1</code> — derived; reading via
/// <code>$Property</code> may execute SQLCOMPUTECODE that is not safe
/// to run during a tool dispatch (no transaction context, no
/// <code>$$$JobSessionId</code>, etc.).</li>
/// <li><code>MultiDimensional = 1</code> — array properties have no
/// scalar JSON projection.</li>
/// <li><code>Collection != ""</code> — list/array/relationship —
/// represented as a count-only entry rather than a full enumeration
/// (avoids unbounded JSON size).</li>
/// </ul>
ClassMethod RenderViaPropertyReflection(pBody As %RegisteredObject, pBodyClass As %String, pInner As %DynamicObject)
{
    Set tMap = {}
    Set tPropertyNames = []
    Set tPropertyCount = 0
    Set tDef = $$$NULLOREF
    Try {
        Set tDef = ##class(%Dictionary.CompiledClass).%OpenId(pBodyClass)
    }
    Catch ex {
        Set tDef = $$$NULLOREF
    }
    If $IsObject(tDef) {
        For tIdx = 1:1:tDef.Properties.Count() {
            Set tPropDef = tDef.Properties.GetAt(tIdx)
            If '$IsObject(tPropDef) Continue
            ; Skip rules.
            If +tPropDef.Private Continue
            If +tPropDef.Internal Continue
            If +tPropDef.Calculated Continue
            If +tPropDef.MultiDimensional Continue
            Set tColl = tPropDef.Collection
            Set tName = tPropDef.Name
            If tName = "" Continue
            ; Collection properties — render as a count summary, not the
            ; full enumeration (keeps body_repr bounded; full enumeration
            ; deferred to a future "expand" tool if needed).
            ; Runtime collection class for declared `As list Of X` is
            ; %Collection.ListOfDT (or .ListOfObj); .Count() is the
            ; common API across both. Probe duck-typed — %Library.AbstractList
            ; is the wrong superclass per Task-0 probe (returns 0 even on
            ; live %Collection.ListOfDT instance); %Collection.AbstractList
            ; is the correct shared superclass.
            If tColl '= "" {
                Set tCollCount = -1
                Try {
                    Set tCollOref = $Property(pBody, tName)
                    If $IsObject(tCollOref) {
                        ; Try Count() — works for ListOf*, ArrayOf*,
                        ; AbstractList, AbstractArray. Wrapped in inner
                        ; Try in case some custom collection lacks it.
                        Try {
                            Set tCollCount = +tCollOref.Count()
                        } Catch innerEx {
                            Set tCollCount = -1
                        }
                    }
                }
                Catch collEx { Set tCollCount = -1 }
                Do tMap.%Set(tName, "<" _ tColl _ " of " _ tCollCount _ ">")
                Do tPropertyNames.%Push(tName)
                Set tPropertyCount = tPropertyCount + 1
                Continue
            }
            ; Scalar property — read via $Property.
            Set tVal = ""
            Try {
                Set tVal = $Property(pBody, tName)
            }
            Catch propEx {
                Set tVal = ""
            }
            ; Coerce object refs (e.g. embedded objects) to a class
            ; marker rather than letting %Set serialize them
            ; lossily.
            If $IsObject(tVal) {
                Do tMap.%Set(tName, "<" _ $ClassName(tVal) _ ">")
            } Else {
                Do tMap.%Set(tName, tVal)
            }
            Do tPropertyNames.%Push(tName)
            Set tPropertyCount = tPropertyCount + 1
        }
    }
    Do pInner.%Set("property_map", tMap)
    Do pInner.%Set("property_names", tPropertyNames)
    Do pInner.%Set("property_count", tPropertyCount, "number")
    ; body_repr is the JSON-serialized property map (operator-readable
    ; and matches the JSON-shape the LLM expects for grounding).
    Do pInner.%Set("body_repr", tMap.%ToJSON())
    Do pInner.%Set("truncated", 0, "boolean")
    Quit
}

/// <p>Build the operator-facing <code>content[0].text</code> summary line
/// (1-3 lines, <em>not</em> for the LLM grounding — that's
/// <code>structuredContent</code>). Chooses wording per
/// <code>render_strategy</code>.</p>
ClassMethod BuildSummaryText(pStrategy As %String, pInner As %DynamicObject) As %String
{
    Set tBodyClass = pInner.%Get("body_class")
    Set tBodyId = pInner.%Get("body_id")
    If pStrategy = "hl7" {
        Set tType = pInner.%Get("message_type")
        Set tCnt = +pInner.%Get("segment_count")
        Quit "HL7 " _ tType _ " message, " _ tCnt _ " segments — see body_repr for full ER7"
    }
    If pStrategy = "json_adaptor" {
        Quit "%JSON.Adaptor body of class " _ tBodyClass _ " — see body_repr for JSON"
    }
    If pStrategy = "json_adaptor_error" {
        Quit "%JSON.Adaptor export failed for " _ tBodyClass _ " — see error_text"
    }
    If pStrategy = "xml_adaptor" {
        Quit "%XML.Adaptor body of class " _ tBodyClass _ " — see body_repr for XML"
    }
    If pStrategy = "xml_adaptor_error" {
        Quit "%XML.Adaptor export failed for " _ tBodyClass _ " — see error_text"
    }
    If pStrategy = "stream" {
        Set tBytes = +pInner.%Get("read_byte_count")
        Set tTr = +pInner.%Get("truncated")
        Quit "%Stream.Object (" _ tBodyClass _ "), " _ tBytes _ " bytes read" _ $Select(tTr: " (truncated — more remains)", 1: "")
    }
    If pStrategy = "ens_message_body" {
        Set tCnt = +pInner.%Get("property_count")
        Quit "Ens.MessageBody subclass " _ tBodyClass _ ", " _ tCnt _ " properties — see property_map"
    }
    If pStrategy = "persistent" {
        Set tCnt = +pInner.%Get("property_count")
        Quit "%Persistent body " _ tBodyClass _ ", " _ tCnt _ " properties — see property_map"
    }
    If pStrategy = "header_not_found" {
        Quit "no Ens.MessageHeader row for id " _ pInner.%Get("message_id")
    }
    If pStrategy = "no_body" {
        Quit "message " _ pInner.%Get("message_id") _ " has no body (MessageBodyId is empty)"
    }
    If pStrategy = "body_not_found" {
        Quit "could not open body " _ tBodyClass _ ":" _ tBodyId
    }
    If pStrategy = "unknown" {
        Quit "no dispatch path found for body class " _ tBodyClass
    }
    Quit "render_strategy=" _ pStrategy
}

}
