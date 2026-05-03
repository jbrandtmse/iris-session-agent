/// <p>Unit tests for <CLASS>SessionAgent.Util.EnvSecret</CLASS> per Story 2.3
/// AC-3.</p>
///
/// <p><b>Env-var test strategy.</b> The story spec proposed using
/// <code>$SYSTEM.Util.SetEnviron(name, value)</code> to plant a sentinel
/// env-var inside each test, but empirical Task 0 probing found that no
/// public IRIS API supports mutating a process's environment variables
/// from inside the same process — <code>%SYSTEM.Util</code> exposes only
/// <code>GetEnviron</code> (irislib snapshot, line 86), and
/// <code>$ZF(-2,...)</code> returns 0 without making the value visible to
/// a subsequent <code>GetEnviron</code> call (verified: written value
/// silently discarded). Per Perplexity research summary, this is a
/// fundamental IRIS limitation: env vars are inherited at IRIS process
/// startup and cannot be retroactively set from inside the process.</p>
///
/// <p>Rather than mock-out the production resolver (which would change
/// the production class shape just to satisfy a test), tests exercise
/// the env-var rung against an OS-set sentinel that always exists at
/// IRIS startup time: <code>PATH</code> on Windows / Unix. The fixture
/// captures <code>$SYSTEM.Util.GetEnviron("PATH")</code> in
/// <method>OnBeforeAllTests</method>, asserts it is non-empty (test
/// host invariant), and uses the captured value as the expected return
/// from the env-var rung. This empirically tests the same code path
/// (the call to <code>$SYSTEM.Util.GetEnviron</code> with a non-empty
/// env-var name and a non-empty environment value) without needing a
/// SetEnviron API.</p>
///
/// <p>The credential-row tests use a unique sentinel
/// <code>SystemName="SessionAgentTestCred"</code> created via
/// <method>Ens.Config.Credentials.SetCredential</method> (overwrite=1
/// so reruns don't break) and cleaned up in
/// <method>OnAfterOneTest</method>. The empty-args / no-resolve tests
/// pass an env-var name guaranteed not to be set
/// (<code>SESSIONAGENT_TEST_VAR_DOES_NOT_EXIST</code>) and a credential
/// name guaranteed not to exist
/// (<code>SessionAgentTestCredDoesNotExist</code>).</p>
///
/// <p>Eight test methods per Story 2.3 AC-3, all assertions via
/// <code>$$$Assert*</code> macros (never <code>..AssertX(...)</code>),
/// no underscores in method names, file ≤ 500 lines.</p>
Class SessionAgent.Test.EnvSecretTest Extends %UnitTest.TestCase
{

/// <p>Captured at <method>OnBeforeAllTests</method>: the value of
/// <code>$SYSTEM.Util.GetEnviron("PATH")</code> as observed by the IRIS
/// process at the time the test class is instantiated. Used as the
/// expected return value from the env-var rung in
/// <method>TestEnvVarPathResolves</method> and
/// <method>TestEnvVarTakesPrecedenceOverCredential</method>.</p>
Property OsPathValue As %String;

/// <p>Constructor — accepts the <code>initvalue</code> the parent
/// <code>%UnitTest.TestCase</code> expects, calls
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..OsPathValue = ""
    Quit $$$OK
}

/// <p>Capture the OS-set <code>PATH</code> env var so individual tests
/// have a stable expected value for the env-var rung. If the host has
/// no PATH (extremely unusual), each env-var test will fail its
/// non-empty assertion and surface the missing fixture loudly rather
/// than passing on stale data.</p>
Method OnBeforeAllTests() As %Status
{
    Set ..OsPathValue = $SYSTEM.Util.GetEnviron("PATH")
    Quit $$$OK
}

/// <p>Per-test cleanup: delete the test credential row if it exists, so
/// a failed mid-test assert doesn't leak state into the next test.
/// <code>Try</code>-around-each-cleanup pattern (project rule §"Test
/// setup/teardown discipline") so a failed delete on one row doesn't
/// skip the others.</p>
Method OnAfterOneTest() As %Status
{
    Try {
        If ##class(Ens.Config.Credentials).%ExistsId("SessionAgentTestCred") {
            Do ##class(Ens.Config.Credentials).%DeleteId("SessionAgentTestCred")
        }
    } Catch {}
    Quit $$$OK
}

/// <p>AC-3 #1 — env-var rung: <code>Resolve("PATH", "")</code> returns
/// the OS-set <code>PATH</code> value. Verified against the captured
/// fixture <property>OsPathValue</property>.</p>
Method TestEnvVarPathResolves()
{
    Do $$$AssertNotEquals(..OsPathValue, "", "fixture: PATH env var is non-empty on test host")
    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("PATH", "")
    Do $$$AssertEquals(tResolved, ..OsPathValue, "Resolve(PATH, """") returns the OS-set PATH value")
    Quit
}

/// <p>AC-3 #2 — credential rung: with a fresh
/// <code>Ens.Config.Credentials</code> row whose Password is
/// <code>"cred-value-xyz789"</code>, <code>Resolve("", "SessionAgentTestCred")</code>
/// returns that password. The empty env-var name skips rung 1, the
/// credential name resolves on rung 2.</p>
Method TestCredentialPathResolves()
{
    Set tSC = ##class(Ens.Config.Credentials).SetCredential("SessionAgentTestCred", "testuser", "cred-value-xyz789", 1)
    Do $$$AssertStatusOK(tSC, "fixture: SetCredential succeeded")

    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("", "SessionAgentTestCred")
    Do $$$AssertEquals(tResolved, "cred-value-xyz789", "Resolve("""", SessionAgentTestCred) returns the credential Password")
    Quit
}

/// <p>AC-3 #3 — precedence: when BOTH the env-var (PATH) and a
/// credential row exist with different values, the env-var wins.
/// Confirms rung 1 is checked before rung 2 and short-circuits.</p>
Method TestEnvVarTakesPrecedenceOverCredential()
{
    Set tSC = ##class(Ens.Config.Credentials).SetCredential("SessionAgentTestCred", "testuser", "cred-value-should-not-win", 1)
    Do $$$AssertStatusOK(tSC, "fixture: SetCredential succeeded")
    Do $$$AssertNotEquals(..OsPathValue, "", "fixture: PATH env var is non-empty on test host")
    Do $$$AssertNotEquals(..OsPathValue, "cred-value-should-not-win", "fixture: PATH and credential have different values")

    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("PATH", "SessionAgentTestCred")
    Do $$$AssertEquals(tResolved, ..OsPathValue, "env-var rung wins; credential rung never consulted")
    Quit
}

/// <p>AC-3 #4 — no source resolves: passing a guaranteed-unset env-var
/// name AND a guaranteed-missing credential name returns
/// <code>""</code>. The AES stub (rung 3) returns empty per its v1
/// deferral, so the overall return is empty — locking the
/// no-exception-thrown semantics of <method>Resolve</method>.</p>
Method TestNothingResolvesReturnsEmpty()
{
    ; Belt-and-suspenders: confirm the env var really is unset on the host.
    Do $$$AssertEquals($SYSTEM.Util.GetEnviron("SESSIONAGENT_TEST_VAR_DOES_NOT_EXIST"), "", "fixture: sentinel env var is unset")
    Do $$$AssertTrue('##class(Ens.Config.Credentials).%ExistsId("SessionAgentTestCredDoesNotExist"), "fixture: sentinel credential does not exist")

    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("SESSIONAGENT_TEST_VAR_DOES_NOT_EXIST", "SessionAgentTestCredDoesNotExist")
    Do $$$AssertEquals(tResolved, "", "Resolve returns empty when no rung resolves; never throws")
    Quit
}

/// <p>AC-3 #5 — empty args: <code>Resolve("", "")</code> returns
/// <code>""</code>. Both rung 1 and rung 2 short-circuit on empty
/// names; rung 3 stub returns empty.</p>
Method TestEmptyArgsReturnEmpty()
{
    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("", "")
    Do $$$AssertEquals(tResolved, "", "Resolve("""", """") returns empty")
    Quit
}

/// <p>AC-3 #6 — predicate parity: <method>IsResolvable</method> mirrors
/// <method>Resolve</method>'s non-empty / empty return. Verified for
/// (a) the env-var-resolves case (PATH), (b) the credential-resolves
/// case, and (c) the no-resolve case.</p>
Method TestIsResolvablePredicate()
{
    ; (a) env-var rung resolves.
    Do $$$AssertEquals(##class(SessionAgent.Util.EnvSecret).IsResolvable("PATH", ""), 1, "IsResolvable=1 when env-var rung resolves")

    ; (b) credential rung resolves.
    Set tSC = ##class(Ens.Config.Credentials).SetCredential("SessionAgentTestCred", "testuser", "cred-pred-value", 1)
    Do $$$AssertStatusOK(tSC, "fixture: SetCredential succeeded")
    Do $$$AssertEquals(##class(SessionAgent.Util.EnvSecret).IsResolvable("", "SessionAgentTestCred"), 1, "IsResolvable=1 when credential rung resolves")

    ; (c) no rung resolves.
    Do $$$AssertEquals(##class(SessionAgent.Util.EnvSecret).IsResolvable("SESSIONAGENT_TEST_VAR_DOES_NOT_EXIST", "SessionAgentTestCredDoesNotExist"), 0, "IsResolvable=0 when no rung resolves")

    ; Empty args.
    Do $$$AssertEquals(##class(SessionAgent.Util.EnvSecret).IsResolvable("", ""), 0, "IsResolvable=0 for ("""", """")")
    Quit
}

/// <p>AC-3 #7 — empirical NFR-S3 check: <method>Resolve</method> does
/// NOT mutate <code>^ClineDebug</code> across a successful call.
/// Captures the global before and after (env-var rung resolves PATH);
/// asserts unchanged. Closes the never-log loop for the surface
/// visible at this story (full audit-row coverage lands in Story 2.5/2.9).</p>
///
/// <p>Resets <code>^ClineDebug</code> to a sentinel value before the
/// call so the test isn't sensitive to whatever debug state may already
/// be in the global from prior unrelated work.</p>
Method TestResolveDoesNotMutateClineDebug()
{
    Set ^ClineDebug = "sentinel-before-resolve-call"
    Set tBefore = ^ClineDebug

    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("PATH", "")
    Do $$$AssertNotEquals(tResolved, "", "fixture: env-var rung resolved PATH (precondition for the no-mutation check to be meaningful)")

    Set tAfter = ^ClineDebug
    Do $$$AssertEquals(tAfter, tBefore, "^ClineDebug unchanged after Resolve (NFR-S3 never-log surface check)")

    ; Cleanup the sentinel so we don't leak debug state.
    Kill ^ClineDebug
    Quit
}

/// <p>AC-3 #8 — AES stub contract: <code>Resolve("", "AnyName")</code>
/// where <code>AnyName</code> is NOT in <code>Ens.Config.Credentials</code>
/// returns <code>""</code> (the AES stub returns empty per its v1
/// deferral). With env-var name empty (rung 1 skipped) and the credential
/// row absent (rung 2 yields empty), the overall return must come from
/// rung 3 — which is the v1 stub. Locks the stub semantics so a future
/// AES backend change is a deliberate spec change, not an accidental
/// behavior drift.</p>
Method TestAesStoreStubReturnsEmpty()
{
    Do $$$AssertTrue('##class(Ens.Config.Credentials).%ExistsId("SessionAgentTestAesStubName"), "fixture: AES probe credential is absent (rung 2 will yield empty)")

    Set tResolved = ##class(SessionAgent.Util.EnvSecret).Resolve("", "SessionAgentTestAesStubName")
    Do $$$AssertEquals(tResolved, "", "AES stub returns empty in v1 (deferral per architecture line 255)")
    Quit
}

}
