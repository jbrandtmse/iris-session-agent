/// <p>Unit tests for <CLASS>SessionAgent.LLM.Util.MessageAdapter</CLASS>
/// (Story 2.8). Locks the canonical↔provider message-history translation
/// contract for the four LLM providers shipped in v1
/// (anthropic / openai / gemini / openai-compatible).</p>
///
/// <p><b>AC-4 method coverage:</b></p>
/// <ol>
/// <li><b>TestCanonicalAnthropicPassthrough</b> — anthropic provider name
/// returns the input unchanged for canonical→provider direction.</li>
/// <li><b>TestCanonicalToOpenAiToolUseStringifiesArgs</b> — assistant
/// tool_use block with object input produces OpenAI tool_calls with
/// <code>arguments</code> as a STRING (not object).</li>
/// <li><b>TestCanonicalToGeminiRoleMapping</b> — assistant role maps to
/// model; tool role maps to user with functionResponse parts.</li>
/// <li><b>TestRoundTripOpenAi</b> — canonical → OpenAI provider shape →
/// OpenAI response shape → canonical, preserves tool_use semantics
/// (args parse back to object).</li>
/// <li><b>TestRoundTripAnthropic</b> — passthrough both ways.</li>
/// <li><b>TestRoundTripGemini</b> — text + functionCall round-trip
/// preserves semantics.</li>
/// <li><b>TestProviderToCanonicalOpenAiUsageMapping</b> — OpenAI
/// <code>usage.prompt_tokens</code> maps to canonical
/// <code>input_tokens</code>; <code>completion_tokens</code> maps to
/// <code>output_tokens</code>.</li>
/// </ol>
Class SessionAgent.Test.MessageAdapterTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accept the <code>initvalue</code> parameter the
/// parent <CLASS>%UnitTest.TestCase</CLASS> expects, call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-4 #1 — anthropic provider name returns input unchanged for
/// <method>CanonicalToProvider</method>. Build a canonical history with
/// text + tool_use + tool_result; assert the output array reference is
/// the input (passthrough).</p>
Method TestCanonicalAnthropicPassthrough()
{
    Set tCanon = ..BuildMixedCanonicalHistory()
    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("anthropic", tCanon)
    ; Passthrough — same instance.
    Do $$$AssertEquals(tOut.%Size(), tCanon.%Size(), "Anthropic passthrough preserves array size")
    ; Spot-check structure.
    Do $$$AssertEquals(tOut.%Get(0).%Get("role"), "user", "Anthropic passthrough preserves role")
    Do $$$AssertEquals(tOut.%Get(1).%Get("content").%Get(0).%Get("type"), "text", "Anthropic passthrough preserves block type")
    Do $$$AssertEquals(tOut.%Get(1).%Get("content").%Get(1).%Get("type"), "tool_use", "Anthropic passthrough preserves tool_use block")
    Quit
}

/// <p>AC-4 #2 — assistant message with tool_use block (object input)
/// produces OpenAI assistant message with
/// <code>tool_calls[0].function.arguments</code> as a STRING (not
/// object). This is the most-likely adapter bug source.</p>
Method TestCanonicalToOpenAiToolUseStringifiesArgs()
{
    Set tCanon = ##class(%DynamicArray).%New()

    ; Assistant turn with one tool_use block carrying an object input.
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Set tContent = ##class(%DynamicArray).%New()
    Set tToolUse = ##class(%DynamicObject).%New()
    Do tToolUse.%Set("type", "tool_use")
    Do tToolUse.%Set("id", "call_42")
    Do tToolUse.%Set("name", "FindSession")
    Set tInput = ##class(%DynamicObject).%New()
    Do tInput.%Set("session_id", "12345")
    Do tInput.%Set("limit", 5)
    Do tToolUse.%Set("input", tInput)
    Do tContent.%Push(tToolUse)
    Do tMsg.%Set("content", tContent)
    Do tCanon.%Push(tMsg)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tCanon)

    Do $$$AssertEquals(tOut.%Size(), 1, "OpenAI output has 1 assistant message")
    Set tOaMsg = tOut.%Get(0)
    Do $$$AssertEquals(tOaMsg.%Get("role"), "assistant", "OpenAI message role is assistant")
    Do $$$AssertTrue(tOaMsg.%IsDefined("tool_calls"), "OpenAI message has tool_calls field")
    Set tCalls = tOaMsg.%Get("tool_calls")
    Do $$$AssertEquals(tCalls.%Size(), 1, "OpenAI tool_calls has 1 entry")
    Set tCall = tCalls.%Get(0)
    Do $$$AssertEquals(tCall.%Get("id"), "call_42", "tool_call.id preserved")
    Do $$$AssertEquals(tCall.%Get("type"), "function", "tool_call.type = function")
    Set tFn = tCall.%Get("function")
    Do $$$AssertEquals(tFn.%Get("name"), "FindSession", "function.name preserved")

    ; The critical assertion — arguments is a string, not an object.
    Set tArgs = tFn.%Get("arguments")
    Do $$$AssertTrue('$IsObject(tArgs), "function.arguments is a STRING, not an object (got isObject=" _ $IsObject(tArgs) _ ")")
    ; And it parses back to the original input object.
    Set tParsed = ##class(%DynamicObject).%FromJSON(tArgs)
    Do $$$AssertEquals(tParsed.%Get("session_id"), "12345", "arguments string parses back: session_id preserved")
    Do $$$AssertEquals(+tParsed.%Get("limit"), 5, "arguments string parses back: limit preserved")
    Quit
}

/// <p>AC-4 #3 — assistant role maps to <code>model</code>; tool role
/// with tool_result maps to <code>user</code> with
/// <code>functionResponse</code> parts.</p>
Method TestCanonicalToGeminiRoleMapping()
{
    Set tCanon = ##class(%DynamicArray).%New()

    ; Assistant message with text.
    Set tA = ##class(%DynamicObject).%New()
    Do tA.%Set("role", "assistant")
    Set tAContent = ##class(%DynamicArray).%New()
    Set tAtext = ##class(%DynamicObject).%New()
    Do tAtext.%Set("type", "text")
    Do tAtext.%Set("text", "I will look that up")
    Do tAContent.%Push(tAtext)
    Do tA.%Set("content", tAContent)
    Do tCanon.%Push(tA)

    ; Tool message with tool_result.
    Set tT = ##class(%DynamicObject).%New()
    Do tT.%Set("role", "tool")
    Set tTContent = ##class(%DynamicArray).%New()
    Set tTRes = ##class(%DynamicObject).%New()
    Do tTRes.%Set("type", "tool_result")
    Do tTRes.%Set("tool_use_id", "call_99")
    Do tTRes.%Set("content", "session 12345 found")
    Do tTContent.%Push(tTRes)
    Do tT.%Set("content", tTContent)
    Do tCanon.%Push(tT)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("gemini", tCanon)

    Do $$$AssertEquals(tOut.%Size(), 2, "Gemini output has 2 messages")
    Do $$$AssertEquals(tOut.%Get(0).%Get("role"), "model", "assistant role maps to model")
    Do $$$AssertEquals(tOut.%Get(1).%Get("role"), "user", "tool role maps to user")

    ; Assistant message: text part.
    Set tAParts = tOut.%Get(0).%Get("parts")
    Do $$$AssertEquals(tAParts.%Size(), 1, "assistant has 1 part")
    Do $$$AssertEquals(tAParts.%Get(0).%Get("text"), "I will look that up", "assistant text part preserved")

    ; Tool message: functionResponse part.
    Set tTParts = tOut.%Get(1).%Get("parts")
    Do $$$AssertEquals(tTParts.%Size(), 1, "tool message has 1 part")
    Set tFr = tTParts.%Get(0)
    Do $$$AssertTrue(tFr.%IsDefined("functionResponse"), "tool part has functionResponse field")
    Do $$$AssertEquals(tFr.%Get("functionResponse").%Get("name"), "call_99", "functionResponse.name carries tool_use_id (v1 convention)")
    Quit
}

/// <p>AC-4 #4 — round-trip canonical → OpenAI provider shape → OpenAI
/// response shape → canonical preserves tool_use semantics. Forward
/// direction stringifies args; reverse parses them back.</p>
Method TestRoundTripOpenAi()
{
    ; Build a canonical assistant turn with text + tool_use.
    Set tOriginal = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Set tContent = ##class(%DynamicArray).%New()
    Set tText = ##class(%DynamicObject).%New()
    Do tText.%Set("type", "text")
    Do tText.%Set("text", "checking sessions")
    Do tContent.%Push(tText)
    Set tToolUse = ##class(%DynamicObject).%New()
    Do tToolUse.%Set("type", "tool_use")
    Do tToolUse.%Set("id", "call_abc")
    Do tToolUse.%Set("name", "FindSession")
    Set tInput = ##class(%DynamicObject).%New()
    Do tInput.%Set("query", "abc")
    Do tToolUse.%Set("input", tInput)
    Do tContent.%Push(tToolUse)
    Do tMsg.%Set("content", tContent)
    Do tOriginal.%Push(tMsg)

    ; Forward — canonical to OpenAI shape.
    Set tOaShape = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tOriginal)

    ; Synthesize an OpenAI-shaped response containing the same tool_call
    ; (mirrors what the provider would echo back as its assistant turn).
    Set tOaRespMsg = tOaShape.%Get(0)
    Set tOaRawResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Do tChoice.%Set("finish_reason", "tool_calls")
    Do tChoice.%Set("message", tOaRespMsg)
    Do tChoices.%Push(tChoice)
    Do tOaRawResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 100)
    Do tUsage.%Set("completion_tokens", 25)
    Do tOaRawResp.%Set("usage", tUsage)

    ; Reverse — OpenAI raw response to canonical.
    Set tBack = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical("openai", tOaRawResp)

    Do $$$AssertEquals(tBack.%Get("role"), "assistant", "Round-trip: role = assistant")
    Do $$$AssertEquals(tBack.%Get("stopReason"), "tool_use", "Round-trip: stopReason mapped tool_calls→tool_use")
    Set tBackContent = tBack.%Get("content")
    Do $$$AssertEquals(tBackContent.%Size(), 2, "Round-trip: 2 content blocks (text + tool_use)")
    Do $$$AssertEquals(tBackContent.%Get(0).%Get("type"), "text", "Round-trip: block 0 is text")
    Do $$$AssertEquals(tBackContent.%Get(0).%Get("text"), "checking sessions", "Round-trip: text preserved")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("type"), "tool_use", "Round-trip: block 1 is tool_use")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("id"), "call_abc", "Round-trip: tool_use.id preserved")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("name"), "FindSession", "Round-trip: tool_use.name preserved")
    ; The critical: input is back to an OBJECT, not a string.
    Set tBackInput = tBackContent.%Get(1).%Get("input")
    Do $$$AssertTrue($IsObject(tBackInput), "Round-trip: tool_use.input is OBJECT (parsed back from string)")
    Do $$$AssertEquals(tBackInput.%Get("query"), "abc", "Round-trip: tool_use.input.query preserved")
    Quit
}

/// <p>AC-4 #5 — anthropic round-trip is double passthrough.</p>
Method TestRoundTripAnthropic()
{
    Set tCanon = ..BuildMixedCanonicalHistory()
    Set tForward = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("anthropic", tCanon)

    ; For ProviderToCanonical, build an Anthropic-shaped raw response.
    Set tRaw = ##class(%DynamicObject).%New()
    Do tRaw.%Set("role", "assistant")
    Set tRawContent = ##class(%DynamicArray).%New()
    Set tBlk = ##class(%DynamicObject).%New()
    Do tBlk.%Set("type", "text")
    Do tBlk.%Set("text", "anthropic answer")
    Do tRawContent.%Push(tBlk)
    Do tRaw.%Set("content", tRawContent)
    Do tRaw.%Set("stopReason", "end_turn")
    Set tBack = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical("anthropic", tRaw)

    Do $$$AssertEquals(tForward.%Size(), tCanon.%Size(), "Anthropic forward passthrough preserves size")
    Do $$$AssertEquals(tBack.%Get("role"), "assistant", "Anthropic reverse passthrough preserves role")
    Do $$$AssertEquals(tBack.%Get("content").%Get(0).%Get("text"), "anthropic answer", "Anthropic reverse preserves content")
    Do $$$AssertEquals(tBack.%Get("stopReason"), "end_turn", "Anthropic reverse preserves stopReason")
    Quit
}

/// <p>AC-4 #6 — Gemini round-trip preserves text + functionCall semantics
/// across canonical ↔ Gemini.</p>
Method TestRoundTripGemini()
{
    ; Build a canonical assistant turn: text + tool_use.
    Set tCanon = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Set tContent = ##class(%DynamicArray).%New()
    Set tText = ##class(%DynamicObject).%New()
    Do tText.%Set("type", "text")
    Do tText.%Set("text", "let me search")
    Do tContent.%Push(tText)
    Set tTu = ##class(%DynamicObject).%New()
    Do tTu.%Set("type", "tool_use")
    Do tTu.%Set("id", "call_g1")
    Do tTu.%Set("name", "Search")
    Set tInput = ##class(%DynamicObject).%New()
    Do tInput.%Set("q", "hello")
    Do tTu.%Set("input", tInput)
    Do tContent.%Push(tTu)
    Do tMsg.%Set("content", tContent)
    Do tCanon.%Push(tMsg)

    ; Forward — canonical to Gemini shape.
    Set tGemShape = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("gemini", tCanon)
    Do $$$AssertEquals(tGemShape.%Size(), 1, "Gemini forward: 1 message")
    Set tGmsg = tGemShape.%Get(0)
    Do $$$AssertEquals(tGmsg.%Get("role"), "model", "Gemini forward: assistant→model")
    Set tParts = tGmsg.%Get("parts")
    Do $$$AssertEquals(tParts.%Size(), 2, "Gemini forward: 2 parts (text + functionCall)")
    Do $$$AssertEquals(tParts.%Get(0).%Get("text"), "let me search", "Gemini forward: text part preserved")
    Set tFc = tParts.%Get(1).%Get("functionCall")
    Do $$$AssertEquals(tFc.%Get("name"), "Search", "Gemini forward: functionCall.name preserved")
    Do $$$AssertEquals(tFc.%Get("args").%Get("q"), "hello", "Gemini forward: functionCall.args preserved")

    ; Synthesize a Gemini-shaped raw response (assistant turn echoing same shape).
    Set tRaw = ##class(%DynamicObject).%New()
    Set tCands = ##class(%DynamicArray).%New()
    Set tCand = ##class(%DynamicObject).%New()
    Do tCand.%Set("finishReason", "TOOL_CALLS")
    Set tCandContent = ##class(%DynamicObject).%New()
    Do tCandContent.%Set("parts", tParts)
    Do tCand.%Set("content", tCandContent)
    Do tCands.%Push(tCand)
    Do tRaw.%Set("candidates", tCands)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("promptTokenCount", 50)
    Do tUsage.%Set("candidatesTokenCount", 12)
    Do tRaw.%Set("usageMetadata", tUsage)

    ; Reverse — Gemini raw response to canonical.
    Set tBack = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical("gemini", tRaw)
    Do $$$AssertEquals(tBack.%Get("role"), "assistant", "Gemini reverse: role = assistant")
    Do $$$AssertEquals(tBack.%Get("stopReason"), "tool_use", "Gemini reverse: stopReason mapped TOOL_CALLS→tool_use")
    Set tBackContent = tBack.%Get("content")
    Do $$$AssertEquals(tBackContent.%Size(), 2, "Gemini reverse: 2 content blocks")
    Do $$$AssertEquals(tBackContent.%Get(0).%Get("type"), "text", "Gemini reverse: block 0 is text")
    Do $$$AssertEquals(tBackContent.%Get(0).%Get("text"), "let me search", "Gemini reverse: text preserved")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("type"), "tool_use", "Gemini reverse: block 1 is tool_use")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("name"), "Search", "Gemini reverse: tool_use.name preserved")
    Do $$$AssertEquals(tBackContent.%Get(1).%Get("input").%Get("q"), "hello", "Gemini reverse: tool_use.input.q preserved")
    Do $$$AssertEquals(+tBack.%Get("usage").%Get("input_tokens"), 50, "Gemini reverse: input_tokens = promptTokenCount")
    Do $$$AssertEquals(+tBack.%Get("usage").%Get("output_tokens"), 12, "Gemini reverse: output_tokens = candidatesTokenCount")
    Quit
}

/// <p>AC-4 #7 — OpenAI <code>usage.prompt_tokens</code> maps to canonical
/// <code>input_tokens</code>; <code>completion_tokens</code> maps to
/// <code>output_tokens</code>.</p>
Method TestProviderToCanonicalOpenAiUsageMapping()
{
    ; Minimal OpenAI raw response with usage block.
    Set tRaw = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Do tChoice.%Set("finish_reason", "stop")
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Do tMsg.%Set("content", "ok")
    Do tChoice.%Set("message", tMsg)
    Do tChoices.%Push(tChoice)
    Do tRaw.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 250)
    Do tUsage.%Set("completion_tokens", 75)
    Do tRaw.%Set("usage", tUsage)

    Set tCanon = ##class(SessionAgent.LLM.Util.MessageAdapter).ProviderToCanonical("openai", tRaw)

    Do $$$AssertEquals(tCanon.%Get("stopReason"), "end_turn", "stop → end_turn")
    Set tCanonUsage = tCanon.%Get("usage")
    Do $$$AssertEquals(+tCanonUsage.%Get("input_tokens"), 250, "input_tokens = prompt_tokens")
    Do $$$AssertEquals(+tCanonUsage.%Get("output_tokens"), 75, "output_tokens = completion_tokens")
    Do $$$AssertEquals(+tCanonUsage.%Get("cache_creation_input_tokens"), 0, "cache_creation_input_tokens = 0 (default)")
    Do $$$AssertEquals(+tCanonUsage.%Get("cache_read_input_tokens"), 0, "cache_read_input_tokens = 0 (default)")
    Quit
}

/// <p>Regression for the Story 3.0 carry-forward bug: canonical
/// Anthropic packs <code>tool_result</code> blocks inside
/// <code>role:"user"</code> messages. The original Story 2.8 adapter
/// only handled <code>role:"tool"</code>, so OpenAI got an orphaned
/// <code>tool_calls</code> on turn 2 and rejected with HTTP 400.
/// This test feeds a user-role message with a single tool_result
/// block and asserts the OpenAI output has exactly one
/// <code>{role:"tool", tool_call_id, content}</code> message — and
/// no empty user message.</p>
Method TestCanonicalUserToolResultBecomesOpenAiToolMessage()
{
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "tool_result")
    Do tBlock.%Set("tool_use_id", "call_abc")
    Do tBlock.%Set("content", "found 5 messages")
    Do tContent.%Push(tBlock)
    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tHistory)
    Do $$$AssertEquals(tOut.%Size(), 1, "Exactly one OpenAI message emitted (the tool message); empty user message suppressed")
    Set tOaMsg = tOut.%Get(0)
    Do $$$AssertEquals(tOaMsg.%Get("role"), "tool", "role is 'tool'")
    Do $$$AssertEquals(tOaMsg.%Get("tool_call_id"), "call_abc", "tool_call_id propagated from canonical tool_use_id")
    Do $$$AssertEquals(tOaMsg.%Get("content"), "found 5 messages", "tool_result content preserved")
    Quit
}

/// <p>User-role canonical message with BOTH tool_result and text
/// blocks (mixed shape — rare but legal in canonical Anthropic). Adapter
/// must emit the tool message FIRST, then a separate user message
/// carrying the text. Order matters for OpenAI conversation flow.</p>
Method TestCanonicalUserMixedTextAndToolResult()
{
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()
    Set tToolBlk = ##class(%DynamicObject).%New()
    Do tToolBlk.%Set("type", "tool_result")
    Do tToolBlk.%Set("tool_use_id", "call_x")
    Do tToolBlk.%Set("content", "first result")
    Do tContent.%Push(tToolBlk)
    Set tTextBlk = ##class(%DynamicObject).%New()
    Do tTextBlk.%Set("type", "text")
    Do tTextBlk.%Set("text", "and another question")
    Do tContent.%Push(tTextBlk)
    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tHistory)
    Do $$$AssertEquals(tOut.%Size(), 2, "Two OpenAI messages: one tool, one user")
    Do $$$AssertEquals(tOut.%Get(0).%Get("role"), "tool", "Index 0 is tool message")
    Do $$$AssertEquals(tOut.%Get(0).%Get("tool_call_id"), "call_x", "tool_call_id correct")
    Do $$$AssertEquals(tOut.%Get(1).%Get("role"), "user", "Index 1 is user message")
    Do $$$AssertEquals(tOut.%Get(1).%Get("content"), "and another question", "user text preserved")
    Quit
}

/// <p>Full 4-turn multi-turn tool flow round-trip: user → assistant
/// tool_use → user tool_result → assistant final answer. Asserts the
/// OpenAI translation preserves the conversation structure end-to-end:
/// every assistant tool_calls.id has a matching subsequent
/// tool.tool_call_id (this is exactly the invariant OpenAI's HTTP 400
/// validates server-side).</p>
Method TestCanonicalToOpenAiMultiTurnToolFlowPreservesIdLinkage()
{
    Set tHistory = ##class(%DynamicArray).%New()

    ; Turn 1: user
    Set tU = ##class(%DynamicObject).%New()
    Do tU.%Set("role", "user")
    Set tUC = ##class(%DynamicArray).%New()
    Set tUT = ##class(%DynamicObject).%New()
    Do tUT.%Set("type", "text")
    Do tUT.%Set("text", "summarize session 42")
    Do tUC.%Push(tUT)
    Do tU.%Set("content", tUC)
    Do tHistory.%Push(tU)

    ; Turn 2: assistant tool_use
    Set tA1 = ##class(%DynamicObject).%New()
    Do tA1.%Set("role", "assistant")
    Set tA1C = ##class(%DynamicArray).%New()
    Set tA1Tu = ##class(%DynamicObject).%New()
    Do tA1Tu.%Set("type", "tool_use")
    Do tA1Tu.%Set("id", "call_zzz")
    Do tA1Tu.%Set("name", "session_summary")
    Set tA1Args = ##class(%DynamicObject).%New()
    Do tA1Args.%Set("session_id", "42")
    Do tA1Tu.%Set("input", tA1Args)
    Do tA1C.%Push(tA1Tu)
    Do tA1.%Set("content", tA1C)
    Do tHistory.%Push(tA1)

    ; Turn 3: user tool_result (canonical Anthropic shape)
    Set tTr = ##class(%DynamicObject).%New()
    Do tTr.%Set("role", "user")
    Set tTrC = ##class(%DynamicArray).%New()
    Set tTrBlk = ##class(%DynamicObject).%New()
    Do tTrBlk.%Set("type", "tool_result")
    Do tTrBlk.%Set("tool_use_id", "call_zzz")
    Do tTrBlk.%Set("content", "5 messages, 0 errors")
    Do tTrC.%Push(tTrBlk)
    Do tTr.%Set("content", tTrC)
    Do tHistory.%Push(tTr)

    ; Turn 4: assistant final text
    Set tA2 = ##class(%DynamicObject).%New()
    Do tA2.%Set("role", "assistant")
    Set tA2C = ##class(%DynamicArray).%New()
    Set tA2T = ##class(%DynamicObject).%New()
    Do tA2T.%Set("type", "text")
    Do tA2T.%Set("text", "Session 42 had 5 messages with no errors.")
    Do tA2C.%Push(tA2T)
    Do tA2.%Set("content", tA2C)
    Do tHistory.%Push(tA2)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tHistory)
    Do $$$AssertEquals(tOut.%Size(), 4, "Four OpenAI messages: user, assistant(tool_calls), tool, assistant(text)")

    ; Index 1: assistant message with tool_calls[0].id = call_zzz
    Set tOaA1 = tOut.%Get(1)
    Do $$$AssertEquals(tOaA1.%Get("role"), "assistant", "Index 1 role assistant")
    Set tCalls = tOaA1.%Get("tool_calls")
    Do $$$AssertTrue($IsObject(tCalls), "Index 1 has tool_calls array")
    Do $$$AssertEquals(tCalls.%Get(0).%Get("id"), "call_zzz", "tool_calls[0].id = call_zzz")

    ; Index 2: tool message with tool_call_id = call_zzz (THE INVARIANT)
    Set tOaTool = tOut.%Get(2)
    Do $$$AssertEquals(tOaTool.%Get("role"), "tool", "Index 2 role tool")
    Do $$$AssertEquals(tOaTool.%Get("tool_call_id"), "call_zzz", "tool.tool_call_id MATCHES assistant.tool_calls[0].id (the invariant OpenAI HTTP 400 validates)")
    Do $$$AssertEquals(tOaTool.%Get("content"), "5 messages, 0 errors", "tool message content preserved")
    Quit
}

/// <p>Story 5.0 AC-6 — verify the OpenAI tool_result fan-out path
/// emits one OpenAI <code>{role:"tool"}</code> message per tool_result
/// block when a single canonical user-role message carries TWO
/// tool_result blocks. Mixed content shapes: one block has plain
/// string content, the other has array-of-text-blocks content (which
/// the adapter must stringify to JSON via <code>%ToJSON</code>).
/// This was the deferred test gap from Story 2.8 review (named
/// successor: Story 2.9; silently dropped; surfaced in Epic 4 retro
/// continued-deferrals; verified empirically here).</p>
Method TestCanonicalUserTwoToolResultBlocksFanOutToTwoOpenAiToolMessages()
{
    Set tHistory = ##class(%DynamicArray).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "user")
    Set tContent = ##class(%DynamicArray).%New()

    ; Block 1 — tool_result with plain string content.
    Set tBlk1 = ##class(%DynamicObject).%New()
    Do tBlk1.%Set("type", "tool_result")
    Do tBlk1.%Set("tool_use_id", "call_alpha")
    Do tBlk1.%Set("content", "session 42 has 5 messages")
    Do tContent.%Push(tBlk1)

    ; Block 2 — tool_result with array-of-text-blocks content
    ; (canonical Anthropic permits both shapes). Adapter must stringify
    ; the array via %ToJSON.
    Set tBlk2 = ##class(%DynamicObject).%New()
    Do tBlk2.%Set("type", "tool_result")
    Do tBlk2.%Set("tool_use_id", "call_beta")
    Set tBlk2Content = ##class(%DynamicArray).%New()
    Set tTextBlk = ##class(%DynamicObject).%New()
    Do tTextBlk.%Set("type", "text")
    Do tTextBlk.%Set("text", "second tool returned 12 rows")
    Do tBlk2Content.%Push(tTextBlk)
    Do tBlk2.%Set("content", tBlk2Content)
    Do tContent.%Push(tBlk2)

    Do tMsg.%Set("content", tContent)
    Do tHistory.%Push(tMsg)

    Set tOut = ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToProvider("openai", tHistory)

    ; FAN-OUT INVARIANT: TWO tool_result blocks → TWO OpenAI tool messages.
    Do $$$AssertEquals(tOut.%Size(), 2, "Two OpenAI messages emitted (fan-out: one per tool_result block; empty user message suppressed)")

    ; First message — string content path.
    Set tOaMsg1 = tOut.%Get(0)
    Do $$$AssertEquals(tOaMsg1.%Get("role"), "tool", "Index 0 role='tool' (first fan-out)")
    Do $$$AssertEquals(tOaMsg1.%Get("tool_call_id"), "call_alpha", "Index 0 tool_call_id='call_alpha' (string-content block's tool_use_id)")
    Do $$$AssertEquals(tOaMsg1.%Get("content"), "session 42 has 5 messages", "Index 0 content preserved verbatim from string tool_result")

    ; Second message — array-of-text-blocks content path; stringified to JSON.
    Set tOaMsg2 = tOut.%Get(1)
    Do $$$AssertEquals(tOaMsg2.%Get("role"), "tool", "Index 1 role='tool' (second fan-out)")
    Do $$$AssertEquals(tOaMsg2.%Get("tool_call_id"), "call_beta", "Index 1 tool_call_id='call_beta' (array-content block's tool_use_id)")
    ; Content for the array form is %ToJSON of the array — assert it's a
    ; string (not an object) and contains the expected text.
    Set tContent2 = tOaMsg2.%Get("content")
    Do $$$AssertTrue('$IsObject(tContent2), "Index 1 content is a STRING (array-of-text-blocks stringified via %ToJSON), got isObject=" _ $IsObject(tContent2))
    Do $$$AssertTrue(tContent2 [ "second tool returned 12 rows", "Index 1 stringified content includes the inner text payload")
    Do $$$AssertTrue(tContent2 [ """type"":""text""", "Index 1 stringified content preserves the array-of-text-blocks JSON shape")
    Quit
}

/// <p>Internal helper — build a 3-message canonical history with mixed
/// block types: <code>user</code> with text, <code>assistant</code> with
/// text + tool_use, <code>tool</code> with tool_result.</p>
ClassMethod BuildMixedCanonicalHistory() As %DynamicArray [ Internal ]
{
    Set tHistory = ##class(%DynamicArray).%New()

    ; user
    Set tU = ##class(%DynamicObject).%New()
    Do tU.%Set("role", "user")
    Set tUC = ##class(%DynamicArray).%New()
    Set tUText = ##class(%DynamicObject).%New()
    Do tUText.%Set("type", "text")
    Do tUText.%Set("text", "find a session")
    Do tUC.%Push(tUText)
    Do tU.%Set("content", tUC)
    Do tHistory.%Push(tU)

    ; assistant text + tool_use
    Set tA = ##class(%DynamicObject).%New()
    Do tA.%Set("role", "assistant")
    Set tAC = ##class(%DynamicArray).%New()
    Set tAText = ##class(%DynamicObject).%New()
    Do tAText.%Set("type", "text")
    Do tAText.%Set("text", "ok one moment")
    Do tAC.%Push(tAText)
    Set tATu = ##class(%DynamicObject).%New()
    Do tATu.%Set("type", "tool_use")
    Do tATu.%Set("id", "call_x")
    Do tATu.%Set("name", "FindSession")
    Set tATuInput = ##class(%DynamicObject).%New()
    Do tATuInput.%Set("q", "alpha")
    Do tATu.%Set("input", tATuInput)
    Do tAC.%Push(tATu)
    Do tA.%Set("content", tAC)
    Do tHistory.%Push(tA)

    ; tool tool_result
    Set tT = ##class(%DynamicObject).%New()
    Do tT.%Set("role", "tool")
    Set tTC = ##class(%DynamicArray).%New()
    Set tTRes = ##class(%DynamicObject).%New()
    Do tTRes.%Set("type", "tool_result")
    Do tTRes.%Set("tool_use_id", "call_x")
    Do tTRes.%Set("content", "found 1 session")
    Do tTC.%Push(tTRes)
    Do tT.%Set("content", tTC)
    Do tHistory.%Push(tT)

    Quit tHistory
}

}
