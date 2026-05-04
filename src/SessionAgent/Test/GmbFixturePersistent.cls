/// <p>Story 4.2 fixture — generic <code>%Persistent</code> body for the
/// dispatch ladder Step 8 test. Deliberately does NOT extend
/// <code>Ens.MessageBody</code>, <code>%JSON.Adaptor</code>,
/// <code>%XML.Adaptor</code>, or <code>%Stream.Object</code> — so the
/// ladder falls through Steps 3-7 and lands on Step 8.</p>
Class SessionAgent.Test.GmbFixturePersistent Extends %Persistent
{

Property Code As %String;

Property Quantity As %Integer;

Storage Default
{
<Data name="GmbFixturePersistentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Code</Value>
</Value>
<Value name="3">
<Value>Quantity</Value>
</Value>
</Data>
<DataLocation>^SessionAge60F7.GmbFixtureP151BD</DataLocation>
<DefaultData>GmbFixturePersistentDefaultData</DefaultData>
<IdLocation>^SessionAge60F7.GmbFixtureP151BD</IdLocation>
<IndexLocation>^SessionAge60F7.GmbFixtureP151BI</IndexLocation>
<StreamLocation>^SessionAge60F7.GmbFixtureP151BS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
