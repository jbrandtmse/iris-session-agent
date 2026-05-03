/// <p>Shared base class for the Story 2.12 AgentLoop test families.
/// Holds the OnBefore/OnAfter setup, the helper methods that build
/// canned OpenAI-shape responses, and the override-installation
/// helpers. Subclasses (<CLASS>SessionAgent.Test.AgentLoopTest</CLASS>
/// + <CLASS>SessionAgent.Test.AgentLoopGuardsTest</CLASS>) hold only
/// the test methods themselves; the split keeps each subclass small
/// enough to fit within the MCP test-runner's per-class time budget
/// (the runner adds non-trivial framework overhead per test method
/// that drives the AgentLoop iteration loop, so packing too many
/// loop-driving tests into one subclass causes the runner to truncate
/// late tests).</p>
///
/// <p>Not abstract — IRIS unit-test framework discovers concrete
/// subclasses; making the base abstract is unnecessary because there
/// are no <code>Test*</code> methods on it (no test ever runs against
/// the base directly).</p>
Class SessionAgent.Test.AgentLoopTestBase Extends %UnitTest.TestCase [ Abstract ]
{

/// <p>Stable per-test session-key prefix; the suffix is the method
/// name. Built once at class load to keep the tuple deterministic
/// across the test methods.</p>
Parameter SESSIONKEYPREFIX As %String = "al-test";

/// <p>Captured original <code>Enabled</code> value for the
/// <code>session-inspection</code> agent so
/// <method>OnAfterOneTest</method> restores any mutation a test
/// performed (e.g., the Disabled-agent test flips it to 0 then must
/// flip it back).</p>
Property OrigEnabled As %Boolean;

/// <p>Captured original <code>Provider</code> value for the
/// <code>session-inspection</code> agent so cleanup restores any
/// test mutation that swapped in a non-openai provider name.</p>
Property OrigProvider As %String;

/// <p>Constructor — accepts <code>initvalue</code>, forwards via
/// <code>##super</code> per project rule §"Critical Constructor
/// Requirements". No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OrigEnabled = 0
    Set ..OrigProvider = ""
    Quit $$$OK
}

/// <p>Per-test setup — capture original Config.Agent fields, ensure
/// the inspection agent is enabled with provider="openai" so the
/// mock-provider override path is exercised, clear any prior
/// override from a leaked previous test.</p>
Method OnBeforeOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
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

/// <p>Per-test teardown — clear the override, restore the captured
/// Config.Agent fields. Chat-history rows from this test method are
/// left in place for inspection; the per-test session-key prefix
/// ensures different methods do not collide.
/// <method>OnAfterAllTests</method> sweeps the prefix at the end.</p>
Method OnAfterOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfg) {
        Set tCfg.Enabled = ..OrigEnabled
        Set tCfg.Provider = ..OrigProvider
        Do tCfg.%Save()
    }
    Quit $$$OK
}

/// <p>End-of-class cleanup — sweep any chat-history rows whose
/// <property>SessionKey</property> matches the per-test prefix.</p>
Method OnAfterAllTests() As %Status
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH ?")) {
        Do tStmt.%Execute(..#SESSIONKEYPREFIX)
    }
    Quit $$$OK
}

/// <p>Build the per-test session key (unique per method to avoid
/// cross-test concurrency issues if the runner ever parallelizes).</p>
Method SessionKey(pSuffix As %String) As %String
{
    Quit ..#SESSIONKEYPREFIX _ "-" _ pSuffix
}

/// <p>Helper — install the AgentLoopMockProvider as the per-process
/// override with the given response list. Builds a JSON config of
/// the shape <code>{"responses":[...]}</code> and stashes it via
/// <method>SessionAgent.Agent.ProviderOverride.SetOverride</method>.
/// Each subsequent call to
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// instantiates a fresh
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> that reads
/// the next canned response on each round-trip.</p>
ClassMethod InstallMockProvider(pResponses As %DynamicArray)
{
    Set tConfig = ##class(%DynamicObject).%New()
    Do tConfig.%Set("responses", pResponses)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentLoopMockProvider", tConfig.%ToJSON())
    Quit
}

/// <p>Helper — install the override with both responses and per-call
/// status codes (for testing HTTP-error paths).</p>
ClassMethod InstallMockProviderWithStatuses(pResponses As %DynamicArray, pStatusCodes As %DynamicArray)
{
    Set tConfig = ##class(%DynamicObject).%New()
    Do tConfig.%Set("responses", pResponses)
    Do tConfig.%Set("statusCodes", pStatusCodes)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentLoopMockProvider", tConfig.%ToJSON())
    Quit
}

/// <p>Helper — build a single OpenAI-shape response body the mock
/// will return verbatim. Two flavors:</p>
/// <ul>
/// <li>Text/end_turn: <var>pText</var> populated, <var>pToolName</var>
/// empty.</li>
/// <li>Tool_use: <var>pToolName</var> + <var>pToolArgsJson</var>
/// populated.</li>
/// </ul>
ClassMethod BuildOpenAiResponse(pText As %String = "", pToolName As %String = "", pToolArgsJson As %String = "{}") As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    If pToolName '= "" {
        ; tool_calls path — finish_reason = tool_calls
        Set tCalls = ##class(%DynamicArray).%New()
        Set tCall = ##class(%DynamicObject).%New()
        Do tCall.%Set("id", "call_test_" _ pToolName)
        Do tCall.%Set("type", "function")
        Set tFn = ##class(%DynamicObject).%New()
        Do tFn.%Set("name", pToolName)
        Do tFn.%Set("arguments", pToolArgsJson)
        Do tCall.%Set("function", tFn)
        Do tCalls.%Push(tCall)
        Do tMsg.%Set("tool_calls", tCalls)
        Do tMsg.%Set("content", "")
        Do tChoice.%Set("finish_reason", "tool_calls")
    } Else {
        ; text/stop path — finish_reason = stop
        Do tMsg.%Set("content", pText)
        Do tChoice.%Set("finish_reason", "stop")
    }
    Do tChoice.%Set("message", tMsg)
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 5)
    Do tUsage.%Set("completion_tokens", 7)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>Helper — build an OpenAI HTTP-error response body that the
/// mock returns with <var>pStatusCode</var>. The body shape mirrors
/// OpenAI's documented error envelope so the OpenAIProvider's
/// non-2xx classifier surfaces it verbatim.</p>
ClassMethod BuildErrorResponse(pStatusCode As %Integer) As %String
{
    Set tBody = ##class(%DynamicObject).%New()
    Set tErr = ##class(%DynamicObject).%New()
    Do tErr.%Set("message", "Synthetic test error " _ pStatusCode)
    Do tErr.%Set("type", "test_error")
    Do tBody.%Set("error", tErr)
    Quit tBody.%ToJSON()
}

}
