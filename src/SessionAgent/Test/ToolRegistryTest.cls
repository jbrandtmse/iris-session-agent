/// <p>Unit tests for <CLASS>SessionAgent.Tool.Registry</CLASS> — the
/// reflection-based tool registry + L2-enforced dispatch entry point
/// shipped by Story 2.10.</p>
///
/// <p>Seven Test* methods cover Story 2.10 AC-2 through AC-3:</p>
/// <ol>
/// <li><b>TestListToolsIncludesStubReadOnlyTool</b> — discovery surfaces
/// the stub fixture.</li>
/// <li><b>TestListToolsExcludesAbstractBase</b> — abstract base is
/// filtered out (Abstract=1 row excluded).</li>
/// <li><b>TestDispatchSuccessReturnsResultAndEmitsAudit</b> — happy
/// path returns the stub envelope AND writes one ToolCall row.</li>
/// <li><b>TestDispatchRejectsMutatesStateOne</b> — L2 enforcement blocks
/// <parameter>MutatesState=1</parameter> dispatches.</li>
/// <li><b>TestDispatchExceptionWrappedAsErrorEnvelope</b> — exceptions
/// from <method>Invoke</method> become MCP error envelopes with the
/// stack trace landing only in <property>Audit.ToolCall.ErrorText</property>.</li>
/// <li><b>TestDispatchUnknownToolReturnsErrorEnvelope</b> — unknown
/// tool name returns the standard error shape (no exception).</li>
/// <li><b>TestRegisterIfMissingFiresOnFirstDispatch</b> — first dispatch
/// per tool name lazy-registers the (SessionAgent, ToolCall, &lt;name&gt;)
/// triple in <code>%SYS Security.Events</code>.</li>
/// </ol>
///
/// <p><b>NFR-S4 100% completeness</b> is covered transitively by item
/// (3) — every successful dispatch writes exactly one row.</p>
Class SessionAgent.Test.ToolRegistryTest Extends %UnitTest.TestCase
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

/// <p>Cleanup hook — runs after each Test* method. Deletes any
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> rows whose ToolName
/// belongs to the Story 2.10 stub fixtures, plus the lazy-registered
/// triples in <code>%SYS Security.Events</code>. Keeps the test ledger
/// + event registry clean across runs.</p>
Method OnAfterOneTest() As %Status
{
    ; Delete stub-tool audit rows.
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tDelSC = tStmt.%Prepare("DELETE FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName) IN ('test_readonly_tool','test_write_tool','test_throwing_tool')")
    If $$$ISOK(tDelSC) Do tStmt.%Execute()

    ; Delete lazy-registered triples.
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        For tName = "test_readonly_tool", "test_write_tool", "test_throwing_tool" {
            If ##class(Security.Events).Exists("SessionAgent","ToolCall",tName) {
                Do ##class(Security.Events).Delete("SessionAgent","ToolCall",tName)
            }
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit $$$OK
}

/// <p>Helper — build a <CLASS>SessionAgent.Agent.CallerContext</CLASS>
/// for the inspection agent flavor. Used by every Test* method that
/// dispatches through the registry.</p>
Method NewInspectionCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = "test-session-2-10"
    Set tCtx.SearchSessionKey = ""
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-2 #1 — the stub read-only tool appears in the discovery list.</p>
Method TestListToolsExcludesSessionAgentTestStubs()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools returns an object")
    Set tFoundStub = 0, tFoundProd = 0
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If tEntry.name = "test_readonly_tool" Set tFoundStub = 1
        If tEntry.name = "test_throwing_tool" Set tFoundStub = 1
        If tEntry.name = "test_write_tool" Set tFoundStub = 1
        If tEntry.name = "session_summary" Set tFoundProd = 1
    }
    Do $$$AssertEquals(tFoundStub, 0, "Story 3.0 carry-forward: SessionAgent.Test.* stub tools EXCLUDED from production ListTools")
    Do $$$AssertEquals(tFoundProd, 1, "Production tool (session_summary) still present — exclusion is package-scoped, not over-broad")
    Quit
}

/// <p>AC-2 #2 — the abstract base itself is excluded (Abstract=1 row
/// filtered out by the discovery query).</p>
Method TestListToolsExcludesAbstractBase()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Set tFoundBase = 0
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        ; The abstract base has Parameter ToolName = "" — if the filter
        ; were broken, the empty-name entry would appear. Catch both
        ; failure modes (raw class name OR empty name leakage).
        If tEntry.name = "" Set tFoundBase = 1
    }
    Do $$$AssertEquals(tFoundBase, 0, "SessionAgent.Tool.Base (with empty ToolName) excluded from ListTools")
    Quit
}

/// <p>AC-2 #3 — happy-path dispatch returns the stub envelope AND
/// writes exactly one <CLASS>SessionAgent.Audit.ToolCall</CLASS> row
/// (NFR-S4 100% completeness).</p>
Method TestDispatchSuccessReturnsResultAndEmitsAudit()
{
    Set tCtx = ..NewInspectionCtx()
    Set tArgs = {"echo": "ping"}
    Set tResult = ""

    Set tBefore = ..CountToolCallRows("test_readonly_tool")

    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("test_readonly_tool", tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK on success path")
    Do $$$AssertTrue($IsObject(tResult), "pResult populated")
    Do $$$AssertEquals(tResult.content.%Get(0).text, "ok", "Stub envelope text returned to caller")
    Do $$$AssertEquals(tResult.structuredContent.stub, "readonly", "Stub structuredContent returned")

    Set tAfter = ..CountToolCallRows("test_readonly_tool")
    Do $$$AssertEquals(tAfter - tBefore, 1, "Exactly one ToolCall row written (NFR-S4)")
    Quit
}

/// <p>AC-2 #4 — Layer-2 read-only enforcement (FR36) blocks any
/// dispatch where the resolved subclass declares
/// <parameter>MutatesState=1</parameter>. The stub's
/// <method>Invoke</method> body throws if it ever runs, so the test
/// would surface that as a failure if the gate were broken.</p>
Method TestDispatchRejectsMutatesStateOne()
{
    Set tCtx = ..NewInspectionCtx()
    Set tArgs = {}
    Set tResult = ""

    Set tBefore = ..CountToolCallRows("test_write_tool")
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("test_write_tool", tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns OK (envelope-based error signaling)")
    Do $$$AssertEquals(tResult.%Get("isError"), 1, "Result envelope has isError=1")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "read-only policy", "Error text mentions read-only policy")

    ; Story 3.0 carry-forward fix: blocked-by-policy dispatches DO now
    ; write an audit row (NFR-S4 100% completeness). The original Story
    ; 2.10 design skipped audit on blocked paths but that opened a gap
    ; (an attacker spamming blocked tools left no trail).
    Set tAfter = ..CountToolCallRows("test_write_tool")
    Do $$$AssertEquals(tAfter - tBefore, 1, "Story 3.0 carry-forward: blocked-by-policy dispatch writes one audit row with IsError=1")
    Quit
}

/// <p>AC-2 #5 — exceptions from <method>Invoke</method> are caught by
/// the registry's outer Try/Catch and wrapped as MCP error envelopes.
/// The operator-readable text uses <code>ex.DisplayString()</code>; the
/// raw stack trace lands in
/// <property>SessionAgent.Audit.ToolCall.ErrorText</property> only
/// (architecture line 476).</p>
Method TestDispatchExceptionWrappedAsErrorEnvelope()
{
    Set tCtx = ..NewInspectionCtx()
    Set tArgs = {}
    Set tResult = ""

    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("test_throwing_tool", tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns OK even when tool throws (envelope-based error)")
    Do $$$AssertEquals(tResult.%Get("isError"), 1, "Result envelope has isError=1")
    Do $$$AssertTrue($Length(tResult.content.%Get(0).text) > 0, "Error text non-empty (carries exception message)")

    ; Verify an audit row was written and its ErrorText is non-empty
    ; (the stack-trace-only path).
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 %EXACT(ErrorText) AS ET FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName) = 'test_throwing_tool' ORDER BY ID DESC")
    Do $$$AssertStatusOK(tPrepSC, "Prepare audit ErrorText query")
    Set tRs = tStmt.%Execute()
    Do $$$AssertTrue(tRs.%Next(), "Audit row exists for throwing tool")
    Do $$$AssertTrue($Length(tRs.%Get("ET")) > 0, "ErrorText populated on audit row (stack-trace surface, NOT operator surface)")
    Quit
}

/// <p>AC-2 #6 — unknown tool name returns the standard MCP error
/// envelope without throwing. The lookup miss is a normal control-flow
/// signal, not an exception.</p>
Method TestDispatchUnknownToolReturnsErrorEnvelope()
{
    Set tCtx = ..NewInspectionCtx()
    Set tArgs = {}
    Set tResult = ""

    Set tBefore = ..CountToolCallRows("does_not_exist")
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("does_not_exist", tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns OK for unknown tool (envelope-based)")
    Do $$$AssertEquals(tResult.%Get("isError"), 1, "Result envelope has isError=1")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "unknown tool", "Error text contains 'unknown tool'")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "does_not_exist", "Error text echoes the requested tool name")

    ; Story 3.0 carry-forward fix: unknown-tool dispatches DO now
    ; write an audit row (NFR-S4 100% completeness — every Dispatch
    ; call produces exactly one row).
    Set tAfter = ..CountToolCallRows("does_not_exist")
    Do $$$AssertEquals(tAfter - tBefore, 1, "Story 3.0 carry-forward: unknown-tool dispatch writes one audit row with IsError=1")
    Quit
}

/// <p>AC-2 #7 — the <code>(SessionAgent, ToolCall, test_readonly_tool)</code>
/// triple is lazy-registered on first dispatch (Story 2.0 carry-forward
/// closed by Story 2.10; the actual <method>RegisterIfMissing</method>
/// call is delegated to
/// <method>SessionAgent.Audit.Emit.LogToolCall</method> which performs
/// it before the row save — see Story 2.5 implementation).</p>
Method TestRegisterIfMissingFiresOnFirstDispatch()
{
    ; Clean slate — explicitly delete the triple before the dispatch.
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Events).Exists("SessionAgent","ToolCall","test_readonly_tool") {
            Do ##class(Security.Events).Delete("SessionAgent","ToolCall","test_readonly_tool")
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }

    ; Confirm the triple is absent before dispatch.
    Set tBefore = ..TripleExists("test_readonly_tool")
    Do $$$AssertEquals(tBefore, 0, "Triple absent before dispatch")

    ; Dispatch one call.
    Set tCtx = ..NewInspectionCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("test_readonly_tool", tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch OK")

    ; Confirm the triple now exists (lazy-registered through
    ; LogToolCall → RegisterIfMissing).
    Set tAfter = ..TripleExists("test_readonly_tool")
    Do $$$AssertEquals(tAfter, 1, "Triple lazy-registered after dispatch")
    Quit
}

/// <p>Helper — count <CLASS>SessionAgent.Audit.ToolCall</CLASS> rows
/// for the given ToolName. Used by both the success and the
/// blocked-dispatch tests.</p>
Method CountToolCallRows(pToolName As %String) As %Integer
{
    Set tCount = 0
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT COUNT(*) AS C FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName) = ?")
    If $$$ISERR(tSC) Quit 0
    Set tRs = tStmt.%Execute(pToolName)
    If tRs.%Next() Set tCount = tRs.%Get("C")
    Quit tCount
}

/// <p>Helper — check whether the
/// <code>(SessionAgent, ToolCall, &lt;pToolName&gt;)</code> triple is
/// registered in <code>%SYS Security.Events</code>. Uses the explicit
/// save/restore pattern for <code>$NAMESPACE</code>.</p>
Method TripleExists(pToolName As %String) As %Boolean
{
    Set tExists = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Set tExists = ##class(Security.Events).Exists("SessionAgent","ToolCall",pToolName)
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tExists
}

/// <p>Story 3.0 AC-6 — Dispatch must populate the standard MCP error
/// envelope when called with a NULLOREF or wrong-type
/// <var>pCallerCtx</var>, NEVER throw, and STILL emit an audit row
/// (Rule 8 Fix #5 — always-audit semantics hold even on guard paths).</p>
Method TestDispatchRejectsNullCallerCtx()
{
    ; Case A — NULLOREF pCallerCtx.
    Set tArgs = {}
    Set tResult = ""
    Set tBefore = ..CountToolCallRows("test_readonly_tool")
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("test_readonly_tool", $$$NULLOREF, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK on NULLOREF pCallerCtx (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on NULLOREF pCallerCtx")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "CallerContext", "error text mentions 'CallerContext'")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "Internal", "error text marks the failure as 'Internal'")

    ; Always-audit invariant — one ToolCall row written even on the guard path.
    Set tAfter = ..CountToolCallRows("test_readonly_tool")
    Do $$$AssertEquals(tAfter - tBefore, 1, "Always-audit: NULLOREF pCallerCtx still writes exactly one audit row")

    ; Case B — wrong-type pCallerCtx (a plain %DynamicObject).
    Set tBogusCtx = ##class(%DynamicObject).%New()
    Do tBogusCtx.%Set("AgentName", "session-inspection")
    Set tBefore2 = ..CountToolCallRows("test_readonly_tool")
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Registry).Dispatch("test_readonly_tool", tBogusCtx, tArgs, .tResult2)
    Do $$$AssertStatusOK(tSC2, "Dispatch returns $$$OK on wrong-type pCallerCtx")
    Do $$$AssertEquals(+tResult2.%Get("isError"), 1, "isError=1 on wrong-type pCallerCtx")
    Set tAfter2 = ..CountToolCallRows("test_readonly_tool")
    Do $$$AssertEquals(tAfter2 - tBefore2, 1, "Always-audit: wrong-type pCallerCtx still writes exactly one audit row")
    Quit
}

}
