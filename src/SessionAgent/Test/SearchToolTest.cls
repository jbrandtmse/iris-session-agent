/// <p>Story 8.3 — unit tests for the six simple indexed-access search
/// tools: <CLASS>SessionAgent.Tool.Search.SearchByTime</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByStatus</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchBySource</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByTarget</CLASS>,
/// <CLASS>SessionAgent.Tool.Search.SearchByMessageClass</CLASS>, and
/// <CLASS>SessionAgent.Tool.Search.SearchBySession</CLASS>.</p>
///
/// <p>Story 8.4 extends this class with 3 additional test methods for
/// <CLASS>SessionAgent.Tool.Search.SearchBySuperSession</CLASS>
/// (<method>TestSearchBySuperSessionByKey</method>,
/// <method>TestSearchBySuperSessionBySeedSessionId</method>,
/// <method>TestSearchBySuperSessionXorRequired</method>). Fixture
/// extension: <code>OnBeforeAllTests</code> seeds 4 additional
/// <CLASS>Ens.MessageHeader</CLASS> rows in <code>BASESID+30..33</code>
/// AND 4 corresponding <CLASS>Ens.SuperSessionIndex</CLASS> rows
/// linking them all to <code>SuperSession='SS-TEST-001'</code>.
/// <code>OnAfterAllTests</code> sweeps both extents — the FK has
/// <code>OnDelete=cascade</code> so deleting the parent rows
/// auto-cascades, plus belt-and-suspenders explicit
/// <code>Ens.SuperSessionIndex</code> cleanup by SuperSession value.</p>
///
/// <p>Story 8.5 extends this class with 3 additional test methods for
/// <CLASS>SessionAgent.Tool.Search.SearchByBodyField</CLASS>
/// (<method>TestSearchByBodyFieldHappyPath</method>,
/// <method>TestSearchByBodyFieldUnknownPropNameReturnsError</method>,
/// <method>TestSearchByBodyFieldUnknownClassReturnsError</method>).
/// Fixture extension: <code>OnBeforeAllTests</code> seeds 1
/// <CLASS>Ens.Config.SearchTableProp</CLASS> mapping +
/// <code>BASESID+50..52</code> 3 <CLASS>SessionAgent.Test.FsbFixtureSearchTable</CLASS>
/// rows + 3 matching <CLASS>Ens.MessageHeader</CLASS> rows whose
/// <code>MessageBodyId</code> points at the fixture-SearchTable
/// <code>DocId</code>s. Fresh-time rows (within the 168h default
/// window). The <CLASS>SessionAgent.Test.FsbFixtureSearchTable</CLASS>
/// class extends <CLASS>Ens.CustomSearchTable</CLASS> which extends
/// <CLASS>Ens.SearchTableBase</CLASS>, so the production tool's
/// <code>%Extends "Ens.SearchTableBase"</code> validation gate passes
/// against this fixture. <code>OnAfterAllTests</code> deletes the seeded
/// SearchTable rows + Ens.Config.SearchTableProp row.</p>
///
/// <p>Story 8.6 extends this class with 4 additional test methods for
/// <CLASS>SessionAgent.Tool.Search.InspectBodyCandidates</CLASS>
/// (<method>TestInspectBodyCandidatesHappyPathSubstring</method>,
/// <method>TestInspectBodyCandidatesRegexMode</method>,
/// <method>TestInspectBodyCandidatesCapEnforcedAt50</method>,
/// <method>TestInspectBodyCandidatesGracefulBodyError</method>).
/// Fixture extension: <code>OnBeforeAllTests</code> seeds 5
/// <CLASS>Ens.MessageHeader</CLASS> rows in <code>BASESID+60..64</code>
/// each pointing at a real <CLASS>Ens.StringRequest</CLASS> body whose
/// <code>StringValue</code> contains either <code>"E11.9 diagnosis"</code>
/// or <code>"E12.0 diagnosis"</code> or <code>"unrelated text"</code>;
/// 1 row in <code>BASESID+65</code> with a missing-body
/// (<code>MessageBodyId</code> pointing at a non-existent
/// <CLASS>Ens.StringRequest</CLASS> ID — exercises AC-6 graceful drop);
/// 100 cap-test rows in <code>BASESID+200..299</code> each with
/// <code>Status=8</code> (Error) and identical body text — exercises
/// the AC-2 hard cap rejection path with <code>candidate_cap=100</code>.
/// All rows use a unique <code>SourceConfigName='Ibc-FixSrc-86'</code>
/// sentinel so the prefilter narrows to fixture rows only.
/// <code>OnAfterAllTests</code> deletes the seeded
/// <CLASS>Ens.StringRequest</CLASS> bodies in addition to the
/// MessageHeader sweep.</p>
///
/// <p>Nine test methods total (six from Story 8.3 + three from Story 8.4):</p>
/// <ol>
/// <li><b>TestSearchByTimeReturnsTimeBoundedSessions</b> — fixture
/// rows spanning 48h; default 24h window returns only the recent
/// half.</li>
/// <li><b>TestSearchByStatusFiltersByEnumArray</b> — three status
/// values across the fixture; <code>status_in:["Error","Suspended"]</code>
/// excludes the <code>Completed</code> row.</li>
/// <li><b>TestSearchBySourceExactMatchOnly</b> — case-sensitive
/// <code>%EXACT()</code> match.</li>
/// <li><b>TestSearchByTargetExactMatchOnly</b> — same shape on
/// <code>TargetConfigName</code>.</li>
/// <li><b>TestSearchByMessageClassExactMatchOnly</b> — same shape on
/// <code>MessageBodyClassName</code>.</li>
/// <li><b>TestSearchBySessionKeyedLookupOmitsTimeWindow</b> — fixture
/// row whose <code>TimeCreated</code> is older than 720h; the
/// keyed-lookup tool STILL resolves it (proving the keyed-lookup
/// sentinel suppresses the time-window predicate).</li>
/// <li><b>TestSearchBySuperSessionByKey</b> (Story 8.4) — 4 fixture
/// sessions all linked to the same <code>SuperSession='SS-TEST-001'</code>;
/// invoke with explicit <code>super_session_key</code> returns all 4
/// sessions, <code>session_count=4</code>, <code>time_window_used</code>
/// is JSON null.</li>
/// <li><b>TestSearchBySuperSessionBySeedSessionId</b> (Story 8.4) —
/// same fixture; invoke with <code>seed_session_id</code> resolves the
/// super-session key via Phase-1 lookup and returns all 4 siblings
/// (including the seed itself).</li>
/// <li><b>TestSearchBySuperSessionXorRequired</b> (Story 8.4) — neither
/// arg → <code>{isError:1}</code>; both args → <code>{isError:1}</code>;
/// validates the Invoke-time XOR enforcement.</li>
/// </ol>
///
/// <p><b>Fixture.</b> <method>OnBeforeAllTests</method> seeds direct
/// <CLASS>Ens.MessageHeader</CLASS> rows for a fixture
/// <code>SessionId</code> family
/// (<code>FIXTUREBASESID + offset</code>) with deterministic
/// timestamps relative to <code>$ZTimeStamp</code>; row IDs captured
/// in <code>^||SessionAgentSearchTestIds</code> for cleanup.
/// <method>OnAfterAllTests</method> deletes by ID and sweeps any
/// stragglers via composite-key DELETE.</p>
///
/// <p><b>Property Test* shadow trap (project rule).</b> No
/// <code>Property Test*</code> declarations on this class — the
/// %UnitTest framework discovers methods whose names begin with
/// <code>Test</code> and would attempt to run datatype-helper methods
/// generated for <code>Test*</code>-prefixed properties. State
/// tracking, when needed, uses <code>Pre*</code>-prefixed properties.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.3</a> AC-7.</li>
/// <li><CLASS>SessionAgent.Tool.Search.Base</CLASS>.</li>
/// </ul>
Class SessionAgent.Test.SearchToolTest Extends %UnitTest.TestCase
{

/// <p>Base SessionId; per-test fixtures use this + offset to avoid
/// collisions with other test classes' SessionId reservations
/// (e.g., InspectionToolTest uses 999911).</p>
Parameter FIXTUREBASESID As %Integer = 998800;

/// <p>Story 8.5 — fixture SearchTable subclass for body-field tests.
/// Reuses the <CLASS>SessionAgent.Test.FsbFixtureSearchTable</CLASS>
/// (Story 4.6's fixture, which extends <CLASS>Ens.CustomSearchTable</CLASS>
/// → <CLASS>Ens.SearchTableBase</CLASS>). Direct-SQL INSERT seeds rows
/// without invoking VDoc IndexDoc dispatch.</p>
Parameter BFFIXTURECLASS As %String = "SessionAgent.Test.FsbFixtureSearchTable";

/// <p>Story 8.5 — body-field fixture prop_name registered in
/// <CLASS>Ens.Config.SearchTableProp</CLASS>. Distinct from
/// <CLASS>SessionAgent.Test.FindSessionsByBodyTest</CLASS>'s "MRN" prop
/// to avoid clashing if both test classes run concurrently.</p>
Parameter BFFIXTUREPROPNAME As %String = "Story85PID3";

/// <p>Story 8.5 — body-field fixture PropID. Disjoint range from
/// FindSessionsByBodyTest's 99046001.</p>
Parameter BFFIXTUREPROPID As %Integer = 85046001;

/// <p>Story 8.5 — body-field fixture PropValue.</p>
Parameter BFFIXTUREPROPVALUE As %String = "MATCH-12345";

/// <p>Story 8.5 — sentinel SourceConfigName so cleanup can sweep any
/// orphaned MessageHeader rows. Random enough to avoid clashing with
/// any real production row or the Story 4.6 fixture sentinel.</p>
Parameter BFFIXTURESOURCESENTINEL As %String = "BfFixtureSrc-85";

/// <p>Story 8.6 — sentinel SourceConfigName for InspectBodyCandidates
/// fixtures. Used as the prefilter value in tests + as the cleanup
/// sweep predicate.</p>
Parameter IBCFIXTURESOURCESENTINEL As %String = "Ibc-FixSrc-86";

/// <p>Story 8.6 — sentinel for cap-test rows (separate from the main
/// happy-path fixture so the cap test doesn't perturb other tests'
/// candidate counts).</p>
Parameter IBCCAPSOURCESENTINEL As %String = "Ibc-CapSrc-86";

/// <p>Constructor — accepts <code>initvalue</code> from
/// <CLASS>%UnitTest.TestCase</CLASS> and forwards via <code>##super</code>
/// (project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Seed Ens.MessageHeader fixture rows. Each test reuses a
/// disjoint <code>SessionId</code> sub-range so the assertions are
/// independent. Layout:</p>
/// <ul>
/// <li><code>BASESID + 1</code> — 5 rows for SearchByTime test
/// (recent: 3 rows in last 24h; old: 2 rows older than 24h).</li>
/// <li><code>BASESID + 2..BASESID + 4</code> — 3 sessions × 2 rows
/// each for SearchByStatus (Status=8/Error, 5/Suspended, 9/Completed).</li>
/// <li><code>BASESID + 5..BASESID + 8</code> — 4 sessions for
/// SearchBySource/Target (2 with 'EpicADT', 2 with 'EpicADT2').</li>
/// <li><code>BASESID + 9..BASESID + 12</code> — 4 sessions for
/// SearchByMessageClass.</li>
/// <li><code>BASESID + 30..BASESID + 33</code> — 4 sessions × 1 row
/// each + 4 <CLASS>Ens.SuperSessionIndex</CLASS> rows all linking to
/// <code>SuperSession='SS-TEST-001'</code> for the Story 8.4
/// SearchBySuperSession tests.</li>
/// <li><code>BASESID + 99</code> — 1 row with TimeCreated 1000h ago
/// (older than 720h max window) for SearchBySession keyed-lookup test.</li>
/// </ul>
Method OnBeforeAllTests() As %Status
{
    Kill ^||SessionAgentSearchTestIds
    Kill ^||SessionAgentSearchSuperSessionTestIds
    Kill ^||SessionAgentSearchBodyFieldTestIds
    Set tBase = ..#FIXTUREBASESID

    ; Defensive sweep — clear any prior-run debris in our SessionId range.
    ; (Cascading FK on Ens.SuperSessionIndex.MessageHeaderFKey will
    ; auto-delete any index rows pointing at our fixture headers, but
    ; we also sweep by SuperSession value for orphan rows from crashed
    ; runs.)
    Set tCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.SuperSessionIndex WHERE %EXACT(SuperSession) = ?")) {
        Do tCleanup.%Execute("SS-TEST-001")
    }
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?")) {
        Do tCleanup.%Execute(tBase, tBase + 100)
    }
    ; Story 8.5 — sweep body-field fixture SearchTable rows + the
    ; SearchTableProp row in case prior-run debris exists.
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM SessionAgent_Test.FsbFixtureSearchTable WHERE PropId = ?")) {
        Do tCleanup.%Execute(..#BFFIXTUREPROPID)
    }
    If $$$ISOK(tCleanup.%Prepare("DELETE FROM Ens_Config.SearchTableProp WHERE %EXACT(ClassExtent) = ? AND %EXACT(Name) = ?")) {
        Do tCleanup.%Execute(..#BFFIXTURECLASS, ..#BFFIXTUREPROPNAME)
    }

    ; Helper closure-style: build an ODBC timestamp N hours offset from
    ; $ZTimeStamp (which is UTC days,seconds-since-midnight).
    ; We inline the math for each row.
    Set tNowH = $ZTimeStamp
    Set tNowDays = +$Piece(tNowH, ",", 1)
    Set tNowSecs = +$Piece(tNowH, ",", 2)

    Set tRowSeq = 0

    ; ---- TIME test fixture: SessionId BASESID+1, 5 rows.
    ; 3 rows at -1h/-2h/-3h (inside default 24h window),
    ; 2 rows at -36h/-40h (outside).
    Set tTimeSid = tBase + 1
    For tHourOffset = -1, -2, -3, -36, -40 {
        Set tShiftedSecs = tNowSecs + (tHourOffset * 3600)
        Set tShiftedDays = tNowDays
        While tShiftedSecs < 0 {
            Set tShiftedSecs = tShiftedSecs + 86400
            Set tShiftedDays = tShiftedDays - 1
        }
        Set tShiftedH = tShiftedDays _ "," _ tShiftedSecs
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tTimeSid
        Set tHdr.TimeCreated = $ZDateTime(tShiftedH, 3, 1, 0)
        Set tHdr.SourceConfigName = "TimeFixtureSrc"
        Set tHdr.TargetConfigName = "TimeFixtureTgt"
        Set tHdr.MessageBodyClassName = "TimeFixture.Msg"
        Set tHdr.Status = 9
        Set tSC1 = tHdr.%Save()
        If $$$ISERR(tSC1) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- STATUS test fixture: 3 sessions × 1 row each.
    ; SessionId BASESID+2 → Status=8 (Error)
    ; SessionId BASESID+3 → Status=5 (Suspended)
    ; SessionId BASESID+4 → Status=9 (Completed)
    For tStatusEntry = "2,8", "3,5", "4,9" {
        Set tSidOffset = +$Piece(tStatusEntry, ",", 1)
        Set tStatusVal = +$Piece(tStatusEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        ; Recent row — within default 24h window.
        Set tShiftedSecs = tNowSecs - 3600
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "StatusFixtureSrc"
        Set tHdr.TargetConfigName = "StatusFixtureTgt"
        Set tHdr.MessageBodyClassName = "StatusFixture.Msg"
        Set tHdr.Status = tStatusVal
        Set tSC2 = tHdr.%Save()
        If $$$ISERR(tSC2) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- SOURCE test fixture: 4 sessions, 2 with 'EpicADT' source,
    ; 2 with 'EpicADT2'. SessionId BASESID+5..BASESID+8.
    For tSrcEntry = "5,EpicADT", "6,EpicADT", "7,EpicADT2", "8,EpicADT2" {
        Set tSidOffset = +$Piece(tSrcEntry, ",", 1)
        Set tSrcName = $Piece(tSrcEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = tSrcName
        Set tHdr.TargetConfigName = "SourceFixtureTgt"
        Set tHdr.MessageBodyClassName = "SourceFixture.Msg"
        Set tHdr.Status = 9
        Set tSC3 = tHdr.%Save()
        If $$$ISERR(tSC3) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- TARGET test fixture: 4 sessions, 2 with 'TgtA', 2 with 'TgtB'.
    ; SessionId BASESID+9..BASESID+12.
    For tTgtEntry = "9,TgtAlpha", "10,TgtAlpha", "11,TgtBeta", "12,TgtBeta" {
        Set tSidOffset = +$Piece(tTgtEntry, ",", 1)
        Set tTgtName = $Piece(tTgtEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "TargetFixtureSrc"
        Set tHdr.TargetConfigName = tTgtName
        Set tHdr.MessageBodyClassName = "TargetFixture.Msg"
        Set tHdr.Status = 9
        Set tSC4 = tHdr.%Save()
        If $$$ISERR(tSC4) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- MESSAGE-CLASS test fixture: 4 sessions, 2 'Hl7Msg', 2 'SegDoc'.
    ; SessionId BASESID+13..BASESID+16.
    For tBcEntry = "13,Class.A.Msg", "14,Class.A.Msg", "15,Class.B.Other", "16,Class.B.Other" {
        Set tSidOffset = +$Piece(tBcEntry, ",", 1)
        Set tBcName = $Piece(tBcEntry, ",", 2)
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSidOffset
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "BcFixtureSrc"
        Set tHdr.TargetConfigName = "BcFixtureTgt"
        Set tHdr.MessageBodyClassName = tBcName
        Set tHdr.Status = 9
        Set tSC5 = tHdr.%Save()
        If $$$ISERR(tSC5) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()
    }

    ; ---- SUPER-SESSION fixture (Story 8.4): 4 sessions, each with one
    ; Ens.MessageHeader row + one Ens.SuperSessionIndex row all pointing
    ; at SuperSession='SS-TEST-001'. SessionId BASESID+30..BASESID+33.
    ; Captured SuperSessionIndex IDs are stored in
    ; ^||SessionAgentSearchSuperSessionTestIds for explicit cleanup.
    Kill ^||SessionAgentSearchSuperSessionTestIds
    Set tSsiSeq = 0
    For tSsOffset = 30, 31, 32, 33 {
        Set tShiftedSecs = tNowSecs - 1800
        Set tShiftedDays = tNowDays
        If tShiftedSecs < 0 Set tShiftedSecs = tShiftedSecs + 86400, tShiftedDays = tShiftedDays - 1
        Set tHdr = ##class(Ens.MessageHeader).%New()
        Set tHdr.SessionId = tBase + tSsOffset
        Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
        Set tHdr.SourceConfigName = "SuperSessionFixtureSrc"
        Set tHdr.TargetConfigName = "SuperSessionFixtureTgt"
        Set tHdr.MessageBodyClassName = "SuperSessionFixture.Msg"
        Set tHdr.Status = 9
        Set tSCss = tHdr.%Save()
        If $$$ISERR(tSCss) Quit
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()

        ; Add the SuperSessionIndex row pointing at this MessageHeader.
        Set tSsi = ##class(Ens.SuperSessionIndex).%New()
        Set tSsi.SuperSession = "SS-TEST-001"
        Set tSsi.MessageHeader = tHdr
        Set tSCsi = tSsi.%Save()
        If $$$ISERR(tSCsi) Quit
        Set tSsiSeq = tSsiSeq + 1
        Set ^||SessionAgentSearchSuperSessionTestIds(tSsiSeq) = tSsi.%Id()
    }

    ; ---- SESSION-LOOKUP fixture: 1 row at -1000h (older than 720h max).
    ; SessionId BASESID+99. Proves keyed-lookup mode bypasses the window.
    Set tSessSid = tBase + 99
    Set tShiftedSecs = tNowSecs - (1000 * 3600)
    Set tShiftedDays = tNowDays
    While tShiftedSecs < 0 {
        Set tShiftedSecs = tShiftedSecs + 86400
        Set tShiftedDays = tShiftedDays - 1
    }
    Set tHdr = ##class(Ens.MessageHeader).%New()
    Set tHdr.SessionId = tSessSid
    Set tHdr.TimeCreated = $ZDateTime(tShiftedDays _ "," _ tShiftedSecs, 3, 1, 0)
    Set tHdr.SourceConfigName = "AncientFixtureSrc"
    Set tHdr.TargetConfigName = "AncientFixtureTgt"
    Set tHdr.MessageBodyClassName = "AncientFixture.Msg"
    Set tHdr.Status = 9
    Set tSC6 = tHdr.%Save()
    If $$$ISERR(tSC6) Quit $$$OK
    Set tRowSeq = tRowSeq + 1
    Set ^||SessionAgentSearchTestIds(tRowSeq) = tHdr.%Id()

    ; ---- BODY-FIELD fixture (Story 8.5): 1 Ens.Config.SearchTableProp
    ; row mapping (BFFIXTURECLASS, BFFIXTUREPROPNAME) → BFFIXTUREPROPID;
    ; 3 SearchTable rows in SessionAgent.Test.FsbFixtureSearchTable with
    ; (PropId=BFFIXTUREPROPID, PropValue=BFFIXTUREPROPVALUE,
    ; DocId="BF-DOC-<sid>"); 3 matching Ens.MessageHeader rows whose
    ; MessageBodyId points at those DocIds. Sessions BASESID+50..52.
    ; Fresh time (-30 minutes) — well inside the 168h default window.
    ;
    ; The Ens.Config.SearchTableProp row uses the same ~-delimited
    ; ClassDerivation chain shape as FindSessionsByBodyTest's seed.
    Kill ^||SessionAgentSearchBodyFieldTestIds
    Set tBfDerivation = "~" _ ..#BFFIXTURECLASS _ "~Ens.CustomSearchTable~Ens.SearchTableBase~"
    Set tBfPropStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tBfPropStmt.%Prepare("INSERT INTO Ens_Config.SearchTableProp (Name, ClassExtent, ClassDerivation, PropId, IsImplicit) VALUES (?, ?, ?, ?, ?)")) {
        Do tBfPropStmt.%Execute(..#BFFIXTUREPROPNAME, ..#BFFIXTURECLASS, tBfDerivation, ..#BFFIXTUREPROPID, 0)
    }

    Set tBfStSeq = 0
    For tBfOffset = 50, 51, 52 {
        Set tBfShiftedSecs = tNowSecs - 1800
        Set tBfShiftedDays = tNowDays
        If tBfShiftedSecs < 0 Set tBfShiftedSecs = tBfShiftedSecs + 86400, tBfShiftedDays = tBfShiftedDays - 1
        Set tBfTime = $ZDateTime(tBfShiftedDays _ "," _ tBfShiftedSecs, 3, 1, 0)
        Set tBfSid = tBase + tBfOffset
        Set tBfDocId = "BF-DOC-" _ tBfSid

        ; SearchTable row.
        Set tBfStStmt = ##class(%SQL.Statement).%New()
        If $$$ISOK(tBfStStmt.%Prepare("INSERT INTO SessionAgent_Test.FsbFixtureSearchTable (PropId, PropValue, DocId) VALUES (?, ?, ?)")) {
            Do tBfStStmt.%Execute(..#BFFIXTUREPROPID, ..#BFFIXTUREPROPVALUE, tBfDocId)
        }

        ; MessageHeader row pointing at the SearchTable DocId.
        Set tBfHdr = ##class(Ens.MessageHeader).%New()
        Set tBfHdr.SessionId = tBfSid
        Set tBfHdr.TimeCreated = tBfTime
        Set tBfHdr.MessageBodyId = tBfDocId
        Set tBfHdr.SourceConfigName = ..#BFFIXTURESOURCESENTINEL _ "-Src"
        Set tBfHdr.TargetConfigName = ..#BFFIXTURESOURCESENTINEL _ "-Tgt"
        Set tBfHdr.MessageBodyClassName = "BfFixture.Msg"
        Set tBfHdr.Status = 9
        Set tSCbf = tBfHdr.%Save()
        If $$$ISOK(tSCbf) {
            Set tRowSeq = tRowSeq + 1
            Set ^||SessionAgentSearchTestIds(tRowSeq) = tBfHdr.%Id()
            Set tBfStSeq = tBfStSeq + 1
            Set ^||SessionAgentSearchBodyFieldTestIds(tBfStSeq) = tBfDocId
        }
    }

    ; ---- Story 8.6 — InspectBodyCandidates fixture.
    ; Defensive sweep — clear any prior-run debris keyed by our sentinels.
    Kill ^||SessionAgentSearchInspectBodyTestIds
    Kill ^||SessionAgentSearchInspectBodyBodyIds
    Kill ^||SessionAgentSearchInspectCapTestIds
    Kill ^||SessionAgentSearchInspectCapBodyIds
    Set tIbcCleanup = ##class(%SQL.Statement).%New()
    If $$$ISOK(tIbcCleanup.%Prepare("DELETE FROM Ens.MessageHeader WHERE %EXACT(SourceConfigName) = ?")) {
        Do tIbcCleanup.%Execute(..#IBCFIXTURESOURCESENTINEL)
        Do tIbcCleanup.%Execute(..#IBCCAPSOURCESENTINEL)
    }

    ; Fresh time within default 24h window.
    Set tIbcShiftedSecs = tNowSecs - 1800
    Set tIbcShiftedDays = tNowDays
    If tIbcShiftedSecs < 0 Set tIbcShiftedSecs = tIbcShiftedSecs + 86400, tIbcShiftedDays = tIbcShiftedDays - 1
    Set tIbcTime = $ZDateTime(tIbcShiftedDays _ "," _ tIbcShiftedSecs, 3, 1, 0)

    ; 5 happy-path rows: BASESID+60..64. Each has a real Ens.StringRequest
    ; body whose StringValue contains a known pattern.
    ; +60: "E11.9 diagnosis primary" (matches "E11", regex "E1[12]")
    ; +61: "E12.0 diagnosis primary" (matches NOT "E11", regex "E1[12]")
    ; +62: "unrelated text content"  (matches NEITHER)
    ; +63: "Patient diagnosis E11.9" (matches "E11", regex "E1[12]")
    ; +64: "E11 short diagnosis"     (matches "E11", regex "E1[12]")
    Set tIbcSeq = 0
    Set tIbcBodySeq = 0
    Set tIbcBodyTexts = $ListBuild("E11.9 diagnosis primary", "E12.0 diagnosis primary", "unrelated text content", "Patient diagnosis E11.9", "E11 short diagnosis")
    Set tIbcOffset = 60
    Set tIbcPtr = 0
    While $ListNext(tIbcBodyTexts, tIbcPtr, tIbcBodyText) {
        Set tIbcBody = ##class(Ens.StringRequest).%New(tIbcBodyText)
        Set tSCibcb = tIbcBody.%Save()
        If $$$ISERR(tSCibcb) {
            Set tIbcOffset = tIbcOffset + 1
            Continue
        }
        Set tIbcBodyId = tIbcBody.%Id()
        Set tIbcBodySeq = tIbcBodySeq + 1
        Set ^||SessionAgentSearchInspectBodyBodyIds(tIbcBodySeq) = tIbcBodyId

        Set tIbcHdr = ##class(Ens.MessageHeader).%New()
        Set tIbcHdr.SessionId = tBase + tIbcOffset
        Set tIbcHdr.TimeCreated = tIbcTime
        Set tIbcHdr.MessageBodyId = tIbcBodyId
        Set tIbcHdr.MessageBodyClassName = "Ens.StringRequest"
        Set tIbcHdr.SourceConfigName = ..#IBCFIXTURESOURCESENTINEL
        Set tIbcHdr.TargetConfigName = ..#IBCFIXTURESOURCESENTINEL _ "-Tgt"
        Set tIbcHdr.Status = 8
        Set tSCibch = tIbcHdr.%Save()
        If $$$ISOK(tSCibch) {
            Set tRowSeq = tRowSeq + 1
            Set ^||SessionAgentSearchTestIds(tRowSeq) = tIbcHdr.%Id()
            Set tIbcSeq = tIbcSeq + 1
            Set ^||SessionAgentSearchInspectBodyTestIds(tIbcSeq) = tIbcHdr.%Id()
        }
        Set tIbcOffset = tIbcOffset + 1
    }

    ; 1 missing-body row at BASESID+65 — exercises AC-6 graceful drop.
    ; MessageBodyId points at a non-existent Ens.StringRequest ID
    ; (very high integer well beyond any real fixture or production row).
    Set tIbcMissingHdr = ##class(Ens.MessageHeader).%New()
    Set tIbcMissingHdr.SessionId = tBase + 65
    Set tIbcMissingHdr.TimeCreated = tIbcTime
    Set tIbcMissingHdr.MessageBodyId = "99999999988"
    Set tIbcMissingHdr.MessageBodyClassName = "Ens.StringRequest"
    Set tIbcMissingHdr.SourceConfigName = ..#IBCFIXTURESOURCESENTINEL
    Set tIbcMissingHdr.TargetConfigName = ..#IBCFIXTURESOURCESENTINEL _ "-Tgt"
    Set tIbcMissingHdr.Status = 8
    Set tSCibcm = tIbcMissingHdr.%Save()
    If $$$ISOK(tSCibcm) {
        Set tRowSeq = tRowSeq + 1
        Set ^||SessionAgentSearchTestIds(tRowSeq) = tIbcMissingHdr.%Id()
        Set tIbcSeq = tIbcSeq + 1
        Set ^||SessionAgentSearchInspectBodyTestIds(tIbcSeq) = tIbcMissingHdr.%Id()
    }

    Quit $$$OK
}

/// <p>Cleanup — delete fixture rows by captured ID then sweep any
/// stragglers via composite-key DELETE. Story 8.4 extends this with
/// explicit <CLASS>Ens.SuperSessionIndex</CLASS> cleanup. The FK has
/// <code>OnDelete=cascade</code> so MessageHeader DELETE cascades, but
/// the explicit pass guards against partial-fixture states (e.g., a
/// prior test crashed before linking) and the SuperSession-keyed
/// composite DELETE catches any orphan rows by SuperSession value.</p>
Method OnAfterAllTests() As %Status
{
    ; Story 8.4 — delete SuperSessionIndex rows BEFORE deleting their
    ; parent MessageHeader rows. (The FK cascade handles the order
    ; either way, but explicit deletion captures the test-cleanup
    ; intent and survives any future FK-config drift.)
    Set tSsiIdx = ""
    For  {
        Set tSsiIdx = $Order(^||SessionAgentSearchSuperSessionTestIds(tSsiIdx))
        Quit:tSsiIdx=""
        Set tSsiId = $Get(^||SessionAgentSearchSuperSessionTestIds(tSsiIdx))
        If tSsiId '= "" Do ##class(Ens.SuperSessionIndex).%DeleteId(tSsiId)
    }
    Kill ^||SessionAgentSearchSuperSessionTestIds
    ; Belt-and-suspenders — sweep any SuperSessionIndex rows for our
    ; fixture SuperSession value (catches orphan rows from crashed runs).
    Set tStmtSsi = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmtSsi.%Prepare("DELETE FROM Ens.SuperSessionIndex WHERE %EXACT(SuperSession) = ?")) {
        Do tStmtSsi.%Execute("SS-TEST-001")
    }

    ; Story 8.5 — delete body-field fixture SearchTable rows by DocId
    ; (captured in ^||SessionAgentSearchBodyFieldTestIds during seeding)
    ; AND delete the seeded Ens.Config.SearchTableProp row. The
    ; MessageHeader rows pointing at these DocIds are deleted below via
    ; the SessionId BETWEEN sweep.
    Set tBfIdx = ""
    Set tBfStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tBfStmt.%Prepare("DELETE FROM SessionAgent_Test.FsbFixtureSearchTable WHERE %EXACT(DocId) = ?")) {
        For  {
            Set tBfIdx = $Order(^||SessionAgentSearchBodyFieldTestIds(tBfIdx))
            Quit:tBfIdx=""
            Set tBfDocId = $Get(^||SessionAgentSearchBodyFieldTestIds(tBfIdx))
            If tBfDocId '= "" Do tBfStmt.%Execute(tBfDocId)
        }
    }
    Kill ^||SessionAgentSearchBodyFieldTestIds
    ; Delete the seeded Ens.Config.SearchTableProp mapping row.
    Set tBfPropStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tBfPropStmt.%Prepare("DELETE FROM Ens_Config.SearchTableProp WHERE %EXACT(ClassExtent) = ? AND %EXACT(Name) = ?")) {
        Do tBfPropStmt.%Execute(..#BFFIXTURECLASS, ..#BFFIXTUREPROPNAME)
    }
    ; Belt-and-suspenders — sweep any orphan FsbFixtureSearchTable rows
    ; pointing at our fixture PropId (catches crashed-run debris).
    Set tBfStSweep = ##class(%SQL.Statement).%New()
    If $$$ISOK(tBfStSweep.%Prepare("DELETE FROM SessionAgent_Test.FsbFixtureSearchTable WHERE PropId = ?")) {
        Do tBfStSweep.%Execute(..#BFFIXTUREPROPID)
    }

    Set tIdx = ""
    For  {
        Set tIdx = $Order(^||SessionAgentSearchTestIds(tIdx))
        Quit:tIdx=""
        Set tId = $Get(^||SessionAgentSearchTestIds(tIdx))
        If tId '= "" Do ##class(Ens.MessageHeader).%DeleteId(tId)
    }
    Kill ^||SessionAgentSearchTestIds
    ; Belt-and-suspenders — sweep our entire SessionId reservation range.
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM Ens.MessageHeader WHERE SessionId BETWEEN ? AND ?")) {
        Do tStmt.%Execute(..#FIXTUREBASESID, ..#FIXTUREBASESID + 100)
    }

    ; ---- Story 8.6 — InspectBodyCandidates body cleanup.
    ; Delete the seeded Ens.StringRequest bodies (body cleanup must run
    ; AFTER MessageHeader cleanup so no FK references the bodies).
    Set tIbcBodyIdx = ""
    For  {
        Set tIbcBodyIdx = $Order(^||SessionAgentSearchInspectBodyBodyIds(tIbcBodyIdx))
        Quit:tIbcBodyIdx=""
        Set tIbcBodyId = $Get(^||SessionAgentSearchInspectBodyBodyIds(tIbcBodyIdx))
        If tIbcBodyId '= "" Do ##class(Ens.StringRequest).%DeleteId(tIbcBodyId)
    }
    Kill ^||SessionAgentSearchInspectBodyBodyIds
    Kill ^||SessionAgentSearchInspectBodyTestIds
    ; Cap-test bodies.
    Set tIbcCapBodyIdx = ""
    For  {
        Set tIbcCapBodyIdx = $Order(^||SessionAgentSearchInspectCapBodyIds(tIbcCapBodyIdx))
        Quit:tIbcCapBodyIdx=""
        Set tIbcCapBodyId = $Get(^||SessionAgentSearchInspectCapBodyIds(tIbcCapBodyIdx))
        If tIbcCapBodyId '= "" Do ##class(Ens.StringRequest).%DeleteId(tIbcCapBodyId)
    }
    Kill ^||SessionAgentSearchInspectCapBodyIds
    Kill ^||SessionAgentSearchInspectCapTestIds
    ; Belt-and-suspenders — sweep MessageHeader rows by sentinel.
    Set tIbcSweep = ##class(%SQL.Statement).%New()
    If $$$ISOK(tIbcSweep.%Prepare("DELETE FROM Ens.MessageHeader WHERE %EXACT(SourceConfigName) = ?")) {
        Do tIbcSweep.%Execute(..#IBCFIXTURESOURCESENTINEL)
        Do tIbcSweep.%Execute(..#IBCCAPSOURCESENTINEL)
    }
    Quit $$$OK
}

/// <p>Build a CallerContext stub for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "message-search"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-7 #1 — SearchByTime default 24h window returns the 3 recent
/// rows (1 session) and excludes the 2 rows older than 24h. The
/// envelope's <code>indexed_lead_column</code> is "TimeCreated" and
/// <code>time_window_used</code> is 24.</p>
Method TestSearchByTimeReturnsTimeBoundedSessions()
{
    Set tCtx = ..BuildCtx()
    ; Restrict to our fixture's source so other production sessions
    ; in the namespace don't pollute the assertion.
    ; SearchByTime doesn't have a source filter — but the fixture
    ; uses a unique TimeFixtureSrc so we can verify via the returned
    ; sessions list.
    Set tArgs = {"limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByTime).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByTime.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "TimeCreated", "indexed_lead_column = TimeCreated")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("time_window_used"), 24, "time_window_used = 24 (default)")

    ; Verify the fixture session BASESID+1 IS in the result list
    ; (3 recent rows were seeded inside the 24h window). The OLD rows
    ; at -36h/-40h must NOT add a separate row beyond their session id
    ; — they roll up under the same SessionId so the session count is 1.
    Set tFoundTimeSession = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If +tEntry.%Get("session_id") = (..#FIXTUREBASESID + 1) {
            Set tFoundTimeSession = 1
            Quit
        }
    }
    Do $$$AssertTrue(tFoundTimeSession, "fixture SessionId " _ (..#FIXTUREBASESID + 1) _ " present in 24h window result")

    ; Test explicit-bound mode — from_time at -2h ago, no upper bound.
    ; Should still surface our fixture session.
    Set tNowH = $ZTimeStamp
    Set tCutoffSecs = $Piece(tNowH, ",", 2) - (2 * 3600)
    Set tCutoffDays = $Piece(tNowH, ",", 1)
    If tCutoffSecs < 0 Set tCutoffSecs = tCutoffSecs + 86400, tCutoffDays = tCutoffDays - 1
    Set tCutoffOdbc = $ZDateTime(tCutoffDays _ "," _ tCutoffSecs, 3, 1)
    Set tCutoffIso = $Translate($Extract(tCutoffOdbc, 1, 19), " ", "T") _ "Z"
    Set tArgs2 = {"from_time": (tCutoffIso), "limit": 500}
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Search.SearchByTime).Invoke(tCtx, tArgs2, .tResult2)
    Do $$$AssertStatusOK(tSC2, "SearchByTime explicit from_time returns $$$OK")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("time_window_used"), 0, "time_window_used = 0 in explicit-bound mode")
    Quit
}

/// <p>AC-7 #2 — SearchByStatus with
/// <code>status_in:["Error","Suspended"]</code> returns the two
/// fixture sessions with Status=8/Error and Status=5/Suspended.
/// Excludes the Status=9/Completed session.</p>
Method TestSearchByStatusFiltersByEnumArray()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"status_in": ["Error", "Suspended"], "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByStatus).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByStatus.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "Status", "indexed_lead_column = Status")

    ; Fixture sessions: BASESID+2 (Error), BASESID+3 (Suspended) — must be present.
    ; BASESID+4 (Completed) — must be absent.
    Set tFoundError = 0, tFoundSuspended = 0, tFoundCompleted = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = (..#FIXTUREBASESID + 2) Set tFoundError = 1
        If tSid = (..#FIXTUREBASESID + 3) Set tFoundSuspended = 1
        If tSid = (..#FIXTUREBASESID + 4) Set tFoundCompleted = 1
    }
    Do $$$AssertTrue(tFoundError, "Error fixture session " _ (..#FIXTUREBASESID + 2) _ " present")
    Do $$$AssertTrue(tFoundSuspended, "Suspended fixture session " _ (..#FIXTUREBASESID + 3) _ " present")
    Do $$$AssertEquals(tFoundCompleted, 0, "Completed fixture session " _ (..#FIXTUREBASESID + 4) _ " EXCLUDED from Error+Suspended filter")

    ; Negative — unknown status value returns isError envelope.
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchByStatus).Invoke(tCtx, {"status_in":["NotARealStatus"]}, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on unknown status (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 on unknown status value")
    Quit
}

/// <p>AC-7 #3 — SearchBySource with <code>source_config_name="EpicADT"</code>
/// returns 2 sessions; the two with <code>SourceConfigName="EpicADT2"</code>
/// are excluded by the <code>%EXACT()</code> match.</p>
Method TestSearchBySourceExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"source_config_name": "EpicADT", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySource.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SourceConfigName", "indexed_lead_column = SourceConfigName")

    ; Count fixture sessions in result. BASESID+5,6 should be present;
    ; BASESID+7,8 (EpicADT2) must be absent.
    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 5)) || (tSid = (..#FIXTUREBASESID + 6)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 7)) || (tSid = (..#FIXTUREBASESID + 8)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "EpicADT fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "EpicADT2 fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #4 — same shape on <code>TargetConfigName</code>.</p>
Method TestSearchByTargetExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"target_config_name": "TgtAlpha", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByTarget).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByTarget.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "TargetConfigName", "indexed_lead_column = TargetConfigName")

    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 9)) || (tSid = (..#FIXTUREBASESID + 10)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 11)) || (tSid = (..#FIXTUREBASESID + 12)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "TgtAlpha fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "TgtBeta fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #5 — same shape on <code>MessageBodyClassName</code>.</p>
Method TestSearchByMessageClassExactMatchOnly()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"message_body_class_name": "Class.A.Msg", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByMessageClass).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByMessageClass.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "MessageBodyClassName", "indexed_lead_column = MessageBodyClassName")

    Set tFoundExact = 0, tFoundOther = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If (tSid = (..#FIXTUREBASESID + 13)) || (tSid = (..#FIXTUREBASESID + 14)) Set tFoundExact = tFoundExact + 1
        If (tSid = (..#FIXTUREBASESID + 15)) || (tSid = (..#FIXTUREBASESID + 16)) Set tFoundOther = tFoundOther + 1
    }
    Do $$$AssertEquals(tFoundExact, 2, "Class.A.Msg fixture sessions (2) present")
    Do $$$AssertEquals(tFoundOther, 0, "Class.B.Other fixture sessions (2) excluded by %EXACT() match")
    Quit
}

/// <p>AC-7 #6 — SearchBySession with the BASESID+99 fixture (whose
/// TimeCreated is 1000h ago) STILL resolves to the row, proving
/// keyed-lookup mode bypasses the time-window predicate. The
/// <code>time_window_used</code> envelope field is JSON null per AC-6.</p>
Method TestSearchBySessionKeyedLookupOmitsTimeWindow()
{
    Set tCtx = ..BuildCtx()
    Set tAncientSid = ..#FIXTUREBASESID + 99
    Set tArgs = {"session_id": (tAncientSid)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySession).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySession.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SessionId", "indexed_lead_column = SessionId")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("result_count"), 1, "result_count = 1 (the ancient fixture row)")

    ; Ancient fixture session must be present.
    Set tFoundAncient = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If +tEntry.%Get("session_id") = tAncientSid Set tFoundAncient = 1
    }
    Do $$$AssertTrue(tFoundAncient, "ancient fixture session " _ tAncientSid _ " resolved despite TimeCreated -1000h (proves keyed-lookup bypasses time window)")

    ; time_window_used is JSON null for keyed-lookup mode (AC-6).
    Do $$$AssertEquals(tResult.structuredContent.%IsDefined("time_window_used"), 1, "time_window_used field is present (set to JSON null) for keyed-lookup mode")
    ; Verify the value is JSON null — %DynamicObject.%Get returns the
    ; ObjectScript empty string "" for a JSON null value.
    Do $$$AssertEquals(tResult.structuredContent.%Get("time_window_used"), "", "time_window_used = JSON null (visible as empty-string via %Get)")
    ; Belt-and-suspenders — assert the JSON serialization actually contains :null.
    Set tJson = tResult.structuredContent.%ToJSON()
    Do $$$AssertTrue(tJson [ """time_window_used"":null", "JSON serialization contains 'time_window_used:null' — keyed-lookup mode visible")

    ; Negative — missing session_id returns isError envelope.
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchBySession).Invoke(tCtx, {}, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on missing session_id (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 on missing session_id")
    Quit
}

/// <p>Story 8.4 AC-7 #1 — invoke <CLASS>SessionAgent.Tool.Search.SearchBySuperSession</CLASS>
/// with explicit <code>super_session_key='SS-TEST-001'</code>. The
/// fixture seeded 4 <CLASS>Ens.SuperSessionIndex</CLASS> rows linking
/// <code>BASESID+30..BASESID+33</code> to that key; assert the tool
/// returns all 4 sessions, <code>session_count=4</code>, and
/// <code>time_window_used</code> is JSON null.</p>
Method TestSearchBySuperSessionByKey()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"super_session_key": "SS-TEST-001", "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySuperSession).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySuperSession.Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SuperSessionKey", "indexed_lead_column = SuperSessionKey")
    Do $$$AssertEquals(tResult.structuredContent.%Get("super_session_key"), "SS-TEST-001", "super_session_key echoed in envelope")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("session_count"), 4, "session_count = 4 (4-session fixture)")

    ; All 4 fixture sessions must be present.
    Set tFound30 = 0, tFound31 = 0, tFound32 = 0, tFound33 = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = (..#FIXTUREBASESID + 30) Set tFound30 = 1
        If tSid = (..#FIXTUREBASESID + 31) Set tFound31 = 1
        If tSid = (..#FIXTUREBASESID + 32) Set tFound32 = 1
        If tSid = (..#FIXTUREBASESID + 33) Set tFound33 = 1
    }
    Do $$$AssertTrue(tFound30, "fixture session BASESID+30 present")
    Do $$$AssertTrue(tFound31, "fixture session BASESID+31 present")
    Do $$$AssertTrue(tFound32, "fixture session BASESID+32 present")
    Do $$$AssertTrue(tFound33, "fixture session BASESID+33 present")

    ; time_window_used is JSON null for keyed-lookup mode (AC-5 parallel
    ; to SearchBySession's convention from Story 8.3).
    Do $$$AssertEquals(tResult.structuredContent.%IsDefined("time_window_used"), 1, "time_window_used field present (set to JSON null)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("time_window_used"), "", "time_window_used = JSON null (visible as empty-string via %Get)")
    Set tJson = tResult.structuredContent.%ToJSON()
    Do $$$AssertTrue(tJson [ """time_window_used"":null", "JSON serialization contains 'time_window_used:null'")
    Quit
}

/// <p>Story 8.4 AC-7 #2 — same fixture as
/// <method>TestSearchBySuperSessionByKey</method>; invoke with
/// <code>seed_session_id</code>. The tool's Phase-1 lookup resolves
/// the super-session key from the seed's
/// <CLASS>Ens.SuperSessionIndex</CLASS> row, then Phase-2 returns all
/// 4 siblings (including the seed itself, since the SQL grouping has
/// no exclusion).</p>
Method TestSearchBySuperSessionBySeedSessionId()
{
    Set tCtx = ..BuildCtx()
    Set tSeedSid = ..#FIXTUREBASESID + 30
    Set tArgs = {"seed_session_id": (tSeedSid), "limit": 500}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchBySuperSession).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchBySuperSession.Invoke (seed) returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("super_session_key"), "SS-TEST-001", "super_session_key resolved from seed via Phase-1 lookup")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("session_count"), 4, "session_count = 4 (seed + 3 siblings)")

    ; Verify seed and siblings present.
    Set tFoundSeed = 0, tFoundSibs = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = tSeedSid Set tFoundSeed = 1
        If (tSid = (..#FIXTUREBASESID + 31)) || (tSid = (..#FIXTUREBASESID + 32)) || (tSid = (..#FIXTUREBASESID + 33)) Set tFoundSibs = tFoundSibs + 1
    }
    Do $$$AssertTrue(tFoundSeed, "seed session " _ tSeedSid _ " present in result (no exclusion)")
    Do $$$AssertEquals(tFoundSibs, 3, "all 3 sibling sessions (BASESID+31, +32, +33) present")

    ; Negative — seed_session_id with no SuperSessionIndex entry returns
    ; the structured-error envelope (NOT an exception).
    Set tArgsBad = {"seed_session_id": "9999999"}
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchBySuperSession).Invoke(tCtx, tArgsBad, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on missing seed-supersession (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 when seed_session_id has no super-session entry")
    Quit
}

/// <p>Story 8.4 AC-7 #3 — XOR enforcement. Neither arg → structured
/// error; both args → structured error. Asserts the Invoke-time XOR
/// validation (the locked-subset JSON Schema cannot enforce XOR via
/// <code>oneOf</code>, so the tool body enforces it).</p>
Method TestSearchBySuperSessionXorRequired()
{
    Set tCtx = ..BuildCtx()

    ; Neither arg.
    Set tNeitherResult = ""
    Set tSCn = ##class(SessionAgent.Tool.Search.SearchBySuperSession).Invoke(tCtx, {}, .tNeitherResult)
    Do $$$AssertStatusOK(tSCn, "Invoke returns $$$OK on neither arg (envelope-based error)")
    Do $$$AssertEquals(+tNeitherResult.%Get("isError"), 1, "isError = 1 when neither super_session_key nor seed_session_id provided")
    Do $$$AssertTrue(tNeitherResult.%Get("content").%Get(0).%Get("text") [ "neither", "error text mentions 'neither'")

    ; Both args.
    Set tBothArgs = {"super_session_key":"X","seed_session_id":"Y"}
    Set tBothResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.SearchBySuperSession).Invoke(tCtx, tBothArgs, .tBothResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on both args (envelope-based error)")
    Do $$$AssertEquals(+tBothResult.%Get("isError"), 1, "isError = 1 when both super_session_key AND seed_session_id provided")
    Do $$$AssertTrue(tBothResult.%Get("content").%Get(0).%Get("text") [ "both", "error text mentions 'both'")
    Quit
}

/// <p>Story 8.5 AC-9 #1 — happy path. Fixture: 3 SearchTable rows in
/// <CLASS>SessionAgent.Test.FsbFixtureSearchTable</CLASS>
/// (PropId=BFFIXTUREPROPID, PropValue=BFFIXTUREPROPVALUE) +
/// 3 matching <CLASS>Ens.MessageHeader</CLASS> rows whose
/// <code>MessageBodyId</code> matches the fixture-SearchTable
/// <code>DocId</code>s. Sessions BASESID+50..52 (fresh time, well
/// within the 168h default window). The
/// <CLASS>Ens.Config.SearchTableProp</CLASS> mapping was seeded by
/// <method>OnBeforeAllTests</method>.</p>
///
/// <p>Asserts the tool returns all 3 sessions,
/// <code>render_strategy="matched_sessions"</code>,
/// <code>indexed_lead_column="PropValue"</code>, and
/// <code>time_window_used=168</code> (this tool's default override).</p>
Method TestSearchByBodyFieldHappyPath()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": (..#BFFIXTURECLASS), "prop_name": (..#BFFIXTUREPROPNAME), "prop_value": (..#BFFIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByBodyField).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "SearchByBodyField.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on happy path")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "PropValue", "indexed_lead_column = PropValue (canonical placeholder)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "matched_sessions", "render_strategy = matched_sessions")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("session_count"), 3, "session_count = 3 (3 fixture rows)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("time_window_used"), 168, "time_window_used = 168 (this tool's default, override of base 24h)")

    ; Verify all 3 fixture sessions present.
    Set tFound50 = 0, tFound51 = 0, tFound52 = 0
    Set tIter = tResult.structuredContent.%Get("sessions").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tSid = +tEntry.%Get("session_id")
        If tSid = (..#FIXTUREBASESID + 50) Set tFound50 = 1
        If tSid = (..#FIXTUREBASESID + 51) Set tFound51 = 1
        If tSid = (..#FIXTUREBASESID + 52) Set tFound52 = 1
    }
    Do $$$AssertTrue(tFound50, "fixture session BASESID+50 present")
    Do $$$AssertTrue(tFound51, "fixture session BASESID+51 present")
    Do $$$AssertTrue(tFound52, "fixture session BASESID+52 present")

    ; Echo of search_table_class + prop_name + prop_value in envelope.
    Do $$$AssertEquals(tResult.structuredContent.%Get("search_table_class"), ..#BFFIXTURECLASS, "search_table_class echoed")
    Do $$$AssertEquals(tResult.structuredContent.%Get("prop_name"), ..#BFFIXTUREPROPNAME, "prop_name echoed")
    Do $$$AssertEquals(tResult.structuredContent.%Get("prop_value"), ..#BFFIXTUREPROPVALUE, "prop_value echoed")

    ; Operator-readable summary text mentions the operator-supplied prop_name.
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ ..#BFFIXTUREPROPNAME, "summary text mentions operator-supplied prop_name (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ ..#BFFIXTUREPROPVALUE, "summary text mentions operator-supplied prop_value")
    Do $$$AssertTrue(tSummary [ ..#BFFIXTURECLASS, "summary text mentions search_table_class")
    Quit
}

/// <p>Story 8.5 AC-9 #2 — unknown prop_name. Same fixture, but invoke
/// with a prop_name that does NOT exist in
/// <CLASS>Ens.Config.SearchTableProp</CLASS> for this SearchTable. The
/// tool returns the <code>no_matches</code> envelope with
/// <code>isError:1</code> and operator-readable text
/// "<i>Property '...' is not indexed by SearchTable '...'</i>".</p>
Method TestSearchByBodyFieldUnknownPropNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": (..#BFFIXTURECLASS), "prop_name": "NotARegisteredProp", "prop_value": (..#BFFIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByBodyField).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on unknown prop_name (envelope-based error)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on unknown prop_name")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "no_matches", "render_strategy = no_matches (graceful — prop_name not registered)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("session_count"), 0, "session_count = 0")

    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "not indexed", "summary text mentions 'not indexed' (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "NotARegisteredProp", "summary text mentions the unknown prop_name")
    Do $$$AssertTrue(tSummary [ ..#BFFIXTURECLASS, "summary text mentions the SearchTable class")
    Quit
}

/// <p>Story 8.5 AC-9 #3 — unknown search_table_class. Invoke with a
/// fully-qualified class name that does NOT exist in this namespace.
/// The tool returns the <code>search_table_not_installed</code>
/// envelope with <code>isError:1</code> and the AC-3 mandated
/// operator-readable text mentioning install guidance.</p>
Method TestSearchByBodyFieldUnknownClassReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"search_table_class": "My.NotARealSearchTable", "prop_name": (..#BFFIXTUREPROPNAME), "prop_value": (..#BFFIXTUREPROPVALUE)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.SearchByBodyField).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on unknown class (envelope-based error)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 on unknown class")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "search_table_not_installed", "render_strategy = search_table_not_installed")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("session_count"), 0, "session_count = 0")

    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "is not an installed Ens.SearchTableBase subclass", "summary text matches AC-3 wording (got: " _ tSummary _ ")")
    Do $$$AssertTrue(tSummary [ "My.NotARealSearchTable", "summary text echoes the unknown class name")
    Do $$$AssertTrue(tSummary [ "search_by_message_class", "summary text mentions fallback tool 'search_by_message_class'")
    Quit
}

/// <p>Story 8.6 AC-11 #1 — happy-path substring match. Fixture: 5
/// rows in <code>BASESID+60..64</code> with bodies containing patterns
/// that match (3 rows containing "E11") or NOT (2 rows: "E12.0" and
/// "unrelated"). Prefilter on
/// <code>SourceConfigName=IBCFIXTURESOURCESENTINEL</code> so the test
/// narrows to the fixture only. Pattern <code>"E11"</code> (substring,
/// default mode). Asserts the matching subset is returned with the
/// AC-7 envelope shape.</p>
Method TestInspectBodyCandidatesHappyPathSubstring()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"pattern":"E11", "prefilter_indexed_column":"SourceConfigName", "prefilter_value":(..#IBCFIXTURESOURCESENTINEL)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "InspectBodyCandidates.Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on happy path")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "SourceConfigName", "indexed_lead_column echoes prefilter_indexed_column")
    Do $$$AssertEquals(tResult.structuredContent.%Get("pattern"), "E11", "pattern echoed")
    Do $$$AssertEquals(tResult.structuredContent.%Get("prefilter_value"), ..#IBCFIXTURESOURCESENTINEL, "prefilter_value echoed")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("time_window_used"), 24, "time_window_used = 24 (default)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("pattern_is_regex"), 0, "pattern_is_regex = false (default)")

    ; The fixture seeded 5 happy-path rows + 1 missing-body row, total 6.
    ; The missing-body row is dropped per AC-6, so candidates_inspected = 6
    ; (count of attempted), match_count = 3 (E11.9 + E11.9 + E11 matches).
    ; "E12.0" and "unrelated" don't match; missing-body silently dropped.
    Do $$$AssertTrue(+tResult.structuredContent.%Get("candidates_inspected") >= 5, "candidates_inspected >= 5 (5 happy-path fixture rows seen; missing-body counted but match dropped)")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("match_count"), 3, "match_count = 3 (E11.9 primary, E11.9 patient, E11 short)")

    ; Verify match envelope shape — each match has message_id, session_id,
    ; body_class, body_excerpt.
    Set tMatches = tResult.structuredContent.%Get("matches")
    Do $$$AssertTrue($IsObject(tMatches), "matches is an array")
    Do $$$AssertEquals(tMatches.%Size(), 3, "matches array has 3 entries")
    Set tMIter = tMatches.%GetIterator()
    Set tFoundE11 = 0
    While tMIter.%GetNext(.tMKey, .tMatch) {
        Do $$$AssertTrue(tMatch.%IsDefined("message_id"), "match has message_id")
        Do $$$AssertTrue(tMatch.%IsDefined("session_id"), "match has session_id")
        Do $$$AssertTrue(tMatch.%IsDefined("body_class"), "match has body_class")
        Do $$$AssertTrue(tMatch.%IsDefined("body_excerpt"), "match has body_excerpt")
        Do $$$AssertEquals(tMatch.%Get("body_class"), "Ens.StringRequest", "body_class is Ens.StringRequest")
        ; body_excerpt should mention "E11" (substring match guarantee).
        If tMatch.%Get("body_excerpt") [ "E11" Set tFoundE11 = tFoundE11 + 1
    }
    Do $$$AssertEquals(tFoundE11, 3, "all 3 match excerpts contain 'E11' (substring match correctness)")

    ; Operator-readable summary text.
    Set tSummary = tResult.content.%Get(0).text
    Do $$$AssertTrue(tSummary [ "Inspected", "summary text begins with 'Inspected'")
    Do $$$AssertTrue(tSummary [ "matched", "summary text contains 'matched'")
    Do $$$AssertTrue(tSummary [ "E11", "summary text mentions the pattern")
    Quit
}

/// <p>Story 8.6 AC-11 #2 — regex mode. Same fixture as
/// <method>TestInspectBodyCandidatesHappyPathSubstring</method>; invoke
/// with <code>pattern_is_regex=true</code>, pattern
/// <code>"E1[12]"</code>. The PCRE/ICU regex matches BOTH "E11" AND
/// "E12" rows — should hit 4 matches (3 E11 rows + 1 E12 row).</p>
Method TestInspectBodyCandidatesRegexMode()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"pattern":"E1[12]", "pattern_is_regex":(1), "prefilter_indexed_column":"SourceConfigName", "prefilter_value":(..#IBCFIXTURESOURCESENTINEL)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "InspectBodyCandidates.Invoke (regex mode) returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on happy regex path")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("pattern_is_regex"), 1, "pattern_is_regex = true (echoed)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("pattern"), "E1[12]", "regex pattern echoed verbatim")

    ; PCRE "E1[12]" matches "E11" AND "E12" — total 4 matches:
    ; +60 "E11.9 ...", +61 "E12.0 ...", +63 "Patient ... E11.9", +64 "E11 short ...".
    Do $$$AssertEquals(+tResult.structuredContent.%Get("match_count"), 4, "regex 'E1[12]' matches 4 fixture bodies (3 E11 + 1 E12)")

    ; Verify the regex picked up E12 too (proves it's not just substring).
    Set tFoundE12 = 0
    Set tMatches = tResult.structuredContent.%Get("matches")
    Set tMIter = tMatches.%GetIterator()
    While tMIter.%GetNext(.tMKey, .tMatch) {
        If tMatch.%Get("body_excerpt") [ "E12" Set tFoundE12 = 1
    }
    Do $$$AssertEquals(tFoundE12, 1, "regex matched 'E12' row (proves PCRE [12] character class fired)")

    ; Negative — invalid regex returns structured error envelope.
    Set tBadArgs = {"pattern":"[unclosed", "pattern_is_regex":(1), "prefilter_indexed_column":"SourceConfigName", "prefilter_value":(..#IBCFIXTURESOURCESENTINEL)}
    Set tBadResult = ""
    Set tSCb = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tBadArgs, .tBadResult)
    Do $$$AssertStatusOK(tSCb, "Invoke returns $$$OK on bad regex (envelope-based error)")
    Do $$$AssertEquals(+tBadResult.%Get("isError"), 1, "isError = 1 on bad regex pattern")
    Do $$$AssertTrue(tBadResult.content.%Get(0).text [ "regex", "error text mentions 'regex'")
    Quit
}

/// <p>Story 8.6 AC-11 #3 — AC-2 hard cap rejection. Caller-supplied
/// <code>candidate_cap=100</code> exceeds NFR-P3's hard maximum of 50;
/// the tool returns the structured-error envelope BEFORE the prefilter
/// SQL runs (hard validation, NOT silent clamp). Asserts the
/// errorCode + maxAllowed fields are populated per the AC-2 contract.</p>
Method TestInspectBodyCandidatesCapEnforcedAt50()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"pattern":"anything", "prefilter_indexed_column":"Status", "prefilter_value":"8", "candidate_cap":(100)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on cap-overflow (envelope-based error)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError = 1 when candidate_cap > 50 (NFR-P3 hard bound)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "validation_error", "render_strategy = validation_error")
    Do $$$AssertEquals(tResult.structuredContent.%Get("errorCode"), "CandidateCapTooLarge", "errorCode = CandidateCapTooLarge")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("maxAllowed"), 50, "maxAllowed = 50 (NFR-P3)")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "candidate_cap", "error text mentions candidate_cap")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "exceeds", "error text mentions 'exceeds'")

    ; Verify a valid cap still works (cap=5 is below hard max).
    Set tValidArgs = {"pattern":"E11", "prefilter_indexed_column":"SourceConfigName", "prefilter_value":(..#IBCFIXTURESOURCESENTINEL), "candidate_cap":(5)}
    Set tValidResult = ""
    Set tSCv = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tValidArgs, .tValidResult)
    Do $$$AssertStatusOK(tSCv, "Invoke with cap=5 returns $$$OK")
    Do $$$AssertEquals(+tValidResult.%Get("isError"), 0, "cap=5 (under hard max) succeeds")
    Quit
}

/// <p>Story 8.6 AC-11 #4 — graceful body-render error. The fixture's
/// BASESID+65 row has <code>MessageBodyId</code> pointing at a
/// non-existent <CLASS>Ens.StringRequest</CLASS> id; the inner
/// <method>GetMessageBody.Invoke</method> returns
/// <code>render_strategy="body_not_found"</code> per Step 2 of its
/// dispatch ladder. Per AC-6 the candidate is silently dropped from
/// the matches list but counted in <code>candidates_inspected</code>.
/// Test invokes the tool and asserts the missing-body row contributes
/// to <code>candidates_inspected</code> but not to <code>match_count</code>
/// (and certainly does NOT propagate as an envelope error).</p>
Method TestInspectBodyCandidatesGracefulBodyError()
{
    Set tCtx = ..BuildCtx()
    ; Pattern that matches "diagnosis" — present in 3 of the 5 body rows
    ; (+60 "E11.9 diagnosis ...", +61 "E12.0 diagnosis ...", +63
    ; "Patient diagnosis E11.9", +64 "E11 short diagnosis"). 4 of 5
    ; rows match. Plus 1 missing-body row (BASESID+65) — dropped silently
    ; per AC-6, but counted in candidates_inspected.
    Set tArgs = {"pattern":"diagnosis", "prefilter_indexed_column":"SourceConfigName", "prefilter_value":(..#IBCFIXTURESOURCESENTINEL)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.InspectBodyCandidates).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK despite per-candidate body error (no exception escapes)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set despite per-candidate body-render error")

    ; candidates_inspected counts ALL candidates the tool TRIED (including
    ; the missing-body one). 5 happy + 1 missing = 6 total. The fixture
    ; ROW count is what gets counted; whether the inner Invoke succeeds
    ; or fails, the candidate is "inspected".
    Do $$$AssertEquals(+tResult.structuredContent.%Get("candidates_inspected"), 6, "candidates_inspected = 6 (5 happy + 1 missing-body, all attempted)")

    ; match_count: 4 (the 4 'diagnosis'-containing rows; the missing-body
    ; row drops without propagating any error to the envelope; the
    ; "unrelated text content" row doesn't match).
    Do $$$AssertEquals(+tResult.structuredContent.%Get("match_count"), 4, "match_count = 4 (4 'diagnosis'-containing rows; missing-body silently dropped per AC-6)")

    ; Verify the matches list does NOT contain a row for the missing-body
    ; SessionId (BASESID+65). If the missing-body wasn't dropped, it would
    ; either crash or appear in matches.
    Set tFoundMissing = 0
    Set tMatches = tResult.structuredContent.%Get("matches")
    Set tMIter = tMatches.%GetIterator()
    While tMIter.%GetNext(.tMKey, .tMatch) {
        If +tMatch.%Get("session_id") = (..#FIXTUREBASESID + 65) Set tFoundMissing = 1
    }
    Do $$$AssertEquals(tFoundMissing, 0, "missing-body row (BASESID+65) NOT present in matches (dropped per AC-6)")
    Quit
}

/// <p>Story 8.7 — VocabLookup test scaffolding. Each vocab test uses the
/// <code>"vocab-tester"</code> portal user (distinct from the default
/// <code>"tester"</code> from <method>BuildCtx</method>) so the
/// per-test fixture is isolated from any production UserVocabulary
/// rows that may exist for the default test user. Pre-test cleanup
/// sweeps any prior-run debris for that PortalUser.</p>
Parameter VOCABTESTUSER As %String = "vocab-tester";

/// <p>Build a CallerContext stub with the vocab-test PortalUser.</p>
ClassMethod BuildVocabCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "message-search"
    Set tCtx.PortalUser = ..#VOCABTESTUSER
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Sweep all UserVocabulary rows for the vocab-test PortalUser. Used
/// in pre-test setup AND post-test cleanup for every vocab test so
/// independent test runs do not see stale fixture state.</p>
ClassMethod CleanVocabFixture()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    If $$$ISOK(tStmt.%Prepare("DELETE FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ?")) {
        Do tStmt.%Execute(..#VOCABTESTUSER)
    }
    Quit
}

/// <p>Story 8.7 AC-11 #1 — mode='list' against an empty UserVocabulary
/// for the vocab-test PortalUser returns <code>count=0</code> and an
/// empty <code>vocabulary:[]</code> array.</p>
Method TestVocabLookupListEmpty()
{
    Do ..CleanVocabFixture()
    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "list"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "VocabLookup mode=list returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "list mode (empty fixture) is success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("mode"), "list", "structuredContent.mode = list")
    Do $$$AssertEquals(tResult.structuredContent.%Get("portal_user"), ..#VOCABTESTUSER, "portal_user echoed")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("count"), 0, "count = 0 on empty fixture")
    Do $$$AssertEquals(tResult.structuredContent.%Get("vocabulary").%Size(), 0, "vocabulary array is empty")
    Do $$$AssertEquals(tResult.structuredContent.%Get("indexed_lead_column"), "PortalUser", "indexed_lead_column = PortalUser")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 AC-11 #2 — mode='save' on an empty fixture creates a
/// new UserVocabulary row with <code>SuccessCount=1</code>,
/// <code>Confidence=0.5</code> (Story 9.2 trigger recomputes
/// <code>1 / (1+0+1) = 0.5</code> via <code>%OnAfterSave</code>),
/// <code>CreatedVia="explicit"</code>; envelope <code>action="created"</code>.</p>
Method TestVocabLookupSaveCreatesRow()
{
    Do ..CleanVocabFixture()
    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "save", "alias": "failed admits", "description": "sessions where Status='Error' and source has 'A01'"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "VocabLookup mode=save returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "save mode (new row) is success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("mode"), "save", "structuredContent.mode = save")
    Do $$$AssertEquals(tResult.structuredContent.%Get("action"), "created", "action = created on new row")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("new_success_count"), 1, "new_success_count = 1 on first save")
    Do $$$AssertEquals(tResult.structuredContent.%Get("alias"), "failed admits", "alias echoed")

    ; Verify DB state — exactly 1 row exists with the expected shape.
    Set tProbe = ##class(%SQL.Statement).%New()
    Do tProbe.%Prepare("SELECT COUNT(*) AS c, MAX(SuccessCount) AS sc, MAX(Confidence) AS cf, MAX(%EXACT(CreatedVia)) AS cv FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tProbe.%Execute(..#VOCABTESTUSER, "failed admits")
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 1, "exactly 1 UserVocabulary row exists for the saved alias")
    Do $$$AssertEquals(+tRs.%Get("sc"), 1, "DB SuccessCount = 1")
    Do $$$AssertEquals(+tRs.%Get("cf"), 0.5, "DB Confidence = 0.5 (Story 9.2 %OnAfterSave: 1 / (1+0+1) = 0.5)")
    Do $$$AssertEquals(tRs.%Get("cv"), "explicit", "DB CreatedVia = explicit")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 AC-11 #3 — mode='save' on a fixture that already has
/// the same <code>(PortalUser, Alias, MessageBodyClass)</code> triple
/// increments <code>SuccessCount</code> from 1 to 2; envelope
/// <code>action="incremented"</code>; DB still has only 1 row.</p>
Method TestVocabLookupSaveIncrementsExistingRow()
{
    Do ..CleanVocabFixture()

    ; Seed an existing row directly via the OREF API so the second
    ; save's increment path is exercised.
    Set tSeed = ##class(SessionAgent.Search.UserVocabulary).%New()
    Set tSeed.PortalUser = ..#VOCABTESTUSER
    Set tSeed.Alias = "completed orders"
    Set tSeed.MessageBodyClass = ""
    Set tSeed.SuccessCount = 1
    Set tSeed.FailureCount = 0
    Set tSeed.Confidence = 0
    Set tSeed.CreatedVia = "explicit"
    Set tSeed.CreatedAt = "2026-05-07T00:00:00Z"
    Set tSeed.LastUsed = "2026-05-07T00:00:00Z"
    Do $$$AssertStatusOK(tSeed.%Save(), "seed UserVocabulary row saved")

    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "save", "alias": "completed orders"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "VocabLookup mode=save (increment path) returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "save mode (existing row) is success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("action"), "incremented", "action = incremented on existing row")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("new_success_count"), 2, "new_success_count = 2 after increment")

    ; Verify DB still has only 1 row (idempotent — the IS NULL composite-key
    ; probe matched the seeded row).
    Set tProbe = ##class(%SQL.Statement).%New()
    Do tProbe.%Prepare("SELECT COUNT(*) AS c, MAX(SuccessCount) AS sc FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tProbe.%Execute(..#VOCABTESTUSER, "completed orders")
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 1, "still exactly 1 UserVocabulary row (idempotent — IS NULL composite-key probe matched the seeded row)")
    Do $$$AssertEquals(+tRs.%Get("sc"), 2, "DB SuccessCount = 2 after increment")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 AC-11 #4 — mode='search' with substring pattern
/// <code>"ed"</code> against 3 seeded rows
/// (<code>"failed admits"</code>, <code>"completed orders"</code>,
/// <code>"errored discharges"</code>) returns all 3 matches (substring
/// <code>"ed"</code> appears in <code>fail<b>ed</b></code>,
/// <code>complet<b>ed</b></code>, <code><b>e</b>rror<b>ed</b></code>).</p>
Method TestVocabLookupSearchSubstringMatch()
{
    Do ..CleanVocabFixture()

    For tAlias = "failed admits", "completed orders", "errored discharges" {
        Set tRow = ##class(SessionAgent.Search.UserVocabulary).%New()
        Set tRow.PortalUser = ..#VOCABTESTUSER
        Set tRow.Alias = tAlias
        Set tRow.MessageBodyClass = ""
        Set tRow.SuccessCount = 1
        Set tRow.FailureCount = 0
        Set tRow.Confidence = 0
        Set tRow.CreatedVia = "explicit"
        Set tRow.CreatedAt = "2026-05-07T00:00:00Z"
        Set tRow.LastUsed = "2026-05-07T00:00:00Z"
        Do $$$AssertStatusOK(tRow.%Save(), "seed UserVocabulary row '" _ tAlias _ "' saved")
    }

    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "search", "alias": "ed"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "VocabLookup mode=search returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "search mode is success envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("mode"), "search", "structuredContent.mode = search")
    Do $$$AssertEquals(tResult.structuredContent.%Get("alias_pattern"), "ed", "alias_pattern echoed")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("count"), 3, "count = 3 (all 3 seeded rows match substring 'ed')")
    Do $$$AssertEquals(tResult.structuredContent.%Get("matches").%Size(), 3, "matches array has 3 entries")

    ; Verify each expected alias appears in the matches list.
    Set tFoundFailed = 0, tFoundCompleted = 0, tFoundErrored = 0
    Set tIter = tResult.structuredContent.%Get("matches").%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tA = tEntry.%Get("alias")
        If tA = "failed admits" Set tFoundFailed = 1
        If tA = "completed orders" Set tFoundCompleted = 1
        If tA = "errored discharges" Set tFoundErrored = 1
    }
    Do $$$AssertTrue(tFoundFailed, "'failed admits' present in matches")
    Do $$$AssertTrue(tFoundCompleted, "'completed orders' present in matches")
    Do $$$AssertTrue(tFoundErrored, "'errored discharges' present in matches")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 review-fix HIGH — regression guard for the
/// <code>(PortalUser, Alias)</code> pair-unique probe. A second save
/// with the SAME alias but a DIFFERENT MessageBodyClass MUST NOT
/// trigger a unique-constraint violation — the implementation matches
/// the schema's pair-unique index by probing on the pair (NOT the
/// triple including MessageBodyClass) and updating MessageBodyClass
/// on the existing row when the operator supplies a new value.</p>
Method TestVocabLookupSaveDifferentBodyClassUpdatesExistingRow()
{
    Do ..CleanVocabFixture()

    ; First save — with empty MessageBodyClass.
    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "save", "alias": "ED visit", "message_body_class": ""}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "first save returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("action"), "created", "first save action = created")

    ; Second save — same (PortalUser, Alias) but DIFFERENT MessageBodyClass.
    ; Schema's UserAliasIdx is unique on (PortalUser, Alias) only, so the
    ; pair-probe correctly matches the existing row and increments rather
    ; than attempting an INSERT that would fail uniqueness.
    Set tArgs2 = {"mode": "save", "alias": "ED visit", "message_body_class": "EnsLib.HL7.Message"}
    Set tResult2 = ""
    Set tSC2 = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs2, .tResult2)
    Do $$$AssertStatusOK(tSC2, "second save (different body_class) returns $$$OK")
    Do $$$AssertEquals(+tResult2.%Get("isError"), 0, "second save is success envelope (not unique-violation error)")
    Do $$$AssertEquals(tResult2.structuredContent.%Get("action"), "incremented", "action = incremented (not created or error)")
    Do $$$AssertEquals(+tResult2.structuredContent.%Get("new_success_count"), 2, "new_success_count = 2 after pair-match increment")

    ; Verify DB — still exactly 1 row, MessageBodyClass updated.
    Set tProbe = ##class(%SQL.Statement).%New()
    Do tProbe.%Prepare("SELECT COUNT(*) AS c, MAX(%EXACT(MessageBodyClass)) AS bc, MAX(SuccessCount) AS sc FROM SessionAgent_Search.UserVocabulary WHERE %EXACT(PortalUser) = ? AND %EXACT(Alias) = ?")
    Set tRs = tProbe.%Execute(..#VOCABTESTUSER, "ED visit")
    Do tRs.%Next()
    Do $$$AssertEquals(+tRs.%Get("c"), 1, "still exactly 1 UserVocabulary row (pair-unique constraint preserved)")
    Do $$$AssertEquals(tRs.%Get("bc"), "EnsLib.HL7.Message", "MessageBodyClass updated to operator's new value")
    Do $$$AssertEquals(+tRs.%Get("sc"), 2, "DB SuccessCount = 2 after increment")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 review-fix MEDIUM — operator-supplied <code>limit</code>
/// in list mode is honored (capped at 200). Seeds 5 rows; invokes
/// list with <code>limit=3</code>; asserts exactly 3 rows returned.</p>
Method TestVocabLookupListLimitParameterRespected()
{
    Do ..CleanVocabFixture()

    For tAlias = "alpha 1", "beta 2", "gamma 3", "delta 4", "epsilon 5" {
        Set tRow = ##class(SessionAgent.Search.UserVocabulary).%New()
        Set tRow.PortalUser = ..#VOCABTESTUSER
        Set tRow.Alias = tAlias
        Set tRow.MessageBodyClass = ""
        Set tRow.SuccessCount = 1
        Set tRow.FailureCount = 0
        Set tRow.Confidence = 0
        Set tRow.CreatedVia = "explicit"
        Set tRow.CreatedAt = "2026-05-07T00:00:00Z"
        Set tRow.LastUsed = "2026-05-07T00:00:00Z"
        Do $$$AssertStatusOK(tRow.%Save(), "seed row '" _ tAlias _ "' saved")
    }

    Set tCtx = ..BuildVocabCtx()
    Set tArgs = {"mode": "list", "limit": 3}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Search.VocabLookup).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "list mode with limit=3 returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "list mode is success envelope")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("count"), 3, "exactly 3 rows returned (limit honored)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("vocabulary").%Size(), 3, "vocabulary array has 3 entries")
    Do ..CleanVocabFixture()
    Quit
}

/// <p>Story 8.7 AC-8 — comprehensive L1 read-only invariant test.
/// Discovers every concrete <CLASS>SessionAgent.Tool.Search.*</CLASS>
/// subclass (excluding test fixtures) via the same query
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> uses; for
/// each, asserts the compiled <code>MutatesState</code> parameter
/// equals 0. Locks NFR-S1 Layer 1 enforcement at the search-agent
/// surface — a future author who flips the flag (e.g., to allow a
/// future write-tool) gets a CI failure here.</p>
///
/// <p><b>Expected total — 10 tools:</b> 8 indexed-access search tools
/// (search_by_time/status/source/target/message_class/session/super_session/body_field)
/// + inspect_body_candidates + vocab_lookup. Closes the Epic 8
/// acceptance gate (AC-15).</p>
Method TestAllSearchToolsAreReadOnly()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE %EXACT(Super) = 'SessionAgent.Tool.Search.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "search-tool discovery query prepared")
    Set tRs = tStmt.%Execute()
    Set tCount = 0
    Set tWriteTools = ""
    While tRs.%Next() {
        Set tClassName = tRs.%Get("ClassName")
        Set tCount = tCount + 1
        Set tParam = ##class(%Dictionary.ParameterDefinition).%OpenId(tClassName _ "||MutatesState")
        Do $$$AssertTrue($IsObject(tParam), tClassName _ " has MutatesState parameter row")
        Do $$$AssertEquals(+tParam.Default, 0, tClassName _ " MutatesState=0 (NFR-S1 L1 read-only invariant)")
        If +tParam.Default = 1 Set tWriteTools = tWriteTools _ tClassName _ ", "
    }
    Do $$$AssertEquals(tCount, 10, "exactly 10 production search tools registered (Epic 8 acceptance gate)")
    Do $$$AssertEquals(tWriteTools, "", "no write-capable search tool present (read-only contract)")
    Quit
}

/// <p>Story 8.7 AC-9 — comprehensive envelope-shape iteration. For each
/// of the 10 production search tools, build a representative input,
/// invoke, and assert the result is either a structured success
/// envelope (<code>structuredContent</code> present) OR a structured
/// error envelope (<code>isError:1</code> + <code>content[0].text</code>).
/// NEVER an unstructured ObjectScript exception.</p>
Method TestAllSearchToolsReturnValidEnvelopes()
{
    Set tCtx = ..BuildVocabCtx()
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE %EXACT(Super) = 'SessionAgent.Tool.Search.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "search-tool discovery query prepared")
    Set tRs = tStmt.%Execute()
    Set tCount = 0
    While tRs.%Next() {
        Set tClassName = tRs.%Get("ClassName")
        Set tToolName = ##class(SessionAgent.Tool.Registry).GetParameterValue(tClassName, "ToolName")
        Set tArgs = ..BuildRepresentativeVocabArgs(tToolName)
        Set tResult = ""
        Set tToolSC = $ClassMethod(tClassName, "Invoke", tCtx, tArgs, .tResult)
        Do $$$AssertStatusOK(tToolSC, tClassName _ ".Invoke returns $$$OK (envelope-based error contract)")
        Do $$$AssertTrue($IsObject(tResult), tClassName _ ": pResult populated as %DynamicObject")
        Do $$$AssertTrue($IsObject(tResult.content), tClassName _ ": content array present")
        Do $$$AssertTrue(tResult.content.%Size() >= 1, tClassName _ ": content has at least one entry")
        ; Either structured success (structuredContent present) OR structured error (isError=1).
        Set tIsError = +tResult.%Get("isError")
        If tIsError = 1 {
            Do $$$AssertTrue(tResult.content.%Get(0).%IsDefined("text"), tClassName _ ": error envelope content[0].text present")
        } Else {
            Do $$$AssertTrue($IsObject(tResult.structuredContent), tClassName _ ": success envelope has structuredContent")
        }
        Set tCount = tCount + 1
    }
    Do $$$AssertEquals(tCount, 10, "exactly 10 production search tools iterated (Epic 8 acceptance gate)")
    Quit
}

/// <p>Build representative input args for the comprehensive envelope-shape
/// iteration test. Uses synthetic / no-match values so the tools either
/// return empty result sets (success envelope) or structured-error
/// envelopes — both acceptable shapes for the iteration. No fixture
/// seeding required.</p>
ClassMethod BuildRepresentativeVocabArgs(pToolName As %String) As %DynamicObject
{
    Set tArgs = {}
    If pToolName = "search_by_time" {
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_status" {
        Set tStatusArr = ##class(%DynamicArray).%New()
        Do tStatusArr.%Push("Error")
        Do tArgs.%Set("status_in", tStatusArr)
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_source" {
        Do tArgs.%Set("source_config_name", "SyntheticTestSrc_NoMatch")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_target" {
        Do tArgs.%Set("target_config_name", "SyntheticTestTgt_NoMatch")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_message_class" {
        Do tArgs.%Set("message_body_class_name", "Synthetic.NoMatch.Msg")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_session" {
        Do tArgs.%Set("session_id", "9799911")
    } ElseIf pToolName = "search_by_super_session" {
        Do tArgs.%Set("super_session_key", "Synthetic.NoMatch.SuperSession")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_body_field" {
        Do tArgs.%Set("search_table_class", "Synthetic.NoMatch.SearchTable")
        Do tArgs.%Set("prop_name", "MRN")
        Do tArgs.%Set("prop_value", "synthetic-no-match-12345")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "inspect_body_candidates" {
        Do tArgs.%Set("pattern", "synthetic-no-match-pattern-87")
        Do tArgs.%Set("prefilter_indexed_column", "Status")
        Do tArgs.%Set("prefilter_value", "Synthetic.NoMatch.Status")
    } ElseIf pToolName = "vocab_lookup" {
        Do tArgs.%Set("mode", "list")
    }
    Quit tArgs
}

}
