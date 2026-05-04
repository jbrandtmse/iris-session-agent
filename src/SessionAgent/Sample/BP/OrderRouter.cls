/// <p>Sample routing Business Process. Receives an OrderRequest from the
/// adapterless OrderIngest BS, dispatches synchronously to the validator
/// (so a rejection short-circuits the trace before any persist work), and
/// — if approved — dispatches asynchronously to both the SqlPersist BO
/// and the FilePublish BO. Replies with a final OrderResponse summarising
/// the outcome of all three child calls.</p>
///
/// <p>The async fan-out + OnResponse/OnComplete pattern produces an
/// Ens.MessageHeader trace with at least 4 rows under happy-path
/// (BS request → Router request → Validator request → Persist request →
/// Publish request, plus their replies) — easily satisfying AC-7's
/// "≥4 rows" assertion. Persisted properties on this class capture the
/// per-child outcomes so OnComplete can assemble the final response.</p>
Class SessionAgent.Sample.BP.OrderRouter Extends Ens.BusinessProcess
{

/// Captured order id from the originating request, used by OnComplete to
/// build the response (request object itself is not in scope inside
/// OnResponse for async children).
Property OrderId As %String(MAXLEN = 64);

/// Final disposition the router will reply with.
Property FinalStatus As %String(VALUELIST = ",Approved,Rejected,PartialApproval");

/// Free-text rejection / partial-success reason assembled across child
/// responses.
Property FailureNotes As %String(MAXLEN = 1024);

/// Persisted row id from SqlPersist (if it succeeded).
Property PersistedRowId As %Integer;

/// Set when the SqlPersist async response has arrived.
Property PersistDone As %Boolean [ InitialExpression = 0 ];

/// Set when the FilePublish async response has arrived.
Property PublishDone As %Boolean [ InitialExpression = 0 ];

/// Set when the SqlPersist async response was an error.
Property PersistFailed As %Boolean [ InitialExpression = 0 ];

/// Set when the FilePublish async response was an error.
Property PublishFailed As %Boolean [ InitialExpression = 0 ];

Method OnRequest(pRequest As SessionAgent.Sample.Msg.OrderRequest, Output pResponse As SessionAgent.Sample.Msg.OrderResponse) As %Status
{
    Set tSC = $$$OK
    Set pResponse = $$$NULLOREF

    Try {
        Set ..OrderId = pRequest.OrderId

        ; Synchronous call to the validator; if Rejected, short-circuit.
        Set tValidatorResp = ##class(SessionAgent.Sample.Msg.OrderResponse).%New()
        Set tSyncSC = ..SendRequestSync("SessionAgent.Sample.BP.OrderValidator", pRequest, .tValidatorResp)
        If $$$ISERR(tSyncSC) {
            ; Treat sync-call failure as a rejection.
            Set ..FinalStatus = "Rejected"
            Set ..FailureNotes = "Validator call failed: "_$System.Status.GetErrorText(tSyncSC)
            Set pResponse = ..buildResponse()
            Quit
        }

        If '$IsObject(tValidatorResp) || (tValidatorResp.Status = "Rejected") {
            Set ..FinalStatus = "Rejected"
            Set ..FailureNotes = $Select($IsObject(tValidatorResp):tValidatorResp.RejectionReason, 1:"Validator returned no response")
            Set pResponse = ..buildResponse()
            Quit
        }

        ; Validator approved — fan out to both BOs asynchronously with
        ; distinct completion keys so OnResponse can tell them apart.
        Set tSC = ..SendRequestAsync("SessionAgent.Sample.BO.SqlPersist", pRequest, 1, "persist")
        If $$$ISERR(tSC) {
            Set ..FinalStatus = "Rejected"
            Set ..FailureNotes = "Failed to dispatch SqlPersist: "_$System.Status.GetErrorText(tSC)
            Set pResponse = ..buildResponse()
            Quit
        }
        Set tSC = ..SendRequestAsync("SessionAgent.Sample.BO.FilePublish", pRequest, 1, "publish")
        If $$$ISERR(tSC) {
            Set ..FinalStatus = "Rejected"
            Set ..FailureNotes = "Failed to dispatch FilePublish: "_$System.Status.GetErrorText(tSC)
            Set pResponse = ..buildResponse()
            Quit
        }

        ; Returning $$$OK with no pResponse leaves the BP in a "waiting for
        ; async responses" state — OnResponse + OnComplete will produce
        ; the final reply.
    }
    Catch ex {
        Set tSC = ex.AsStatus()
        Set ..FinalStatus = "Rejected"
        Set ..FailureNotes = "Router exception: "_$System.Status.GetErrorText(tSC)
        Set pResponse = ..buildResponse()
    }

    Quit tSC
}

Method OnResponse(request As SessionAgent.Sample.Msg.OrderRequest, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As SessionAgent.Sample.Msg.OrderResponse, pCompletionKey As %String) As %Status
{
    Try {
        If pCompletionKey = "persist" {
            Set ..PersistDone = 1
            If $IsObject(callresponse) && (callresponse.Status = "Approved") {
                Set ..PersistedRowId = callresponse.PersistedRowId
            } Else {
                Set ..PersistFailed = 1
                Set ..FailureNotes = ..FailureNotes _ $Select(..FailureNotes="":"", 1:"; ") _ "Persist: "_$Select($IsObject(callresponse):callresponse.RejectionReason, 1:"no response")
            }
        } ElseIf pCompletionKey = "publish" {
            Set ..PublishDone = 1
            If '$IsObject(callresponse) || (callresponse.Status '= "Approved") {
                Set ..PublishFailed = 1
                Set ..FailureNotes = ..FailureNotes _ $Select(..FailureNotes="":"", 1:"; ") _ "Publish: "_$Select($IsObject(callresponse):callresponse.RejectionReason, 1:"no response")
            }
        }
    }
    Catch ex {
        Set ..FailureNotes = ..FailureNotes _ $Select(..FailureNotes="":"", 1:"; ") _ "OnResponse exception: "_$System.Status.GetErrorText(ex.AsStatus())
    }

    Quit $$$OK
}

/// Treat errored async responses (where the child BO returned $$$ERROR)
/// the same as a non-Approved response — flip the corresponding flag, do
/// not propagate the error up to the BP framework.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
    If pCompletionKey = "persist" {
        Set ..PersistDone = 1
        Set ..PersistFailed = 1
        Set ..FailureNotes = ..FailureNotes _ $Select(..FailureNotes="":"", 1:"; ") _ "Persist error: "_$System.Status.GetErrorText(pErrorStatus)
    } ElseIf pCompletionKey = "publish" {
        Set ..PublishDone = 1
        Set ..PublishFailed = 1
        Set ..FailureNotes = ..FailureNotes _ $Select(..FailureNotes="":"", 1:"; ") _ "Publish error: "_$System.Status.GetErrorText(pErrorStatus)
    }
    ; Returning $$$OK swallows the error so the BP does not terminate; we
    ; want the trace to show one IsError row plus a final OnComplete reply.
    Quit $$$OK
}

Method OnComplete(request As SessionAgent.Sample.Msg.OrderRequest, ByRef response As SessionAgent.Sample.Msg.OrderResponse) As %Status
{
    If ..FinalStatus = "" {
        ; Determine status from the per-child flags.
        If ..PersistFailed && ..PublishFailed {
            Set ..FinalStatus = "Rejected"
        } ElseIf ..PersistFailed || ..PublishFailed {
            Set ..FinalStatus = "PartialApproval"
        } Else {
            Set ..FinalStatus = "Approved"
        }
    }
    Set response = ..buildResponse()
    Quit $$$OK
}

/// Helper — build the OrderResponse object from accumulated state on the
/// BP instance.
Method buildResponse() As SessionAgent.Sample.Msg.OrderResponse [ Internal ]
{
    Set tResp = ##class(SessionAgent.Sample.Msg.OrderResponse).%New()
    Set tResp.OrderId = ..OrderId
    Set tResp.Status = $Select(..FinalStatus="":"Rejected", 1:..FinalStatus)
    Set tResp.RejectionReason = ..FailureNotes
    Set tResp.PersistedRowId = ..PersistedRowId
    Set tResp.ProcessedTimestamp = $ZDateTime($ZTimeStamp, 3, 1)
    Quit tResp
}

Storage Default
{
<Data name="OrderRouterDefaultData">
<Subscript>"OrderRouter"</Subscript>
<Value name="1">
<Value>OrderId</Value>
</Value>
<Value name="2">
<Value>FinalStatus</Value>
</Value>
<Value name="3">
<Value>FailureNotes</Value>
</Value>
<Value name="4">
<Value>PersistedRowId</Value>
</Value>
<Value name="5">
<Value>PersistDone</Value>
</Value>
<Value name="6">
<Value>PublishDone</Value>
</Value>
<Value name="7">
<Value>PersistFailed</Value>
</Value>
<Value name="8">
<Value>PublishFailed</Value>
</Value>
</Data>
<DefaultData>OrderRouterDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
