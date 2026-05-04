/// <p>CSP page that serves <code>static/chat-panel.js</code> at the URL
/// <code>/csp/&lt;ns&gt;/SessionAgent.UI.ChatPanelAsset.cls</code> on every
/// namespace where the <code>SessionAgent.PKG</code> resource is mapped.</p>
///
/// <p><b>Why this exists:</b> the original Story 3.6 + earlier story-1.1
/// approach used a dedicated static-asset
/// <code>&lt;CSPApplication Url="/csp/static/iris-session-agent"&gt;</code>
/// + <code>&lt;FileCopy&gt;</code> in <code>module.xml</code> with the
/// <code>${cspdir}</code> ZPM template variable that did NOT expand at
/// install time — the literal substring <code>${cspdir}</code> ended up in
/// the CSP application's <code>Path</code>, breaking static-asset serving.
/// The Story 3.6 lead-driven AC-5 smoke (2026-05-03) discovered this
/// integration-time bug + collaboration with the project lead pivoted the
/// design to "serve the JS via a class" — eliminating the entire
/// install-time file-copy + per-namespace CSP application machinery.</p>
///
/// <p><b>Multi-namespace deployments:</b> ZERO additional configuration.
/// Because this is an ObjectScript class shipped via the
/// <code>SessionAgent.PKG</code> ZPM resource, the same class is available
/// on every namespace where the package is mapped. Any operator who runs
/// <code>zpm install iris-session-agent</code> in additional namespaces
/// gets the page for free at
/// <code>/csp/&lt;those-ns&gt;/SessionAgent.UI.ChatPanelAsset.cls</code>.
/// Compare the previous file-copy approach which required the operator to
/// re-run install OR manually copy <code>chat-panel.js</code> into each
/// namespace's CSP directory.</p>
///
/// <p><b>Source of truth:</b> <code>static/chat-panel.js</code> (in the IPM
/// module's <code>Root</code> directory). This page reads it at runtime via
/// <code>%Stream.FileCharacter</code>. The auto-sync workflow keeps the
/// file fresh in dev; in production the file ships with the IPM source
/// tree (IPM persists source post-install per project convention). Tests
/// (<CLASS>SessionAgent.Test.ChatPanelJsTest</CLASS>) continue to read the
/// file directly from disk — same source of truth.</p>
///
/// <p><b>Why a runtime file read instead of an XData block embedding:</b>
/// chat-panel.js is ~755 lines / ~35 KB. Embedding it inline in an XData
/// block would inflate this class file to ~800 lines and create a
/// dual-maintenance burden (XData and <code>static/chat-panel.js</code>
/// could drift). Runtime read keeps the class small (~50 lines), preserves
/// a single source of truth, and the IPM <code>Module.Root</code> resolution
/// is reliable across install topologies. Trade-off: runtime depends on the
/// IPM source tree being intact post-install — true on every standard IPM
/// install.</p>
///
/// <p><b>Defense-in-depth:</b> if the IPM module lookup OR the file read
/// fails, OnPage emits a <code>/* ... */</code> JS comment with the failure
/// reason instead of throwing. Operators see "The chat panel is missing"
/// in the dev console rather than a Zen page crash; the operator-quickstart
/// README documents this contract.</p>
Class SessionAgent.UI.ChatPanelAsset Extends %CSP.Page
{

/// <p>Default Content-Type for the served response. Overridden in
/// <method>OnPreHTTP</method> as well so the value is set BEFORE the
/// response headers are committed (per <code>%CSP.Page</code> contract —
/// see InterSystems documentation).</p>
Parameter CONTENTTYPE = "text/javascript";

/// <p>Set Content-Type + caching headers BEFORE response headers commit.
/// Per <code>%CSP.Page</code> docs the <code>OnPreHTTP</code> hook is the
/// only safe site to mutate <code>%response</code>.</p>
///
/// <p><b>Caching:</b> the browser caches chat-panel.js for 5 minutes
/// (300 seconds) — long enough to skip re-downloads during a multi-page
/// operator session, short enough that a hot-fix to chat-panel.js
/// auto-propagates within minutes without operator action.</p>
ClassMethod OnPreHTTP() As %Boolean
{
    Set %response.ContentType = "text/javascript"
    Set %response.CharSet = "UTF-8"
    ; Cache for 5 minutes — short enough that hot-fix propagation is fast,
    ; long enough that operator multi-page sessions don't re-download.
    Do %response.SetHeader("Cache-Control", "public, max-age=300")
    Quit 1
}

/// <p>Stream <code>static/chat-panel.js</code> from the IPM module's source
/// root to the response. On any failure (module not found, file missing,
/// stream error), emits a <code>/* ... */</code> JS comment instead of
/// throwing — operator sees the failure in the dev console, not a Zen
/// page crash.</p>
ClassMethod OnPage() As %Status
{
    Set tSC = $$$OK
    Try {
        Set tMod = ##class(%IPM.Storage.Module).NameOpen("iris-session-agent")
        If '$IsObject(tMod) {
            Write "/* iris-session-agent: IPM module 'iris-session-agent' not found in registry — chat panel JS unavailable */"
            Quit
        }
        ; IRIS file APIs accept forward slashes on Windows + Unix; the
        ; tMod.Root value already has the platform-correct trailing slash.
        Set tPath = tMod.Root _ "static/chat-panel.js"
        If '##class(%File).Exists(tPath) {
            Write "/* iris-session-agent: chat-panel.js not found at " _ tPath _ " — IPM source tree may be moved or pruned */"
            Quit
        }

        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tLinkSC = tStream.LinkToFile(tPath)
        If $$$ISERR(tLinkSC) {
            Write "/* iris-session-agent: failed to link to " _ tPath _ ": " _ $System.Status.GetErrorText(tLinkSC) _ " */"
            Quit
        }

        ; Stream chunks to %response. Default Read chunk size is 32KB —
        ; chat-panel.js fits in 1-2 reads.
        Do tStream.Rewind()
        While 'tStream.AtEnd {
            Write tStream.Read()
        }
    }
    Catch ex {
        Write "/* iris-session-agent: " _ ex.DisplayString() _ " */"
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
