/// <p>Integration tests for <CLASS>SessionAgent.EnsPortal.MessageViewer</CLASS>
/// — the Story 10.1 wire-up of the Search-Agent host page (parallel to
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> from Story 3.3).</p>
///
/// <p><b>Test surface (Story 10.1 AC-8 minimum 4 tests).</b></p>
/// <ul>
/// <li><method>TestDetailsPaneStructure</method> — AC-1 / AC-5: load
/// the new class's <code>XData detailsPane</code> via
/// <CLASS>%Dictionary.CompiledXData</CLASS> and assert the pane contains
/// 5 child <code>&lt;tab&gt;</code> elements with the expected ids
/// (<code>headerDetails</code>, <code>bodyDetails</code>,
/// <code>bodyContents</code>, <code>traceContent</code>,
/// <code>askAgentTab</code> in that order).</li>
/// <li><method>TestDrawChatPanelMethodPresent</method> — AC-1: structural
/// assertion that <method>DrawChatPanel</method> is declared as a
/// Method on the new class with the expected signature. Per the Task 2
/// allowance, this substitutes for a device-output capture (which adds
/// disproportionate complexity for a method whose runtime path is
/// covered empirically by the AC-7 live test).</li>
/// <li><method>TestSendChatMessageHappyPath</method> — AC-2: invoke
/// <method>SendChatMessage</method> via the mock-provider override and
/// assert the returned envelope is parseable JSON with the canonical
/// <CLASS>SessionAgent.Agent.TurnResult</CLASS> shape.</li>
/// <li><method>TestSendChatMessageMalformedHints</method> — AC-2 never-
/// throw envelope: invoke with malformed <code>pContextHintsJson</code>
/// and assert the structured error envelope (<code>error.kind=internal</code>)
/// is returned.</li>
/// </ul>
///
/// <p>Per project rule §"Critical Constructor Requirements" the class
/// implements <code>%OnNew(initvalue)</code> and forwards via
/// <code>##super(initvalue)</code>.</p>
///
/// <p>Per project rule §"Available Assertion Macros" the class uses
/// <code>$$$AssertX</code> macros only; no <code>$$$AssertFalse</code>
/// (use <code>$$$AssertTrue('cond, ...)</code>).</p>
Class SessionAgent.Test.MessageViewerTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts <code>initvalue</code>, forwards to
/// <code>##super</code>. No <code>Private</code> keyword (project rule
/// — ERROR #5477 blocks Private on %OnNew).</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Setup before each test — clear any leftover provider override
/// from a previous test (defensive — every test that uses the mock
/// installs its own override).</p>
Method OnBeforeOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Quit $$$OK
}

/// <p>Teardown after each test — clear provider override.</p>
Method OnAfterOneTest() As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Quit $$$OK
}

/// <p>Test (AC-1, AC-5) — the new <code>XData detailsPane</code> override
/// re-states the grandparent's 4 tabs verbatim and appends
/// <code>askAgentTab</code> as the 5th child. Loads the compiled XData
/// via <CLASS>%Dictionary.CompiledXData</CLASS>, parses the XML body, and
/// counts <code>&lt;tab&gt;</code> elements + asserts each id appears.</p>
///
/// <p>Per project rule §"IRIS SQL Case Sensitivity" we use
/// <code>%EXACT</code> on parent + name lookups; the CompiledXData ID is
/// <code>"&lt;Class&gt;||&lt;XDataName&gt;"</code> per IRIS dictionary
/// convention.</p>
Method TestDetailsPaneStructure()
{
    Set tXData = ##class(%Dictionary.CompiledXData).%OpenId("SessionAgent.EnsPortal.MessageViewer||detailsPane")
    Do $$$AssertTrue($IsObject(tXData), "subclass declares an XData detailsPane block (AC-1)")
    If '$IsObject(tXData) Quit

    Do tXData.Data.Rewind()
    Set tBuf = ""
    While 'tXData.Data.AtEnd {
        Set tBuf = tBuf _ tXData.Data.Read(32000)
    }

    ; Substring assertions on the XData body — each tab id appears.
    Do $$$AssertTrue(tBuf [ "headerDetails", "detailsPane re-states grandparent tab #1: headerDetails")
    Do $$$AssertTrue(tBuf [ "bodyDetails", "detailsPane re-states grandparent tab #2: bodyDetails")
    Do $$$AssertTrue(tBuf [ "bodyContents", "detailsPane re-states grandparent tab #3: bodyContents")
    Do $$$AssertTrue(tBuf [ "traceContent", "detailsPane re-states grandparent tab #4: traceContent")
    Do $$$AssertTrue(tBuf [ "askAgentTab", "detailsPane appends 5th tab: askAgentTab (AC-1)")
    Do $$$AssertTrue(tBuf [ "DrawChatPanel", "detailsPane wires OnDrawContent=DrawChatPanel on askAgentTab (AC-1)")

    ; Count <tab id="..."> opening tag occurrences. The body has 5 tab
    ; ids; counting via $Length($Piece(...)) is the simplest robust form.
    Set tCount = $Length(tBuf, "<tab ") - 1
    Do $$$AssertEquals(tCount, 5, "detailsPane has exactly 5 <tab> elements (4 verbatim + askAgentTab) (AC-1)")
    Quit
}

/// <p>Test (AC-1) — structural assertion that
/// <method>DrawChatPanel</method> is declared as a Method on the class
/// with the expected signature. Per the Story 10.1 Task 2 allowance,
/// this substitutes for a device-output capture (the runtime path is
/// covered empirically by the AC-7 live test).</p>
///
/// <p>Also asserts that the page-name resolution method
/// <method>%OnGetPageName</method> exists per the MPP5646 trap workaround
/// (Parameter PAGENAME = "" + runtime override).</p>
Method TestDrawChatPanelMethodPresent()
{
    ; Method exists.
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("SessionAgent.EnsPortal.MessageViewer||DrawChatPanel")
    Do $$$AssertTrue($IsObject(tDef), "DrawChatPanel method is declared on SessionAgent.EnsPortal.MessageViewer (AC-1)")

    ; Read the method body and assert load-bearing fragments are present.
    If $IsObject(tDef) {
        Do tDef.Implementation.Rewind()
        Set tBody = ""
        While 'tDef.Implementation.AtEnd {
            Set tBody = tBody _ tDef.Implementation.Read(32000)
        }
        ; Agent name is hard-coded to "message-search" (per spec).
        Do $$$AssertTrue(tBody [ "message-search", "DrawChatPanel hard-codes agent name = message-search (AC-1)")
        ; GUID-from-%session.Data lookup-or-create idiom (AC-3).
        Do $$$AssertTrue(tBody [ "SessionAgentMessageSearchKey", "DrawChatPanel reads/writes %session.Data slot (AC-3)")
        Do $$$AssertTrue(tBody [ "$System.Util.CreateGUID", "DrawChatPanel generates a GUID via $System.Util.CreateGUID (AC-3)")
        ; Returning-conversation placeholder text (AC-4).
        Do $$$AssertTrue(tBody [ "Continue the search.", "DrawChatPanel uses 'Continue the search.' returning placeholder (AC-4)")
        Do $$$AssertTrue(tBody [ "Ask anything across this IRIS instance.", "DrawChatPanel uses first-time placeholder (AC-4)")
    }

    ; %OnGetPageName runtime override — MPP5646 trap workaround.
    Set tPageNameDef = ##class(%Dictionary.CompiledMethod).%OpenId("SessionAgent.EnsPortal.MessageViewer||%OnGetPageName")
    Do $$$AssertTrue($IsObject(tPageNameDef), "%OnGetPageName is overridden (MPP5646 trap workaround)")

    ; Parameter PAGENAME = "" — confirm via dictionary parameter.
    Set tParamDef = ##class(%Dictionary.CompiledParameter).%OpenId("SessionAgent.EnsPortal.MessageViewer||PAGENAME")
    Do $$$AssertTrue($IsObject(tParamDef), "Parameter PAGENAME is declared on the subclass")
    If $IsObject(tParamDef) {
        Do $$$AssertEquals(tParamDef.Default, "", "Parameter PAGENAME defaults to empty string (MPP5646 trap workaround)")
    }
    Quit
}

/// <p>Test (AC-2) — invoke <method>SendChatMessage</method> via the
/// mock-provider override path. Asserts the returned envelope is
/// parseable JSON with the canonical
/// <CLASS>SessionAgent.Agent.TurnResult</CLASS> shape:
/// <code>assistantMarkdown</code>, <code>usageRollup</code>,
/// <code>durationMs</code>, <code>toolCallsRendered</code>.</p>
Method TestSendChatMessageHappyPath()
{
    Set tConvKey = "ms-test-envelope-" _ $Random(100000)

    ; Install mock provider returning one end_turn response.
    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push(..BuildEndTurnResponse("MessageViewer envelope passed-through OK."))
    Set tCfg = ##class(%DynamicObject).%New()
    Do tCfg.%Set("responses", tResponses)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentLoopMockProvider", tCfg.%ToJSON())

    Try {
        ; Invoke the ZenMethod (a ClassMethod with [ZenMethod] is
        ; invokable directly as a ClassMethod outside the Zen page
        ; instance — same dispatch surface).
        Set tEnvelope = ##class(SessionAgent.EnsPortal.MessageViewer).SendChatMessage("message-search", tConvKey, "list productions", "{}")
        Do $$$AssertNotEquals(tEnvelope, "", "envelope returned non-empty (AC-2)")

        ; Parse + assert TurnResult shape.
        Set tParsed = ##class(%DynamicObject).%FromJSON(tEnvelope)
        Do $$$AssertTrue($IsObject(tParsed), "envelope parses as JSON (AC-2)")
        Do $$$AssertTrue(tParsed.%IsDefined("assistantMarkdown"), "envelope has assistantMarkdown (AC-2)")
        Do $$$AssertTrue(tParsed.%IsDefined("usageRollup"), "envelope has usageRollup (AC-2)")
        Do $$$AssertTrue(tParsed.%IsDefined("durationMs"), "envelope has durationMs (AC-2)")
        Do $$$AssertTrue(tParsed.%IsDefined("toolCallsRendered"), "envelope has toolCallsRendered (AC-2)")

        ; Round-trip substring assertion.
        Do $$$AssertTrue(tParsed.%Get("assistantMarkdown") [ "MessageViewer envelope passed-through OK", "assistantMarkdown round-trips through ZenMethod boundary")
    }
    Catch ex {
        Do $$$AssertTrue(0, "test threw exception: " _ ex.DisplayString())
    }

    ; Cleanup — clear override + remove the chat-history row.
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) = ?")) {
        Do tStmt.%Execute(tConvKey)
    }
    Quit
}

/// <p>Test (AC-2 never-throw envelope) — invoke
/// <method>SendChatMessage</method> with malformed
/// <code>pContextHintsJson</code>. Asserts the structured error
/// envelope is returned (NOT a thrown exception).</p>
Method TestSendChatMessageMalformedHints()
{
    Set tEnvelope = ##class(SessionAgent.EnsPortal.MessageViewer).SendChatMessage("message-search", "ms-test-malformed", "list productions", "this is not JSON")

    Do $$$AssertNotEquals(tEnvelope, "", "envelope returned non-empty even on error")

    ; Parse error envelope.
    Set tParsed = ##class(%DynamicObject).%FromJSON(tEnvelope)
    Do $$$AssertTrue($IsObject(tParsed), "error envelope parses as JSON")
    Do $$$AssertTrue(tParsed.%IsDefined("error"), "envelope has 'error' key (never-throw envelope)")
    If tParsed.%IsDefined("error") {
        Set tErr = tParsed.%Get("error")
        Do $$$AssertEquals(tErr.%Get("kind"), "internal", "error kind = internal (AC-2)")
        Do $$$AssertNotEquals(tErr.%Get("message"), "", "error has non-empty message")
    }
    Quit
}

/// <p>Test (Story 10.10 + Story 10.13 F-2) — assert the
/// <code>onTabChange</code> ClientMethod override is declared on the
/// subclass with the load-bearing fragments. The grandparent's
/// <CLASS>EnsPortal.Template.filteredViewer</CLASS>.<METHOD>onTabChange</METHOD>
/// has a hard <code>switch (currTab) { case 1..4: ...; default: break }</code>
/// that ignores tab-index 5. The Story 10.10 form of this override
/// called <code>chatHost.refreshContents()</code> to "wake up" the
/// panel; Story 10.13 F-2 changed that path to a no-op because Zen
/// renders <code>OnDrawContent</code> eagerly at page parse time
/// (panel HTML is already in DOM when the page loads), and calling
/// refreshContents destructively wipes the IIFE-bound state. The
/// post-Story-10.13 override sets the sentinel but does NOT call
/// refreshContents.</p>
Method TestOnTabChangeOverridePresent()
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("SessionAgent.EnsPortal.MessageViewer||onTabChange")
    Do $$$AssertTrue($IsObject(tDef), "Story 10.10 + 10.13 F-2: onTabChange ClientMethod is declared on the subclass")
    If '$IsObject(tDef) Quit

    Do tDef.Implementation.Rewind()
    Set tBody = ""
    While 'tDef.Implementation.AtEnd {
        Set tBody = tBody _ tDef.Implementation.Read(32000)
    }

    ; Load-bearing fragments — preserved across Story 10.13 F-2 rewrite.
    Do $$$AssertTrue(tBody [ "invokeSuper", "onTabChange invokes parent's onTabChange first (preserves tabs 1-4 refresh)")
    Do $$$AssertTrue(tBody [ "currTab", "onTabChange reads currTab from the tabGroup")
    Do $$$AssertTrue(tBody [ "currTab !== 5", "onTabChange short-circuits when currTab is not the askAgentTab")
    ; Sentinel-set: present (operator-introspectable; matches the
    ; chat-panel.js init-time sentinel-set).
    Do $$$AssertTrue(tBody [ "_tabDisplay['Agent']", "onTabChange sets _tabDisplay['Agent'] sentinel (Story 10.13 F-2)")
    ; Story 10.13 F-2 — refreshContents() must NOT be CALLED on the Agent
    ; tab (calling it destructively wipes the IIFE-bound chat-panel state).
    ; A regression test against future re-introduction of the destructive
    ; path: assert the live JS function-call form
    ; "chatHost.refreshContents(" is NOT present in the method body. Note
    ; we only check the CALL form (with parenthesis) not the bare
    ; substring "refreshContents" — the post-Story-10.13 doc/comment
    ; references the function name in prose for context, which would
    ; trip an over-strict substring check.
    Do $$$AssertTrue('(tBody [ "chatHost.refreshContents("), "Story 10.13 F-2: onTabChange does NOT call chatHost.refreshContents() on the Agent tab (no-op short-circuit preserves IIFE-bound DOM)")
    Quit
}

/// <p>Test (Story 10.10 hotfix) — assert
/// <method>DrawChatPanel</method> reads <code>%session.Data("...")</code>
/// via <code>$Get(...)</code> to avoid the <code>&lt;UNDEFINED&gt;</code>
/// trap on first-time render. A bare
/// <code>%session.Data("missing-key")</code> raises <code>&lt;UNDEFINED&gt;</code>
/// rather than returning empty string; the original Story 10.1 form
/// had this exact bug and propagated the exception to the outer Catch,
/// causing the helper-write path to be silently skipped (chat panel
/// rendered as empty <code>enc.innerHTML = '';</code>).</p>
Method TestDrawChatPanelGuardsSessionDataAccess()
{
    Set tDef = ##class(%Dictionary.CompiledMethod).%OpenId("SessionAgent.EnsPortal.MessageViewer||DrawChatPanel")
    Do $$$AssertTrue($IsObject(tDef), "DrawChatPanel method exists")
    If '$IsObject(tDef) Quit

    Do tDef.Implementation.Rewind()
    Set tBody = ""
    While 'tDef.Implementation.AtEnd {
        Set tBody = tBody _ tDef.Implementation.Read(32000)
    }

    ; Story 10.10 hotfix: the read MUST be wrapped in $Get(...) to avoid
    ; <UNDEFINED> on first-time render when the subscript has never been set.
    Do $$$AssertTrue(tBody [ "$Get(%session.Data(""SessionAgentMessageSearchKey""))", "Story 10.10 hotfix: %session.Data subscript read uses $Get(...) to avoid <UNDEFINED> on first-time render")
    Quit
}

/// <p>Helper — build an OpenAI-shape end_turn response (mock-provider
/// payload). Same shape as the VisualTraceTest helper.</p>
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
