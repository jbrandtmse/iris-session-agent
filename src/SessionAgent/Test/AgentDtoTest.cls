/// <p>Unit tests for the three Agent DTO classes shipped by Story 2.7:
/// <CLASS>SessionAgent.Agent.CallerContext</CLASS>,
/// <CLASS>SessionAgent.Agent.ProviderResponse</CLASS>, and
/// <CLASS>SessionAgent.Agent.TurnResult</CLASS>.</p>
///
/// <p>Verifies the six behaviors required by Story 2.7 acceptance
/// criterion AC-4:</p>
/// <ol>
/// <li><b>TestCallerContextRoundTrip</b> — set + read all 5
/// properties on <CLASS>CallerContext</CLASS>.</li>
/// <li><b>TestProviderResponseRoundTrip</b> — set + read 3
/// properties on <CLASS>ProviderResponse</CLASS>; verify the
/// <CLASS>%DynamicArray</CLASS> / <CLASS>%DynamicObject</CLASS>
/// properties preserve their shape.</li>
/// <li><b>TestTurnResultRoundTrip</b> — set + read all 4
/// properties on <CLASS>TurnResult</CLASS>.</li>
/// <li><b>TestTurnResultToJsonProducesExpectedKeys</b> —
/// <method>ToJson</method> emits the four documented top-level
/// keys.</li>
/// <li><b>TestTurnResultToJsonHandlesEmptyArrays</b> — empty
/// <property>ToolCallsRendered</property> renders as
/// <code>"toolCallsRendered":[]</code>.</li>
/// <li><b>TestNoBusinessLogic</b> — sanity check via
/// <CLASS>%Dictionary.MethodDefinition</CLASS>: no DTO has any
/// non-trivial method beyond <method>ToJson</method> on
/// <CLASS>TurnResult</CLASS>.</li>
/// </ol>
Class SessionAgent.Test.AgentDtoTest Extends %UnitTest.TestCase
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

/// <p>AC-4 #1 — instantiate <CLASS>CallerContext</CLASS>, set all 5
/// properties, read them back; verify each.</p>
Method TestCallerContextRoundTrip()
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = "12345"
    Set tCtx.SearchSessionKey = ""
    Set tCtx.PortalUser = "alice"
    Set tCtx.Namespace = "HSCUSTOM"

    Do $$$AssertEquals(tCtx.AgentName, "session-inspection", "AgentName round-trips")
    Do $$$AssertEquals(tCtx.IrisSessionId, "12345", "IrisSessionId round-trips")
    Do $$$AssertEquals(tCtx.SearchSessionKey, "", "SearchSessionKey round-trips (empty for inspection)")
    Do $$$AssertEquals(tCtx.PortalUser, "alice", "PortalUser round-trips")
    Do $$$AssertEquals(tCtx.Namespace, "HSCUSTOM", "Namespace round-trips")
    Quit
}

/// <p>AC-4 #2 — instantiate <CLASS>ProviderResponse</CLASS>, set
/// <property>Content</property> as a
/// <CLASS>%DynamicArray</CLASS>, <property>StopReason</property>
/// as a string, <property>Usage</property> as a
/// <CLASS>%DynamicObject</CLASS>; read back; verify the dynamic
/// types preserve their shape.</p>
Method TestProviderResponseRoundTrip()
{
    Set tResp = ##class(SessionAgent.Agent.ProviderResponse).%New()

    ; Build a canonical Anthropic content array with one text block
    ; and one tool_use block.
    Set tContent = ##class(%DynamicArray).%New()
    Do tContent.%Push({"type": "text", "text": "hello"})
    Do tContent.%Push({"type": "tool_use", "id": "call_1", "name": "FindSession", "input": {"q": "abc"}})
    Set tResp.Content = tContent

    Set tResp.StopReason = "tool_use"

    Set tUsage = ##class(%DynamicObject).%New()
    Set tUsage."input_tokens" = 100
    Set tUsage."output_tokens" = 50
    Set tUsage."cache_creation_input_tokens" = 0
    Set tUsage."cache_read_input_tokens" = 0
    Set tResp.Usage = tUsage

    ; StopReason scalar.
    Do $$$AssertEquals(tResp.StopReason, "tool_use", "StopReason round-trips")

    ; Content is still a %DynamicArray of length 2; element shape preserved.
    Do $$$AssertEquals(tResp.Content.%Size(), 2, "Content has 2 blocks")
    Do $$$AssertEquals(tResp.Content.%Get(0).%Get("type"), "text", "Content[0].type = text")
    Do $$$AssertEquals(tResp.Content.%Get(0).%Get("text"), "hello", "Content[0].text preserved")
    Do $$$AssertEquals(tResp.Content.%Get(1).%Get("type"), "tool_use", "Content[1].type = tool_use")
    Do $$$AssertEquals(tResp.Content.%Get(1).%Get("name"), "FindSession", "Content[1].name preserved")
    Do $$$AssertEquals(tResp.Content.%Get(1).%Get("input").%Get("q"), "abc", "Content[1].input.q preserved")

    ; Usage is still a %DynamicObject with the four canonical keys.
    Do $$$AssertEquals(tResp.Usage."input_tokens", 100, "Usage.input_tokens preserved")
    Do $$$AssertEquals(tResp.Usage."output_tokens", 50, "Usage.output_tokens preserved")
    Do $$$AssertEquals(tResp.Usage."cache_creation_input_tokens", 0, "Usage.cache_creation_input_tokens preserved")
    Do $$$AssertEquals(tResp.Usage."cache_read_input_tokens", 0, "Usage.cache_read_input_tokens preserved")
    Quit
}

/// <p>AC-4 #3 — instantiate <CLASS>TurnResult</CLASS>, set all 4
/// properties, read them back; verify each.</p>
Method TestTurnResultRoundTrip()
{
    Set tResult = ##class(SessionAgent.Agent.TurnResult).%New()

    Set tResult.AssistantMarkdown = "# Found 3 sessions\n\n- session 12345\n- session 12346\n- session 12347"

    Set tUsage = ##class(%DynamicObject).%New()
    Set tUsage."input_tokens" = 250
    Set tUsage."output_tokens" = 125
    Set tResult.UsageRollup = tUsage

    Set tResult.DurationMs = 4321

    Set tCalls = ##class(%DynamicArray).%New()
    Do tCalls.%Push({"name": "FindSession", "args": {"q": "abc"}, "result": {"count": 3}, "status": "ok"})
    Set tResult.ToolCallsRendered = tCalls

    Do $$$AssertTrue(tResult.AssistantMarkdown [ "Found 3 sessions", "AssistantMarkdown round-trips")
    Do $$$AssertEquals(tResult.UsageRollup."input_tokens", 250, "UsageRollup.input_tokens preserved")
    Do $$$AssertEquals(tResult.UsageRollup."output_tokens", 125, "UsageRollup.output_tokens preserved")
    Do $$$AssertEquals(tResult.DurationMs, 4321, "DurationMs round-trips")
    Do $$$AssertEquals(tResult.ToolCallsRendered.%Size(), 1, "ToolCallsRendered has 1 entry")
    Do $$$AssertEquals(tResult.ToolCallsRendered.%Get(0).%Get("name"), "FindSession", "ToolCallsRendered[0].name preserved")
    Do $$$AssertEquals(tResult.ToolCallsRendered.%Get(0).%Get("status"), "ok", "ToolCallsRendered[0].status preserved")
    Quit
}

/// <p>AC-4 #4 — instantiate <CLASS>TurnResult</CLASS>, set all 4
/// properties, call <method>ToJson</method>, parse the result via
/// <code>%FromJSON</code>, assert the four documented top-level keys
/// are present (<code>assistantMarkdown</code>,
/// <code>usageRollup</code>, <code>durationMs</code>,
/// <code>toolCallsRendered</code>) and carry the expected values.</p>
Method TestTurnResultToJsonProducesExpectedKeys()
{
    Set tResult = ##class(SessionAgent.Agent.TurnResult).%New()
    Set tResult.AssistantMarkdown = "answer text"

    Set tUsage = ##class(%DynamicObject).%New()
    Set tUsage."input_tokens" = 10
    Set tUsage."output_tokens" = 5
    Set tResult.UsageRollup = tUsage

    Set tResult.DurationMs = 1500

    Set tCalls = ##class(%DynamicArray).%New()
    Do tCalls.%Push({"name": "T1", "args": {}, "result": {}, "status": "ok"})
    Set tResult.ToolCallsRendered = tCalls

    Set tJson = tResult.ToJson()
    Set tParsed = {}.%FromJSON(tJson)

    Do $$$AssertTrue(tParsed.%IsDefined("assistantMarkdown"), "JSON has assistantMarkdown key")
    Do $$$AssertTrue(tParsed.%IsDefined("usageRollup"), "JSON has usageRollup key")
    Do $$$AssertTrue(tParsed.%IsDefined("durationMs"), "JSON has durationMs key")
    Do $$$AssertTrue(tParsed.%IsDefined("toolCallsRendered"), "JSON has toolCallsRendered key")

    Do $$$AssertEquals(tParsed.assistantMarkdown, "answer text", "JSON.assistantMarkdown value preserved")
    Do $$$AssertEquals(tParsed.usageRollup."input_tokens", 10, "JSON.usageRollup.input_tokens preserved")
    Do $$$AssertEquals(tParsed.usageRollup."output_tokens", 5, "JSON.usageRollup.output_tokens preserved")
    Do $$$AssertEquals(tParsed.durationMs, 1500, "JSON.durationMs preserved")
    Do $$$AssertEquals(tParsed.toolCallsRendered.%Size(), 1, "JSON.toolCallsRendered has 1 entry")
    Do $$$AssertEquals(tParsed.toolCallsRendered.%Get(0).%Get("name"), "T1", "JSON.toolCallsRendered[0].name preserved")
    Quit
}

/// <p>AC-4 #5 — instantiate <CLASS>TurnResult</CLASS> with
/// <property>ToolCallsRendered</property> = empty
/// <CLASS>%DynamicArray</CLASS> AND <property>UsageRollup</property> =
/// empty <CLASS>%DynamicObject</CLASS>; call <method>ToJson</method>;
/// assert the resulting JSON contains <code>"toolCallsRendered":[]</code>
/// AND <code>"usageRollup":{}</code> (literal empty values — not
/// <code>null</code>, not absent). Both AC-3 defensive defaults are
/// covered.</p>
Method TestTurnResultToJsonHandlesEmptyArrays()
{
    Set tResult = ##class(SessionAgent.Agent.TurnResult).%New()
    Set tResult.AssistantMarkdown = ""
    Set tResult.UsageRollup = ##class(%DynamicObject).%New()
    Set tResult.DurationMs = 0
    Set tResult.ToolCallsRendered = ##class(%DynamicArray).%New()

    Set tJson = tResult.ToJson()
    Do $$$AssertTrue(tJson [ """toolCallsRendered"":[]", "JSON contains literal empty array for toolCallsRendered (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ """toolCallsRendered"":null"), "JSON does NOT contain null for toolCallsRendered (got: " _ tJson _ ")")
    Do $$$AssertTrue(tJson [ """usageRollup"":{}", "JSON contains literal empty object for usageRollup (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ """usageRollup"":null"), "JSON does NOT contain null for usageRollup (got: " _ tJson _ ")")
    Quit
}

/// <p>AC-3 defensive-default guard — exercises the
/// <method>ToJson</method> Else branches by leaving
/// <property>UsageRollup</property> and
/// <property>ToolCallsRendered</property> truly unset (never
/// assigned). The defensive fallback in <method>ToJson</method> must
/// substitute fresh empty <CLASS>%DynamicObject</CLASS> /
/// <CLASS>%DynamicArray</CLASS> instances so the browser-bound JSON
/// shape is stable. Without this test, the Else branches in
/// <method>ToJson</method> are dead code under coverage.</p>
Method TestTurnResultToJsonHandlesUnsetDynamicProps()
{
    Set tResult = ##class(SessionAgent.Agent.TurnResult).%New()
    Set tResult.AssistantMarkdown = "answer"
    Set tResult.DurationMs = 100
    ; Deliberately do NOT set UsageRollup or ToolCallsRendered.

    Set tJson = tResult.ToJson()
    Do $$$AssertTrue(tJson [ """usageRollup"":{}", "Unset UsageRollup defaults to {} (got: " _ tJson _ ")")
    Do $$$AssertTrue(tJson [ """toolCallsRendered"":[]", "Unset ToolCallsRendered defaults to [] (got: " _ tJson _ ")")
    Do $$$AssertTrue('(tJson [ """usageRollup"":null"), "Unset UsageRollup is not null")
    Do $$$AssertTrue('(tJson [ """toolCallsRendered"":null"), "Unset ToolCallsRendered is not null")
    Quit
}

/// <p>AC-4 #6 — sanity assertion that the three DTOs are pure data
/// per AC-5. Enumerates user-defined methods on each class via
/// <CLASS>%Dictionary.MethodDefinition</CLASS>; asserts that
/// <CLASS>CallerContext</CLASS> and <CLASS>ProviderResponse</CLASS>
/// have ZERO user-defined methods, and <CLASS>TurnResult</CLASS> has
/// exactly ONE (<method>ToJson</method>). Property accessors and
/// inherited <CLASS>%RegisteredObject</CLASS> system methods are
/// excluded automatically — <CLASS>%Dictionary.MethodDefinition</CLASS>
/// only enumerates methods defined on the class itself.</p>
Method TestNoBusinessLogic()
{
    Do $$$AssertEquals(..CountUserMethods("SessionAgent.Agent.CallerContext"), 0, "CallerContext has no user-defined methods")
    Do $$$AssertEquals(..CountUserMethods("SessionAgent.Agent.ProviderResponse"), 0, "ProviderResponse has no user-defined methods")
    Set tTurnMethods = ..ListUserMethods("SessionAgent.Agent.TurnResult")
    Do $$$AssertEquals($ListLength(tTurnMethods), 1, "TurnResult has exactly 1 user-defined method (got: " _ ..JoinList(tTurnMethods) _ ")")
    Do $$$AssertEquals($ListGet(tTurnMethods, 1), "ToJson", "TurnResult's only user-defined method is ToJson")
    Quit
}

/// <p>Helper — count user-defined methods on the named class via
/// <CLASS>%Dictionary.MethodDefinition</CLASS>'s
/// <method>IDKEYOpen</method>. Returns the size of the result.</p>
ClassMethod CountUserMethods(pClassName As %String) As %Integer [ Internal ]
{
    Quit $ListLength(..ListUserMethods(pClassName))
}

/// <p>Helper — list user-defined method names on the named class as
/// a <code>$ListBuild</code> list. Iterates
/// <CLASS>%Dictionary.MethodDefinition</CLASS>'s
/// <code>Summary</code> query for the class. Throws if
/// <var>pClassName</var> does not exist as a compiled class — without
/// this guard a typo would silently report 0 user methods (fake-green
/// for <method>TestNoBusinessLogic</method>).</p>
ClassMethod ListUserMethods(pClassName As %String) As %List [ Internal ]
{
    If '##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
        Throw ##class(%Exception.General).%New("ListUserMethods",,,"class does not exist: " _ pClassName)
    }
    Set tList = ""
    Set tRS = ##class(%ResultSet).%New("%Dictionary.MethodDefinition:Summary")
    Do tRS.Execute(pClassName)
    While tRS.Next() {
        Set tName = tRS.Get("Name")
        ; Skip property accessors (Name has $$$ in it for generated
        ; methods; but the Summary query already filters those — no
        ; explicit skip needed).
        Set tList = tList _ $ListBuild(tName)
    }
    Do tRS.%Close()
    Quit tList
}

/// <p>Helper — join a <code>$ListBuild</code> list into a
/// comma-separated string for assertion-failure messages.</p>
ClassMethod JoinList(pList As %List) As %String [ Internal ]
{
    Set tOut = ""
    Set tPtr = 0
    While $ListNext(pList, tPtr, tElem) {
        Set tOut = tOut _ $Select(tOut="": "", 1: ", ") _ tElem
    }
    Quit tOut
}

}
