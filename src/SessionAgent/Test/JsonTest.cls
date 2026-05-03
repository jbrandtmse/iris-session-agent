/// <p>Unit tests for <CLASS>SessionAgent.Util.Json</CLASS>.</p>
///
/// <p>Verifies the eight behaviors required by Story 2.1 acceptance
/// criterion AC-3:</p>
/// <ol>
/// <li><b>TestEmitNullProducesJsonNullNotString</b> — <code>EmitNull</code>
/// emits the JSON literal <code>null</code>, not the string <code>"null"</code>.</li>
/// <li><b>TestRedactNestedObjects</b> — <code>Redact</code> walks nested
/// objects and replaces matching keys at every depth.</li>
/// <li><b>TestRedactNestedArrays</b> — <code>Redact</code> descends into
/// arrays whose elements are objects.</li>
/// <li><b>TestRedactDoesNotMutateInput</b> — input object's
/// <code>%ToJSON()</code> is unchanged after <code>Redact</code>.</li>
/// <li><b>TestDeepMergeOverlayNullOverrides</b> — overlay <code>null</code>
/// emits JSON null on the merged result.</li>
/// <li><b>TestDeepMergeOverlayScalarOverridesObject</b> — overlay scalar
/// replaces base object.</li>
/// <li><b>TestDeepMergeOverlayArrayReplacesBaseArray</b> — overlay array
/// replaces base array (not concatenate).</li>
/// <li><b>TestIsObjectAndIsArrayPredicates</b> — predicates return 1 only
/// for matching dynamic types.</li>
/// </ol>
Class SessionAgent.Test.JsonTest Extends %UnitTest.TestCase
{

/// <p>Constructor — must accept the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, and must call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-3 #1 — build a <code>%DynamicObject</code>, call
/// <code>EmitNull(obj, "k")</code>, assert the resulting JSON contains
/// <code>"k":null</code> (literal null) and NOT <code>"k":"null"</code>
/// (string).</p>
Method TestEmitNullProducesJsonNullNotString()
{
    Set tObj = ##class(%DynamicObject).%New()
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).EmitNull(tObj, "k"), "EmitNull returns OK")
    Set tJson = tObj.%ToJSON()
    Do $$$AssertTrue(tJson [ """k"":null", "JSON contains literal null for key k (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ """k"":""null"""), "JSON does NOT contain string ""null"" for key k (got: " _ tJson _ ")")
    Quit
}

/// <p>AC-3 #2 — feed a 3-level-nested object with credential keys
/// (<code>api_key</code>, <code>Authorization</code>, <code>password</code>)
/// at each level; assert every match is replaced with
/// <code>"&lt;redacted&gt;"</code> and non-matching keys are preserved.</p>
Method TestRedactNestedObjects()
{
    Set tIn = {
        "api_key": "sk-AAAA",
        "user": "alice",
        "headers": {
            "Authorization": "Bearer XYZ",
            "Content-Type": "application/json",
            "nested": {
                "password": "hunter2",
                "keep_me": "ok"
            }
        }
    }
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).Redact(tIn, "api_key,Authorization,password", .tOut), "Redact returns OK")

    ; Top-level redaction.
    Do $$$AssertEquals(tOut.%Get("api_key"), "<redacted>", "top-level api_key redacted")
    Do $$$AssertEquals(tOut.%Get("user"), "alice", "non-matching user preserved")

    ; Second-level redaction.
    Set tHeaders = tOut.%Get("headers")
    Do $$$AssertEquals(tHeaders.%Get("Authorization"), "<redacted>", "Authorization redacted")
    Do $$$AssertEquals(tHeaders.%Get("Content-Type"), "application/json", "Content-Type preserved")

    ; Third-level redaction.
    Set tNested = tHeaders.%Get("nested")
    Do $$$AssertEquals(tNested.%Get("password"), "<redacted>", "nested password redacted")
    Do $$$AssertEquals(tNested.%Get("keep_me"), "ok", "nested keep_me preserved")
    Quit
}

/// <p>AC-3 #3 — feed an object with an array of objects each carrying a
/// credential key; assert recursion into array elements works.</p>
///
/// <p>Two probes:</p>
/// <ol>
/// <li>Object-key match inside array element: <code>headers[0].Authorization</code>
/// is in <code>pKeyList</code>, must be redacted.</li>
/// <li>Non-matching key inside array element: <code>headers[0].value</code>
/// is NOT in <code>pKeyList</code>, must be preserved.</li>
/// </ol>
Method TestRedactNestedArrays()
{
    Set tIn = {
        "headers": [
            {"Authorization": "Bearer ABC", "value": "keep-this"},
            {"Authorization": "Bearer DEF", "name": "h2"}
        ]
    }
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).Redact(tIn, "Authorization", .tOut), "Redact returns OK")

    Set tArr = tOut.%Get("headers")
    Set tElem0 = tArr.%Get(0)
    Set tElem1 = tArr.%Get(1)
    Do $$$AssertEquals(tElem0.%Get("Authorization"), "<redacted>", "headers[0].Authorization redacted")
    Do $$$AssertEquals(tElem0.%Get("value"), "keep-this", "headers[0].value preserved (key not in pKeyList)")
    Do $$$AssertEquals(tElem1.%Get("Authorization"), "<redacted>", "headers[1].Authorization redacted")
    Do $$$AssertEquals(tElem1.%Get("name"), "h2", "headers[1].name preserved")
    Quit
}

/// <p>AC-3 #4 — capture input <code>%ToJSON()</code> before and after,
/// assert unchanged (deep-clone semantics; <code>Redact</code> must not
/// mutate the source).</p>
Method TestRedactDoesNotMutateInput()
{
    Set tIn = {
        "api_key": "sk-original",
        "nested": {"password": "secret"}
    }
    Set tBefore = tIn.%ToJSON()
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).Redact(tIn, "api_key,password", .tOut), "Redact returns OK")
    Set tAfter = tIn.%ToJSON()
    Do $$$AssertEquals(tAfter, tBefore, "input %ToJSON unchanged after Redact (deep-clone semantics)")
    ; Spot-check the source values directly.
    Do $$$AssertEquals(tIn.%Get("api_key"), "sk-original", "source api_key unchanged")
    Do $$$AssertEquals(tIn.%Get("nested").%Get("password"), "secret", "source nested.password unchanged")
    Quit
}

/// <p>AC-3 #5 — base <code>{a: "x"}</code>, overlay <code>{a: null}</code>;
/// assert merged is <code>{a: null}</code> (literal JSON null, not the
/// string).</p>
Method TestDeepMergeOverlayNullOverrides()
{
    Set tBase = {"a": "x"}
    ; Construct overlay with explicit JSON null.
    Set tOverlay = ##class(%DynamicObject).%New()
    Do tOverlay.%Set("a", "", "null")

    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).DeepMerge(tBase, tOverlay, .tOut), "DeepMerge returns OK")
    Set tJson = tOut.%ToJSON()
    Do $$$AssertTrue(tJson [ """a"":null", "merged emits literal null for a (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ """a"":""null"""), "merged does NOT emit string ""null"" for a (got: " _ tJson _ ")")
    Do $$$AssertEquals(tOut.%GetTypeOf("a"), "null", "type of merged a is null")
    Quit
}

/// <p>AC-3 #6 — base <code>{a: {b: 1}}</code>, overlay <code>{a: 2}</code>;
/// assert merged is <code>{a: 2}</code> (scalar replaces object).</p>
Method TestDeepMergeOverlayScalarOverridesObject()
{
    Set tBase = {"a": {"b": 1}}
    Set tOverlay = {"a": 2}
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).DeepMerge(tBase, tOverlay, .tOut), "DeepMerge returns OK")
    Do $$$AssertEquals(tOut.%Get("a"), 2, "scalar overlay replaces base object at key a")
    Quit
}

/// <p>AC-3 #7 — base <code>{a: [1, 2]}</code>, overlay <code>{a: [3]}</code>;
/// assert merged is <code>{a: [3]}</code> (array REPLACES, does NOT
/// concatenate to <code>[1, 2, 3]</code>).</p>
Method TestDeepMergeOverlayArrayReplacesBaseArray()
{
    Set tBase = {"a": [1, 2]}
    Set tOverlay = {"a": [3]}
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).DeepMerge(tBase, tOverlay, .tOut), "DeepMerge returns OK")
    Set tArr = tOut.%Get("a")
    Do $$$AssertEquals(tArr.%Size(), 1, "merged array has length 1 (overlay replaces; not concatenated)")
    Do $$$AssertEquals(tArr.%Get(0), 3, "merged array[0] = 3 from overlay")
    Quit
}

/// <p>Code-review follow-up (Story 2.1, 2026-05-03) — locks the
/// deep-clone-of-pBase invariant in <code>DeepMerge</code>. The
/// implementation deep-clones <code>pBase</code> via
/// <code>%FromJSON(%ToJSON())</code> before walking overlay keys, so the
/// caller's <code>pBase</code> argument is never mutated. This test
/// captures the input <code>%ToJSON()</code> before and after, asserts
/// unchanged, and spot-checks that nested values inside the base survive
/// untouched even when overlay replaces them on the merged result.</p>
Method TestDeepMergeDoesNotMutateBase()
{
    Set tBase = {"a": {"b": 1}, "c": [1, 2]}
    Set tOverlay = {"a": 2, "c": [3]}
    Set tBefore = tBase.%ToJSON()
    Set tOut = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Util.Json).DeepMerge(tBase, tOverlay, .tOut), "DeepMerge returns OK")
    Set tAfter = tBase.%ToJSON()
    Do $$$AssertEquals(tAfter, tBefore, "input pBase %ToJSON unchanged after DeepMerge (deep-clone semantics)")
    ; Spot-check: pBase.a is still the original nested object (not 2).
    Do $$$AssertEquals(tBase.%Get("a").%Get("b"), 1, "source pBase.a.b unchanged")
    ; Spot-check: pBase.c is still the original [1,2] array (not [3]).
    Do $$$AssertEquals(tBase.%Get("c").%Size(), 2, "source pBase.c length unchanged")
    Do $$$AssertEquals(tBase.%Get("c").%Get(0), 1, "source pBase.c[0] unchanged")
    Quit
}

/// <p>AC-3 #8 — covers <code>%DynamicObject</code>,
/// <code>%DynamicArray</code>, scalar <code>%String</code>,
/// <code>%Integer</code>, and <code>""</code> (empty); assert predicates
/// return 1 only for the matching dynamic types.</p>
Method TestIsObjectAndIsArrayPredicates()
{
    Set tObj = ##class(%DynamicObject).%New()
    Set tArr = ##class(%DynamicArray).%New()
    Set tStr = "hello"
    Set tInt = 42
    Set tEmpty = ""

    ; IsObject
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsObject(tObj), 1, "IsObject(%DynamicObject) = 1")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsObject(tArr), 0, "IsObject(%DynamicArray) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsObject(tStr), 0, "IsObject(%String) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsObject(tInt), 0, "IsObject(%Integer) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsObject(tEmpty), 0, "IsObject('') = 0")

    ; IsArray
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsArray(tArr), 1, "IsArray(%DynamicArray) = 1")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsArray(tObj), 0, "IsArray(%DynamicObject) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsArray(tStr), 0, "IsArray(%String) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsArray(tInt), 0, "IsArray(%Integer) = 0")
    Do $$$AssertEquals(##class(SessionAgent.Util.Json).IsArray(tEmpty), 0, "IsArray('') = 0")
    Quit
}

}
