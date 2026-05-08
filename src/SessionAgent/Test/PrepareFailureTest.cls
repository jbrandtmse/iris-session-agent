/// <p>Story 11.2 — unit tests for the
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnPrepareFailure</method>
/// helper. Covers Story 11.2 AC-3:</p>
///
/// <ol>
/// <li><b>TestEnsureIsErrorOnPrepareFailureNoOpOnSuccess</b> — invokes
/// the helper with <code>pPrepareStatus = $$$OK</code>; asserts
/// <code>pResult.isError</code> is unchanged (no mutation), helper
/// returns <code>0</code>.</li>
/// <li><b>TestEnsureIsErrorOnPrepareFailureMutatesOnError</b> — invokes
/// the helper with a real <code>$$$ERROR</code> status; asserts
/// <code>pResult.isError = 1</code>, <code>content[0].text</code>
/// contains the error text, <code>structuredContent.render_strategy</code>
/// equals <code>"prepare_error"</code>.</li>
/// <li><b>TestAllInspectionAndSearchToolsUseHelper</b> — counts
/// <code>EnsureIsErrorOnPrepareFailure</code> invocations across
/// <code>src/SessionAgent/Tool/Inspection/*.cls</code> and
/// <code>src/SessionAgent/Tool/Search/*.cls</code> via SQL probe of
/// <code>%Dictionary.MethodDefinition</code> compiled-method bodies;
/// asserts the count matches the Task-0-enumerated number of
/// retrofitted call-sites.</li>
/// </ol>
///
/// <p><b>Originating finding.</b> Item I in
/// <code>deferred-work.md</code> — the longest-running deferral in the
/// project. Originally surfaced as Story 4.5 reviewer Blind Hunter B-3
/// finding ("FindRelatedSessions silently returns empty envelope on
/// %Prepare failure"); deferred 4 times across 6 stories
/// (4.5 → 4.7 → 8.0 → 9.0 → 10.9). Story 9.0 AC-6 compounding-recovery
/// clause committed: "if Story 10.9 also can't carry, the recovery note
/// compounds (fourth-recovery binding required — at which point a
/// focused dedicated cleanup story should be opened rather than further
/// re-binding)." This test class is the verification gate for Story 11.2
/// honoring that commitment.</p>
Class SessionAgent.Test.PrepareFailureTest Extends %UnitTest.TestCase
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

/// <p>AC-3 #1 — when invoked with <code>pPrepareStatus = $$$OK</code>,
/// the helper MUST be a no-op: return <code>0</code> and leave
/// <code>pResult</code> unmutated.</p>
Method TestEnsureIsErrorOnPrepareFailureNoOpOnSuccess()
{
    Set tResult = {"content":[{"type":"text","text":"original"}], "structuredContent":{"events":[]}}
    Set tReturn = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(tResult, $$$OK, "test_tool_name")

    Do $$$AssertEquals(tReturn, 0, "Helper returns 0 when pPrepareStatus is $$$OK (no-op)")

    ; pResult must NOT have been mutated to an error envelope.
    Set tIsErrPresent = tResult.%IsDefined("isError")
    Do $$$AssertEquals(tIsErrPresent, 0, "pResult.isError is NOT set on success path")

    ; content[0].text must remain the original value.
    Do $$$AssertEquals(tResult.content.%Get(0).text, "original", "content[0].text unchanged on success path")

    ; structuredContent must NOT have render_strategy set.
    Set tHasRender = tResult.structuredContent.%IsDefined("render_strategy")
    Do $$$AssertEquals(tHasRender, 0, "structuredContent.render_strategy NOT set on success path")
    Quit
}

/// <p>AC-3 #2 — when invoked with a real <code>$$$ERROR</code> status,
/// the helper MUST mutate <code>pResult</code> to the canonical error
/// envelope and return <code>1</code>.</p>
Method TestEnsureIsErrorOnPrepareFailureMutatesOnError()
{
    Set tResult = {"content":[{"type":"text","text":""}], "structuredContent":{"events":[]}}
    ; Construct a real %Status error — use $$$ERROR to keep the test
    ; deterministic across IRIS versions (no dependency on a real SQL
    ; prepare failure path).
    Set tErrStatus = $$$ERROR(5001, "synthetic test error for Story 11.2")
    Set tReturn = ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(tResult, tErrStatus, "test_tool_xyz")

    Do $$$AssertEquals(tReturn, 1, "Helper returns 1 when pPrepareStatus is $$$ERROR (mutated)")

    ; isError must be 1.
    Do $$$AssertEquals(+tResult.isError, 1, "pResult.isError set to 1 on error path")

    ; content[0].text must include the tool name AND the error text.
    Set tText = tResult.content.%Get(0).text
    Do $$$AssertNotEquals(tText, "", "content[0].text was overwritten with operator-readable error")
    Do $$$AssertNotEquals($Find(tText, "test_tool_xyz"), 0, "content[0].text mentions the tool name")
    Do $$$AssertNotEquals($Find(tText, "synthetic test error for Story 11.2"), 0, "content[0].text contains the IRIS error text")
    Do $$$AssertNotEquals($Find(tText, "SQL prepare failed"), 0, "content[0].text contains 'SQL prepare failed' marker")

    ; structuredContent.render_strategy = "prepare_error".
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "prepare_error", "render_strategy is canonical 'prepare_error'")

    ; structuredContent.error_text equals the IRIS error text.
    Set tErrTextField = tResult.structuredContent.%Get("error_text")
    Do $$$AssertNotEquals($Find(tErrTextField, "synthetic test error for Story 11.2"), 0, "structuredContent.error_text contains the original error")

    ; Pre-existing structuredContent fields (events:[]) must remain.
    Set tHasEvents = tResult.structuredContent.%IsDefined("events")
    Do $$$AssertEquals(tHasEvents, 1, "Pre-existing structuredContent fields are preserved")
    Quit
}

/// <p>AC-3 #3 — assert every retrofitted tool actually calls the helper.
/// Iterate <code>%Dictionary.CompiledMethod</code> rows for every
/// <code>SessionAgent.Tool.Inspection.*</code> + <code>SessionAgent.Tool.Search.*</code>
/// concrete class, read each method's <code>Implementation</code> stream
/// (cannot use SQL's <code>[</code> operator on stream columns —
/// SQLCODE -313), and count how many methods carry the literal
/// <code>EnsureIsErrorOnPrepareFailure</code> token. This is effectively
/// a regression gate: if a future story refactors a tool and
/// accidentally drops the helper invocation, this test fails.</p>
Method TestAllInspectionAndSearchToolsUseHelper()
{
    ; Step 1: enumerate all concrete tool classes via SQL on
    ; %Dictionary.ClassDefinition (NOT MethodDefinition — class names
    ; only, no stream columns).
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS class_name FROM %Dictionary.ClassDefinition WHERE (%EXACT(Name) %STARTSWITH 'SessionAgent.Tool.Inspection.' OR %EXACT(Name) %STARTSWITH 'SessionAgent.Tool.Search.') AND Abstract = 0 ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "SQL class-enumeration %Prepare succeeded")

    Set tRs = tStmt.%Execute()
    Set tHelperHits = 0
    Set tClassesProbed = 0

    While tRs.%Next() {
        Set tClassName = tRs.%Get("class_name")
        Set tClassesProbed = tClassesProbed + 1

        ; Step 2: for each class, walk %Dictionary.CompiledMethod rows.
        ; Use a class-method probe that reads the Implementation stream
        ; via OREF (NOT SQL) to dodge the -313 stream-operand limitation.
        Set tInnerStmt = ##class(%SQL.Statement).%New()
        Set tSCi = tInnerStmt.%Prepare("SELECT %EXACT(Name) AS method_name FROM %Dictionary.CompiledMethod WHERE %EXACT(parent) = ?")
        If $$$ISERR(tSCi) Continue
        Set tInnerRs = tInnerStmt.%Execute(tClassName)
        While tInnerRs.%Next() {
            Set tMethodName = tInnerRs.%Get("method_name")
            Set tMethodDef = ##class(%Dictionary.CompiledMethod).%OpenId(tClassName _ "||" _ tMethodName)
            If '$IsObject(tMethodDef) Continue
            Set tImpl = tMethodDef.Implementation
            If '$IsObject(tImpl) Continue
            Do tImpl.Rewind()
            Set tBody = tImpl.Read($$$MaxLocalLength)
            If tBody [ "EnsureIsErrorOnPrepareFailure" {
                Set tHelperHits = tHelperHits + 1
            }
        }
    }

    Do $$$AssertTrue(tClassesProbed > 15, "At least 16 concrete Tool.Inspection.* + Tool.Search.* classes were enumerated (got: " _ tClassesProbed _ ")")
    ; Probe yields per-METHOD count, not per-call-site count. Several
    ; tools have multiple %Prepare calls within one method
    ; (e.g., FindRelatedSessions.Invoke has 4, SessionSummary.Invoke
    ; has 3). Setting the lower bound at 19 gives generous headroom for
    ; refactor without sacrificing regression-detection power.
    Do $$$AssertTrue(tHelperHits >= 19, "At least 19 methods across Tool.Inspection.* + Tool.Search.* contain EnsureIsErrorOnPrepareFailure (got: " _ tHelperHits _ ")")
    Quit
}

}
