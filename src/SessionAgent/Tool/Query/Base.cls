/// <p><b>Abstract base class for SessionAgent guarded dynamic-SQL Query
/// tools</b> (Story 14.3 / FR60). Concrete subclasses ship under
/// <code>SessionAgent.Tool.Query.*</code> and MUST route every execution
/// through the single protected pipeline entry point
/// <method>RunGuardedSelect</method> — the CI invariant test
/// <CLASS>SessionAgent.Test.ReadOnlySqlInvariantTest</CLASS> rejects any
/// concrete Query tool whose <code>Invoke</code> calls
/// <code>%Prepare</code>/<code>%Execute</code> directly.</p>
///
/// <p><b>Guard pipeline (AC-1).</b></p>
/// <ol>
/// <li><b>Single-statement validation</b> — semicolons outside string
/// literals AND outside comments are rejected (trailing semicolons
/// tolerated; a semicolon inside a <code>/* */</code> or <code>--</code>
/// comment does not false-reject a single SELECT); a leading
/// <code>EXPLAIN</code> keyword is ALLOWED only when the keyword that
/// follows it is <code>SELECT</code> (Story 14.6 plan-reasoning
/// allowance — any case, comment/whitespace-prefixed and
/// comment-interleaved handled identically); <code>EXPLAIN</code> of
/// any non-SELECT inner statement (INSERT / UPDATE / DELETE / WITH /
/// parenthesized) is rejected — the conservative
/// reject-inner-write default (see empirical note below).</li>
/// <li><b><code>%Prepare</code></b> — failure routes through
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnPrepareFailure</method>
/// plus an appended SQLCODE/symptom <code>hint</code> drawn from the
/// knowledge corpus's <code>diagnostic-checklist</code> article.</li>
/// <li><b><code>statementType</code> gate</b> — the compiler-level
/// read-only gate. Only <code>%Metadata.statementType = 1</code> (SELECT
/// per <code>irislib/%SQL/StatementMetadata.cls</code>; re-verified
/// empirically on this install: SELECT=1, INSERT=2, UPDATE=3, DELETE=4,
/// CALL=45) or <code>= 79</code> (the documented EXPLAIN type — accepted
/// defensively for builds that report it; THIS build reports 1 for
/// EXPLAIN) passes; anything else returns a
/// <code>render_strategy:"not_select"</code> error envelope naming the
/// rejected statement type.</li>
/// <li><b>Execute</b> — failure routes through
/// <method>SessionAgent.Tool.Base.EnsureIsErrorOnExecuteFailure</method>
/// plus the SQLCODE hint.</li>
/// <li><b>Capped, elapsed-guarded fetch</b> — row cap, total result char
/// budget with an explicit <code>truncated</code> marker, an elapsed
/// check between fetch iterations, and a post-loop fetch-fault gate
/// (negative <code>%SQLCODE</code> after <code>%Next()</code> returns 0
/// is an error; <code>100</code> is clean done — the Story 14.2-review
/// reference pattern).</li>
/// <li><b>Envelope shaping</b> — <code>columns</code> array +
/// <code>rows</code> + <code>row_count</code>, <code>truncated</code>,
/// <code>elapsed_ms</code> in <code>structuredContent</code>.</li>
/// </ol>
///
/// <p><b>EXPLAIN empirical note (Story 14.3 Task 0 + Story 14.6 Task 0,
/// 2026-06-11).</b> On this IRIS build EVERY <code>EXPLAIN ...</code>
/// statement prepares with <code>statementType = 1</code>, NOT the
/// documented 79 — the statementType gate cannot distinguish EXPLAIN
/// from SELECT, so stage 1 owns the EXPLAIN policy. Story 14.6 probes:
/// <code>EXPLAIN SELECT</code> executes plan-only (one row, one
/// <code>Plan</code> column of XML showplan); <code>EXPLAIN INSERT</code>
/// prepares but FAILS at execute (SQLCODE -481) and writes nothing;
/// <code>EXPLAIN DELETE</code> against a MATCHING row executes, returns
/// a plan row, and the target row SURVIVES (plan-only proven). Policy:
/// <code>EXPLAIN SELECT</code> is allowed; EXPLAIN of any non-SELECT
/// inner statement is rejected at stage 1 by inner keyword — the
/// conservative reject-inner-write default, because plan-only semantics
/// are a per-build empirical premise (the 1-vs-79 drift proves builds
/// vary) and the -481 execute failure makes the allowed path useless
/// for writes anyway.</p>
///
/// <p><b>Elapsed-guard semantics — stated honestly.</b> In-process
/// dynamic SQL cannot be preempted mid-statement. The guard fires
/// BETWEEN fetch iterations; a single long-running <code>%Execute</code>
/// is bounded only by the Web Gateway's 300-second backstop. This class
/// does NOT claim preemption.</p>
///
/// <p><b>Residual risk (documented, accepted — proposal §4.2 item 1).</b>
/// A SELECT statement can invoke SQL-projected class methods (stored
/// functions/procedures referenced in expressions) that have side
/// effects — the statementType gate proves the OUTER statement is a
/// SELECT, not that every function it calls is pure. Mitigations:
/// L3 RBAC (<code>SessionAgent_ReadOnly</code> role on the executing
/// context), 100% ToolCall audit (the args JSON carries the full SQL
/// text), and the read-only prompt covenant. Optional future hardening
/// (a restricted-privilege execution job) is explicitly out of scope
/// for v1.</p>
///
/// <p><b>SQL-injection posture (adapted 4 layers — the input IS SQL by
/// design).</b> L1 = schema-description priming on the concrete tool's
/// <code>sql</code> arg; L2 = the statementType compiler gate (stronger
/// than any regex); L3 = parameterless single-statement execution with
/// caps — NOTHING is ever concatenated into the operator's SQL text and
/// no parameter substitution is performed on it; L4 = reviewer confirms
/// 1–3 explicitly.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/14-3-execute-readonly-sql-tool-query-base-invariant-test.md">Story 14.3</a> — AC-1 source.</li>
/// <li><a href="../Search/Base.cls">SessionAgent.Tool.Search.Base</a> — family-base precedent.</li>
/// <li><code>irislib/%SQL/Statement.cls</code> / <code>StatementMetadata.cls</code> / <code>StatementResult.cls</code> — API behavior.</li>
/// </ul>
Class SessionAgent.Tool.Query.Base Extends SessionAgent.Tool.Base [ Abstract ]
{

/// <p>Default row cap applied when the caller supplies no
/// <code>max_rows</code> (AR10 calibration pattern).</p>
Parameter DEFAULTMAXROWS As %Integer = 50;

/// <p>Hard ceiling on the row cap — caller-supplied values above this
/// are clamped down to it.</p>
Parameter HARDMAXROWS As %Integer = 200;

/// <p>Total result character budget across all fetched cell values.
/// When accumulating the next row would exceed it, the fetch stops and
/// the envelope carries <code>truncated = true</code>.</p>
Parameter RESULTCHARBUDGET As %Integer = 32000;

/// <p>Default elapsed guard in seconds — checked between fetch
/// iterations (NOT preemptive; see class doc-comment).</p>
Parameter DEFAULTELAPSEDGUARDSEC As %Integer = 30;

/// <p>Hard ceiling on the elapsed guard in seconds.</p>
Parameter HARDELAPSEDGUARDSEC As %Integer = 60;

/// <p><b>The single guarded execution entry point (AC-1).</b> Every
/// concrete <code>SessionAgent.Tool.Query.*</code> tool's
/// <code>Invoke</code> MUST route SQL execution through this method —
/// no direct <code>%Prepare</code>/<code>%Execute</code> calls outside
/// it (enforced by <CLASS>SessionAgent.Test.ReadOnlySqlInvariantTest</CLASS>).</p>
///
/// <p>Initializes <var>pResult</var> to the canonical success-shape
/// envelope, runs the 6-stage guard pipeline, and returns
/// <code>$$$OK</code> always — success vs failure is signaled inside
/// the envelope (<code>isError</code>). <var>pMaxRows</var> is clamped
/// to <code>1..HARDMAXROWS</code> with <code>DEFAULTMAXROWS</code>
/// substituted for missing/non-positive input.
/// <var>pElapsedGuardSec</var> defaults to
/// <code>DEFAULTELAPSEDGUARDSEC</code> and is clamped to
/// <code>HARDELAPSEDGUARDSEC</code>.</p>
ClassMethod RunGuardedSelect(pSql As %String, pMaxRows As %Integer = 0, Output pResult As %DynamicObject, pElapsedGuardSec As %Integer = 0) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        Set tStart = $ZHorolog

        ; ---- Clamp calibration inputs (defensive — concrete tools also clamp). ----
        Set tMaxRows = +$Get(pMaxRows)
        If tMaxRows < 1 Set tMaxRows = ..#DEFAULTMAXROWS
        If tMaxRows > ..#HARDMAXROWS Set tMaxRows = ..#HARDMAXROWS
        Set tGuardSec = +$Get(pElapsedGuardSec)
        If tGuardSec < 1 Set tGuardSec = ..#DEFAULTELAPSEDGUARDSEC
        If tGuardSec > ..#HARDELAPSEDGUARDSEC Set tGuardSec = ..#HARDELAPSEDGUARDSEC

        ; ---- Stage 1: single-statement validation. ----
        Set tSql = ..ValidateSingleStatement(pSql, .tValidationError, .tValidationStrategy)
        If tValidationError '= "" {
            Do pResult.%Set("isError", 1, "boolean")
            Set pResult.content.%Get(0).text = "Tool '" _ ..#ToolName _ "': " _ tValidationError
            Do pResult.structuredContent.%Set("render_strategy", tValidationStrategy)
            Do pResult.structuredContent.%Set("error_text", tValidationError)
            Quit
        }

        ; ---- Stage 2: %Prepare (ODBC select mode for stable timestamp /
        ;      decode rendering — set on the instance PRE-%Prepare, per
        ;      irislib/%SQL/Statement.cls line 243; Task 0 verified ODBC
        ;      renders Ens.DataType.UTC as UTC ODBC text). ----
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tStmt.%SelectMode = 1
        Set tSCp = tStmt.%Prepare(tSql)
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnPrepareFailure(pResult, tSCp, ..#ToolName) {
            Do ..AppendSqlcodeHint(pResult, ..ExtractSqlcodeFromStatus(tSCp))
            Quit
        }

        ; ---- Stage 3: statementType compiler gate (the read-only gate).
        ;      1 = SELECT; 79 = documented EXPLAIN type, accepted
        ;      defensively (Story 14.6 — this build reports 1 for
        ;      EXPLAIN, but a build that reports 79 must not reject the
        ;      stage-1-approved EXPLAIN SELECT). ----
        Set tType = tStmt.%Metadata.statementType
        If (tType '= 1) && (tType '= 79) {
            Set tTypeName = ..StatementTypeName(tType)
            Do pResult.%Set("isError", 1, "boolean")
            Set pResult.content.%Get(0).text = "Tool '" _ ..#ToolName _ "' rejected non-SELECT statement: " _ tTypeName _ " (statementType=" _ tType _ "). Only a single SELECT is allowed."
            Do pResult.structuredContent.%Set("render_strategy", "not_select")
            Do pResult.structuredContent.%Set("rejected_statement_type", tTypeName)
            Do pResult.structuredContent.%Set("statement_type_code", tType, "number")
            Quit
        }

        ; ---- Stage 4: Execute (parameterless — L3: nothing is ever
        ;      concatenated into or substituted into the operator's SQL). ----
        Set tRS = tStmt.%Execute()
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) {
            If $IsObject($Get(tRS)) Do ..AppendSqlcodeHint(pResult, tRS.%SQLCODE)
            Quit
        }

        ; ---- Stage 5: capped, elapsed-guarded fetch. ----
        Set tColumns = []
        Set tColCount = tStmt.%Metadata.columnCount
        For i = 1:1:tColCount {
            Do tColumns.%Push(tStmt.%Metadata.columns.GetAt(i).colName)
        }
        Set tRows = []
        Set tRowCount = 0
        Set tCharsUsed = 0
        Set tTruncated = 0
        Set tTruncateReason = ""
        While tRS.%Next() {
            ; Elapsed guard — fires BETWEEN fetch iterations (not preemptive).
            If ($ZHorolog - tStart) > tGuardSec {
                Set tTruncated = 1, tTruncateReason = "elapsed_guard"
                Quit
            }
            ; Build the row + measure its char weight.
            Set tRow = []
            Set tRowChars = 0
            For i = 1:1:tColCount {
                Set tVal = tRS.%GetData(i)
                Set tRowChars = tRowChars + $Length(tVal)
                Do tRow.%Push(tVal)
            }
            ; Char budget — adding this row would exceed it.
            If (tCharsUsed + tRowChars) > ..#RESULTCHARBUDGET {
                Set tTruncated = 1, tTruncateReason = "char_budget"
                Quit
            }
            Set tCharsUsed = tCharsUsed + tRowChars
            Do tRows.%Push(tRow)
            Set tRowCount = tRowCount + 1
            ; Row cap.
            If tRowCount >= tMaxRows {
                ; Mark truncated only if more rows remain.
                If tRS.%Next() {
                    Set tTruncated = 1, tTruncateReason = "row_cap"
                }
                Quit
            }
        }
        ; Post-loop fetch-fault gate (Story 14.2-review reference pattern) —
        ; a negative %SQLCODE after %Next() returns 0 is a runtime fetch
        ; fault; 100 is clean end-of-data. Partial rows must not ship
        ; inside an ok envelope.
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) {
            Do ..AppendSqlcodeHint(pResult, tRS.%SQLCODE)
            Quit
        }

        ; ---- Stage 6: envelope shaping. ----
        Set tElapsedMs = $Normalize(($ZHorolog - tStart) * 1000, 0)
        Do pResult.structuredContent.%Set("render_strategy", "ok")
        Do pResult.structuredContent.%Set("columns", tColumns)
        Do pResult.structuredContent.%Set("rows", tRows)
        Do pResult.structuredContent.%Set("row_count", tRowCount, "number")
        Do pResult.structuredContent.%Set("truncated", tTruncated, "boolean")
        If tTruncated Do pResult.structuredContent.%Set("truncate_reason", tTruncateReason)
        Do pResult.structuredContent.%Set("elapsed_ms", tElapsedMs, "number")
        Set pResult.content.%Get(0).text = ..#ToolName _ ": " _ tRowCount _ " row(s), " _ tColCount _ " column(s)" _ $Select(tTruncated:" [truncated: " _ tTruncateReason _ "]", 1:"") _ ", " _ tElapsedMs _ " ms"
        Quit
    }
    Catch ex {
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}]}
    }
    Quit tSC
}

/// <p>Stage-1 helper — single-statement validation. Returns the
/// normalized SQL text (trailing semicolons stripped) and sets
/// <var>pError</var> to a non-empty message on rejection:</p>
/// <ul>
/// <li>Empty/whitespace-only input.</li>
/// <li>Leading <code>EXPLAIN</code> keyword followed by anything other
/// than <code>SELECT</code> (Story 14.6 allowance: <code>EXPLAIN
/// SELECT ...</code> passes — plan-only, write-proofed; <code>EXPLAIN
/// INSERT/UPDATE/DELETE/WITH/(...)</code> is rejected — the
/// conservative reject-inner-write default; EXPLAIN prepares as
/// statementType=1 on this build, so this keyword check is the honest
/// policy point). The token scan is COMMENT-AWARE for BOTH tokens — a
/// block- or line-comment prefix (<code>/* c */ EXPLAIN ...</code>,
/// <code>-- c\nEXPLAIN ...</code>) or an interleaved comment
/// (<code>EXPLAIN /* c */ INSERT</code>) cannot smuggle a shape past
/// the check (Story 14.3 review fix cr-14-3-A, extended by 14.6).</li>
/// <li>A semicolon outside string literals AND outside comments that is
/// not trailing — multi-statement input. Semicolons INSIDE
/// <code>'...'</code> literals (with <code>''</code> escape-doubling
/// honored) OR inside <code>/* */</code> / <code>--</code> comments are
/// fine — a legitimate single SELECT carrying a comment with a semicolon
/// is NOT false-rejected (Story 14.3 review fix cr-14-3-B).</li>
/// </ul>
/// <p>Defense-in-depth note: this scanner is belt-and-suspenders. The
/// security control is the stage-3 <code>statementType</code> compiler
/// gate (only type 1 = SELECT passes) plus <code>%Prepare</code>'s own
/// rejection of multi-statement input (SQLCODE -25). Making the scanner
/// comment-aware removes false-positives without weakening the gate.</p>
ClassMethod ValidateSingleStatement(pSql As %String, Output pError As %String, Output pStrategy As %String) As %String
{
    Set pError = ""
    Set pStrategy = ""
    Set tSql = $ZStrip($Get(pSql), "<>WC")
    If tSql = "" {
        Set pError = "sql is required and must be a single SELECT statement"
        Set pStrategy = "validation_error"
        Quit ""
    }
    ; Strip trailing semicolons (tolerated) + interleaved whitespace.
    While $Extract(tSql, *) = ";" {
        Set tSql = $ZStrip($Extract(tSql, 1, *-1), ">WC")
    }
    If tSql = "" {
        Set pError = "sql is required and must be a single SELECT statement"
        Set pStrategy = "validation_error"
        Quit ""
    }
    ; --- Comment-aware single-pass scan. Tracks string-literal, block-
    ;     comment (/* */) and line-comment (--) state. Captures the first
    ;     TWO significant SQL keywords (for the EXPLAIN allowance check —
    ;     Story 14.6: `EXPLAIN SELECT` passes, `EXPLAIN <anything else>`
    ;     is rejected; comments are transparent BETWEEN tokens so neither
    ;     a comment prefix nor an interleaved comment can hide a shape)
    ;     and flags a bare semicolon (a statement separator) only when it
    ;     sits outside all three states (so a comment carrying a ';' does
    ;     not false-reject a single SELECT). ---
    Set tInString = 0
    Set tInBlock = 0
    Set tInLine = 0
    Set tLen = $Length(tSql)
    Set tPos = 1
    Set tTok1 = ""
    Set tTok2 = ""
    Set tCur = ""
    Set tCaptureDone = 0
    While tPos <= tLen {
        Set tChar = $Extract(tSql, tPos)
        Set tNext = $Extract(tSql, tPos + 1)
        If tInLine {
            If (tChar = $Char(10)) || (tChar = $Char(13)) Set tInLine = 0
            Set tPos = tPos + 1
            Continue
        }
        If tInBlock {
            If (tChar = "*") && (tNext = "/") {
                Set tInBlock = 0
                Set tPos = tPos + 2
            } Else {
                Set tPos = tPos + 1
            }
            Continue
        }
        If tInString {
            If tChar = "'" {
                ; '' inside a literal is an escaped quote — skip the pair.
                If tNext = "'" {
                    Set tPos = tPos + 2
                    Continue
                }
                Set tInString = 0
            }
            Set tPos = tPos + 1
            Continue
        }
        ; --- outside string + comments ---
        ; A comment ends an IN-PROGRESS token but is otherwise
        ; TRANSPARENT — the scan keeps looking for the next keyword, so
        ; `/* c */ EXPLAIN ...`, `-- c\nEXPLAIN ...` AND
        ; `EXPLAIN /* c */ INSERT` are all seen by the keyword checks.
        If (tChar = "/") && (tNext = "*") {
            Set tInBlock = 1
            If (tCur '= "") && ('tCaptureDone) {
                If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur  Set tCaptureDone = 1 }
                Set tCur = ""
            }
            Set tPos = tPos + 2
            Continue
        }
        If (tChar = "-") && (tNext = "-") {
            Set tInLine = 1
            If (tCur '= "") && ('tCaptureDone) {
                If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur  Set tCaptureDone = 1 }
                Set tCur = ""
            }
            Set tPos = tPos + 2
            Continue
        }
        If tChar = "'" {
            Set tInString = 1
            If (tCur '= "") && ('tCaptureDone) {
                If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur  Set tCaptureDone = 1 }
                Set tCur = ""
            }
            Set tCaptureDone = 1
            Set tPos = tPos + 1
            Continue
        }
        If tChar = ";" {
            Set pError = "multi-statement input rejected: semicolon found outside a string literal (only a single SELECT statement is accepted; a trailing semicolon is tolerated)"
            Set pStrategy = "multi_statement"
            Quit
        }
        ; Keyword capture (alphabetic runs) — up to two tokens for the
        ; EXPLAIN allowance check. Whitespace between tokens is skipped;
        ; a non-alpha significant char (e.g. '(' for a parenthesized
        ; SELECT) ends the capture — the statementType gate (and, for
        ; EXPLAIN, the SELECT-only inner-keyword rule) handles those.
        If 'tCaptureDone {
            If tChar?1A {
                Set tCur = tCur _ tChar
            } ElseIf $ZStrip(tChar, "*WC") = "" {
                ; whitespace — completes an in-progress token.
                If tCur '= "" {
                    If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur  Set tCaptureDone = 1 }
                    Set tCur = ""
                }
            } Else {
                ; significant non-alpha — completes the token AND ends capture.
                If tCur '= "" {
                    If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur }
                    Set tCur = ""
                }
                Set tCaptureDone = 1
            }
        }
        Set tPos = tPos + 1
    }
    If pError '= "" Quit ""
    ; End-of-input completes a trailing in-progress token.
    If (tCur '= "") && ('tCaptureDone) {
        If tTok1 = "" { Set tTok1 = tCur } Else { Set tTok2 = tCur }
    }
    ; --- Story 14.6 EXPLAIN allowance: EXPLAIN SELECT passes; EXPLAIN of
    ;     any other inner shape (INSERT/UPDATE/DELETE/WITH/parenthesized)
    ;     is rejected — the conservative reject-inner-write default
    ;     (plan-only semantics are a per-build premise; see class doc). ---
    If $ZConvert(tTok1, "U") = "EXPLAIN" {
        If $ZConvert(tTok2, "U") '= "SELECT" {
            Set pError = "EXPLAIN is allowed only for a single SELECT statement (EXPLAIN SELECT ...); EXPLAIN of INSERT/UPDATE/DELETE or any other non-SELECT shape is rejected"
            Set pStrategy = "not_select"
            Quit ""
        }
    }
    Quit tSql
}

/// <p>AC-4 — append a <code>hint</code> drawn from the knowledge
/// corpus's <code>diagnostic-checklist</code> article (Story 14.1 locked
/// contract: <code>SQLCODE &lt;n&gt; / symptom -&gt; fix</code> lines).
/// Reads the article body at failure time via the generated unique-index
/// accessor (cheap single-row read; no caching needed) and matches the
/// line whose second space-delimited token equals the failing SQLCODE.
/// Falls back to a generic consult-the-corpus hint when no line matches
/// or the article is absent. Composes AFTER the
/// <code>EnsureIsErrorOn*Failure</code> helper shaped the canonical
/// envelope.</p>
ClassMethod AppendSqlcodeHint(pResult As %DynamicObject, pSqlcode As %String)
{
    Set tHint = ""
    Try {
        If (pSqlcode '= "") && (+pSqlcode < 0) {
            Set tArticle = ##class(SessionAgent.Knowledge.Article).SlugIdxOpen("diagnostic-checklist")
            If $IsObject(tArticle) {
                Set tBody = tArticle.Body
                For i = 1:1:$Length(tBody, $Char(10)) {
                    Set tLine = $Piece(tBody, $Char(10), i)
                    If ($Extract(tLine, 1, 8) = "SQLCODE ") && ($Piece(tLine, " ", 2) = (+pSqlcode)) {
                        Set tHint = tLine
                        Quit
                    }
                }
            }
        }
    }
    Catch ex {
        Set tHint = ""
    }
    If tHint = "" {
        Set tHint = "No SQLCODE-specific hint matched; consult get_query_knowledge topic=methodology (diagnostic-checklist article) and topic=dialect for IRIS SQL traps."
    }
    Do pResult.structuredContent.%Set("hint", tHint)
    If pResult.content.%Size() > 0 {
        Set pResult.content.%Get(0).text = pResult.content.%Get(0).text _ " Hint: " _ tHint
    }
    Quit
}

/// <p>Extract the SQLCODE from a <code>%Prepare</code>-failure
/// <code>%Status</code> error text. Keys on the locale-independent
/// <code>"SQLCODE: "</code> marker (Task 0 verified the error prefix
/// itself is locale-dependent on this server — never key on
/// <code>"ERROR #"</code>). Returns the signed integer as a string, or
/// <code>""</code> when no marker is present.</p>
ClassMethod ExtractSqlcodeFromStatus(pStatus As %Status) As %String
{
    Set tCode = ""
    Try {
        Set tText = $System.Status.GetErrorText(pStatus)
        Set tIdx = $Find(tText, "SQLCODE: ")
        If tIdx > 0 {
            Set tTail = $ZStrip($Extract(tText, tIdx, *), "<W")
            Set tToken = $Piece($Translate(tTail, $Char(9), " "), " ", 1)
            If +tToken '= 0 Set tCode = +tToken
        }
    }
    Catch ex {
        Set tCode = ""
    }
    Quit tCode
}

/// <p>Map a <code>statementType</code> code to its human-readable name
/// for the <code>not_select</code> envelope (values per
/// <code>irislib/%SQL/StatementMetadata.cls</code> lines 25–105;
/// Task 0 re-verified 1/2/3/4/45 empirically on this install).</p>
ClassMethod StatementTypeName(pType As %Integer) As %String
{
    Quit $Case(pType,
        2: "INSERT",
        3: "UPDATE",
        4: "DELETE",
        5: "COMMIT",
        6: "ROLLBACK",
        7: "GRANT",
        8: "REVOKE",
        9: "CREATE TABLE",
        10: "ALTER TABLE",
        11: "DROP TABLE",
        12: "CREATE VIEW",
        14: "DROP VIEW",
        15: "CREATE INDEX",
        17: "DROP INDEX",
        33: "GRANT",
        34: "REVOKE",
        37: "CREATE PROCEDURE",
        45: "CALL",
        47: "LOCK TABLE",
        52: "TUNE TABLE",
        65: "PURGE",
        79: "EXPLAIN",
        : "statementType=" _ pType)
}

}
