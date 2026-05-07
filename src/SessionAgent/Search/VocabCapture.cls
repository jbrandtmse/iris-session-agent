/// <p>Story 9.5 — click-through capture entry point. Receives the
/// contributing-tool-calls JSON for a search-result row that the operator
/// clicked through to inspect, synthesizes an alias for each contributing
/// tool call via Story 9.1's
/// <CLASS>SessionAgent.Search.SynthesizeAlias</CLASS>, then records the
/// alias success via Story 9.2's
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// <method>RecordSuccess</method> with
/// <code>CreatedVia="clickthrough"</code>.</p>
///
/// <p><b>Class location decision (lead-recorded).</b> This class ships as
/// a regular <code>%RegisteredObject</code> with a regular ClassMethod
/// (NOT a <code>[ZenMethod]</code>). ZenMethod hyperevent dispatch
/// requires the host class to extend <code>%ZEN.Component.page</code> /
/// <code>EnsPortal.Template.standardPage</code>; Epic 10 Story 10.1 ships
/// the search-portal subclass <code>EnsPortal.MessageViewer</code> that
/// hosts the hyperevent surface. Decoupling the alias-capture business
/// logic (Epic 9, this story) from the hyperevent surface (Epic 10
/// Story 10.1) lets Epic 9 close cleanly without Epic 10's portal
/// subclass existing. Epic 10 Story 10.1 will declare a thin
/// <code>[ZenMethod] RecordClickThrough(...)</code> on its portal subclass
/// that resolves <code>%session.Username</code> at the boundary AND
/// delegates to this ClassMethod.</p>
///
/// <p><b>Caller-context resolution at the boundary.</b> Per architecture
/// §"Caller context propagation" — <code>%session.Username</code> MUST be
/// resolved at the public-surface boundary, never inside business logic.
/// Epic 10 Story 10.1's portal-subclass
/// <code>[ZenMethod] RecordClickThrough</code> is the boundary; it
/// resolves <code>%session.Username</code> and delegates to this
/// ClassMethod with <var>pPortalUser</var> as a parameter. Story 9.5's
/// ClassMethod accepts <var>pPortalUser</var> — does NOT read
/// <code>%session</code> itself.</p>
///
/// <p><b>FR37 — never throw.</b> Per architecture §"Capture surface error
/// handling": the entry point is wrapped in a defensive
/// <code>Try / Catch</code> guard. Any exception escape converts to a
/// structured <code>{"success": false, "error": ...}</code> JSON envelope.
/// Exceptions never escape this ClassMethod.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/implementation-artifacts/9-5-recordclickthrough-zenmethod-hyperevent-stub.md">Story 9.5 spec</a> — AC-1 through AC-6 verbatim source.</li>
/// <li><CLASS>SessionAgent.Search.SynthesizeAlias</CLASS> — Story 9.1 alias-string synthesis (substrate).</li>
/// <li><CLASS>SessionAgent.Search.UserVocabulary</CLASS> §<method>RecordSuccess</method> — Story 9.2 persistence + audit emit (substrate).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR12 / AR13-Epic9</a> — click-through capture key contract.</li>
/// <li>Epic 10 Story 10.1 — portal-subclass ZenMethod wrapper that delegates here.</li>
/// </ul>
Class SessionAgent.Search.VocabCapture Extends %RegisteredObject
{

/// <p>Story 9.5 AC-2 — click-through capture entry point. For each
/// contributing tool call in <var>pContributingToolCallsJson</var>,
/// synthesizes an alias via Story 9.1's
/// <CLASS>SessionAgent.Search.SynthesizeAlias</CLASS> and records a
/// vocabulary success via Story 9.2's
/// <CLASS>SessionAgent.Search.UserVocabulary</CLASS>
/// <method>RecordSuccess</method>. De-duplicates aliases within a single
/// call so two contributing tool calls that synthesize the same alias
/// only result in ONE <code>RecordSuccess</code> increment.</p>
///
/// <p><b>Caller-side input-validation guard (Story 9.0 carry-forward
/// LOW-9.2-F06).</b> Empty <var>pPortalUser</var> short-circuits to a
/// structured error envelope. The persistence-layer guard
/// (<method>RecordSuccess</method> / <method>RecordFailure</method>) remains
/// deferred per <code>deferred-work.md</code>; this caller-side guard is
/// the front-line check.</p>
///
/// <p><b>Parameters.</b></p>
/// <ul>
/// <li><var>pSearchSessionKey</var> — opaque per-search-session key from
/// the UI; echoed back in the response JSON for the UI's client-side
/// telemetry. Not used by alias-capture logic.</li>
/// <li><var>pSessionId</var> — Ens session ID the operator clicked
/// through to. Echoed back in the response JSON. Not used by
/// alias-capture logic.</li>
/// <li><var>pContributingToolCallsJson</var> — JSON-serialized
/// <code>%DynamicArray</code> of tool-call blocks. Each block expected
/// shape: <code>{"tool_name": "...", "args": {...}, "result": {...}}</code>.</li>
/// <li><var>pPortalUser</var> — already-resolved portal user (Epic 10
/// Story 10.1's portal-subclass ZenMethod resolves
/// <code>%session.Username</code> at the boundary).</li>
/// </ul>
///
/// <p><b>Response shape.</b> Returns a JSON string of
/// <code>%DynamicObject</code> shape:</p>
/// <ul>
/// <li><code>success: true|false</code> — overall capture status.</li>
/// <li><code>aliases_recorded: [...]</code> — distinct aliases that
/// successfully invoked <code>RecordSuccess</code>.</li>
/// <li><code>aliases_failed: [...]</code> (only if any failed) — aliases
/// whose <code>RecordSuccess</code> returned an error status.</li>
/// <li><code>search_session_key</code>, <code>session_id</code> —
/// passthrough echoes (AC-3).</li>
/// <li><code>error</code> (only if <code>success: false</code>) — human-
/// readable error text.</li>
/// </ul>
ClassMethod RecordClickThrough(pSearchSessionKey As %String, pSessionId As %String, pContributingToolCallsJson As %String, pPortalUser As %String) As %String
{
    Set tResponseJson = ""
    Try {
        ; ---- Caller-side input-validation guard (Story 9.0 carry-forward
        ; LOW-9.2-F06). Empty pPortalUser short-circuits to structured error.
        If $Get(pPortalUser, "") = "" {
            Set tErr = {"success": (0), "error": "pPortalUser required", "search_session_key": (pSearchSessionKey), "session_id": (pSessionId)}
            Set tResponseJson = tErr.%ToJSON()
            Quit
        }

        ; ---- Parse pContributingToolCallsJson into a %DynamicArray.
        ; %FromJSON with $$$ISERR-on-status pattern: if the JSON parse
        ; fails (malformed JSON, non-array, etc.), %FromJSON throws —
        ; the outer Try / Catch converts that into the structured error.
        Set tParsedArr = ""
        Set tParseStatus = $$$OK
        Try {
            Set tParsedArr = ##class(%DynamicAbstractObject).%FromJSON($Get(pContributingToolCallsJson, ""))
        }
        Catch tParseEx {
            Set tParseStatus = tParseEx.AsStatus()
        }
        If $$$ISERR(tParseStatus) {
            Set tErr = {"success": (0), "error": ("invalid JSON: " _ $System.Status.GetErrorText(tParseStatus)), "search_session_key": (pSearchSessionKey), "session_id": (pSessionId)}
            Set tResponseJson = tErr.%ToJSON()
            Quit
        }

        ; Defensive: parse may produce a %DynamicObject (e.g., "{}") instead
        ; of a %DynamicArray. Treat anything that's not a %DynamicArray as
        ; an empty iteration (no contributing tool calls = no aliases to
        ; record). This is structurally equivalent to "[]" input.
        If '$IsObject(tParsedArr) || (tParsedArr.%ClassName(1) '= "%Library.DynamicArray") {
            ; Non-array → no contributing tool calls; success with empty list.
            Set tEmpty = {"success": (1), "aliases_recorded": [], "search_session_key": (pSearchSessionKey), "session_id": (pSessionId)}
            Set tResponseJson = tEmpty.%ToJSON()
            Quit
        }

        ; ---- Iterate the array via %GetIterator(); read-only iteration
        ; per project rule §"%DynamicObject Iterator Safety" — no %Set /
        ; %Remove calls on tParsedArr during iteration.
        Set tIter = tParsedArr.%GetIterator()
        Set tRecordedAliases = []
        Set tFailedAliases = []
        ; tSeen — alias-dedupe set keyed by the alias text. Per the spec's
        ; AC-2 step 8 dedupe pattern, use a %DynamicObject so %IsDefined
        ; correctly distinguishes "key absent" from "key present with
        ; empty value".
        Set tSeen = {}
        Set tHadAnyFailures = 0

        While tIter.%GetNext(.tIdx, .tBlock, .tBlockType) {
            ; Defensive: skip non-object blocks silently (a malformed
            ; tool-call block shouldn't crash the capture).
            If '$IsObject(tBlock) Continue
            If (tBlockType '= "object") Continue

            ; Extract tool_name; skip if empty.
            Set tToolName = ""
            If tBlock.%IsDefined("tool_name") {
                Set tToolName = tBlock.%Get("tool_name")
            }
            If $Get(tToolName, "") = "" Continue

            ; Extract args; default to empty object if absent.
            Set tArgs = ""
            If tBlock.%IsDefined("args") && $IsObject(tBlock.%Get("args")) {
                Set tArgs = tBlock.%Get("args")
            } Else {
                Set tArgs = {}
            }

            ; ---- Synthesize the alias via Story 9.1.
            Set tAlias = ##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias(tToolName, tArgs)

            ; ---- De-dupe within this call. Two contributing tool calls
            ; that synthesize the same alias should only result in ONE
            ; RecordSuccess invocation (the second would be a no-op
            ; increment, but cleaner to dedupe at the entry point).
            If tSeen.%IsDefined(tAlias) Continue
            Do tSeen.%Set(tAlias, 1)

            ; ---- Extract MessageBodyClass per AC-2 step 5.
            Set tBodyClass = ""
            If tArgs.%IsDefined("message_body_class_name") {
                Set tCandidate = tArgs.%Get("message_body_class_name")
                If $Get(tCandidate, "") '= "" Set tBodyClass = tCandidate
            }
            If (tBodyClass = "") && tArgs.%IsDefined("prefilter_indexed_column") && tArgs.%IsDefined("prefilter_value") {
                Set tCol = tArgs.%Get("prefilter_indexed_column")
                Set tVal = tArgs.%Get("prefilter_value")
                If ($Get(tCol, "") = "MessageBodyClassName") && ($Get(tVal, "") '= "") {
                    Set tBodyClass = tVal
                }
            }

            ; ---- Invoke RecordSuccess. On error, capture the failed alias
            ; and continue iterating (don't let one bad alias kill the
            ; whole capture).
            Set tRecSC = ##class(SessionAgent.Search.UserVocabulary).RecordSuccess(pPortalUser, tAlias, tBodyClass, "clickthrough", "")
            If $$$ISERR(tRecSC) {
                Do tFailedAliases.%Push(tAlias)
                Set tHadAnyFailures = 1
            } Else {
                Do tRecordedAliases.%Push(tAlias)
            }
        }

        ; ---- Build the success envelope. Echo passthrough IDs (AC-3).
        Set tResp = {}
        Do tResp.%Set("success", 1, "boolean")
        Do tResp.%Set("aliases_recorded", tRecordedAliases)
        If tHadAnyFailures {
            Do tResp.%Set("aliases_failed", tFailedAliases)
        }
        Do tResp.%Set("search_session_key", pSearchSessionKey)
        Do tResp.%Set("session_id", pSessionId)
        Set tResponseJson = tResp.%ToJSON()
    }
    Catch ex {
        ; FR37 — never throw. Convert any escaped exception to structured
        ; error envelope.
        Set tErr = {}
        Do tErr.%Set("success", 0, "boolean")
        Do tErr.%Set("error", ex.DisplayString())
        Do tErr.%Set("search_session_key", $Get(pSearchSessionKey, ""))
        Do tErr.%Set("session_id", $Get(pSessionId, ""))
        Set tResponseJson = tErr.%ToJSON()
    }
    Quit tResponseJson
}

}
