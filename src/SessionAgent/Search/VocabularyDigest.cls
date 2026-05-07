/// <p>Story 9.3 — vocabulary digest assembly for the Search Agent's
/// first-user-message prefix injection (Story 9.4 consumer). Renders the
/// operator's top-N <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// rows (filtered to <code>Confidence &gt;= ..#MinUserConfidence</code>,
/// ordered by <code>Confidence DESC, LastUsed DESC</code>, capped at
/// <code>..#MaxEntries</code>) as a Markdown digest the LLM can scan.
/// First-time users with zero qualifying rows fall back to the top-5
/// <CLASS>SessionAgent.Search.SeedVocabulary</CLASS> templates so the
/// agent always has at least some vocabulary grounding.</p>
///
/// <p><b>Calibration constants (architecture §"Calibration constants" /
/// epics.md AR10).</b> <code>MaxEntries=20</code> caps the row count;
/// <code>MinUserConfidence=0.3</code> floors the inclusion bar. Both are
/// declared as Class Parameters so pilot tuning is cheap (no schema
/// migration). Per project rule §"Naming Conventions" / "Basics", IRIS
/// class parameter names use camelCase (no underscores allowed).</p>
///
/// <p><b>Token-budget cap.</b> The rendered digest is capped at ~1,200
/// tokens via the <code>$Length(digest) \ 4</code> rule-of-thumb (standard
/// GPT/Claude tokenizer approximation: ~4 chars/token for English
/// Markdown). Truncation is row-granular — never cut a row mid-string —
/// and the appended marker
/// <code>_(N more aliases hidden ...)_</code> tells the LLM that a longer
/// list exists and points it at <code>vocab_lookup mode='list'</code>.</p>
///
/// <p><b>NFR-P6 prompt-cache discipline.</b> The Story 9.4 consumer
/// (<CLASS>SessionAgent.Agent.AgentLoop</CLASS>) injects this digest into
/// the FIRST USER MESSAGE — never into the cached
/// <code>system + tools</code> prefix — so the Anthropic prompt-cache hit
/// rate stays high across turns. This class produces the digest text but
/// does not orchestrate the injection.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/9-3-search-vocabularydigest-build.md">Story 9.3 spec</a> — AC-1 / AC-2 / AC-3 / AC-4 verbatim source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md §"Calibration constants"</a> — MaxEntries=20 / MinUserConfidence=0.3.</li>
/// <li><CLASS>SessionAgent.Search.UserVocabulary</CLASS> §<method>RecordSuccess</method> / §<method>%OnAfterSave</method> — Story 9.2 substrate this digest reads from.</li>
/// <li><CLASS>SessionAgent.Search.SeedVocabulary</CLASS> §<method>Seed</method> — Story 8.1 install-time fallback rows.</li>
/// </ul>
Class SessionAgent.Search.VocabularyDigest Extends %RegisteredObject
{

/// <p>Maximum number of <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// rows included in the digest (architecture §"Calibration constants").
/// Beyond this cap the row-list is truncated and a
/// <code>(N more aliases hidden ...)</code> marker appended. Operators
/// who want the full list invoke <code>vocab_lookup mode='list'</code>.</p>
Parameter MaxEntries As INTEGER = 20;

/// <p>Inclusion threshold — rows with <code>Confidence &lt;
/// ..#MinUserConfidence</code> are filtered out of the digest.
/// <code>0.3</code> ≈ "operator clicked through at least once but the
/// alias has not yet built up a strong confirmation track record"; below
/// that floor the row is too noisy to surface as guidance to the LLM.
/// Operators tuning the floor edit this parameter and recompile (no
/// schema migration).</p>
Parameter MinUserConfidence As %Numeric = 0.3;

/// <p>Story 9.3 AC-2 — assemble the per-user vocabulary digest. Queries
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS> for rows matching
/// <var>pPortalUser</var> with <code>Confidence &gt;=
/// ..#MinUserConfidence</code>, ordered <code>Confidence DESC, LastUsed
/// DESC</code>, takes <code>TOP ..#MaxEntries</code>, and renders as a
/// Markdown digest. If zero rows qualify, falls back to
/// <method>SeedFallback</method> (AC-3). Output is capped at ~1,200
/// tokens via the AC-4 token-budget logic.</p>
///
/// <p><b>Per-row format:</b>
/// <code>- "&lt;Alias&gt;" — &lt;descriptor&gt; (confidence X.XX)</code>
/// where <var>descriptor</var> is <code>MessageBodyClass</code> if
/// non-empty (preferred — more semantic for the LLM), otherwise
/// <code>CreatedVia</code>, otherwise the literal <code>"saved alias"</code>
/// placeholder. The em-dash <code>—</code> (U+2014, NOT hyphen) gives a
/// stronger visual break and avoids confusion with the leading bullet
/// <code>- </code>.</p>
///
/// <p><b>Returns:</b> the rendered Markdown digest as a
/// <code>%String</code>. Never returns empty — even a brand-new user
/// gets the seed-vocabulary fallback section so the LLM always has some
/// grounding.</p>
ClassMethod Build(pPortalUser As %String) As %String
{
    Set tDigest = ""
    Try {
        ; ---- Query qualifying user rows.
        ; Use %SQL.Statement with parameter binding; %EXACT() on string
        ; columns per project rule §"IRIS SQL Case Sensitivity". We do
        ; NOT cap at TOP ..#MaxEntries in SQL because the AC-4 truncation
        ; marker requires knowing the TOTAL count of qualifying rows so
        ; the marker reports "(N more aliases hidden)" accurately. Cap
        ; happens row-by-row during render below.
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare(
            "SELECT " _
            "%EXACT(Alias) AS al, " _
            "%EXACT(MessageBodyClass) AS mbc, " _
            "%EXACT(CreatedVia) AS cv, " _
            "Confidence AS cf, " _
            "%EXACT(LastUsed) AS lu " _
            "FROM SessionAgent_Search.UserVocabulary " _
            "WHERE %EXACT(PortalUser) = ? AND Confidence >= ? " _
            "ORDER BY Confidence DESC, %EXACT(LastUsed) DESC")
        If $$$ISERR(tPrepSC) Set tDigest = ..SeedFallback() Quit

        Set tRs = tStmt.%Execute(pPortalUser, ..#MinUserConfidence)

        ; ---- Collect rendered rows into a list (so we can apply the
        ; row-granular token cap and MaxEntries cap after rendering).
        Set tRows = ""
        Set tTotalRendered = 0
        While tRs.%Next() {
            Set tAlias = tRs.%Get("al")
            Set tBodyClass = tRs.%Get("mbc")
            Set tCreatedVia = tRs.%Get("cv")
            Set tConfidence = +tRs.%Get("cf")
            ; Descriptor: prefer MessageBodyClass, else CreatedVia, else placeholder.
            Set tDescriptor = "saved alias"
            If tBodyClass '= "" {
                Set tDescriptor = tBodyClass
            } ElseIf tCreatedVia '= "" {
                Set tDescriptor = tCreatedVia
            }
            ; Confidence rounded to 2 decimals via $FNumber per spec.
            Set tConfStr = $FNumber(tConfidence, "", 2)
            ; Em-dash U+2014 between alias and descriptor.
            Set tRowText = "- """ _ tAlias _ """ " _ $Char(8212) _ " " _ tDescriptor _ " (confidence " _ tConfStr _ ")"
            Set tRows = tRows _ $ListBuild(tRowText)
            Set tTotalRendered = tTotalRendered + 1
        }

        ; ---- Branch: zero qualifying rows → seed fallback.
        If tTotalRendered = 0 {
            Set tDigest = ..SeedFallback()
            Quit
        }

        ; ---- Render the user-aliases digest with MaxEntries + token-budget caps.
        Set tHeader = "## Saved aliases for this user" _ $Char(10) _ $Char(10)
        Set tDigest = tHeader

        ; Greedy include rows up to BOTH:
        ;  - ..#MaxEntries cap (max row count)
        ;  - 1200 tokens cap via $Length(digest) \ 4 rule-of-thumb.
        ; Row-granular truncation: if adding the next row would push past
        ; either cap, stop. AC-4 marker fires when truncation occurs.
        Set tIncluded = 0
        Set tPtr = 0
        Set tBudgetExceeded = 0
        While $ListNext(tRows, tPtr, tRowText) {
            ; MaxEntries gate.
            If tIncluded >= ..#MaxEntries {
                Set tBudgetExceeded = 1
                Quit
            }
            ; Token-budget gate.
            Set tCandidate = tDigest _ tRowText _ $Char(10)
            Set tEstTokens = $Length(tCandidate) \ 4
            If tEstTokens > 1200 {
                Set tBudgetExceeded = 1
                Quit
            }
            Set tDigest = tCandidate
            Set tIncluded = tIncluded + 1
        }

        ; If any cap kicked in (i.e., included < total rendered), append marker.
        ; Per AC-4: marker ONLY when truncation actually happened.
        If tBudgetExceeded || (tIncluded < tTotalRendered) {
            Set tHidden = tTotalRendered - tIncluded
            Set tDigest = tDigest _ $Char(10) _ "_(" _ tHidden _ " more aliases hidden " _ $Char(8212) _ " increase confidence threshold or use vocab_lookup tool to see all)_" _ $Char(10)
        }
    }
    Catch ex {
        ; Defensive — if anything fails, fall back to seed so the digest
        ; is never empty. The LLM gets at least the seed-idiom grounding.
        ; BUT — capture the exception details to a process-private global
        ; so dev-time programming errors (schema drift, METHOD DOES NOT
        ; EXIST, UNDEFINED) surface during dev/test instead of being
        ; silently masked. The AgentLoop consumer (Story 9.4) keeps
        ; running on seed fallback per design rationale; the dev sees
        ; ^||SessionAgent.VocabDigest.LastError on inspection.
        Set ^||SessionAgent.VocabDigest.LastError = $ZDateTime($ZTimeStamp, 3, 1) _ "Z | " _ ex.DisplayString() _ " | code=" _ ex.Code _ " | location=" _ ex.Location
        Set tDigest = ..SeedFallback()
    }
    Quit tDigest
}

/// <p>Story 9.3 AC-3 — seed-vocabulary fallback digest for first-time
/// users (zero qualifying <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// rows). Queries the top-5
/// <CLASS>SessionAgent.Search.SeedVocabulary</CLASS> rows ordered by
/// <code>ID ASC</code> (insertion order = curated install-time priority
/// per Story 8.1 <method>Seed</method>) and renders them under a header
/// that explicitly tells the operator their personal vocabulary is empty
/// (no surprise; sets correct expectations).</p>
///
/// <p><b>Per-row format:</b>
/// <code>- "&lt;Alias&gt;" — &lt;Description&gt; (seed)</code> where
/// <var>Description</var> is the seed row's full operator-readable
/// description (truncated to ~200 chars if longer, defensive).</p>
///
/// <p><b>Returns:</b> rendered Markdown digest. If the seed extent is
/// empty (the install-time <method>Seed</method> never ran), returns a
/// minimal stub digest so callers never see an empty string.</p>
ClassMethod SeedFallback() As %String [ Internal ]
{
    Set tDigest = "## Common idioms (no personal aliases yet)" _ $Char(10) _ $Char(10)
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare(
            "SELECT TOP 5 " _
            "%EXACT(Alias) AS al, " _
            "%EXACT(Description) AS dc " _
            "FROM SessionAgent_Search.SeedVocabulary " _
            "ORDER BY ID ASC")
        If $$$ISERR(tPrepSC) Quit

        Set tRs = tStmt.%Execute()
        Set tRowCount = 0
        While tRs.%Next() {
            Set tAlias = tRs.%Get("al")
            Set tDesc = tRs.%Get("dc")
            ; Defensive truncation — Description is MAXLEN=2048 in
            ; SeedVocabulary; cap at ~200 chars for the digest to keep
            ; the per-row footprint compact.
            If $Length(tDesc) > 200 {
                Set tDesc = $Extract(tDesc, 1, 197) _ "..."
            }
            ; Em-dash U+2014 separator.
            Set tDigest = tDigest _ "- """ _ tAlias _ """ " _ $Char(8212) _ " " _ tDesc _ " (seed)" _ $Char(10)
            Set tRowCount = tRowCount + 1
        }
    }
    Catch ex {
        ; Swallow — fallback already has the header; an empty body is
        ; better than an exception bubbling to the AgentLoop.
    }
    Quit tDigest
}

}
