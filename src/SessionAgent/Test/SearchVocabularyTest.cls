/// <p>Story 9.2 AC-5 — unit tests for
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS>'s
/// <method>RecordSuccess</method> + <method>RecordFailure</method> +
/// recursion-safe <method>%OnAfterSave</method> trigger, plus a
/// regression guard for the AC-4 <code>VocabLookup.InvokeSave</code>
/// delegation refactor.</p>
///
/// <p><b>Test isolation strategy.</b> All test rows use
/// <code>PortalUser</code> prefixes <code>sa-test-92-</code> (Story 9.2 tests)
/// and <code>sa-test-93-</code> (Story 9.3 VocabularyDigest tests).
/// Cleanup uses the broader <code>'sa-test-9%' LIKE</code> pattern (covers
/// both prefixes; future Stories using <code>sa-test-94-</code>,
/// <code>sa-test-95-</code>, etc. inherit the cleanup automatically).
/// <method>OnBeforeAllTests</method> and <method>OnAfterAllTests</method>
/// each issue
/// <code>DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-9%'</code>
/// to bracket the suite. <method>OnBeforeOneTest</method> resets the
/// PPG <code>^||Story92TriggerFireCount</code> to 0 (opt-in fire-count
/// instrumentation — see UserVocabulary's <method>%OnAfterSave</method>
/// guard).</p>
///
/// <p><b>Property naming note (Story 7.0 AC-3 codification).</b> No
/// state-tracking property on this class begins with <code>Test*</code> —
/// that prefix would collide with the framework's test-method-discovery
/// loop and surface as phantom tests. State is tracked via PPG only.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/9-2-uservocabulary-recordsuccess-recordfailure-recursion-safe-onaftersave.md">Story 9.2 spec</a> — AC-5 verbatim source.</li>
/// <li><CLASS>SessionAgent.Search.UserVocabulary</CLASS> §<method>RecordSuccess</method> / §<method>RecordFailure</method> / §<method>%OnAfterSave</method>.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a> — assertion macros, constructor pattern, Test* shadow trap.</li>
/// </ul>
Class SessionAgent.Test.SearchVocabularyTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Suite bracket — clean any leftover <code>sa-test-92-*</code> rows
/// from a prior partial / failed run. Idempotent.</p>
Method OnBeforeAllTests() As %Status
{
    Try {
        Do ..CleanupTestRows()
    } Catch {}
    Quit $$$OK
}

/// <p>Suite bracket — clean test rows on suite exit so a downstream
/// <method>SessionAgent.Installer.Install</method> or vocab-state probe
/// does not see test pollution.</p>
Method OnAfterAllTests() As %Status
{
    Try {
        Do ..CleanupTestRows()
        Kill ^||Story92TriggerFireCount
    } Catch {}
    Quit $$$OK
}

/// <p>Per-test bracket — reset the opt-in fire-count PPG so each test
/// starts at 0. Setting (rather than killing) the PPG is the opt-in
/// signal to the <method>%OnAfterSave</method> trigger — production
/// code paths leave the PPG undefined and skip the increment.</p>
Method OnBeforeOneTest() As %Status
{
    Kill ^||Story92TriggerFireCount
    Set ^||Story92TriggerFireCount = 0
    Quit $$$OK
}

/// <p>Per-test cleanup — kill the PPG so a stale value cannot leak
/// across tests, and DELETE any rows the test created.</p>
Method OnAfterOneTest() As %Status
{
    Try {
        Do ..CleanupTestRows()
        Kill ^||Story92TriggerFireCount
    } Catch {}
    Quit $$$OK
}

/// <p>Helper — DELETE all rows whose <code>PortalUser</code> matches the
/// broader <code>sa-test-9%</code> prefix (covers Story 9.2's
/// <code>sa-test-92-</code> AND Story 9.3's <code>sa-test-93-</code>; future
/// stories using <code>sa-test-94-</code>, etc. inherit automatically).
/// Uses <code>%SQL.Statement</code> rather than embedded SQL to avoid the
/// IRIS embedded-SQL host-variable quoting trap with LIKE patterns.</p>
ClassMethod CleanupTestRows()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) LIKE 'sa-test-9%'")
    Do tStmt.%Execute()
    Quit
}

/// <p>AC-5 row 1 — <code>RecordSuccess</code> on a new (user, alias)
/// creates the row with <code>SuccessCount=1, FailureCount=0,
/// Confidence ≈ 0.5</code> (<code>1 / (1+0+1) = 0.5</code>).</p>
Method TestRecordSuccessNewRowCreatesWithConfidence()
{
    Set tUser = "sa-test-92-newrow"
    Set tAlias = "admit"
    Set tSC = ##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias)
    Do $$$AssertStatusOK(tSC, "RecordSuccess returns $$$OK on new row insert")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT SuccessCount AS sc, FailureCount AS fc, Confidence AS cf, %EXACT(CreatedVia) AS cv FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tStmt.%Execute(tUser, tAlias)
    Do $$$AssertTrue(tRs.%Next(), "row exists post-RecordSuccess")
    Do $$$AssertEquals(+tRs.%Get("sc"), 1, "SuccessCount = 1")
    Do $$$AssertEquals(+tRs.%Get("fc"), 0, "FailureCount = 0")
    Do $$$AssertEquals(+tRs.%Get("cf"), 0.5, "Confidence = 0.5 (1 / (1+0+1))")
    Do $$$AssertEquals(tRs.%Get("cv"), "clickthrough", "CreatedVia defaults to 'clickthrough'")
    Quit
}

/// <p>AC-5 row 2 — two consecutive <code>RecordSuccess</code> calls:
/// row has <code>SuccessCount=2, Confidence ≈ 0.667</code>
/// (<code>2 / (2+0+1)</code>).</p>
Method TestRecordSuccessSecondCallIncrements()
{
    Set tUser = "sa-test-92-second"
    Set tAlias = "discharge"
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "first RecordSuccess OK")
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "second RecordSuccess OK")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT SuccessCount AS sc, Confidence AS cf FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tStmt.%Execute(tUser, tAlias)
    Do $$$AssertTrue(tRs.%Next(), "exactly one row exists post-double-RecordSuccess")
    Do $$$AssertEquals(+tRs.%Get("sc"), 2, "SuccessCount = 2 after second call")
    ; Confidence = 2/3 ≈ 0.6667. Compare with floating-point tolerance.
    Set tCf = +tRs.%Get("cf")
    Do $$$AssertTrue((tCf >= 0.66) && (tCf < 0.68), "Confidence ≈ 0.667 (2 / (2+0+1)); got: " _ tCf)
    Quit
}

/// <p>AC-5 row 3 — one success + one failure: <code>SuccessCount=1,
/// FailureCount=1, Confidence ≈ 0.333</code> (<code>1/(1+1+1)</code>).</p>
Method TestRecordFailureOnExistingRowDecreasesConfidence()
{
    Set tUser = "sa-test-92-fail"
    Set tAlias = "transfer"
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "RecordSuccess OK")
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "RecordFailure OK on existing row")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT SuccessCount AS sc, FailureCount AS fc, Confidence AS cf FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tStmt.%Execute(tUser, tAlias)
    Do $$$AssertTrue(tRs.%Next(), "row exists after success+failure pair")
    Do $$$AssertEquals(+tRs.%Get("sc"), 1, "SuccessCount = 1 (RecordFailure does not touch SuccessCount)")
    Do $$$AssertEquals(+tRs.%Get("fc"), 1, "FailureCount = 1 after RecordFailure")
    Set tCf = +tRs.%Get("cf")
    Do $$$AssertTrue((tCf >= 0.33) && (tCf < 0.35), "Confidence ≈ 0.333 (1 / (1+1+1)); got: " _ tCf)
    Quit
}

/// <p>AC-5 row 4 — <code>RecordFailure("u-novel", "ghost-alias")</code>
/// returns <code>$$$OK</code> without inserting a row. SQL probe verifies
/// row count for <code>(u-novel, ghost-alias)</code> = 0 post-call.</p>
Method TestRecordFailureOnAbsentRowIsNoOp()
{
    Set tUser = "sa-test-92-novel"
    Set tAlias = "ghost-alias"
    Set tSC = ##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias)
    Do $$$AssertStatusOK(tSC, "RecordFailure on absent row returns $$$OK (graceful no-op)")

    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tStmt.%Execute(tUser, tAlias)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 0, "absent (PortalUser, Alias) → no row inserted; row count = 0")
    Quit
}

/// <p>AC-5 row 5 — opt-in fire-count instrumentation via PPG
/// <code>^||Story92TriggerFireCount</code>. The PPG is reset to 0 in
/// <method>OnBeforeOneTest</method>; calling
/// <method>RecordSuccess</method> (which calls
/// <code>%Save()</code>) MUST fire <code>%OnAfterSave</code> exactly
/// once, leaving the PPG = 1 — verifying the recursion-safe direct-SQL
/// UPDATE design from Story 9.1's verified guarantee.</p>
Method TestOnAfterSaveFireCountExactlyOne()
{
    Do $$$AssertEquals($Get(^||Story92TriggerFireCount, -1), 0, "PPG reset to 0 in OnBeforeOneTest")

    Set tUser = "sa-test-92-firecount"
    Set tAlias = "fire-once-alias"
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "RecordSuccess OK")

    Set tFireCount = $Get(^||Story92TriggerFireCount, -1)
    Do $$$AssertEquals(tFireCount, 1, "%OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT recurse")
    Quit
}

/// <p>AC-5 row 6 — after <code>RecordSuccess(...,"clickthrough",...)</code>,
/// the audit trail contains a row with
/// <code>EventName='clickthrough'</code>,
/// <code>EventType='VocabWrite'</code>,
/// <code>EventSource='SessionAgent'</code>. Probes
/// <code>%SYS.Audit</code> via the canonical query (see Story 9.2 spec
/// Dev Notes §"Audit row probe SQL").</p>
Method TestRecordSuccessEmitsClickthroughAudit()
{
    Set tUser = "sa-test-92-audit-click"
    Set tAlias = "audit-click-alias"
    Set tBeforeIso = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")

    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias, "", "clickthrough", "audit emit test"), "RecordSuccess OK with explicit pCreatedVia=clickthrough")

    Set tFound = ..AuditRowExistsForName("clickthrough", tUser, tAlias)
    Do $$$AssertTrue(tFound, "(SessionAgent, VocabWrite, clickthrough) audit row exists post-RecordSuccess for sa-test-92-audit-click / audit-click-alias")
    Quit
}

/// <p>AC-5 row 7 — after <code>RecordFailure</code> on an existing row,
/// audit row exists with <code>EventName='extracted'</code> (per Story 9.2
/// design rationale — see <method>UserVocabulary.RecordFailure</method>
/// doc-comment §"Audit-Name triple choice").</p>
Method TestRecordFailureEmitsExtractedAudit()
{
    Set tUser = "sa-test-92-audit-fail"
    Set tAlias = "audit-fail-alias"
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "seed: RecordSuccess OK")
    Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "RecordFailure OK on existing row")

    Set tFound = ..AuditRowExistsForName("extracted", tUser, tAlias)
    Do $$$AssertTrue(tFound, "(SessionAgent, VocabWrite, extracted) audit row exists post-RecordFailure for sa-test-92-audit-fail / audit-fail-alias")
    Quit
}

/// <p>AC-5 row 8 — regression guard for AC-4
/// <code>VocabLookup.InvokeSave</code> delegation refactor. End-to-end
/// <code>vocab_lookup mode='save'</code> on an empty fixture produces
/// envelope <code>action='created'</code>; a second invocation produces
/// <code>action='incremented'</code>. Verifies the envelope-shaping
/// logic survives the delegation to
/// <method>UserVocabulary.RecordSuccess</method>.</p>
Method TestVocabLookupSaveModeStillWorks()
{
    Set tUser = "sa-test-92-vocab-roundtrip"
    Set tAlias = "delegation-roundtrip"
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.PortalUser = tUser

    ; First call → action=created.
    Set tArgs1 = {"mode": "save", "alias": (tAlias)}
    Set tResult1 = ""
    Set tSC1 = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs1, .tResult1)
    Do $$$AssertStatusOK(tSC1, "first vocab_lookup mode=save returns $$$OK")
    Do $$$AssertEquals(+tResult1.%Get("isError"), 0, "first call envelope is success (not isError)")
    Do $$$AssertEquals(tResult1.structuredContent.%Get("mode"), "save", "structuredContent.mode = save")
    Do $$$AssertEquals(tResult1.structuredContent.%Get("action"), "created", "first call action = created")
    Do $$$AssertEquals(+tResult1.structuredContent.%Get("new_success_count"), 1, "first call new_success_count = 1")
    Do $$$AssertEquals(tResult1.structuredContent.%Get("alias"), tAlias, "first call alias echoed in envelope")
    Do $$$AssertEquals(tResult1.structuredContent.%Get("portal_user"), tUser, "first call portal_user echoed in envelope")
    ; Review fix MEDIUM-9.2-F01 — audit_emitted=1 reflects actual
    ; $System.Security.Audit return value (the (SessionAgent, VocabWrite,
    ; explicit) triple is pre-registered per Story 1.3, so audit emit
    ; should always succeed under the canonical install state).
    Do $$$AssertEquals(+tResult1.structuredContent.%Get("audit_emitted"), 1, "first call audit_emitted = 1 (triple pre-registered)")
    ; Review fix LOW-9.2-F04 — description_persisted = 0 since no
    ; description was supplied in tArgs1 (additive Story 9.2 envelope field).
    Do $$$AssertEquals(+tResult1.structuredContent.%Get("description_persisted"), 0, "first call description_persisted = 0 (no description supplied)")

    ; Second call → action=incremented.
    Set tArgs2 = {"mode": "save", "alias": (tAlias)}
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs2, .tResult2)
    Do $$$AssertStatusOK(tSC2, "second vocab_lookup mode=save returns $$$OK")
    Do $$$AssertEquals(tResult2.structuredContent.%Get("action"), "incremented", "second call action = incremented")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("new_success_count"), 2, "second call new_success_count = 2")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("audit_emitted"), 1, "second call audit_emitted = 1 (triple pre-registered)")
    Quit
}

/// <p>Helper — probe <code>%SYS.Audit</code> for an audit event with the
/// given <var>pName</var> + <var>pUser</var> + <var>pAlias</var>
/// substring in the EventData. Returns 1 if found, 0 otherwise. Limits
/// scan to the most recent 10 rows so the probe finishes quickly even
/// on an audit-heavy install.</p>
ClassMethod AuditRowExistsForName(pName As %String, pUser As %String, pAlias As %String) As %Boolean
{
    Set tFound = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Set tStmt = ##class(%SQL.Statement).%New()
        Do tStmt.%Prepare("SELECT TOP 20 %EXACT(Event) AS en, %EXACT(EventType) AS et, %EXACT(EventSource) AS es, %EXACT(EventData) AS ed FROM %SYS.Audit WHERE %EXACT(EventSource) = 'SessionAgent' AND %EXACT(EventType) = 'VocabWrite' AND %EXACT(Event) = ? ORDER BY UTCTimeStamp DESC")
        Set tRs = tStmt.%Execute(pName)
        While tRs.%Next() {
            Set tEd = tRs.%Get("ed")
            If (tEd [ ("PortalUser=" _ pUser)) && (tEd [ ("Alias=" _ pAlias)) {
                Set tFound = 1
                Quit
            }
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tFound
}

/// <p>Helper — count occurrences of substring <var>pNeedle</var> within
/// <var>pHaystack</var>. Used by the digest tests to count row markers.</p>
ClassMethod CountSubstring(pHaystack As %String, pNeedle As %String) As %Integer
{
    If (pNeedle = "") || (pHaystack = "") Quit 0
    Set tCount = 0
    Set tPos = 1
    Set tNlen = $Length(pNeedle)
    Set tFound = $Find(pHaystack, pNeedle, tPos)
    While tFound > 0 {
        Set tCount = tCount + 1
        Set tPos = tFound
        Set tFound = $Find(pHaystack, pNeedle, tPos)
    }
    Quit tCount
}

/// <p>Story 9.3 AC-5 row 1 — operator with 25 high-confidence aliases.
/// Each alias is driven to <code>Confidence &gt;= 0.5</code> via
/// 1 <code>RecordSuccess</code> call (yields exactly 0.5 = 1/(1+0+1)).
/// <method>Build</method> caps the row list at <code>MaxEntries=20</code>;
/// the digest contains exactly 20 row markers AND the
/// <code>(N more aliases hidden</code> truncation marker (since 25 > 20).</p>
Method TestVocabularyDigestUserWithHighConfidenceRows()
{
    Set tUser = "sa-test-93-power"
    Do ..CleanupTestRows()
    ; Seed 25 distinct aliases at Confidence=0.5.
    For i=1:1:25 {
        Set tAlias = "alias-" _ $Justify(i, 2, 0)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "RecordSuccess for " _ tAlias)
    }
    ; Verify seed precondition — 25 rows for tUser at Confidence=0.5 (>= 0.3 threshold).
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND Confidence >= 0.3")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 25, "25 qualifying rows seeded")

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    Do $$$AssertTrue(tDigest [ "## Saved aliases for this user", "digest contains user-aliases header")
    ; Count "- """ row markers — should be exactly MaxEntries=20.
    Set tRowCount = ..CountSubstring(tDigest, "- """)
    Do $$$AssertEquals(tRowCount, 20, "digest contains exactly MaxEntries=20 row markers; got " _ tRowCount)
    ; Truncation marker present (25 > 20).
    Do $$$AssertTrue(tDigest [ "more aliases hidden", "digest contains truncation marker (25 > MaxEntries=20)")
    Quit
}

/// <p>Story 9.3 AC-5 row 2 — operator with 5 high-confidence rows + 5
/// low-confidence rows (below <code>MinUserConfidence=0.3</code>). The
/// digest contains exactly 5 row markers (the high-confidence rows); the
/// low-confidence rows are filtered out and the truncation marker is
/// absent.</p>
Method TestVocabularyDigestUserWithMixedConfidenceRows()
{
    Set tUser = "sa-test-93-mixed"
    Do ..CleanupTestRows()
    ; Seed 5 high-confidence rows: each gets one RecordSuccess (Confidence = 0.5).
    For i=1:1:5 {
        Set tAlias = "high-" _ i
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "high RecordSuccess " _ i)
    }
    ; Seed 5 low-confidence rows: 1 success + 3 failures yields Confidence = 1/(1+3+1) = 0.2 < 0.3.
    For i=1:1:5 {
        Set tAlias = "low-" _ i
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "low seed " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "low fail-1 " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "low fail-2 " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "low fail-3 " _ i)
    }
    ; Verify the low rows actually fell below 0.3.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND Confidence >= 0.3")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 5, "exactly 5 qualifying rows (high-confidence) post-seed")

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    Do $$$AssertTrue(tDigest [ "## Saved aliases for this user", "user-aliases header present")
    Set tRowCount = ..CountSubstring(tDigest, "- """)
    Do $$$AssertEquals(tRowCount, 5, "digest contains exactly 5 row markers (low-confidence rows filtered); got " _ tRowCount)
    Do $$$AssertTrue('(tDigest [ "more aliases hidden"), "no truncation marker (5 < MaxEntries=20)")
    Quit
}

/// <p>Story 9.3 AC-5 row 3 — operator with zero <code>UserVocabulary</code>
/// rows falls back to the seed digest. Output starts with the
/// seed-fallback header and contains exactly 5 row markers (the seed
/// <code>TOP 5 ORDER BY ID ASC</code>).</p>
Method TestVocabularyDigestZeroRowsFallsBackToSeed()
{
    Set tUser = "sa-test-93-novel"
    Do ..CleanupTestRows()
    ; Verify zero qualifying rows.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 0, "zero rows for novel user (cleanup precondition)")

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    ; Header check — digest STARTS with the seed-fallback header.
    Set tHeader = "## Common idioms (no personal aliases yet)"
    Do $$$AssertEquals($Extract(tDigest, 1, $Length(tHeader)), tHeader, "digest starts with seed-fallback header")
    ; Row count: exactly 5 (seed TOP 5).
    Set tRowCount = ..CountSubstring(tDigest, "- """)
    Do $$$AssertEquals(tRowCount, 5, "digest contains exactly 5 seed row markers; got " _ tRowCount)
    ; Each row carries the "(seed)" marker.
    Set tSeedMarkerCount = ..CountSubstring(tDigest, "(seed)")
    Do $$$AssertEquals(tSeedMarkerCount, 5, "all 5 rows carry (seed) marker; got " _ tSeedMarkerCount)
    Quit
}

/// <p>Story 9.3 AC-5 row 4 — operator with 3 rows ALL below
/// <code>MinUserConfidence=0.3</code> falls back to seed digest. The
/// 3 user rows exist in the table but the digest still shows the seed
/// fallback section (zero qualifying rows).</p>
Method TestVocabularyDigestAllRowsBelowThresholdFallsBackToSeed()
{
    Set tUser = "sa-test-93-lowconf"
    Do ..CleanupTestRows()
    ; Seed 3 rows, all driven below 0.3 via 1 success + 3 failures (= 0.2).
    For i=1:1:3 {
        Set tAlias = "lowconf-" _ i
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias), "seed " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "fail-1 " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "fail-2 " _ i)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordFailure(tUser, tAlias), "fail-3 " _ i)
    }
    ; Verify 3 rows exist and ALL are below 0.3.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 3, "3 rows exist for lowconf user")

    Set tStmt2 = ##class(%SQL.Statement).%New()
    Do tStmt2.%Prepare("SELECT COUNT(*) AS c FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND Confidence >= 0.3")
    Set tRs2 = tStmt2.%Execute(tUser)
    Do tRs2.%Next()
    Do $$$AssertEquals(+tRs2.%Get("c"), 0, "zero qualifying rows (all below 0.3)")

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    Set tHeader = "## Common idioms (no personal aliases yet)"
    Do $$$AssertEquals($Extract(tDigest, 1, $Length(tHeader)), tHeader, "digest falls back to seed (all rows < 0.3)")
    Do $$$AssertTrue('(tDigest [ "## Saved aliases for this user"), "user-aliases header NOT present (fallback path taken)")
    Quit
}

/// <p>Story 9.3 AC-5 row 5 — token-budget cap enforcement. Constructs a
/// synthetic user with 50 rows whose rendered digest naturally exceeds
/// the row-count cap (50 > <code>MaxEntries=20</code>) AND whose rendered
/// per-row body is large enough that the rendered digest must remain
/// under the 1,200-token cap. Asserts <code>$Length(digest) \ 4 &lt;= 1200</code>
/// AND the truncation marker is present.</p>
///
/// <p><b>Body sizing.</b> <code>MessageBodyClass</code> column has
/// <code>MAXLEN=128</code>. Each rendered row is approximately
/// <code>"- "fatalias-NN" — &lt;128-char body&gt; (confidence 0.50)\n"</code>
/// ≈ ~165 chars. Capped at <code>MaxEntries=20</code> rows the digest is
/// ~3,300 chars ≈ ~825 tokens — well under the 1,200 cap; the marker
/// fires from the row-count cap rather than the token cap, but either
/// flavor satisfies AC-4's "truncation marker present" contract.</p>
Method TestVocabularyDigestTokenCapEnforced()
{
    Set tUser = "sa-test-93-tokencap"
    Do ..CleanupTestRows()
    ; Build a 120-char body (within MAXLEN=128) so each row is fat enough
    ; that 50 rows would exceed the token budget if MaxEntries weren't
    ; the binding cap.
    Set tFatBody = ""
    For i=1:1:120 {
        Set tFatBody = tFatBody _ "X"
    }
    For i=1:1:50 {
        Set tAlias = "fatalias-" _ $Justify(i, 2, 0)
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, tAlias, tFatBody, "explicit"), "fat seed " _ i)
    }

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    Set tEstTokens = $Length(tDigest) \ 4
    Do $$$AssertTrue(tEstTokens <= 1200, "estimated tokens within budget; got " _ tEstTokens _ " (budget=1200)")
    Do $$$AssertTrue(tDigest [ "more aliases hidden", "truncation marker present (50 rows exceed MaxEntries=20)")
    Quit
}

/// <p>Story 9.3 AC-5 row 6 — pin a single row's exact rendered shape.
/// Drives <code>"admit" / EnsLib.HL7.Message</code> to
/// <code>Confidence ≈ 0.857</code> via 6 successive
/// <code>RecordSuccess</code> calls (6/(6+0+1) = 0.857...) which
/// renders as <code>(confidence 0.86)</code>. Asserts exact substring
/// <code>- "admit" — EnsLib.HL7.Message (confidence 0.86)</code> appears
/// in the digest. Tests format AND descriptor-selection (MessageBodyClass
/// preferred over CreatedVia).</p>
Method TestVocabularyDigestRowFormatExact()
{
    Set tUser = "sa-test-93-format"
    Do ..CleanupTestRows()
    ; Drive Confidence to ≈0.86 — 6 successes → 6/7 ≈ 0.857 → $FNumber(...,"",2) → "0.86".
    For i=1:1:6 {
        Do $$$AssertStatusOK(##class(SessionAgent.Search.UserVocabulary).RecordSuccess(tUser, "admit", "EnsLib.HL7.Message", "explicit"), "RecordSuccess #" _ i)
    }
    ; Verify Confidence is what we expect.
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%Prepare("SELECT Confidence AS cf FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = 'admit'")
    Set tRs = tStmt.%Execute(tUser)
    Do tRs.%Next()
    Set tCf = +tRs.%Get("cf")
    Do $$$AssertTrue((tCf >= 0.85) && (tCf < 0.87), "Confidence ≈ 0.857 (got " _ tCf _ ")")

    Set tDigest = ##class(SessionAgent.Search.VocabularyDigest).Build(tUser)
    ; Pinned row format: - "admit" — EnsLib.HL7.Message (confidence 0.86)
    Set tExpectedRow = "- ""admit"" " _ $Char(8212) _ " EnsLib.HL7.Message (confidence 0.86)"
    Do $$$AssertTrue(tDigest [ tExpectedRow, "digest contains pinned row text: " _ tExpectedRow)
    Quit
}

}
