/// <p>Inspection tool — reads the adapter class, pool size, enabled flag,
/// and explicitly configured settings of any named config item in an
/// Ensemble production. Helps operators diagnose config-related failures
/// (wrong file path, wrong credentials, pool=0, scheduler disabled).</p>
///
/// <p><b>Tool name:</b> <code>get_production_config_item</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b>
/// <code>{production_name (required), config_item_name (required)}</code>.
/// Both are class names — pass the class name only, no method suffixes.</p>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{production_name, config_item_name, class_name, adapter_class,
/// enabled, pool_size, comment, host_settings, adapter_settings,
/// render_strategy}</code>. <code>host_settings</code> and
/// <code>adapter_settings</code> are arrays of
/// <code>{name, value}</code> objects — both empty when the item uses
/// all default settings.</p>
///
/// <p><b>render_strategy values:</b>
/// <code>"ok"</code> (item found), <code>"production_not_found"</code>,
/// <code>"item_not_found"</code>, <code>"validation_error"</code>.</p>
///
/// <p><b>Strip-last-segment fallback (production_name only).</b>
/// If the production is not found on first attempt AND
/// <code>production_name</code> contains a dot, the last dot-segment is
/// stripped and the lookup retried once. On success the response includes
/// <code>production_name_auto_corrected_from</code>. On failure the
/// response includes <code>candidate_production_name</code> so the LLM
/// can self-correct. <code>config_item_name</code> is NOT stripped — it
/// is an Ensemble config-item name, not a class name.</p>
///
/// <p><b>CRITICAL API notes.</b>
/// <code>Ens.Config.Item.NameKeyOpen()</code> and
/// <code>Ens.Config.Item.NameOpen()</code> do NOT exist. Item lookup
/// uses parameterized SQL against <code>Ens_Config.Item</code>.
/// <code>Ens.Config.Setting</code> is a <code>%SerialObject</code>
/// embedded in Item — there is no <code>Ens_Config.Setting</code> SQL
/// table. Settings are accessed only via
/// <code>tItem.Settings.GetAt(i)</code>.</p>
///
/// <p><b>No throws.</b> Outer Try/Catch around all steps; any unexpected
/// exception → <code>{isError:1, error_text:...}</code>.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/13-3-get-production-config-item-tool.md">
/// Story 13.3</a> — AC source.</li>
/// <li><a href="GetQueueState.cls">GetQueueState.cls</a> — tool class
/// pattern reference.</li>
/// <li><a href="GetBusinessProcessSource.cls">GetBusinessProcessSource.cls</a>
/// — strip-last-segment pattern.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.GetProductionConfigItem Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "get_production_config_item";

Parameter Description As %String = "Read the adapter class, pool size, enabled flag, and explicitly configured settings of any named config item in an Ensemble production — use this to diagnose config-related failures such as wrong file path, wrong credentials, pool=0, or a scheduler item disabled.";

Parameter MutatesState As %Boolean = 0;

/// <p>JSON Schema — required: <code>production_name</code>,
/// <code>config_item_name</code>. No additional properties.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "production_name": {
                "type": "string",
                "description": "Full class name of the Ensemble production (e.g. SessionAgent.Sample.Production). Pass the class name only — do not include method names (e.g. pass 'SessionAgent.Sample.Production', not 'SessionAgent.Sample.Production.OnRequest')."
            },
            "config_item_name": {
                "type": "string",
                "description": "Ensemble config item name as it appears in the production (e.g. SessionAgent.Sample.BO.FilePublish). Pass the class name only — do not include method names."
            }
        },
        "required": ["production_name", "config_item_name"],
        "additionalProperties": false
    }
}

/// <p>Read the config item from the named production. Validates inputs,
/// looks up the production and item via SQL + %OpenId, splits settings
/// by Target, and composes the response envelope.</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; ---- Extract and validate required inputs ----
        Set tProductionName = ""
        Set tConfigItemName = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tProductionName = pJsonArgs.%Get("production_name")
            Set:tProductionName=$$$NULLOREF tProductionName = ""
            Set tConfigItemName = pJsonArgs.%Get("config_item_name")
            Set:tConfigItemName=$$$NULLOREF tConfigItemName = ""
        }

        If tProductionName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing production_name"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing production_name"}}
            Quit
        }
        If tConfigItemName = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing config_item_name"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing config_item_name"}}
            Quit
        }

        ; ---- Validate production_name format ----
        If '$Match(tProductionName, "^[A-Za-z%][A-Za-z0-9%._]*$") {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"invalid production_name format"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"production_name contains invalid characters"}}
            Quit
        }

        ; ---- Step 1: Verify production exists ----
        Set tOrigProductionName = tProductionName
        Set tAutoCorrected = 0
        Set tStrippedName = ""

        Set tProd = ##class(Ens.Config.Production).%OpenId(tProductionName)

        ; Strip-last-segment fallback on production_name only
        If '$IsObject(tProd), tProductionName [ "." {
            Set tSegCount = $Length(tProductionName, ".")
            If tSegCount > 1 {
                Set tStrippedName = $Piece(tProductionName, ".", 1, tSegCount - 1)
                Set tProd = ##class(Ens.Config.Production).%OpenId(tStrippedName)
                If $IsObject(tProd) {
                    Set tProductionName = tStrippedName
                    Set tAutoCorrected = 1
                }
            }
        }

        If '$IsObject(tProd) {
            Do pResult.structuredContent.%Set("production_name", tOrigProductionName)
            Do pResult.structuredContent.%Set("render_strategy", "production_not_found")
            If tStrippedName '= "" {
                Do pResult.structuredContent.%Set("candidate_production_name", tStrippedName)
            }
            Set pResult.content.%Get(0).text = "production not found: " _ tOrigProductionName
            Quit
        }

        ; ---- Step 2: Find item by parameterized SQL ----
        Set tStmt = ##class(%SQL.Statement).%New()
        Set tSC2 = tStmt.%Prepare("SELECT %EXACT(ID), %EXACT(ClassName), Enabled, PoolSize, %EXACT(Comment) FROM Ens_Config.Item WHERE %EXACT(Production) = ? AND %EXACT(Name) = ?")
        If $$$ISERR(tSC2) {
            Set tErrText = $System.Status.GetErrorText(tSC2)
            Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"server_fault", "error_text":(tErrText)}}
            Quit
        }
        Set tRS = tStmt.%Execute(tProductionName, tConfigItemName)
        ; Story 14.0 — centralized execute-failure gate (cr-13-3).
        If ##class(SessionAgent.Tool.Base).EnsureIsErrorOnExecuteFailure(pResult, tRS, ..#ToolName) Quit
        If 'tRS.%Next() {
            Do pResult.structuredContent.%Set("production_name", tProductionName)
            Do pResult.structuredContent.%Set("config_item_name", tConfigItemName)
            Do pResult.structuredContent.%Set("render_strategy", "item_not_found")
            Set pResult.content.%Get(0).text = "config item not found: '" _ tConfigItemName _ "' in production '" _ tProductionName _ "'"
            Quit
        }

        ; Use positional access — %EXACT() wrapping changes column name aliases
        ; Column order: 1=ID, 2=ClassName, 3=Enabled, 4=PoolSize, 5=Comment
        Set tItemID = tRS.%GetData(1)
        Set tClassName = tRS.%GetData(2)
        Set tEnabled = tRS.%GetData(3)
        Set tPoolSize = tRS.%GetData(4)
        Set tComment = tRS.%GetData(5)
        If tComment = $Char(0) Set tComment = ""

        ; ---- Step 3: Open item object for adapter class and settings ----
        Set tItem = ##class(Ens.Config.Item).%OpenId(tItemID)
        Set tAdapterClass = ""
        If $IsObject(tItem) {
            Set tAdapterClass = tItem.AdapterClassName()
            If tAdapterClass = $$$NULLOREF Set tAdapterClass = ""
        }

        ; ---- Step 4: Split settings by Target ----
        Set tHostSettings = []
        Set tAdapterSettings = []
        If $IsObject(tItem) {
            Set tKey = ""
            For {
                Set tSetting = tItem.Settings.GetNext(.tKey)
                Quit:tKey=""
                If $IsObject(tSetting) {
                    Set tEntry = {}
                    Do tEntry.%Set("name", tSetting.Name)
                    Do tEntry.%Set("value", tSetting.Value)
                    If tSetting.Target = "Host" {
                        Do tHostSettings.%Push(tEntry)
                    } ElseIf tSetting.Target = "Adapter" {
                        Do tAdapterSettings.%Push(tEntry)
                    }
                }
            }
        }

        ; ---- Step 5: Compose response ----
        Do pResult.structuredContent.%Set("production_name", tProductionName)
        Do pResult.structuredContent.%Set("config_item_name", tConfigItemName)
        Do pResult.structuredContent.%Set("class_name", tClassName)
        Do pResult.structuredContent.%Set("adapter_class", tAdapterClass)
        Do pResult.structuredContent.%Set("enabled", ''tEnabled, "boolean")
        Do pResult.structuredContent.%Set("pool_size", +tPoolSize, "number")
        Do pResult.structuredContent.%Set("comment", tComment)
        Do pResult.structuredContent.%Set("host_settings", tHostSettings)
        Do pResult.structuredContent.%Set("adapter_settings", tAdapterSettings)
        Do pResult.structuredContent.%Set("render_strategy", "ok")

        ; Auto-correction marker when strip-last-segment fired
        If tAutoCorrected {
            Do pResult.structuredContent.%Set("production_name_auto_corrected_from", tOrigProductionName)
        }

        Set tEnabledLabel = $Select(''tEnabled:"enabled", 1:"disabled")
        Set tText = "'" _ tConfigItemName _ "' in '" _ tProductionName _ "': class=" _ tClassName _ ", adapter=" _ tAdapterClass _ ", " _ tEnabledLabel _ ", pool_size=" _ +tPoolSize
        Set pResult.content.%Get(0).text = tText
        Quit
    }
    Catch ex {
        ; No-throw guarantee — any escaping exception returns an isError envelope.
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"server_fault", "error_text":(tErrText)}}
    }
    Quit tSC
}

}
