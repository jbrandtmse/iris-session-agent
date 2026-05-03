/// <p>Sibling unit tests to <CLASS>SessionAgent.Test.AgentLoopTest</CLASS>
/// covering the guard-clause invariants — max-iter cap, never-throw on
/// provider error, disabled-agent guard, unconfigured-agent guard.
/// Split out per the rationale on
/// <CLASS>SessionAgent.Test.AgentLoopTestBase</CLASS> (per-class
/// runner-overhead budget).</p>
Class SessionAgent.Test.AgentLoopGuardsTest Extends SessionAgent.Test.AgentLoopTestBase
{

/// <p>AC-2 #2 — max-iter cap. Mock returns
/// <code>tool_use</code> for <code>session_summary</code> on every
/// turn forever. Assert the loop terminates at
/// <parameter>MaxIterationsPerTurn</parameter>=10 and the persisted
/// history contains the synthetic "Max iterations reached" assistant
/// turn.</p>
Method TestRunTurnMaxIterationsCap()
{
    Set tSessionKey = ..SessionKey("maxiter")
    ; Build 12 identical tool_use responses; the mock's wrap-around
    ; behavior also keeps it from running off the end (defensive — the
    ; loop should cap at 10 long before this).
    Set tResponses = ##class(%DynamicArray).%New()
    For tI = 1:1:12 {
        Do tResponses.%Push(..BuildOpenAiResponse("", "session_summary", "{""session_id"":""nonexistent""}"))
    }
    Do ..InstallMockProvider(tResponses)

    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "loop forever")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult OREF")
    Do $$$AssertTrue(tResult.AssistantMarkdown [ "Max iterations reached", "AssistantMarkdown contains 'Max iterations reached' (got: " _ tResult.AssistantMarkdown _ ")")

    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row was persisted")
    Set tHistId = tHist.%Id()
    Do tHist.%Close()

    ; Assert exactly 10 LlmCall rows for this chat-history (one per
    ; iteration, capped at MaxIterationsPerTurn).
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs = tStmt.%Execute(tHistId)
    Set tCount = -1
    If tRs.%Next() Set tCount = +tRs.%Get("cnt")
    Do $$$AssertEquals(tCount, 10, "LlmCall row count = MaxIterationsPerTurn=10 (got: " _ tCount _ ")")
    Quit
}

/// <p>AC-2 #4 — never-throw on provider error. Mock returns an HTTP
/// 500 (the mock CallMessages classifies non-2xx as the OpenAI HTTP
/// error envelope), assert <method>RunTurn</method> does NOT throw,
/// returns a TurnResult with the error message in
/// <property>AssistantMarkdown</property>, and the chat-history row
/// was persisted (lock released).</p>
Method TestRunTurnNoExceptionEvenIfProviderErrors()
{
    Set tSessionKey = ..SessionKey("provider-error")
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push(..BuildErrorResponse(500))
    Set tStatuses = ##class(%DynamicArray).%New()
    Do tStatuses.%Push(500)
    Do ..InstallMockProviderWithStatuses(tResponses, tStatuses)

    Set tThrew = 0
    Set tResult = ""
    Try {
        Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "trigger 500")
    } Catch ex {
        Set tThrew = 1
    }
    Do $$$AssertEquals(tThrew, 0, "RunTurn never throws (caught nothing)")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returned TurnResult OREF on provider error")
    Do $$$AssertTrue((tResult.AssistantMarkdown [ "OpenAI") || (tResult.AssistantMarkdown [ "error"), "AssistantMarkdown carries operator-readable error (got: " _ tResult.AssistantMarkdown _ ")")

    ; Lock-released invariant — Chat.History row persisted.
    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row was persisted (lock released even on provider error)")
    If $IsObject(tHist) Do tHist.%Close()
    Quit
}

/// <p>AC-2 #5 — disabled-agent guard. Set
/// <code>Config.Agent.Enabled=0</code> for inspection; assert
/// <method>RunTurn</method> returns the structured envelope
/// <code>"Agent session-inspection is disabled"</code>; the lock is
/// not held (a follow-on <method>LoadOrCreate</method> succeeds
/// immediately).</p>
Method TestRunTurnDisabledAgentReturnsErrorTurnResult()
{
    Set tSessionKey = ..SessionKey("disabled")
    ; Mutate Enabled to 0; OnAfterOneTest restores from OrigEnabled.
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tCfg), "Config.Agent row exists")
    Set tCfg.Enabled = 0
    Do tCfg.%Save()

    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, "tester", "should fail")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult on disabled agent")
    Do $$$AssertTrue(tResult.AssistantMarkdown [ "disabled", "AssistantMarkdown carries disabled message (got: " _ tResult.AssistantMarkdown _ ")")

    ; Lock-released invariant.
    Set tStatus = $$$OK
    Set tHist2 = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", tSessionKey, "tester", "", .tStatus)
    Do $$$AssertTrue($IsObject(tHist2), "LoadOrCreate succeeds after disabled-agent return (lock released)")
    If $IsObject(tHist2) Do tHist2.%Save()
    Quit
}

/// <p>AC-2 #6 — unconfigured-agent guard. Pass an
/// <var>pAgentName</var> that has no
/// <CLASS>SessionAgent.Config.Agent</CLASS> row; assert
/// <method>RunTurn</method> returns the
/// <code>"Agent not configured: &lt;name&gt;"</code> envelope and
/// does not throw.</p>
Method TestRunTurnUnconfiguredAgentReturnsErrorTurnResult()
{
    Set tSessionKey = ..SessionKey("unconfigured")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("nonexistent", tSessionKey, "tester", "no agent")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult on unconfigured agent")
    Do $$$AssertTrue(tResult.AssistantMarkdown [ "not configured", "AssistantMarkdown carries 'not configured' message (got: " _ tResult.AssistantMarkdown _ ")")
    Quit
}

}
