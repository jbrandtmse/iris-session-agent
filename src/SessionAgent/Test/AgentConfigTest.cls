/// <p>Unit tests for the server-side helpers on
/// <CLASS>SessionAgent.UI.AgentConfig</CLASS> (Story 6.1):
/// <method>GetCredentialsList</method> + <method>LoadAgentConfig</method>.
/// Page-rendering tests (Zen XData smoke) are out of scope for
/// %UnitTest — verified via the Rule 12 browser screenshot in the
/// story's empirical battery.</p>
///
/// <p><b>Three minimum tests per AC-9:</b></p>
/// <ol>
/// <li><method>TestLoadAgentConfigReturnsSeededRow</method> — calls
/// <method>LoadAgentConfig</method>("session-inspection"), asserts the
/// returned JSON has <code>found=1</code> and the seeded provider/model
/// shape from <CLASS>SessionAgent.Config.AgentDefaults</CLASS>.</li>
/// <li><method>TestLoadAgentConfigEmptyForUnknownAgent</method> — calls
/// <method>LoadAgentConfig</method>("nonexistent-agent"), asserts
/// <code>found=0</code> and the empty-defaults shape.</li>
/// <li><method>TestGetCredentialsListReturnsConfigEntries</method> —
/// inserts a transient credential row, calls
/// <method>GetCredentialsList</method>, asserts the returned string
/// contains the inserted entry, then cleans up.</li>
/// </ol>
///
/// <p><b>Test isolation strategy.</b> The seeded-row tests rely on the
/// install-time seed (or run a re-seed if missing) and never mutate the
/// row. The credentials-list test creates and deletes a transient
/// <code>Ens.Config.Credentials</code> row scoped to this test only.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md</a>
/// Story 6.1 AC-9 — test contract.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list and constructor pattern.</li>
/// <li><CLASS>SessionAgent.Test.ConfigAgentTest</CLASS> — sibling test
/// class providing the constructor + per-test fixture pattern.</li>
/// </ul>
Class SessionAgent.Test.AgentConfigTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> the parent
/// <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Per-test setup: ensure the install-time seed is present so
/// <method>TestLoadAgentConfigReturnsSeededRow</method> has a row to
/// fetch. Idempotent — <method>SeedDefaultAgentConfigs</method> skips
/// rows that already exist via the AgentNameIdxExists predicate.</p>
Method OnBeforeOneTest() As %Status
{
    Try {
        Do ##class(SessionAgent.Installer).SeedDefaultAgentConfigs()
    }
    Catch ex {
        ; Best-effort — if seeding fails, the seeded-row test will
        ; report the actual failure mode (found=0 when it expected
        ; found=1) and the empty-shape test still works.
    }
    Quit $$$OK
}

/// <p><b>AC-9 Test 1.</b> Calls
/// <method>SessionAgent.UI.AgentConfig.LoadAgentConfig</method>("session-inspection"),
/// parses the returned JSON, asserts <code>found=1</code> and that the
/// returned row has the seeded shape (Provider="openai" per
/// <CLASS>SessionAgent.Config.AgentDefaults</CLASS> OD4 default).</p>
Method TestLoadAgentConfigReturnsSeededRow()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadAgentConfig("session-inspection")
    Do $$$AssertNotEquals(tJson, "", "LoadAgentConfig returned empty string")

    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertTrue($IsObject(tObj), "Returned JSON parses to a %DynamicObject")
    Do $$$AssertTrue('$IsObject(tObj.%Get("error")) && (tObj.%Get("error") = ""), "No error key on happy path")
    Do $$$AssertEquals(tObj.%Get("found"), 1, "found=1 — seeded session-inspection row exists")
    Do $$$AssertEquals(tObj.%Get("Provider"), "openai", "Provider=openai (OD4 seed default)")

    ; MaxTokens is an integer-shape sanity check — exact value comes
    ; from AgentDefaults.GetSeedConfig.
    Do $$$AssertTrue(tObj.%Get("MaxTokens") > 0, "MaxTokens is a positive integer")
    ; Enabled is an integer-shape sanity check (0 or 1) — exact value
    ; depends on operator state and is not asserted here. The test must
    ; not break when an operator has flipped Enabled=1 during
    ; configuration. The seed-default is 0, but live state can drift.
    Set tEnabled = tObj.%Get("Enabled")
    Do $$$AssertTrue((tEnabled = 0) || (tEnabled = 1), "Enabled is a boolean (0 or 1)")
}

/// <p><b>AC-9 Test 2.</b> Calls
/// <method>LoadAgentConfig</method>("nonexistent-agent-name-xyz"),
/// asserts the empty-defaults shape (no exception, structured response,
/// <code>found=0</code>).</p>
Method TestLoadAgentConfigEmptyForUnknownAgent()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadAgentConfig("nonexistent-agent-name-xyz")
    Do $$$AssertNotEquals(tJson, "", "LoadAgentConfig returned empty string")

    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertTrue($IsObject(tObj), "Returned JSON parses to a %DynamicObject")
    Do $$$AssertEquals(tObj.%Get("found"), 0, "found=0 — unknown agent has no row")

    ; Empty-defaults shape per AC-5: Provider=openai, MaxTokens=32000
    ; (hyperscaler-class default per 2026-05-06 manual-test fix bundle —
    ; the prior 4000 was an Ollama-tier holdover that silently truncated
    ; long hyperscaler responses).
    Do $$$AssertEquals(tObj.%Get("Provider"), "openai", "Empty-defaults Provider=openai")
    Do $$$AssertEquals(tObj.%Get("MaxTokens"), 32000, "Empty-defaults MaxTokens=32000 (hyperscaler-class)")
    Do $$$AssertEquals(tObj.%Get("EnvVarName"), "OPENAI_API_KEY", "Empty-defaults EnvVarName=OPENAI_API_KEY")
    Do $$$AssertEquals(tObj.%Get("Enabled"), 0, "Empty-defaults Enabled=0")
}

/// <p><b>AC-9 Test 3.</b> Inserts a transient
/// <code>Ens.Config.Credentials</code> row, calls
/// <method>GetCredentialsList</method>, asserts the returned
/// comma-separated string contains the inserted entry, then deletes
/// the row. The test asserts existence of the inserted entry — NOT
/// the full list shape — because pre-existing credentials in the
/// HSCUSTOM namespace (e.g., the Epic 5 SessionAgentOpenAI /
/// SessionAgentAnthropic / SessionAgentGemini rows) are part of the
/// operator state.</p>
Method TestGetCredentialsListReturnsConfigEntries()
{
    Set tTransientName = "AgentConfigTestCredXyz123"

    ; Pre-clean in case a prior failed test left the row.
    Set tExists = ##class(Ens.Config.Credentials).%ExistsId(tTransientName)
    If tExists {
        Do ##class(Ens.Config.Credentials).%DeleteId(tTransientName)
    }

    ; Insert a transient row using the Ens.Config.Credentials API.
    Set tCred = ##class(Ens.Config.Credentials).%New()
    Set tCred.SystemName = tTransientName
    Set tCred.Username = "test-marker"
    Do tCred.PasswordSet("test-password")
    Set tSC = tCred.%Save()
    Do $$$AssertStatusOK(tSC, "Transient credential saved successfully")
    Do tCred.%Close()

    Try {
        Set tList = ##class(SessionAgent.UI.AgentConfig).GetCredentialsList()
        Do $$$AssertNotEquals(tList, "", "GetCredentialsList returned non-empty string")

        ; The returned list is comma-separated. Split and check our
        ; transient entry is present.
        Set tFound = 0
        For tIdx = 1:1:$Length(tList, ",") {
            If $Piece(tList, ",", tIdx) = tTransientName {
                Set tFound = 1
                Quit
            }
        }
        Do $$$AssertEquals(tFound, 1, "GetCredentialsList contains the transient inserted entry")
    }
    Catch ex {
        ; Even if the assertion fails, we still need to clean up below.
    }

    ; Cleanup — always delete the transient row.
    Do ##class(Ens.Config.Credentials).%DeleteId(tTransientName)
    Do $$$AssertEquals(##class(Ens.Config.Credentials).%ExistsId(tTransientName), 0, "Transient credential cleaned up")
}

/// <p><b>AC-9 Test 4 (added by code review).</b> Regression test for the
/// structural invariant that
/// <method>SessionAgent.UI.AgentConfig.LoadAgentConfig</method>'s JSON
/// envelope must never contain NUL bytes. The bug shape: SQL UPDATE
/// statements that store empty string produce the in-table $Char(0)
/// sentinel; the OREF getter returns it verbatim, so the read-site must
/// normalize to empty string before serializing into the JSON envelope.
/// Without normalization, a literal NUL byte ships in the JSON; the JS
/// client's defaulting fails because the NUL char is truthy in JS, and
/// the form renders a NUL control character in the input.</p>
///
/// <p>This test calls LoadAgentConfig against both the seeded row and
/// the empty-defaults branch and asserts both envelopes are NUL-free.
/// The deeper SQL-UPDATE-produces-$Char(0) condition is verified
/// empirically at code-review time; this test guards the read-site
/// normalization against regression in any subsequent edit.</p>
Method TestLoadAgentConfigJsonHasNoNulBytes()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadAgentConfig("session-inspection")
    Do $$$AssertNotEquals(tJson, "", "LoadAgentConfig returned non-empty envelope")

    Set tHasNul = 0
    Set tNulIdx = 0
    For tIdx = 1:1:$Length(tJson) {
        If $Ascii(tJson, tIdx) = 0 {
            Set tHasNul = 1
            Set tNulIdx = tIdx
            Quit
        }
    }
    Do $$$AssertEquals(tHasNul, 0, "Seeded-row envelope contains no NUL bytes (idx="_tNulIdx_")")

    ; Empty-defaults branch must also be NUL-clean.
    Set tJson2 = ##class(SessionAgent.UI.AgentConfig).LoadAgentConfig("nonexistent-xyz-abc")
    Set tHasNul2 = 0
    For tIdx = 1:1:$Length(tJson2) {
        If $Ascii(tJson2, tIdx) = 0 {
            Set tHasNul2 = 1
            Quit
        }
    }
    Do $$$AssertEquals(tHasNul2, 0, "Empty-defaults envelope contains no NUL bytes")
}

/// <p><b>Story 6.2 AC-5 + AC-6 — hot-config-change verification (NFR-O2)
/// + audit-row provider attribution.</b> Drives
/// <method>SessionAgent.UI.AgentConfig.SaveAgentConfig</method> twice in
/// a single test method, with a
/// <method>SessionAgent.Agent.AgentLoop.RunTurn</method> call between
/// each save. Asserts:</p>
/// <ol>
/// <li>The chat-history rows persist across the config change (FR12 —
/// in-progress conversation continues seamlessly).</li>
/// <li>The audit row written for the second turn carries the NEW
/// provider name — proving the AgentLoop re-read
/// <CLASS>SessionAgent.Config.Agent</CLASS> live (NFR-O2 invariant).</li>
/// <li>No IRIS restart is needed between turns (the test runs in a
/// single <code>%UnitTest</code> invocation against a single IRIS
/// process).</li>
/// </ol>
/// <p><b>Mock used:</b>
/// <CLASS>SessionAgent.Test.AgentConfigMultiProviderMock</CLASS> — overrides
/// <method>GetProviderName</method> so the audit row's Provider column
/// tracks the live <code>Config.Agent.Provider</code> instead of the
/// static <code>"openai"</code> the parent
/// <CLASS>SessionAgent.Test.AgentLoopMockProvider</CLASS> would
/// otherwise emit.</p>
/// <p><b>Self-cleaning:</b> the test captures the original
/// <code>session-inspection</code> Config.Agent state in the OnBefore
/// fixture, mutates via <method>SaveAgentConfig</method> during the
/// test, restores in the OnAfter fixture by writing a final
/// <method>SaveAgentConfig</method> with the captured original
/// values.</p>
Method TestHotConfigChangeAcrossRunTurnInvocations()
{
    Set tSessionKey = "ac6-hot-config-" _ $Job
    Set tAgentName = "session-inspection"

    ; ─────────────────────────────────────────────────────────────
    ; Step 1 — Capture pre-state baseline.
    ; ─────────────────────────────────────────────────────────────
    Set tCfgBefore = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertTrue($IsObject(tCfgBefore), "Pre-state — session-inspection row exists")
    Set tOrigProvider = tCfgBefore.Provider
    Set tOrigModel = tCfgBefore.Model
    Set tOrigEnvVar = tCfgBefore.EnvVarName
    Set tOrigCredName = tCfgBefore.CredentialName
    Set tOrigEnabled = tCfgBefore.Enabled
    Set tOrigEndpoint = tCfgBefore.EndpointUrl
    Set tOrigMaxTokens = tCfgBefore.MaxTokens
    Set tOrigTemp = tCfgBefore.Temperature
    Set tOrigSpo = tCfgBefore.SystemPromptOverride
    Do tCfgBefore.%Close()

    ; ─────────────────────────────────────────────────────────────
    ; Step 2 — Switch via SaveAgentConfig to Provider=openai.
    ; ─────────────────────────────────────────────────────────────
    Set tSaveJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "0.1", "", "1")
    Set tSaveObj = ##class(%DynamicObject).%FromJSON(tSaveJson)
    Do $$$AssertEquals(tSaveObj.%Get("success"), 1, "SaveAgentConfig success — switched to openai")

    ; ─────────────────────────────────────────────────────────────
    ; Step 3 — Install multi-provider mock + run RunTurn.
    ; ─────────────────────────────────────────────────────────────
    Set tResponses1 = ##class(%DynamicArray).%New()
    Do tResponses1.%Push(##class(SessionAgent.Test.AgentLoopTestBase).BuildOpenAiResponse("first turn — openai provider"))
    Set tCfg = ##class(%DynamicObject).%New()
    Do tCfg.%Set("responses", tResponses1)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentConfigMultiProviderMock", tCfg.%ToJSON())

    Set tResult1 = ##class(SessionAgent.Agent.AgentLoop).RunTurn(tAgentName, tSessionKey, "tester", "first turn")
    Do $$$AssertTrue($IsObject(tResult1), "Turn 1 returned TurnResult OREF")

    ; ─────────────────────────────────────────────────────────────
    ; Step 4 — AC-6 probe — most-recent audit row Provider = openai.
    ; ─────────────────────────────────────────────────────────────
    Set tHist1 = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(tAgentName, tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist1), "Chat.History row persisted after turn 1")
    Set tHistId = tHist1.%Id()
    Do tHist1.%Close()

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT TOP 1 %EXACT(Provider) AS Prov FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ? ORDER BY ID DESC")
    Set tRs = tStmt.%Execute(tHistId)
    Set tProv1 = "<no-row>"
    If tRs.%Next() Set tProv1 = tRs.%Get("Prov")
    Do tRs.%Close()
    Do $$$AssertEquals(tProv1, "openai", "AC-6 turn-1 audit row Provider = openai (got: " _ tProv1 _ ")")

    ; ─────────────────────────────────────────────────────────────
    ; Step 5 — Switch via SaveAgentConfig to Provider=anthropic.
    ; The radio-aware credential clearing must NOT corrupt the test
    ; setup — the EnvSecret resolver still reads PATH on the fast path
    ; (the env-var "PATH" is always defined on Windows + POSIX).
    ; ─────────────────────────────────────────────────────────────
    Set tSaveJson2 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "anthropic", "claude-sonnet-4-5", "", "env",
        "PATH", "", "4000", "0.1", "", "1")
    Set tSaveObj2 = ##class(%DynamicObject).%FromJSON(tSaveJson2)
    Do $$$AssertEquals(tSaveObj2.%Get("success"), 1, "SaveAgentConfig success — switched to anthropic")

    ; ─────────────────────────────────────────────────────────────
    ; Step 6 — Run RunTurn again with the same mock — same chat
    ; session key so chat history is preserved (FR12).
    ; ─────────────────────────────────────────────────────────────
    Set tResponses2 = ##class(%DynamicArray).%New()
    Do tResponses2.%Push(##class(SessionAgent.Test.AgentLoopTestBase).BuildOpenAiResponse("second turn — anthropic provider"))
    Set tCfg2 = ##class(%DynamicObject).%New()
    Do tCfg2.%Set("responses", tResponses2)
    Do ##class(SessionAgent.Agent.ProviderOverride).SetOverride("SessionAgent.Test.AgentConfigMultiProviderMock", tCfg2.%ToJSON())

    Set tResult2 = ##class(SessionAgent.Agent.AgentLoop).RunTurn(tAgentName, tSessionKey, "tester", "second turn")
    Do $$$AssertTrue($IsObject(tResult2), "Turn 2 returned TurnResult OREF")

    ; ─────────────────────────────────────────────────────────────
    ; Step 7 — AC-5 chat-history preservation + AC-6 turn-2 audit row.
    ; ─────────────────────────────────────────────────────────────
    Set tHist2 = ##class(SessionAgent.Chat.History).ConvKeyIdxOpen(tAgentName, tSessionKey, "tester")
    Do $$$AssertTrue($IsObject(tHist2), "AC-5 — chat history row PRESERVED across config change")
    Do $$$AssertEquals(tHist2.%Id(), tHistId, "AC-5 — same chat-history row ID across turns (in-progress conversation continues)")
    Do tHist2.%Close()

    Set tRs2 = tStmt.%Execute(tHistId)
    Set tProv2 = "<no-row>"
    If tRs2.%Next() Set tProv2 = tRs2.%Get("Prov")
    Do tRs2.%Close()
    Do $$$AssertEquals(tProv2, "anthropic", "AC-6 turn-2 audit row Provider = anthropic (got: " _ tProv2 _ ") — proves NFR-O2 hot-config-change took effect")

    ; ─────────────────────────────────────────────────────────────
    ; Step 8 — Assert ≥ 2 audit rows (one per turn) — proves both
    ; turns wrote audit telemetry without IRIS restart.
    ; ─────────────────────────────────────────────────────────────
    Set tStmtCt = ##class(%SQL.Statement).%New()
    Do tStmtCt.%Prepare("SELECT COUNT(*) AS cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(ChatHistoryId) = ?")
    Set tRsCt = tStmtCt.%Execute(tHistId)
    Set tCount = -1
    If tRsCt.%Next() Set tCount = +tRsCt.%Get("cnt")
    Do tRsCt.%Close()
    Do $$$AssertTrue(tCount >= 2, "AC-5 — ≥ 2 audit rows for the same chat-history (one per turn) — got: " _ tCount)

    ; ─────────────────────────────────────────────────────────────
    ; Step 9 — Self-cleaning: restore pre-state baseline.
    ; ─────────────────────────────────────────────────────────────
    Do ##class(SessionAgent.Agent.ProviderOverride).ClearOverride()
    Set tCredType = $Select(tOrigCredName '= "" : "creds", 1 : "env")
    ; Restore via SaveAgentConfig — exercises the same code path the
    ; UI uses, ensuring restoration is round-trip-safe.
    Set tEnabledStr = $Select(tOrigEnabled = 1 : "1", 1 : "0")
    Set tRestoreJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, tOrigProvider, tOrigModel, tOrigEndpoint, tCredType,
        tOrigEnvVar, tOrigCredName, tOrigMaxTokens, tOrigTemp, tOrigSpo, tEnabledStr)
    Set tRestoreObj = ##class(%DynamicObject).%FromJSON(tRestoreJson)
    Do $$$AssertEquals(tRestoreObj.%Get("success"), 1, "Pre-state restored via SaveAgentConfig")

    ; Sweep the test chat-history row.
    Set tStmtDel = ##class(%SQL.Statement).%New()
    Do tStmtDel.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(SessionKey) = ?")
    Do tStmtDel.%Execute(tSessionKey)
}

/// <p><b>Story 6.2 AC-7 case 1 — unknown agent.</b> SaveAgentConfig with
/// pAgentName="nonexistent-agent" must reject with errors[0].field =
/// "agentSelect".</p>
Method TestSaveAgentConfigRejectsUnknownAgent()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "nonexistent-agent", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "Unknown agent rejected (success=false)")
    Set tErrors = tObj.%Get("errors")
    Do $$$AssertTrue($IsObject(tErrors), "errors[] is an array")
    Do $$$AssertTrue(tErrors.%Size() > 0, "At least one error reported")
    Set tErr0 = tErrors.%Get(0)
    Do $$$AssertEquals(tErr0.%Get("field"), "agentSelect", "errors[0].field=agentSelect")
}

/// <p><b>Story 6.2 AC-7 case 2 — unknown provider.</b></p>
Method TestSaveAgentConfigRejectsUnknownProvider()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "grok", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "Unknown provider rejected")
    Set tErrors = tObj.%Get("errors")
    Set tErr0 = tErrors.%Get(0)
    Do $$$AssertEquals(tErr0.%Get("field"), "providerSelect", "errors[0].field=providerSelect")
}

/// <p><b>Story 6.2 AC-7 case 3 — bad max tokens (negative + over-cap).</b></p>
Method TestSaveAgentConfigRejectsBadMaxTokens()
{
    ; Negative — but pMaxTokens is %String, validator requires non-negative numeric.
    Set tJson1 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "-50", "0.1", "", "1")
    Set tObj1 = ##class(%DynamicObject).%FromJSON(tJson1)
    Do $$$AssertEquals(tObj1.%Get("success"), 0, "Negative max tokens rejected")
    Set tErr1 = tObj1.%Get("errors").%Get(0)
    Do $$$AssertEquals(tErr1.%Get("field"), "maxTokensText", "errors[0].field=maxTokensText for negative max-tokens")

    ; Over-cap.
    Set tJson2 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "99999", "0.1", "", "1")
    Set tObj2 = ##class(%DynamicObject).%FromJSON(tJson2)
    Do $$$AssertEquals(tObj2.%Get("success"), 0, "Over-cap max tokens rejected")
    Set tErr2 = tObj2.%Get("errors").%Get(0)
    Do $$$AssertEquals(tErr2.%Get("field"), "maxTokensText", "errors[0].field=maxTokensText for over-cap max-tokens")
}

/// <p><b>Story 6.2 AC-7 case 4 — bad temperature (negative + over-2).</b></p>
Method TestSaveAgentConfigRejectsBadTemperature()
{
    Set tJson1 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "-0.5", "", "1")
    Set tObj1 = ##class(%DynamicObject).%FromJSON(tJson1)
    Do $$$AssertEquals(tObj1.%Get("success"), 0, "Negative temperature rejected")
    Set tErrors1 = tObj1.%Get("errors")
    Set tFoundTemp1 = 0
    For tI = 0:1:tErrors1.%Size()-1 {
        If tErrors1.%Get(tI).%Get("field") = "temperatureText" Set tFoundTemp1 = 1
    }
    Do $$$AssertEquals(tFoundTemp1, 1, "errors[] contains temperatureText for negative temp")

    Set tJson2 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "3", "", "1")
    Set tObj2 = ##class(%DynamicObject).%FromJSON(tJson2)
    Do $$$AssertEquals(tObj2.%Get("success"), 0, "Over-2 temperature rejected")
    Set tErrors2 = tObj2.%Get("errors")
    Set tFoundTemp2 = 0
    For tI = 0:1:tErrors2.%Size()-1 {
        If tErrors2.%Get(tI).%Get("field") = "temperatureText" Set tFoundTemp2 = 1
    }
    Do $$$AssertEquals(tFoundTemp2, 1, "errors[] contains temperatureText for over-2 temp")
}

/// <p><b>Story 6.2 AC-7 reviewer addition — invalid credTypeRadio rejected.</b>
/// The original Story 6.2 dev shipped without a domain guard on
/// <var>pCredTypeRadio</var> — anything that wasn't <code>"env"</code> fell
/// through to the Else branch of the persistence radio dispatch and was
/// silently treated as <code>"creds"</code>, clearing
/// <code>EnvVarName</code> and overwriting <code>CredentialName</code>.
/// The reviewer caught this in the empirical pass with
/// <code>pCredTypeRadio="banana"</code> — it returned
/// <code>{"success":true,"message":"Saved"}</code> and corrupted the row.
/// The fix adds a domain guard (Rule 4b) that rejects anything other
/// than the two valid radio values; this test enforces it.</p>
Method TestSaveAgentConfigRejectsInvalidCredTypeRadio()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "banana",
        "PATH", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "Invalid credTypeRadio 'banana' rejected")
    Set tErrors = tObj.%Get("errors")
    Set tFound = 0
    For tI = 0:1:tErrors.%Size()-1 {
        If tErrors.%Get(tI).%Get("field") = "credTypeRadio" Set tFound = 1
    }
    Do $$$AssertEquals(tFound, 1, "errors[] contains credTypeRadio domain failure for unexpected value")

    ; Also reject empty credTypeRadio.
    Set tJson2 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "",
        "PATH", "", "4000", "0.1", "", "1")
    Set tObj2 = ##class(%DynamicObject).%FromJSON(tJson2)
    Do $$$AssertEquals(tObj2.%Get("success"), 0, "Empty credTypeRadio rejected")
}

/// <p><b>Story 6.2 AC-7 case 5 — env requires EnvVarName.</b></p>
Method TestSaveAgentConfigEnvRequiresEnvVarName()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "env with empty EnvVarName rejected")
    Set tErrors = tObj.%Get("errors")
    Set tFound = 0
    For tI = 0:1:tErrors.%Size()-1 {
        If tErrors.%Get(tI).%Get("field") = "envVarText" Set tFound = 1
    }
    Do $$$AssertEquals(tFound, 1, "errors[] contains envVarText")
}

/// <p><b>Story 6.2 AC-7 case 6 — creds requires CredentialName.</b></p>
Method TestSaveAgentConfigCredsRequiresCredentialName()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "creds",
        "", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "creds with empty CredentialName rejected")
    Set tErrors = tObj.%Get("errors")
    Set tFound = 0
    For tI = 0:1:tErrors.%Size()-1 {
        If tErrors.%Get(tI).%Get("field") = "credCombo" Set tFound = 1
    }
    Do $$$AssertEquals(tFound, 1, "errors[] contains credCombo")
}

/// <p><b>Story 6.2 AC-7 case 7 — openai-compatible requires EndpointUrl.</b></p>
Method TestSaveAgentConfigOpenAICompatRequiresEndpointUrl()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai-compatible", "qwen2.5:32b", "", "env",
        "PATH", "", "4000", "0.1", "", "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "openai-compatible without endpoint rejected")
    Set tErrors = tObj.%Get("errors")
    Set tFound = 0
    For tI = 0:1:tErrors.%Size()-1 {
        If tErrors.%Get(tI).%Get("field") = "endpointUrlText" Set tFound = 1
    }
    Do $$$AssertEquals(tFound, 1, "errors[] contains endpointUrlText")
}

/// <p><b>Story 6.2 AC-7 case 8 — radio-aware clearing rule.</b> First save
/// with credTypeRadio="env" and EnvVarName="OPENAI_API_KEY". Second save
/// with credTypeRadio="creds" and CredentialName="OtherCred". After the
/// second save, EnvVarName MUST be cleared to "" — the OPPOSITE field is
/// always cleared (NFR-S2 schema discipline).</p>
Method TestSaveAgentConfigClearsUnusedCredentialField()
{
    Set tAgentName = "session-inspection"
    ; Capture original to restore after the test.
    Set tCfg0 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Set tOrigEnv = tCfg0.EnvVarName
    Set tOrigCred = tCfg0.CredentialName
    Do tCfg0.%Close()

    ; Save with env path.
    Set tJson1 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "openai", "gpt-4.1-mini", "", "env",
        "OPENAI_API_KEY", "", "4000", "0.1", "", "1")
    Set tObj1 = ##class(%DynamicObject).%FromJSON(tJson1)
    Do $$$AssertEquals(tObj1.%Get("success"), 1, "First save (env) succeeded")
    Set tCfg1 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertEquals(tCfg1.EnvVarName, "OPENAI_API_KEY", "EnvVarName set on env-path save")
    Do $$$AssertEquals(tCfg1.CredentialName, "", "CredentialName cleared on env-path save")
    Do tCfg1.%Close()

    ; Save with creds path — EnvVarName MUST be cleared.
    Set tJson2 = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "openai", "gpt-4.1-mini", "", "creds",
        "", "SessionAgentOpenAI", "4000", "0.1", "", "1")
    Set tObj2 = ##class(%DynamicObject).%FromJSON(tJson2)
    Do $$$AssertEquals(tObj2.%Get("success"), 1, "Second save (creds) succeeded")
    Set tCfg2 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertEquals(tCfg2.EnvVarName, "", "EnvVarName CLEARED after switching to creds (NFR-S2)")
    Do $$$AssertEquals(tCfg2.CredentialName, "SessionAgentOpenAI", "CredentialName set on creds-path save")
    Do tCfg2.%Close()

    ; Restore.
    Set tRestoreType = $Select(tOrigCred '= "" : "creds", 1 : "env")
    Do ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "openai", "gpt-4.1-mini", "", tRestoreType,
        tOrigEnv, tOrigCred, "4000", "0.1", "", "1")
}

/// <p><b>Story 6.2 AC-7 case 9 — system prompt over 8192 chars rejected.</b></p>
Method TestSaveAgentConfigSystemPromptOver8192Rejected()
{
    Set tBigPrompt = $Justify("", 9000)
    Set tBigPrompt = $Translate(tBigPrompt, " ", "X")
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        "session-inspection", "openai", "gpt-4.1-mini", "", "env",
        "PATH", "", "4000", "0.1", tBigPrompt, "1")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 0, "9000-char prompt rejected")
    Set tErrors = tObj.%Get("errors")
    Set tFound = 0
    For tI = 0:1:tErrors.%Size()-1 {
        If tErrors.%Get(tI).%Get("field") = "systemPromptText" Set tFound = 1
    }
    Do $$$AssertEquals(tFound, 1, "errors[] contains systemPromptText for over-cap prompt")
}

/// <p><b>Story 6.2 AC-7 case 10 — creates row if missing.</b> Deletes the
/// row, then saves with valid inputs, asserts a new row was created.</p>
Method TestSaveAgentConfigCreatesRowIfMissing()
{
    Set tAgentName = "message-search"
    ; Capture original for restoration.
    Set tCfg0 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Set tOrigProvider = ""
    Set tOrigModel = ""
    Set tOrigEnvVar = ""
    Set tOrigCredName = ""
    Set tOrigEnabled = 0
    If $IsObject(tCfg0) {
        Set tOrigProvider = tCfg0.Provider
        Set tOrigModel = tCfg0.Model
        Set tOrigEnvVar = tCfg0.EnvVarName
        Set tOrigCredName = tCfg0.CredentialName
        Set tOrigEnabled = tCfg0.Enabled
        Do tCfg0.%Close()

        ; Delete the existing row.
        Set tStmt = ##class(%SQL.Statement).%New()
        Do tStmt.%Prepare("DELETE FROM SessionAgent_Config.Agent WHERE %EXACT(AgentName) = ?")
        Do tStmt.%Execute(tAgentName)
    }

    ; Confirm row is gone.
    Set tCfgGone = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertTrue('$IsObject(tCfgGone), "Pre-condition — row absent before save")

    ; Save with valid inputs.
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, "openai", "gpt-4.1-mini", "", "env",
        "OPENAI_API_KEY", "", "4000", "0.1", "", "0")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 1, "Save creates new row when missing")

    ; Confirm row was created.
    Set tCfgNew = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertTrue($IsObject(tCfgNew), "New row created (open-or-create path)")
    Do $$$AssertEquals(tCfgNew.AgentName, tAgentName, "AgentName persisted on create")
    Do $$$AssertEquals(tCfgNew.Provider, "openai", "Provider persisted on create")
    Do tCfgNew.%Close()

    ; Restore original — if we captured one, write it back; if not, leave the
    ; new row in place (the message-search seed row is idempotent re-seedable).
    If tOrigProvider '= "" {
        Set tRestoreType = $Select(tOrigCredName '= "" : "creds", 1 : "env")
        Set tEnabledStr = $Select(tOrigEnabled = 1 : "1", 1 : "0")
        Do ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
            tAgentName, tOrigProvider, tOrigModel, "", tRestoreType,
            tOrigEnvVar, tOrigCredName, "4000", "0.1", "", tEnabledStr)
    }
}

/// <p><b>Story 10.8 AC-2 Test 1.</b>
/// <method>TestSearchVariantPrePopulatesRetentionDays</method> — call
/// <method>SessionAgent.UI.AgentConfig.LoadAgentConfig</method>("message-search"),
/// parse the JSON envelope, assert the
/// <code>SearchChatRetentionDays</code> field is present and equals
/// the seeded default value (30 per Config.Agent InitialExpression).
/// The field is Search-Agent specific (Inspection ignores it); the
/// test exercises the LoadAgentConfig contract that the message-search
/// row carries the column.</p>
Method TestSearchVariantPrePopulatesRetentionDays()
{
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadAgentConfig("message-search")
    Do $$$AssertNotEquals(tJson, "", "LoadAgentConfig returned non-empty for message-search")

    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertTrue($IsObject(tObj), "Returned JSON parses to a %DynamicObject")
    Do $$$AssertEquals(tObj.%Get("found"), 1, "message-search seed row resolves (found=1)")

    Set tRetention = +tObj.%Get("SearchChatRetentionDays")
    Do $$$AssertTrue(tRetention >= 1, "SearchChatRetentionDays is a positive integer (>= 1)")
    ; Default is 30 per Config.Agent.SearchChatRetentionDays InitialExpression
    ; (architecture row OD4). The seed path keeps it at the default; this
    ; test asserts the canonical contract.
    Do $$$AssertEquals(tRetention, 30, "SearchChatRetentionDays defaults to 30 per architecture OD4")
    Quit
}

/// <p><b>Story 10.11 AC-5 Test.</b>
/// <method>TestProviderRotationCascadesModelCredential</method> — invokes the
/// new <method>SessionAgent.UI.AgentConfig.LoadProviderDefaults</method>
/// ZenMethod for each of the four supported providers and asserts the
/// returned canonical triple matches
/// <method>SessionAgent.Config.AgentDefaults.GetCanonicalDefaults</method>.
/// This guards the per-provider canonical mapping against accidental
/// drift in either class — if the form-side cascade and the
/// AgentDefaults canonical helper disagree, the form would silently
/// persist incoherent (Provider, Model, CredentialName) triples on
/// rotation (the Story 10.10-walkthrough-surfaced bug shape).</p>
///
/// <p>The test exercises the JSON-envelope contract directly (not the
/// form's client-side cascade) — the JS-side cascade is verified by the
/// chrome-devtools-mcp walkthrough captured in the story's empirical
/// battery. The assertion shape mirrors the per-provider table in
/// <method>GetCanonicalDefaults</method> doc-comment.</p>
Method TestProviderRotationCascadesModelCredential()
{
    ; openai.
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadProviderDefaults("openai")
    Do $$$AssertNotEquals(tJson, "", "LoadProviderDefaults('openai') returned non-empty")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("model"), "gpt-4.1-mini", "openai canonical model = gpt-4.1-mini")
    Do $$$AssertEquals(tObj.%Get("credentialName"), "SessionAgentOpenAI", "openai canonical credentialName = SessionAgentOpenAI")
    Do $$$AssertEquals(tObj.%Get("envVarName"), "OPENAI_API_KEY", "openai canonical envVarName = OPENAI_API_KEY")

    ; anthropic.
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadProviderDefaults("anthropic")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("model"), "claude-haiku-4-5-20251001", "anthropic canonical model = claude-haiku-4-5-20251001")
    Do $$$AssertEquals(tObj.%Get("credentialName"), "SessionAgentAnthropic", "anthropic canonical credentialName = SessionAgentAnthropic")
    Do $$$AssertEquals(tObj.%Get("envVarName"), "ANTHROPIC_API_KEY", "anthropic canonical envVarName = ANTHROPIC_API_KEY")

    ; gemini.
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadProviderDefaults("gemini")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("model"), "gemini-2.5-flash", "gemini canonical model = gemini-2.5-flash")
    Do $$$AssertEquals(tObj.%Get("credentialName"), "SessionAgentGemini", "gemini canonical credentialName = SessionAgentGemini")
    Do $$$AssertEquals(tObj.%Get("envVarName"), "GEMINI_API_KEY", "gemini canonical envVarName = GEMINI_API_KEY")

    ; openai-compatible — empty cred + empty env (operator-supplied).
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadProviderDefaults("openai-compatible")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("model"), "qwen2.5:32b", "openai-compatible canonical model = qwen2.5:32b")
    Do $$$AssertEquals(tObj.%Get("credentialName"), "", "openai-compatible canonical credentialName empty")
    Do $$$AssertEquals(tObj.%Get("envVarName"), "", "openai-compatible canonical envVarName empty")

    ; Unknown provider falls through to openai canonical (defense-in-depth).
    Set tJson = ##class(SessionAgent.UI.AgentConfig).LoadProviderDefaults("nonexistent-provider-xyz")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("model"), "gpt-4.1-mini", "unknown provider falls through to openai canonical")
    Quit
}

/// <p><b>Story 10.8 AC-2 Test 2.</b>
/// <method>TestSaveHandlerPersistsRetentionDays</method> — call
/// <method>SessionAgent.UI.AgentConfig.SaveAgentConfig</method> with a
/// non-default <code>SearchChatRetentionDays</code> value (45), confirm
/// the success envelope, then re-read the row and assert the value
/// persisted. Restores the original value at the end.</p>
Method TestSaveHandlerPersistsRetentionDays()
{
    Set tAgentName = "message-search"

    ; Capture original retention for restoration.
    Set tCfg0 = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Set tOrigRetention = 30
    If $IsObject(tCfg0) {
        Set tOrigRetention = +tCfg0.SearchChatRetentionDays
        If tOrigRetention < 1 Set tOrigRetention = 30
        Set tOrigProvider = tCfg0.Provider
        Set tOrigModel = tCfg0.Model
        Set tOrigEnabled = tCfg0.Enabled
        Do tCfg0.%Close()
    } Else {
        Set tOrigProvider = "openai"
        Set tOrigModel = "gpt-4.1-mini"
        Set tOrigEnabled = 0
    }

    ; Save with retention=45.
    Set tEnabledStr = $Select(tOrigEnabled = 1 : "1", 1 : "0")
    Set tJson = ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, tOrigProvider, tOrigModel, "", "env",
        "OPENAI_API_KEY", "", "4000", "0.1", "", tEnabledStr, "45")
    Set tObj = ##class(%DynamicObject).%FromJSON(tJson)
    Do $$$AssertEquals(tObj.%Get("success"), 1, "Save with retention=45 succeeds (got " _ tJson _ ")")

    ; Re-read the row and assert the value persisted.
    Set tCfgNew = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tAgentName)
    Do $$$AssertTrue($IsObject(tCfgNew), "Row resolves after save")
    If $IsObject(tCfgNew) {
        Do $$$AssertEquals(+tCfgNew.SearchChatRetentionDays, 45, "SearchChatRetentionDays persists as 45 (Story 10.8 AC-2)")
        Do tCfgNew.%Close()
    }

    ; Restore original retention.
    Do ##class(SessionAgent.UI.AgentConfig).SaveAgentConfig(
        tAgentName, tOrigProvider, tOrigModel, "", "env",
        "OPENAI_API_KEY", "", "4000", "0.1", "", tEnabledStr, tOrigRetention)
    Quit
}

}
