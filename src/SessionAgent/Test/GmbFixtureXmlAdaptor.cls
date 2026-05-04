/// <p>Story 4.2 fixture — minimal <code>%XML.Adaptor</code>-extending
/// <code>%Persistent</code> body for the dispatch ladder Step 5 test.
/// Does NOT extend <code>Ens.MessageBody</code> — Step 5's exclusion
/// guard skips Ens.MessageBody subclasses to Step 7's reflection path.</p>
Class SessionAgent.Test.GmbFixtureXmlAdaptor Extends (%Persistent, %XML.Adaptor)
{

Property Title As %String;

Property Count As %Integer;

Storage Default
{
<Data name="GmbFixtureXmlAdaptorDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Title</Value>
</Value>
<Value name="3">
<Value>Count</Value>
</Value>
</Data>
<DataLocation>^SessionAge60F7.GmbFixtureXC507D</DataLocation>
<DefaultData>GmbFixtureXmlAdaptorDefaultData</DefaultData>
<IdLocation>^SessionAge60F7.GmbFixtureXC507D</IdLocation>
<IndexLocation>^SessionAge60F7.GmbFixtureXC507I</IndexLocation>
<StreamLocation>^SessionAge60F7.GmbFixtureXC507S</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
