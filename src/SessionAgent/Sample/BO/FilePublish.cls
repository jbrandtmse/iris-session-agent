/// <p>Sample Business Operation that "publishes" an order by writing a
/// stub payload file to the temp directory. Adapterless — no
/// EnsLib.File.OutboundAdapter required; the file write goes through
/// <class>%Stream.FileCharacter</class> directly so the sample stays
/// self-contained.</p>
///
/// <p>Second error-injection point alongside
/// <class>SessionAgent.Sample.BO.SqlPersist</class>. Throws under
/// pErrorMode="businessOperationFailure" OR pErrorMode="partialSuccess"
/// (in the partialSuccess case, SqlPersist succeeds but FilePublish fails,
/// driving a partial-success Ens.MessageHeader trace where one BO has
/// IsError=1 and the other does not).</p>
Class SessionAgent.Sample.BO.FilePublish Extends Ens.BusinessOperation
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

        If (tErrorMode = "businessOperationFailure") || (tErrorMode = "partialSuccess") {
            $$$LOGERROR("Sample FilePublish injected failure (errorMode="_tErrorMode_") for OrderId="_pRequest.OrderId)
            Set tSC = $$$ERROR($$$EnsErrGeneral, "Injected file publish failure for OrderId="_pRequest.OrderId_" (sample error mode "_tErrorMode_")")
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "Injected file publish failure"
            Quit
        }

        ; Build a temp file path; use $System.Util.ManagerDirectory() as a
        ; deterministic location available on every IRIS install (avoids
        ; reliance on the OS TEMP env var).
        Set tDir = $System.Util.ManagerDirectory() _ "Temp"
        ; Best-effort directory create — ignore failure since the dir may
        ; already exist or be unwritable; the file write below will surface
        ; the real error.
        Do ##class(%File).CreateDirectoryChain(tDir)
        Set tPath = tDir _ "/sample-order-" _ pRequest.OrderId _ ".txt"

        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.Filename = tPath
        Do tStream.WriteLine("OrderId: "_pRequest.OrderId)
        Do tStream.WriteLine("Customer: "_pRequest.CustomerName)
        Do tStream.WriteLine("Timestamp: "_pRequest.OrderTimestamp)
        Do tStream.WriteLine("Total: "_pRequest.TotalAmount)
        Do tStream.WriteLine("LineItemCount: "_pRequest.LineItems.Count())
        If pRequest.Notes '= "" {
            Do tStream.WriteLine("Notes: "_pRequest.Notes)
        }
        Set tWriteSC = tStream.%Save()
        If $$$ISERR(tWriteSC) {
            Set tSC = tWriteSC
            Set pResponse.Status = "Rejected"
            Set pResponse.RejectionReason = "FilePublish write failed: "_$System.Status.GetErrorText(tWriteSC)
            Quit
        }

        Set pResponse.Status = "Approved"
        $$$LOGINFO("Sample FilePublish wrote stub file for OrderId="_pRequest.OrderId_" path="_tPath)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Set pResponse.Status = "Rejected"
        Set pResponse.RejectionReason = "FilePublish exception: "_$System.Status.GetErrorText(tSC)
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
