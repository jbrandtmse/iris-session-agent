/// <p>Inspection tool — decode a <code>%Status</code> serialized value
/// or a bare IRIS error code/message into operator-readable text with
/// common-causes and suggested-diagnostics annotations. Thirteenth and
/// final inspection tool; ships with Story 4.7 (Epic 4 closer).</p>
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
/// <code>&lt;UNDEFINED&gt;</code>, <code>&lt;Ens&gt;ErrBPTerm</code>, or
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
/// <p><b>Curated lookup table.</b> 10 named IRIS error codes per Story
/// 4.7 AC-3 / epics.md line 1633. Stored as a Class Parameter
/// <parameter>ERRORTABLE</parameter> JSON literal (compile-time constant —
/// no PPG seeding). Per-process JSON parse cost is negligible (~10 entries)
/// and preserves the no-side-effects discipline.</p>
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
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 4.7</a> (lines 1620+) — AC source.</li>
/// <li><a href="../../../../irislib/%25SYSTEM/Status.cls">irislib/%SYSTEM/Status.cls</a>
/// — <code>GetErrorText(statuscode, language)</code> signature, line 77.</li>
/// <li><a href="../../../../irislib/%25Library/Status.cls">irislib/%Library/Status.cls</a>
/// — <code>%Status</code> datatype contract.</li>
/// </ul>
Class SessionAgent.Tool.Inspection.ExplainError Extends SessionAgent.Tool.Base
{

Parameter ToolName As %String = "explain_error";

Parameter Description As %String = "Decode a %Status value or IRIS error code/message into operator-readable explanation with common causes and suggested diagnostics.";

Parameter MutatesState As %Boolean = 0;

/// <p>Curated table builder — 10 named IRIS error codes per Story 4.7
/// AC-3. Returns a <code>%DynamicObject</code> keyed by error code with
/// <code>{code_class, decoded_text, common_causes, suggested_diagnostics}</code>
/// per entry. Built fresh each call (cheap — 10 entries) so we avoid PPG
/// state and stay no-side-effects.</p>
///
/// <p>Operator-readable explanations sourced from the IRIS 2024.1 docs
/// (RERR_system, RCOS_vstorage, GCSP_errorcodes) verified current via
/// Perplexity search 2026-05-04 per Rule 10 (external-default research
/// at spec time).</p>
ClassMethod BuildErrorTable() As %DynamicObject [ Internal ]
{
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
    Do tTable.%Set("<Ens>ErrBPTerm", {
        "code_class": "interop",
        "decoded_text": "An Ensemble/InterSystems IRIS production Business Process terminated abnormally — typically the BP threw an exception that the production halted on.",
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
    Quit tTable
}

/// <p>Locked-subset JSON Schema. Required: <code>status_or_error_string</code>.
/// <code>additionalProperties</code> false.</p>
ClassMethod GetInputSchema() As %DynamicObject
{
    Quit {
        "type": "object",
        "properties": {
            "status_or_error_string": {"type": "string", "description": "A serialized %Status value (e.g. captured via $$$ERROR or %Save status) OR a bare IRIS error code/message string like '<PROTECT>' or '<Ens>ErrBPTerm'."}
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
        Do tHints.%Push("Curated table covers: <PROTECT>, <UNDEFINED>, <NOTOPEN>, <METHOD DOES NOT EXIST>, <CLASS DOES NOT EXIST>, <INVALID OREF>, <SYNTAX>, <MAXSTRING>, <STORE>, <Ens>ErrBPTerm.")
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

/// <p>Internal — scan the curated <parameter>ERRORTABLE</parameter> for
/// any code whose name appears as a substring of <code>pHaystack</code>.
/// Returns the first matching code (longest first to avoid
/// <code>&lt;CLASS&gt;</code>-vs-<code>&lt;CLASS DOES NOT EXIST&gt;</code>
/// kind of false positives), or empty string when no curated code
/// matches. Case-sensitive — IRIS error codes are upper-case.</p>
ClassMethod LookupCuratedCode(pHaystack As %String) As %String
{
    Set tFound = ""
    Try {
        Set tTable = ..BuildErrorTable()
        ; Codes ordered longest-first so <METHOD DOES NOT EXIST> wins
        ; over <METHOD> (not in table but defensive against future entries).
        Set tCodes = $ListBuild("<METHOD DOES NOT EXIST>", "<CLASS DOES NOT EXIST>", "<Ens>ErrBPTerm", "<INVALID OREF>", "<MAXSTRING>", "<UNDEFINED>", "<PROTECT>", "<NOTOPEN>", "<SYNTAX>", "<STORE>")
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
