/// <p>Integration tests for Story 10.6's two new sweep tasks:
/// <CLASS>SessionAgent.Task.PurgeStaleSearchChat</CLASS> (daily 03:00 UTC,
/// removes Search-keyed <code>Chat.History</code> rows older than
/// <code>Config.Agent.SearchChatRetentionDays</code> default 30) and
/// <CLASS>SessionAgent.Task.UserVocabularyDecay</CLASS> (Sunday 04:00 UTC,
/// removes <code>UserVocabulary</code> rows where
/// <code>Confidence &lt; 0.2 AND LastUsed &gt; 90d</code>).</p>
///
/// <p><b>Six AC-5 tests</b> from epics.md §"Story 10.6 AC-5":</p>
/// <ol>
/// <li><b>TestPurgeStaleSearchChatDeletesStaleRows</b> — seed 100 rows
/// (50 stale + 50 fresh) with <code>AgentName='message-search'</code>; run
/// <code>OnTask()</code>; assert 50 deleted / 50 preserved.</li>
/// <li><b>TestPurgeStaleSearchChatRetentionDaysFromConfig</b> — set
/// <code>SearchChatRetentionDays = 14</code>; seed rows at 10/15/20 days
/// old; assert only the 15+ and 20+ rows are deleted (boundary check).</li>
/// <li><b>TestPurgeStaleSearchChatAuditEvent</b> — verify the
/// <code>(SessionAgent, TaskRun, PurgeStaleSearchChat)</code> audit
/// triple landed after <code>OnTask()</code>.</li>
/// <li><b>TestUserVocabularyDecayDeletesStaleRows</b> — seed 50 rows
/// (10 decayed + 40 fresh); run <code>OnTask()</code>; assert 10 deleted
/// / 40 preserved.</li>
/// <li><b>TestUserVocabularyDecayThresholdBoundary</b> — seed rows with
/// <code>Confidence ∈ {0.19, 0.20, 0.21}</code> (all stale); assert only
/// the 0.19 row is deleted (strict-less-than).</li>
/// <li><b>TestUserVocabularyDecayAuditEvent</b> — verify the
/// <code>(SessionAgent, TaskRun, UserVocabularyDecay)</code> audit triple
/// landed after <code>OnTask()</code>.</li>
/// </ol>
///
/// <p><b>Property naming.</b> All instance/state properties on this class
/// use a NON-<code>Test*</code> prefix
/// (<code>FixturePortalUser</code>, <code>FixtureBaseAgent</code>) per
/// Story 7.0 / Epic 6 retro AI-3 shadow-trap rule — the framework's
/// test-method-discovery loop matches every method whose name begins with
/// <code>Test</code>, including the auto-generated datatype helpers
/// (<code>&lt;PropName&gt;DisplayToLogical</code>, etc.) so a property
/// named <code>TestX</code> would surface phantom tests.</p>
///
/// <p><b>Test isolation strategy.</b>
/// <method>OnBeforeOneTest</method> kills the data globals for both tables
/// AND saves the current
/// <code>Config.Agent.SearchChatRetentionDays</code> value so the
/// boundary-check test can restore it on cleanup. <method>OnAfterOneTest</method>
/// kills the globals again and restores
/// <code>SearchChatRetentionDays</code>.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 10.6 AC-5</a> — six-test contract.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list, constructor pattern, file-size cap, shadow-trap
/// rule for <code>Property Test*</code>.</li>
/// <li><a href="../Task/PurgeStaleSearchChat.cls">SessionAgent.Task.PurgeStaleSearchChat</a>
/// — system-under-test #1.</li>
/// <li><a href="../Task/UserVocabularyDecay.cls">SessionAgent.Task.UserVocabularyDecay</a>
/// — system-under-test #2.</li>
/// </ul>
Class SessionAgent.Test.SweepTaskTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts <code>initvalue</code> and calls
/// <code>##super(initvalue)</code> per project rule §"Critical Constructor
/// Requirements". No <code>Private</code> keyword (ERROR #5477).</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..FixturePortalUser = "sa-test-106-fixture"
    Set ..SavedRetentionDays = -1
    Quit $$$OK
}

/// <p>PortalUser used as the seed value for vocabulary-fixture rows.
/// Non-<code>Test*</code> prefix per shadow-trap rule.</p>
Property FixturePortalUser As %String;

/// <p>Saved <code>SearchChatRetentionDays</code> value captured in
/// <method>OnBeforeOneTest</method> and restored in
/// <method>OnAfterOneTest</method> so per-test mutations of the config
/// don't leak across tests. <code>-1</code> sentinel = "not yet captured".</p>
Property SavedRetentionDays As %Integer [ InitialExpression = -1 ];

/// <p>Per-test fixture: kill the data globals for both tables; save
/// current <code>SearchChatRetentionDays</code> for restore in
/// <method>OnAfterOneTest</method>.</p>
Method OnBeforeOneTest() As %Status
{
    Kill ^SessionAgent.Chat.HistoryD
    Kill ^SessionAgent.Chat.HistoryI
    Kill ^SessionAgent.Chat.HistoryS
    Kill ^SessionAgenC88B.UserVocabularyD
    Kill ^SessionAgenC88B.UserVocabularyI
    Kill ^SessionAgenC88B.UserVocabularyS

    ; Save the current SearchChatRetentionDays value for the message-search
    ; agent row so per-test mutations can be reversed.
    Set tCfgId = ""
    If ##class(SessionAgent.Config.Agent).AgentNameIdxExists("message-search", .tCfgId) {
        Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(tCfgId)
        If $IsObject(tCfg) {
            Set ..SavedRetentionDays = +tCfg.SearchChatRetentionDays
        }
    }
    Quit $$$OK
}

/// <p>Per-test cleanup: kill globals; restore
/// <code>SearchChatRetentionDays</code> to its pre-test value if mutated.</p>
Method OnAfterOneTest() As %Status
{
    Try { Kill ^SessionAgent.Chat.HistoryD } Catch {}
    Try { Kill ^SessionAgent.Chat.HistoryI } Catch {}
    Try { Kill ^SessionAgent.Chat.HistoryS } Catch {}
    Try { Kill ^SessionAgenC88B.UserVocabularyD } Catch {}
    Try { Kill ^SessionAgenC88B.UserVocabularyI } Catch {}
    Try { Kill ^SessionAgenC88B.UserVocabularyS } Catch {}

    ; Restore SearchChatRetentionDays if a test mutated it.
    Try {
        If ..SavedRetentionDays >= 0 {
            Set tCfgId = ""
            If ##class(SessionAgent.Config.Agent).AgentNameIdxExists("message-search", .tCfgId) {
                Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(tCfgId)
                If $IsObject(tCfg) && (+tCfg.SearchChatRetentionDays '= ..SavedRetentionDays) {
                    Set tCfg.SearchChatRetentionDays = ..SavedRetentionDays
                    Do tCfg.%Save()
                }
            }
        }
    } Catch {}
    Quit $$$OK
}

/// <p>AC-5 #1 — seed 100 <code>Chat.History</code> rows
/// (50 older than retentionDays + 50 newer) with
/// <code>AgentName='message-search'</code>. Run
/// <code>PurgeStaleSearchChat:OnTask()</code>. Assert 50 stale rows
/// deleted; 50 fresh rows preserved.</p>
Method TestPurgeStaleSearchChatDeletesStaleRows()
{
    ; Use default retentionDays = 30. Seed 50 rows at 60 days old (stale),
    ; 50 rows at 1 day old (fresh).
    Do ..SeedChatHistoryRows("message-search", 50, 60, "stale")
    Do ..SeedChatHistoryRows("message-search", 50, 1, "fresh")

    Do $$$AssertEquals(..CountChatHistoryByAgent("message-search"), 100, "100 message-search rows seeded")

    Set tSC = ##class(SessionAgent.Task.PurgeStaleSearchChat).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")

    Set tRemaining = ..CountChatHistoryByAgent("message-search")
    Do $$$AssertEquals(tRemaining, 50, "50 rows remain (the fresh ones)")
    Quit
}

/// <p>AC-5 #2 — set <code>Config.Agent.SearchChatRetentionDays = 14</code>.
/// Seed rows at 10, 15, 20 days old. Assert the 15+ and 20+ day rows are
/// deleted; the 10-day row is preserved (strict-less-than boundary).</p>
Method TestPurgeStaleSearchChatRetentionDaysFromConfig()
{
    ; Set retentionDays = 14 on the message-search Config.Agent row.
    Set tCfgId = ""
    Do $$$AssertTrue(##class(SessionAgent.Config.Agent).AgentNameIdxExists("message-search", .tCfgId), "message-search row exists")
    Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(tCfgId)
    Set tCfg.SearchChatRetentionDays = 14
    Do $$$AssertStatusOK(tCfg.%Save(), "saved retentionDays=14")

    ; Seed three rows at 10, 15, 20 days old. With cutoff = now - 14 days,
    ; the 15-day and 20-day rows are stale (UpdatedAt < cutoff).
    Do ..SeedChatHistoryRows("message-search", 1, 10, "10d")
    Do ..SeedChatHistoryRows("message-search", 1, 15, "15d")
    Do ..SeedChatHistoryRows("message-search", 1, 20, "20d")

    Set tSC = ##class(SessionAgent.Task.PurgeStaleSearchChat).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")

    Set tRemaining = ..CountChatHistoryByAgent("message-search")
    Do $$$AssertEquals(tRemaining, 1, "1 row remains (the 10-day one); 15+ and 20+ deleted")
    Quit
}

/// <p>AC-5 #3 — verify the
/// <code>(SessionAgent, TaskRun, PurgeStaleSearchChat)</code> audit
/// triple landed in <code>%SYS.Audit</code> after
/// <code>PurgeStaleSearchChat:OnTask()</code>.</p>
Method TestPurgeStaleSearchChatAuditEvent()
{
    Set tCountBefore = ..CountTaskRunAuditRows("PurgeStaleSearchChat")
    Set tSC = ##class(SessionAgent.Task.PurgeStaleSearchChat).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")
    ; Story 14.0 — audit-daemon flush is asynchronous; bounded poll
    ; (120s ceiling, exits on first increase — see helper doc).
    Set tCountAfter = ..WaitForTaskRunAuditIncrease("PurgeStaleSearchChat", tCountBefore)
    Do $$$AssertTrue(tCountAfter > tCountBefore, "TaskRun/PurgeStaleSearchChat audit row count increased; before=" _ tCountBefore _ " after=" _ tCountAfter)
    Quit
}

/// <p>AC-5 #4 — seed 50 <code>UserVocabulary</code> rows
/// (10 with <code>Confidence &lt; 0.2 AND LastUsed &gt; 90d</code>;
/// 40 fresh). Run <code>UserVocabularyDecay:OnTask()</code>. Assert 10
/// decayed rows deleted; 40 fresh preserved.</p>
Method TestUserVocabularyDecayDeletesStaleRows()
{
    ; Seed 10 decayed rows (Confidence=0.1, LastUsed=120 days ago).
    Do ..SeedVocabularyRows(10, 0.1, 120, "decayed")
    ; Seed 40 fresh rows (Confidence=0.5, LastUsed=10 days ago).
    Do ..SeedVocabularyRows(40, 0.5, 10, "fresh")

    Do $$$AssertEquals(..CountVocabularyRowsForFixtureUser(), 50, "50 vocabulary rows seeded")

    Set tSC = ##class(SessionAgent.Task.UserVocabularyDecay).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")

    Set tRemaining = ..CountVocabularyRowsForFixtureUser()
    Do $$$AssertEquals(tRemaining, 40, "40 rows remain (the fresh ones)")
    Quit
}

/// <p>AC-5 #5 — seed 3 stale-LastUsed rows with
/// <code>Confidence ∈ {0.19, 0.20, 0.21}</code>. Assert only the 0.19 row
/// is deleted (strict-less-than threshold).</p>
Method TestUserVocabularyDecayThresholdBoundary()
{
    ; All three rows are stale (LastUsed = 100 days ago > 90 day window),
    ; so only Confidence selects which gets deleted.
    Do ..SeedOneVocabularyRow(0.19, 100, "alias_019")
    Do ..SeedOneVocabularyRow(0.20, 100, "alias_020")
    Do ..SeedOneVocabularyRow(0.21, 100, "alias_021")

    Do $$$AssertEquals(..CountVocabularyRowsForFixtureUser(), 3, "3 vocabulary rows seeded")

    Set tSC = ##class(SessionAgent.Task.UserVocabularyDecay).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")

    Set tRemaining = ..CountVocabularyRowsForFixtureUser()
    Do $$$AssertEquals(tRemaining, 2, "2 rows remain (0.20 + 0.21); strict < 0.2 deleted only 0.19")
    Quit
}

/// <p>AC-5 #6 — verify the
/// <code>(SessionAgent, TaskRun, UserVocabularyDecay)</code> audit
/// triple landed in <code>%SYS.Audit</code> after
/// <code>UserVocabularyDecay:OnTask()</code>.</p>
Method TestUserVocabularyDecayAuditEvent()
{
    Set tCountBefore = ..CountTaskRunAuditRows("UserVocabularyDecay")
    Set tSC = ##class(SessionAgent.Task.UserVocabularyDecay).%New().OnTask()
    Do $$$AssertStatusOK(tSC, "OnTask returned $$$OK")
    ; Story 14.0 — audit-daemon flush is asynchronous; bounded poll
    ; (120s ceiling, exits on first increase — see helper doc).
    Set tCountAfter = ..WaitForTaskRunAuditIncrease("UserVocabularyDecay", tCountBefore)
    Do $$$AssertTrue(tCountAfter > tCountBefore, "TaskRun/UserVocabularyDecay audit row count increased; before=" _ tCountBefore _ " after=" _ tCountAfter)
    Quit
}

/// <p>Helper — seed <var>pCount</var> <code>Chat.History</code> rows for
/// the supplied <var>pAgentName</var> with <code>UpdatedAt</code> set to
/// <code>now - <var>pAgeDays</var></code>. The
/// <code>(AgentName, SessionKey, PortalUser)</code> tuple is unique per
/// row to avoid the <code>ConvKeyIdx</code> unique-index violation; the
/// <var>pTag</var> + a sequential index make each SessionKey unique.</p>
ClassMethod SeedChatHistoryRows(pAgentName As %String, pCount As %Integer, pAgeDays As %Integer, pTag As %String)
{
    Set tBackdatedH = $ZTimeStamp
    Set $Piece(tBackdatedH, ",", 1) = $Piece(tBackdatedH, ",", 1) - pAgeDays
    Set tBackdatedIso = $Translate($ZDateTime(tBackdatedH, 3, 1), " ", "T") _ "Z"
    Set tNowIso = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"

    For tI = 1:1:pCount {
        Set tRow = ##class(SessionAgent.Chat.History).%New()
        Set tRow.AgentName = pAgentName
        Set tRow.SessionKey = "sk-" _ pTag _ "-" _ tI
        Set tRow.PortalUser = "sa-test-106-seed"
        Set tRow.CreatedAt = tBackdatedIso
        Set tRow.UpdatedAt = tBackdatedIso
        ; TurnsJson is a stream; leave empty (default).
        Do tRow.%Save()
    }
    Quit
}

/// <p>Helper — count <code>Chat.History</code> rows for the supplied
/// <var>pAgentName</var>.</p>
ClassMethod CountChatHistoryByAgent(pAgentName As %String) As %Integer
{
    Set tCount = 0
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Chat.History WHERE %EXACT(AgentName) = ?")
    Set tRs = tStmt.%Execute(pAgentName)
    If tRs.%Next() Set tCount = +tRs.%Get("Cnt")
    Quit tCount
}

/// <p>Helper — seed <var>pCount</var> <code>UserVocabulary</code> rows
/// for <code>FixturePortalUser</code> with the supplied
/// <var>pConfidence</var> and a <code>LastUsed</code> backdated by
/// <var>pAgeDays</var>. Aliases are made unique via
/// <code>pTag-{i}</code>.</p>
Method SeedVocabularyRows(pCount As %Integer, pConfidence As %Numeric, pAgeDays As %Integer, pTag As %String)
{
    Set tBackdatedH = $ZTimeStamp
    Set $Piece(tBackdatedH, ",", 1) = $Piece(tBackdatedH, ",", 1) - pAgeDays
    Set tBackdatedIso = $Translate($ZDateTime(tBackdatedH, 3, 1), " ", "T") _ "Z"

    For tI = 1:1:pCount {
        Set tAlias = pTag _ "-" _ tI
        Do ..SeedOneVocabularyRow(pConfidence, pAgeDays, tAlias)
    }
    Quit
}

/// <p>Helper — seed one <code>UserVocabulary</code> row with a specific
/// confidence + age + alias. Bypasses
/// <method>UserVocabulary.RecordSuccess</method> because that method
/// overrides Confidence via the
/// <method>%OnAfterSave</method> trigger; the test needs to inject
/// arbitrary Confidence values to exercise the boundary case. Direct SQL
/// UPDATE post-<code>%Save()</code> bypasses the trigger
/// (per Story 9.2's documented bypass pattern).</p>
Method SeedOneVocabularyRow(pConfidence As %Numeric, pAgeDays As %Integer, pAlias As %String)
{
    Set tBackdatedH = $ZTimeStamp
    Set $Piece(tBackdatedH, ",", 1) = $Piece(tBackdatedH, ",", 1) - pAgeDays
    Set tBackdatedIso = $Translate($ZDateTime(tBackdatedH, 3, 1), " ", "T") _ "Z"

    Set tRow = ##class(SessionAgent.Search.UserVocabulary).%New()
    Set tRow.PortalUser = ..FixturePortalUser
    Set tRow.Alias = pAlias
    Set tRow.MessageBodyClass = ""
    Set tRow.SuccessCount = 0
    Set tRow.FailureCount = 0
    Set tRow.Confidence = pConfidence
    Set tRow.LastUsed = tBackdatedIso
    Set tRow.CreatedAt = tBackdatedIso
    Set tRow.CreatedVia = "seed"
    Do tRow.%Save()

    ; The %OnAfterSave trigger overwrites Confidence; force the value back
    ; via direct SQL UPDATE so the test fixture is honored.
    Set tId = tRow.%Id()
    &sql(UPDATE SessionAgent_Search.UserVocabulary
         SET Confidence = :pConfidence, LastUsed = :tBackdatedIso
         WHERE %ID = :tId)
    Quit
}

/// <p>Helper — count <code>UserVocabulary</code> rows for
/// <code>FixturePortalUser</code>.</p>
Method CountVocabularyRowsForFixtureUser() As %Integer
{
    Set tCount = 0
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(..FixturePortalUser)
    If tRs.%Next() Set tCount = +tRs.%Get("Cnt")
    Quit tCount
}

/// <p>Helper — count <code>%SYS.Audit</code> rows matching
/// <code>(EventSource=SessionAgent, EventType=TaskRun,
/// Event=<var>pName</var>)</code>. Limits the scan to the most recent 50
/// rows so the probe finishes quickly even on an audit-heavy install.</p>
ClassMethod CountTaskRunAuditRows(pName As %String) As %Integer
{
    Set tCount = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        ; Story 14.0 — best-effort header apply, mirroring what the
        ; %SYS.Audit:List query does implicitly (irislib/%SYS/Audit.cls
        ; ListExecute line 1752). It covers only records written to the
        ; audit HEADER buffer; it does NOT flush the kernel audit daemon
        ; (Story 14.0 probe: afterApply=before for $System.Security.Audit
        ; events). The actual flake fix is the bounded poll in
        ; WaitForTaskRunAuditIncrease — see its doc comment.
        Do ##class(%SYS.Audit).ApplyAuditHeader()
        Set tStmt = ##class(%SQL.Statement).%New()
        Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM %SYS.Audit WHERE %EXACT(EventSource) = 'SessionAgent' AND %EXACT(EventType) = 'TaskRun' AND %EXACT(Event) = ?")
        Set tRs = tStmt.%Execute(pName)
        If tRs.%Next() Set tCount = +tRs.%Get("Cnt")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tCount
}

/// <p>Story 14.0 sweep fix — the kernel audit daemon flushes
/// <code>$System.Security.Audit</code> events to the IRISAUDIT database
/// asynchronously, so a COUNT(*) probe issued milliseconds after
/// <code>OnTask()</code> reads the pre-write count. Empirically verified
/// same-process on the 2026-06 fresh server (Story 14.0 probe:
/// <code>auditRet=1</code> with <code>afterImmediate=before</code> and
/// <code>afterApply=before</code> —
/// <code>%SYS.Audit:ApplyAuditHeader()</code> does not surface these
/// rows; it only applies audit-HEADER-buffer records, per
/// irislib/%SYS/Audit.cls). No public forced-flush API exists
/// (Perplexity research 2026-06-10).</p>
/// <p><b>Authoritative poll bound (Story 14.0 review fix — single
/// statement, call sites reference here):</b> 240 × 0.5s = <b>120s
/// ceiling</b>, exiting on the FIRST observed increase. Daemon lag was
/// observed at ~30–60s on the 2026-06 fresh server (a 60s ceiling
/// passed with only ~0.6s to spare), so 120s carries a 2x margin.
/// Returns the first increased count, or the last observed count on
/// timeout (the assertion then fails with the real numbers).</p>
ClassMethod WaitForTaskRunAuditIncrease(pName As %String, pBefore As %Integer) As %Integer
{
    Set tCount = pBefore
    ; 240 x 0.5s = 120s ceiling; exits on first increase (see doc above).
    For tAttempt = 1:1:240 {
        Set tCount = ..CountTaskRunAuditRows(pName)
        If tCount > pBefore Quit
        Hang 0.5
    }
    Quit tCount
}

}
