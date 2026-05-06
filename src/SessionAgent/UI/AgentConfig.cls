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
/// <p><b>Inheritance.</b> Extends <code>%ZEN.Component.page</code> per
/// epics.md line 1826. <code>Parameter APPLICATION =
/// "EnsPortal.Application"</code> wires the page into the Mgmt Portal
/// stylesheet/header pipeline so the form looks like sibling EnsPortal
/// pages without re-implementing the chrome (UX-DR26 — no
/// Material/Tailwind/etc.).</p>
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
Class SessionAgent.UI.AgentConfig Extends %ZEN.Component.page
{

/// <p>Wire the page into the Mgmt Portal stylesheet/header pipeline so
/// the form chrome matches sibling EnsPortal pages (UX-DR26).</p>
Parameter APPLICATION = "EnsPortal.Application";

/// <p>Operator-friendly title rendered in the page title bar.</p>
Parameter PAGENAME = "Agent Configuration";

/// <p>Resource gating: operator must have %Ens_Portal:USE (the standard
/// Mgmt Portal access resource) to view the page. The
/// SessionAgent_ReadOnly role grants %Ens_Portal:USE indirectly via
/// Story 1.4's role install. Edit-time enforcement (the actual save
/// handler) lands in Story 6.2 with EDITRESOURCE wiring.</p>
Parameter RESOURCE = "%Ens_Portal:USE";

/// <p>Localized strings resolve via the existing Ens domain catalog
/// (matches <CLASS>EnsPortal.Credentials</CLASS> pattern).</p>
Parameter DOMAIN = "%Ensemble";

/// <p>Form layout. Thirteen components in the order specified by AC-2.
/// All <code>label</code> / <code>caption</code> / <code>displayList</code>
/// attributes are deliberately omitted — they are populated at runtime
/// in <method>%OnAfterCreatePage</method> to avoid compile-time MPP5646
/// <code>&lt;PROTECT&gt;</code> errors against the
/// <code>^%qMsg("%Ensemble",...)</code> catalog (see class doc-comment).
/// Tab navigation follows visible order.</p>
XData Contents [ XMLNamespace = "http://www.intersystems.com/zen" ]
{
<page xmlns="http://www.intersystems.com/zen">
<vgroup cellStyle="padding:6px;">

<select id="agentSelect" valueList="session-inspection,message-search" value="session-inspection" onchange="zenPage.loadAgent();" />

<select id="providerSelect" valueList="openai,anthropic,gemini,openai-compatible" onchange="zenPage.providerChanged();" />

<combobox id="modelCombo" editable="true" />

<text id="endpointUrlText" hidden="true" size="60" />

<radioSet id="credTypeRadio" valueList="env,creds" value="env" onchange="zenPage.credTypeChanged();" />

<text id="envVarText" size="40" />

<combobox id="credCombo" editable="true" hidden="true" />

<text id="maxTokensText" size="8" />

<text id="temperatureText" size="8" />

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
</page>
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
ClientMethod onloadHandler() [ Language = javascript ]
{
    zenPage.loadAgent();
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
ClassMethod GetCredentialsList() As %String
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
        Do tObj.%Set("MaxTokens", 4000)
        Do tObj.%Set("Temperature", 0.1)
        Do tObj.%Set("SystemPromptOverride", "")
        Do tObj.%Set("Enabled", 0)
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
    zen('maxTokensText').setValue(data.MaxTokens || 4000);
    zen('temperatureText').setValue(data.Temperature || 0.1);
    zen('systemPromptText').setValue(data.SystemPromptOverride || '');
    zen('enabledCheck').setValue(data.Enabled ? 1 : 0);

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

    // Clear any stale save-status message from a prior interaction.
    zen('saveStatus').setValue('');
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

/// <p>Client-side handler — Save button. Story 6.1 stub: surfaces an
/// inline message that the persistence path ships in Story 6.2. The
/// form's dirty state is preserved so the operator can re-test once
/// 6.2 lands. No JS alert / no modal — UX-DR28 / Mgmt-Portal-style.</p>
ClientMethod saveConfig() [ Language = javascript ]
{
    var status = zen('saveStatus');
    if (status) {
        status.setValue('Save handler ships in Story 6.2 — your changes are not yet persisted.');
        status.setProperty('controlClass', 'saveStatusInfo');
        if (typeof status.refreshContents === 'function') {
            status.refreshContents();
        }
    }
}

/// <p>Client-side handler — Cancel button. Re-loads the current
/// <CLASS>SessionAgent.Config.Agent</CLASS> row via
/// <method>loadAgent</method>, effectively reverting any pending
/// changes. The char counter resets to the loaded override's length
/// because <method>loadAgent</method> calls
/// <method>spoChanged</method> at the end.</p>
ClientMethod cancelEdit() [ Language = javascript ]
{
    zenPage.loadAgent();
}

}
