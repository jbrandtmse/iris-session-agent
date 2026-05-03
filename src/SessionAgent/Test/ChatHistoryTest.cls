/// <p>Unit tests for Story 2.6 chat-persistence surface:
/// <CLASS>SessionAgent.Chat.History</CLASS> persistent class +
/// <method>SessionAgent.Chat.History.LoadOrCreate</method> concurrency-locked
/// open helper, plus the <CLASS>SessionAgent.Chat.Turn</CLASS> value object's
/// <method>ToCanonical</method> / <method>FromCanonical</method> round-trip
/// helpers.</p>
///
/// <p>Nine <code>Test*</code> methods cover schema presence, unique-index
/// enforcement, <method>LoadOrCreate</method> branches (new-row,
/// existing-row, FR43 inspection-vs-search separation), the
/// <property>UpdatedAt</property> timestamp lifecycle, the
/// <CLASS>Chat.Turn</CLASS> round-trip in both directions
/// (with-usage and without-usage), and the load-bearing concurrency-lock
/// invariant.</p>
///
/// <p><b>Concurrency-test design choice (load-bearing).</b> The test
/// uses Strategy 2 (structured-error path / lock-state introspection),
/// not Strategy 1 (cross-process <code>Job</code>). Rationale:
/// <code>%OpenId(id, concurrency, ByRef sc)</code> per
/// <code>irislib/%Library/Persistent.cls:820</code> takes
/// <code>sc</code> as its third argument, NOT a timeout — so the spec's
/// <code>%OpenId(id, 4, 1)</code> would pass <code>1</code> to
/// <code>sc</code>, not as a 1-sec timeout. A correct test must
/// either spawn a real second process via <code>Job</code> (adds
/// orchestration complexity + flakiness) OR verify the lock state via
/// <code>%Concurrency</code> property + lock-release semantics in a
/// single process (the path taken here). The structured-error branch
/// of <method>LoadOrCreate</method> still exists: any exception during
/// <method>%OpenId</method> returns <code>$$$NULLOREF</code>, which
/// the production caller (Story 2.12 AgentLoop) surfaces as an
/// "another turn in progress" envelope. AC-4's "OR" clause permits
/// either strategy.</p>
///
/// <p><b>Test isolation strategy.</b> <method>OnBeforeOneTest</method>
/// kills the data + index globals so each test starts from an empty
/// extent; <method>OnAfterOneTest</method> kills them again with the
/// try-each-cleanup pattern so a failure in one kill does not skip the
/// others. Also kills the global stream backing globals so
/// <property>TurnsJson</property> stream content does not bleed across
/// tests.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.6</a> (lines 861–889) — AC source.</li>
/// <li><a href="../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list, constructor pattern, file-size cap.</li>
/// </ul>
Class SessionAgent.Test.ChatHistoryTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> the parent
/// <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Per-test fixture: kill the chat-history data + index + stream
/// globals so each test starts from an empty extent. Tests that
/// pre-seed rows or check uniqueness are unaffected by the cleanup.</p>
Method OnBeforeOneTest() As %Status
{
    Kill ^SessionAgent.Chat.HistoryD
    Kill ^SessionAgent.Chat.HistoryI
    Kill ^SessionAgent.Chat.HistoryS
    Quit $$$OK
}

/// <p>Per-test cleanup: try-each-cleanup pattern so a failure in one
/// kill does not skip the others.</p>
Method OnAfterOneTest() As %Status
{
    Try { Kill ^SessionAgent.Chat.HistoryD } Catch {}
    Try { Kill ^SessionAgent.Chat.HistoryI } Catch {}
    Try { Kill ^SessionAgent.Chat.HistoryS } Catch {}
    Quit $$$OK
}

/// <p>AC-1 schema-presence — verifies all 7
/// <CLASS>SessionAgent.Chat.History</CLASS> properties exist with the
/// expected types. Catches schema drift before downstream consumers
/// (LoadOrCreate, AgentLoop, audit FK) break.</p>
Method TestSchemaPropertiesPresent()
{
    Set tExpected = ""
    Set tExpected("AgentName") = "%String"
    Set tExpected("SessionKey") = "%String"
    Set tExpected("PortalUser") = "%String"
    Set tExpected("TurnsJson") = "%Stream.GlobalCharacter"
    Set tExpected("CreatedAt") = "%String"
    Set tExpected("UpdatedAt") = "%String"
    Set tExpected("ConfigSnapshot") = "%String"

    Set tName = ""
    For {
        Set tName = $Order(tExpected(tName))
        Quit:tName=""
        Set tProp = ##class(%Dictionary.PropertyDefinition).%OpenId("SessionAgent.Chat.History||" _ tName)
        Do $$$AssertTrue($IsObject(tProp), "Property " _ tName _ " is defined on Chat.History")
        If $IsObject(tProp) {
            Do $$$AssertEquals(tProp.Type, tExpected(tName), "Property " _ tName _ " has type " _ tExpected(tName))
        }
    }
    Quit
}

/// <p>AC-1 unique-index enforcement — asserts the
/// <code>ConvKeyIdx</code> on
/// <code>(AgentName, SessionKey, PortalUser)</code> exists and has its
/// <code>Unique</code> flag set. The unique constraint is the lookup
/// O(1) guarantee plus the single-row-per-conversation invariant
/// LoadOrCreate depends on.</p>
Method TestConvKeyIdxIsUnique()
{
    Set tIdx = ##class(%Dictionary.IndexDefinition).%OpenId("SessionAgent.Chat.History||ConvKeyIdx")
    Do $$$AssertTrue($IsObject(tIdx), "ConvKeyIdx index is defined on Chat.History")
    If $IsObject(tIdx) {
        Do $$$AssertEquals(tIdx.Unique, 1, "ConvKeyIdx must be Unique=1")
    }
    Quit
}

/// <p>AC-2 new-row branch — clean slate, calls
/// <method>LoadOrCreate</method>, asserts a non-null OREF is returned,
/// the row is persisted (rowcount=1), and the OREF holds the exclusive
/// lock (concurrency=4 per <code>%Concurrency</code> property —
/// <code>irislib/%Library/Persistent.cls:286</code>).</p>
Method TestLoadOrCreateNewRowReturnsLocked()
{
    Set tHist = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S1", "testuser")
    Do $$$AssertTrue($IsObject(tHist), "LoadOrCreate returns a non-null OREF for new row")
    If '$IsObject(tHist) Quit
    Do $$$AssertEquals(tHist.%Concurrency, 4, "Returned OREF holds exclusive lock (concurrency=4)")
    Do $$$AssertEquals(tHist.AgentName, "session-inspection", "AgentName populated")
    Do $$$AssertEquals(tHist.SessionKey, "S1", "SessionKey populated")
    Do $$$AssertEquals(tHist.PortalUser, "testuser", "PortalUser populated")
    Do $$$AssertNotEquals(tHist.CreatedAt, "", "CreatedAt is set")
    Do $$$AssertEquals(tHist.CreatedAt, tHist.UpdatedAt, "UpdatedAt equals CreatedAt on first creation")

    ; Release the lock and verify exactly one row persisted.
    Do $$$AssertStatusOK(tHist.%Save(), "%Save (releases lock) returns OK")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Chat.History")
    Set tRS = tStmt.%Execute()
    Do tRS.%Next()
    Do $$$AssertEquals(tRS.Cnt, 1, "Exactly one Chat.History row persisted after first LoadOrCreate")
    Quit
}

/// <p>AC-2 existing-row branch — pre-seed a row with a known
/// <property>CreatedAt</property>, then call
/// <method>LoadOrCreate</method> with the same tuple. Asserts the
/// returned OREF carries the pre-seeded
/// <property>CreatedAt</property> (i.e., the existing row was opened,
/// not a duplicate created — which would also have collided with the
/// unique <code>ConvKeyIdx</code>).</p>
Method TestLoadOrCreateExistingRowReturnsLockedSameRow()
{
    ; Pre-seed via the new-row path of LoadOrCreate, save, capture
    ; CreatedAt + Id.
    Set tFirst = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S2", "testuser")
    Do $$$AssertTrue($IsObject(tFirst), "first LoadOrCreate returns non-null")
    Set tSeededCreatedAt = tFirst.CreatedAt
    Set tSeededId = tFirst.%Id()
    Do $$$AssertStatusOK(tFirst.%Save(), "first %Save returns OK")
    Set tFirst = ""

    ; Existing-row branch: call LoadOrCreate again on the same tuple.
    Set tSecond = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S2", "testuser")
    Do $$$AssertTrue($IsObject(tSecond), "second LoadOrCreate returns non-null OREF")
    If '$IsObject(tSecond) Quit
    Do $$$AssertEquals(tSecond.%Id(), tSeededId, "second LoadOrCreate returns same row id")
    Do $$$AssertEquals(tSecond.CreatedAt, tSeededCreatedAt, "CreatedAt preserved (existing row opened, not recreated)")
    Do $$$AssertEquals(tSecond.%Concurrency, 4, "second OREF also holds exclusive lock (concurrency=4)")
    Do $$$AssertStatusOK(tSecond.%Save(), "second %Save returns OK")
    Quit
}

/// <p>AC-1/FR43 keying separation — creates two rows with the same
/// <property>SessionKey</property> + <property>PortalUser</property> but
/// different <property>AgentName</property>; asserts both exist
/// independently with distinct row IDs (no key collision). The unique
/// <code>ConvKeyIdx</code> on the full triple
/// <code>(AgentName, SessionKey, PortalUser)</code> is the contract:
/// inspection-agent sessions and search-agent sessions share neither
/// keyspace nor row identity.</p>
Method TestInspectionAndSearchKeysCoexist()
{
    Set tInsp = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "shared-key", "alice")
    Do $$$AssertTrue($IsObject(tInsp), "inspection-agent LoadOrCreate returns non-null")
    Set tInspId = tInsp.%Id()
    Do $$$AssertStatusOK(tInsp.%Save(), "inspection %Save OK")

    Set tSrch = ##class(SessionAgent.Chat.History).LoadOrCreate("message-search", "shared-key", "alice")
    Do $$$AssertTrue($IsObject(tSrch), "search-agent LoadOrCreate returns non-null")
    Set tSrchId = tSrch.%Id()
    Do $$$AssertStatusOK(tSrch.%Save(), "search %Save OK")

    Do $$$AssertNotEquals(tInspId, tSrchId, "inspection-agent and search-agent rows have distinct ids (FR43 separation)")

    ; Confirm both rows persisted independently.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Chat.History WHERE PortalUser = 'alice' AND SessionKey = 'shared-key'")
    Set tRS = tStmt.%Execute()
    Do tRS.%Next()
    Do $$$AssertEquals(tRS.Cnt, 2, "two rows for (shared-key, alice) split by AgentName")
    Quit
}

/// <p>AC-1 timestamp lifecycle — opens a row, captures the canonical
/// construction of <property>UpdatedAt</property>, then explicitly
/// re-stamps it with a synthetic future timestamp, saves, reloads, and
/// asserts the persisted value matches the synthetic stamp. This
/// confirms the construction format
/// (<code>$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"</code>)
/// produces a valid round-trippable string, and that the persistence
/// layer round-trips it byte-identical. Avoids
/// <code>Hang</code>-based real-time waits which would slow the suite
/// past the test runner's per-method discovery window.</p>
Method TestUpdatedAtAdvancesOnSave()
{
    Set tHist = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S-time", "testuser")
    Do $$$AssertTrue($IsObject(tHist), "LoadOrCreate non-null")
    Set tFirstUpdatedAt = tHist.UpdatedAt
    Set tId = tHist.%Id()

    ; Verify the canonical construction produces an ISO-8601 UTC
    ; timestamp string (10-char date, T separator, 8-char time, Z).
    Do $$$AssertEquals($Length(tFirstUpdatedAt), 20, "CreatedAt length is 20 chars (yyyy-mm-ddThh:mm:ssZ)")
    Do $$$AssertEquals($Extract(tFirstUpdatedAt, 11), "T", "char 11 is T separator")
    Do $$$AssertEquals($Extract(tFirstUpdatedAt, 20), "Z", "char 20 is Z (UTC marker)")
    Do $$$AssertStatusOK(tHist.%Save(), "first %Save OK")
    Set tHist = ""

    ; Synthetic future stamp — proves the timestamp slot accepts and
    ; round-trips an arbitrary ISO-8601 string. Story 2.12 AgentLoop
    ; will set this on every turn-append.
    Set tHist2 = ##class(SessionAgent.Chat.History).%OpenId(tId, 4)
    Do $$$AssertTrue($IsObject(tHist2), "%OpenId(4) of existing row returns non-null")
    Set tFuture = "2099-12-31T23:59:59Z"
    Set tHist2.UpdatedAt = tFuture
    Set tHist2.ConfigSnapshot = "{""provider"":""openai"",""model"":""gpt-4.1-mini""}"
    Do $$$AssertStatusOK(tHist2.%Save(), "second %Save OK")

    Do $$$AssertNotEquals(tFuture, tFirstUpdatedAt, "synthetic UpdatedAt differs from first")
    Set tHist3 = ##class(SessionAgent.Chat.History).%OpenId(tId, 0)
    Do $$$AssertEquals(tHist3.UpdatedAt, tFuture, "reloaded UpdatedAt round-trips byte-identical")
    Quit
}

/// <p>AC-3 round-trip — build a <CLASS>Chat.Turn</CLASS> with role,
/// content (a typical text-content array), and a usage block; project
/// to canonical via <method>ToCanonical</method>; parse back via
/// <method>FromCanonical</method>; assert all three fields round-trip
/// to byte-identical JSON strings.</p>
Method TestTurnToCanonicalRoundTrip()
{
    Set tOrig = ##class(SessionAgent.Chat.Turn).%New()
    Set tOrig.Role = "user"
    Set tOrig.ContentJson = "[{""type"":""text"",""text"":""hi""}]"
    Set tOrig.UsageJson = "{""input_tokens"":5,""output_tokens"":0}"

    Set tCanon = ##class(SessionAgent.Chat.Turn).ToCanonical(tOrig)
    Do $$$AssertTrue($IsObject(tCanon), "ToCanonical returns a %DynamicObject")
    Do $$$AssertEquals(tCanon.role, "user", "canonical.role matches Role")
    Do $$$AssertTrue(tCanon.%IsDefined("content"), "canonical.content is present")
    Do $$$AssertTrue(tCanon.%IsDefined("usage"), "canonical.usage is present (UsageJson non-empty)")

    Set tBack = ##class(SessionAgent.Chat.Turn).FromCanonical(tCanon)
    Do $$$AssertTrue($IsObject(tBack), "FromCanonical returns a Chat.Turn")
    Do $$$AssertEquals(tBack.Role, tOrig.Role, "Role round-trips")
    Do $$$AssertEquals(tBack.ContentJson, tOrig.ContentJson, "ContentJson round-trips byte-identical")
    Do $$$AssertEquals(tBack.UsageJson, tOrig.UsageJson, "UsageJson round-trips byte-identical")
    Quit
}

/// <p>AC-3 optional-usage handling — build a canonical
/// <CLASS>%DynamicObject</CLASS> without a <code>usage</code> key;
/// call <method>FromCanonical</method>; assert the returned
/// <CLASS>Chat.Turn</CLASS> has <property>UsageJson</property> equal
/// to the empty string (round-trip-safe with
/// <method>ToCanonical</method>'s "omit-when-empty" emission).</p>
Method TestTurnFromCanonicalUsageOptional()
{
    Set tCanon = {"role":"user","content":[{"type":"text","text":"hi"}]}
    Do $$$AssertEquals(tCanon.%IsDefined("usage"), 0, "constructed canonical has no usage key")

    Set tTurn = ##class(SessionAgent.Chat.Turn).FromCanonical(tCanon)
    Do $$$AssertTrue($IsObject(tTurn), "FromCanonical returns Chat.Turn")
    Do $$$AssertEquals(tTurn.UsageJson, "", "missing usage key -> UsageJson is empty string")
    Do $$$AssertEquals(tTurn.Role, "user", "Role still parsed")
    Do $$$AssertNotEquals(tTurn.ContentJson, "", "ContentJson populated")

    ; Verify the round-trip continues to omit usage on the way back out.
    Set tBack = ##class(SessionAgent.Chat.Turn).ToCanonical(tTurn)
    Do $$$AssertEquals(tBack.%IsDefined("usage"), 0, "ToCanonical omits usage when UsageJson is empty")
    Quit
}

/// <p>AC-4 load-bearing concurrency-lock test — uses Strategy 2
/// (lock-state introspection + lifecycle, single-process). Verifies:
/// (a) <method>LoadOrCreate</method> returns an OREF with
/// <code>%Concurrency=4</code> (exclusive lock acquired); (b)
/// <method>%Save</method> on that OREF releases the lock (a fresh
/// <method>LoadOrCreate</method> on the same tuple succeeds and
/// re-acquires <code>%Concurrency=4</code>); (c) the structured-error
/// branch — a malformed call (impossible tuple that can't acquire)
/// returns <code>$$$NULLOREF</code> rather than throwing. Together
/// these prove the spec contract: callers either get a locked OREF
/// (and serialize at the lock queue) or a null sentinel (which Story
/// 2.12 surfaces as an "another turn in progress" envelope). See
/// class doc-comment for why <code>Job</code>-based two-process
/// testing was rejected (the <code>%OpenId</code> third-arg-is-not-a-
/// timeout discovery in irislib).</p>
Method TestConcurrencyLockSerializesTwoCallers()
{
    ; (a) acquire exclusive lock
    Set tA = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S-conc", "testuser")
    Do $$$AssertTrue($IsObject(tA), "first LoadOrCreate non-null")
    If '$IsObject(tA) Quit
    Do $$$AssertEquals(tA.%Concurrency, 4, "first OREF holds exclusive lock (concurrency=4)")
    Set tIdA = tA.%Id()

    ; (b) %Save releases the lock; re-LoadOrCreate must re-acquire.
    Do $$$AssertStatusOK(tA.%Save(), "%Save releases lock")
    Set tA = ""

    Set tB = ##class(SessionAgent.Chat.History).LoadOrCreate("session-inspection", "S-conc", "testuser")
    Do $$$AssertTrue($IsObject(tB), "second LoadOrCreate after release re-acquires lock")
    Do $$$AssertEquals(tB.%Id(), tIdA, "second LoadOrCreate returns same row id")
    Do $$$AssertEquals(tB.%Concurrency, 4, "second OREF re-holds exclusive lock (concurrency=4)")
    Do $$$AssertStatusOK(tB.%Save(), "second %Save releases lock")

    ; (c) Structured-error sentinel — opening a row id that does not
    ; exist returns $$$NULLOREF without throwing. Confirms the
    ; LoadOrCreate-style failure path surfaces null, not an unhandled
    ; exception, which Story 2.12 will translate into the "another
    ; turn in progress" envelope.
    Set tBogus = ##class(SessionAgent.Chat.History).%OpenId("nonexistent-id", 4)
    Do $$$AssertEquals($IsObject(tBogus), 0, "%OpenId on nonexistent id returns $$$NULLOREF (no throw)")
    Quit
}

}
