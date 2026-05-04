/// <p>Sample Business Process that validates an OrderRequest's line items
/// + total amount. Returns an
/// <class>SessionAgent.Sample.Msg.OrderResponse</class> with Status set to
/// "Approved" or "Rejected".</p>
///
/// <p>Injection point for pErrorMode = "businessProcessFailure" — when set,
/// the validator unconditionally returns Rejected so the routing BP can
/// short-circuit before any persist + publish work runs (a different shape
/// of trace than businessOperationFailure, useful for the inspection
/// agent's diagnostic-question repertoire).</p>
Class SessionAgent.Sample.BP.OrderValidator Extends Ens.BusinessProcess
{

Method OnRequest(pRequest As SessionAgent.Sample.Msg.OrderRequest, Output pResponse As SessionAgent.Sample.Msg.OrderResponse) As %Status
{
    Set tSC = $$$OK
    Set pResponse = ##class(SessionAgent.Sample.Msg.OrderResponse).%New()
    Set pResponse.OrderId = pRequest.OrderId
    Set pResponse.ProcessedTimestamp = $ZDateTime($ZTimeStamp, 3, 1)

    Try {
        Set tErrorMode = $Select($IsObject(pRequest):pRequest.ErrorMode, 1:"none")
        Set:tErrorMode="" tErrorMode = "none"

        If tErrorMode = "businessProcessFailure" {
            $$$LOGERROR("Sample OrderValidator injected rejection (errorMode=businessProcessFailure) for OrderId="_pRequest.OrderId)
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "Injected validator rejection (sample error mode)"
            Quit
        }

        ; Real validation: must have at least one line item, total must be
        ; positive, no zero-quantity items.
        If pRequest.LineItems.Count() = 0 {
            $$$LOGWARNING("Sample OrderValidator rejected OrderId="_pRequest.OrderId_": no line items")
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "OrderRequest contains no line items"
            Quit
        }

        If pRequest.TotalAmount <= 0 {
            $$$LOGWARNING("Sample OrderValidator rejected OrderId="_pRequest.OrderId_": non-positive total "_pRequest.TotalAmount)
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "TotalAmount must be > 0 (got "_pRequest.TotalAmount_")"
            Quit
        }

        For i = 1:1:pRequest.LineItems.Count() {
            Set tEntry = pRequest.LineItems.GetAt(i)
            Set tQty = +$Piece(tEntry, "|", 2)
            If tQty <= 0 {
                $$$LOGWARNING("Sample OrderValidator rejected OrderId="_pRequest.OrderId_": zero-quantity line item "_tEntry)
                Set pResponse.Status = "Rejected"
                Set pResponse.RejectionReason = "Line item has non-positive quantity: "_tEntry
                Quit
            }
        }

        If pResponse.Status = "" {
            Set pResponse.Status = "Approved"
            $$$LOGINFO("Sample OrderValidator approved OrderId="_pRequest.OrderId_" with "_pRequest.LineItems.Count()_" line items")
        }
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Set pResponse.Status = "Rejected"
        Set pResponse.RejectionReason = "Validator exception: "_$System.Status.GetErrorText(tSC)
    }

    Quit tSC
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
