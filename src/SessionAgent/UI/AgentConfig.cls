/// <p>Operator-Admin form for editing per-agent runtime configuration
/// rows (<CLASS>SessionAgent.Config.Agent</CLASS>). Renders a Zen form
/// with agent selector (Inspection / Search), provider dropdown,
/// model combobox with provider-specific suggestions, credential-source
/// radio (env-var OR <CLASS>Ens.Config.Credentials</CLASS> entry),
/// endpoint-URL field (visible only for openai-compatible providers),
/// max-tokens / temperature / system-prompt-override inputs, and an
/// enabled flag.</p>
///
/// <p><b>Story 6.1 scope: form layout only.</b> The Save handler that
/// actually persists changes ships in Story 6.2 — clicking Save on this
/// page surfaces an inline message ("Save handler ships in Story 6.2 —
/// your changes are not yet persisted.") and leaves the form dirty so
/// the operator can re-test once 6.2 lands. This split keeps the form
/// layout testable in isolation per UX-DR11 (matches
/// <CLASS>EnsPortal.Credentials</CLASS> conventions).</p>
///
/// <p><b>Inheritance.</b> Extends
/// <CLASS>EnsPortal.Template.standardPage</CLASS> so the page renders
/// inside the standard Mgmt-Portal chrome (title bar, locator/breadcrumb
/// strip, ribbon, small-menu, session-keepalive, autologout) — matching
/// the sibling <CLASS>EnsPortal.Credentials</CLASS> page operators
/// already know. The 2026-05-06 manual-test pass surfaced that the
/// previous <code>%ZEN.Component.page</code> + <code>APPLICATION =
/// "EnsPortal.Application"</code> shape inherited the stylesheet but
/// not the chrome — operators saw a bare unstyled form. Switching the
/// parent class is the correct fix per UX-DR26 (look like other Mgmt
/// Portal config pages). The standardPage parent already declares
/// <code>APPLICATION</code> + <code>DOMAIN</code> so we drop those
/// duplicate parameters here.</p>
///
/// <p>The form layout moves from <code>XData Contents</code> with a
/// <code>&lt;page&gt;</code> root to <code>XData contentPane</code> with
/// a <code>&lt;pane&gt;</code> root — the pane is what
/// <CLASS>EnsPortal.Template.standardPage</CLASS> embeds inside the
/// chrome. Component IDs and JS handler bindings are unchanged so all
/// existing tests, screenshots, and operator muscle memory still apply.</p>
///
/// <p><b>Static-text-at-runtime pattern.</b> The XData Contents block
/// declares form components with NO label/caption/displayList attributes
/// — those are set in <method>%OnAfterCreatePage</method> at runtime.
/// Reason: the parent's <code>DOMAIN="%Ensemble"</code> setting causes
/// the Zen XData compiler to <code>%macroText</code> custom captions
/// which raises <code>&lt;PROTECT&gt;</code> when inserting new strings
/// into <code>^IRIS.Msg("Ensemble",...)</code> from a non-ENSLIB build
/// context (MPP5646). Same workaround the Story 3.3
/// <CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> subclass uses for
/// its tab caption/title (see <code>%OnAfterCreatePage</code> there).</p>
///
/// <p><b>System-prompt override char counter (Story 6.0 AC-2 binding
/// reassignment of Story 5.1 deferred-work Item G).</b> The
/// <code>SystemPromptOverride</code> textarea ships with a live char
/// counter + soft validator: warning at 7500 chars (amber), exceedance
/// flag at 8192 chars (danger). Operators see the cap they're approaching
/// instead of silently hitting the persistence-layer truncation. The
/// property-cap raise (8192 → 32767) is OUT OF SCOPE for Story 6.1 and
/// deferred to a sibling Story 6.x backend tweak per the deferred-work
/// entry's last clause; this story ships the operator-warning UX.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md</a>
/// Story 6.1 (lines 1815–1858) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// line 873 — class file path; UX-DR26 styling.</li>
/// <li><a href="../../../_bmad-output/implementation-artifacts/deferred-work.md">deferred-work.md</a>
/// — Story 5.1 entry "SystemPromptOverride MAXLEN=8192 silent truncation"
/// (Item G, BINDING for Story 6.1 AC-3 + AC-7).</li>
/// <li><CLASS>SessionAgent.Config.Agent</CLASS> — the row this form
/// edits.</li>
/// <li><CLASS>EnsPortal.Credentials</CLASS> — sibling Mgmt Portal config
/// page; provided the Zen-page layout precedent.</li>
/// <li><CLASS>SessionAgent.EnsPortal.VisualTrace</CLASS> — sibling Zen
/// subclass; provided the runtime-caption-set workaround for MPP5646.</li>
/// </ul>
Class SessionAgent.UI.AgentConfig Extends EnsPortal.Template.standardPage [ System = 4 ]
{

/// <p>Page name is intentionally empty at the parameter level — the
/// runtime <method>%OnGetPageName</method> override returns the
/// operator-friendly string. Setting <code>PAGENAME = "Agent
/// Configuration"</code> at compile time triggers the parent's
/// <code>$$$Text(..#PAGENAME)</code> code generator to write the new
/// string into <code>^IRIS.Msg("Ensemble",...)</code> from a non-ENSLIB
/// build context, raising MPP5646 / <code>&lt;PROTECT&gt;</code> at
/// compile time. Empty parameter + runtime callback is the pattern
/// other custom-string EnsPortal subclasses use.</p>
Parameter PAGENAME = "";

/// <p>Resource gating: operator must have %Ens_Portal:USE (the standard
/// Mgmt Portal access resource) to view the page. The
/// SessionAgent_ReadOnly role grants %Ens_Portal:USE indirectly via
/// Story 1.4's role install. Edit-time enforcement (the actual save
/// handler) lands in Story 6.2 with EDITRESOURCE wiring.</p>
Parameter RESOURCE = "%Ens_Portal:USE";

/// <p>Form layout. Thirteen components in the order specified by AC-2.
/// All <code>label</code> / <code>caption</code> / <code>displayList</code>
/// attributes are deliberately omitted — they are populated at runtime
/// in <method>%OnAfterCreatePage</method> to avoid compile-time MPP5646
/// <code>&lt;PROTECT&gt;</code> errors against the
/// <code>^%qMsg("%Ensemble",...)</code> catalog (see class doc-comment).
/// Tab navigation follows visible order.</p>
///
/// <p><b>Block name + root.</b> Per the
/// <CLASS>EnsPortal.Template.standardPage</CLASS> contract the form
/// layout lives in <code>XData contentPane</code> with a
/// <code>&lt;pane&gt;</code> root — the parent's chrome embeds this
/// pane inside its rendered title-bar / locator / ribbon / footer.
/// Sibling <CLASS>EnsPortal.Credentials</CLASS> uses the same pattern.</p>
XData contentPane [ XMLNamespace = "http://www.intersystems.com/zen" ]
{
<pane xmlns="http://www.intersystems.com/zen">
<vgroup cellStyle="padding:6px;">

<select id="agentSelect" valueList="session-inspection,message-search" value="session-inspection" onchange="zenPage.loadAgent();" />

<select id="providerSelect" valueList="openai,anthropic,gemini,openai-compatible" onchange="zenPage.onChangeProvider(zenThis.value);" />

<combobox id="modelCombo" editable="true" />

<text id="endpointUrlText" hidden="true" size="60" />

<radioSet id="credTypeRadio" valueList="env,creds" value="env" onchange="zenPage.credTypeChanged();" />

<text id="envVarText" size="40" />

<combobox id="credCombo" editable="true" hidden="true" />

<text id="maxTokensText" size="8" />

<text id="temperatureText" size="8" />

<text id="maxIterText" size="8" />

<text id="searchChatRetentionDays" size="8" hidden="true" />

<textarea id="systemPromptText" rows="6" cols="80" onchange="zenPage.spoChanged();" onkeyup="zenPage.spoChanged();" />

<label id="spoCharCounter" value="0 / 8192 characters" />

<checkbox id="enabledCheck" />

<label id="saveStatus" value="" />

<hgroup>
<button id="saveButton" onclick="zenPage.saveConfig();" />
<spacer width="6" />
<button id="cancelButton" onclick="zenPage.cancelEdit();" />
</hgroup>

</vgroup>
</pane>
}

/// <p>Inline CSS for the SystemPromptOverride char-counter color
/// thresholds. Defined in a Zen Style block so the rules ship with the
/// page (no separate stylesheet round-trip). The three classes
/// (<code>spoCounterNormal</code>, <code>spoCounterWarn</code>,
/// <code>spoCounterDanger</code>) are toggled by
/// <method>spoChanged</method>. Colors use named CSS values rather than
/// design-token CSS variables because Zen pages predate the Angular
/// token system; the EnsPortal-style precedent uses literal colors in
/// per-page Style blocks.</p>
XData Style
{
<style type="text/css">
.spoCounterNormal {
    color: #404040;
    font-size: 9pt;
}
.spoCounterWarn {
    color: #B07000;
    font-size: 9pt;
    font-weight: bold;
}
.spoCounterDanger {
    color: #C03030;
    font-size: 9pt;
    font-weight: bold;
}
.saveStatusInfo {
    color: #404040;
    font-style: italic;
    font-size: 9pt;
    padding-top: 4px;
}
</style>
}

/// <p>Page-name callback (parent contract — used by
/// <method>%GetLocatorLinks</method> to render the breadcrumb /
/// locator-bar entry for this page).</p>
Method %OnGetPageName() As %String
{
    Quit "Agent Configuration"
}

/// <p>Title callback (parent contract — used by the title-bar
/// rendering pipeline). Returning the same string as the page name keeps
/// the chrome consistent with sibling Mgmt-Portal config pages.</p>
Method %OnGetTitle() As %String
{
    Quit "Agent Configuration"
}

/// <p>Page-load callback. Sets the page title + every component's
/// label / caption / displayList at runtime (the XData declarations
/// omit these to avoid the compile-time MPP5646 / <code>&lt;PROTECT&gt;</code>
/// error — see class doc-comment). Pre-populates the
/// <CLASS>Ens.Config.Credentials</CLASS> combobox with available
/// credential entries so the suggestions render with the page.</p>
Method %OnAfterCreatePage() As %Status
{
    Set tSC = ##super()
    If $$$ISERR(tSC) Quit tSC

    ; Page title.
    Set ..title = "Agent Configuration"

    ; Per-component labels / captions / displayLists. The runtime
    ; setter path uses the inherited %ZEN.Component.* setters which
    ; do NOT trigger the catalog write that the compile-time path
    ; tripped over.
    Set tCmp = ..%GetComponentById("agentSelect")
    If $IsObject(tCmp) {
        Set tCmp.label = "Agent"
        Set tCmp.displayList = "Session Inspection,Message Search"
    }

    Set tCmp = ..%GetComponentById("providerSelect")
    If $IsObject(tCmp) {
        Set tCmp.label = "Provider"
        Set tCmp.displayList = "OpenAI,Anthropic,Google Gemini,OpenAI-Compatible (Ollama/vLLM)"
    }

    Set tCmp = ..%GetComponentById("modelCombo")
    If $IsObject(tCmp) {
        Set tCmp.label = "Model"
    }

    Set tCmp = ..%GetComponentById("endpointUrlText")
    If $IsObject(tCmp) {
        Set tCmp.label = "Endpoint URL (OpenAI-Compatible only)"
    }

    Set tCmp = ..%GetComponentById("credTypeRadio")
    If $IsObject(tCmp) {
        Set tCmp.label = "Credential Source"
        Set tCmp.displayList = "Environment Variable,Ens.Config.Credentials"
    }

    Set tCmp = ..%GetComponentById("envVarText")
    If $IsObject(tCmp) {
        Set tCmp.label = "Environment Variable Name"
    }

    Set tCmp = ..%GetComponentById("credCombo")
    If $IsObject(tCmp) {
        Set tCmp.label = "Ens.Config.Credentials Entry"
    }

    Set tCmp = ..%GetComponentById("maxTokensText")
    If $IsObject(tCmp) {
        Set tCmp.label = "Max Tokens"
    }

    Set tCmp = ..%GetComponentById("temperatureText")
    If $IsObject(tCmp) {
        Set tCmp.label = "Temperature"
    }

    ; Story 12.4 (BUG-06) AC-3 — operator-tuneable iteration cap.
    ; Label set at runtime per the same MPP5646 workaround the other
    ; components use. Hint text guides operators to the 1-100 range
    ; (matching SaveAgentConfig Rule 9 + Config.Agent property
    ; MAXVAL=100 / MINVAL=1).
    Set tCmp = ..%GetComponentById("maxIterText")
    If $IsObject(tCmp) {
        Set tCmp.label = "Max iterations per turn"
        Set tCmp.hint = "1-100 (default 10)"
    }

    ; Story 10.8 AC-2 — Search-Agent retentionDays field. Label set at
    ; runtime per the same MPP5646 workaround the other components use.
    ; Visibility (hidden when agent=session-inspection, visible when
    ; agent=message-search) is toggled in the loadAgent client handler;
    ; the XData declaration sets hidden="true" as the first-render
    ; default so the field doesn't flash visible during initial load
    ; before loadAgent settles the agentSelect value.
    Set tCmp = ..%GetComponentById("searchChatRetentionDays")
    If $IsObject(tCmp) {
        Set tCmp.label = "Search Chat Retention (days)"
    }

    Set tCmp = ..%GetComponentById("systemPromptText")
    If $IsObject(tCmp) {
        Set tCmp.label = "System Prompt Override (optional)"
    }

    Set tCmp = ..%GetComponentById("enabledCheck")
    If $IsObject(tCmp) {
        Set tCmp.caption = "Enable this agent"
    }

    Set tCmp = ..%GetComponentById("saveButton")
    If $IsObject(tCmp) {
        Set tCmp.caption = "Save"
    }

    Set tCmp = ..%GetComponentById("cancelButton")
    If $IsObject(tCmp) {
        Set tCmp.caption = "Cancel"
    }

    ; Populate the credentials combobox with available
    ; Ens.Config.Credentials entries. Server-side helper returns a
    ; comma-separated string per AC-5.
    Try {
        Set tCredList = ..GetCredentialsList()
        Set tCombo = ..%GetComponentById("credCombo")
        If $IsObject(tCombo) {
            ; Zen combobox suggestions populate from valueList /
            ; displayList — both set to the same string for an
            ; identifier-only combobox.
            Set tCombo.valueList = tCredList
            Set tCombo.displayList = tCredList
        }
    }
    Catch ex {
        ; Best-effort — if Ens_Config.Credentials lookup fails (e.g.,
        ; ENSLIB not mapped in this namespace), the combobox renders
        ; empty and the operator can still type a free-text entry.
    }

    Quit $$$OK
}

/// <p>Page-loaded client event — fires after the Zen runtime has rendered
/// every component. Triggers the initial agent-row load so the form
/// fields display the chosen agent's current values immediately
/// (rather than empty). The default agent is
/// <code>session-inspection</code> per AC-2's "agent selector defaults
/// to session-inspection" clause.</p>
///
/// <p>Also re-populates the <code>credCombo</code> dropdown options at
/// runtime (in addition to the server-side <code>valueList</code> set in
/// <method>%OnAfterCreatePage</method>). The server-side property
/// assignment alone produced an empty option list at first render in
/// the manual-test pass on 2026-05-06; the client-side re-population
/// closes that gap so the dropdown shows
/// <CLASS>Ens.Config.Credentials</CLASS> entries reliably.</p>
ClientMethod onloadHandler() [ Language = javascript ]
{
    if (this.invokeSuper) this.invokeSuper('onloadHandler', arguments);
    zenPage.populateCredCombo();
    zenPage.loadAgent();
}

/// <p>Re-populate the <code>credCombo</code> dropdown options at runtime.
/// The server-side <code>valueList</code> property assignment in
/// <method>%OnAfterCreatePage</method> serializes the value into the
/// rendered HTML, but Zen's combobox doesn't always materialize the
/// option list from the property after first render — operators saw an
/// empty dropdown despite the server returning four credentials in the
/// manual-test session 2026-05-06. This setter forces the combobox to
/// re-build its option list from the freshly-fetched server-side string.</p>
ClientMethod populateCredCombo() [ Language = javascript ]
{
    var combo = zen('credCombo');
    if (!combo) return;
    var list = zenPage.GetCredentialsList();
    combo.valueList = list || '';
    combo.displayList = list || '';
    if (typeof combo.refreshContents === 'function') {
        combo.refreshContents();
    }
}

/// <p>Server-side helper — query
/// <CLASS>Ens.Config.Credentials</CLASS> for available credential
/// entries and return them as a comma-separated string suitable for a
/// Zen combobox's <code>valueList</code> / <code>displayList</code>
/// attribute. Sorted alphabetically per
/// <code>ORDER BY %EXACT(ID)</code> (case-preserving per project
/// IRIS-SQL rule).</p>
///
/// <p>Returns an empty string when no credentials exist or the lookup
/// fails — the combobox renders an empty suggestion list, and the
/// operator can still type a free-text entry (combobox
/// <code>editable="true"</code>).</p>
///
/// <p><b>[ZenMethod]</b> — also callable from client-side JS via
/// <code>zenPage.GetCredentialsList()</code> so
/// <method>populateCredCombo</method> can refresh the dropdown after
/// the Zen runtime initializes the combobox.</p>
ClassMethod GetCredentialsList() As %String [ ZenMethod ]
{
    Set tList = ""
    Try {
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC = tStmt.%Prepare("SELECT %EXACT(ID) AS Cid FROM Ens_Config.Credentials ORDER BY %EXACT(ID)")
        If $$$ISERR(tSC) Quit
        Set tRS = tStmt.%Execute()
        If '$IsObject(tRS) Quit
        While tRS.%Next() {
            Set tCid = tRS.%Get("Cid")
            If tCid '= "" {
                Set tList = $Select(tList = "" : tCid, 1 : tList _ "," _ tCid)
            }
        }
        Do tRS.%Close()
    }
    Catch ex {
        ; Swallow — return whatever was accumulated. Empty string is
        ; the safe degradation (operator types free-text).
    }
    Quit tList
}

/// <p>ZenMethod hyperevent — invoked by the client-side
/// <method>loadAgent</method> with the chosen <var>pAgentName</var>.
/// Looks up the <CLASS>SessionAgent.Config.Agent</CLASS> row and returns
/// a JSON-serialized object with all form-field values. If no row exists,
/// returns an empty-defaults shape so the form still renders sensibly
/// (Provider="openai", MaxTokens=4000, Temperature=0.1, etc.).</p>
///
/// <p><b>Never-throw contract.</b> Any exception converts to a
/// structured error envelope <code>{"error":"...message..."}</code> so
/// the client can render a useful failure indication rather than seeing
/// a Zen TypeError.</p>
///
/// <p><b>Returned shape:</b></p>
/// <pre>
/// {
///   "Provider": "openai",
///   "Model": "gpt-4.1-mini",
///   "EndpointUrl": "",
///   "EnvVarName": "OPENAI_API_KEY",
///   "CredentialName": "",
///   "MaxTokens": 4000,
///   "Temperature": 0.1,
///   "SystemPromptOverride": "",
///   "Enabled": 0,
///   "found": 1
/// }
/// </pre>
ClassMethod LoadAgentConfig(pAgentName As %String) As %String [ ZenMethod ]
{
    Set tEnvelope = ""
    Try {
        Set tObj = ##class(%DynamicObject).%New()

        ; Default empty-defaults shape per AC-5 last clause. These get
        ; overwritten below if the row exists.
        Do tObj.%Set("Provider", "openai")
        Do tObj.%Set("Model", "")
        Do tObj.%Set("EndpointUrl", "")
        Do tObj.%Set("EnvVarName", "OPENAI_API_KEY")
        Do tObj.%Set("CredentialName", "")
        Do tObj.%Set("MaxTokens", 32000)
        Do tObj.%Set("Temperature", 0.1)
        Do tObj.%Set("SystemPromptOverride", "")
        Do tObj.%Set("Enabled", 0)
        ; Story 10.8 AC-2 — SearchChatRetentionDays default per Config.Agent
        ; InitialExpression = 30. Returned for both inspection and search
        ; rows; the client-side handler decides visibility.
        Do tObj.%Set("SearchChatRetentionDays", 30)
        ; Story 12.4 (BUG-06) AC-3 — MaxIterationsPerTurn default 10
        ; (matches Config.Agent.MaxIterationsPerTurn InitialExpression).
        ; Returned for both agents so the form populates consistently.
        Do tObj.%Set("MaxIterationsPerTurn", 10)
        Do tObj.%Set("found", 0)

        If pAgentName '= "" {
            Set tCfg = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(pAgentName)
            If $IsObject(tCfg) {
                ; $Char(0) → "" normalization at every %String read site per
                ; .claude/rules/iris-objectscript-basics.md §"$Char(0) sentinel".
                ; Story 6.2's Save handler will issue SQL UPDATE statements
                ; that store "" as the in-table $Char(0) sentinel; without
                ; normalization the JSON envelope ships a literal NUL byte
                ; that JS treats as truthy ('' is truthy in JS), so
                ; `data.Provider || 'openai'` defaulting fails and the form
                ; renders a NUL control char in the input. Predicted-bug
                ; per Rule 8 — fix-now even though the bug doesn't fire
                ; today because no SQL UPDATE has yet executed against
                ; these rows.
                Set tProvider = tCfg.Provider
                If tProvider = $Char(0) Set tProvider = ""
                Set tModel = tCfg.Model
                If tModel = $Char(0) Set tModel = ""
                Set tEndpointUrl = tCfg.EndpointUrl
                If tEndpointUrl = $Char(0) Set tEndpointUrl = ""
                Set tEnvVarName = tCfg.EnvVarName
                If tEnvVarName = $Char(0) Set tEnvVarName = ""
                Set tCredentialName = tCfg.CredentialName
                If tCredentialName = $Char(0) Set tCredentialName = ""
                Set tSpo = tCfg.SystemPromptOverride
                If tSpo = $Char(0) Set tSpo = ""

                Do tObj.%Set("Provider", tProvider)
                Do tObj.%Set("Model", tModel)
                Do tObj.%Set("EndpointUrl", tEndpointUrl)
                Do tObj.%Set("EnvVarName", tEnvVarName)
                Do tObj.%Set("CredentialName", tCredentialName)
                Do tObj.%Set("MaxTokens", tCfg.MaxTokens)
                Do tObj.%Set("Temperature", tCfg.Temperature)
                Do tObj.%Set("SystemPromptOverride", tSpo)
                Do tObj.%Set("Enabled", tCfg.Enabled)
                ; Story 10.8 AC-2 — SearchChatRetentionDays read.
                ; %Integer column; no $Char(0) normalization needed (the
                ; sentinel only manifests for %String reads per
                ; .claude/rules/iris-objectscript-basics.md §"$Char(0)
                ; sentinel" — numeric columns store NULL as "" via the
                ; storage layer and the OREF-getter coerces to 0). If
                ; the value is missing or 0, fall back to the canonical
                ; default of 30 (matches Config.Agent.SearchChatRetentionDays
                ; InitialExpression) so an empty row doesn't surface a
                ; useless 0-day retention value.
                Set tRetentionDays = +tCfg.SearchChatRetentionDays
                If tRetentionDays '> 0 Set tRetentionDays = 30
                Do tObj.%Set("SearchChatRetentionDays", tRetentionDays)
                ; Story 12.4 (BUG-06) AC-3 — read MaxIterationsPerTurn
                ; with the same defensive fallback the AgentLoop uses
                ; on the runtime read site. The OREF getter returns ""
                ; for legacy rows whose column was added by post-12.4
                ; schema upgrade and never written; the SQL UPDATE
                ; write path can also clear via $Char(0) sentinel
                ; (defensive). Below 1 → fall back to canonical 10.
                Set tMaxIter = tCfg.MaxIterationsPerTurn
                If (tMaxIter = $Char(0)) || (tMaxIter = "") || (+tMaxIter < 1) {
                    Set tMaxIter = 10
                }
                Do tObj.%Set("MaxIterationsPerTurn", +tMaxIter)
                Do tObj.%Set("found", 1)
                Do tCfg.%Close()
            }
        }

        Set tEnvelope = tObj.%ToJSON()
    }
    Catch ex {
        Set tErr = ##class(%DynamicObject).%New()
        Do tErr.%Set("error", "LoadAgentConfig: " _ ex.DisplayString())
        Set tEnvelope = tErr.%ToJSON()
    }
    Quit tEnvelope
}

/// <p>Client-side handler — fired on initial page load and on every
/// agent-selector change. Calls <method>LoadAgentConfig</method> for the
/// selected agent, parses the returned JSON, and assigns each value into
/// the corresponding form field. After populating, fires
/// <method>providerChanged</method> + <method>credTypeChanged</method>
/// + <method>spoChanged</method> so the model-suggestion list,
/// endpoint-URL visibility, env/cred field visibility, and char counter
/// all reflect the loaded values without a separate handler call from
/// the operator.</p>
ClientMethod loadAgent() [ Language = javascript ]
{
    var agentName = zen('agentSelect').getValue();
    var json = zenPage.LoadAgentConfig(agentName);
    var data;
    try {
        data = JSON.parse(json);
    } catch (e) {
        data = { error: 'parse failure' };
    }
    if (data.error) {
        // Surface the error in the saveStatus label so the operator
        // sees something useful. The form fields stay at their last
        // values (or empty on initial load).
        zen('saveStatus').setValue('Load failed: ' + data.error);
        return;
    }

    // Populate fields. setValue() updates both the underlying value and
    // the rendered control. Coerce undefined/null to empty string so
    // we never feed "undefined" into a text input.
    zen('providerSelect').setValue(data.Provider || 'openai');
    zen('modelCombo').setValue(data.Model || '');
    zen('endpointUrlText').setValue(data.EndpointUrl || '');
    zen('envVarText').setValue(data.EnvVarName || '');
    zen('credCombo').setValue(data.CredentialName || '');
    zen('maxTokensText').setValue(data.MaxTokens || 32000);

    // Story 11.1 — capture the loaded Provider so the rotation cascade
    // (onChangeProvider) can compute the OLD provider's canonical
    // MaxTokens default and apply the preserve-when-customized
    // heuristic. Without this initialization the first rotation has
    // no notion of "what was the old provider" and falls back to the
    // legacy stomp-the-MaxTokens behavior.
    zenPage._loadedProvider = data.Provider || 'openai';
    zenPage._previousProvider = zenPage._loadedProvider;
    zen('temperatureText').setValue(data.Temperature || 0.1);
    zen('systemPromptText').setValue(data.SystemPromptOverride || '');
    zen('enabledCheck').setValue(data.Enabled ? 1 : 0);

    // Story 12.4 (BUG-06) AC-3/AC-4 — populate MaxIterationsPerTurn
    // from the server. Default fallback to 10 (matches the
    // Config.Agent.MaxIterationsPerTurn InitialExpression) on a
    // missing / 0 / empty value. Capture the loaded value on the
    // page object so the onChangeProvider cascade can apply the
    // preserve-when-customized heuristic on subsequent rotations.
    var maxIterField = zen('maxIterText');
    if (maxIterField) {
        var loadedMaxIter = +data.MaxIterationsPerTurn || 10;
        maxIterField.setValue(loadedMaxIter);
    }

    // Story 10.8 AC-2 — SearchChatRetentionDays is Search-Agent specific.
    // Populate the value (default 30 to match Config.Agent
    // InitialExpression) and toggle the field's visibility based on the
    // selected agent. The field is HIDDEN when agent=session-inspection
    // (the inspection agent's chat history is bound to the IRIS
    // Production session lifecycle per Story 7 — retentionDays is
    // ignored for that path) and VISIBLE when agent=message-search (the
    // Story 10.6 PurgeStaleSearchChat sweep reads the column).
    var retentionField = zen('searchChatRetentionDays');
    if (retentionField) {
        retentionField.setValue(data.SearchChatRetentionDays || 30);
        retentionField.setHidden(agentName !== 'message-search');
    }

    // Decide credTypeRadio state from which field has a non-empty
    // value. If both are empty, default to 'env' (the OD4 default
    // shape). If both are populated (rare — operator-side edit), prefer
    // 'creds' since CredentialName is the more sophisticated path.
    var hasCred = (data.CredentialName && data.CredentialName !== '');
    if (hasCred) {
        zen('credTypeRadio').setValue('creds');
    } else {
        zen('credTypeRadio').setValue('env');
    }

    // Fire the change handlers so visibility + suggestions reflect
    // the loaded state.
    zenPage.providerChanged();
    zenPage.credTypeChanged();
    zenPage.spoChanged();

    // Story 11.1 (review fix-now) — providerChanged() above runs the
    // same stale-canonical guard set as the rotation cascade and will
    // stomp an operator-saved MaxTokens=4000 (or 4096 against a
    // hyperscaler row) to the loaded provider's NEW canonical default
    // on every form-load. Same operator-observable bug shape Story 11.1
    // was created to fix, different trigger. Apply the
    // preserve-when-customized heuristic mirroring onChangeProvider:
    // if the loaded MaxTokens (data.MaxTokens) differs from the
    // loaded provider's canonical default, the operator had customized
    // the value — restore it over whatever providerChanged() wrote.
    var loadedMaxTokens = String(data.MaxTokens || '');
    var loadedCanonicalMax = zenPage.getCanonicalMaxTokens(zenPage._loadedProvider);
    if (loadedMaxTokens !== '' && loadedCanonicalMax !== ''
        && loadedMaxTokens !== loadedCanonicalMax) {
        // Operator-customized — restore over providerChanged()'s stomp.
        var maxTokensFieldOnLoad = zen('maxTokensText');
        if (maxTokensFieldOnLoad) {
            maxTokensFieldOnLoad.setValue(loadedMaxTokens);
        }
    }

    // Clear any stale save-status message from a prior interaction.
    zen('saveStatus').setValue('');
}

/// <p><b>Story 10.11.</b> Server-side helper — returns the per-provider
/// canonical default triple (Model, CredentialName, EnvVarName, EndpointUrl)
/// as a JSON envelope. Delegates to
/// <method>SessionAgent.Config.AgentDefaults.GetCanonicalDefaults</method>
/// so the canonical mapping lives in one place (the same class
/// <method>GetSeedConfig</method> reads from at install time).</p>
///
/// <p>Returned shape:</p>
/// <pre>
/// {"model":"...","credentialName":"...","envVarName":"...","endpointUrl":"..."}
/// </pre>
///
/// <p><b>Never-throw contract.</b> Any exception converts to
/// <code>{"error":"..."}</code> so the client can degrade gracefully —
/// the form just leaves the existing field values in place if the
/// helper fails.</p>
ClassMethod LoadProviderDefaults(pProvider As %String) As %String [ ZenMethod ]
{
    Set tEnvelope = ""
    Try {
        Set tObj = ##class(SessionAgent.Config.AgentDefaults).GetCanonicalDefaults(pProvider)
        Set tEnvelope = tObj.%ToJSON()
    }
    Catch ex {
        Set tErr = ##class(%DynamicObject).%New()
        Do tErr.%Set("error", "LoadProviderDefaults: " _ ex.DisplayString())
        Set tEnvelope = tErr.%ToJSON()
    }
    Quit tEnvelope
}

/// <p><b>Story 10.11.</b> Provider-rotation cascade — fired when the
/// operator changes the Provider selector. Without this cascade the form
/// persists an incoherent (Provider, Model, CredentialName, EnvVarName)
/// triple on Save: the operator picks Provider=anthropic but Model +
/// CredentialName + EnvVarName remain at the prior provider's values
/// (e.g., gpt-4.1-mini + SessionAgentOpenAI + OPENAI_API_KEY) because
/// the form's <method>providerChanged</method> handler only updates the
/// model dropdown's <i>suggestion list</i>, not the actual field values.</p>
///
/// <p>This handler:</p>
/// <ol>
/// <li>Invokes <method>LoadProviderDefaults</method> for the new
/// provider — returns the canonical triple as JSON.</li>
/// <li>Sets <code>modelCombo</code> + <code>credCombo</code> +
/// <code>envVarText</code> + <code>endpointUrlText</code> field values
/// from the canonical triple.</li>
/// <li>Flips <code>credTypeRadio</code> to <code>creds</code> when the
/// canonical credential is non-empty (the standard hyperscaler shape —
/// operators typically use <CLASS>Ens.Config.Credentials</CLASS> entries
/// for OpenAI / Anthropic / Gemini), or to <code>env</code> when the
/// canonical credential is empty (openai-compatible / Ollama path,
/// where there's no canonical credential and the operator typically
/// uses an env-var or no credential at all).</li>
/// <li>Calls the existing <method>providerChanged</method> handler so
/// the model-suggestion dropdown contents + endpoint-URL visibility +
/// other downstream UI state still update consistently. Note that
/// <method>providerChanged</method>'s own EnvVarName / MaxTokens
/// auto-suggest paths still run and may further adjust those fields'
/// values — but only if the cascaded value sits inside their stale-
/// canonical guard set, which the canonical defaults above do.</li>
/// <li>Calls <method>credTypeChanged</method> to apply visibility
/// changes from the radio-flip in step 3.</li>
/// </ol>
///
/// <p>Operator's typed custom values (e.g., a per-tenant model name like
/// "gpt-4.1-fine-tune-acme") ARE overwritten on provider rotation —
/// rotating Provider semantically means "switch to that provider's
/// canonical setup" and the operator can re-type the custom value after
/// the cascade if they want. This matches operator muscle memory from
/// other Mgmt Portal config forms (e.g., <CLASS>EnsPortal.Credentials</CLASS>
/// re-populates fields when the dropdown selection changes).</p>
ClientMethod onChangeProvider(value) [ Language = javascript ]
{
    // Story 11.1 — capture pre-cascade MaxTokens + the OLD provider
    // BEFORE any cascade fires. The preserve-when-customized heuristic
    // (AC-2) needs both:
    //   - the OLD provider's canonical MaxTokens default
    //   - the operator's pre-cascade MaxTokens value (which providerChanged
    //     would otherwise stomp via its stale-canonical guard set)
    // After the existing cascades run, we apply the heuristic: if the
    // pre-cascade value DIFFERS from the OLD canonical default, the
    // operator has customized — restore the pre-cascade value over
    // whatever the cascade wrote. If the pre-cascade value EQUALS the
    // OLD canonical default, leave the cascade-applied NEW canonical
    // default in place (fresh-state semantic).
    var oldProvider = zenPage._previousProvider || zenPage._loadedProvider || 'openai';
    var oldCanonicalMax = zenPage.getCanonicalMaxTokens(oldProvider);
    var maxTokensField = zen('maxTokensText');
    var preCascadeMaxTokens = '';
    if (maxTokensField) {
        preCascadeMaxTokens = String(maxTokensField.getValue() || '');
    }

    // Story 12.4 (BUG-06) AC-4 — capture pre-cascade MaxIterationsPerTurn.
    // Mirrors the MaxTokens preserve-when-customized capture above. The
    // OLD canonical value is 10 for every provider (the same canonical
    // default ships across openai/anthropic/gemini/openai-compatible),
    // so the heuristic only needs to detect "operator typed something
    // OTHER than 10" to trigger preservation across rotations.
    var oldCanonicalMaxIter = '10';
    var maxIterFieldOnRotate = zen('maxIterText');
    var preCascadeMaxIter = '';
    if (maxIterFieldOnRotate) {
        preCascadeMaxIter = String(maxIterFieldOnRotate.getValue() || '');
    }

    var json = zenPage.LoadProviderDefaults(value);
    var data;
    try {
        data = JSON.parse(json);
    } catch (e) {
        data = { error: 'parse failure' };
    }
    if (data && !data.error) {
        // Cascade canonical defaults into dependent fields.
        var modelCombo = zen('modelCombo');
        if (modelCombo) modelCombo.setValue(data.model || '');
        var credCombo = zen('credCombo');
        if (credCombo) credCombo.setValue(data.credentialName || '');
        var envVar = zen('envVarText');
        if (envVar) envVar.setValue(data.envVarName || '');
        var endpoint = zen('endpointUrlText');
        if (endpoint) endpoint.setValue(data.endpointUrl || '');

        // Flip the credential-source radio to match the canonical shape.
        // Hyperscalers (openai/anthropic/gemini) ship with a canonical
        // Ens.Config.Credentials entry → 'creds'. openai-compatible has
        // no canonical credential → 'env' (operator typically uses
        // OLLAMA_API_KEY or leaves it empty for unauth Ollama).
        var credRadio = zen('credTypeRadio');
        if (credRadio) {
            credRadio.setValue((data.credentialName && data.credentialName !== '') ? 'creds' : 'env');
        }
    }

    // Always run the existing providerChanged path so the model
    // suggestion list + endpoint-URL visibility + downstream UI updates
    // still happen even on a LoadProviderDefaults parse failure.
    zenPage.providerChanged();
    // And re-apply credential-source visibility now that the radio may
    // have flipped above.
    zenPage.credTypeChanged();

    // Story 11.1 — preserve-when-customized heuristic for MaxTokens.
    // providerChanged() above may have updated maxTokensText to the
    // NEW provider's canonical default (its stale-canonical guard set
    // includes 4000/4096/32000, so a 4000 value rotating to a
    // hyperscaler gets stomped to 32000). Apply the AC-2 heuristic:
    // if the operator's pre-cascade value differs from the OLD
    // provider's canonical default (and was non-empty), they had
    // customized it — restore. Otherwise leave the cascade-applied
    // NEW canonical default. Empty pre-cascade values are treated
    // as "fresh state" — let the cascade apply the new default.
    if (maxTokensField && preCascadeMaxTokens !== '' && oldCanonicalMax !== '') {
        if (preCascadeMaxTokens !== String(oldCanonicalMax)) {
            // Operator-customized — restore the pre-cascade value.
            maxTokensField.setValue(preCascadeMaxTokens);
        }
        // else: pre-cascade value == OLD canonical → fresh state,
        // leave the NEW canonical default that providerChanged()
        // applied.
    }

    // Story 12.4 (BUG-06) AC-4 — MaxIterationsPerTurn cascade with
    // preserve-when-customized. The canonical default is 10 for
    // every provider, so on a fresh-state rotation we cascade to 10;
    // on a customized rotation (operator had typed e.g. 25) we
    // preserve. The heuristic mirrors MaxTokens above:
    //   - empty pre-cascade → fresh state, apply canonical 10.
    //   - pre-cascade == OLD canonical (10) → fresh state, apply 10.
    //   - pre-cascade != OLD canonical → operator-customized, preserve.
    if (maxIterFieldOnRotate) {
        if (preCascadeMaxIter === '' || preCascadeMaxIter === oldCanonicalMaxIter) {
            // Fresh state — apply NEW canonical (currently 10 for all
            // providers; if a future story makes it provider-specific,
            // the cascaded value flows from data.maxIterationsPerTurn
            // returned by LoadProviderDefaults).
            var cascadedMaxIter = (data && !data.error && data.maxIterationsPerTurn) ? data.maxIterationsPerTurn : 10;
            maxIterFieldOnRotate.setValue(cascadedMaxIter);
        }
        // else: pre-cascade value is operator-customized — leave it
        // untouched (no value to set; the field already carries the
        // operator's typed value).
    }

    // Story 10.13 F-3 (defense-in-depth) — when rotating to openai-
    // compatible, EXPLICITLY ensure endpointUrlText is unhidden. The
    // upstream providerChanged() handler already toggles visibility via
    // setHidden(provider !== 'openai-compatible'), but the rotation-cascade
    // path is the operator's first-encounter surface and an empirical
    // bug here ships as a release-blocker (operator can't see the field
    // they need to fill). The explicit setHidden(false) below is
    // idempotent with providerChanged() and serves as a regression guard
    // if a future edit to providerChanged() breaks the visibility branch.
    if (value === 'openai-compatible') {
        var endpointForceUnhide = zen('endpointUrlText');
        if (endpointForceUnhide) {
            endpointForceUnhide.setHidden(false);
        }
    }

    // Story 11.1 — update _previousProvider for the NEXT rotation so
    // the heuristic computes against the correct OLD canonical on
    // subsequent rotations.
    zenPage._previousProvider = value;
}

/// <p><b>Story 11.1.</b> Returns the canonical default MaxTokens value
/// for a given provider. Mirrors the per-provider switch in
/// <method>providerChanged</method> exactly so the preserve-when-customized
/// heuristic in <method>onChangeProvider</method> agrees with the
/// stale-canonical guard that providerChanged uses internally.</p>
///
/// <p>If a future story adds a provider, the new arm must be added to
/// BOTH <method>providerChanged</method>'s switch AND this helper —
/// otherwise the rotation cascade and the preservation heuristic will
/// disagree on what counts as "the old canonical".</p>
ClientMethod getCanonicalMaxTokens(provider) [ Language = javascript ]
{
    switch (provider) {
        case 'openai':            return '32000';
        case 'anthropic':         return '32000';
        case 'gemini':            return '32000';
        case 'openai-compatible': return '4096';
        default:                  return '';
    }
}

/// <p>Client-side handler — fired on provider-selector change. Updates
/// the model combobox's suggestion list per AC-4's table:</p>
/// <ul>
/// <li>openai → gpt-4.1-mini, gpt-4.1-nano, gpt-5-mini</li>
/// <li>anthropic → claude-sonnet-4-5, claude-opus-4-7</li>
/// <li>gemini → gemini-2.5-pro, gemini-3-pro</li>
/// <li>openai-compatible → qwen2.5:32b, llama3.3:70b</li>
/// </ul>
/// <p>Also toggles the endpoint-URL field's visibility — visible only
/// when provider is <code>openai-compatible</code>. Other providers'
/// concrete adapters know their canonical endpoints; the operator
/// supplies a custom endpoint only for the open-ended case.</p>
ClientMethod providerChanged() [ Language = javascript ]
{
    var provider = zen('providerSelect').getValue();
    var modelCombo = zen('modelCombo');
    var suggestions;

    switch (provider) {
        case 'openai':
            suggestions = 'gpt-4.1-mini,gpt-4.1-nano,gpt-5-mini';
            break;
        case 'anthropic':
            suggestions = 'claude-sonnet-4-5,claude-opus-4-7';
            break;
        case 'gemini':
            suggestions = 'gemini-2.5-pro,gemini-3-pro';
            break;
        case 'openai-compatible':
            suggestions = 'qwen2.5:32b,llama3.3:70b';
            break;
        default:
            suggestions = '';
    }

    // Update the combobox suggestions. Zen combobox lookups via
    // valueList / displayList — same string for an identifier-only
    // combobox.
    modelCombo.valueList = suggestions;
    modelCombo.displayList = suggestions;
    // Force the dropdown options to re-render. Zen recomputes the
    // <option> children when refreshContents is called on the
    // enclosing component.
    if (typeof modelCombo.refreshContents === 'function') {
        modelCombo.refreshContents();
    }

    // Endpoint-URL visibility — visible iff provider === openai-compatible.
    zen('endpointUrlText').setHidden(provider !== 'openai-compatible');

    // Provider-aware EnvVarName auto-suggest. The 2026-05-06 manual-test
    // pass surfaced operator-state drift: a session-inspection row with
    // Provider=openai but EnvVarName=PATH (left over from a Story 5.3
    // Ollama-no-auth probe) produced a 401 because $ENV(PATH) — a
    // Windows path string — was used as a Bearer token. Nudge the
    // operator toward the canonical env var when they switch providers,
    // BUT only if the current value is empty or one of the known stale
    // canonical defaults (so we never overwrite an operator's deliberate
    // custom value like a per-tenant env-var name). For openai-compatible
    // (Ollama / vLLM / etc.), there is no canonical default — leave the
    // field as-is so the operator's chosen value is preserved.
    var envVar = zen('envVarText');
    if (envVar) {
        var current = envVar.getValue() || '';
        // Story 10.13 F-3: OLLAMA_API_KEY added to the stale-canonical guard
        // set so a rotation FROM openai-compatible TO a hyperscaler correctly
        // upgrades the env-var name. Without this the operator who picked
        // openai-compatible (which now seeds OLLAMA_API_KEY per the cascade)
        // and then rotates to openai would keep OLLAMA_API_KEY — predicted
        // bug per Rule 8.
        var canonicalDefaults = ['', 'PATH', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'OLLAMA_API_KEY'];
        var isStaleCanonical = (canonicalDefaults.indexOf(current) >= 0);
        if (isStaleCanonical) {
            var newDefault = '';
            switch (provider) {
                case 'openai':            newDefault = 'OPENAI_API_KEY';    break;
                case 'anthropic':         newDefault = 'ANTHROPIC_API_KEY'; break;
                case 'gemini':            newDefault = 'GEMINI_API_KEY';    break;
                case 'openai-compatible': newDefault = 'OLLAMA_API_KEY';    break;
            }
            if (newDefault !== current) {
                envVar.setValue(newDefault);
            }
        }
    }

    // Provider-aware MaxTokens auto-suggest. The 2026-05-06 manual-test
    // pass surfaced that the legacy 4096 default (a holdover from
    // Ollama-class limits) is far too small for hyperscalers — gpt-4.1,
    // claude-sonnet-4-5, and gemini-2.5-pro routinely emit 16k+ tokens
    // for tool-call-heavy multi-turn answers, and 4096 silently truncates
    // mid-response. Bump to 32000 for hyperscalers (matches the AC-1
    // validation cap exactly) and keep 4096 for openai-compatible
    // (Ollama / vLLM are typically deployed on smaller models with
    // tighter output budgets). Same stale-canonical guard pattern as
    // EnvVarName above — operator-typed custom values (e.g., 8192,
    // 16384) survive a provider switch.
    var maxTokensField = zen('maxTokensText');
    if (maxTokensField) {
        var currentMax = String(maxTokensField.getValue() || '');
        var canonicalMaxDefaults = ['', '4000', '4096', '32000'];
        var isStaleMaxCanonical = (canonicalMaxDefaults.indexOf(currentMax) >= 0);
        if (isStaleMaxCanonical) {
            var newMaxDefault = '';
            switch (provider) {
                case 'openai':            newMaxDefault = '32000'; break;
                case 'anthropic':         newMaxDefault = '32000'; break;
                case 'gemini':            newMaxDefault = '32000'; break;
                case 'openai-compatible': newMaxDefault = '4096';  break;
            }
            if (newMaxDefault !== '' && newMaxDefault !== currentMax) {
                maxTokensField.setValue(newMaxDefault);
            }
        }
    }
}

/// <p>Client-side handler — fired on credential-type radio change.
/// Toggles which credential-source field is visible:</p>
/// <ul>
/// <li>credTypeRadio = "env" → envVarText visible, credCombo hidden</li>
/// <li>credTypeRadio = "creds" → envVarText hidden, credCombo visible</li>
/// </ul>
ClientMethod credTypeChanged() [ Language = javascript ]
{
    var credType = zen('credTypeRadio').getValue();
    if (credType === 'creds') {
        zen('envVarText').setHidden(true);
        zen('credCombo').setHidden(false);
    } else {
        zen('envVarText').setHidden(false);
        zen('credCombo').setHidden(true);
    }
}

/// <p>Client-side handler — fired on every keystroke and change in the
/// systemPromptText textarea (AC-3 binding from Story 6.0 AC-2 / Item G).
/// Updates the live char counter and applies a CSS-class threshold:</p>
/// <ul>
/// <li>length &lt;= 7500 → spoCounterNormal (gray)</li>
/// <li>length &gt; 7500 and &lt; 8192 → spoCounterWarn (amber) +
/// "approaching cap" suffix</li>
/// <li>length === 8192 exactly → "at cap (may have been silently
/// truncated previously)" suffix — the AC-3 prior-truncation marker</li>
/// <li>length &gt; 8192 → spoCounterDanger (red) + "exceeds cap; will
/// truncate on save" suffix</li>
/// </ul>
/// <p>The actual block-or-truncate-with-confirm logic on save lives in
/// Story 6.2; Story 6.1 only renders the warning text.</p>
ClientMethod spoChanged() [ Language = javascript ]
{
    var text = zen('systemPromptText').getValue() || '';
    var len = text.length;
    var counter = zen('spoCharCounter');
    if (!counter) return;

    var label;
    var cssClass;
    if (len > 8192) {
        label = len + ' / 8192 characters — exceeds cap; will truncate on save';
        cssClass = 'spoCounterDanger';
    } else if (len === 8192) {
        label = '8192 / 8192 characters — at cap (may have been silently truncated previously)';
        cssClass = 'spoCounterDanger';
    } else if (len > 7500) {
        label = len + ' / 8192 characters — approaching cap';
        cssClass = 'spoCounterWarn';
    } else {
        label = len + ' / 8192 characters';
        cssClass = 'spoCounterNormal';
    }

    counter.setValue(label);
    // Apply the CSS class to the rendered control. Zen labels expose a
    // controlClass attribute which becomes the rendered span's class.
    counter.setProperty('controlClass', cssClass);
    if (typeof counter.refreshContents === 'function') {
        counter.refreshContents();
    }
}

/// <p>Story 6.2 — server-side Save handler. Validates the 11 form-field
/// inputs against the 8 validation rules in AC-1, persists the row via
/// open-or-create on the unique <code>AgentNameIdx</code>, applies the
/// radio-aware credential clearing rule (NFR-S2 schema discipline —
/// EnvVarName XOR CredentialName, never both), and returns a structured
/// JSON envelope.</p>
///
/// <p><b>Validation accumulation.</b> Every rule failure appends to
/// <code>errors[]</code>; the operator sees ALL failures in a single
/// round-trip rather than fix-one-at-a-time. The order of rules in the
/// AC table is preserved so the UI can render errors in field-natural
/// order.</p>
///
/// <p><b>NFR-S2 invariant.</b> The signature has NO <code>pApiKey</code>
/// parameter; the underlying <CLASS>SessionAgent.Config.Agent</CLASS>
/// class has no <code>ApiKey</code> property (Story 2.4
/// <code>TestSchemaHasNoApiKey</code> enforces this). Credential refs
/// only — <code>EnvVarName</code> for the env-var rung and
/// <code>CredentialName</code> for the <code>Ens.Config.Credentials</code>
/// rung. The radio choice (<var>pCredTypeRadio</var>) selects which
/// field is set; the OTHER is always cleared to "" so the EnvSecret
/// resolver's three-rung ladder behaves deterministically.</p>
///
/// <p><b>Hot-config-change (NFR-O2) — implementation-side.</b> This
/// method only writes the row; the read-side invariant (AgentLoop
/// re-reads <code>Config.Agent</code> via <code>AgentNameIdxOpen</code>
/// on every <method>RunTurn</method> invocation per
/// <CLASS>SessionAgent.Agent.AgentLoop</CLASS> line 152) means a saved
/// row affects the very next turn — no IRIS restart required. The
/// integration test
/// <method>SessionAgent.Test.AgentConfigTest.TestHotConfigChangeAcrossRunTurnInvocations</method>
/// is the empirical proof of the contract.</p>
///
/// <p><b>Returned shape on success:</b>
/// <code>{"success":true,"message":"Saved"}</code></p>
/// <p><b>Returned shape on failure:</b>
/// <code>{"success":false,"errors":[{"field":"&lt;id&gt;","message":"&lt;text&gt;"}, ...]}</code></p>
ClassMethod SaveAgentConfig(pAgentName As %String, pProvider As %String, pModel As %String, pEndpointUrl As %String, pCredTypeRadio As %String, pEnvVarName As %String, pCredentialName As %String, pMaxTokens As %String, pTemperature As %String, pSystemPrompt As %String, pEnabled As %String, pSearchChatRetentionDays As %String = "", pMaxIterationsPerTurn As %String = "") As %String [ ZenMethod ]
{
    Set tEnvelope = ""
    Try {
        Set tErrors = ##class(%DynamicArray).%New()

        ; ─────────────────────────────────────────────────────────────
        ; Rule 1 — pAgentName must be one of the known agents.
        ; ─────────────────────────────────────────────────────────────
        If (pAgentName '= "session-inspection") && (pAgentName '= "message-search") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "agentSelect")
            Do tErr.%Set("message", "Unknown agent")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 2 — pProvider must be one of the supported providers.
        ; ─────────────────────────────────────────────────────────────
        If (pProvider '= "openai") && (pProvider '= "anthropic") && (pProvider '= "gemini") && (pProvider '= "openai-compatible") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "providerSelect")
            Do tErr.%Set("message", "Unknown provider")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 3 — pMaxTokens must be a positive integer ≤ 32000.
        ; ─────────────────────────────────────────────────────────────
        Set tMaxTokensNum = +pMaxTokens
        If (tMaxTokensNum '> 0) || (tMaxTokensNum > 32000) || ('$Match(pMaxTokens, "^[0-9]+$")) {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "maxTokensText")
            Do tErr.%Set("message", "Max tokens must be 1–32000")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 4 — pTemperature must be in [0, 2].
        ; ─────────────────────────────────────────────────────────────
        ; Accept canonical numeric forms: "0", "0.1", ".1", "-0.5", "1",
        ; "1.5". The regex permits an optional leading minus, an optional
        ; integer part, an optional dot, and an optional fractional part —
        ; but at least one digit must be present overall. IRIS stringifies
        ; stored %Numeric values as ".1" (no leading zero), so the leading
        ; integer part must be optional.
        Set tTempNum = +pTemperature
        If (tTempNum < 0) || (tTempNum > 2) || ('$Match(pTemperature, "^-?(([0-9]+)(\.[0-9]+)?|(\.[0-9]+))$")) {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "temperatureText")
            Do tErr.%Set("message", "Temperature must be 0–2")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 4b — pCredTypeRadio domain guard. The persistence branch
        ; below (env vs creds) treats anything that isn't "env" as
        ; "creds", which silently corrupts the row when an unexpected
        ; value is supplied (e.g., a malformed JS post that sends an
        ; empty string or a typo'd radio value). Reject early so the
        ; persistence Else branch invariant — "the OPPOSITE field is
        ; cleared" — only fires for the two valid radio choices.
        ; (Predicted-bug fix-now per Rule 8 — caught by reviewer's
        ; manual probe with pCredTypeRadio="banana"; without this
        ; guard, EnvVarName was cleared and CredentialName was set to
        ; the supplied value with no operator-visible feedback.)
        ; ─────────────────────────────────────────────────────────────
        If (pCredTypeRadio '= "env") && (pCredTypeRadio '= "creds") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "credTypeRadio")
            Do tErr.%Set("message", "Credential type must be 'env' or 'creds'")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 5 — credTypeRadio="env" requires non-empty EnvVarName.
        ; ─────────────────────────────────────────────────────────────
        If (pCredTypeRadio = "env") && (pEnvVarName = "") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "envVarText")
            Do tErr.%Set("message", "Environment variable name required")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 6 — credTypeRadio="creds" requires non-empty CredentialName.
        ; ─────────────────────────────────────────────────────────────
        If (pCredTypeRadio = "creds") && (pCredentialName = "") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "credCombo")
            Do tErr.%Set("message", "Credential name required")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 7 — provider="openai-compatible" requires EndpointUrl.
        ; ─────────────────────────────────────────────────────────────
        If (pProvider = "openai-compatible") && (pEndpointUrl = "") {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "endpointUrlText")
            Do tErr.%Set("message", "Endpoint URL required for OpenAI-Compatible")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Rule 8 — system prompt length cap (Item G binding from
        ; Story 6.0 / 6.1 — soft-validate at form, hard-block at save).
        ; ─────────────────────────────────────────────────────────────
        If $Length(pSystemPrompt) > 8192 {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "systemPromptText")
            Do tErr.%Set("message", "System prompt exceeds 8192 chars; please trim")
            Do tErrors.%Push(tErr)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Story 10.8 AC-2 — SearchChatRetentionDays validation. Only
        ; enforced for the message-search agent (the inspection agent
        ; ignores the column — see Config.Agent.SearchChatRetentionDays
        ; doc-comment). Empty string and 0 are accepted as "use default";
        ; the persistence branch below substitutes 30 in those cases.
        ; Positive integers >= 1 are accepted; anything else (negative,
        ; non-numeric, > 365) is rejected so an operator typo doesn't
        ; silently set a 0-day retention (purge-everything-immediately)
        ; or a 5000-day retention (effectively never purge).
        ; ─────────────────────────────────────────────────────────────
        Set tRetentionDaysNum = +pSearchChatRetentionDays
        If (pAgentName = "message-search") && (pSearchChatRetentionDays '= "") && (pSearchChatRetentionDays '= "0") {
            If (tRetentionDaysNum < 1) || (tRetentionDaysNum > 365) || ('$Match(pSearchChatRetentionDays, "^[0-9]+$")) {
                Set tErr = ##class(%DynamicObject).%New()
                Do tErr.%Set("field", "searchChatRetentionDays")
                Do tErr.%Set("message", "Retention days must be 1–365")
                Do tErrors.%Push(tErr)
            }
        }

        ; ─────────────────────────────────────────────────────────────
        ; Story 12.4 (BUG-06) AC-4 — Rule 9: MaxIterationsPerTurn must
        ; be a positive integer in [1, 100], matching the Config.Agent
        ; property MAXVAL/MINVAL. Empty string is accepted as "use the
        ; default 10" — the persistence branch substitutes 10 when
        ; pMaxIterationsPerTurn is empty so an operator who blanked
        ; the field gets a usable cap rather than the persistence-
        ; layer's 0-default. Out-of-range / non-numeric input is
        ; rejected with a per-field error so the operator sees
        ; actionable feedback.
        ; ─────────────────────────────────────────────────────────────
        Set tMaxIterNum = +pMaxIterationsPerTurn
        If pMaxIterationsPerTurn '= "" {
            If (tMaxIterNum < 1) || (tMaxIterNum > 100) || ('$Match(pMaxIterationsPerTurn, "^[0-9]+$")) {
                Set tErr = ##class(%DynamicObject).%New()
                Do tErr.%Set("field", "maxIterText")
                Do tErr.%Set("message", "Max iterations per turn must be 1–100")
                Do tErrors.%Push(tErr)
            }
        }

        ; If any errors, build the failure envelope and return.
        If tErrors.%Size() > 0 {
            Set tFail = ##class(%DynamicObject).%New()
            Do tFail.%Set("success", 0, "boolean")
            Do tFail.%Set("errors", tErrors)
            Set tEnvelope = tFail.%ToJSON()
            Quit
        }

        ; ─────────────────────────────────────────────────────────────
        ; Persistence — open-or-create.
        ; ─────────────────────────────────────────────────────────────
        Set tConfig = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(pAgentName)
        If '$IsObject(tConfig) {
            Set tConfig = ##class(SessionAgent.Config.Agent).%New()
            Set tConfig.AgentName = pAgentName
        }

        Set tConfig.Provider = pProvider
        Set tConfig.Model = pModel
        Set tConfig.EndpointUrl = pEndpointUrl
        Set tConfig.MaxTokens = tMaxTokensNum
        Set tConfig.Temperature = tTempNum
        Set tConfig.SystemPromptOverride = pSystemPrompt
        Set tConfig.Enabled = $Select(+pEnabled = 1 : 1, 1 : 0)

        ; Story 10.8 AC-2 — Persist SearchChatRetentionDays for the
        ; message-search row only. For session-inspection, leave the
        ; column at its existing value (the form hides the field for
        ; that agent so the operator never typed a value to persist).
        ; Empty / "0" / non-positive input falls back to the canonical
        ; default 30 to match Config.Agent.InitialExpression so an
        ; operator who blanked the field gets a usable retention rather
        ; than an immediate-purge 0-day setting.
        If pAgentName = "message-search" {
            Set tConfig.SearchChatRetentionDays = $Select(tRetentionDaysNum > 0 : tRetentionDaysNum, 1 : 30)
        }

        ; Story 12.4 (BUG-06) AC-4 — persist MaxIterationsPerTurn for
        ; both agents. Empty / 0 / out-of-range input (already rejected
        ; by Rule 9 above except empty) falls back to canonical 10 so
        ; the persisted value is always a usable iteration cap.
        Set tConfig.MaxIterationsPerTurn = $Select(tMaxIterNum > 0 : tMaxIterNum, 1 : 10)

        ; Radio-aware credential clearing — NFR-S2 schema discipline:
        ; EnvVarName XOR CredentialName, never both populated. The
        ; OPPOSITE field is unconditionally cleared so the EnvSecret
        ; three-rung resolver behaves deterministically.
        If pCredTypeRadio = "env" {
            Set tConfig.EnvVarName = pEnvVarName
            Set tConfig.CredentialName = ""
        } Else {
            ; pCredTypeRadio = "creds" (validated above).
            Set tConfig.EnvVarName = ""
            Set tConfig.CredentialName = pCredentialName
        }

        Set tSC = tConfig.%Save()
        Do tConfig.%Close()

        If $$$ISERR(tSC) {
            Set tErr = ##class(%DynamicObject).%New()
            Do tErr.%Set("field", "_form")
            Do tErr.%Set("message", "Save failed: " _ $System.Status.GetErrorText(tSC))
            Set tFail = ##class(%DynamicObject).%New()
            Do tFail.%Set("success", 0, "boolean")
            Set tFailErrors = ##class(%DynamicArray).%New()
            Do tFailErrors.%Push(tErr)
            Do tFail.%Set("errors", tFailErrors)
            Set tEnvelope = tFail.%ToJSON()
            Quit
        }

        ; Success envelope.
        Set tOk = ##class(%DynamicObject).%New()
        Do tOk.%Set("success", 1, "boolean")
        Do tOk.%Set("message", "Saved")
        Set tEnvelope = tOk.%ToJSON()
    }
    Catch ex {
        ; Defense-in-depth — never throw out of the ZenMethod (the
        ; client cannot recover from a Zen TypeError envelope). Surface
        ; the exception text in the structured error envelope so the
        ; operator sees an actionable message.
        Set tErr = ##class(%DynamicObject).%New()
        Do tErr.%Set("field", "_form")
        Do tErr.%Set("message", "Save handler exception: " _ ex.DisplayString())
        Set tFail = ##class(%DynamicObject).%New()
        Do tFail.%Set("success", 0, "boolean")
        Set tFailErrors = ##class(%DynamicArray).%New()
        Do tFailErrors.%Push(tErr)
        Do tFail.%Set("errors", tFailErrors)
        Set tEnvelope = tFail.%ToJSON()
    }
    Quit tEnvelope
}

/// <p>Story 6.2 — client-side Save handler. Replaces the Story 6.1 stub.
/// Reads the 11 form fields, calls
/// <method>SaveAgentConfig</method> via Zen hyperevent, parses the
/// returned JSON envelope, and renders an inline message — Mgmt-Portal-
/// style per UX-DR28 (no <code>alert()</code>, no modal).</p>
///
/// <p><b>On success:</b> writes "Saved" into the
/// <code>saveStatus</code> label, then auto-clears it after ~3 seconds
/// via <code>setTimeout</code> so the form returns to a clean idle
/// state. Any prior per-field error labels are also cleared.</p>
///
/// <p><b>On error:</b> writes each accumulated error into a per-field
/// inline label. Field IDs match those in the
/// <method>SaveAgentConfig</method> error envelope's <code>field</code>
/// values: <code>agentSelect</code>, <code>providerSelect</code>,
/// <code>maxTokensText</code>, <code>temperatureText</code>,
/// <code>envVarText</code>, <code>credCombo</code>,
/// <code>endpointUrlText</code>, <code>systemPromptText</code>.
/// The pseudo-field <code>_form</code> (used for save-failure /
/// exception envelopes) is rendered into the
/// <code>saveStatus</code> label.</p>
ClientMethod saveConfig() [ Language = javascript ]
{
    // Clear any prior status/error labels before issuing the save.
    zenPage.clearErrorLabels();

    // Read form values.
    var agentName     = zen('agentSelect').getValue();
    var provider      = zen('providerSelect').getValue();
    var model         = zen('modelCombo').getValue();
    var endpointUrl   = zen('endpointUrlText').getValue() || '';
    var credTypeRadio = zen('credTypeRadio').getValue();
    var envVarName    = zen('envVarText').getValue() || '';
    var credName      = zen('credCombo').getValue() || '';
    var maxTokens     = String(zen('maxTokensText').getValue() || '');
    var temperature   = String(zen('temperatureText').getValue() || '');
    var systemPrompt  = zen('systemPromptText').getValue() || '';
    // Zen checkbox returns "true"/"false" or 1/0 depending on build —
    // coerce to 1/0 string for the ZenMethod %String parameter.
    var enabledRaw = zen('enabledCheck').getValue();
    var enabled = (enabledRaw === true || enabledRaw === 1 || enabledRaw === '1' || enabledRaw === 'true') ? '1' : '0';

    // Story 10.8 AC-2 — SearchChatRetentionDays. Read the field even
    // when hidden (Zen retains the value across visibility toggles);
    // SaveAgentConfig only persists it for agent=message-search rows.
    var retentionRaw = zen('searchChatRetentionDays');
    var retention = retentionRaw ? String(retentionRaw.getValue() || '') : '';

    // Story 12.4 (BUG-06) AC-4 — MaxIterationsPerTurn. Read the field
    // value as a string so the server-side regex validation can
    // distinguish missing (empty string) from typed but invalid (non-
    // numeric). Empty string is treated as "use default 10" per the
    // SaveAgentConfig persistence branch.
    var maxIterRaw = zen('maxIterText');
    var maxIter = maxIterRaw ? String(maxIterRaw.getValue() || '') : '';

    // Hyperevent — ZenMethod returns %String JSON envelope.
    var json = zenPage.SaveAgentConfig(
        agentName, provider, model, endpointUrl, credTypeRadio,
        envVarName, credName, maxTokens, temperature, systemPrompt, enabled,
        retention, maxIter
    );

    // Story 10.8 fix-now (Rule 8 predicted-bug — ReferenceError shape):
    // statusLabel was previously referenced inside saveConfig without
    // being declared. The reference would throw on every parse-failure
    // / success / _form-error code path; only un-fired because real-
    // world JSON-envelope-parse failures are rare. Now that Story 10.8
    // adds a new code path (the retention-days validation error landing
    // in the per-field error map), the latent bug becomes an active
    // hazard. Declared here at the top of the post-hyperevent block so
    // every downstream branch has a valid handle to the saveStatus
    // label component.
    var statusLabel = zen('saveStatus');

    var data;
    try {
        data = JSON.parse(json);
    } catch (e) {
        if (statusLabel) {
            statusLabel.setValue('Save failed: response parse error');
            statusLabel.setProperty('controlClass', 'saveStatusInfo');
            if (typeof statusLabel.refreshContents === 'function') statusLabel.refreshContents();
        }
        return;
    }

    if (data && data.success) {
        if (statusLabel) {
            statusLabel.setValue('Saved');
            statusLabel.setProperty('controlClass', 'saveStatusInfo');
            if (typeof statusLabel.refreshContents === 'function') statusLabel.refreshContents();
        }
        // Auto-clear after ~3 seconds — UX-DR28 ephemeral confirmation.
        setTimeout(function() {
            var s = zen('saveStatus');
            if (s) {
                s.setValue('');
                if (typeof s.refreshContents === 'function') s.refreshContents();
            }
        }, 3000);
        return;
    }

    // Error path — render each error inline near its field.
    var errors = (data && data.errors) ? data.errors : [];
    for (var j = 0; j < errors.length; j++) {
        var err = errors[j];
        var fld = err.field || '_form';
        if (fld === '_form') {
            // Form-level error (save-status text).
            if (statusLabel) {
                statusLabel.setValue(err.message || 'Save failed');
                statusLabel.setProperty('controlClass', 'saveStatusInfo');
                if (typeof statusLabel.refreshContents === 'function') statusLabel.refreshContents();
            }
            continue;
        }
        // Per-field error label. Insert (or update) a sibling
        // <label id="<field>ErrorMessage"> element in the DOM after the
        // form field. The Zen-rendered control IDs match the XData id
        // attribute, so document.getElementById(fld) finds the input.
        var lblId = fld + 'ErrorMessage';
        var lbl = self.document.getElementById(lblId);
        if (!lbl) {
            // Lazy-create the label element next to the field.
            var fieldEl = self.document.getElementById(fld);
            if (fieldEl && fieldEl.parentNode) {
                lbl = self.document.createElement('label');
                lbl.id = lblId;
                lbl.style.color = '#C03030';
                lbl.style.fontStyle = 'italic';
                lbl.style.fontSize = '9pt';
                lbl.style.display = 'block';
                lbl.style.paddingTop = '2px';
                fieldEl.parentNode.appendChild(lbl);
            }
        }
        if (lbl) {
            lbl.innerHTML = err.message || '';
            lbl.style.display = 'block';
        }
    }
}

/// <p>Client-side handler — Cancel button. Clears any inline error
/// labels left over from a prior failed Save (manual-test 2026-05-06
/// surfaced that stale "Max tokens must be 1–32000" persisted past
/// Cancel — the field values reverted but the error nodes did not),
/// then re-loads the current <CLASS>SessionAgent.Config.Agent</CLASS>
/// row via <method>loadAgent</method>, effectively reverting any
/// pending changes. The char counter resets to the loaded override's
/// length because <method>loadAgent</method> calls
/// <method>spoChanged</method> at the end.</p>
ClientMethod cancelEdit() [ Language = javascript ]
{
    zenPage.clearErrorLabels();
    var statusLabel = zen('saveStatus');
    if (statusLabel) statusLabel.setValue('');
    zenPage.loadAgent();
}

/// <p>Client-side helper — clears all per-field inline error labels
/// (DOM nodes with id <code>&lt;fieldId&gt;ErrorMessage</code>) so a
/// fresh interaction starts from a clean slate. Called by both
/// <method>saveConfig</method> (before issuing a new save) and
/// <method>cancelEdit</method> (so reverting the form does NOT leave
/// stale error text on screen).</p>
ClientMethod clearErrorLabels() [ Language = javascript ]
{
    var errorFieldIds = [
        'agentSelect', 'providerSelect', 'maxTokensText', 'temperatureText',
        'credTypeRadio', 'envVarText', 'credCombo', 'endpointUrlText',
        'systemPromptText', 'searchChatRetentionDays', 'maxIterText'
    ];
    for (var i = 0; i < errorFieldIds.length; i++) {
        var lbl = self.document.getElementById(errorFieldIds[i] + 'ErrorMessage');
        if (lbl) {
            lbl.innerHTML = '';
            lbl.style.display = 'none';
        }
    }
}

}
