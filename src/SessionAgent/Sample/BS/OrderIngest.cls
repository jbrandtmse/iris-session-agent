/// <p>Sample adapterless Business Service. Has no inbound adapter — instead
/// operators (or the Story 3.9 test class) invoke the
/// <method>RunScenario</method> ClassMethod directly. The BS still extends
/// <class>Ens.BusinessService</class> so it participates in the production
/// graph + audit trail; it simply skips the
/// adapter → <method>OnProcessInput</method> wiring.</p>
///
/// <p>Implementation pattern: <method>RunScenario</method> calls
/// <method>Ens.Director.CreateBusinessService</method> (per
/// <code>irislib/Ens/Director.cls</code> line 1401) to obtain a properly
/// initialised BS instance with the right <code>%ConfigName</code> +
/// SessionId scaffolding, builds an
/// <class>SessionAgent.Sample.Msg.OrderRequest</class> with realistic seed
/// data + the requested error-injection mode tagged on the
/// <property>ErrorMode</property> property (the signal travels on the
/// message body itself because BPs/BOs run in dedicated jobs and cannot
/// see the operator-process's process-private globals), then calls
/// <method>..SendRequestAsync</method> on the BS instance to dispatch
/// into the OrderRouter BP.</p>
///
/// <p>Scenarios:
/// <ul>
///   <li><b>none</b> — happy path; 3 line items; expects Approved.</li>
///   <li><b>businessProcessFailure</b> — validator unconditionally
///       rejects.</li>
///   <li><b>businessOperationFailure</b> — both BOs throw injected
///       errors.</li>
///   <li><b>partialSuccess</b> — SqlPersist succeeds; FilePublish throws.</li>
/// </ul>
/// </p>
Class SessionAgent.Sample.BS.OrderIngest Extends Ens.BusinessService
{

/// Configured target dispatch name for the routing BP. Must match the
/// item name used in Bootstrap's production XData.
Parameter ROUTERTARGET As %String = "SessionAgent.Sample.BP.OrderRouter";

/// <p>Adapterless BS — never called by an adapter. Returns
/// <code>$$$NotImplemented</code> per the parent's contract; real entry
/// is via <method>RunScenario</method>.</p>
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
{
    Quit $$$ERROR($$$NotImplemented)
}

/// <p>Operator-invoked entry point. Dispatches a single fresh
/// OrderRequest into the production with the requested error-injection
/// mode. Returns <code>$$$OK</code> on successful dispatch (BO/BP errors
/// propagate through the trace, not the return value); errors here
/// indicate either the production is not running or the BS config item is
/// disabled.</p>
///
/// <p>The third output parameter <var>pSessionId</var> receives the
/// Ens.MessageHeader.SessionId value the dispatch was assigned to —
/// callers (and the test class) use this to query the trace.</p>
ClassMethod RunScenario(pErrorMode As %String = "none", pConfigName As %String = "SessionAgent.Sample.BS.OrderIngest", Output pSessionId As %String = "") As %Status
{
    Set tSC = $$$OK
    Set pSessionId = ""

    Try {
        ; Validate pErrorMode against the supported set.
        If '$ListFind($ListBuild("none","businessProcessFailure","businessOperationFailure","partialSuccess"), pErrorMode) {
            Set tSC = $$$ERROR($$$EnsErrGeneral, "Unsupported pErrorMode: '"_pErrorMode_"'. Allowed: none, businessProcessFailure, businessOperationFailure, partialSuccess.")
            Quit
        }

        ; Note: the error-mode signal travels on the OrderRequest body
        ; itself (ErrorMode property) — we cannot use a process-private
        ; global because BPs/BOs run in their own jobs (separate
        ; processes from the operator-invoked caller). Setting on the
        ; request below in buildOrderRequest.

        ; Create the BS instance via Director (the canonical adapterless
        ; entry point per irislib/Ens/Director.cls line 1401).
        Set tBSCreateSC = ##class(Ens.Director).CreateBusinessService(pConfigName, .tBS)
        If $$$ISERR(tBSCreateSC) {
            Set tSC = tBSCreateSC
            Quit
        }
        If '$IsObject(tBS) {
            Set tSC = $$$ERROR($$$EnsErrGeneral, "Failed to instantiate BusinessService '"_pConfigName_"'")
            Quit
        }

        ; Build a realistic OrderRequest. Different scenarios get slightly
        ; different shapes for richer inspection-agent storytelling.
        Set tRequest = ..buildOrderRequest(pErrorMode)

        ; Dispatch async into the routing BP.
        Set tDispatchSC = tBS.SendRequestAsync(..#ROUTERTARGET, tRequest)

        ; Capture the SessionId regardless of dispatch outcome — the trace
        ; row(s) are present even on dispatch failure.
        Set pSessionId = tBS.%SessionId

        If $$$ISERR(tDispatchSC) {
            Set tSC = tDispatchSC
            Quit
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }

    Quit tSC
}

/// <p>Build a deterministic-but-rich OrderRequest. Uses
/// <code>$Increment(^SessionAgent.Sample.OrderCounter)</code> for unique
/// OrderIds across calls, picks a customer name from a fixed roster, and
/// shapes the line-item count to the scenario.</p>
ClassMethod buildOrderRequest(pErrorMode As %String) As SessionAgent.Sample.Msg.OrderRequest [ Internal ]
{
    Set tCounter = $Increment(^SessionAgent.Sample.OrderCounter)
    Set tRequest = ##class(SessionAgent.Sample.Msg.OrderRequest).%New()
    Set tRequest.OrderId = "ORD-" _ ..numberToStringPad(tCounter, 6)
    Set tRequest.ErrorMode = pErrorMode
    ; Use IRIS %TimeStamp-compatible ODBC format (YYYY-MM-DD HH:MM:SS) — the
    ; %TimeStamp validator rejects ISO-8601 with the trailing "Z".
    Set tRequest.OrderTimestamp = $ZDateTime($ZTimeStamp, 3, 1)

    ; Customer roster — deterministic by counter modulo for reproducibility.
    Set tCustomers = $ListBuild("Acme Corp", "Globex Industries", "Initech LLC", "Umbrella Co", "Stark Enterprises")
    Set tRequest.CustomerName = $ListGet(tCustomers, ((tCounter - 1) # 5) + 1)

    ; Catalog of (sku, price) tuples to draw from.
    Set tCatalog = $ListBuild(
        $ListBuild("WIDGET-100", 12.50),
        $ListBuild("GADGET-200", 24.99),
        $ListBuild("SPROCKET-300", 7.25),
        $ListBuild("BOLT-400", 0.75),
        $ListBuild("PANEL-500", 49.00),
        $ListBuild("CABLE-600", 3.10),
        $ListBuild("MOTOR-700", 119.00),
        $ListBuild("SENSOR-800", 38.40),
        $ListBuild("FRAME-900", 215.00),
        $ListBuild("HOUSING-A1", 87.65)
    )

    ; Line item count varies by scenario for richer trace shape.
    Set tItemCount = $Case(pErrorMode,
        "partialSuccess": 5,
        "businessOperationFailure": 1,
        "businessProcessFailure": 2,
        : 3)

    Set tTotal = 0
    For i = 1:1:tItemCount {
        Set tCatIdx = (((tCounter - 1) + (i - 1)) # 10) + 1
        Set tCatEntry = $ListGet(tCatalog, tCatIdx)
        Set tSku = $ListGet(tCatEntry, 1)
        Set tPrice = $ListGet(tCatEntry, 2)
        Set tQty = ((i - 1) # 3) + 1  ; 1, 2, 3, 1, 2, …
        Set tLineTotal = tQty * tPrice
        Set tTotal = tTotal + tLineTotal
        Do tRequest.LineItems.Insert(tSku _ "|" _ tQty _ "|" _ tPrice)
    }
    Set tRequest.TotalAmount = $FNumber(tTotal, "", 2)

    Set tRequest.Notes = "Sample order generated by RunScenario(""" _ pErrorMode _ """) — counter=" _ tCounter _ ", customer=" _ tRequest.CustomerName _ ", line items=" _ tItemCount _ "."

    Quit tRequest
}

/// <p>Helper that wraps <code>$Justify</code> + zero-pad for the OrderId
/// counter — exposed as a macro-style helper so we don't depend on a
/// project include file. Defined at class scope so the value is computed
/// per call.</p>
ClassMethod numberToStringPad(pNumber As %Integer, pWidth As %Integer) As %String [ Internal ]
{
    Set tStr = pNumber
    While $Length(tStr) < pWidth {
        Set tStr = "0" _ tStr
    }
    Quit tStr
}

}
