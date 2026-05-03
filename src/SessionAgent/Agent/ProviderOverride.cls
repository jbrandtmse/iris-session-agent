/// <p>Test-only injection point for the
/// <CLASS>SessionAgent.LLM.Provider</CLASS> override that
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// consults at the top of every turn. Production code never touches
/// this class; it carries no production audit footprint, no operator-
/// visible surface, and no persistent storage.</p>
///
/// <p><b>Why a dedicated holder.</b> ObjectScript has no portable
/// process-private OREF channel — process-private globals
/// (<code>^||...</code>) round-trip OREFs as the literal string
/// <code>"oref@class"</code> with <code>$IsObject</code> returning 0;
/// regular variables (<code>%foo</code>) are NEW'd implicitly across
/// ClassMethod boundaries. The pattern that works: stash a *class
/// name* and a *configuration JSON* in a process-private global, then
/// instantiate a fresh mock from those primitives inside
/// <method>InstantiateProvider</method>. The mock's per-call mutable
/// state (response-list cursor) lives in a separate process-private
/// global it reads/writes itself.</p>
///
/// <p><b>Test contract.</b></p>
/// <ol>
/// <li>Before the test invokes <method>RunTurn</method>, call
/// <method>SetOverride</method> with a class name and a configuration
/// payload (the response-list array's JSON serialization).</li>
/// <li><method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// detects the override, instantiates the named class, calls its
/// <method>%InstallOverrideConfig</method> with the configuration
/// payload, and returns the configured OREF.</li>
/// <li>After the test, call <method>ClearOverride</method> in
/// <code>OnAfterOneTest</code>.</li>
/// </ol>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.12</a> (lines 1064–1096) — context.</li>
/// <li><a href="../../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a>
/// §"ObjectScript Collection and Object Handling" — OREF
/// stringification gotcha that motivated the
/// "name + JSON config, instantiate-on-read" pattern.</li>
/// </ul>
Class SessionAgent.Agent.ProviderOverride Extends %RegisteredObject
{

/// <p>Stash an override for the next
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>
/// call. <var>pClassName</var> is the fully-qualified class name to
/// instantiate; <var>pConfigJson</var> is an arbitrary JSON string the
/// instantiated mock reads via its
/// <code>%InstallOverrideConfig</code> hook to configure itself.</p>
ClassMethod SetOverride(pClassName As %String, pConfigJson As %String = "")
{
    Set ^||SessionAgentProviderOverrideClass = pClassName
    Set ^||SessionAgentProviderOverrideConfig = pConfigJson
    ; Reset the per-mock response cursor so the new test starts at
    ; index 0 even if the prior test consumed responses.
    Kill ^||SessionAgentProviderOverrideCursor
    Quit
}

/// <p>Return a configured override OREF if one is installed; else
/// <code>$$$NULLOREF</code>. Production code calls this and falls
/// through to the production provider switch on NULLOREF.</p>
ClassMethod GetOverride() As SessionAgent.LLM.Provider
{
    If '$Data(^||SessionAgentProviderOverrideClass) Quit $$$NULLOREF
    Set tClassName = ^||SessionAgentProviderOverrideClass
    If tClassName = "" Quit $$$NULLOREF

    Set tInst = $$$NULLOREF
    Try {
        Set tInst = $ClassMethod(tClassName, "%New")
        If $IsObject(tInst), $Data(^||SessionAgentProviderOverrideConfig) {
            Set tConfig = ^||SessionAgentProviderOverrideConfig
            Do $Method(tInst, "%InstallOverrideConfig", tConfig)
        }
    }
    Catch ex {
        Set tInst = $$$NULLOREF
    }
    Quit tInst
}

/// <p>Read the next canned response payload from the per-process
/// response list, advancing the cursor. The mock's
/// <method>IssueHttpsPost</method> override calls this to walk
/// through the response sequence one round-trip at a time. When the
/// list is exhausted, returns the LAST entry on every subsequent call
/// (defensive — keeps under-provisioned tests from crashing on an
/// out-of-bounds read).</p>
///
/// <p>Returns the empty string when no override is installed.</p>
ClassMethod NextCannedResponse() As %String
{
    If '$Data(^||SessionAgentProviderOverrideConfig) Quit ""
    Set tConfigJson = ^||SessionAgentProviderOverrideConfig
    If tConfigJson = "" Quit ""

    Set tIdx = $Get(^||SessionAgentProviderOverrideCursor, 0)
    Set ^||SessionAgentProviderOverrideCursor = tIdx + 1

    Set tBody = ""
    Try {
        Set tConfig = ##class(%DynamicObject).%FromJSON(tConfigJson)
        If $IsObject(tConfig), tConfig.%IsDefined("responses") {
            Set tResponses = tConfig.%Get("responses")
            If $IsObject(tResponses), tResponses.%Size() > 0 {
                Set tCount = tResponses.%Size()
                Set tUseIdx = tIdx
                If tUseIdx >= tCount {
                    Set tUseIdx = tCount - 1
                }
                Set tBody = tResponses.%Get(tUseIdx)
            }
        }
    }
    Catch ex {
        Set tBody = ""
    }
    Quit tBody
}

/// <p>Read the HTTP status code paired with the current response. If
/// the override config carries a parallel <code>"statusCodes"</code>
/// array, returns the matching index; otherwise returns 200.</p>
///
/// <p><b>Note:</b> reads the cursor at <i>tIdx-1</i> because
/// <method>NextCannedResponse</method> advances before its caller
/// reads the status. Callers that need the status MUST read it AFTER
/// <method>NextCannedResponse</method>.</p>
ClassMethod CurrentStatusCode() As %Integer
{
    If '$Data(^||SessionAgentProviderOverrideConfig) Quit 200
    Set tConfigJson = ^||SessionAgentProviderOverrideConfig
    If tConfigJson = "" Quit 200

    Set tIdx = $Get(^||SessionAgentProviderOverrideCursor, 1) - 1
    If tIdx < 0 Set tIdx = 0

    Set tStatus = 200
    Try {
        Set tConfig = ##class(%DynamicObject).%FromJSON(tConfigJson)
        If $IsObject(tConfig), tConfig.%IsDefined("statusCodes") {
            Set tCodes = tConfig.%Get("statusCodes")
            If $IsObject(tCodes), tCodes.%Size() > 0 {
                Set tCount = tCodes.%Size()
                Set tUseIdx = tIdx
                If tUseIdx >= tCount {
                    Set tUseIdx = tCount - 1
                }
                Set tStatus = +tCodes.%Get(tUseIdx)
            }
        }
    }
    Catch ex {
        Set tStatus = 200
    }
    Quit tStatus
}

/// <p>Clear the override — production behavior is restored on the
/// next call to
/// <method>SessionAgent.Agent.AgentLoop.InstantiateProvider</method>.
/// Test classes call this in <code>OnAfterOneTest</code>.</p>
ClassMethod ClearOverride()
{
    Kill ^||SessionAgentProviderOverrideClass
    Kill ^||SessionAgentProviderOverrideConfig
    Kill ^||SessionAgentProviderOverrideCursor
    Quit
}

/// <p>Return the per-test call counter — number of times the mock has
/// returned a canned response since the last
/// <method>SetOverride</method> reset. Useful in assertions ("the
/// loop ran exactly N round-trips").</p>
ClassMethod CallCount() As %Integer
{
    Quit $Get(^||SessionAgentProviderOverrideCursor, 0)
}

}
