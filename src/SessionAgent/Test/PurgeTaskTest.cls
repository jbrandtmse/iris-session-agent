/// <p>Story 7.3 — 1,000-Session Integration Test for
/// <CLASS>SessionAgent.Task.PurgeOrphanedChatHistory</CLASS>. Validates the
/// Story 7.2 sweep against realistic operator-grade data volumes:</p>
/// <ul>
/// <li>1,000 fixture <code>Ens.MessageHeader</code> rows (sessions whose
///     SessionId is in the fixture range).</li>
/// <li>600 fixture Inspection-keyed <code>SessionAgent.Chat.History</code>
///     rows (sessions 1..600 of the 1,000 have chat history; 601..1000 do
///     not).</li>
/// <li>50 fixture <code>Audit.LlmCall</code> + <code>Audit.ToolCall</code>
///     row pairs (chat rows 1..50 carry audit fan-out).</li>
/// <li>10 search-keyed (<code>AgentName='message-search'</code>)
///     <code>Chat.History</code> rows used to assert the sweep's per-agent
///     filter (defense-in-depth).</li>
/// </ul>
///
/// <p><b>Fixture-isolation contract.</b> The story spec called for a
/// <code>"PurgeTest73-"</code> string prefix on
/// <code>Ens.MessageHeader.SessionId</code>, but Task 2 schema introspection
/// surfaced that <code>Ens.MessageHeader.SessionId</code> is
/// <code>%Library.Integer</code> — a string-prefix value fails IRIS
/// integer-validation (SQLCODE -104). The dev adapted the contract to use
/// an <b>integer fixture range</b> that is structurally protected from
/// production collision: <code>Ens.MessageHeader.SessionId</code> in
/// <code>90000001..90001000</code>. The maximum production SessionId at
/// story-write time is 5,580; the fixture range is ~16,000× higher, so
/// collision is impossible. The chat-row <code>SessionKey</code> stores
/// the integer as a string (<code>"90000001"</code>...<code>"90001000"</code>)
/// matching the existing real-row pattern (live row at story-write time
/// uses <code>SessionKey="5294"</code> against
/// <code>Ens.MessageHeader.SessionId=5294</code>). The sweep's existence
/// check (<code>%EXACT(SessionId) = :tSessionKey</code>) IRIS-implicit-
/// converts the string back to integer for comparison.</p>
///
/// <p>The 10 search-keyed rows DO use a string identifier
/// (<code>"PurgeTest73-S"_i</code>) — they don't match an Ens row by
/// design (search-agent <code>SessionKey</code> is a registry GUID,
/// not an Ens session ID). Those rows test that the sweep's
/// <code>AgentName='session-inspection'</code> filter prevents
/// cross-agent contamination.</p>
///
/// <p><b>Single-shot fixture lifecycle.</b> The 1,000-row INSERT is
/// expensive, so all fixtures live for the whole test-class run via
/// <method>OnBeforeAllTests</method> +
/// <method>OnAfterAllTests</method>. Per-test isolation comes from the
/// test methods operating on disjoint subsets of the fixture lattice:
/// <method>Test1RemovesOrphans</method> exercises the headline
/// numerical claim (200 deleted-orphan chat rows + 400 surviving chat
/// rows); <method>Test2CascadesAuditRows</method> exercises the
/// audit-cascade contract on the 50 audit-attached rows
/// (subset of the 200 deleted orphans);
/// <method>Test3RespectsAgentNameFilter</method> exercises the
/// per-agent filter against the 10 search-keyed rows (untouched).</p>
///
/// <p><b>Test method execution order.</b> Method names are
/// numeric-prefixed to enforce alphabetic-sort ordering by the
/// <code>%UnitTest</code> framework:
/// <method>Test1RemovesOrphans</method> runs first (simulates 300-session
/// Ens.MessageHeader.Purge() + invokes the sweep + asserts 400 chat rows
/// remain).
/// <method>Test2CascadesAuditRows</method> runs second on the
/// post-Removes state (asserts the 50 fixture audit-row pairs cascaded
/// to 0 — Story 7.1 Option B contract).
/// <method>Test3RespectsAgentNameFilter</method> runs last; the 10
/// search-keyed rows inserted by <method>OnBeforeAllTests</method>
/// remain untouched (the sweep's
/// <code>AgentName='session-inspection'</code> filter prevents
/// cross-agent contamination).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/implementation-artifacts/7-3-1000-session-integration-test.md">Story 7.3 spec</a>.</li>
/// <li><a href="../../_bmad-output/implementation-artifacts/7-1-task-0-probe-audit-fk-cascade-design.md">Story 7.1 Option B contract</a> — audit-row cascade ordering.</li>
/// <li><a href="../../_bmad-output/implementation-artifacts/7-2-purgeorphanedchathistory-task-installer-scheduling.md">Story 7.2 sweep implementation</a>.</li>
/// <li><a href="../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a> — <code>%UnitTest.TestCase</code> patterns, constructor, file-size cap.</li>
/// </ul>
Class SessionAgent.Test.PurgeTaskTest Extends %UnitTest.TestCase
{

/// <p>Fixture range start — the lowest <code>Ens.MessageHeader.SessionId</code>
/// the test populates. Chosen well above any production SessionId
/// (max real-world SessionId at story-write time was 5,580). Sessions
/// 1..1000 of the test correspond to integer SessionIds
/// <code>RangeStart..RangeStart+999</code> = 90,000,001..90,001,000.</p>
Parameter RangeStart As %Integer = 90000001;

/// <p>Fixture range end — the highest <code>Ens.MessageHeader.SessionId</code>
/// the test populates. Inclusive boundary;
/// <code>RangeEnd - RangeStart + 1 = 1000</code>.</p>
Parameter RangeEnd As %Integer = 90001000;

/// <p>Fixture-attribution PortalUser — every fixture
/// <code>Chat.History</code> row carries this value so cleanup can be
/// scoped via a single equality predicate. The literal string is also
/// the load-bearing isolation marker for search-keyed rows (which use
/// non-numeric SessionKeys).</p>
Parameter PortalUser As %String = "purge-test-user";

/// <p>Constructor — accepts the <code>initvalue</code> parent expects,
/// calls <code>##super(initvalue)</code>. No <code>Private</code>
/// keyword (project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>One-shot fixture build (per AC-3, AC-8). Defensive cleanup first
/// (in case a prior aborted run left rows behind), then bulk-INSERT
/// the lattice:</p>
/// <ol>
/// <li>1,000 <code>Ens.MessageHeader</code> rows.</li>
/// <li>600 Inspection-keyed <code>Chat.History</code> rows.</li>
/// <li>50 <code>Audit.LlmCall</code> + <code>Audit.ToolCall</code>
///     row pairs attached to chat rows 1..50.</li>
/// <li>10 search-keyed (<code>AgentName='message-search'</code>)
///     <code>Chat.History</code> rows for AC-8.</li>
/// </ol>
/// <p>All bulk INSERTs use a single
/// <code>%SQL.Statement.%Prepare</code> + repeated
/// <code>%Execute</code> for efficiency. Wrapped in
/// <code>TSTART</code>/<code>TCOMMIT</code> per-phase to amortize
/// commit cost; project rule "Transaction Side Effects" honored
/// (no JOB / Event.Signal / external I/O inside the transaction).</p>
Method OnBeforeAllTests() As %Status
{
    Set tSC = $$$OK
    Try {
        ; Defensive cleanup before fresh build.
        Set tSC = ..KillTestData()
        If $$$ISERR(tSC) Quit

        ; Phase 1: 1,000 Ens.MessageHeader rows.
        Set tEnsStmt = ##class(%SQL.Statement).%New()
        Set tSC = tEnsStmt.%Prepare("INSERT INTO Ens.MessageHeader (SessionId, Type, Status) VALUES (?, 1, 9)")
        If $$$ISERR(tSC) Quit
        TSTART
        For i = 1:1:1000 {
            Set tSid = ..#RangeStart + i - 1
            Set tRS = tEnsStmt.%Execute(tSid)
            If tRS.%SQLCODE < 0 {
                Set tSC = $$$ERROR($$$GeneralError, "Ens.MessageHeader INSERT failed at i="_i_" SQLCODE="_tRS.%SQLCODE_" "_tRS.%Message)
                TROLLBACK
                Quit
            }
            Do tRS.%Close()
        }
        If $$$ISERR(tSC) Quit
        TCOMMIT

        ; Phase 2: 600 Inspection-keyed Chat.History rows for sessions 1..600.
        Set tChatStmt = ##class(%SQL.Statement).%New()
        Set tSC = tChatStmt.%Prepare("INSERT INTO SessionAgent_Chat.History (AgentName, SessionKey, PortalUser, CreatedAt, UpdatedAt) VALUES ('session-inspection', ?, ?, ?, ?)")
        If $$$ISERR(tSC) Quit
        Set tNow = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
        TSTART
        For i = 1:1:600 {
            Set tSid = ..#RangeStart + i - 1
            Set tSessionKey = tSid _ ""
            Set tRS = tChatStmt.%Execute(tSessionKey, ..#PortalUser, tNow, tNow)
            If tRS.%SQLCODE < 0 {
                Set tSC = $$$ERROR($$$GeneralError, "Chat.History INSERT failed at i="_i_" SQLCODE="_tRS.%SQLCODE_" "_tRS.%Message)
                TROLLBACK
                Quit
            }
            Do tRS.%Close()
        }
        If $$$ISERR(tSC) Quit
        TCOMMIT

        ; Phase 3: 50 audit row pairs attached to chat rows 1..50.
        ; First fetch the chat-row IDs for sessions 1..50, then INSERT
        ; one Audit.LlmCall + one Audit.ToolCall referencing each ID.
        Set tIdStmt = ##class(%SQL.Statement).%New()
        Set tSC = tIdStmt.%Prepare("SELECT %ID AS chatId FROM SessionAgent_Chat.History WHERE %EXACT(AgentName)='session-inspection' AND %EXACT(PortalUser)=? AND SessionKey >= ? AND SessionKey <= ? ORDER BY SessionKey")
        If $$$ISERR(tSC) Quit
        Set tFirstSk = (..#RangeStart) _ ""
        Set tLastSk = (..#RangeStart + 49) _ ""
        Set tIdRS = tIdStmt.%Execute(..#PortalUser, tFirstSk, tLastSk)
        Set tAuditChatIds = ""
        While tIdRS.%Next() {
            Set tAuditChatIds = tAuditChatIds _ $ListBuild(tIdRS.%Get("chatId"))
        }
        Do tIdRS.%Close()
        If $ListLength(tAuditChatIds) '= 50 {
            Set tSC = $$$ERROR($$$GeneralError, "Expected 50 chat IDs for audit attachment, got "_$ListLength(tAuditChatIds))
            Quit
        }

        Set tLlmIns = ##class(%SQL.Statement).%New()
        Set tSC = tLlmIns.%Prepare("INSERT INTO SessionAgent_Audit.LlmCall (Timestamp, ChatHistoryId, Provider, Model, RequestTokens, ResponseTokens, LatencyMs, StopReason, IsError) VALUES (?, ?, 'openai', 'gpt-4.1-mini', 100, 50, 250, 'stop', 0)")
        If $$$ISERR(tSC) Quit
        Set tToolIns = ##class(%SQL.Statement).%New()
        Set tSC = tToolIns.%Prepare("INSERT INTO SessionAgent_Audit.ToolCall (Timestamp, ChatHistoryId, ToolName, ArgsJson, ResultJson, LatencyMs, IsError) VALUES (?, ?, 'session_summary', '{}', '{}', 100, 0)")
        If $$$ISERR(tSC) Quit
        TSTART
        Set tPtr = 0
        While $ListNext(tAuditChatIds, tPtr, tChatId) {
            Set tRS1 = tLlmIns.%Execute(tNow, tChatId)
            If tRS1.%SQLCODE < 0 {
                Set tSC = $$$ERROR($$$GeneralError, "Audit.LlmCall INSERT failed for chatId="_tChatId_" SQLCODE="_tRS1.%SQLCODE_" "_tRS1.%Message)
                TROLLBACK
                Quit
            }
            Do tRS1.%Close()
            Set tRS2 = tToolIns.%Execute(tNow, tChatId)
            If tRS2.%SQLCODE < 0 {
                Set tSC = $$$ERROR($$$GeneralError, "Audit.ToolCall INSERT failed for chatId="_tChatId_" SQLCODE="_tRS2.%SQLCODE_" "_tRS2.%Message)
                TROLLBACK
                Quit
            }
            Do tRS2.%Close()
        }
        If $$$ISERR(tSC) Quit
        TCOMMIT

        ; Phase 4: 10 search-keyed Chat.History rows for AC-8 cross-agent
        ; isolation. Use a string SessionKey (search-agent rows use
        ; registry GUIDs, NOT integers) — this is the load-bearing
        ; "different keyspace" the per-agent filter must respect.
        Set tSchStmt = ##class(%SQL.Statement).%New()
        Set tSC = tSchStmt.%Prepare("INSERT INTO SessionAgent_Chat.History (AgentName, SessionKey, PortalUser, CreatedAt, UpdatedAt) VALUES ('message-search', ?, ?, ?, ?)")
        If $$$ISERR(tSC) Quit
        TSTART
        For i = 1:1:10 {
            Set tSk = "PurgeTest73-S" _ i
            Set tRS = tSchStmt.%Execute(tSk, ..#PortalUser, tNow, tNow)
            If tRS.%SQLCODE < 0 {
                Set tSC = $$$ERROR($$$GeneralError, "Search Chat.History INSERT failed at i="_i_" SQLCODE="_tRS.%SQLCODE_" "_tRS.%Message)
                TROLLBACK
                Quit
            }
            Do tRS.%Close()
        }
        If $$$ISERR(tSC) Quit
        TCOMMIT
    }
    Catch ex {
        ; Defensive TROLLBACK for any phase that threw a non-SQLCODE
        ; runtime exception (e.g., <UNDEFINED>) mid-TSTART. The SQLCODE
        ; branches above explicitly TROLLBACK before Quit; this Catch
        ; covers the unexpected-exception path so the test process never
        ; leaves a dangling transaction (lock-retention risk on a
        ; long-running test harness).
        If $TLevel { TROLLBACK }
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>One-shot fixture teardown (AC-5). Calls
/// <method>KillTestData</method> to remove every fixture row by
/// scoped predicate; idempotent (re-running on already-clean state
/// is a no-op).</p>
Method OnAfterAllTests() As %Status
{
    Quit ..KillTestData()
}

/// <p>Per-test setup is intentionally a no-op (AC-4). The 1,000-row
/// fixture is too expensive to rebuild per test; per-test isolation
/// comes from the test methods operating on disjoint subsets of
/// the lattice (see class doc-comment §"Test method execution
/// order").</p>
Method OnBeforeOneTest() As %Status
{
    Quit $$$OK
}

/// <p>Class-level fixture cleanup helper. Removes ALL fixture rows by
/// scoped predicate:</p>
/// <ul>
/// <li><code>Ens.MessageHeader</code>:
///     <code>SessionId BETWEEN RangeStart AND RangeEnd</code>.</li>
/// <li><code>Chat.History</code>: scoped by <code>PortalUser</code>
///     equality (covers BOTH the inspection-keyed rows AND the
///     search-keyed rows in one DELETE).</li>
/// <li><code>Audit.LlmCall</code> + <code>Audit.ToolCall</code>: scoped
///     by <code>ChatHistoryId IN (&lt;the fixture chat IDs&gt;)</code> —
///     however the chat rows may be gone by the time cleanup runs
///     (TestPurgeRemovesOrphans deletes 200 of them mid-test), so we
///     use a self-join-style predicate that targets ANY orphaned audit
///     row whose <code>ChatHistoryId</code> no longer references a
///     <code>Chat.History</code> row. Since the fixture is the ONLY
///     test-only audit-data path, this predicate cleans up reliably
///     after either test outcome.</li>
/// </ul>
/// <p>Idempotent: each DELETE returns SQLCODE=0 (rows deleted) or
/// SQLCODE=100 (no matching rows); both are success. Per project rule
/// §"Pattern Replication Completeness", re-running after clean state
/// must not error.</p>
Method KillTestData() As %Status [ Private ]
{
    Set tSC = $$$OK
    Try {
        ; Step 1 — delete audit rows by fixture-marker properties
        ; (Provider+Model+counters for LlmCall; ToolName+ArgsJson+
        ; ResultJson+LatencyMs for ToolCall). Marker-based predicates
        ; are robust to mid-test chat-row deletion: a chat-row-join
        ; predicate would miss audit rows whose parent Chat.History
        ; row was already deleted by Test1RemovesOrphans.
        Set tDelLlm = ##class(%SQL.Statement).%New()
        Set tSC = tDelLlm.%Prepare("DELETE FROM SessionAgent_Audit.LlmCall WHERE %EXACT(Provider)='openai' AND %EXACT(Model)='gpt-4.1-mini' AND RequestTokens=100 AND ResponseTokens=50 AND LatencyMs=250 AND %EXACT(StopReason)='stop'")
        If $$$ISERR(tSC) Quit
        Set tDelLlmRS = tDelLlm.%Execute()
        Do tDelLlmRS.%Close()

        Set tDelTool = ##class(%SQL.Statement).%New()
        Set tSC = tDelTool.%Prepare("DELETE FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName)='session_summary' AND %EXACT(ArgsJson)='{}' AND %EXACT(ResultJson)='{}' AND LatencyMs=100")
        If $$$ISERR(tSC) Quit
        Set tDelToolRS = tDelTool.%Execute()
        Do tDelToolRS.%Close()

        ; Step 2 — delete Chat.History rows by PortalUser scope.
        Set tDelChat = ##class(%SQL.Statement).%New()
        Set tSC = tDelChat.%Prepare("DELETE FROM SessionAgent_Chat.History WHERE %EXACT(PortalUser) = ?")
        If $$$ISERR(tSC) Quit
        Set tDelChatRS = tDelChat.%Execute(..#PortalUser)
        Do tDelChatRS.%Close()

        ; Step 3 — delete Ens.MessageHeader rows by integer-range scope.
        Set tDelEns = ##class(%SQL.Statement).%New()
        Set tSC = tDelEns.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?")
        If $$$ISERR(tSC) Quit
        Set tDelEnsRS = tDelEns.%Execute(..#RangeStart, ..#RangeEnd)
        Do tDelEnsRS.%Close()
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Headline test (AC-6). Simulates a partial purge of 300 sessions
/// (200 with-chat: ids 1..200 of the fixture; 100 without-chat: ids
/// 901..1000), invokes the sweep, asserts the surviving chat-row
/// count.</p>
///
/// <p>Pre-state: 1,000 Ens rows (sessions 1..1000); 600 Inspection
/// chat rows (1..600); 50 audit pairs (1..50).</p>
/// <p>Mid-state (after Ens DELETE): 700 Ens rows (201..900); 600
/// chat rows; orphans = 200 (chat rows 1..200 reference deleted Ens
/// sessions; chat rows 201..600 are NOT orphans because Ens
/// 201..900 still exist).</p>
/// <p>Post-state (after sweep): 700 Ens rows; 400 chat rows
/// (201..600); 0 audit rows (the 50 audit pairs cascaded with their
/// parent chat rows 1..50).</p>
Method Test1RemovesOrphans()
{
    ; Step 1 — simulate Ens.MessageHeader.Purge() removing 300 sessions:
    ; 200 with-chat (sessions 1..200 of the fixture) +
    ; 100 without-chat (sessions 901..1000).
    Set tSidLow1 = ..#RangeStart                  ; 90000001 (session 1)
    Set tSidHigh1 = ..#RangeStart + 199           ; 90000200 (session 200)
    Set tSidLow2 = ..#RangeStart + 900            ; 90000901 (session 901)
    Set tSidHigh2 = ..#RangeStart + 999           ; 90001000 (session 1000)

    Set tDel1 = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tDel1.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?"), "DELETE prepare ok")
    Set tDel1RS = tDel1.%Execute(tSidLow1, tSidHigh1)
    Do $$$AssertEquals(tDel1RS.%SQLCODE, 0, "DELETE 200 with-chat sessions SQLCODE=0")
    Do tDel1RS.%Close()

    Set tDel1RS2 = tDel1.%Execute(tSidLow2, tSidHigh2)
    Do $$$AssertEquals(tDel1RS2.%SQLCODE, 0, "DELETE 100 without-chat sessions SQLCODE=0")
    Do tDel1RS2.%Close()

    ; Step 2 — invoke the sweep.
    Set tInst = ##class(SessionAgent.Task.PurgeOrphanedChatHistory).%New()
    Set tSweepSC = tInst.OnTask()
    Do $$$AssertStatusOK(tSweepSC, "OnTask returns OK")

    ; Step 3 — assert 400 inspection chat rows remain in the fixture
    ; range. The sweep should have deleted exactly 200 (sessions 1..200);
    ; 400 should remain (sessions 201..600).
    Set tSidStart = (..#RangeStart) _ ""
    Set tSidEnd = (..#RangeStart + 599) _ ""
    Set tCntStmt = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tCntStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Chat.History WHERE %EXACT(AgentName)='session-inspection' AND %EXACT(PortalUser)=? AND SessionKey >= ? AND SessionKey <= ?"), "COUNT prepare ok")
    Set tCntRS = tCntStmt.%Execute(..#PortalUser, tSidStart, tSidEnd)
    Do tCntRS.%Next()
    Set tRemaining = tCntRS.%Get("Cnt")
    Do tCntRS.%Close()
    Do $$$AssertEquals(tRemaining, 400, "400 chat rows remain after sweep (200 fixture-deleted as orphans; 400 surviving for sessions 201..600)")

    ; Step 4 — assert the 200 deleted-orphan chat rows are gone
    ; specifically (sessions 1..200).
    Set tSidEnd2 = (..#RangeStart + 199) _ ""
    Set tCntRS2 = tCntStmt.%Execute(..#PortalUser, tSidStart, tSidEnd2)
    Do tCntRS2.%Next()
    Set tDeleted = tCntRS2.%Get("Cnt")
    Do tCntRS2.%Close()
    Do $$$AssertEquals(tDeleted, 0, "0 chat rows for sessions 1..200 (deleted as orphans)")

    ; Step 5 — assert the 400 surviving chat rows match sessions 201..600.
    Set tSidStart3 = (..#RangeStart + 200) _ ""
    Set tSidEnd3 = (..#RangeStart + 599) _ ""
    Set tCntRS3 = tCntStmt.%Execute(..#PortalUser, tSidStart3, tSidEnd3)
    Do tCntRS3.%Next()
    Set tSurviving = tCntRS3.%Get("Cnt")
    Do tCntRS3.%Close()
    Do $$$AssertEquals(tSurviving, 400, "400 chat rows survive for sessions 201..600 (Ens rows still alive)")

    Quit
}

/// <p>Audit-cascade test (AC-7) — Story 7.1 Option B contract. Asserts
/// that every fixture audit row pair attached to the 50 deleted-orphan
/// chat rows (sessions 1..50) was cascaded by the sweep. This test
/// re-asserts the post-sweep state from <method>Test1RemovesOrphans</method>:
/// the 50 chat rows 1..50 are deleted, and their attached audit rows
/// (50 LlmCall + 50 ToolCall = 100 audit rows total) must be gone.</p>
///
/// <p>The simplification — slicing the 50 audit-attached rows out of
/// the 200 deleted-orphan rows rather than full-matrix coverage — is
/// documented in the spec (AC-7 #2/#3 explicitly authorize the
/// "rows 1..50 audit subset" assertion form). The test scope is
/// "audit rows attached to deleted chat rows ARE cascaded", not
/// full-matrix.</p>
///
/// <p>Test-method execution dependency: this test relies on
/// <method>Test1RemovesOrphans</method> having run first. The numeric
/// prefix on method names enforces the alphabetic-sort ordering
/// (<code>Test1...</code> &lt; <code>Test2...</code> &lt;
/// <code>Test3...</code>) that <code>%UnitTest</code> uses. If the
/// methods ran out of order or in isolation, this test would fail
/// because the audit rows would still be present.</p>
Method Test2CascadesAuditRows()
{
    ; Assert 0 LlmCall rows match the fixture marker — every fixture
    ; LlmCall was attached to chat rows 1..50, all of which were
    ; deleted as orphans by Test1RemovesOrphans, so the sweep's
    ; Option B audit-cascade should have deleted them all.
    Set tCntLlm = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tCntLlm.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Audit.LlmCall WHERE %EXACT(Provider)='openai' AND %EXACT(Model)='gpt-4.1-mini' AND RequestTokens=100 AND ResponseTokens=50 AND LatencyMs=250 AND %EXACT(StopReason)='stop'"), "LlmCall COUNT prepare ok")
    Set tLlmRS = tCntLlm.%Execute()
    Do tLlmRS.%Next()
    Set tLlmCount = tLlmRS.%Get("Cnt")
    Do tLlmRS.%Close()
    Do $$$AssertEquals(tLlmCount, 0, "0 fixture LlmCall rows remain — Option B cascade deleted all 50 attached to orphan chat rows 1..50")

    Set tCntTool = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tCntTool.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Audit.ToolCall WHERE %EXACT(ToolName)='session_summary' AND %EXACT(ArgsJson)='{}' AND %EXACT(ResultJson)='{}' AND LatencyMs=100"), "ToolCall COUNT prepare ok")
    Set tToolRS = tCntTool.%Execute()
    Do tToolRS.%Next()
    Set tToolCount = tToolRS.%Get("Cnt")
    Do tToolRS.%Close()
    Do $$$AssertEquals(tToolCount, 0, "0 fixture ToolCall rows remain — Option B cascade deleted all 50 attached to orphan chat rows 1..50")

    Quit
}

/// <p>Per-agent filter test (AC-8) — defense-in-depth. Asserts the
/// 10 search-keyed fixture rows
/// (<code>AgentName='message-search'</code>) are untouched by the
/// Inspection-keyed sweep. The sweep's WHERE clause filters
/// <code>%EXACT(AgentName) = 'session-inspection'</code>; without
/// that filter, search-keyed rows whose
/// <code>SessionKey="PurgeTest73-S"_i</code> doesn't convert to a
/// matching <code>Ens.MessageHeader.SessionId</code> integer would
/// also be deleted as orphans (cross-agent contamination).</p>
///
/// <p>Test-method execution order: this test runs LAST
/// (<code>Test3...</code> alphabetic suffix). The 10 search-keyed rows
/// were inserted in <method>OnBeforeAllTests</method> and remain
/// untouched throughout the prior tests (the sweep's per-agent filter
/// prevents them from being considered orphan candidates).</p>
Method Test3RespectsAgentNameFilter()
{
    Set tCntStmt = ##class(%SQL.Statement).%New()
    Do $$$AssertStatusOK(tCntStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Chat.History WHERE %EXACT(AgentName)='message-search' AND %EXACT(PortalUser)=? AND SessionKey %STARTSWITH 'PurgeTest73-S'"), "Search-keyed COUNT prepare ok")
    Set tRS = tCntStmt.%Execute(..#PortalUser)
    Do tRS.%Next()
    Set tCount = tRS.%Get("Cnt")
    Do tRS.%Close()
    Do $$$AssertEquals(tCount, 10, "10 search-keyed (AgentName='message-search') chat rows untouched by Inspection-keyed sweep — per-agent filter respected")
    Quit
}

}
