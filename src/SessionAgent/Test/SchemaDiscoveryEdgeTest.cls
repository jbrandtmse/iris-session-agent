/// <p>Story 14.2 code-review additions — edge coverage split out of
/// <CLASS>SessionAgent.Test.SchemaDiscoveryToolTest</CLASS> to keep that
/// class near the ~500-line test-class guideline. Two review-driven
/// locks:</p>
/// <ol>
///   <li><b>TestDescribeMessageClassCharBudgetTrim</b> — exercises the
///   AC-2 16 KB <method>ApplyCharBudget</method> trim path (previously
///   shipped untested: only the negative truncated=false path was
///   asserted) including the review-added <code>indexes</code> trim step
///   and the plan-exhausted-but-still-over-budget marker.</li>
///   <li><b>TestDiscoverTablesDottedFragmentMatchesQualified</b> — locks
///   the review fix for dotted fragments (e.g. 'Ens.MessageHeader'),
///   which previously could never match because the LIKE applied to
///   TABLE_NAME only; dotted input is the most likely LLM input since
///   the sibling tools' own outputs prime qualified class names.</li>
/// </ol>
Class SessionAgent.Test.SchemaDiscoveryEdgeTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>CallerContext with sane defaults (same shape as
/// SchemaDiscoveryToolTest.BuildCtx).</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = 9799943
    Set tCtx.PortalUser = "tester-142r"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Build a synthetic structuredContent envelope whose named array
/// carries <var>pCount</var> entries of <var>pEntryChars</var>-char
/// strings (NOT Test-prefixed — discovery-shadow rule).</p>
ClassMethod BuildOversizeEnvelope(pField As %String, pCount As %Integer, pEntryChars As %Integer) As %DynamicObject
{
    Set tResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Set tArr = []
    Set tFiller = $Translate($Justify("", pEntryChars), " ", "x")
    For i=1:1:pCount {
        Do tArr.%Push(tFiller _ i)
    }
    Do tResult.structuredContent.%Set(pField, tArr)
    Quit tResult
}

/// <p>AC-2 16 KB budget — three scenarios against
/// <method>ApplyCharBudget</method> directly (the Dispatch-level ok-path
/// is covered by SchemaDiscoveryToolTest; no compiled class in a stock
/// namespace deterministically exceeds 16 KB, so the trim branch is
/// exercised synthetically):</p>
/// <ol>
///   <li>oversize <code>extent_classes</code> trims to the plan cap (20)
///   and sets <code>truncated=true</code>;</li>
///   <li>oversize <code>indexes</code> trims to its plan cap (20) — the
///   review-added step; pre-review the indexes array was untrimmable;</li>
///   <li>over-budget with NO trimmable arrays still sets
///   <code>truncated=true</code> (plan-exhausted marker).</li>
/// </ol>
Method TestDescribeMessageClassCharBudgetTrim()
{
    ; (1) extent_classes 30 x ~700 chars (~21 KB) -> trimmed to 20.
    Set tResult = ..BuildOversizeEnvelope("extent_classes", 30, 700)
    Do ##class(SessionAgent.Tool.Inspection.DescribeMessageClass).ApplyCharBudget(tResult)
    Do $$$AssertEquals(tResult.structuredContent.%Get("extent_classes").%Size(), 20, "extent_classes trimmed to plan cap 20")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 1, "truncated=true after extent trim")
    Do $$$AssertTrue($Length(tResult.structuredContent.%ToJSON()) <= 16384, "post-trim JSON inside the 16 KB budget")

    ; (2) indexes 30 x ~800 chars (~24 KB) -> trimmed to 20.
    Set tResult2 = ..BuildOversizeEnvelope("indexes", 30, 800)
    Do ##class(SessionAgent.Tool.Inspection.DescribeMessageClass).ApplyCharBudget(tResult2)
    Do $$$AssertEquals(tResult2.structuredContent.%Get("indexes").%Size(), 20, "indexes trimmed to plan cap 20 (review-added trim step)")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("truncated"), 1, "truncated=true after indexes trim")

    ; (3) one 20000-char scalar, no trimmable arrays -> still flagged.
    Set tResult3 = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Do tResult3.structuredContent.%Set("blob", $Translate($Justify("", 20000), " ", "y"))
    Do ##class(SessionAgent.Tool.Inspection.DescribeMessageClass).ApplyCharBudget(tResult3)
    Do $$$AssertEquals(+tResult3.structuredContent.%Get("truncated"), 1, "truncated=true when over budget with nothing trimmable (contract never silently violated)")

    ; Negative control — small envelope stays untrimmed.
    Set tResult4 = ..BuildOversizeEnvelope("extent_classes", 3, 20)
    Do ##class(SessionAgent.Tool.Inspection.DescribeMessageClass).ApplyCharBudget(tResult4)
    Do $$$AssertEquals(+tResult4.structuredContent.%Get("truncated"), 0, "small envelope: truncated=false")
    Do $$$AssertEquals(tResult4.structuredContent.%Get("extent_classes").%Size(), 3, "small envelope: arrays untouched")
    Quit
}

/// <p>Review fix lock — dotted fragment matches the qualified
/// schema.name through the real Dispatch trust boundary.</p>
Method TestDiscoverTablesDottedFragmentMatchesQualified()
{
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("discover_tables", ..BuildCtx(), {"name_fragment": "Ens.MessageHeader"}, .tResult)
    Do $$$AssertStatusOK(tSC, "dotted-fragment Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "dotted fragment passes the layer-2 regex (success envelope)")
    Set tFound = 0
    Set tIter = tResult.structuredContent.%Get("tables").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If (tEntry.%Get("schema") = "Ens") && (tEntry.%Get("name") = "MessageHeader") Set tFound = 1
    }
    Do $$$AssertTrue(tFound, "'Ens.MessageHeader' (dotted) finds Ens.MessageHeader via the qualified-name match")
    Quit
}

}
