/// <p>Canonical-to-provider tool-definition adapter. Translates the
/// canonical Anthropic tool-definition shape (<code>{name, description,
/// input_schema}</code>) into the OpenAI / Gemini / OpenAI-compatible
/// wire shapes. Sister class to
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> — both ship in
/// Story 2.8 because the adapter pattern is one design surface and one
/// review.</p>
///
/// <p><b>Canonical (Anthropic) tool definition shape:</b></p>
/// <pre>
/// [
///   {name: "FindSession", description: "...", input_schema: {type:"object", properties:{...}}},
///   ...
/// ]
/// </pre>
///
/// <p><b>Anthropic.</b> Passthrough.</p>
///
/// <p><b>OpenAI / OpenAI-compatible.</b> Wrap each tool in
/// <code>{type:"function", function:{name, description,
/// parameters:&lt;input_schema&gt;}}</code> per the OpenAI Chat Completions
/// tool-definition spec. The output is an array of these wrappers, one
/// per canonical entry.</p>
///
/// <p><b>Gemini.</b> Wrap <b>all</b> tools in a <b>single</b>
/// <code>{functionDeclarations: [{name, description,
/// parameters:&lt;input_schema&gt;}]}</code> object — Gemini's
/// generateContent tool spec groups declarations under one
/// <code>functionDeclarations</code> array, then the whole thing goes
/// inside the request's <code>tools</code> array as a single element.
/// The output is a one-element array containing this wrapper object.
/// (Per-tool wrapping would be a wire-shape error — Gemini rejects it
/// with a 400 InvalidArgument.)</p>
///
/// <p><b>Unknown providers.</b> Passthrough — never throw on the LLM
/// hot path.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.8</a> AC-3 — adapter contract.</li>
/// <li>OpenAI tools spec:
/// https://platform.openai.com/docs/guides/function-calling</li>
/// <li>Gemini function-calling spec:
/// https://ai.google.dev/gemini-api/docs/function-calling
/// (single functionDeclarations array per tools[] element).</li>
/// </ul>
Class SessionAgent.LLM.Util.ToolDefAdapter Extends %RegisteredObject
{

/// <p>Provider name constants — kept identical to those in
/// <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS> so the dispatch
/// values are coordinated across both adapters.</p>
Parameter PROVIDERANTHROPIC = "anthropic";

Parameter PROVIDEROPENAI = "openai";

Parameter PROVIDERGEMINI = "gemini";

Parameter PROVIDEROPENAICOMPAT = "openai-compatible";

/// <p>Translate canonical tool definitions into the named provider's
/// wire shape. Returns a fresh <CLASS>%DynamicArray</CLASS>; the input
/// is never mutated.</p>
ClassMethod CanonicalToProvider(pProviderName As %String, pCanonicalToolDefs As %DynamicArray) As %DynamicArray
{
    If '$IsObject(pCanonicalToolDefs) {
        Quit ##class(%DynamicArray).%New()
    }

    If pProviderName = ..#PROVIDERANTHROPIC {
        Quit pCanonicalToolDefs
    }
    If (pProviderName = ..#PROVIDEROPENAI) || (pProviderName = ..#PROVIDEROPENAICOMPAT) {
        Quit ..CanonicalToOpenAi(pCanonicalToolDefs)
    }
    If pProviderName = ..#PROVIDERGEMINI {
        Quit ..CanonicalToGemini(pCanonicalToolDefs)
    }

    ; Unknown — passthrough.
    Quit pCanonicalToolDefs
}

/// <p>Internal — canonical → OpenAI tool array. Per-tool wrap.</p>
ClassMethod CanonicalToOpenAi(pCanonical As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set tOut = ##class(%DynamicArray).%New()
    Set tIter = pCanonical.%GetIterator()
    While tIter.%GetNext(.tIdx, .tTool) {
        If '$IsObject(tTool) Continue
        Set tWrap = ##class(%DynamicObject).%New()
        Do tWrap.%Set("type", "function")
        Set tFn = ##class(%DynamicObject).%New()
        If tTool.%IsDefined("name") {
            Do tFn.%Set("name", tTool.%Get("name"))
        }
        If tTool.%IsDefined("description") {
            Do tFn.%Set("description", tTool.%Get("description"))
        }
        If tTool.%IsDefined("input_schema") {
            Do tFn.%Set("parameters", tTool.%Get("input_schema"))
        }
        Do tWrap.%Set("function", tFn)
        Do tOut.%Push(tWrap)
    }
    Quit tOut
}

/// <p>Internal — canonical → Gemini tool array. ALL canonical tools
/// fold into ONE <code>functionDeclarations</code> array inside ONE
/// <code>tools</code>-array element. The result is therefore a one-element
/// array even when the input has many tools.</p>
ClassMethod CanonicalToGemini(pCanonical As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set tDecls = ##class(%DynamicArray).%New()
    Set tIter = pCanonical.%GetIterator()
    While tIter.%GetNext(.tIdx, .tTool) {
        If '$IsObject(tTool) Continue
        Set tDecl = ##class(%DynamicObject).%New()
        If tTool.%IsDefined("name") {
            Do tDecl.%Set("name", tTool.%Get("name"))
        }
        If tTool.%IsDefined("description") {
            Do tDecl.%Set("description", tTool.%Get("description"))
        }
        If tTool.%IsDefined("input_schema") {
            Do tDecl.%Set("parameters", tTool.%Get("input_schema"))
        }
        Do tDecls.%Push(tDecl)
    }

    Set tWrap = ##class(%DynamicObject).%New()
    Do tWrap.%Set("functionDeclarations", tDecls)

    Set tOut = ##class(%DynamicArray).%New()
    Do tOut.%Push(tWrap)
    Quit tOut
}

}
