/// <p>Unit tests for <CLASS>SessionAgent.LLM.Util.ToolDefAdapter</CLASS>
/// (Story 2.8). Locks the canonical→provider tool-definition translation
/// contract for the four LLM providers shipped in v1.</p>
///
/// <p><b>AC-4 method coverage:</b></p>
/// <ol>
/// <li><b>TestCanonicalToOpenAiWraps</b> — each canonical tool wraps in
/// <code>{type:"function", function:{name, description,
/// parameters:&lt;input_schema&gt;}}</code>.</li>
/// <li><b>TestCanonicalToGeminiSingleObject</b> — all canonical tools
/// fold into ONE <code>{functionDeclarations:[...]}</code> object.</li>
/// <li><b>TestCanonicalToAnthropicPassthrough</b> — anthropic provider
/// returns the input unchanged.</li>
/// </ol>
Class SessionAgent.Test.ToolDefAdapterTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accept the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects, call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-4 #1 — feed two canonical tools, assert the OpenAI output is a
/// 2-element array of <code>{type:"function", function:{...}}</code>
/// wrappers with name / description / parameters preserved.</p>
Method TestCanonicalToOpenAiWraps()
{
    Set tCanon = ..BuildTwoToolDefs()
    Set tOut = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider("openai", tCanon)

    Do $$$AssertEquals(tOut.%Size(), 2, "OpenAI output has 2 wrappers (one per tool)")

    Set tWrap0 = tOut.%Get(0)
    Do $$$AssertEquals(tWrap0.%Get("type"), "function", "wrapper 0: type = function")
    Set tFn0 = tWrap0.%Get("function")
    Do $$$AssertEquals(tFn0.%Get("name"), "FindSession", "wrapper 0: function.name preserved")
    Do $$$AssertEquals(tFn0.%Get("description"), "Find an Ensemble session by id or query", "wrapper 0: function.description preserved")
    Set tParams0 = tFn0.%Get("parameters")
    Do $$$AssertEquals(tParams0.%Get("type"), "object", "wrapper 0: function.parameters carries input_schema (type=object)")
    Do $$$AssertTrue(tParams0.%IsDefined("properties"), "wrapper 0: function.parameters has properties")

    Set tWrap1 = tOut.%Get(1)
    Set tFn1 = tWrap1.%Get("function")
    Do $$$AssertEquals(tFn1.%Get("name"), "GetMessageDetail", "wrapper 1: function.name preserved")
    Quit
}

/// <p>AC-4 #2 — feed two canonical tools, assert the Gemini output is a
/// 1-element array containing a single
/// <code>{functionDeclarations:[...]}</code> object that holds BOTH tools
/// in its declarations array. (Per-tool wrapping would be a wire-shape
/// error — Gemini rejects it.)</p>
Method TestCanonicalToGeminiSingleObject()
{
    Set tCanon = ..BuildTwoToolDefs()
    Set tOut = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider("gemini", tCanon)

    Do $$$AssertEquals(tOut.%Size(), 1, "Gemini output has exactly 1 wrapper element (not per-tool)")
    Set tWrap = tOut.%Get(0)
    Do $$$AssertTrue(tWrap.%IsDefined("functionDeclarations"), "Gemini wrapper has functionDeclarations field")
    Set tDecls = tWrap.%Get("functionDeclarations")
    Do $$$AssertEquals(tDecls.%Size(), 2, "functionDeclarations contains BOTH tools (size=2)")

    Set tD0 = tDecls.%Get(0)
    Do $$$AssertEquals(tD0.%Get("name"), "FindSession", "decl 0: name preserved")
    Do $$$AssertEquals(tD0.%Get("description"), "Find an Ensemble session by id or query", "decl 0: description preserved")
    Set tD0Params = tD0.%Get("parameters")
    Do $$$AssertEquals(tD0Params.%Get("type"), "object", "decl 0: parameters carries input_schema")

    Set tD1 = tDecls.%Get(1)
    Do $$$AssertEquals(tD1.%Get("name"), "GetMessageDetail", "decl 1: name preserved")
    Quit
}

/// <p>AC-4 #3 — anthropic passthrough: input array reference returned
/// unchanged. Spot-check shape preservation.</p>
Method TestCanonicalToAnthropicPassthrough()
{
    Set tCanon = ..BuildTwoToolDefs()
    Set tOut = ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToProvider("anthropic", tCanon)

    Do $$$AssertEquals(tOut.%Size(), tCanon.%Size(), "Anthropic passthrough preserves array size")
    Do $$$AssertEquals(tOut.%Get(0).%Get("name"), "FindSession", "Anthropic passthrough preserves tool 0 name")
    Do $$$AssertEquals(tOut.%Get(0).%Get("input_schema").%Get("type"), "object", "Anthropic passthrough preserves input_schema (NOT renamed to parameters)")
    Do $$$AssertEquals(tOut.%Get(1).%Get("name"), "GetMessageDetail", "Anthropic passthrough preserves tool 1 name")
    Quit
}

/// <p>Internal helper — build a 2-tool canonical tool-defs array with
/// realistic shape. Both tools have type=object input_schema with a
/// properties block.</p>
ClassMethod BuildTwoToolDefs() As %DynamicArray [ Internal ]
{
    Set tDefs = ##class(%DynamicArray).%New()

    ; Tool 0
    Set t0 = ##class(%DynamicObject).%New()
    Do t0.%Set("name", "FindSession")
    Do t0.%Set("description", "Find an Ensemble session by id or query")
    Set t0Schema = ##class(%DynamicObject).%New()
    Do t0Schema.%Set("type", "object")
    Set t0Props = ##class(%DynamicObject).%New()
    Set t0Q = ##class(%DynamicObject).%New()
    Do t0Q.%Set("type", "string")
    Do t0Props.%Set("query", t0Q)
    Do t0Schema.%Set("properties", t0Props)
    Do t0.%Set("input_schema", t0Schema)
    Do tDefs.%Push(t0)

    ; Tool 1
    Set t1 = ##class(%DynamicObject).%New()
    Do t1.%Set("name", "GetMessageDetail")
    Do t1.%Set("description", "Return the body of a message in a session")
    Set t1Schema = ##class(%DynamicObject).%New()
    Do t1Schema.%Set("type", "object")
    Set t1Props = ##class(%DynamicObject).%New()
    Set t1MsgId = ##class(%DynamicObject).%New()
    Do t1MsgId.%Set("type", "string")
    Do t1Props.%Set("message_id", t1MsgId)
    Do t1Schema.%Set("properties", t1Props)
    Do t1.%Set("input_schema", t1Schema)
    Do tDefs.%Push(t1)

    Quit tDefs
}

}
