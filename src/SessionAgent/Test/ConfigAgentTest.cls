/// <p>Unit tests for <CLASS>SessionAgent.Config.Agent</CLASS> (schema
/// shape + NFR-S2 schema discipline + unique index),
/// <CLASS>SessionAgent.Config.AgentDefaults</CLASS> (seed-config defaults
/// + system-prompt strings), and
/// <method>SessionAgent.Installer.SeedDefaultAgentConfigs</method>
/// (idempotency + persistence round-trip), per Story 2.4 AC-4.</p>
///
/// <p>Ten test methods, all assertions via <code>$$$Assert*</code> macros
/// (never <code>..AssertX(...)</code> per project rule §"Macro vs Method
/// Distinction"), no underscores in method names, file ≤ 500 lines.</p>
///
/// <p><b>Test isolation strategy.</b> The seeding tests blow away the
/// <code>^SessionAgent.Config.AgentD</code> data global before each test
/// in <method>OnBeforeOneTest</method> so a prior install-seeded state
/// does not contaminate the assertions. Cleanup in
/// <method>OnAfterOneTest</method> kills the global again so a subsequent
/// <method>SessionAgent.Installer.Install</method> call can re-seed
/// without colliding. The other (read-only schema introspection) tests
/// do not depend on the data global.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../planning-artifacts/epics.md">epics.md Story 2.4</a>
/// (lines 798–821) — AC source.</li>
/// <li><a href="../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list and constructor pattern.</li>
/// </ul>
Class SessionAgent.Test.ConfigAgentTest Extends %UnitTest.TestCase
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

/// <p>Per-test fixture: kill the persistent class's data global so each
/// seeding test starts from an empty extent. Read-only schema-
/// introspection tests are unaffected by the kill (they query
/// <code>%Dictionary.*</code>, not the data extent).</p>
Method OnBeforeOneTest() As %Status
{
    Kill ^SessionAgent.Config.AgentD
    Kill ^SessionAgent.Config.AgentI
    Quit $$$OK
}

/// <p>Per-test cleanup: kill the data global again so a follow-on
/// <method>SessionAgent.Installer.Install</method> call (e.g., a manual
/// re-install or a downstream test) can re-seed cleanly.</p>
Method OnAfterOneTest() As %Status
{
    Try {
        Kill ^SessionAgent.Config.AgentD
        Kill ^SessionAgent.Config.AgentI
    } Catch {}
    Quit $$$OK
}

/// <p>End-of-class restoration (Story 3.0 carry-forward fix): re-seed
/// the two Config.Agent rows AND restore any operator-customized
/// fields captured at the start of the class (Enabled, CredentialName,
/// EnvVarName, EndpointUrl). Without this, the per-test kills above
/// leave the global empty after the last test method (breaking the
/// suite) AND any pre-test live operator config (e.g., CredentialName
/// pointing at an operator-supplied credential, Enabled=1) gets
/// silently nuked. Capturing in <method>OnBeforeAllTests</method>
/// preserves live state across test runs.</p>
Method OnAfterAllTests() As %Status
{
    Try {
        ; Re-seed both rows with default shape (idempotent — skips if present).
        Do ##class(SessionAgent.Installer).SeedDefaultAgentConfigs()
        ; Restore captured operator-side fields per agent. The pre-state
        ; map lives in ^||SessionAgentTestConfigPreState{name} where each
        ; node is $LB(Enabled, CredentialName, EnvVarName, EndpointUrl).
        For tName = "session-inspection", "message-search" {
            If $Data(^||SessionAgentTestConfigPreState(tName)) {
                Set tList = ^||SessionAgentTestConfigPreState(tName)
                Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tName)
                If $IsObject(tCfg) {
                    Set tCfg.Enabled = $List(tList, 1)
                    Set tCfg.CredentialName = $List(tList, 2)
                    Set tCfg.EnvVarName = $List(tList, 3)
                    Set tCfg.EndpointUrl = $List(tList, 4)
                    Do tCfg.%Save()
                }
            }
        }
        Kill ^||SessionAgentTestConfigPreState
    } Catch {}
    Quit $$$OK
}

/// <p>Capture operator-side fields BEFORE the destructive per-test
/// kills run, so <method>OnAfterAllTests</method> can restore them.
/// Stores in process-private global keyed by agent name. No-op if no
/// row exists for an agent (first install, etc.).</p>
Method OnBeforeAllTests() As %Status
{
    Try {
        For tName = "session-inspection", "message-search" {
            Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(tName)
            If $IsObject(tCfg) {
                Set ^||SessionAgentTestConfigPreState(tName) = $ListBuild(
                    tCfg.Enabled, tCfg.CredentialName, tCfg.EnvVarName, tCfg.EndpointUrl)
            }
        }
    } Catch {}
    Quit $$$OK
}

/// <p>AC-4 #1 — schema-presence check. Verifies each of the 12 required
/// properties exists on <CLASS>SessionAgent.Config.Agent</CLASS> with the
/// correct type per AC-1 table. Catches schema drift early — if a future
/// edit drops or renames a property, the schema-shape AC fails before
/// any downstream consumer breaks.</p>
Method TestSchemaPropertiesPresent()
{
    ; Property name → expected type (per AC-1 table). Empirically verified:
    ; %Dictionary.PropertyDefinition.Type returns the short form (%String, etc.),
    ; not the fully-qualified form (%Library.String).
    Set tExpected = ""
    Set tExpected("AgentName") = "%String"
    Set tExpected("Provider") = "%String"
    Set tExpected("Model") = "%String"
    Set tExpected("MaxTokens") = "%Integer"
    Set tExpected("Temperature") = "%Numeric"
    Set tExpected("SystemPromptOverride") = "%String"
    Set tExpected("CredentialName") = "%String"
    Set tExpected("EnvVarName") = "%String"
    Set tExpected("EndpointUrl") = "%String"
    Set tExpected("ReadOnly") = "%Boolean"
    Set tExpected("Enabled") = "%Boolean"
    Set tExpected("SearchChatRetentionDays") = "%Integer"

    Set tName = ""
    For {
        Set tName = $Order(tExpected(tName))
        Quit:tName=""
        Set tCompoundId = "SessionAgent.Config.Agent||" _ tName
        Do $$$AssertTrue(##class(%Dictionary.PropertyDefinition).%ExistsId(tCompoundId), "Property "_tName_" must exist on SessionAgent.Config.Agent")
        Set tProp = ##class(%Dictionary.PropertyDefinition).%OpenId(tCompoundId)
        If $IsObject(tProp) {
            Do $$$AssertEquals(tProp.Type, tExpected(tName), "Property "_tName_" type must be "_tExpected(tName))
        }
    }
    Quit
}

/// <p>AC-4 #2 — NFR-S2 schema discipline. Asserts that no
/// <code>ApiKey</code> property has been added to
/// <CLASS>SessionAgent.Config.Agent</CLASS>. The class stores credential
/// <i>references</i> (<code>CredentialName</code>, <code>EnvVarName</code>)
/// — never the resolved key value. Empirical guard against accidental
/// re-introduction.</p>
Method TestSchemaHasNoApiKey()
{
    Do $$$AssertEquals(##class(%Dictionary.PropertyDefinition).%ExistsId("SessionAgent.Config.Agent||ApiKey"), 0, "ApiKey property MUST NOT exist on SessionAgent.Config.Agent (NFR-S2)")
    Quit
}

/// <p>AC-4 #3 — unique-index check. Asserts the
/// <code>AgentNameIdx</code> index is declared with
/// <code>Unique=1</code>. The Installer's idempotency check
/// (<code>AgentNameIdxExists</code>) only protects against duplicate
/// inserts on the seeding path; the unique constraint is the
/// authoritative database-level guard against duplicate-row creation
/// from any other code path.</p>
Method TestAgentNameIdxIsUnique()
{
    Set tIdx = ##class(%Dictionary.IndexDefinition).%OpenId("SessionAgent.Config.Agent||AgentNameIdx")
    Do $$$AssertTrue($IsObject(tIdx), "AgentNameIdx must exist on SessionAgent.Config.Agent")
    If $IsObject(tIdx) {
        Do $$$AssertEquals(tIdx.Unique, 1, "AgentNameIdx must be declared Unique")
    }
    Quit
}

/// <p>AC-4 #4 — seed-config defaults for the inspection agent. Verifies
/// the OD4 default shape returned by
/// <method>SessionAgent.Config.AgentDefaults.GetSeedConfig</method> for
/// <code>session-inspection</code>.</p>
Method TestGetSeedConfigInspectionDefaults()
{
    Set tAgent = ##class(SessionAgent.Config.AgentDefaults).GetSeedConfig("session-inspection")
    Do $$$AssertTrue($IsObject(tAgent), "GetSeedConfig must return an instance for session-inspection")
    If $IsObject(tAgent) {
        Do $$$AssertEquals(tAgent.AgentName, "session-inspection", "AgentName")
        Do $$$AssertEquals(tAgent.Provider, "openai", "Provider=openai")
        Do $$$AssertEquals(tAgent.Model, "gpt-4.1-mini", "Model=gpt-4.1-mini")
        Do $$$AssertEquals(tAgent.MaxTokens, 4096, "MaxTokens=4096")
        Do $$$AssertEquals(tAgent.Temperature, 0.0, "Temperature=0.0")
        Do $$$AssertEquals(tAgent.EnvVarName, "OPENAI_API_KEY", "EnvVarName=OPENAI_API_KEY")
        Do $$$AssertEquals(tAgent.Enabled, 0, "Enabled=0 (operator opt-in)")
        Do $$$AssertEquals(tAgent.ReadOnly, 1, "ReadOnly=1 (L4 invariant)")
        Do $$$AssertEquals(tAgent.SearchChatRetentionDays, 30, "SearchChatRetentionDays=30")
    }
    Quit
}

/// <p>AC-4 #5 — seed-config defaults for the search agent. Same shape as
/// inspection (both seeded with OpenAI defaults per OD4); only
/// <code>AgentName</code> differs.</p>
Method TestGetSeedConfigSearchDefaults()
{
    Set tAgent = ##class(SessionAgent.Config.AgentDefaults).GetSeedConfig("message-search")
    Do $$$AssertTrue($IsObject(tAgent), "GetSeedConfig must return an instance for message-search")
    If $IsObject(tAgent) {
        Do $$$AssertEquals(tAgent.AgentName, "message-search", "AgentName")
        Do $$$AssertEquals(tAgent.Provider, "openai", "Provider=openai")
        Do $$$AssertEquals(tAgent.Model, "gpt-4.1-mini", "Model=gpt-4.1-mini")
        Do $$$AssertEquals(tAgent.MaxTokens, 4096, "MaxTokens=4096")
        Do $$$AssertEquals(tAgent.Temperature, 0.0, "Temperature=0.0")
        Do $$$AssertEquals(tAgent.EnvVarName, "OPENAI_API_KEY", "EnvVarName=OPENAI_API_KEY")
        Do $$$AssertEquals(tAgent.Enabled, 0, "Enabled=0 (operator opt-in)")
        Do $$$AssertEquals(tAgent.ReadOnly, 1, "ReadOnly=1 (L4 invariant)")
        Do $$$AssertEquals(tAgent.SearchChatRetentionDays, 30, "SearchChatRetentionDays=30")
    }
    Quit
}

/// <p>AC-4 #6 — unknown-agent fallthrough.
/// <method>GetSeedConfig</method> must return <code>$$$NULLOREF</code>
/// for any unrecognized agent name; <code>$IsObject(result)</code>
/// returns 0. Locks the contract the Installer relies on for safety.</p>
Method TestGetSeedConfigUnknownAgentReturnsNull()
{
    Set tResult = ##class(SessionAgent.Config.AgentDefaults).GetSeedConfig("unknown-agent")
    Do $$$AssertEquals($IsObject(tResult), 0, "Unknown agent name must yield $$$NULLOREF")
    Quit
}

/// <p>AC-4 #7 — inspection-agent system prompt mentions tool names.
/// Inspection prompt MUST NOT hardcode tool names — the runtime passes the
/// actual loaded tool list separately as a typed `tools` parameter. Hardcoded
/// names cause the LLM to hallucinate capabilities for tools that haven't shipped
/// yet (Epic 3 manual-test finding 2026-05-03: agent claimed Epic 4/8 tools it
/// didn't have). Updated assertion: prompt mentions read-only invariant + the
/// "tools available" boilerplate, but does NOT enumerate tool names.</p>
Method TestGetSystemPromptInspectionDescribesRoleAndConstraints()
{
    Set tPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("session-inspection")
    Do $$$AssertNotEquals(tPrompt, "", "Inspection prompt must be non-empty")
    Set tLower = $ZConvert(tPrompt, "L")
    Do $$$AssertTrue(tLower [ "read-only", "Inspection prompt must mention the read-only invariant")
    Do $$$AssertTrue(tLower [ "session-inspection assistant", "Inspection prompt must identify the assistant role")
    Do $$$AssertTrue(tLower [ "do not invent tool names", "Inspection prompt must instruct the LLM not to invent tool names (defends against capability hallucination)")
    Do $$$AssertTrue(tLower [ "objectid", "Inspection prompt must distinguish ObjectId/MessageId from SessionId for citation chips")

    ; Negative invariant: the prompt MUST NOT enumerate Epic 4/8 tool names.
    ; If it does, the LLM will claim those capabilities even when the registry
    ; doesn't load them (the bug surfaced in Epic 3 manual testing).
    Set tFutureTools = $ListBuild("event_log", "rule_log", "find_related_sessions",
        "find_sessions_by_body", "get_message_body", "get_message_detail",
        "get_business_process_source", "get_business_process_instance",
        "list_business_process_methods", "explain_error")
    Set tPtr = 0
    While $ListNext(tFutureTools, tPtr, tName) {
        If tName '= "" {
            Do $$$AssertTrue('(tPrompt [ tName), "Inspection prompt MUST NOT name future tool '"_tName_"' (Epic 3 only loads 3 tools; the rest hallucinate)")
        }
    }
    Quit
}

/// <p>AC-4 #8 — search-agent system prompt mentions the bounded-WHERE
/// invariant and the time-window phrase. Both substrings checked
/// case-insensitively via <code>$ZConvert(...,"L")</code> on the haystack.</p>
Method TestGetSystemPromptSearchMentionsBoundedWhere()
{
    Set tPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("message-search")
    Do $$$AssertNotEquals(tPrompt, "", "Search prompt must be non-empty")
    Set tLower = $ZConvert(tPrompt, "L")
    Do $$$AssertTrue(tLower [ "bounded", "Search prompt must mention 'bounded'")
    Do $$$AssertTrue(tLower [ "time window", "Search prompt must mention 'time window'")
    Quit
}

/// <p>AC-4 #9 — idempotency. After a fresh seed, the extent has exactly
/// 2 rows; after a re-seed (re-install scenario), the extent still has
/// exactly 2 rows — no duplicates created. The unique
/// <code>AgentNameIdx</code> would also fail any duplicate
/// <method>%Save</method>, so this test exercises both the
/// Installer-side <code>AgentNameIdxExists</code> guard and the
/// database-side unique constraint as a safety net.</p>
Method TestSeedingIsIdempotent()
{
    ; First seed: empty extent → 2 rows.
    Set tSC = ##class(SessionAgent.Installer).SeedDefaultAgentConfigs()
    Do $$$AssertStatusOK(tSC, "First SeedDefaultAgentConfigs returns OK")
    Set tCount1 = ..CountAgents()
    Do $$$AssertEquals(tCount1, 2, "After first seed, extent has 2 rows")

    ; Second seed: existing extent → still 2 rows.
    Set tSC = ##class(SessionAgent.Installer).SeedDefaultAgentConfigs()
    Do $$$AssertStatusOK(tSC, "Second SeedDefaultAgentConfigs returns OK")
    Set tCount2 = ..CountAgents()
    Do $$$AssertEquals(tCount2, 2, "After re-seed, extent still has 2 rows (no duplicates)")
    Quit
}

/// <p>AC-4 #10 — round-trip persistence. Seed the rows, open one by name,
/// mutate <code>MaxTokens</code> to 8192, save, re-open in a fresh
/// instance, assert the mutated value persists. Confirms the
/// auto-generated <code>Storage</code> section actually backs each
/// property to disk.</p>
Method TestSavedRowRoundTrip()
{
    ; Seed first so we have a row to mutate.
    Set tSC = ##class(SessionAgent.Installer).SeedDefaultAgentConfigs()
    Do $$$AssertStatusOK(tSC, "Seed succeeded; row available for round-trip mutation")

    Set tFirst = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tFirst), "Open by AgentNameIdx returns the seeded row")
    If $IsObject(tFirst) {
        Set tFirst.MaxTokens = 8192
        Set tSaveSC = tFirst.%Save()
        Do $$$AssertStatusOK(tSaveSC, "Mutation %Save succeeded")
    }

    ; Fresh open in a new instance to confirm round-trip from disk.
    Set tReopened = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
    Do $$$AssertTrue($IsObject(tReopened), "Re-open returns the row")
    If $IsObject(tReopened) {
        Do $$$AssertEquals(tReopened.MaxTokens, 8192, "Mutated MaxTokens persists across open")
    }
    Quit
}

/// <p>Helper — returns the count of rows in
/// <code>SessionAgent.Config.Agent</code> via SQL. Avoids %ResultSet
/// boilerplate inline in the tests.</p>
ClassMethod CountAgents() As %Integer
{
    Set tCount = -1
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS C FROM SessionAgent_Config.Agent")
    If $$$ISERR(tPrepSC) Quit tCount
    Set tRS = tStmt.%Execute()
    If tRS.%Next() {
        Set tCount = tRS.%Get("C")
    }
    Quit tCount
}

}
