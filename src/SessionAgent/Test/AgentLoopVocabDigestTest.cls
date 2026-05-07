/// <p>Story 9.4 — verifies the search-agent first-user-message vocabulary
/// digest injection wiring in
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method>. Five AC-3 tests
/// + one AC-4 cached-prefix test (six methods total).</p>
///
/// <p><b>Two-array invariant under test (AC-2).</b> The dev-time
/// invariant codified in the AgentLoop class doc-comment: the
/// digest-prefixed user text rides only on the LLM-bound array; the
/// canonical <var>pUserText</var> persists to
/// <property>SessionAgent.Chat.History.TurnsJson</property>. The
/// <method>TestPersistedTurnsJsonContainsCanonicalUserText</method>
/// method asserts this directly via a SQL probe of the persisted
/// stream.</p>
///
/// <p><b>Anthropic prompt-cache preservation (AC-4 / NFR-P6).</b> The
/// <method>TestAnthropicCachedPrefixUnchangedAcrossTurns</method> method
/// captures <var>pSystemPrompt</var> + <var>pToolDefs</var> on each
/// provider invocation and asserts byte-identical equality across turns
/// 1 and 2 of the same conversation. Capture happens inside a dedicated
/// mock subclass (<CLASS>SessionAgent.Test.VocabDigestCaptureMock</CLASS>)
/// so the production code path is unmodified.</p>
///
/// <p><b>Test isolation.</b> Per-test PortalUser prefix
/// <code>sa-test-94-</code> + SessionKey prefix <code>sa-test-94-</code>;
/// cleanup sweeps <code>LIKE 'sa-test-9%'</code> (broadened in Story
/// 9.3 to cover sibling cleanup).</p>
///
/// <p><b>Why this class does not extend</b>
/// <CLASS>SessionAgent.Test.AgentLoopTestBase</CLASS><b>.</b> The base
/// class fixes the SessionKey prefix to <code>al-test</code> and only
/// manipulates the <code>session-inspection</code> Config.Agent row in
/// OnBefore/OnAfter. Story 9.4 requires the <code>message-search</code>
/// row to be Enabled=1 with Provider mutated for AC-4. Forking a fresh
/// base class for one story would inflate the codebase; copying just
/// the parts we need keeps this class self-contained.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/9-4-agentloop-integration-first-user-message-prefix-injection.md">Story 9.4 spec</a> — AC-3 / AC-4 / AC-5 verbatim source.</li>
/// <li><CLASS>SessionAgent.Agent.AgentLoop</CLASS> §RunTurn class doc-comment §"Two-array invariant".</li>
/// <li><CLASS>SessionAgent.Search.VocabularyDigest</CLASS> §Build — Story 9.3 substrate.</li>
/// </ul>
Class SessionAgent.Test.AgentLoopVocabDigestTest Extends %UnitTest.TestCase
{

/// <p>Stable per-test session-key prefix (matches PortalUser prefix);
/// cleanup sweeps any row whose SessionKey/PortalUser starts with
/// <code>sa-test-9</code> (broader than this story's prefix to cover
/// Story 9.3 leftovers).</p>
Parameter SAPREFIX As %String = "sa-test-94-";

/// <p>Captured original Enabled value on the message-search Config.Agent
/// row so OnAfterOneTest restores it.</p>
Property OrigSearchEnabled As %Boolean;

/// <p>Captured original Provider value on the message-search Config.Agent
/// row so OnAfterOneTest restores it.</p>
Property OrigSearchProvider As %String;

/// <p>Captured original Enabled value on the session-inspection
/// Config.Agent row so OnAfterOneTest restores it.</p>
Property OrigInspEnabled As %Boolean;

/// <p>Captured original Provider value on the session-inspection
/// Config.Agent row so OnAfterOneTest restores it.</p>
Property OrigInspProvider As %String;

/// <p>Constructor — accepts initvalue per project rule §"Critical
/// Constructor Requirements". No Private keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OrigSearchEnabled = 0
    Set ..OrigSearchProvider = ""
    Set ..OrigInspEnabled = 0
    Set ..OrigInspProvider = ""
    Quit $$$OK
}

/// <p>Per-test setup — capture original Config.Agent fields, ensure
/// both the message-search agent (Enabled=1, Provider=openai by default)
/// and the session-inspection agent (Enabled=1, Provider=openai) are
/// configured for mock-provider override. Sweep prior test rows.</p>
Method OnBeforeOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    ; Capture + ensure message-search agent is enabled with openai provider.
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    If $IsObject(tCfg) {
        Set ..OrigSearchEnabled = tCfg.Enabled
        Set ..OrigSearchProvider = tCfg.Provider
        Set tCfg.Enabled = 1
        Set tCfg.Provider = "openai"
        Do tCfg.%Save()
    }

    ; Capture + ensure session-inspection agent is enabled with openai provider.
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfgI) {
        Set ..OrigInspEnabled = tCfgI.Enabled
        Set ..OrigInspProvider = tCfgI.Provider
        Set tCfgI.Enabled = 1
        Set tCfgI.Provider = "openai"
        Do tCfgI.%Save()
    }

    ; Sweep audit + chat-history rows from prior runs of this story's tests.
    ; Broadened pattern (sa-test-9%) catches Story 9.3 leftovers too.
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) IN (SELECT ID FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-9' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-9')")) {
        Do tStmt.%Execute()
    }
    Set tStmt2 = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt2.%Prepare("DELETE FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ChatHistoryId) IN (SELECT ID FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-9' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-9')")) {
        Do tStmt2.%Execute()
    }
    Set tStmt3 = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt3.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-9' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-9'")) {
        Do tStmt3.%Execute()
    }

    ; Clear capture PPGs so each test starts with a clean slate.
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools

    Quit $$$OK
}

/// <p>Per-test teardown — clear override, restore captured fields.</p>
Method OnAfterOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    If $IsObject(tCfg) {
        Set tCfg.Enabled = ..OrigSearchEnabled
        Set tCfg.Provider = ..OrigSearchProvider
        Do tCfg.%Save()
    }
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfgI) {
        Set tCfgI.Enabled = ..OrigInspEnabled
        Set tCfgI.Provider = ..OrigInspProvider
        Do tCfgI.%Save()
    }
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools
    Quit $$$OK
}

/// <p>End-of-class cleanup.</p>
Method OnAfterAllTests() As %Status
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-9' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-9'")) {
        Do tStmt.%Execute()
    }
    Quit $$$OK
}

/// <p>Helper — install the VocabDigestCaptureMock as the per-process
/// override with a single canned text response.</p>
ClassMethod InstallCaptureMock(pCannedText As %String = "Captured response.")
{
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push(..BuildOpenAiTextResponse(pCannedText))
    Set tConfig = ##class(%DynamicObject).%New()
    Do tConfig.%Set("responses", tResponses)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.VocabDigestCaptureMock", tConfig.%ToJSON())
    Quit
}

/// <p>Helper — install the capture mock with multiple canned responses
/// (one per turn). Used by the AC-4 cached-prefix test.</p>
ClassMethod InstallCaptureMockMulti(pResponseTexts As %DynamicArray)
{
    Set tResponses = ##class(%DynamicArray).%New()
    Set tIter = pResponseTexts.%GetIterator()
    While tIter.%GetNext(.tIdx, .tTxt) {
        Do tResponses.%Push(..BuildOpenAiTextResponse(tTxt))
    }
    Set tConfig = ##class(%DynamicObject).%New()
    Do tConfig.%Set("responses", tResponses)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.VocabDigestCaptureMock", tConfig.%ToJSON())
    Quit
}

/// <p>Helper — build a single OpenAI-shape text response (finish_reason
/// = stop). The AgentLoopMockProvider's CallMessages translates this to
/// canonical via MessageAdapter.ProviderToCanonical.</p>
ClassMethod BuildOpenAiTextResponse(pText As %String) As %String
{
    Set tResp = ##class(%DynamicObject).%New()
    Set tChoices = ##class(%DynamicArray).%New()
    Set tChoice = ##class(%DynamicObject).%New()
    Set tMsg = ##class(%DynamicObject).%New()
    Do tMsg.%Set("role", "assistant")
    Do tMsg.%Set("content", pText)
    Do tChoice.%Set("finish_reason", "stop")
    Do tChoice.%Set("message", tMsg)
    Do tChoices.%Push(tChoice)
    Do tResp.%Set("choices", tChoices)
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("prompt_tokens", 5)
    Do tUsage.%Set("completion_tokens", 7)
    Do tResp.%Set("usage", tUsage)
    Quit tResp.%ToJSON()
}

/// <p>AC-3 row 1 — search-agent first turn receives digest. Invokes
/// <method>RunTurn</method> with <code>pAgentName="message-search"</code>
/// and a fresh PortalUser whose <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// is empty. The Story 9.3 substrate falls back to the seed-vocabulary
/// digest (5 seed rows). Asserts the captured user-block text (a) contains
/// the seed-vocabulary header marker, (b) contains the canonical
/// "User: &lt;pUserText&gt;" trailer, (c) contains the "---" delimiter.</p>
Method TestSearchAgentFirstTurnReceivesDigest()
{
    Set tSessionKey = ..#SAPREFIX _ "key-recv"
    Set tPortalUser = ..#SAPREFIX _ "power-recv"
    Set tUserText = "find me failed admits"

    Do ..InstallCaptureMock("Acknowledged.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, tUserText)
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult OREF")

    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertNotEquals(tCaptured, "", "VocabDigestCaptureMock captured user-block text (got empty)")
    ; AC-3 row 1 a — contains seed-fallback header (digest substrate).
    Do $$$AssertTrue(tCaptured [ "## Common idioms (no personal aliases yet)", "captured text contains seed-vocabulary digest header (got: " _ $Extract(tCaptured, 1, 400) _ ")")
    ; AC-3 row 1 b — contains the canonical "User: " trailer with pUserText.
    Do $$$AssertTrue(tCaptured [ ("User: " _ tUserText), "captured text contains 'User: <pUserText>' trailer")
    ; AC-3 row 1 c — contains the "---" delimiter.
    Do $$$AssertTrue(tCaptured [ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "captured text contains the '\n\n---\n\n' delimiter")
    Quit
}

/// <p>AC-3 row 2 — second turn does NOT re-inject the digest. After
/// the first turn persists, invoke a second <method>RunTurn</method>
/// against the same SessionKey + PortalUser and assert the captured
/// user-block text contains ONLY the raw <var>pUserText</var> — no
/// digest, no delimiter.</p>
Method TestSearchAgentSecondTurnDoesNotReinjectDigest()
{
    Set tSessionKey = ..#SAPREFIX _ "key-second"
    Set tPortalUser = ..#SAPREFIX _ "power-second"

    ; Two canned responses for two turns.
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push("Turn 1 ack.")
    Do tResponses.%Push("Turn 2 ack.")
    Do ..InstallCaptureMockMulti(tResponses)

    ; Turn 1 — digest applies.
    Set tResult1 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, "first message")
    Do $$$AssertTrue($IsObject(tResult1), "Turn 1 RunTurn returns TurnResult")

    ; Sanity check turn 1 captured text contains the digest (otherwise
    ; the test is mis-set-up).
    Set tCap1 = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertTrue(tCap1 [ "## Common idioms", "Turn 1 captured text contains digest header (sanity check)")

    ; Reset capture for turn 2.
    Kill ^||SessionAgentVocabDigestCapture

    ; Turn 2 — same conversation, second turn — digest must NOT inject.
    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, "second message")
    Do $$$AssertTrue($IsObject(tResult2), "Turn 2 RunTurn returns TurnResult")

    Set tCap2 = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertNotEquals(tCap2, "", "Turn 2 capture is non-empty")
    ; AC-3 row 2 — Turn 2 must NOT contain the digest header.
    Do $$$AssertTrue(tCap2 '[ "## Common idioms", "Turn 2 captured text does NOT contain digest header (got: " _ $Extract(tCap2, 1, 400) _ ")")
    ; AC-3 row 2 — Turn 2 must NOT contain the "---" delimiter that the
    ; digest-prefixed first turn carried.
    Do $$$AssertTrue(tCap2 '[ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "Turn 2 captured text does NOT contain '\n\n---\n\n' delimiter")
    Quit
}

/// <p>AC-3 row 3 — inspection-agent does NOT receive digest. Invoke
/// <method>RunTurn</method> with <code>pAgentName="session-inspection"</code>
/// and assert the captured user-block text contains ONLY the raw
/// <var>pUserText</var> — no digest, no delimiter.</p>
Method TestInspectionAgentDoesNotReceiveDigest()
{
    Set tSessionKey = ..#SAPREFIX _ "insp-key"
    Set tPortalUser = ..#SAPREFIX _ "power-insp"

    Do ..InstallCaptureMock("Inspection ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, "what happened")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")

    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertNotEquals(tCaptured, "", "Inspection-agent capture is non-empty")
    ; AC-3 row 3 — must NOT contain digest header.
    Do $$$AssertTrue(tCaptured '[ "## Common idioms", "Inspection-agent captured text does NOT contain digest header")
    ; AC-3 row 3 — must NOT contain the "---" delimiter.
    Do $$$AssertTrue(tCaptured '[ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "Inspection-agent captured text does NOT contain '---' delimiter")
    ; AC-3 row 3 — must contain the raw user text.
    Do $$$AssertTrue(tCaptured [ "what happened", "Inspection-agent captured text contains raw pUserText")
    Quit
}

/// <p>AC-3 row 4 — persisted TurnsJson contains canonical user text.
/// After the first search-agent turn runs, load the persisted
/// <property>SessionAgent.Chat.History.TurnsJson</property> and assert
/// the first user turn's <code>text</code> field equals the canonical
/// <var>pUserText</var> verbatim — NOT the digest-prefixed form. This
/// validates the AC-2 two-array invariant.</p>
Method TestPersistedTurnsJsonContainsCanonicalUserText()
{
    Set tSessionKey = ..#SAPREFIX _ "key-persist"
    Set tPortalUser = ..#SAPREFIX _ "power-persist"
    Set tUserText = "find me failed admits"

    Do ..InstallCaptureMock("Persist ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, tUserText)
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")

    ; Load the persisted Chat.History row via the dictionary-generated
    ; ConvKeyIdxOpen (matches what production reads). The SQL projection
    ; of a %Stream.GlobalCharacter column returns the stream OREF as a
    ; serialized OID reference, not the underlying text — open the row
    ; via the persistent index and read TurnsJson as a stream instead.
    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("message-search", tSessionKey, tPortalUser)
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row was persisted for the test conversation tuple (ConvKeyIdxOpen returned OREF)")
    If '$IsObject(tHist) Quit

    ; Read the TurnsJson stream into a string.
    Set tBuf = ""
    If $IsObject(tHist.TurnsJson) {
        Do tHist.TurnsJson.Rewind()
        While 'tHist.TurnsJson.AtEnd {
            Set tBuf = tBuf _ tHist.TurnsJson.Read(32000)
        }
    }
    Do tHist.%Close()
    Do $$$AssertNotEquals(tBuf, "", "TurnsJson stream is non-empty after RunTurn persisted")

    ; Parse the persisted JSON; first turn (index 0) should be the
    ; canonical user turn with text = pUserText verbatim.
    Set tTurns = ##class(%DynamicArray).%FromJSON(tBuf)
    Do $$$AssertTrue($IsObject(tTurns), "Persisted TurnsJson parses as %DynamicArray")
    Do $$$AssertTrue(tTurns.%Size() >= 1, "Persisted TurnsJson contains at least one turn (got: " _ tTurns.%Size() _ ")")

    Set tFirstTurn = tTurns.%Get(0)
    Do $$$AssertTrue($IsObject(tFirstTurn), "First turn is an object")
    Do $$$AssertEquals(tFirstTurn.%Get("role"), "user", "First turn role = 'user'")

    Set tFirstContent = tFirstTurn.%Get("content")
    Do $$$AssertTrue($IsObject(tFirstContent), "First turn content is an array")
    Do $$$AssertTrue(tFirstContent.%Size() >= 1, "First turn content has at least one block")

    Set tFirstBlock = tFirstContent.%Get(0)
    Do $$$AssertTrue($IsObject(tFirstBlock), "First content block is an object")
    Set tPersistedText = tFirstBlock.%Get("text")

    ; AC-3 row 4 — text MUST equal pUserText verbatim (no digest prefix).
    Do $$$AssertEquals(tPersistedText, tUserText, "Persisted user-turn text equals canonical pUserText (got: " _ $Extract(tPersistedText, 1, 200) _ ")")
    ; AC-3 row 4 — text MUST NOT contain digest markers.
    Do $$$AssertTrue(tPersistedText '[ "## Common idioms", "Persisted text does NOT contain digest header")
    Do $$$AssertTrue(tPersistedText '[ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "Persisted text does NOT contain '---' delimiter")
    Quit
}

/// <p>AC-3 row 5 — empty digest still wires through. Inserts a control-
/// path invariant: if <method>SessionAgent.Search.VocabularyDigest.Build</method>
/// were ever to return <code>""</code> (defensive — the seed-fallback
/// path should always return non-empty, but a future schema regression
/// might break it), the AgentLoop must still wire the user-block as
/// <code>"User: &lt;pUserText&gt;"</code> with no orphan delimiter.
/// We can't directly stub Build (no production hook), so we validate
/// the intent structurally: read the compiled RunTurn body and assert
/// the empty-digest branch (<code>If tDigest '= ""</code>) is present
/// with the correct fallback construction.</p>
Method TestEmptyDigestStillWiresThrough()
{
    ; Static-inspection probe of the compiled RunTurn body — same
    ; pattern as TestRunTurnOmitsSessionIdSentenceWhenSessionKeyEmpty
    ; in AgentLoopGuardsTest. Asserts the empty-digest fallback branch
    ; exists and has the correct shape.
    Set tMethod = ##class(%Dictionary.CompiledMethod).%OpenId("SessionAgent.Agent.AgentLoop||RunTurn")
    Do $$$AssertTrue($IsObject(tMethod), "RunTurn ClassMethod is defined on SessionAgent.Agent.AgentLoop")
    If '$IsObject(tMethod) Quit

    Do tMethod.Implementation.Rewind()
    Set tBody = ""
    While 'tMethod.Implementation.AtEnd {
        Set tBody = tBody _ tMethod.Implementation.Read(32000)
    }

    ; The empty-digest guard literal: "If tDigest '= """ — branches the
    ; digest-injection path on whether Build returned a non-empty string.
    Do $$$AssertTrue(tBody [ "If tDigest '= """, "RunTurn body contains the 'If tDigest ''= """"' empty-digest guard")
    ; The fallback construction — when digest is empty, just prepend
    ; "User: " to pUserText with no delimiter block.
    Do $$$AssertTrue(tBody [ """User: """, "RunTurn body contains the 'User: ' literal for both branches")
    ; The two-array machinery still fires when digest is empty (the
    ; tInjectDigest = 1 flag is set unconditionally inside the
    ; first-turn search-agent guard, regardless of whether tDigest is
    ; non-empty).
    Do $$$AssertTrue(tBody [ "Set tInjectDigest = 1", "RunTurn body sets tInjectDigest=1 inside the guard regardless of digest emptiness")

    ; Empirical wire-through check: invoke RunTurn with a fresh
    ; conversation and confirm the captured user-block text is
    ; non-empty (digest+user OR User-prefix-only — both are OK; the
    ; assertion is that wiring works).
    Set tSessionKey = ..#SAPREFIX _ "key-emptywire"
    Set tPortalUser = ..#SAPREFIX _ "power-emptywire"
    Do ..InstallCaptureMock("Empty-wire ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, "test wire")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult on the empty-wire empirical probe")
    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertTrue(tCaptured [ "User: test wire", "Captured text contains 'User: test wire' regardless of digest emptiness")
    Quit
}

/// <p>AC-4 — Anthropic prompt-cache hit-rate preservation (NFR-P6).
/// Sets <code>Config.Agent.message-search.Provider="anthropic"</code>
/// (preserved by OnAfter teardown), invokes <method>RunTurn</method>
/// twice in succession with the same SessionKey + PortalUser, captures
/// the provider-bound <var>pSystemPrompt</var> and <var>pToolDefs</var>
/// for each turn via the VocabDigestCaptureMock, and asserts:</p>
/// <ul>
/// <li><code>$Length(tSystem1) = $Length(tSystem2)</code> AND
/// <code>tSystem1 = tSystem2</code> — system prompt byte-identical.</li>
/// <li><code>tTools1.%ToJSON() = tTools2.%ToJSON()</code> — tools array
/// JSON-canonical equality.</li>
/// </ul>
/// <p>The cached-prefix structural assertion runs against the mock; no
/// live Anthropic credential is required.</p>
Method TestAnthropicCachedPrefixUnchangedAcrossTurns()
{
    Set tSessionKey = ..#SAPREFIX _ "key-anth"
    Set tPortalUser = ..#SAPREFIX _ "power-anth"

    ; Mutate Provider="anthropic" so the AgentLoop emits cache_control
    ; flags in tCacheCfg. The override short-circuits the actual
    ; provider construction, so the AnthropicProvider concrete is never
    ; instantiated — the mock returns canned text instead. OnAfter
    ; restores OrigSearchProvider.
    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    Do $$$AssertTrue($IsObject(tCfg), "message-search Config.Agent row exists")
    Set tCfg.Provider = "anthropic"
    Do tCfg.%Save()

    ; Two canned text responses for the two turns.
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push("Turn 1 anth ack.")
    Do tResponses.%Push("Turn 2 anth ack.")
    Do ..InstallCaptureMockMulti(tResponses)

    ; Turn 1.
    Set tResult1 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, "first cache turn")
    Do $$$AssertTrue($IsObject(tResult1), "Turn 1 RunTurn returns TurnResult")
    ; Capture turn 1's system + tools.
    Set tSystem1 = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Set tTools1 = $Get(^||SessionAgentVocabDigestCaptureTools, "")
    Do $$$AssertNotEquals(tSystem1, "", "Turn 1 captured system prompt is non-empty")
    Do $$$AssertNotEquals(tTools1, "", "Turn 1 captured tools JSON is non-empty")

    ; Reset captures for turn 2.
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools

    ; Turn 2.
    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", tSessionKey, tPortalUser, "second cache turn")
    Do $$$AssertTrue($IsObject(tResult2), "Turn 2 RunTurn returns TurnResult")
    Set tSystem2 = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Set tTools2 = $Get(^||SessionAgentVocabDigestCaptureTools, "")
    Do $$$AssertNotEquals(tSystem2, "", "Turn 2 captured system prompt is non-empty")
    Do $$$AssertNotEquals(tTools2, "", "Turn 2 captured tools JSON is non-empty")

    ; AC-4 — system prompt byte-identical across turns.
    Do $$$AssertEquals($Length(tSystem1), $Length(tSystem2), "system prompt length identical across turns (turn1 len=" _ $Length(tSystem1) _ ", turn2 len=" _ $Length(tSystem2) _ ")")
    Do $$$AssertEquals(tSystem1, tSystem2, "system prompt byte-identical across turns (cached-prefix invariant)")

    ; AC-4 — tools array JSON byte-identical across turns.
    Do $$$AssertEquals($Length(tTools1), $Length(tTools2), "tools JSON length identical across turns (turn1 len=" _ $Length(tTools1) _ ", turn2 len=" _ $Length(tTools2) _ ")")
    Do $$$AssertEquals(tTools1, tTools2, "tools JSON byte-identical across turns (cached-prefix invariant)")
    Quit
}

}
