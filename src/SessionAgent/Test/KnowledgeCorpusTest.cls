/// <p>Story 14.1 AC-2 / AC-3 / AC-6 — knowledge-corpus seeding tests:
/// idempotent <method>Seed</method> + exact count lock, every-topic
/// representation, the ASCII-only body invariant (Rule 12 mojibake
/// precedent), the unique-Slug upsert contract, and the
/// <code>diagnostic-checklist</code> SQLCODE-hint-shape contract that
/// Story 14.3's error-envelope hint map consumes (locked: body carries
/// <code>SQLCODE &lt;n&gt; / symptom -&gt; fix</code> lines including
/// -29, -37, -400).</p>
///
/// <p>Tool-retrieval behavior is covered by the sister class
/// <CLASS>SessionAgent.Test.GetQueryKnowledgeTest</CLASS> (split per
/// .claude/rules/object-script-testing.md §"Test Class Size").</p>
Class SessionAgent.Test.KnowledgeCorpusTest Extends %UnitTest.TestCase
{

/// <p>The exact article count shipped by
/// <CLASS>SessionAgent.Knowledge.SeedContent</CLASS> — 2 methodology +
/// 14 dialect + 8 message-model + 6 performance + 2 discovery +
/// 3 reference + 12 cookbook. AC-2 locks this count (&gt;= 33 floor);
/// any story growing/shrinking the corpus must update this constant.</p>
Parameter EXPECTEDARTICLECOUNT As %Integer = 47;

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Defensive cleanup — remove any <code>ztest-</code> fixture rows a
/// crashed sibling test may have leaked, so the exact count lock below
/// never fails on unrelated debris.</p>
Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ..DeleteFixtureRows()
    Quit $$$OK
}

/// <p>Delete all <code>ztest-</code>-prefixed fixture articles.</p>
ClassMethod DeleteFixtureRows()
{
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("DELETE FROM SessionAgent_Knowledge.Article WHERE Slug %STARTSWITH ?")
        If $$$ISOK(tSC) Do tStmt.%Execute("ztest-")
    }
    Catch ex {
    }
}

/// <p>Count all non-fixture articles.</p>
ClassMethod CountArticles() As %Integer
{
    Set tCount = -1
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Knowledge.Article WHERE NOT (Slug %STARTSWITH ?)")
    If $$$ISERR(tSC) Quit tCount
    Set tRS = tStmt.%Execute("ztest-")
    If tRS.%Next() Set tCount = tRS.%Get("Cnt")
    Quit tCount
}

/// <p>AC-3 — Seed() is idempotent: running it twice yields the same
/// exact row count, and that count is locked at
/// <parameter>EXPECTEDARTICLECOUNT</parameter> (AC-2: &gt;= 33).</p>
Method TestSeedIdempotencyAndCountLock()
{
    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "first Seed() returns $$$OK")
    Set tFirst = ..CountArticles()
    Do $$$AssertEquals(tFirst, ..#EXPECTEDARTICLECOUNT, "post-seed article count locked at " _ ..#EXPECTEDARTICLECOUNT)
    Do $$$AssertTrue(tFirst >= 33, "article count >= 33 (AC-2 floor)")

    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "second Seed() returns $$$OK")
    Set tSecond = ..CountArticles()
    Do $$$AssertEquals(tSecond, tFirst, "re-seed does not change the count (idempotent upsert by Slug)")
    Quit
}

/// <p>AC-2 — every Appendix-C topic is represented by at least one
/// article, and only the 7 corpus topics appear.</p>
Method TestEveryTopicRepresented()
{
    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "Seed() returns $$$OK")
    Kill tCounts
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT %EXACT(Topic) AS Topic, COUNT(*) AS Cnt FROM SessionAgent_Knowledge.Article WHERE NOT (Slug %STARTSWITH ?) GROUP BY %EXACT(Topic)")
    Do $$$AssertStatusOK(tPrepSC, "topic-count prepare OK")
    Set tRS = tStmt.%Execute("ztest-")
    Set tTopicTotal = 0
    While tRS.%Next() {
        Set tCounts(tRS.%Get("Topic")) = tRS.%Get("Cnt")
        Set tTopicTotal = tTopicTotal + 1
    }
    Set tExpected = $ListBuild("methodology", "dialect", "message-model", "performance", "discovery", "reference", "cookbook")
    Set tPtr = 0
    While $ListNext(tExpected, tPtr, tTopic) {
        Do $$$AssertTrue(+$Get(tCounts(tTopic)) >= 1, "topic '" _ tTopic _ "' represented by >= 1 article (got " _ +$Get(tCounts(tTopic)) _ ")")
    }
    Do $$$AssertEquals(tTopicTotal, 7, "exactly the 7 corpus topics appear (got " _ tTopicTotal _ ")")
    Quit
}

/// <p>AC-2 — ASCII-only invariant: no seeded article carries a character
/// above codepoint 127 in <b>any</b> envelope-rendered text field —
/// Body per the AC, plus Slug / Title / Keywords (review extension:
/// Title is returned verbatim in every tool envelope, so a Unicode
/// arrow/dash there is the same Rule 12 mojibake shape as a body; Story
/// 3.7 welcome-message precedent). Greps every character.</p>
Method TestBodiesAsciiOnly()
{
    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "Seed() returns $$$OK")
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tPrepSC = tStmt.%Prepare("SELECT %EXACT(Slug) AS Slug, %EXACT(Title) AS Title, %EXACT(Keywords) AS Keywords, Body FROM SessionAgent_Knowledge.Article WHERE NOT (Slug %STARTSWITH ?)")
    Do $$$AssertStatusOK(tPrepSC, "body-scan prepare OK")
    Set tRS = tStmt.%Execute("ztest-")
    Set tRows = 0
    Set tViolations = ""
    While tRS.%Next() {
        Set tRows = tRows + 1
        Set tSlug = tRS.%Get("Slug")
        Set tFields = $ListBuild("Slug", "Title", "Keywords", "Body")
        Set tPtr = 0
        While $ListNext(tFields, tPtr, tField) {
            Set tText = tRS.%Get(tField)
            For j = 1:1:$Length(tText) {
                If $Ascii($Extract(tText, j)) > 127 {
                    Set tViolations = tViolations _ tSlug _ "." _ tField _ "@" _ j _ "(" _ $Ascii($Extract(tText, j)) _ ") "
                    Quit
                }
            }
        }
    }
    Do $$$AssertTrue(tRows >= 33, "scanned >= 33 articles (got " _ tRows _ ")")
    Do $$$AssertEquals(tViolations, "", "no Slug/Title/Keywords/Body contains bytes > 127 (violations: " _ tViolations _ ")")
    Quit
}

/// <p>AC-6 — Story 14.3 consumer contract: the
/// <code>diagnostic-checklist</code> article body carries
/// <code>SQLCODE &lt;n&gt; / symptom -&gt; fix</code> hint lines for at
/// least -29, -37, and -400 (plus the shape marker on each).</p>
Method TestDiagnosticChecklistSqlcodeHintShape()
{
    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "Seed() returns $$$OK")
    Set tRow = ##class(SessionAgent.Knowledge.Article).SlugIdxOpen("diagnostic-checklist", , .tOpenSC)
    Do $$$AssertTrue($IsObject(tRow), "diagnostic-checklist article exists")
    If '$IsObject(tRow) Quit
    Do $$$AssertEquals(tRow.Topic, "methodology", "diagnostic-checklist topic = methodology")
    Set tBody = tRow.Body
    Set tCodes = $ListBuild("-29", "-37", "-400")
    Set tPtr = 0
    While $ListNext(tCodes, tPtr, tCode) {
        Set tMarker = "SQLCODE " _ tCode _ " /"
        Do $$$AssertTrue(tBody [ tMarker, "body carries the '" _ tMarker _ "' hint line (14.3 contract)")
        ; The hint line shape is 'SQLCODE <n> / symptom -> fix' — confirm
        ; the '->' connector appears after the marker on the same line.
        Set tIdx = $Find(tBody, tMarker)
        Set tLine = $Piece($Extract(tBody, tIdx, *), $Char(10), 1)
        Do $$$AssertTrue(tLine [ "->", "'" _ tMarker _ "' line carries the '-> fix' connector")
    }
    Quit
}

/// <p>AC-3 — Installer wiring regression lock (QA gap coverage): the
/// compiled <method>SessionAgent.Installer.Install</method> implementation
/// invokes <code>##class(SessionAgent.Knowledge.SeedContent).Seed()</code>
/// and logs the post-seed count via
/// <code>LogPostSeedKnowledgeCount</code> (NFR-R5 precedent). A future
/// Installer refactor that drops either line would ship installs with an
/// empty corpus — breaking the Story 14.3 / 14.5 consumer contract — and
/// this test fails loudly instead. Source-definition introspection via
/// <CLASS>%Dictionary.MethodDefinition</CLASS> (the UDL source, not the
/// compiled method — cheap; a live re-Install is intentionally NOT run
/// here; per the substring-grep pattern this guards against deletion,
/// not against a saved-but-uncompiled or commented-out edit).</p>
Method TestInstallerWiresKnowledgeSeed()
{
    Set tMeth = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Installer||Install")
    Do $$$AssertTrue($IsObject(tMeth), "SessionAgent.Installer:Install method definition opens")
    If '$IsObject(tMeth) Quit
    Set tImpl = ""
    Do tMeth.Implementation.Rewind()
    While 'tMeth.Implementation.AtEnd {
        Set tImpl = tImpl _ tMeth.Implementation.Read(32000)
    }
    Do $$$AssertTrue(tImpl [ "##class(SessionAgent.Knowledge.SeedContent).Seed()", "Install() invokes SessionAgent.Knowledge.SeedContent.Seed()")
    Do $$$AssertTrue(tImpl [ "LogPostSeedKnowledgeCount", "Install() logs the post-seed knowledge article count (NFR-R5)")
    ; The count-log helper itself must exist on the Installer.
    Do $$$AssertTrue(##class(%Dictionary.MethodDefinition).%ExistsId("SessionAgent.Installer||LogPostSeedKnowledgeCount"), "LogPostSeedKnowledgeCount helper method exists on Installer")
    Quit
}

/// <p>AC-1 / AC-3 — the unique Slug index enforces one-row-per-slug:
/// saving a second row with an existing slug fails, which is the
/// structural guarantee behind the idempotent upsert.</p>
Method TestSlugUniqueIndexEnforced()
{
    Set tSC = ##class(SessionAgent.Knowledge.SeedContent).Seed()
    Do $$$AssertStatusOK(tSC, "Seed() returns $$$OK")
    Set tDup = ##class(SessionAgent.Knowledge.Article).%New()
    Set tDup.Slug = "top-not-limit"
    Set tDup.Topic = "dialect"
    Set tDup.Title = "duplicate"
    Set tDup.Keywords = "dup"
    Set tDup.Body = "duplicate body"
    Set tSaveSC = tDup.%Save()
    Do $$$AssertStatusNotOK(tSaveSC, "%Save of a duplicate Slug fails (unique SlugIdx)")
    Quit
}

}
