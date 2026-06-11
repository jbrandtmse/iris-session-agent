/// <p>Story 14.4 AC-5 — unit tests for
/// <CLASS>SessionAgent.Knowledge.SchemaNoteDigest</CLASS>:
/// most-recently-verified-first ordering, the MAXENTRIES=10 entry cap,
/// the MAXCHARS=2000 row-granular char cap, the age marker, and the
/// empty-namespace → <code>""</code> contract (no seed fallback —
/// unlike <CLASS>SessionAgent.Search.VocabularyDigest</CLASS>).</p>
Class SessionAgent.Test.SchemaNoteDigestTest Extends %UnitTest.TestCase
{

/// <p>Synthetic fixture namespace (Story 14.4 review fix): seeding under
/// a namespace string no operator ever uses makes the absolute-count
/// assertions (entry cap, hidden-rows marker) deterministic regardless
/// of operator-saved notes in the live namespace. The Namespace column
/// is a scoping string — no real IRIS namespace is required.</p>
Parameter DIGNS As %String = "ZTESTNS144DIG";

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Quit ##class(SessionAgent.Test.SchemaNoteToolTest).DeleteFixtureRows()
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Quit ##class(SessionAgent.Test.SchemaNoteToolTest).DeleteFixtureRows()
}

/// <p>AC-5 — zero notes for the namespace returns the EMPTY string (no
/// seed fallback; the AgentLoop empty-digest collapse depends on this).</p>
Method TestEmptyNamespaceReturnsEmptyString()
{
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build("ZTESTNOSUCHNS144")
    Do $$$AssertEquals(tDigest, "", "no notes -> Build returns '' (AC-5 Then)")
    ; Defensive: empty namespace argument also returns "".
    Do $$$AssertEquals(##class(SessionAgent.Knowledge.SchemaNoteDigest).Build(""), "", "empty namespace arg -> ''")
    Quit
}

/// <p>AC-5 — ordering: most recently verified first; each line carries
/// the subject and an age marker.</p>
Method TestOrderingMostRecentFirstWithAgeMarkers()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-dig-old", "old digest fact", 7, ..#DIGNS), "7-day-old fixture seeded")
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-dig-fresh", "fresh digest fact", 0, ..#DIGNS), "fresh fixture seeded")

    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build(..#DIGNS)
    Do $$$AssertNotEquals(tDigest, "", "digest non-empty with fixtures present")
    Do $$$AssertTrue(tDigest [ "## Learned schema notes", "digest carries the header")

    Set tFreshPos = $Find(tDigest, "ztest-dig-fresh")
    Set tOldPos = $Find(tDigest, "ztest-dig-old")
    Do $$$AssertTrue(tFreshPos > 0, "fresh subject present in digest")
    Do $$$AssertTrue(tOldPos > 0, "old subject present in digest")
    Do $$$AssertTrue(tFreshPos < tOldPos, "fresh note renders BEFORE the 7-day-old note (most-recently-verified first)")

    ; Age markers (AC-5: each line carries subject + age marker).
    Do $$$AssertTrue(tDigest [ "(verified today)", "fresh note carries the 'verified today' marker")
    Do $$$AssertTrue(tDigest [ "(verified 7 day(s) ago)", "old note carries the day-count age marker")
    Quit
}

/// <p>AC-5 — MAXENTRIES=10 entry cap: 12 notes render 10 lines plus the
/// hidden-rows marker naming the 2 hidden notes.</p>
Method TestEntryCap()
{
    For i = 1:1:12 {
        Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-cap-" _ $Translate($Justify(i, 2), " ", "0"), "entry cap fixture " _ i, 0, ..#DIGNS), "fixture " _ i _ " seeded")
    }
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build(..#DIGNS)
    Do $$$AssertNotEquals(tDigest, "", "digest non-empty")

    ; Count rendered bullet lines.
    Set tLines = 0
    For j = 1:1:$Length(tDigest, $Char(10)) {
        If $Extract($Piece(tDigest, $Char(10), j), 1, 2) = "- " Set tLines = tLines + 1
    }
    Do $$$AssertEquals(tLines, 10, "exactly MAXENTRIES=10 bullet lines rendered (got " _ tLines _ ")")
    Do $$$AssertTrue(tDigest [ "(2 more schema note(s) hidden", "hidden-rows marker names the 2 capped notes")
    Do $$$AssertTrue(tDigest [ "get_schema_notes", "marker points the LLM at get_schema_notes")
    Quit
}

/// <p>AC-5 — MAXCHARS=2000 row-granular char cap: long-subject fixtures
/// (~250-char subjects → ~450-char lines) bind the char cap before the
/// entry cap; the digest stays under MAXCHARS (plus the marker tail)
/// and the hidden-rows marker fires.</p>
Method TestCharCap()
{
    Set tLongTail = $Translate($Justify("", 230), " ", "x") ; 230-char filler
    For i = 1:1:8 {
        Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-char-" _ i _ "-" _ tLongTail, "char cap fixture body " _ i _ " " _ $Translate($Justify("", 150), " ", "y"), 0, ..#DIGNS), "fixture " _ i _ " seeded")
    }
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build(..#DIGNS)
    Do $$$AssertNotEquals(tDigest, "", "digest non-empty")

    ; Count rendered bullet lines — with ~450-char lines the 2000-char
    ; cap admits ~4 of the 8 fixtures, so strictly fewer than 8 render.
    Set tLines = 0
    For j = 1:1:$Length(tDigest, $Char(10)) {
        If $Extract($Piece(tDigest, $Char(10), j), 1, 2) = "- " Set tLines = tLines + 1
    }
    Do $$$AssertTrue(tLines < 8, "char cap excluded at least one fixture (rendered " _ tLines _ " of 8)")
    Do $$$AssertTrue(tLines > 0, "at least one fixture rendered")
    Do $$$AssertTrue(tDigest [ "more schema note(s) hidden", "hidden-rows marker fires under the char cap")

    ; The pre-marker digest body honors MAXCHARS (the marker tail is
    ; appended after the cap, mirroring the VocabularyDigest precedent).
    Set tPreMarker = $Piece(tDigest, $Char(10) _ "_(", 1)
    Do $$$AssertTrue($Length(tPreMarker) <= 2000, "rendered header+rows stay within MAXCHARS=2000 (got " _ $Length(tPreMarker) _ ")")
    Quit
}

/// <p>AC-5 — class-parameter lock: MAXENTRIES=10 / MAXCHARS=2000 per
/// the spec (mirrors the VocabularyDigest calibration-constant shape).</p>
Method TestClassParameterCalibration()
{
    Set tMaxEntries = ##class(%Dictionary.ParameterDefinition).%OpenId("SessionAgent.Knowledge.SchemaNoteDigest||MAXENTRIES")
    Do $$$AssertTrue($IsObject(tMaxEntries), "MAXENTRIES parameter defined")
    If $IsObject(tMaxEntries) Do $$$AssertEquals(+tMaxEntries.Default, 10, "MAXENTRIES = 10")
    Set tMaxChars = ##class(%Dictionary.ParameterDefinition).%OpenId("SessionAgent.Knowledge.SchemaNoteDigest||MAXCHARS")
    Do $$$AssertTrue($IsObject(tMaxChars), "MAXCHARS parameter defined")
    If $IsObject(tMaxChars) Do $$$AssertEquals(+tMaxChars.Default, 2000, "MAXCHARS = 2000")
    Quit
}

/// <p>AC-5 — note bodies render as single-line snippets: internal
/// newlines collapse to spaces and over-long bodies truncate with an
/// ellipsis marker, so one verbose note cannot wreck the digest's
/// line-per-note scannability.</p>
Method TestSnippetCollapsesAndTruncates()
{
    Set tBody = "line one" _ $Char(10) _ "line two" _ $Char(9) _ "tabbed " _ $Translate($Justify("", 200), " ", "z")
    Do $$$AssertStatusOK(##class(SessionAgent.Test.GetSchemaNotesTest).SeedNote("ztest-snip", tBody, 0, ..#DIGNS), "snippet fixture seeded")
    Set tDigest = ##class(SessionAgent.Knowledge.SchemaNoteDigest).Build(..#DIGNS)
    Do $$$AssertTrue(tDigest [ "line one line two", "newline collapsed to space inside the snippet")
    Do $$$AssertTrue(tDigest [ "...", "over-long body truncated with ellipsis")
    Quit
}

}
