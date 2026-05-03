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
/// install time. The <code>ToolCall</code> event family is NOT registered
/// here because the tool-name universe is not known until Epic 2 (Story
/// 2.10) defines the tool registry; lazy registration on first emit is
/// the deferred design choice.</p>
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

        ; The eleven triples Story 1.3 pre-registers. Source is always
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
            $ListBuild("TaskRun", "UserVocabularyDecay", "SessionAgent scheduled task: user vocabulary decay"))

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

}
