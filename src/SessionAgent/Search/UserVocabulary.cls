/// <p>Per-portal-user vocabulary mapping for the Search Agent. Each row
/// records an alias the user has confirmed (via clickthrough, explicit
/// teach, extraction, or seeding) maps to a particular concept in the
/// HL7 / ObjectScript / interop domain. The Search Agent reads the
/// matching <code>(PortalUser, Alias)</code> row at search time to
/// translate operator-typed natural-language phrasing into the canonical
/// query primitive (a SearchTable property comparison, an HL7 message
/// type filter, etc.).</p>
///
/// <p><b>Per-class refinement (saved memory <code>project_search_agent_body_search_refinement.md</code>).</b>
/// The optional <code>MessageBodyClass</code> property scopes the
/// alias to a specific body-class taxonomy (e.g.,
/// <code>EnsLib.HL7.Message</code>) so the same alias can carry a
/// different meaning when the user is searching HL7 vs CSV vs JSON
/// traffic. Empty <code>MessageBodyClass</code> means
/// <i>"applies to any class"</i> — the Search Agent's lookup falls back
/// to the empty-class row when no class-specific row is found.</p>
///
/// <p><b>v1 vs Epic 9 boundary on Confidence.</b> The
/// <code>Confidence</code> property is stored as the numeric output of
/// the recursion-safe <code>%OnAfterSave</code> trigger that
/// recomputes from <code>SuccessCount</code> / <code>FailureCount</code>.
/// That trigger ships in <b>Epic 9 Story 9.2</b>; until then, this story
/// (8.1) ships <code>Confidence</code> with default <code>0</code> and
/// every read returns <code>0</code> verbatim. Stories 8.2 – 8.7 do not
/// depend on Confidence — the substrate is in place but inert. Story 9.2
/// will overlay the trigger without schema migration.</p>
///
/// <p><b>NFR-S2 schema discipline.</b> No credential material, no API
/// keys, no PHI body content lives on this class. Aliases and counts
/// only.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Search.UserVocabulary</code> — the
/// per-property doc-comments below surface as column descriptions in
/// the IRIS SQL Catalog Mgmt-Portal view (per Story 8.0 AC-1
/// codification of operator-observable artifact descriptions).</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md Story 8.1</a> — AC-1 verbatim source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR19</a> — vocabulary persistence design.</li>
/// <li>Saved memory <code>project_search_agent_body_search_refinement.md</code> — per-class vocabulary refinement.</li>
/// </ul>
Class SessionAgent.Search.UserVocabulary Extends %Persistent
{

/// <p>Portal user (typically the IRIS login name) who confirmed this alias
/// mapping. The unique <code>UserAliasIdx</code> below scopes alias rows
/// per user so two users may map the same alias to different concepts.</p>
Property PortalUser As %String;

/// <p>The natural-language alias the user typed or clicked-through to
/// confirm — e.g., <code>"admit"</code>, <code>"failed"</code>,
/// <code>"MRN search"</code>. <code>MAXLEN=512</code> covers
/// multi-word phrases without forcing a stream backing store.</p>
Property Alias As %String(MAXLEN = 512);

/// <p>Optional body-class scope for per-class vocabulary refinement —
/// e.g., <code>EnsLib.HL7.Message</code>. Empty means
/// <i>"applies to any class"</i> (the cross-class default). Per the
/// saved memory, allowing the same alias to carry different meanings
/// per body class is a v1 design decision.</p>
Property MessageBodyClass As %String(MAXLEN = 128);

/// <p>Count of times the alias mapping resulted in a successful search
/// (clickthrough on a returned hit). Increments via Story 9.2's
/// <code>RecordSuccess</code> path.</p>
Property SuccessCount As %Integer [ InitialExpression = 0 ];

/// <p>Count of times the alias mapping yielded zero useful results
/// (operator typed the alias, results returned, operator did not click
/// any hit). Increments via Story 9.2's <code>RecordFailure</code> path.</p>
Property FailureCount As %Integer [ InitialExpression = 0 ];

/// <p>Numeric confidence score in <code>[0.0, 1.0]</code>, recomputed by
/// Story 9.2's recursion-safe <code>%OnAfterSave</code> trigger from
/// the success / failure counts. Until Story 9.2 ships, the default
/// <code>0</code> is the only legal value — the substrate is in place
/// but inert.</p>
Property Confidence As %Numeric [ InitialExpression = 0 ];

/// <p>ISO-8601 UTC timestamp (e.g., <code>2026-05-07T10:30:00Z</code>) of
/// the most recent successful use of this alias. Stored as
/// <code>%String</code> so the format is operator-readable in the SQL
/// Catalog without horolog conversion.</p>
Property LastUsed As %String;

/// <p>ISO-8601 UTC timestamp of row creation. Set at insert time;
/// never updated.</p>
Property CreatedAt As %String;

/// <p>Provenance — one of <code>clickthrough</code> /
/// <code>explicit</code> / <code>extracted</code> / <code>seed</code>.
/// Lets the Search Agent weight directly-confirmed mappings above
/// extracted-from-conversation mappings when ranking candidate aliases.</p>
Property CreatedVia As %String;

/// <p>Unique index on <code>(PortalUser, Alias)</code> — enforces single
/// vocabulary row per user per alias text. The unique constraint is
/// load-bearing for the Search Agent's lookup contract: a single
/// <code>UserAliasIdxOpen(user, alias)</code> call returns the canonical
/// alias mapping (or null if absent), no de-duplication logic needed.</p>
Index UserAliasIdx On (PortalUser, Alias) [ Unique ];

Storage Default
{
<Data name="UserVocabularyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PortalUser</Value>
</Value>
<Value name="3">
<Value>Alias</Value>
</Value>
<Value name="4">
<Value>MessageBodyClass</Value>
</Value>
<Value name="5">
<Value>SuccessCount</Value>
</Value>
<Value name="6">
<Value>FailureCount</Value>
</Value>
<Value name="7">
<Value>Confidence</Value>
</Value>
<Value name="8">
<Value>LastUsed</Value>
</Value>
<Value name="9">
<Value>CreatedAt</Value>
</Value>
<Value name="10">
<Value>CreatedVia</Value>
</Value>
</Data>
<DataLocation>^SessionAgenC88B.UserVocabularyD</DataLocation>
<DefaultData>UserVocabularyDefaultData</DefaultData>
<IdLocation>^SessionAgenC88B.UserVocabularyD</IdLocation>
<IndexLocation>^SessionAgenC88B.UserVocabularyI</IndexLocation>
<StreamLocation>^SessionAgenC88B.UserVocabularyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
