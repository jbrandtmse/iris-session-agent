/// <p>Story 14.1 AC-4 / AC-6 — retrieval tests for the
/// <code>get_query_knowledge</code> tool
/// (<CLASS>SessionAgent.Tool.Inspection.GetQueryKnowledge</CLASS>):
/// topic-only, keyword-only, combined topic+keyword (e2e via
/// <CLASS>SessionAgent.Tool.Registry</CLASS> Dispatch — the in-story
/// Integration AC), max_results clamp, char-budget truncation, and the
/// validation-failure envelope.</p>
///
/// <p>Corpus seeding/content invariants live in the sister class
/// <CLASS>SessionAgent.Test.KnowledgeCorpusTest</CLASS> (split per
/// .claude/rules/object-script-testing.md §"Test Class Size").</p>
Class SessionAgent.Test.GetQueryKnowledgeTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Ensure the corpus is seeded (idempotent) before each test, and
/// defensively clear any leaked <code>ztest-</code> fixture rows.</p>
Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ##class(SessionAgent.Test.KnowledgeCorpusTest).DeleteFixtureRows()
    Quit ##class(SessionAgent.Knowledge.SeedContent).Seed()
}

/// <p>Clean up truncation fixtures even when an assertion failed
/// mid-test.</p>
Method OnAfterOneTest(testname As %String) As %Status
{
    Do ##class(SessionAgent.Test.KnowledgeCorpusTest).DeleteFixtureRows()
    Quit $$$OK
}

/// <p>CallerContext fixture — same shape as
/// InspectionSuiteVerificationTest.BuildCtx.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-4 — topic-only retrieval: <code>topic="methodology"</code>
/// returns both methodology articles with the success envelope shape.</p>
Method TestTopicOnlyRetrieval()
{
    Set tArgs = {"topic":"methodology", "max_results":5}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope on topic-only call")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 2, "methodology returns its 2 articles")
    Do $$$AssertEquals(tResult.structuredContent.%Get("truncated"), 0, "truncated = false")
    Set tSlugs = ""
    Set tIter = tResult.structuredContent.articles.%GetIterator()
    While tIter.%GetNext(.tKey, .tArt) {
        Set tSlugs = tSlugs _ "," _ tArt.%Get("slug")
        Do $$$AssertNotEquals(tArt.%Get("body"), "", "article '" _ tArt.%Get("slug") _ "' carries a body")
    }
    Do $$$AssertTrue(tSlugs [ ",diagnostic-checklist", "diagnostic-checklist returned")
    Do $$$AssertTrue(tSlugs [ ",methodology-loop", "methodology-loop returned")
    Quit
}

/// <p>AC-4 — keyword-only retrieval: free-text terms match Keywords +
/// Title case-insensitively and rank by term-hit count.</p>
Method TestKeywordOnlyRetrieval()
{
    Set tArgs = {"keywords":"ORPHAN delete"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope on keyword-only call")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertTrue(tResult.structuredContent.%Get("article_count") >= 1, "at least one keyword match")
    ; Both orphan articles carry 'orphan' + 'delete'/'cleanup' keywords.
    Set tSlugs = ""
    Set tIter = tResult.structuredContent.articles.%GetIterator()
    While tIter.%GetNext(.tKey, .tArt) {
        Set tSlugs = tSlugs _ "," _ tArt.%Get("slug")
    }
    Do $$$AssertTrue((tSlugs [ "orphan-detection-caveats") || (tSlugs [ "orphan-screen"), "an orphan article ranks in the results (got: " _ tSlugs _ ")")
    Quit
}

/// <p>AC-4 "Then" clause + in-story Integration AC — e2e dispatch via
/// <CLASS>SessionAgent.Tool.Registry</CLASS> with
/// <code>topic="dialect", keywords="TOP integer status"</code> returns
/// at least one article. The 2-term-hit integer-string-trap article
/// must rank first (relevance ordering).</p>
Method TestCombinedTopicKeywordDispatchE2E()
{
    Set tArgs = {"topic":"dialect", "keywords":"TOP integer status"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("get_query_knowledge", ..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Registry.Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertTrue(tResult.structuredContent.%Get("article_count") >= 1, "dispatch returns >= 1 article (AC-4 Then)")
    Do $$$AssertEquals(tResult.structuredContent.articles.%Get(0).%Get("slug"), "integer-string-trap", "integer-string-trap (2 term hits) ranks first")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "article(s)", "operator text reports the article count")
    Quit
}

/// <p>AC-4 — both <code>topic</code> and <code>keywords</code> empty
/// returns the canonical validation-failure envelope (FR37 shape), via
/// Registry dispatch.</p>
Method TestBothEmptyValidationFailure()
{
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("get_query_knowledge", ..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK (envelope-based error contract)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 when both topic and keywords are empty")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "at least one of topic or keywords", "operator text names the missing-arg contract")
    Quit
}

/// <p>Defensive — an out-of-enum topic returns the validation-failure
/// envelope naming the valid topics (never a SQL error).</p>
Method TestInvalidTopicValidationFailure()
{
    Set tArgs = {"topic":"bogus-topic"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on invalid topic")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "invalid topic", "operator text flags the invalid topic")
    Quit
}

/// <p>AC-4 — max_results clamps: default 3 when omitted; hard max 5
/// even when the caller asks for more (dialect has 14 articles).</p>
Method TestMaxResultsClamp()
{
    ; Omitted -> default 3.
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), {"topic":"dialect"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK (default max)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 3, "default max_results = 3")

    ; 99 -> clamped to hard max 5.
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), {"topic":"dialect", "max_results":99}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK (max_results=99)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 5, "max_results=99 clamps to hard max 5")
    Quit
}

/// <p>AC-4 / AC-6 — char-budget truncation: two fixture articles of
/// ~9000 body chars each match a unique keyword; the second would push
/// the total past the ~16 KB budget, so exactly one article returns
/// with <code>truncated=true</code>. Fixture rows are
/// <code>ztest-</code>-prefixed and cleaned up in OnAfterOneTest.</p>
Method TestCharBudgetTruncation()
{
    ; Build two 9000-char-body fixture articles sharing a unique keyword.
    Set tBigBody = $Translate($Justify("", 9000), " ", "x")
    For i = 1:1:2 {
        Set tRow = ##class(SessionAgent.Knowledge.Article).%New()
        Set tRow.Slug = "ztest-trunc-" _ i
        Set tRow.Topic = "cookbook"
        Set tRow.Title = "ztest truncation fixture " _ i
        Set tRow.Keywords = "ztesttruncmarker"
        Set tRow.Body = tBigBody
        Set tSaveSC = tRow.%Save()
        Do $$$AssertStatusOK(tSaveSC, "fixture article " _ i _ " saved")
    }

    Set tArgs = {"keywords":"ztesttruncmarker", "max_results":5}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 1, "second 9000-char article exceeds the 16000-char budget - only 1 returned")
    Do $$$AssertEquals(tResult.structuredContent.%Get("truncated"), 1, "truncated marker set when the budget cuts the result")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "truncated", "operator text flags the truncation")

    ; Cleanup happens in OnAfterOneTest; also delete inline so a
    ; same-process follow-on test never sees the fixtures.
    Do ##class(SessionAgent.Test.KnowledgeCorpusTest).DeleteFixtureRows()
    Quit
}

/// <p>QA gap coverage — ListTools manifest shape for the new tool (the
/// per-tool precedent: TestRegistryListToolsIncludes&lt;Tool&gt;):
/// <method>SessionAgent.Tool.Registry.ListTools</method> surfaces
/// <code>get_query_knowledge</code> with a non-empty priming Description
/// (consult BEFORE authoring SQL; names the topic taxonomy) and an
/// input_schema whose <code>topic.enum</code> carries exactly the 7
/// static corpus topics.</p>
Method TestRegistryListToolsIncludesGetQueryKnowledge()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools() returns object")
    Set tFound = 0
    Set tDesc = ""
    Set tSchema = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If tEntry.%Get("name") = "get_query_knowledge" {
            Set tFound = 1
            Set tDesc = tEntry.%Get("description")
            Set tSchema = tEntry.%Get("input_schema")
        }
    }
    Do $$$AssertEquals(tFound, 1, "registry surfaces 'get_query_knowledge'")
    Do $$$AssertTrue(tDesc '= "", "get_query_knowledge has non-empty Description in ListTools output")
    Do $$$AssertTrue(tDesc [ "BEFORE", "Description primes consult-BEFORE-authoring-SQL usage (AC-4)")
    Do $$$AssertTrue((tDesc [ "methodology") && (tDesc [ "cookbook"), "Description names the topic taxonomy ends (methodology ... cookbook)")
    Do $$$AssertTrue($IsObject(tSchema), "input_schema present in manifest entry")
    If '$IsObject(tSchema) Quit
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps), "input_schema carries properties")
    If '$IsObject(tProps) Quit
    Set tEnum = tProps.%Get("topic").%Get("enum")
    Do $$$AssertTrue($IsObject(tEnum), "topic property carries an enum")
    If $IsObject(tEnum) Do $$$AssertEquals(tEnum.%Size(), 7, "topic enum locks the 7-topic static taxonomy")
    Do $$$AssertTrue($IsObject(tProps.%Get("keywords")), "keywords property present in schema")
    Do $$$AssertTrue($IsObject(tProps.%Get("max_results")), "max_results property present in schema")
    Quit
}

/// <p>QA gap coverage — relevance ranking is deterministic for
/// multi-term scoring: 4 <code>ztest-</code> fixtures carry 3/2/1/1
/// term hits against a 3-term query; results must order strictly by
/// score descending, then slug ascending for the 1-hit tie pair.
/// Fixture-based so the assertion does not drift with corpus content
/// (the existing combined e2e test only pins position 0). Stable
/// ordering matters to the Story 14.5 golden questions.</p>
Method TestRelevanceRankingDeterministic()
{
    ; Fixtures: unique marker terms no corpus article carries.
    Do $$$AssertStatusOK(..SaveRankFixture("ztest-rank-a", "ztrkalpha, ztrkbeta, ztrkgamma"), "fixture ztest-rank-a saved")
    Do $$$AssertStatusOK(..SaveRankFixture("ztest-rank-b", "ztrkalpha, ztrkbeta"), "fixture ztest-rank-b saved")
    Do $$$AssertStatusOK(..SaveRankFixture("ztest-rank-c", "ztrkalpha"), "fixture ztest-rank-c saved")
    Do $$$AssertStatusOK(..SaveRankFixture("ztest-rank-d", "ztrkalpha"), "fixture ztest-rank-d saved")

    Set tArgs = {"keywords":"ztrkalpha ztrkbeta ztrkgamma", "max_results":5}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 4, "exactly the 4 scoring fixtures match (corpus articles score 0)")
    Set tArts = tResult.structuredContent.articles
    Do $$$AssertEquals(tArts.%Get(0).%Get("slug"), "ztest-rank-a", "3-term-hit fixture ranks first")
    Do $$$AssertEquals(tArts.%Get(1).%Get("slug"), "ztest-rank-b", "2-term-hit fixture ranks second")
    Do $$$AssertEquals(tArts.%Get(2).%Get("slug"), "ztest-rank-c", "1-hit tie breaks by slug ascending: c third")
    Do $$$AssertEquals(tArts.%Get(3).%Get("slug"), "ztest-rank-d", "1-hit tie breaks by slug ascending: d fourth")

    Do ##class(SessionAgent.Test.KnowledgeCorpusTest).DeleteFixtureRows()
    Quit
}

/// <p>Helper — save one short ranking fixture article (slug must be
/// <code>ztest-</code>-prefixed so DeleteFixtureRows reclaims it).
/// Titles stay free of the marker terms so only Keywords score.
/// Returns the <code>%Save</code> status so call sites can assert it
/// (project rule "Write Status Checking").</p>
ClassMethod SaveRankFixture(pSlug As %String, pKeywords As %String) As %Status
{
    Set tRow = ##class(SessionAgent.Knowledge.Article).%New()
    Set tRow.Slug = pSlug
    Set tRow.Topic = "cookbook"
    Set tRow.Title = "ranking fixture " _ pSlug
    Set tRow.Keywords = pKeywords
    Set tRow.Body = "short fixture body for " _ pSlug
    Quit tRow.%Save()
}

/// <p>QA gap coverage — keyword-input robustness. All keyword terms
/// bind via parameterized <code>?</code> placeholders, so quote
/// characters can never raise a SQL error; and the tool intentionally
/// does NOT escape <code>%</code> / <code>_</code> inside terms — they
/// pass through as LIKE wildcards (accepted-as-wildcard semantics,
/// locked here with a fixture: an <code>_</code> in the query term
/// matches a <code>-</code> in the stored keyword). Every shape below
/// must return a well-formed envelope, never a SQL error.</p>
Method TestKeywordSpecialCharactersRobust()
{
    ; --- Quote characters (single + double) never error ---
    Set tArgs = {}
    Do tArgs.%Set("keywords", "o'brien " _ $Char(34) _ "quoted" _ $Char(34))
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for quote-bearing keywords")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "quote characters in keywords never raise an error envelope (parameterized binding)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "quote-bearing keywords return a success-shape envelope")

    ; --- Pure '%' term acts as match-all wildcard, stays bounded ---
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), {"keywords":"%"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for '%' keyword")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "'%' keyword never errors")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 3, "'%' matches everything but stays bounded by the default max_results of 3")

    ; --- '_' wildcard semantics locked with a fixture: query term
    ;     'ztrw_marker' (underscore) matches stored keyword
    ;     'ztrw-marker' (hyphen) ---
    Set tRow = ##class(SessionAgent.Knowledge.Article).%New()
    Set tRow.Slug = "ztest-wildcard-fixture"
    Set tRow.Topic = "cookbook"
    Set tRow.Title = "wildcard semantics fixture"
    Set tRow.Keywords = "ztrw-marker"
    Set tRow.Body = "short fixture body for the underscore-wildcard semantic lock"
    Do $$$AssertStatusOK(tRow.%Save(), "wildcard-semantics fixture saved")
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), {"keywords":"ztrw_marker"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for '_'-bearing keyword")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "'_' in a keyword never errors")
    Do $$$AssertEquals(tResult.structuredContent.%Get("article_count"), 1, "'_' acts as a single-char LIKE wildcard: 'ztrw_marker' matches stored 'ztrw-marker'")
    Do $$$AssertEquals(tResult.structuredContent.articles.%Get(0).%Get("slug"), "ztest-wildcard-fixture", "the wildcard-matched fixture is the article returned")

    ; --- Term cap: 12 whitespace-separated terms (cap is 8) never error ---
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), {"keywords":"t1 t2 t3 t4 t5 t6 t7 t8 t9 t10 t11 integer"}, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for a 12-term keyword string")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "term count beyond the 8-term cap never errors (excess terms dropped)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "over-cap keyword string returns a success-shape envelope")

    ; --- Review fix lock (Story 14.1 code review): tab/newline-separated
    ;     keywords are normalized to spaces before tokenizing, so the
    ;     terms still split and match (multiline LLM input shape) ---
    Set tArgs = {}
    Do tArgs.%Set("keywords", "integer" _ $Char(9) _ "status" _ $Char(10) _ "filter")
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetQueryKnowledge).Invoke(..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for tab/newline-separated keywords")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "tab/newline-separated keywords never error")
    Do $$$AssertTrue(tResult.structuredContent.%Get("article_count") >= 1, "tab/newline-separated terms split and match (integer-string-trap expected)")

    Do ##class(SessionAgent.Test.KnowledgeCorpusTest).DeleteFixtureRows()
    Quit
}

}
