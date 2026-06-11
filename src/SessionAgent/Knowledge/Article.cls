/// <p>One distilled IRIS-SQL / Interoperability expertise article in the
/// query-knowledge corpus (Epic 14 FR62). Rows are seeded at install time
/// by <CLASS>SessionAgent.Knowledge.SeedContent</CLASS> (idempotent upsert
/// by <property>Slug</property>) and retrieved on demand by the
/// <code>get_query_knowledge</code> tool
/// (<CLASS>SessionAgent.Tool.Inspection.GetQueryKnowledge</CLASS>) so
/// agents consult dialect/trap knowledge BEFORE authoring SQL instead of
/// bloating the cached system prompt.</p>
///
/// <p><b>Content source.</b> Articles are distilled from
/// <code>docs/iris-query-guide/</code> (10 files) per the Epic 14 sprint
/// change proposal Appendix C distillation map. Bodies are ASCII-only
/// (no Unicode arrows/dashes) per the SeedVocabulary Rule 12 mojibake
/// precedent.</p>
///
/// <p><b>Operator-observable surface.</b> This class projects to SQL
/// catalog as <code>SessionAgent_Knowledge.Article</code> — the
/// per-property doc-comments below surface as column descriptions in the
/// IRIS SQL Catalog Mgmt-Portal view.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-1-knowledge-corpus-get-query-knowledge-tool.md">Story 14.1</a> — AC-1 source.</li>
/// <li><a href="../Search/SeedVocabulary.cls">SessionAgent.Search.SeedVocabulary</a> — seeding + NFR-R5 precedent.</li>
/// <li><a href="../../../docs/iris-query-guide/README.md">docs/iris-query-guide/</a> — raw knowledge source.</li>
/// </ul>
Class SessionAgent.Knowledge.Article Extends %Persistent
{

/// <p>Unique, stable, lowercase-hyphenated article identifier — e.g.
/// <code>"top-not-limit"</code>, <code>"diagnostic-checklist"</code>.
/// The idempotent-upsert key for <CLASS>SessionAgent.Knowledge.SeedContent</CLASS>
/// <method>Seed</method>: re-seeding updates the row with this Slug
/// instead of inserting a duplicate.</p>
Property Slug As %String(MAXLEN = 128) [ Required ];

/// <p>Topic group the article belongs to — one of the 7 fixed corpus
/// topics. The <code>get_query_knowledge</code> tool filters on this
/// column when the caller supplies the <code>topic</code> argument.</p>
Property Topic As %String(VALUELIST = ",methodology,dialect,message-model,performance,discovery,reference,cookbook") [ Required ];

/// <p>Operator/LLM-readable article title — e.g.
/// <code>"Row limiting: TOP, not LIMIT"</code>. Matched (case-insensitive)
/// by the <code>get_query_knowledge</code> keyword search alongside
/// <property>Keywords</property>.</p>
Property Title As %String(MAXLEN = 256) [ Required ];

/// <p>Comma-separated lowercase keyword list used by the
/// <code>get_query_knowledge</code> keyword search — e.g.
/// <code>"top,limit,row limiting,select top"</code>.</p>
Property Keywords As %String(MAXLEN = 1024);

/// <p>The distilled article body — self-contained, ASCII-only plain text
/// (typical length under ~2000 characters; hard cap 16000). Cookbook
/// articles carry runnable parameterized SQL with placeholder markers
/// like <code>{component}</code> / <code>:session_id</code>.</p>
Property Body As %String(MAXLEN = 16000) [ Required ];

/// <p>Unique index on <property>Slug</property> — enforces the
/// one-row-per-slug invariant the idempotent <method>Seed</method>
/// upsert relies on, and gives O(log N) slug lookup.</p>
Index SlugIdx On Slug [ Unique ];

Storage Default
{
<Data name="ArticleDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Slug</Value>
</Value>
<Value name="3">
<Value>Topic</Value>
</Value>
<Value name="4">
<Value>Title</Value>
</Value>
<Value name="5">
<Value>Keywords</Value>
</Value>
<Value name="6">
<Value>Body</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.KnowlA5DE.ArticleD</DataLocation>
<DefaultData>ArticleDefaultData</DefaultData>
<IdLocation>^SessionAgent.KnowlA5DE.ArticleD</IdLocation>
<IndexLocation>^SessionAgent.KnowlA5DE.ArticleI</IndexLocation>
<StreamLocation>^SessionAgent.KnowlA5DE.ArticleS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
