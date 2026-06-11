/// <p>Story 14.3 AC-5 — CI invariant test for the guarded dynamic-SQL
/// discipline (FR60). Mirrors
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS>: discovers
/// every concrete subclass of
/// <CLASS>SessionAgent.Tool.Query.Base</CLASS> registered in the current
/// namespace (excluding <code>SessionAgent.Test.*</code> fixtures) and
/// asserts via SOURCE INTROSPECTION that each tool routes execution
/// through the base pipeline's single entry point
/// (<method>RunGuardedSelect</method>) — no direct <code>%Prepare</code>
/// / <code>%Execute</code> / embedded <code>&amp;sql(</code> anywhere in
/// the concrete class's own methods. Any future Query-tool author who
/// bypasses the guard pipeline gets a CI failure here, NOT an unguarded
/// write path in production.</p>
///
/// <p><b>Forbidden-token enumeration (Epic 12 AI-5 substring-grep
/// binding).</b> The token list is enumerated in ONE place
/// (<method>GetForbiddenTokens</method>) and each token is checked
/// against each method implementation — enumerate-all-check-each, never
/// a single ad-hoc substring.</p>
///
/// <p><b>Negative control.</b>
/// <CLASS>SessionAgent.Test.Fixture.StubNonConformingQueryTool</CLASS>
/// deliberately violates the contract (direct <code>%Prepare</code> +
/// <code>%Execute</code> in <code>Invoke</code>); the conformance
/// checker MUST flag it — a positive control of the rejection logic,
/// proving a future non-conforming Query tool fails this test.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md">Story 14.3</a> — AC-5 source.</li>
/// <li><a href="BoundedWhereInvariantTest.cls">BoundedWhereInvariantTest.cls</a> — the invariant-test precedent.</li>
/// </ul>
Class SessionAgent.Test.ReadOnlySqlInvariantTest Extends %UnitTest.TestCase
{

Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>The enumerated forbidden-token list — direct-SQL surfaces a
/// concrete Query tool must NEVER contain in its own method bodies
/// (the only sanctioned <code>%Prepare</code>/<code>%Execute</code>
/// call-sites live in <method>SessionAgent.Tool.Query.Base.RunGuardedSelect</method>).
/// Matching is case-insensitive.</p>
ClassMethod GetForbiddenTokens() As %List
{
    ; Story 14.3 review fix cr-14-3-D — added "%SQL.STATEMENT" to close the
    ; instantiation-based evasion vector: a non-conforming tool that builds
    ; its %Prepare/%Execute method names dynamically (e.g.
    ; $Method(s,"%Pre"_"pare")) would slip the %PREPARE/%EXECUTE substring
    ; greps, but it still has to instantiate %SQL.Statement to get the
    ; result-set object. A conforming Query tool routes ALL execution
    ; through the base RunGuardedSelect and NEVER touches %SQL.Statement in
    ; its own method bodies, so the token has no legitimate production use.
    Quit $ListBuild("%PREPARE", "%EXECUTE", "&SQL(", "%SQL.STATEMENT")
}

/// <p>Conformance checker — returns 1 when <var>pClassName</var>
/// satisfies the guarded-pipeline contract, else 0 with
/// <var>pViolations</var> populated:</p>
/// <ol>
/// <li>The class defines its own <code>Invoke</code> method.</li>
/// <li><code>Invoke</code>'s implementation contains a
/// <code>RunGuardedSelect</code> routing call.</li>
/// <li>NO locally-defined method's implementation contains any
/// forbidden token (<method>GetForbiddenTokens</method>).</li>
/// </ol>
/// <p>Reads <code>%Dictionary.MethodDefinition.Implementation</code>
/// (source, not codegen) — doc comments are NOT part of the
/// implementation stream, so prose mentions of <code>%Prepare</code>
/// in <code>///</code> banners do not false-positive.</p>
ClassMethod CheckQueryToolConformance(pClassName As %String, Output pViolations As %DynamicArray) As %Boolean
{
    Set pViolations = []

    ; --- (1) + (2): local Invoke exists and routes through the pipeline. ---
    Set tInvoke = ##class(%Dictionary.MethodDefinition).%OpenId(pClassName _ "||Invoke")
    If '$IsObject(tInvoke) {
        Do pViolations.%Push(pClassName _ ": no locally-defined Invoke method")
    } Else {
        Set tImpl = ..ReadImplementation(tInvoke)
        If '($ZConvert(tImpl, "U") [ "RUNGUARDEDSELECT") {
            Do pViolations.%Push(pClassName _ ": Invoke does not route through RunGuardedSelect")
        }
    }

    ; --- (3): enumerate-all-check-each — every local method body is
    ;     grepped against every forbidden token. ---
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS MethodName FROM %Dictionary.MethodDefinition WHERE parent = ? ORDER BY %EXACT(Name)")
    If $$$ISERR(tSC) {
        Do pViolations.%Push(pClassName _ ": method-enumeration prepare failed: " _ $System.Status.GetErrorText(tSC))
        Quit 0
    }
    Set tRS = tStmt.%Execute(pClassName)
    While tRS.%Next() {
        Set tMethodName = tRS.%Get("MethodName")
        Set tMethod = ##class(%Dictionary.MethodDefinition).%OpenId(pClassName _ "||" _ tMethodName)
        If '$IsObject(tMethod) Continue
        Set tImpl = $ZConvert(..ReadImplementation(tMethod), "U")
        Set tTokens = ..GetForbiddenTokens()
        Set tPtr = 0
        While $ListNext(tTokens, tPtr, tToken) {
            If tImpl [ tToken {
                Do pViolations.%Push(pClassName _ "." _ tMethodName _ ": contains forbidden direct-SQL token '" _ tToken _ "' (must route through RunGuardedSelect)")
            }
        }
    }
    If tRS.%SQLCODE < 0 {
        Do pViolations.%Push(pClassName _ ": method-enumeration fetch failed: SQLCODE " _ tRS.%SQLCODE)
    }

    Quit (pViolations.%Size() = 0)
}

/// <p>Helper — read a <code>%Dictionary.MethodDefinition</code>'s full
/// implementation stream as one string.</p>
ClassMethod ReadImplementation(pMethod As %Dictionary.MethodDefinition) As %String
{
    Set tImpl = ""
    Try {
        Do pMethod.Implementation.Rewind()
        While 'pMethod.Implementation.AtEnd {
            Set tImpl = tImpl _ pMethod.Implementation.Read(32000)
        }
    }
    Catch ex {
        Set tImpl = ""
    }
    Quit tImpl
}

/// <p>AC-5 — discovery loop over every concrete production subclass of
/// <CLASS>SessionAgent.Tool.Query.Base</CLASS>. Each MUST pass the
/// conformance check. At Story 14.3 close exactly 1 tool
/// (<code>execute_readonly_sql</code>) is discovered; future Query
/// tools are picked up automatically by the Super-equality convention
/// (same filter family as <CLASS>SessionAgent.Tool.Registry</CLASS>
/// discovery).</p>
Method TestRegisteredQueryToolsRouteThroughGuardedPipeline()
{
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS ClassName FROM %Dictionary.ClassDefinition WHERE %EXACT(Super) = 'SessionAgent.Tool.Query.Base' AND Abstract = 0 AND NOT (%EXACT(Name) %STARTSWITH 'SessionAgent.Test.') ORDER BY %EXACT(Name)")
    Do $$$AssertStatusOK(tSC, "Production-query-tool discovery query prepared")
    Set tRS = tStmt.%Execute()

    Set tCount = 0
    Set tViolationTotal = 0
    While tRS.%Next() {
        Set tCount = tCount + 1
        Set tClassName = tRS.%Get("ClassName")
        Set tConformant = ..CheckQueryToolConformance(tClassName, .tViolations)
        Do $$$AssertEquals(tConformant, 1, tClassName _ " routes ALL execution through RunGuardedSelect (violations: " _ tViolations.%ToJSON() _ ")")
        Set tViolationTotal = tViolationTotal + tViolations.%Size()
    }
    Do ..LogMessage(tCount _ " production query tool(s) discovered; " _ tViolationTotal _ " violation(s)")
    Do $$$AssertTrue(tCount >= 1, "at least 1 production query tool discovered (execute_readonly_sql ships in Story 14.3; got " _ tCount _ ")")
    Do $$$AssertEquals(tViolationTotal, 0, "All production query tools satisfy the guarded-pipeline invariant")
    Quit
}

/// <p>Positive control of the conformance logic on the shipped tool —
/// <CLASS>SessionAgent.Tool.Query.ExecuteReadonlySql</CLASS> passes
/// with zero violations.</p>
Method TestExecuteReadonlySqlConforms()
{
    Set tConformant = ..CheckQueryToolConformance("SessionAgent.Tool.Query.ExecuteReadonlySql", .tViolations)
    Do $$$AssertEquals(tConformant, 1, "ExecuteReadonlySql passes the conformance check")
    Do $$$AssertEquals(tViolations.%Size(), 0, "ExecuteReadonlySql has zero violations")
    Quit
}

/// <p>Negative control — the deliberately non-conforming fixture
/// (<CLASS>SessionAgent.Test.Fixture.StubNonConformingQueryTool</CLASS>,
/// direct <code>%Prepare</code> + <code>%Execute</code> in
/// <code>Invoke</code>, no <code>RunGuardedSelect</code> routing) is
/// FLAGGED by the checker. Proves a future non-conforming Query tool
/// fails <method>TestRegisteredQueryToolsRouteThroughGuardedPipeline</method>
/// rather than silently shipping an unguarded SQL path.</p>
Method TestNonConformingFixtureWouldBeRejected()
{
    Set tConformant = ..CheckQueryToolConformance("SessionAgent.Test.Fixture.StubNonConformingQueryTool", .tViolations)
    Do $$$AssertEquals(tConformant, 0, "StubNonConformingQueryTool FAILS the conformance check — would be rejected by the production discovery loop")
    Do $$$AssertTrue(tViolations.%Size() >= 2, "violations include both the missing RunGuardedSelect routing and the forbidden tokens (got " _ tViolations.%Size() _ ")")
    ; Enumerate-all-check-each: both direct-SQL tokens are individually named.
    Set tJoined = $ZConvert(tViolations.%ToJSON(), "U")
    Do $$$AssertTrue(tJoined [ "%PREPARE", "a violation names the %Prepare token")
    Do $$$AssertTrue(tJoined [ "%EXECUTE", "a violation names the %Execute token")
    Do $$$AssertTrue(tJoined [ "RUNGUARDEDSELECT", "a violation names the missing RunGuardedSelect routing")
    Quit
}

/// <p>The forbidden-token list itself is locked — a maintainer who
/// trims it weakens the invariant silently; this assertion makes the
/// trim explicit.</p>
Method TestForbiddenTokenListLocked()
{
    Set tTokens = ..GetForbiddenTokens()
    Do $$$AssertEquals($ListLength(tTokens), 4, "exactly 4 forbidden tokens enumerated")
    Do $$$AssertTrue($ListFind(tTokens, "%PREPARE") > 0, "%PREPARE enumerated")
    Do $$$AssertTrue($ListFind(tTokens, "%EXECUTE") > 0, "%EXECUTE enumerated")
    Do $$$AssertTrue($ListFind(tTokens, "&SQL(") > 0, "&SQL( enumerated")
    Do $$$AssertTrue($ListFind(tTokens, "%SQL.STATEMENT") > 0, "%SQL.STATEMENT enumerated (instantiation-evasion guard)")
    Quit
}

}
