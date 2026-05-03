/// <p>Persistent chat-history row keyed by
/// <code>(AgentName, SessionKey, PortalUser)</code> — one row per
/// (agent, conversation, user) triple. Holds the canonical-Anthropic-shape
/// turns array as a <CLASS>%Stream.GlobalCharacter</CLASS> so an
/// arbitrarily-long conversation does not bloat the row.</p>
///
/// <p><b>FR contract.</b> Implements the chat-persistence half of FR46
/// (concurrent-tab serialization), NFR-P4 (lock contention bound), FR43
/// (Inspection-keying vs Search-keying are distinct so the same portal
/// user can have two parallel conversations against the two agents
/// without collision), and FR34 (this row's <code>ID</code> is the FK
/// target the audit ledger references via
/// <code>SessionAgent.Audit.LlmCall.ChatHistoryId</code>).</p>
///
/// <p><b>Concurrency lock.</b> The
/// <method>LoadOrCreate</method> ClassMethod returns an OREF that has
/// already acquired the per-row exclusive lock via
/// <code>%OpenId(id, 4)</code> (concurrency=4 = exclusive — see
/// <code>irislib/%Library/Persistent.cls</code> lines 273–280). The
/// caller (Story 2.12 <code>AgentLoop.RunTurn</code>) is responsible for
/// releasing the lock by either calling <code>%Save()</code> (which
/// commits + releases) or <code>%Close()</code> (which discards in-memory
/// state + releases). Holding the OREF without saving leaks the lock
/// until the OREF goes out of scope. Two browser tabs hitting the same
/// <code>(agent, session, user)</code> tuple thus serialize naturally:
/// the second tab's <code>LoadOrCreate</code> blocks at the IRIS lock
/// queue until the first tab's <code>%Save()</code> completes, then
/// proceeds with the freshly-saved <property>TurnsJson</property>
/// visible (architecture line 611).</p>
///
/// <p><b>Schema.</b> Seven properties cover the ConvKey tuple
/// (<property>AgentName</property>/<property>SessionKey</property>/
/// <property>PortalUser</property>), the conversation payload
/// (<property>TurnsJson</property> stream of canonical Anthropic-shape
/// turns), the lifecycle timestamps
/// (<property>CreatedAt</property>/<property>UpdatedAt</property>), and
/// the per-conversation pinned LLM config snapshot
/// (<property>ConfigSnapshot</property>) so that mid-conversation
/// operator config edits do not silently change the
/// provider/model/budget the user already started chatting with.</p>
///
/// <p><b>FR43 keying.</b> The unique
/// <code>ConvKeyIdx</code> on the tuple
/// <code>(AgentName, SessionKey, PortalUser)</code> guarantees one row
/// per conversation. Inspection-agent rows use the IRIS Production
/// session ID for <property>SessionKey</property>; search-agent rows
/// use a registry-issued GUID. The two key spaces never collide because
/// <property>AgentName</property> is part of the tuple — Story 7.2
/// (PurgeOrphanedChatHistory) and Story 10.6 (PurgeStaleSearchChat)
/// rely on this separation to apply per-agent retention policy.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.6</a> (lines 861–889) — AC source.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// lines 235, 238, 607–611 — schema, concurrency-lock pattern, file path.</li>
/// <li><a href="../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR34, FR43, FR46, NFR-P4.</li>
/// <li><a href="../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a>
/// §"Storage Sections", §"Timestamp and Encoding Standards", §"Naming
/// Conventions".</li>
/// </ul>
Class SessionAgent.Chat.History Extends %Persistent
{

/// <p>Agent identifier — partitions the keyspace into the two v1
/// agents. Values: <code>session-inspection</code> (Inspection agent —
/// uses Ens session ID for <property>SessionKey</property>) and
/// <code>message-search</code> (Search agent — uses registry-issued
/// GUID for <property>SessionKey</property>). Joined with
/// <property>SessionKey</property> + <property>PortalUser</property>
/// in the unique <code>ConvKeyIdx</code> below.</p>
Property AgentName As %String;

/// <p>Conversation key. Inspection-agent rows: the IRIS Production
/// session ID the operator is inspecting. Search-agent rows: a
/// registry-issued GUID (Story 7 surface). The two key spaces never
/// collide because <property>AgentName</property> is part of the
/// unique <code>ConvKeyIdx</code> tuple (FR43).</p>
Property SessionKey As %String;

/// <p>Portal user that owns the conversation. Set to
/// <code>$Username</code> at <method>LoadOrCreate</method> time. The
/// audit ledger correlates LLM/tool rows back to the portal user via
/// the <property>ChatHistoryId</property> FK, so this value is the
/// audit-trail attribution anchor.</p>
Property PortalUser As %String;

/// <p>Canonical Anthropic-shape turns array, persisted as a global
/// stream so multi-turn conversations of arbitrary length do not bloat
/// the row. Read with
/// <code>##class(%DynamicArray).%FromJSON(..TurnsJson)</code> after
/// rewinding; written with <code>..TurnsJson.Clear()</code> +
/// <code>tArr.%ToJSON(..TurnsJson)</code>. Empty stream on a
/// freshly-created row.</p>
Property TurnsJson As %Stream.GlobalCharacter;

/// <p>ISO-8601 UTC timestamp of row creation. Built via
/// <code>$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"</code> —
/// <code>$ZTimeStamp</code> is UTC, so the trailing <code>Z</code> is
/// semantically correct on any host (project rule §"Timestamp and
/// Encoding Standards"). Set once by
/// <method>LoadOrCreate</method> on first creation; never updated.</p>
Property CreatedAt As %String;

/// <p>ISO-8601 UTC timestamp of the most recent
/// <method>%Save</method>. Same construction as
/// <property>CreatedAt</property>. Story 2.12
/// (<code>AgentLoop</code>) is responsible for re-stamping this on
/// every turn-append; <method>LoadOrCreate</method> sets it equal to
/// <property>CreatedAt</property> on first creation.</p>
Property UpdatedAt As %String;

/// <p>Per-conversation pinned LLM-config snapshot — a JSON object of
/// the form <code>{"provider":..., "model":..., "maxTokens":...,
/// "temperature":...}</code> captured at
/// <method>LoadOrCreate</method> time from the live
/// <CLASS>SessionAgent.Config.Agent</CLASS> row. Pinning prevents an
/// operator's mid-conversation config edit from silently swapping the
/// provider/model/budget under an in-flight user. <code>MAXLEN=2048</code>
/// accommodates several extension keys without forcing a stream backing
/// store. Story 2.12 will populate this; this story only ships the
/// schema slot.</p>
Property ConfigSnapshot As %String(MAXLEN = 2048);

/// <p>Unique tuple index — guarantees single-row-per-conversation and
/// gives O(1) lookup via the dictionary-generated
/// <code>ConvKeyIdxExists(AgentName, SessionKey, PortalUser, .id)</code>
/// predicate that <method>LoadOrCreate</method> uses for its
/// existence check.</p>
Index ConvKeyIdx On (AgentName, SessionKey, PortalUser) [ Unique ];

/// <p>Returns an exclusively-locked
/// <CLASS>SessionAgent.Chat.History</CLASS> OREF for the requested
/// conversation tuple — creates the row on first call, opens the
/// existing row on subsequent calls. The returned OREF is held under
/// concurrency=4 (exclusive lock) so two concurrent callers (e.g.,
/// two browser tabs) serialize at the IRIS lock queue rather than
/// racing each other's writes (FR46, NFR-P4, architecture line 611).</p>
///
/// <p><b>Caller responsibility.</b> The caller MUST call either
/// <method>%Save</method> (which commits + releases the lock) or
/// <method>%Close</method> (which discards + releases) on the returned
/// OREF, otherwise the lock leaks until the OREF goes out of scope.
/// Story 2.12 <method>AgentLoop.RunTurn</method> will wrap every turn
/// in a <code>Try</code>/<code>Finally</code> envelope to guarantee
/// release.</p>
///
/// <p><b>Returns.</b> A locked OREF on success, or
/// <code>$$$NULLOREF</code> on a lock-acquisition timeout / open
/// failure / persistence error. When NULLOREF is returned, the
/// ByRef <code>pStatus</code> parameter carries the IRIS-level
/// error: lock conflicts surface as <code>$$$ERRORLOCKFAILED</code>,
/// validation/save failures surface as their %Save status, and any
/// caught exception is converted to a status via
/// <code>ex.AsStatus()</code>. Story 2.12
/// <method>AgentLoop.RunTurn</method> inspects <code>pStatus</code>
/// to distinguish "another turn in progress" (lock conflict — retry
/// or surface to UI) from a true persistence failure (escalate).</p>
ClassMethod LoadOrCreate(pAgentName As %String, pSessionKey As %String, pPortalUser As %String, pConfigSnapshot As %String = "", ByRef pStatus As %Status = {$$$OK}) As SessionAgent.Chat.History
{
    Set tHist = $$$NULLOREF
    Set pStatus = $$$OK
    ; Story 3.0 AC-5 — non-empty validation. Empty triple-key components
    ; produce silent garbage rows that the unique ConvKeyIdx then collides
    ; with on the next legitimate call. Reject up front; existing callers
    ; (test fixtures, AgentLoop) all pass real values so backward-compat
    ; preserved.
    If (pAgentName = "") || (pSessionKey = "") || (pPortalUser = "") {
        Set pStatus = $$$ERROR($$$GeneralError, "LoadOrCreate: pAgentName / pSessionKey / pPortalUser must all be non-empty")
        Quit $$$NULLOREF
    }
    Try {
        ; Lookup-or-create: ConvKeyIdxExists sets tId by ref when the
        ; tuple already has a row.
        Set tId = ""
        If ..ConvKeyIdxExists(pAgentName, pSessionKey, pPortalUser, .tId) {
            Set pStatus = $$$OK
            Set tHist = ..%OpenId(tId, 4, .pStatus)
            ; tHist is $$$NULLOREF on lock-acquisition failure; pStatus
            ; carries the IRIS-level error to the caller.
            Quit
        }
        ; New-row branch.
        Set tNew = ..%New()
        Set tNew.AgentName = pAgentName
        Set tNew.SessionKey = pSessionKey
        Set tNew.PortalUser = pPortalUser
        Set tNew.ConfigSnapshot = pConfigSnapshot
        Set tNow = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
        Set tNew.CreatedAt = tNow
        Set tNew.UpdatedAt = tNow
        Set pStatus = tNew.%Save()
        If $$$ISERR(pStatus) Quit
        Set tNewId = tNew.%Id()
        ; Re-open under exclusive lock so the caller receives a locked
        ; OREF identical to the existing-row branch's contract.
        Do tNew.%Close()
        Set tHist = ..%OpenId(tNewId, 4, .pStatus)
        Quit
    }
    Catch ex {
        ; Best-effort: if anything threw mid-flight, return $$$NULLOREF
        ; rather than a half-locked OREF, and propagate the exception
        ; as a status the caller can inspect.
        Set tHist = $$$NULLOREF
        Set pStatus = ex.AsStatus()
    }
    Quit tHist
}

Storage Default
{
<Data name="HistoryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>AgentName</Value>
</Value>
<Value name="3">
<Value>SessionKey</Value>
</Value>
<Value name="4">
<Value>PortalUser</Value>
</Value>
<Value name="5">
<Value>TurnsJson</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
<Value name="7">
<Value>UpdatedAt</Value>
</Value>
<Value name="8">
<Value>ConfigSnapshot</Value>
</Value>
</Data>
<DataLocation>^SessionAgent.Chat.HistoryD</DataLocation>
<DefaultData>HistoryDefaultData</DefaultData>
<IdLocation>^SessionAgent.Chat.HistoryD</IdLocation>
<IndexLocation>^SessionAgent.Chat.HistoryI</IndexLocation>
<StreamLocation>^SessionAgent.Chat.HistoryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
