/// <p>Audit event lifecycle helper. Pre-registers all <code>SessionAgent</code>
/// audit event types in <code>%SYS</code> via <code>Security.Events.Create()</code>
/// before any code attempts to emit them.</p>
///
/// <p>Without pre-registration, <code>$System.Security.Audit("SessionAgent","Type","Name", ...)</code>
/// silently returns 0 (the audit event is lost with no error, no exception,
/// and no log entry) — see project rule §"Security.Events Pre-Registration
/// for Audit" in <code>.claude/rules/iris-objectscript-basics.md</code>.</p>
///
/// <p>This class is invoked at install time by an <code>&lt;Invoke&gt;</code>
/// hook in <code>module.xml</code> (uncommented in Story 1.5). It is also
/// safe to call manually at any time — the implementation is idempotent
/// (per acceptance criterion AC-2 / NFR-R5) and will not duplicate
/// registrations on re-invocation.</p>
///
/// <p>Story 1.3 registers the eleven triples that are concretely known at
/// install time; Story 14.4 adds the twelfth —
/// <code>(SessionAgent, SchemaNoteWrite, explicit)</code> — for
/// schema-note writes via the <code>save_schema_note</code> tool. The
/// <code>ToolCall</code> event family is NOT registered here because the
/// tool-name universe is not known until Epic 2 (Story 2.10) defines the
/// tool registry; lazy registration on first emit is the deferred design
/// choice.</p>
Class SessionAgent.Audit.Emit Extends %RegisteredObject
{

/// <p>Pre-register all <code>SessionAgent</code> audit event types in the
/// <code>%SYS</code> namespace. Idempotent — safe to call on every install,
/// upgrade, or manual invocation.</p>
///
/// <p>For each (Source, Type, Name) triple, calls
/// <code>Security.Events.Exists()</code> first and only calls
/// <code>Security.Events.Create()</code> when the triple is absent.</p>
///
/// <p>Uses the explicit save/restore pattern for <code>$NAMESPACE</code>
/// (per project rule §"Namespace Switching"); the catch block restores
/// the namespace as its first line. Argumented <code>Quit</code> is not
/// used inside the try/catch (per project rule §"QUIT Statement
/// Restrictions in Try/Catch Blocks").</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on success;
/// otherwise the failure status from the underlying
/// <code>Security.Events.Create()</code> call or the trapped exception.</p>
ClassMethod EnsureEvents() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"

        ; The pre-registered triples — eleven from Story 1.3 plus the
        ; Story 14.4 SchemaNoteWrite triple (schema-note saves via the
        ; save_schema_note tool; Description populated per Rule 4
        ; operator-observable-surface enumeration). Source is always
        ; "SessionAgent". Each row is $ListBuild(Type, Name, Description).
        Set tTriples = $ListBuild(
            $ListBuild("LlmCall", "openai", "SessionAgent LLM provider call: OpenAI"),
            $ListBuild("LlmCall", "anthropic", "SessionAgent LLM provider call: Anthropic"),
            $ListBuild("LlmCall", "gemini", "SessionAgent LLM provider call: Google Gemini"),
            $ListBuild("LlmCall", "ollama", "SessionAgent LLM provider call: Ollama / OpenAI-compatible"),
            $ListBuild("VocabWrite", "clickthrough", "SessionAgent vocabulary write: clickthrough source"),
            $ListBuild("VocabWrite", "explicit", "SessionAgent vocabulary write: explicit user input"),
            $ListBuild("VocabWrite", "extracted", "SessionAgent vocabulary write: extracted from chat"),
            $ListBuild("VocabWrite", "seed", "SessionAgent vocabulary write: seed value"),
            $ListBuild("TaskRun", "PurgeOrphanedChatHistory", "SessionAgent scheduled task: purge orphaned chat history"),
            $ListBuild("TaskRun", "PurgeStaleSearchChat", "SessionAgent scheduled task: purge stale search chat"),
            $ListBuild("TaskRun", "UserVocabularyDecay", "SessionAgent scheduled task: user vocabulary decay"),
            $ListBuild("SchemaNoteWrite", "explicit", "SessionAgent schema-note write: agent-saved namespace fact (save_schema_note)"))

        Set tPtr = 0
        While $ListNext(tTriples, tPtr, tRow) {
            Set tType = $ListGet(tRow, 1)
            Set tName = $ListGet(tRow, 2)
            Set tDesc = $ListGet(tRow, 3)
            If '##class(Security.Events).Exists("SessionAgent", tType, tName) {
                Set tCreate = ##class(Security.Events).Create("SessionAgent", tType, tName, tDesc, 1)
                If $$$ISERR(tCreate) {
                    Set tSC = tCreate
                    Quit ; argumentless quit out of While; try/catch closes below
                }
            }
        }

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Persist one <CLASS>SessionAgent.Audit.LlmCall</CLASS> row capturing
/// telemetry for a single LLM provider call, then emit the native
/// <code>$System.Security.Audit("SessionAgent","LlmCall",pProvider,...)</code>
/// event. Returns <code>%Status</code>: <code>$$$OK</code> on success;
/// failure surfaces the underlying <code>%Save()</code> error
/// (NFR-S4 — never silently discarded).</p>
///
/// <p>This method is the AgentLoop's only writer for the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> table; one invocation per
/// LLM round-trip yields exactly one row (FR32–FR34 / NFR-S4 100%
/// completeness contract).</p>
///
/// <p><b>Note:</b> <property>SessionAgent.Audit.LlmCall.ErrorText</property>
/// must NEVER carry credential material (NFR-S3); the caller is
/// responsible for ensuring <code>pErrorText</code> is credential-clean.
/// Provider headers / API keys live inside the LLM adapter and never
/// appear in <code>pErrorText</code> by design.</p>
ClassMethod LogLlmCall(pChatHistoryId As %String, pProvider As %String, pModel As %String, pRequestMessageCount As %Integer, pRequestTokens As %Integer, pResponseTokens As %Integer, pLatencyMs As %Integer, pStopReason As %String, pCacheHitTokens As %Integer = 0, pIsError As %Boolean = 0, pErrorText As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        Set tRow = ##class(SessionAgent.Audit.LlmCall).%New()
        Set tRow.Timestamp = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
        Set tRow.ChatHistoryId = pChatHistoryId
        Set tRow.Provider = pProvider
        Set tRow.Model = pModel
        Set tRow.RequestMessageCount = pRequestMessageCount
        Set tRow.RequestTokens = pRequestTokens
        Set tRow.ResponseTokens = pResponseTokens
        Set tRow.LatencyMs = pLatencyMs
        Set tRow.StopReason = pStopReason
        Set tRow.CacheHitTokens = pCacheHitTokens
        Set tRow.IsError = pIsError
        Set tRow.ErrorText = pErrorText

        Set tSave = tRow.%Save()
        If $$$ISERR(tSave) {
            Set tSC = tSave
            Quit ; argumentless quit; let Catch run if needed
        }

        ; Native audit emit AFTER successful row write. The
        ; (SessionAgent, LlmCall, <Provider>) triple was pre-registered
        ; at install time by EnsureEvents() — no lazy registration here.
        Do $System.Security.Audit("SessionAgent", "LlmCall", pProvider, $$$OK, pChatHistoryId)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Persist one <CLASS>SessionAgent.Audit.ToolCall</CLASS> row capturing
/// telemetry for a single tool dispatch, then emit the native
/// <code>$System.Security.Audit("SessionAgent","ToolCall",pToolName,...)</code>
/// event. Returns <code>%Status</code>: <code>$$$OK</code> on success;
/// failure surfaces the underlying <code>%Save()</code> error
/// (NFR-S4).</p>
///
/// <p><b>Redaction (NFR-S3).</b> Both <code>pArgsJson</code> and
/// <code>pResultJson</code> are deserialized via
/// <code>%FromJSON</code>, redacted via
/// <method>SessionAgent.Util.Json.Redact</method> with the project-standard
/// key list, and re-serialized via <code>%ToJSON</code> BEFORE being stored
/// on the row. The literal credential material (e.g.,
/// <code>sk-leak-12345</code>) does not appear in the persisted row.</p>
///
/// <p><b>Lazy registration (Story 2.0 triage carry-forward).</b> Before
/// the native emit, calls <method>RegisterIfMissing</method> for the
/// <code>(SessionAgent, ToolCall, pToolName)</code> triple. Since the
/// universe of tool names is not known at install time (the registry
/// lands in Story 2.10), each tool's audit-event triple is created on
/// first emit. Subsequent emits for the same tool find the triple
/// already registered and skip creation.</p>
ClassMethod LogToolCall(pChatHistoryId As %String, pToolName As %String, pArgsJson As %String, pResultJson As %String, pLatencyMs As %Integer, pIsError As %Boolean = 0, pErrorText As %String = "", pResultSetSize As %Integer = "", pQueryTemplate As %String = "", pIndexUsed As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        ; Redact ArgsJson via deserialize → Redact → re-serialize.
        Set tArgsClean = ..RedactJsonString(pArgsJson, .tArgsSC)
        If $$$ISERR(tArgsSC) {
            Set tSC = tArgsSC
            Quit
        }

        ; Same for ResultJson.
        Set tResultClean = ..RedactJsonString(pResultJson, .tResultSC)
        If $$$ISERR(tResultSC) {
            Set tSC = tResultSC
            Quit
        }

        ; Lazy-register the (SessionAgent, ToolCall, <ToolName>) triple
        ; BEFORE the row save and native emit. Story 2.0 triage
        ; carry-forward: per-tool registration on first emit (registry
        ; lands in Story 2.10). Registration must precede the row save
        ; so a registration failure does not leave a persisted row
        ; behind that a retry would duplicate.
        Set tReg = ..RegisterIfMissing("SessionAgent", "ToolCall", pToolName)
        If $$$ISERR(tReg) {
            Set tSC = tReg
            Quit
        }

        Set tRow = ##class(SessionAgent.Audit.ToolCall).%New()
        Set tRow.Timestamp = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
        Set tRow.ChatHistoryId = pChatHistoryId
        Set tRow.ToolName = pToolName
        Set tRow.ArgsJson = tArgsClean
        Set tRow.ResultJson = tResultClean
        Set tRow.LatencyMs = pLatencyMs
        Set tRow.IsError = pIsError
        Set tRow.ErrorText = pErrorText
        Set tRow.ResultSetSize = pResultSetSize
        Set tRow.QueryTemplate = pQueryTemplate
        Set tRow.IndexUsed = pIndexUsed

        Set tSave = tRow.%Save()
        If $$$ISERR(tSave) {
            Set tSC = tSave
            Quit
        }

        Do $System.Security.Audit("SessionAgent", "ToolCall", pToolName, $$$OK, pChatHistoryId)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Internal helper — deserialize <code>pJson</code> via
/// <code>%FromJSON</code>, redact credential keys via
/// <method>SessionAgent.Util.Json.Redact</method>, re-serialize via
/// <code>%ToJSON</code>. Returns the cleaned JSON string. On failure
/// (deserialize error or Redact error), sets <code>pSC</code> to the
/// failure status and returns the original input unchanged so the caller
/// can decide whether to surface or swallow.</p>
///
/// <p><b>Empty input handling.</b> If <code>pJson</code> is empty (some
/// tool calls have no args or no result envelope), returns the empty
/// string with <code>pSC = $$$OK</code> — no deserialize attempted.</p>
ClassMethod RedactJsonString(pJson As %String, ByRef pSC As %Status) As %String [ Private ]
{
    Set pSC = $$$OK
    If pJson = "" Quit ""
    Set tCleaned = pJson
    Try {
        Set tObj = ##class(%DynamicObject).%FromJSON(pJson)
        Set tRedactSC = ##class(SessionAgent.Util.Json).Redact(tObj, "api_key,Authorization,authorization,password,secret,bearer,access_token", .tCleanObj)
        If $$$ISERR(tRedactSC) {
            Set pSC = tRedactSC
            Quit
        }
        Set tCleaned = tCleanObj.%ToJSON()
    }
    Catch ex {
        Set pSC = ex.AsStatus()
    }
    Quit tCleaned
}

/// <p>Lazy-register an audit-event triple in
/// <code>%SYS Security.Events</code>. Returns <code>$$$OK</code> if the
/// triple was already present OR was successfully created. Returns the
/// failure status from <code>Security.Events.Create()</code> on creation
/// failure.</p>
///
/// <p>Uses the explicit save/restore pattern for <code>$NAMESPACE</code>
/// (project rule §"Namespace Switching"); the catch block restores the
/// caller's namespace as its first line.</p>
///
/// <p>This helper is the Story 2.0 triage carry-forward of the per-tool
/// registration that originally lived in the deferred Tool.Registry
/// design. Story 2.10 may move it to
/// <code>SessionAgent.Tool.Registry</code> if cleaner; for now it lives
/// in <CLASS>SessionAgent.Audit.Emit</CLASS> alongside
/// <method>EnsureEvents</method> (which already owns the
/// <code>%SYS</code> switch pattern).</p>
ClassMethod RegisterIfMissing(pSource As %String, pType As %String, pName As %String) As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"

        If '##class(Security.Events).Exists(pSource, pType, pName) {
            Set tCreate = ##class(Security.Events).Create(pSource, pType, pName, pSource _ " " _ pType _ ": " _ pName, 1)
            If $$$ISERR(tCreate) {
                Set tSC = tCreate
                Quit ; argumentless quit; namespace restored after Try
            }
        }

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
