/// <p>Story 14.4 AC-6 — verifies the learned-schema-notes first-turn
/// digest injection in <method>SessionAgent.Agent.AgentLoop.RunTurn</method>
/// for BOTH agents (decision D4), riding the Story 9.4 two-array
/// machinery: search agent = vocabulary digest + schema-notes digest
/// concatenated (vocab first); inspection agent = schema-notes digest
/// only; subsequent turns unprefixed; empty-digest collapse for both
/// agents; canonical persistence unchanged; and the NFR-P6
/// cache-stability extension for the inspection agent (the search-agent
/// cache-stability test lives in
/// <CLASS>SessionAgent.Test.AgentLoopVocabDigestTest</CLASS>).</p>
///
/// <p>Reuses <CLASS>SessionAgent.Test.VocabDigestCaptureMock</CLASS> +
/// the Story 9.4 capture PPGs. Test isolation: SessionKey/PortalUser
/// prefix <code>sa-test-144-</code>; schema-note fixtures use the
/// <code>ztest-</code> subject convention and are swept per-test.</p>
Class SessionAgent.Test.AgentLoopSchemaDigestTest Extends %UnitTest.TestCase
{

Parameter SAPREFIX As %String = "sa-test-144-";

Property OrigSearchEnabled As %Boolean;

Property OrigSearchProvider As %String;

Property OrigInspEnabled As %Boolean;

Property OrigInspProvider As %String;

/// Story 14.5 review fix (HIGH) — the two Story 14.5 tests mutate
/// SystemPromptOverride on the live Config.Agent rows; an exception or
/// early Quit mid-test would otherwise leave the operator's row
/// polluted ("ztest-145 ..." or $Char(0)). Snapshot/restore in
/// OnBeforeOneTest/OnAfterOneTest, matching the Enabled/Provider
/// pattern above. MAXLEN="" — overrides are full prompt strings
/// (Epic 5 Bug-2 MAXLEN-overflow lesson).
Property OrigSearchOverride As %String(MAXLEN = "");

/// See <property>OrigSearchOverride</property>.
Property OrigInspOverride As %String(MAXLEN = "");

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OrigSearchEnabled = 0
    Set ..OrigSearchProvider = ""
    Set ..OrigInspEnabled = 0
    Set ..OrigInspProvider = ""
    Set ..OrigSearchOverride = ""
    Set ..OrigInspOverride = ""
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    If $IsObject(tCfg) {
        Set ..OrigSearchEnabled = tCfg.Enabled
        Set ..OrigSearchProvider = tCfg.Provider
        Set ..OrigSearchOverride = tCfg.SystemPromptOverride
        Set tCfg.Enabled = 1
        Set tCfg.Provider = "openai"
        Do tCfg.%Save()
    }
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfgI) {
        Set ..OrigInspEnabled = tCfgI.Enabled
        Set ..OrigInspProvider = tCfgI.Provider
        Set ..OrigInspOverride = tCfgI.SystemPromptOverride
        Set tCfgI.Enabled = 1
        Set tCfgI.Provider = "openai"
        Do tCfgI.%Save()
    }

    Set tSweepSC = ..SweepFixtures()
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools
    Quit tSweepSC
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()

    Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    If $IsObject(tCfg) {
        Set tCfg.Enabled = ..OrigSearchEnabled
        Set tCfg.Provider = ..OrigSearchProvider
        Set tCfg.SystemPromptOverride = ..OrigSearchOverride
        Do tCfg.%Save()
    }
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    If $IsObject(tCfgI) {
        Set tCfgI.Enabled = ..OrigInspEnabled
        Set tCfgI.Provider = ..OrigInspProvider
        Set tCfgI.SystemPromptOverride = ..OrigInspOverride
        Do tCfgI.%Save()
    }

    Set tSweepSC = ..SweepFixtures()
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools
    Quit tSweepSC
}

/// <p>Sweep chat-history rows + audit children for this class's prefix,
/// and the ztest- schema-note fixtures. Returns the schema-note sweep
/// status (Story 14.4 review fix — a silently failed sweep poisons the
/// digest-dependent assertions).</p>
ClassMethod SweepFixtures() As %Status
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) IN (SELECT ID FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-144' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-144')")) {
        Do tStmt.%Execute()
    }
    Set tStmt2 = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt2.%Prepare("DELETE FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ChatHistoryId) IN (SELECT ID FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-144' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-144')")) {
        Do tStmt2.%Execute()
    }
    Set tStmt3 = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt3.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) %STARTSWITH 'sa-test-144' OR %EXACT(PortalUser) %STARTSWITH 'sa-test-144'")) {
        Do tStmt3.%Execute()
    }
    Quit ##class(SessionAgent.Test.SchemaNoteToolTest).DeleteFixtureRows()
}

/// <p>AC-6 — inspection agent's FIRST first-turn injection: with a
/// schema note present, the provider-bound user-block carries the
/// schema-notes digest header, the note subject, the single "---"
/// delimiter, and the "User: " trailer.</p>
Method TestInspectionAgentFirstTurnReceivesSchemaDigest()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-insp-fact", "inspection digest fixture fact"), "fixture note seeded")

    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("Inspection digest ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SAPREFIX _ "insp-first", ..#SAPREFIX _ "user-insp", "what failed today")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")

    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertNotEquals(tCaptured, "", "capture non-empty")
    Do $$$AssertTrue(tCaptured [ "## Learned schema notes", "inspection first turn carries the schema-notes digest header (AC-6 Then)")
    Do $$$AssertTrue(tCaptured [ "ztest-al-insp-fact", "digest carries the fixture subject")
    Do $$$AssertTrue(tCaptured [ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "single '---' delimiter block present")
    Do $$$AssertTrue(tCaptured [ "User: what failed today", "'User: <pUserText>' trailer present")
    ; Inspection agent must NOT receive vocabulary content.
    Do $$$AssertTrue(tCaptured '[ "## Common idioms", "no seed-vocabulary digest for the inspection agent")
    Do $$$AssertTrue(tCaptured '[ "## Saved aliases", "no user-vocabulary digest for the inspection agent")
    Quit
}

/// <p>AC-6 — search agent first turn carries BOTH digests in order:
/// vocabulary digest FIRST, schema-notes digest second, then the single
/// "---" delimiter, then the "User: " trailer.</p>
Method TestSearchAgentFirstTurnContainsBothDigestsInOrder()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-search-fact", "search digest fixture fact"), "fixture note seeded")

    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("Search digest ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", ..#SAPREFIX _ "search-first", ..#SAPREFIX _ "user-search", "find failed admits")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")

    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertNotEquals(tCaptured, "", "capture non-empty")
    ; Vocab digest present (seed fallback for a fresh PortalUser).
    Set tVocabPos = $Find(tCaptured, "## Common idioms")
    Do $$$AssertTrue(tVocabPos > 0, "vocabulary digest present (seed-fallback header)")
    ; Schema digest present.
    Set tSchemaPos = $Find(tCaptured, "## Learned schema notes")
    Do $$$AssertTrue(tSchemaPos > 0, "schema-notes digest present")
    ; Order: vocab FIRST, then schema, then the delimiter, then User:.
    Set tDelimPos = $Find(tCaptured, $Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10))
    Set tUserPos = $Find(tCaptured, "User: find failed admits")
    Do $$$AssertTrue(tVocabPos < tSchemaPos, "vocabulary digest renders BEFORE the schema-notes digest (vocab first)")
    Do $$$AssertTrue(tSchemaPos < tDelimPos, "the '---' delimiter follows the concatenated digest block")
    Do $$$AssertTrue(tDelimPos < tUserPos, "'User: <pUserText>' trailer follows the delimiter")
    ; Single delimiter block (the block structure is preserved — the
    ; digests concatenate with a blank line, NOT a second delimiter).
    Set tDelim = $Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)
    Set tCount = ($Length(tCaptured, tDelim) - 1)
    Do $$$AssertEquals(tCount, 1, "exactly ONE '---' delimiter block (got " _ tCount _ ")")
    Quit
}

/// <p>AC-6 — subsequent turns unprefixed (inspection agent): turn 2's
/// provider-bound user-block is the raw <var>pUserText</var> with no
/// digest header and no "User: " prefix.</p>
Method TestInspectionAgentSecondTurnUnprefixed()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-second", "second-turn fixture fact"), "fixture note seeded")

    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push("Turn 1 ack.")
    Do tResponses.%Push("Turn 2 ack.")
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMockMulti(tResponses)

    Set tSessionKey = ..#SAPREFIX _ "insp-second"
    Set tPortalUser = ..#SAPREFIX _ "user-second"
    Set tResult1 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, "first question")
    Do $$$AssertTrue($IsObject(tResult1), "Turn 1 RunTurn returns TurnResult")
    Set tCap1 = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertTrue(tCap1 [ "## Learned schema notes", "Turn 1 carries the schema digest (sanity)")

    Kill ^||SessionAgentVocabDigestCapture
    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, "second question")
    Do $$$AssertTrue($IsObject(tResult2), "Turn 2 RunTurn returns TurnResult")
    Set tCap2 = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertEquals(tCap2, "second question", "Turn 2 user-block is the raw pUserText (no digest, no 'User: ' prefix)")
    Quit
}

/// <p>AC-6 — empty-digest collapse (inspection agent): with ZERO schema
/// notes the user-block collapses to <code>"User: " + pUserText</code>
/// with no digest header and no orphan delimiter, and the two-array
/// machinery still wires through.</p>
Method TestInspectionAgentEmptyDigestCollapse()
{
    ; OnBeforeOneTest swept the ztest- fixtures; HSCUSTOM may carry
    ; operator notes, so assert the collapse contract structurally when
    ; notes exist and exactly when they don't.
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build($NAMESPACE)

    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("Collapse ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SAPREFIX _ "insp-empty", ..#SAPREFIX _ "user-empty", "anything wrong")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")
    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    If tDigest = "" {
        ; The empirical empty-collapse case (normal sweep state).
        Do $$$AssertEquals(tCaptured, "User: anything wrong", "empty digest collapses to 'User: <pUserText>' with no prefix block")
        Do $$$AssertTrue(tCaptured '[ "---", "no orphan delimiter on the empty-digest collapse")
    } Else {
        ; Operator notes exist in this namespace — the injection fires;
        ; lock the trailer instead (the collapse branch is additionally
        ; locked by source introspection below).
        Do $$$AssertTrue(tCaptured [ "User: anything wrong", "digest-prefixed block still carries the 'User: ' trailer")
    }

    ; Structural lock for the collapse branch (Story 9.4 precedent —
    ; the empty-digest guard and fallback construction are present and
    ; the inject flag is unconditional inside the first-turn guard).
    Set tMethod = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Agent.AgentLoop||RunTurn")
    Do $$$AssertTrue($IsObject(tMethod), "RunTurn is defined")
    If '$IsObject(tMethod) Quit
    Do tMethod.Implementation.Rewind()
    Set tBody = ""
    While 'tMethod.Implementation.AtEnd { Set tBody = tBody _ tMethod.Implementation.Read(32000) }
    Do $$$AssertTrue(tBody [ "If tTurns.%Size() = 0", "first-turn guard fires for BOTH agents (no agent-name condition on the outer guard)")
    Do $$$AssertTrue(tBody [ "SchemaNoteDigest", "RunTurn calls SchemaNoteDigest.Build")
    Do $$$AssertTrue(tBody [ "tCtx.Namespace", "schema digest is namespace-scoped via the CallerContext")
    Do $$$AssertTrue(tBody [ ("Set tInjectedUserText = ""User: "" _ pUserText"), "empty-digest collapse construction present in source (Story 14.4 review fix - the collapse line itself is locked)")
    Quit
}

/// <p>AC-6 — empty-SCHEMA-digest collapse (search agent): with zero
/// schema notes the search agent still receives its vocabulary digest
/// and the single delimiter; no schema header appears.</p>
Method TestSearchAgentEmptySchemaDigestStillHasVocab()
{
    ; ztest- fixtures swept in OnBeforeOneTest. Skip-guard: if operator
    ; notes exist in this namespace the schema digest is legitimately
    ; non-empty; the vocab-first ordering test above covers that state.
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build($NAMESPACE)

    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("Vocab-only ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", ..#SAPREFIX _ "search-empty", ..#SAPREFIX _ "user-vempty", "find admits")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")
    Set tCaptured = $Get(^||SessionAgentVocabDigestCapture, "")
    Do $$$AssertTrue(tCaptured [ "## Common idioms", "vocabulary digest still injects for the search agent")
    Do $$$AssertTrue(tCaptured [ ($Char(10) _ $Char(10) _ "---" _ $Char(10) _ $Char(10)), "single '---' delimiter present")
    Do $$$AssertTrue(tCaptured [ "User: find admits", "'User: ' trailer present")
    If tDigest = "" {
        Do $$$AssertTrue(tCaptured '[ "## Learned schema notes", "no schema-notes header when the namespace has no notes")
    }
    Quit
}

/// <p>AC-6 — two-array invariant holds for the NEW inspection-agent
/// injection: the persisted TurnsJson first user turn equals the
/// canonical <var>pUserText</var> verbatim (the digest rides ONLY the
/// LLM-bound array — Story 9.4 contract).</p>
Method TestInspectionPersistedTurnsJsonCanonical()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-persist", "persistence fixture fact"), "fixture note seeded")

    Set tSessionKey = ..#SAPREFIX _ "insp-persist"
    Set tPortalUser = ..#SAPREFIX _ "user-persist"
    Set tUserText = "what errored overnight"
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("Persist ack.")
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, tUserText)
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult")
    ; Sanity: the LLM side DID receive the digest-prefixed form.
    Do $$$AssertTrue($Get(^||SessionAgentVocabDigestCapture, "") [ "## Learned schema notes", "LLM-bound text carries the digest (sanity)")

    Set tHist = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen("session-inspection", tSessionKey, tPortalUser)
    Do $$$AssertTrue($IsObject(tHist), "Chat.History row persisted")
    If '$IsObject(tHist) Quit
    Set tBuf = ""
    If $IsObject(tHist.TurnsJson) {
        Do tHist.TurnsJson.Rewind()
        While 'tHist.TurnsJson.AtEnd { Set tBuf = tBuf _ tHist.TurnsJson.Read(32000) }
    }
    Do tHist.%Close()
    Set tTurns = ##class(%DynamicArray).%FromJSON(tBuf)
    Set tFirstText = tTurns.%Get(0).%Get("content").%Get(0).%Get("text")
    Do $$$AssertEquals(tFirstText, tUserText, "persisted first user turn = canonical pUserText verbatim (no digest leak)")
    Do $$$AssertTrue(tFirstText '[ "## Learned schema notes", "persisted text carries no digest header")
    Quit
}

/// <p>AC-6 / NFR-P6 — cache-stability EXTENSION for the inspection
/// agent (the existing search-agent test lives in
/// AgentLoopVocabDigestTest): with the inspection agent on
/// Provider="anthropic" and a schema note present (digest actually
/// injected on turn 1), the provider-bound system prompt + tools JSON
/// are byte-identical across turns 1 and 2 — the digest rides ONLY the
/// uncached first-user-message segment.</p>
Method TestAnthropicCachedPrefixUnchangedInspectionAgent()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-cache", "cache stability fixture fact"), "fixture note seeded")

    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tCfgI), "session-inspection Config.Agent row exists")
    Set tCfgI.Provider = "anthropic"
    Do tCfgI.%Save()

    Set tResponses = ##class(%DynamicArray).%New()
    Do tResponses.%Push("Turn 1 anth ack.")
    Do tResponses.%Push("Turn 2 anth ack.")
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMockMulti(tResponses)

    Set tSessionKey = ..#SAPREFIX _ "insp-cache"
    Set tPortalUser = ..#SAPREFIX _ "user-cache"

    Set tResult1 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, "first cache turn")
    Do $$$AssertTrue($IsObject(tResult1), "Turn 1 RunTurn returns TurnResult")
    ; Sanity — turn 1 actually carried the digest in the user block.
    Do $$$AssertTrue($Get(^||SessionAgentVocabDigestCapture, "") [ "## Learned schema notes", "Turn 1 user block carries the schema digest (sanity)")
    Set tSystem1 = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Set tTools1 = $Get(^||SessionAgentVocabDigestCaptureTools, "")
    Do $$$AssertNotEquals(tSystem1, "", "Turn 1 system prompt captured")
    Do $$$AssertNotEquals(tTools1, "", "Turn 1 tools JSON captured")

    Kill ^||SessionAgentVocabDigestCaptureSystem
    Kill ^||SessionAgentVocabDigestCaptureTools

    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", tSessionKey, tPortalUser, "second cache turn")
    Do $$$AssertTrue($IsObject(tResult2), "Turn 2 RunTurn returns TurnResult")
    Set tSystem2 = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Set tTools2 = $Get(^||SessionAgentVocabDigestCaptureTools, "")

    Do $$$AssertEquals($Length(tSystem1), $Length(tSystem2), "system prompt length identical across turns")
    Do $$$AssertEquals(tSystem1, tSystem2, "system prompt byte-identical across turns (NFR-P6 cached-prefix invariant, inspection agent)")
    Do $$$AssertEquals($Length(tTools1), $Length(tTools2), "tools JSON length identical across turns")
    Do $$$AssertEquals(tTools1, tTools2, "tools JSON byte-identical across turns (NFR-P6 cached-prefix invariant, inspection agent)")
    Quit
}

/// <p><b>Story 14.5 AC-1 / AC-6 — SystemPromptOverride replacement
/// semantics.</b> (1) A non-empty per-row override REPLACES the default
/// prompt INCLUDING the Story 14.5 methodology card (the card is part
/// of the default prompt, not a separate channel). (2) A
/// <code>$Char(0)</code> sentinel in the column (the IRIS legacy
/// SQL-UPDATE-cleared-%String shape) is normalized to <code>""</code>
/// at the AgentLoop read site (AgentLoop Step 6 guard, Story 6.0) so
/// the default prompt WITH the card is used and no NUL byte leaks to
/// the provider. Captures the provider-bound system prompt via
/// <CLASS>SessionAgent.Test.VocabDigestCaptureMock</CLASS>.</p>
Method TestSystemPromptOverrideReplacesDefaultIncludingCard()
{
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tCfgI), "session-inspection Config.Agent row exists")
    If '$IsObject(tCfgI) Quit
    Set tOrigOverride = tCfgI.SystemPromptOverride

    Set tCard = ##class(SessionAgent.Config.AgentDefaults).GetMethodologyCard()
    Do $$$AssertNotEquals(tCard, "", "methodology card non-empty (precondition)")

    ; ---- Case 1: non-empty override replaces default INCLUDING card.
    ; (Exception-path safety: OnBeforeOneTest/OnAfterOneTest snapshot and
    ; restore SystemPromptOverride — Story 14.5 review fix.)
    Set tCfgI.SystemPromptOverride = "ztest-145 custom operator override prompt."
    Do $$$AssertStatusOK(tCfgI.%Save(), "Case-1 override %Save succeeded (premise guard)")
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("override ack.")
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Set tResult = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SAPREFIX _ "ovr-a", ..#SAPREFIX _ "user-ovr", "hello")
    Do $$$AssertTrue($IsObject(tResult), "RunTurn returns TurnResult (override case)")
    Set tSystem = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Do $$$AssertTrue(tSystem [ "ztest-145 custom operator override prompt.", "override text reaches the provider-bound system prompt (AC-1 override semantics)")
    Do $$$AssertTrue('(tSystem [ tCard), "override REPLACES the default INCLUDING the methodology card (AC-1)")

    ; ---- Case 2: $Char(0) sentinel normalizes to "" -> default WITH card.
    Set tCfgI2 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Set tCfgI2.SystemPromptOverride = $Char(0)
    Do $$$AssertStatusOK(tCfgI2.%Save(), "Case-2 $Char(0) sentinel %Save succeeded (premise guard)")
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("sentinel ack.")
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SAPREFIX _ "ovr-b", ..#SAPREFIX _ "user-ovr", "hello again")
    Do $$$AssertTrue($IsObject(tResult2), "RunTurn returns TurnResult (sentinel case)")
    Set tSystem2 = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Do $$$AssertTrue(tSystem2 [ tCard, "$Char(0) sentinel normalized to empty -> default prompt WITH card used (AC-6 $Char(0) lock)")
    Do $$$AssertTrue('(tSystem2 [ $Char(0)), "no NUL byte leaks into the provider-bound system prompt (AC-6)")

    ; ---- Restore the original override value (OnAfterOneTest also
    ; restores — this keeps the straight-line path self-contained).
    Set tCfgI3 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Set tCfgI3.SystemPromptOverride = tOrigOverride
    Do $$$AssertStatusOK(tCfgI3.%Save(), "override restore %Save succeeded")
    Quit
}

/// <p><b>Story 14.5 QA gap coverage — cache-channel separation + the
/// provider-bound methodology card for BOTH agents.</b> With a schema
/// note present (digest actually injected on turn 1) and no per-row
/// override, asserts at AgentLoop runtime for EACH agent: (1) the
/// methodology card rides the provider-bound SYSTEM segment (the AC-1
/// card reaches the wire, not just the AgentDefaults unit surface —
/// closes the message-search runtime gap); (2) the schema-notes /
/// vocabulary digests do NOT ride the SYSTEM segment (NFR-P6: a digest
/// wrongly riding the cached system prefix would be byte-identical
/// across turns and slip past the turn-stability tests above); (3) the
/// card does NOT leak into the USER block (the digest channel). Captures
/// via <CLASS>SessionAgent.Test.VocabDigestCaptureMock</CLASS>.</p>
Method TestMethodologyCardRidesSystemSegmentBothAgents()
{
    Set tCard = ##class(SessionAgent.Config.AgentDefaults).GetMethodologyCard()
    Do $$$AssertNotEquals(tCard, "", "methodology card non-empty (precondition)")

    ; Clear any operator override on both rows for the duration so the
    ; DEFAULT prompt (with card) is the one bound; restore at the end.
    ; Story 14.5 review fix (HIGH): open + validate BOTH rows BEFORE
    ; mutating either — the old order mutated the inspection row, then
    ; early-Quit on a missing message-search row left it un-restored.
    ; (OnBeforeOneTest/OnAfterOneTest also snapshot/restore for the
    ; exception path.)
    Set tCfgI = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tCfgI), "session-inspection Config.Agent row exists")
    Set tCfgS = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    Do $$$AssertTrue($IsObject(tCfgS), "message-search Config.Agent row exists")
    If ('$IsObject(tCfgI)) || ('$IsObject(tCfgS)) Quit
    Set tOrigOvrI = tCfgI.SystemPromptOverride
    Set tCfgI.SystemPromptOverride = ""
    Do $$$AssertStatusOK(tCfgI.%Save(), "inspection override cleared for card-channel test (premise guard)")
    Set tOrigOvrS = tCfgS.SystemPromptOverride
    Set tCfgS.SystemPromptOverride = ""
    Do $$$AssertStatusOK(tCfgS.%Save(), "search override cleared for card-channel test (premise guard)")

    ; Seed a note so the schema digest actually injects on turn 1.
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-al-card-chan", "card channel fixture fact"), "fixture note seeded")

    ; ---- Inspection agent first turn.
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("card chan insp ack.")
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Set tResultI = ##class(SessionAgent.Agent.AgentLoop).RunTurn("session-inspection", ..#SAPREFIX _ "card-insp", ..#SAPREFIX _ "user-card-i", "what failed today")
    Do $$$AssertTrue($IsObject(tResultI), "inspection RunTurn returns TurnResult")
    Set tUserI = $Get(^||SessionAgentVocabDigestCapture, "")
    Set tSystemI = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Do $$$AssertTrue(tSystemI [ tCard, "inspection provider-bound SYSTEM segment carries the methodology card (AC-1/AC-3 runtime)")
    Do $$$AssertTrue('(tSystemI [ "## Learned schema notes"), "schema digest does NOT ride the inspection SYSTEM segment (NFR-P6 cache-channel separation)")
    Do $$$AssertTrue(tUserI [ "## Learned schema notes", "schema digest rides the inspection USER block (sanity)")
    Do $$$AssertTrue('(tUserI [ tCard), "methodology card does NOT leak into the inspection USER block (cache-channel separation)")

    ; ---- Search agent first turn.
    Do ##class(SessionAgent.Test.AgentLoopVocabDigestTest).InstallCaptureMock("card chan search ack.")
    Kill ^||SessionAgentVocabDigestCapture
    Kill ^||SessionAgentVocabDigestCaptureSystem
    Set tResultS = ##class(SessionAgent.Agent.AgentLoop).RunTurn("message-search", ..#SAPREFIX _ "card-search", ..#SAPREFIX _ "user-card-s", "find failed admits")
    Do $$$AssertTrue($IsObject(tResultS), "search RunTurn returns TurnResult")
    Set tUserS = $Get(^||SessionAgentVocabDigestCapture, "")
    Set tSystemS = $Get(^||SessionAgentVocabDigestCaptureSystem, "")
    Do $$$AssertTrue(tSystemS [ tCard, "search provider-bound SYSTEM segment carries the methodology card (AC-1 runtime — closes the message-search gap)")
    ; Story 14.5 review fix (vacuous-pass guard): positively assert the
    ; digest actually rode the search USER block — otherwise the three
    ; negative channel-separation assertions below pass trivially when
    ; no digest is injected at all.
    Do $$$AssertTrue(tUserS [ "## Learned schema notes", "schema digest rides the search USER block (positive control)")
    Do $$$AssertTrue('(tSystemS [ "## Learned schema notes"), "schema digest does NOT ride the search SYSTEM segment (NFR-P6)")
    Do $$$AssertTrue('(tSystemS [ "## Common idioms"), "vocabulary digest does NOT ride the search SYSTEM segment (NFR-P6)")
    Do $$$AssertTrue('(tUserS [ tCard), "methodology card does NOT leak into the search USER block (cache-channel separation)")

    ; ---- Restore both rows' original override values (OnAfterOneTest
    ; also restores — this keeps the straight-line path self-contained).
    Set tCfgI2 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Set tCfgI2.SystemPromptOverride = tOrigOvrI
    Do $$$AssertStatusOK(tCfgI2.%Save(), "inspection override restore %Save succeeded")
    Set tCfgS2 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("message-search")
    Set tCfgS2.SystemPromptOverride = tOrigOvrS
    Do $$$AssertStatusOK(tCfgS2.%Save(), "search override restore %Save succeeded")
    Quit
}

}
