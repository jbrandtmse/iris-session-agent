/// <p>Unit tests for Story 2.5 audit-ledger surface:
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> /
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> persistent classes plus the
/// <method>SessionAgent.Audit.Emit.LogLlmCall</method>,
/// <method>SessionAgent.Audit.Emit.LogToolCall</method>, and
/// <method>SessionAgent.Audit.Emit.RegisterIfMissing</method> helpers.</p>
///
/// <p>Distinct from <CLASS>SessionAgent.Test.AuditEmitTest</CLASS> (Story
/// 1.3) which exercises the install-time <method>EnsureEvents</method>
/// triple-registration only. Both files coexist; this one covers the
/// per-call row-write + redaction + lazy-registration paths added in
/// Story 2.5.</p>
///
/// <p>All assertions via <code>$$$Assert*</code> macros (never
/// <code>..AssertX(...)</code>). <code>%OnNew(initvalue)</code> calls
/// <code>##super(initvalue)</code> per project rule §"Critical
/// Constructor Requirements".</p>
///
/// <p><b>Test isolation strategy.</b> Audit-row-counting tests blow away
/// the <code>^SessionAgent.Audit.LlmCallD</code> /
/// <code>^SessionAgent.Audit.ToolCallD</code> globals before each test
/// in <method>OnBeforeOneTest</method> so a prior smoke-test or production
/// run cannot contaminate the row-count assertions.
/// <method>OnAfterOneTest</method> kills them again and removes any
/// test-only audit-event triples (<code>test_tool</code>) registered by
/// the lazy-registration tests.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.5</a> (lines 823–860) — AC source.</li>
/// <li><a href="../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list, constructor pattern, file-size cap.</li>
/// </ul>
Class SessionAgent.Test.AuditTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> the parent
/// <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword.</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Per-test fixture: kill the audit data globals so each row-counting
/// test starts from an empty extent. Schema-introspection and
/// triple-registration tests are unaffected by the kill.</p>
Method OnBeforeOneTest() As %Status
{
    Kill ^SessionAgent.Audit.LlmCallD
    Kill ^SessionAgent.Audit.LlmCallI
    Kill ^SessionAgent.Audit.ToolCallD
    Kill ^SessionAgent.Audit.ToolCallI
    Quit $$$OK
}

/// <p>Per-test cleanup: try-each-cleanup pattern so a failure in one
/// kill does not skip the others. Removes the test-only
/// <code>(SessionAgent, ToolCall, test_tool)</code> triple if present.</p>
Method OnAfterOneTest() As %Status
{
    Try { Kill ^SessionAgent.Audit.LlmCallD } Catch {}
    Try { Kill ^SessionAgent.Audit.LlmCallI } Catch {}
    Try { Kill ^SessionAgent.Audit.ToolCallD } Catch {}
    Try { Kill ^SessionAgent.Audit.ToolCallI } Catch {}
    Try {
        Set tOrigNS = $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Events).Exists("SessionAgent","ToolCall","test_tool") {
            Do ##class(Security.Events).Delete("SessionAgent","ToolCall","test_tool")
        }
        Set $NAMESPACE = tOrigNS
    } Catch {
        Set $NAMESPACE = tOrigNS
    }
    Quit $$$OK
}

/// <p>AC-1 schema-presence — verifies all 12
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> properties exist with the
/// expected types. Catches schema drift before downstream consumers
/// (audit-emit helpers, SQL recipes) break.</p>
Method TestLlmCallSchemaPropertiesPresent()
{
    Set tExpected = ""
    Set tExpected("Timestamp") = "%String"
    Set tExpected("ChatHistoryId") = "%String"
    Set tExpected("Provider") = "%String"
    Set tExpected("Model") = "%String"
    Set tExpected("RequestMessageCount") = "%Integer"
    Set tExpected("RequestTokens") = "%Integer"
    Set tExpected("ResponseTokens") = "%Integer"
    Set tExpected("LatencyMs") = "%Integer"
    Set tExpected("StopReason") = "%String"
    Set tExpected("CacheHitTokens") = "%Integer"
    Set tExpected("IsError") = "%Boolean"
    Set tExpected("ErrorText") = "%String"

    Set tName = ""
    For {
        Set tName = $Order(tExpected(tName))
        Quit:tName=""
        Set tProp = ##class(%Dictionary.PropertyDefinition).%OpenId("SessionAgent.Audit.LlmCall||" _ tName)
        Do $$$AssertTrue($IsObject(tProp), "Property " _ tName _ " is defined on Audit.LlmCall")
        If $IsObject(tProp) {
            Do $$$AssertEquals(tProp.Type, tExpected(tName), "Property " _ tName _ " has type " _ tExpected(tName))
        }
    }
    Quit
}

/// <p>AC-2 schema-presence — verifies all 11
/// <CLASS>SessionAgent.Audit.ToolCall</CLASS> properties exist with
/// expected types.</p>
Method TestToolCallSchemaPropertiesPresent()
{
    Set tExpected = ""
    Set tExpected("Timestamp") = "%String"
    Set tExpected("ChatHistoryId") = "%String"
    Set tExpected("ToolName") = "%String"
    Set tExpected("ArgsJson") = "%String"
    Set tExpected("ResultJson") = "%String"
    Set tExpected("LatencyMs") = "%Integer"
    Set tExpected("IsError") = "%Boolean"
    Set tExpected("ErrorText") = "%String"
    Set tExpected("ResultSetSize") = "%Integer"
    Set tExpected("QueryTemplate") = "%String"
    Set tExpected("IndexUsed") = "%String"

    Set tName = ""
    For {
        Set tName = $Order(tExpected(tName))
        Quit:tName=""
        Set tProp = ##class(%Dictionary.PropertyDefinition).%OpenId("SessionAgent.Audit.ToolCall||" _ tName)
        Do $$$AssertTrue($IsObject(tProp), "Property " _ tName _ " is defined on Audit.ToolCall")
        If $IsObject(tProp) {
            Do $$$AssertEquals(tProp.Type, tExpected(tName), "Property " _ tName _ " has type " _ tExpected(tName))
        }
    }
    Quit
}

/// <p>AC-4 NFR-S4 100% completeness for LLM calls — call
/// <method>LogLlmCall</method> 5 times, assert exactly 5 rows persisted.
/// Validates "N invocations → N rows" — never silently dropped.</p>
Method TestLogLlmCallWritesOneRow()
{
    For i = 1:1:5 {
        Set tSC = ##class(SessionAgent.Audit.Emit).LogLlmCall(
            "chat-" _ i, "openai", "gpt-4o", 3, 100, 50, 1234, "stop", 0, 0, "")
        Do $$$AssertStatusOK(tSC, "LogLlmCall #" _ i _ " returns OK")
    }

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Audit.LlmCall")
    Do $$$AssertStatusOK(tPrepSC, "COUNT(*) prepares OK")
    Set tRS = tStmt.%Execute()
    Do tRS.%Next()
    Do $$$AssertEquals(tRS.Cnt, 5, "5 LogLlmCall invocations -> 5 rows persisted")
    Quit
}

/// <p>AC-4 NFR-S4 100% completeness for tool calls — call
/// <method>LogToolCall</method> 7 times, assert exactly 7 rows
/// persisted.</p>
Method TestLogToolCallWritesOneRow()
{
    For i = 1:1:7 {
        Set tSC = ##class(SessionAgent.Audit.Emit).LogToolCall(
            "chat-" _ i, "test_tool", "{}", "{}", 100, 0, "", "", "", "")
        Do $$$AssertStatusOK(tSC, "LogToolCall #" _ i _ " returns OK")
    }

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Audit.ToolCall")
    Do $$$AssertStatusOK(tPrepSC, "COUNT(*) prepares OK")
    Set tRS = tStmt.%Execute()
    Do tRS.%Next()
    Do $$$AssertEquals(tRS.Cnt, 7, "7 LogToolCall invocations -> 7 rows persisted")
    Quit
}

/// <p>AC-3 / NFR-S3 redaction — feed
/// <code>pArgsJson</code> containing a literal credential
/// (<code>"api_key": "sk-leak-12345"</code>), call <method>LogToolCall</method>,
/// then query the persisted <code>ArgsJson</code>. Asserts the literal
/// credential string does NOT appear and <code>&lt;redacted&gt;</code>
/// DOES appear.</p>
Method TestLogToolCallRedactsCredentialsInArgsJson()
{
    Set tArgsJson = "{""session_id"":""abc"",""api_key"":""sk-leak-12345""}"
    Set tSC = ##class(SessionAgent.Audit.Emit).LogToolCall(
        "chat-redact", "test_tool", tArgsJson, "{}", 100, 0, "", "", "", "")
    Do $$$AssertStatusOK(tSC, "LogToolCall returns OK")

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT %EXACT(ArgsJson) AS A FROM SessionAgent_Audit.ToolCall")
    Do $$$AssertStatusOK(tPrepSC, "SELECT prepares OK")
    Set tRS = tStmt.%Execute()
    Do tRS.%Next()
    Set tStored = tRS.A

    Do $$$AssertEquals(tStored [ "sk-leak-12345", 0, "literal credential 'sk-leak-12345' must NOT appear in persisted ArgsJson")
    Do $$$AssertEquals(tStored [ "<redacted>", 1, "'<redacted>' marker must appear in persisted ArgsJson")
    Quit
}

/// <p>AC-3 / NFR-S4 — induce a <code>%Save</code> failure by passing an
/// <code>ErrorText</code> longer than the property's
/// <code>MAXLEN=4096</code>. Asserts <method>LogLlmCall</method> returns
/// <code>$$$ISERR=1</code> (failure surfaced; not silently discarded).</p>
Method TestLogLlmCallStatusFailureSurfaces()
{
    Set tBig = ""
    For i = 1:1:5000 {
        Set tBig = tBig _ "X"
    }

    Set tSC = ##class(SessionAgent.Audit.Emit).LogLlmCall(
        "chat-fail", "openai", "gpt-4o", 1, 1, 1, 1, "stop", 0, 1, tBig)

    Do $$$AssertEquals($$$ISERR(tSC), 1, "LogLlmCall surfaces %Save failure when ErrorText exceeds MAXLEN=4096")
    Quit
}

/// <p>AC-3 lazy-registration idempotency — call
/// <method>RegisterIfMissing</method> twice for the same
/// <code>(SessionAgent, ToolCall, test_tool)</code> triple. Both calls
/// must return <code>$$$OK</code> (no duplicate-create error on second
/// call), and the triple must exist in
/// <code>%SYS Security.Events</code> after both calls.</p>
Method TestRegisterIfMissingIsIdempotent()
{
    Set tSC1 = ##class(SessionAgent.Audit.Emit).RegisterIfMissing("SessionAgent", "ToolCall", "test_tool")
    Do $$$AssertStatusOK(tSC1, "first RegisterIfMissing call returns OK")

    Set tSC2 = ##class(SessionAgent.Audit.Emit).RegisterIfMissing("SessionAgent", "ToolCall", "test_tool")
    Do $$$AssertStatusOK(tSC2, "second RegisterIfMissing call returns OK (no duplicate-create error)")

    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","ToolCall","test_tool"), "(SessionAgent,ToolCall,test_tool) triple is registered")
        Set $NAMESPACE = tOrigNS
    } Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>Regression guard — Story 1.3 pre-registered 11 audit-event
/// triples via <method>EnsureEvents</method>; Story 2.5 must not have
/// inadvertently broken any of them. Asserts each of the 11 triples is
/// still present in <code>%SYS Security.Events</code>.</p>
Method TestEpic1AuditEmitTripleRegistrationIntact()
{
    ; First, ensure they're registered (defensive — install or prior
    ; test may have removed; EnsureEvents is idempotent).
    Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "EnsureEvents returns OK")

    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","openai"), "LlmCall/openai still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","anthropic"), "LlmCall/anthropic still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","gemini"), "LlmCall/gemini still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","ollama"), "LlmCall/ollama still registered")

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","clickthrough"), "VocabWrite/clickthrough still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","explicit"), "VocabWrite/explicit still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","extracted"), "VocabWrite/extracted still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","seed"), "VocabWrite/seed still registered")

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","PurgeOrphanedChatHistory"), "TaskRun/PurgeOrphanedChatHistory still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","PurgeStaleSearchChat"), "TaskRun/PurgeStaleSearchChat still registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","UserVocabularyDecay"), "TaskRun/UserVocabularyDecay still registered")

        Set $NAMESPACE = tOrigNS
    } Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

}
