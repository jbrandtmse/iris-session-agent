/// <p>Utility class for the <code>SessionAgent.Test</code> package.
/// Provides shared helpers used across multiple test suites.</p>
///
/// <p><b>AC-1 (Story 13.1 / AI-2 carry-forward).</b>
/// <method>RegressionSweepCount</method> encapsulates the canonical
/// numerical-MAX SQL probe against <code>%UnitTest_Result.TestMethod</code>.
/// Subsequent Epic-13 stories MUST call this helper rather than repeating
/// the SQL inline. The numerical-MAX form avoids the lexicographic-
/// collation trap documented in
/// <code>.claude/rules/object-script-testing.md §"SQL-probe-as-ground-truth"</code>.</p>
Class SessionAgent.Test.Util
{

/// <p>Return the aggregate test-pass counts for the latest run of every
/// <code>SessionAgent.Test.*</code> test class via the canonical
/// numerical-MAX SQL probe (AC-1 Story 13.1 / AI-2 carry-forward).</p>
///
/// <p>Uses a three-way JOIN that:</p>
/// <ol>
/// <li>Extracts the numeric run-id via <code>$PIECE(ID,'||',1)+0</code>
///   so MAX() compares by integer magnitude, not by lexicographic order.</li>
/// <li>Anchors the MAX() aggregate to classes that actually have
///   <code>TestMethod</code> rows in the target run (avoids orphaned
///   <code>TestCase</code> rows from partial runs).</li>
/// </ol>
///
/// <p>Output parameters are populated even on SQL error (defaulting to 0)
/// so callers can always read the values safely.</p>
ClassMethod RegressionSweepCount(Output pTotal As %Integer, Output pPassed As %Integer, Output pFailed As %Integer) As %Status
{
    Set tSC = $$$OK
    Set pTotal = 0, pPassed = 0, pFailed = 0
    &sql(SELECT COUNT(*),
                SUM(CASE WHEN tm.Status=1 THEN 1 ELSE 0 END),
                SUM(CASE WHEN tm.Status=0 THEN 1 ELSE 0 END)
         INTO :pTotal, :pPassed, :pFailed
         FROM %UnitTest_Result.TestMethod tm
         JOIN %UnitTest_Result.TestCase tc ON tm.TestCase = tc.ID
         JOIN (SELECT %EXACT(tc2.Name) AS ClassName,
                      MAX($PIECE(tc2.ID,'||',1)+0) AS MaxRunIdx
               FROM %UnitTest_Result.TestMethod tm2
               JOIN %UnitTest_Result.TestCase tc2 ON tm2.TestCase = tc2.ID
               WHERE %EXACT(tc2.Name) LIKE 'SessionAgent.Test.%'
               GROUP BY %EXACT(tc2.Name)) latest
           ON %EXACT(tc.Name) = latest.ClassName
          AND ($PIECE(tc.ID,'||',1)+0) = latest.MaxRunIdx
         WHERE %EXACT(tc.Name) LIKE 'SessionAgent.Test.%')
    If SQLCODE < 0 {
        Set tSC = $$$ERROR($$$SQLError, SQLCODE, %msg)
    }
    Quit tSC
}

}
