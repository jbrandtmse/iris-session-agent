/// <p>Story 9.1 Task-0 probe — verifies that <code>%OnAfterSave</code>
/// issuing a direct SQL UPDATE against the same row that just saved does
/// NOT re-fire <code>%OnAfterSave</code> on IRIS 2024.1. Story 9.2's
/// recursion-safe Confidence-recompute trigger depends on this guarantee.</p>
///
/// <p>This is a <b>%Persistent probe</b>, NOT a <code>%UnitTest.TestCase</code> —
/// the probe needs persistence-layer trigger behavior (the OREF-graph
/// <code>%Save()</code> dispatching <code>%OnAfterSave</code>), not the
/// %UnitTest assertion macros. The companion <code>RunProbe()</code>
/// ClassMethod returns a structured <code>%DynamicObject</code> for
/// verbatim Completion-Notes capture.</p>
///
/// <p><b>Fire-count instrumentation.</b> The <code>%OnAfterSave</code>
/// trigger increments process-private global
/// <code>^||SessionAgentOnAfterSaveProbeCount</code> on every entry. The
/// probe expects fire count = <code>1</code> after a single
/// <code>..%Save()</code>: the outer save fires <code>%OnAfterSave</code>
/// once, the inner direct-SQL UPDATE bypasses the OREF persistence layer's
/// trigger dispatch and therefore does NOT recurse.</p>
///
/// <p><b>Subscript naming.</b> Per project rule "Process-Private Globals" —
/// <code>^||SessionAgentOnAfterSaveProbeCount</code> uses camelCase, no
/// hyphens (the <code>-</code> char is the concatenation operator in
/// ObjectScript and would parse as subtraction at the subscript site).</p>
///
/// <p><b>Property naming.</b> Per project rule "Property Test* Test-Method-
/// Discovery Shadow Trap" — properties are <code>A</code> and <code>B</code>
/// (no <code>Test*</code> prefix), so even if this class were misread as a
/// %UnitTest subclass by a future test runner, no auto-generated datatype
/// helpers would shadow as phantom test methods.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li>Story 9.1 AC-1 — verbatim probe spec.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md §"Carry-forward Task-0 probes" Epic 9 entry 5</a> — non-recursion guarantee dependency for Story 9.2.</li>
/// </ul>
Class SessionAgent.Test.OnAfterSaveRecursionProbe Extends %Persistent
{

/// <p>Probe scalar #1 — set by <code>RunProbe()</code> to <code>5</code>
/// before the outer <code>%Save()</code>. The <code>%OnAfterSave</code>
/// trigger reads this value and writes it back via direct SQL UPDATE.</p>
Property A As %Integer;

/// <p>Probe scalar #2 — set by <code>RunProbe()</code> to <code>10</code>
/// before the outer <code>%Save()</code>. Not touched by the
/// <code>%OnAfterSave</code> trigger; present so the row has more than
/// one column to round-trip.</p>
Property B As %Integer;

/// <p>Trigger callback. Increments the fire-count PPG, then issues a
/// direct SQL UPDATE on the same row. If the persistence layer
/// re-dispatches <code>%OnAfterSave</code> in response to the inner
/// UPDATE, this method re-enters and the count climbs above 1 — that
/// signals recursion, and Story 9.2's design must be escalated per
/// AC-4.</p>
Method %OnAfterSave(insert As %Boolean) As %Status
{
    Set ^||SessionAgentOnAfterSaveProbeCount = $Get(^||SessionAgentOnAfterSaveProbeCount, 0) + 1
    ; Issue direct SQL UPDATE on the row that just saved. Per AC-1, this
    ; is the precise scenario Story 9.2 needs verified — direct SQL
    ; bypasses the OREF persistence layer and SHOULD NOT re-fire
    ; %OnAfterSave on 2024.1.
    Set tId = ..%Id()
    Set tA = ..A
    &sql(UPDATE SessionAgent_Test.OnAfterSaveRecursionProbe SET A = :tA WHERE %ID = :tId)
    Quit $$$OK
}

/// <p>Probe entry point. Resets the fire-count PPG, instantiates a row,
/// sets <code>A=5, B=10</code>, calls <code>..%Save()</code>, captures
/// the post-save fire count, and returns a structured
/// <code>%DynamicObject</code> for verbatim Completion-Notes capture.
/// Cleans up the row via <code>%KillExtent()</code> before returning so
/// re-running the probe does not accumulate rows or fire counts.</p>
ClassMethod RunProbe() As %DynamicObject
{
    Set tResult = {}
    Try {
        ; Reset instrumentation
        Kill ^||SessionAgentOnAfterSaveProbeCount
        Set ^||SessionAgentOnAfterSaveProbeCount = 0

        ; Clean any leftover rows from a prior failed probe
        Do ..%KillExtent()

        ; Outer save — expected to fire %OnAfterSave exactly once.
        Set tObj = ..%New()
        Set tObj.A = 5
        Set tObj.B = 10
        Set tSC = tObj.%Save()
        Set tResult."save_ok" = $$$ISOK(tSC)
        Set tResult."save_status_text" = $System.Status.GetErrorText(tSC)
        Set tResult."row_id" = tObj.%Id()

        ; Capture fire count
        Set tCount = $Get(^||SessionAgentOnAfterSaveProbeCount, 0)
        Set tResult."fire_count" = tCount
        Set tResult."recursion_detected" = $Select(tCount > 1: 1, 1: 0)
        Set tResult."expected_fire_count" = 1

        ; Verbatim verdict for AC-1 evidence shape
        If tCount = 1 {
            Set tResult."verdict" = "PASS — %OnAfterSave fired exactly once; direct SQL UPDATE on same row did NOT re-fire trigger."
        } ElseIf tCount > 1 {
            Set tResult."verdict" = "FAIL — recursion detected on 2024.1. Escalate per Story 9.1 AC-4."
        } Else {
            Set tResult."verdict" = "FAIL — %OnAfterSave never fired (expected 1)."
        }

        ; Cleanup
        Do ..%KillExtent()
        Kill ^||SessionAgentOnAfterSaveProbeCount
    }
    Catch ex {
        Set tResult."error" = ex.DisplayString()
        Set tResult."verdict" = "ERROR — exception during probe."
    }
    Quit tResult
}

Storage Default
{
<Data name="OnAfterSaveRecursionProbeDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>A</Value>
</Value>
<Value name="3">
<Value>B</Value>
</Value>
</Data>
<DataLocation>^SessionAge60F7.OnAfterSaveBD0BD</DataLocation>
<DefaultData>OnAfterSaveRecursionProbeDefaultData</DefaultData>
<IdLocation>^SessionAge60F7.OnAfterSaveBD0BD</IdLocation>
<IndexLocation>^SessionAge60F7.OnAfterSaveBD0BI</IndexLocation>
<StreamLocation>^SessionAge60F7.OnAfterSaveBD0BS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
