/// <p>Story 4.7 AC-4 + AC-5 — Comprehensive read-only suite verification.
/// Two thrust areas:</p>
///
/// <p><b>AC-4 — L1 read-only invariant (NFR-S1 Layer 1).</b>
/// <method>TestAllToolsDeclareReadOnlyMutatesState</method> iterates every
/// concrete subclass of <CLASS>SessionAgent.Tool.Base</CLASS> in the
/// namespace and asserts <parameter>MutatesState</parameter>=0. Any new
/// tool that omits the parameter or sets it to 1 fails CI immediately —
/// the structural enforcement that makes the read-only catalog promise
/// auditable.</p>
///
/// <p><b>AC-5 — Comprehensive all-tool exercise.</b>
/// <method>TestAllToolsExerciseAgainstFixture</method> dispatches
/// EVERY registered tool with a representative input chosen so
/// the dispatch returns a non-error envelope where realistic, or the
/// well-defined "missing/not_found" envelope where the input is
/// deliberately empty. Validates the no-throws contract (no exception
/// escapes <method>Invoke</method>) and the MCP envelope shape
/// (<code>content</code> array + <code>structuredContent</code> object on
/// success; <code>isError:1</code> on validation failure). Closes Story
/// 4.4 R-1 (live-test gap — every tool now structurally exercised, no
/// LLM-discretion gap).</p>
///
/// <p><b>Validation-input verification.</b>
/// <method>TestAllToolsValidationFailureReturnsEnvelope</method>
/// dispatches each tool with empty <code>{}</code> args (or syntactically
/// minimal input that fails the tool's required-field check) and asserts
/// the result is the standard <code>{isError:1, content:[...]}</code>
/// envelope — NEVER an exception, NEVER an empty pResult. This is the
/// FR37-conformance gate.</p>
///
/// <p><b>No fixture seeding.</b> This test class does NOT seed Ens
/// fixtures. The all-tool exercise reuses existing tool semantics —
/// <code>session_summary</code>'s "session_exists=false" envelope for an
/// unknown session, <code>get_message_body</code>'s "header_not_found"
/// envelope for an unknown id, etc. Per-tool happy-path assertions are
/// covered by the dedicated test classes (InspectionToolTest, Story41,
/// FindRelatedSessions, FindSessionsByBody, BusinessProcessIntrospection,
/// GetMessageBody, GetMessageDetail).</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.7</a> AC-4 and AC-5 — AC source.</li>
/// <li><a href="../Tool/Base.cls">SessionAgent.Tool.Base.cls</a> —
/// <parameter>MutatesState</parameter> contract.</li>
/// <li><a href="../Tool/Registry.cls">SessionAgent.Tool.Registry.cls</a> —
/// L2 enforcement (FR36) reads the same parameter at dispatch time.</li>
/// <li><a href="InspectionToolTest.cls">InspectionToolTest.cls</a> — sister
/// suite at the 500-line cap; new asserts moved here per
/// .claude/rules/object-script-testing.md §"Test Class Size".</li>
/// </ul>
Class SessionAgent.Test.InspectionSuiteVerificationTest Extends %UnitTest.TestCase
{

/// <p>Expected production tool count surfaced by
/// <method>SessionAgent.Tool.Registry.ListTools</method>. Future stories
/// incrementing the catalog must update this constant + the named-tool
/// list in <method>TestRegistryListsExpectedToolCount</method> + the
/// representative-args table in <method>GetRepresentativeArgs</method>.</p>
/// <p>As of Story 14.0 this is <b>28</b> — 17 inspection tools
/// (Stories 2.11 + 4.x + 13.4: <code>get_queue_state</code>; Story 13.2:
/// <code>get_rule_source</code>; Story 13.1:
/// <code>get_class_source</code>; Story 13.3:
/// <code>get_production_config_item</code>) + 11
/// search tools (Story 8.3: <code>search_by_time</code>,
/// <code>search_by_status</code>, <code>search_by_source</code>,
/// <code>search_by_target</code>, <code>search_by_message_class</code>,
/// <code>search_by_session</code>; Story 8.4:
/// <code>search_by_super_session</code>; Story 8.5:
/// <code>search_by_body_field</code>; Story 8.6:
/// <code>inspect_body_candidates</code>; Story 8.7:
/// <code>vocab_lookup</code>; Story 13.5:
/// <code>find_sessions_using_class</code>).</p>
/// <p><b>Story 14.0 correction (Epic 13 retro AI-3 incident):</b> Story
/// 13.5 shipped <code>find_sessions_using_class</code> without bumping
/// this constant 27→28 or extending the named-tool list — the three
/// count-equality assertions in this class failed against the live
/// 28-tool registry until Story 14.0 reconciled them.</p>
Parameter EXPECTEDTOOLCOUNT As %Integer = 28;

/// <p>Synthetic session id well outside any realistic Ens production
/// range. Used by every "not found" / "validation error" envelope assertion
/// so the suite never accidentally collides with fixture data seeded by
/// other test classes.</p>
Parameter SYNTHETICSESSIONID As %Integer = 9799911;

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Build a CallerContext with sane defaults — same shape used by
/// InspectionToolTest. Tools should not crash on partially-populated
/// contexts; they only read PortalUser / Namespace / IrisSessionId
/// fields.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = ..#SYNTHETICSESSIONID
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>Return the array of concrete subclass names of
/// <CLASS>SessionAgent.Tool.Base</CLASS>, EXCLUDING the
/// <code>SessionAgent.Test.*</code> stub fixtures. Same filter
/// <method>SessionAgent.Tool.Registry.ListTools</method> uses (Story 3.0
/// carry-forward).</p>
ClassMethod GetConcreteToolClasses() As %DynamicArray
{
    Set tList = []
    Set tStmt = ##class(%SQL.Statement).%New()
    ; Story 8.3 — also discover concrete search tools that extend the
    ; Tool.Search.Base intermediate abstract. Keep this filter in
    ; lockstep with SessionAgent.Tool.Registry's discovery filter.
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE (%EXACT(Super) = 'SessionAgent.Tool.Base' OR %EXACT(Super) = 'SessionAgent.Tool.Search.Base') AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    If $$$ISERR(tSC) Quit tList
    Set tRs = tStmt.%Execute()
    While tRs.%Next() {
        Do tList.%Push(tRs.%Get("ClassName"))
    }
    Quit tList
}

/// <p>Return a representative input fixture for a given tool name,
/// chosen to drive the tool down a clean code path. Prefers
/// "not-found"-shape inputs so the test does not require Ens fixtures.
/// Returns an empty <code>{}</code> object when the tool has no required
/// fields.</p>
ClassMethod GetRepresentativeArgs(pToolName As %String) As %DynamicObject
{
    Set tArgs = {}
    If pToolName = "session_summary" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "session_timeline" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "message_headers" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "event_log" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "rule_log" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "get_message_body" {
        Do tArgs.%Set("message_id", "9799911999")
    } ElseIf pToolName = "get_message_detail" {
        Do tArgs.%Set("message_id", "9799911999")
    } ElseIf pToolName = "get_business_process_source" {
        Do tArgs.%Set("bp_class_name", "Ens.BusinessProcess")
    } ElseIf pToolName = "get_business_process_instance" {
        Do tArgs.%Set("bp_class_name", "Ens.BusinessProcess")
    } ElseIf pToolName = "list_business_process_methods" {
        Do tArgs.%Set("bp_class_name", "Ens.BusinessProcess")
    } ElseIf pToolName = "find_related_sessions" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "find_sessions_by_body" {
        Do tArgs.%Set("body_class", "Ens.MessageBody")
        Do tArgs.%Set("field", "ID")
        Do tArgs.%Set("value", "9799911999")
    } ElseIf pToolName = "explain_error" {
        Do tArgs.%Set("status_or_error_string", "<UNDEFINED>")
    } ElseIf pToolName = "search_by_time" {
        ; Story 8.3 — empty time-window inputs trigger the helper's
        ; default 24h mode; small limit avoids large result sets.
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_status" {
        ; Story 8.3 — at least one valid status enum value satisfies the
        ; required-field contract.
        Set tStatusArr = ##class(%DynamicArray).%New()
        Do tStatusArr.%Push("Error")
        Do tArgs.%Set("status_in", tStatusArr)
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_source" {
        ; Story 8.3 — synthetic SourceConfigName that won't match
        ; production rows (returns empty result set, avoiding fixture
        ; coupling).
        Do tArgs.%Set("source_config_name", "SyntheticTestSrc_NoMatch")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_target" {
        Do tArgs.%Set("target_config_name", "SyntheticTestTgt_NoMatch")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_message_class" {
        Do tArgs.%Set("message_body_class_name", "Synthetic.NoMatch.Msg")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_session" {
        Do tArgs.%Set("session_id", ..#SYNTHETICSESSIONID, "number")
    } ElseIf pToolName = "search_by_super_session" {
        ; Story 8.4 — synthetic super-session key won't match production
        ; rows (returns empty result set, avoiding fixture coupling).
        Do tArgs.%Set("super_session_key", "Synthetic.NoMatch.SuperSession")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "search_by_body_field" {
        ; Story 8.5 — synthetic SearchTable class triggers AC-3
        ; "search_table_not_installed" envelope (isError:1; structured
        ; error path exercised without depending on installed
        ; HealthShare SearchTables).
        Do tArgs.%Set("search_table_class", "Synthetic.NoMatch.SearchTable")
        Do tArgs.%Set("prop_name", "MRN")
        Do tArgs.%Set("prop_value", "synthetic-no-match-12345")
        Do tArgs.%Set("limit", 5, "number")
    } ElseIf pToolName = "inspect_body_candidates" {
        ; Story 8.6 — synthetic prefilter_value (sentinel value certain
        ; not to match production rows). Returns 0 candidates inspected,
        ; 0 matches, success envelope. No fixture seeding required.
        Do tArgs.%Set("pattern", "synthetic-no-match-pattern-86")
        Do tArgs.%Set("prefilter_indexed_column", "Status")
        Do tArgs.%Set("prefilter_value", "Synthetic.NoMatch.Status")
    } ElseIf pToolName = "vocab_lookup" {
        ; Story 8.7 — list mode with a synthetic PortalUser scope is
        ; the simplest representative input (uses BuildCtx's "tester"
        ; PortalUser; returns count=0 with empty vocabulary array; no
        ; UserVocabulary fixture seeding required).
        Do tArgs.%Set("mode", "list")
    } ElseIf pToolName = "get_queue_state" {
        ; Story 13.4 — synthetic queue name that does not exist; absent
        ; queue is not an error (returns zero-state, no isError). No
        ; fixture seeding required.
        Do tArgs.%Set("config_item_name", "Synthetic.NoMatch.Queue134")
    } ElseIf pToolName = "get_rule_source" {
        ; Story 13.2 — use the Fixture.SampleRule class compiled by
        ; GetRuleSourceTest.OnBeforeAllTests(). On a fresh namespace
        ; this may not yet be compiled, so the tool returns class_not_found
        ; (not an error envelope). The suite verification test only
        ; requires the Dispatch envelope contract (content array present,
        ; $$$OK return); class_not_found is a valid success-shape envelope.
        Do tArgs.%Set("rule_class", "SessionAgent.Test.Fixture.SampleRule")
    } ElseIf pToolName = "get_class_source" {
        ; Story 13.1 — use SessionAgent.Tool.Base which is always compiled.
        ; Returns a success "ok" envelope with full class source.
        Do tArgs.%Set("class_name", "SessionAgent.Tool.Base")
    } ElseIf pToolName = "get_production_config_item" {
        ; Story 13.3 — use the live sample production with a known item.
        ; Returns an "ok" envelope. Both required args needed.
        Do tArgs.%Set("production_name", "SessionAgent.Sample.Production")
        Do tArgs.%Set("config_item_name", "SessionAgent.Sample.BP.OrderRouter")
    } ElseIf pToolName = "find_sessions_using_class" {
        ; Story 13.5 tool (representative args added in Story 14.0 —
        ; Epic 13 retro AI-3 reconciliation). The sample production's
        ; OrderRouter config name matches SourceConfigName/TargetConfigName
        ; rows when scenario data exists; with no scenario data the tool
        ; returns a success no_matches-shape envelope. Either way the
        ; Dispatch envelope contract holds.
        Do tArgs.%Set("class_name", "SessionAgent.Sample.BP.OrderRouter")
        Do tArgs.%Set("limit", 5, "number")
    }
    Quit tArgs
}

/// <p>AC-4 — L1 read-only invariant. Iterate every concrete subclass of
/// <CLASS>SessionAgent.Tool.Base</CLASS> in the namespace and assert
/// each declares <parameter>MutatesState</parameter>=0. The test fails
/// loudly if a future story adds a write-capable tool without explicitly
/// updating the v1 read-only contract — the whole point of the L1
/// declarative invariant.</p>
Method TestAllToolsDeclareReadOnlyMutatesState()
{
    Set tClasses = ..GetConcreteToolClasses()
    Do $$$AssertTrue(tClasses.%Size() > 0, "at least one concrete tool class found")
    Set tIter = tClasses.%GetIterator()
    Set tCount = 0
    While tIter.%GetNext(.tKey, .tClassName) {
        Set tParam = ##class(%Dictionary.ParameterDefinition).%OpenId(tClassName _ "||MutatesState")
        Do $$$AssertTrue($IsObject(tParam), tClassName _ " has MutatesState parameter row (Tool.Base contract)")
        Do $$$AssertEquals(+tParam.Default, 0, tClassName _ " MutatesState=0 (read-only invariant)")
        Set tCount = tCount + 1
    }
    Do $$$AssertTrue(tCount >= ..#EXPECTEDTOOLCOUNT, "expected >= " _ ..#EXPECTEDTOOLCOUNT _ " tools, got " _ tCount)
    Quit
}

/// <p>AC-5 — comprehensive all-tool exercise. Iterate every registered
/// tool, dispatch each with a representative fixture input via the
/// trust-boundary <method>SessionAgent.Tool.Registry.Dispatch</method>,
/// and validate per dispatch:</p>
/// <ul>
/// <li>The %Status return is $$$OK (envelope-based error contract).</li>
/// <li>pResult is a populated %DynamicObject with a <code>content</code>
/// array.</li>
/// <li>If the result is a success envelope, <code>structuredContent</code>
/// is also a populated %DynamicObject.</li>
/// <li>NO exception escapes Dispatch (would fail the test runner instead
/// of the assertion).</li>
/// </ul>
/// <p>Closes Story 4.4 R-1: every tool structurally exercised, no
/// LLM-discretion gap.</p>
Method TestAllToolsExerciseAgainstFixture()
{
    Set tCtx = ..BuildCtx()
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertEquals(tList.%Size(), ..#EXPECTEDTOOLCOUNT, "registry surfaces exactly " _ ..#EXPECTEDTOOLCOUNT _ " tools")

    Set tIter = tList.%GetIterator()
    Set tDispatchCount = 0
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tToolName = tEntry.%Get("name")
        Set tArgs = ..GetRepresentativeArgs(tToolName)
        Set tResult = ""
        Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch(tToolName, tCtx, tArgs, .tResult)
        Do $$$AssertStatusOK(tSC, tToolName _ ": Dispatch returns $$$OK")
        Do $$$AssertTrue($IsObject(tResult), tToolName _ ": pResult populated as %DynamicObject")
        Do $$$AssertTrue($IsObject(tResult.content), tToolName _ ": pResult.content present")
        Do $$$AssertTrue(tResult.content.%Size() >= 1, tToolName _ ": pResult.content has at least one entry")
        ; If success envelope, structuredContent must be present.
        If +tResult.%Get("isError") '= 1 {
            Do $$$AssertTrue($IsObject(tResult.structuredContent), tToolName _ ": success envelope has structuredContent")
        }
        Set tDispatchCount = tDispatchCount + 1
    }
    Do $$$AssertEquals(tDispatchCount, ..#EXPECTEDTOOLCOUNT, "dispatched all " _ ..#EXPECTEDTOOLCOUNT _ " tools")
    Quit
}

/// <p>AC-5 (companion) — every tool's empty-args path returns either a
/// success or error envelope (NEVER throws). Tools with at least one
/// required field MUST emit <code>isError=1</code>; tools without
/// required fields (Story 8.3 added <code>search_by_time</code> — all
/// inputs optional, default 24h window) MAY return a success envelope
/// on empty args. Closes the FR37 conformance gate.</p>
Method TestAllToolsValidationFailureReturnsEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Set tIter = tList.%GetIterator()
    Set tIsErrorCount = 0
    Set tDispatchCount = 0
    ; Tools whose entire input schema is optional — empty args returns
    ; a success envelope, not an isError envelope. Story 8.3 adds
    ; search_by_time (default 24h window when no bounds supplied).
    Set tNoRequiredArgs = $ListBuild("search_by_time")
    Set tNoRequiredCount = 0
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tToolName = tEntry.%Get("name")
        Set tEmptyArgs = {}
        Set tResult = ""
        Set tSC = ##class(SessionAgent.Tool.Registry).Dispatch(tToolName, tCtx, tEmptyArgs, .tResult)
        Do $$$AssertStatusOK(tSC, tToolName _ ": Dispatch with empty args returns $$$OK (envelope-based)")
        Do $$$AssertTrue($IsObject(tResult), tToolName _ ": pResult populated even on empty args")
        Do $$$AssertTrue($IsObject(tResult.content), tToolName _ ": pResult.content present even on empty args")
        Set tDispatchCount = tDispatchCount + 1
        If $ListFind(tNoRequiredArgs, tToolName) > 0 {
            Set tNoRequiredCount = tNoRequiredCount + 1
            ; Tools with no required args MUST return success envelope
            ; on empty args (proves the optional-only schema honors empty
            ; input as the default-mode trigger).
            Do $$$AssertEquals(+tResult.%Get("isError"), 0, tToolName _ ": no required args → empty args returns success envelope")
        } Else {
            ; All other tools have at least one required arg; they MUST emit isError.
            If +tResult.%Get("isError") = 1 {
                Set tIsErrorCount = tIsErrorCount + 1
            }
        }
    }
    Do $$$AssertEquals(tDispatchCount, ..#EXPECTEDTOOLCOUNT, "all " _ ..#EXPECTEDTOOLCOUNT _ " tools dispatched on empty args")
    Do $$$AssertEquals(tIsErrorCount, ..#EXPECTEDTOOLCOUNT - tNoRequiredCount, "(" _ (..#EXPECTEDTOOLCOUNT - tNoRequiredCount) _ ") tools with required args returned isError=1 on empty args (FR37)")
    Quit
}

/// <p>AC-5 — registry surfaces exactly the expected named tools. Catches
/// off-by-one drift if a future story accidentally adds (or doesn't add)
/// a tool.</p>
Method TestRegistryListsExpectedToolCount()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertEquals(tList.%Size(), ..#EXPECTEDTOOLCOUNT, "exactly " _ ..#EXPECTEDTOOLCOUNT _ " tools registered")

    ; Verify every expected name is present (order-independent).
    Set tExpected = $ListBuild("session_summary", "session_timeline", "message_headers", "event_log", "rule_log", "get_message_body", "get_message_detail", "get_business_process_source", "get_business_process_instance", "list_business_process_methods", "find_related_sessions", "find_sessions_by_body", "explain_error", "search_by_time", "search_by_status", "search_by_source", "search_by_target", "search_by_message_class", "search_by_session", "search_by_super_session", "search_by_body_field", "inspect_body_candidates", "vocab_lookup", "get_queue_state", "get_rule_source", "get_class_source", "get_production_config_item", "find_sessions_using_class")
    Set tFound = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        Set tFound = tFound _ "," _ tEntry.%Get("name") _ ","
    }
    Set tPtr = 0
    While $ListNext(tExpected, tPtr, tName) {
        Do $$$AssertTrue(tFound [ ("," _ tName _ ","), "registry surfaces tool '" _ tName _ "'")
    }
    Quit
}

/// <p>Smoke test the Story 4.7 closer: explain_error decodes a curated
/// error code AND a %Status round-trip without throwing. Happy-path
/// assertions live here rather than a dedicated ExplainErrorTest class
/// because the tool is small (single SQL-free lookup) and the envelope
/// contract is fully validated by the suite tests above.</p>
Method TestExplainErrorMatchedCodeReturnsCuratedEntry()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"status_or_error_string": "<PROTECT>"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "explain_error Invoke returns $$$OK")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "matched", "render_strategy = 'matched' for known code")
    Do $$$AssertEquals(tResult.structuredContent.%Get("code_class"), "security", "code_class = 'security' for <PROTECT>")
    Do $$$AssertTrue($IsObject(tResult.structuredContent.%Get("common_causes")), "common_causes is array")
    Do $$$AssertTrue(tResult.structuredContent.%Get("common_causes").%Size() > 0, "common_causes non-empty for matched code")
    Do $$$AssertTrue($IsObject(tResult.structuredContent.%Get("suggested_diagnostics")), "suggested_diagnostics is array")
    Do $$$AssertTrue(tResult.structuredContent.%Get("suggested_diagnostics").%Size() > 0, "suggested_diagnostics non-empty for matched code")
    Quit
}

/// <p>explain_error returns the success-shape "unmatched" envelope (NOT
/// an error envelope) when the input is not a curated code and not a
/// %Status — so the operator always sees the input echoed back with a
/// "search documentation" hint.</p>
Method TestExplainErrorUnmatchedReturnsHint()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"status_or_error_string": "<TOTALLY_BOGUS>"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on unmatched code")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on unmatched code (success-shape)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "unmatched", "render_strategy = 'unmatched'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("code_class"), "unknown", "code_class = 'unknown' on unmatched")
    Do $$$AssertTrue(tResult.content.%Get(0).text [ "<TOTALLY_BOGUS>", "operator-text echoes the input")
    Quit
}

/// <p>explain_error decodes a real %Status produced by
/// <code>$System.Status.Error</code> and folds in a curated entry when
/// the embedded code matches the curated table.</p>
Method TestExplainErrorStatusShapeDecodes()
{
    Set tCtx = ..BuildCtx()
    ; Build a real %Status with an embedded <UNDEFINED>-ish message.
    Set tStatus = $System.Status.Error(5002, "<UNDEFINED>fakeVar")
    Set tArgs = {"status_or_error_string": (tStatus)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on %Status input")
    Set tStrategy = tResult.structuredContent.%Get("render_strategy")
    Do $$$AssertTrue((tStrategy = "matched") || (tStrategy = "status_decoded"), "render_strategy = 'matched' or 'status_decoded' on %Status input (got: " _ tStrategy _ ")")
    Do $$$AssertNotEquals(tResult.structuredContent.%Get("decoded_text"), "", "decoded_text non-empty on %Status input")
    Quit
}

/// <p>FR37 — explain_error returns isError envelope on missing required
/// arg, like every other tool.</p>
Method TestExplainErrorMissingInputReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on missing input (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing status_or_error_string")
    Quit
}

/// <p>AC-7 (Story 4.5 R-4) — Tool.Base.FormatExceptionForOperator helper
/// strips IRIS-internal prefixes from a real exception's DisplayString
/// and returns operator-friendly text. The helper is exercised here
/// rather than ToolBaseTest because it's tightly coupled to the AC-7
/// sweep semantics (every tool's catch block uses it).</p>
Method TestFormatExceptionForOperatorStripsNoise()
{
    Set tEx = ##class(%Exception.SystemException).%New("<UNDEFINED>", 5002, "%xMethod+12^MyPackage.MyClass.1", "fakeVar")
    Set tFormatted = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(tEx)
    Do $$$AssertNotEquals(tFormatted, "", "FormatExceptionForOperator returns non-empty")
    Do $$$AssertTrue(tFormatted [ "<UNDEFINED>", "operator-text retains the IRIS error tag")
    ; The internal frame +<line>^<routine>.<num> should be stripped.
    Do $$$AssertEquals(tFormatted [ "+12^", 0, "operator-text drops the frame line+routine suffix")
    Quit
}

/// <p>Defensive — FormatExceptionForOperator returns an empty string
/// on null exception input rather than throwing.</p>
Method TestFormatExceptionForOperatorNullInputReturnsEmpty()
{
    Set tFormatted = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator($$$NULLOREF)
    Do $$$AssertEquals(tFormatted, "", "FormatExceptionForOperator($$$NULLOREF) = ''")
    Quit
}

/// <p>Story 5.0 AC-5 — assert each new Ens-specific curated code returns
/// a complete matched envelope: <code>render_strategy="matched"</code>,
/// non-empty <code>decoded_text</code>, populated <code>common_causes</code>
/// array, populated <code>suggested_diagnostics</code> array,
/// <code>code_class="interop"</code>. Single helper-driven test
/// exercises all 4 new codes (ErrGeneral, ErrBPTimeout, ErrNoTimeout,
/// ErrException) plus the corrected <code>&lt;Ens&gt;ErrBPTerminated</code>
/// (replaces stale <code>&lt;Ens&gt;ErrBPTerm</code> from Story 4.7).</p>
Method TestExplainErrorStory50EnsCodesAllReturnMatchedEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tCodes = $ListBuild("<Ens>ErrGeneral", "<Ens>ErrBPTimeout", "<Ens>ErrNoTimeout", "<Ens>ErrException", "<Ens>ErrSearchTableNotIndex", "<Ens>ErrBPTerminated")
    Set tPtr = 0
    While $ListNext(tCodes, tPtr, tCode) {
        Set tArgs = {"status_or_error_string": (tCode)}
        Set tResult = ""
        Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
        Do $$$AssertStatusOK(tSC, tCode _ ": Invoke returns $$$OK")
        Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "matched", tCode _ ": render_strategy='matched'")
        Do $$$AssertEquals(tResult.structuredContent.%Get("matched_code"), tCode, tCode _ ": matched_code echoes the input code")
        Do $$$AssertEquals(tResult.structuredContent.%Get("code_class"), "interop", tCode _ ": code_class='interop' (Ens family)")
        Do $$$AssertNotEquals(tResult.structuredContent.%Get("decoded_text"), "", tCode _ ": decoded_text non-empty")
        Set tCauses = tResult.structuredContent.%Get("common_causes")
        Do $$$AssertTrue($IsObject(tCauses), tCode _ ": common_causes is array")
        Do $$$AssertTrue(tCauses.%Size() > 0, tCode _ ": common_causes non-empty (>= 1 entry)")
        Set tDiags = tResult.structuredContent.%Get("suggested_diagnostics")
        Do $$$AssertTrue($IsObject(tDiags), tCode _ ": suggested_diagnostics is array")
        Do $$$AssertTrue(tDiags.%Size() > 0, tCode _ ": suggested_diagnostics non-empty (>= 1 entry)")
    }
    Quit
}

/// <p>Story 5.0 AC-5 — verify the stale <code>&lt;Ens&gt;ErrBPTerm</code>
/// key is GONE from the curated table (corrected to canonical
/// <code>&lt;Ens&gt;ErrBPTerminated</code> per
/// <code>irislib/EnsErrors.inc</code> line 18). The bare lookup of the
/// stale name must fall through to the unmatched-shape envelope.</p>
Method TestExplainErrorStaleErrBPTermNoLongerMatches()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"status_or_error_string": "<Ens>ErrBPTerm"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.ExplainError).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on stale ErrBPTerm")
    ; The stale name is a substring of <Ens>ErrBPTerminated — the
    ; ordered LookupCuratedCode must NOT match the longer canonical
    ; name when the input is the SHORTER stale name. Allowed outcomes:
    ; either "unmatched" (the stale name is gone) OR "matched" with
    ; matched_code = "<Ens>ErrBPTerminated" (longest-prefix lookup
    ; resolved upward). Either is acceptable; what is FORBIDDEN is
    ; matched_code = "<Ens>ErrBPTerm" (stale name still in the table).
    Set tStrategy = tResult.structuredContent.%Get("render_strategy")
    If tStrategy = "matched" {
        Do $$$AssertNotEquals(tResult.structuredContent.%Get("matched_code"), "<Ens>ErrBPTerm", "matched_code MUST NOT be the stale '<Ens>ErrBPTerm' name (Story 5.0 correction)")
    } Else {
        Do $$$AssertEquals(tStrategy, "unmatched", "render_strategy is 'unmatched' for the stale ErrBPTerm name (Story 5.0)")
    }
    Quit
}

/// <p>Story 5.0 Item G fold-in — the curated table is per-process
/// cached via <code>^||SessionAgentExplainErrorTable</code>. Verify
/// the cache PPG is set after a BuildErrorTable call, and that a
/// second call returns a populated table when the cache is present.
/// (Cannot directly assert "no rebuild on cache hit" without
/// instrumentation; this test instead asserts the contract: cache is
/// seeded after first call, cache rehydration yields the same shape.)</p>
Method TestExplainErrorTableCachedInProcessPrivateGlobal()
{
    ; Clear the cache to force a fresh build.
    Kill ^||SessionAgentExplainErrorTable
    Do $$$AssertEquals($Data(^||SessionAgentExplainErrorTable), 0, "cache PPG cleared at start")
    Set tFirst = ##class(SessionAgent.Tool.Inspection.ExplainError).BuildErrorTable()
    Do $$$AssertTrue(tFirst.%Size() > 0, "first BuildErrorTable returns populated table")
    Do $$$AssertNotEquals($Data(^||SessionAgentExplainErrorTable), 0, "cache PPG seeded after first call")
    ; Second call — should rehydrate from cache and return a table of
    ; the same size with the same keys.
    Set tSecond = ##class(SessionAgent.Tool.Inspection.ExplainError).BuildErrorTable()
    Do $$$AssertEquals(tSecond.%Size(), tFirst.%Size(), "cached call returns same-sized table")
    Do $$$AssertTrue(tSecond.%IsDefined("<Ens>ErrGeneral"), "cached call has <Ens>ErrGeneral entry")
    Do $$$AssertTrue(tSecond.%IsDefined("<Ens>ErrBPTerminated"), "cached call has corrected <Ens>ErrBPTerminated entry")
    ; Cleanup.
    Kill ^||SessionAgentExplainErrorTable
    Quit
}

}
