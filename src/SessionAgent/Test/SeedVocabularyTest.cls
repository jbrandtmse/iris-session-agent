/// <p>Unit tests for <CLASS>SessionAgent.Search.SeedVocabulary</CLASS>'s
/// <method>Seed</method> idempotency contract +
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS>'s
/// <code>UserAliasIdx</code> unique-constraint enforcement, per
/// Story 8.1 AC-6.</p>
///
/// <p><b>Test isolation strategy.</b> Each test that exercises the
/// SeedVocabulary extent kills the data + index globals in
/// <method>OnBeforeOneTest</method> so a prior install-seeded state does
/// not contaminate counts / idempotency assertions. The unique-index
/// test on UserVocabulary kills its own globals too. Cleanup in
/// <method>OnAfterOneTest</method> kills both extents again so a
/// subsequent <method>SessionAgent.Installer.Install</method> call can
/// re-seed without colliding. <method>OnAfterAllTests</method> re-runs
/// <method>SessionAgent.Search.SeedVocabulary.Seed</method> so the
/// install-seeded state is restored after the suite finishes — without
/// this, a later regression run would see an empty SeedVocabulary
/// table and operator-visible state would drift.</p>
///
/// <p><b>Property naming note (Story 7.0 AC-3 codification).</b> No
/// state-tracking property on this class begins with <code>Test*</code> —
/// that prefix would collide with the framework's test-method-discovery
/// loop and surface as phantom tests. This class uses plain method-local
/// variables instead.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md Story 8.1</a> — AC-6 source.</li>
/// <li><a href="../../../.claude/rules/object-script-testing.md">.claude/rules/object-script-testing.md</a>
/// — assertion macro list, constructor pattern, Test* shadow trap.</li>
/// </ul>
Class SessionAgent.Test.SeedVocabularyTest Extends %UnitTest.TestCase
{

/// <p>Documented HL7 seed list size — must match the literal count of
/// <method>InsertIfMissing</method> calls in
/// <method>SessionAgent.Search.SeedVocabulary.Seed</method>. Tracked as
/// a parameter so a future seed-list addition surfaces here as a single
/// constant change + a per-test recount.</p>
Parameter EXPECTEDSEEDCOUNT = 10;

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

/// <p>Per-test fixture: clear both the SeedVocabulary and UserVocabulary
/// extents via <method>%KillExtent</method> so each test starts from an
/// empty extent. Uses <method>%KillExtent</method> rather than direct
/// <code>Kill ^SessionAgenC88B.*</code> on mangled storage globals — the
/// compiler-generated global names depend on the package hash and would
/// silently no-op the kill if a future rename / refactor caused the
/// compiler to emit a different mangled prefix; <method>%KillExtent</method>
/// resolves the extent through the Storage section regardless.</p>
Method OnBeforeOneTest() As %Status
{
    Do ##class(SessionAgent.Search.SeedVocabulary).%KillExtent()
    Do ##class(SessionAgent.Search.UserVocabulary).%KillExtent()
    Quit $$$OK
}

/// <p>Per-test cleanup: clear both extents again so a follow-on
/// <method>SessionAgent.Installer.Install</method> call (e.g., a manual
/// re-install or a downstream test) can re-seed cleanly. Uses
/// <method>%KillExtent</method> for the same Storage-section-resilience
/// reason as <method>OnBeforeOneTest</method>.</p>
Method OnAfterOneTest() As %Status
{
    Try {
        Do ##class(SessionAgent.Search.SeedVocabulary).%KillExtent()
        Do ##class(SessionAgent.Search.UserVocabulary).%KillExtent()
    } Catch {}
    Quit $$$OK
}

/// <p>End-of-class restoration: re-seed the SeedVocabulary extent
/// so the install-seeded state is restored after the suite finishes.
/// Without this, a later regression run sees an empty
/// <code>SessionAgent_Search.SeedVocabulary</code> table and
/// operator-visible state has drifted.</p>
Method OnAfterAllTests() As %Status
{
    Try {
        Do ##class(SessionAgent.Search.SeedVocabulary).Seed()
    } Catch {}
    Quit $$$OK
}

/// <p>AC-6 #1 — Seed first call inserts templates. Asserts that after a
/// fresh <method>Seed</method> invocation, the row count equals the
/// documented HL7 list size (parameter <code>EXPECTEDSEEDCOUNT</code>).</p>
Method TestSeedFirstCallInsertsTemplates()
{
    Set tSC = ##class(SessionAgent.Search.SeedVocabulary).Seed()
    Do $$$AssertStatusOK(tSC, "Seed must return $$$OK on fresh extent")
    Set tCount = ..GetSeedRowCount()
    Do $$$AssertEquals(tCount, ..#EXPECTEDSEEDCOUNT, "Fresh Seed must insert " _ ..#EXPECTEDSEEDCOUNT _ " templates; observed " _ tCount)
    Quit
}

/// <p>AC-6 #2 — idempotency. After two successive
/// <method>Seed</method> invocations, the row count must equal the
/// documented HL7 list size (NOT 2x). Validates the
/// composite-key existence probe in
/// <method>InsertIfMissing</method> works for the empty-MessageBodyClass
/// case (which IRIS stores as SQL NULL).</p>
Method TestSeedSecondCallIdempotent()
{
    Set tSC = ##class(SessionAgent.Search.SeedVocabulary).Seed()
    Do $$$AssertStatusOK(tSC, "First Seed must return $$$OK")
    Set tFirstCount = ..GetSeedRowCount()
    Do $$$AssertEquals(tFirstCount, ..#EXPECTEDSEEDCOUNT, "First Seed inserted expected count")

    Set tSC = ##class(SessionAgent.Search.SeedVocabulary).Seed()
    Do $$$AssertStatusOK(tSC, "Second Seed must return $$$OK")
    Set tSecondCount = ..GetSeedRowCount()
    Do $$$AssertEquals(tSecondCount, ..#EXPECTEDSEEDCOUNT, "Second Seed must NOT duplicate; observed " _ tSecondCount _ ", expected " _ ..#EXPECTEDSEEDCOUNT)
    Quit
}

/// <p>AC-6 #3 — template count matches spec. Asserts the documented
/// HL7 seed list size (<code>EXPECTEDSEEDCOUNT</code>) matches the
/// post-Seed row count exactly. Catches drift if a future edit adds
/// or removes a template without updating the parameter.</p>
Method TestSeedTemplateCountMatchesSpec()
{
    Set tSC = ##class(SessionAgent.Search.SeedVocabulary).Seed()
    Do $$$AssertStatusOK(tSC, "Seed must return $$$OK")
    Set tCount = ..GetSeedRowCount()
    Do $$$AssertEquals(tCount, ..#EXPECTEDSEEDCOUNT, "HL7 seed list size must equal EXPECTEDSEEDCOUNT parameter; observed " _ tCount)
    Quit
}

/// <p>AC-6 #4 — UserAliasIdx unique constraint enforcement. Inserts
/// two UserVocabulary rows with the same <code>(PortalUser, Alias)</code>
/// composite key; the second <code>%Save</code> must return an error
/// status (the unique-constraint violation), proving the database-
/// level guard fires.</p>
Method TestUserAliasIdxUniqueConstraint()
{
    Set tFirst = ##class(SessionAgent.Search.UserVocabulary).%New()
    Set tFirst.PortalUser = "test_user_8_1"
    Set tFirst.Alias = "duplicate-alias"
    Set tFirst.MessageBodyClass = ""
    Set tFirst.CreatedVia = "explicit"
    Set tFirst.CreatedAt = "2026-05-07T00:00:00Z"
    Set tSC = tFirst.%Save()
    Do $$$AssertStatusOK(tSC, "First %Save must succeed")

    Set tSecond = ##class(SessionAgent.Search.UserVocabulary).%New()
    Set tSecond.PortalUser = "test_user_8_1"
    Set tSecond.Alias = "duplicate-alias"
    Set tSecond.MessageBodyClass = ""
    Set tSecond.CreatedVia = "explicit"
    Set tSecond.CreatedAt = "2026-05-07T00:00:01Z"
    Set tSC2 = tSecond.%Save()
    Do $$$AssertStatusNotOK(tSC2, "Second %Save with same (PortalUser, Alias) must fail unique-constraint check")
    Quit
}

/// <p>AC-5 satisfaction probe — descriptions are operator-readable
/// ASCII (no Unicode mojibake risk). Probes the first row's Description
/// field for the literal ASCII <code>-&gt;</code> connector and asserts
/// no Unicode arrow is present. Prevents accidental re-introduction of
/// the <code>&lt;-&gt;</code> Unicode arrow that the spec used.</p>
Method TestSeedDescriptionsAreAscii()
{
    Set tSC = ##class(SessionAgent.Search.SeedVocabulary).Seed()
    Do $$$AssertStatusOK(tSC, "Seed must return $$$OK")

    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT %EXACT(Description) AS Descr FROM SessionAgent_Search.SeedVocabulary WHERE %EXACT(Alias) = 'admit'")
    Do $$$AssertStatusOK(tPrepSC, "Prepare must succeed")
    Set tRS = tStmt.%Execute()
    Do $$$AssertTrue(tRS.%Next(), "admit row must exist after Seed")
    Set tDescr = tRS.%Get("Descr")
    Do $$$AssertTrue(tDescr [ "->", "Description must contain ASCII '->'; got: " _ tDescr)
    ; Reject Unicode left-right arrow U+2194 (encoded as $Char(8596) but in UTF-8 byte sequence $Char(226,134,148))
    Do $$$AssertEquals(tDescr [ $Char(226,134,148), 0, "Description must NOT contain UTF-8 Unicode arrow bytes")
    Quit
}

/// <p>Helper — returns the SeedVocabulary row count via SQL. Centralized
/// so the count-probe path is consistent across tests and a single
/// fixture change updates every test.</p>
Method GetSeedRowCount() As %Integer
{
    Set tCount = -1
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Search.SeedVocabulary")
        If $$$ISERR(tPrepSC) Quit
        Set tRS = tStmt.%Execute()
        If tRS.%Next() {
            Set tCount = tRS.%Get("Cnt")
        }
    } Catch {}
    Quit tCount
}

}
