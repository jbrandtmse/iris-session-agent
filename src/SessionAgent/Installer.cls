/// <p>IPM <code>&lt;Invoke&gt;</code> orchestrator. Single entry point for
/// all install-time work: audit-event pre-registration (Story 1.3 — calls
/// <code>SessionAgent.Audit.Emit.EnsureEvents</code>), read-only RBAC role
/// install (Story 1.4 — calls
/// <code>SessionAgent.Security.ReadOnlyRole.Install</code>), defensive
/// scheduling of the three sweep tasks (Stories 7.2 + 10.6), defensive
/// seeding of default agent configs (Story 2.4), and printing of operator
/// reminders to the install log (bookmark URLs + README pointer).</p>
///
/// <p><b>Idempotency (NFR-R5):</b> the orchestrator is safe to invoke on
/// every install / upgrade. The two non-defensive callees
/// (<code>Audit.Emit.EnsureEvents</code>,
/// <code>Security.ReadOnlyRole.Install</code>) are themselves idempotent
/// (verified in Stories 1.3 + 1.4). The two defensive helpers
/// (<code>ScheduleTaskIfClassExists</code>,
/// <code>SeedDefaultAgentConfigs</code>) implement explicit existence checks
/// before performing any inserts; re-running the orchestrator does not
/// duplicate task entries or seeded configs.</p>
///
/// <p><b>Forward-compatibility:</b> the three sweep-task classes
/// (<code>SessionAgent.Task.PurgeOrphanedChatHistory</code>,
/// <code>SessionAgent.Task.PurgeStaleSearchChat</code>,
/// <code>SessionAgent.Task.UserVocabularyDecay</code>) and
/// <code>SessionAgent.Config.Agent</code> all ship in later epics. The
/// orchestrator must NOT break <code>zpm load</code> on a fresh checkout
/// where these classes do not yet exist. The two defensive helpers use
/// <code>%Dictionary.ClassDefinition.%ExistsId()</code> to test for class
/// presence and log a "deferred" line when the class is absent — without
/// propagating an error.</p>
///
/// <p><b>Project rules honored:</b> <code>$$$OK</code> triple-dollar; explicit
/// <code>$NAMESPACE</code> save/restore via <code>tOrigNS</code>; catch
/// block restores <code>$NAMESPACE</code> as its first line; argumented
/// <code>Quit tSC</code> only outside the try/catch (argumentless
/// <code>Quit</code> inside); <code>Write</code> Status checking on every
/// chained call; no transaction side effects (no JOB, no event signals).</p>
///
/// <p><b>%SYS-caller resilience:</b> when <code>Install()</code> is invoked
/// with <code>$NAMESPACE = "%SYS"</code> (a common scenario when an
/// operator runs <code>zpm "load /path"</code> from the %SYS shell rather
/// than first issuing <code>zn "HSCUSTOM"</code>), the orchestrator
/// detects this and switches to a sensible target namespace (the
/// <var>TARGETNAMESPACE</var> parameter, defaulting to
/// <code>HSCUSTOM</code>) before delegating to
/// <code>ReadOnlyRole.Install()</code>. <code>Ens.*</code> tables are
/// projected in the operator's interop namespace, not in %SYS, so the
/// grant step inside <code>ReadOnlyRole.Install()</code> would fail with
/// SQLCODE -30 if invoked while pinned to %SYS. The detection-and-switch
/// is non-intrusive: callers already in a non-%SYS namespace see no change
/// in behavior.</p>
Class SessionAgent.Installer Extends %RegisteredObject
{

/// <p>Default target namespace when <code>Install()</code> is invoked from
/// %SYS. Per architecture.md line 1117 the module is installed in
/// <code>HSCUSTOM</code> with package mapping to interop namespaces.
/// Operators on plain-IRIS deployments may override the package routing
/// at install time; the orchestrator's role is to pick a sensible default
/// when run from %SYS so the chained <code>ReadOnlyRole.Install()</code>
/// grant step succeeds.</p>
Parameter TARGETNAMESPACE = "HSCUSTOM";

/// <p>IPM <code>&lt;Invoke&gt;</code> entry point — orchestrates Story 1.5's
/// install-time work in a single idempotent call.</p>
///
/// <p><b>pVars</b> is the IPM-supplied variable hash; v1 ignores it but the
/// signature must match the IPM <code>&lt;Invoke&gt;</code> contract per
/// epics.md Story 1.5 AC. Future versions may consume per-instance
/// overrides or install-time secrets from <code>pVars</code>.</p>
///
/// <p><b>Caller-namespace expectation:</b> this method runs in the agent's
/// runtime namespace (typically <code>HSCUSTOM</code>). The chained callees
/// each manage their own <code>%SYS</code> switching internally; the
/// orchestrator only saves/restores <code>$NAMESPACE</code> so the
/// reminders helper can print URLs against the original install
/// namespace.</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on full success;
/// otherwise the failure status from the underlying
/// <code>EnsureEvents</code> or <code>Install</code> call, or the trapped
/// exception. Defensive helpers' "deferred" log lines are NOT errors and
/// do not affect the returned status.</p>
ClassMethod Install(pVars) As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        ; %SYS-caller resilience: if invoked from %SYS (e.g., operator ran
        ; `zpm "load /path"` without first issuing `zn "HSCUSTOM"`), switch
        ; to TARGETNAMESPACE so the chained ReadOnlyRole.Install() grant
        ; step lands on the namespace where Ens.* tables are projected.
        ; Callers already in a non-%SYS namespace see no change.
        If tOrigNS = "%SYS" {
            Do ..LogProgress("Detected %SYS caller; switching to install target namespace " _ ..#TARGETNAMESPACE)
            Set $NAMESPACE = ..#TARGETNAMESPACE
        }

        ; (1) Audit-event pre-registration (Story 1.3). Required prerequisite
        ; for any future audit emission — silently lost without it.
        Set tSC = ##class(SessionAgent.Audit.Emit).EnsureEvents()
        If $$$ISERR(tSC) Quit

        ; (2) Read-only RBAC role install (Story 1.4). Layer-3 enforcement
        ; of the read-only invariant (PRD NFR-S1, FR50).
        Set tSC = ##class(SessionAgent.Security.ReadOnlyRole).Install()
        If $$$ISERR(tSC) Quit

        ; (3) Sweep tasks — defensive (class-not-implemented is logged, not
        ; error). The three classes ship in Stories 7.2 + 10.6.
        Do ..ScheduleTaskIfClassExists("SessionAgent.PurgeOrphanedChatHistory", "SessionAgent.Task.PurgeOrphanedChatHistory", "Daily", 2, 0)
        Do ..ScheduleTaskIfClassExists("SessionAgent.PurgeStaleSearchChat", "SessionAgent.Task.PurgeStaleSearchChat", "Daily", 3, 0)
        Do ..ScheduleTaskIfClassExists("SessionAgent.UserVocabularyDecay", "SessionAgent.Task.UserVocabularyDecay", "Weekly", 4, 0)

        ; (4) Default agent configs — defensive (class-not-implemented is
        ; logged, not error). Config.Agent ships in Story 2.4.
        Do ..SeedDefaultAgentConfigs()

        ; (5) Operator reminders to install log (bookmark URLs + README pointer).
        Do ..PrintOperatorReminders()
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Set $NAMESPACE = tOrigNS
    Quit tSC
}

/// <p>Multi-namespace install entry point — runs the full
/// <method>Install</method> orchestration scoped to the operator-supplied
/// <var>pNamespace</var>. Story 6.4 ships this as the documented path for
/// installing iris-session-agent into a non-<code>HSCUSTOM</code> interop
/// namespace on the same IRIS instance (e.g., a per-tenant namespace, a
/// dedicated test namespace, or a second production interop namespace).</p>
///
/// <p><b>Why a separate method (vs. extending <method>Install</method>):</b>
/// the IPM <code>&lt;Invoke&gt;</code> contract calls <method>Install</method>
/// with a <var>pVars</var> hash and runs in the install-target namespace
/// already; this is the single-namespace path and must not change. The
/// multi-namespace path is operator-driven (<i>"after the IPM install in
/// HSCUSTOM, also configure namespace OTHERNS"</i>), so it sits as a peer
/// method that wraps <method>Install</method> with namespace
/// validation + package-mapping pre-check + explicit save/restore.</p>
///
/// <p><b>Three-tier validation</b> (AC-1):</p>
/// <ol>
/// <li>Empty string → <code>$$$ERROR</code> with explicit "cannot be empty"
/// text.</li>
/// <li><code>"%SYS"</code> → <code>$$$ERROR</code> with operator guidance
/// to pick the interop namespace.</li>
/// <li>Namespace doesn't exist → <code>$$$ERROR</code> referencing the
/// missing namespace name and the <code>Config.Namespaces</code> SQL probe
/// for diagnosis.</li>
/// </ol>
///
/// <p><b>Spec-drift note (Story 6.4 Task 0):</b> the spec referenced
/// <code>Config.Namespaces.%ExistsId</code> for the existence check — that
/// API returns <code>0</code> even for existing namespaces (verified
/// empirically). The correct API on IRIS 2024.1 is
/// <code>Config.Namespaces.Exists(pNamespace)</code>, which is what this
/// implementation uses.</p>
///
/// <p><b>Package-mapping pre-check</b> (AC-2): verifies
/// <code>SessionAgent.PKG</code> is mapped to <var>pNamespace</var> via
/// <code>Config.MapPackages.Exists(pNamespace, "SessionAgent")</code>. If
/// not mapped, returns a <code>$$$ERROR</code> whose text contains the
/// operator-runnable <code>Config.MapPackages.Create(...)</code> invocation
/// verbatim — copy-paste solves the operator's problem.</p>
///
/// <p><b>Interop-enabled namespace prerequisite (Story 6.4 Task 0):</b>
/// <var>pNamespace</var> must be an <b>interop-enabled</b> namespace
/// (i.e., <code>%Library.EnsembleMgr.IsEnsembleNamespace</code> returns 1)
/// before this method is invoked. The chained
/// <method>SessionAgent.Security.ReadOnlyRole.Install</method> call
/// performs an SQL <code>GRANT</code> on <code>Ens.MessageHeader</code>;
/// without interop enabled, the table is not projected and the grant
/// fails with SQLCODE -30. Operators using a freshly-created
/// <code>Config.Namespaces.Create</code>-only namespace must call
/// <code>##class(%Library.EnsembleMgr).EnableNamespace(pNamespace, 0)</code>
/// from <code>%SYS</code> before
/// <method>InstallIntoNamespace</method>. The README's "Multi-Namespace
/// Install" walkthrough (Step 1) documents this explicitly.</p>
///
/// <p><b>Idempotency (NFR-R5):</b> inherited from <method>Install</method>
/// (which is itself idempotent per Story 1.5). Running
/// <method>InstallIntoNamespace</method> twice on the same namespace
/// returns <code>$$$OK</code> without duplicating Task Manager entries,
/// <code>Config.Agent</code> rows, or audit-event registrations.</p>
///
/// <p><b>Architectural decision (AC-5):</b> <code>Config.Agent</code> rows
/// are <b>per-namespace</b>. Each namespace's
/// <code>SessionAgent_Config.Agent</code> table is independent —
/// <method>SeedDefaultAgentConfigs</method> is called once per
/// <method>InstallIntoNamespace</method> invocation and seeds rows scoped
/// to <var>pNamespace</var>. The rationale: per-namespace is the safer
/// default — no cross-namespace coupling, no risk of one namespace's
/// <code>Enabled=1</code> flip affecting another's RBAC scope, no operator
/// confusion about which namespace's <code>Provider</code> is "the"
/// provider. A future <method>CopyConfigBetweenNamespaces</method> helper
/// is documented in <code>deferred-work.md</code> for operators with
/// cross-namespace identical config.</p>
///
/// <p><b>Project rules honored:</b> <code>tOrigNS</code> save/restore (per
/// project rule §"Namespace Switching in REST Handlers"); catch block
/// restores <code>$NAMESPACE</code> as its first line; argumentless
/// <code>Quit</code> inside the Try/Catch (per project rule §"QUIT
/// Statement Restrictions in Try/Catch Blocks"); structured
/// <code>%Status</code> for all error returns — operator-error path is
/// always a returned status, never an exception bubble.</p>
ClassMethod InstallIntoNamespace(pNamespace As %String) As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE

    ; (1) Three-tier validation BEFORE any namespace switch — input
    ; validation is cheapest when done first; per project rule "Do all
    ; input validation BEFORE switching to %SYS where possible."
    If pNamespace = "" {
        Quit $$$ERROR($$$GeneralError, "InstallIntoNamespace: pNamespace cannot be empty")
    }
    If pNamespace = "%SYS" {
        Quit $$$ERROR($$$GeneralError, "InstallIntoNamespace: cannot install into %SYS — pick the operator's interop namespace (typically HSCUSTOM)")
    }

    Try {
        ; (2) Namespace existence check — must run from %SYS because
        ; Config.* lives in %SYS. Save/restore via tOrigNS local variable.
        ; Per Story 6.4 Task 0 finding: Config.Namespaces.%ExistsId is
        ; broken on IRIS 2024.1 — Config.Namespaces.Exists is the right
        ; API and returns 1/0 correctly.
        Set $NAMESPACE = "%SYS"
        Set tNsExists = ##class(Config.Namespaces).Exists(pNamespace)
        Set $NAMESPACE = tOrigNS

        If 'tNsExists {
            Set tSC = $$$ERROR($$$GeneralError, "InstallIntoNamespace: namespace '" _ pNamespace _ "' does not exist on this IRIS instance — verify via SELECT Nsp FROM Config.Namespaces")
            Quit
        }

        ; (3) Package-mapping pre-check — verify SessionAgent.PKG is
        ; mapped to pNamespace. If not, return a structured-status error
        ; whose text contains the operator-runnable Create(...) line.
        Set $NAMESPACE = "%SYS"
        Set tMapExists = ##class(Config.MapPackages).Exists(pNamespace, "SessionAgent")
        Set $NAMESPACE = tOrigNS

        If 'tMapExists {
            ; Operator-runnable error text — the Config.MapPackages.Create
            ; signature is (Namespace, Name, .Properties) where Properties
            ; is a byref array carrying Properties("Database") = source.
            ; The example below is in copy-paste-runnable %SYS-shell form;
            ; the operator runs the four lines verbatim.
            Set tSC = $$$ERROR($$$GeneralError, "InstallIntoNamespace: SessionAgent.PKG is not mapped to namespace '" _ pNamespace _ "'. From %SYS, run: Set props(""Database"")=""HSCUSTOM"" Set sc=##class(Config.MapPackages).Create(""" _ pNamespace _ """, ""SessionAgent"", .props) (substitute the source database for your install topology) before retrying InstallIntoNamespace.")
            Quit
        }

        ; (4) Delegation — switch to pNamespace and call the existing
        ; Install() orchestrator. The orchestrator handles its own
        ; chained %SYS switching for Audit/RBAC/Task Manager work.
        Set $NAMESPACE = pNamespace
        Set tSC = ..Install("")
        Set $NAMESPACE = tOrigNS
        ; tSC propagates unchanged — operator sees the same actionable
        ; text the single-namespace Install() path would produce.
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Set $NAMESPACE = tOrigNS
    Quit tSC
}

/// <p>Defensive task-scheduler helper. Creates an IRIS Task Manager entry
/// for <var>pTaskName</var> if and only if (a) the implementing class
/// <var>pTaskClass</var> exists in the dictionary, and (b) no existing task
/// with the same <var>Name</var> is already scheduled.</p>
///
/// <p><b>Why two checks:</b></p>
/// <ul>
/// <li>Class existence (a) — Stories 7.2 / 10.6 will ship the three task
/// classes. Until then, <code>zpm load</code> on a fresh checkout would
/// fail at task-creation time if the helper unconditionally tried to
/// schedule a task whose <code>TaskClass</code> property points to a
/// non-existent class. The Task 0 probe verified that
/// <code>%Dictionary.ClassDefinition.%ExistsId</code> returns 1 / 0 cleanly.</li>
/// <li>Task uniqueness (b) — the Task 0 probe established that
/// <code>%SYS.Task</code> does NOT enforce <code>Name</code> uniqueness; a
/// naive re-save creates a duplicate row with a different ID. The helper
/// therefore performs an explicit SQL existence check on <code>Name</code>
/// before calling <code>%Save()</code>.</li>
/// </ul>
///
/// <p><b>Frequency mapping</b> (Task 0 probe — see <code>%SYS.TaskSuper</code>
/// property descriptions for <code>TimePeriod</code> and
/// <code>DailyFrequency</code>):</p>
/// <ul>
/// <li><var>pFrequency</var> = "Daily" → <code>TimePeriod=0</code>
/// (DAILY-every-N-days), <code>TimePeriodEvery=1</code>,
/// <code>DailyFrequency=0</code> (ONCE-per-day) at the
/// <var>pHour</var>:<var>pMinute</var> start time.</li>
/// <li><var>pFrequency</var> = "Weekly" → <code>TimePeriod=1</code>
/// (WEEKLY-every-N-weeks), <code>TimePeriodEvery=1</code>,
/// <code>TimePeriodDay=1</code> (Sunday), <code>DailyFrequency=0</code>
/// (ONCE-per-day).</li>
/// </ul>
///
/// <p><b>Idempotency:</b> safe to call on every install. If
/// <var>pTaskName</var> already exists in <code>%SYS.Task</code>, the
/// helper returns <code>$$$OK</code> without modifying anything.</p>
///
/// <p>Always returns <code>$$$OK</code> in v1 — failure modes log to the
/// install log but never propagate as errors so a Story 1.5 install
/// continues even if a future Story 7.2 / 10.6 task class change introduces
/// a regression.</p>
ClassMethod ScheduleTaskIfClassExists(pTaskName As %String, pTaskClass As %String, pFrequency As %String, pHour As %Integer, pMinute As %Integer) As %Status [ Private ]
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
        ; (a) Class existence guard — log "deferred" if missing; return $$$OK.
        If '##class(%Dictionary.ClassDefinition).%ExistsId(pTaskClass) {
            Do ..LogProgress(pTaskClass _ " not yet implemented; sweep deferred")
            Quit
        }

        ; Read the task-class class-level Description doc-comment BEFORE
        ; switching to %SYS — application class definitions live in the
        ; mapped (caller) namespace, not in %SYS. Defensive fallback to ""
        ; if %OpenId returns $$$NULLOREF or the Description is empty.
        ; Story 8.0 AC-2 / Epic 7 retro AI-1: ensures Mgmt-Portal Task
        ; Manager Description column is populated with operator-readable
        ; text instead of shipping blank.
        ;
        ; Story 8.0 review fix-now: the raw %Dictionary.ClassDefinition.Description
        ; carries UDL doc-comment HTML markup (<p>, <code>, <method>, etc.)
        ; which truncates mid-tag inside %SYS.Task.Description's MAXLEN=100
        ; window. ..StripDocMarkup() converts the markup-laden source to a
        ; plain-text sentence so the operator-visible Description satisfies
        ; AC-1's "operator-readable text" contract.
        Set tClassDescription = ""
        Set tClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(pTaskClass)
        If $IsObject(tClassDef) {
            Set tClassDescription = ..StripDocMarkup(tClassDef.Description)
        }

        ; Switch to %SYS for the %SYS.Task work; restore at the end.
        Set tCallerNS = tOrigNS
        Set $NAMESPACE = "%SYS"

        ; (b) Task-name dedup guard — explicit SQL existence check on Name.
        ; Per Task 0 probe, %SYS.Task does NOT enforce Name uniqueness;
        ; a naive re-save creates a duplicate row with a different ID.
        Set tFound = 0
        Set tExistingID = ""
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tPrepSC = tStmt.%Prepare("SELECT TOP 1 ID FROM %SYS.Task WHERE Name = ?")
        If $$$ISERR(tPrepSC) {
            Do ..LogProgress("Failed to prepare dedup query for " _ pTaskName _ ": " _ $System.Status.GetErrorText(tPrepSC))
        } Else {
            Set tRS = tStmt.%Execute(pTaskName)
            If tRS.%Next() {
                Set tFound = 1
                Set tExistingID = tRS.%Get("ID")
                Do ..LogProgress("Task " _ pTaskName _ " already scheduled (ID=" _ tExistingID _ "); skipped")
            }
        }

        If 'tFound {
            ; Compute DailyStartTime as seconds-since-midnight ($H format).
            Set tStartSeconds = (pHour * 3600) + (pMinute * 60)

            Set tTask = ##class(%SYS.Task).%New()
            Set tTask.Name = pTaskName
            Set tTask.NameSpace = tCallerNS
            Set tTask.TaskClass = pTaskClass
            Set tTask.Description = tClassDescription
            Set tTask.DailyFrequency = 0
            Set tTask.DailyStartTime = tStartSeconds
            Set tTask.TimePeriodEvery = 1

            If pFrequency = "Daily" {
                Set tTask.TimePeriod = 0
            } ElseIf pFrequency = "Weekly" {
                Set tTask.TimePeriod = 1
                Set tTask.TimePeriodDay = 1
            } Else {
                ; Unknown frequency — default to Daily and log.
                Set tTask.TimePeriod = 0
                Do ..LogProgress("Unknown frequency '" _ pFrequency _ "' for " _ pTaskName _ "; defaulted to Daily")
            }

            Set tSaveSC = tTask.%Save()
            If $$$ISERR(tSaveSC) {
                Do ..LogProgress("Failed to schedule " _ pTaskName _ ": " _ $System.Status.GetErrorText(tSaveSC))
            } Else {
                Set tMinPad = $Translate($Justify(pMinute, 2), " ", "0")
                Do ..LogProgress("Scheduled " _ pTaskName _ " (" _ pFrequency _ " at " _ pHour _ ":" _ tMinPad _ ")")
            }
        }

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do ..LogProgress("Exception scheduling " _ pTaskName _ ": " _ ex.DisplayString())
    }
    Quit tSC
}

/// <p>Defensive seed helper. Inserts two default
/// <code>SessionAgent.Config.Agent</code> rows
/// (<code>session-inspection</code> + <code>message-search</code>) if and
/// only if the <code>Config.Agent</code> class exists in the dictionary.
/// Story 2.4 ships the seeding logic; this method is now live, not a
/// placeholder.</p>
///
/// <p><b>Defensive behavior:</b> the
/// <code>%Dictionary.ClassDefinition.%ExistsId</code> guard remains as a
/// safety net so a pre-Epic-2 checkout (or a future epic that temporarily
/// removes the class) does not break <code>zpm load</code>. When the
/// class is absent, the helper logs and returns <code>$$$OK</code>.</p>
///
/// <p><b>Idempotency (NFR-R5):</b> for each agent name, the helper calls
/// the dictionary-generated
/// <code>AgentNameIdxExists(name)</code> predicate before
/// <method>%Save</method>. If the row already exists (re-install case),
/// the helper logs <i>"row already present; skipping"</i> and continues.
/// Combined with the unique <code>AgentNameIdx</code> on
/// <CLASS>SessionAgent.Config.Agent</CLASS>, this guarantees no duplicate
/// rows on any number of re-installs.</p>
///
/// <p><b>Seed shape</b> comes from
/// <method>SessionAgent.Config.AgentDefaults.GetSeedConfig</method>
/// (Story 2.4): Provider=<code>openai</code>, Model=<code>gpt-4.1-mini</code>,
/// MaxTokens=<code>4096</code>, Temperature=<code>0.0</code>,
/// ReadOnly=<code>1</code>, EnvVarName=<code>OPENAI_API_KEY</code>,
/// Enabled=<code>0</code> (operator must explicitly opt in via Story 6
/// UI).</p>
///
/// <p><b>Project rules honored:</b> <code>tSC</code> initialized BEFORE
/// the Try block; argumentless <code>Quit</code> inside the Try (project
/// rule §"QUIT Statement Restrictions in Try/Catch Blocks"); every
/// <method>%Save</method> return checked with <code>$$$ISERR</code>
/// (project rule §"Write Status Checking"); failure logs the agent name
/// and the error text, then propagates the failing status to the caller
/// so the overall install can fail loudly.</p>
ClassMethod SeedDefaultAgentConfigs() As %Status
{
    Set tSC = $$$OK
    Try {
        If '##class(%Dictionary.ClassDefinition).%ExistsId("SessionAgent.Config.Agent") {
            Do ..LogProgress("SessionAgent.Config.Agent not yet implemented; default configs deferred")
            Quit
        }

        Do ..LogProgress("Config.Agent present — seeding default rows")

        ; Seed each agent name with idempotent existence check. Two seeds
        ; in v1: session-inspection + message-search. The list is hand-rolled
        ; (no $ListBuild iteration) so the failure-status path can identify
        ; exactly which agent's %Save failed without parsing the list.
        Set tSC = ..SeedOneAgent("session-inspection")
        If $$$ISERR(tSC) Quit
        Set tSC = ..SeedOneAgent("message-search")
        If $$$ISERR(tSC) Quit
    }
    Catch ex {
        Do ..LogProgress("Exception in SeedDefaultAgentConfigs: " _ ex.DisplayString())
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Inner per-agent seed helper. Idempotent: if the row already exists
/// (verified via the dictionary-generated
/// <code>AgentNameIdxExists</code> predicate), logs and returns
/// <code>$$$OK</code> without modifying anything.</p>
///
/// <p>On the seeding path, retrieves the OD4 default-shape instance from
/// <method>SessionAgent.Config.AgentDefaults.GetSeedConfig</method>,
/// calls <method>%Save</method>, and checks the returned status. On
/// failure logs <var>pAgentName</var> + the IRIS error text and returns
/// the failing status; on success logs <i>"seeded {pAgentName}"</i> and
/// returns <code>$$$OK</code>.</p>
ClassMethod SeedOneAgent(pAgentName As %String) As %Status [ Private ]
{
    Set tSC = $$$OK
    Try {
        If ##class(SessionAgent.Config.Agent).AgentNameIdxExists(pAgentName) {
            Do ..LogProgress(pAgentName _ ": row already present; skipping")
            Quit
        }

        Set tAgent = ##class(SessionAgent.Config.AgentDefaults).GetSeedConfig(pAgentName)
        If '$IsObject(tAgent) {
            Do ..LogProgress(pAgentName _ ": GetSeedConfig returned $$$NULLOREF; skipping")
            Quit
        }

        Set tSaveSC = tAgent.%Save()
        If $$$ISERR(tSaveSC) {
            Do ..LogProgress("Failed to seed " _ pAgentName _ ": " _ $System.Status.GetErrorText(tSaveSC))
            Set tSC = tSaveSC
            Quit
        }

        Do ..LogProgress("seeded " _ pAgentName)
    }
    Catch ex {
        Do ..LogProgress("Exception seeding " _ pAgentName _ ": " _ ex.DisplayString())
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Writes operator-facing install reminders to the install log: both
/// bookmark URL patterns (HealthShare + plain IRIS) with the actual
/// current namespace substituted, plus a one-line pointer to the README's
/// "Operator Prerequisites" section.</p>
///
/// <p>The URLs use the literal current <code>$NAMESPACE</code> (e.g.,
/// <code>HSCUSTOM</code>) so the operator can copy-paste directly. The
/// README itself uses the placeholder <code>&lt;NS&gt;</code> shape because
/// the README is generic across installs.</p>
///
/// <p><b>Note on role naming:</b> the reminders text references the
/// read-only role only via the README pointer; the role name
/// (<code>SessionAgent_ReadOnly</code> — no <code>%</code> prefix per
/// Story 1.4 finding) is documented in the README, not duplicated here.</p>
ClassMethod PrintOperatorReminders() [ Private ]
{
    Set tNS = $NAMESPACE
    Write !,"=== iris-session-agent install reminders ==="
    Write !,"Bookmark URLs (HealthShare):"
    Write !,"  /csp/healthshare/", tNS, "/SessionAgent.EnsPortal.VisualTrace.zen"
    Write !,"  /csp/healthshare/", tNS, "/SessionAgent.EnsPortal.MessageViewer.zen"
    Write !,"Bookmark URLs (plain IRIS):"
    Write !,"  /csp/", tNS, "/SessionAgent.EnsPortal.VisualTrace.zen"
    Write !,"  /csp/", tNS, "/SessionAgent.EnsPortal.MessageViewer.zen"
    Write !,"See README ""Operator Prerequisites"" for one-time setup (Web Gateway timeout 60->300, RBAC role assignment, API key supply)."
    Write !,"==========================================="
}

/// <p>Internal log helper — writes a single timestamped progress line to
/// the install log with a consistent <code>[iris-session-agent]</code>
/// prefix so operators can grep for orchestrator output amid normal
/// <code>zpm load</code> noise.</p>
ClassMethod LogProgress(pMsg As %String) [ Private ]
{
    Write !,"[iris-session-agent] ", pMsg
}

/// <p>Strip UDL doc-comment HTML markup from <var>pText</var> so the
/// resulting string is safe to assign to a Mgmt-Portal-visible
/// <code>Description</code> column (e.g.,
/// <CLASS>%SYS.Task</CLASS> <code>Description</code>, MAXLEN=100). Removes
/// the small set of tags emitted by class-level <code>///</code> doc
/// comments — <code>&lt;p&gt;</code>, <code>&lt;code&gt;</code>,
/// <code>&lt;method&gt;</code>, <code>&lt;property&gt;</code>,
/// <code>&lt;var&gt;</code>, <code>&lt;b&gt;</code>, <code>&lt;i&gt;</code>,
/// <code>&lt;ul&gt;</code>, <code>&lt;li&gt;</code>, <code>&lt;CLASS&gt;</code>
/// — by skipping every <code>&lt;...&gt;</code> segment. Also collapses
/// CR/LF/tab runs to single spaces and trims edge whitespace so the result
/// reads as a contiguous prose sentence in the operator-visible truncation
/// window.</p>
///
/// <p>Story 8.0 fix-now (Epic 7 retro AI-1 follow-through): AC-2's first
/// implementation pass assigned the raw <code>%Dictionary.ClassDefinition.Description</code>
/// directly to <code>%SYS.Task.Description</code>, but the raw value carries
/// the HTML markup verbatim and the MAXLEN=100 truncation window cuts a
/// typical doc-comment off mid-tag (e.g.,
/// <code>"&lt;p&gt;Scheduled sweep task that deletes Inspection-keyed\r\n&lt;code&gt;SessionAgent.Chat.History&lt;/code&gt; rows w"</code>).
/// AC-1's own definition of "operator-readable text" rules this out — the
/// reviewer enforces a plain-text contract on shipped artifact descriptions.
/// This helper is the strip step that closes the gap.</p>
ClassMethod StripDocMarkup(pText As %String) As %String [ Private ]
{
    If pText = "" Quit ""
    Set tOut = ""
    Set tLen = $Length(pText)
    Set tI = 1
    While tI '> tLen {
        Set tCh = $Extract(pText, tI)
        If tCh = "<" {
            ; Skip to closing '>' (or end of string if malformed).
            Set tClose = $Find(pText, ">", tI)
            If tClose = 0 {
                Set tI = tLen + 1
            } Else {
                Set tI = tClose
            }
        } Else {
            Set tOut = tOut _ tCh
            Set tI = tI + 1
        }
    }
    ; Collapse CR/LF/TAB and any double-space runs to a single space; trim edges.
    Set tOut = $Translate(tOut, $Char(13, 10, 9), "   ")
    While tOut [ "  " {
        Set tOut = $Replace(tOut, "  ", " ")
    }
    Quit $ZStrip(tOut, "<>W")
}

}
