/// <p>Story 14.4 AC-4 — retrieval tests for the
/// <code>get_schema_notes</code> tool
/// (<CLASS>SessionAgent.Tool.Inspection.GetSchemaNotes</CLASS>):
/// most-recently-verified-first ordering, <code>age_days</code>
/// staleness surfacing, parameterized fragment filter, max_results
/// clamp, the empty ok-envelope, and the ListTools manifest lock.</p>
///
/// <p>Save-side tests live in
/// <CLASS>SessionAgent.Test.SchemaNoteToolTest</CLASS> (split per
/// .claude/rules/object-script-testing.md §"Test Class Size").</p>
Class SessionAgent.Test.GetSchemaNotesTest Extends %UnitTest.TestCase
{

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

ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Quit ##class(SessionAgent.Test.SchemaNoteToolTest).BuildCtx()
}

/// <p>Helper — seed one fixture note, optionally backdating
/// <property>VerifiedAt</property> by <var>pAgeDays</var> via a direct
/// property write (Upsert always stamps "now"; the backdate makes
/// age_days/ordering assertions deterministic). <var>pNamespace</var>
/// defaults to <code>$NAMESPACE</code>; SchemaNoteDigestTest passes a
/// synthetic namespace so its absolute-count assertions are immune to
/// operator-saved notes in the live namespace (Story 14.4 review fix).
/// Returns the %Save status so call sites can assert it (project rule
/// "Write Status Checking").</p>
ClassMethod SeedNote(pSubject As %String, pBody As %String, pAgeDays As %Integer = 0, pNamespace As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        Set tNs = $Select(pNamespace '= "": pNamespace, 1: $NAMESPACE)
        Set tAction = ""
        Set tAudit = 0
        Set tSC = ##class(SessionAgent.Knowledge.SchemaNote).Upsert(tNs, pSubject, pBody, "session-inspection", .tAction, .tAudit)
        If $$$ISERR(tSC) Quit
        If pAgeDays > 0 {
            Set tRow = ##class(SessionAgent.Knowledge.SchemaNote).NsSubjectIdxOpen(tNs, pSubject, 4)
            If $IsObject(tRow) {
                Set tBackdatedH = $ZTimeStamp
                Set $Piece(tBackdatedH, ",", 1) = $Piece(tBackdatedH, ",", 1) - pAgeDays
                Set tRow.VerifiedAt = $ZDateTime(tBackdatedH, 3, 1)
                Set tSC = tRow.%Save()
            }
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>AC-4 — notes return most-recently-verified first and each entry
/// carries <code>age_days</code>: a fresh note reads 0, a 5-day-old
/// note reads 5, and the fresh note ranks first.</p>
Method TestRetrievalOrderingAndStaleness()
{
    Do $$$AssertStatusOK(..SeedNote("ztest-get-old", "old fact", 5), "5-day-old fixture seeded")
    Do $$$AssertStatusOK(..SeedNote("ztest-get-mid", "mid fact", 2), "2-day-old fixture seeded")
    Do $$$AssertStatusOK(..SeedNote("ztest-get-fresh", "fresh fact", 0), "fresh fixture seeded")

    Set tArgs = {"subject_fragment":"ztest-get-"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("get_schema_notes", ..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Registry.Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "no error envelope")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 3, "all 3 fixtures returned")

    Set tNotes = tResult.structuredContent.notes
    Do $$$AssertEquals(tNotes.%Get(0).%Get("subject"), "ztest-get-fresh", "fresh note ranks first (most recently verified)")
    Do $$$AssertEquals(tNotes.%Get(1).%Get("subject"), "ztest-get-mid", "2-day-old note ranks second")
    Do $$$AssertEquals(tNotes.%Get(2).%Get("subject"), "ztest-get-old", "5-day-old note ranks third")
    Do $$$AssertEquals(tNotes.%Get(0).%Get("age_days"), 0, "fresh note age_days = 0 (AC-4 Then)")
    Do $$$AssertEquals(tNotes.%Get(1).%Get("age_days"), 2, "2-day-old note age_days = 2")
    Do $$$AssertEquals(tNotes.%Get(2).%Get("age_days"), 5, "5-day-old note age_days = 5")
    Do $$$AssertNotEquals(tNotes.%Get(0).%Get("verified_at"), "", "verified_at populated (ISO-8601 Z)")
    Do $$$AssertTrue(tNotes.%Get(0).%Get("verified_at") [ "Z", "verified_at carries the Z suffix")
    Quit
}

/// <p>AC-4 — fragment filter is a case-insensitive parameterized
/// substring match; non-matching rows are excluded.</p>
Method TestFragmentFilter()
{
    Do $$$AssertStatusOK(..SeedNote("ztest-frag-orders", "order fact"), "orders fixture seeded")
    Do $$$AssertStatusOK(..SeedNote("ztest-frag-claims", "claim fact"), "claims fixture seeded")

    ; Case-insensitive match (stored lowercase, query uppercase).
    Set tArgs = {"subject_fragment":"FRAG-ORDERS"}
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(..BuildCtx(), tArgs, .tResult), "Invoke $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 1, "only the orders fixture matches the fragment")
    Do $$$AssertEquals(tResult.structuredContent.notes.%Get(0).%Get("subject"), "ztest-frag-orders", "fragment matched case-insensitively")
    Quit
}

/// <p>AC-4 — max_results clamps: default 10 when omitted (12 fixtures
/// seeded → 10 returned); explicit small value honored; the hard max 50
/// + floor are locked via source-introspection (seeding 51+ rows for an
/// empirical 50-cap probe would bloat the audit stream — Epic 12 AI-5
/// substring-grep binding).</p>
Method TestMaxResultsClamp()
{
    For i = 1:1:12 {
        Do $$$AssertStatusOK(..SeedNote("ztest-clamp-" _ $Translate($Justify(i, 2), " ", "0"), "clamp fixture " _ i), "clamp fixture " _ i _ " seeded")
    }

    ; Omitted -> default 10.
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(..BuildCtx(), {"subject_fragment":"ztest-clamp-"}, .tResult), "Invoke $$$OK (default)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 10, "default max_results = 10 (12 fixtures, 10 returned)")

    ; Explicit 3 -> 3.
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(..BuildCtx(), {"subject_fragment":"ztest-clamp-", "max_results":3}, .tResult), "Invoke $$$OK (3)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 3, "max_results=3 honored")

    ; Lower boundary: explicit 1 -> exactly 1 row (Story 14.4 review fix
    ; — boundary empirically exercised, not just source-locked).
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(..BuildCtx(), {"subject_fragment":"ztest-clamp-", "max_results":1}, .tResult), "Invoke $$$OK (1)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 1, "max_results=1 boundary honored")

    ; 99 -> clamped to 50 (source lock) and never errors (12 returned).
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(..BuildCtx(), {"subject_fragment":"ztest-clamp-", "max_results":99}, .tResult), "Invoke $$$OK (99)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "max_results=99 never errors")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 12, "over-cap request returns all 12 fixtures")

    ; Source-introspection lock for the 1..50 clamp arithmetic.
    Set tMethod = ##class(%Dictionary.MethodDefinition).%OpenId("SessionAgent.Tool.Inspection.GetSchemaNotes||Invoke")
    Do $$$AssertTrue($IsObject(tMethod), "GetSchemaNotes.Invoke is defined")
    If '$IsObject(tMethod) Quit
    Do tMethod.Implementation.Rewind()
    Set tBody = ""
    While 'tMethod.Implementation.AtEnd { Set tBody = tBody _ tMethod.Implementation.Read(32000) }
    Do $$$AssertTrue(tBody [ "If tMax < 1 Set tMax = 10", "low clamp -> default 10 present in source")
    Do $$$AssertTrue(tBody [ "If tMax > 50 Set tMax = 50", "hard max 50 clamp present in source")
    Do $$$AssertTrue(tBody [ "Set tMax = tMax \ 1", "fractional-floor line present in source (Story 14.4 review fix)")
    Quit
}

/// <p>AC-4 "Then" — empty result is the ok-envelope (no notes is not an
/// error), with an operator text pointing at save_schema_note.</p>
Method TestEmptyResultOkEnvelope()
{
    Set tArgs = {"subject_fragment":"ztest-no-such-note-fragment"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch("get_schema_notes", ..BuildCtx(), tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Dispatch returns $$$OK")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "empty result is NOT an error envelope (AC-4 Then)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy = 'ok'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("count"), 0, "count = 0")
    Do $$$AssertTrue(tResult.content.%Get(0).%Get("text") [ "No schema notes", "operator text reads as the friendly empty state")
    Quit
}

/// <p>Trust-boundary guard — empty CallerContext.Namespace returns the
/// error envelope (namespace is never an LLM argument).</p>
Method TestMissingNamespaceReturnsError()
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = ""
    Set tResult = ""
    Do $$$AssertStatusOK(##class(SessionAgent.Tool.Inspection.GetSchemaNotes).Invoke(tCtx, {}, .tResult), "Invoke $$$OK (empty namespace)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on empty CallerContext.Namespace")
    Quit
}

/// <p>ListTools manifest lock (TestRegistryListToolsIncludes*
/// precedent): the registry surfaces <code>get_schema_notes</code> with
/// a Description that primes the age_days staleness semantics, and an
/// all-optional input_schema (subject_fragment + max_results, no
/// namespace property).</p>
Method TestRegistryListToolsIncludesGetSchemaNotes()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Set tFound = 0
    Set tDesc = ""
    Set tSchema = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If tEntry.%Get("name") = "get_schema_notes" {
            Set tFound = 1
            Set tDesc = tEntry.%Get("description")
            Set tSchema = tEntry.%Get("input_schema")
        }
    }
    Do $$$AssertEquals(tFound, 1, "registry surfaces 'get_schema_notes'")
    Do $$$AssertTrue(tDesc '= "", "get_schema_notes has non-empty Description")
    Do $$$AssertTrue(tDesc [ "age_days", "Description primes the age_days staleness contract (FR63)")
    Do $$$AssertTrue($IsObject(tSchema), "input_schema present")
    If '$IsObject(tSchema) Quit
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps.%Get("subject_fragment")), "subject_fragment property present")
    Do $$$AssertTrue($IsObject(tProps.%Get("max_results")), "max_results property present")
    Do $$$AssertTrue('$IsObject(tProps.%Get("namespace")), "NO namespace property (CallerContext-only, NFR-S6)")
    Set tRequired = tSchema.%Get("required")
    If $IsObject(tRequired) Do $$$AssertEquals(tRequired.%Size(), 0, "all properties optional")
    Quit
}

}
