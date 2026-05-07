/// <p>Story 8.2 — CI invariant test for the bounded-WHERE discipline
/// (FR19, AR11, NFR-P2, NFR-SC1). Iterates every concrete subclass of
/// <CLASS>SessionAgent.Tool.Search.Base</CLASS> registered in the current
/// namespace (excluding <code>SessionAgent.Test.*</code> fixtures) and
/// asserts each tool's <method>GetIndexedLeadColumns</method> intersects
/// the documented Ens.MessageHeader indexed set. Any future search-tool
/// author who forgets to declare an indexed lead column gets a CI failure
/// here, NOT a 10-million-row scan in production.</p>
///
/// <p>Until Story 8.3 ships its first concrete search tool, the
/// production-tool iteration loop reports
/// <code>"0 production search tools registered"</code> verbatim and
/// passes (no tool, no violation). Concrete tools land via
/// Stories 8.3–8.7 and are picked up automatically.</p>
///
/// <p><b>Stub-fixture coverage.</b> Two fixtures under
/// <code>SessionAgent.Test.Fixture.*</code> exercise the invariant logic
/// itself: <CLASS>SessionAgent.Test.Fixture.StubBoundedSearchTool</CLASS>
/// (positive control — returns <code>["TimeCreated", "Status"]</code>)
/// and <CLASS>SessionAgent.Test.Fixture.StubUnboundedSearchTool</CLASS>
/// (negative control — returns <code>[]</code>). The negative-control
/// test is a positive-control of the rejection logic, not a fail
/// assertion.</p>
///
/// <p><b>Documented indexed-set</b> (architecture §"AR11 Bounded WHERE
/// invariant" + OD8): <code>TimeCreated</code>, <code>Status</code>,
/// <code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>, <code>SessionId</code>,
/// <code>SuperSessionKey</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.2</a> — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"AR11 Bounded WHERE invariant", §"OD8 keyed-lookup mode".</li>
/// </ul>
Class SessionAgent.Test.BoundedWhereInvariantTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts <code>initvalue</code> from
/// <CLASS>%UnitTest.TestCase</CLASS> and forwards via <code>##super</code>
/// (project rule §"Critical Constructor Requirements"). No
/// <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-5 #1, #2 — discovery loop over every concrete production
/// subclass of <CLASS>SessionAgent.Tool.Search.Base</CLASS>. Each such
/// tool MUST return a non-empty <code>%DynamicArray</code> from
/// <method>GetIndexedLeadColumns</method> AND at least one entry MUST
/// appear in the documented Ens.MessageHeader indexed set.</p>
///
/// <p>Until Story 8.3 ships the first concrete search tool, the loop
/// iterates 0 production tools and emits the verbatim
/// <code>"0 production search tools registered"</code> log line via
/// <method>..LogMessage</method> (PASS — no tool, no violation).</p>
Method TestRegisteredSearchToolsHaveBoundedWhere()
{
    Do ..BuildIndexedColumnSet(.tIndexedSet)
    Set tStmt = ##class(%SQL.Statement).%New()
    ; Discovery query — concrete subclasses of Tool.Search.Base, excluding
    ; SessionAgent.Test.* fixtures (parallel to ToolRegistry.ListTools's
    ; Story 3.0 carry-forward exclusion of stub-tool fixtures).
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE %EXACT(Super) = 'SessionAgent.Tool.Search.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "Production-search-tool discovery query prepared")
    Set tRs = tStmt.%Execute()

    Set tCount = 0
    Set tViolations = []
    While tRs.%Next() {
        Set tCount = tCount + 1
        Set tClassName = tRs.%Get("ClassName")
        Set tCols = $ClassMethod(tClassName, "GetIndexedLeadColumns")
        Do $$$AssertTrue($IsObject(tCols), tClassName _ ".GetIndexedLeadColumns returns an object")
        Set tNonEmpty = (tCols.%Size() > 0)
        Do $$$AssertTrue(tNonEmpty, tClassName _ ".GetIndexedLeadColumns returns non-empty array")

        ; At least one entry must be in the documented indexed set.
        Set tHit = 0
        Set tIter = tCols.%GetIterator()
        While tIter.%GetNext(.tKey, .tCol) {
            If $Data(tIndexedSet(tCol)) Set tHit = 1 Quit
        }
        If 'tHit Do tViolations.%Push(tClassName)
        Do $$$AssertEquals(tHit, 1, tClassName _ " — at least one indexed lead column is in the documented indexed set")
    }

    If tCount = 0 {
        Do ..LogMessage("0 production search tools registered")
    } Else {
        Do ..LogMessage(tCount _ " production search tool(s) discovered; " _ tViolations.%Size() _ " violation(s)")
    }
    Do $$$AssertEquals(tViolations.%Size(), 0, "All production search tools satisfy the bounded-WHERE invariant")
    Quit
}

/// <p>AC-5 #3 + AC-6 default — the StubBoundedSearchTool fixture, called
/// with <code>pTimeWindowHours = 0</code>, produces a fragment leading
/// with <code>TimeCreated &gt; ?</code> and a single-element
/// <var>pParams</var> array containing the cutoff timestamp.</p>
///
/// <p><b>Cutoff-timestamp shape assertion (review-fix LOW patch).</b> The
/// pParams[0] entry is also asserted to be a non-empty 19-character ODBC
/// timestamp (<code>YYYY-MM-DD HH:MM:SS</code>). This guards against a
/// future regression in the <code>$ZTimeStamp</code> carry/borrow math
/// (or an accidental switch to a non-ODBC format) that would silently
/// pass a <code>%Size()=1</code> assertion while emitting a malformed
/// bind value.</p>
Method TestStubFixtureBoundedWhereDefaultsTo24h()
{
    Set tParams = []
    Set tErr = ""
    Set tFrag = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(0, .tParams, .tErr)
    Do $$$AssertEquals(tFrag, "TimeCreated > ?", "Default-window fragment leads with TimeCreated > ?")
    Do $$$AssertEquals(tParams.%Size(), 1, "Exactly one parameterized bind value (the cutoff timestamp)")
    Do $$$AssertEquals(tErr, "", "No error envelope on default-window mode")

    ; Cutoff-timestamp shape — non-empty, 19-char ODBC form.
    Set tCutoff = tParams.%Get(0)
    Do $$$AssertTrue(tCutoff '= "", "Cutoff timestamp non-empty")
    Do $$$AssertEquals($Length(tCutoff), 19, "Cutoff timestamp is 19-char ODBC form (YYYY-MM-DD HH:MM:SS)")
    Do $$$AssertEquals($Extract(tCutoff, 5), "-", "Cutoff has dash at position 5")
    Do $$$AssertEquals($Extract(tCutoff, 11), " ", "Cutoff has space separator at position 11")
    Do $$$AssertEquals($Extract(tCutoff, 14), ":", "Cutoff has colon at position 14")

    ; AC-5 #3 — also exercise GetIndexedLeadColumns on the fixture.
    Set tCols = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).GetIndexedLeadColumns()
    Do $$$AssertEquals(tCols.%Size(), 2, "Stub returns two indexed lead columns")
    Do $$$AssertEquals(tCols.%Get(0), "TimeCreated", "First indexed column is TimeCreated")
    Do $$$AssertEquals(tCols.%Get(1), "Status", "Second indexed column is Status")
    Quit
}

/// <p>AC-6 cap — calling the helper with
/// <code>pTimeWindowHours = 1000</code> (above the 720-hour max) returns
/// the empty fragment AND populates the <var>pErr</var> outparam with the
/// canonical structured-error envelope.</p>
Method TestStubFixtureBoundedWhereCapsAt720h()
{
    Set tParams = []
    Set tErr = ""
    Set tFrag = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(1000, .tParams, .tErr)
    Do $$$AssertEquals(tFrag, "", "Over-cap window returns empty fragment")
    Do $$$AssertTrue($IsObject(tErr), "pErr is a populated %DynamicObject")
    Do $$$AssertEquals(+tErr.%Get("isError"), 1, "pErr.isError = 1")
    Do $$$AssertEquals(tErr.%Get("errorCode"), "TimeWindowTooLarge", "pErr.errorCode = TimeWindowTooLarge")
    Do $$$AssertEquals(+tErr.%Get("maxAllowed"), 720, "pErr.maxAllowed = 720")
    Do $$$AssertEquals(tParams.%Size(), 0, "pParams not populated on rejection path")
    Quit
}

/// <p>AC-3 + AC-6 keyed-lookup mode — calling the helper with the
/// sentinel value (<code>pTimeWindowHours = -1</code>) omits the
/// <code>TimeCreated</code> predicate. The caller's
/// <var>pAdditionalPredicates</var> entry forms the entire fragment.</p>
Method TestStubFixtureKeyedLookupModeOmitsTimeWindow()
{
    Set tParams = []
    Set tErr = ""
    Set tFrag = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(-1, .tParams, .tErr, "", "%EXACT(SessionId) = ?")
    Do $$$AssertEquals(tFrag, "%EXACT(SessionId) = ?", "Keyed-lookup fragment is exactly the additional predicate")
    Do $$$AssertTrue('(tFrag [ "TimeCreated"), "Keyed-lookup fragment does NOT contain TimeCreated")
    Do $$$AssertEquals(tParams.%Size(), 0, "Keyed-lookup mode does NOT push a TimeCreated cutoff onto pParams (the caller binds the keyed-predicate value separately)")
    Do $$$AssertEquals(tErr, "", "No error envelope on keyed-lookup mode")
    Quit
}

/// <p>Story 8.6 AC-9 sub-2 — alias-form positive test. Calling the
/// helper with <code>pTimeColumnAlias="mh"</code> qualifies the
/// emitted <code>TimeCreated</code> predicate as
/// <code>"mh.TimeCreated > ?"</code> instead of the bare form.
/// Closes the MEDIUM-8.5-F02 carry-forward by locking the alias-form
/// emission as a structural contract: any future regression that
/// drops the alias-qualification path will fail here, NOT silently
/// produce ambiguous-column SQL at runtime.</p>
Method TestStubFixtureBoundedWhereWithAliasQualifies()
{
    Set tParams = []
    Set tErr = ""
    ; Default-window mode + alias = "mh" → emits "mh.TimeCreated > ?".
    Set tFrag = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(0, .tParams, .tErr, "mh")
    Do $$$AssertEquals(tFrag, "mh.TimeCreated > ?", "Alias-form fragment leads with mh.TimeCreated > ? (Story 8.6 AC-9 sub-2)")
    Do $$$AssertEquals(tParams.%Size(), 1, "Alias mode still pushes exactly one cutoff bind value")
    Do $$$AssertEquals(tErr, "", "No error envelope on alias mode")

    ; With additional JOIN-form predicates concatenated.
    Set tParams2 = []
    Set tErr2 = ""
    Set tFrag2 = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(0, .tParams2, .tErr2, "mh", "st.PropId = ?", "%EXACT(st.PropValue) = ?")
    Do $$$AssertEquals(tFrag2, "mh.TimeCreated > ? AND st.PropId = ? AND %EXACT(st.PropValue) = ?", "Alias-form fragment composes with JOIN-form additional predicates")
    Do $$$AssertEquals(tParams2.%Size(), 1, "Only the cutoff is pushed by the helper; caller binds the additional-predicate values separately")

    ; Backward-compat: empty alias → bare form. (Existing behavior; the
    ; primary backward-compat test is TestStubFixtureBoundedWhereDefaultsTo24h
    ; which calls without the alias parameter.) Verify that explicitly
    ; passing "" produces the same bare form.
    Set tParams3 = []
    Set tErr3 = ""
    Set tFrag3 = ##class(SessionAgent.Test.Fixture.StubBoundedSearchTool).BuildBoundedWhereClause(0, .tParams3, .tErr3, "")
    Do $$$AssertEquals(tFrag3, "TimeCreated > ?", "Empty alias produces bare 'TimeCreated > ?' (backward-compatible with pre-Story-8.6 behavior)")
    Quit
}

/// <p>AC-5 #4 — positive-control of the rejection logic. The
/// StubUnboundedSearchTool returns <code>[]</code>; the discovery loop
/// would reject it. This test asserts the empty-array shape directly so
/// that if a future maintainer breaks the invariant logic in
/// <method>TestRegisteredSearchToolsHaveBoundedWhere</method>, this
/// secondary assertion still catches the upstream condition.</p>
///
/// <p><b>Note.</b> This test does NOT cause the test class to fail —
/// it asserts the fixture's empty-array return shape. The "would be
/// rejected" framing is in the assertion message and verified by
/// computing the intersection check inline (no production-loop
/// invocation).</p>
Method TestUnboundedFixtureWouldBeRejected()
{
    Set tCols = ##class(SessionAgent.Test.Fixture.StubUnboundedSearchTool).GetIndexedLeadColumns()
    Do $$$AssertTrue($IsObject(tCols), "StubUnbounded returns a %DynamicArray")
    Do $$$AssertEquals(tCols.%Size(), 0, "StubUnbounded returns EMPTY array — would be rejected by production discovery loop")

    ; Compute the intersection check inline, asserting the same logic
    ; the production-loop runs.
    Do ..BuildIndexedColumnSet(.tIndexedSet)
    Set tHit = 0
    Set tIter = tCols.%GetIterator()
    While tIter.%GetNext(.tKey, .tCol) {
        If $Data(tIndexedSet(tCol)) Set tHit = 1 Quit
    }
    Do $$$AssertEquals(tHit, 0, "Empty StubUnbounded does not intersect the documented indexed set — would-be-rejected confirmed")
    Quit
}

/// <p>Helper — populate the documented Ens.MessageHeader (and adjacent
/// indexed-extent) indexed-set as a multidim local keyed by column name.
/// Caller passes a <var>pSet</var> by reference; membership check is
/// <code>If $Data(pSet(colName))</code>. Architecture §"AR11" lists
/// <code>TimeCreated</code>, <code>Status</code>,
/// <code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>, <code>SessionId</code>;
/// <code>SuperSessionKey</code> is added for OD8 keyed-lookup mode (the
/// SuperSession-index tools land in Story 8.4).
/// <code>PropValue</code> is added for Story 8.5
/// (<CLASS>SessionAgent.Tool.Search.SearchByBodyField</CLASS>) — the
/// canonical indexed column on every <CLASS>Ens.SearchTableBase</CLASS>
/// subclass extent (the <code>(PropId, PropValue, DocId)</code> row
/// shape's middle column). The body-field-search tool's
/// <method>GetIndexedLeadColumns</method> returns
/// <code>["PropValue"]</code> as a stable canonical placeholder
/// (operator's per-call <code>prop_name</code> is the LOGICAL name; the
/// PHYSICAL indexed column is always <code>PropValue</code>).</p>
ClassMethod BuildIndexedColumnSet(ByRef pSet)
{
    Set pSet("TimeCreated") = 1
    Set pSet("Status") = 1
    Set pSet("SourceConfigName") = 1
    Set pSet("TargetConfigName") = 1
    Set pSet("MessageBodyClassName") = 1
    Set pSet("SessionId") = 1
    Set pSet("SuperSessionKey") = 1
    Set pSet("PropValue") = 1
    Quit
}

}
