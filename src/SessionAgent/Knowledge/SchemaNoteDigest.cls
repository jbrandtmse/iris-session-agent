/// <p>Story 14.4 (FR63 / D4) — learned-schema-notes digest assembly for
/// the first-user-message prefix injection in
/// <CLASS>SessionAgent.Agent.AgentLoop</CLASS> (the Story 9.4 two-array
/// channel, extended to BOTH agents by Story 14.4). Renders the
/// namespace's most-recently-verified
/// <CLASS>SessionAgent.Knowledge.SchemaNote</CLASS> rows as a Markdown
/// digest the LLM can scan, each line carrying the subject, an age
/// marker (staleness signal), and a one-line note snippet.</p>
///
/// <p><b>Mirrors <CLASS>SessionAgent.Search.VocabularyDigest</CLASS>
/// §Build</b> — class-parameter caps, row-granular truncation, hidden-
/// rows marker — with ONE deliberate difference: there is NO seed
/// fallback. A namespace with zero notes returns the empty string and
/// the AgentLoop's empty-digest collapse drops the prefix block
/// gracefully (no orphan delimiter). Empty is correct: a brand-new
/// namespace has nothing learned yet.</p>
///
/// <p><b>NFR-P6 prompt-cache discipline.</b> The AgentLoop injects this
/// digest into the FIRST USER MESSAGE — never into the cached
/// <code>system + tools</code> prefix — so the Anthropic prompt-cache
/// hit rate stays high across turns. This class produces the digest
/// text but does not orchestrate the injection.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/14-4-learned-schema-notes-digest-injection.md">Story 14.4</a> — AC-5 source.</li>
/// <li><a href="../Search/VocabularyDigest.cls">SessionAgent.Search.VocabularyDigest</a> — the Build-shape precedent.</li>
/// </ul>
Class SessionAgent.Knowledge.SchemaNoteDigest Extends %RegisteredObject
{

/// <p>Maximum number of <CLASS>SessionAgent.Knowledge.SchemaNote</CLASS>
/// rows included in the digest. Beyond this cap the row-list is
/// truncated and a <code>(N more schema note(s) hidden ...)</code>
/// marker appended pointing the LLM at <code>get_schema_notes</code>.</p>
Parameter MAXENTRIES As %Integer = 10;

/// <p>Hard cap on the total rendered digest size in characters.
/// Truncation is row-granular — never cut a row mid-string. With
/// <code>Subject MAXLEN=256</code> + the 160-char snippet cap a single
/// line tops out around ~450 chars, so the cap binds before
/// <parameter>MAXENTRIES</parameter> only when subjects/snippets run
/// long.</p>
Parameter MAXCHARS As %Integer = 2000;

/// <p>Per-line note-snippet cap — keeps each digest line scannable; the
/// full body is one <code>get_schema_notes</code> call away.</p>
Parameter SNIPPETCHARS As %Integer = 160;

/// <p>Story 14.4 AC-5 — assemble the learned-schema-notes digest for
/// <var>pNamespace</var>. Queries
/// <CLASS>SessionAgent.Knowledge.SchemaNote</CLASS> rows for the
/// namespace ordered <code>VerifiedAt DESC</code> (most recently
/// verified first), caps at <parameter>MAXENTRIES</parameter> rows /
/// <parameter>MAXCHARS</parameter> chars (row-granular), and renders as
/// Markdown.</p>
///
/// <p><b>Per-row format:</b>
/// <code>- "&lt;Subject&gt;" (verified today | verified N day(s) ago):
/// &lt;snippet&gt;</code> — the age marker surfaces staleness per FR63.</p>
///
/// <p><b>Returns:</b> the rendered Markdown digest, or <code>""</code>
/// when the namespace has no notes (no seed fallback — see class
/// doc-comment). Defensive failures also return <code>""</code> (the
/// injection collapses gracefully); exception details are captured to
/// <code>^||SessionAgent.SchemaDigest.LastError</code> so dev-time
/// errors surface on inspection instead of being silently masked
/// (VocabularyDigest precedent).</p>
ClassMethod Build(pNamespace As %String) As %String
{
    Set tDigest = ""
    Try {
        If $Get(pNamespace) = "" Quit

        ; Total row count first (Story 14.4 review fix — bounded work):
        ; the digest runs on EVERY agent's first turn, so it must not
        ; scan the namespace's full note set. COUNT(*) supplies the
        ; hidden-rows marker arithmetic; TOP MAXENTRIES bounds the fetch.
        Set tCntStmt = ##class(%SQL.Statement).%New()
        Set tCntPrepSC = tCntStmt.%Prepare(
            "SELECT COUNT(*) AS cnt FROM SessionAgent_Knowledge.SchemaNote WHERE %EXACT(Namespace) = ?")
        If $$$ISERR(tCntPrepSC) Quit ; tDigest stays "" — graceful collapse
        Set tCntRs = tCntStmt.%Execute(pNamespace)
        If ('$IsObject(tCntRs)) || (tCntRs.%SQLCODE < 0) Quit
        Set tTotal = 0
        If tCntRs.%Next() Set tTotal = +tCntRs.%Get("cnt")
        If tTotal = 0 Quit

        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare(
            "SELECT TOP " _ (+..#MAXENTRIES) _ " %EXACT(Subject) AS sub, %EXACT(Body) AS bod, VerifiedAt AS va " _
            "FROM SessionAgent_Knowledge.SchemaNote " _
            "WHERE %EXACT(Namespace) = ? " _
            "ORDER BY VerifiedAt DESC, %EXACT(Subject) ASC")
        If $$$ISERR(tPrepSC) Quit ; tDigest stays "" — graceful collapse

        Set tRs = tStmt.%Execute(pNamespace)
        If ('$IsObject(tRs)) || (tRs.%SQLCODE < 0) Quit

        Set tHeader = "## Learned schema notes for this namespace" _ $Char(10) _ $Char(10)
        Set tBody = ""
        Set tIncluded = 0
        Set tNowDay = $Piece($ZTimeStamp, ",", 1)
        While tRs.%Next() {
            ; Row-count cap — defensive only; the TOP clause already
            ; bounds the fetch to MAXENTRIES rows.
            If tIncluded >= ..#MAXENTRIES Quit

            ; Renderer-side sanitization (Story 14.4 review fix —
            ; defense-in-depth): the tool boundary normalizes subjects,
            ; but SchemaNote.Upsert is a public API and SQL UPDATE
            ; bypasses it entirely — a newline-bearing Subject must not
            ; be able to forge the "\n\n---\n\n" prefix-block delimiter.
            Set tSubject = $Translate(tRs.%Get("sub"), $Char(9) _ $Char(13) _ $Char(10), "   ")
            Set tNoteBody = tRs.%Get("bod")
            Set tVa = tRs.%Get("va")

            ; Age marker (UTC-to-UTC day delta; clamp at 0).
            Set tAgeMarker = "age unknown"
            If tVa '= "" {
                Set tAgeDays = tNowDay - $Piece($ZDateTimeH(tVa, 3), ",", 1)
                If tAgeDays < 0 Set tAgeDays = 0
                Set tAgeMarker = $Select(tAgeDays = 0: "verified today", 1: "verified " _ tAgeDays _ " day(s) ago")
            }

            ; One-line snippet: collapse internal whitespace, cap length.
            Set tSnippet = $Translate(tNoteBody, $Char(9) _ $Char(13) _ $Char(10), "   ")
            If $Length(tSnippet) > ..#SNIPPETCHARS {
                Set tSnippet = $Extract(tSnippet, 1, ..#SNIPPETCHARS - 3) _ "..."
            }

            Set tLine = "- """ _ tSubject _ """ (" _ tAgeMarker _ "): " _ tSnippet _ $Char(10)

            ; MAXCHARS row-granular gate — header + accumulated body +
            ; this line must fit; otherwise STOP (Story 14.4 review fix:
            ; skipping just the over-long row and admitting later — older
            ; — rows inverted the most-recently-verified-first priority;
            ; stop-on-cap mirrors the VocabularyDigest precedent).
            If ($Length(tHeader) + $Length(tBody) + $Length(tLine)) > ..#MAXCHARS Quit

            Set tBody = tBody _ tLine
            Set tIncluded = tIncluded + 1
        }

        ; Zero notes (or nothing fit — impossible given the line-size
        ; bound, but defensive) → empty digest, graceful collapse.
        If tIncluded = 0 Quit

        Set tDigest = tHeader _ tBody
        If tTotal > tIncluded {
            Set tHidden = tTotal - tIncluded
            Set tDigest = tDigest _ $Char(10) _ "_(" _ tHidden _ " more schema note(s) hidden - use get_schema_notes to see all)_" _ $Char(10)
        }
    }
    Catch ex {
        ; Defensive — never let a digest failure break the AgentLoop
        ; turn; return "" (graceful collapse) but capture the exception
        ; for dev-time inspection (VocabularyDigest precedent).
        Set ^||SessionAgent.SchemaDigest.LastError = $ZDateTime($ZTimeStamp, 3, 1) _ "Z | " _ ex.DisplayString() _ " | code=" _ ex.Code _ " | location=" _ ex.Location
        Set tDigest = ""
    }
    Quit tDigest
}

}
