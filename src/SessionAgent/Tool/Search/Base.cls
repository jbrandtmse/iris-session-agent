/// <p><b>Abstract base class for all SessionAgent Search Agent tools</b>
/// (Stories 8.3–8.7). Concrete subclasses ship under
/// <code>SessionAgent.Tool.Search.*</code> and inherit the bounded-WHERE
/// invariant defined here.</p>
///
/// <p><b>Bounded-WHERE invariant (FR19, AR11, NFR-P2, NFR-SC1).</b> Every
/// concrete <code>SessionAgent.Tool.Search.*</code> tool issues SQL against
/// operator-grade <CLASS>Ens.MessageHeader</CLASS> extents that may carry
/// up to ten million rows. To prevent unbounded scans, every search SQL
/// query MUST satisfy at least one of the following two predicates as the
/// first filter in its <code>WHERE</code> clause:</p>
/// <ol>
/// <li><b>Time-window predicate</b> — <code>TimeCreated &gt; ?</code>
/// where the <code>?</code> is bound to a parameterized timestamp computed
/// from the caller-supplied (or default) time-window-hours. The helper
/// <method>BuildBoundedWhereClause</method> assembles this for callers.</li>
/// <li><b>Keyed-lookup predicate</b> — a single-row pick on an indexed
/// column (e.g., <code>SessionId = ?</code>, <code>SuperSessionKey = ?</code>).
/// A keyed-lookup IS its own bound; the time-window predicate may be
/// omitted (architecture §"OD8 keyed-lookup mode").</li>
/// </ol>
///
/// <p><b>Indexed-column registration.</b> Concrete subclasses MUST override
/// <method>GetIndexedLeadColumns</method> to declare which indexed columns
/// their queries rely on. The CI invariant test
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> reads this
/// list and rejects any tool that does not lead with at least one column
/// from the documented Ens.MessageHeader indexed set
/// (<code>TimeCreated</code>, <code>Status</code>,
/// <code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>, <code>SessionId</code>,
/// <code>SuperSessionKey</code>).</p>
///
/// <p><b>Calibration constants (architecture §"Calibration constants").</b>
/// Default time window is 24 hours; maximum is 720 hours (30 days). A
/// caller-supplied window above the maximum is rejected via a structured
/// error envelope; a caller-supplied window of <code>0</code> applies the
/// default; a sentinel value of <code>-1</code> selects keyed-lookup mode
/// (no time-window predicate emitted).</p>
///
/// <p><b>SQL safety.</b> All caller-supplied values flow through
/// parameterized <code>?</code> placeholders — <method>BuildBoundedWhereClause</method>
/// returns the WHERE-fragment text and a parallel <code>%DynamicArray</code>
/// of values for the prepared-statement bind pass. Concrete tools NEVER
/// concatenate user-controlled strings into the SQL text (architecture
/// §"Search-Arg-Construction Safety").</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 8.2</a> — AC source.</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// §"AR11 Bounded WHERE invariant", §"OD8 keyed-lookup mode",
/// §"Calibration constants", §"Search-Arg-Construction Safety".</li>
/// <li><a href="../../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR19, NFR-P2, NFR-SC1.</li>
/// </ul>
Class SessionAgent.Tool.Search.Base Extends SessionAgent.Tool.Base [ Abstract ]
{

/// <p>Default time-window in hours applied when the caller-supplied
/// <code>pTimeWindowHours</code> is <code>0</code> or omitted. Per
/// architecture §"Calibration constants" the default is
/// <b>24 hours</b> — a recent-history slice that aligns with operator
/// "what happened today" inspections without scanning the full extent.</p>
Parameter DefaultTimeWindowHours As %Integer = 24;

/// <p>Maximum allowed time-window in hours. A caller-supplied value
/// above this cap is rejected via a structured error envelope
/// (<code>errorCode = "TimeWindowTooLarge"</code>). Per architecture
/// §"Calibration constants" the maximum is <b>720 hours = 30 days</b> —
/// chosen to bound worst-case scan cost on a 10M-row Ens.MessageHeader
/// extent (NFR-P2, NFR-SC1).</p>
Parameter MaxTimeWindowHours As %Integer = 720;

/// <p><b>Sentinel value for keyed-lookup mode.</b> When a concrete tool
/// invokes <method>BuildBoundedWhereClause</method> with
/// <code>pTimeWindowHours = -1</code>, the helper omits the
/// <code>TimeCreated &gt; ?</code> predicate entirely — the caller has
/// declared that one of the <code>pAdditionalPredicates</code> entries
/// supplies the bound (a single-row pick on an indexed column, e.g.
/// <code>SessionId = ?</code>). Per architecture §"OD8 keyed-lookup mode".</p>
///
/// <p><b>Design choice (Story 8.2 dev note).</b> The keyed-lookup signal
/// rides on <code>pTimeWindowHours = -1</code> rather than a separate
/// <code>pKeyedLookup As %Boolean</code> parameter to avoid disturbing
/// the variadic <code>pAdditionalPredicates...</code> tail and keeping
/// the caller signature ergonomic. <code>-1</code> is unambiguous — a
/// negative time window has no real-world meaning.</p>
Parameter KeyedLookupSentinel As %Integer = -1;

/// <p>Return the list of indexed Ens.MessageHeader column names this
/// tool's queries rely on (e.g., <code>["TimeCreated", "Status"]</code>
/// or <code>["SessionId"]</code> for a keyed-lookup tool). Used by
/// <CLASS>SessionAgent.Test.BoundedWhereInvariantTest</CLASS> to
/// verify the tool satisfies the bounded-WHERE invariant — at least
/// one entry MUST appear in the documented indexed set
/// (<code>TimeCreated</code>, <code>Status</code>,
/// <code>SourceConfigName</code>, <code>TargetConfigName</code>,
/// <code>MessageBodyClassName</code>, <code>SessionId</code>,
/// <code>SuperSessionKey</code>).</p>
///
/// <p>Abstract method body returns an empty <code>%DynamicArray</code>;
/// per project rule §"Abstract Methods in ObjectScript" the curly-brace
/// body is REQUIRED for compilation even though concrete subclasses
/// always override.</p>
ClassMethod GetIndexedLeadColumns() As %DynamicArray [ Abstract ]
{
    Quit []
}

/// <p><b>Construct a bounded WHERE-clause fragment.</b> Returns the
/// fragment text (without the leading <code>WHERE</code> keyword) and
/// populates <var>pParams</var> with the parameterized values in order.
/// Concrete tools call this from inside their own <method>Invoke</method>
/// and concatenate the returned fragment into a <code>%SQL.Statement.%Prepare</code>
/// query, then bind <var>pParams</var> via <code>%Execute</code>.</p>
///
/// <p><b>Modes.</b></p>
/// <ul>
/// <li><b>Default-window mode</b> — <code>pTimeWindowHours = 0</code> or
/// omitted. The fragment leads with <code>TimeCreated &gt; ?</code> and
/// the first entry of <var>pParams</var> is the ODBC-form timestamp
/// representing <code>$ZTimeStamp - DefaultTimeWindowHours</code>.</li>
/// <li><b>Explicit-window mode</b> — <code>pTimeWindowHours &gt; 0</code>
/// and <code>&lt;= MaxTimeWindowHours</code>. Same shape, but the
/// timestamp is computed from the caller-supplied window.</li>
/// <li><b>Keyed-lookup mode</b> — <code>pTimeWindowHours = -1</code>
/// (KeyedLookupSentinel). The <code>TimeCreated</code> predicate is
/// OMITTED; the caller's <var>pAdditionalPredicates</var> are
/// concatenated as the entire fragment. The caller IS responsible for
/// supplying a single-row indexed pick (e.g.
/// <code>"SessionId = ?"</code>) and binding the corresponding
/// <var>pParams</var> entry.</li>
/// </ul>
///
/// <p><b>Error contract.</b> Returns the empty string AND sets
/// <var>pErr</var> to <code>{isError:1, errorCode, message, maxAllowed?}</code>
/// on rejection:</p>
/// <ul>
/// <li><code>pTimeWindowHours &gt; MaxTimeWindowHours</code> →
/// <code>errorCode="TimeWindowTooLarge"</code>,
/// <code>maxAllowed=720</code>.</li>
/// <li><code>pTimeWindowHours &lt; -1</code> (i.e., negative but not the
/// sentinel) → <code>errorCode="TimeWindowTooSmall"</code>.</li>
/// </ul>
///
/// <p><b>SQL-injection safety.</b> The helper NEVER interpolates
/// <var>pTimeWindowHours</var> into SQL text — it computes the cutoff
/// timestamp in ObjectScript and pushes it onto <var>pParams</var> as
/// a parameterized bind value. The <var>pAdditionalPredicates</var>
/// strings are concatenated by the helper, so the CALLER is responsible
/// for ensuring those strings contain only literal SQL fragments with
/// <code>?</code> placeholders — never user-controlled values
/// interpolated into the predicate text.</p>
///
/// <p><b>%EXACT() discipline.</b> Per project rule §"IRIS SQL Case
/// Sensitivity", concrete-tool authors writing
/// <var>pAdditionalPredicates</var> for string-column comparisons MUST
/// wrap the column reference in <code>%EXACT(...)</code> so the
/// case-sensitive comparison fires. Example:
/// <code>"%EXACT(SourceConfigName) = ?"</code>. The helper itself uses
/// <code>TimeCreated</code> (a non-string Ens.DataType.UTC column) so
/// no <code>%EXACT()</code> wrap is needed for the time predicate.</p>
ClassMethod BuildBoundedWhereClause(pTimeWindowHours As %Integer = 0, ByRef pParams As %DynamicArray, ByRef pErr As %DynamicObject, pAdditionalPredicates...) As %String
{
    Set pErr = ""
    If '$IsObject($Get(pParams)) Set pParams = []

    ; ---- Mode selection. ----
    Set tKeyedLookup = (pTimeWindowHours = ..#KeyedLookupSentinel)
    Set tFragment = ""

    If 'tKeyedLookup {
        ; Reject negative-but-not-sentinel values.
        If pTimeWindowHours < 0 {
            Set pErr = {"isError":(1), "errorCode":"TimeWindowTooSmall", "message":("pTimeWindowHours must be >= 1 (or -1 for keyed-lookup mode); got " _ pTimeWindowHours)}
            Quit ""
        }
        ; Reject above-cap.
        If pTimeWindowHours > ..#MaxTimeWindowHours {
            Set pErr = {"isError":(1), "errorCode":"TimeWindowTooLarge", "message":("pTimeWindowHours " _ pTimeWindowHours _ " exceeds maximum allowed " _ ..#MaxTimeWindowHours), "maxAllowed":(..#MaxTimeWindowHours)}
            Quit ""
        }
        ; Apply default for 0.
        Set tEffectiveHours = pTimeWindowHours
        If tEffectiveHours = 0 Set tEffectiveHours = ..#DefaultTimeWindowHours

        ; Compute cutoff timestamp in ODBC form (TimeCreated is Ens.DataType.UTC,
        ; which stores values in UTC ODBC form per irislib/Ens/DataType/UTC.cls).
        ; $ZTimeStamp returns UTC in "<days>,<seconds-since-midnight>" form
        ; (e.g. "66825,3725.678"). Subtract tEffectiveHours expressed as
        ; seconds from the seconds portion; carry/borrow days as needed.
        Set tNowH = $ZTimeStamp
        Set tDays = +$Piece(tNowH, ",", 1)
        Set tSecs = +$Piece(tNowH, ",", 2)
        Set tSecs = tSecs - (tEffectiveHours * 3600)
        While tSecs < 0 {
            Set tSecs = tSecs + 86400
            Set tDays = tDays - 1
        }
        Set tCutoffH = tDays _ "," _ tSecs
        Set tCutoffOdbc = $ZDateTime(tCutoffH, 3, 1)

        Set tFragment = "TimeCreated > ?"
        Do pParams.%Push(tCutoffOdbc)
    }

    ; ---- Concatenate additional predicates. ----
    For tIdx = 1:1:$Get(pAdditionalPredicates) {
        Set tPred = $Get(pAdditionalPredicates(tIdx))
        If tPred = "" Continue
        If tFragment = "" {
            Set tFragment = tPred
        } Else {
            Set tFragment = tFragment _ " AND " _ tPred
        }
    }

    Quit tFragment
}

}
