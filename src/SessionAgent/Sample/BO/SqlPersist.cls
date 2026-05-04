/// <p>Sample Business Operation that persists an
/// <class>SessionAgent.Sample.Msg.OrderRequest</class> to the
/// <class>SessionAgent.Sample.Persist.OrderRow</class> SQL table.</p>
///
/// <p>This BO is one of the two error-injection points exercised by
/// <method>SessionAgent.Sample.BS.OrderIngest.RunScenario</method> when
/// pErrorMode = "businessOperationFailure" or "partialSuccess". The
/// injection signal is the
/// <property>SessionAgent.Sample.Msg.OrderRequest.ErrorMode</property>
/// property carried on the request body itself (BPs/BOs run in
/// dedicated jobs and cannot see the operator-process's process-private
/// globals, so the signal must travel with the message).</p>
///
/// <p>Adapterless — has no inbound or outbound adapter. The persist target
/// is the IRIS SQL surface, accessed via the persistent class API.</p>
Class SessionAgent.Sample.BO.SqlPersist Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As SessionAgent.Sample.Msg.OrderRequest, Output pResponse As SessionAgent.Sample.Msg.OrderResponse) As %Status
{
    Set tSC = $$$OK
    Set pResponse = ##class(SessionAgent.Sample.Msg.OrderResponse).%New()
    Set pResponse.OrderId = pRequest.OrderId
    Set pResponse.ProcessedTimestamp = $ZDateTime($ZTimeStamp, 3, 1)

    Try {
        Set tErrorMode = $Select($IsObject(pRequest):pRequest.ErrorMode, 1:"none")
        Set:tErrorMode="" tErrorMode = "none"

        ; Build SKU list flattened from the request's LineItems.
        Set tSkuList = ""
        For i = 1:1:pRequest.LineItems.Count() {
            Set tEntry = pRequest.LineItems.GetAt(i)
            Set tSku = $Piece(tEntry, "|", 1)
            Set tSkuList = tSkuList _ $Select(tSkuList="":"", 1:",") _ tSku
        }

        ; Inject failure BEFORE persisting if requested. Only this BO
        ; throws under "businessOperationFailure"; under "partialSuccess"
        ; only FilePublish throws (so the SQL row IS persisted).
        If tErrorMode = "businessOperationFailure" {
            $$$LOGERROR("Sample SqlPersist injected failure (errorMode=businessOperationFailure) for OrderId="_pRequest.OrderId)
            Set tSC = $$$ERROR($$$EnsErrGeneral, "Injected SQL persist failure for OrderId="_pRequest.OrderId_" (sample error mode)")
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "Injected SQL persist failure"
            Quit
        }

        Set tRow = ##class(SessionAgent.Sample.Persist.OrderRow).%New()
        Set tRow.OrderId = pRequest.OrderId
        Set tRow.CustomerName = pRequest.CustomerName
        Set tRow.OrderTimestamp = pRequest.OrderTimestamp
        Set tRow.TotalAmount = pRequest.TotalAmount
        Set tRow.SkuList = tSkuList
        Set tRow.Status = "Approved"
        Set tRow.PersistedAt = pResponse.ProcessedTimestamp

        Set tSaveSC = tRow.%Save()
        If $$$ISERR(tSaveSC) {
            Set tSC = tSaveSC
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "Persist failed: "_$System.Status.GetErrorText(tSaveSC)
            Quit
        }

        Set pResponse.PersistedRowId = tRow.%Id()
        Set pResponse.Status = "Approved"
        $$$LOGINFO("Sample SqlPersist saved OrderId="_pRequest.OrderId_" as RowId="_pResponse.PersistedRowId)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Set pResponse.Status = "Rejected"
        Set pResponse.RejectionReason = "Persist exception: "_$System.Status.GetErrorText(tSC)
    }

    Quit tSC
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="SessionAgent.Sample.Msg.OrderRequest">
    <Method>OnMessage</Method>
  </MapItem>
</MapItems>
}

}
