/// <p>Story 4.2 fixture — minimal <code>Ens.MessageBody</code>-extending
/// body for the dispatch ladder Step 7 test. Even though the live
/// <code>SessionAgent.Sample.Msg.OrderRequest</code> already exercises
/// Step 7 in the ad-hoc smoke probe, the test class wants a stable
/// fixture it can seed and tear down without coupling to the sample
/// production state.</p>
Class SessionAgent.Test.GmbFixtureEnsBody Extends Ens.MessageBody
{

Property Subject As %String;

Property Amount As %Numeric;

Property Note As %String(MAXLEN = 256);

Storage Default
{
<Data name="GmbFixtureEnsBodyDefaultData">
<Subscript>"GmbFixtureEnsBody"</Subscript>
<Value name="1">
<Value>Subject</Value>
</Value>
<Value name="2">
<Value>Amount</Value>
</Value>
<Value name="3">
<Value>Note</Value>
</Value>
</Data>
<DefaultData>GmbFixtureEnsBodyDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
