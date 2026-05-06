/// <p>Inspection tool — decode a <code>%Status</code> serialized value
/// or a bare IRIS error code/message into operator-readable text with
/// common-causes and suggested-diagnostics annotations. Thirteenth and
/// final inspection tool; ships with Story 4.7 (Epic 4 closer); Story 5.0
/// extended the curated table to 15 entries (10 base, with the stale
/// <code>&lt;Ens&gt;ErrBPTerm</code> entry corrected in-place to the
/// canonical <code>&lt;Ens&gt;ErrBPTerminated</code> name, plus 5 new
/// Ens-specific adds: <code>&lt;Ens&gt;ErrGeneral</code>,
/// <code>&lt;Ens&gt;ErrBPTimeout</code>, <code>&lt;Ens&gt;ErrNoTimeout</code>,
/// <code>&lt;Ens&gt;ErrException</code>,
/// <code>&lt;Ens&gt;ErrSearchTableNotIndex</code>).</p>
///
/// <p><b>Tool name:</b> <code>explain_error</code>. Read-only
/// (<parameter>MutatesState</parameter>=0).</p>
///
/// <p><b>Input:</b> <code>{status_or_error_string (required)}</code>.
/// Accepts either:</p>
/// <ul>
/// <li>A serialized <code>%Status</code> value (begins with the byte
/// pair <code>"0 "</code> for errors per <code>irislib/%Library/Status.cls</code>
/// and <code>%SYSTEM.Status::Error</code> probe). Decoded via
/// <code>$System.Status.GetErrorText</code>.</li>
/// <li>A bare error-code/message string like <code>&lt;PROTECT&gt;</code>,
/// <code>&lt;UNDEFINED&gt;</code>, <code>&lt;Ens&gt;ErrBPTerminated</code>, or
/// a free-form description containing one of the curated codes.</li>
/// </ul>
///
/// <p><b>Output (structuredContent):</b>
/// <code>{input, decoded_text, code_class, common_causes:[...],
/// suggested_diagnostics:[...], render_strategy:"matched"|"unmatched"|
/// "status_decoded"|"decode_error"}</code>. Even on unmatched input the
/// envelope is success-shape (no <code>isError</code>) so the operator
/// always sees the input echoed back with a "search documentation" hint.</p>
///
/// <p><b>Curated lookup table.</b> 15 named IRIS error codes per Story
/// 4.7 AC-3 (10 base, one of which — <code>&lt;Ens&gt;ErrBPTerm</code>
/// — was corrected in Story 5.0 to the canonical
/// <code>&lt;Ens&gt;ErrBPTerminated</code>) + Story 5.0 AC-5 (5
/// Ens-specific adds). Built in <method>BuildErrorTable</method> as a
/// <code>%DynamicObject</code> and **cached per-process** in the
/// process-private global <code>^||SessionAgentExplainErrorTable</code>
/// (seeded once via <code>%ToJSON</code>, rehydrated via
/// <code>%FromJSON</code>) so we avoid the per-Invoke rebuild cost
/// without committing to global side effects (PPGs are process-scoped —
/// no inter-process state, no persistence). The cache is a JSON string
/// round-trip rather than an OREF (per project rule on Process-Private
/// Globals — OREFs do not preserve identity across <code>^||</code>);
/// the rebuild cost is ~15 entries' worth of object construction, paid
/// once per process.</p>
///
/// <p><b>Status-shape detection.</b> A <code>%Status</code> serialized
/// error begins with the bytes <code>"0 "</code> (ASCII 48, 32) followed
/// by binary length-prefix bytes (verified via
/// <code>%SYSTEM.Status::Error(5001, "probe")</code> — first two bytes
/// returned 48 and 32). A success status is the literal <code>"1"</code>.
/// The detection accepts either as the "this is a %Status" signal and
/// dispatches to <code>$System.Status.GetErrorText</code>; everything else
/// falls through to the curated-table lookup.</p>
///
/// <p><b>Story 5.0 stale-name correction.</b> The original Story 4.7
/// table entry keyed <code>&lt;Ens&gt;ErrBPTerm</code>; the canonical
/// IRIS error name per <code>irislib/EnsErrors.inc</code> line 18 is
/// <code>&lt;Ens&gt;ErrBPTerminated</code> (used live at
/// <code>irislib/Ens/BusinessProcess.cls:701</code> via
/// <code>$$$EnsErrBPTerminated</code>). Story 5.0 corrected the table
/// entry per Rule 4 (stale-reference scan) + Rule 8 (fix-now is default).</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.7</a> (lines 1620+) — original AC source.</li>
/// <li><a href="../../../../_bmad-output/implementation-artifacts/5-0-epic-4-deferred-cleanup.md">Story 5.0</a>
/// AC-5 — Ens-specific additions.</li>
/// <li><a href="../../../../irislib/EnsErrors.inc">irislib/EnsErrors.inc</a>
/// — canonical Ens error code names; verified via grep on 2026-05-06.</li>
/// <li><a href="../../../../irislib/%25SYSTEM/Status.cls">irislib/%SYSTEM/Status.cls</a>
/// — <code>GetErrorText(statuscode, language)</code> signature, line 77.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.ExplainError Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "explain_error";

Parameter Description As %String = "Decode a %Status value or IRIS error code/message into operator-readable explanation with common causes and suggested diagnostics.";

Parameter MutatesState As %Boolean = 0;

/// <p>Curated table builder — 15 named IRIS error codes (10 base from
/// Story 4.7 AC-3, one renamed in-place via the
/// <code>&lt;Ens&gt;ErrBPTerm</code> → <code>&lt;Ens&gt;ErrBPTerminated</code>
/// stale-name correction; plus 5 Ens-specific adds from Story 5.0 AC-5).
/// Returns a <code>%DynamicObject</code> keyed by error code with
/// <code>{code_class, decoded_text, common_causes,
/// suggested_diagnostics}</code> per entry. **Per-process cached** via
/// <code>^||SessionAgentExplainErrorTable</code> as a JSON string —
/// rebuild cost paid once per process, not once per Invoke. PPG keys
/// per project rule on Process-Private Globals (no hyphens; subscript
/// is the literal global name).</p>
///
/// <p>Operator-readable explanations sourced from the IRIS 2024.1 docs
/// (RERR_system, RCOS_vstorage, GCSP_errorcodes, ECONFIG_settings_busop,
/// EBPL_use) verified current via Perplexity search 2026-05-06 per Rule
/// 10 (external-default research at spec time). Cross-checked against
/// canonical names in <code>irislib/EnsErrors.inc</code>.</p>
ClassMethod BuildErrorTable() As %DynamicObject [ Internal ]
{
    ; Per-process cache — seed once, rehydrate via %FromJSON on
    ; subsequent calls. PPG stores the JSON string (not an OREF) per
    ; project rule on Process-Private Globals. Argumentless Quit
    ; pattern inside Try/Catch (project rule on QUIT restrictions);
    ; the actual Return happens via the tCached variable after the block.
    Set tCached = ""
    If $Data(^||SessionAgentExplainErrorTable) {
        Try {
            Set tCached = ##class(%DynamicObject).%FromJSON(^||SessionAgentExplainErrorTable)
        }
        Catch ex {
            ; Cache corrupt — fall through and rebuild.
            Set tCached = ""
            Kill ^||SessionAgentExplainErrorTable
        }
    }
    If $IsObject(tCached) {
        Quit tCached
    }
    Set tTable = {}
    Do tTable.%Set("<PROTECT>", {
        "code_class": "security",
        "decoded_text": "Attempt to access a protected resource (variable, routine, global, or database) without sufficient privileges.",
        "common_causes": [
            "Insufficient user role/permissions for the requested global, class, or database.",
            "Privilege required on the resource (e.g. %DB_HSCUSTOM, %Admin_Operate) is missing from the calling user's role grants.",
            "Code path crossed a namespace boundary into a database the caller cannot read or write."
        ],
        "suggested_diagnostics": [
            "Check $ZERROR for the protected item (global name, class name, or routine).",
            "Review the caller's roles in System Administration > Security > Users / Roles.",
            "Confirm the resource grant table (Security.Resources) covers the target database."
        ]
    })
    Do tTable.%Set("<UNDEFINED>", {
        "code_class": "runtime",
        "decoded_text": "Reference to an undefined symbol (local variable, global node, label, or routine).",
        "common_causes": [
            "Typo in variable, global, or routine name.",
            "Variable not Set before reading; reading a global node that has no value (use $Get to default it).",
            "Routine or class not loaded/compiled in the current namespace."
        ],
        "suggested_diagnostics": [
            "Examine $ZERROR for the exact undefined item and source line.",
            "Wrap the read with $Get(var) or guard with $Data(var)#2 to default when absent.",
            "Verify routine/class compilation in the target namespace via Studio or Atelier."
        ]
    })
    Do tTable.%Set("<NOTOPEN>", {
        "code_class": "io",
        "decoded_text": "Attempt to read or write a device (file, pipe, terminal) that has not been opened or has been closed.",
        "common_causes": [
            "Use or Read/Write executed before the matching Open command.",
            "Device closed by a prior error path; subsequent code still references the old device.",
            "File-system permission failure during Open turned a legitimate Open into a no-op."
        ],
        "suggested_diagnostics": [
            "Check $ZERROR for the device name.",
            "Wrap Open with a status check; only Use the device if Open succeeded.",
            "Verify file-system permissions and confirm the device path exists."
        ]
    })
    Do tTable.%Set("<METHOD DOES NOT EXIST>", {
        "code_class": "dispatch",
        "decoded_text": "Call to a method that the class (or any of its superclasses) does not declare.",
        "common_causes": [
            "Typo in method name at the call site (case matters).",
            "Method declared on a sibling class but not inherited by the caller's class.",
            "Class compiled stale; method was added or renamed in source but the compiled .CLS is older."
        ],
        "suggested_diagnostics": [
            "Inspect $ZERROR for the class and method name.",
            "Confirm method existence via Studio or %Dictionary.CompiledMethod query.",
            "Recompile the class (and any Storage-Inheriting subclasses) and retry."
        ]
    })
    Do tTable.%Set("<Ens>ErrBPTerminated", {
        "code_class": "interop",
        "decoded_text": "An Ensemble/InterSystems IRIS production Business Process terminated abnormally — typically the BP threw an exception that the production halted on. (Story 5.0: corrected from stale '<Ens>ErrBPTerm' to canonical '<Ens>ErrBPTerminated' per irislib/EnsErrors.inc:18.)",
        "common_causes": [
            "A downstream service or operation returned an unhandled error status that the BP did not catch.",
            "The BP class itself threw a runtime error (UNDEFINED, INVALID OREF, etc.) inside an OnRequest, OnResponse, or state-transition method.",
            "Configuration drift — the BP class compiled at install time differs from the running production's expected signature."
        ],
        "suggested_diagnostics": [
            "Open the Production trace in the Management Portal and locate the failed BP message header (IsError=1).",
            "Examine the linked Ens.MessageHeader.Status for the underlying error chain.",
            "Call the get_business_process_instance tool with the BP class to inspect %LastError on the persisted Context."
        ]
    })
    Do tTable.%Set("<CLASS DOES NOT EXIST>", {
        "code_class": "dispatch",
        "decoded_text": "Reference to a class that does not exist in the current namespace.",
        "common_causes": [
            "Typo in class name (case sensitive).",
            "Class lives in a different namespace and is not mapped into the current one.",
            "Class was compiled into a package mapping that excludes the current namespace."
        ],
        "suggested_diagnostics": [
            "Query ##class(%Dictionary.ClassDefinition).%ExistsId('Class.Name') to confirm absence.",
            "Check namespace package mappings (Config.MapPackages) for the offending class's package.",
            "If the class lives in HSCUSTOM but is referenced from %SYS, restore the original namespace before the call (project rule on Namespace Switching)."
        ]
    })
    Do tTable.%Set("<INVALID OREF>", {
        "code_class": "runtime",
        "decoded_text": "Use of an invalid object reference (a NULLOREF, a destroyed object, or a stringified OREF that lost identity).",
        "common_causes": [
            "Object never instantiated (##class(...).%New() missing or returned NULLOREF).",
            "Object stored in a $ListBuild or process-private global which serialized it to a string (project rule on Process-Private Globals — OREF round-trips as a string).",
            "Property accessed on a non-object expression."
        ],
        "suggested_diagnostics": [
            "Guard with If $IsObject(obj) before any property/method access.",
            "Replace $ListBuild storage with named locals or a %RegisteredObject singleton.",
            "Trace object lifecycle — confirm the OREF is alive at the call site, not a stale handle from a prior turn."
        ]
    })
    Do tTable.%Set("<SYNTAX>", {
        "code_class": "compile",
        "decoded_text": "Invalid ObjectScript syntax — the parser could not interpret the source line as a legal statement or expression.",
        "common_causes": [
            "Unbalanced quotes, parentheses, or curly braces.",
            "Wrong macro syntax — $$ used where $$$ (triple-dollar) is required.",
            "ObjectScript-only operator embedded in a context that doesn't support it (e.g. unescaped underscore in a global subscript reads as concatenation)."
        ],
        "suggested_diagnostics": [
            "Read $ZERROR for the source line and column.",
            "If the source uses $$$ macros, recompile after a clean Save to surface mismatched-paren positions.",
            "Search for stray hyphens in subscripts (^||MyState-1 parses as subtraction)."
        ]
    })
    Do tTable.%Set("<MAXSTRING>", {
        "code_class": "runtime",
        "decoded_text": "String or expression exceeded IRIS's maximum string length (typically 3,641,144 bytes for long strings).",
        "common_causes": [
            "Concatenating a stream into a single string instead of streaming.",
            "Building a giant JSON or XML payload in memory by repeated underscore concatenation.",
            "Multiple Base64-encode round-trips on a stream that should be encoded in one Read+Encode call."
        ],
        "suggested_diagnostics": [
            "Switch to %Stream.GlobalCharacter or %Stream.FileBinary for the offending payload.",
            "If the call is a single $System.Encryption.Base64Encode, ensure the Read is one big read (project rule on Timestamp and Encoding Standards).",
            "Profile $Length at the failure point to confirm the size before/after the offending operation."
        ]
    })
    Do tTable.%Set("<STORE>", {
        "code_class": "runtime",
        "decoded_text": "Process exhausted its local-variable storage memory ($STORAGE reached zero or negative).",
        "common_causes": [
            "Excessive local variables or large arrays not Killed between iterations.",
            "Deep recursion that captures large stack frames.",
            "An Ens production method called repeatedly in a tight loop without releasing %DynamicObject locals between calls."
        ],
        "suggested_diagnostics": [
            "Monitor $STORAGE at suspected hot spots; aim to keep > 256K free.",
            "Add Kill var (or Kill ^||temp) at the end of each loop iteration.",
            "If process-wide, raise $ZSTORAGE or split the workload into smaller batches."
        ]
    })
    ; ---- Story 5.0 AC-5 — Ens-specific additions ----
    Do tTable.%Set("<Ens>ErrGeneral", {
        "code_class": "interop",
        "decoded_text": "Generic Ensemble runtime error — a catch-all wrapper used when a Business Service, Business Process, or Business Operation host detects a failure that does not map to a more specific Ens error code. The underlying cause is usually preserved in the message body or linked Ens.Util.Log row.",
        "common_causes": [
            "Injected sample-production failure (test-harness error injection point, e.g. SampleProduction.RunScenario error variants).",
            "Business Operation caught an external-system failure (database, HTTP, file I/O) and re-raised it as ErrGeneral without a specific sub-code.",
            "Business Process logic threw an unhandled exception inside OnRequest/OnResponse/state-transition methods."
        ],
        "suggested_diagnostics": [
            "Open the linked Ens.MessageHeader and follow Status to the underlying error chain.",
            "Query Ens.Util.Log for entries near the failure timestamp — the SourceClass and Text columns usually carry the real cause.",
            "If injected from sample fixtures, cross-check against SessionAgent.SampleProduction.RunScenario error-injection options."
        ]
    })
    Do tTable.%Set("<Ens>ErrBPTimeout", {
        "code_class": "interop",
        "decoded_text": "A Business Process awaited a synchronous response from a downstream operation that did not arrive within the configured timeout. The BP transitions to its error/fault branch and the queued message moves to error state.",
        "common_causes": [
            "Downstream Business Operation is slow, blocked, or its retry budget exceeds the BP's await timeout.",
            "BP <call> with a too-short timeout attribute — the operation runs longer than the BPL contract allows.",
            "Operation queue backlog (QueueCountAlert threshold) or a suspended/disabled operation that never replies."
        ],
        "suggested_diagnostics": [
            "Inspect the BP's BPL <call> or <sync> action and raise the timeout (or set timeout='-1' for never-timeout on critical paths).",
            "Check the downstream operation's queue state via Ensemble > Monitor > Queues — a backlog indicates the operation cannot keep up.",
            "Enable Log Trace Events on both the BP and the operation to measure actual round-trip time and locate the bottleneck."
        ]
    })
    Do tTable.%Set("<Ens>ErrNoTimeout", {
        "code_class": "interop",
        "decoded_text": "An asynchronous Ensemble call was issued without a configured timeout — Ensemble best-practice violation. Productions enforce timeouts on async <call>s with ResponseTo/ResponseFrom routing because an untimed async call can wait indefinitely for a reply that never arrives.",
        "common_causes": [
            "BPL <call> with async='true' and ReplyTo set, but no timeout attribute.",
            "Routing process configured with 'Response From' populated but 'Response Timeout' left blank.",
            "Force Sync Send is true but no FailureTimeout on the operation."
        ],
        "suggested_diagnostics": [
            "Add a timeout attribute to the BPL <call> (e.g. timeout='30' or timeout='-1' for never-timeout when truly long-running).",
            "On a routing process, set 'Response Timeout' to a positive value or '-1' whenever 'Response From' is set.",
            "Validate the BP via Ens.BPL.Utils.ValidateBP — it surfaces missing-timeout configuration."
        ]
    })
    Do tTable.%Set("<Ens>ErrException", {
        "code_class": "interop",
        "decoded_text": "Wrapping shape for caught exceptions inside Ensemble hosts — the framework caught an ObjectScript exception thrown from a Business Service, Business Process, or Business Operation method and re-raised it as a structured Ens error so the production's error-handling path engages.",
        "common_causes": [
            "Unhandled <UNDEFINED>, <INVALID OREF>, or other runtime exception inside an Ensemble host's request/response handler.",
            "External-system failure (HTTP error, SQL connection drop, file I/O failure) caught by the framework wrapper.",
            "Business Operation code threw before the host's own Try/Catch caught it — the framework's outer wrapper is the catcher of last resort."
        ],
        "suggested_diagnostics": [
            "The wrapped exception's DisplayString is usually preserved in the Ens.Util.Log row Text column — query by SessionId near the failure timestamp.",
            "Inspect %LastError on the persisted Context (Business Process) or the operation's audit trail for the inner exception class and message.",
            "Add explicit Try/Catch inside the host method to handle the inner exception specifically — letting it bubble to ErrException loses contextual information."
        ]
    })
    Do tTable.%Set("<Ens>ErrSearchTableNotIndex", {
        "code_class": "interop",
        "decoded_text": "An Ens.SearchTableBase subclass referenced by a query, business component, or message-search operation has not been indexed (BuildIndex never ran) — so the SearchTable's persistent extent is empty or out-of-date relative to the parent message-body class.",
        "common_causes": [
            "Operator added a SearchTable subclass to the production but did not run BuildIndex against the existing message corpus.",
            "Schema migration created/altered the SearchTable definition but the rebuild step was skipped.",
            "Mid-cycle test code references a SearchTable that the test harness installed but did not populate."
        ],
        "suggested_diagnostics": [
            "Run ##class(<SearchTable>).BuildIndex() (or the per-class BuildIndex method) to populate the SearchTable extent from existing messages.",
            "Verify the SearchTable's parent message-body class compiles cleanly — a stale parent prevents BuildIndex from seeding new rows.",
            "If the failure surfaces in a tool like find_sessions_by_body, confirm the body_class argument actually has the Ens.SearchTableBase subclass installed and indexed."
        ]
    })
    ; ---- Seed the per-process cache for subsequent calls ----
    Try {
        Set ^||SessionAgentExplainErrorTable = tTable.%ToJSON()
    }
    Catch ex {
        ; Best-effort — if the cache write fails the function still
        ; returns the freshly-built table.
        Kill ^||SessionAgentExplainErrorTable
    }
    Quit tTable
}

/// <p>Locked-subset JSON Schema. Required: <code>status_or_error_string</code>.
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "status_or_error_string": {"type": "string", "description": "A serialized %Status value (e.g. captured via $$$ERROR or %Save status) OR a bare IRIS error code/message string like '<PROTECT>' or '<Ens>ErrBPTerminated'."}
        },
        "required": ["status_or_error_string"],
        "additionalProperties": false
    }
}

/// <p>Decode the input. Status-shape goes through
/// <code>$System.Status.GetErrorText</code>; bare error codes/messages
/// go through the curated table. Unmatched input is echoed back with a
/// "search documentation" hint — NOT an error envelope (operator can
/// still see the original input).</p>
ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pResult = {"content":[{"type":"text","text":""}], "structuredContent":{}}
    Try {
        ; ---- Pre-validation ----
        Set tInput = ""
        If $IsObject($Get(pJsonArgs)) {
            Set tInput = pJsonArgs.%Get("status_or_error_string")
            Set:tInput=$$$NULLOREF tInput = ""
        }
        If tInput = "" {
            Set pResult = {"isError":(1), "content":[{"type":"text","text":"missing status_or_error_string"}], "structuredContent":{"render_strategy":"validation_error", "error_text":"missing status_or_error_string"}}
            Quit
        }

        ; ---- Step 1 — %Status shape detection ----
        ; Per probe (%SYSTEM.Status::Error(5001, "probe")) — error %Status
        ; begins with bytes 48 ('0') + 32 (' '). Success is literal "1".
        ; Anything else is treated as a bare error-code string.
        Set tIsStatusShape = 0
        Set tStatusText = ""
        If ($Length(tInput) >= 2) && ($Ascii(tInput, 1) = 48) && ($Ascii(tInput, 2) = 32) {
            Set tIsStatusShape = 1
            Set tStatusText = $System.Status.GetErrorText(tInput)
        }

        If tIsStatusShape {
            ; The decoded text from a %Status often embeds a bare IRIS code
            ; (e.g. "ERROR #5002: ObjectScript error: <UNDEFINED>foo") —
            ; try a curated lookup AGAINST the decoded text so the operator
            ; gets common-causes + diagnostics whenever possible.
            Set tMatch = ..LookupCuratedCode(tStatusText)
            If tMatch '= "" {
                Set tEntry = ..GetTableEntry(tMatch)
                Do pResult.structuredContent.%Set("input", tInput)
                Do pResult.structuredContent.%Set("decoded_text", tStatusText)
                Do pResult.structuredContent.%Set("code_class", tEntry.%Get("code_class"))
                Do pResult.structuredContent.%Set("common_causes", tEntry.%Get("common_causes"))
                Do pResult.structuredContent.%Set("suggested_diagnostics", tEntry.%Get("suggested_diagnostics"))
                Do pResult.structuredContent.%Set("render_strategy", "matched")
                Do pResult.structuredContent.%Set("matched_code", tMatch)
                Set pResult.content.%Get(0).text = "%Status decoded (matched " _ tMatch _ "): " _ tEntry.%Get("decoded_text")
            } Else {
                ; %Status decoded but no curated entry hit — render the raw
                ; GetErrorText output and tag as status_decoded.
                Do pResult.structuredContent.%Set("input", tInput)
                Do pResult.structuredContent.%Set("decoded_text", tStatusText)
                Do pResult.structuredContent.%Set("code_class", "status")
                Do pResult.structuredContent.%Set("common_causes", [])
                Do pResult.structuredContent.%Set("suggested_diagnostics", ["Search the IRIS docs for the message text or error number embedded above."])
                Do pResult.structuredContent.%Set("render_strategy", "status_decoded")
                Set pResult.content.%Get(0).text = "%Status decoded: " _ tStatusText
            }
            Quit
        }

        ; ---- Step 2 — bare error-code/message lookup ----
        Set tMatch = ..LookupCuratedCode(tInput)
        If tMatch '= "" {
            Set tEntry = ..GetTableEntry(tMatch)
            Do pResult.structuredContent.%Set("input", tInput)
            Do pResult.structuredContent.%Set("decoded_text", tEntry.%Get("decoded_text"))
            Do pResult.structuredContent.%Set("code_class", tEntry.%Get("code_class"))
            Do pResult.structuredContent.%Set("common_causes", tEntry.%Get("common_causes"))
            Do pResult.structuredContent.%Set("suggested_diagnostics", tEntry.%Get("suggested_diagnostics"))
            Do pResult.structuredContent.%Set("render_strategy", "matched")
            Do pResult.structuredContent.%Set("matched_code", tMatch)
            Set pResult.content.%Get(0).text = tMatch _ ": " _ tEntry.%Get("decoded_text")
            Quit
        }

        ; ---- Step 3 — unmatched. Echo input with hint. ----
        Do pResult.structuredContent.%Set("input", tInput)
        Do pResult.structuredContent.%Set("decoded_text", tInput)
        Do pResult.structuredContent.%Set("code_class", "unknown")
        Do pResult.structuredContent.%Set("common_causes", [])
        Set tHints = []
        Do tHints.%Push("Search documentation for IRIS error: " _ tInput)
        Do tHints.%Push("Curated table covers: <PROTECT>, <UNDEFINED>, <NOTOPEN>, <METHOD DOES NOT EXIST>, <CLASS DOES NOT EXIST>, <INVALID OREF>, <SYNTAX>, <MAXSTRING>, <STORE>, <Ens>ErrBPTerminated, <Ens>ErrGeneral, <Ens>ErrBPTimeout, <Ens>ErrNoTimeout, <Ens>ErrException, <Ens>ErrSearchTableNotIndex.")
        Do pResult.structuredContent.%Set("suggested_diagnostics", tHints)
        Do pResult.structuredContent.%Set("render_strategy", "unmatched")
        Set pResult.content.%Get(0).text = "Unmatched IRIS error code (" _ tInput _ "). Try the suggested_diagnostics hints."
        Quit
    }
    Catch ex {
        ; No-throw guarantee. Use the new operator-friendly helper.
        Set tErrText = ##class(SessionAgent.Tool.Base).FormatExceptionForOperator(ex)
        Set pResult = {"isError":(1), "content":[{"type":"text","text":(tErrText)}], "structuredContent":{"render_strategy":"decode_error", "error_text":(tErrText)}}
    }
    Quit tSC
}

/// <p>Internal — scan the curated table for any code whose name appears
/// as a substring of <code>pHaystack</code>. Returns the first matching
/// code (longest first to avoid <code>&lt;CLASS&gt;</code>-vs-<code>&lt;CLASS
/// DOES NOT EXIST&gt;</code> kind of false positives), or empty string
/// when no curated code matches. Case-sensitive — IRIS error codes are
/// upper-case.</p>
///
/// <p><b>Story 5.0:</b> code list extended with the 4 new Ens-specific
/// codes + the corrected <code>&lt;Ens&gt;ErrBPTerminated</code> name.
/// Order matters: longer codes must precede shorter codes that are
/// substrings of them (e.g. <code>&lt;Ens&gt;ErrBPTerminated</code>
/// precedes <code>&lt;Ens&gt;ErrBPTimeout</code> — though they're not
/// substrings of each other in this case, the ordering principle holds
/// for future additions).</p>
ClassMethod LookupCuratedCode(pHaystack As %String) As %String
{
    Set tFound = ""
    Try {
        Set tTable = ..BuildErrorTable()
        ; Codes ordered longest-first so longer-prefix codes win over
        ; shorter ones that share a prefix. Safe ordering for the v1
        ; table: <METHOD DOES NOT EXIST> > <CLASS DOES NOT EXIST> >
        ; <Ens>ErrSearchTableNotIndex > <Ens>ErrBPTerminated >
        ; <Ens>ErrBPTimeout > <Ens>ErrException > <Ens>ErrNoTimeout >
        ; <Ens>ErrGeneral > <INVALID OREF> > <MAXSTRING> > <UNDEFINED> >
        ; <PROTECT> > <NOTOPEN> > <SYNTAX> > <STORE>.
        Set tCodes = $ListBuild("<METHOD DOES NOT EXIST>", "<CLASS DOES NOT EXIST>", "<Ens>ErrSearchTableNotIndex", "<Ens>ErrBPTerminated", "<Ens>ErrBPTimeout", "<Ens>ErrException", "<Ens>ErrNoTimeout", "<Ens>ErrGeneral", "<INVALID OREF>", "<MAXSTRING>", "<UNDEFINED>", "<PROTECT>", "<NOTOPEN>", "<SYNTAX>", "<STORE>")
        Set tPtr = 0
        While $ListNext(tCodes, tPtr, tCode) {
            If pHaystack [ tCode {
                If tTable.%IsDefined(tCode) {
                    Set tFound = tCode
                    Quit
                }
            }
        }
    }
    Catch ex {
        Set tFound = ""
    }
    Quit tFound
}

/// <p>Internal — fetch a curated table entry by code. Returns an empty
/// %DynamicObject if the code is not in the table.</p>
ClassMethod GetTableEntry(pCode As %String) As %DynamicObject
{
    Set tEntry = {}
    Try {
        Set tTable = ..BuildErrorTable()
        If tTable.%IsDefined(pCode) {
            Set tEntry = tTable.%Get(pCode)
        }
    }
    Catch ex {
        Set tEntry = {}
    }
    Quit tEntry
}

}
