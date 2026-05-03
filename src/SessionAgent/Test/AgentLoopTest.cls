/// <p>Unit tests for <CLASS>SessionAgent.Agent.AgentLoop</CLASS>
/// (Story 2.12 — capstone of Epic 2). Verifies the orchestration
/// invariants that DO trigger the iteration loop — single-turn happy
/// path, lock-release discipline, and audit-row completeness for
/// tool dispatch.</p>
///
/// <p><b>Sibling class:</b>
/// <CLASS>SessionAgent.Test.AgentLoopGuardsTest</CLASS> covers the
/// guard-clause tests (max-iter cap, never-throw on provider error,
/// disabled-agent guard, unconfigured-agent guard) — split out
/// because each test method that actually drives the iteration loop
/// adds non-trivial framework overhead in the MCP test runner. Two
/// smaller classes keep each batch within the runner's per-class
/// time budget.</p>
///
/// <p><b>Mock-provider injection.</b> See
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> +
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> for the
/// design rationale (why a process-private global cannot carry an
/// OREF — OREF stringification on global assignment loses object
/// identity).</p>
Class SessionAgent.Test.AgentLoopTest Extends SessionAgent.Test.AgentLoopTestBase
{

/// <p>AC-2 #1 — single-turn happy path. Mock returns
/// <code>finish_reason=stop</code> with text content. Assert
/// <property>TurnResult.AssistantMarkdown</property> contains the
/// expected text and that exactly 1 LlmCall row was emitted.</p>
Method TestRunTurnWithMockProviderSingleTurn()
{
    Set tSessionKey = ..SessionKey("single")
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push(..BuildOpenAiResponse("Hello from the mock provider."))
    Do ..InstallMockProvider(tResponses)

    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "Say hello")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult OREF")
    Do $$$AssertTrue(tResult.AssistantMarkdown [ "Hello from the mock provider", "AssistantMarkdown contains mock text (got: " _ tResult.AssistantMarkdown _ ")")
    Do $$$AssertTrue(tResult.DurationMs >= 0, "DurationMs non-negative")

    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row was persisted")
    Set tHistId = tHist.%Id()
    Do tHist.%Close()

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs = tStmt.%Execute(tHistId)
    Set tCount = -1
    If tRs.%Next() Set tCount = +tRs.%Get("cnt")
    Do $$$AssertEquals(tCount, 1, "LlmCall row count for this turn = 1 (got: " _ tCount _ ")")
    Quit
}

/// <p>AC-2 #3 — lock-release discipline. After
/// <method>RunTurn</method> returns, the chat-history row's per-row
/// lock must be released so a follow-on
/// <method>SessionAgent.Chat.History.LoadOrCreate</method> succeeds
/// immediately (returns an OREF, not <code>$$$NULLOREF</code>).</p>
Method TestRunTurnLockReleasedOnSave()
{
    Set tSessionKey = ..SessionKey("lockrelease")
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push(..BuildOpenAiResponse("first turn done"))
    Do ..InstallMockProvider(tResponses)

    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "first")
    Do $$$AssertTrue($IsObject(tResult), "first RunTurn returned TurnResult")

    ; The lock should be released — re-acquire via LoadOrCreate.
    Set tStatus = $$$OK
    Set tHist2 = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", tSessionKey, "tester", "", .tStatus)
    Do $$$AssertTrue($IsObject(tHist2), "second LoadOrCreate after RunTurn succeeds (lock released)")
    Do $$$AssertStatusOK(tStatus, "LoadOrCreate returned $$$OK")
    If $IsObject(tHist2) {
        ; Release the lock our test acquired so cleanup works.
        Do tHist2.%Save()
    }
    Quit
}

/// <p>AC-2 #7 — audit-row completeness for tool dispatch. Mock returns
/// <code>tool_use</code> for <code>session_summary</code> on turn 1
/// then <code>end_turn</code> with text on turn 2. Assert exactly 2
/// LlmCall rows AND 1 ToolCall row exist for the chat-history id.</p>
Method TestRunTurnAuditCompletenessForToolDispatch()
{
    Set tSessionKey = ..SessionKey("audit")
    Set tResponses = ##class(%DynamicArray).%New()
    ; Turn 1 — tool_use for session_summary against a fake session id;
    ; we don't care if the tool errors — what we audit is the dispatch
    ; happened.
    Do tResponses.%Push(..BuildOpenAiResponse("", "session_summary", "{""session_id"":""999999""}"))
    ; Turn 2 — terminal end_turn with text.
    Do tResponses.%Push(..BuildOpenAiResponse("Done with the dispatch."))
    Do ..InstallMockProvider(tResponses)

    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "use a tool")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")

    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row persisted")
    Set tHistId = tHist.%Id()
    Do tHist.%Close()

    ; Two LlmCall rows for this ChatHistoryId.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs = tStmt.%Execute(tHistId)
    Set tLlmCount = -1
    If tRs.%Next() Set tLlmCount = +tRs.%Get("cnt")
    Do $$$AssertEquals(tLlmCount, 2, "LlmCall row count = 2 (one per provider round-trip; got: " _ tLlmCount _ ")")

    ; One ToolCall row for this ChatHistoryId.
    Set tStmt2 = ##class(%SQL.Statement).%New()
    Do tStmt2.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs2 = tStmt2.%Execute(tHistId)
    Set tToolCount = -1
    If tRs2.%Next() Set tToolCount = +tRs2.%Get("cnt")
    Do $$$AssertEquals(tToolCount, 1, "ToolCall row count = 1 (one tool dispatched; got: " _ tToolCount _ ")")
    Quit
}

}
