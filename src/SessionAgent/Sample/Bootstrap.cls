Include Ensemble

/// <p>Operator-invoked installer / uninstaller for the Story 3.9 sample
/// interop production. Not wired into the IPM install hook — the sample
/// production is intentionally dormant until an operator runs
/// <method>InstallProduction</method>.</p>
///
/// <p>Idempotent: re-running InstallProduction on an existing install
/// re-loads the production definition from XData (stale items are
/// dropped + re-added). Re-running UninstallProduction when no production
/// is installed is a no-op.</p>
Class SessionAgent.Sample.Bootstrap Extends %RegisteredObject
{

Parameter PRODUCTIONNAME As %String = "SessionAgent.Sample.Production";

/// <p>Install (or re-install) the sample production. Calls
/// <code>Ens.Config.Production.LoadFromClass()</code> which parses the
/// XData ProductionDefinition + saves the Ens.Config.Production row +
/// child Ens.Config.Item rows. After successful load, logs a one-line
/// operator instruction to current device.</p>
///
/// <p>Does NOT auto-start the production — operators decide when to start
/// it (typically via <code>Do ##class(Ens.Director).StartProduction("SessionAgent.Sample.Production")</code>
/// or via the Mgmt Portal Production Configuration page). The sibling
/// <method>StartProductionIfStopped</method> helper covers the
/// programmatic-start path used by tests + by the lead during the
/// walkthrough re-run.</p>
ClassMethod InstallProduction() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tProdName = ..#PRODUCTIONNAME

        ; Verify the production class compiles + exists in this namespace
        ; before attempting LoadFromClass (better diagnostic if the install
        ; ran in a namespace where SessionAgent.* isn't mapped).
        If '##class(%Dictionary.CompiledClass).%ExistsId(tProdName) {
            Set tSC = $$$ERROR($$$EnsErrGeneral, "Production class "_tProdName_" not found in current namespace ("_$Namespace_") — verify SessionAgent.* package mapping")
            Quit
        }

        Set tSC = ##class(Ens.Config.Production).LoadFromClass(tProdName)
        If $$$ISERR(tSC) {
            Write !, "[SessionAgent.Sample.Bootstrap] InstallProduction FAILED: ", $System.Status.GetErrorText(tSC), !
            Quit
        }

        Write !, "[SessionAgent.Sample.Bootstrap] Sample production installed: ", tProdName, !
        Write "  Start it: Do ##class(Ens.Director).StartProduction(""", tProdName, """)", !
        Write "  Run scenarios via:", !
        Write "    Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario(""none"")", !
        Write "    Do ##class(SessionAgent.Sample.BS.OrderIngest).RunScenario(""businessOperationFailure"")", !
        Write "  Uninstall later: Do ##class(SessionAgent.Sample.Bootstrap).UninstallProduction()", !
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Stop + remove the sample production. Steps:</p>
/// <ol>
///   <li>If a production is currently running and it is OUR production,
///       stop it (with a 10s graceful timeout).</li>
///   <li>Delete the Ens.Config.Production row + cascade-delete child
///       Ens.Config.Item rows.</li>
/// </ol>
/// <p>Returns $$$OK if the production was uninstalled OR was never
/// installed in the first place. Returns the underlying error if a stop
/// or delete failed.</p>
ClassMethod UninstallProduction() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tProdName = ..#PRODUCTIONNAME

        ; Stop if running.
        Set tStatusSC = ##class(Ens.Director).GetProductionStatus(.tRunningName, .tState)
        If $$$ISOK(tStatusSC) && (tRunningName = tProdName) && (tState '= $$$eProductionStateStopped) {
            Set tStopSC = ##class(Ens.Director).StopProduction(10, 1)
            If $$$ISERR(tStopSC) {
                Write !, "[SessionAgent.Sample.Bootstrap] WARNING: failed to stop production: ", $System.Status.GetErrorText(tStopSC), !
                ; continue — deletion may still succeed if process is gone
            }
        }

        ; Delete the production row if it exists.
        If ##class(Ens.Config.Production).%ExistsId(tProdName) {
            Set tDelSC = ##class(Ens.Config.Production).%DeleteId(tProdName)
            If $$$ISERR(tDelSC) {
                Set tSC = tDelSC
                Write !, "[SessionAgent.Sample.Bootstrap] UninstallProduction FAILED: ", $System.Status.GetErrorText(tDelSC), !
                Quit
            }
            Write !, "[SessionAgent.Sample.Bootstrap] Sample production uninstalled: ", tProdName, !
        } Else {
            Write !, "[SessionAgent.Sample.Bootstrap] No production to uninstall (", tProdName, " not registered)", !
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Start the sample production if it is not already running. Returns
/// $$$OK if it was already running OR successfully started; returns the
/// error if start failed. Used by tests to bring the production up
/// without forcing operators to remember the Director invocation.</p>
ClassMethod StartProductionIfStopped() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tProdName = ..#PRODUCTIONNAME

        Set tStatusSC = ##class(Ens.Director).GetProductionStatus(.tRunningName, .tState)
        If $$$ISERR(tStatusSC) {
            Set tSC = tStatusSC
            Quit
        }

        If (tRunningName = tProdName) && (tState = $$$eProductionStateRunning) {
            ; Already running — nothing to do.
            Quit
        }

        ; If a DIFFERENT production is running, stop it first (per Ens.Production.TestStart pattern).
        If (tRunningName '= "") && (tRunningName '= tProdName) && (tState '= $$$eProductionStateStopped) {
            Set tStopSC = ##class(Ens.Director).StopProduction(10, 1)
            If $$$ISERR(tStopSC) {
                Set tSC = tStopSC
                Quit
            }
        }

        Set tSC = ##class(Ens.Director).StartProduction(tProdName)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
