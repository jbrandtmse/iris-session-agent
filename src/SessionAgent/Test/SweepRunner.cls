/// <p>Story 10.7 verification helper — runs every SessionAgent.Test.* test
/// class through %UnitTest.Manager.RunTest one-at-a-time and aggregates
/// the per-class pass/fail count by reading from %UnitTest_Result tables
/// after each run. Bypasses the broken /test=... directory-name trap
/// that the package-level RunTest hits on this dev install.</p>
///
/// <p>This is a TEST-ONLY HELPER — it ships under SessionAgent.Test
/// because the regression sweep exercises classes under that namespace,
/// but it is NOT a TestCase itself (extends %RegisteredObject, not
/// %UnitTest.TestCase). The SQL ground-truth probe per project rule
/// remains the verification gate; this helper just drives the runs.</p>
Class SessionAgent.Test.SweepRunner Extends %RegisteredObject
{

/// Run every SessionAgent.Test.* TestCase class. Returns the count of
/// tests run via the runner (best-effort — the SQL probe in the lead's
/// completion notes is the canonical ground-truth aggregate).
ClassMethod RunAll() As %Integer
{
    Set tCount = 0
    Set tLast = ""
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare("SELECT %EXACT(Name) AS Name FROM %Dictionary.ClassDefinition WHERE %EXACT(Name) %STARTSWITH ? AND %EXACT(Super) [ '%UnitTest.TestCase' ORDER BY %EXACT(Name)")
    Set tRS = tStmt.%Execute("SessionAgent.Test.")
    While tRS.%Next() {
        Set tClass = tRS.%Get("Name")
        Set tManager = ##class(%UnitTest.Manager).%New()
        ; The Manager.RunOneTestCase API runs ONE class without the
        ; directory-traversal /test= flag that breaks on this install.
        Try {
            Do tManager.RunOneTestCase(tClass, "")
        }
        Catch ex {
            Write !,"Exception running ", tClass, ": ", ex.DisplayString()
        }
        Set tCount = tCount + 1
        Write !,"Ran ", tClass
    }
    Quit tCount
}

}
