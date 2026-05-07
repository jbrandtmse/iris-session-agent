/// <p>Namespace-wide vocabulary baseline for the Search Agent —
/// aggregates per-user vocabulary mappings into a cross-user "this
/// namespace's collective alias-to-concept understanding" view that
/// the Search Agent can consult when neither the per-user
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS> row nor the
/// <CLASS>SessionAgent.Search.SeedVocabulary</CLASS> fallback exists.</p>
///
/// <p><b>v1 vs v1.5 boundary (schema-only in v1).</b> This class ships
/// in Story 8.1 as <b>schema-only</b> — the persistence substrate is
/// in place but no insert / update logic ships in v1. Operators see an
/// empty <code>SessionAgent_Search.NamespaceVocabulary</code> table in
/// the IRIS SQL Catalog. The aggregation logic that populates rows
/// from <CLASS>SessionAgent.Search.UserVocabulary</CLASS> baselines
/// (NFR-S2 schema discipline preserved — no PII / no body content,
/// only alias / class / counts) is deferred to <b>v1.5 / Vision tier
/// per the epics.md plan</b>. Stories 8.2 – 8.7 do not depend on this
/// class being populated; the substrate is in place but inert.</p>
///
/// <p><b>NFR-S2 schema discipline.</b> No credential material, no API
/// keys, no PHI body content lives on this class. Aliases and aggregate
/// counts only.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Search.NamespaceVocabulary</code> —
/// the per-property doc-comments below surface as column descriptions
/// in the IRIS SQL Catalog Mgmt-Portal view. The empty-table state in
/// v1 is the operator-visible "v1.5 deferred" signal.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md Story 8.1</a> — AC-3 verbatim source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR19</a> — vocabulary persistence design + v1 vs v1.5 boundary.</li>
/// </ul>
Class SessionAgent.Search.NamespaceVocabulary Extends %Persistent
{

/// <p>The natural-language alias the namespace baseline records — same
/// shape as <CLASS>SessionAgent.Search.UserVocabulary</CLASS>'s
/// <code>Alias</code> column, just aggregated cross-user. Empty in v1
/// (no aggregation logic yet); v1.5 / Vision tier populates from
/// per-user rows.</p>
Property Alias As %String(MAXLEN = 512);

/// <p>Optional body-class scope for per-class refinement —
/// e.g., <code>EnsLib.HL7.Message</code>. Same semantics as the
/// <code>MessageBodyClass</code> on the user / seed vocabulary classes.
/// Empty means <i>"applies to any class"</i>.</p>
Property MessageBodyClass As %String(MAXLEN = 128);

/// <p>Comma-separated synonym list aggregated across users —
/// the union of synonyms each contributing user supplied for this alias.
/// Empty in v1; populated by v1.5 aggregation.</p>
Property Aliases As %String(MAXLEN = 2048);

/// <p>Aggregate baseline confidence in <code>[0.0, 1.0]</code>, derived
/// from contributing users' individual <code>Confidence</code> values
/// (Story 9.2). Empty / 0 in v1; v1.5 aggregation computes the
/// weighted mean. The Search Agent's lookup ladder consults this when
/// neither per-user nor seed rows exist.</p>
Property BaselineConfidence As %Numeric;

/// <p>Count of distinct users contributing to this baseline — surfaces
/// in the Mgmt-Portal SQL Catalog so operators can see the breadth of
/// the namespace's vocabulary maturity. Empty / 0 in v1; v1.5
/// aggregation increments per contributing user.</p>
Property BasedOnUsers As %Integer;

Storage Default
{
<Data name="NamespaceVocabularyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Alias</Value>
</Value>
<Value name="3">
<Value>MessageBodyClass</Value>
</Value>
<Value name="4">
<Value>Aliases</Value>
</Value>
<Value name="5">
<Value>BaselineConfidence</Value>
</Value>
<Value name="6">
<Value>BasedOnUsers</Value>
</Value>
</Data>
<DataLocation>^SessionAgeC88B.NamespaceVoDDDDD</DataLocation>
<DefaultData>NamespaceVocabularyDefaultData</DefaultData>
<IdLocation>^SessionAgeC88B.NamespaceVoDDDDD</IdLocation>
<IndexLocation>^SessionAgeC88B.NamespaceVoDDDDI</IndexLocation>
<StreamLocation>^SessionAgeC88B.NamespaceVoDDDDS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
