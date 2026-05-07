/// <p>Unit tests for the Story 9.1 candidate function
/// <CLASS>SessionAgent.Search.SynthesizeAlias</CLASS>:
/// <method>SynthesizeAlias(pToolName, pArgs)</method>. Verifies the
/// 10 reordering / equivalence / divergence scenarios from Story 9.1
/// AC-2.</p>
///
/// <p><b>Test method roster</b> (each test corresponds to a verbatim
/// AC-2 row):</p>
/// <table>
/// <tr><td>1</td><td>TestKeyOrderSwapProducesSameAlias</td>
///     <td><code>{status:"Error",source:"EpicADT"}</code> ≡
///         <code>{source:"EpicADT",status:"Error"}</code></td></tr>
/// <tr><td>2</td><td>TestKeyCaseProducesSameAlias</td>
///     <td><code>{Status:"Error"}</code> ≡ <code>{status:"Error"}</code></td></tr>
/// <tr><td>3</td><td>TestValueCaseProducesSameAlias</td>
///     <td><code>{status:"Error"}</code> ≡ <code>{status:"ERROR"}</code></td></tr>
/// <tr><td>4</td><td>TestArrayReorderProducesSameAlias</td>
///     <td><code>{status_in:["Error","Suspended"]}</code> ≡
///         <code>{status_in:["Suspended","Error"]}</code></td></tr>
/// <tr><td>5</td><td>TestDifferentToolNamesProduceDifferentAliases</td>
///     <td><code>(search_by_status, …)</code> ≢
///         <code>(search_by_message_class, …)</code></td></tr>
/// <tr><td>6</td><td>TestDifferentKeysPresentProduceDifferentAliases</td>
///     <td><code>{status:"Error"}</code> ≢
///         <code>{status:"Error",source:"EpicADT"}</code></td></tr>
/// <tr><td>7</td><td>TestNumericValueAndStringValueConverge</td>
///     <td><code>{limit:50}</code> ≡ <code>{limit:"50"}</code>
///         (Story 9.1 dev choice — convergence is the chosen design)</td></tr>
/// <tr><td>8</td><td>TestEmptyValueDistinctFromAbsentKey</td>
///     <td><code>{status:"Error"}</code> ≢
///         <code>{status:"Error",source:""}</code></td></tr>
/// <tr><td>9</td><td>TestNestedObjectKeyOrderProducesSameAlias</td>
///     <td><code>{filters:{a:1,b:2}}</code> ≡
///         <code>{filters:{b:2,a:1}}</code></td></tr>
/// <tr><td>10</td><td>TestWhitespaceInValuesIsSignificant</td>
///     <td><code>{description:"foo bar"}</code> ≢
///         <code>{description:"foo  bar"}</code></td></tr>
/// </table>
///
/// <p>Plus two additional sanity tests beyond the AC-2 minimum:</p>
/// <ul>
/// <li><b>TestEmptyArgsProducesBareToolPrefix</b> — null/empty
/// <code>pArgs</code> produces <code>tool_name:</code></li>
/// <li><b>TestToolNameLowercased</b> — ToolName "Search_By_Status"
/// equivalent to "search_by_status".</li>
/// </ul>
Class SessionAgent.Test.SynthesizeAliasTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects, and calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-2 row 1 — key-order swap produces the same alias.</p>
Method TestKeyOrderSwapProducesSameAlias()
{
    Set tA = {"status":"Error","source":"EpicADT"}
    Set tB = {"source":"EpicADT","status":"Error"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 1: key-order swap. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 2 — key-case mismatch (PascalCase vs camelCase) produces
/// the same alias.</p>
Method TestKeyCaseProducesSameAlias()
{
    Set tA = {"Status":"Error"}
    Set tB = {"status":"Error"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 2: key case. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 3 — value-case mismatch (mixed-case status) produces
/// the same alias under v1 lowercase-everything normalization.</p>
Method TestValueCaseProducesSameAlias()
{
    Set tA = {"status":"Error"}
    Set tB = {"status":"ERROR"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 3: value case. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 4 — array reorder produces the same alias.</p>
Method TestArrayReorderProducesSameAlias()
{
    Set tA = {"status_in":["Error","Suspended"]}
    Set tB = {"status_in":["Suspended","Error"]}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 4: array reorder. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 5 — different tool names produce DIFFERENT aliases
/// (cross-tool collision prevention).</p>
Method TestDifferentToolNamesProduceDifferentAliases()
{
    Set tArgs = {"status":"Error"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tArgs)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_message_class", tArgs)
    Do $$$AssertNotEquals(tAliasA, tAliasB, "AC-2 row 5: different tool names. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 6 — different keys present produce DIFFERENT aliases
/// (argument-shape difference matters).</p>
Method TestDifferentKeysPresentProduceDifferentAliases()
{
    Set tA = {"status":"Error"}
    Set tB = {"status":"Error","source":"EpicADT"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertNotEquals(tAliasA, tAliasB, "AC-2 row 6: different keys. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 7 — numeric value and string-of-number value converge
/// (Story 9.1 dev choice; documented in
/// <CLASS>SessionAgent.Search.SynthesizeAlias</CLASS> class header
/// rule 6).</p>
Method TestNumericValueAndStringValueConverge()
{
    Set tA = {"limit":50}
    Set tB = {"limit":"50"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 7: numeric vs string-of-number. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 8 — empty-string value is DISTINCT from absent key
/// (presence-of-key matters).</p>
Method TestEmptyValueDistinctFromAbsentKey()
{
    Set tA = {"status":"Error"}
    Set tB = {"status":"Error","source":""}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertNotEquals(tAliasA, tAliasB, "AC-2 row 8: empty value vs absent key. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 9 — nested object key-order swap produces the same
/// alias (recursive normalization).</p>
Method TestNestedObjectKeyOrderProducesSameAlias()
{
    Set tA = {"filters":{"a":1,"b":2}}
    Set tB = {"filters":{"b":2,"a":1}}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertEquals(tAliasA, tAliasB, "AC-2 row 9: nested object key order. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>AC-2 row 10 — whitespace is significant; "foo bar" and
/// "foo  bar" produce DIFFERENT aliases (whitespace NOT collapsed).</p>
Method TestWhitespaceInValuesIsSignificant()
{
    Set tA = {"description":"foo bar"}
    Set tB = {"description":"foo  bar"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tA)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tB)
    Do $$$AssertNotEquals(tAliasA, tAliasB, "AC-2 row 10: whitespace significance. AliasA="_tAliasA_" AliasB="_tAliasB)
}

/// <p>Sanity #1 — empty/null pArgs produces the bare tool prefix
/// "<code>tool_name:</code>" with no args blob.</p>
Method TestEmptyArgsProducesBareToolPrefix()
{
    Set tAlias = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", "")
    Do $$$AssertEquals(tAlias, "search_by_status:", "Empty pArgs (string) should produce bare prefix. Got: "_tAlias)

    Set tEmptyObj = {}
    Set tAlias2 = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tEmptyObj)
    Do $$$AssertEquals(tAlias2, "search_by_status:", "Empty pArgs (empty object) should produce bare prefix. Got: "_tAlias2)
}

/// <p>Sanity #2 — tool name is lowercased, so "Search_By_Status"
/// produces the same alias as "search_by_status".</p>
Method TestToolNameLowercased()
{
    Set tArgs = {"status":"Error"}
    Set tAliasA = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("Search_By_Status", tArgs)
    Set tAliasB = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias("search_by_status", tArgs)
    Do $$$AssertEquals(tAliasA, tAliasB, "Tool name should be case-normalized. AliasA="_tAliasA_" AliasB="_tAliasB)
}

}
