/// <p>Sample interop response message — produced by
/// <class>SessionAgent.Sample.BP.OrderRouter</class> after running an order
/// through the validator + persist + publish operations.</p>
///
/// <p>Properties per Story 3.9 AC-3.</p>
Class SessionAgent.Sample.Msg.OrderResponse Extends Ens.Response
{

/// Echoed order identifier — joins the response to the originating request.
Property OrderId As %String(MAXLEN = 64);

/// Final disposition of the order from the routing process.
Property Status As %String(VALUELIST = ",Approved,Rejected,PartialApproval");

/// Populated when Status="Rejected" or Status="PartialApproval" — short
/// human-readable explanation the inspection agent can quote back.
Property RejectionReason As %String(MAXLEN = 512);

/// ISO-8601 UTC timestamp at which the routing process finalised the
/// response.
Property ProcessedTimestamp As %TimeStamp;

/// %Id() of the SessionAgent.Sample.Persist.OrderRow created by the
/// SqlPersist BO; empty if persist failed or was not invoked.
Property PersistedRowId As %Integer;

Storage Default
{
<Data name="OrderResponseDefaultData">
<Subscript>"OrderResponse"</Subscript>
<Value name="1">
<Value>OrderId</Value>
</Value>
<Value name="2">
<Value>Status</Value>
</Value>
<Value name="3">
<Value>RejectionReason</Value>
</Value>
<Value name="4">
<Value>ProcessedTimestamp</Value>
</Value>
<Value name="5">
<Value>PersistedRowId</Value>
</Value>
</Data>
<DefaultData>OrderResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
