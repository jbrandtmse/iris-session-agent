/// <p>End-to-end smoke test for Story 2.12 — exercises the full
/// orchestration path from <method>SessionAgent.Agent.AgentLoop.RunTurn</method>
/// through provider mock, tool dispatch, audit emission, and chat-history
/// persistence. The pre-alpha demo gate per Epic 2 — when this test
/// passes, the maintainer has empirical confidence that the backend
/// is wireable end-to-end before staking pilot operators on the UI in
/// Epic 3.</p>
///
/// <p><b>Fixture.</b> Seeds 5 <CLASS>Ens.MessageHeader</CLASS> rows
/// for <code>SessionId=2-12-smoke</code> in <method>OnBeforeAllTests</method>;
/// cleans them up in <method>OnAfterAllTests</method>. The fixture
/// shape mirrors <CLASS>SessionAgent.Test.InspectionToolTest</CLASS>'s
/// 5-row pattern (2 rows with <code>IsError=1</code>) so the
/// <CLASS>SessionAgent.Tool.Inspection.SessionSummary</CLASS> tool
/// returns deterministic counts.</p>
///
/// <p><b>Mock provider.</b> Same
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> +
/// <CLASS>SessionAgent.Agent.ProviderOverride</CLASS> mechanism the
/// AgentLoopTest family uses. The smoke test installs a 2-turn
/// scripted dialog: turn 1 returns
/// <code>tool_use:session_summary</code>; turn 2 returns
/// <code>end_turn</code> with the deterministic substring "5 messages"
/// the test asserts on.</p>
Class SessionAgent.Test.SmokeTest Extends %UnitTest.TestCase
{

/// <p>Numeric session id for the fixture
/// <CLASS>Ens.MessageHeader</CLASS> rows. Outside the range of any
/// realistic Ens production value to avoid collision; chosen
/// distinct from <CLASS>SessionAgent.Test.InspectionToolTest</CLASS>'s
/// 999911 so concurrent test runs do not poison each other's count
/// assertions.</p>
Parameter SMOKESESSIONID As %Integer = 999212;

/// <p>Conversation key the smoke test uses to drive
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method>.</p>
Parameter SMOKECONVKEY As %String = "smoke-conv-1";

/// <p>Captured original Config.Agent.Enabled so cleanup restores it.</p>
Property OrigEnabled As %Boolean;

/// <p>Captured original Config.Agent.Provider so cleanup restores it.</p>
Property OrigProvider As %String;

/// <p>Constructor — accepts <code>initvalue</code>, forwards via
/// <code>##super</code> per project rule §"Critical Constructor
/// Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OrigEnabled = 0
    Set ..OrigProvider = ""
    Quit $$$OK
}

/// <p>Seed 5 <CLASS>Ens.MessageHeader</CLASS> fixture rows for
/// <code>SessionId = 999212</code>. Two rows carry
/// <code>IsError=1</code> (rows 3 and 5). Mirrors the
/// <CLASS>SessionAgent.Test.InspectionToolTest</CLASS> seed pattern
/// (5 rows, 2 errors) so the
/// <CLASS>SessionAgent.Tool.Inspection.SessionSummary</CLASS> tool
/// returns deterministic counts the smoke assertion latches onto.</p>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentSmokeTestIds
    Set tSession = ..#SMOKESESSIONID

    ; Defensive sweep — remove any prior-run debris so the seeded
    ; count is deterministic.
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tCleanup.%Execute(tSession)
    }

    Set tBaseDate = +$Horolog
    Set tBaseSecs = +$Piece($Horolog, ",", 2)
    For tIdx = 1:1:5 {
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tSession
        Set tHdr.SourceConfigName = "SmokeSource_" _ tIdx
        Set tHdr.TargetConfigName = "SmokeTarget_" _ tIdx
        Set tHdr.MessageBodyClassName = $Case(tIdx, 1: "Smoke.RootRequest", : "Smoke.FollowupMessage_" _ tIdx)
        Set tShiftedSecs = tBaseSecs + tIdx
        Set tShiftedHorolog = $Select(tShiftedSecs >= 86400: (tBaseDate + 1) _ "," _ (tShiftedSecs - 86400), 1: tBaseDate _ "," _ tShiftedSecs)
        Set tHdr.TimeCreated = $ZDateTime(tShiftedHorolog, 3, 1, 0)
        Set tHdr.IsError = $Case(tIdx, 3: 1, 5: 1, : 0)
        Set tSaveSC = tHdr.%Save()
        If $$$ISERR(tSaveSC) Quit
        Set ^||SessionAgentSmokeTestIds(tIdx) = tHdr.%Id()
    }

    ; Capture + adjust Config.Agent.session-inspection.
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfg) {
        Set ..OrigEnabled = tCfg.Enabled
        Set ..OrigProvider = tCfg.Provider
        Set tCfg.Enabled = 1
        Set tCfg.Provider = "openai"
        Do tCfg.%Save()
    }

    Quit $$$OK
}

/// <p>Cleanup — delete the 5 fixture rows by ID; clear the override;
/// restore Config.Agent fields; sweep the chat-history row created
/// by the smoke turn.</p>
Method OnAfterAllTests() As %Status
{
    For tIdx = 1:1:5 {
        Set tId = $Get(^||SessionAgentSmokeTestIds(tIdx))
        If tId '= "" {
            Do ##class(Ens.MessageHeader).%DeleteId(tId)
        }
    }
    Kill ^||SessionAgentSmokeTestIds
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId = ?")) {
        Do tStmt.%Execute(..#SMOKESESSIONID)
    }

    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfg) {
        Set tCfg.Enabled = ..OrigEnabled
        Set tCfg.Provider = ..OrigProvider
        Do tCfg.%Save()
    }

    Set tStmt2 = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt2.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) = ?")) {
        Do tStmt2.%Execute(..#SMOKECONVKEY)
    }
    Quit $$$OK
}

/// <p>The end-to-end smoke. Drives the full
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> path:
/// (1) install a deterministic 2-turn mock dialog, (2) call
/// <method>RunTurn</method> with the smoke session key,
/// (3) assert the AssistantMarkdown contains the deterministic
/// substring, (4) assert audit completeness (2 LlmCall + 1 ToolCall
/// rows for the new chat-history id), (5) assert the persisted
/// <property>TurnsJson</property> contains the 4 expected turns.</p>
Method TestSmokeEndToEnd()
{
    ; Build deterministic 2-turn dialog.
    Set tResponses = ##class(%DynamicArray).%New()

    ; Turn 1: tool_use for session_summary against the fixture session.
    Set tArgs1 = "{""session_id"":""" _ ..#SMOKESESSIONID _ """}"
    Do tResponses.%Push(..BuildToolUseResponse("session_summary", tArgs1))

    ; Turn 2: end_turn with the deterministic substring.
    Do tResponses.%Push(..BuildEndTurnResponse("Session " _ ..#SMOKESESSIONID _ " has 5 messages with 2 errors."))

    Set tCfg = ##class(%DynamicObject).%New()
    Do tCfg.%Set("responses", tResponses)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentLoopMockProvider", tCfg.%ToJSON())

    ; (3) Drive RunTurn end-to-end.
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SMOKECONVKEY, "tester", "Tell me about session " _ ..#SMOKESESSIONID)
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returned a TurnResult OREF")

    ; (4) AssistantMarkdown contains the deterministic substring.
    Do $$$AssertTrue(tResult.AssistantMarkdown [ "5 messages", "AssistantMarkdown contains '5 messages' (got: " _ tResult.AssistantMarkdown _ ")")

    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", ..#SMOKECONVKEY, "tester")
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row was persisted")
    Set tHistId = tHist.%Id()

    ; (5a) Two LlmCall rows for this chat-history id.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs = tStmt.%Execute(tHistId)
    Set tLlmCount = -1
    If tRs.%Next() Set tLlmCount = +tRs.%Get("cnt")
    Do $$$AssertEquals(tLlmCount, 2, "LlmCall row count = 2 (got: " _ tLlmCount _ ")")

    ; (5b) One ToolCall row for this chat-history id.
    Set tStmt2 = ##class(%SQL.Statement).%New()
    Do tStmt2.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRs2 = tStmt2.%Execute(tHistId)
    Set tToolCount = -1
    If tRs2.%Next() Set tToolCount = +tRs2.%Get("cnt")
    Do $$$AssertEquals(tToolCount, 1, "ToolCall row count = 1 (got: " _ tToolCount _ ")")

    ; (6) TurnsJson contains 4 entries: user, assistant tool_use,
    ; tool_result, assistant final.
    Do tHist.TurnsJson.Rewind()
    Set tTurnsBuf = ""
    While 'tHist.TurnsJson.AtEnd {
        Set tTurnsBuf = tTurnsBuf _ tHist.TurnsJson.Read(32000)
    }
    Set tTurnsArr = ##class(%DynamicArray).%FromJSON(tTurnsBuf)
    Do $$$AssertEquals(tTurnsArr.%Size(), 4, "TurnsJson contains 4 entries (user / assistant tool_use / tool_result / assistant final; got: " _ tTurnsArr.%Size() _ ")")

    Set tTurn0 = tTurnsArr.%Get(0)
    Do $$$AssertEquals(tTurn0.%Get("role"), "user", "Turn 0 is the user message")
    Set tTurn3 = tTurnsArr.%Get(3)
    Do $$$AssertEquals(tTurn3.%Get("role"), "assistant", "Turn 3 is the final assistant turn")

    Do tHist.%Close()
    Quit
}

/// <p>Helper — build an OpenAI-shape response with a tool_calls
/// finish_reason. Same shape as
/// <CLASS>SessionAgent.Test.AgentLoopTestBase</CLASS>'s
/// <method>BuildOpenAiResponse</method> tool_use branch; copied here
/// so the smoke test does not couple to the AgentLoopTestBase class.</p>
ClassMethod BuildToolUseResponse(pToolName As %String, pToolArgsJson As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Set tCalls = ##class(%DynamicArray).%New()
    Set tCall = ##class(%DynamicObject).%New()
    Do tCall.%Set("id", "call_smoke_" _ pToolName)
    Do tCall.%Set("type", "function")
    Set tFn = ##class(%DynamicObject).%New()
    Do tFn.%Set("name", pToolName)
    Do tFn.%Set("arguments", pToolArgsJson)
    Do tCall.%Set("function", tFn)
    Do tCalls.%Push(tCall)
    Do tMsg.%Set("tool_calls", tCalls)
    Do tMsg.%Set("content", "")
    Do tChoice.%Set("message", tMsg)
    Do tChoice.%Set("finish_reason", "tool_calls")
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 12)
    Do tUsage.%Set("completion_tokens", 8)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Helper — build an OpenAI-shape response with finish_reason=stop
/// and the given text content.</p>
ClassMethod BuildEndTurnResponse(pText As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Do tMsg.%Set("content", pText)
    Do tChoice.%Set("message", tMsg)
    Do tChoice.%Set("finish_reason", "stop")
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 18)
    Do tUsage.%Set("completion_tokens", 22)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

}
