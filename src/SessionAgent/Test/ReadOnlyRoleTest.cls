/// <p>Unit tests for <CLASS>SessionAgent.Security.ReadOnlyRole</CLASS>.</p>
///
/// <p>Verifies the six behaviors required by Story 1.4 acceptance
/// criterion AC-5:</p>
/// <ol>
/// <li><b>TestRoleInstallCreates</b> — invoke <code>Install()</code> once;
/// assert <code>Security.Roles.Exists("SessionAgent_ReadOnly")</code>
/// returns 1.</li>
/// <li><b>TestRoleInstallIdempotent</b> — invoke <code>Install()</code>
/// twice; both calls return <code>$$$OK</code> and the role is still
/// present after the second call.</li>
/// <li><b>TestPrivilegeEnforcementInsertFails</b> — create a test user,
/// grant the role, query <code>CheckPrivilege</code> for INSERT on
/// <code>Ens.MessageHeader</code>, assert it returns 0.</li>
/// <li><b>TestPrivilegeEnforcementDeleteFails</b> — same pattern for
/// DELETE.</li>
/// <li><b>TestPrivilegeEnforcementSelectSucceeds</b> — same pattern for
/// SELECT, asserts it returns 1.</li>
/// <li><b>TestRestoresNamespace</b> — capture <code>$NAMESPACE</code>
/// before and after <code>Install()</code>; assert unchanged.</li>
/// </ol>
///
/// <p><b>Process-context test strategy (Story 1.4 Task 0 §"Process-context
/// test strategy decision"):</b> the privilege-enforcement tests use
/// <b>Approach 4 — synthetic CheckPrivilege query</b>. Rather than spawn a
/// JOB with the test user's credentials and attempt an actual INSERT
/// (which would PROTECT-error), we ask
/// <code>$SYSTEM.SQL.Security.CheckPrivilege</code> whether the test user
/// holds the INSERT/DELETE/SELECT privilege on
/// <code>Ens.MessageHeader</code>. Approach 4 was chosen because:
/// (a) it authentically queries the IRIS privilege catalog the same way
/// any real INSERT/DELETE attempt would consult it; (b) Approach 1 (JOB
/// with test-user creds) would require cross-process error retrieval and
/// re-entry into ObjectScript with the test user's credentials, which is
/// complex and brittle on 2024.1; (c) Approaches 2 and 3
/// (<code>SetCredentials</code> / per-call security context arg) do not
/// exist on <code>Security.Users</code> or <code>%SQL.Statement</code> per
/// the Task 0 probes; and (d) the L1+L2 layers of the read-only stack
/// backstop the runtime path. The probe transcript verified end-to-end
/// that CheckPrivilege returns 1 for SELECT and 0 for INSERT/DELETE for a
/// real user with this role attached.</p>
///
/// <p><b>Cleanup contract:</b> tests create a throwaway test user
/// (<code>SaReadOnlyTestUser</code>) in <code>OnBeforeOneTest</code> and
/// delete it in <code>OnAfterOneTest</code>. The
/// <code>SessionAgent_ReadOnly</code> role itself is the install
/// side-effect — it persists after the test runs (this is intentional;
/// future stories rely on the role being installed). The test user does
/// NOT persist.</p>
Class SessionAgent.Test.ReadOnlyRoleTest Extends %UnitTest.TestCase
{

/// <p>The throwaway user the test creates. Underscore-form name keeps it
/// distinct from the role name and makes ad-hoc cleanup queries easier.</p>
Parameter TESTUSER = "SaReadOnlyTestUser";

/// <p>The role the install creates. Mirrors
/// <code>SessionAgent.Security.ReadOnlyRole.ROLENAME</code>; we duplicate
/// here only because <code>Parameter</code>s on a different class are not
/// directly composable into a literal in another class file. If the role
/// name changes, both parameters must change.</p>
Parameter ROLENAME = "SessionAgent_ReadOnly";

/// <p>The known-good password the test uses. Not security-sensitive — the
/// test user is deleted in <code>OnAfterOneTest</code> and only ever
/// exists during a test run.</p>
Parameter TESTPWD = "SaReadOnlyTestPwd123!";

/// <p>Constructor — must accept the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, and must call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Per-test setup: ensure the role is installed (so privilege-query
/// tests can rely on its grants), then create the throwaway test user
/// with the role attached. Idempotent w.r.t. the role; the test user is
/// always re-created from a clean state.</p>
Method OnBeforeOneTest() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        ; Ensure the role + grants are installed before each test.
        Set tSC = ##class(SessionAgent.Security.ReadOnlyRole).Install()
        If $$$ISERR(tSC) {
            Set $NAMESPACE = tOrigNS
            Quit
        }

        Set $NAMESPACE = "%SYS"
        ; Drop any leftover test user from a prior run before re-creating.
        If ##class(Security.Users).Exists(..#TESTUSER) {
            Do ##class(Security.Users).Delete(..#TESTUSER)
        }
        Set tSC = ##class(Security.Users).Create(
            ..#TESTUSER,
            ..#ROLENAME,
            ..#TESTPWD,
            "SessionAgent ReadOnly Test User",
            $Get(tOrigNS, "HSCUSTOM"),
            "",
            "",
            "",
            1,
            "Story 1.4 RBAC enforcement test — safe to delete")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Per-test teardown: delete the throwaway test user. The role itself
/// is intentionally left in place — that is the install side-effect this
/// story is about, and future stories rely on the role's presence. The
/// test must never leave a test USER behind, only the role.</p>
Method OnAfterOneTest() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Users).Exists(..#TESTUSER) {
            Do ##class(Security.Users).Delete(..#TESTUSER)
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>AC-5 #1 / Story Task 2 #1 — invoke <code>Install()</code> and
/// assert the role is present in <code>%SYS Security.Roles</code>.</p>
Method TestRoleInstallCreates()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Security.ReadOnlyRole).Install(), "Install returns OK")

    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Do $$$AssertTrue(##class(Security.Roles).Exists(..#ROLENAME), "SessionAgent_ReadOnly role exists after Install()")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-5 #2 / AC-3 — invoke <code>Install()</code> twice; both calls
/// must return <code>$$$OK</code>. Confirms idempotent reinstall (no
/// duplicate-create error, no double-grant error).</p>
Method TestRoleInstallIdempotent()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Security.ReadOnlyRole).Install(), "first Install() OK")
    Do $$$AssertStatusOK(##class(SessionAgent.Security.ReadOnlyRole).Install(), "second Install() OK (no duplicate-create or double-grant error)")

    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Do $$$AssertTrue(##class(Security.Roles).Exists(..#ROLENAME), "role still present after second Install()")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-5 #4 — verify the test user (with only
/// <code>SessionAgent_ReadOnly</code>) does NOT hold INSERT privilege on
/// <code>Ens.MessageHeader</code>.</p>
///
/// <p><b>Approach 4 (CheckPrivilege synthetic query):</b> queries the IRIS
/// privilege catalog directly rather than spawning a JOB with the test
/// user's credentials and attempting an actual INSERT. Rationale in the
/// class-level docstring §"Process-context test strategy". Verified
/// end-to-end during Task 0 probe.</p>
Method TestPrivilegeEnforcementInsertFails()
{
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "HSCUSTOM"
        Set tHasInsert = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens.MessageHeader", "i", "HSCUSTOM")
        Do $$$AssertEquals(tHasInsert, 0, "test user does NOT hold INSERT on Ens.MessageHeader (CheckPrivilege returns 0)")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-5 #5 — verify the test user does NOT hold DELETE privilege on
/// <code>Ens.MessageHeader</code>. Same approach + rationale as
/// <code>TestPrivilegeEnforcementInsertFails</code>.</p>
Method TestPrivilegeEnforcementDeleteFails()
{
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "HSCUSTOM"
        Set tHasDelete = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens.MessageHeader", "d", "HSCUSTOM")
        Do $$$AssertEquals(tHasDelete, 0, "test user does NOT hold DELETE on Ens.MessageHeader (CheckPrivilege returns 0)")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-5 #6 — verify the test user DOES hold SELECT privilege on
/// <code>Ens.MessageHeader</code>. Confirms the GRANT was correctly
/// applied to the role for the canonical session-trace surface.</p>
Method TestPrivilegeEnforcementSelectSucceeds()
{
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "HSCUSTOM"
        Set tHasSelect = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens.MessageHeader", "s", "HSCUSTOM")
        Do $$$AssertEquals(tHasSelect, 1, "test user holds SELECT on Ens.MessageHeader (CheckPrivilege returns 1)")

        ; Spot-check the other three canonical tables to confirm the
        ; GRANT loop covers each surface, not just Ens.MessageHeader.
        Set tHasSelectSSI = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens.SuperSessionIndex", "s", "HSCUSTOM")
        Do $$$AssertEquals(tHasSelectSSI, 1, "test user holds SELECT on Ens.SuperSessionIndex")

        Set tHasSelectUL = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens_Util.Log", "s", "HSCUSTOM")
        Do $$$AssertEquals(tHasSelectUL, 1, "test user holds SELECT on Ens_Util.Log")

        Set tHasSelectRL = $SYSTEM.SQL.Security.CheckPrivilege(..#TESTUSER, 1, "Ens_Rule.Log", "s", "HSCUSTOM")
        Do $$$AssertEquals(tHasSelectRL, 1, "test user holds SELECT on Ens_Rule.Log")

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-5 / AC-1 — capture <code>$NAMESPACE</code> before the call,
/// invoke <code>Install()</code>, verify <code>$NAMESPACE</code> is
/// unchanged afterward (success-path coverage of the explicit
/// save/restore pattern).</p>
Method TestRestoresNamespace()
{
    Set tBefore = $NAMESPACE
    Do $$$AssertStatusOK(##class(SessionAgent.Security.ReadOnlyRole).Install(), "Install OK")
    Do $$$AssertEquals($NAMESPACE, tBefore, "namespace restored after Install()")
    Quit
}

}
