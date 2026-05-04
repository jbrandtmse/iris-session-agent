/// <p>Sample interop request message — an order being submitted into the
/// <class>SessionAgent.Sample.Production</class> sample production. Rich
/// enough that <class>SessionAgent.Tool.Inspection.SessionSummary</class> /
/// <class>SessionTimeline</class> / <class>MessageHeaders</class> have
/// realistic shape data to inspect.</p>
///
/// <p>Properties per Story 3.9 AC-3: at least 5 fields plus optional Notes
/// for narrative richness.</p>
Class SessionAgent.Sample.Msg.OrderRequest Extends Ens.Request
{

/// Stable order identifier issued by the Business Service before dispatch.
Property OrderId As %String(MAXLEN = 64);

/// Originating customer's display name (used by the agent's summary tool).
Property CustomerName As %String(MAXLEN = 128);

/// ISO-8601 UTC timestamp captured at ingest time.
Property OrderTimestamp As %TimeStamp;

/// One delimited string per line item in the form "sku|qty|price".
Property LineItems As list Of %String(MAXLEN = 256);

/// Sum of (qty * price) across LineItems — denormalized for the validator.
Property TotalAmount As %Numeric(SCALE = 2);

/// Optional free-text narrative — gives the agent richer body content.
Property Notes As %String(MAXLEN = 1000);

/// Error-injection mode carried with the request so BPs/BOs (which run
/// in their own jobs and cannot see the caller's process-private globals)
/// can branch on it. Allowed values: "none", "businessProcessFailure",
/// "businessOperationFailure", "partialSuccess".
Property ErrorMode As %String(MAXLEN = 64) [ InitialExpression = "none" ];

Storage Default
{
<Data name="OrderRequestDefaultData">
<Subscript>"OrderRequest"</Subscript>
<Value name="1">
<Value>OrderId</Value>
</Value>
<Value name="2">
<Value>CustomerName</Value>
</Value>
<Value name="3">
<Value>OrderTimestamp</Value>
</Value>
<Value name="4">
<Value>LineItems</Value>
</Value>
<Value name="5">
<Value>TotalAmount</Value>
</Value>
<Value name="6">
<Value>Notes</Value>
</Value>
<Value name="7">
<Value>ErrorMode</Value>
</Value>
</Data>
<DefaultData>OrderRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
