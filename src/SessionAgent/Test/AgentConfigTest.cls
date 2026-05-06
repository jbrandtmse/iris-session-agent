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

    ; Empty-defaults shape per AC-5: Provider=openai, MaxTokens=4000, etc.
    Do $$$AssertEquals(tObj.%Get("Provider"), "openai", "Empty-defaults Provider=openai")
    Do $$$AssertEquals(tObj.%Get("MaxTokens"), 4000, "Empty-defaults MaxTokens=4000")
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

}
