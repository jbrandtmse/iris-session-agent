/// <p>Test fixture SearchTable subclass for Story 4.6
/// (<CLASS>SessionAgent.Tool.Inspection.FindSessionsByBody</CLASS>). Mirrors
/// the canonical VDoc-style row shape
/// (<code>PropId %Integer, PropValue %String, DocId %String</code>) so
/// the production tool's parameterized SQL can be exercised against a
/// fixture without depending on <CLASS>EnsLib.HL7.SearchTable</CLASS>
/// being populated on the dev install (it isn't — sample production
/// carries no HL7 traffic).</p>
///
/// <p><b>Why <CLASS>Ens.CustomSearchTable</CLASS> base.</b>
/// <CLASS>Ens.VDoc.SearchTable</CLASS>'s code-generator-driven
/// <method>IndexDoc</method> requires a <code>DOCCLASS</code> parameter
/// AND a <code>SearchSpec</code> XData block; subclasses without those
/// trip the <code>$$$EnsSearchTableDocClassRequired</code> error at
/// compile time. <CLASS>Ens.CustomSearchTable</CLASS> only requires
/// <code>DocId</code> and a unique index on it — perfect for fixture
/// tests that seed via direct SQL <code>INSERT</code>.</p>
///
/// <p><b>Properties.</b></p>
/// <ul>
/// <li><code>DocId</code> — inherited from
/// <CLASS>Ens.CustomSearchTable</CLASS>;
/// <code>%String(COLLATION = "EXACT", MAXLEN = "")</code>.</li>
/// <li><code>PropId</code> — <code>%Integer</code>, mirrors the
/// VDoc shape so the production tool's
/// <code>WHERE st.PropId = ?</code> predicate exercises the same path
/// as a real HL7 SearchTable.</li>
/// <li><code>PropValue</code> — <code>%String(MAXLEN = 256)</code>,
/// matches VDoc shape.</li>
/// </ul>
///
/// <p><b>Used by:</b>
/// <CLASS>SessionAgent.Test.FindSessionsByBodyTest</CLASS>. Companion to
/// <CLASS>SessionAgent.Test.GmbFixtureEnsBody</CLASS> et al. (Story 4.2
/// fixtures).</p>
Class SessionAgent.Test.FsbFixtureSearchTable Extends Ens.CustomSearchTable
{

/// DOCCLASS — required by Ens.SearchTableBase / Ens.CustomSearchTable
/// code-generators (BuildIndex, IndexDoc, SearchHeader). Set to
/// <CLASS>Ens.MessageHeader</CLASS> as a placeholder; we never invoke
/// IndexDoc/BuildIndex on this fixture (we INSERT rows via direct SQL),
/// but the parameter must be set or compilation fails with
/// <code>$$$EnsSearchTableDocClassRequired</code>.
Parameter DOCCLASS As %String = "Ens.MessageHeader";

/// PropId — integer key registered in
/// <CLASS>Ens.Config.SearchTableProp</CLASS> (test setUp seeds
/// matching rows so the production tool's prop-name → PropId lookup
/// succeeds).
Property PropId As %Integer;

/// PropValue — exact-match value the production tool's
/// <code>WHERE %EXACT(st.PropValue) = ?</code> predicate binds against.
Property PropValue As %String(MAXLEN = 256, TRUNCATE = 1);

/// Index on PropId for the search predicate. Mirrors VDoc-style
/// <code>indexValue</code>, scoped to (PropId, PropValue, DocId) for
/// the production-equivalent index path.
Index indexValue On (PropId, PropValue, DocId);

/// OnIndexDoc — required by Ens.CustomSearchTable but unused in the
/// fixture (we seed via direct SQL INSERT, not via Ens production
/// IndexDoc dispatch).
ClassMethod OnIndexDoc(pDocObj As %Persistent, pSearchTable As Ens.CustomSearchTable) As %Status
{
    Quit $$$OK
}

Storage Default
{
<Data name="FsbFixtureSearchTableDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PropId</Value>
</Value>
<Value name="3">
<Value>DocId</Value>
</Value>
<Value name="4">
<Value>PropValue</Value>
</Value>
</Data>
<DataLocation>^SessionAge60F7.FsbFixtureSEADAD</DataLocation>
<DefaultData>FsbFixtureSearchTableDefaultData</DefaultData>
<IdLocation>^SessionAge60F7.FsbFixtureSEADAD</IdLocation>
<IndexLocation>^SessionAge60F7.FsbFixtureSEADAI</IndexLocation>
<StreamLocation>^SessionAge60F7.FsbFixtureSEADAS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
