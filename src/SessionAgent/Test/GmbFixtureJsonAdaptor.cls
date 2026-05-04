/// <p>Story 4.2 fixture — minimal <code>%JSON.Adaptor</code>-extending
/// <code>%Persistent</code> body for the dispatch ladder Step 4 test
/// (<class>SessionAgent.Test.GetMessageBodyTest</class>). Lives under
/// <code>SessionAgent.Test.</code> so the
/// <CLASS>SessionAgent.Tool.Registry</CLASS> reflection filter excludes
/// it from the operator-facing tool list (see
/// <code>NOT %STARTSWITH 'SessionAgent.Test.'</code> in
/// <method>Registry.ListTools</method>).</p>
Class SessionAgent.Test.GmbFixtureJsonAdaptor Extends (%Persistent, %JSON.Adaptor)
{

Property Field1 As %String;

Property Field2 As %Integer;

Storage Default
{
<Data name="GmbFixtureJsonAdaptorDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Field1</Value>
</Value>
<Value name="3">
<Value>Field2</Value>
</Value>
</Data>
<DataLocation>^SessionAge60F7.GmbFixtureJA49DD</DataLocation>
<DefaultData>GmbFixtureJsonAdaptorDefaultData</DefaultData>
<IdLocation>^SessionAge60F7.GmbFixtureJA49DD</IdLocation>
<IndexLocation>^SessionAge60F7.GmbFixtureJA49DI</IndexLocation>
<StreamLocation>^SessionAge60F7.GmbFixtureJA49DS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
