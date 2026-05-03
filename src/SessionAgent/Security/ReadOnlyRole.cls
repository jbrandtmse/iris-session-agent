/// <p>Layer-3 RBAC installer. Creates the <code>SessionAgent_ReadOnly</code>
/// role and grants SELECT-only on the canonical <code>Ens.*</code> tables
/// the agent reads. (See the <code>ROLENAME</code> parameter docstring
/// below for why the role does NOT carry the <code>%</code> prefix the
/// original project memory specified.)</p>
///
/// <p>This is the third layer of the read-only enforcement stack
/// (PRD NFR-S1, FR50). Layers 1 (code discipline per tool) and 2
/// (<code>SessionAgent.Tool.Registry.Dispatch</code> <code>MutatesState=0</code>
/// gate) live inside the agent's process; this layer survives an L1/L2
/// oversight by enforcing privilege at the IRIS database layer.</p>
///
/// <p><b>Idempotency:</b> the implementation is safe to call on every IPM
/// install / upgrade. The role is created only when absent
/// (<code>Security.Roles.Exists</code> check), and
/// <code>$SYSTEM.SQL.Security.GrantPrivilege</code> is itself idempotent
/// (verified in Story 1.4 Task 0 — re-granting an already-granted privilege
/// returns <code>$$$OK</code> silently).</p>
///
/// <p><b>Future Epic 4 hook:</b> body-class SELECT grants land in Epic 4
/// Story 4.2 GetMessageBody dispatch ladder — that story will extend this
/// install with additional table grants on the body classes that ship with
/// IRIS interoperability productions (e.g. <code>EnsLib.HL7.Message</code>,
/// <code>EnsLib.EDI.XML.Document</code>).</p>
Class SessionAgent.Security.ReadOnlyRole Extends %RegisteredObject
{

/// <p>The role name installed by this class.</p>
///
/// <p><b>Naming-decision note (Story 1.4 Task 0):</b> the original project
/// memory specified <code>%SessionAgent_ReadOnly</code> on the assumption
/// the leading <code>%</code> would mark it as a system role. Live IRIS
/// rejects that name with error #887 ("Invalid role name") — the
/// <code>Security.Roles.Create</code> validator reserves the <code>%</code>
/// prefix exclusively for IRIS-shipped pre-defined system roles
/// (<code>%All</code>, <code>%Manager</code>, <code>%Operator</code>, ...).
/// User-created roles must NOT begin with <code>%</code>. The role name was
/// therefore changed to <code>SessionAgent_ReadOnly</code>; the underscore
/// is permitted by the validator. See
/// <code>_bmad-output/implementation-artifacts/probes/story-1-4-rbac-api-probe-2026-05-02.txt</code>
/// §"Naming-decision note" for the verbatim probe transcript.</p>
Parameter ROLENAME = "SessionAgent_ReadOnly";

/// <p>Idempotent install: create the <code>SessionAgent_ReadOnly</code>
/// role if absent, then grant SELECT (and ONLY SELECT) on the canonical
/// <code>Ens.*</code> tables the agent reads.</p>
///
/// <p><b>Caller-namespace expectation:</b> this method must be invoked from
/// the namespace where the agent runs (i.e., where the <code>Ens.*</code>
/// tables are projected — typically <code>HSCUSTOM</code> or the
/// operator's chosen Ens namespace). If invoked from <code>%SYS</code>
/// directly, step (2) will fail with SQLCODE -30 ("Table or view not
/// found") because <code>Ens.*</code> tables do not exist there. The
/// production path is the ZPM <code>&lt;Invoke&gt;</code> hook in
/// <code>module.xml</code>, which runs the method in the module's install
/// namespace — i.e., the agent's runtime namespace, which is correct.</p>
///
/// <p>Uses the explicit save/restore pattern for <code>$NAMESPACE</code>
/// (per project rule §"Namespace Switching"); the catch block restores the
/// namespace as its first line. Argumented <code>Quit</code> is not used
/// inside the try/catch (per project rule §"QUIT Statement Restrictions in
/// Try/Catch Blocks").</p>
///
/// <p>Returns <code>%Status</code>: <code>$$$OK</code> on success;
/// otherwise the failure status from the underlying
/// <code>Security.Roles.Create</code> or
/// <code>$SYSTEM.SQL.Security.GrantPrivilege</code> call, or the trapped
/// exception.</p>
ClassMethod Install() As %Status
{
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE

    ; %SYS-caller resilience (Story 1.5 follow-up): if invoked from %SYS
    ; (e.g., operator ran `zpm "load /path"` without first issuing
    ; `zn "HSCUSTOM"`, or this is the standalone <Invoke> of this method
    ; in module.xml — the orchestrator switches its own context but each
    ; <Invoke> sees a fresh $NAMESPACE), pick a sensible target namespace
    ; for the SQL grant in step (2). Ens.* tables are projected in the
    ; operator's interop namespace (typically HSCUSTOM), not in %SYS, so
    ; the grant would fail with SQLCODE -30 if invoked while pinned to
    ; %SYS. We pick HSCUSTOM as the default; an operator running on
    ; plain-IRIS may need to manually re-grant in their chosen namespace.
    If tOrigNS = "%SYS" {
        Set tOrigNS = "HSCUSTOM"
    }

    Try {
        Set $NAMESPACE = "%SYS"

        ; (1) Create the role if absent. Resources="" and GrantedRoles=""
        ; — the role conveys NO IRIS resource permissions and NO nested
        ; role memberships; its only privilege is the SELECT grants applied
        ; in step (2).
        If '##class(Security.Roles).Exists(..#ROLENAME) {
            Set tSC = ##class(Security.Roles).Create(
                ..#ROLENAME,
                "Read-only access to Ens.* tables for iris-session-agent",
                "",
                "")
            If $$$ISERR(tSC) {
                Set $NAMESPACE = tOrigNS
                Quit
            }
        }

        ; (2) Grant SELECT on the canonical Ens.* surfaces. The grant API
        ; ($SYSTEM.SQL.Security.GrantPrivilege) is idempotent: re-granting
        ; an already-granted privilege returns $$$OK silently (verified in
        ; Story 1.4 Task 0). No Exists-check wrapping needed.
        ;
        ; SQL projection note: Ens.Util.Log and Ens.Rule.Log are projected
        ; with underscore-separator schemas (Ens_Util.Log / Ens_Rule.Log).
        ; The class names use dots; the SQL names use underscores. We use
        ; the SQL names because $SYSTEM.SQL.Security.GrantPrivilege is a
        ; SQL-layer API.
        ;
        ; Ens.SuperSessionIndex projects with the dot-form (no underscore
        ; needed) — this is the IRIS class projection convention; classes
        ; named %.X project to schema X, classes named A.B project to
        ; schema A_B with table B unless the class is at the top of its
        ; package, in which case the class name itself becomes the table.
        ;
        ; Future epic-4 hook: body-class SELECT grants land in Epic 4
        ; Story 4.2 GetMessageBody dispatch ladder.
        Set tTables = "Ens.MessageHeader,Ens.SuperSessionIndex,Ens_Util.Log,Ens_Rule.Log"
        Set $NAMESPACE = tOrigNS  ; GrantPrivilege expects to be called from the namespace where the tables live
        Set tSC = $SYSTEM.SQL.Security.GrantPrivilege("SELECT", tTables, "TABLE", ..#ROLENAME)
        If $$$ISERR(tSC) Quit
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
