/// <p>Story 6.4 AC-7 integration test for
/// <method>SessionAgent.Installer.InstallIntoNamespace</method>. Verifies
/// the multi-namespace install path against a pre-prepared interop
/// namespace <code>SATEST64</code>, plus the three rejection paths
/// (empty / %SYS / missing namespace), the unmapped-package error
/// envelope, and the idempotency invariant inherited from
/// <method>Install</method>.</p>
///
/// <p><b>Pre-prepared namespace strategy:</b>
/// <method>%Library.EnsembleMgr.EnableNamespace</method> can take 30+
/// seconds — longer than the MCP test runner's per-class budget. To stay
/// inside the budget, the integration tests work against a
/// <i>pre-prepared</i> <code>SATEST64</code> namespace that has interop
/// enabled. <method>OnBeforeOneTest</method> attempts to prepare it once
/// (creating the namespace + enabling interop) and caches the result on
/// the test class instance. Subsequent test invocations reuse the existing
/// namespace if present (a no-op detection check, sub-second). The
/// namespace is left in place between test runs — the operator removes
/// it manually via the Mgmt Portal after running the suite (this keeps
/// the test runner's per-class budget under control).</p>
///
/// <p><b>Permission requirement:</b> the create-namespace path requires
/// <code>%Admin_Manage:USE</code> on the test runner. If the runner lacks
/// this permission (probed empirically in
/// <method>OnBeforeOneTest</method>), the create-namespace dependent
/// tests gracefully skip via <code>$$$AssertSkipped</code> rather than
/// fail. The pure-validation tests (rejection paths) run unconditionally.</p>
///
/// <p><b>Cross-namespace independence assertion:</b>
/// <method>TestInstallIntoNamespaceCreatesPerNamespaceState</method>
/// captures <code>HSCUSTOM</code>'s <code>session-inspection</code>
/// <code>Provider</code> value before the test and verifies it is
/// unchanged after seeding <code>SATEST64</code> — this is the canonical
/// AC-5 architectural-decision test (per-namespace
/// <code>Config.Agent</code> rows are independent).</p>
Class SessionAgent.Test.MultiNamespaceInstallTest Extends %UnitTest.TestCase
{

/// <p>The temporary test namespace name. Underscore not allowed in
/// identifiers per project naming convention; chosen short for readability
/// in error messages and SQL probes.</p>
Parameter TESTNS = "SATEST64";

/// <p>A second namespace name reserved for the unmapped-package test —
/// this namespace gets created but does NOT get the package mapping, so
/// <method>InstallIntoNamespace</method> rejects it with the
/// operator-runnable <code>Create(...)</code> error. Distinct from
/// <code>TESTNS</code> because it does NOT need interop enabled (the
/// rejection happens before any <code>Ens.*</code> grant).</p>
Parameter TESTNSNOMAP = "SATEST64NM";

/// <p>Whether this test runner has create-namespace permission. Computed
/// once in <method>OnBeforeOneTest</method> and consulted by each test
/// that depends on the create path.</p>
Property HasCreatePermission As %Boolean [ InitialExpression = 0 ];

/// <p>Whether <code>TESTNS</code> is prepared (created + interop-enabled +
/// package-mapped). Set to 1 by <method>EnsureTestNamespacePrepared</method>
/// when prep succeeds. Tests check this before working against
/// <code>TESTNS</code>.</p>
Property PreparedTestNs As %Boolean [ InitialExpression = 0 ];

/// <p>Constructor — must accept <var>initvalue</var> and call
/// <code>##super(initvalue)</code> per project rule §"Critical Constructor
/// Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Set ..HasCreatePermission = 0
    Set ..PreparedTestNs = 0
    Quit $$$OK
}

/// <p>Per-test setup: probes for create-namespace permission and
/// (re)prepares the <code>TESTNS</code> namespace if needed. The
/// preparation is idempotent — if <code>TESTNS</code> already exists +
/// has interop enabled + has the package mapped, it is reused as-is
/// (sub-second). If any of those is missing, the helper performs the
/// missing setup steps (which can be slow on first run).</p>
Method OnBeforeOneTest() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        ; (1) Probe create-namespace permission via a probe-create-and-delete
        ; cycle on a unique probe-only name. The TESTNS path is independent —
        ; it only runs if the probe succeeds.
        Set $NAMESPACE = "%SYS"
        Set tProbeName = "SATEST64PROBE"
        If ##class(Config.Namespaces).Exists(tProbeName) {
            Do ##class(Config.Namespaces).Delete(tProbeName)
        }
        Set tProbeProps("Globals") = "USER"
        Set tProbeSC = ##class(Config.Namespaces).Create(tProbeName, .tProbeProps)
        If $$$ISOK(tProbeSC) {
            Set ..HasCreatePermission = 1
            Do ##class(Config.Namespaces).Delete(tProbeName)
        } Else {
            Set ..HasCreatePermission = 0
        }
        Set $NAMESPACE = tOrigNS

        ; (2) Prepare TESTNS if we have permission. Sub-second when already
        ; prepared; can take 30+ seconds on first prep (EnableNamespace).
        If ..HasCreatePermission {
            Set tPrepSC = ..EnsureTestNamespacePrepared()
            If $$$ISOK(tPrepSC) {
                Set ..PreparedTestNs = 1
            }
        }
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set ..HasCreatePermission = 0
        Set ..PreparedTestNs = 0
    }
    Quit tSC
}

/// <p>Per-test teardown: drops the unmapped-package test namespace
/// (<code>TESTNSNOMAP</code>) if it was created during the test. The
/// <code>TESTNS</code> interop namespace is intentionally left in place
/// across the suite to keep the test runner's per-class budget under
/// control — the operator removes it manually via the Mgmt Portal after
/// the suite completes (or via the SQL command documented at the end of
/// this class's docstring).</p>
Method OnAfterOneTest() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If ##class(Config.MapPackages).Exists(..#TESTNSNOMAP, "SessionAgent") {
            Do ##class(Config.MapPackages).Delete(..#TESTNSNOMAP, "SessionAgent")
        }
        If ##class(Config.Namespaces).Exists(..#TESTNSNOMAP) {
            If ##class(%Library.EnsembleMgr).IsEnsembleNamespace(..#TESTNSNOMAP) {
                Do ##class(%Library.EnsembleMgr).DisableNamespace(..#TESTNSNOMAP)
            }
            Do ##class(Config.Namespaces).Delete(..#TESTNSNOMAP)
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
    }
    Quit tSC
}

/// <p>AC-1 (validation #1) — invoke
/// <method>InstallIntoNamespace</method> with empty string; assert the
/// returned <code>%Status</code> is an error and references the
/// "cannot be empty" wording. Runs unconditionally — no namespace-create
/// dependency.</p>
Method TestInstallIntoNamespaceRejectsEmptyString()
{
    Set tSC = ##class(SessionAgent.Installer).InstallIntoNamespace("")
    Do $$$AssertEquals($$$ISERR(tSC), 1, "empty pNamespace returns ERROR status")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ "cannot be empty", "error text references 'cannot be empty': " _ tText)
    Quit
}

/// <p>AC-1 (validation #2) — invoke
/// <method>InstallIntoNamespace</method> with <code>"%SYS"</code>; assert
/// the returned <code>%Status</code> is an error and references
/// <code>%SYS</code>. Runs unconditionally.</p>
Method TestInstallIntoNamespaceRejectsSysNs()
{
    Set tSC = ##class(SessionAgent.Installer).InstallIntoNamespace("%SYS")
    Do $$$AssertEquals($$$ISERR(tSC), 1, "%SYS pNamespace returns ERROR status")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ "%SYS", "error text references %SYS: " _ tText)
    Quit
}

/// <p>AC-1 (validation #3) — invoke
/// <method>InstallIntoNamespace</method> with a guaranteed-non-existent
/// namespace; assert the returned <code>%Status</code> is an error and
/// references the namespace name. Runs unconditionally.</p>
Method TestInstallIntoNamespaceRejectsMissingNamespace()
{
    Set tBogusName = "NOTANAMESPACE64"
    Set tSC = ##class(SessionAgent.Installer).InstallIntoNamespace(tBogusName)
    Do $$$AssertEquals($$$ISERR(tSC), 1, "non-existent pNamespace returns ERROR status")
    Set tText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tText [ tBogusName, "error text references namespace name '" _ tBogusName _ "': " _ tText)
    Quit
}

/// <p>AC-2 — create the test namespace but do NOT map
/// <code>SessionAgent.PKG</code> to it; invoke
/// <method>InstallIntoNamespace</method>; assert the error text contains
/// the operator-runnable <code>Config.MapPackages.Create(...)</code> line
/// verbatim. Skips gracefully if the runner lacks create-namespace
/// permission. The unmapped-package check happens before the
/// <code>Ens.*</code> table grant, so this test does NOT need interop
/// enabled on <code>TESTNSNOMAP</code> — fast.</p>
Method TestInstallIntoNamespaceRejectsUnmappedPackage()
{
    If '..HasCreatePermission {
        Do $$$AssertSkipped("Test requires create-namespace permission; skipped on this runner")
        Quit
    }

    Set tOrigNS = $NAMESPACE
    Try {
        ; Create TESTNSNOMAP (no interop, no package mapping). Fast.
        Set $NAMESPACE = "%SYS"
        Set tProps("Globals") = "USER"
        Set tCreateSC = ##class(Config.Namespaces).Create(..#TESTNSNOMAP, .tProps)
        Set $NAMESPACE = tOrigNS
        If $$$ISERR(tCreateSC) {
            Do $$$AssertTrue(0, "Failed to create test namespace " _ ..#TESTNSNOMAP _ ": " _ $System.Status.GetErrorText(tCreateSC))
            Quit
        }

        ; Invoke InstallIntoNamespace — should reject with operator-runnable text.
        Set tSC = ##class(SessionAgent.Installer).InstallIntoNamespace(..#TESTNSNOMAP)
        Do $$$AssertEquals($$$ISERR(tSC), 1, "unmapped namespace returns ERROR status")
        Set tText = $System.Status.GetErrorText(tSC)
        Do $$$AssertTrue(tText [ "is not mapped", "error text says 'is not mapped': " _ tText)
        Do $$$AssertTrue(tText [ "Config.MapPackages", "error text contains Config.MapPackages: " _ tText)
        Do $$$AssertTrue(tText [ ..#TESTNSNOMAP, "error text references the namespace name: " _ tText)
        Do $$$AssertTrue(tText [ "SessionAgent", "error text references the package name: " _ tText)
    }
    Catch ex {
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }

    Set $NAMESPACE = tOrigNS
    Quit
}

/// <p>AC-3 + AC-5 — full happy-path: against a pre-prepared
/// <code>TESTNS</code>, invoke <method>InstallIntoNamespace</method> and
/// assert the full per-namespace install state plus cross-namespace
/// independence of <code>Config.Agent</code> rows.</p>
///
/// <p>Skips gracefully if the runner lacks create-namespace permission
/// or if <code>TESTNS</code> failed to prepare.</p>
Method TestInstallIntoNamespaceCreatesPerNamespaceState()
{
    If '..HasCreatePermission {
        Do $$$AssertSkipped("Test requires create-namespace permission; skipped on this runner")
        Quit
    }
    If '..PreparedTestNs {
        Do $$$AssertSkipped("Test requires SATEST64 prepared (interop-enabled + package-mapped); EnsureTestNamespacePrepared failed — see runner permissions or EnableNamespace timing")
        Quit
    }

    Set tOrigNS = $NAMESPACE
    Try {
        ; Capture HSCUSTOM's session-inspection Provider before the test —
        ; the cross-namespace independence assertion compares this value
        ; afterward to confirm SATEST64 changes did not bleed across.
        Set tHsBefore = ..GetHSCustomSessionInspectionProvider()

        ; Run InstallIntoNamespace.
        Set tInstallSC = ##class(SessionAgent.Installer).InstallIntoNamespace(..#TESTNS)
        Do $$$AssertStatusOK(tInstallSC, "InstallIntoNamespace OK on prepared TESTNS")

        ; (a) RBAC role exists. Roles are global (not per-namespace).
        Set $NAMESPACE = "%SYS"
        Do $$$AssertTrue(##class(Security.Roles).Exists("SessionAgent_ReadOnly"), "SessionAgent_ReadOnly role exists after InstallIntoNamespace")
        Set $NAMESPACE = tOrigNS

        ; (b) Config.Agent rows are seeded in the test namespace.
        Set $NAMESPACE = ..#TESTNS
        Set tCount = ..CountAgentRows()
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(tCount >= 2, "SATEST64 has >= 2 agent rows (seed shape) — actual: " _ tCount)

        ; (c) Cross-namespace independence: flip SATEST64's
        ; session-inspection Provider to "anthropic"; verify HSCUSTOM's
        ; Provider is still tHsBefore (the per-namespace AC-5 invariant).
        Set $NAMESPACE = ..#TESTNS
        Do ..SetSessionInspectionProvider("anthropic")
        Set $NAMESPACE = tOrigNS

        Set tHsAfter = ..GetHSCustomSessionInspectionProvider()
        Do $$$AssertEquals(tHsAfter, tHsBefore, "HSCUSTOM session-inspection Provider unchanged after SATEST64 flip — per-namespace invariant holds (before='" _ tHsBefore _ "', after='" _ tHsAfter _ "')")

        Set $NAMESPACE = ..#TESTNS
        Set tSatestProvider = ..GetSessionInspectionProvider()
        Set $NAMESPACE = tOrigNS
        Do $$$AssertEquals(tSatestProvider, "anthropic", "SATEST64 session-inspection Provider is 'anthropic' (the test set it)")
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Set $NAMESPACE = tOrigNS
    Quit
}

/// <p>AC-4 / AC-7 #3 — idempotency. Run
/// <method>InstallIntoNamespace</method> twice on the same prepared
/// namespace and assert (a) both calls return <code>$$$OK</code>, (b) the
/// row count in <code>Config.Agent</code> is identical after the second
/// call, (c) the Task Manager entry count for the SessionAgent tasks is
/// identical.</p>
///
/// <p>Skips gracefully if the runner lacks create-namespace permission
/// or if <code>TESTNS</code> failed to prepare.</p>
Method TestInstallIntoNamespaceIdempotency()
{
    If '..HasCreatePermission {
        Do $$$AssertSkipped("Test requires create-namespace permission; skipped on this runner")
        Quit
    }
    If '..PreparedTestNs {
        Do $$$AssertSkipped("Test requires SATEST64 prepared (interop-enabled + package-mapped)")
        Quit
    }

    Set tOrigNS = $NAMESPACE
    Try {
        ; First install — capture row count + task count.
        Set tFirstSC = ##class(SessionAgent.Installer).InstallIntoNamespace(..#TESTNS)
        Do $$$AssertStatusOK(tFirstSC, "first InstallIntoNamespace OK")

        Set $NAMESPACE = ..#TESTNS
        Set tFirstAgentCount = ..CountAgentRows()
        Set $NAMESPACE = tOrigNS
        Set tFirstTaskCount = ..CountSessionAgentTasks()

        ; Second install — re-run on the same namespace. Should be a no-op.
        Set tSecondSC = ##class(SessionAgent.Installer).InstallIntoNamespace(..#TESTNS)
        Do $$$AssertStatusOK(tSecondSC, "second InstallIntoNamespace OK (idempotency contract)")

        Set $NAMESPACE = ..#TESTNS
        Set tSecondAgentCount = ..CountAgentRows()
        Set $NAMESPACE = tOrigNS
        Set tSecondTaskCount = ..CountSessionAgentTasks()

        Do $$$AssertEquals(tSecondAgentCount, tFirstAgentCount, "Config.Agent row count unchanged after second InstallIntoNamespace (first=" _ tFirstAgentCount _ ", second=" _ tSecondAgentCount _ ")")
        Do $$$AssertEquals(tSecondTaskCount, tFirstTaskCount, "SessionAgent Task Manager entry count unchanged after second InstallIntoNamespace (first=" _ tFirstTaskCount _ ", second=" _ tSecondTaskCount _ ")")
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Set $NAMESPACE = tOrigNS
    Quit
}

/// <p>Story 11.3 AC-5 — verify <method>InstallIntoNamespace</method>
/// programmatically copies the Story 10.7 vendored static bundle from
/// <code>${cspdir}/hscustom/sa-static/</code> to
/// <code>${cspdir}/satest64/sa-static/</code>. Asserts that the canonical
/// per-namespace asset <code>marked.min.js</code> exists at the expected
/// target path after the install runs.</p>
///
/// <p>Skips gracefully if the runner lacks create-namespace permission
/// or if <code>TESTNS</code> failed to prepare. Also skips gracefully if
/// the source bundle directory is not present on this IRIS instance —
/// e.g., a fresh checkout where the original Story 10.7 IPM
/// <code>&lt;FileCopy&gt;</code> has not run yet (the helper logs the
/// bail-out and returns OK; the install still succeeds, but no files
/// arrive at the target).</p>
Method TestInstallIntoNamespaceCopiesStaticBundle()
{
    If '..HasCreatePermission {
        Do $$$AssertSkipped("Test requires create-namespace permission; skipped on this runner")
        Quit
    }
    If '..PreparedTestNs {
        Do $$$AssertSkipped("Test requires SATEST64 prepared (interop-enabled + package-mapped)")
        Quit
    }

    Set tOrigNS = $NAMESPACE
    Try {
        ; Resolve canonical paths cross-platform — same strategy as
        ; SessionAgent.Installer:CopyStaticBundleToNamespace.
        Set tCspRoot = ##class(%File).SubDirectoryName($System.Util.InstallDirectory(), "csp", 1)
        Set tSourceDir = ##class(%File).SubDirectoryName(##class(%File).SubDirectoryName(tCspRoot, "hscustom", 1), "sa-static", 1)
        Set tTargetDir = ##class(%File).SubDirectoryName(##class(%File).SubDirectoryName(tCspRoot, $ZConvert(..#TESTNS, "L"), 1), "sa-static", 1)

        ; Skip if the source bundle is not present (operator never ran the
        ; original Story 10.7 IPM <FileCopy>).
        If '##class(%File).DirectoryExists(tSourceDir) {
            Do $$$AssertSkipped("Source bundle directory not present at " _ tSourceDir _ " — Story 10.7 <FileCopy> may not have fired in HSCUSTOM yet")
            Quit
        }

        ; Run InstallIntoNamespace — the bundle-copy step is the last action.
        Set tInstallSC = ##class(SessionAgent.Installer).InstallIntoNamespace(..#TESTNS)
        Do $$$AssertStatusOK(tInstallSC, "InstallIntoNamespace OK on prepared TESTNS")

        ; Assert target directory exists post-install.
        Do $$$AssertTrue(##class(%File).DirectoryExists(tTargetDir), "Target bundle directory exists after install: " _ tTargetDir)

        ; Assert the canonical marked.min.js asset arrived at the target.
        Set tMarkedPath = ##class(%File).NormalizeFilename("marked.min.js", tTargetDir)
        Do $$$AssertTrue(##class(%File).Exists(tMarkedPath), "marked.min.js exists at " _ tMarkedPath)

        ; Assert at least 2 files were copied (idempotence smoke — the bundle
        ; is 13 files in v1.0.1; tolerate variance for future bundle drift).
        Set tFileCount = 0
        Set tRs = ##class(%ResultSet).%New("%File:FileSet")
        Do tRs.Execute(tTargetDir, "*", "Name", 1)
        While tRs.Next() {
            If '##class(%File).DirectoryExists(tRs.Get("Name")) {
                Set tFileCount = tFileCount + 1
            }
        }
        Do tRs.Close()
        Do $$$AssertTrue(tFileCount >= 2, "Target directory contains >= 2 files (actual: " _ tFileCount _ ")")
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Set $NAMESPACE = tOrigNS
    Quit
}

/// <p>Helper — ensures <code>TESTNS</code> is prepared for the integration
/// tests (created + interop-enabled + package-mapped). Idempotent: if
/// each prerequisite is already met, the method is a no-op (sub-second).
/// Returns <code>%Status</code>; restores <code>$NAMESPACE</code> on
/// every path.</p>
///
/// <p>The first invocation on a fresh IRIS instance can take 30+ seconds
/// because <method>%Library.EnsembleMgr.EnableNamespace</method> performs
/// significant setup work. Subsequent test runs (across MCP test runner
/// invocations) reuse the existing namespace via the
/// <code>IsEnsembleNamespace</code> short-circuit.</p>
Method EnsureTestNamespacePrepared() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"

        ; (1) Create the namespace if absent.
        If '##class(Config.Namespaces).Exists(..#TESTNS) {
            Set tProps("Globals") = "USER"
            Set tSC = ##class(Config.Namespaces).Create(..#TESTNS, .tProps)
            If $$$ISERR(tSC) {
                Set $NAMESPACE = tOrigNS
                Quit
            }
        }

        ; (2) Enable interop if not already enabled. This is the slow step
        ; (30+ seconds on first run, sub-second when already enabled).
        If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(..#TESTNS) {
            Set tSC = ##class(%Library.EnsembleMgr).EnableNamespace(..#TESTNS, 0)
            If $$$ISERR(tSC) {
                Set $NAMESPACE = tOrigNS
                Quit
            }
        }

        ; (3) Map SessionAgent.PKG to the namespace if not mapped.
        If '##class(Config.MapPackages).Exists(..#TESTNS, "SessionAgent") {
            Set tMapProps("Database") = "HSCUSTOM"
            Set tSC = ##class(Config.MapPackages).Create(..#TESTNS, "SessionAgent", .tMapProps)
            If $$$ISERR(tSC) {
                Set $NAMESPACE = tOrigNS
                Quit
            }
        }

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Helper — counts rows in the current namespace's
/// <code>SessionAgent_Config.Agent</code> table. Defaults to 0 if the
/// table is not visible (e.g., if seeding silently failed).</p>
Method CountAgentRows() As %Integer [ Private ]
{
    Set tCount = 0
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM SessionAgent_Config.Agent")
        If $$$ISERR(tSC) Quit
        Set tRS = tStmt.%Execute()
        If tRS.%Next() {
            Set tCount = tRS.%Get("Cnt")
        }
    }
    Catch ex {
        Set tCount = -1
    }
    Quit tCount
}

/// <p>Helper — reads the <code>session-inspection</code> agent's
/// <code>Provider</code> in the current namespace.</p>
Method GetSessionInspectionProvider() As %String [ Private ]
{
    Set tProvider = ""
    Try {
        Set tAgent = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
        If $IsObject(tAgent) {
            Set tProvider = tAgent.Provider
        }
    }
    Catch ex {
        Set tProvider = "<exception:" _ ex.DisplayString() _ ">"
    }
    Quit tProvider
}

/// <p>Helper — sets the current namespace's <code>session-inspection</code>
/// agent <code>Provider</code> to <var>pProvider</var>. Used by the
/// cross-namespace independence assertion.</p>
Method SetSessionInspectionProvider(pProvider As %String) [ Private ]
{
    Try {
        Set tAgent = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen("session-inspection")
        If $IsObject(tAgent) {
            Set tAgent.Provider = pProvider
            Do tAgent.%Save()
        }
    }
    Catch ex {
    }
    Quit
}

/// <p>Helper — reads HSCUSTOM's <code>session-inspection</code>
/// <code>Provider</code> with explicit namespace switch + restore. Safe to
/// call from any namespace.</p>
Method GetHSCustomSessionInspectionProvider() As %String [ Private ]
{
    Set tProvider = ""
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "HSCUSTOM"
        Set tProvider = ..GetSessionInspectionProvider()
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tProvider = "<exception:" _ ex.DisplayString() _ ">"
    }
    Quit tProvider
}

/// <p>Helper — counts <code>%SYS.Task</code> entries scoped to the test
/// namespace whose <code>Name</code> matches the SessionAgent
/// orchestrator-scheduled task names. Used by the idempotency assertion.</p>
Method CountSessionAgentTasks() As %Integer [ Private ]
{
    Set tCount = 0
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("SELECT COUNT(*) AS Cnt FROM %SYS.Task WHERE NameSpace = ? AND Name %STARTSWITH 'SessionAgent.'")
        If $$$ISERR(tSC) {
            Set $NAMESPACE = tOrigNS
            Quit
        }
        Set tRS = tStmt.%Execute(..#TESTNS)
        If tRS.%Next() {
            Set tCount = tRS.%Get("Cnt")
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tCount = -1
    }
    Quit tCount
}

/// <p>Operator-facing cleanup helper — drops <code>TESTNS</code> +
/// <code>TESTNSNOMAP</code> after the test suite has finished. Run this
/// manually after the integration test run to remove the persistent test
/// fixture namespace:</p>
///
/// <pre>
/// USER&gt; Do ##class(SessionAgent.Test.MultiNamespaceInstallTest).CleanupTestNamespaces()
/// </pre>
ClassMethod CleanupTestNamespaces() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        For tNs = "SATEST64", "SATEST64NM", "SATEST64PROBE" {
            If ##class(Config.MapPackages).Exists(tNs, "SessionAgent") {
                Do ##class(Config.MapPackages).Delete(tNs, "SessionAgent")
                Write !,"Deleted package mapping for ", tNs
            }
            If ##class(Config.Namespaces).Exists(tNs) {
                If ##class(%Library.EnsembleMgr).IsEnsembleNamespace(tNs) {
                    Do ##class(%Library.EnsembleMgr).DisableNamespace(tNs)
                    Write !,"Disabled interop on ", tNs
                }
                Do ##class(Config.Namespaces).Delete(tNs)
                Write !,"Deleted namespace ", tNs
            }
        }
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
